module main

import os
import json2
import time

struct Result { name string code int seconds f64 }

fn run(name string, program string, args []string, work string) !Result {
	mut child := os.new_process(program)
	child.set_args(args); child.set_redirect_stdio_merged()
	started := time.now(); child.run(); output := child.stdout_slurp(); child.wait(); code := child.code; child.close()
	os.write_file(work + '/' + name + '.txt', output)!
	if code != 0 || output.contains('V panic:') || output.contains('ERROR: AddressSanitizer') || output.contains('runtime error:') {
		return error(name + ' failed: ' + output)
	}
	println(name + ' PASS')
	return Result{ name: name, code: code, seconds: f64(time.since(started).milliseconds()) / 1000.0 }
}

fn check() ! {
	work := os.real_path(os.dir(@FILE))
	phase := os.args[1]
	v := os.real_path('build/package-release-work/v-toolchain/v')
	if phase == 'launcher' {
		mut checks := []Result{}
		binary := work + '/launcher'
		checks << run('launcher-compile', v, ['-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-path', '@vlib|@vmodules|tests/linuxkpi|.', '-o', binary, 'tests/packages/launcher-check.v'], work)!
		checks << run('launcher-run', binary, [work + '/launcher-current'], work)!
		os.write_file(work + '/launcher-results.json', json2.encode(checks) + '\n')!
		return
	}
	assert phase in ['ui', 'asan']
	stage := work + '/' + phase + '-sources-qualified'
	assert !os.exists(stage)
	os.mkdir(stage)!
	for file in os.ls('desktop')! { if file.starts_with('software_') && file.ends_with('.v') { os.cp('desktop/' + file, stage + '/' + file)! } }
	for file in os.ls('tests/packages')! { if file.starts_with('software_') && file.ends_with('_fixture.v') && file != 'software_image_fixture.v' { os.cp('tests/packages/' + file, stage + '/' + if file == 'software_fixture.v' { 'main.v' } else { file })! } }
	mut flags := ['-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-enable-globals', '-d', 'ui2_headless', '-d', 'track_heap', '-d', 'no_segfault_handler', '-cflags', '-I' + os.getwd() + '/desktop',
		'-path', '@vlib|' + os.getwd() + '|' + os.getwd() + '/tools/accounts|' + os.real_path('build/package-view-reader-work/desktop/modules') + '|@vmodules']
	if phase == 'asan' { flags << ['-cc', 'clang', '-cflags', '-fsanitize=address,undefined -fno-omit-frame-pointer', '-ldflags', '-fsanitize=address,undefined'] }
	os.setenv('ASAN_OPTIONS', 'detect_leaks=0', true); os.setenv('UBSAN_OPTIONS', 'halt_on_error=1', true)
	mut checks := []Result{}
	binary := work + '/' + phase
	checks << run(phase + '-compile', v, [...flags, '-o', binary, stage], work)!
	broker := work + '/session-broker-' + phase
	checks << run(phase + '-broker-compile', v, ['-nocache', '-no-skip-unused', '-gc', 'none', '-manualfree', '-enable-globals', '-path', '@vlib|@vmodules|.', '-o', broker, 'desktop/services/session/main.v'], work)!
	checks << run(phase + '-chooser', binary, ['deployment-chooser', broker], work)!
	checks << run(phase + '-memory', binary, ['deployment-chooser-memory'], work)!
	checks << run(phase + '-release-memory', binary, ['release-memory'], work)!
	checks << run(phase + '-navigation-memory', binary, ['deployment-navigation-memory'], work)!
	checks << run(phase + '-functional', binary, [], work)!
	os.write_file(work + '/' + phase + '-results.json', json2.encode(checks) + '\n')!
}

fn main() { check() or { eprintln(err); exit(1) } }
