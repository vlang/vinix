// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

const helper = '/usr/local/bin/vinix-art-source-generators'
const interpreter = '/usr/local/bin/vinix-art-mterp'
const compiler_memory_flags = '-g0 --param=ggc-min-expand=10 --param=ggc-min-heapsize=16384'
const paths = ['build/core/main.mk', 'build/core/definitions.mk', 'build/core/cleanspec.mk',
	'build/core/dumpvar.mk', 'build/core/post_clean.mk', 'art/runtime/Android.mk', 'art/compiler/Android.mk',
	'art/dex2oat/Android.mk', 'art/libartbase/Android.mk', 'art/libdexfile/Android.mk',
	'art/build/Android.common_build.mk']
const base_paths = ['art/libartbase/base/globals.h', 'art/libartbase/base/safe_copy.cc',
	'art/libartbase/arch/instruction_set.h', 'art/runtime/thread.cc',
	'art/runtime/monitor_pool.h', 'libcore/luni/src/main/native/Register.cpp']

fn replace_exact(input string, old string, new string, count int) !string {
	if input.count(old) != count { return error('expected ${count} occurrences of ' + old) }
	return input.replace(old, new)
}

fn rewrite(path string, input string) !string {
	mut text := input
	if path in ['build/core/main.mk', 'build/core/definitions.mk', 'build/core/cleanspec.mk'] {
		text = replace_exact(text, 'build/tools/findleaves.py ', helper + ' find-leaves ', 1)!
	} else if path == 'build/core/dumpvar.mk' {
		text = replace_exact(text, 'python3 -c "import platform; print(platform.platform())"',
			helper + ' platform', 1)!
	} else if path == 'build/core/post_clean.mk' {
		text = replace_exact(text, 'build/tools/diff_package_overlays.py ', helper + ' package-overlays ', 1)!
	} else if path == 'art/build/Android.common_build.mk' {
		// Deployed libraries are stripped. Keep optimization and runtime macros,
		// while omitting compiler debug metadata that exceeds the retained RSS cap.
		text = replace_exact(text, '-ggdb3', compiler_memory_flags, 1)!
	} else {
		text = replace_exact(text, 'art/tools/generate_operator_out.py ', helper + ' operators ', 1)!
		if path in ['art/runtime/Android.mk', 'art/compiler/Android.mk', 'art/dex2oat/Android.mk'] {
			text = replace_exact(text, 'art/tools/cpp-define-generator/make_header.py ',
				helper + ' asm-header ', 1)!
		}
		if path == 'art/runtime/Android.mk' {
			for arch in ['arm', 'arm64', 'mips', 'mips64', 'x86', 'x86_64'] {
				old := 'art/runtime/interpreter/mterp/gen_mterp.py $$@ $(LOCAL_PATH)/$(libart_mterp.${arch}_SRCS)'
				new := interpreter + ' art/libdexfile/dex/dex_instruction_list.h $(LOCAL_PATH)/$(libart_mterp.${arch}_SRCS) > $$@'
				text = replace_exact(text, old, new, 1)!
			}
		}
	}
	// Java-layer checking belongs to the unused Java compilation recipe. Keep
	// that conditional untouched; this overlay supports native ARM64 ART only.
	audited := if path == 'build/core/definitions.mk' {
		text.replace('build/tools/java-layers.py ', '')
	} else { text }
	if text == input || audited.contains('.py ') || audited.contains('python3 -c') {
		return error('unconverted generator command in ' + path)
	}
	return text
}

fn digest(text string) string { return sha256.sum(text.bytes()).hex() }

fn check_applied(source string, base string, make_tree string, oat string, output string) ! {
	mut expected := map[string]string{}
	for path in base_paths {
		expected[path] = base + '/' + path
	}
	for path in paths { expected[path] = make_tree + '/' + path }
	expected['art/runtime/oat_file_assistant.cc'] = oat
	mut names := expected.keys()
	names.sort()
	mut records := []map[string]string{}
	for path in names {
		actual := os.read_file(source + '/' + path)!
		wanted := os.read_file(expected[path])!
		if actual != wanted { return error('applied ART input differs: ' + path) }
		records << {'path': path, 'sha256': digest(actual), 'expected': os.real_path(expected[path])}
	}
	os.mkdir(output)!
	os.write_file(output + '/applied-inputs.json', json2.encode(records, prettify: true) + '\n')!
	println('ART-APPLIED-INPUTS-PASS files=${records.len} ABI/lifetime, imageless guard and V Makefiles')
}

fn prepare(input string, output string) ! {
	// Validate every input before creating output. Retain source and only emit
	// an overlay; applying to the native tree is a separate checked build step.
	mut originals := map[string]string{}
	mut modified := map[string]string{}
	for path in paths {
		source := input + '/' + path
		if os.is_link(source) || os.file_size(source) > 1024 * 1024 {
			return error('invalid bounded Makefile: ' + path)
		}
		originals[path] = os.read_file(source)!
		modified[path] = rewrite(path, originals[path])!
	}
	os.mkdir(output)!
	mut patch := ''
	mut records := []map[string]string{}
	for path in paths {
		target := output + '/tree/' + path
		os.mkdir_all(os.dir(target))!
		os.write_file(target, modified[path])!
		diff := os.exec(['/usr/bin/diff', '-u', '--label', 'a/' + path, '--label', 'b/' + path,
			input + '/' + path, target])
		if diff.exit_code != 1 || diff.output.len == 0 || diff.output.len > 65536 {
			return error('bounded Makefile diff failed: ' + path)
		}
		patch += diff.output
		if path == 'art/build/Android.common_build.mk' {
			os.write_file(output + '/release-no-debug.patch', diff.output)!
			// An incremental build may already have the debug-only change. Emit
			// its exact transition too; never reverse or fuzz an applied patch.
			prior := output + '/debug-metadata-only.mk'
			os.write_file(prior, originals[path].replace('-ggdb3', '-g0'))!
			delta := os.exec(['/usr/bin/diff', '-u', '--label', 'a/' + path,
				'--label', 'b/' + path, prior, target])
			if delta.exit_code != 1 { return error('compiler-memory diff failed') }
			os.write_file(output + '/compiler-memory.patch', delta.output)!
		}
		if os.read_file(input + '/' + path)! != originals[path]
			|| os.read_file(target)! != modified[path] { return error('Makefile changed during preparation') }
		records << {'path': path, 'input_sha256': digest(originals[path]), 'output_sha256': digest(modified[path])}
	}
	os.write_file(output + '/v-generators.patch', patch)!
	os.write_file(output + '/inputs.json', json2.encode(records, prettify: true) + '\n')!
	os.write_file(output + '/patch.sha256', digest(patch) + '  v-generators.patch\n')!
	// Preserve the production recipe's native 16-KiB ABI flags in a V-generated
	// buildspec. The build receipt must retain this file and emitted C++ argv.
	buildspec := 'COMMON_GLOBAL_CFLAGS += -DART_PAGE_SIZE=16384\n' +
		'COMMON_GLOBAL_CPPFLAGS += -DART_PAGE_SIZE=16384\n'
	os.write_file(output + '/art16k-buildspec.mk', buildspec)!
	os.write_file(output + '/buildspec.sha256', digest(buildspec) + '  art16k-buildspec.mk\n')!
	println('ART-GENERATOR-OVERLAY-PASS files=${paths.len}; native ARM64 build required')
}

fn selftest(input string, output string) ! {
	os.mkdir(output)!
	prepare(input, output + '/overlay')!
	if _ := prepare(input, output + '/overlay') { return error('existing output accepted') }
	for path in paths {
		source := os.read_file(input + '/' + path)!
		changed := rewrite(path, source)!
		if _ := rewrite(path, changed) { return error('repeated rewrite accepted') }
		if _ := rewrite(path, '') { return error('missing command accepted') }
		if _ := rewrite(path, source + source) { return error('duplicated commands accepted') }
		os.mkdir_all(os.dir(output + '/apply/' + path))!
		os.write_file(output + '/apply/' + path, source)!
	}
	for dry in [true, false] {
		mut args := ['/usr/bin/patch', '--batch', '--fuzz=0', '-p1', '-d', output + '/apply',
			'-i', output + '/overlay/v-generators.patch']
		if dry { args << '--dry-run' }
		if os.system_args(args) != 0 { return error('Makefile patch failed exact application') }
	}
	for path in paths {
		if os.read_file(output + '/apply/' + path)! != os.read_file(output + '/overlay/tree/' + path)! {
			return error('Makefile patch readback differs')
		}
	}
	os.mkdir_all(output + '/compiler-apply/art/build')!
	os.cp(output + '/overlay/debug-metadata-only.mk', output + '/compiler-apply/art/build/Android.common_build.mk')!
	for dry in [true, false] {
		mut args := ['/usr/bin/patch', '--batch', '--forward', '--fuzz=0', '-p1',
			'-d', output + '/compiler-apply', '-i', output + '/overlay/compiler-memory.patch']
		if dry { args << '--dry-run' }
		if os.system_args(args) != 0 { return error('compiler-memory transition failed exact application') }
	}
	if os.read_file(output + '/compiler-apply/art/build/Android.common_build.mk')!
		!= os.read_file(output + '/overlay/tree/art/build/Android.common_build.mk')! {
		return error('compiler-memory transition readback differs')
	}
	// Execute the exact rewritten ARM64 rule through Make's eval expansion.
	// printf records the argv; real generator behavior is checked separately.
	runtime := os.read_file(output + '/overlay/tree/art/runtime/Android.mk')!
	start := runtime.index('libart_mterp.arm64_SRCS') or { return error('ARM64 rule missing') }
	end := runtime[start..].index('\nendef') or { return error('ARM64 rule terminator missing') }
	block := runtime[start..start + end + 6].replace(interpreter, r"/usr/bin/printf '%s\n'")
	fixture := output + '/make'
	os.mkdir_all(fixture + '/art/runtime/interpreter/mterp/arm64')!
	os.mkdir_all(fixture + '/generated')!
	for name in ['a.S', 'b.S'] {
		os.write_file(fixture + '/art/runtime/interpreter/mterp/arm64/' + name, '# input\n')!
	}
	makefile := 'LOCAL_PATH := art/runtime\nlocal-generated-sources-dir = generated\n' +
		'transform-generated-source = $(PRIVATE_CUSTOM_TOOL)\n' + block +
		'\n$(eval $(libart_mterp.arm64_GENERATED_SOURCES))\nall: $(libart_mterp.arm64_GEN)\n'
	os.write_file(fixture + '/Makefile', makefile)!
	make := os.exec(['/usr/bin/make', '-C', fixture, 'all'])
	os.write_file(fixture + '/make.log', make.output)!
	if make.exit_code != 0 { return error('rewritten ARM64 Make rule failed: ' + make.output) }
	expected := 'art/libdexfile/dex/dex_instruction_list.h\n' +
		'art/runtime/interpreter/mterp/arm64/a.S\nart/runtime/interpreter/mterp/arm64/b.S\n'
	if os.read_file(fixture + '/generated/mterp_arm64.S')! != expected {
		return error('Make expansion, globbing or output redirection differs')
	}
	for path in base_paths {
		os.mkdir_all(os.dir(output + '/base/' + path))!
		os.mkdir_all(os.dir(output + '/apply/' + path))!
		text := 'audited source fixture for ' + path + '\n'
		os.write_file(output + '/base/' + path, text)!
		os.write_file(output + '/apply/' + path, text)!
	}
	os.write_file(output + '/oat.expected', 'audited imageless guard fixture\n')!
	os.cp(output + '/oat.expected', output + '/apply/art/runtime/oat_file_assistant.cc')!
	check_applied(output + '/apply', output + '/base', output + '/overlay/tree',
		output + '/oat.expected', output + '/applied-inputs')!
	for i, path in ['art/runtime/monitor_pool.h', 'build/core/definitions.mk', 'art/runtime/oat_file_assistant.cc',
		'art/build/Android.common_build.mk'] {
		file := output + '/apply/' + path
		original := os.read_file(file)!
		os.write_file(file, original + 'source drift\n')!
		rejected := output + '/rejected-${i}'
		if _ := check_applied(output + '/apply', output + '/base', output + '/overlay/tree',
			output + '/oat.expected', rejected) { return error('applied source drift accepted: ' + path) }
		if os.exists(rejected) { return error('rejected input published a receipt') }
		os.write_file(file, original)!
	}
	println('ART-GENERATOR-OVERLAY-CHECK-PASS overwrite, drift, duplicate, zero-fuzz dry-run, apply and readback')
}

fn main() {
	if os.args.len == 7 && os.args[1] == '--check-applied' {
		check_applied(os.args[2], os.args[3], os.args[4], os.args[5], os.args[6]) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len == 4 && os.args[1] == '--self-test' {
		selftest(os.abs_path(os.args[2]), os.abs_path(os.args[3])) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len != 3 { eprintln('usage: art-generator-overlay SOURCE_ROOT FRESH_OUTPUT | --self-test SOURCE_ROOT FRESH_OUTPUT'); exit(2) }
	prepare(os.abs_path(os.args[1]), os.abs_path(os.args[2])) or { eprintln(err); exit(1) }
}
