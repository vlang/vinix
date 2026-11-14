// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import selecttimeoutcheck
import selectordercheck
import selectfdscheck
import selectcheck
import json2
import os

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

fn allocation_groups(text string) ![]string {
	for line in ['aarch64: 806 source files, 391 allocation sites (V exit 0)',
		'x86_64: 800 source files, 291 allocation sites (V exit 0)'] {
		require(text.split_into_lines().filter(it == line).len == 1, 'Incomplete allocation scan')!
	}
	mut groups := text.split_into_lines().filter(it.starts_with('NEW: '))
	groups.sort()
	require(groups.len == 180, 'Different baseline allocation excess groups')!
	return groups
}

fn generated(before string, after string) ! {
	mut stripped := after
	mut new_helpers := ''
	for name in ['file__select_deadline','file__select_remaining','file__select_finish_timeout'] {
		helper := body(after,name)!
		prototype := helper.all_before('\n').trim_string_right(' {')+';\n'
		require(stripped.count(prototype) == 1, 'Missing/repeated helper prototype')!
		stripped = stripped.replace(prototype,'').replace(helper+'\n','')
		new_helpers += helper
	}
	mut reconstructed := before
	mut old_all, mut new_all := '', new_helpers
	for name in ['file__do_select','file__syscall_pselect6','file__syscall_select'] {
		if !before.contains(' '+name+'(') { continue }
		old := body(before,name)!
		current := body(after,name)!
		reconstructed = reconstructed.replace(old,current)
		old_all += old; new_all += current
	}
	require(reconstructed == stripped, 'Generated C changed outside select timeout functions')!
	for token in ['__new_array','array_push(','array__free(','string__clone(',
		'malloc(','memdup(','refcount','file__ppoll(','proc__begin_wait_mask(',
		'time__new_timer(','time__Timer__disarm(','event__await_one('] {
		require(old_all.count(token) == new_all.count(token), 'Allocation, cleanup or wait count changed: '+token)!
	}
	require(new_all.count('vinix_stack_alloc(') == old_all.count('vinix_stack_alloc(')+1,
		'Timeout output is not one explicit stack slot')!
	finish := body(after,'file__select_finish_timeout')!
	require(finish.contains('address == 0') && finish.contains('deadline.tv_sec == 0')
		&& finish.contains('deadline.tv_nsec == 0') && finish.contains('file__select_remaining(deadline)')
		&& finish.contains('remaining->tv_nsec /= 1000')
		&& finish.count('usercopy__copy_to_user(') == 1 && !finish.contains('errno__'),
		'Missing zero/null guard, remainder, timeval truncation or result preservation')!
	for name in ['file__syscall_pselect6','file__syscall_select'] {
		if !after.contains(' '+name+'(') { continue }
		entry := body(after,name)!
		deadline := entry.index('file__select_deadline(') or { return error('Missing deadline at import') }
		core := entry.index('file__do_select(') or { return error('Missing select call') }
		writeback := entry.index('file__select_finish_timeout(') or { return error('Missing timeout writeback') }
		require(deadline < core && core < writeback, 'Wrong deadline/writeback order')!
		if name == 'file__syscall_pselect6' {
			mask := entry.index('proc__begin_wait_mask(') or { return error('Missing mask validation') }
			require(deadline < mask && mask < core && entry.contains('deadline, false)'), 'Wrong pselect mask/deadline order or timeout ABI')!
		} else { require(entry.contains('deadline, true)'), 'Wrong select timeout ABI')! }
	}
	deadline := body(after,'file__select_deadline')!
	require(deadline.contains('time__clock_type_monotonic')
		&& deadline.contains('if (duration.tv_sec > (((i64)(0x7fffffffffffffff) - now.tv_sec) - carry))')
		&& deadline.contains('.tv_sec = (i64)(0x7fffffffffffffff), .tv_nsec = 0')
		&& deadline.contains('i64 _t2 = (i64)(1000000000)')
		&& deadline.contains('i64 _t4 = (i64)(1000000000)'), 'Missing saturated monotonic arithmetic')!
	require(body(after,'file__select_remaining')!.contains('time__TimeSpec__sub('), 'Missing expired-time clamp')!
	require(body(after,'file__do_select')!.count('file__select_remaining(deadline)') == 2, 'Waits do not use the imported deadline')!
}

fn altered(source string, name string, old string, replacement string) !string {
	current := body(source,name)!
	require(current.contains(old), 'Ineffective generated-C mutation: '+old)!
	return source.replace(current,current.replace(old,replacement))
}

fn generated_controls(before string, after string) ! {
	generated(before,after)!
	mut negatives := 0
	for bad in [after+'void unrelated(void) {}',
		altered(after,'file__select_finish_timeout','remaining->tv_nsec /= 1000','remaining->tv_nsec /= 1')!,
		altered(after,'file__syscall_pselect6','file__select_finish_timeout(timeout, deadline, false)','file__select_finish_timeout(timeout, deadline, true)')!,
		altered(after,'file__do_select','file__select_remaining(deadline)','deadline')!,
		altered(after,'file__select_finish_timeout','address == 0','address == 1')!,
		altered(after,'file__select_deadline','i64 _t4 = (i64)(1000000000)','i64 _t4 = (i64)(1)')!,
		altered(after,'file__select_remaining','time__TimeSpec__sub(','time__other_sub(')!,
		altered(after,'file__select_finish_timeout','usercopy__copy_to_user(address,','errno__set(14);\n\tusercopy__copy_to_user(address,')!,
		altered(after,'file__select_finish_timeout','vinix_stack_alloc(sizeof(time__TimeSpec))','memdup(0,sizeof(time__TimeSpec))')!] {
		require(bad != after, 'Ineffective generated-C mutation')!
		generated(before,bad) or { negatives++; continue }
		return error('Invalid select timeout C accepted')
	}
	println('Select timeout C controls: PASS (1 positive, '+negatives.str()+' negative)')
}

fn check(root string) ! {
	manifest := json2.decode[map[string]string](os.read_file(root+'/manifest.json')!)!
	mut actual := map[string]string{}
	inventory(root, '', mut actual)!
	require(actual == manifest, 'Missing, extra or changed bundle artifact')!
	require(allocation_groups(os.read_file(root+'/allocs-original.log')!)! ==
		allocation_groups(os.read_file(root+'/allocs-fixed.log')!)!, 'Allocation excess groups changed')!
	review := os.read_file(root+'/review.txt')!
	require(review.contains('Independent lifetime review: PASS. No findings.'), 'Missing lifetime review')!
	for path in ['source/fixed/pselect.v','source/tests/linux-compat/selecttimeoutfixture/core.v',
		'source/tests/linux-compat/selecttimeoutfixture/storage.v','build-fixed-arm/blob.c',
		'build-fixed-x86/blob.c','compile-arm-r1/fixture.c','compile-x86-r1/fixture.c'] {
		require(review.contains(digest(root+'/'+path)!), 'Lifetime review does not match tested input: '+path)!
	}
	for pair in [['arm','aarch64'],['x86','x86_64']] {
		suffix, arch := pair[0], pair[1]
		compile := root+'/compile-'+suffix+'-r1'
		probe := digest(compile+'/probe')!
		compilation := object(compile+'/receipt.json')!
		require(compilation['architecture']!.str() == arch, 'Different compile architecture')!
		inputs := json2.decode[map[string]string](json2.encode(compilation['inputs']!))!
		for name in ['core.v','storage.v'] {
			pin(inputs, '/selecttimeoutfixture/'+name, digest(root+'/source/tests/linux-compat/selecttimeoutfixture/'+name)!)!
		}
		pin(inputs, '/selecttimeoutreferenceinit/core.v', digest(root+'/source/tests/linux-compat/selecttimeoutreferenceinit/core.v')!)!
		outputs := json2.decode[map[string]string](json2.encode(compilation['outputs']!))!
		pin(outputs, '/probe', probe)!
		pin(outputs, '/reference-init', digest(compile+'/reference-init')!)!
		fixture_c := os.read_file(compile+'/fixture.c')!
		require(!fixture_c.contains('memdup(') && !fixture_c.contains('malloc(')
			&& fixture_c.contains('selecttimeoutfixture__State* scratch =')
			&& fixture_c.contains('alloca((size_t)(sizeof(selecttimeoutfixture__State)))')
			&& fixture_c.contains('__atomic_store_n(&s->entered, 1, 5)')
			&& fixture_c.contains('__atomic_load_n(&s->done, 5)'), 'Fixture storage/atomic lowering changed')!
		for mode in ['original','fixed'] {
			build := root+'/build-'+mode+'-'+suffix
			kernel := digest(build+'/kernel/bin/vinix')!
			require(os.read_file(build+'/build.log.status')!.trim_space() == '0', 'Kernel build failed')!
			build_outputs := json2.decode[map[string]string](os.read_file(build+'/outputs.json')!)!
			pin(build_outputs, '/kernel/bin/vinix', kernel)!
			pin(build_outputs, '/blob.c', digest(build+'/blob.c')!)!
			build_inputs := json2.decode[map[string]string](os.read_file(build+'/inputs.json')!)!
			pin(build_inputs, '/kernel/file/pselect.v', digest(root+'/source/'+mode+'/pselect.v')!)!
			state := root+'/'+mode+'-'+suffix
			receipt := object(state+'/receipt.json')!
			passed(receipt,arch)!
			require(receipt['probe']!.str() == probe && digest(state+'/rootfs/sbin/init')! == probe
				&& receipt['kernel']!.str() == kernel && digest(state+'/kernel/bin/vinix')! == kernel
				&& receipt['serial']!.str() == digest(state+'/serial.log')!, 'Different native artifacts')!
			pins := json2.decode[map[string]string](os.read_file(state+'/inputs.json')!)!
			pin(pins, '/probe',probe)!
			pin(pins, '/kernel/bin/vinix',kernel)!
			selecttimeoutcheck.verify(os.read_file(state+'/serial.log')!,arch,mode == 'original',false)!
		}
		generated(os.read_file(root+'/build-original-'+suffix+'/blob.c')!,os.read_file(root+'/build-fixed-'+suffix+'/blob.c')!)!
		old_inputs := json2.decode[map[string]string](os.read_file(root+'/build-original-'+suffix+'/inputs.json')!)!
		new_inputs := json2.decode[map[string]string](os.read_file(root+'/build-fixed-'+suffix+'/inputs.json')!)!
		require(old_inputs.len == new_inputs.len, 'Build input set changed')!
		for path,value in old_inputs {
			if !path.ends_with('/kernel/file/pselect.v') { require(new_inputs[path] == value, 'Other build input changed: '+path)! }
		}
		reference := root+'/reference-'+suffix
		r := object(reference+'/receipt.json')!
		passed(r,arch)!
		require(digest(reference+'/probe')! == probe && digest(reference+'/init')! == digest(compile+'/reference-init')!, 'Different Linux probe/launcher')!
		artifacts := r['artifacts']!.as_map()
		for key,path in {'kernel':'linux','probe':'probe','wrapper_elf':'init','initramfs':'initramfs.cpio','serial':'serial.log'} {
			require(artifacts[key]!.str() == digest(reference+'/'+path)!, 'Different Linux artifact: '+key)!
		}
		require(artifacts['wrapper_source']!.str() == digest(root+'/source/tests/linux-compat/selecttimeoutreferenceinit/core.v')!, 'Different Linux wrapper')!
		selecttimeoutcheck.verify(os.read_file(reference+'/serial.log')!,arch,false,true)!
		kernel := digest(root+'/build-fixed-'+suffix+'/kernel/bin/vinix')!
		registered := root+'/registered-'+suffix
		registration := object(registered+'/receipt.json')!
		require(registration['architecture']!.str() == arch && registration['kernel_sha256']!.str() == kernel
			&& digest(registered+'/kernel/bin/vinix')! == kernel, 'Different registered kernel')!
		mut names := []string{}
		for item in registration['results']!.as_array() {
			row := item.as_map()
			name := row['name']!.str()
			require(name in ['selecttimeout','selectorder','selectempty','maskwait','selectfds'] && name !in names && row['exit_code']!.int() == 0, 'Different registered case')!
			names << name
			state := registered+'/'+name
			require(row['init_sha256']!.str() == digest(state+'/init')!
				&& row['iso_sha256']!.str() == digest(state+'/test.iso')!, 'Different registered artifacts')!
			frozen := json2.decode[map[string]string](json2.encode(row['source_inputs']!))!
			files := if name != 'maskwait' { ['core.v','storage.v'] } else { ['core.v'] }
			require(frozen.len == files.len, 'Incomplete frozen fixture')!
			for file in files {
				expected := digest(root+'/source/tests/linux-compat/'+name+'fixture/'+file)!
				pin(frozen,'/'+name+'fixture/'+file,expected)!
				require(digest(registered+'/sources/'+name+'fixture/'+file)! == expected, 'Different frozen source')!
			}
			log := os.read_file(state+'/serial.log')!
			if name == 'selecttimeout' { selecttimeoutcheck.verify(log,arch,false,false)! }
			else if name == 'selectorder' { selectordercheck.verify(log,arch,false,false)! }
			else if name == 'selectempty' { selectcheck.verify(log,arch,false,false)! }
			else if name == 'selectfds' { selectfdscheck.verify(log,arch,false,false)! }
			else { masked(log,arch,false)! }
		}
		require(names.len == 5, 'Missing registered cases')!
	}
	println('Select timeout evidence: PASS ('+manifest.len.str()+' files; original/fixed/Linux comparisons, generated C, flat storage and 5 registered cases per architecture)')
}

fn main() {
	if os.args.len == 2 && os.args[1] == 'self-test' { selecttimeoutcheck.self_test() or { panic(err) }; return }
	if os.args.len == 4 && os.args[1] == 'generated' {
		generated_controls(os.read_file(os.args[2])!,os.read_file(os.args[3])!) or { panic(err) }
		println('Select timeout generated-C scope: PASS'); return
	}
	if os.args.len != 2 { panic('Usage: selecttimeout-evidence self-test|BUNDLE; generated BEFORE-C AFTER-C') }
	check(os.args[1]) or { panic(err) }
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
