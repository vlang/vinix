// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import selectfdscheck
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
	old := body(before, 'file__do_select')!
	current := body(after, 'file__do_select')!
	helper := body(after, 'file__select_fds_open')!
	prototype := 'bool file__select_fds_open(proc__Process* process, Array polls);\n'
	require(after.count(prototype) == 1 && !before.contains('file__select_fds_open'), 'Unexpected helper declarations')!
	require(before.replace(old, current) == after.replace(prototype, '').replace(helper + '\n', ''),
		'Generated C changed outside descriptor validation and select output')!
	require(helper.count('klock__Lock__acquire(&target->fds_lock);') == 1
		&& helper.count('klock__Lock__release(&target->fds_lock);') == 3
		&& helper.contains('array_get(target->fds, (i64)(poll.fd))) == NULL'), 'Invalid locked slot validation')!
	for token in ['malloc(', 'memdup(', 'array_push(', 'array__free(', 'refcount', 'Resource', 'boxed', 'file__fd_from_fdnum'] {
		require(!helper.contains(token), 'Helper changes ownership: '+token)!
	}
	for token in ['__new_array', 'array_push(', 'string__clone(', 'vinix_stack_alloc(', 'file__ppoll('] {
		require(current.count(token) == old.count(token), 'Select allocation/poll count changed: '+token)!
	}
	for name in ['polls','indexes'] {
		token := 'array__free(&'+name+');'
		require(current.count(token) == old.count(token)+1, 'Missing early cleanup: '+name)!
	}
	require(current.count('file__pollnval') == 3
		&& current.contains('errno__ebadf') && current.contains('!file__select_fds_open(current_thread->process, polls)'), 'Missing descriptor semantics')!
	start := current.index('!file__select_fds_open(') or { return error('Missing validation') }
	finish := current.index('if (polls.len == 0)') or { return error('Missing empty branch') }
	require(start < finish && current[start..finish].contains('array__free(&polls);')
		&& current[start..finish].contains('array__free(&indexes);'), 'Error cleanup ordering changed')!
}

fn passed(receipt map[string]json2.Any, arch string) ! {
	require(receipt['architecture']!.str() == arch && receipt['passed']!.bool()
		&& receipt['finished']!.bool() && receipt['status']!.int() == 0, 'Unfinished/failed session')!
}

fn generated_controls(before string, after string) ! {
	generated(before,after)!
	mut rejected := 0
	for bad in [after+'void unrelated(void) {}\n',
		after.replace('klock__Lock__release(&target->fds_lock);',''),
		after.replace('proc__Process* target = process;', 'proc__Process* target = process;\n\tmemdup(process, 8);'),
		after.replace('file__pollpri | file__pollnval','file__pollpri'),
		after.replace('errno__ebadf};','errno__efault};'),
		after.replace('array__free(&indexes);','') ] {
		generated(before,bad) or { rejected++; continue }
		return error('Altered generated C accepted')
	}
	println('Select generated-C controls: PASS (1 positive, '+rejected.str()+' negative controls)')
}

fn check(root string) ! {
	manifest := json2.decode[map[string]string](os.read_file(root+'/manifest.json')!)!
	mut actual := map[string]string{}
	inventory(root, '', mut actual)!
	require(actual == manifest, 'Missing, extra or changed bundle artifact')!
	for pair in [['arm','aarch64'],['x86','x86_64']] {
		suffix, arch := pair[0], pair[1]
		compile := root+'/compile-'+suffix+'-r4'
		probe := digest(compile+'/probe')!
		compilation := object(compile+'/receipt.json')!
		require(compilation['architecture']!.str() == arch, 'Different compile architecture')!
		inputs := json2.decode[map[string]string](json2.encode(compilation['inputs']!))!
		for name in ['core.v','storage.v'] {
			pin(inputs, '/selectfdsfixture/'+name, digest(root+'/source/tests/linux-compat/selectfdsfixture/'+name)!)!
		}
		pin(inputs, '/selectfdsreferenceinit/core.v', digest(root+'/source/tests/linux-compat/selectfdsreferenceinit/core.v')!)!
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
			selectfdscheck.verify(os.read_file(state+'/serial.log')!,arch,mode == 'original',false)!
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
		require(artifacts['wrapper_source']!.str() == digest(root+'/source/tests/linux-compat/selectfdsreferenceinit/core.v')!, 'Different Linux wrapper')!
		selectfdscheck.verify(os.read_file(reference+'/serial.log')!,arch,false,true)!
		kernel := digest(root+'/build-fixed-'+suffix+'/kernel/bin/vinix')!
		for name in ['selectready','opathpoll','selectempty','maskwait','runtime','jit','execown'] {
			state := root+'/reg-'+suffix+'/'+name
			rr := object(state+'/receipt.json')!
			passed(rr,arch)!
			require(rr['case']!.str() == name && rr['kernel_sha256']!.str() == kernel
				&& digest(state+'/kernel/bin/vinix')! == kernel
				&& rr['probe_sha256']!.str() == digest(state+'/init')!
				&& digest(state+'/rootfs/sbin/init')! == digest(state+'/init')!
				&& rr['serial_sha256']!.str() == digest(state+'/serial.log')!, 'Different regression artifacts')!
			log := os.read_file(state+'/serial.log')!
			require(log.contains('LINUX '+name.to_upper()+': PASS') && !log.contains('KERNEL PANIC')
				&& !log.contains('FATAL EXCEPTION') && !log.contains('LINUX '+name.to_upper()+' FAIL'), 'Regression failed')!
		}
		registered := root+'/registered-'+suffix
		registration := object(registered+'/receipt.json')!
		require(registration['architecture']!.str() == arch && registration['kernel_sha256']!.str() == kernel
			&& digest(registered+'/kernel/bin/vinix')! == kernel, 'Different registered kernel')!
		mut names := []string{}
		for item in registration['results']!.as_array() {
			row := item.as_map()
			name := row['name']!.str()
			require(name in ['selectfds','selectbad'] && name !in names && row['exit_code']!.int() == 0, 'Different registered case')!
			names << name
			state := registered+'/'+name
			require(row['init_sha256']!.str() == digest(state+'/init')!
				&& row['iso_sha256']!.str() == digest(state+'/test.iso')!, 'Different registered artifacts')!
			frozen := json2.decode[map[string]string](json2.encode(row['source_inputs']!))!
			files := if name == 'selectfds' { ['core.v','storage.v'] } else { ['core.v'] }
			require(frozen.len == files.len, 'Incomplete frozen fixture')!
			for file in files {
				expected := digest(root+'/source/tests/linux-compat/'+name+'fixture/'+file)!
				pin(frozen,'/'+name+'fixture/'+file,expected)!
				require(digest(registered+'/sources/'+name+'fixture/'+file)! == expected, 'Different frozen source')!
			}
			log := os.read_file(state+'/serial.log')!
			if name == 'selectfds' { selectfdscheck.verify(log,arch,false,false)! }
			else { require(log.contains('LINUX SELECTBAD SUMMARY: checks='+if arch == 'aarch64' { '2520' } else { '3360' }+' failures=0')
				&& log.contains('LINUX SELECTBAD: PASS') && !log.contains('KERNEL PANIC'), 'Selectbad regression failed')! }
		}
		require(names.len == 2, 'Missing registered cases')!
	}
	println('Select descriptor evidence: PASS ('+manifest.len.str()+' files; original/fixed/Linux comparisons, generated C, flat storage and 9 regression cases per architecture)')
}

fn main() {
	if os.args.len == 2 && os.args[1] == 'self-test' { selectfdscheck.self_test() or { panic(err) }; return }
	if os.args.len == 4 && os.args[1] == 'generated' {
		generated_controls(os.read_file(os.args[2])!,os.read_file(os.args[3])!) or { panic(err) }
		println('Select generated-C scope: PASS'); return
	}
	if os.args.len != 2 { panic('Usage: selectfds-evidence self-test|BUNDLE; generated BEFORE-C AFTER-C') }
	check(os.args[1]) or { panic(err) }
}
