module main
import os
fn main() {
	work := os.real_path(os.dir(@FILE)); phase := os.args[1]
	compiler := os.real_path('build/package-release-work/v-toolchain/v')
	os.setenv('V_MACOS_V3_NO_FALLBACK', '1', true); os.setenv('V_C_ERROR_BUG_REPORT_DISABLED', '1', true)
	mut source := 'tools/packages/pkglaunch/client_ownership_test.v'
	mut flags := ['-keepc', '-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-d', 'track_heap']
	if phase == 'baseline' {
		base := work + '/baseline/pkglaunch'
		os.mkdir_all(base)!
		if !os.is_file(base + '/client.v') {
			for name in os.ls('tools/packages/pkglaunch')! { if name.ends_with('.v') && !name.ends_with('_test.v') { os.cp('tools/packages/pkglaunch/' + name, base + '/' + name)! } }
		}
		os.mkdir_all(work + '/baseline/tools/packages/pkgadmin')!
		for name in ['protocol.v', 'socket.c.v']! {
			old := os.exec(['git', 'show', '4f038484b:tools/packages/pkgadmin/' + name])
			assert old.exit_code == 0
			os.write_file(work + '/baseline/tools/packages/pkgadmin/' + name, old.output)!
		}
		os.write_file(work + '/baseline/v.mod', "Module { name: 'launch-client-baseline' }\n")!
		os.write_file(base + '/client_ownership_test.v', os.read_file(source)!.replace('@VMODROOT/../../../desktop/tools/tests/heap_tracker.h', os.real_path('desktop/tools/tests/heap_tracker.h')))!
		source = base + '/client_ownership_test.v'; flags << ['-d', 'launch_client_baseline']
	}
	if phase == 'asan' {
		flags = ['-keepc', '-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-cc', 'clang', '-d', 'no_segfault_handler',
			'-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined']
		os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	}
	if phase == 'comparison' { flags << ['-d', 'launch_client_baseline'] }
	flags << ['-path', '@vlib|@vmodules|.|tools/accounts', '-o', work + '/' + phase + '-fixture', source]
	mut child := os.new_process(compiler); child.set_args(flags); child.set_redirect_stdio_merged(); child.run()
	output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + phase + '-compile.txt', output)!
	if code != 0 { print(output); exit(code) }
	result := os.exec([work + '/' + phase + '-fixture'])
	os.write_file(work + '/' + phase + '-run.txt', result.output)!
	print(result.output); exit(result.exit_code)
}
