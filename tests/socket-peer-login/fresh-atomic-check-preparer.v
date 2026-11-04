// Fixed independent-check profile; the qualified observer source stays untouched.
module main

import crypto.sha256
import json2
import os

const source = '/Users/alex/code/vinix/build/package-audio-peer-login-guarded-worktree/tests/socket-peer-login/fresh-atomic-observer.v'
const source_sha = 'a473233234928cc68a5a6d87e432c2dc34ff5ecb6d5037dfe9bd1cc4e181a006'
const seal = '/Users/alex/Library/Caches/vinix-codex/section14/matched-peer-frame-atomic-fresh-20261026-seal-01'
const output = seal + '/native-bootstrap-06'

fn require(ok bool, message string) ! { if !ok { return error(message) } }
fn present(path string) bool { return os.exists(path) || os.is_link(path) }

fn ordinary_directory(path string) ! {
	require(os.real_path(path) == path && os.lstat(path)!.mode & 0o170000 == 0o040000,
		'canonical ordinary directory required: ' + path)!
}

fn pinned_read(path string, expected string) !string {
	require(os.real_path(path) == path, 'canonical source path required')!
	before := os.lstat(path)!
	require(before.mode & 0o170000 == 0o100000 && before.size <= 1024 * 1024,
		'bounded ordinary source required')!
	text := os.read_file(path)!
	after := os.lstat(path)!
	require(before.dev == after.dev && before.inode == after.inode && before.mode == after.mode
		&& before.uid == after.uid && before.gid == after.gid && before.size == after.size
		&& before.mtime == after.mtime && before.ctime == after.ctime && u64(text.len) == after.size,
		'source changed during read')!
	require(sha256.sum(text.bytes()).hex() == expected, 'source hash differs')!
	return text
}

fn run() ! {
	require(os.args.len == 1, 'fixed independent-check preparation takes no operands')!
	ordinary_directory(seal)!
	require(!present(output), 'fresh fixed independent-check output required')!
	base := pinned_read(source, source_sha)!
	old_check := "'/native-check-01'"
	new_check := "'/native-check-02'"
	old_controls := "'/native-controls-02'"
	new_controls := "'/native-controls-04'"
	old_quiet := 'mut quiet := Watch{state: quiet_state, wall: 600 * u64(time.millisecond), audit: second}'
	new_quiet := 'mut quiet := Watch{state: quiet_state, wall: 900 * u64(time.millisecond), audit: second, started: time.sys_mono_now()}'
	require(base.count(old_check) == 6 && base.count(old_controls) == 1
		&& base.count(new_check) == 0 && base.count(new_controls) == 0
		&& base.count(old_quiet) == 1 && base.count(new_quiet) == 0,
		'exact quoted replacement counts differ')!
	derived := base.replace(old_check, new_check).replace(old_controls, new_controls).replace(old_quiet, new_quiet)
	require(derived.count(old_check) == 0 && derived.count(old_controls) == 0
		&& derived.count(new_check) == 6 && derived.count(new_controls) == 1
		&& derived.count(old_quiet) == 0 && derived.count(new_quiet) == 1
		&& derived.len == base.len + new_quiet.len - old_quiet.len
		&& derived.replace(new_check, old_check).replace(new_controls, old_controls).replace(new_quiet, old_quiet) == base,
		'derived profile differs beyond seven fixed literals and one control initializer')!
	derived_sha := sha256.sum(derived.bytes()).hex()
	os.mkdir(output)!
	os.mkdir(output + '/source')!
	destination := output + '/source/fresh-atomic-observer.v'
	os.write_file(destination, derived)!
	pinned_read(destination, derived_sha)!
	pinned_read(source, source_sha)!
	os.write_file(output + '/source-derivation.json', json2.encode({'format': '1',
		'base_source': source, 'base_source_sha256': source_sha,
		'derived_source': destination, 'derived_source_sha256': derived_sha,
		'check_replacements': '6', 'controls_replacements': '1', 'quiet_initializer_replacements': '1',
		'check_state': seal + '/native-check-02', 'controls_state': seal + '/native-controls-04',
		'quiet_scope': 'Synthetic900ms wall starts before admission, strictly before first1s periodic trigger. Pre-spawn admission refusal is not a completed quiet-child control.',
		'scope': 'Only seven state literals and one quiet-control initializer differ. Production CLI/core/pins/budgets/errors unchanged; fresh strict bootstrap and61 controls required before independent original check.'}) + '\n')!
	println('FRESH ATOMIC INDEPENDENT CHECK SOURCE PASS ' + derived_sha)
}

fn main() { run() or { eprintln(err); exit(1) } }
