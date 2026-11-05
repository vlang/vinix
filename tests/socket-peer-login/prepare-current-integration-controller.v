// SPDX-License-Identifier: GPL-2.0-or-later
// Fixed source derivation only. Never compiles, builds, audits or starts a VM.
module main

import crypto.sha256
import json2
import os

const repository = '/Users/alex/code/vinix'
const worktree = repository + '/build/package-peer-frame-current-20261105-worktree'
const state = '/Users/alex/Library/Caches/vinix-codex/section14/current-peer-frame-integration-20261105-01'
const output = state + '/controller-reproduction-01'
const original_sha = '20aa8efe95413e461a2cb95f1a0fd94331709fa79225029f334cc72103cc43dd'
const prepared_sha = '46be2985c371399c6f1b6081fc58340cce9a67d20baf3bca1fc2efac4e2ccc31'

struct Edit {
	label string
	old string
	new string
	count int = 1
}

fn require(ok bool, message string) ! {
	if !ok { return error(message) }
}

fn present(path string) bool {
	return os.exists(path) || os.is_link(path)
}

fn sum(body string) string {
	return sha256.sum(body.bytes()).hex()
}

fn stable(path string, expected string) !string {
	require(os.real_path(path) == path, 'canonical input required: ' + path)!
	before := os.lstat(path)!
	require(before.mode & 0o170000 == 0o100000 && before.size <= 4 * 1024 * 1024,
		'bounded ordinary source required: ' + path)!
	body := os.read_file(path)!
	after := os.lstat(path)!
	require(before.dev == after.dev && before.inode == after.inode && before.mode == after.mode
		&& before.uid == after.uid && before.gid == after.gid && before.size == after.size
		&& before.mtime == after.mtime && before.ctime == after.ctime && u64(body.len) == after.size,
		'source changed during read: ' + path)!
	require(sum(body) == expected, 'source hash differs: ' + path)!
	return body
}

fn change(body string, edit Edit) !string {
	require(edit.old != '' && edit.new != '' && edit.old != edit.new && edit.count == 1
		&& body.count(edit.old) == edit.count && body.count(edit.new) == 0,
		'exact replacement input differs: ' + edit.label)!
	changed := body.replace(edit.old, edit.new)
	require(changed.count(edit.new) == edit.count && changed.count(edit.old) == 0
		&& changed.len == body.len + edit.count * (edit.new.len - edit.old.len)
		&& changed.replace(edit.new, edit.old) == body,
		'replacement changes unrelated bytes: ' + edit.label)!
	return changed
}

fn edits() []Edit {
	return [
		Edit{label: 'selected revision', old: "const revision = '9acefa77bee69247c837e97987a2377536aa41cc'", new: "const revision = 'ffe3a39016fe89ff494cf59fa1126aca8a76dee5'"},
		Edit{label: 'tracker source', old: "root + '/kernel/alloctrack/track_d_alloc_track.v': '23aacc0a9c15cb1f22a6fd808c7b849d7ac203975c10118dbf9a0a509660302e'", new: "root + '/kernel/alloctrack/track_d_alloc_track.v': '1948b5f6d2bc30dae9ca50bc5726ee47937d56bcb05869891ceb9e644e4fa698'"},
		Edit{label: 'UNIX source', old: "else { 'c869568959cd09e16b58dbcc5400b49fdb0a1cb27275d0b73c430dce8f82f810' }", new: "else { 'fec45e9c6f5ac12c615b3e8790ae0307ba809381e3a36cc36c220feb37951261' }"},
		Edit{label: 'candidate root', old: 'root := if frame_baseline { frame_baseline_root } else { controller_root }', new: "root := if frame_baseline { frame_baseline_root } else { repository + '/build/package-peer-frame-current-20261105-worktree' }"},
		Edit{label: 'as-run source capture', old: "\t\t'tests/socket-peer-login/dylibclosure/core.v', 'tests/socket-peer-login/dylibclosure/core_test.v'] {", new: "\t\t'tests/socket-peer-login/dylibclosure/core.v', 'tests/socket-peer-login/dylibclosure/core_test.v',\n\t\t'tests/socket-peer-login/current-head-profile/guarded-build-check.v',\n\t\t'tests/socket-peer-login/current-head-profile/abi.h',\n\t\t'tests/socket-peer-login/current-head-profile/dylibclosure/core.v',\n\t\t'tests/socket-peer-login/current-head-profile/dylibclosure/core_test.v'] {"},
	]
}

fn run() ! {
	require(os.args.len == 1, 'fixed source preparer accepts no operands')!
	require(os.read_file(@FILE)! == $embed_file('prepare-current-integration-controller.v').to_string(),
		'preparer source differs from compiled source')!
	for path in [worktree, state] {
		require(os.real_path(path) == path && os.lstat(path)!.mode & 0o170000 == 0o040000,
			'canonical ordinary directory required: ' + path)!
	}
	require(!present(output), 'fresh reproduction directory required')!
	parent := worktree + '/tests/socket-peer-login'
	original := stable(parent + '/guarded-build-check.v', original_sha)!
	prepared := stable(parent + '/current-head-profile/guarded-build-check.v', prepared_sha)!
	changes := edits()
	require(changes.len == 5, 'exactly five substitutions required')!
	mut body := original
	for edit in changes { body = change(body, edit)! }
	mut inverse := body
	for i := changes.len - 1; i >= 0; i-- { inverse = inverse.replace(changes[i].new, changes[i].old) }
	require(inverse == original && body == prepared && sum(body) == prepared_sha,
		'complete inverse or reviewed prepared bytes differ')!
	pins := {
		'abi.h': '363c81fbbf005e6a396c43c9f66834ed31098caf2b71c89d134e623d30654a5e'
		'dylibclosure/core.v': '503f30711a16017ef56a12555bf609dfb5ecb5bad4d0ec5ff18e3768caf6727c'
		'dylibclosure/core_test.v': 'ca9b386e31bc3ccd92b02c91d3d8322b4778e844dc7735d3736620f0fd464346'
	}
	mut closure := map[string]string{}
	for relative, pin in pins {
		closure[relative] = stable(parent + '/' + relative, pin)!
		require(stable(parent + '/current-head-profile/' + relative, pin)! == closure[relative],
			'prepared closure differs: ' + relative)!
	}
	os.mkdir(output)!
	os.mkdir(output + '/dylibclosure')!
	os.write_file(output + '/guarded-build-check.v', body)!
	stable(output + '/guarded-build-check.v', prepared_sha)!
	for relative, content in closure {
		os.write_file(output + '/' + relative, content)!
		stable(output + '/' + relative, pins[relative])!
		stable(parent + '/' + relative, pins[relative])!
		stable(parent + '/current-head-profile/' + relative, pins[relative])!
	}
	stable(parent + '/guarded-build-check.v', original_sha)!
	stable(parent + '/current-head-profile/guarded-build-check.v', prepared_sha)!
	os.write_file(output + '/derivation.json', json2.encode({'format': '1',
		'original_source': parent + '/guarded-build-check.v', 'original_sha256': original_sha,
		'prepared_reference': parent + '/current-head-profile/guarded-build-check.v',
		'prepared_sha256': prepared_sha, 'result_source': output + '/guarded-build-check.v',
		'result_sha256': sum(body), 'substitutions': json2.encode(changes),
		'exact_substitution_count': '5', 'complete_inverse': 'equal to original bytes',
		'scope': 'Exact reviewed source reproduction only. No compile, build, audit, VM or qualification.'}) + '\n')!
	println('CURRENT INTEGRATION CONTROLLER SOURCE REPRODUCTION PASS ' + prepared_sha)
}

fn main() {
	run() or { eprintln(err); exit(1) }
}
