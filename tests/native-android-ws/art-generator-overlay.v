// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

const helper = '/usr/local/bin/vinix-art-source-generators'
const interpreter = '/usr/local/bin/vinix-art-mterp'
const paths = ['build/core/main.mk', 'build/core/definitions.mk', 'build/core/cleanspec.mk',
	'build/core/dumpvar.mk', 'build/core/post_clean.mk', 'art/runtime/Android.mk', 'art/compiler/Android.mk',
	'art/dex2oat/Android.mk', 'art/libartbase/Android.mk', 'art/libdexfile/Android.mk']

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
		if os.read_file(input + '/' + path)! != originals[path]
			|| os.read_file(target)! != modified[path] { return error('Makefile changed during preparation') }
		records << {'path': path, 'input_sha256': digest(originals[path]), 'output_sha256': digest(modified[path])}
	}
	os.write_file(output + '/v-generators.patch', patch)!
	os.write_file(output + '/inputs.json', json2.encode(records, prettify: true) + '\n')!
	os.write_file(output + '/patch.sha256', digest(patch) + '  v-generators.patch\n')!
	println('ART-GENERATOR-OVERLAY-PASS files=10; native ARM64 build required')
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
	println('ART-GENERATOR-OVERLAY-CHECK-PASS overwrite, drift, duplicate, zero-fuzz dry-run, apply and readback')
}

fn main() {
	if os.args.len == 4 && os.args[1] == '--self-test' {
		selftest(os.abs_path(os.args[2]), os.abs_path(os.args[3])) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len != 3 { eprintln('usage: art-generator-overlay SOURCE_ROOT FRESH_OUTPUT | --self-test SOURCE_ROOT FRESH_OUTPUT'); exit(2) }
	prepare(os.abs_path(os.args[1]), os.abs_path(os.args[2])) or { eprintln(err); exit(1) }
}
