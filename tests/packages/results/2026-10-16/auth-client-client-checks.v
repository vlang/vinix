module main
import os
fn check() ! {
	work := os.real_path(os.dir(@FILE))
	phase := os.args[1]
	compiler := os.real_path('build/package-release-work/v-toolchain/v')
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true)
	os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	mut source := 'tools/accounts/authclient/ownership_test.v'
	mut flags := ['-keepc', '-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-d', 'track_heap']
	if phase == 'comparison' { flags << ['-d', 'auth_client_baseline'] }
	if phase == 'asan' {
		flags = ['-keepc', '-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-cc', 'clang', '-d', 'no_segfault_handler',
			'-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined']
		os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	}
	if phase == 'baseline' {
		os.mkdir_all(work + '/baseline/authclient')!
		if !os.is_file(work + '/baseline/authclient/client.v') { os.cp('tools/accounts/authclient/client.v', work + '/baseline/authclient/client.v')! }
		test_source := os.read_file(source)!
		os.write_file(work + '/baseline/authclient/ownership_test.v', test_source.replace('@VMODROOT/../../../desktop/tools/tests/heap_tracker.h', os.real_path('desktop/tools/tests/heap_tracker.h')))!
		os.write_file(work + '/baseline/v.mod', "Module { name: 'auth-client-baseline' }\n")!
		source = work + '/baseline/authclient/ownership_test.v'
		flags << ['-d', 'auth_client_baseline']
	}
	flags << ['-path', '@vlib|@vmodules|.|tools/accounts', '-o', work + '/' + phase + '-fixture', source]
	mut child := os.new_process(compiler); child.set_args(flags); child.set_redirect_stdio_merged(); child.run()
	output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + phase + '-compile.txt', output)!
	if code != 0 { print(output); exit(code) }
	result := os.exec([work + '/' + phase + '-fixture'])
	os.write_file(work + '/' + phase + '-run.txt', result.output)!
	print(result.output); exit(result.exit_code)
}
fn main() { check() or { eprintln(err); exit(1) } }
