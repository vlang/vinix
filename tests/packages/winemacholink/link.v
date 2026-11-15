// SPDX-License-Identifier: GPL-2.0-or-later
// Experimental captured-link qualification; not a mandatory host receipt.
module winemacholink

import os
import json2
import tests.packages.winelink
import tests.packages.winesource
import tests.packages.winehostimages

const clang = '/opt/homebrew/opt/llvm/bin/clang'
const linker = '/opt/homebrew/bin/ld64.lld'
const sdk = '/Library/Developer/CommandLineTools/SDKs/MacOSX27.2.sdk'
const llvm = '/opt/homebrew/Cellar/llvm/23.1.5_1'

struct Proof {
	format int = 1
	recorded_directory string
	inputs map[string]string
	files map[string]string
}

fn digest(path string) !string {
	if os.lstat(path)!.get_filetype() != .regular || os.real_path(path) != path { return error('Mach-O evidence must be canonical ordinary files') }
	return winesource.file_digest(path)
}

fn relative(path string) bool {
	if path == '' || path.starts_with('/') { return false }
	for byte in path.bytes() { if !byte.is_alnum() && byte !in [u8(`/`), `.`, `_`, `-`, `+`] { return false } }
	return !path.split('/').any(it in ['', '.', '..'])
}

fn be32(bytes []u8) u64 {
	return u64(bytes[0]) << 24 | u64(bytes[1]) << 16 | u64(bytes[2]) << 8 | u64(bytes[3])
}

// Apple's compiler runtime is a fat container of ar archives. Validate all
// slice bounds and overlap before selecting the ordinary arm64 archive.
fn runtime_archive(bytes []u8) bool {
	if bytes.len < 8 || bytes[..4] != [u8(0xca), 0xfe, 0xba, 0xbe] { return false }
	count := be32(bytes[4..8])
	if count < 1 || count > 16 || u64(bytes.len) < 8 + count * 20 { return false }
	mut arm64 := 0
	mut starts := []u64{}
	mut ends := []u64{}
	for i in 0 .. int(count) {
		entry := bytes[8 + i * 20..28 + i * 20]
		offset := be32(entry[8..12]); size := be32(entry[12..16]); align := be32(entry[16..20])
		if align > 31 || offset < 8 + count * 20 || size < 8 || offset + size > u64(bytes.len)
			|| offset % (u64(1) << align) != 0 { return false }
		for j, start in starts { if offset < ends[j] && start < offset + size { return false } }
		if bytes[int(offset)..int(offset) + 8] != '!<arch>\n'.bytes() { return false }
		starts << offset; ends << offset + size
		if be32(entry[..4]) == 0x0100000c && be32(entry[4..8]) == 0 { arm64++ }
	}
	return arm64 == 1
}

// Exact observed SDK/toolchain profile. libLTO is an obsolete ignored option
// in this LLD; it is preserved in the response but is not a captured input.
pub fn profile(archive winelink.Archive, bytes []u8, recorded string) ! {
	lines := archive.response.trim_space().split_into_lines()
	if lines.len != 15 || lines[..9] != ['-demangle', '-lto_library ' + llvm + '/lib/libLTO.dylib',
		'-dynamic', '-arch arm64', '-platform_version macos 27.2.0 27.2', '-syslibroot ' + sdk[1..],
		'-w', '-mllvm -enable-linkonceodr-outlining', '-o program']
		|| lines[11..14] != ['-lm', '-lpthread', '-lSystem']
		|| lines[14] != llvm[1..] + '/lib/clang/23/lib/darwin/libclang_rt.osx.a' {
		return error('Mach-O response profile differs')
	}
	if archive.version != 'Homebrew LLD 23.1.5\n' { return error('Mach-O archive version differs') }
	for index in [9, 10] {
		path := lines[index]
		prefix := recorded[1..] + '/host-tmp/' + if index == 9 { 'program-' } else { 'runtime-' }
		if !relative(path) || !path.starts_with(prefix) || !path.ends_with('.o') || path[prefix.len..].contains('/') {
			return error('Mach-O object namespace differs')
		}
		member := archive.members['link-inputs/' + path] or { return error('Mach-O object absent') }
		object := bytes[member.offset..member.offset + member.size]
		// Thin little-endian MH_OBJECT, CPU_TYPE_ARM64; bitcode is refused.
		if object.len < 32 || object[..8] != [u8(0xcf), 0xfa, 0xed, 0xfe, 0x0c, 0, 0, 1]
			|| object[12..16] != [u8(1), 0, 0, 0] { return error('Mach-O object header differs') }
	}
	for path, member in archive.members {
		if path in ['link-inputs/response.txt', 'link-inputs/version.txt', 'link-inputs/' + lines[9],
			'link-inputs/' + lines[10], 'link-inputs/' + lines[14]] { continue }
		if !path.starts_with('link-inputs/' + sdk[1..] + '/usr/lib/') || !path.ends_with('.tbd')
			|| !bytes[member.offset..member.offset + member.size].bytestr().starts_with('--- !tapi-tbd\n') {
			return error('Mach-O archive input profile differs')
		}
	}
	for path in [sdk[1..] + '/usr/lib/libSystem.tbd', lines[14]] {
		if 'link-inputs/' + path !in archive.members { return error('Mach-O library input absent') }
	}
	runtime := archive.members['link-inputs/' + lines[14]]
	if !runtime_archive(bytes[runtime.offset..runtime.offset + runtime.size]) {
		return error('Mach-O runtime archive header differs')
	}
}

fn command(directory string) []string {
	return [clang, '-fuse-ld=' + linker, '-Wl,--reproduce=' + directory + '/link-inputs.tar',
		'-arch', 'arm64', '-isysroot', sdk, '-O2', '-w', '-fno-lto', '-Wno-error=incompatible-pointer-types',
		'-resource-dir=' + llvm + '/lib/clang/23', directory + '/program.c', directory + '/runtime.c',
		'-lm', '-lpthread', '-o', directory + '/program']
}

fn artifacts(archive winelink.Archive) []string {
	mut files := ['program.c', 'runtime.c', 'program', 'link-inputs.tar', 'replay/link-inputs/program',
		'host-images-before.json', 'host-clang-version.log', 'host-linker-version.log', 'cc.log']
	for name in ['host-clang-version.log', 'host-linker-version.log', 'cc.log'] {
		for suffix in ['.argv.json', '.environment.json', '.dyld.log', '.images.json'] { files << name + suffix }
	}
	files << winehostimages.macho_artifacts()
	for path, _ in archive.members { files << 'replay/' + path }
	return files
}

pub fn admit(directory string) ! {
	proof := json2.decode[Proof](os.read_file(directory + '/macho-link.json')!)!
	if proof.format != 1 || !relative(proof.recorded_directory.trim_left('/'))
		|| !proof.recorded_directory.starts_with('/') { return error('Mach-O proof namespace differs') }
	for path, hash in proof.inputs { if digest(path)! != hash { return error('Mach-O selected input changed') } }
	if proof.inputs.len != 2 || os.real_path(clang) !in proof.inputs || os.real_path(linker) !in proof.inputs {
		return error('Mach-O selected tools absent')
	}
	bytes := os.read_bytes(directory + '/link-inputs.tar')!
	archive := winelink.parse(bytes)!
	profile(archive, bytes, proof.recorded_directory)!
	files := artifacts(archive)
	if proof.files.len != files.len { return error('Mach-O evidence inventory differs') }
	for path in files {
		if path !in proof.files || digest(directory + '/' + path)! != proof.files[path] { return error('Mach-O evidence bytes differ') }
	}
	for path, member in archive.members {
		if digest(directory + '/replay/' + path)! != member.sha256 { return error('Mach-O extracted member differs') }
	}
	if proof.files['program'] != proof.files['replay/link-inputs/program'] { return error('Mach-O replay output differs') }
	output := os.read_bytes(directory + '/program')!
	if output.len < 32 || output[..8] != [u8(0xcf), 0xfa, 0xed, 0xfe, 0x0c, 0, 0, 1]
		|| output[12..16] != [u8(2), 0, 0, 0] { return error('Mach-O executable header differs') }
	if json2.decode[[]string](os.read_file(directory + '/cc.log.argv.json')!)! != command(proof.recorded_directory)
		|| json2.decode[[]string](os.read_file(directory + '/macho-replay.log.argv.json')!)! != [linker, '@response.txt'] {
		return error('Mach-O command differs')
	}
	if os.read_file(directory + '/macho-version.log')! != archive.version { return error('Mach-O linker version differs') }
	winehostimages.admit_macho_capture(directory, proof.recorded_directory)!
	winehostimages.admit_macho(directory, proof.recorded_directory)!
}

pub fn build(source string, requested string) ! {
	directory := os.abs_path(requested)
	if os.exists(directory) || os.is_link(directory) { return error('fresh Mach-O link directory required') }
	os.mkdir_all(directory)!
	if os.real_path(directory) != directory { return error('canonical Mach-O link directory required') }
	for name in ['program.c', 'runtime.c'] { os.cp(source + '/' + name, directory + '/' + name)! }
	mut inputs := map[string]string{}
	for tool in [clang, linker] { inputs[os.real_path(tool)] = digest(os.real_path(tool))! }
	winehostimages.invoke(command(directory), directory, directory + '/cc.log')!
	bytes := os.read_bytes(directory + '/link-inputs.tar')!
	archive := winelink.parse(bytes)!
	profile(archive, bytes, directory)!
	for path, member in archive.members {
		os.mkdir_all(os.dir(directory + '/replay/' + path))!
		os.write_file_array(directory + '/replay/' + path, bytes[member.offset..member.offset + member.size])!
	}
	winehostimages.invoke_macho([linker, '@response.txt'], directory + '/replay/link-inputs', directory + '/macho-replay.log')!
	mut files := map[string]string{}
	for path in artifacts(archive) { files[path] = digest(directory + '/' + path)! }
	os.write_file(directory + '/macho-link.json', json2.encode(Proof{recorded_directory: directory, inputs: inputs, files: files}) + '\n')!
	admit(directory)!
}
