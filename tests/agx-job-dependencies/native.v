// SPDX-License-Identifier: GPL-2.0-or-later
import crypto.sha256
import os

const baseline = '4755d6b55c6459658fe48fc25b7fbcc0ebf71abb'
const overlays = ['kernel/gpu/agx/file/file.v', 'kernel/gpu/agx/submission/dependencies.v']

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn run(program string, args []string, folder string, log string, expected int) ! {
	mut p := os.new_process(program)
	p.set_args(args); p.set_work_folder(folder); p.set_redirect_stdio_merged(); p.run()
	out := p.stdout_slurp(); p.wait()
	os.write_file(log, out)!
	assert p.code == expected, '${log}: exit ${p.code}, expected ${expected}'
	p.close()
}

fn main() {
	assert os.args.len == 3, 'usage: native prepare|aarch64|x86_64|allocations|contracts EXTERNAL_STATE'
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	state := os.abs_path(os.args[2])
	assert os.real_path(state) == state && !state.starts_with(repo + '/')
	work := state + '/kernel-build'
	mode := os.args[1]
	if mode == 'prepare' {
		assert !os.exists(work)
		run('git', ['worktree', 'add', '--detach', '--no-checkout', work, baseline], repo, state + '/worktree.log', 0)!
		run('git', ['sparse-checkout', 'set', '--cone', 'kernel', 'build-support', 'tests/kernel-allocs',
			'tests/native-generators', 'tests/linuxkpi/hosttest', 'tools/sourcecommand'], work, state + '/sparse.log', 0)!
		run('git', ['reset', '--hard', 'HEAD'], work, state + '/checkout.log', 0)!
		for path in ['freestnd-c-hdrs', 'cc-runtime', 'c/flanterm', 'c/nanoprintf.h', 'c/lwip',
			'c/uacpi', 'uacpi-repository', 'lwip-repository'] {
			if !os.exists(work + '/kernel/' + path) { os.symlink(repo + '/kernel/' + path, work + '/kernel/' + path)! }
		}
		for path in overlays { os.cp(repo + '/' + path, work + '/' + path)! }
		os.mkdir_all(state + '/tmp')!
		os.write_file(state + '/baseline.txt', baseline + '\n')!
		println('Isolated native baseline plus two owned job-dependency overlays; concurrent event changes excluded.')
		return
	}
	for path in overlays { assert digest(repo + '/' + path)! == digest(work + '/' + path)! }
	os.setenv('VTMP', state + '/tmp', true)
	os.setenv('VJOBS', '2', true)
	if mode == 'allocations' {
		os.setenv('VINIX_KERNEL_ALLOCS_ROOT', work, true)
		run(repo + '/tests/kernel-allocs/run.sh', [], repo, state + '/kernel-allocs.log', 1)!
		println('Allocation allowance diagnostics retained (existing failures expected).')
		return
	}
	if mode == 'contracts' {
		root := state + '/contracts-source'
		assert !os.exists(root)
		os.mkdir_all(root)!
		run('git', ['archive', '-o', state + '/contracts.tar', baseline, 'kernel', 'tools/agx-re'], repo, state + '/contracts-archive.log', 0)!
		run('tar', ['-xf', state + '/contracts.tar', '-C', root], repo, state + '/contracts-extract.log', 0)!
		for path in overlays { os.cp(repo + '/' + path, root + '/' + path)! }
		for path in ['job_dependency_test.v'] { os.cp(repo + '/tools/agx-re/g13contract/' + path, root + '/tools/agx-re/g13contract/' + path)! }

		run(os.getenv_opt('V') or { 'v' }, ['-path', root + '/tools/agx-re|@vlib|@vmodules',
			'test', root + '/tools/agx-re/g13contract'], repo, state + '/contracts.log', 0)!
		println('Isolated source contracts pass.')
		return
	}
	assert mode in ['aarch64', 'x86_64'] && !os.exists(state + '/vinix-' + mode)
	run('make', ['clean', 'ARCH=' + mode], work + '/kernel', state + '/clean-' + mode + '.log', 0)!
	run('make', ['-j2', 'ARCH=' + mode, if mode == 'aarch64' { 'LIMINE_MP=1' } else { 'LIMINE_MP=0' },
		'LD_X86_64=ld.lld', 'KERNEL_LINK_SEED=0'], work + '/kernel', state + '/build-' + mode + '.log', 0)!
	for path in overlays { assert digest(repo + '/' + path)! == digest(work + '/' + path)! }
	for name, path in {'vinix-': 'bin/vinix', 'blob-': 'obj/blob.c'} {
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
