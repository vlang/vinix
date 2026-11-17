// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn main() {
	assert os.args.len == 3 && os.args[1] in ['--prepare', '--refresh']
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..')); state := os.abs_path(os.args[2])
	assert !state.starts_with(repo + '/') && os.real_path(state) == state
	if os.args[1] == '--prepare' {
		prior := '/Users/alex/.local/state/vinix/omarchy-m1-teardown-gc-20261117/bundle'
		assert hash(repo + '/tests/agx-teardown-gc/qualify.v')! == hash(prior + '/source/tests/agx-teardown-gc/qualify.v')!
		os.cp(prior + '/prepare', state + '/context-base-prepare')!
		mut p := os.new_process(state + '/context-base-prepare'); p.set_args([state]); p.run(); p.wait(); assert p.code == 0; p.close()
	} else {
		// Preserve the completed diagnostic build made before the helper moved
		// to its own file. Refresh is only used for this task's private worktree.
		assert os.read_file(state + '/baseline.txt')!.trim_space() == '144702f4e8360b28df56d0c4491b7bb3d8de5b7f'
		for file in ['vinix-aarch64', 'blob-aarch64.c', 'inputs-aarch64.txt', 'build-aarch64.log', 'clean-aarch64.log', 'arm.log'] {
			assert !os.exists(state + '/pre-split-' + file); os.mv(state + '/' + file, state + '/pre-split-' + file)!
		}
	}
	for path in ['kernel/gpu/agx/gpu/g13_context.v', 'kernel/gpu/agx/gpu/g13_garbage.v', 'kernel/gpu/agx/gpu/g13.v', 'kernel/gpu/agx/fw/channels.v'] {
		os.cp(repo + '/' + path, state + '/kernel-build/' + path)!
	}
	println('Prepared final context-retirement source layout in the private worktree.')
}
