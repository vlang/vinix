module main
import json2
import os
import time
struct Check { name string seconds f64 }
fn task(name string, argv []string, work string) !Check {
	mut child := os.new_process(argv[0]); child.set_args(argv[1..]); child.set_redirect_stdio_merged()
	start := time.now(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + name + '.txt', output)!
	assert code == 0, name + ': ' + output
	println(name + ' PASS')
	return Check{ name: name, seconds: f64(time.since(start).milliseconds()) / 1000.0 }
}
fn main() {
	work := os.real_path(os.dir(@FILE)); v := os.real_path('build/package-release-work/v-toolchain/v')
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true); os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	flags := ['-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|.|tools/accounts']
	mut results := []Check{}
	for name in ['apple_context', 'context', 'launch_ownership'] {
		binary := work + '/' + name + '-final'
		heap := if name == 'launch_ownership' { ['-d', 'track_heap'] } else { []string{} }
		results << task(name + '-compile', [v, ...flags, ...heap, '-o', binary, 'tools/packages/pkgcore/' + name + '_test.v'], work)!
		results << task(name + '-run', [binary], work)!
	}
	results << task('sanitizer-compile', [v, ...flags, '-cc', 'clang', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer',
		'-ldflags', '-fsanitize=address,undefined', '-o', work + '/apple-sanitize', 'tools/packages/pkgcore/apple_context_test.v'], work)!
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	results << task('sanitizer-run', [work + '/apple-sanitize'], work)!
	os.write_file(work + '/host.json', json2.encode(results) + '\n')!
}
