// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn run(program string, args []string, folder string, log string) !string {
	mut p := os.new_process(program); p.set_args(args); p.set_work_folder(folder); p.set_redirect_stdio_merged()
	p.run(); data := p.stdout_slurp(); p.wait(); code := p.code; p.close(); os.write_file(log, data)!
	assert code == 0, log; return data
}
fn main() {
	assert os.args.len in [2, 3]
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..')); state := os.abs_path(os.args.last())
	assert !state.starts_with(repo + '/') && os.real_path(state) == state
	work := state + '/kernel-build'
	if os.args.len == 3 {
		assert os.args[1] == '--refresh' && os.read_file(state + '/baseline.txt')!.trim_space() == '8ec593e64572c29ad840e4b6295f480e3a7b4ea6'
		for file in ['vinix-aarch64', 'blob-aarch64.c', 'inputs-aarch64.txt', 'build-aarch64.log', 'clean-aarch64.log', 'arm.log'] {
			assert !os.exists(state + '/pre-tag-' + file); os.mv(state + '/' + file, state + '/pre-tag-' + file)!
		}
	} else {
		assert !os.exists(work)
		prior := '/Users/alex/.local/state/vinix/omarchy-m1-queue-unwind-20261117/bundle'
		assert hash(repo + '/tests/agx-queue-unwind/qualify.v')! == hash(prior + '/source/tests/agx-queue-unwind/qualify.v')!
		revision := run('git', ['rev-parse', 'HEAD'], repo, state + '/baseline.txt')!.trim_space()
		assert revision == '8ec593e64572c29ad840e4b6295f480e3a7b4ea6'
		_ = run('git', ['worktree', 'add', '--detach', '--no-checkout', work, revision], repo, state + '/worktree-create.log')!
		_ = run('git', ['sparse-checkout', 'set', '--cone', 'kernel', 'build-support', 'tests/kernel-allocs', 'tests/native-generators', 'tests/linuxkpi/hosttest', 'tools/sourcecommand'], work, state + '/worktree-sparse.log')!
		_ = run('git', ['reset', '--hard', 'HEAD'], work, state + '/worktree-checkout.log')!
		for dependency in ['freestnd-c-hdrs', 'cc-runtime', 'c/flanterm', 'c/nanoprintf.h', 'c/lwip', 'c/uacpi', 'uacpi-repository', 'lwip-repository'] {
			if !os.exists(work + '/kernel/' + dependency) { os.symlink(repo + '/kernel/' + dependency, work + '/kernel/' + dependency)! }
		}
		os.mkdir_all(state + '/baseline')!; os.mkdir_all(state + '/tmp')!
		for path in ['kernel/gpu/agx/gpu/g13.v', 'kernel/gpu/agx/file/file.v'] {
			_ = run('git', ['show', revision + ':' + path], repo, state + '/baseline/' + os.file_name(path))!
		}
		assert hash(repo + '/tests/agx-worker/native.v')! == hash(prior + '/source/tests/agx-worker/native.v')!
	}
	for path in ['kernel/gpu/agx/gpu/g13.v', 'kernel/gpu/agx/file/file.v'] { os.cp(repo + '/' + path, work + '/' + path)! }
	println('Prepared final-owner queue-record overlays in an isolated baseline worktree.')
}
