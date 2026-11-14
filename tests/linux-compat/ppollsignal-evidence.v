// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import ppolltimecheck
import ppollargscheck
import ppollsignalcheck
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

// V includes the source file's absolute-path hash in ignored-variable names.
// Separate worktrees change that identifier component without changing code.
fn canonical(source string) string {
	mut result := strings.new_builder(source.len)
	mut position := 0
	for position < source.len {
		if source[position] == `_` && position + 10 <= source.len && source[position..position + 10] == '__discard_' {
			result.write_string('__discard_')
			position += '__discard_'.len
			for position < source.len && source[position] >= `0` && source[position] <= `9` { position++ }
		} else {
			result.write_u8(source[position])
			position++
		}
	}
	return result.str()
}

fn check(root string) ! {
 manifest := json2.decode[map[string]string](os.read_file(root+'/manifest.json')!)!
 mut found := map[string]string{}
 inventory(root,'',mut found)!
 require(found == manifest,'Incomplete or changed evidence inventory')!
 review := os.read_file(root+'/review.txt')!
 require(review.contains('Follow-up review of the final r2 fixture and kernel change: PASS. No findings.'),'Missing independent review')!
 for file in ['core.v','storage.v','bounds.v'] {
  require(review.contains(digest(root+'/source/tests/linux-compat/ppollsignalfixture/'+file)!),'Outdated fixture review')!
 }
 require(review.contains(digest(root+'/source/kernel/file/file.v')!),'Outdated kernel review')!
 ppollsignalcheck.self_test()!
 for suffix in ['arm','x86'] {
  initial := root+'/reference-'+suffix
  failed := object(initial+'/receipt.json')!
  require(!failed['passed']!.bool() && os.read_file(initial+'/serial.log')!.contains('checks=576 failures=16'),'Initial Linux oracle refusal missing')!
  initial_artifacts := failed['artifacts']!.as_map()
  require(initial_artifacts['probe']!.str() == digest(initial+'/probe')!
   && digest(initial+'/probe')! == digest(root+'/compile-'+suffix+'/probe')!
   && initial_artifacts['serial']!.str() == digest(initial+'/serial.log')!,'Initial reference identity changed')!
 }
 mut storage_refused := false
 ppollsignalcheck.verify(os.read_file(root+'/fixed-arm-r2/serial.log')!,'aarch64',false,false) or { storage_refused = err.msg() == 'Storage changed' }
 require(storage_refused,'Historical ARM storage guard no longer refuses growth')!
 mut baseline_storage_refused := false
 ppollsignalcheck.verify(os.read_file(root+'/original-arm-r1/serial.log')!,'aarch64',true,false) or { baseline_storage_refused = err.msg() == 'Storage changed' }
 require(baseline_storage_refused,'Historical baseline storage growth not retained')!
 for kind in ['original','fixed'] {
  timed := object(root+'/'+kind+'-x86-r2/receipt.json')!
  require(!timed['passed']!.bool(),'Historical native timeout not retained')!
  require(timed['probe']!.str() == digest(root+'/compile-x86-r2/probe')!,'Different interrupted replay ELF')!
 }

 for pair in [['arm','aarch64'],['x86','x86_64']] {
 suffix, arch := pair[0],pair[1]
 build := root+'/build-'+suffix
 original := root+'/baseline-'+suffix
 compile := root+'/compile-'+suffix+'-r2'
 kernel := digest(build+'/kernel/bin/vinix')!
 require(os.read_file(build+'/build.log.status')!.trim_space() == '0','Kernel build failed')!
 build_inputs := json2.decode[map[string]string](os.read_file(build+'/inputs.json')!)!
 pin(build_inputs,'/kernel/file/file.v',digest(root+'/source/kernel/file/file.v')!)!
 for path in [compile+'/fixture.c',build+'/blob.c'] { require(review.contains(digest(path)!),'Outdated generated-C review')! }
 for previous in [true,false] {
  generation := if previous && suffix == 'arm' { '-r2' } else { '-r3' }
  state := root+'/'+if previous { 'original-'+suffix+generation } else { 'fixed-'+suffix+generation }
  r := object(state+'/receipt.json')!
  passed(r,arch)!
  if generation == '-r3' {
   native_inputs := json2.decode[map[string]string](os.read_file(state+'/inputs.json')!)!
   pin(native_inputs,'/ppollsignal-host.v',digest(root+'/source/tests/linux-compat/ppollsignal-host.v')!)!
   pin(native_inputs,'/host',digest(root+'/host')!)!
  }
  require(r['probe']!.str() == digest(compile+'/probe')! && digest(state+'/rootfs/sbin/init')! == r['probe']!.str()
   && r['kernel']!.str() == digest(state+'/kernel/bin/vinix')! && r['serial']!.str() == digest(state+'/serial.log')!,'Native executable or log changed')!
  expected_kernel := if previous { original } else { build }
  require(r['kernel']!.str() == digest(expected_kernel+'/kernel/bin/vinix')!,'Different native kernel')!
  ppollsignalcheck.verify(os.read_file(state+'/serial.log')!,arch,previous,false)!
 }
 c := object(compile+'/receipt.json')!
 inputs := json2.decode[map[string]string](json2.encode(c['inputs']!))!
 for file in ['core.v','storage.v','bounds.v'] { pin(inputs,'/ppollsignalfixture/'+file,digest(root+'/source/tests/linux-compat/ppollsignalfixture/'+file)!)! }
 outputs := json2.decode[map[string]string](json2.encode(c['outputs']!))!
 pin(outputs,'/probe',digest(compile+'/probe')!)!
 pin(outputs,'/reference-init',digest(compile+'/reference-init')!)!
 reference := root+'/reference-'+suffix+'-r2'
 rr := object(reference+'/receipt.json')!
 passed(rr,arch)!
 artifacts := rr['artifacts']!.as_map()
 for key,path in {'kernel':'linux','probe':'probe','wrapper_elf':'init','initramfs':'initramfs.cpio','serial':'serial.log'} {
  require(artifacts[key]!.str() == digest(reference+'/'+path)!,'Linux artifact changed')!
 }
 require(digest(reference+'/probe')! == digest(compile+'/probe')! && digest(reference+'/init')! == digest(compile+'/reference-init')!,'Different Linux ELF/launcher')!
 ppollsignalcheck.verify(os.read_file(reference+'/serial.log')!,arch,false,true)!
 before := os.read_file(original+'/blob.c')!
 after := os.read_file(build+'/blob.c')!
 old := body(before,'file__poll_user_fds')!
 new := body(after,'file__poll_user_fds')!
 require(canonical(before.replace(old,new)) == canonical(after),'Kernel C changed outside poll copyout helper')!
 require(new.contains('err != 0') && new.contains('errno__eintr') && new.contains('return (multi_return_u64_u64){ret, err}'),'Missing EINTR publication/preservation')!
 for token in ['__new_array','__free(', 'usercopy__copy_to_pagemap('] { require(old.count(token) == new.count(token),'Allocation/copy scope changed')! }
 registered := root+'/registered-'+suffix
 reg := object(registered+'/receipt.json')!
 require(reg['kernel_sha256']!.str() == kernel,'Registered kernel changed')!
 mut names := []string{}
 for row in reg['results']!.as_array() {
  r := row.as_map()
  name := r['name']!.str()
  require(name in ['ppollsignal','ppollargs','ppolltime'] && name !in names && r['exit_code']!.int() == 0,'Registered failure')!
  names << name
  if name == 'ppollsignal' {
   frozen := json2.decode[map[string]string](json2.encode(r['source_inputs']!))!
   require(frozen.len == 3,'Incomplete frozen ppoll fixture')!
   for file in ['core.v','storage.v','bounds.v'] {
    expected := digest(root+'/source/tests/linux-compat/ppollsignalfixture/'+file)!
    pin(frozen,'/ppollsignalfixture/'+file,expected)!
    require(digest(registered+'/sources/ppollsignalfixture/'+file)! == expected,'Frozen source changed')!
   }
  }
  require(r['init_sha256']!.str() == digest(registered+'/'+name+'/init')! && r['iso_sha256']!.str() == digest(registered+'/'+name+'/test.iso')!,'Registered artifacts changed')!
  log := os.read_file(registered+'/'+name+'/serial.log')!
  if name == 'ppollsignal' { ppollsignalcheck.verify(log,arch,false,false)! }
  else if name == 'ppollargs' { ppollargscheck.verify(log,arch,false,false)! }
  else { ppolltimecheck.verify(log,arch,false,false)! }
 }
 require(names.len == 3,'Missing regressions')!
 }
 println('Ppoll signal evidence: PASS ('+manifest.len.str()+' files; originals 20 failures each, fixed/Linux 672 checks each, flat storage, 3/3 regressions per architecture, generated-C and review)')
}
fn main() {
 if os.args.len != 2 { panic('Usage: ppollsignal-evidence BUNDLE') }
 check(os.args[1]) or { panic(err) }
}
