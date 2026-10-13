// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import crypto.sha256
import encoding.binary
import json2
import os
import sourcecommand

fn command(argv []string, environment map[string]string, log string) ! {
	result := sourcecommand.capture_full(argv, environment, -1, 32 * 1024 * 1024, cachecli.cancelled)!
	text := result.stdout + result.stderr
	os.write_file(log, text)!
	if result.status != 0 || ['retrying with', 'V panic:', 'runtime error:', 'ERROR: AddressSanitizer'].any(text.contains(it)) {
		eprint(text)
		return error('native CPython smoke build failed: ' + log)
	}
}

fn elf(path string, machine u16, interpreter string) ! {
	bytes := os.read_bytes(path)!
	if bytes.len < 64 || bytes[..6] != [u8(127), `E`, `L`, `F`, 2, 1] || binary.little_endian_u16_at(bytes, 18) != machine {
		return error('wrong native smoke ELF architecture')
	}
	if interpreter == '' { return }
	start := binary.little_endian_u64_at(bytes, 32)
	width := binary.little_endian_u16_at(bytes, 54)
	count := binary.little_endian_u16_at(bytes, 56)
	if width != 56 || start > u64(bytes.len) || u64(count) * width > u64(bytes.len) - start {
		return error('invalid smoke program headers')
	}
	mut found := false
	for index in 0 .. int(count) {
		at := int(start) + index * int(width)
		if binary.little_endian_u32_at(bytes, at) != 3 { continue }
		offset, size := binary.little_endian_u64_at(bytes, at + 8), binary.little_endian_u64_at(bytes, at + 32)
		if offset > u64(bytes.len) || size > u64(bytes.len) - offset || size != u64(interpreter.len + 1) {
			return error('invalid smoke interpreter')
		}
		if bytes[int(offset)..int(offset + size)].bytestr() != interpreter + '\x00' {
			return error('wrong smoke dynamic interpreter')
		}
		found = true
	}
	if !found { return error('native smoke must link against the shared musl runtime') }
}

fn parent(path string) string {
	if !path.contains('/') { return '.' }
	prefix := path.all_before_last('/')
	return if prefix == '' { '/' } else { prefix }
}

fn remove(path string) ! {
	if os.is_link(path) || os.is_file(path) {
		os.rm(path)!
		return
	}
	for name in os.ls(path)! { remove(path + '/' + name)! }
	os.rmdir(path)!
}

fn build() ! {
	args := cachecli.arguments(os.args[1..], ['--arch', '--sysroot', '--libc', '--cc', '--output'], [], [], 0, 0,
		'Usage: python-smoke --output ELF [--arch aarch64|x86_64 --sysroot DIR --libc SHARED_MUSL --cc CLANG]\nGenerate and link the native V CPython smoke controller; no interpreter is executed.')!
	output := args.value('--output', '')
	if output == '' { return error_with_code('--output is required', 2) }
	arch := args.value('--arch', os.getenv_opt('VINIX_ARCH') or { 'aarch64' })
	if arch !in ['aarch64', 'x86_64'] {
		return error_with_code('arch must be aarch64 or x86_64', 2)
	}
	root := os.real_path(os.dir(@FILE) + '/..')
	compiler := os.getenv_opt('V') or { return error('set V to the qualified compiler, or use build-support/python-smoke') }
	arm := arch == 'aarch64'
	machine := if arm { u16(183) } else { u16(62) }
	sdk := args.value('--sysroot', if arm {
		os.getenv_opt('VINIX_AARCH64_SYSROOT') or { root + '/build-aarch64-userland/sysroot' }
	} else {
		os.getenv_opt('VINIX_AMD64_SYSROOT') or { root + '/build-amd64-desktop/initramfs-root' }
	})
	lib := sdk + if arm { '/lib' } else { '/usr/lib' }
	interpreter := '/lib/ld-musl-' + arch + '.so.1'
	default_runtime := os.getenv_opt('VINIX_PYTHON_MUSL') or {
		base := if arm { root + '/build-aarch64-userland/staging' } else { sdk }
		base + interpreter
	}
	runtime := args.value('--libc', default_runtime)
	cc := args.value('--cc', os.getenv_opt('CC') or { 'clang' })
	for path in [sdk + if arm { '/include' } else { '/usr/include' }, lib + '/crt1.o', lib + '/crti.o',
		lib + '/crtn.o', runtime] {
		if !os.exists(path) { return error('missing native smoke SDK input: ' + path) }
	}
	elf(runtime, machine, '')!
	mut gcc := lib
	if !arm {
		base := lib + '/gcc/x86_64-alpine-linux-musl'
		versions := os.ls(base)!.sorted()
		if versions.len == 0 { return error('missing amd64 GCC support archive') }
		gcc = base + '/' + versions.last()
	}
	if !os.is_file(gcc + '/libgcc.a') { return error('missing compiler support archive') }
	os.mkdir_all(parent(output))!
	mut pattern := (parent(output) + '/.python-smoke.XXXXXX\x00').bytes()
	if C.mkdtemp(pattern.data) == unsafe { nil } { return os.error_posix() }
	work := pattern.bytestr().all_before('\x00')
	mut completed := false
	defer { if completed {
		remove(work) or {}
	} else {
		eprintln('Retained native build evidence: ' + work)
	} }
	mut environment := os.environ()
	environment['V_C_ERROR_BUG_REPORT_DISABLED'] = '1'
	environment['V_MACOS_V3_NO_FALLBACK'] = '1'
	source := work + '/smoke.c'
	generate := [compiler, '-nocache', '-os', 'linux', '-arch', if arm { 'arm64' } else { 'amd64' },
		'-gc', 'none', '-d', 'no_segfault_handler', '-o', source,
		root + '/tests/native-python-smoke/main.v']
	command(generate, environment, work + '/generate.log')!
	// V's bundled cross linker lacks ARM runtimes. Use the already built musl
	// SDK explicitly after normal V Linux/architecture C generation.
	link := [cc, '--target=' + arch + '-linux-musl', '--sysroot=' + sdk, '-nostdlib', '-O2', '-pthread',
		'-fno-strict-aliasing', '-Wno-pointer-sign', '-Wno-format', '-Wno-macro-redefined',
		'-Wno-invalid-noreturn', lib + '/crt1.o', lib + '/crti.o', source, '-L' + lib, '-L' + gcc,
		'-Wl,--dynamic-linker=' + interpreter, '-fuse-ld=lld', '-o', work + '/smoke', runtime,
		'-lgcc', lib + '/crtn.o']
	command(link, environment, work + '/link.log')!
	elf(work + '/smoke', machine, interpreter)!
	os.chmod(work + '/smoke', 0o755)!
	mut inputs := []json2.Any{}
	for path in ['tests/native-python-smoke/main.v', 'tests/native-python-smoke/pysmoke/core.v',
		'tests/native-python-smoke/pysmoke/entry.v', 'build-support/cpythonapi/core.v'] {
		inputs << json2.Any({
			'path':   json2.Any(path)
			'sha256': json2.Any(sha256.sum(os.read_bytes(root + '/' + path)!).hex())
		})
	}
	manifest := json2.Any({
		'arch':              json2.Any(arch)
		'inputs':            json2.Any(inputs)
		'generate':          json2.Any(generate.map(json2.Any(it)))
		'link':              json2.Any(link.map(json2.Any(it)))
		'runtime':           json2.Any(runtime)
		'runtime_sha256':    json2.Any(sha256.sum(os.read_bytes(runtime)!).hex())
		'compiler_sha256':   json2.Any(sha256.sum(os.read_bytes(compiler)!).hex())
		'executable_sha256': json2.Any(sha256.sum(os.read_bytes(work + '/smoke')!).hex())
		'qualification':     json2.Any('Build-only; no CPython or Vinix guest executed.')
	})
	os.write_file(work + '/manifest.json', json2.encode(manifest, prettify: true) + '\n')!
	os.rename(work + '/smoke', output)!
	os.rename(work + '/manifest.json', output + '.native.json')!
	completed = true
	println('Built native V CPython smoke for ' + arch + ': ' + output)
}

fn main() {
	guard := cachecli.own_commands()
	defer { guard.close() }
	build() or {
		eprintln(err)
		exit(if cachecli.cancelled() {
			cachecli.interrupt_status()
		} else if err.code() == 2 {
			2
		} else {
			1
		})
	}
}
