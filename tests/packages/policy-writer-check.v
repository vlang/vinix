// SPDX-License-Identifier: GPL-2.0-or-later
// Public SDK consumer: submit authored policy to the real read-only CLI.
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
		} else {
			entries[path] = digest(root + path)!
		}
	}
}

fn invoke(cli string, root string, path string) !(int, string) {
	mut child := os.new_process(cli)
	defer { child.close() }
	child.set_args(['--root', root, '--json', 'policy-review', path])
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0])
	child.stdio_fd[0] = -1
	text := child.stdout_slurp()
	child.wait()
	return child.code, text
}

fn check() ! {
	if os.args.len != 3 {
		return error('usage: policy-writer-check PACKAGE_EXECUTABLE NEW_WORK_DIRECTORY')
	}
	cli := os.real_path(os.args[1])
	work := os.abs_path(os.args[2])
	require(os.is_file(cli) && !os.exists(work) && !os.is_link(work), 'provide a CLI and new private directory')!
	root := work + '/root'
	os.mkdir_all(root + '/etc/vinix-packages', mode: 0o755)!
	os.write_file(root + '/etc/vinix-packages/config.json', '{"format":1,"architecture":"aarch64","repositories":[],"policy":{"offline":true,"reserve_bytes":0}}\n')!
	os.mkdir_all(root + '/var/lib/vinix-packages/generations', mode: 0o755)!
	os.mkdir(root + '/var/lib/vinix-packages/objects', mode: 0o755)!
	os.write_file(root + '/var/lib/vinix-packages/lock', '')!
	os.write_file(root + '/sentinel', 'preserve unrelated data\n')!
	// These arrays are caller-owned buffers borrowing literal strings.
	mut allowed := ['org.example.z', 'org.example.a']
	mut pins := [
		pkgprotocol.PolicyPin{ id: 'org.example.z', minimum: '1.0.0', before: '2.0.0' },
		pkgprotocol.PolicyPin{ id: 'org.example.a', before: '3.0.0' },
	]
	mut permissions := ['process', 'files']
	mut licenses := ['Zlib', 'MIT']
	mut duplicate := ['org.example.a', 'org.example.a']
	mut bad_ids := ['Invalid']
	mut bad_pins := [pkgprotocol.PolicyPin{ id: 'org.example.a', minimum: '2.0.0', before: '1.0.0' }]
	mut duplicate_pins := [pkgprotocol.PolicyPin{ id: 'org.example.a' },
		pkgprotocol.PolicyPin{ id: 'org.example.a' }]
	mut bad_permissions := ['administrator']
	mut duplicate_licenses := ['MIT', 'MIT']
	defer {
		unsafe {
			(&array(&allowed)).free()
			(&array(&pins)).free()
			(&array(&permissions)).free()
			(&array(&licenses)).free()
			(&array(&duplicate)).free()
			(&array(&bad_ids)).free()
			(&array(&bad_pins)).free()
			(&array(&duplicate_pins)).free()
			(&array(&bad_permissions)).free()
			(&array(&duplicate_licenses)).free()
		}
	}
	base := pkgprotocol.PolicyDocument{ format: 1, architecture: 'aarch64' }
	proposed := pkgprotocol.PolicySettings{
		offline:        true
		allowed:        allowed
		pins:           pins
		permissions:    permissions
		licenses:       licenses
		allow_firmware: true
		reserve_bytes:  1024
	}
	mut sorted_allowed := ['org.example.a', 'org.example.z']
	mut sorted_pins := [pins[1], pins[0]]
	mut sorted_permissions := ['files', 'process']
	mut sorted_licenses := ['MIT', 'Zlib']
	defer {
		unsafe {
			(&array(&sorted_allowed)).free()
			(&array(&sorted_pins)).free()
			(&array(&sorted_permissions)).free()
			(&array(&sorted_licenses)).free()
		}
	}
	canonical := pkgprotocol.PolicySettings{
		...proposed
		allowed:     sorted_allowed
		pins:        sorted_pins
		permissions: sorted_permissions
		licenses:    sorted_licenses
	}
	mut documents := [base, pkgprotocol.PolicyDocument{ ...base, policy: proposed },
		pkgprotocol.PolicyDocument{ ...base, policy: canonical },
		pkgprotocol.PolicyDocument{ ...base, architecture: 'x86_64' },
		pkgprotocol.PolicyDocument{ ...base, policy: pkgprotocol.PolicySettings{ allowed: duplicate } },
		pkgprotocol.PolicyDocument{ ...base, policy: pkgprotocol.PolicySettings{ allowed: bad_ids } },
		pkgprotocol.PolicyDocument{ ...base, policy: pkgprotocol.PolicySettings{ pins: bad_pins } },
		pkgprotocol.PolicyDocument{ ...base, policy: pkgprotocol.PolicySettings{ pins: duplicate_pins } },
		pkgprotocol.PolicyDocument{ ...base, policy: pkgprotocol.PolicySettings{ permissions: bad_permissions } },
		pkgprotocol.PolicyDocument{ ...base, policy: pkgprotocol.PolicySettings{ licenses: duplicate_licenses } },
		pkgprotocol.PolicyDocument{ ...base, policy: pkgprotocol.PolicySettings{ reserve_bytes: (u64(1) << 40) + 1 } }]
	defer { unsafe { (&array(&documents)).free() } }
	mut before := map[string]string{}
	tree(root, '', mut before)!
	mut inputs := map[string]string{}
	mut full_fingerprint := ''
	defer { unsafe { full_fingerprint.free() } }
	for index, document in documents {
		path := work + '/policy-' + index.str() + '.json'
		text := document.encode()!
		defer { unsafe { text.free() } }
		os.write_file(path, text)!
		inputs[path] = digest(path)!
		code, reply := invoke(cli, root, path)!
		defer { unsafe { reply.free() } }
		os.write_file(path + '.reply', reply)!
		if index < 3 {
			require(code == 0, 'CLI refused a valid encoded policy')!
			mut review := pkgprotocol.decode_policy_review(reply)!
			defer { review.close() }
			require(review.format == 1 && review.architecture == 'aarch64' && review.generation == 0
				&& review.rows.len == 0 && review.fingerprint.len == 64, 'unexpected policy review')!
			if index == 0 {
				require(review.proposed == base.policy, 'empty/false fields changed')!
			} else {
				require(review.proposed == canonical, 'service did not canonicalize full authored settings')!
				if index == 1 {
					full_fingerprint = review.fingerprint.clone()
				} else {
					require(review.fingerprint == full_fingerprint, 'order affected canonical review fingerprint')!
				}
			}
		} else {
			require(code != 0, 'wire writer bypassed service semantic validation')!
		}
		mut after := map[string]string{}
		tree(root, '', mut after)!
		require(before == after, 'review/refusal changed package configuration, state or unrelated files')!
	}
	require(allowed == ['org.example.z', 'org.example.a'] && pins[0].id == 'org.example.z'
		&& permissions == ['process', 'files'] && licenses == ['Zlib', 'MIT'], 'writer altered borrowed input')!
	for path, hash in inputs { require(digest(path)! == hash, 'CLI changed encoded proposal')! }
	os.write_file(work + '/evidence.json', json2.encode({
		'cli_sha256':                           digest(cli)!
		'valid_reviews':                        '3'
		'semantic_refusals':                    '8'
		'package_tree_and_proposals_unchanged': 'true'
		'scope':                                'host SDK authoring/real CLI read-only compatibility; no apply, trust or target execution'
	}) + '\n')!
	println('POLICY WRITER real CLI accepts complete/empty/arbitrary-order policies, canonical fingerprint agrees, refuses 8 semantic cases, preserves state PASS')
}

fn main() {
	check() or {
		eprintln(err)
		exit(1)
	}
}
