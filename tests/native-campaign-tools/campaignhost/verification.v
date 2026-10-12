// SPDX-License-Identifier: GPL-2.0-or-later
module campaignhost

import comparecore
import guesthost
import json2
import os
import strconv
import tarstream

fn decimal(text string) !i64 {
	if text == '' || !text.bytes().all(it.is_digit()) {
		return error('invalid decimal verification record')
	}
	return strconv.parse_int(text, 10, 64)!
}

fn nullable(text string) json2.Any {
	return if text == '' { json2.Any(json2.Null{}) } else { json2.Any(text) }
}

fn ordered_fields(line string, prefix string, names []string) ?map[string]string {
	if !line.starts_with(prefix + ' ') { return none }
	parts := line[prefix.len + 1..].split(' ')
	if parts.len != names.len { return none }
	mut result := map[string]string{}
	for i, name in names {
		if !parts[i].starts_with(name + '=') { return none }
		result[name] = parts[i][name.len + 1..]
	}
	return result
}

pub fn verification_records(raw []u8, arch string) !map[string]json2.Any {
	output := guesthost.replacement_text(raw).replace('\r\n', '\n').replace('\r', '\n')
	lines := comparecore.lines(output)
	if ['UALLOC-FAIL', 'UALLOC-ARM-FAIL', 'CLOCK-FAIL', 'KERNEL PANIC', 'FATAL EXCEPTION'].any(output.contains(it)) {
		return error('allocator verification reported a failure')
	}
	if output.count(if arch == 'x86_64' { 'UALLOC-VERIFY-COMPLETE' } else { 'UALLOC-ARM-DONE' }) != 1 || output.count('CLOCK-DONE ') != 1 {
		return error('allocator verification completion or clock record missing')
	}
	for marker in ['UALLOC-ALL-CLASSES classes=48 burst=72 rounds=3',
		'UALLOC-THREAD-TRANSITIONS cycles=24', 'UALLOC-GROUP-REFILLS requests=18 rounds=129',
		'UALLOC-ATFORK-ALLOCATIONS phases=2 forks=8'] {
		if lines.filter(it == marker).len != 4 {
			return error('allocator verification marker count: ' + marker)
		}
	}
	mut policy := ''
	mut mode := ''
	mut cases := []json2.Any{}
	mut footprints := []json2.Any{}
	mut corruption := []json2.Any{}
	mut identities := map[string]bool{}
	mut corruption_ids := map[string]bool{}
	mut total := i64(0)
	for line in lines {
		if arch == 'x86_64' {
			if fields := ordered_fields(line, 'UALLOC-POLICY', ['policy']) {
				if fields['policy'] in ['optimized', 'disabled'] { policy = fields['policy'] }
			}
			if fields := ordered_fields(line, 'UALLOC-LINKAGE', ['policy', 'mode']) {
				if fields['policy'] in ['optimized', 'disabled'] && fields['mode'] in [
					'dynamic',
					'static',
				] {
					policy = fields['policy']
					mode = fields['mode']
				}
			}
		} else {
			if fields := ordered_fields(line, 'UALLOC-ARM-BEGIN', ['program']) {
				for p in ['optimized', 'disabled'] {
					for m in ['dynamic', 'static'] {
						if fields['program'] in ['/tests/verify-' + p + '-' + m,
							'/tests/verify-all-classes-' + p + '-' + m] {
							policy = p
							mode = m
						}
					}
				}
			}
		}
		for suite, prefix in {
			'original':     'UALLOC-DONE'
			'supplemental': 'UALLOC-SUPPLEMENT-DONE'
		} {
			if fields := ordered_fields(line, prefix, ['checks']) {
				count := decimal(fields['checks'])!
				if count != if suite == 'original' { 1910 } else { 30942 } {
					return error('allocator verification check count differs')
				}
				cases << json2.Any({
					'policy': nullable(policy)
					'mode':   nullable(mode)
					'suite':  json2.Any(suite)
					'checks': json2.Any(count)
				})
				identities[policy + ' ' + mode + ' ' + suite] = true
				total += count
			}
		}
		if fields := ordered_fields(line, 'UALLOC-FOOTPRINT', ['before', 'retained', 'trimmed']) {
			before := decimal(fields['before'])!
			retained := decimal(fields['retained'])!
			trimmed := decimal(fields['trimmed'])!
			if trimmed != before || retained - before > 12 * 1024 * 1024 {
				return error('allocator footprint bound or trim failed')
			}
			footprints << json2.Any({
				'policy':         nullable(policy)
				'mode':           nullable(mode)
				'before':         json2.Any(before)
				'retained':       json2.Any(retained)
				'trimmed':        json2.Any(trimmed)
				'retained_delta': json2.Any(retained - before)
				'trimmed_delta':  json2.Any(trimmed - before)
			})
		}
		if fields := ordered_fields(line, 'UALLOC-CORRUPTION', ['test', 'status', 'signal', 'exit']) {
			// The original record grammar admits a single test digit and a signed
			// decimal exit. A matching failed child must be rejected even when
			// sixteen other children already supplied complete coverage.
			if fields['test'].len != 1 || fields['test'] !in ['0', '1', '2', '3'] {
				continue
			}
			test := decimal(fields['test'])!
			status := decimal(fields['status'])!
			signal := decimal(fields['signal'])!
			if fields['exit'] != '-1' { return error('corruption child returned normally') }
			if test >= 0 && test <= 3 {
				if signal !in if arch == 'x86_64' { [i64(4), 6, 11] } else { [i64(4), 5, 6, 11] } || (status & 0x7f) != signal {
					return error('corruption child was not rejected by the recorded signal')
				}
				corruption << json2.Any({
					'policy': nullable(policy)
					'mode':   nullable(mode)
					'test':   json2.Any(test)
					'status': json2.Any(status)
					'signal': json2.Any(signal)
					'exit':   json2.Any(-1)
					'line':   json2.Any(line)
				})
				corruption_ids[policy + ' ' + mode + ' ' + test.str()] = true
			}
		}
	}
	if cases.len != 8 || footprints.len != 4 || corruption.len != 16 || identities.len != 8 || corruption_ids.len != 16 {
		return error('allocator verification mode coverage incomplete')
	}
	for p in ['optimized', 'disabled'] {
		for m in ['dynamic', 'static'] {
			for suite in ['original', 'supplemental'] {
				if p + ' ' + m + ' ' + suite !in identities {
					return error('allocator verification mode missing')
				}
			}
			for test in 0 .. 4 {
				if p + ' ' + m + ' ' + test.str() !in corruption_ids {
					return error('corruption mode missing')
				}
			}
		}
	}
	return {
		'cases':        json2.Any(cases)
		'total_checks': json2.Any(total)
		'footprints':   json2.Any(footprints)
		'corruption':   json2.Any(corruption)
		'clock_lines':  json2.Any(lines.filter(it.starts_with('CLOCK-')).map(json2.Any(it)))
	}
}

pub fn archive_hashes(path string, wanted []string) !map[string]string {
	mut reader := tarstream.open(path)!
	defer { reader.close() }
	mut hashes := map[string]string{}
	for {
		entry := reader.next() or {
			if err is tarstream.End { break }
			return err
		}
		if entry.name in wanted {
			if !entry.regular() { return error('embedded input is not a file: ' + entry.name) }
			hashes[entry.name] = reader.digest()!
		}
	}
	for name in wanted { if name !in hashes { return error('embedded input missing: ' + name) } }
	return hashes
}

pub fn collect_verification(context Context, arch string) !int {
	if arch !in ['x86_64', 'aarch64'] { return error('invalid verification architecture') }
	base := context.root + '/third_party/useralloc-libc/build/useralloc'
	state := if arch == 'x86_64' {
		base + '/verify-x86-v6-final'
	} else {
		context.root + '/build/useralloc-arm-v6-final'
	}
	serial := state + '/serial.log'
	mut result := verification_records(os.read_bytes(serial)!, arch)!
	config := read_json(state + '/' + if arch == 'x86_64' { 'config.json' } else { 'build.json' })!
	mut proof := if arch == 'x86_64' {
		read_json(state + '/embedded-input-check.json')!
	} else {
		map[string]json2.Any{}
	}
	if arch == 'x86_64' {
		for field, path in {
			'source_sha256':              'verify.c'
			'supplemental_source_sha256': 'verify-all-classes.c'
			'clock_source_sha256':        'clock.c'
		} {
			if config[field]!.str() != digest(context.root + '/tests/user-alloc/' + path)! {
				return error('verification source differs: ' + path)
			}
		}
	} else {
		for path in ['verify.c', 'verify-all-classes.c', 'clock.c'] {
			if config['source_sha256']!.as_map()[path]!.str() != digest(context.root + '/tests/user-alloc/' + path)! {
				return error('verification source differs: ' + path)
			}
		}
		for name, remote in {
			'embedded-kernel':        '::/boot/vinix'
			'embedded-initramfs.tar': '::/boot/initramfs.tar'
		} {
			captured(['mcopy', '-o', '-i', state + '/boot.img', remote, state + '/' + name])!
		}
		if digest(state + '/embedded-kernel')! != config['kernel_sha256']!.str() {
			return error('embedded ARM kernel differs')
		}
		artifacts := config['artifacts_sha256']!.as_map()
		wanted := artifacts.keys().map('./' + it)
		hashes := archive_hashes(state + '/embedded-initramfs.tar', wanted)!
		mut files := map[string]json2.Any{}
		for path, expected in artifacts {
			if hashes['./' + path]! != expected.str() {
				return error('embedded ARM artifact differs: ' + path)
			}
			files[path] = expected
		}
		proof = {
			'match':            json2.Any(true)
			'kernel_sha256':    json2.Any(digest(state + '/embedded-kernel')!)
			'boot_disk_sha256': json2.Any(digest(state + '/boot.img')!)
			'files_sha256':     json2.Any(files)
		}
		write_json(state + '/embedded-input-check.json', proof)!
	}
	kernel := if arch == 'x86_64' {
		'16140916ef5abca52cc6f0a8e80bb6dedc24b5e5f05efd747f57182523098e74'
	} else {
		'3d721f3168a990373cb2549bd26322329923014ee4613cda2ae3d4f6884bf8f7'
	}
	if config['kernel_sha256']!.str() != kernel || proof['kernel_sha256']!.str() != kernel || !gate_passed(proof['match']!, json2.Any(true)) {
		return error('verification kernel identity differs')
	}
	patch := 'ec459e48e5c3c9946c91e805428149802d0ab1835c64e5e023811ab54a48af1d'
	for policy in ['optimized', 'disabled'] {
		stage := base + '/' + policy + if arch == 'x86_64' {
			'-v6-final'
		} else {
			'-arm126-v6-final'
		}
		manifest := read_json(stage + '/usr/share/vinix/musl-build.json')!
		if manifest['patches']!.as_array().last().as_map()['sha256']!.str() != patch {
			return error('verification allocator patch differs')
		}
		checked_hash(stage + '/lib/ld-musl-' + arch + '.so.1', manifest['libc_so_sha256']!.str())!
		checked_hash(stage + '/usr/lib/libc.a', manifest['libc_a_sha256']!.str())!
		actual := if arch == 'x86_64' {
			config['libc_builds']!.as_map()[policy]!.as_map()
		} else {
			read_json(state + '/musl-' + policy + '.json')!
		}
		if actual != manifest { return error('executed libc manifest differs: ' + policy) }
	}
	result['passed'] = true
	result['serial_sha256'] = digest(serial)!
	result['config'] = config.clone()
	result['embedded_input_check'] = proof.clone()
	result['patch_sha256'] = patch
	result['kernel_sha256'] = kernel
	write_json(state + '/results.json', result)!
	println(arch + ' PASS ' + result['total_checks']!.str() + ' checks ' + result['corruption']!.as_array().len.str() + ' rejected corruption children')
	flush_stdout()
	return 0
}
