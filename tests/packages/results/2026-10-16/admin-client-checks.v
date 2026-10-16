module main
import json2
import os
import time
struct Result { name string code int seconds f64 }
fn task(name string, program string, args []string, work string) !Result {
	mut child := os.new_process(program); child.set_args(args); child.set_redirect_stdio_merged()
	started := time.now(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + name + '.txt', output)!
	if code != 0 || output.contains(': fn test_') || output.contains('V panic:') { print(output); return error(name + ' failed: ' + code.str()) }
	println(name + ' PASS')
	return Result{ name: name, code: code, seconds: f64(time.since(started).milliseconds()) / 1000.0 }
}
fn main() {
	work := os.real_path(os.dir(@FILE)); phase := os.args[1]; v := os.real_path('build/package-release-work/v-toolchain/v')
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true); os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	mut source := 'tools/packages/pkgadmin/client_ownership_test.v'
	mut extra := ['-d', 'track_heap']
	if phase == 'baseline' {
		source = work + '/baseline/pkgadmin/client_ownership_test.v'
		os.write_file(source, os.read_file('tools/packages/pkgadmin/client_ownership_test.v')!.replace('@VMODROOT/../../../desktop/tools/tests/heap_tracker.h', os.real_path('desktop/tools/tests/heap_tracker.h')))!
		extra << ['-d', 'admin_client_baseline']
	} else if phase == 'asan' {
		extra = ['-cc', 'clang', '-d', 'no_segfault_handler', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined']
	}
	flags := ['-keepc', '-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|.|tools/accounts']
	mut results := []Result{}
	results << task(phase + '-compile', v, [...flags, ...extra, '-o', work + '/' + phase + '-fixture', source], work)!
	results << task(phase + '-run', work + '/' + phase + '-fixture', [], work)!
	os.write_file(work + '/results-' + phase + '.json', json2.encode(results) + '\n')!
}
