// SPDX-License-Identifier: GPL-2.0-or-later
module qemuhost

import crypto.sha256
import hosttest
import os
import policyhost
import strconv

pub const old_sequence = [u8(0x09), 0x90, 0x90, 0x52, 0xc9, 0x03, 0xa0, 0x72, 0x1f, 0x01, 0x09,
	0xeb, 0xa3, 0x00, 0x00, 0x54]
pub const new_sequence = [u8(0x09), 0xd4, 0x90, 0x52, 0x29, 0x00, 0xa0, 0x72, 0x1f, 0x01, 0x09,
	0xeb, 0xa3, 0x00, 0x00, 0x54]

fn little(data []u8, at int, count int) !u64 {
	if at < 0 || count > data.len - at { return error('Truncated Mach-O field') }
	mut value := u64(0)
	for index in 0 .. count { value |= u64(data[at + index]) << (index * 8) }
	return value
}

pub fn patched(data []u8, symbols string) ![]u8 {
	mut matches := []u64{}
	for line in symbols.split_into_lines() {
		fields := line.fields()
		if fields.len == 3 && fields[1] in ['t', 'T'] && fields[2] == '_hvf_wfi' && fields[0] != '' && fields[0].bytes().all(it.is_digit() || it in [
			`a`,
			`b`,
			`c`,
			`d`,
			`e`,
			`f`,
			`A`,
			`B`,
			`C`,
			`D`,
			`E`,
			`F`,
		]) {
			matches << strconv.parse_uint(fields[0], 16, 64)!
		}
	}
	if matches.len != 1 || data.len < 32 || data[..4] != [u8(0xcf), 0xfa, 0xed, 0xfe] {
		return error('Expected the ARM64 KekVM QEMU bottle with hvf_wfi')
	}
	if matches[0] > u64(0xffffffffffffffff) - 0x168 - old_sequence.len {
		return error('Invalid hvf_wfi address')
	}
	address := matches[0] + 0x168
	count := little(data, 16, 4)!
	mut at := 32
	for _ in 0 .. count {
		command := little(data, at, 4)!
		length := little(data, at + 4, 4)!
		if length < 8 || length > u64(data.len - at) { return error('Invalid Mach-O load command') }
		if command == 0x19 {
			if length < 72 { return error('Invalid Mach-O segment command') }
			vmaddr := little(data, at + 24, 8)!
			fileoff := little(data, at + 40, 8)!
			filesize := little(data, at + 48, 8)!
			if address >= vmaddr && filesize >= old_sequence.len && address - vmaddr <= filesize - old_sequence.len {
				delta := address - vmaddr
				if fileoff > u64(data.len) || delta > u64(data.len) - fileoff || old_sequence.len > u64(data.len) - fileoff - delta {
					return error('Invalid Mach-O file offset')
				}
				offset := int(fileoff + delta)
				if data[offset..offset + old_sequence.len] !in [old_sequence, new_sequence] {
					return error('Unsupported QEMU HVF WFI instruction sequence')
				}
				mut result := data.clone()
				for index, byte in new_sequence { result[offset + index] = byte }
				return result
			}
		}
		at += int(length)
	}
	return error('Unsupported QEMU HVF WFI instruction sequence')
}

pub fn prepare(source string, target string) ! {
	data := os.read_bytes(source)!
	mut hash := sha256.new()
	hash.write(data)!
	hash.write(new_sequence)!
	digest := hash.sum([]u8{}).hex()
	stamp := target[..target.len - os.file_ext(target).len] + '.sha256'
	if os.is_file(target) && os.is_file(stamp) && os.read_file(stamp)!.trim_space() == digest {
		return
	}
	symbols := policyhost.capture(['nm', '-an', source])!
	output := patched(data, symbols)!
	os.mkdir_all(os.dir(target))!
	work := os.dir(target) + '/.venus-qemu-' + os.getpid().str()
	hosttest.work_dir(work, '')!
	defer { hosttest.remove_work_dir(work) or {} }
	temporary := work + '/' + os.file_name(target)
	os.write_file_array(temporary, output)!
	os.chmod(temporary, 0o755)!
	policyhost.inherited(['codesign', '--force', '--sign', '-', '--entitlements',
		hosttest.root() + '/build-support/venus/hvf-entitlements.plist', temporary])!
	os.mv(temporary, target)!
	os.write_file(stamp, digest + '\n')!
	policyhost.inherited(['defaults', 'write', os.file_name(target), 'NSAppSleepDisabled', '-bool',
		'YES'])!
}
