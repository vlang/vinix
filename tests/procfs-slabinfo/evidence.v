// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os
import strconv

fn require(ok bool, why string) ! { if !ok { return error(why) } }
fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn object(path string) !map[string]json2.Any {
	return json2.decode[map[string]json2.Any](os.read_file(path)!)!
}
fn equal_pair(text string, zero bool) ! {
	parts := text.split('/')
	require(parts.len == 2, 'counter pair required')!
	for part in parts {
		require(part.len != 0 && (part == '0' || !part.starts_with('0'))
			&& part.bytes().all(it >= `0` && it <= `9`), 'noncanonical counter')!
		_ := strconv.parse_uint(part, 10, 64)!
	}
	require(parts[0] == parts[1] && (!zero || parts[0] == '0'), 'storage is not flat/clean')!
}

fn transcript(raw string, arch string) ! {
	for bad in ['FAIL', 'KERNEL PANIC', 'FATAL EXCEPTION', 'V panic:'] {
		require(!raw.contains(bad), 'failure marker: ' + bad)!
	}
	mut rows := []string{}
	for row in raw.split('\n') {
		if row.starts_with('SLABINFO ') || row.starts_with('LINUX SLABINFO') { rows << row.trim_right('\r') }
	}
	mut sizes := [u64(16), 32, 48, 64, 96, 128, 192, 256, 384, 512, 768, 1024, 1536, 2048]
	if arch == 'aarch64' { sizes << [u64(2688), 4048, 5392, 8096] }
	require(rows.len == 2 * (10 + sizes.len) + 2, 'incomplete native transcript')!
	mut index := 0
	for uid in [0, 1000] {
		for chunk in [1, 2, 7, 19, 31, 127, 4096] {
			fields := rows[index].fields()
			require(fields.len == 5 && fields[..3] == ['SLABINFO', 'CHUNK', 'count=${chunk}']
				&& fields[3].starts_with('bytes=') && fields[3].all_after('bytes=').int() in 1 .. 4096
				&& fields[4] == 'PASS', 'missing/reordered partial read')!
			index++
		}
		require(rows[index].starts_with('SLABINFO SEMANTICS chunks=7 bytes=') && rows[index].ends_with(' PASS'),
			'missing native read semantics')!
		index++
		for size in sizes {
			fields := rows[index].fields()
			require(fields.len == 6 && fields[..4] == ['SLABINFO', 'CLASS', 'uid=${uid}', 'size=${size}']
				&& fields[4].starts_with('objects=') && fields[5].starts_with('pages='), 'class coverage differs')!
			equal_pair(fields[4].all_after('objects='), false)!
			equal_pair(fields[5].all_after('pages='), false)!
			index++
		}
		fields := rows[index].fields()
		require(fields.len == 5 && fields[..3] == ['SLABINFO', 'STORAGE', 'uid=${uid}']
			&& fields[3].starts_with('large=') && fields[4].starts_with('written='), 'missing native storage')!
		equal_pair(fields[3].all_after('large='), false)!
		equal_pair(fields[4].all_after('written='), true)!
		index++
		require(rows[index] == 'SLABINFO COHORT uid=${uid} reads=200 PASS', 'missing measured cohort')!
		index++
	}
	require(rows[index..] == ['SLABINFO SUMMARY cohorts=2 reads=400 PASS', 'LINUX SLABINFO: PASS'], 'missing completion')!
}

fn controls(raw string, arch string) !int {
	text := raw.replace('\r', '')
	mut bad := [text + 'KERNEL PANIC\n', text + 'FATAL EXCEPTION\n',
		text.replace('reads=200', 'reads=199'), text.replace('written=0/0', 'written=1/1')]
	for row in text.split_into_lines() {
		if row.starts_with('SLABINFO ') || row.starts_with('LINUX SLABINFO') {
			bad << text.replace_once(row + '\n', '')
			bad << text + row + '\n'
		}
	}
	mut refused := 0
	for candidate in bad {
		transcript(candidate, arch) or { refused++; continue }
		return error('missed transcript corruption')
	}
	return refused
}

fn run() ! {
	if os.args.len != 2 { return error('usage: evidence COMPLETE-FOCUSED-STATE') }
	state := os.real_path(os.args[1])
	mut result := map[string]string{}
	for arch in ['arm', 'x86'] {
		machine := if arch == 'arm' { 'aarch64' } else { 'x86_64' }
		for kind in ['baseline', 'fixed'] {
			build := state + '/build-' + kind + '-' + arch + if arch == 'arm' {
				if kind == 'fixed' { '-final' } else { '' }
			} else { '-r2' }
			require(os.read_file(build + '/build.log.status')!.trim_space() == '0', 'kernel build failed')!
			for path, pin in json2.decode[map[string]string](os.read_file(build + '/outputs.json')!)! {
				require(hash(path)! == pin, 'changed kernel output: ' + path)!
			}
			native := state + '/native-' + kind + '-' + arch + '-r4'
			r := object(native + '/receipt.json')!
			require(r['architecture']!.str() == machine && r['finished']!.bool() && r['passed']!.bool()
				&& r['status']!.int() == 0, 'native session failed')!
			require(r['kernel_sha256']!.str() == hash(build + '/kernel/bin/vinix')!
				&& r['probe_sha256']!.str() == hash(state + '/native-build-' + arch + '-r4/native')!
				&& r['serial_sha256']!.str() == hash(native + '/serial.log')!, 'native artifact differs')!
			for path, pin in r['inputs']!.as_map() { require(hash(path)! == pin.str(), 'changed native input: ' + path)! }
			raw := os.read_file(native + '/serial.log')!
			transcript(raw, machine)!
			result[kind + ':' + machine + ':transcript_refusals'] = controls(raw, machine)!.str()
			result[kind + ':' + machine] = hash(native + '/receipt.json')!
		}
		generated := object(state + '/generated-' + arch + '.json')!
		fixed := state + '/build-fixed-' + arch + if arch == 'arm' { '-final' } else { '-r2' }
		require(generated['blob_sha256']!.str() == hash(fixed + '/blob.c')!
			&& generated['allocation_refusals']!.int() == 13
			&& generated['functions']!.as_map().len == 13, 'incomplete generated-C scope')!
	}
	mut refusals := map[string][]string{}
	for kind in ['baseline', 'fixed'] {
		for row in os.read_file(state + '/allocations-' + kind + '.log')!.split_into_lines() {
			if row.starts_with('NEW: ') { refusals[kind] << row }
		}
	}
	require(refusals['baseline'].len > 0 && refusals['baseline'] == refusals['fixed'], 'allocation-policy refusals changed')!
	result['lifetime_review'] = hash(state + '/lifetime-review.md')!
	result['allocation_policy'] = 'both refused identically; no allowances changed'
	println(json2.encode(result, prettify: true))
}

fn main() { run() or { eprintln(err); exit(1) } }
