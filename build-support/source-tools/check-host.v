// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module main

import compress.deflate
import encoding.binary
import hostfixture
import hash.crc32
import os
import plist
import sourcecommand
import time

fn zip_members(path string, root string) ![]string {
	zip := os.read_bytes(path)!
	mut position := 0
	mut names := []string{}
	mut offsets := []int{}
	for binary.little_endian_u32_at(zip, position) == 0x04034b50 {
		offsets << position
		assert binary.little_endian_u16_at(zip, position + 8) == 8
		flags := binary.little_endian_u16_at(zip, position + 6)
		size := int(binary.little_endian_u32_at(zip, position + 18))
		length := int(binary.little_endian_u16_at(zip, position + 26))
		name := zip[position + 30..position + 30 + length].bytestr()
		assert flags == if name.bytes().any(it >= 128) { 0x800 } else { 0 }
		names << name
		start := position + 30 + length
		contents := deflate.decompress(zip[start..start + size])!
		assert contents == os.read_bytes(root + '/' + name.all_after('Payload/'))!
		assert crc32.sum(contents) == binary.little_endian_u32_at(zip, position + 14)
		assert contents.len == int(binary.little_endian_u32_at(zip, position + 22))
		position = start + size
	}
	central_start := position
	for index, name in names {
		assert binary.little_endian_u32_at(zip, position) == 0x02014b50
		assert binary.little_endian_u32_at(zip, position + 42) == u32(offsets[index])
		length := int(binary.little_endian_u16_at(zip, position + 28))
		assert zip[position + 46..position + 46 + length].bytestr() == name
		state := os.stat(root + '/' + name.all_after('Payload/'))!
		assert binary.little_endian_u32_at(zip, position + 38) == state.mode << 16
		stamp := time.unix(state.mtime).local()
		assert binary.little_endian_u16_at(zip, position + 12) == u16(stamp.hour << 11 | stamp.minute << 5 | stamp.second / 2)
		assert binary.little_endian_u16_at(zip, position + 14) == u16((stamp.year - 1980) << 9 | stamp.month << 5 | stamp.day)
		position += 46 + length
	}
	assert binary.little_endian_u32_at(zip, position) == 0x06054b50
	assert binary.little_endian_u16_at(zip, position + 10) == u16(names.len)
	assert binary.little_endian_u32_at(zip, position + 12) == u32(position - central_start)
	assert binary.little_endian_u32_at(zip, position + 16) == u32(central_start)
	assert position + 22 == zip.len
	return names
}

fn header(directory string, major string, minor string) ! {
	os.mkdir_all(directory)!
	os.write_file(directory + '/Python.h', '// SDK fixture\n')!
	os.write_file(directory + '/patchlevel.h', '#define PY_MAJOR_VERSION ' + major + '\n#define PY_MINOR_VERSION ' + minor + '\n')!
}

fn check(work string, root string) ! {
	if os.exists(work) { return error('expected a new fixture directory') }
	os.mkdir_all(work)!
	for kind in ['cxx', 'assertions', 'safety', 'process'] {
		cases, label := hostfixture.signal_cases(kind)!
		assert label != ''
		for item in cases {
			hostfixture.validate_signal(sourcecommand.Output{status:-item.number, stderr:'prefix\n' + item.diagnostic + 'suffix'}, item)!
			hostfixture.validate_signal(sourcecommand.Output{status:item.number, stderr:item.diagnostic}, item) or { continue }
			return error('positive signal status was accepted')
		}
	}
	cases, _ := hostfixture.signal_cases('cxx')!
	mut missing_rejected := false
	hostfixture.validate_signal(sourcecommand.Output{status:-6, stdout:cases[0].diagnostic}, cases[0]) or {
		assert err.msg().contains('missing diagnostic')
		missing_rejected = true
	}
	assert missing_rejected
	// The fake executable must never run, even for discovery failures.
	bin := work + '/sdk/bin'
	os.mkdir_all(bin)!
	os.write_file(bin + '/python3.12', '#!/bin/sh\necho INTERPRETER_WAS_RUN >&2\nexit 99\n')!
	os.chmod(bin + '/python3.12', 0o755)!
	header(work + '/sdk/include/python3.12', '3', '12')!
	assert hostfixture.cpython_version(bin + '/python3.12', '')! == '3.12'
	assert hostfixture.cpython_headers(bin + '/python3.12', '')! == work + '/sdk/include/python3.12'
	os.mkdir_all(work + '/venv/bin')!
	os.symlink(bin + '/python3.12', work + '/venv/bin/python3')!
	os.write_file(work + '/venv/pyvenv.cfg', 'home = ' + bin + '\n')!
	assert hostfixture.cpython_version(work + '/venv/bin/python3', '')! == '3.12'
	header(work + '/explicit', '3', '9')!
	assert hostfixture.cpython_version('/missing/executable', work + '/explicit')! == '3.9'
	os.write_file(work + '/explicit/patchlevel.h', '#define PY_MAJOR_VERSION 3\n#define PY_MINOR_VERSION invalid\n')!
	mut sdk_rejected := false
	hostfixture.cpython_version('/missing/executable', work + '/explicit') or {
		assert err.msg().contains('invalid CPython version')
		sdk_rejected = true
		''
	}
	assert sdk_rejected
	os.write_file(bin + '/python3', '#!/bin/sh\nexit 99\n')!
	os.chmod(bin + '/python3', 0o755)!
	header(work + '/sdk/include/python3.13', '3', '13')!
	mut ambiguous_rejected := false
	hostfixture.cpython_headers(bin + '/python3', '') or {
		assert err.msg().contains('ambiguous CPython SDK')
		ambiguous_rejected = true
		''
	}
	assert ambiguous_rejected
	mut missing_sdk_rejected := false
	hostfixture.cpython_headers('/missing/executable', '') or { missing_sdk_rejected = true; '' }
	assert missing_sdk_rejected
	source := root + '/build/ios/2048/source/NumberTileGame/NumberTileGame'
	app := work + '/NumberTileGame.app'
	os.mkdir(app)!
	os.write_file(app + '/kept', 'preserved unrelated resource')!
	hostfixture.game_bundle(source, app)!
	info := plist.parse(os.read_bytes(app + '/Info.plist')!)!
	original := plist.parse(os.read_bytes(source + '/NumberTileGame-Info.plist')!)!
	for key, value in original.fields {
		if key in ['CFBundleDisplayName', 'CFBundleExecutable', 'CFBundleName', 'CFBundleIdentifier', 'UIRequiredDeviceCapabilities'] { continue }
		assert info.fields[key] == value
	}
	for key in ['CFBundleDisplayName', 'CFBundleExecutable', 'CFBundleName'] { assert info.fields[key].text == 'NumberTileGame' }
	assert info.fields['CFBundleIdentifier'].text == 'f3nghuang.NumberTileGame'
	assert info.fields['UIRequiredDeviceCapabilities'].values[0].text == 'arm64'
	assert os.read_file(app + '/kept')! == 'preserved unrelated resource'
	for path in os.walk_ext(source + '/Base.lproj', '') {
		copied := app + '/Base.lproj/' + path.all_after(source + '/Base.lproj/')
		assert os.read_bytes(path)! == os.read_bytes(copied)!
		before := os.stat(path)!
		after := os.stat(copied)!
		assert before.mode == after.mode && before.mtime == after.mtime
	}
	os.write_file_array(app + '/binary', [u8(0), 255, 1, 0])!
	os.write_file(app + '/z-日本語', 'Unicode resource')!
	os.chmod(app + '/binary', 0o755)!
	os.utime(app + '/binary', 1700000001, 1700000001)!
	os.symlink('binary', app + '/file-link')!
	os.symlink('missing', app + '/dangling')!
	os.symlink('Base.lproj', app + '/directory-link')!
	hostfixture.ipa(work, 'NumberTileGame')!
	names := zip_members(work + '/NumberTileGame.ipa', work)!
	mut sorted := names.clone(); sorted.sort()
	assert names == sorted && 'Payload/NumberTileGame.app/file-link' in names
	assert !names.any(it.contains('directory-link/') || it.ends_with('/dangling'))
	os.mkdir(work + '/Calculator.app')!
	hostfixture.ipa(work, 'Calculator')!
	assert os.read_bytes(work + '/Calculator.ipa')!.len == 22
	os.write_file(work + '/Calculator.app/old', 'old')!
	os.utime(work + '/Calculator.app/old', 1, 1)!
	hostfixture.ipa(work, 'Calculator') or {
		assert err.msg().contains('timestamp')
		println('PASS native signal verdicts, SDK discovery, pinned plist/resources and IPA CRC/content/order/mode/timestamp/link/error policies')
		return
	}
	return error('pre-1980 ZIP timestamp accepted')
}

fn main() {
	if os.args.len != 3 { eprintln('expected NEW_DIRECTORY REPOSITORY'); exit(1) }
	check(os.args[1], os.args[2]) or { eprintln(err); exit(1) }
}
