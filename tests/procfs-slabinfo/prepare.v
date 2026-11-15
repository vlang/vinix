// SPDX-License-Identifier: GPL-2.0-or-later
// Prepare an isolated kernel checkout; generated build outputs stay external.
module main

import crypto.sha256
import json2
import os

fn execute(args []string) !string {
	result := os.exec(args)
	if result.exit_code != 0 { return error(result.output) }
	return result.output
}

fn run() ! {
	if os.args.len != 5 {
		return error('usage: prepare ROOT REVISION FRESH-WORKTREE baseline|fixed')
	}
	root, revision, worktree, mode := os.real_path(os.args[1]), os.args[2], os.abs_path(os.args[3]), os.args[4]
	if mode !in ['baseline', 'fixed'] || os.exists(worktree) || os.is_link(worktree) {
		return error('fresh worktree and explicit mode required')
	}
	resolved := execute(['git', '-C', root, 'rev-parse', revision + '^{commit}'])!.trim_space()
	execute(['git', '-C', root, 'worktree', 'add', '--detach', '--no-checkout', worktree, resolved])!
	execute(['git', '-C', worktree, 'sparse-checkout', 'set', 'kernel', 'build-support',
		'tests/native-generators', 'tests/kernel-allocs', 'tests/linuxkpi/hosttest', 'tools/sourcecommand'])!
	execute(['git', '-C', worktree, 'checkout', '--detach', resolved])!
	for relative in ['freestnd-c-hdrs', 'cc-runtime', 'c/flanterm', 'c/lwip', 'c/uacpi', 'c/nanoprintf.h'] {
		path := worktree + '/kernel/' + relative
		if os.exists(path) || os.is_link(path) { return error('unexpected existing dependency: ' + path) }
		os.symlink(root + '/kernel/' + relative, path)!
	}
	mut overlay := map[string]string{}
	if mode == 'fixed' {
		for relative in ['kernel/fs/procfs.v', 'kernel/memory/heap_snapshot.v', 'kernel/slabreport/core.v'] {
			os.mkdir_all(os.dir(worktree + '/' + relative))!
			os.cp(root + '/' + relative, worktree + '/' + relative)!
			overlay[relative] = sha256.sum(os.read_bytes(root + '/' + relative)!).hex()
		}
		legacy := worktree + '/kernel/memory/heap_snapshot_d_linuxkpi.v'
		if os.exists(legacy) { os.rm(legacy)! }
	}
	os.write_file(worktree + '/slabinfo-source.json', json2.encode({
		'revision': json2.Any(resolved), 'mode': mode,
		'overlay': json2.decode[json2.Any](json2.encode(overlay))!
	}, prettify: true) + '\n')!
	println('Prepared isolated ' + mode + ' kernel ' + resolved)
}

fn main() { run() or { eprintln(err); exit(1) } }
