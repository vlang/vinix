// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import ppollsignalcheck
import ppolltimecheck
import pollcopycheck
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

fn scope(before string, after string) ! {
 old := body(before,'file__poll_user_fds')!
 new := body(after,'file__poll_user_fds')!
 require(canonical(before.replace(old,new)) == canonical(after),'Kernel C changed outside poll copyout')!
 require(old.count('usercopy__copy_to_pagemap(') == 1 && new.count('usercopy__copy_to_pagemap(') == 1,'Unexpected copy operation')!
 require(new.contains('offsetof(file__PollFD, revents)') && new.contains('sizeof(i16)') && new.contains('.revents'),'Whole-record copy remains')!
 for token in ['__new_array','__free(', 'proc__reserve_kernel(', 'kbudget__release(', 'vinix_stack_alloc('] { require(old.count(token) == new.count(token),'Ownership changed: '+token)! }
}

fn check(root string) ! {
 manifest := json2.decode[map[string]string](os.read_file(root+'/manifest.json')!)!
 mut found := map[string]string{}
 inventory(root,'',mut found)!
 require(found == manifest,'Incomplete or changed evidence inventory')!
 review := os.read_file(root+'/review.txt')!
 require(review.contains('Independent poll-copyout review: PASS.'),'Missing independent review')!
 require(review.contains(digest(root+'/source/tests/linux-compat/pollcopycheck/core.v')!),'Outdated checker review')!
 for file in ['core.v','storage.v'] {
  require(review.contains(digest(root+'/source/tests/linux-compat/pollcopyfixture/'+file)!),'Outdated fixture review')!
 }
 require(review.contains(digest(root+'/source/kernel/file/file.v')!),'Outdated kernel review')!
 pollcopycheck.self_test()!
 for pair in [['arm','aarch64'],['x86','x86_64']] {
 suffix, arch := pair[0],pair[1]
 build := root+'/build-'+suffix
 original := root+'/baseline-'+suffix
 compile := root+'/compile-'+suffix
 kernel := digest(build+'/kernel/bin/vinix')!
 require(os.read_file(build+'/build.log.status')!.trim_space() == '0','Kernel build failed')!
 build_inputs := json2.decode[map[string]string](os.read_file(build+'/inputs.json')!)!
 pin(build_inputs,'/kernel/file/file.v',digest(root+'/source/kernel/file/file.v')!)!
 for path in [compile+'/fixture.c',build+'/blob.c'] { require(review.contains(digest(path)!),'Outdated generated-C review')! }
 for previous in [true,false] {
  state := root+'/'+if previous { 'original-'+suffix } else { 'fixed-'+suffix }
  r := object(state+'/receipt.json')!
  passed(r,arch)!
  require(r['probe']!.str() == digest(compile+'/probe')! && digest(state+'/rootfs/sbin/init')! == r['probe']!.str()
   && r['kernel']!.str() == digest(state+'/kernel/bin/vinix')! && r['serial']!.str() == digest(state+'/serial.log')!,'Native executable or log changed')!
  expected_kernel := if previous { original } else { build }
  require(r['kernel']!.str() == digest(expected_kernel+'/kernel/bin/vinix')!,'Different native kernel')!
  pollcopycheck.verify(os.read_file(state+'/serial.log')!,arch,previous,false)!
 }
 c := object(compile+'/receipt.json')!
 inputs := json2.decode[map[string]string](json2.encode(c['inputs']!))!
 for file in ['core.v','storage.v'] { pin(inputs,'/pollcopyfixture/'+file,digest(root+'/source/tests/linux-compat/pollcopyfixture/'+file)!)! }
 outputs := json2.decode[map[string]string](json2.encode(c['outputs']!))!
 pin(outputs,'/probe',digest(compile+'/probe')!)!
 pin(outputs,'/reference-init',digest(compile+'/reference-init')!)!
 reference := root+'/reference-'+suffix
 rr := object(reference+'/receipt.json')!
 passed(rr,arch)!
 artifacts := rr['artifacts']!.as_map()
 for key,path in {'kernel':'linux','probe':'probe','wrapper_elf':'init','initramfs':'initramfs.cpio','serial':'serial.log'} {
  require(artifacts[key]!.str() == digest(reference+'/'+path)!,'Linux artifact changed')!
 }
 require(digest(reference+'/probe')! == digest(compile+'/probe')! && digest(reference+'/init')! == digest(compile+'/reference-init')!,'Different Linux ELF/launcher')!
 pollcopycheck.verify(os.read_file(reference+'/serial.log')!,arch,false,true)!
 before := os.read_file(original+'/blob.c')!
 after := os.read_file(build+'/blob.c')!
 scope(before,after)!
 registered := root+'/registered-'+suffix
 reg := object(registered+'/receipt.json')!
 require(reg['kernel_sha256']!.str() == kernel,'Registered kernel changed')!
 mut names := []string{}
 for row in reg['results']!.as_array() {
  r := row.as_map()
  name := r['name']!.str()
  require(name in ['pollcopy','ppolltime','ppollsignal'] && name !in names && r['exit_code']!.int() == 0,'Registered failure')!
  names << name
  if name == 'pollcopy' {
   frozen := json2.decode[map[string]string](json2.encode(r['source_inputs']!))!
   require(frozen.len == 2,'Incomplete frozen poll copyout fixture')!
   for file in ['core.v','storage.v'] {
    expected := digest(root+'/source/tests/linux-compat/pollcopyfixture/'+file)!
    pin(frozen,'/pollcopyfixture/'+file,expected)!
    require(digest(registered+'/sources/pollcopyfixture/'+file)! == expected,'Frozen source changed')!
   }
  }
  require(r['init_sha256']!.str() == digest(registered+'/'+name+'/init')! && r['iso_sha256']!.str() == digest(registered+'/'+name+'/test.iso')!,'Registered artifacts changed')!
  log := os.read_file(registered+'/'+name+'/serial.log')!
  if name == 'pollcopy' { pollcopycheck.verify(log,arch,false,false)! }
  else if name == 'ppolltime' { ppolltimecheck.verify(log,arch,false,false)! }
  else { ppollsignalcheck.verify(log,arch,false,false)! }
 }
 require(names.len == 3,'Missing regressions')!
 }
 println('Poll copyout evidence: PASS ('+manifest.len.str()+' files; original failures 1296 ARM / 1728 x86, fixed/Linux 10368 ARM / 13824 x86 checks, flat storage, 3/3 regressions per architecture, generated-C and review)')
}
fn main() {
 if os.args.len == 2 && os.args[1] == 'self-test' { pollcopycheck.self_test() or { panic(err) }; return }
 if os.args.len == 4 && os.args[1] == 'scope' {
  scope(os.read_file(os.args[2]) or { panic(err) },os.read_file(os.args[3]) or { panic(err) }) or { panic(err) }
  println('Poll copyout generated-C scope: PASS'); return
 }
 if os.args.len == 5 && os.args[1] == 'serial' {
  if os.args[3] !in ['baseline','native','reference'] { panic('Invalid execution profile') }
  pollcopycheck.verify(os.read_file(os.args[4]) or { panic(err) },os.args[2],os.args[3] == 'baseline',os.args[3] == 'reference') or { panic(err) }
  println('Poll copyout serial: PASS'); return
 }
 if os.args.len != 2 { panic('Usage: pollcopy-evidence BUNDLE | self-test | scope OLD-C NEW-C | serial ARCH baseline|native|reference LOG') }
 check(os.args[1]) or { panic(err) }
}
