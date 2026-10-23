// SPDX-License-Identifier: GPL-2.0-or-later
// V-only host qualification and two-target public SDK consumer compilation.
module main

import crypto.sha256
import json2
import os

#include <unistd.h>

fn digest(path string) !string { return sha256.hexhash(os.read_file(path)!) }
fn require(ok bool, message string) ! { if !ok { return error(message) } }

fn invoke(argv []string, log string) ! {
	os.write_file(log + '.argv.json', json2.encode(argv) + '\n')!
	mut child := os.new_process(argv[0])
	defer { child.close() }
	child.set_args(argv[1..])
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	text := child.stdout_slurp()
	child.wait()
	os.write_file(log, text)!
	if child.code != 0 { return error('command failed; see ' + log) }
}

fn source_paths(root string) ![]string {
	mut child := os.new_process('/usr/bin/git')
	defer { child.close() }
	child.set_args(['-C', root, 'ls-files', '--cached', '--others', '--exclude-standard', '-z', '--',
		'tools/packages', 'tools/accounts', 'tools/keyring', 'tools/security-events',
		'compat/linux', 'compat/ios/plist', 'desktop/tools/tests/heap_tracker.h',
		'tests/packages/deployment-writer-build.v', 'tests/packages/deployment-writer-check.v'])
	child.set_redirect_stdio_merged()
	child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	text := child.stdout_slurp()
	child.wait()
	require(child.code == 0, 'cannot inventory package sources')!
	mut paths := text.split('\x00').filter(it != '' && (it.ends_with('.v') || it.ends_with('.h') || it.ends_with('.c')))
	paths.sort()
	return paths
}

fn verify(root string, paths []string, hashes map[string]string) ! {
	require(source_paths(root)! == paths, 'source inventory changed')!
	for path, hash in hashes { require(digest(root + '/' + path)! == hash, 'source changed: ' + path)! }
}

fn cross(v string, source string, repository string, output string, arch string) ! {
	directory := output + '/' + arch
	os.mkdir(directory, mode: 0o700)!
	cfile := directory + '/deployment-writer-check.c'
	invoke([v, '-backend', 'c', '-path', '@vlib|@vmodules|' + source, '-gc', 'none', '-manualfree',
		'-d', 'no_backtrace', '-d', 'no_segfault_handler', '-os', 'linux', '-arch',
		if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-o', cfile,
		source + '/tests/packages/deployment-writer-check.v'], directory + '/v.log')!
	sysroot := repository + if arch == 'aarch64' { '/build-aarch64-x11/sysroot' } else { '/build-amd64-x11/sysroot' }
	userland := repository + if arch == 'aarch64' { '/build-aarch64-userland/staging' } else { '/build/session-amd64-sysroot' }
	parent := userland + '/usr/lib/gcc/' + arch + '-alpine-linux-musl'
	mut versions := os.ls(parent)!
	versions.sort()
	require(versions.len != 0, 'musl GCC support missing')!
	invoke(['/opt/homebrew/opt/llvm/bin/clang', '--target=' + arch + '-linux-musl', '--sysroot=' + sysroot,
		'--gcc-install-dir=' + parent + '/' + versions.last(), '-fuse-ld=lld', '-w', '-fno-stack-protector',
		'-Wno-error=incompatible-pointer-types', '-D_GNU_SOURCE', '-L' + sysroot + '/lib', '-L' + sysroot + '/usr/lib',
		'-Wl,-rpath-link,' + sysroot + '/lib', '-Wl,-rpath-link,' + sysroot + '/usr/lib', output + '/runtime.c',
		'-O2', '-std=gnu11', '-static', '-o', directory + '/deployment-writer-check', cfile, '-lm', '-lpthread'], directory + '/cc.log')!
	bytes := os.read_bytes(directory + '/deployment-writer-check')!
	require(bytes.len >= 20 && bytes[..6] == [u8(127), `E`, `L`, `F`, 2, 1]
		&& int(bytes[18]) + (int(bytes[19]) << 8) == if arch == 'aarch64' { 183 } else { 62 }, 'wrong consumer ELF architecture')!
}

fn check() ! {
	$if prod {} $else { return error('compile deployment-writer-build with -prod to bind its source') }
	embedded := sha256.hexhash($embed_file('deployment-writer-build.v').to_string())
	require(digest(@FILE)! == embedded, 'driver source differs from executable')!
	if os.args.len != 4 { return error('usage: deployment-writer-build SOURCE_WORKTREE REPOSITORY_WITH_SYSROOTS NEW_OUTPUT_DIRECTORY') }
	root := os.real_path(os.args[1])
	repository := os.real_path(os.args[2])
	output := os.abs_path(os.args[3])
	require(!os.exists(output) && !os.is_link(output), 'output directory must be new')!
	v := os.real_path(os.getenv_opt('V') or { repository + '/build/package-https-runtime-work/toolchain/v' })
	for key in ['V', 'VEXE', 'V_MACOS_V3_CALLER_VEXE'] { os.setenv(key, v, true) }
	os.setenv('V_MACOS_V3_CALLER_VEXE_PRESENT', '1', true)
	os.setenv('V_MACOS_V3_CALLER_VCHILD_PRESENT', '0', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0:halt_on_error=1', true)
	os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	paths := source_paths(root)!
	mut hashes := map[string]string{}
	for path in paths { hashes[path] = digest(root + '/' + path)! }
	require(digest(@FILE)! == embedded, 'driver source changed during capture')!
	require(hashes['tests/packages/deployment-writer-build.v'] == embedded, 'captured driver differs from executable')!
	os.mkdir(output, mode: 0o700)!
	source := output + '/source'
	for path in paths {
		os.mkdir_all(os.dir(source + '/' + path), mode: 0o755)!
		os.cp(root + '/' + path, source + '/' + path)!
		require(digest(source + '/' + path)! == hashes[path], 'source copy changed')!
	}
	os.write_file(output + '/source.json', json2.encode(hashes) + '\n')!
	verify(root, paths, hashes)!
	path := '@vlib|@vmodules|' + source + '|' + source + '/tools/accounts'
	for mode in ['normal', 'prod', 'tracked', 'tracked-prod', 'sanitized', 'legacy', 'cli', 'cli-prod', 'consumer'] {
		mut argv := [v, '-backend', 'c', '-keepc', '-gc', 'none', '-manualfree', '-path', path]
		if mode in ['tracked', 'tracked-prod'] { argv << ['-d', 'track_heap'] }
		if mode in ['prod', 'tracked-prod', 'cli-prod', 'consumer'] { argv << '-prod' }
		if mode == 'sanitized' {
			argv << ['-cc', 'clang', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined']
		}
		program := match mode {
			'cli', 'cli-prod' { 'tools/packages/main.v' }
			'consumer' { 'tests/packages/deployment-writer-check.v' }
			'legacy' { 'tools/packages/pkgprotocol/deployment_document_test.v' }
			else { 'tools/packages/pkgprotocol/deployment_writer_test.v' }
		}
		argv << ['-o', output + '/' + mode, source + '/' + program]
		invoke(argv, output + '/' + mode + '.build.log')!
		if mode !in ['cli', 'cli-prod', 'consumer'] { invoke([output + '/' + mode], output + '/' + mode + '.run.log')! }
	}
	for mode in ['cli', 'cli-prod'] {
		invoke([output + '/consumer', output + '/' + mode, output + '/' + mode + '-state'], output + '/' + mode + '.check.log')!
	}
	vroot := os.dir(v)
	os.write_file(output + '/runtime.c', '#include <unistd.h>\n#include <fcntl.h>\n#include <sys/wait.h>\n#define V_OS_EXECUTE_SCOPE\n#include "' +
		vroot + '/vlib/os/execute_capture_nix.h"\n#define V_SYNC_THREAD_SCOPE\n#include "' + vroot + '/vlib/sync/thread_helper.h"\n')!
	for arch in ['aarch64', 'x86_64'] { cross(v, source, repository, output, arch)! }
	verify(root, paths, hashes)!
	for relative, hash in hashes { require(digest(source + '/' + relative)! == hash, 'frozen source changed')! }
	mut artifacts := map[string]string{}
	for file in os.walk_ext(output, '') {
		if os.is_file(file) && !file.starts_with(source + '/') { artifacts[file[output.len + 1..]] = digest(file)! }
	}
	for file in [v, vroot + '/vlib/os/execute_capture_nix.h', vroot + '/vlib/sync/thread_helper.h', '/opt/homebrew/opt/llvm/bin/clang', os.executable()] {
		artifacts[file] = digest(file)!
	}
	os.write_file(output + '/artifacts.json', json2.encode(artifacts) + '\n')!
	println('DEPLOYMENT WRITER normal/prod/tracked/sanitized/legacy/real-CLI checks and both target consumer builds PASS: ' + output)
}

fn main() { check() or { eprintln(err); exit(1) } }
