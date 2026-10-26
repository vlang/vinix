// SPDX-License-Identifier: GPL-2.0-or-later
// Freeze one coupled runtime selection while preserving the isolated request.
module main

import crypto.sha256
import json2
import os
import v.embed_file

const source_text = source($embed_file(@FILE))
const roles = ['framework', 'native', 'account', 'launch', 'token', 'token_controller', 'ui', 'browser_client']
const artifacts = ['request.json', 'original-request.json', 'selection.json', 'source.v', 'refresh', 'refresh.json']

struct Refreshed {
	text string
	roots []string
}

fn source(data embed_file.EmbedFileData) string {
	if data.str().all_after('uncompressed: ').trim_right(' }') == '0' {
		panic('refresh-coupled-maps-account-request requires -prod embedded source')
	}
	return data.to_string()
}

fn valid_pin(value string) bool {
	return value.len == 64 && value.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn relative_file(path string) bool {
	return path != '' && !path.starts_with('/') && !path.contains_any('\\\x00\n\r\t')
		&& path.split('/').all(it !in ['', '.', '..'])
}

fn text_field(value map[string]json2.Any, name string) !string {
	field := value[name] or { return error('missing string field: ' + name) }
	if field is string { return field }
	return error('string field required: ' + name)
}

fn read_bounded(path string, limit int) !string {
	if path != os.real_path(path) || os.lstat(path)!.get_filetype() != .regular
		|| os.lstat(path)!.size > u64(limit) { return error('canonical bounded regular input required') }
	mut file := os.open(path)!
	defer { file.close() }
	mut result := []u8{}
	defer { unsafe { result.free() } }
	mut buffer := []u8{len: int_min(65536, limit + 1)}
	defer { unsafe { buffer.free() } }
	for {
		// Even a concurrently growing input cannot make this read allocate
		// beyond a bounded text buffer before it is rejected.
		mut part := unsafe { buffer[..int_min(buffer.len, limit + 1 - result.len)] }
		n := file.read(mut part) or { if err is os.Eof { break } else { return err } }
		if n == 0 { break }
		result << part[..n]
		if result.len > limit { return error('input grew beyond bound') }
	}
	if path != os.real_path(path) || os.lstat(path)!.get_filetype() != .regular {
		return error('input inode changed during read')
	}
	return result.bytestr()
}

fn pinned_text(path string, pin string, limit int) !string {
	text := read_bounded(path, limit)!
	if !valid_pin(pin) || sha256.hexhash(text) != pin { return error('selected input pin differs: ' + path) }
	return text
}

fn external(path string) !string {
	parent := os.dir(path)
	name := os.file_name(path)
	if !os.is_dir(parent) || path != os.real_path(parent) + '/' + name || name in ['', '.', '..']
		|| path.contains_any('\x00\n\r\t') || path == '/Users/alex/code/vinix'
		|| path.starts_with('/Users/alex/code/vinix/') || os.exists(path) || os.is_link(path) {
		return error('fresh canonical external output required')
	}
	return path
}

fn disjoint(output string, inputs []string) ! {
	for input in inputs {
		if input != os.real_path(input) || !os.exists(input) || output == input
			|| output.starts_with(input + '/') || input.starts_with(output + '/') {
			return error('output must be disjoint from canonical inputs')
		}
	}
}

fn selected_ref(value json2.Any) !(map[string]json2.Any, map[string]string) {
	if value !is map[string]json2.Any { return error('typed selected bundle reference required') }
	ref := value.as_map()
	if ref.len != 2 || 'root' !in ref || 'seal' !in ref { return error('exact selected bundle root and seal required') }
	root := text_field(ref, 'root')!
	seal := text_field(ref, 'seal')!
	if root != os.real_path(root) || !os.is_dir(root) || os.is_link(root) { return error('canonical selected bundle required') }
	manifest := pinned_text(root + '/sha256.json', seal, 32 * 1024 * 1024)!
	pins := json2.decode[map[string]string](manifest, strict: true)!
	if pins.len == 0 || 'sha256.json' in pins { return error('invalid selected inventory') }
	for name, pin in pins {
		if !relative_file(name) || !valid_pin(pin) { return error('invalid selected manifest entry') }
	}
	return ref, pins
}

fn refresh(original string, selection string) !Refreshed {
	mut fields := json2.decode[map[string]json2.Any](original, strict: true)!
	if text_field(fields, 'kind')! != 'vinix-maps-account-stage-request-v1' {
		return error('unexpected original request kind')
	}
	chosen := json2.decode[map[string]json2.Any](selection, strict: true)!
	if chosen.len != roles.len + 1 || text_field(chosen, 'kind')! != 'vinix-maps-account-coupled-selection-v1' {
		return error('exact coupled selection required')
	}
	mut roots := []string{}
	for role in roles {
		ref, pins := selected_ref(chosen[role] or { return error('selected role absent: ' + role) })!
		roots << text_field(ref, 'root')!
		if role == 'ui' {
			if 'stage.json' !in pins { return error('selected UI stage receipt absent') }
			fields[role] = ref['root']!
		} else {
			if 'build.json' !in pins { return error('selected build receipt absent: ' + role) }
			fields[role] = ref
		}
		if role == 'framework' {
			fields['framework_jar'] = pins['api-impl.jar'] or { return error('selected framework jar absent') }
			fields['framework_dex'] = pins['classes.dex'] or { return error('selected framework dex absent') }
		}
		if role == 'token' {
			fields['token_apk'] = pins['probe.apk'] or { return error('selected signed token APK absent') }
		}
	}
	encoded := json2.encode(fields, prettify: true) + '\n'
	if encoded.len > 32768 { return error('refreshed request exceeds bound') }
	mut before := json2.decode[map[string]json2.Any](original)!
	mut after := json2.decode[map[string]json2.Any](encoded)!
	for name in roles { before.delete(name); after.delete(name) }
	for name in ['framework_jar', 'framework_dex', 'token_apk'] { before.delete(name); after.delete(name) }
	if before != after { return error('unselected request fields changed') }
	return Refreshed{encoded, roots}
}

fn recheck(original_path string, original_pin string, selection_path string, selection_pin string,
	original string, selection string, expected Refreshed) ! {
	if pinned_text(original_path, original_pin, 32768)! != original
		|| pinned_text(selection_path, selection_pin, 32768)! != selection
		|| refresh(original, selection)!.text != expected.text {
		return error('coupled selection or request changed during refresh')
	}
}

fn create_refresh(original_path string, original_pin string, selection_path string, selection_pin string,
	output string) ! {
	original := pinned_text(original_path, original_pin, 32768)!
	selection := pinned_text(selection_path, selection_pin, 32768)!
	updated := refresh(original, selection)!
	root := external(output)!
	mut inputs := [original_path, selection_path]
	inputs << updated.roots
	disjoint(root, inputs)!
	os.mkdir(root, mode: 0o700)!
	os.write_file(root + '/request.json', updated.text)!
	os.write_file(root + '/original-request.json', original)!
	os.write_file(root + '/selection.json', selection)!
	os.write_file(root + '/source.v', source_text)!
	os.cp(os.executable(), root + '/refresh')!
	os.chmod(root + '/refresh', 0o755)!
	recheck(original_path, original_pin, selection_path, selection_pin, original, selection, updated)!
	if read_bounded(root + '/request.json', 32768)! != updated.text {
		return error('request readback differs')
	}
	fields := json2.decode[map[string]json2.Any](original)!
	mut preserved := fields.keys().filter(it !in roles && it !in ['framework_jar', 'framework_dex', 'token_apk'])
	preserved.sort()
	proof := {
		'kind': json2.Any('vinix-maps-account-coupled-request-refresh-v1')
		'original_request_sha256': json2.Any(original_pin)
		'selection_sha256': json2.Any(selection_pin)
		'request_sha256': json2.Any(sha256.hexhash(updated.text))
		'preserved_fields': json2.Any(preserved.map(json2.Any(it)))
		'scope': json2.Any('Pinned manifest selection only; complete producer inventories, signatures, build coupling and UI profile pins remain mandatory in the Maps stager.')
	}
	os.write_file(root + '/refresh.json', json2.encode(proof, prettify: true) + '\n')!
	mut inventory := map[string]string{}
	for name in artifacts { inventory[name] = sha256.hexhash(read_bounded(root + '/' + name, 64 * 1024 * 1024)!) }
	os.write_file(root + '/sha256.json', json2.encode(inventory, prettify: true) + '\n')!
	if os.ls(root)!.len != artifacts.len + 1
		|| json2.decode[map[string]string](read_bounded(root + '/sha256.json', 32768)!, strict: true)! != inventory {
		return error('refresh evidence inventory differs')
	}
	for name, pin in inventory { pinned_text(root + '/' + name, pin, 64 * 1024 * 1024)! }
	recheck(original_path, original_pin, selection_path, selection_pin, original, selection, updated)!
	println('MAPS-ACCOUNT-COUPLED-REQUEST PASS SHA256=' + sha256.hexhash(updated.text))
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--self-test' {
		self_test(os.args[2]) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len != 6 {
		eprintln('usage: refresh-coupled-maps-account-request ORIGINAL ORIGINAL_SHA256 SELECTION SELECTION_SHA256 FRESH_OUTPUT_DIR | --self-test FRESH_EXTERNAL_DIR')
		exit(2)
	}
	create_refresh(os.args[1], os.args[2], os.args[3], os.args[4], os.args[5]) or { eprintln(err); exit(1) }
}

fn reject_refresh(original string, selection string) ! {
	if _ := refresh(original, selection) { return error('invalid selection accepted') }
}

fn reject_manifest(original string, selection string, role string, manifest string) ! {
	mut chosen := json2.decode[map[string]json2.Any](selection)!
	mut ref := chosen[role]!.as_map()
	path := text_field(ref, 'root')! + '/sha256.json'
	before := read_bounded(path, 32768)!
	os.write_file(path, manifest)!
	defer { os.write_file(path, before) or { panic(err) } }
	ref['seal'] = sha256.hexhash(manifest)
	chosen[role] = ref
	reject_refresh(original, json2.encode(chosen))!
}

fn self_test(output string) ! {
	root := external(output)!
	os.mkdir(root, mode: 0o700)!
	mut chosen := {
		'kind': json2.Any('vinix-maps-account-coupled-selection-v1')
	}
	mut fields := json2.decode[map[string]json2.Any]('{
		"kind":"vinix-maps-account-stage-request-v1", "base":"preserved-base",
		"guest":{"root":"preserved-guest","seal":"preserved-guest-pin"},
		"browser":{"root":"preserved-browser","seal":"preserved-browser-pin"},
		"java":"preserved-java", "signer":"preserved-signer",
		"future":{"array":[null,true,17,"unchanged"],"nested":{"name":"preserved"}},
		"framework_jar":"old-jar", "framework_dex":"old-dex", "token_apk":"old-apk"
	}')!
	for role in roles {
		bundle := root + '/' + role
		os.mkdir(bundle, mode: 0o700)!
		mut pins := {
			if role == 'ui' { 'stage.json' } else { 'build.json' }: sha256.hexhash(role + '-receipt')
		}
		if role == 'framework' {
			pins['api-impl.jar'] = sha256.hexhash('selected-jar')
			pins['classes.dex'] = sha256.hexhash('selected-dex')
		}
		if role == 'token' { pins['probe.apk'] = sha256.hexhash('selected-apk') }
		manifest := json2.encode(pins)
		os.write_file(bundle + '/sha256.json', manifest)!
		chosen[role] = {'root': json2.Any(bundle), 'seal': json2.Any(sha256.hexhash(manifest))}
		fields[role] = if role == 'ui' { json2.Any('old-ui') } else {
			json2.Any({'root': json2.Any('old-' + role), 'seal': json2.Any('old-pin')})
		}
	}
	original := json2.encode(fields)
	selection := json2.encode(chosen)
	original_pin := sha256.hexhash(original)
	selection_pin := sha256.hexhash(selection)
	os.write_file(root + '/original.json', original)!
	os.write_file(root + '/chosen.json', selection)!
	updated := refresh(original, selection)!
	after := json2.decode[map[string]json2.Any](updated.text)!
	for role in roles {
		assert after[role]! == if role == 'ui' { chosen[role]!.as_map()['root']! } else { chosen[role]! }
	}
	for name in ['kind', 'base', 'guest', 'browser', 'java', 'signer', 'future'] { assert after[name]! == fields[name]! }
	assert after['framework_jar']! == json2.Any(sha256.hexhash('selected-jar'))
	assert after['framework_dex']! == json2.Any(sha256.hexhash('selected-dex'))
	assert after['token_apk']! == json2.Any(sha256.hexhash('selected-apk'))
	assert after['browser_client']! == chosen['browser_client']!
	assert after['browser']! == fields['browser']!
	create_refresh(root + '/original.json', original_pin, root + '/chosen.json', selection_pin, root + '/result')!
	assert read_bounded(root + '/result/source.v', 1024 * 1024)! == source_text
	assert read_bounded(root + '/result/refresh', 64 * 1024 * 1024)! == read_bounded(os.executable(), 64 * 1024 * 1024)!
	assert read_bounded(root + '/result/request.json', 32768)! == updated.text
	proof := json2.decode[map[string]json2.Any](read_bounded(root + '/result/refresh.json', 32768)!)!
	assert 'future' in proof['preserved_fields']!.as_array().map(it.str())
	for role in roles {
		mut missing := json2.decode[map[string]json2.Any](selection)!
		missing.delete(role)
		reject_refresh(original, json2.encode(missing))!
		if _ := create_refresh(root + '/original.json', original_pin, root + '/chosen.json', selection_pin,
			root + '/' + role + '/forbidden') { return error('output within selected bundle accepted') }
		assert !os.exists(root + '/' + role + '/forbidden')
	}
	mut extra := json2.decode[map[string]json2.Any](selection)!
	extra['unknown'] = 'not-a-role'
	reject_refresh(original, json2.encode(extra))!
	reject_refresh('{}', selection)!
	reject_refresh('[', selection)!
	mut malformed := json2.decode[map[string]json2.Any](selection)!
	for bad_ref in [json2.Any(7), json2.Any({'root': json2.Any(7), 'seal': json2.Any('a'.repeat(64))}),
		json2.Any({'root': json2.Any(root + '/framework'), 'seal': json2.Any('a'.repeat(64)), 'extra': json2.Any(true)})] {
		malformed['framework'] = bad_ref
		reject_refresh(original, json2.encode(malformed))!
	}
	malformed['framework'] = {'root': json2.Any(root + '/framework'), 'seal': json2.Any('0'.repeat(64))}
	reject_refresh(original, json2.encode(malformed))!
	for bad in ['{', '[]', '{}', '{"sha256.json":"' + 'a'.repeat(64) + '"}',
		'{"../escape":"' + 'a'.repeat(64) + '"}', '{"build.json":"wrong"}',
		'{"build.json":null}', '{"build.json":17}'] {
		reject_manifest(original, selection, 'native', bad)!
	}
	for role, member in {'framework': 'api-impl.jar', 'token': 'probe.apk', 'ui': 'stage.json', 'browser_client': 'build.json'} {
		manifest_path := root + '/' + role + '/sha256.json'
		mut pins := json2.decode[map[string]string](read_bounded(manifest_path, 32768)!)!
		pins.delete(member)
		reject_manifest(original, selection, role, json2.encode(pins))!
	}
	mut no_dex := json2.decode[map[string]string](read_bounded(root + '/framework/sha256.json', 32768)!)!
	no_dex.delete('classes.dex')
	reject_manifest(original, selection, 'framework', json2.encode(no_dex))!
	if _ := create_refresh(root + '/original.json', '0'.repeat(64), root + '/chosen.json', selection_pin, root + '/bad-original') {
		return error('wrong original pin accepted')
	}
	if _ := create_refresh(root + '/original.json', original_pin, root + '/chosen.json', '0'.repeat(64), root + '/bad-selection') {
		return error('wrong selection pin accepted')
	}
	if _ := create_refresh(root + '/original.json', original_pin, root + '/chosen.json', selection_pin, root + '/result') {
		return error('existing output accepted')
	}
	mut oversized := json2.decode[map[string]json2.Any](original)!
	oversized['padding'] = ''
	oversized['padding'] = 'x'.repeat(32760 - json2.encode(oversized).len)
	oversized_text := json2.encode(oversized)
	assert oversized_text.len == 32760
	os.write_file(root + '/large-original.json', oversized_text)!
	if _ := create_refresh(root + '/large-original.json', sha256.hexhash(oversized_text), root + '/chosen.json',
		selection_pin, root + '/large-result') { return error('oversized refreshed request accepted') }
	assert !os.exists(root + '/large-result')
	os.symlink(root + '/original.json', root + '/original-link')!
	if _ := read_bounded(root + '/original-link', 32768) { return error('symlink input accepted') }
	os.symlink(root + '/framework', root + '/framework-link')!
	malformed['framework'] = {'root': json2.Any(root + '/framework-link'), 'seal': chosen['framework']!.as_map()['seal']!}
	reject_refresh(original, json2.encode(malformed))!
	os.write_file(root + '/oversized', 'x'.repeat(33))!
	if _ := read_bounded(root + '/oversized', 32) { return error('oversized text accepted') }
	os.write_file(root + '/original.json', original + ' ')!
	if _ := recheck(root + '/original.json', original_pin, root + '/chosen.json', selection_pin, original, selection, updated) {
		return error('original mutation accepted at recheck')
	}
	os.write_file(root + '/original.json', original)!
	os.write_file(root + '/chosen.json', selection + ' ')!
	if _ := recheck(root + '/original.json', original_pin, root + '/chosen.json', selection_pin, original, selection, updated) {
		return error('selection mutation accepted at recheck')
	}
	os.write_file(root + '/chosen.json', selection)!
	native_manifest := read_bounded(root + '/native/sha256.json', 32768)!
	os.write_file(root + '/native/sha256.json', '{}')!
	if _ := recheck(root + '/original.json', original_pin, root + '/chosen.json', selection_pin, original, selection, updated) {
		return error('manifest mutation accepted at recheck')
	}
	os.write_file(root + '/native/sha256.json', native_manifest)!
	println('MAPS-ACCOUNT-COUPLED-REQUEST SELF-TEST PASS')
}
