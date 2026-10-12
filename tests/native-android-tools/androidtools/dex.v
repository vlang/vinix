// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import androidhost as ah
import crypto.sha256
import encoding.binary
import hosttest
import os

#include <stdlib.h>
fn C.mkdtemp(&char) &char

fn temporary_in(parent string, prefix string) !string {
	mut name := (parent + '/' + prefix + 'XXXXXX\x00').bytes()
	if isnil(C.mkdtemp(unsafe { &char(name.data) })) { return os.error_posix() }
	return name.bytestr().all_before('\x00')
}

pub const r8_sha256 = '900dfbc649519969fc5a4c7520d6b7355338e565fa1249874e0190b8d61b1199'
pub const core_sha256 = 'f47736d9d410766a20ae1f60d679607d8e85241e8cdeb5a0c040ab260ba68f42'
pub const dex_arguments = ['--release', '--min-api', '26', '--android-platform-build', '--force-passthrough-assertions']

pub fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

pub fn check_hash(path string, expected string) ! {
	if digest(path)! != expected { return error('ATL compiler input checksum mismatch: ' + path) }
}

pub fn dex_callsites(data []u8) ! {
	if data.len < 56 || data[..4].bytestr() != 'dex\n' { return error('invalid D8 output') }
	offset := u64(binary.little_endian_u32(data[52..56]))
	if offset > u64(data.len) || u64(data.len) - offset < 4 { return error('truncated D8 map') }
	count := u64(binary.little_endian_u32(data[int(offset)..int(offset) + 4]))
	if count > (u64(data.len) - offset - 4) / 12 { return error('truncated D8 map') }
	for index := u64(0); index < count; index++ {
		at := int(offset + 4 + 12 * index)
		kind := binary.little_endian_u16(data[at..at + 2])
		size := binary.little_endian_u32(data[at + 4..at + 8])
		if kind == 7 && size > 0 { return error('D8 retained unsupported Java bootstrap callsites') }
	}
}

pub fn dex_compile(arguments []string, r8 string, core string, java string) ! {
	check_hash(r8, r8_sha256)!
	check_hash(core, core_sha256)!
	outputs := arguments.filter(it.starts_with('--output=')).map(it['--output='.len..])
	inputs := arguments.filter(!it.starts_with('--'))
	if outputs.len != 1 || inputs.len != 1 { return error('unsupported ATL dx arguments') }
	for argument in arguments {
		if argument.starts_with('--') && argument !in ['--dex', '--incremental'] && !argument.starts_with('--output=') { return error('unsupported ATL dx arguments') }
	}
	source := hosttest.module_resolve(inputs[0])!
	output := hosttest.module_resolve(outputs[0])!
	mut libraries := ['--lib', core]
	hax := os.dir(os.dir(source)) + '/api-impl/hax.jar'
	if source != hax && os.is_file(hax) { libraries << ['--lib', hax] }
	scratch := temporary_in(os.dir(output), 'atl-dex-')!
	defer { hosttest.remove_work_dir(scratch) or {} }
	checked([java, '-cp', r8, 'com.android.tools.r8.D8', ...dex_arguments, ...libraries, '--output', scratch, source])!
	dex_package(source, scratch, output)!
}

pub fn dex_package(source string, directory string, output string) ! {
	classes := ah.open_archive(source)!
	mut payload := map[string][]u8{}
	for name in classes.names() {
		if !name.ends_with('.class') && !name.ends_with('/') { payload[name] = classes.read(name)! }
	}
	mut names := []string{}
	for name in os.ls(directory)! { if name.ends_with('.dex') && os.is_file(directory + '/' + name) { names << name } }
	names.sort()
	for name in names {
		data := os.read_bytes(directory + '/' + name)!
		dex_callsites(data)!
		payload[name] = data
	}
	if 'classes.dex' !in payload { return error('D8 did not produce classes.dex') }
	temporary := hosttest.replace_suffix(output, '.jar.next')
	mut members := []ah.ArchiveItem{}
	mut ordered := payload.keys()
	ordered.sort()
	for name in ordered { members << ah.ArchiveItem{name: name, data: payload[name]!, mode: 0o644} }
	ah.write_archive(temporary, members)!
	if C.rename(temporary.str, output.str) != 0 { return os.error_posix() }
}
