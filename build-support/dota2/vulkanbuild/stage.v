// SPDX-License-Identifier: GPL-2.0-or-later
module vulkanbuild

import crypto.sha256
import json2
import os
import qemubuild

fn split_lines(value string) []string {
	mut result := []string{}
	mut begin := 0
	mut offset := 0
	mut skip_lf := false
	for ch in value.runes() {
		width := ch.str().len
		if skip_lf && ch == `\n` {
			offset += width
			begin = offset
			skip_lf = false
			continue
		}
		skip_lf = false
		if ch in [`\n`, `\r`, rune(11), rune(12), rune(28), rune(29), rune(30), rune(133),
			rune(0x2028), rune(0x2029)] {
			result << value[begin..offset]
			begin = offset + width
			skip_lf = ch == `\r`
		}
		offset += width
	}
	if begin < value.len { result << value[begin..] }
	return result
}

fn null(value json2.Any) bool { return value is json2.Null }

fn valid(root string, glibc json2.Any, lavapipe json2.Any, venus json2.Any) !bool {
	if !null(glibc) && !public('glibc_package_valid', [paths(root), glibc])!.bool() { return false }
	if !null(lavapipe) && !public('lavapipe_valid', [paths(root), lavapipe])!.bool() {
		return false
	}
	if !null(venus) && !public('venus_valid', [paths(root), venus])!.bool() { return false }
	return true
}

pub fn stage(metadata map[string]json2.Any, options map[string]json2.Any, repo string) ! {
	steam := qemubuild.resolve(path(options['steam_build']!)!)!
	build := qemubuild.resolve(path(options['build']!)!)!
	source := steam + '/staging/usr/libexec/vinix-steam/root'
	root := qemubuild.resolve(if null(field(options, 'root')) {
		build + '/staging/usr/libexec/vinix-dota2/root'
	} else {
		path(options['root']!)!
	})!
	release := text(options, 'release')
	index := steam + '/downloads/' + release + '_amd64_Packages'
	manifest := steam + '/amd64-packages'
	if !qemubuild.exists(source + '/lib64/ld-linux-x86-64.so.2')! || !qemubuild.exists(index)! {
		return argument_error('scripts/build-steam-aarch64.sh must stage the glibc root and package index first')
	}
	if !qemubuild.separate(root, source) {
		return argument_error('the Vulkan build must be separate from the Steam build')
	}
	resolver := request({
		'kind': json2.Any('resolver')
	})!
	mut existing := map[string]bool{}
	for line in split_lines(qemubuild.read_text(manifest)!) {
		existing[line.all_before('\t')] = true
	}
	packages := method(resolver, 'parse_index', [paths(index)])!.as_array()
	ignored := existing.keys()
	mut ignored_names := ignored.clone()
	ignored_names << ['python3', 'dpkg']
	mut selected := method(resolver, 'resolve', [json2.Any(packages), words([
		'libvulkan1',
		'mesa-vulkan-drivers',
		'vulkan-tools',
		'libpipewire-0.3-0',
		'libopenal1',
		'libnm0',
	]), json2.Any({
		'set': words(ignored_names)
	})])!.as_array()
	mut certificates := json2.Any(json2.Null{})
	for item in packages {
		if text(package(item), 'name') == 'ca-certificates' {
			certificates = item
			break
		}
	}
	if null(certificates) { return StageError{'StopIteration', ''} }
	selected << certificates
	mut by_name := map[string]json2.Any{}
	for item in selected { by_name[text(package(item), 'name')] = item }
	mut names := by_name.keys()
	names.sort()
	selected = names.map(by_name[it] or { json2.Null{} })
	mut rows := []json2.Any{}
	for item in selected {
		value := package(item)
		rows << json2.Any({
			'package':  value['name']!
			'version':  value['version']!
			'filename': value['filename']!
			'sha256':   value['sha256']!
		})
	}
	glibc := if options['keep_steam_libc']!.bool() {
		json2.Any(json2.Null{})
	} else {
		public('load_glibc_pin', [])!
	}
	lavapipe := if options['debian_lavapipe']!.bool() {
		json2.Any(json2.Null{})
	} else {
		public('lavapipe_inputs', [])!
	}
	venus := if options['no_venus']!.bool() {
		json2.Any(json2.Null{})
	} else {
		public('venus_inputs', [])!
	}
	mut policy := map[string]json2.Any{}
	source_reader := request({
		'kind': json2.Any('global')
		'name': json2.Any('_native')
		'key':  json2.Any('policy_sources')
	})!
	sources := request({
		'kind':   json2.Any('call')
		'target': source_reader
	})!.as_array()
	for value in sources {
		filename := path(value)!
		policy[filename[repo.trim_right('/').len + 1..]] = json2.Any(digest(filename)!)
	}
	mmap_source := path(global('MMAP32_SOURCE')!)!
	early_source := path(global('EARLY_CLIENT_SOURCE')!)!
	inputs := json2.Any({
		'format':                json2.Any(6)
		'source':                json2.Any(source)
		'guest_root':            options['guest_root']!
		'release':               options['release']!
		'packages':              json2.Any(rows)
		'builder_sha256':        json2.Any(digest(text(metadata, 'builder'))!)
		'native_policy':         json2.Any(policy)
		'glibc_package':         glibc
		'glibc_alias_policy':    global('GLIBC_ALIAS_POLICY')!
		'lavapipe':              lavapipe
		'venus':                 venus
		'amd64':                 json2.Any(qemubuild.read_text(manifest)!)
		'i386':                  json2.Any(qemubuild.read_text(steam + '/i386-packages')!)
		'mmap32_source':         json2.Any(qemubuild.digest(mmap_source)!)
		'mmap32_compile':        global('MMAP32_COMPILE')!
		'mmap32_v_inputs':       public('mmap32_inputs', [])!
		'early_client_source':   json2.Any(qemubuild.digest(early_source)!)
		'early_client_v_inputs': public('early_client_inputs', [])!
		'early_client_compile':  global('EARLY_CLIENT_COMPILE')!
	})
	generation := sha256.sum(dumps(inputs, true, false)!.bytes()).hex()
	stamp_name := '.vinix-dota2-vulkan-generation'
	stamp := root + '/' + stamp_name
	if qemubuild.exists(root)! && !qemubuild.exists(stamp)! && !options['refresh']!.bool() {
		return argument_error('existing destination has no generation stamp; use --refresh to replace this private root')
	}
	required := ['lib64/ld-linux-x86-64.so.2', 'usr/bin/vulkaninfo', 'usr/bin/vkcube',
		'usr/lib/x86_64-linux-gnu/libvulkan_lvp.so', 'usr/lib/x86_64-linux-gnu/libvulkan.so.1',
		'usr/share/vulkan/icd.d/lvp_icd.x86_64.json', 'etc/ssl/certs/ca-certificates.crt',
		'usr/lib/x86_64-linux-gnu/libfreetype.so.6', constant('MMAP32_LIBRARY')!,
		constant('EARLY_CLIENT_LIBRARY')!]
	qemubuild.mkdir(build, true, true)!
	mut reported := rows.clone()
	if !null(glibc) { reported << glibc }
	write_json(build + '/vulkan-packages.json', json2.Any(reported), false)!
	mut cache_hit := qemubuild.exists(stamp)! && strip_space(qemubuild.read_text(stamp)!) == generation
	if cache_hit {
		for relative in required {
			if !qemubuild.exists(root + '/' + relative)! {
				cache_hit = false
				break
			}
		}
	}
	if cache_hit && valid(root, glibc, lavapipe, venus)! {
		request({
			'kind':      json2.Any('print')
			'arguments': json2.Any([paths(root)])
		})!
		return
	}
	pid := text(metadata, 'pid')
	pending := root + '.vulkan-stage-' + pid
	public('clone_tree', [paths(source), paths(pending)])!
	cache := build + '/downloads'
	qemubuild.mkdir(cache, true, true)!
	for item in selected {
		archive := method(resolver, 'download', [options['mirror']!, item, paths(cache)])!
		method(resolver, 'extract_deb', [archive, paths(pending)])!
	}
	// Both drivers must see Bookworm's libc before its private family is replaced.
	if !null(lavapipe) {
		public('stage_lavapipe', [json2.Any(selected), paths(pending), paths(build + '/mesa'),
			lavapipe])!
	}
	if !null(venus) {
		public('stage_venus', [paths(pending), paths(build + '/venus'), options['guest_root']!,
			venus])!
	}
	if !null(glibc) {
		public('stage_glibc_package', [resolver, glibc, paths(cache), paths(pending)])!
	}
	public('build_mmap32', [paths(pending + '/' + constant('MMAP32_LIBRARY')!),
		paths(build + '/native-v')])!
	public('build_early_client', [
		paths(pending + '/' + constant('EARLY_CLIENT_LIBRARY')!),
		paths(build + '/native-v'),
	])!
	certificate_dir := pending + '/usr/share/ca-certificates/mozilla'
	mut certificate_names := os_names(certificate_dir)!.filter(it.ends_with('.crt'))
	certificate_names.sort()
	if certificate_names.len == 0 {
		return fail('ca-certificates package contains no public trust certificates')
	}
	bundle := pending + '/etc/ssl/certs/ca-certificates.crt'
	qemubuild.mkdir(parent(bundle), true, true)!
	mut trust := ''
	for name in certificate_names {
		trust += qemubuild.read(certificate_dir + '/' + name)!.trim_right(' \t\r\n\v\f') + '\n'
	}
	qemubuild.write(bundle, trust)!
	icd := pending + '/usr/share/vulkan/icd.d/lvp_icd.x86_64.json'
	mut data := decode_json(qemubuild.read_text(icd)!)!.as_map()
	mut driver := data['ICD']!.as_map()
	driver['library_path'] = json2.Any(text(options, 'guest_root').trim_right('/') + '/usr/lib/x86_64-linux-gnu/libvulkan_lvp.so')
	data['ICD'] = json2.Any(driver)
	write_json(icd, json2.Any(data), false)!
	if !null(glibc) && !public('glibc_package_valid', [paths(pending), glibc])!.bool() {
		return fail('staged Dota libc6 package or loader aliases do not match the pin')
	}
	if !null(lavapipe) && !public('lavapipe_valid', [paths(pending), lavapipe])!.bool() {
		return fail('staged Lavapipe does not match its patched build')
	}
	if !null(venus) && !public('venus_valid', [paths(pending), venus])!.bool() {
		return fail('staged Venus driver does not match its build')
	}
	write_text(pending + '/' + stamp_name, generation + '\n')!
	if qemubuild.exists(root)! {
		old := root + '.vulkan-old-' + pid
		qemubuild.replace(root, old)!
		qemubuild.replace(pending, root) or {
			failure := err
			qemubuild.replace(old, root)!
			return failure
		}
		qemubuild.remove_tree(old)!
	} else {
		qemubuild.replace(pending, root)!
	}
	request({
		'kind':      json2.Any('print')
		'arguments': json2.Any([paths(root)])
	})!
}

fn os_names(path string) ![]string {
	return os.ls(path) or { []string{} }
}
