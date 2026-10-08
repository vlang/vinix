// SPDX-License-Identifier: GPL-2.0-or-later
module runnercore

import androidhost as ah
import encoding.hex

fn dictionary_assets(directory string) !ah.Value {
	data := join(directory, 'dictionary.vnd')!
	license_file := join(directory, 'LICENSE.WordNet')!
	if !boolean(path(data, 'is_file', []ah.Value{}, map[string]ah.Value{})!) || !boolean(path(license_file, 'is_file', []ah.Value{}, map[string]ah.Value{})!) {
		return failed('ValueError', 'dictionary data requires regular dictionary.vnd and LICENSE.WordNet files')
	}
	size := callback('stat', {
		'path': ah.Value(data)
	})!
	if compare('lt', size, ah.Value(24))! || compare('gt', size, ah.Value(64 * 1024 * 1024))! {
		return failed('ValueError', 'dictionary data or license exceeds supported size bounds')
	}
	license_size := callback('stat', {
		'path': ah.Value(license_file)
	})!
	if compare('le', license_size, ah.Value(0))! || compare('gt', license_size, ah.Value(16384))! {
		return failed('ValueError', 'dictionary data or license exceeds supported size bounds')
	}
	owner := callback('enter', {
		'name':      ah.Value('open')
		'path':      ah.Value(data)
		'arguments': ah.Value([value_arg(ah.Value('rb'))])
	})!.object()
	id := ah.field(owner, 'id').text()
	mut header_hex := ''
	mut read_failure := ?IError(none)
	header_hex = callback('read', {
		'id':   ah.Value(id)
		'size': ah.Value(24)
	}) or {
		read_failure = err
		ah.Value('')
	}.text()
	suppressed := exit_owner(id, read_failure)!
	if cause := read_failure {
		if !suppressed { return cause }
		version := callback('python_version', map[string]ah.Value{})!.items()
		message := if (ah.integer(version[1]) or { u64(0) }) >= 11 {
			"cannot access local variable 'header' where it is not associated with a value"
		} else {
			"local variable 'header' referenced before assignment"
		}
		return failed('UnboundLocalError', message)
	}
	header := hex.decode(header_hex)!
	if header.len != 24 || header[..8].bytestr() != 'VNXDICT1' {
		return failed('ValueError', 'dictionary.vnd has an invalid VNXDICT1 header')
	}
	mut words := []u64{cap: 4}
	for offset := 8; offset < 24; offset += 4 {
		words << u64(header[offset]) | u64(header[offset + 1]) << 8 | u64(header[offset + 2]) << 16 | u64(header[offset + 3]) << 24
	}
	count, keys, definitions, reserved := words[0], words[1], words[2], words[3]
	if count < 1 || count > 200000 || keys < count || keys > count * 128 || definitions < count || definitions > count * 65536 || reserved != 0 || !compare('eq', size, ah.Value(24 + count * 16 + keys + definitions))! {
		return failed('ValueError', 'dictionary.vnd has invalid header bounds or length')
	}
	return strings([data, license_file])
}

fn compile_measure(source string, output string) !ah.Value {
	mut llvm := library('os', 'getenv', [value_arg(ah.Value('LLVM_BIN')),
		value_arg(ah.Value('/opt/homebrew/opt/llvm/bin'))])!.text()
	if !boolean(path(join(llvm, 'clang')!, 'exists', []ah.Value{}, map[string]ah.Value{})!) {
		located := library('shutil', 'which', [value_arg(ah.Value('clang'))])!
		actual := if located.text() == '' { 'clang' } else { located.text() }
		llvm = path(actual, 'parent', []ah.Value{}, map[string]ah.Value{})!.text()
	}
	default_root := join(constant('ROOT')!.text(), 'build-aarch64-userland/staging')!
	sysroot := library('os', 'getenv', [value_arg(ah.Value('VINIX_AARCH64_SYSROOT')),
		value_arg(ah.Value(default_root))])!.text()
	versions := callback('iterdir', {
		'path': ah.Value(join(sysroot, 'usr/lib/gcc/aarch64-alpine-linux-musl')!)
	})!.items()
	if versions.len == 0 { return failed('IndexError', 'list index out of range') }
	gcc := versions.last().text()
	lib := join(sysroot, 'usr/lib')!
	command := [join(llvm, 'clang')!, '--target=aarch64-linux-musl', '-static', '-nostdinc', '-nostdlib',
		'-isystem', join(gcc, 'include')!, '-isystem', join(sysroot, 'usr/include')!, '-O2', '-Wall',
		join(lib, 'crt1.o')!, join(lib, 'crti.o')!, join(gcc, 'crtbeginT.o')!, source, '-L' + lib,
		'-L' + gcc, '-lc', '-lgcc', join(gcc, 'crtend.o')!, join(lib, 'crtn.o')!, '-fuse-ld=lld',
		'-B' + llvm, '-o', output]
	invoke('', 'run_guest_command', [value_arg(strings(command))], {
		'check': ah.Value(true)
	})!
	return null()
}
