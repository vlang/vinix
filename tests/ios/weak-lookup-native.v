// SPDX-License-Identifier: GPL-2.0-or-later
// Generate Mach-O objects in V, link them with the Mac's ld, and compare native
// dyld's weak coalescing with the loader's expected definition order.
module main

import os
import macho
import crypto.sha256

#include <dlfcn.h>
fn C.dlopen(&char, int) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.dlerror() &char
fn C.dlclose(voidptr) int

fn number(mut bytes []u8, offset int, value u64, width int) {
	for i in 0 .. width { bytes[offset + i] = u8(value >> (i * 8)) }
}

fn label(mut bytes []u8, offset int, value string) {
	for i, byte in value.bytes() { bytes[offset + i] = byte }
}

fn object(path string, weak bool, value u64, client bool) {
	first := if client { '_vinix_lookup_slot' } else { '_vinix_lookup_data' }
	second := if client { '_vinix_lookup_data' } else { '_vinix_force_weakdefs' }
	strings := '\x00' + first + '\x00' + second + '\x00'
	mut bytes := []u8{len: 288 + strings.len}
	number(mut bytes, 0, 0xfeedfacf, 4)
	number(mut bytes, 4, 0x100000c, 4)
	number(mut bytes, 12, 1, 4) // MH_OBJECT
	number(mut bytes, 16, 3, 4)
	number(mut bytes, 20, 200, 4)
	number(mut bytes, 24, 0x2000, 4) // MH_SUBSECTIONS_VIA_SYMBOLS: separate coalescible atoms
	number(mut bytes, 32, 0x19, 4) // LC_SEGMENT_64 plus one section
	number(mut bytes, 36, 152, 4)
	number(mut bytes, 64, if client { 8 } else { 16 }, 8)
	number(mut bytes, 72, 240, 8)
	number(mut bytes, 80, if client { 8 } else { 16 }, 8)
	number(mut bytes, 88, 7, 4)
	number(mut bytes, 92, 3, 4)
	number(mut bytes, 96, 1, 4)
	label(mut bytes, 104, '__data')
	label(mut bytes, 120, '__DATA')
	number(mut bytes, 144, if client { 8 } else { 16 }, 8)
	number(mut bytes, 152, 240, 4)
	number(mut bytes, 156, 3, 4)
	if client {
		number(mut bytes, 160, 248, 4)
		number(mut bytes, 164, 1, 4)
		// ARM64_RELOC_UNSIGNED: external nlist index 1, eight-byte pointer.
		number(mut bytes, 252, 0x0e000001, 4)
	} else {
		number(mut bytes, 240, value, 8)
	}
	number(mut bytes, 184, 2, 4) // LC_SYMTAB
	number(mut bytes, 188, 24, 4)
	number(mut bytes, 192, 256, 4)
	number(mut bytes, 196, 2, 4)
	number(mut bytes, 200, 288, 4)
	number(mut bytes, 204, u64(strings.len), 4)
	number(mut bytes, 208, 0x32, 4) // LC_BUILD_VERSION, macOS 14
	number(mut bytes, 212, 24, 4)
	number(mut bytes, 216, 1, 4)
	number(mut bytes, 220, 0xe0000, 4)
	number(mut bytes, 224, 0xf0000, 4)
	number(mut bytes, 256, 1, 4)
	number(mut bytes, 260, 0xf, 1)
	number(mut bytes, 261, 1, 1)
	number(mut bytes, 262, if weak { 0x80 } else { 0 }, 2)
	number(mut bytes, 272, u64(first.len + 2), 4)
	number(mut bytes, 276, if client { 1 } else { 0xf }, 1)
	number(mut bytes, 277, if client { 0 } else { 1 }, 1)
	number(mut bytes, 278, if client { 0 } else { 0x80 }, 2)
	number(mut bytes, 280, if client { 0 } else { 8 }, 8)
	label(mut bytes, 288, strings)
	os.write_file_array(path, bytes) or { panic(err) }
}

fn checked(args []string, log string) {
	mut process := os.new_process(args[0])
	process.set_args(args[1..])
	process.set_redirect_stdio_merged()
	process.run()
	output := process.stdout_slurp()
	process.wait()
	os.write_file(log, output) or { panic(err) }
	os.write_file(log + '.status.txt', '${process.code}\n') or { panic(err) }
	assert process.code == 0, output
	process.close()
}

fn native(out string, order []string) {
	mut handles := []voidptr{}
	for name in order {
		path := out + '/' + name + '.dylib'
		handle := C.dlopen(unsafe { &char(path.str) }, 10) // RTLD_NOW | RTLD_GLOBAL
		assert handle != unsafe { nil }, unsafe { C.dlerror().vstring() }
		handles << handle
	}
	path := out + '/client.dylib'
	client := C.dlopen(unsafe { &char(path.str) }, 2)
	assert client != unsafe { nil }, unsafe { C.dlerror().vstring() }
	slot := C.dlsym(client, c'vinix_lookup_slot')
	assert slot != unsafe { nil }
	chosen := if 'strong' in order { order.index('strong') } else { 0 }
	definition := C.dlsym(handles[chosen], c'vinix_lookup_data')
	assert unsafe { *(&u64(slot)) } == u64(definition)
	value := unsafe { *(&u64(definition)) }
	expected := if 'strong' in order { u64(33) } else if order[0] == 'weak-b' { u64(22) } else { u64(11) }
	assert value == expected
	assert C.dlclose(client) == 0
	for handle in handles { assert C.dlclose(handle) == 0 }
	println('IOS-MODULE-LOOKUP-NATIVE: ${order.join(",")} selected ${value}')
}

fn main() {
	assert os.args.len >= 2, 'usage: weak-lookup-native OUTPUT-DIRECTORY [native ORDER...]'
	out := os.real_path(os.args[1])
	if os.args.len > 2 { native(out, os.args[3..]); return }
	os.mkdir_all(out)!
	for name, value in {'weak-a': u64(11), 'weak-b': u64(22), 'strong': u64(33), 'client': u64(0)} {
		object(out + '/' + name + '.o', name.starts_with('weak'), value, name == 'client')
		mut args := ['/usr/bin/ld', '-dylib', '-arch', 'arm64', '-platform_version', 'macos', '14.0', '15.0',
			'-syslibroot', '/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk', '-lSystem',
			'-install_name', out + '/' + name + '.dylib', '-o', out + '/' + name + '.dylib', out + '/' + name + '.o']
		if name == 'client' { continue }
		checked(args, out + '/' + name + '-link.log')
	}
	checked(['/usr/bin/ld', '-dylib', '-arch', 'arm64', '-platform_version', 'macos', '14.0', '15.0',
		'-syslibroot', '/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk', '-lSystem',
		'-fixup_chains', '-install_name', out + '/client.dylib', '-o', out + '/client.dylib',
		out + '/client.o', out + '/weak-a.dylib'], out + '/client-link.log')
	image := macho.parse(os.read_bytes(out + '/client.dylib')!)!
	imports := image.imported_symbols()!
	assert imports.any(it.library == '<weak lookup>' && it.name == '_vinix_lookup_data' && !it.weak)
	for index, order in [['weak-a', 'weak-b'], ['weak-b', 'weak-a'], ['weak-a', 'strong'], ['strong', 'weak-a']] {
		mut args := [os.executable(), out, 'native']
		args << order
		checked(args, out + '/native-${index}.log')
	}
	mut hashes := ''
	for name in os.ls(out)! {
		if name.ends_with('.o') || name.ends_with('.dylib') {
			hashes += '${sha256.sum(os.read_bytes(out + "/" + name)!).hex()} ${name}\n'
		}
	}
	os.write_file(out + '/fixtures.sha256', hashes)!
	println('IOS-MODULE-LOOKUP-NATIVE: four native dyld orders passed; required chained weak import confirmed')
}
