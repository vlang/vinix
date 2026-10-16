module main
import json2
import os
import time
struct Result { name string code int seconds f64 }
fn run(name string, program string, args []string, work string) !Result {
	mut child := os.new_process(program); child.set_args(args); child.set_redirect_stdio_merged()
	start := time.now(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + name + '.txt', output)!
	if code != 0 || output.contains(': fn test_') || output.contains('V panic:') { return error(name + ': status ' + code.str()) }
	println('PASS ' + name)
	return Result{ name: name, code: code, seconds: f64(time.since(start).milliseconds()) / 1000.0 }
}
fn check() ! {
	work := os.real_path(os.dir(@FILE)); v := os.real_path('build/package-release-work/v-toolchain/v')
	os.setenv('V', v, true); os.setenv('VFLAGS', '-nocache', true)
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true); os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	flags := ['-keepc', '-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|.|tools/accounts']
	mut results := []Result{}
	for name in ['protocol', 'streams', 'ownership', 'memory', 'asan-streams', 'asan-ownership'] {
		source := if name == 'memory' { 'ownership' } else { name.replace('asan-', '') }
		extra := if name == 'memory' { ['-d', 'track_heap'] } else if name.starts_with('asan-') {
			['-cc', 'clang', '-d', 'no_segfault_handler', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined']
		} else { []string{} }
		results << run(name + '-compile', v, [...flags, ...extra, '-o', work + '/' + name, 'tools/packages/pkglaunch/' + source + '_test.v'], work)!
		results << run(name + '-run', work + '/' + name, [], work)!
	}
	os.write_file(work + '/host.json', json2.encode(results) + '\n')!
}
fn main() { check() or { eprintln(err); exit(1) } }
