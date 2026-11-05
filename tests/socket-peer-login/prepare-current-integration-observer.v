// SPDX-License-Identifier: GPL-2.0-or-later
// Fixed data derivation from the qualified 67-control frame owner.
module main

import crypto.sha256
import json2
import os

const repository = '/Users/alex/code/vinix'
const qualified = '/Users/alex/Library/Caches/vinix-codex/section14/frame-peer-baseline-fresh-20261026-seal-01'
const source = qualified + '/native-profiles-01/primary/source/fresh-frame-observer.v'
const source_sha = '203100b0be37aae9ba593412da22e30fb7507e5bb6acf7dff7765d974264673c'
const state = '/Users/alex/Library/Caches/vinix-codex/section14/current-peer-frame-integration-20261105-01'
const host = state + '/host-bootstrap-01'
const stage = state + '/observer-host-01'
const output = stage + '/derived'
const worktree = repository + '/build/package-peer-frame-current-20261105-worktree'
const controller = host + '/controller/guarded-build-check'
const controller_sha = 'd9d2153f831990a5a2ed20398e09b254b6c24dae77864a4a95fcea1f92c04820'
const controller_source = worktree + '/tests/socket-peer-login/current-head-profile/guarded-build-check.v'
const controller_source_sha = '46be2985c371399c6f1b6081fc58340cce9a67d20baf3bca1fc2efac4e2ccc31'
const input_map_sha = 'e6582519df2c91330848552ba6f1bcd9582ea27a5757c667e12b6ad8bf5f61f5'

struct Edit {
	label string
	old string
	new string
	count int = 1
}

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn present(path string) bool { return os.exists(path) || os.is_link(path) }
fn sum(body string) string { return sha256.sum(body.bytes()).hex() }

fn pin(path string, expected string, limit u64) !string {
	require(os.real_path(path) == path, 'canonical ordinary input required: ' + path)!
	before := os.lstat(path)!
	require(before.mode & 0o170000 == 0o100000 && before.size <= limit,
		'bounded ordinary input required: ' + path)!
	body := os.read_file(path)!
	after := os.lstat(path)!
	require(before.dev == after.dev && before.inode == after.inode && before.mode == after.mode
		&& before.uid == after.uid && before.gid == after.gid && before.size == after.size
		&& before.mtime == after.mtime && before.ctime == after.ctime && u64(body.len) == after.size,
		'input changed during read: ' + path)!
	require(sum(body) == expected, 'reviewed input hash differs: ' + path)!
	return body
}

fn change(body string, edit Edit) !string {
	require(edit.old != '' && edit.new != '' && edit.old != edit.new && edit.count > 0
		&& body.count(edit.old) == edit.count && body.count(edit.new) == 0,
		'exact substitution input differs: ' + edit.label)!
	changed := body.replace(edit.old, edit.new)
	require(changed.count(edit.new) == edit.count && changed.count(edit.old) == 0
		&& changed.len == body.len + edit.count * (edit.new.len - edit.old.len)
		&& changed.replace(edit.new, edit.old) == body,
		'substitution changed unrelated bytes: ' + edit.label)!
	return changed
}

fn edits() []Edit {
	return [
		Edit{label: 'held donor root', old: "const donor = '/Users/alex/code/vinix/build/peer-login-runtime-guarded-worktree'", new: "const donor = '/Users/alex/code/vinix/build/package-peer-login-atomic-fresh-worktree'"},
		Edit{label: 'current worktree', old: "const worktree = '/Users/alex/code/vinix/build/package-peer-login-frame-fresh-worktree'", new: "const worktree = '${worktree}'"},
		Edit{label: 'fresh raw state', old: "const raw = '/Users/alex/Library/Caches/vinix-codex/section14/frame-peer-baseline-fresh-20261026'", new: "const raw = '${state}'"},
		Edit{label: 'qualified controller', old: "const controller = raw + '/bootstrap-01/guarded-build-check'", new: "const controller = raw + '/host-bootstrap-01/controller/guarded-build-check'"},
		Edit{label: 'controller executable pin', old: "const controller_sha = '7ac1b909a935dc3c039617444fcf87ec701d859acfa6e26871a7d421678dfcf4'", new: "const controller_sha = '${controller_sha}'"},
		Edit{label: 'controller source pin', old: "const controller_source_sha = '42e831eb2ef501edc54113cd1731de7eeedfd50fc732407ca9a34ea4e071275a'", new: "const controller_source_sha = '${controller_source_sha}'"},
		Edit{label: 'nested controller source', old: "regular_hash(worktree + '/tests/socket-peer-login/guarded-build-check.v', 1024 * 1024)!", new: "regular_hash(worktree + '/tests/socket-peer-login/current-head-profile/guarded-build-check.v', 1024 * 1024)!"},
		Edit{label: 'Git administration charge', old: 'fn roots() []string { return [donor, worktree, raw, seal] }', new: "fn roots() []string { return [donor, worktree, raw, seal, '/Users/alex/code/vinix/.git/worktrees/package-peer-frame-current-20261105-worktree'] }"},
		Edit{label: 'canonical SDK', old: "'/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk'", new: "'/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk'"},
		Edit{label: 'candidate build argv and control', old: "[controller, '--frame-baseline', raw + '/build-01']", new: "[controller, raw + '/build-01']", count: 2},
		Edit{label: 'paired architecture function', old: "fn frame_arches() []string { return ['x86_64'] }", new: "fn frame_arches() []string { return ['x86_64', 'aarch64'] }"},
		Edit{label: 'paired architecture control', old: "require(frame_arches() == ['x86_64'], 'frame receipt scope differs')!", new: "require(frame_arches() == ['x86_64', 'aarch64'], 'frame receipt scope differs')!"},
		Edit{label: 'both architecture receipts', old: "|| inner['x86_64'].starts_with('unavailable')) {", new: "|| inner['x86_64'].starts_with('unavailable') || inner['aarch64'].starts_with('unavailable')) {"},
		Edit{label: 'fresh build scratch', old: "p := raw + '/bootstrap-01'", new: "p := raw + '/observer-host-01/build-private-01'"},
	]
}

fn controller_pins() ! {
	pin(host + '/actual-outer-status.json', '734ec94963beca9f3f49176c541e6489afd5658826cf79acc7d88853264f0e8b', 16384)!
	pin(host + '/inputs-before.json', input_map_sha, 4 * 1024 * 1024)!
	for phase in ['preparer', 'reproduce', 'controller', 'host-controls', 'closure-controls'] {
		pin(host + '/' + phase + '/inputs-after.json', input_map_sha, 4 * 1024 * 1024)!
	}
	pin(controller, controller_sha, 8 * 1024 * 1024)!
	pin(controller_source, controller_source_sha, 1024 * 1024)!
	pin(host + '/host-controls-output/host-controls.json', 'bad7355a21128d32e618430dcf4b9797565fc5bf6f53f49fc2232ea5504182e7', 65536)!
	pin(host + '/closure-controls-output/closure.json', 'f5907cc473bd7678be69144a0f5e2978766236d019585127e0868232a0030c68', 4 * 1024 * 1024)!
}

fn owner_module_pins() ! {
	for relative, expected in {
		'abi.h': 'a816e3d27024ede2dfba4e04eeb473d81ee0f47f1381ada687edce51a6e32d23'
		'core.v': '5b5ba4be07027e508ff881602a9a9f100491f0c65164607b39ee58e987117212'
		'pty.v': '733cd8ebed8e1f358ba4616d9b97d0c0bcb399e1a809aba1ce523b534497fa18'
		'reader.v': '20c3b6a17589d65e59d6d8a31ce6af4276333757a1db78458d368f84fed38129'
		'logged.v': 'c09ebbda5f9f76fd2cfc9a17c8ff66442efa16a2210a5bfb83c354b6fd9fcafa'
		'duplex.v': 'c6b57a59aa570f208b7b8f17d775d6623ca8edf8a525f485039d101c27d97dc2'
		'pty_test.v': 'fde3a446ff0d242566f015d464210708d5ed7a66455dd63a9cc654571c75ccc3'
	} {
		pin(repository + '/build/peer-login-runtime-guarded-worktree/tools/sourcecommand/' + relative, expected, 1024 * 1024)!
		pin(stage + '/source-03/tools/sourcecommand/' + relative, expected, 1024 * 1024)!
	}
}

fn run() ! {
	require(os.args.len == 1, 'fixed observer source preparer takes no operands')!
	require(os.read_file(@FILE)! == $embed_file('prepare-current-integration-observer.v').to_string(),
		'preparer source differs from compiled source')!
	require(os.real_path(stage) == stage && os.lstat(stage)!.mode & 0o170000 == 0o040000,
		'canonical fresh stage required')!
	require(!present(output), 'fresh derived source directory required')!
	base := pin(source, source_sha, 1024 * 1024)!
	pin(qualified + '/native-control-actions-01/closed-controls-summary.json',
		'c837d56667d7d1997905ab888620ea88e9346889b7cefa84d463afcbd79c9fef', 65536)!
	controller_pins()!
	owner_module_pins()!
	changes := edits()
	require(changes.len == 14, 'exactly fourteen contextual fixed-data substitutions required')!
	mut body := base
	for edit in changes { body = change(body, edit)! }
	mut inverse := body
	for i := changes.len - 1; i >= 0; i-- { inverse = inverse.replace(changes[i].new, changes[i].old) }
	require(inverse == base, 'complete source inverse differs')!
	digest := sum(body)
	os.mkdir(output)!
	os.mkdir(output + '/source')!
	destination := output + '/source/fresh-frame-observer.v'
	os.write_file(destination, body)!
	pin(destination, digest, 1024 * 1024)!
	pin(source, source_sha, 1024 * 1024)!
	controller_pins()!
	owner_module_pins()!
	os.write_file(output + '/source-derivation.json', json2.encode({'format': '1',
		'qualified_base': source, 'qualified_base_sha256': source_sha,
		'controller_binary_sha256': controller_sha, 'controller_source_sha256': controller_source_sha,
		'derived_source': destination, 'derived_source_sha256': digest,
		'exact_substitutions': '14', 'logical_data_changes': '13', 'substitutions': json2.encode(changes),
		'complete_inverse': 'equal to qualified original', 'expected_controls': '67',
		'build_argv': json2.encode([controller, state + '/build-01']),
		'architectures': 'x86_64,aarch64', 'build_wall_seconds': '1100',
		'scope': 'Fixed data only. Qualified67 owner, timing/log protections, limits, original auditor and control count unchanged. Fresh strict bootstrap, full diff review and exact67 controls required before use; no build, audit or VM performed.'}) + '\n')!
	println('CURRENT INTEGRATION OBSERVER SOURCE PASS ' + digest)
}

fn main() { run() or { eprintln(err); exit(1) } }
