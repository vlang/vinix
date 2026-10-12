// SPDX-License-Identifier: GPL-2.0-or-later
module cachefixture

import crypto.sha256
import hosttest
import os
import sourcecommand
import time

#include <signal.h>
#include <unistd.h>

fn C.signal(i32, voidptr) voidptr

fn run(argv []string, status int) !string {
	result := sourcecommand.capture(argv, os.environ(), 40, 4 * 1024 * 1024, unsafe { nil })!
	assert result.status == status, argv.join(' ') + '\n' + result.stdout + result.stderr
	return result.stdout + result.stderr
}

// Independent framing of the unchanged content-key wire format.
fn golden(fields []string, payload string) string {
	mut bytes := []u8{}
	for field in fields {
		for shift in [56, 48, 40, 32, 24, 16, 8, 0] { bytes << u8(u64(field.len) >> shift) }
		bytes << field.bytes()
	}
	bytes << payload.bytes()
	return sha256.sum(bytes).hex() + '\n'
}

fn content_and_cli(work string, content string, staging string, desktop string, office string) ! {
	file := work + '/payload'
	os.write_file(file, 'known\n')!
	os.chmod(file, 0o640)!
	assert run([content, file], 0)! == golden(['vinix-content-key-v1', 'root-0', '0o640', 'file',
		'6'], 'known\n')
	assert run([content, work + '/missing'], 0)! == golden(['vinix-content-key-v1', 'root-0', 'missing'], '')
	run([content], 2)!
	for binary in [staging, desktop, office] {
		run([binary], 2)!
		run([binary, '--help'], 0)!
		run([binary, '--he'], 0)!
		run([binary, '--help=value'], 2)!
		run([binary, '--unknown'], 2)!
	}
	os.mkdir_all(work + '/staged')!
	os.write_file(work + '/staged/app', 'executable')!
	os.chmod(work + '/staged/app', 0o755)!
	args := ['--state', work + '/state', '--staging', work + '/staged', '--executable-any', 'missing',
		'--executable-any', 'app', '--required', 'app', '--value=', '--source', file]
	run([staging, 'check', ...args], 1)!
	run([staging, 'record', ...args], 0)!
	first := os.read_file(work + '/state')!
	run([staging, 'check', ...args], 0)!
	os.chmod(work + '/staged/app', 0o644)!
	run([staging, 'record', ...args], 2)!
	assert os.read_file(work + '/state')! == first
	os.chmod(work + '/staged/app', 0o755)!
	os.write_file(file, 'changed\n')!
	run([staging, 'check', ...args], 1)!
	// Malformed compiler quoting must fail rather than execute a shell command.
	os.setenv('VINIX_MUSL_CC_AARCH64', 'cc "unterminated', true)
	run([desktop, '--root', work, '--v', file], 1)!
	os.unsetenv('VINIX_MUSL_CC_AARCH64')
	compiler := work + '/compiler'
	os.write_file(compiler, '#!/bin/sh\nprintf first; printf " version\\n" >&2; printf ignored\\n\n')!
	os.chmod(compiler, 0o755)!
	os.setenv('VINIX_MUSL_CC_AARCH64', '"' + compiler + '" "a b"', true)
	key := run([desktop, '--root', work, '--v', file], 0)!.trim_space()
	assert key.len == 64 && key.bytes().all(it.is_hex_digit())
	assert key == run([desktop, '--root', work, '--v', file], 0)!.trim_space()
	// Discovery is controlled by the original compiler argv and PATH only.
	os.setenv('VINIX_CACHE_MUSL_EXECUTABLE', '/no/such/compiler', true)
	assert key == run([desktop, '--root', work, '--v', file], 0)!.trim_space()
	os.unsetenv('VINIX_CACHE_MUSL_EXECUTABLE')
	os.write_file(compiler, '#!/bin/sh\nexit 7\n')!
	assert key != run([desktop, '--root', work, '--v', file], 0)!.trim_space()
	os.unsetenv('VINIX_MUSL_CC_AARCH64')
}

fn prepare_office(repo string, work string) ! {
	// Reuse the existing independent fake-toolchain setup without changing its
	// build assertions. This setup contains no interpreter invocation.
	text := os.read_file(repo + '/tests/vlang/test-voffice-cache.sh')!
	mut setup := text.all_before('\nbuild() {')
	setup = setup.replace('repo=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)', 'repo=' + hosttest.shell_quote(repo))
	setup = setup.replace(r'work=$(mktemp -d "${TMPDIR:-/tmp}/vinix-voffice-cache-test.XXXXXX")', 'work=' + hosttest.shell_quote(work))
	setup = setup.replace('trap \'rm -rf "$work"\' EXIT HUP INT TERM', '')
	assert !setup.contains('python')
	os.mkdir_all(work)!
	os.write_file(work + '/setup.sh', setup)!
	run(['/bin/sh', work + '/setup.sh'], 0)!
	os.write_file(work + '/toolchain/vlib/net/mbedtls/mbedtls.c.v', '#flag @VEXEROOT/thirdparty/mbedtls/library/one.o\n#flag @VEXEROOT/thirdparty/mbedtls/library/two.o\n')!
	os.write_file(work + '/bin/clang', '#!/bin/sh\nexec ' + hosttest.shell_quote(os.executable()) + ' --compiler "$@"\n')!
	os.chmod(work + '/bin/clang', 0o755)!
	os.mkdir(work + '/output')!
	os.write_file(work + '/output/voffice-calc', 'published calc')!
	os.write_file(work + '/output/voffice-writer', 'published writer')!
	os.write_file(work + '/output/.vinix-voffice-build-state.json', '{"version":2,"apps":{}}\n')!
}

fn alive(pid int) bool { return C.kill(pid, 0) == 0 }

fn interrupt_office(repo string, base string, office string, signal int) ! {
	work := base + '/signal-' + signal.str()
	prepare_office(repo, work)!
	os.setenv('VINIX_CACHE_FIXTURE_DIR', work, true)
	defer { os.unsetenv('VINIX_CACHE_FIXTURE_DIR') }
	mut process := os.new_process(office)
	process.set_args(['--repo', repo, '--office-source', work + '/office', '--ui2-source',
		work + '/ui2', '--output', work + '/output', '--work', work + '/build', '--v',
		work + '/toolchain/v', '--arch', 'arm64', '--clang', work + '/bin/clang', '--strip',
		work + '/bin/strip', '--target', 'aarch64-linux-musl', '--sysroot', work + '/sysroot',
		'--gcclib', work + '/gcclib', '--jobs', '2'])
	process.set_redirect_stdio()
	process.run()
	defer {
		if process.is_alive() {
			C.kill(process.pid, C.SIGTERM)
			process.wait()
		}
		process.close()
	}
	deadline := time.sys_mono_now() + 30 * u64(time.second)
	for !os.exists(work + '/one.c.pids') || !os.exists(work + '/two.c.pids') {
		assert process.is_alive(), process.stdout_slurp() + process.stderr_slurp()
		assert time.sys_mono_now() < deadline, 'TLS workers did not start'
		time.sleep(20 * time.millisecond)
	}
	mut owners := []int{}
	for name in ['one', 'two'] {
		owners << os.read_file(work + '/' + name + '.c.pids')!.fields().map(it.int())
	}
	assert owners.len == 4 && owners.all(alive(it))
	assert C.kill(process.pid, signal) == 0
	for process.is_alive() {
		assert time.sys_mono_now() < deadline
		time.sleep(20 * time.millisecond)
	}
	process.wait()
	assert process.code == 128 + signal, process.stderr_slurp()
	for owners.any(alive(it)) {
		assert time.sys_mono_now() < deadline, 'compiler descendant survived'
		time.sleep(20 * time.millisecond)
	}
	assert os.read_file(work + '/output/voffice-calc')! == 'published calc'
	assert os.read_file(work + '/output/voffice-writer')! == 'published writer'
	assert os.read_file(work + '/output/.vinix-voffice-build-state.json')! == '{"version":2,"apps":{}}\n'
}

fn compile_child(argv []string) ! {
	work := os.getenv('VINIX_CACHE_FIXTURE_DIR')
	if argv == ['--print-resource-dir'] {
		println(work + '/clang-resource')
		return
	}
	index := argv.index('-c')
	assert index >= 0 && index + 1 < argv.len
	mut descendant := os.new_process(os.executable())
	descendant.set_args(['--descendant'])
	descendant.run()
	os.write_file(work + '/' + os.base(argv[index + 1]) + '.pids', os.getpid().str() + ' ' + descendant.pid.str() + '\n')!
	for { time.sleep(20 * time.millisecond) }
}

pub fn cli(argv []string) ! {
	if argv.len > 0 && argv[0] == '--compiler' {
		compile_child(argv[1..])!
		return
	}
	if argv == ['--descendant'] {
		unsafe {
			C.signal(C.SIGINT, C.SIG_IGN)
			C.signal(C.SIGTERM, C.SIG_IGN)
		}
		for { time.sleep(20 * time.millisecond) }
	}
	assert argv.len == 6, 'test-cache-tools WORK REPOSITORY CONTENT STAGING DESKTOP OFFICE'
	os.mkdir_all(argv[0])!
	content_and_cli(argv[0], argv[2], argv[3], argv[4], argv[5])!
	for signal in [int(C.SIGINT), int(C.SIGTERM)] {
		interrupt_office(argv[1], argv[0], argv[5], signal)!
	}
	println('PASS cache CLI, original content framing, failure publication and two parallel compiler groups with descendants on SIGINT/SIGTERM')
}
