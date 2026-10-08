module main

import os

#include <stdlib.h>

fn C.mkdtemp(&char) &char

fn execute(arguments []string, environment map[string]string) int {
	mut process := os.new_process(arguments[0])
	defer { process.close() }
	process.set_args(arguments[1..])
	process.set_environment(environment)
	process.run()
	process.wait()
	status := process.code
	return status
}

fn run() int {
	mut template := (os.join_path(os.temp_dir(), 'vinix-android-launcher-XXXXXX') + '\x00').bytes()
	assert !isnil(C.mkdtemp(&char(template.data)))
	directory := template[..template.len - 1].bytestr()
	defer { os.rmdir_all(directory) or { panic(err) } }
	source := os.dir(@FILE)
	loader := os.join_path(directory, 'loader')
	test := os.join_path(directory, 'launcher-test')
	mut environment := os.environ()
	environment['VEXE'] = @VEXE
	for input, output in {
		os.join_path(source, 'launcherfixture/loader.v'): loader
		os.join_path(source, 'launcher_fixture_test.v'):  test
	} {
		status := execute([@VEXE, '-d', 'use_bundled_libgc', '-cc', 'clang', '-o', output, input],
			environment)
		if status != 0 { return status }
	}
	environment['VINIX_ANDROID_FIXTURE_LOADER'] = loader
	status := execute([test], environment)
	if status != 0 { return status }
	println('Android launcher: 9 native launcher cases and concurrent output check completed')
	return 0
}

fn main() { exit(run()) }
