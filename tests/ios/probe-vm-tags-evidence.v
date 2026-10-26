// SPDX-License-Identifier: GPL-2.0-or-later
// Preserve the tagged anonymous reservation fix and its next startup boundary.
module main

import crypto.sha256
import os
import strconv

fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut buffer := []u8{len: 1024 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		count := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if count == 0 { break }
		hash.write(buffer[..count])!
	}
	return hash.sum([]u8{}).hex()
}

fn files(root string, relative string) ![]string {
	mut result := []string{}
	for name in os.ls(os.join_path(root, relative))! {
		path := if relative == '' { name } else { relative + '/' + name }
		full := root + '/' + path
		if os.is_link(full) { return error('symlink in evidence: ' + path) }
		if os.is_dir(full) { result << files(root, path)! } else { result << path }
	}
	result.sort()
	return result
}

fn safe_path(path string) bool {
	return !path.starts_with('/') && !path.contains('\\')
		&& !path.split('/').any(it in ['', '.', '..'])
}

fn require_text(out string, path string, markers []string) !string {
	text := os.read_file(out + '/' + path)!.replace('\r\n', '\n')
	for marker in markers {
		if !text.contains(marker) { return error(path + ': missing ' + marker) }
	}
	// This checkpoint records one known application panic, not a successful launch.
	expected := 'V panic: iOS: unsupported block capture disposal'
	checked := if path.ends_with('/serial.log') && text.count('V panic:') == 1
		&& text.count(expected) == 1 { text.replace(expected, 'EXPECTED-APPLICATION-STOP') } else { text }
	for bad in ['runtime error:', '> assert ', 'KERNEL PANIC', 'V panic:',
		'FATAL EXCEPTION', 'IOS-NATIVE: FAIL', 'iOS FAIL:', 'ERROR: AddressSanitizer'] {
		if checked.contains(bad) { return error(path + ': ' + bad) }
	}
	return text
}

fn probe_state(out string) !string {
	state := os.file_name(os.read_file(out + '/probe-no-ads-state.txt')!.trim_space())
	if !state.starts_with('probe-no-ads-') || !safe_path(state) { return error('invalid VM pointer') }
	for name in ['boot.img', 'efivars.fd', 'initramfs.tar.gz', 'limine.conf', 'serial.log'] {
		if !os.is_file(out + '/' + state + '/' + name) { return error('missing guest media: ' + name) }
	}
	return state
}

fn field(line string, name string) !u64 {
	if !line.contains(name + '=0x') { return error('missing ' + name) }
	return strconv.parse_uint(line.all_after(name + '=0x').all_before(' ').trim_space(), 16, 64)
}

fn vm_reservation(serial string) ! {
	expected := 'IOS-PROBE-VM: op=mmap address=0x0 size=0x600000000 args=0x3,0x1042,0xf1000000,0x0,0x0,0x0,0x0,0x0,0x0,0x0 result='
	mut found := 0
	for line in serial.split_into_lines() {
		if !line.starts_with(expected) { continue }
		result := field(line, 'result')!
		if result == 0 || result == ~u64(0) || result % 4096 != 0 {
			return error('tagged anonymous reservation failed')
		}
		found++
	}
	if found != 1 { return error('missing or repeated 24 GiB tagged reservation') }
	allocator := serial.index('Using MallocBinned3 allocator.') or { return error('missing allocator') }
	reservation := serial.index(expected) or { return error('missing reservation') }
	stop := serial.index('V panic: iOS: unsupported block capture disposal') or { return error('missing next boundary') }
	if allocator >= reservation || reservation >= stop { return error('unexpected reservation order') }
	if serial.contains('result=0xffffffffffffffff') { return error('VM call failure in tagged checkpoint') }
}

fn results(out string) ! {
	revision := os.read_file(out + '/source-revision.txt')!.trim_space()
	if revision.len != 40 || revision.bytes().any(!it.is_hex_digit()) { return error('invalid revision') }
	for path in ['source/compat/ios/faultprobe/fault.c.v', 'source/compat/ios/runner/native.c.v',
		'source/compat/ios/runner/vm_probe.c.v', 'source/compat/ios/runner/vm_probe_test.v',
		'source/tests/ios/probefault/check.c.v', 'source/tests/ios/native-init.v',
		'source/tests/ios/notification-checks.v', 'source/tests/ios/notification-vm.v',
		'source/compat/ios/runner/files.c.v', 'source/compat/ios/runner/blocks.c.v',
		'source/tests/ios/probe-vm-tags-evidence.v', 'source-files.txt', 'build-inputs.sha256',
		'notification-checks', 'notification-vm', 'probe-vm-tags-evidence', 'inventory-inputs',
		'native-init', 'native-init.c', 'run-ios-gles', 'run-ios-gles.c',
		'vm-probe-checks', 'vm-probe-checks.c',
		'application/FortniteClient-IOS-Shipping', 'application/Frameworks/EOSSDK.framework/EOSSDK',
		'application/Frameworks/MarketplaceKitWrapper.framework/MarketplaceKitWrapper'] {
		if !os.is_file(out + '/' + path) { return error('missing ' + path) }
	}
	mut seen := map[string]bool{}
	for path in os.read_lines(out + '/source-files.txt')! {
		if !safe_path(path) || path in seen { return error('invalid source path') }
		seen[path] = true
		if !os.is_file(out + '/source/' + path) { return error('missing source ' + path) }
	}
	if seen.len == 0 { return error('empty source inventory') }
	inputs := os.read_lines(out + '/build-inputs.sha256')!
	if inputs.len == 0 { return error('empty selected input inventory') }
	for line in inputs {
		if line.len < 67 || line[64..66] != '  ' || line[..64].bytes().any(!it.is_hex_digit()) {
			return error('invalid selected input record')
		}
	}
	for label in ['host-generate', 'host-object-0', 'host-object-1', 'host-object-2', 'host-object-3',
		'host-link', 'host', 'host-deterministic', 'build-init', 'build-vm-probe', 'build-run-ios-gles', 'probe-no-ads'] {
		if os.read_file(out + '/' + label + '.status.txt')!.trim_space() != '0' { return error(label + ' failed') }
		require_text(out, label + '.log', [])!
	}
	for label in ['host', 'host-deterministic'] {
		require_text(out, label + '.log', [
			'IOS-VM-PROBE: disabled mode, reserve/commit/release, Mach results, errno and failed diagnostic write PASS',
			'IOS-VM-TAGS: anonymous tags, ignored offset, unsupported flags, file descriptor/offset and fixed mapping guard PASS'])!
	}
	if digest(out + '/application/FortniteClient-IOS-Shipping')! != '6aae5109d316864fb67bea6a92046c347edbb04dc2a104c6666713da989cd373' {
		return error('unexpected application executable')
	}
	state := probe_state(out)!
	serial := require_text(out, state + '/serial.log', [
		'IOS-PROBE-BUDGET: check exceed=false wait=0',
		'IOS-PROBE-BUDGET: check exceed=true wait=9', 'oom_kill 1;',
		'IOS-PROBE-BUDGET: enforcement and supervisor isolation PASS', 'max=2147483648 ',
		'IOS-PROBE-FAULT: signal context and restoration PASS',
		'IOS-PROBE-FAULT: signal=0x000000000000000b code=0x0000000000000002',
		'IOS-VM-PROBE: disabled mode, reserve/commit/release, Mach results, errno and failed diagnostic write PASS',
		'IOS-VM-TAGS: anonymous tags, ignored offset, unsupported flags, file descriptor/offset and fixed mapping guard PASS',
		'IOS-NATIVE: /opt/ios/vm-probe-checks wait status 0',
		'iOS probe image: base=0x', 'Using MallocBinned3 allocator.',
		'V panic: iOS: unsupported block capture disposal',
		'IOS-NATIVE: /opt/ios/run-ios wait status 256',
		'FORTNITE PROBE: process exit status 1', 'FORTNITE PROBE COMPLETE'])!
	if serial.count('IOS-PROBE-FAULT: signal=') != 1 || serial.count('IOS-PROBE-REGS:') != 1 {
		return error('missing fixture context or unexpected application fault')
	}
	vm_reservation(serial)!
	for line in serial.split_into_lines() {
		if line.starts_with('IOS-PROBE-REGS:') && line.count(' x') != 31 {
			return error('incomplete ARM64 registers')
		}
	}
	mut queries := 0
	mut final_budget := false
	for line in serial.split_into_lines() {
		if line.starts_with('iOS memory: os_proc_available_memory=') {
			value := line.all_after('=')
			if value == '' || value.bytes().any(!it.is_digit()) || value.u64() == 0 || value.u64() > 2147483648 {
				return error('invalid or zero application headroom')
			}
			queries++
		}
		if line.starts_with('IOS-PROBE-BUDGET: final current=') {
			if !line.contains('oom 0;oom_kill 0;') { return error('application cgroup OOM') }
			final_budget = true
		}
	}
	if queries == 0 || !final_budget { return error('missing application memory accounting') }
	if serial.count('iOS +load: ') != 9 || serial.count('iOS startup: initializers for ') != 3
		|| serial.contains('iOS startup: application entry') { return error('unexpected startup boundary') }
}

fn seal(out string) ! {
	results(out)!
	mut lines := []string{}
	for path in files(out, '')! {
		if path != 'manifest.sha256' { lines << digest(out + '/' + path)! + '  ' + path }
	}
	os.write_file(out + '/manifest.sha256', lines.join('\n') + '\n')!
}

fn check(out string) ! {
	mut seen := map[string]bool{}
	lines := os.read_lines(out + '/manifest.sha256')!
	for line in lines {
		if line.len < 67 || line[64..66] != '  ' { return error('invalid manifest record') }
		path := line[66..]
		if line[..64].bytes().any(!it.is_hex_digit()) || !safe_path(path) || path == 'manifest.sha256' || path in seen {
			return error('unsafe or duplicate manifest path')
		}
		seen[path] = true
	}
	actual := files(out, '')!
	if actual.len != seen.len + 1 { return error('manifest file count mismatch') }
	for path in actual {
		if path != 'manifest.sha256' && path !in seen { return error('unmanifested file: ' + path) }
	}
	for line in lines {
		if digest(out + '/' + line[66..])! != line[..64] { return error('checksum mismatch: ' + line[66..]) }
	}
	results(out)!
}

fn selftest(out string) ! {
	check(out)!
	media := out + '/' + probe_state(out)! + '/boot.img'
	backup := media + '.selftest'
	if os.exists(backup) { return error('selftest backup exists') }
	os.mv(media, backup)!
	mut rejected := false
	check(out) or { rejected = true }
	os.mv(backup, media)!
	if !rejected { return error('missing guest media accepted') }
	println('missing guest media: rejected')
	log := out + '/' + probe_state(out)! + '/serial.log'
	original := os.read_file(log)!
	reservation := original.split_into_lines().filter(it.starts_with('IOS-PROBE-VM: op=mmap address=0x0 size=0x600000000 '))[0]
	result := 'result=' + reservation.all_after('result=').all_before(' ')
	for changed in [original.replace('size=0x600000000', 'size=0x600000001'),
		original.replace('0xf1000000', '0xf0000000'),
		original.replace(result, 'result=0xffffffffffffffff'),
		original.replace(result, 'result=0x0'),
		original.replace('IOS-PROBE-VM:', 'REMOVED-VM:')] {
		if changed == original { return error('selftest did not change VM diagnostics') }
		rejected = false
		vm_reservation(changed.replace('\r\n', '\n')) or { rejected = true }
		if !rejected { return error('changed VM diagnostics accepted') }
	}
	println('changed VM size, tag, failed/null result and missing trace: rejected')
	os.write_file(log, original + '\nSELFTEST-TAMPER\n')!
	rejected = false
	check(out) or { rejected = true }
	os.write_file(log, original)!
	if !rejected { return error('changed log accepted') }
	println('changed log: rejected')
	extra := out + '/selftest-unmanifested.txt'
	if os.exists(extra) { return error('selftest extra file exists') }
	os.write_file(extra, 'unmanifested\n')!
	rejected = false
	check(out) or { rejected = true }
	os.rm(extra)!
	if !rejected { return error('unmanifested file accepted') }
	println('unmanifested file: rejected')
	check(out)!
}

fn main() {
	if os.args.len != 3 { eprintln('usage: probe-vm-tags-evidence seal|check|selftest DIR | hash FILE'); exit(2) }
	if os.args[1] == 'hash' { println(digest(os.args[2]) or { eprintln(err); exit(1) }); return }
	out := os.real_path(os.args[2]); root := os.real_path(os.getwd())
	if !os.is_dir(out) || out == root || out.starts_with(root + '/') { eprintln('evidence must exist outside the repository'); exit(2) }
	match os.args[1] {
		'seal' { seal(out) or { eprintln(err); exit(1) } }
		'check' { check(out) or { eprintln(err); exit(1) } }
		'selftest' { selftest(out) or { eprintln(err); exit(1) } }
		else { eprintln('unknown mode'); exit(2) }
	}
	println('Probe VM tags evidence ' + os.args[1] + ': PASS (application startup remains incomplete)')
}
