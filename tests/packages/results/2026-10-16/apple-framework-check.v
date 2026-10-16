module main
import json2
import os
import time
struct Check { name string status int seconds f64 }
fn task(name string, argv []string, work string) !Check {
	mut child := os.new_process(argv[0]); child.set_args(argv[1..]); child.set_redirect_stdio_merged()
	start := time.now(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + name + '.txt', output)!
	if code != 0 { print(output) }
	assert code == 0, name
	println(name + ' PASS')
	return Check{ name: name, status: code, seconds: f64(time.since(start).milliseconds()) / 1000.0 }
}
fn main() {
	work := os.real_path(os.dir(@FILE)); v := os.real_path('build/package-release-work/v-toolchain/v')
	os.setenv('V', v, true); os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true); os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	flags := ['-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|.|compat/ios|tools/accounts|tests/hardware-platform']
	mut results := []Check{}
	if os.args.len == 1 {
	results << task('fixture-build', [v, ...flags, '-o', work + '/fixture-test', 'tests/packages/applefixture/framework_test.v'], work)!
	results << task('fixture-run', [work + '/fixture-test'], work)!
	results << task('controller-build', [v, ...flags, '-o', work + '/controller', 'tests/packages/apple-runtime-check.v'], work)!
	results << task('temporary-directory-build', [v, '-nocache', '-enable-globals', '-gc', 'none', '-d', 'no_backtrace',
		'-path', '@vlib|' + os.real_path('compat/ios') + '|@vmodules', '-o', work + '/temp-test', 'compat/ios/runner/ns_temp_directory_test.v'], work)!
	results << task('temporary-directory-run', [work + '/temp-test'], work)!
	} else {
		assert os.args == [os.args[0], '--sanitizer']
		results = json2.decode[[]Check](os.read_file(work + '/host.json')!)!
		assert results.len == 5
	}
	results << task('sanitizer-build', [v, '-nocache', '-enable-globals', '-gc', 'none', '-d', 'no_backtrace',
		'-cc', 'clang', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined',
		'-path', '@vlib|' + os.real_path('compat/ios') + '|@vmodules', '-o', work + '/temp-sanitize', 'compat/ios/runner/ns_temp_directory_test.v'], work)!
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	results << task('sanitizer-run', [work + '/temp-sanitize'], work)!
	os.write_file(work + '/host.json', json2.encode(results) + '\n')!
}
