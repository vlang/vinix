// SPDX-License-Identifier: GPL-2.0-or-later
import crypto.sha256
import os

const baseline = '612f3032a27ab253800be6a1f8464d898b8beabd'
const overlays = ['kernel/gpu/agx/driver/driver.v', 'kernel/gpu/agx/file/file.v',
	'kernel/gpu/agx/file/modern.v', 'kernel/gpu/agx/file/modern_submit.v',
	'kernel/gpu/agx/params/modern.v', 'kernel/gpu/agx/submission/modern.v',
	'kernel/gpu/agx/workqueue/workqueue.v']

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn command(program string, args []string, folder string, log string, expected int) ! {
	mut p := os.new_process(program)
	p.set_args(args)
	p.set_work_folder(folder)
	p.set_redirect_stdio_merged()
	p.run()
	out := p.stdout_slurp()
	p.wait()
	code := p.code
	p.close()
	os.write_file(log, out)!
	assert code == expected, '${log}: exit ${code}, expected ${expected}'
}

fn main() {
	assert os.args.len == 3, 'usage: native prepare|refresh|checkpoint|aarch64|x86_64|allocations STATE'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	state := os.abs_path(os.args[2])
	assert os.real_path(state) == state && !state.starts_with(repo + '/')
	work := state + '/kernel-build'
	mode := os.args[1]
	if mode == 'checkpoint' {
		mut diagnostic := state + '/before-stack-fix'
		if os.exists(diagnostic) { diagnostic = state + '/before-value-snapshot' }
		assert !os.exists(diagnostic)
		os.mkdir_all(diagnostic)!
		for name in ['vinix-aarch64', 'vinix-x86_64', 'blob-aarch64.c', 'blob-x86_64.c',
			'build-aarch64.log', 'build-x86_64.log', 'clean-aarch64.log', 'clean-x86_64.log',
			'inputs-aarch64.txt', 'inputs-x86_64.txt', 'arm.log', 'x86.log', 'kernel-allocs.log',
			'allocations.log'] {
			if os.exists(state + '/' + name) { os.mv(state + '/' + name, diagnostic + '/' + name)! }
		}
		os.cp(work + '/kernel/gpu/agx/submission/modern.v', diagnostic + '/modern-sync.v')!
		println('Preserved first native builds and diagnostics before removing implicit sync boxing.')
		return
	}
	if mode in ['prepare', 'refresh'] {
		if mode == 'prepare' {
			assert !os.exists(work)
			command('git', ['worktree', 'add', '--detach', '--no-checkout', work, baseline], repo, state + '/worktree.log', 0)!
			command('git', ['sparse-checkout', 'set', '--cone', 'kernel', 'build-support',
				'tests/kernel-allocs', 'tests/native-generators', 'tests/linuxkpi/hosttest',
				'tools/sourcecommand'], work, state + '/sparse.log', 0)!
			command('git', ['reset', '--hard', 'HEAD'], work, state + '/checkout.log', 0)!
			for dep in ['freestnd-c-hdrs', 'cc-runtime', 'c/flanterm', 'c/nanoprintf.h', 'c/lwip',
				'c/uacpi', 'uacpi-repository', 'lwip-repository'] {
				if !os.exists(work + '/kernel/' + dep) {
					os.symlink(repo + '/kernel/' + dep, work + '/kernel/' + dep)!
				}
			}
			os.mkdir_all(state + '/tmp')!
		}
		assert !os.exists(state + '/vinix-aarch64') && !os.exists(state + '/vinix-x86_64'), 'never replace sources after a retained successful build'
		for path in overlays { os.cp(repo + '/' + path, work + '/' + path)! }
		os.write_file(state + '/baseline.txt', baseline + '\n')!
		println('Prepared isolated ABI overlays; concurrent event edits excluded.')
		return
	}
	os.setenv('VTMP', state + '/tmp', true)
	os.setenv('VJOBS', '2', true)
	if mode == 'allocations' {
		os.setenv('VINIX_KERNEL_ALLOCS_ROOT', work, true)
		command(repo + '/tests/kernel-allocs/run.sh', [], repo, state + '/kernel-allocs.log', 1)!
		println('Allocation diagnostics retained; existing allowance check still fails.')
		return
	}
	assert mode in ['aarch64', 'x86_64'] && !os.exists(state + '/vinix-' + mode)
	for path in overlays {
		assert digest(repo + '/' + path)! == digest(work + '/' + path)!, path
	}
	command('make', ['clean', 'ARCH=' + mode], work + '/kernel', state + '/clean-' + mode + '.log', 0)!
	mp := if mode == 'aarch64' { 'LIMINE_MP=1' } else { 'LIMINE_MP=0' }
	command('make', ['-j2', 'ARCH=' + mode, mp, 'LD_X86_64=ld.lld', 'KERNEL_LINK_SEED=0'],
		work + '/kernel', state + '/build-' + mode + '.log', 0)!
	for path in overlays {
		assert digest(repo + '/' + path)! == digest(work + '/' + path)!, path
	}
	for name, path in {
		'vinix-': 'bin/vinix'
		'blob-':  'obj/blob.c'
	} {
		target := state + '/' + name + mode + if name == 'blob-' { '.c' } else { '' }
		os.cp(work + '/kernel/' + path, target)!
		println(os.file_name(target) + ' sha256 ' + digest(target)!)
	}
	mut inputs := []string{}
	for path in os.walk_ext(work + '/kernel', '.v') {
		if path.contains('/obj/') || path.contains('/.cache/') { continue }
		inputs << path[(work + '/').len..] + ' sha256 ' + digest(path)!
	}
	inputs.sort()
	os.write_file(state + '/inputs-' + mode + '.txt', inputs.join('\n') + '\n')!
}
