// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
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

fn generated(before string, after string) ! {
	mut reconstructed := before
	mut old_all, mut new_all := '', ''
	for name in ['file__do_select','file__syscall_pselect6','file__syscall_select'] {
		if !before.contains(' '+name+'(') { continue }
		old := body(before,name)!
		current := body(after,name)!
		reconstructed = reconstructed.replace(old,current)
		old_all += old; new_all += current
		if name == 'file__do_select' {
			old_proto := old.all_before('\n').trim_string_right(' {')+';\n'
			new_proto := current.all_before('\n').trim_string_right(' {')+';\n'
			require(reconstructed.count(old_proto) == 1, 'Different select helper declaration')!
			reconstructed = reconstructed.replace(old_proto,new_proto)
		}
	}
	require(reconstructed == after, 'Generated C changed outside select entrypoints/helper')!
	for token in ['__new_array','array_push(','array__free(','string__clone(','vinix_stack_alloc(',
		'malloc(','memdup(','refcount','file__ppoll(','proc__begin_wait_mask('] {
		require(old_all.count(token) == new_all.count(token), 'Allocation, cleanup or wait count changed: '+token)!
	}
	entry := body(after,'file__syscall_pselect6')!
	pack := entry.index('usercopy__copy_from_user((void*)(&arg), sigmask, sizeof(file__SigmaskArg))') or { return error('Missing pack import') }
	timer := entry.index('usercopy__copy_from_user((void*)(&deadline), timeout, sizeof(time__TimeSpec))') or { return error('Missing timeout import') }
	size := entry.index('arg.size != sizeof(u64)') or { return error('Missing mask size check') }
	mask := entry.index('usercopy__copy_from_user((void*)(&wanted), arg.mask, sizeof(u64))') or { return error('Missing mask import') }
	install := entry.index('proc__begin_wait_mask(masked_thread, wanted)') or { return error('Missing mask installation') }
	core := entry.index('file__do_select(') or { return error('Missing select helper call') }
	require(pack < timer && timer < size && size < mask && mask < install && install < core
		&& !entry.contains('nfds < 0') && entry.contains('file__SigmaskArg arg =') && entry.contains('u64 wanted ='), 'Wrong pselect import/validation order or stack storage')!
	helper := body(after,'file__do_select')!
	count := helper.index('nfds < 0') or { return error('Missing count guard') }
	sets := helper.index('file__read_fd_set(') or { return error('Missing bitmap import') }
	require(count < sets && !helper.contains('SigmaskArg') && !helper.contains('begin_wait_mask'), 'Core validates mask late or imports sets before count')!
	if after.contains(' file__syscall_select(') {
		select_entry := body(after,'file__syscall_select')!
		require(!select_entry.contains('nfds < 0') && select_entry.contains('usercopy__copy_from_user('), 'Raw select checks count before timeout')!
	}
}

fn generated_controls(before string, after string) ! {
	generated(before,after)!
	mut negatives := 0
	for bad in [after+'void unrelated(void) {}',after.replace('arg.size != sizeof(u64)','arg.size == sizeof(u64)'),
		after.replace('proc__begin_wait_mask(masked_thread, wanted)','proc__begin_wait_mask(masked_thread, 0)'),
		after.replace('i64 nfds = (i64)((i32)(nfds_word));','i64 nfds = (i64)((i32)(nfds_word));\n\tif (nfds < 0) return (multi_return_u64_u64){errno__err, errno__einval};'),
		after.replace('file__SigmaskArg arg =','file__SigmaskArg arg = memdup(0,8);\n\tfile__SigmaskArg extra ='),
		after.replace('file__ppoll(NULL, 0, NULL, NULL)','file__other_wait(NULL, 0, NULL, NULL)')] {
		generated(before,bad) or { negatives++; continue }
		return error('Invalid select argument-order C accepted')
	}
	println('Select argument-order C controls: PASS (1 positive, '+negatives.str()+' negative)')
}

fn check(root string) ! {
	manifest := json2.decode[map[string]string](os.read_file(root+'/manifest.json')!)!
	mut actual := map[string]string{}
	inventory(root, '', mut actual)!
	require(actual == manifest, 'Missing, extra or changed bundle artifact')!
	for pair in [['arm','aarch64'],['x86','x86_64']] {
		suffix, arch := pair[0], pair[1]
		compile := root+'/compile-'+suffix+'-r1'
		probe := digest(compile+'/probe')!
		compilation := object(compile+'/receipt.json')!
		require(compilation['architecture']!.str() == arch, 'Different compile architecture')!
		inputs := json2.decode[map[string]string](json2.encode(compilation['inputs']!))!
		for name in ['core.v','storage.v'] {
			pin(inputs, '/selectorderfixture/'+name, digest(root+'/source/tests/linux-compat/selectorderfixture/'+name)!)!
		}
		pin(inputs, '/selectorderreferenceinit/core.v', digest(root+'/source/tests/linux-compat/selectorderreferenceinit/core.v')!)!
		outputs := json2.decode[map[string]string](json2.encode(compilation['outputs']!))!
		pin(outputs, '/probe', probe)!
		pin(outputs, '/reference-init', digest(compile+'/reference-init')!)!
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
			selectordercheck.verify(os.read_file(state+'/serial.log')!,arch,mode == 'original',false)!
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
		require(artifacts['wrapper_source']!.str() == digest(root+'/source/tests/linux-compat/selectorderreferenceinit/core.v')!, 'Different Linux wrapper')!
		selectordercheck.verify(os.read_file(reference+'/serial.log')!,arch,false,true)!
		kernel := digest(root+'/build-fixed-'+suffix+'/kernel/bin/vinix')!
		registered := root+'/registered-'+suffix
		registration := object(registered+'/receipt.json')!
		require(registration['architecture']!.str() == arch && registration['kernel_sha256']!.str() == kernel
			&& digest(registered+'/kernel/bin/vinix')! == kernel, 'Different registered kernel')!
		mut names := []string{}
		for item in registration['results']!.as_array() {
			row := item.as_map()
			name := row['name']!.str()
			require(name in ['selectorder','selectempty','maskwait','selectfds'] && name !in names && row['exit_code']!.int() == 0, 'Different registered case')!
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
			if name == 'selectorder' { selectordercheck.verify(log,arch,false,false)! }
			else if name == 'selectempty' { selectcheck.verify(log,arch,false,false)! }
			else if name == 'selectfds' { selectfdscheck.verify(log,arch,false,false)! }
			else { masked(log,arch,false)! }
		}
		require(names.len == 4, 'Missing registered cases')!
	}
	println('Select argument order evidence: PASS ('+manifest.len.str()+' files; original/fixed/Linux comparisons, generated C, flat storage and 4 registered cases per architecture)')
}

fn main() {
	if os.args.len == 2 && os.args[1] == 'self-test' { selectordercheck.self_test() or { panic(err) }; return }
	if os.args.len == 4 && os.args[1] == 'generated' {
		generated_controls(os.read_file(os.args[2])!,os.read_file(os.args[3])!) or { panic(err) }
		println('Select argument-order generated-C scope: PASS'); return
	}
	if os.args.len != 2 { panic('Usage: selectorder-evidence self-test|BUNDLE; generated BEFORE-C AFTER-C') }
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
