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
	assert os.args.len == 2
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..')); state := os.abs_path(os.args[1])
	assert !state.starts_with(repo + '/') && !os.exists(state + '/kernel-build'); os.mkdir_all(state)!
	prior := '/Users/alex/.local/state/vinix/omarchy-m1-context-retire-20261117/bundle'
	assert hash(repo + '/tests/agx-context-retire/qualify.v')! == hash(prior + '/source/tests/agx-context-retire/qualify.v')!
	work := state + '/kernel-build'
	revision := run('git', ['rev-parse', 'HEAD'], repo, state + '/baseline.txt')!.trim_space()
	assert revision == '5e5798e4aaa30917e928b87b585161b64c8610d2'
	_ = run('git', ['worktree', 'add', '--detach', '--no-checkout', work, revision], repo, state + '/worktree-create.log')!
	_ = run('git', ['sparse-checkout', 'set', '--cone', 'kernel', 'build-support', 'tests/kernel-allocs', 'tests/native-generators', 'tests/linuxkpi/hosttest', 'tools/sourcecommand'], work, state + '/worktree-sparse.log')!
	_ = run('git', ['reset', '--hard', 'HEAD'], work, state + '/worktree-checkout.log')!
	for dependency in ['freestnd-c-hdrs', 'cc-runtime', 'c/flanterm', 'c/nanoprintf.h', 'c/lwip', 'c/uacpi', 'uacpi-repository', 'lwip-repository'] {
		if !os.exists(work + '/kernel/' + dependency) { os.symlink(repo + '/kernel/' + dependency, work + '/kernel/' + dependency)! }
	}
	os.mkdir_all(state + '/baseline')!; os.mkdir_all(state + '/tmp')!
	for path in ['kernel/gpu/agx/gpu/gpu.v', 'kernel/gpu/agx/gpu/g13.v', 'kernel/gpu/agx/gpu/g13_context.v'] {
		os.cp(repo + '/' + path, state + '/kernel-build/' + path)!
		mut show := os.new_process('git'); show.set_work_folder(repo); show.set_args(['show', 'HEAD:' + path]); show.set_redirect_stdio_merged()
		show.run(); data := show.stdout_slurp(); show.wait(); assert show.code == 0; show.close()
		os.write_file(state + '/baseline/' + os.file_name(path), data)!
	}
	assert hash(repo + '/tests/agx-worker/native.v')! == hash(prior + '/source/tests/agx-worker/native.v')!
	println('Prepared deferred-context overlays in an isolated baseline worktree; native runner source matches preceding evidence.')
}
