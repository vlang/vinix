// SPDX-License-Identifier: GPL-2.0-or-later
module winelink

import os
import json2
import crypto.sha256
import tests.packages.winesource
import tests.packages.winecsource
import tests.packages.winehostimages

const linker = '/opt/homebrew/bin/ld.lld'

pub struct Member {
pub:
	offset int
	size int
	sha256 string
}

pub struct Archive {
pub:
	members map[string]Member
	response string
	version string
}

struct Proof {
	format int = 1
	archive_sha256 string
	members map[string]Member
	linker string
	linker_sha256 string
	output string
	output_sha256 string
	recorded_directory string
}

fn digest(bytes []u8) string {
	sum := sha256.sum(bytes)
	defer { unsafe { sum.free() } }
	return sum.hex()
}

fn zero(bytes []u8) bool {
	for byte in bytes { if byte != 0 { return false } }
	return true
}

fn text_field(bytes []u8) !string {
	end := bytes.index(u8(0))
	if end < 0 { return bytes.bytestr() }
	if !zero(bytes[end..]) { return error('link archive field padding differs') }
	return bytes[..end].bytestr()
}

fn octal(bytes []u8) !int {
	mut value := u64(0)
	mut ended := false
	mut started := false
	for byte in bytes {
		if byte == 0 || byte == ` ` { if started { ended = true }; continue }
		if ended || byte < `0` || byte > `7` || value > 512 * 1024 * 1024 { return error('invalid link archive number') }
		value = value * 8 + u64(byte - `0`); started = true
	}
	if value > 512 * 1024 * 1024 { return error('link archive number exceeds bound') }
	return int(value)
}

fn relative(path string) bool {
	if path == '' || path.len > 4096 || path.starts_with('-') { return false }
	for byte in path.bytes() {
		if !byte.is_alnum() && byte !in [u8(`/`), `.`, `_`, `-`, `+`] { return false }
	}
	for part in path.split('/') { if part in ['', '.', '..'] { return false } }
	return true
}

// This profile accepts only ordinary USTAR members, never extracts an archive
// with a general-purpose tar program, and checks the complete end region.
pub fn parse(bytes []u8) !Archive {
	if bytes.len < 1024 || bytes.len > 512 * 1024 * 1024 || bytes.len % 512 != 0 {
		return error('link archive size differs')
	}
	mut position := 0
	mut members := map[string]Member{}
	mut folded := map[string]bool{}
	mut directories := map[string]bool{}
	mut response := ''
	mut version := ''
	for position < bytes.len {
		header := bytes[position..position + 512]
		if zero(header) {
			if bytes.len - position < 1024 || !zero(bytes[position..]) || members.len < 3
				|| response == '' || version == '' { return error('link archive end or metadata differs') }
			return Archive{members, response, version}
		}
		mut checksum := 0
		for index, byte in header { checksum += if index >= 148 && index < 156 { 32 } else { int(byte) } }
		if octal(header[148..156])! != checksum || header[257..263] != 'ustar\x00'.bytes()
			|| header[263..265] != '00'.bytes() || header[156] !in [u8(0), `0`] || !zero(header[157..257]) {
			return error('link archive header differs')
		}
		name := text_field(header[..100])!
		prefix := text_field(header[345..500])!
		path := if prefix == '' { name } else { prefix + '/' + name }
		key := path.to_lower()
		if !path.starts_with('link-inputs/') || !relative(path) || key in folded || key in directories || members.len >= 10000 {
			return error('link archive member path differs')
		}
		mut parent := key.all_before_last('/')
		for parent != '' {
			if parent in folded { return error('link archive file/directory collision') }
			directories[parent] = true
			if !parent.contains('/') { break }
			parent = parent.all_before_last('/')
		}
		folded[key] = true
		size := octal(header[124..136])!
		start := position + 512
		if size > 128 * 1024 * 1024 || size > bytes.len - start { return error('link archive member exceeds bound') }
		end := start + size
		next := start + (size + 511) / 512 * 512
		if next > bytes.len || !zero(bytes[end..next]) { return error('link archive data padding differs') }
		members[path] = Member{start, size, digest(bytes[start..end])}
		if path == 'link-inputs/response.txt' || path == 'link-inputs/version.txt' {
			if size == 0 || size > 65536 { return error('link archive metadata size differs') }
			if path.ends_with('/response.txt') { response = bytes[start..end].bytestr() }
			else { version = bytes[start..end].bytestr() }
		}
		position = next
	}
	return error('link archive has no complete end marker')
}

fn response_check(archive Archive, output string) ! {
	if output !in ['wine-runner', 'guest', 'package', 'program'] { return error('link replay output differs') }
	mut roots := 0
	mut outputs := 0
	mut inputs := 0
	if !archive.response.ends_with('\n') { return error('link response is incomplete') }
	for line in archive.response.split_into_lines() {
		for byte in line.bytes() { if byte < 32 || byte > 126 { return error('link response control byte') } }
		if line == '--chroot .' { roots++; continue }
		if line == '-o ' + output { outputs++; continue }
		if line in ['--hash-style gnu', '--eh-frame-hdr', '-m elf_x86_64', '-m aarch64linux', '--Bstatic',
			'-l m', '-l pthread', '-l gcc', '-l gcc_eh', '-l c', '--start-group', '--end-group'] { continue }
		if line.starts_with('--sysroot ') {
			if !relative(line[10..]) { return error('link response sysroot differs') }
			continue
		}
		if line.starts_with('-L ') {
			if !relative(line[3..]) { return error('link response library directory differs') }
			continue
		}
		if relative(line) && 'link-inputs/' + line in archive.members { inputs++; continue }
		return error('link response contains unsupported argument')
	}
	if roots != 1 || outputs != 1 || inputs < 3 { return error('link response profile differs') }
}

fn version_matches(observed string, archived string) bool {
	return observed == archived || observed == archived.trim_right('\n') + ' (compatible with GNU linkers)\n'
}

fn read(path string, bound int) ![]u8 {
	st := os.lstat(path)!
	if st.get_filetype() != .regular || st.size < 1 || st.size > u64(bound) {
		return error('link evidence must be a bounded ordinary file')
	}
	return os.read_bytes(path)
}

fn invoke(command []string, cwd string, log string) !string {
	return winehostimages.invoke(command, cwd, log)
}

pub fn build(base []string, directory string, logs string) ! {
	if base.filter(it.starts_with('-fuse-ld=')).len != 1 || '-fuse-ld=' + linker !in base {
		return error('link compiler selection differs')
	}
	archive_path := directory + '/link-inputs.tar'
	if os.exists(archive_path) || os.is_link(archive_path) || os.exists(directory + '/link-replay') {
		return error('link evidence output must be fresh')
	}
	before := winesource.file_digest(linker)!
	version := invoke([linker, '--version'], directory, logs + '/link-version.log')!
	mut command := base.clone()
	command.insert(1, '-Wl,--reproduce=' + archive_path)
	winecsource.build(command, directory, logs)!
	bytes := read(archive_path, 512 * 1024 * 1024)!
	defer { unsafe { bytes.free() } }
	archive := parse(bytes)!
	output := os.file_name(base.last())
	response_check(archive, output)!
	if !version_matches(version, archive.version) { return error('link archive linker version differs') }
	for path, member in archive.members {
		to := directory + '/link-replay/' + path
		os.mkdir_all(os.dir(to))!
		os.write_file_array(to, bytes[member.offset..member.offset + member.size])!
	}
	for path, member in archive.members {
		full := directory + '/link-replay/' + path
		if os.real_path(full) != full || digest(read(full, 128 * 1024 * 1024)!) != member.sha256 {
			return error('link extracted input differs before replay')
		}
	}
	replay := directory + '/link-replay/link-inputs'
	invoke([linker, '@response.txt'], replay, logs + '/link-replay.log')!
	hash := winesource.file_digest(base.last())!
	if winesource.file_digest(replay + '/' + output)! != hash || winesource.file_digest(linker)! != before {
		return error('link replay output or linker changed')
	}
	os.write_file(directory + '/link-proof.json', json2.encode(Proof{archive_sha256: digest(bytes), members: archive.members,
		linker: linker, linker_sha256: before, output: output, output_sha256: hash, recorded_directory: directory}) + '\n')!
	admit(directory, logs, base.last())!
	winehostimages.admit_link(logs, logs)!
}

pub fn admit(directory string, logs string, binary string) ! {
	proof_bytes := read(directory + '/link-proof.json', 8 * 1024 * 1024)!
	proof := json2.decode[Proof](proof_bytes.bytestr())!
	bytes := read(directory + '/link-inputs.tar', 512 * 1024 * 1024)!
	defer { unsafe { proof_bytes.free(); bytes.free() } }
	archive := parse(bytes)!
	response_check(archive, proof.output)!
	if proof.format != 1 || proof.linker != linker || winesource.file_digest(linker)! != proof.linker_sha256
		|| digest(bytes) != proof.archive_sha256 || archive.members != proof.members
		|| winesource.file_digest(binary)! != proof.output_sha256 || os.file_name(binary) != proof.output {
		return error('link proof binding differs')
	}
	cc := json2.decode[[]string](read(logs + '/cc.log.argv.json', 65536)!.bytestr())!
	flags := cc.filter(it.starts_with('-Wl,--reproduce='))
	if !os.is_abs_path(proof.recorded_directory) || flags != ['-Wl,--reproduce=' + proof.recorded_directory + '/link-inputs.tar']
		|| '-fuse-ld=' + linker !in cc || os.file_name(cc.last()) != proof.output {
		return error('link compile argv binding differs')
	}
	if !version_matches(read(logs + '/link-version.log', 65536)!.bytestr(), archive.version)
		|| json2.decode[[]string](read(logs + '/link-version.log.argv.json', 65536)!.bytestr())! != [linker, '--version']
		|| json2.decode[[]string](read(logs + '/link-replay.log.argv.json', 65536)!.bytestr())! != [linker, '@response.txt'] {
		return error('link replay argv or version differs')
	}
	for path, member in archive.members {
		full := directory + '/link-replay/' + path
		if os.real_path(full) != full || digest(read(full, 128 * 1024 * 1024)!) != member.sha256 {
			return error('link replay input differs')
		}
	}
	rebuilt := directory + '/link-replay/link-inputs/' + proof.output
	if os.real_path(rebuilt) != rebuilt || winesource.file_digest(rebuilt)! != proof.output_sha256 {
		return error('link replay executable differs')
	}
}

pub fn artifacts(directory string) ![]string {
	proof := json2.decode[Proof](read(directory + '/link-proof.json', 8 * 1024 * 1024)!.bytestr())!
	archive := parse(read(directory + '/link-inputs.tar', 512 * 1024 * 1024)!)!
	response_check(archive, proof.output)!
	mut result := archive.members.keys().map('link-replay/' + it)
	result << 'link-replay/link-inputs/' + proof.output
	result.sort()
	return result
}
