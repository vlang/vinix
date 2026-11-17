// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

const revision = 'bc40b06d096fc9626f25f5c8cbd519dfbc8cdf97'
const overlays = ['kernel/gpu/agx/workqueue/workqueue.v', 'kernel/gpu/agx/file/file.v', 'kernel/gpu/agx/fake/driver.v']
fn run(args []string, folder string, log string) !string {
	mut p := os.new_process('git'); p.set_args(args); p.set_work_folder(folder); p.set_redirect_stdio_merged()
	p.run(); data := p.stdout_slurp(); p.wait(); code := p.code; p.close(); os.write_file(log, data)!
	assert code == 0, log; return data
}
fn main() {
	assert os.args.len in [2, 3]
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..')); state := os.abs_path(os.args.last())
	assert !state.starts_with(repo + '/') && os.real_path(state) == state
	work := state + '/kernel-build'
	if os.args.len == 3 {
		assert os.args[1] == '--refresh'
		for file in ['vinix-aarch64', 'blob-aarch64.c', 'inputs-aarch64.txt', 'build-aarch64.log', 'clean-aarch64.log', 'arm.log'] {
			assert !os.exists(state + '/pre-tag-' + file)
			os.mv(state + '/' + file, state + '/pre-tag-' + file)!
		}
	}
	else {
		assert !os.exists(work)
		assert run(['rev-parse', 'HEAD'], repo, state + '/baseline.txt')!.trim_space() == revision
		_ = run(['worktree', 'add', '--detach', '--no-checkout', work, revision], repo, state + '/worktree-create.log')!
		_ = run(['sparse-checkout', 'set', '--cone', 'kernel', 'build-support', 'tests/kernel-allocs', 'tests/native-generators', 'tests/linuxkpi/hosttest', 'tools/sourcecommand'], work, state + '/worktree-sparse.log')!
		_ = run(['reset', '--hard', 'HEAD'], work, state + '/worktree-checkout.log')!
		for dependency in ['freestnd-c-hdrs', 'cc-runtime', 'c/flanterm', 'c/nanoprintf.h', 'c/lwip', 'c/uacpi', 'uacpi-repository', 'lwip-repository'] {
			if !os.exists(work + '/kernel/' + dependency) { os.symlink(repo + '/kernel/' + dependency, work + '/kernel/' + dependency)! }
		}
		os.mkdir_all(state + '/baseline')!
		for path in overlays { _ = run(['show', revision + ':' + path], repo, state + '/baseline/' + os.file_name(path))! }
		prior := '/Users/alex/.local/state/vinix/omarchy-m1-queue-records-20261117/bundle/source/tests/agx-worker/native.v'
		assert sha256.sum(os.read_bytes(repo + '/tests/agx-worker/native.v')!) == sha256.sum(os.read_bytes(prior)!)
	}
	for path in overlays { os.cp(repo + '/' + path, work + '/' + path)! }
	println('Prepared logical queue lifetime overlays in an isolated baseline worktree.')
}
