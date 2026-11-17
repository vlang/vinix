// SPDX-License-Identifier: GPL-2.0-or-later
import os
import crypto.sha256

fn run(program string, args []string, folder string, log string, expected int) !string {
	mut p := os.new_process(program); p.set_args(args); p.set_work_folder(folder)
	p.set_redirect_stdio_merged(); p.run()
	out := p.stdout_slurp(); p.wait()
	os.write_file(log, out)!
	assert p.code == expected, log + ': ' + out
	p.close(); return out
}
fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn main() {
	assert os.args.len == 3, 'usage: qualify --prepare|--aarch64|--x86_64|--resume-x86_64|--allocations EXTERNAL_STATE'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	state := os.abs_path(os.args[2]); assert !state.starts_with(repo + '/') && state != repo
	os.mkdir_all(state)!
	work := state + '/kernel-build'
	if os.args[1] == '--baseline-x86' {
		control := state + '/kernel-baseline'
		assert !os.exists(control)
		revision := os.read_file(state + '/baseline.txt')!.trim_space()
		_ = run('git', ['worktree', 'add', '--detach', '--no-checkout', control, revision], repo, state + '/baseline-create.log', 0)!
		_ = run('git', ['sparse-checkout', 'set', '--cone', 'kernel', 'build-support'], control, state + '/baseline-sparse.log', 0)!
		_ = run('git', ['reset', '--hard', 'HEAD'], control, state + '/baseline-checkout.log', 0)!
		for dependency in ['freestnd-c-hdrs', 'cc-runtime', 'c/flanterm', 'c/nanoprintf.h', 'c/lwip', 'c/uacpi', 'uacpi-repository', 'lwip-repository'] {
			if !os.exists(control + '/kernel/' + dependency) { os.symlink(repo + '/kernel/' + dependency, control + '/kernel/' + dependency)! }
		}
		_ = run('make', ['obj/blob.c.o', 'ARCH=x86_64', 'LD_X86_64=ld.lld', 'KERNEL_LINK_SEED=0'], control + '/kernel', state + '/baseline-build-x86_64.log', 0)!
		os.cp(control + '/kernel/obj/blob.c', state + '/baseline-blob-x86_64.c')!
		assert run('git', ['diff', '--name-only'], control, state + '/baseline-clean.log', 0)!.trim_space() == ''
		println('Fresh baseline x86 C generated with the current compiler.'); return
	}
	if os.args[1] == '--prepare' {
		assert !os.exists(work)
		revision := run('git', ['rev-parse', 'HEAD'], repo, state + '/baseline.txt', 0)!.trim_space()
		assert revision.len == 40
		_ = run('git', ['worktree', 'add', '--detach', '--no-checkout', work, revision], repo, state + '/worktree-create.log', 0)!
		_ = run('git', ['sparse-checkout', 'set', '--cone', 'kernel', 'build-support', 'tests/kernel-allocs', 'tests/native-generators', 'tests/linuxkpi/hosttest', 'tools/sourcecommand'], work, state + '/worktree-sparse.log', 0)!
		_ = run('git', ['reset', '--hard', 'HEAD'], work, state + '/worktree-checkout.log', 0)!
		for dependency in ['freestnd-c-hdrs', 'cc-runtime', 'c/flanterm', 'c/nanoprintf.h', 'c/lwip', 'c/uacpi', 'uacpi-repository', 'lwip-repository'] {
			if !os.exists(work + '/kernel/' + dependency) { os.symlink(repo + '/kernel/' + dependency, work + '/kernel/' + dependency)! }
		}
		for path in ['kernel/gpu/agx/fw/channels.v', 'kernel/gpu/agx/gpu/gpu.v', 'kernel/gpu/agx/gpu/g13_garbage.v'] {
			os.cp(repo + '/' + path, work + '/' + path)!
		}
		println('Prepared isolated baseline worktree with three GPU source overlays.'); return
	}
	assert os.is_dir(work)
	os.setenv('VTMP', state + '/tmp', true); os.mkdir_all(state + '/tmp')!
	if os.args[1] == '--allocations' {
		os.setenv('VINIX_KERNEL_ALLOCS_ROOT', work, true)
		_ = run(repo + '/tests/kernel-allocs/run.sh', [], repo, state + '/kernel-allocs.log', 1)!
		println('Allocation report retained with existing allowance failure.'); return
	}
	resume := os.args[1].starts_with('--resume-')
	arch := if resume { os.args[1].all_after('--resume-') } else { os.args[1].trim_left('-') }
	assert arch in ['aarch64', 'x86_64']
	assert !os.exists(state + '/vinix-' + arch)
	if !resume { _ = run('make', ['clean', 'ARCH=' + arch], work + '/kernel', state + '/clean-' + arch + '.log', 0)! }
	_ = run('make', ['-j6', 'ARCH=' + arch, 'LD_X86_64=ld.lld', 'KERNEL_LINK_SEED=0'], work + '/kernel', state + '/build-' + arch + '.log', 0)!
	for path in os.walk_ext(repo + '/kernel/gpu/agx', '.v') {
		rel := path[repo.len + 1..]
		assert digest(path)! == digest(work + '/' + rel)!, rel
	}
	for file in ['bin/vinix', 'obj/blob.c'] {
		name := if file == 'bin/vinix' { 'vinix-' + arch } else { 'blob-' + arch + '.c' }
		os.cp(work + '/kernel/' + file, state + '/' + name)!
		println(name + ' sha256 ' + digest(state + '/' + name)!)
	}
	mut inventory := []string{}
	for path in os.walk_ext(work + '/kernel', '.v') {
		if path.contains('/obj/') || path.contains('/.cache/') { continue }
		inventory << path[(work + '/').len..] + ' sha256 ' + digest(path)!
	}
	inventory.sort(); os.write_file(state + '/inputs-' + arch + '.txt', inventory.join('\n') + '\n')!
}
