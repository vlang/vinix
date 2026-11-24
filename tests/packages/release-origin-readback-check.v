// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import tools.packages.pkgcore

struct Fixture {
	work  string
	cli   string
	url   string
	key   string
	local string
	id    string = 'fixture'
}

fn run(log string, args []string, status int, diagnostic string) !string {
	result := os.exec(args)
	os.write_file(log + '.argv.json', json2.encode(args) + '\n')!
	os.write_file(log + '.log', result.output)!
	if result.exit_code != status || !result.output.contains(diagnostic)
		|| (status != 0 && result.output.trim_space().starts_with('{')) {
		return error('unexpected status or output for ${log}: ${result.exit_code}\n${result.output}')
	}
	return result.output
}

fn (fixture Fixture) check(name string, mode string, status int, diagnostic string, requests []string) !string {
	log := fixture.work + '/requests.log'
	before := os.read_file(log)!
	output := run(fixture.work + '/' + name, [fixture.cli, 'check-release-origin', fixture.local,
		fixture.id, fixture.key, fixture.url + '/' + mode], status, diagnostic)!
	after := os.read_file(log)!
	separator := mode.index('/') or { mode.len }
	prefix := mode[..separator] + ' ' + if separator < mode.len {
		mode[separator + 1..] + '/'
	} else {
		''
	}
	if after != before + requests.map(prefix + it + ' -\n').join('') {
		return error('unexpected HTTPS requests in ${name}')
	}
	println('RELEASE ORIGIN READBACK ${name} PASS')
	return output
}

fn publish(cli string, work string) !string {
	os.mkdir_all(work + '/payload')!
	os.write_file(work + '/payload/content', 'signed release origin payload\n')!
	os.write_file(work + '/payload/empty', '')!
	key := run(work + '/keygen', [cli, 'keygen', work + '/seed'], 0, '')!.trim_space()
	for id in ['first', 'second']! {
		manifest := work + '/' + id + '.json'
		os.write_file(manifest, json2.encode(pkgcore.Package{
			id:           id
			name:         id
			version:      '1.0.0'
			architecture: 'all'
			kind:         'data'
			license:      'MIT'
		}))!
		run(work + '/pack-' + id, [cli, 'pack', manifest, work + '/payload', work + '/workspace'], 0, '')!
	}
	expires := (time.now().unix() + 7200).str()
	for sequence in ['1', '2']! {
		result := run(work + '/publish-' + sequence, [cli, 'publish-release', work + '/workspace',
			'fixture', work + '/seed', sequence, expires, work + '/release ' + sequence], 0, '')!
		info := json2.decode[pkgcore.ReleaseInfo](result)!
		if info.object_count != 2 || info.package_count != 2 {
			return error('fixture lacks shared or empty payload')
		}
	}
	return key
}

fn ready(file string, mut server os.Process) !string {
	for _ in 0 .. 500 {
		if os.exists(file) { return os.read_file(file)! }
		if !server.is_alive() { return error('TLS fixture exited before binding') }
		time.sleep(10 * time.millisecond)
	}
	return error('TLS fixture did not bind')
}

fn inventory(local string) !map[string]string {
	mut files := map[string]string{}
	for name in ['index.json', 'index.sig', ...os.ls(local + '/objects')!.map('objects/' + it)] {
		files[name] = pkgcore.hash_file(local + '/' + name)!
	}
	return files
}

fn check_local_export(cli string, work string, local string, key string, original map[string]string) ! {
	// The verifier must work without curl or other external tools.
	path := os.getenv('PATH')
	os.setenv('PATH', work + '/no-tools', true)
	defer { os.setenv('PATH', path, true) }
	command := [cli, 'check-release-export', local, 'fixture', key]
	published := json2.decode[pkgcore.ReleaseInfo](os.read_file(work + '/publish-1.log')!)!
	history := work + '/workspace/.publisher/history.json'
	floor := pkgcore.hash_file(history)!
	output := run(work + '/offline-export-check', [cli, '--offline', ...command[1..]], 0, '')!
	if json2.decode[pkgcore.ReleaseInfo](output)! != published {
		return error('local export receipt differs from publication')
	}
	run(work + '/local-export-wrong-id', [cli, 'check-release-export', local, 'other', key], 1, '')!
	run(work + '/local-export-wrong-key', [cli, 'check-release-export', local, 'fixture',
		'd75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'], 1, 'signature verification failed')!
	run(work + '/local-export-extra-operand', [...command, 'extra'], 1, 'requires a signed release directory')!
	root := work + '/untouched-local-root'
	run(work + '/local-export-root-option', [cli, '--root', root, ...command[1..]], 1, 'without an installation root option')!
	run(work + '/local-export-workspace', [cli, 'check-release-export', work + '/workspace', 'fixture', key], 1, '')!

	alias := work + '/export-link'
	os.symlink(local, alias)!
	run(work + '/local-export-root-alias', [cli, 'check-release-export', alias, 'fixture', key], 1, 'must be an ordinary directory')!
	os.rm(alias)!
	object := local + '/objects/' + pkgcore.hash_file(work + '/payload/content')!
	os.chmod(object, 0o600)!
	run(work + '/local-export-object-mode', command, 1, 'ordinary single-link file with mode 0644')!
	os.chmod(object, 0o644)!
	os.write_file(object, 'x'.repeat(int(os.file_size(object))))!
	run(work + '/local-export-changed-object', command, 1, 'export payload changed')!
	os.rm(object)!
	run(work + '/local-export-missing-object', command, 1, 'missing entries')!
	os.cp(work + '/payload/content', object)!
	os.chmod(object, 0o644)!
	os.write_file(local + '/untracked', '')!
	run(work + '/local-export-extra-file', command, 1, 'unexpected export entry')!
	os.rm(local + '/untracked')!
	retry := run(work + '/local-export-retry', command, 0, '')!
	if json2.decode[pkgcore.ReleaseInfo](retry)! != published || os.exists(root)
		|| inventory(local)! != original || pkgcore.hash_file(history)! != floor {
		return error('local export check changed the signed export or publisher history')
	}
	println('RELEASE EXPORT offline receipt, ten refusals and exact retry PASS')
}

fn check_index_pins(cli string, work string, local string, key string) ! {
	seed := work + '/secondary-seed'
	defer { os.rm(seed) or {} }
	secondary := work + '/release secondary'
	secondary_key := run(work + '/pin-keygen', [cli, 'keygen', seed], 0, '')!.trim_space()
	expires := (time.now().unix() + 7200).str()
	run(work + '/pin-publish-secondary', [cli, 'publish-release', work + '/workspace',
		'secondary', seed, '1', expires, secondary], 0, '')!
	history := work + '/workspace/.publisher/history.json'
	history_digest := pkgcore.hash_file(history)!
	original := inventory(local)!
	secondary_original := inventory(secondary)!
	first := [local, 'fixture', key]
	second := [secondary, 'secondary', secondary_key]
	first_line := 'fixture ' + original['index.json'] + '\n'
	expected := first_line + 'secondary ' + secondary_original['index.json'] + '\n'
	command := [cli, 'write-release-index-pins']

	path := os.getenv('PATH')
	os.setenv('PATH', work + '/no-tools', true)
	defer { os.setenv('PATH', path, true) }
	pins := work + '/image-indexes.txt'
	single := work + '/single-index.txt'
	retry := work + '/retry-indexes.txt'
	run(work + '/pin-single', [cli, '--offline', command[1], single, ...first], 0, '')!
	run(work + '/pin-batch', [...command, pins, ...second, ...first], 0, '')!
	run(work + '/pin-retry', [...command, retry, ...first, ...second], 0, '')!
	if os.read_file(single)! != first_line || os.read_file(pins)! != expected
		|| os.read_file(retry)! != expected {
		return error('saved index pins differ from canonical signed index digests')
	}

	failed := work + '/failed-indexes.txt'
	run(work + '/pin-duplicate', [...command, failed, ...first, ...first], 1,
		'duplicate release repository ID')!
	run(work + '/pin-wrong-key', [...command, failed, ...first, secondary, 'secondary', key],
		1, 'signature verification failed')!
	run(work + '/pin-incomplete', [...command, failed, ...first, secondary], 1, 'triples')!
	run(work + '/pin-root', [cli, '--root', '/', command[1], failed, ...first], 1, 'without --root')!
	run(work + '/pin-json', [cli, '--json', command[1], failed, ...first], 1, 'or --json')!
	run(work + '/pin-existing', [...command, pins, ...first], 1, 'destination already exists')!
	alias := work + '/pin-link'
	os.symlink(pins, alias)!
	run(work + '/pin-existing-link', [...command, alias, ...first], 1, 'destination already exists')!
	parent_alias := work + '/pin-parent-link'
	os.symlink(secondary + '/objects', parent_alias)!
	nested := parent_alias + '/../pins.txt'
	run(work + '/pin-inside-export', [...command, nested, ...first, ...second], 1,
		'must be saved outside each signed release export')!

	object := secondary + '/objects/' + pkgcore.hash_file(work + '/payload/content')!
	os.write_file(object, 'x'.repeat(int(os.file_size(object))))!
	run(work + '/pin-damaged-second', [...command, failed, ...first, ...second], 1,
		'export payload changed')!
	os.cp(work + '/payload/content', object)!
	if os.exists(failed) || os.exists(nested) || !os.is_link(alias) || os.read_file(alias)! != expected
		|| inventory(local)! != original || inventory(secondary)! != secondary_original
		|| pkgcore.hash_file(history)! != history_digest {
		return error('release index pin refusal changed an export, publisher history or pin destination')
	}
	run(work + '/pin-restored-second', [...command, failed, ...first, ...second], 0, '')!
	if os.read_file(failed)! != expected {
		return error('restored export did not produce the original pins')
	}
	println('RELEASE INDEX PINS canonical offline writes, exact retry and nine refusals PASS')
}

fn check() ! {
	if os.args.len !in [4, 6] {
		return error('usage: release-origin-readback-check VINIX_PACKAGE HTTPS_FIXTURE NEW_WORK [MIXED_RELEASE PUBLIC_KEY_HEX]')
	}
	work := os.abs_path(os.args[3])
	os.mkdir(work)!
	defer {
		os.rm(work + '/key.pem') or {}
		os.rm(work + '/seed') or {}
	}
	cli := os.abs_path(os.args[1])
	key := publish(cli, work)!
	local := work + '/release 1'
	original := inventory(local)!
	check_local_export(cli, work, local, key, original)!
	check_index_pins(cli, work, local, key)!
	local_mode := (os.lstat(local)!).mode
	served := work + '/served'
	os.cp_all(local, served, false)!
	os.cp(work + '/release 2/index.json', served + '/next-index.json')!
	os.mkdir(served + '/other')!
	os.cp(work + '/release 2/index.json', served + '/other/index.json')!
	os.mkdir(served + '/bad-signature')!
	os.cp(local + '/index.json', served + '/bad-signature/index.json')!
	os.cp(work + '/release 2/index.sig', served + '/bad-signature/index.sig')!
	os.write_file(work + '/requests.log', '')!
	run(work + '/certificate', ['openssl', 'req', '-new', '-x509', '-newkey', 'rsa:2048', '-nodes',
		'-days', '1', '-subj', '/CN=Vinix release readback fixture', '-addext',
		'subjectAltName=IP:127.0.0.1', '-keyout', work + '/key.pem', '-out', work + '/ca.pem'], 0, '')!
	os.setenv('CURL_CA_BUNDLE', work + '/ca.pem', true)
	os.setenv('NO_PROXY', '127.0.0.1,localhost', true)
	os.setenv('no_proxy', '127.0.0.1,localhost', true)
	mut server := os.new_process(os.abs_path(os.args[2]))
	server.set_args([work + '/ca.pem', work + '/key.pem', served, work + '/ready',
		work + '/requests.log'])
	server.set_redirect_stdio_merged()
	server.run()
	defer {
		if server.is_alive() { server.signal_kill() }
		server.wait()
		os.write_file(work + '/server.log', server.stdout_slurp()) or {}
		server.close()
	}
	url := ready(work + '/ready', mut server)!
	fixture := Fixture{ work: work, cli: cli, url: url, key: key, local: local }
	objects := os.ls(local + '/objects')!.sorted().map('objects/' + it)
	metadata := ['index.json', 'index.sig']
	all_requests := [...metadata, ...objects, ...metadata]
	info := json2.decode[pkgcore.ReleaseOriginInfo](fixture.check('match', 'ranges', 0, '', all_requests)!)!
	published := json2.decode[pkgcore.ReleaseInfo](os.read_file(work + '/publish-1.log')!)!
	if info.format != 1 || info.url != url + '/ranges' || info.release != published {
		return error('readback metadata differs from the reviewed publication')
	}
	fixture.check('different-index', 'ranges/other', 1, 'hosted release index differs', ['index.json'])!
	fixture.check('wrong-signature', 'ranges/bad-signature', 1, 'hosted release signature differs', metadata)!
	fixture.check('index-changed-during-readback', 'origin-switch', 1, 'hosted release index differs', [
		...metadata,
		...objects,
		'index.json',
	])!
	for i, object in objects {
		if os.file_size(local + '/' + object) == 0 { continue }
		fixture.check('corrupt-object', 'no-range-corrupt', 1, 'hosted release object differs', [
			...metadata,
			...objects[..i + 1],
		])!
		os.rm(served + '/' + object)!
		fixture.check('missing-object', 'ranges', 1, 'download failed (22)', [
			...metadata,
			...objects[..i + 1],
		])!
		os.cp(local + '/' + object, served + '/' + object)!
		os.write_file(local + '/' + object, 'invalid local export')!
		fixture.check('local-object-changed', 'ranges', 1, 'export payload changed', [])!
		os.cp(served + '/' + object, local + '/' + object)!
		break
	}
	before := os.read_file(work + '/requests.log')!
	run(work + '/wrong-repository', [cli, 'check-release-origin', local, 'other', key, url + '/ranges'], 1, '')!
	run(work + '/local-transport', [cli, 'check-release-origin', local, 'fixture', key,
		'file://' + served],
		1, 'requires a valid HTTPS repository URL')!
	run(work + '/offline-flag', [cli, '--offline', 'check-release-origin', local, 'fixture', key,
		url + '/ranges'],
		1, 'without installation root or offline options')!
	run(work + '/wrong-hostname', [cli, 'check-release-origin', local, 'fixture', key,
		url.replace('127.0.0.1', 'localhost') + '/ranges'], 1, 'download failed (60)')!
	run(work + '/alternate-root', [cli, '--root', work + '/untouched', 'check-release-origin',
		local, 'fixture', key, url + '/ranges'], 1, 'without installation root or offline options')!
	if os.exists(work + '/untouched') || os.read_file(work + '/requests.log')! != before || inventory(local)! != original
		|| (os.lstat(local)!).mode != local_mode {
		return error('a refusal contacted the server or changed the reviewed export')
	}
	println('RELEASE ORIGIN READBACK identity, transport, offline and certificate refusals PASS')
	if os.args.len == 6 {
		mixed := os.abs_path(os.args[4])
		index := json2.decode[pkgcore.Index](os.read_file(mixed + '/index.json')!)!
		mixed_export := json2.decode[pkgcore.ReleaseInfo](run(work + '/mixed-local-export',
			[cli, 'check-release-export', mixed, index.repository, os.args[5]], 0, '')!)!
		os.cp_all(mixed, served + '/mixed', false)!
		mixed_fixture := Fixture{ ...fixture, local: mixed, key: os.args[5], id: index.repository }
		paths := os.ls(mixed + '/objects')!.sorted().map('objects/' + it)
		checked := mixed_fixture.check('mixed-catalog', 'ranges/mixed', 0, '', [
			...metadata,
			...paths,
			...metadata,
		])!
		mixed_info := json2.decode[pkgcore.ReleaseOriginInfo](checked)!
		if mixed_info.release != mixed_export || mixed_info.release.object_count != paths.len
			|| mixed_info.release.package_count != index.packages.len
			|| mixed_info.release.index_sha256 != pkgcore.hash_file(mixed + '/index.json')! {
			return error('mixed catalog receipt does not describe the reviewed export')
		}
	}
}

fn main() {
	check() or {
		eprintln(err)
		exit(1)
	}
}
