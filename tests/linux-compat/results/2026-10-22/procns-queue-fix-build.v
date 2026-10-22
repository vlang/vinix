import os
import crypto.sha256

const root = '/Users/alex/code/vinix'
const area = '/Users/alex/.cache/vinix-linux-compat/procns-resume-20261022/queue-fix'
const base = 'cf6426cf16657a6db8d5be8062ef82f170c6b48b'
const compiler = '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/v'

fn run(program string, args []string, folder string, log string) !string {
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
	return output
}

fn main() {
	phase := os.args[1]
	os.mkdir_all(area)!
	if phase == 'prepare' {
		for suffix in ['x86', 'arm'] {
			tree := area + '/kernel-' + suffix
			assert !os.exists(tree)
			run('git', ['worktree', 'add', '--detach', '--no-checkout', tree, base], root, area + '/worktree-' + suffix + '.log')!
			run('git', ['sparse-checkout', 'set', 'kernel', 'build-support', 'tests/linuxkpi', 'tests/native-generators', 'tests/kernel-allocs', 'tests/scheduler-qos', 'tools/sourcecommand', 'tools/linux-compat'], tree, area + '/sparse-' + suffix + '.log')!
			run('git', ['checkout', '--detach', base], tree, area + '/checkout-' + suffix + '.log')!
			for name in ['freestnd-c-hdrs', 'cc-runtime', 'cc-runtime-aarch64', 'cc-runtime-x86_64', 'c/flanterm', 'c/nanoprintf.h', 'c/lwip', 'c/uacpi'] {
				os.symlink(root + '/kernel/' + name, tree + '/kernel/' + name)!
			}
			path := tree + '/kernel/fs/removed.v'
			original := os.read_file(path)!
			old := '\tmut items := []RetiredItem{len: due} @[freed]\n\t// Transfer the original owned strings. V deep-clones a string-bearing\n\t// struct pushed directly from an array index, losing the original names.\n\tunsafe { C.memcpy(items.data, removed_items.data, usize(due) * sizeof(RetiredItem)) }\n\tremoved_items.delete_many(0, due)'
			new := '\tmut items := []RetiredItem{} @[freed]\n\tif due == removed_items.len {\n\t\t// Move the whole buffer when drained. Retiring and callbacks use a new\n\t\t// queue after unlock; the detached batch owns and frees the old buffer.\n\t\titems = unsafe { removed_items }\n\t\tremoved_items = []RetiredItem{}\n\t} else {\n\t\titems = []RetiredItem{len: due}\n\t\t// Transfer the original owned strings. V deep-clones a string-bearing\n\t\t// struct pushed directly from an array index, losing the original names.\n\t\tunsafe { C.memcpy(items.data, removed_items.data, usize(due) * sizeof(RetiredItem)) }\n\t\tremoved_items.delete_many(0, due)\n\t}'
			assert original.count(old) == 1
			os.write_file(area + '/removed-before-' + suffix + '.v', original)!
			os.write_file(path, original.replace(old, new))!
			os.cp(path, area + '/removed-after-' + suffix + '.v')!
			run('git', ['diff', '--check'], tree, area + '/diff-check-' + suffix + '.log')!
			run('git', ['diff', '--', 'kernel/fs/removed.v'], tree, area + '/source-' + suffix + '.diff')!
			run('git', ['status', '--short', '--untracked-files=no'], tree, area + '/source-' + suffix + '.status')!
		}
		os.write_file(area + '/base.txt', base + '\n')!
		assert os.read_file(area + '/source-x86.diff')! == os.read_file(area + '/source-arm.diff')!
		println('Prepared identical isolated source changes from ' + base)
		return
	}
	assert phase == 'build'
	suffix := os.args[2]
	flavor := os.args[3]
	assert suffix in ['arm', 'x86'] && flavor in ['track', 'prod']
	tree := area + '/kernel-' + suffix
	assert os.read_file(tree + '/kernel/fs/removed.v')! == os.read_file(area + '/removed-after-' + suffix + '.v')!
	arch := if suffix == 'arm' { 'aarch64' } else { 'x86_64' }
	mut args := ['ARCH=' + arch, 'V=' + compiler, 'CC=clang', 'PROD=true', '-j2', 'LIMINE_MP=1', 'ALLOC_TRACK=' + if flavor == 'track' { '1' } else { '0' }, 'KERNEL_LINK_SEED=42']
	if suffix == 'x86' { args << 'LD_X86_64=ld.lld' }
	label := suffix + '-' + flavor
	println('Building ' + label + ' in ' + tree)
	run('make', args, tree + '/kernel', area + '/build-' + label + '.log')!
	os.mkdir_all(area + '/' + label + '/kernel/bin')!
	os.cp(tree + '/kernel/bin/vinix', area + '/' + label + '/kernel/bin/vinix')!
	os.cp(tree + '/kernel/obj/blob.c', area + '/' + label + '/blob.c')!
	mut pins := []string{}
	for path in [tree + '/kernel/fs/removed.v', area + '/source-' + suffix + '.diff', area + '/' + label + '/kernel/bin/vinix', area + '/' + label + '/blob.c', area + '/build-' + label + '.log', compiler] {
		pins << sha256.sum(os.read_bytes(path)!).hex() + '  ' + path
	}
	os.write_file(area + '/inputs-' + label + '.sha256', pins.join('\n') + '\n')!
	println(label + ': PASS')
}
