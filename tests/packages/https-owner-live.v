// SPDX-License-Identifier: GPL-2.0-or-later
module main
import os
import json2
import time
import tools.packages.pkgcore
import tools.packages.pkgprotocol
$if track_heap ? {
	#include "@VMODROOT/../../desktop/tools/tests/heap_tracker.h"
}
fn C.vinix_heap_begin()
fn C.vinix_heap_end() u64

fn command(args []string, log string) ! {
	mut child := os.new_process(args[0]); child.set_args(args[1..]); child.set_redirect_stdio_merged()
	child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(log, output)!; assert code == 0, output
}
fn certificate(work string) ! {
	os.mkdir_all(work)!
	os.write_file(work + '/certificate.cnf', '[req]\nprompt=no\ndistinguished_name=subject\nx509_extensions=extensions\n'
		+ '[subject]\nCN=Vinix HTTPS owner fixture\n[extensions]\nbasicConstraints=critical,CA:TRUE\n'
		+ 'keyUsage=critical,digitalSignature,keyEncipherment,keyCertSign\nextendedKeyUsage=serverAuth\nsubjectAltName=IP:127.0.0.1\n')!
	command(['openssl', 'req', '-new', '-x509', '-newkey', 'rsa:2048', '-nodes', '-days', '1', '-config',
		work + '/certificate.cnf', '-keyout', work + '/key.pem', '-out', work + '/ca.pem'], work + '/certificate.txt')!
	os.chmod(work + '/key.pem', 0o600)!
}
fn ready(path string, mut server os.Process) !string {
	for _ in 0 .. 500 {
		if os.exists(path) { return os.read_file(path) }
		assert server.is_alive(), 'TLS fixture exited before binding'
		time.sleep(10 * time.millisecond)
	}
	return error('TLS fixture did not become ready')
}
fn event(progress pkgprotocol.Progress) { progress.validate() or { panic(err) } }
fn request_count(work string) !int {
	text := os.read_file(work + '/requests.txt')!
	defer { unsafe { text.free() } }
	lines := text.split_into_lines(); defer { unsafe { lines.free() } }
	return lines.len
}
struct Live {
	work string
	base string
	text string
	key string
	payload pkgcore.Payload
	index string
	signature string
}
fn scope(f Live, arch string, mode string) ! {
	label := if arch == '' { mode.clone() } else { arch + ' ' + mode }
	defer { unsafe { label.free() } }
	root := f.work + '/store-' + label.replace(' ', '-')
	store := pkgcore.state_directory(root)
	target := f.work + '/transfer.part'
	object := store + '/objects/' + f.payload.sha256
	part := object + '.part'
	current := store + '/current'
	ca := f.work + if mode.ends_with('-untrusted') { '/untrusted/ca.pem' } else { '/ca.pem' }
	base := if mode.ends_with('-hostname') { f.base.replace('127.0.0.1', 'localhost') } else { f.base.clone() }
	route := if mode.ends_with('-fallback') || mode.ends_with('-corrupt') { 'no-range' + if mode.ends_with('-corrupt') { '-corrupt' } else { '' } }
		else if mode.ends_with('-truncated') { 'truncated' } else if mode.ends_with('-http') { 'forbidden' }
		else if mode.ends_with('-redirect') { 'insecure-redirect' } else if mode.ends_with('-size') { 'oversized' } else { 'ranges' }
	url := base + '/' + route
	service := pkgcore.Service{root: root, progress: event}
	mut history := ''
	os.setenv('CURL_CA_BUNDLE', f.work + '/ca.pem', true)
	if !mode.starts_with('fetch-') {
		os.mkdir_all(root + '/etc/vinix-packages')!
		config := pkgcore.Config{architecture: arch, repositories: [pkgcore.Repository{id: 'tls-owner', public_key: f.key, url: f.base + '/ranges'}],
			policy: pkgcore.Policy{reserve_bytes: 0}}
		os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(config))!
		mut catalog := service.refresh()!; catalog.close()
		history = os.read_file(store + '/trust-history.json')!
		repository := pkgcore.Repository{...config.repositories[0], url: url}
		os.write_file(root + '/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{...config, repositories: [repository]}))!
		os.write_file(store + '/catalog.json', json2.encode([pkgcore.Snapshot{repository: repository, text: f.index, signature: f.signature}]))!
	}
	cache := if mode.starts_with('refresh-') { os.read_file(store + '/catalog.json')! } else { '' }
	names := ['app']
	defer { unsafe { (&array(&names)).free() } }
	mut retained := u64(0)
	for pass in 0 .. 2 {
		loops := if pass == 0 { 2 } else { 64 }
		for _ in 0 .. loops {
			os.setenv('CURL_CA_BUNDLE', ca, true)
			// Setup and persistent-state observations stay outside the measured call.
			prefix := if mode.ends_with('-bad-prefix') { 'x'.repeat(512) } else { f.text[..512] }
			if mode.starts_with('fetch-') { os.write_file(target, prefix)! }
			if mode.starts_with('install-') {
				C.remove(current.str); C.remove(object.str); C.remove(part.str)
				if os.exists(store + '/generations/1') { os.rmdir_all(store + '/generations/1')! }
				if mode !in ['install-fresh', 'install-untrusted', 'install-hostname']! { os.write_file(part, prefix)! }
			}
			if mode == 'refresh-signature' { os.write_file(f.work + '/repository/index.sig', '00'.repeat(64))! }
			before := request_count(f.work)!
			$if track_heap ? { C.vinix_heap_begin() }
			mut refused := false
			mut message := ''
			if mode.starts_with('fetch-') {
				resource := if mode.ends_with('-http') || mode.ends_with('-redirect') { '/objects/' + f.payload.sha256 } else { '/payload' }
				endpoint := url + resource
				pkgcore.fetch(endpoint, target, u64(f.text.len), mode != 'fetch-fresh' && mode != 'fetch-size', false) or {
					refused = true; message = err.msg(); unsafe { err.free() }
				}
				unsafe { endpoint.free(); resource.free() }
			} else if mode.starts_with('refresh-') {
				mut catalog := service.refresh() or { refused = true; message = err.msg(); unsafe { err.free() }; pkgcore.Catalog{} }
				catalog.close()
			} else {
				mut result := service.transact('install', names, pkgcore.TransactionOptions{}) or {
					refused = true; message = err.msg(); unsafe { err.free() }; pkgcore.State{}
				}
				if !refused { assert result.generation == 1 && result.packages[0].package.files[0] == f.payload }
				result.close(); result.close()
			}
			expected_failure := mode.ends_with('-untrusted') || mode.ends_with('-hostname') || mode.ends_with('-http')
				|| mode.ends_with('-redirect') || mode.ends_with('-size') || mode.ends_with('-truncated')
				|| mode.ends_with('-corrupt') || mode.ends_with('-signature')
			assert refused == expected_failure, label + ': ' + message
			if refused {
				wanted := if mode.ends_with('-untrusted') || mode.ends_with('-hostname') { 'download failed (60)' }
					else if mode.ends_with('-http') { 'download failed (22)' } else if mode.ends_with('-redirect') { 'download failed (1)' }
					else if mode.ends_with('-size') { 'download failed (63)' } else if mode.ends_with('-truncated') { 'download failed (18)' }
					else if mode.ends_with('-signature') { 'signature verification failed' } else { 'checksum or size mismatch' }
				assert message.contains(wanted), message
			}
			unsafe { message.free() }
			$if track_heap ? { bytes := C.vinix_heap_end(); if pass == 1 { retained += bytes } }
			os.write_file(f.work + '/repository/index.sig', f.signature)!
			if mode.starts_with('refresh-') && refused {
				assert os.read_file(store + '/catalog.json')! == cache && os.read_file(store + '/trust-history.json')! == history
			}
			if mode.starts_with('install-') {
				assert os.exists(current) == !refused && !os.exists(store + '/generations/.stage-1')
				if !refused { assert os.read_file(object)! == f.text && os.read_file(current + '/apps/app/share/payload')! == f.text }
				else { assert !os.exists(store + '/generations/1') }
			}
			if mode.starts_with('fetch-') && !refused { assert os.read_file(target)! == f.text }
			if mode.ends_with('-truncated') { assert os.file_size(if mode.starts_with('fetch-') { target } else { part }) == 1536 }
			if mode.ends_with('-corrupt') { assert !os.exists(part) }
			if mode.ends_with('-http') || mode.ends_with('-redirect') || mode.starts_with('fetch-') && refused && !mode.ends_with('-truncated') {
				assert os.read_file(if mode.starts_with('fetch-') { target } else { part })! == prefix
			}
			count := request_count(f.work)! - before
			wanted_count := if mode.ends_with('-untrusted') || mode.ends_with('-hostname') { 0 }
				else if mode.starts_with('refresh-') || mode.ends_with('-fallback') || mode.ends_with('-bad-prefix') || mode.ends_with('-corrupt') { 2 } else { 1 }
			assert count == wanted_count, label
		}
	}
	println('HTTPS LIVE ' + label + ' retained ' + retained.str() + ' tracked bytes')
	assert retained == 0, label
}
fn check() ! {
	assert os.args.len == 3, 'usage: https-owner-live TLS_FIXTURE NEW_WORK'
	work := os.abs_path(os.args[2]); assert !os.exists(work); os.mkdir_all(work + '/repository')!
	certificate(work)!; certificate(work + '/untrusted')!
	for name in ['CURL_CA_BUNDLE', 'NO_PROXY', 'no_proxy', 'CURL_HOME']! {
		// This controller is a dedicated child of the host driver; its environment
		// changes cannot affect the invoking shell or install a system trust anchor.
		os.unsetenv(name)
	}
	os.setenv('NO_PROXY', '127.0.0.1,localhost', true); os.setenv('no_proxy', '127.0.0.1,localhost', true)
	os.setenv('CURL_HOME', work, true); os.setenv('CURL_CA_BUNDLE', work + '/ca.pem', true)
	os.write_file(work + '/.curlrc', 'insecure\n')!
	text := 'authenticated HTTPS payload\n'.repeat(1024)
	os.write_file(work + '/repository/payload', text)!; os.write_file(work + '/requests.txt', '')!
	os.mkdir_all(work + '/source/share')!; os.write_file(work + '/source/share/payload', text)!
	os.write_file(work + '/manifest.json', json2.encode(pkgcore.Package{id: 'app', name: 'HTTPS owner é🚀',
		version: '1.0.0', architecture: 'all', kind: 'data', license: 'MIT'}))!
	package := pkgcore.pack(work + '/manifest.json', work + '/source', work + '/repository')!
	key := pkgcore.keygen(work + '/seed')!
	pkgcore.publish(work + '/repository', 'tls-owner', work + '/seed', 1, time.now().unix() + 86400)!
	mut server := os.new_process(os.abs_path(os.args[1]))
	server.set_args([work + '/ca.pem', work + '/key.pem', work + '/repository', work + '/ready', work + '/requests.txt'])
	// Inherit the controller's drained output: repeated TLS refusals must not
	// fill a separate undrained server diagnostic pipe.
	server.run()
	defer {
		if server.is_alive() { server.signal_kill() }
		server.wait(); server.close()
	}
	f := Live{work: work, base: ready(work + '/ready', mut server)!, text: text, key: key, payload: package.files[0],
		index: os.read_file(work + '/repository/index.json')!, signature: os.read_file(work + '/repository/index.sig')!}
	for mode in ['fetch-fresh', 'fetch-resume', 'fetch-fallback', 'fetch-truncated', 'fetch-http', 'fetch-redirect', 'fetch-untrusted', 'fetch-hostname', 'fetch-size']! { scope(f, '', mode)! }
	for arch in ['aarch64', 'x86_64']! {
		for mode in ['refresh-fresh', 'refresh-untrusted', 'refresh-hostname', 'refresh-signature', 'install-fresh', 'install-resume',
			'install-fallback', 'install-bad-prefix', 'install-truncated', 'install-http', 'install-redirect', 'install-corrupt', 'install-untrusted', 'install-hostname']! { scope(f, arch, mode)! }
	}
	println('HTTPS LIVE 37 cases with 64 measured calls preserve authenticated state, TLS policy, bounded recovery and independent replies PASS')
}
fn main() { check() or { eprintln(err); exit(1) } }
