// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import os
import sourcefixture
import sourcecommand
import hostfixture
import qmpclient
import hosttest

fn run(args []string) ! {
	if args.len == 0 || args[0] in ['--help', '-h'] {
		println('Usage: source-tools clock|ext2-mmap|private-fixture|private-install INPUT OUTPUT\n       source-tools m1-kernel OUTPUT\n       source-tools test-directory COMPILER DIRECTORY [compiler flags...]\n       source-tools darwin-signals cxx|assertions|safety|process EXECUTABLE\n       source-tools game-bundle SOURCE BUNDLE\n       source-tools ipa BUILD_DIRECTORY Calculator|NumberTileGame\n       source-tools cpython-headers|cpython-version EXECUTABLE [INCLUDE_DIRECTORY]\n       source-tools qmp SOCKET [JSON_REQUEST...]')
		return
	}
	if args.len == 2 && args[0] == 'install-qmp' {
		compiler := os.getenv_opt('V') or { return error('set V to the qualified compiler') }
		os.mkdir_all(os.dir(args[1]))!
		work := hosttest.work_dir('', 'qmp-build-')!
		defer { hosttest.remove_work_dir(work) or {} }
		result := sourcecommand.capture_full([compiler,'-nocache','-cc','cc','-o',work+'/qmp-client',@FILE],
			os.environ(),300,16*1024*1024,cachecli.cancelled)!
		text := result.stdout + result.stderr
		if result.status != 0 || ['retrying with',': fn ','V panic:','runtime error:','ERROR: AddressSanitizer'].any(text.contains(it)) { return error('QMP frontend build failed\n'+text) }
		os.chmod(work+'/qmp-client',0o755)!
		// Copy into an adjacent private staging directory so final rename also
		// works when the caller's output lives on another filesystem.
		mut pattern := (os.dir(args[1])+'/.qmp-build.XXXXXX\x00').bytes()
		if C.mkdtemp(pattern.data) == unsafe {nil} { return os.error_posix() }
		adjacent := pattern.bytestr().all_before('\x00')
		defer { hosttest.remove_work_dir(adjacent) or {} }
		os.cp(work+'/qmp-client',adjacent+'/qmp-client')!
		os.chmod(adjacent+'/qmp-client',0o755)!
		os.rename(adjacent+'/qmp-client',args[1])!
		return
	}
	if args.len == 3 && args[0] == 'darwin-signals' { hostfixture.signals(args[1], args[2], cachecli.cancelled)!; return }
	if args.len == 3 && args[0] == 'game-bundle' { hostfixture.game_bundle(args[1], args[2])!; return }
	if args.len == 3 && args[0] == 'ipa' { hostfixture.ipa(args[1], args[2])!; return }
	if args.len in [2, 3] && args[0] in ['cpython-headers', 'cpython-version'] {
		include_dir := if args.len == 3 { args[2] } else { os.getenv('VINIX_CPYTHON_INCLUDE') }
		println(if args[0] == 'cpython-headers' { hostfixture.cpython_headers(args[1], include_dir)! } else { hostfixture.cpython_version(args[1], include_dir)! })
		return
	}
	if args.len >= 3 && args[0] == 'test-directory' {
		run_tests(args[1], args[2], args[3..])!
		return
	}
	if args.len == 2 && args[0] == 'm1-kernel' {
		os.write_file_array(args[1], sourcefixture.m1_kernel())!
		return
	}
	if args.len != 3 { return error('source-tools requires OPERATION INPUT OUTPUT') }
	text := sourcefixture.read(args[1])!
	match args[0] {
		'clock' { os.write_file(args[2], sourcefixture.clock(text)!)! }
		'ext2-mmap' { os.write_file(args[2], sourcefixture.ext2_mmap(text)!)! }
		'private-fixture' {
			fixture, tests := sourcefixture.private_fixture(text)!
			os.write_file(args[2] + '/fixture.v', fixture)!
			os.write_file(args[2] + '/source_test.v', tests)!
		}
		'private-install' {
			paging := sourcefixture.read(os.dir(args[1]) + '/paging.v')!
			os.write_file(args[2], sourcefixture.private_install(text, paging,
				os.getenv('VINIX_FILE_PAGES_HOST') == '1', os.getenv('VINIX_PAGING_HOST') == '1')!)!
		}
		else { return error('unknown source-tools operation: ' + args[0]) }
	}
}

fn run_tests(compiler string, directory string, flags []string) ! {
	mut tests := os.ls(directory)!.filter(it.ends_with('_test.v') && os.is_file(directory + '/' + it))
	tests.sort()
	if tests.len == 0 { return error('no V tests in ' + directory) }
	mut failed := []string{}
	for name in tests {
		path := directory + '/' + name
		result := sourcecommand.capture_full([compiler, ...flags, path], os.environ(), 300,
			16 * 1024 * 1024, cachecli.cancelled)!
		print(result.stdout)
		eprint(result.stderr)
		text := result.stdout + result.stderr
		if result.status != 0 || ['retrying with', ': fn ', 'V panic:', 'runtime error:', 'ERROR: AddressSanitizer'].any(text.contains(it)) {
			failed << path
		}
	}
	if failed.len != 0 { return error('V host tests failed: ' + failed.join(', ')) }
	println('PASS ' + tests.len.str() + ' V host test files')
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	if os.args.len >= 3 && os.args[1] == 'qmp' {
		result := qmpclient.batch(os.args[2],os.args[3..],0,cachecli.cancelled) or {
			eprintln(err.msg())
			guard.close()
			exit(if cachecli.cancelled() {cachecli.interrupt_status()} else {1})
		}
		if result.print_error { eprintln(result.message) }
		guard.close()
		exit(result.status)
	}
	run(os.args[1..]) or {
		eprintln(err.msg())
		exit(if cachecli.cancelled() { cachecli.interrupt_status() } else { 1 })
	}
}
