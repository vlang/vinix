// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import json2
import time
import tools.packages.pkgcore
import tools.packages.pkgprotocol

struct SavedEnvironment {
	name string
	value string
	present bool
}

fn invoke(arguments []string, log string) ! {
	result := os.exec(arguments)
	os.write_file(log, result.output)!
	if result.exit_code != 0 { return error(result.output) }
}

fn certificate(work string) ! {
	os.write_file(work + '/certificate.cnf', '[req]\nprompt=no\ndistinguished_name=subject\nx509_extensions=extensions\n'
		+ '[subject]\nCN=Vinix package HTTPS fixture\n[extensions]\nbasicConstraints=critical,CA:TRUE\n'
		+ 'keyUsage=critical,digitalSignature,keyEncipherment,keyCertSign\nextendedKeyUsage=serverAuth\nsubjectAltName=IP:127.0.0.1\n')!
	invoke(['openssl', 'req', '-new', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1',
		'-config', work + '/certificate.cnf', '-keyout', work + '/key.pem', '-out', work + '/ca.pem'], work + '/certificate-build.txt')!
	os.chmod(work + '/key.pem', 0o600)!
}

fn wait_ready(path string, mut server os.Process) !string {
	for _ in 0 .. 500 {
		if os.exists(path) { return os.read_file(path)! }
		if !server.is_alive() { return error('HTTPS fixture exited before binding') }
		time.sleep(10 * time.millisecond)
	}
	return error('HTTPS fixture did not become ready')
}

fn transfer_events(event pkgprotocol.Progress) {
	event.validate() or { panic(err) }
	mut file := os.open_file(os.getenv('VINIX_HTTPS_EVENTS'), 'a', 0o600) or { panic(err) }
	file.writeln(json2.encode(event)) or { panic(err) }
	file.close()
}

fn requests(work string, mode string) ![]string {
	return os.read_file(work + '/requests.txt')!.split_into_lines().filter(it.starts_with(mode + ' objects/'))
}

fn qualify_transaction(work string, base string, mode string, text string, key string, payload pkgcore.Payload) ! {
	root := work + '/store-' + mode
	os.mkdir_all(root + '/etc/vinix-packages')!
	configuration := root + '/etc/vinix-packages/config.json'
	initial := pkgcore.Config{architecture: 'aarch64',
		repositories: [pkgcore.Repository{id: 'tls-fixture', public_key: key, url: base + '/ranges'}],
		policy: pkgcore.Policy{reserve_bytes: 0}}
	os.write_file(configuration, json2.encode(initial))!
	os.chmod(configuration, 0o644)!
	plain := pkgcore.Service{root: root}
	plain.refresh()!
	plain.transact('install', ['https-app'], pkgcore.TransactionOptions{})!
	plain.transact('remove', ['https-app'], pkgcore.TransactionOptions{})!
	directory := pkgcore.state_directory(root)
	object := directory + '/objects/' + payload.sha256
	part := object + '.part'
	os.rm(object)!
	prefix := if mode == 'bad-prefix' { 'x'.repeat(4096) } else { text[..4096] }
	os.write_file(part, prefix)!
	url_mode := if mode == 'bad-prefix' { 'ranges' } else { mode }
	os.write_file(configuration, json2.encode(pkgcore.Config{...initial,
		repositories: [pkgcore.Repository{id: 'tls-fixture', public_key: key, url: base + '/' + url_mode}]}))!
	plain.refresh()!
	event_file := root + '/events.txt'
	os.write_file(event_file, '')!
	os.setenv('VINIX_HTTPS_EVENTS', event_file, true)
	service := pkgcore.Service{root: root, progress: transfer_events}
	before := requests(work, url_mode)!.len
	state := service.state()!
	mut review := service.review('install', ['https-app'])!
	defer { review.close() }
	mut failure := ''
	service.transact('install', ['https-app'], pkgcore.TransactionOptions{expected_review: review.fingerprint}) or { failure = err.msg() }
	object_requests := requests(work, url_mode)![before..]
	mut events := []pkgprotocol.Progress{}
	for line in os.read_file(event_file)!.split_into_lines() { events << pkgprotocol.decode_progress(line)! }
	defer { for mut event in events { event.close() } }
	assert events.filter(it.phase == 'download').all(it.total == payload.bytes && it.current <= it.total)
	if mode in ['ranges', 'no-range', 'bad-prefix'] {
		assert failure == '', failure
		assert service.verify()!.generation == 3 && pkgcore.verified_file(object, payload) && !os.exists(part)
		assert os.read_file(directory + '/current/apps/https-app/share/payload')! == text
		assert object_requests.len == if mode == 'ranges' { 1 } else { 2 }
		assert object_requests[0].ends_with('bytes=4096-')
		if mode != 'ranges' {
			assert object_requests[1].ends_with(' -')
			assert events.any(it.phase == 'download' && it.current == 0)
		}
		assert events.last().phase == 'complete'
	} else {
		assert failure != '' && service.verify()! == state, failure
		assert os.readlink(directory + '/current')! == 'generations/2'
		assert os.ls(directory + '/generations')!.sorted() == ['1', '2']
		assert !os.exists(object) && events.all(it.phase !in ['activate', 'complete'])
		if mode == 'no-range-corrupt' {
			assert failure.contains('payload checksum or size mismatch') && object_requests.len == 2
			assert !os.exists(part), 'a fresh fallback must not trigger a third integrity transfer'
		} else {
			assert object_requests.len == 1 && os.exists(part), failure
			if mode == 'forbidden' { assert failure.contains('download failed (22)'), failure }
			if mode == 'insecure-redirect' { assert failure.contains('download failed (1)'), failure }
			assert os.read_file(part)!.starts_with(prefix)
			if mode == 'truncated' {
				assert failure.contains('download failed (18)') && os.file_size(part) == 5120
				os.write_file(configuration, json2.encode(initial))!
				plain.refresh()!
				service.transact('install', ['https-app'], pkgcore.TransactionOptions{})!
				assert service.verify()!.generation == 3 && pkgcore.verified_file(object, payload)
				assert requests(work, 'ranges')!.last().ends_with('bytes=5120-')
				println('PASS HTTPS interrupted transfer retained prefix and resumed on the next transaction')
				return
			}
		}
		assert service.rollback('')!.generation == 3 && service.verify()!.generation == 3
		assert service.state()!.previous == 2 && service.state()!.packages.len == 1
	}
	println('PASS HTTPS signed transaction ' + mode + ' bounded requests, progress and persistent state')
}

fn check() ! {
	if os.args.len != 3 { return error('usage: https-check HTTPS_FIXTURE NEW_WORK_DIRECTORY') }
	work := os.abs_path(os.args[2])
	if os.exists(work) { return error('qualification work directory must be new') }
	os.mkdir_all(work + '/repository')!
	certificate(work)!
	mut environment := []SavedEnvironment{}
	for name, value in {'CURL_CA_BUNDLE': work + '/ca.pem', 'NO_PROXY': '127.0.0.1,localhost',
		'no_proxy': '127.0.0.1,localhost', 'CURL_HOME': work, 'VINIX_HTTPS_EVENTS': ''} {
		if old := os.getenv_opt(name) { environment << SavedEnvironment{name: name, value: old, present: true} }
		else { environment << SavedEnvironment{name: name} }
		os.setenv(name, value, true)
	}
	defer { for old in environment { if old.present { os.setenv(old.name, old.value, true) } else { os.unsetenv(old.name) } } }
	// This must be ignored by the production curl invocation's first --disable.
	os.write_file(work + '/.curlrc', 'insecure\n')!
	text := 'authenticated HTTPS payload\n'.repeat(8192)
	os.write_file(work + '/repository/payload', text)!
	os.write_file(work + '/requests.txt', '')!
	mut server := os.new_process(os.abs_path(os.args[1]))
	server.set_args([work + '/ca.pem', work + '/key.pem', work + '/repository', work + '/ready', work + '/requests.txt'])
	server.set_redirect_stdio_merged()
	server.run()
	defer {
		if server.is_alive() { server.signal_kill() }
		server.wait(); os.write_file(work + '/server.txt', server.stdout_slurp()) or {}; server.close()
	}
	base := wait_ready(work + '/ready', mut server)!
	for mode in ['ranges', 'no-range'] {
		path := work + '/' + mode + '.part'
		os.write_file(path, text[..4096])!
		pkgcore.fetch(base + '/' + mode + '/payload', path, u64(text.len), true, false)!
		assert os.read_file(path)! == text
		println('PASS HTTPS ' + mode + ' recovered authenticated bytes')
	}
	// TLS failures and transport policy refusals must preserve a reusable prefix.
	os.mkdir(work + '/untrusted')!
	certificate(work + '/untrusted')!
	for mode in ['untrusted-ca', 'wrong-host', 'offline', 'plain-http', 'oversized'] {
		path := work + '/' + mode + '.part'
		os.write_file(path, text[..4096])!
		if mode == 'untrusted-ca' { os.setenv('CURL_CA_BUNDLE', work + '/untrusted/ca.pem', true) }
		url := if mode == 'wrong-host' { base.replace('127.0.0.1', 'localhost') + '/ranges/payload' }
			else if mode == 'plain-http' { base.replace('https://', 'http://') + '/ranges/payload' }
			else { base + '/' + if mode == 'oversized' { 'oversized' } else { 'ranges' } + '/payload' }
		mut message := ''
		pkgcore.fetch(url, path, u64(text.len), mode != 'oversized', mode == 'offline') or { message = err.msg() }
		os.setenv('CURL_CA_BUNDLE', work + '/ca.pem', true)
		assert message != '', mode
		assert os.read_file(path)! == text[..4096], mode
		if mode in ['untrusted-ca', 'wrong-host'] { assert message.contains('download failed (60)'), message }
		if mode == 'oversized' { assert message.contains('download failed (63)'), message }
		println('PASS HTTPS ' + mode + ' refusal preserves the prefix')
	}
	os.mkdir_all(work + '/source/share')!
	os.write_file(work + '/source/share/payload', text)!
	os.write_file(work + '/manifest.json', json2.encode(pkgcore.Package{id: 'https-app', version: '1.0.0',
		architecture: 'all', name: 'HTTPS fixture', kind: 'data', license: 'MIT'}))!
	p := pkgcore.pack(work + '/manifest.json', work + '/source', work + '/repository')!
	key := pkgcore.keygen(work + '/seed')!
	pkgcore.publish(work + '/repository', 'tls-fixture', work + '/seed', 1, time.now().unix() + 3600)!
	for mode in ['ranges', 'no-range', 'bad-prefix', 'no-range-corrupt', 'truncated', 'forbidden', 'insecure-redirect'] {
		qualify_transaction(work, base, mode, text, key, p.files[0])!
	}
	println('Package HTTPS: real curl, certificate and redirect enforcement, Range fallback, interrupted recovery, bounded integrity retry and rollback passed')
}

fn main() { check() or { eprintln(err); exit(1) } }
