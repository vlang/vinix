// SPDX-License-Identifier: GPL-2.0-or-later
// An SDK consumer using only the public wire API and the real package CLI.
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
		if os.is_link(root + path) { entries[path] = 'symlink:' + os.readlink(root + path)! }
		else if os.is_dir(root + path) { entries[path] = 'directory'; tree(root, path, mut entries)! }
		else { entries[path] = digest(root + path)! }
	}
}

fn invoke(cli string, root string, path string) !(int, string) {
	mut child := os.new_process(cli)
	defer { child.close() }
	child.set_args(['--root', root, '--json', 'deployment-review', path])
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	text := child.stdout_slurp()
	child.wait()
	return child.code, text
}

fn check() ! {
	if os.args.len != 3 { return error('usage: deployment-writer-check PACKAGE_EXECUTABLE NEW_WORK_DIRECTORY') }
	cli := os.real_path(os.args[1])
	work := os.abs_path(os.args[2])
	require(os.is_file(cli) && !os.exists(work) && !os.is_link(work), 'provide a CLI and a new private directory')!
	os.mkdir_all(work + '/root/etc/vinix-packages', mode: 0o755)!
	root := work + '/root'
	os.write_file(root + '/etc/vinix-packages/config.json', '{"format":1,"architecture":"aarch64","repositories":[],"policy":{"offline":true,"reserve_bytes":0}}\n')!
	os.mkdir_all(root + '/var/lib/vinix-packages/generations', mode: 0o755)!
	os.mkdir(root + '/var/lib/vinix-packages/objects', mode: 0o755)!
	os.write_file(root + '/var/lib/vinix-packages/lock', '')!
	os.write_file(root + '/sentinel', 'preserve unrelated data\n')!
	mut roots := ['INVALID']
	mut duplicate_roots := ['org.example.app', 'org.example.app']
	mut absent_roots := ['org.example.app']
	mut pins := [pkgprotocol.DeploymentPin{ id: 'org.example.app', version: '1.0.0', architecture: 'aarch64',
		repository: 'publisher', public_key: 'a'.repeat(64), minimum_sequence: 0, metadata_sha256: 'b'.repeat(64) }]
	defer { unsafe { (&array(&roots)).free(); (&array(&duplicate_roots)).free(); (&array(&absent_roots)).free();
		pins[0].public_key.free(); pins[0].metadata_sha256.free(); (&array(&pins)).free() } }
	documents := [pkgprotocol.DeploymentDocument{ format: 1, architecture: 'aarch64' },
		pkgprotocol.DeploymentDocument{ format: 2, architecture: 'aarch64' },
		pkgprotocol.DeploymentDocument{ format: 1, architecture: 'x86_64' },
		pkgprotocol.DeploymentDocument{ format: 1, architecture: 'aarch64', packages: roots },
		pkgprotocol.DeploymentDocument{ format: 1, architecture: 'aarch64', packages: duplicate_roots },
		pkgprotocol.DeploymentDocument{ format: 1, architecture: 'aarch64', packages: absent_roots },
		pkgprotocol.DeploymentDocument{ format: 2, architecture: 'aarch64', locked: pins }]
	defer { unsafe { (&array(&documents)).free() } }
	mut before := map[string]string{}
	tree(root, '', mut before)!
	mut inputs := map[string]string{}
	for index, document in documents {
		path := work + '/deployment-' + index.str() + '.json'
		text := document.encode()!
		defer { unsafe { text.free() } }
		os.write_file(path, text)!
		inputs[path] = digest(path)!
		code, reply := invoke(cli, root, path)!
		defer { unsafe { reply.free() } }
		os.write_file(path + '.reply', reply)!
		if index < 2 {
			require(code == 0, 'CLI refused an encoded empty deployment')!
			mut review := pkgprotocol.decode_review(reply)!
			defer { review.close() }
			require(review.operation == 'deploy' && review.architecture == 'aarch64' && review.rows.len == 0
				&& review.generation == 0 && review.fingerprint.len == 64 && review.requested.len == 0,
				'unexpected deployment review')!
		} else { require(code != 0, 'wire encoding bypassed service semantic/catalog validation')! }
	}
	mut after := map[string]string{}
	tree(root, '', mut after)!
	require(before == after, 'read-only review changed package configuration, state or unrelated files')!
	for path, hash in inputs { require(digest(path)! == hash, 'CLI changed encoded input')! }
	os.write_file(work + '/evidence.json', json2.encode({ 'cli_sha256': digest(cli)!,
		'accepted_empty_versions': '1,2', 'service_semantic_or_catalog_refusals': '5',
		'package_tree_unchanged': 'true', 'scope': 'wire/CLI review compatibility; no install, trust or application-runtime qualification' }) + '\n')!
	println('DEPLOYMENT WRITER real CLI accepts formats 1/2, refuses five semantic/catalog cases, preserves package tree PASS')
}

fn main() { check() or { eprintln(err); exit(1) } }
