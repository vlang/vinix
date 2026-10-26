// SPDX-License-Identifier: GPL-2.0-or-later
// Compile the production browser wait binding and calls beside real os.Process.
// Reverting the binding must fail strict target C compilation, without patches.
module main

import crypto.sha256
import json2
import os

struct ProcessAbiCommand {
	argv      []string
	exit_code int
	output    string
}

fn checked_command(work string, label string, argv []string) !ProcessAbiCommand {
	result := os.exec(argv)
	receipt := ProcessAbiCommand{argv, result.exit_code, result.output}
	os.write_file(work + '/' + label + '.json', json2.encode(receipt, prettify: true))!
	return receipt
}

fn main() {
	assert os.args.len in [2, 3], 'usage: check-browser-process-abi OUTPUT_DIR [REPO]'
	repo := if os.args.len == 3 { os.real_path(os.args[2]) } else { os.getwd() }
	work := os.abs_path(os.args[1])
	assert !os.exists(work), 'output directory must be new'
	assert work != repo && !work.starts_with(repo + '/'), 'keep generated evidence outside Git'
	os.mkdir_all(work)!
	source := os.read_file(repo + '/build-support/android/browserlaunch/session.c.v')!
	assert source.contains('process.wait()') && source.contains('process.is_alive()'), 'production must still use os.Process'
	declaration := "@[c: 'waitpid']\nfn C.browser_waitpid(i32, &i32, i32) i32"
	assert source.contains(declaration), 'browser wait binding must have a distinct V name'
	assert !source.contains('fn C.waitpid('), 'browser binding must not override builtin C.waitpid'
	wait_lines := source.split_into_lines().filter(it.contains(':= C.browser_waitpid(')
		|| it.contains('for waited < 0 && C.errno == C.EINTR'))
	assert wait_lines.len == 2, 'retain the exact production wait and EINTR retry'
	fixture := process_abi_fixture.replace('@DECLARATION@', declaration)
		.replace('@WAIT_CALLS@', wait_lines.join('\n'))
	mutant := fixture.replace(declaration, 'fn C.waitpid(i32, &i32, i32) i32')
		.replace('C.browser_waitpid(', 'C.waitpid(')
	assert mutant != fixture
	os.write_file(work + '/production-session.c.v', source)!
	os.write_file(work + '/positive.v', fixture)!
	os.write_file(work + '/binding-regression.v', mutant)!
	compiler := os.real_path(os.getenv_opt('VINIX_V_COMPILER') or { os.find_abs_path_of_executable('v')! })
	compiler_root := os.real_path(os.getenv_opt('VINIX_V_ROOT') or { os.dir(compiler) })
	assert os.is_dir(compiler_root + '/vlib'), 'VINIX_V_ROOT must contain the selected vlib'
	cross := os.getenv_opt('VINIX_CROSS_CC') or { '/opt/homebrew/bin/aarch64-linux-musl-gcc' }
	os.chdir(compiler_root)!
	for name in ['VEXE', 'V', 'VINIX_V_COMPILER'] { os.setenv(name, compiler, true) }
	os.setenv('VROOT', compiler_root, true)
	os.setenv('VFLAGS', '', true)
	for name in ['positive', 'binding-regression'] {
		generate := checked_command(work, name + '-generate', [compiler, '-new-compiler', '-os',
			'linux', '-arch', 'arm64', '-cc', cross, '-gc', 'none', '-nocache', '-skip-running',
			'-exclude', '@vlib/crypto/rand/internal/rand.wasm.v', '-path',
			compiler_root + '/vlib|@vlib|@vmodules', '-o', work + '/' + name + '.c',
			work + '/' + name + '.v'])!
		assert generate.exit_code == 0, generate.output
		compile := checked_command(work, name + '-cross', [cross, '-D_GNU_SOURCE', '-pthread',
			'-Werror=implicit-function-declaration', '-Werror=int-conversion',
			'-Werror=incompatible-pointer-types', '-fsyntax-only', work + '/' + name + '.c'])!
		if name == 'positive' {
			assert compile.exit_code == 0, compile.output
		} else {
			assert compile.exit_code != 0 && compile.output.contains('waitpid')
				&& compile.output.contains('incompatible pointer type'), compile.output
		}
	}
	host_compile := checked_command(work, 'positive-host-compile', [compiler, '-new-compiler',
		'-cc', 'cc', '-gc', 'none', '-nocache', '-path', compiler_root + '/vlib|@vlib|@vmodules',
		'-o', work + '/positive', work + '/positive.v'])!
	assert host_compile.exit_code == 0, host_compile.output
	ran := checked_command(work, 'positive-host-run', [work + '/positive'])!
	assert ran.exit_code == 0 && ran.output.trim_space() == 'BROWSER-PROCESS-ABI-RUN-PASS', ran.output
	revision := checked_command(work, 'source-revision', ['git', '-C', repo, 'rev-parse', 'HEAD'])!
	assert revision.exit_code == 0
	version := checked_command(work, 'cross-version', [cross, '--version'])!
	assert version.exit_code == 0
	os.write_file(work + '/evidence.json', json2.encode({
		'scope':                 'Production typed wait binding and calls with real os.Process; host execution and strict arm64 Linux C compilation; one negative binding mutant; no guest execution.'
		'source_revision':       revision.output.trim_space()
		'source_sha256':         sha256.sum(source.bytes()).hex()
		'fixture_sha256':        sha256.sum(fixture.bytes()).hex()
		'compiler':              compiler
		'compiler_sha256':       sha256.sum(os.read_bytes(compiler)!).hex()
		'compiler_root':         compiler_root
		'cross_compiler':        os.real_path(cross)
		'cross_compiler_sha256': sha256.sum(os.read_bytes(os.real_path(cross))!).hex()
	}, prettify: true))!
	mut checksums := map[string]string{}
	for name in os.ls(work)! {
		assert os.is_file(work + '/' + name)
		checksums[name] = sha256.sum(os.read_bytes(work + '/' + name)!).hex()
	}
	os.write_file(work + '/checksums.json', json2.encode(checksums, prettify: true))!
	println('BROWSER-PROCESS-ABI-PASS production-binding real-process typed-status host-run arm64-cross negative-mutations=1')
}

const process_abi_fixture = '
module main
import os
#include <sys/wait.h>
#include <unistd.h>
#include <errno.h>
fn C.fork() i32
fn C._exit(i32)
@DECLARATION@
fn main() {
 mut process := os.new_process("/bin/sh")
 process.set_args(["-c", "exit 37"])
 process.run()
 process.wait()
 assert process.code == 37
 process.close()
 pid := C.fork()
 assert pid >= 0
 if pid == 0 { C._exit(23) }
 mut status := i32(0)
@WAIT_CALLS@
 assert waited == pid
 assert status == i32(23 << 8)
 println("BROWSER-PROCESS-ABI-RUN-PASS")
}
'
