// SPDX-License-Identifier: GPL-2.0-or-later
// V generation plus entry-renaming glue; no legacy C byte is edited.
module perfproducer

import crypto.sha256
import json2
import os
import hwhost

pub const legacy_sha256 = '2490bc0e69142080f52a469e241cbb37d61d0e0687a191618654a3b617b68771'

// The freestanding initializer uses the maintained host frontend. A separately
// qualified target-only compiler may emit the runtime sampler instead.
pub fn sampler_compiler(fallback string) !string {
	selected := os.getenv_opt('VINIX_PERF_SAMPLER_V') or { fallback }
	if !os.is_abs_path(selected) || selected != os.real_path(selected)
		|| !os.is_file(selected) || !os.is_executable(selected) {
		return error('canonical executable sampler compiler required: VINIX_PERF_SAMPLER_V')
	}
	return selected
}

fn compiler_environment(compiler string) map[string]string {
	return {
		'V': compiler
		'VINIX_V_COMPILER': compiler
		'VEXE': compiler
		'V_MACOS_V3_CALLER_VEXE': compiler
		'V_MACOS_V3_CALLER_VEXE_PRESENT': '1'
		'V_MACOS_V3_CALLER_VCHILD_PRESENT': '0'
		'V_MACOS_V3_NO_FALLBACK': '1'
		'V_MACOS_V3_CALLER_NO_FALLBACK': '1'
		'V_MACOS_V3_CALLER_NO_FALLBACK_PRESENT': '1'
	}
}

pub fn generate_init(compiler string, root string, directory string, arch string) !string {
	if arch !in ['aarch64', 'x86_64'] { return error('unsupported initializer architecture') }
	name := if arch == 'aarch64' { 'perfinitarm' } else { 'perfinitx86' }
	folder := if arch == 'aarch64' { 'arm-init' } else { 'x86-init' }
	source := root + '/tests/desktop-perf/' + folder + '/main.v'
	module_dir := directory + '/' + name
	output := directory + '/init.c'
	if os.exists(module_dir) || os.exists(output) { return error('initializer output must be fresh') }
	os.mkdir_all(module_dir)!
	text := os.read_file(source)!
	os.write_file(module_dir + '/core.v', text)!
	os.write_file(directory + '/init-source.v', text)!
	argv := [root + '/build-support/compile-v-module', module_dir, output, '--arch',
		if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-d', 'nofloat']
	os.write_file(directory + '/init-v.argv.json', json2.encode(argv) + '\n')!
	// find-v.sh gives V precedence over VINIX_V_COMPILER. Override both and
	// VEXE so an inherited sampler selection cannot replace this compiler.
	environment := compiler_environment(compiler)
	os.write_file(directory + '/init-v.env.json', json2.encode(environment) + '\n')!
	hwhost.run_tool(argv, environment, directory + '/init-v.log', 300)!
	return output
}

pub fn generate(compiler string, root string, directory string, arch string) !string {
	if arch !in ['aarch64', 'x86_64'] { return error('unsupported producer architecture') }
	legacy := os.read_file(root + '/tests/desktop-perf/measure.c')!
	if sha256.hexhash(legacy) != legacy_sha256 { return error('legacy operation-probe source differs') }
	for name in ['measure-v.c', 'measure-legacy.c', 'measure-combined.c', 'measure-v.argv.json', 'measure-v.env.json', 'measure-v.log'] {
		if os.exists(directory + '/' + name) || os.is_link(directory + '/' + name) {
			return error('producer output must be fresh')
		}
	}
	vfile := directory + '/measure-v.c'
	// The guest declares the native i32 handler field; os's V-int handler
	// metadata would insert a callback adapter with a different native ABI.
	mut argv := [compiler, '-backend', 'c', '-prod', '-nocache', '-enable-globals', '-os', 'linux',
		'-arch', if arch == 'aarch64' { 'arm64' } else { 'amd64' }, '-gc', 'none', '-manualfree',
		'-exclude', '@vlib/os/os_structs_sigaction_default.c.v',
		'-d', 'no_backtrace', '-d', 'no_segfault_handler', '-path', '@vlib|@vmodules|' + root + '/tests/desktop-perf']
	if arch == 'aarch64' { argv << ['-d', 'perf_slab16k'] }
	argv << ['-o', vfile, root + '/tests/desktop-perf/measure-v']
	os.write_file(directory + '/measure-v.argv.json', json2.encode(argv) + '\n')!
	// A complete frontend checkout in inherited VEXE would otherwise make an
	// older target compiler import the frontend's incompatible standard library.
	environment := compiler_environment(compiler)
	os.write_file(directory + '/measure-v.env.json', json2.encode(environment) + '\n')!
	hwhost.run_tool(argv, environment, directory + '/measure-v.log', 300)!
	copy := directory + '/measure-legacy.c'
	os.write_file(copy, legacy)!
	if sha256.hexhash(os.read_file(copy)!) != legacy_sha256 { return error('legacy probe copy differs') }
	if copy.contains_any('"\\\r\n') { return error('unsupported generated include path') }
	combined := directory + '/measure-combined.c'
	// Only preprocessor entry renaming: probe bodies and the old non-heap modes
	// remain unchanged in the same translation unit as the V observer.
	os.write_file(combined, '#define main vinix_perf_legacy_main\n#include "' + copy + '"\n#undef main\n'
		+ os.read_file(vfile)!)!
	return combined
}
