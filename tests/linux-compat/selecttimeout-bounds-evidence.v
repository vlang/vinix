// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import selecttimeoutcheck
import ppollargscheck
import selectfdscheck
import json2
import os
import strings

fn require(good bool, reason string) ! {
	if !good { return error(reason) }
}

fn digest(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn body(source string, name string) !string {
	mut offset := 0
	mut start := -1
	for line in source.split_into_lines() {
		if !line.starts_with('\t') && line.contains(' ' + name + '(') && line.ends_with(' {') {
			require(start == -1, 'Repeated function definition')!
			start = offset
		}
		offset += line.len + 1
		if start >= 0 && line == '}' {
			return source[start..if offset <= source.len { offset } else { source.len }]
		}
	}
	return error('Missing function: ' + name)
}

fn pin(inputs map[string]string, suffix string, expected string) ! {
	mut found := 0
	for name, value in inputs {
		if name.ends_with(suffix) {
			require(value == expected, 'Different pinned input: ' + name)!
			found++
		}
	}
	require(found == 1, 'Missing/ambiguous pin: ' + suffix)!
}

fn object(path string) !map[string]json2.Any {
	return json2.decode[map[string]json2.Any](os.read_file(path)!)!
}

fn inventory(root string, relative string, mut files map[string]string) ! {
	path := if relative == '' { root } else { root + '/' + relative }
	require(!os.is_link(path), 'Unexpected artifact symlink: ' + relative)!
	if os.is_dir(path) {
		for name in os.ls(path)! {
			child := if relative == '' { name } else { relative + '/' + name }
			if child != 'manifest.json' { inventory(root, child, mut files)! }
		}
	} else {
		require(os.is_file(path), 'Unexpected artifact type: ' + relative)!
		files[relative] = digest(path)!
	}
}

fn passed(receipt map[string]json2.Any, arch string) ! {
	require(receipt['architecture']!.str() == arch && receipt['passed']!.bool()
		&& receipt['finished']!.bool() && receipt['status']!.int() == 0, 'Unfinished/failed session')!
}

// V hashes the absolute source path into the two ignored storage-loop names.
// Keep their offsets and every other C byte in the scope comparison.
fn canonical(source string) !string {
	require(source.count('__discard_') == 6, 'Different ignored storage-loop variables')!
	mut result := strings.new_builder(source.len)
	mut position := 0
	for position < source.len {
		if source[position] == `_` && position + 10 <= source.len
			&& source[position..position + 10] == '__discard_' {
			result.write_string('__discard_')
			position += '__discard_'.len
			start := position
			for position < source.len && source[position] >= `0` && source[position] <= `9` { position++ }
			require(position > start && position + 10 <= source.len
				&& source[position..position + 10] in ['_1786_1787','_1982_1983'], 'Different storage-loop identifier')!
		} else {
			result.write_u8(source[position])
			position++
		}
	}
	return result.str()
}

fn generated(before string, after string) ! {
	mut stripped := after
	helper := body(after,'selecttimeoutfixture__remaining_within_bounds')!
	prototype := helper.all_before('\n').trim_string_right(' {')+';\n'
	require(stripped.count(prototype) == 1, 'Missing bounds prototype')!
	stripped = stripped.replace(prototype,'').replace(helper+'\n','')
	old := body(before,'selecttimeoutfixture__probe')!
	new := body(after,'selecttimeoutfixture__probe')!
	require(canonical(before.replace(old,new))! == canonical(stripped)!, 'Fixture C changed outside input/bounds probe and pure helper')!
	for source in [new,helper] {
		for bad in ['memdup(','malloc(','__new_array','array_push('] {
			require(!source.contains(bad), 'Fixture allocation: '+bad)!
		}
	}
	require(old.count('alloca(') == new.count('alloca(') && new.contains('1500000')
		&& new.contains('selecttimeoutfixture__remaining_within_bounds('), 'Writeback proof or stack lifetimes changed')!
	for token in ['initial_ns < 0','elapsed_ns < 0','seconds < 0','subsecond < 0',
		'seconds >','part > (initial_ns - whole)','left >= truncated_lower'] {
		require(helper.contains(token), 'Missing bounds guard: '+token)!
	}
}

fn traces(log string) ! {
	mut count := 0
	mut coincident := 0
	for raw in log.split_into_lines() {
		if !raw.contains('SELECT-TIME: ') { continue }
		fields := raw.all_after('SELECT-TIME: ').trim_space().fields()
		require(fields.len == 3, 'Malformed clock trace')!
		mut values := []i64{}
		for index,key in ['deadline=','now=','left='] {
			require(fields[index].starts_with(key), 'Wrong trace field')!
			pair := fields[index].all_after('=').split('/')
			require(pair.len == 2, 'Malformed trace time')!
			seconds := pair[0].i64()
			nanos := pair[1].i64()
			require(seconds >= 0 && seconds < 100 && nanos >= 0 && nanos < 1_000_000_000, 'Invalid trace time')!
			values << seconds*1_000_000_000+nanos
		}
		require(values[0]-values[1] == values[2] && values[2] >= 0 && values[2] <= 500_000_000, 'Incorrect sampled remainder')!
		if values[2] == 500_000_000 { coincident++ }
		count++
	}
	require(count == 32 && coincident > 0, 'Missing coincident in-kernel samples')!
}

fn check(root string, historical string) ! {
	require(digest(historical+'/manifest.json')! == 'fa21bda6d3f7af40d1e35821ca144215c46a2a1edde7ae1e1dd962d6a994420d', 'Different historical bundle')!
	legacy := os.exec([historical+'/evidence',historical])
	require(legacy.exit_code == 0 && legacy.output.contains('Ppoll arguments evidence: PASS (639 files;'), 'Historical complete-bundle audit failed: '+legacy.output)!
	manifest := json2.decode[map[string]string](os.read_file(root+'/manifest.json')!)!
	mut found := map[string]string{}
	inventory(root,'',mut found)!
	require(found == manifest, 'Missing, extra or changed current artifact')!
	controls := object(root+'/controls/receipt.json')!
	require(controls['status']!.str() == '0' && controls['source']!.str() == digest(root+'/source/tests/linux-compat/selecttimeoutfixture/bounds.v')!
		&& controls['controller']!.str() == digest(root+'/source/tests/linux-compat/selecttimeout-bounds-check.v')!
		&& controls['compiler']!.str() == digest(root+'/v')! && controls['generated']!.str() == digest(root+'/controls/main.v')!
		&& controls['control']!.str() == digest(root+'/controls/control')!
		&& os.read_file(root+'/controls/controls.log')!.trim_space() == 'Select timeout bounds: PASS (10 positive, 16 negative controls)', 'Invalid bounds controls')!
	review := os.read_file(root+'/review.txt')!
	require(review.contains('Independent timeout-fixture review: PASS. No findings.'), 'Missing lifetime/bounds review')!
	for path in ['source/tests/linux-compat/selecttimeoutfixture/core.v','source/tests/linux-compat/selecttimeoutfixture/bounds.v',
		'source/tests/linux-compat/selecttimeoutfixture/storage.v','source/tests/linux-compat/selecttimeout-bounds-check.v',
		'source/tests/linux-compat/selecttimeout-trace.v','source/tests/linux-compat/run.v',
		'compile-arm/fixture.c','compile-x86/fixture.c','trace-pselect-r1.v','build-trace-x86-r1/blob.c'] {
		require(review.contains(digest(root+'/'+path)!), 'Outdated review: '+path)!
	}
	for pair in [['arm','aarch64'],['x86','x86_64']] {
		suffix, arch := pair[0], pair[1]
		production := root+'/production-'+suffix
		kernel := digest(production+'/kernel/bin/vinix')!
		require(kernel == digest(historical+'/build-fixed-'+suffix+'/kernel/bin/vinix')!
			&& digest(production+'/blob.c')! == digest(historical+'/build-fixed-'+suffix+'/blob.c')!, 'Production kernel changed')!
		compile := root+'/compile-'+suffix
		probe := digest(compile+'/probe')!
		compilation := object(compile+'/receipt.json')!
		require(compilation['architecture']!.str() == arch, 'Different compile architecture')!
		inputs := json2.decode[map[string]string](json2.encode(compilation['inputs']!))!
		for file in ['core.v','storage.v','bounds.v'] {
			pin(inputs,'/selecttimeoutfixture/'+file,digest(root+'/source/tests/linux-compat/selecttimeoutfixture/'+file)!)!
		}
		outputs := json2.decode[map[string]string](json2.encode(compilation['outputs']!))!
		pin(outputs,'/probe',probe)!
		pin(outputs,'/reference-init',digest(compile+'/reference-init')!)!
		generated(os.read_file(historical+'/registered-'+suffix+'/selecttimeout/fixture.c')!,os.read_file(compile+'/fixture.c')!)!
		state := root+'/native-'+suffix
		r := object(state+'/receipt.json')!
		passed(r,arch)!
		require(r['probe']!.str() == probe && digest(state+'/rootfs/sbin/init')! == probe
			&& r['kernel']!.str() == kernel && digest(state+'/kernel/bin/vinix')! == kernel
			&& r['serial']!.str() == digest(state+'/serial.log')!, 'Different native artifacts')!
		selecttimeoutcheck.verify(os.read_file(state+'/serial.log')!,arch,false,false)!
		reference := root+'/reference-'+suffix
		rr := object(reference+'/receipt.json')!
		passed(rr,arch)!
		artifacts := rr['artifacts']!.as_map()
		for key,path in {'kernel':'linux','probe':'probe','wrapper_elf':'init','initramfs':'initramfs.cpio','serial':'serial.log'} {
			require(artifacts[key]!.str() == digest(reference+'/'+path)!, 'Different reference artifact')!
		}
		require(digest(reference+'/probe')! == probe && digest(reference+'/init')! == digest(compile+'/reference-init')!, 'Different Linux probe/launcher')!
		selecttimeoutcheck.verify(os.read_file(reference+'/serial.log')!,arch,false,true)!
		registered := root+'/registered-'+suffix
		registration := object(registered+'/receipt.json')!
		require(registration['architecture']!.str() == arch && registration['kernel_sha256']!.str() == kernel
			&& digest(registered+'/kernel/bin/vinix')! == kernel, 'Different registered kernel')!
		mut names := []string{}
		for item in registration['results']!.as_array() {
			row := item.as_map()
			name := row['name']!.str()
			require(name in ['selecttimeout','ppollargs','maskwait','selectfds'] && name !in names && row['exit_code']!.int() == 0, 'Failed/missing registered case')!
			names << name
			case_state := registered+'/'+name
			require(row['init_sha256']!.str() == digest(case_state+'/init')! && row['iso_sha256']!.str() == digest(case_state+'/test.iso')!, 'Different registered executable/image')!
			files := if name == 'selecttimeout' { ['core.v','storage.v','bounds.v'] } else if name == 'maskwait' { ['core.v'] } else { ['core.v','storage.v'] }
			frozen := json2.decode[map[string]string](json2.encode(row['source_inputs']!))!
			require(frozen.len == files.len, 'Incomplete frozen fixture')!
			for file in files {
				expected := digest(root+'/source/tests/linux-compat/'+name+'fixture/'+file)!
				pin(frozen,'/'+name+'fixture/'+file,expected)!
				require(digest(registered+'/sources/'+name+'fixture/'+file)! == expected, 'Frozen source changed')!
			}
			log := os.read_file(case_state+'/serial.log')!
			if name == 'selecttimeout' { selecttimeoutcheck.verify(log,arch,false,false)! }
			else if name == 'ppollargs' { ppollargscheck.verify(log,arch,false,false)! }
			else if name == 'selectfds' { selectfdscheck.verify(log,arch,false,false)! }
			else { masked(log,arch,false)! }
		}
		require(names.len == 4, 'Missing registered cases')!
	}
	trace := root+'/build-trace-x86-r1'
	require(os.read_file(trace+'/build.log.status')!.trim_space() == '0', 'Trace build failed')!
	trace_inputs := json2.decode[map[string]string](os.read_file(trace+'/inputs.json')!)!
	pin(trace_inputs,'/kernel/file/pselect.v',digest(root+'/trace-pselect-r1.v')!)!
	trace_state := root+'/trace-native-x86'
	t := object(trace_state+'/receipt.json')!
	passed(t,'x86_64')!
	require(t['kernel']!.str() == digest(trace+'/kernel/bin/vinix')! && t['probe']!.str() == digest(historical+'/diagnostic-compile/probe')!
		&& t['serial']!.str() == digest(trace_state+'/serial.log')!, 'Different trace kernel/probe/log')!
	traces(os.read_file(trace_state+'/serial.log')!)!
	println('Select timeout bounds evidence: PASS ('+manifest.len.str()+' files; complete historical audit, coincident kernel samples, 26 controls, fresh native/Linux probes, flat storage, 4/4 registered cases per architecture; unchanged production kernels and historical checkers)')
}

fn main() {
	if os.args.len != 3 { panic('Usage: selecttimeout-bounds-evidence BUNDLE HISTORICAL-PPOLL-BUNDLE') }
	check(os.args[1],os.args[2]) or { panic(err) }
}

fn case_lines() []string {
 mut result := []string{}
 for ordinary in 0 .. 2 { for signal in [10, 12] { for kind in 0 .. 6 { for mode in 0 .. 4 {
  checks := 11 + (if mode == 1 { 3 } else { 0 }) + (if kind in [1, 2, 3, 4] { 2 } else { 0 })
  result << 'LINUX MASKWAIT CASE: uid=' + if ordinary == 0 { '0 gid=0' } else { '1000 gid=2000' }
   + ' signal=' + signal.str() + ' wait=' + kind.str() + ' mode=' + mode.str() + ' checks=' + checks.str() + ' failures=0'
 } } } }
 return result
}
fn masked(text string, arch string, reference bool) ! {
 if arch !in ['aarch64', 'x86_64'] || (reference && !text.contains('Linux version ')) { return error('Reference architecture or Linux boot missing') }
 for bad in ['LINUX MASKWAIT FAIL', 'LINUX MASKWAIT: FAIL', 'LINUX MASKWAIT MISMATCH', 'REFERENCE FAIL', 'Kernel panic', 'BUG:', 'KERNEL PANIC', 'FATAL EXCEPTION'] {
  if text.contains(bad) { return error('Reference failure: ' + bad) }
 }
 mut expected := case_lines()
 expected << ['LINUX MASKWAIT: PASS', 'LINUX MASKWAIT SUMMARY: checks=1256 failures=0']
 mut counts := map[string]int{}
 for raw in text.split_into_lines() {
  line := raw.trim_space()
  if line.starts_with('LINUX MASKWAIT') {
   if line !in expected { return error('Unexpected reference case or summary: ' + line) }
  }
  counts[line]++
 }
 for line in expected { if counts[line] != 1 { return error('Missing or repeated result: ' + line) } }
}
