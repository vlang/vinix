// SPDX-License-Identifier: GPL-2.0-or-later
// Compiler selection refuses unusable explicit inputs without falling back.
module main

import os
import perfproducer

fn check() ! {
	state := os.join_path(os.temp_dir(), 'vinix-producer-' + os.getpid().str())
	if os.exists(state) || os.is_link(state) { return error('fresh producer control state required') }
	os.mkdir(state)!
	defer { os.rmdir_all(state) or {} }
	old := os.getenv_opt('VINIX_PERF_SAMPLER_V')
	defer {
		if value := old { os.setenv('VINIX_PERF_SAMPLER_V', value, true) }
		else { os.unsetenv('VINIX_PERF_SAMPLER_V') }
	}
	compiler := os.real_path(os.executable())
	os.unsetenv('VINIX_PERF_SAMPLER_V')
	if perfproducer.sampler_compiler(compiler)! != compiler { return error('default compiler changed') }
	os.setenv('VINIX_PERF_SAMPLER_V', compiler, true)
	if perfproducer.sampler_compiler('/missing-default')! != compiler { return error('explicit compiler ignored') }
	os.symlink(compiler, state + '/alias')!
	os.write_file(state + '/plain', 'not executable')!
	os.chmod(state + '/plain', 0o600)!
	for path in ['', 'v', state, state + '/missing', state + '/plain', state + '/alias'] {
		os.setenv('VINIX_PERF_SAMPLER_V', path, true)
		perfproducer.sampler_compiler(compiler) or { continue }
		return error('unusable explicit sampler fell back: ' + path)
	}
	println('PERF PRODUCER compiler selection PASS 8 controls')
}

fn main() { check() or { eprintln(err); exit(1) } }
