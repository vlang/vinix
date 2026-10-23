// SPDX-License-Identifier: GPL-2.0-or-later
// Real CLI configuration admission; no enrollment, network or state mutation.
module main

import crypto.sha256
import json2
import os
import tools.packages.pkgprotocol

#include <unistd.h>

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn digest(path string) !string { return sha256.hexhash(os.read_file(path)!) }

fn tree(root string, relative string, mut entries map[string]string) ! {
	for name in os.ls(root + relative)! {
		path := relative + '/' + name
		if os.is_link(root + path) {
			entries[path] = 'symlink:' + os.readlink(root + path)!
		} else if os.is_dir(root + path) {
			entries[path] = 'directory'
			tree(root, path, mut entries)!
		} else { entries[path] = digest(root + path)! }
	}
}

fn invoke(cli string, root string, json bool, log string) !(int, string) {
	mut argv := ['--root', root]
	if json { argv << '--json' }
	argv << 'repo-config'
	os.write_file(log + '.argv.json', json2.encode([cli, ...argv]) + '\n')!
	mut child := os.new_process(cli)
	defer { child.close() }
	child.set_args(argv)
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	text := child.stdout_slurp()
	child.wait()
	os.write_file(log, text)!
	return child.code, text
}

fn check() ! {
	if os.args.len != 3 { return error('usage: repository-url-check PACKAGE_EXECUTABLE NEW_OUTPUT_DIRECTORY') }
	cli := os.real_path(os.args[1]); work := os.abs_path(os.args[2])
	require(os.is_file(cli) && !os.exists(work) && !os.is_link(work), 'provide CLI and new output directory')!
	os.mkdir_all(work + '/fixtures', mode: 0o700)!
	os.mkdir(work + '/logs', mode: 0o700)!
	fixtures := work + '/fixtures'
	os.write_file(fixtures + '/sentinel', 'preserve unrelated data\n')!
	corrupt := fixtures + '/corrupt'
	os.mkdir_all(corrupt + '/etc/vinix-packages', mode: 0o755)!
	os.write_file(corrupt + '/etc/vinix-packages/config.json', '{broken\n')!
	mut baseline := map[string]string{}
	tree(fixtures, '', mut baseline)!
	for kind in ['missing', 'corrupt'] {
		code, _ := invoke(cli, fixtures + '/' + kind, true, work + '/logs/' + kind)!
		require(code == 1, 'missing/corrupt configuration unexpectedly accepted')!
		mut after := map[string]string{}; tree(fixtures, '', mut after)!
		require(after == baseline, 'missing/corrupt configuration observation mutated fixtures')!
	}
	accepted := [
		'https://localhost:8443/catalog', 'https://localhost:000443/catalog',
		'https://localhost:0/catalog', 'https://localhost:65535/catalog',
		'https://[::1]:10443/catalog', 'https://[fe80::1%25en0]/catalog',
		'https://example.invalid/a%20b/%2F/%3f%23', 'https://example.invalid///',
		'file:///media/repository with spaces; $literal', 'file:///media/100%literal/@repo',
		'https://host/' + 'a'.repeat(4096 - 13), 'file:///' + 'a'.repeat(1024),
	]
	refused := [
		'https://', 'https:///catalog', 'https://:443/catalog',
		'https://user:secret@host/catalog', 'https://host:443@other/catalog',
		'https://host name/catalog', 'https://host/a b', 'https://host/a\x00b',
		'https://host/a\\b', 'https://[[::1]]/catalog', 'https://[::1]]/catalog',
		'https://[::1]:/catalog', 'https://host:65536/catalog', 'https://host:port/catalog',
		'https://host/%', 'https://host/%xy', 'https://host/catalog?query',
		'https://host/catalog#fragment', 'file:///a/../b', 'file:///a//b',
		'https://host/' + 'a'.repeat(4097 - 13), 'file:///' + 'a'.repeat(1025),
	]
	key := 'a'.repeat(64)
	mut controls := 0; mut refusals := 0
	for store in ['fresh', 'existing'] {
		root := fixtures + '/' + store
		os.mkdir_all(root + '/etc/vinix-packages', mode: 0o755)!
		os.write_file(root + '/sentinel', 'preserve root data\n')!
		if store == 'existing' {
			os.mkdir_all(root + '/var/lib/vinix-packages/objects', mode: 0o755)!
			os.write_file(root + '/var/lib/vinix-packages/lock', '')!
			os.write_file(root + '/var/lib/vinix-packages/catalog.json', 'preserve catalog bytes\n')!
			os.write_file(root + '/var/lib/vinix-packages/objects/sentinel', 'preserve immutable payload\n')!
		}
		for good in [true, false] {
			for i, url in if good { accepted } else { refused } {
				require(pkgprotocol.valid_repository_url(url) == good, 'SDK and service matrix disagree')!
				configuration := '{"format":1,"architecture":"aarch64","repositories":[{"id":"fixture","url":'
					+ json2.encode(url) + ',"public_key":"' + key + '"}],"policy":{"offline":true,"reserve_bytes":0}}\n'
				os.write_file(root + '/etc/vinix-packages/config.json', configuration)!
				mut before := map[string]string{}; tree(fixtures, '', mut before)!
				for json in [false, true] {
					log := work + '/logs/' + store + '-' + good.str() + '-' + i.str() + '-' + json.str()
					code, reply := invoke(cli, root, json, log)!
					if good {
						require(code == 0, 'supported configured URL refused; see ' + log)!
						if json {
							mut document := pkgprotocol.decode_repository_configuration(reply)!
							defer { document.close() }
							require(document.repositories.len == 1 && document.repositories[0].url == url
								&& document.repositories[0].public_key == key, 'configured URL bytes changed')!
						} else { require(reply.contains('fixture ' + url + '\n'), 'text observation changed URL bytes')! }
						controls++
					} else {
						// Oversized JSON strings are refused by the bounded decoder first.
						expected := if url.len > 4096 {
							'vinix-package: invalid package configuration: package metadata JSON string exceeds its bound\n'
						} else { 'vinix-package: invalid package configuration: invalid or duplicate repository: fixture\n' }
						require(code == 1 && reply == expected,
							'malformed URL did not reach exact service refusal; see ' + log)!
						refusals++
					}
					mut after := map[string]string{}; tree(fixtures, '', mut after)!
					require(after == before, 'configuration observation/refusal changed fixture state')!
				}
			}
		}
	}
	require(controls == 48 && refusals == 88 && !os.exists(fixtures + '/fresh/var')
		&& !os.exists(fixtures + '/missing'), 'incomplete CLI matrix or unexpected initialization')!
	os.write_file(work + '/result.json', json2.encode({
		'cli_sha256': digest(cli)!
		'accepted_url_controls': controls.str()
		'malformed_url_refusals': refusals.str()
		'missing_corrupt_controls': '2'
		'fixture_tree_unchanged_after_every_outcome': 'true'
	}) + '\n')!
	println('REPOSITORY URL actual CLI 48 literal controls, 88 malformed refusals, 2 missing/corrupt controls; fresh/existing roots unchanged PASS')
}

fn main() { check() or { eprintln(err); exit(1) } }
