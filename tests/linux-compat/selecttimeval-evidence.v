// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import selecttimevalcheck
import selecttimeoutcheck
import selectordercheck
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

fn passed(receipt map[string]json2.Any, arch string) ! {
	require(receipt['architecture']!.str() == arch && receipt['passed']!.bool()
		&& receipt['finished']!.bool() && receipt['status']!.int() == 0, 'Unfinished/failed session')!
}

fn allocation_groups(text string) ![]string {
	for line in ['aarch64: 808 source files, 391 allocation sites (V exit 0)',
		'x86_64: 800 source files, 291 allocation sites (V exit 0)'] {
		require(text.split_into_lines().filter(it == line).len == 1, 'Incomplete allocation scan')!
	}
	mut groups := text.split_into_lines().filter(it.starts_with('NEW: '))
	groups.sort()
	require(groups.len == 180, 'Different baseline allocation excess groups')!
	return groups
}

fn generated(before string, after string) ! {
	if !before.contains(' file__syscall_select(') {
		require(before == after, 'Architecture without raw select changed')!
		return
	}
	old := body(before,'file__syscall_select')!
	current := body(after,'file__syscall_select')!
	require(before.replace(old,current) == after, 'Generated C changed outside raw select entrypoint')!
	for token in ['__new_array','array_push(','array__free(','string__clone(',
		'malloc(','memdup(','refcount','vinix_stack_alloc(', 'usercopy__copy_from_user(',
		'file__do_select(','file__select_deadline(','file__select_finish_timeout('] {
		require(old.count(token) == current.count(token), 'Storage, copy or core call count changed: '+token)!
	}
	require(current.contains('i64 seconds =') && current.contains('(u64)(tv[0])')
		&& current.contains('(u64)(') && current.contains('i64 nanos =')
		&& current.contains('if ((seconds < 0) || (nanos < 0))')
		&& current.contains('.tv_sec = seconds, .tv_nsec = nanos'), 'Missing scalar normalization or validation')!
	require(current.count('(1000000)') == 2 && current.contains('* 1000'), 'Wrong timeval units')!
	require(!current.contains('tv[1] >= 1000000') && !current.contains('tv[0] < 0'), 'Valid carries rejected before normalization')!
}

fn altered(source string, old string, replacement string) !string {
	current := body(source,'file__syscall_select')!
	require(current.contains(old), 'Ineffective generated-C mutation: '+old)!
	return source.replace(current,current.replace(old,replacement))
}
fn generated_controls(before string, after string) ! {
	generated(before,after)!
	if !after.contains(' file__syscall_select(') { return }
	mut negatives := 0
	for bad in [after+'void unrelated(void) {}',
		altered(after,'(u64)(tv[0])','(i64)(tv[0])')!,
		altered(after,'seconds < 0','tv[0] < 0')!,
		altered(after,'nanos < 0','tv[1] < 0')!,
		altered(after,'(1000000)','(1000000000)')!,
		altered(after,'* 1000','* 1')!,
		altered(after,'.tv_sec = seconds, .tv_nsec = nanos','.tv_sec = tv[0], .tv_nsec = nanos')!,
		altered(after,'file__select_finish_timeout(','memdup(')!] {
		generated(before,bad) or { negatives++; continue }
		return error('Invalid select timeval C accepted')
	}
	println('Select timeval C controls: PASS (1 positive, '+negatives.str()+' negative)')
}

fn check(root string) ! {
	manifest := json2.decode[map[string]string](os.read_file(root+'/manifest.json')!)!
	mut actual := map[string]string{}
	inventory(root, '', mut actual)!
	require(actual == manifest, 'Missing, extra or changed bundle artifact')!
	require(allocation_groups(os.read_file(root+'/allocs-original.log')!)! ==
		allocation_groups(os.read_file(root+'/allocs-fixed.log')!)!, 'Allocation excess groups changed')!
	review := os.read_file(root+'/review.txt')!
	require(review.contains('Independent timeval normalization review: PASS. No findings.'), 'Missing lifetime review')!
	for path in ['source/fixed/pselect.v','source/tests/linux-compat/selecttimevalfixture/core.v',
		'source/tests/linux-compat/selecttimevalfixture/storage.v','build-fixed-arm/blob.c',
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
			pin(inputs, '/selecttimevalfixture/'+name, digest(root+'/source/tests/linux-compat/selecttimevalfixture/'+name)!)!
		}
		pin(inputs, '/selecttimevalreferenceinit/core.v', digest(root+'/source/tests/linux-compat/selecttimevalreferenceinit/core.v')!)!
		outputs := json2.decode[map[string]string](json2.encode(compilation['outputs']!))!
		pin(outputs, '/probe', probe)!
		pin(outputs, '/reference-init', digest(compile+'/reference-init')!)!
		fixture_c := os.read_file(compile+'/fixture.c')!
		require(!fixture_c.contains('memdup(') && !fixture_c.contains('malloc('), 'Fixture heap promotion')!
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
			selecttimevalcheck.verify(os.read_file(state+'/serial.log')!,arch,mode == 'original',false)!
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
		require(artifacts['wrapper_source']!.str() == digest(root+'/source/tests/linux-compat/selecttimevalreferenceinit/core.v')!, 'Different Linux wrapper')!
		selecttimevalcheck.verify(os.read_file(reference+'/serial.log')!,arch,false,true)!
		kernel := digest(root+'/build-fixed-'+suffix+'/kernel/bin/vinix')!
		registered := root+'/registered-'+suffix
		registration := object(registered+'/receipt.json')!
		require(registration['architecture']!.str() == arch && registration['kernel_sha256']!.str() == kernel
			&& digest(registered+'/kernel/bin/vinix')! == kernel, 'Different registered kernel')!
		mut names := []string{}
		for item in registration['results']!.as_array() {
			row := item.as_map()
			name := row['name']!.str()
			require(name in ['selecttimeval','selecttimeout','selectorder','selectfds'] && name !in names && row['exit_code']!.int() == 0, 'Different registered case')!
			names << name
			state := registered+'/'+name
			require(row['init_sha256']!.str() == digest(state+'/init')!
				&& row['iso_sha256']!.str() == digest(state+'/test.iso')!, 'Different registered artifacts')!
			frozen := json2.decode[map[string]string](json2.encode(row['source_inputs']!))!
			files := ['core.v','storage.v']
			require(frozen.len == files.len, 'Incomplete frozen fixture')!
			for file in files {
				expected := digest(root+'/source/tests/linux-compat/'+name+'fixture/'+file)!
				pin(frozen,'/'+name+'fixture/'+file,expected)!
				require(digest(registered+'/sources/'+name+'fixture/'+file)! == expected, 'Different frozen source')!
			}
			log := os.read_file(state+'/serial.log')!
			if name == 'selecttimeval' { selecttimevalcheck.verify(log,arch,false,false)! }
			else if name == 'selecttimeout' { selecttimeoutcheck.verify(log,arch,false,false)! }
			else if name == 'selectorder' { selectordercheck.verify(log,arch,false,false)! }
			else if name == 'selectfds' { selectfdscheck.verify(log,arch,false,false)! }
			else { return error('Unexpected registered case') }
		}
		require(names.len == 4, 'Missing registered cases')!
	}
	println('Select timeval evidence: PASS ('+manifest.len.str()+' files; original/fixed/Linux comparisons, generated C, flat storage and 4 registered cases per architecture)')
}

fn main() {
	if os.args.len == 2 && os.args[1] == 'self-test' { selecttimevalcheck.self_test() or { panic(err) }; return }
	if os.args.len == 4 && os.args[1] == 'generated' {
		generated_controls(os.read_file(os.args[2])!,os.read_file(os.args[3])!) or { panic(err) }
		println('Select timeval generated-C scope: PASS'); return
	}
	if os.args.len != 2 { panic('Usage: selecttimeval-evidence self-test|BUNDLE; generated BEFORE-C AFTER-C') }
	check(os.args[1]) or { panic(err) }
}
