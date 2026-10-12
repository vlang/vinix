// SPDX-License-Identifier: GPL-2.0-or-later
module main

import campaignhost
import crypto.sha256
import hosttest
import json2
import math
import os

fn numeric(value json2.Any) bool { return value is int || value is i64 || value is u64 || value is f64 }

fn equivalent(actual json2.Any, expected json2.Any, at string) ! {
	if numeric(actual) && numeric(expected) {
		if math.abs(actual.f64() - expected.f64()) > 1e-12 * math.max(1, math.abs(expected.f64())) { return error('numeric evidence differs: ' + at + ' ' + actual.str() + ' ' + expected.str()) }
		return
	}
	if actual is map[string]json2.Any && expected is map[string]json2.Any {
		if actual.len != expected.len { return error('evidence key count differs: ' + at) }
		for key, value in expected { equivalent(actual[key]!, value, at + '/' + key)! }
		return
	}
	if actual is []json2.Any && expected is []json2.Any {
		if actual.len != expected.len { return error('evidence row count differs: ' + at) }
		for i, value in expected { equivalent(actual[i], value, at + '/' + i.str())! }
		return
	}
	if actual != expected { return error('evidence differs: ' + at + ' ' + actual.str() + ' ' + expected.str()) }
}

fn verification_cases(base string) ! {
	for arch, directory in {'x86_64': 'allocator-x86_64', 'aarch64': 'allocator-aarch64'} {
		bytes := os.read_bytes(base + '/' + directory + '/serial.log')!
		expected := campaignhost.read_json(base + '/' + directory + '/results.json')!
		actual := campaignhost.verification_records(bytes, arch)!
		for key, value in actual { equivalent(value, expected[key]!, arch + '/' + key)! }
		original := bytes.bytestr()
		for changed in [original.replace('checks=1910', 'checks=1909'), original.replace('UALLOC-FOOTPRINT before=', 'BROKEN before='), original.replace('UALLOC-CORRUPTION test=3', 'UALLOC-CORRUPTION test=2'), original + '\nUALLOC-FAIL\n', original + '\nUALLOC-CORRUPTION test=0 status=0 signal=0 exit=0\n', original.replace('CLOCK-DONE ', 'CLOCK-MISSING ')] {
			campaignhost.verification_records(changed.bytes(), arch) or { continue }
			return error('verification mutation accepted: ' + arch)
		}
	}
	println('VERIFICATION / both immutable guest captures / eight suites / four footprints / sixteen corruption children / independent record failures: PASS')
}

fn report_cases(base string) ! {
	directory := base + '/v5-hot-diagnostic'
	mut serials := [][]u8{}
	mut serial_hashes := []string{}
	mut config_hashes := []string{}
	for ordinal in [1, 2] {
		prefix := directory + '/boot-' + ordinal.str()
		serials << os.read_bytes(prefix + '/serial.log')!
		serial_hashes << campaignhost.digest(prefix + '/serial.log')!
		config_hashes << campaignhost.digest(prefix + '/config.json')!
	}
	actual := campaignhost.diagnostic_report(serials, serial_hashes, config_hashes)!
	expected := campaignhost.read_json(directory + '/summary.json')!
	equivalent(actual, expected, 'diagnostic')!
	for old, replacement in {'checksum=51000000': 'checksum=51000001', 'sample=7': 'sample=8', 'eligible=32': 'eligible=31', 'need_locks=0': 'need_locks=1', 'mem_page_offset=16': 'mem_page_offset=17', 'DIAG-GUEST-DONE': 'DIAG-GUEST-BROKEN', 'linkage=dynamic': 'linkage=invalid', 'exit_code=0': 'exit_code=1'} {
		mut altered := serials.clone()
		altered[0] = serials[0].bytestr().replace(old, replacement).bytes()
		if altered[0] == serials[0] { return error('missing independent diagnostic mutation: ' + old) }
		campaignhost.diagnostic_report(altered, serial_hashes, config_hashes) or { continue }
		return error('diagnostic mutation accepted: ' + old)
	}
	println('HOT DIAGNOSTIC / two immutable boots / twelve fresh executions / all 168 samples / sampled state and probes / exact retained aggregate report / independent failures: PASS')
}

fn ar_fixture(bodies [][]u8) []u8 {
	mut result := '!<arch>\n'.bytes()
	for body in bodies {
		header := padded('malloc.o/', 16) + padded('0', 12) + padded('0', 6) + padded('0', 6) + padded('100644', 8) + padded(body.len.str(), 10) + '`\n'
		result << header.bytes()
		result << body
		if body.len & 1 == 1 { result << u8(`\n`) }
	}
	return result
}

fn padded(value string, width int) string { return value + ' '.repeat(width - value.len) }

fn object_cases(base string) ! {
	body := 'exact allocator object'.bytes()
	archive := ar_fixture(['public wrapper'.bytes(), body, 'another wrapper'.bytes()])
	members := campaignhost.archive_members(archive)!
	assert members['malloc.o']!.len == 3
	assert members['malloc.o']!.filter(it == body).len == 1
	assert members['malloc.o']![1] == body
	mut extra := archive.clone()
	extra << u8(0)
	for broken in [archive[..archive.len - 1], 'bad archive'.bytes(), archive[..20], archive[..68], extra] {
		campaignhost.archive_members(broken) or { continue }
		return error('malformed ar archive accepted')
	}
	assert campaignhost.instruction_position(' 1: bl target', ['call', 'bl']) >= 0
	assert campaignhost.instruction_position(' symbol_call target', ['call', 'bl']) == -1
	assert campaignhost.instruction_position(' callq target', ['call', 'bl']) == -1
	proof := campaignhost.read_json(base + '/independent-review/object-proof.json')!
	assert proof['object_count']!.u64() == 24
	for stage, value in proof['stages']!.as_map() {
		for name, object in value.as_map()['objects']!.as_map() {
			row := object.as_map()
			path := base + '/independent-review/' + stage + '-' + name.all_before('.') + '-' + name.all_after('.') + '.asm'
			assembly := os.read_file(path)!
			assert sha256.sum(assembly.bytes()).hex() == row['assembly_sha256']!.str()
			symbol := {'malloc': '__libc_malloc_impl', 'free': '__libc_free', 'realloc': '__libc_realloc'}[name.all_before('.')]!
			function := campaignhost.assembly_function(assembly, symbol)!
			assert function.contains('__stack_chk_fail') == row['function_has_stack_canary_reference']!.bool()
			calls := function.split_into_lines().filter(campaignhost.instruction_position(it, ['call', 'bl']) >= 0).map(it.trim_space())
			assert calls == row['function_calls']!.as_array().map(it.str())
		}
	}
	println('OBJECT PROOF / repeated ar members / malformed archive bounds / all 24 immutable assembly functions / exact calls and canary findings: PASS')
}

fn main() {
	base := hosttest.root() + '/tests/alloc-bench/results/2026-10-03-userspace-v6/validation'
	verification_cases(base) or { eprintln(err); exit(1) }
	report_cases(base) or { eprintln(err); exit(1) }
	object_cases(base) or { eprintln(err); exit(1) }
}
