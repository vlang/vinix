import os

const root = '/Users/alex/code/vinix'
const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022'
const compiler = '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/v'

fn run(program string, args []string, folder string, log string) ! {
	mut p := os.new_process(program)
	p.set_args(args)
	p.set_work_folder(folder)
	p.set_redirect_stdio_merged()
	p.run()
	output := p.stdout_slurp()
	p.wait()
	code := p.code
	p.close()
	os.write_file(log, output)!
	os.write_file(log + '.status', '${code}\n')!
	if code != 0 { return error('command failed: ' + log) }
}

fn main() {
	phase := os.args[1]
	if phase in ['allocs', 'allocs-base'] {
		os.setenv('V', compiler, true)
		os.setenv('VINIX_KERNEL_ALLOCS_ROOT', if phase == 'allocs' { area + '/kernel-arm' } else { '/Users/alex/.cache/vinix-linux-compat/procns-20261016/audit-base' }, true)
		run(root + '/tests/kernel-allocs/run.sh', [], root, area + '/' + phase + '.log') or { eprintln(err); exit(1) }
		return
	}
	if phase == 'prepare' {
		for suffix in ['arm', 'x86'] {
			tree := area + '/kernel-' + suffix
			assert !os.exists(tree)
			run('git', ['worktree', 'add', '--detach', '--no-checkout', tree, 'cf6426cf16657a6db8d5be8062ef82f170c6b48b'], root, area + '/worktree-' + suffix + '.log')!
			run('git', ['sparse-checkout', 'set', 'kernel', 'build-support', 'tests/linuxkpi', 'tests/native-generators', 'tests/kernel-allocs', 'tests/scheduler-qos', 'tools/sourcecommand', 'tools/linux-compat', 'docs'], tree, area + '/sparse-' + suffix + '.log')!
			run('git', ['checkout', '--detach', 'cf6426cf16657a6db8d5be8062ef82f170c6b48b'], tree, area + '/checkout-' + suffix + '.log')!
			for name in ['freestnd-c-hdrs', 'cc-runtime', 'cc-runtime-aarch64', 'cc-runtime-x86_64', 'c/flanterm', 'c/nanoprintf.h', 'c/lwip', 'c/uacpi'] {
				os.symlink(root + '/kernel/' + name, tree + '/kernel/' + name)!
			}
		}
		return
	}
	assert phase == 'build'
	suffix := os.args[2]
	flavor := os.args[3]
	assert suffix in ['arm', 'x86'] && flavor in ['track', 'prod']
	tree := area + '/kernel-' + suffix
	arch := if suffix == 'arm' { 'aarch64' } else { 'x86_64' }
	mut args := ['ARCH=' + arch, 'V=' + compiler, 'CC=clang', 'PROD=true', '-j4', 'LIMINE_MP=1', 'ALLOC_TRACK=' + if flavor == 'track' { '1' } else { '0' }, 'KERNEL_LINK_SEED=42']
	if suffix == 'x86' { args << 'LD_X86_64=ld.lld' }
	label := suffix + '-' + flavor
	run('make', args, tree + '/kernel', area + '/build-' + label + '.log')!
	os.mkdir_all(area + '/' + label + '/kernel/bin')!
	os.cp(tree + '/kernel/bin/vinix', area + '/' + label + '/kernel/bin/vinix')!
	os.cp(tree + '/kernel/obj/blob.c', area + '/' + label + '/blob.c')!
	println(label + ': PASS')
}
