// SPDX-License-Identifier: GPL-2.0-or-later
module campaignhost

import corevm.corepolicy
import crypto.sha256
import json2
import os
import tarcore
import tarstream

pub const core_patch = 'ec459e48e5c3c9946c91e805428149802d0ab1835c64e5e023811ab54a48af1d'
pub const core_test = '705b57f7ff40b934d438ff62187ca7bc9983839af8ee3ff0039ed59bcbd77abe'
pub const core_table = 'f71d45c78c2db0e1c198d2aa3443513a5fd2f51975a8209a8fdbf374dc7abf5d'

pub fn core_kernel(arch string) !string {
	return match arch {
		'x86_64' { '16140916ef5abca52cc6f0a8e80bb6dedc24b5e5f05efd747f57182523098e74' }
		'aarch64' { '3d721f3168a990373cb2549bd26322329923014ee4613cda2ae3d4f6884bf8f7' }
		else { return error('invalid core architecture') }
	}
}

// This source scan implements the original puts("QEMU CORE PASS:...")
// grammar directly, including duplicate source markers and architecture exclusions.
pub fn source_markers(source string) []string {
	mut result := []string{}
	mut position := 0
	start := 'puts("QEMU CORE PASS:'
	for position < source.len {
		index := source[position..].index(start) or { break }
		begin := position + index + 6
		remaining := source[begin..]
		end := remaining.index('"') or { break }
		marker := remaining[..end]
		if marker.len > 'QEMU CORE PASS:'.len && !marker.contains('\n') && remaining[end..].starts_with('")') { result << marker }
		position = begin + end + 1
	}
	return result
}

pub fn core_records(raw []u8, source string, mode string, manifest map[string]json2.Any) !map[string]json2.Any {
	if mode !in ['x86_64', 'x86_64-four-level', 'aarch64'] { return error('invalid core mode') }
	output := raw.bytestr()
	arm := mode == 'aarch64'
	mut required := corepolicy.required(false, !arm)
	required << 'PAGETABLE CHECK: PASS'
	if arm { required << ['VINIX QEMU CORE PERSIST: PASS', 'AArch64 QEMU core regression passed across reboot'] }
	mut missing := []string{}
	for marker in required { if output.count(marker) != 1 { missing << marker } }
	mut failures := []string{}
	for marker in [...corepolicy.core_fail_markers, 'PAGETABLE FAIL', 'ERROR:'] { if output.contains(marker) { failures << marker } }
	markers := source_markers(source).filter(!arm || !it.contains('QEMU CORE PASS: x86-64 '))
	for marker in markers { if output.count(marker) != 1 { missing << marker } }
	mut result := manifest.clone()
	result['all_source_core_pass_marker_count'] = u64(markers.len)
	if mode == 'x86_64' {
		if output.count('PAGETABLE PASS: boundary=0x1000000000000 page=4096') != 1 || output.contains('PAGETABLE SKIP: boundary=0x1000000000000') { return error('LA57 high boundary was not checked exactly once') }
		result['la57_256tib_boundary_pass'] = true
	} else if mode == 'x86_64-four-level' {
		if output.count('PAGETABLE SKIP: boundary=0x1000000000000 CPU has four-level paging') != 1 || output.contains('PAGETABLE PASS: boundary=0x1000000000000') { return error('four-level high boundary skip was not explicit') }
		result['cpuid_la57_disabled_explicit_skip'] = true
	}
	if missing.len > 0 || failures.len > 0 { return error('missing=' + missing.str() + '; failed=' + failures.str()) }
	status := manifest['harness_exit_code'] or { manifest['exit_code'] or { json2.Any(json2.Null{}) } }
	if !is_zero(status) { return error('core harness did not succeed') }
	result['boundary_supplement_pass'] = true
	result['all_core_markers_pass'] = true
	result['pagetable_check_pass_count'] = u64(output.count('PAGETABLE CHECK: PASS'))
	result['persistent_second_boot_pass'] = arm
	result['required_marker_count'] = u64(required.len)
	return result
}

pub fn archive_bytes(path string, name string) ![]u8 {
	mut reader := tarstream.open(path)!
	defer { reader.close() }
	mut found := false
	mut bytes := []u8{}
	for {
		entry := reader.next() or { if err is tarstream.End { break }; return err }
		if entry.name != name { continue }
		if !entry.regular() { return error('embedded core payload is not regular: ' + name) }
		if entry.size > 256 * 1024 * 1024 { return error('embedded core payload is too large') }
		mut payload := []u8{cap: int(entry.size)}
		mut buffer := []u8{len: 1024 * 1024}
		for {
			count := reader.read(mut buffer)!
			if count == 0 { break }
			payload << buffer[..count]
		}
		bytes = payload.clone()
		found = true
	}
	if !found { return error('embedded core payload missing: ' + name) }
	return bytes
}

fn add_tree(mut writer tarcore.Writer, path string, name string) ! {
	mode := os.lstat(path)!.mode & 0o7777
	if os.is_link(path) {
		core_tar_member(mut writer, tarcore.Member{name: name, mode: mode, kind: `2`, linkname: os.readlink(path)!, uname: 'root', gname: 'root'}, []u8{})!
	} else if os.is_dir(path) {
		core_tar_member(mut writer, tarcore.Member{name: name, mode: mode, kind: `5`, uname: 'root', gname: 'root'}, []u8{})!
		mut entries := os.ls(path)!
		entries.sort()
		for entry in entries { add_tree(mut writer, path + '/' + entry, name + '/' + entry)! }
	} else if os.is_file(path) {
		data := os.read_bytes(path)!
		core_tar_member(mut writer, tarcore.Member{name: name, mode: mode, size: data.len, uname: 'root', gname: 'root'}, data)!
	} else { return error('unsupported core archive entry: ' + path) }
}

fn core_tar_member(mut writer tarcore.Writer, member tarcore.Member, data []u8) ! {
	if i64(data.len) != member.size { return error('core tar member size differs') }
	mut header := tarcore.header(member)!
	// Both checksum terminators are valid USTAR. These immutable core images
	// use six octal digits, NUL, space, so preserve their exact byte identity.
	header[154] = 0
	writer.write(header)!
	writer.write(data)!
	writer.padding(member.size)!
}

pub fn deterministic_archive(rootfs string, path string) ! {
	mut writer := tarcore.create(path)!
	defer { writer.close() }
	add_tree(mut writer, rootfs, '.')!
	writer.finish()!
	writer.close_checked()!
}

pub fn core_validate(context Context, state string, mode string, manifest map[string]json2.Any) !map[string]json2.Any {
	mut result := core_records(os.read_bytes(state + '/serial.log')!, text(context.state + '/core-x86_64/test.c')!, mode, manifest)!
	if mode == 'aarch64' {
		vm := state + '/vm'
		extracted := state + '/embedded-arm-kernel'
		if !os.exists(extracted) { checked(['mcopy', '-i', vm + '/boot.img', '::/boot/vinix', extracted], context.root, os.environ(), state + '/embedded-arm-check.log')! }
		checked_hash(extracted, core_kernel('aarch64')!)!
		checked_hash(context.root + '/third_party/useralloc-speed-v5/kernel/bin/vinix', core_kernel('aarch64')!)!
		result['embedded_kernel_sha256'] = digest(extracted)!
		result['root_ext2_sha256'] = digest(vm + '/root.ext2')!
		result['boot_img_sha256'] = digest(vm + '/boot.img')!
	}
	return result
}

pub fn core_checkpoint(context Context, status string, active string, extra map[string]json2.Any) ! {
	mut record := extra.clone()
	record['status'] = status
	record['updated_utc'] = now()
	record['driver_pid'] = u64(os.getpid())
	record['active_mode'] = nullable(active)
	atomic_json(context.state + '/checkpoint.json', record)!
}

pub fn core_bundle(path string) !string {
	mut bytes := os.read_bytes(path + '/test.c')!
	bytes << os.read_bytes(path + '/pagetable.c')!
	return sha256.sum(bytes).hex()
}
