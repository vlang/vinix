// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import ppollargscheck
import selecttimeoutcheck
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

// This run remains a failed, unqualified regression. Require the historical
// checker to reject its original log; do not repair its input or its oracle.
fn timeout_refusal(text string) ! {
	mut rejected := false
	selecttimeoutcheck.verify(text,'x86_64',false,false) or {
		require(err.msg() == 'Unexpected semantic record: LINUX SELECTTIMEOUT MISMATCH: stage=7', 'Different historical checker refusal')!
		rejected = true
	}
	require(rejected, 'Expected historical timeout checker refusal missing')!
	mut failures := 0
	mut failed_rows := []string{}
	for line in text.split_into_lines().map(it.trim_space()) {
		if line.starts_with('LINUX SELECTTIMEOUT CASE:') && !line.ends_with('failures=0') {
			require(line in [
				'LINUX SELECTTIMEOUT CASE: uid=0 gid=0 api=2 mode=3 readonly=0 restart=0 checks=12 failures=1',
				'LINUX SELECTTIMEOUT CASE: uid=1000 gid=2000 api=2 mode=3 readonly=0 restart=0 checks=12 failures=1',
			], 'Different failed timeout case')!
			require(line !in failed_rows, 'Repeated failed timeout case')!
			failed_rows << line
			failures++
		}
		for bad in ['KERNEL PANIC','FATAL EXCEPTION','Kernel panic','LINUX SELECTTIMEOUT FAIL:'] {
			require(!line.contains(bad), 'Unexpected timeout failure: '+bad)!
		}
	}
	require(failures in [1,2] && text.count('LINUX SELECTTIMEOUT MISMATCH: stage=7') == failures
		&& text.contains('LINUX SELECTTIMEOUT SUMMARY: checks=2208 failures='+failures.str())
		&& text.contains('LINUX SELECTTIMEOUT: FAIL'), 'Different timeout refusal profile')!
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
	old := body(before,'file__syscall_ppoll')!
	current := body(after,'file__syscall_ppoll')!
	old_proto := old.all_before('\n').trim_string_right(' {')+';\n'
	new_proto := current.all_before('\n').trim_string_right(' {')+';\n'
	require(before.count(old_proto) == 1 && after.count(new_proto) == 1, 'Different ppoll prototype')!
	require(before.replace(old,current).replace(old_proto,new_proto) == after, 'Generated C changed outside ppoll entrypoint/prototype')!
	for token in ['__new_array','array_push(','string__clone(', 'malloc(','memdup(',
		'refcount','vinix_stack_alloc(','usercopy__copy_from_user(','file__poll_user_fds(',
		'proc__reserve_kernel('] {
		require(old.count(token) == current.count(token), 'Allocation/copy/core count changed: '+token)!
	}
	require(current.contains('u64 nfds = (u64)((u32)(nfds_word))')
		&& current.contains('sigset_size != sizeof(u64)')
		&& current.contains('timeout_storage->tv_nsec >= 1000000000')
		&& current.contains('timeout_storage->tv_sec < 0') && current.contains('timeout_storage->tv_nsec < 0'), 'Missing ABI decoding/timeout validation')!
	timeout := current.index('usercopy__copy_from_user((void*)(timeout_storage)') or { return error('Missing timeout import') }
	size := current.index('sigset_size != sizeof(u64)') or { return error('Missing size guard') }
	mask := current.index('usercopy__copy_from_user((void*)(sigmask_storage)') or { return error('Missing mask import') }
	install := current.index('proc__begin_wait_mask(') or { return error('Missing mask installation') }
	count := current.index('nfds > 4096') or { return error('Missing count limit') }
	budget := current.index('proc__reserve_kernel(') or { return error('Missing scratch reservation') }
	array := current.index('__new_array') or { return error('Missing private poll array') }
	sets := current.last_index('usercopy__copy_from_user(') or { return error('Missing poll array import') }
	require(timeout < size && size < mask && mask < install && install < count && count < budget && budget < array && array < sets, 'Wrong argument validation/allocation order')!
	require(current.count('proc__begin_wait_mask(') == 1 && current.contains('timeout_ptr, NULL)'), 'Duplicate/deferred mask installation')!
	require(current.count('array__free(') > 0 && current.count('array__free(') == current.count('kbudget__release(')
		&& current.count('array__free(') <= old.count('array__free('), 'Scratch/array cleanup changed')!
}
fn altered(source string, old string, replacement string) !string {
	current := body(source,'file__syscall_ppoll')!
	require(current.contains(old), 'Ineffective C mutation: '+old)!
	return source.replace(current,current.replace(old,replacement))
}
fn generated_controls(before string, after string) ! {
	generated(before,after)!
	mut negatives := 0
	for bad in [after+'void unrelated(void) {}',
		altered(after,'(u32)(nfds_word)','(u64)(nfds_word)')!,
		altered(after,'sigset_size != sizeof(u64)','sigset_size == sizeof(u64)')!,
		altered(after,'timeout_storage->tv_nsec >= 1000000000','timeout_storage->tv_nsec > 1000000000')!,
		altered(after,'timeout_storage->tv_sec < 0','timeout_storage->tv_sec > 0')!,
		altered(after,'proc__begin_wait_mask(','proc__other_wait_mask(')!,
		altered(after,'timeout_ptr, NULL)','timeout_ptr, sigmask_storage)')!,
		altered(after,'array__free(','other__free(')!,
		altered(after,'vinix_stack_alloc(sizeof(u64))','memdup(0,sizeof(u64))')!] {
		generated(before,bad) or { negatives++; continue }
		return error('Invalid ppoll argument C accepted')
	}
	println('Ppoll argument C controls: PASS (1 positive, '+negatives.str()+' negative)')
}

fn check(root string) ! {
	manifest := json2.decode[map[string]string](os.read_file(root+'/manifest.json')!)!
	mut actual := map[string]string{}
	inventory(root, '', mut actual)!
	require(actual == manifest, 'Missing, extra or changed bundle artifact')!
	require(allocation_groups(os.read_file(root+'/allocs-original.log')!)! ==
		allocation_groups(os.read_file(root+'/allocs-fixed.log')!)!, 'Allocation excess groups changed')!
	review := os.read_file(root+'/review.txt')!
	require(review.contains('Independent ppoll lifetime/ABI review: PASS. No findings.'), 'Missing lifetime review')!
	for path in ['source/fixed/file.v','source/tests/linux-compat/ppollargsfixture/core.v',
		'source/tests/linux-compat/ppollargsfixture/storage.v','build-fixed-arm/blob.c',
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
			pin(inputs, '/ppollargsfixture/'+name, digest(root+'/source/tests/linux-compat/ppollargsfixture/'+name)!)!
		}
		pin(inputs, '/ppollargsreferenceinit/core.v', digest(root+'/source/tests/linux-compat/ppollargsreferenceinit/core.v')!)!
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
			pin(build_inputs, '/kernel/file/file.v', digest(root+'/source/'+mode+'/file.v')!)!
			state := root+'/'+mode+'-'+suffix
			receipt := object(state+'/receipt.json')!
			passed(receipt,arch)!
			require(receipt['probe']!.str() == probe && digest(state+'/rootfs/sbin/init')! == probe
				&& receipt['kernel']!.str() == kernel && digest(state+'/kernel/bin/vinix')! == kernel
				&& receipt['serial']!.str() == digest(state+'/serial.log')!, 'Different native artifacts')!
			pins := json2.decode[map[string]string](os.read_file(state+'/inputs.json')!)!
			pin(pins, '/probe',probe)!
			pin(pins, '/kernel/bin/vinix',kernel)!
			ppollargscheck.verify(os.read_file(state+'/serial.log')!,arch,mode == 'original',false)!
		}
		generated(os.read_file(root+'/build-original-'+suffix+'/blob.c')!,os.read_file(root+'/build-fixed-'+suffix+'/blob.c')!)!
		old_inputs := json2.decode[map[string]string](os.read_file(root+'/build-original-'+suffix+'/inputs.json')!)!
		new_inputs := json2.decode[map[string]string](os.read_file(root+'/build-fixed-'+suffix+'/inputs.json')!)!
		require(old_inputs.len == new_inputs.len, 'Build input set changed')!
		for path,value in old_inputs {
			if !path.ends_with('/kernel/file/file.v') { require(new_inputs[path] == value, 'Other build input changed: '+path)! }
		}
		reference := root+'/reference-'+suffix
		r := object(reference+'/receipt.json')!
		passed(r,arch)!
		require(digest(reference+'/probe')! == probe && digest(reference+'/init')! == digest(compile+'/reference-init')!, 'Different Linux probe/launcher')!
		artifacts := r['artifacts']!.as_map()
		for key,path in {'kernel':'linux','probe':'probe','wrapper_elf':'init','initramfs':'initramfs.cpio','serial':'serial.log'} {
			require(artifacts[key]!.str() == digest(reference+'/'+path)!, 'Different Linux artifact: '+key)!
		}
		require(artifacts['wrapper_source']!.str() == digest(root+'/source/tests/linux-compat/ppollargsreferenceinit/core.v')!, 'Different Linux wrapper')!
		ppollargscheck.verify(os.read_file(reference+'/serial.log')!,arch,false,true)!
		kernel := digest(root+'/build-fixed-'+suffix+'/kernel/bin/vinix')!
		registered := root+'/registered-'+suffix
		registration := object(registered+'/receipt.json')!
		require(registration['architecture']!.str() == arch && registration['kernel_sha256']!.str() == kernel
			&& digest(registered+'/kernel/bin/vinix')! == kernel, 'Different registered kernel')!
		mut names := []string{}
		for item in registration['results']!.as_array() {
			row := item.as_map()
			name := row['name']!.str()
			expected_status := if name == 'selecttimeout' && arch == 'x86_64' { 1 } else { 0 }
			require(name in ['ppollargs','selecttimeout','maskwait','selectfds'] && name !in names && row['exit_code']!.int() == expected_status, 'Different registered case')!
			names << name
			state := registered+'/'+name
			require(row['init_sha256']!.str() == digest(state+'/init')!
				&& row['iso_sha256']!.str() == digest(state+'/test.iso')!, 'Different registered artifacts')!
			frozen := json2.decode[map[string]string](json2.encode(row['source_inputs']!))!
			files := if name == 'maskwait' { ['core.v'] } else { ['core.v','storage.v'] }
			require(frozen.len == files.len, 'Incomplete frozen fixture')!
			for file in files {
				expected := digest(root+'/source/tests/linux-compat/'+name+'fixture/'+file)!
				pin(frozen,'/'+name+'fixture/'+file,expected)!
				require(digest(registered+'/sources/'+name+'fixture/'+file)! == expected, 'Different frozen source')!
			}
			log := os.read_file(state+'/serial.log')!
			if name == 'ppollargs' { ppollargscheck.verify(log,arch,false,false)! }
			else if name == 'selecttimeout' {
				if arch == 'x86_64' { timeout_refusal(log)! }
				else { selecttimeoutcheck.verify(log,arch,false,false)! }
			}
			else if name == 'maskwait' { masked(log,arch,false)! }
			else if name == 'selectfds' { selectfdscheck.verify(log,arch,false,false)! }
			else { return error('Unexpected registered case') }
		}
		require(names.len == 4, 'Missing registered cases')!
		if arch == 'x86_64' {
			for mode in ['original','fixed'] {
				state := root+'/replay-'+mode+'-x86'
				replay := object(state+'/receipt.json')!
				passed(replay,arch)!
				require(replay['probe']!.str() == digest(registered+'/selecttimeout/init')!
					&& digest(state+'/rootfs/sbin/init')! == digest(registered+'/selecttimeout/init')!
					&& replay['kernel']!.str() == digest(root+'/build-'+mode+'-x86/kernel/bin/vinix')!
					&& replay['serial']!.str() == digest(state+'/serial.log')!, 'Different timeout replay artifacts')!
				log := os.read_file(state+'/serial.log')!
				if log.contains('LINUX SELECTTIMEOUT SUMMARY: checks=2208 failures=0') {
					selecttimeoutcheck.verify(log,arch,false,false)!
				} else { timeout_refusal(log)! }
			}
			for mode in ['original','fixed'] {
				state := root+'/diagnostic-'+mode
				diagnostic := object(state+'/receipt.json')!
				passed(diagnostic,arch)!
				require(diagnostic['probe']!.str() == digest(root+'/diagnostic-compile/probe')!
					&& digest(state+'/rootfs/sbin/init')! == digest(root+'/diagnostic-compile/probe')!
					&& diagnostic['kernel']!.str() == digest(root+'/build-'+mode+'-x86/kernel/bin/vinix')!
					&& diagnostic['serial']!.str() == digest(state+'/serial.log')!, 'Different diagnostic artifacts')!
				log := os.read_file(state+'/serial.log')!
				timeout_refusal(log)!
				require(log.contains('api=2 mode=3 readonly=0 original=0/500000 actual=0/500000'), 'Missing numeric timeout refusal')!
			}
		}
	}
	println('Ppoll arguments evidence: PASS ('+manifest.len.str()+' files; original/fixed/Linux ppoll comparisons, generated C and flat storage; registered regressions ARM 4/4, x86 3/4; strict timeout refusal and variable replays retained, numeric diagnostic reproduces on both kernels)')
}

fn main() {
	if os.args.len == 2 && os.args[1] == 'self-test' { ppollargscheck.self_test() or { panic(err) }; return }
	if os.args.len == 4 && os.args[1] == 'generated' {
		generated_controls(os.read_file(os.args[2])!,os.read_file(os.args[3])!) or { panic(err) }
		println('Ppoll arguments generated-C scope: PASS'); return
	}
	if os.args.len != 2 { panic('Usage: ppollargs-evidence self-test|BUNDLE; generated BEFORE-C AFTER-C') }
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
