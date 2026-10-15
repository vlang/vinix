import os
import time

#include <unistd.h>
#include <fcntl.h>
fn C.fork() int
fn C.setsid() int
fn C.open(&char, int, int) int
fn C.dup1(int, int) int
fn C.close(int) int
fn C.execv(&char, &&char) int
fn C._exit(int)

const root = '/Users/alex/code/vinix'
const area = '/Users/alex/.cache/vinix-linux-compat/waituid-20261015'
const old = '/Users/alex/.cache/vinix-linux-compat/attrclass-20261015'
const compiler = '/Users/alex/.cache/vinix-linux-compat/proctask-20261014/compiler/v'

fn capture(source string, destination string) ! {
	expected := os.read_bytes(source)!
	defer { unsafe { expected.free() } }
	os.write_file_array(destination, expected)!
	actual := os.read_bytes(destination)!
	defer { unsafe { actual.free() } }
	matches := actual == expected
	assert matches, 'Incomplete artifact capture: ' + destination
}

fn run(program string, args []string, folder string, output string, expected int) ! {
	mut p := os.new_process(program)
	p.set_args(args)
	if folder != '' { p.set_work_folder(folder) }
	mut env := os.environ()
	env['V'] = compiler; env['VINIX_V_COMPILER'] = compiler; env['TMPDIR'] = area + '/tmp'; env['VINIX_AARCH64_SYSROOT'] = area + '/sdk'; env['CC'] = area + '/arm-cc'
	p.set_environment(env); p.set_redirect_stdio_merged(); p.run()
	data := p.stdout_slurp(); p.wait(); code := p.code; p.close()
	if output != '' {
		mut saved := false
		for _ in 0 .. 300 { os.write_file(output, data) or { time.sleep(time.second); continue }; saved = true; break }
		assert saved, 'producer stdout could not be retained'
	}
	assert code == expected, data
}
fn git(folder string, args []string) string {
	mut p := os.new_process('git'); p.set_args(['-C', folder, ...args]); p.set_redirect_stdio_merged(); p.run()
	data := p.stdout_slurp(); p.wait(); code := p.code; p.close(); assert code == 0, data; return data.trim_space()
}
fn main() {
	phase := os.args[1]
	if phase == 'detach' {
		log := os.args[2]; assert log.starts_with(area + '/') && !os.exists(log)
		mut args := []&char{}; args << os.executable().str
		for arg in os.args[3..] { args << arg.str }; args << unsafe { &char(0) }
		pid := C.fork(); assert pid >= 0
		if pid == 0 { unsafe {
			if C.setsid() < 0 { C._exit(126) }
			fd := C.open(log.str, C.O_WRONLY | C.O_CREAT | C.O_EXCL, 0o600)
			if fd < 0 || C.dup1(fd, 1) < 0 || C.dup1(fd, 2) < 0 { C._exit(126) }
			C.close(fd); C.execv(os.executable().str, &&char(args.data)); C._exit(127)
		} }
		os.write_file(log + '.pid', pid.str() + '\n')!; println('Detached owned job ' + pid.str()); return
	}
	if phase == 'prepare' {
		assert !os.exists(area + '/base.txt')
		for path in ['kernel/userland/linux_task.v'] { assert git(root, ['diff', '--name-only', 'HEAD', '--', path]) == '' }
		base := git(root, ['rev-parse', 'HEAD'])
		assert git(root, ['merge-base', '--is-ancestor', 'e68c1ddbc23059f36ea2dd663f84612a74ccee49', base]) == ''
		os.write_file(area + '/base.txt', base + '\n')!; os.mkdir_all(area + '/tmp')!; os.mkdir_all(area + '/states')!
		for path in ['kernel/userland/linux_task.v'] { os.cp(root + '/' + path, area + '/before-' + os.file_name(path))! }
		for suffix in ['arm', 'x86'] {
			tree := area + '/kernel-' + suffix
			git(root, ['worktree', 'add', '--detach', '--no-checkout', tree, base])
			git(tree, ['sparse-checkout', 'set', 'kernel', 'build-support', 'tests/linuxkpi', 'tests/native-generators', 'tests/kernel-allocs', 'tests/scheduler-qos', 'tools/sourcecommand', 'tools/linux-compat', 'docs'])
			git(tree, ['checkout', '--detach', base])
			for name in ['freestnd-c-hdrs','cc-runtime','cc-runtime-aarch64','cc-runtime-x86_64','c/flanterm','c/nanoprintf.h','c/lwip','c/uacpi'] { os.symlink(root + '/kernel/' + name, tree + '/kernel/' + name)! }
			os.mkdir_all(area + '/objects-' + suffix)!; os.symlink(area + '/objects-' + suffix, tree + '/kernel/obj')!
		}
		println('Frozen waitid child-UID base ' + base); return
	}
	if phase == 'build' {
		suffix := os.args[2]; version := os.args[3]; assert suffix in ['arm','x86'] && version in ['before','after']
		if version == 'after' {
			assert os.exists(area + '/baseline-' + suffix + '/kernel/bin/vinix')
			for path in ['kernel/userland/linux_task.v'] { os.cp(root + '/' + path, area + '/kernel-' + suffix + '/' + path)!; os.cp(root + '/' + path, area + '/after-' + os.file_name(path))! }
		}
		mut args := ['ARCH=' + if suffix == 'arm' { 'aarch64' } else { 'x86_64' },'V=' + compiler,'CC=clang','PROD=true','-j4','-W','userland/linux_task.v']
		if suffix == 'x86' { args << 'LD_X86_64=ld.lld' }
		run('make',args,area + '/kernel-' + suffix + '/kernel',area + '/build-' + version + '-' + suffix + '.log',0)!
		capture(area + '/kernel-' + suffix + '/kernel/obj/blob.c',area + '/' + version + '-' + suffix + '.c')!
		if version == 'before' { os.mkdir_all(area + '/baseline-' + suffix + '/kernel/bin')!; capture(area + '/kernel-' + suffix + '/kernel/bin/vinix',area + '/baseline-' + suffix + '/kernel/bin/vinix')! }
		println(suffix + ' ' + version + ' production build: PASS'); return
	}
	if phase == 'helper' {
		name := os.args[2]; assert name in ['watch','rescan','coverage','preflight','preflight-jobs']
		run(area + '/' + name,os.args[3..],root,area + '/helper-' + os.args[2..].join('-') + '.log',0)!
		println(name + ': PASS'); return
	}
	if phase == 'host' {
		run(compiler,['-enable-globals','-nocache','test',root + '/tools/linux-compat'],root,area + '/host-tests.log',0)!; println('Host tests: PASS'); return
	}
	if phase == 'fetch' {
		run('curl',['--silent','--show-error','--fail','--location','--retry','3','https://raw.githubusercontent.com/torvalds/linux/v6.12/kernel/sys.c'],root,area + '/linux-sys-v6.12.c',0)!
		// curl progress is suppressed below by the quiet option to retain only source.
		return
	}
	if phase == 'compile' {
		for name, source in {'run':'run.v','reference':'waituid-reference.v'} { run(compiler,['-enable-globals','-nocache','-gc','none','-cc','cc','-cflags','-O2','-o',area + '/' + name,root + '/tests/linux-compat/' + source],root,area + '/compile-' + name + '.log',0)! }
		return
	}
	if phase == 'native' || phase == 'reference' {
		suffix := os.args[2]; assert suffix in ['arm','x86']; arch := if suffix == 'arm' { 'aarch64' } else { 'x86_64' }
		version := if phase == 'reference' { 'reference' } else { os.args[3] }
		prefix := if phase == 'native' && os.args.len > 4 { os.args[4] } else if phase == 'reference' { 'p1' } else { 'p1' }
		state := area + '/states/' + prefix + '-' + version + '-' + suffix
		if phase == 'reference' {
			run(area + '/reference',['--arch',arch,'--kernel','/Users/alex/.cache/vinix-linux-compat/statx-20261013/linux-inputs/vmlinuz-' + arch,'--init',area + '/states/' + 'p1-' + 'before-' + suffix + '/waituid/init','--state-dir',state],root,state + '.log',0)!
		} else {
			assert version in ['before','after']
			cases := if os.args.len > 5 { os.args[5] } else if version == 'before' { 'waituid' } else { 'waituid,runtime,waitempty' }
			run(area + '/run',['--arch',arch,'--kernel-dir',area + '/' + if version == 'before' { 'baseline-' + suffix } else { 'kernel-' + suffix } + '/kernel','--state-dir',state,'--cases',cases,'--timeout','1500'],root,state + '.log',if version == 'before' { 1 } else { 0 })!
		}
		println(arch + ' ' + version + ': expected producer status'); return
	}
	panic('unknown phase')
}
