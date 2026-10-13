// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import cachecli
import crypto.sha256
import encoding.binary
import json2
import os
import sourcecommand

fn checked(argv []string, log string) ! {
	r := sourcecommand.capture_full(argv,os.environ(),300,32*1024*1024,cachecli.cancelled)!
	text := r.stdout + r.stderr
	os.write_file(log,text)!
	if r.status != 0 || ['retrying with',': fn ','V panic:','runtime error:','ERROR: AddressSanitizer'].any(text.contains(it)) { return error('trimmer build failed: '+log) }
}

fn build() ! {
	if os.args.len == 2 && os.args[1] == '--help' {
		println('Usage: stage-trimmer OUTPUT\nBuild a static AArch64/Linux V CMake trimmer for the read-only KekVM share. VINIX_AARCH64_SYSROOT and CC select the existing musl SDK; no guest executes.')
		return
	}
	if os.args.len != 2 { return error('expected OUTPUT') }
	root := os.real_path(os.dir(@FILE) + '/../..')
	compiler := os.getenv_opt('V') or { return error('set V to the qualified compiler') }
	sdk := os.getenv_opt('VINIX_AARCH64_SYSROOT') or { root + '/build-aarch64-userland/staging' }
	gcc := sdk + '/usr/lib/gcc/aarch64-alpine-linux-musl/14.2.0'
	output := os.args[1]
	os.mkdir_all(os.dir(output))!
	mut pattern := (os.dir(output) + '/.trim-cmake.XXXXXX\x00').bytes()
	if C.mkdtemp(pattern.data) == unsafe {nil} { return os.error_posix() }
	work := pattern.bytestr().all_before('\x00')
	mut completed := false
	defer { if completed {
		for name in os.ls(work) or {[]string{}} { os.rm(work+'/'+name) or {} }
		os.rmdir(work) or {}
	} else { eprintln('Retained trimmer build evidence: '+work) } }
	generate := [compiler,'-nocache','-os','linux','-arch','arm64','-gc','none','-d','no_segfault_handler',
		'-o',work+'/trim.c',root+'/build-support/source-tools/trim-cmake.v']
	checked(generate,work+'/generate.log')!
	cc := os.getenv_opt('CC') or {'clang'}
	link := [cc,'--target=aarch64-linux-musl','--sysroot='+sdk,'--gcc-install-dir='+gcc,
		'-fuse-ld=lld','-static','-O2','-pthread','-fno-strict-aliasing','-Wno-pointer-sign','-Wno-format','-Wno-macro-redefined',
		'-Wno-unused-function','-Wno-unused-variable','-Wno-unused-label','-Wno-unused-parameter','-Wno-invalid-noreturn',
		work+'/trim.c','-o',work+'/trim-cmake']
	checked(link,work+'/link.log')!
	bytes := os.read_bytes(work+'/trim-cmake')!
	if bytes.len < 64 || bytes[..6] != [u8(127),`E`,`L`,`F`,2,1] || binary.little_endian_u16_at(bytes,18) != 183 {
		return error('trimmer must be an AArch64 ELF64 executable')
	}
	start := binary.little_endian_u64_at(bytes,32)
	width := binary.little_endian_u16_at(bytes,54)
	count := binary.little_endian_u16_at(bytes,56)
	if width != 56 || start > u64(bytes.len) || u64(count)*width > u64(bytes.len)-start { return error('invalid trimmer program headers') }
	for index in 0..int(count) {
		at := int(start)+index*int(width)
		kind := binary.little_endian_u32_at(bytes,at)
		if kind == 3 { return error('guest trimmer must be static') }
		if kind == 1 && binary.little_endian_u64_at(bytes,at+8)%16384 != binary.little_endian_u64_at(bytes,at+16)%16384 {
			return error('guest trimmer must load on the prepared 16 KiB-page kernel')
		}
	}
	os.chmod(work+'/trim-cmake',0o755)!
	mut inputs := map[string]json2.Any{}
	for path in ['build-support/source-tools/trim-cmake.v','build-support/source-tools/sourcefixture/core.v','build-support/source-tools/stage-trimmer.v'] {
		inputs[path] = sha256.sum(os.read_bytes(root+'/'+path)!).hex()
	}
	os.write_file(work+'/manifest.json',json2.encode(json2.Any({'inputs':json2.Any(inputs),
		'generate':json2.Any(generate.map(json2.Any(it))),'link':json2.Any(link.map(json2.Any(it))),
		'compiler_sha256':json2.Any(sha256.sum(os.read_bytes(compiler)!).hex()),
		'executable_sha256':json2.Any(sha256.sum(bytes).hex()),'qualification':json2.Any('Static AArch64 ELF build only; no guest execution.')}),prettify:true)+'\n')!
	os.rename(work+'/trim-cmake',output)!
	os.rename(work+'/manifest.json',output+'.native.json')!
	completed = true
	println('Built native guest source trimmer: '+output)
}

fn main() {
	guard := cachecli.own_commands()
	defer {guard.close()}
	build() or {eprintln(err);exit(if cachecli.cancelled() {cachecli.interrupt_status()} else {1})}
}
