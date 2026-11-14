// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import selectfdscheck
import selectcheck
import opathpollcheck
import selectwordcheck
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

fn generated(before string, after string) ! {
 cast := '\n\ti64 nfds = (i64)((i32)(nfds_word));'
 functions := if before.contains(' file__syscall_select(') { 2 } else { 1 }
 require(before.contains(' file__syscall_pselect6(') && !before.contains('nfds_word')
  && after.count(cast) == functions && after.count('i64 nfds_word,') == functions*2,'Unexpected nfds decoding')!
 old_select := body(before,'file__do_select')!
 new_select := body(after,'file__do_select')!
 require(before.replace(old_select,new_select) == after.replace(cast,'').replace('i64 nfds_word,','i64 nfds,'),'Generated C changed outside signed nfds decodes and empty result output')!
 require(new_select.count('u64 empty_result[16];') == 1
  && new_select.contains('memmove(empty_result, (u64[16]){0}, sizeof(empty_result));')
  && new_select.count('usercopy__copy_to_user(') == old_select.count('usercopy__copy_to_user(')+3
  && new_select.count('&empty_result[0]') == 3,'Missing stack result or complete output sets')!
 for token in ['__new_array','array_push(','string__clone(','vinix_stack_alloc(','malloc(','memdup(','file__ppoll('] {
  require(new_select.count(token) == old_select.count(token),'Select allocations/waits changed: '+token)!
 }
 for vector in ['polls','indexes'] { require(new_select.count('array__free(&'+vector+');') == old_select.count('array__free(&'+vector+');')+3,'Missing empty output error cleanup')! }
 for name in ['file__syscall_pselect6','file__syscall_select'] {
 if !before.contains(' '+name+'(') { continue }
 old := body(before,name)!
 current := body(after,name)!
 for token in ['malloc(','memdup(','array_push(','array__free(','vinix_stack_alloc(','refcount'] { require(old.count(token) == current.count(token),'Ownership changed: '+token)! }
 }
}

fn passed(receipt map[string]json2.Any, arch string) ! {
	require(receipt['architecture']!.str() == arch && receipt['passed']!.bool()
		&& receipt['finished']!.bool() && receipt['status']!.int() == 0, 'Unfinished/failed session')!
}

fn generated_controls(before string, after string) ! {
 generated(before,after)!
 mut rejected := 0
 for bad in [after+'void unrelated(void) {}\n',after.replace('(i32)(nfds_word)','(u32)(nfds_word)'),after.replace('i64 nfds = (i64)((i32)(nfds_word));','i64 nfds = nfds_word;'),after.replace('i64 nfds = (i64)((i32)(nfds_word));','i64 nfds = (i64)((i32)(nfds_word));\n\tmemdup(0,8);'),after.replace('&empty_result[0]','&got_read[0]'),after.replace('u64 empty_result[16];','u64* empty_result = malloc(128);'),after.replace('memmove(empty_result, (u64[16]){0}, sizeof(empty_result));','')] {
 generated(before,bad) or { rejected++; continue }
 return error('Altered generated C accepted')
 }
 println('Select nfds generated-C controls: PASS (1 positive, '+rejected.str()+' negative controls)')
}

fn check(root string) ! {
	manifest := json2.decode[map[string]string](os.read_file(root+'/manifest.json')!)!
	mut actual := map[string]string{}
	inventory(root, '', mut actual)!
	require(actual == manifest, 'Missing, extra or changed bundle artifact')!
	for pair in [['arm','aarch64'],['x86','x86_64']] {
		suffix, arch := pair[0], pair[1]
		compile := root+'/compile-'+suffix+'-r2'
		probe := digest(compile+'/probe')!
		compilation := object(compile+'/receipt.json')!
		require(compilation['architecture']!.str() == arch, 'Different compile architecture')!
		inputs := json2.decode[map[string]string](json2.encode(compilation['inputs']!))!
		for name in ['core.v','storage.v'] {
			pin(inputs, '/selectwordfixture/'+name, digest(root+'/source/tests/linux-compat/selectwordfixture/'+name)!)!
		}
		pin(inputs, '/selectwordreferenceinit/core.v', digest(root+'/source/tests/linux-compat/selectwordreferenceinit/core.v')!)!
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
			selectwordcheck.verify(os.read_file(state+'/serial.log')!,arch,mode == 'original',false)!
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
		require(artifacts['wrapper_source']!.str() == digest(root+'/source/tests/linux-compat/selectwordreferenceinit/core.v')!, 'Different Linux wrapper')!
		selectwordcheck.verify(os.read_file(reference+'/serial.log')!,arch,false,true)!
		kernel := digest(root+'/build-fixed-'+suffix+'/kernel/bin/vinix')!
		for name in ['opathpoll','selectempty','maskwait'] {
			state := root+'/reg-'+suffix+'/'+name
			rr := object(state+'/receipt.json')!
			passed(rr,arch)!
			require(rr['case']!.str() == name && rr['kernel_sha256']!.str() == kernel
				&& digest(state+'/kernel/bin/vinix')! == kernel
				&& rr['probe_sha256']!.str() == digest(state+'/init')!
				&& digest(state+'/rootfs/sbin/init')! == digest(state+'/init')!
				&& rr['serial_sha256']!.str() == digest(state+'/serial.log')!, 'Different regression artifacts')!
			log := os.read_file(state+'/serial.log')!
			if name == 'opathpoll' { opathpollcheck.verify(log,arch,false,false)! }
			if name == 'selectempty' { selectcheck.verify(log,arch,false,false)! }
			require(log.contains('LINUX '+name.to_upper()+': PASS') && !log.contains('KERNEL PANIC')
				&& !log.contains('FATAL EXCEPTION') && !log.contains('LINUX '+name.to_upper()+' FAIL'), 'Regression failed')!
		}
		registered := root+'/registered-'+suffix
		compiler_log := os.read_file(root+'/registered-'+suffix+'.log')!
		require(compiler_log.contains('Linux compatibility qualification failed;')
			&& compiler_log.contains('memdup'), 'Missing failed legacy compilation diagnostics')!
		registration := object(registered+'/receipt.json')!
		require(registration['architecture']!.str() == arch && registration['kernel_sha256']!.str() == kernel
			&& digest(registered+'/kernel/bin/vinix')! == kernel, 'Different registered kernel')!
		mut names := []string{}
		for item in registration['results']!.as_array() {
			row := item.as_map()
			name := row['name']!.str()
			require(name in ['selectword','selectfds','selectbad','selectready','selectempty','maskwait','jit']
				&& name !in names, 'Different registered case')!
			names << name
			state := registered+'/'+name
			frozen := json2.decode[map[string]string](json2.encode(row['source_inputs']!))!
			files := if name in ['selectword','selectfds','selectempty'] { ['core.v','storage.v'] } else { ['core.v'] }
			require(frozen.len == files.len, 'Incomplete frozen fixture')!
			for file in files {
				expected := digest(root+'/source/tests/linux-compat/'+name+'fixture/'+file)!
				pin(frozen,'/'+name+'fixture/'+file,expected)!
				require(digest(registered+'/sources/'+name+'fixture/'+file)! == expected, 'Different frozen source')!
			}
			if name in ['selectempty','maskwait'] {
				require(row['exit_code']!.int() == 1 && row['init_sha256']!.str() == ''
					&& row['iso_sha256']!.str() == '' && row['detail']!.str() == 'Command failed'
					&& !os.exists(state+'/init') && os.read_file(state+'/fixture.c')!.contains('memdup('),
					'Different legacy generator failure; retained replay is mandatory')!
				require(compiler_log.contains('/'+name+'/fixture.c:') && compiler_log.contains('error:'),
					'Missing legacy compiler error context')!
				continue
			}
			require(row['exit_code']!.int() == 0 && row['init_sha256']!.str() == digest(state+'/init')!
				&& row['iso_sha256']!.str() == digest(state+'/test.iso')!, 'Different registered artifacts')!
			log := os.read_file(state+'/serial.log')!
			if name == 'selectword' { selectwordcheck.verify(log,arch,false,false)! }
			else if name == 'selectfds' { selectfdscheck.verify(log,arch,false,false)! }
			else { require(log.contains('LINUX '+name.to_upper()+': PASS') && !log.contains('KERNEL PANIC')
				&& !log.contains('FATAL EXCEPTION') && !log.contains('LINUX '+name.to_upper()+' FAIL'), 'Registered regression failed')! }
		}
		require(names.len == 7, 'Missing registered cases')!
	}
	println('Select nfds word evidence: PASS ('+manifest.len.str()+' files; original/fixed/Linux comparisons, generated C, flat storage and 8 selected cases per architecture)')
}

fn main() {
	if os.args.len == 2 && os.args[1] == 'self-test' { selectwordcheck.self_test() or { panic(err) }; return }
	if os.args.len == 4 && os.args[1] == 'generated' {
		generated_controls(os.read_file(os.args[2])!,os.read_file(os.args[3])!) or { panic(err) }
		println('Select generated-C scope: PASS'); return
	}
	if os.args.len != 2 { panic('Usage: selectword-evidence self-test|BUNDLE; generated BEFORE-C AFTER-C') }
	check(os.args[1]) or { panic(err) }
}
