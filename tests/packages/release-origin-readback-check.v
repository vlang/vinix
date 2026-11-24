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

fn check() ! {
	if os.args.len !in [4, 6] {
		return error('usage: release-origin-readback-check VINIX_PACKAGE HTTPS_FIXTURE NEW_WORK [MIXED_RELEASE PUBLIC_KEY_HEX]')
	}
	work := os.abs_path(os.args[3])
	os.mkdir(work)!
	cli := os.abs_path(os.args[1])
	key := publish(cli, work)!
	local := work + '/release 1'
	original := inventory(local)!
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
		os.rm(work + '/key.pem') or {}
		os.rm(work + '/seed') or {}
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
		os.cp_all(mixed, served + '/mixed', false)!
		mixed_fixture := Fixture{ ...fixture, local: mixed, key: os.args[5], id: index.repository }
		paths := os.ls(mixed + '/objects')!.sorted().map('objects/' + it)
		checked := mixed_fixture.check('mixed-catalog', 'ranges/mixed', 0, '', [
			...metadata,
			...paths,
			...metadata,
		])!
		mixed_info := json2.decode[pkgcore.ReleaseOriginInfo](checked)!
		if mixed_info.release.object_count != paths.len || mixed_info.release.package_count != index.packages.len
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
