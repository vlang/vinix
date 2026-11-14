// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import selecttimeoutcheck
import ppollargscheck
import pollcountcheck
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
 require(review.contains('Independent poll-count lifetime/arithmetic review: PASS. No findings.'),'Missing independent review')!
 for path in ['source/kernel/file/file.v','source/tests/linux-compat/pollcountfixture/core.v','source/tests/linux-compat/pollcountfixture/storage.v','compile-x86-r2/fixture.c','build-x86/blob.c'] {
  require(review.contains(digest(root+'/'+path)!),'Outdated review: '+path)!
 }
 pollcountcheck.self_test()!
 for pair in [['original', 'true'],['fixed','false']] {
  state := root+'/'+pair[0]+'-x86'
  r := object(state+'/receipt.json')!
  passed(r,'x86_64')!
  require(r['probe']!.str() == digest(root+'/compile-x86-r2/probe')! && digest(state+'/rootfs/sbin/init')! == r['probe']!.str()
   && r['kernel']!.str() == digest(state+'/kernel/bin/vinix')! && r['serial']!.str() == digest(state+'/serial.log')!,'Native executable or log changed')!
  expected_kernel := root+'/'+if pair[0] == 'original' { 'baseline' } else { 'build-x86' }
  require(r['kernel']!.str() == digest(expected_kernel+'/kernel/bin/vinix')!,'Different native kernel')!
  pollcountcheck.verify(os.read_file(state+'/serial.log')!,'x86_64',pair[1] == 'true',false)!
 }
 c := object(root+'/compile-x86-r2/receipt.json')!
 inputs := json2.decode[map[string]string](json2.encode(c['inputs']!))!
 for file in ['core.v','storage.v'] { pin(inputs,'/pollcountfixture/'+file,digest(root+'/source/tests/linux-compat/pollcountfixture/'+file)!)! }
 outputs := json2.decode[map[string]string](json2.encode(c['outputs']!))!
 pin(outputs,'/probe',digest(root+'/compile-x86-r2/probe')!)!
 pin(outputs,'/reference-init',digest(root+'/compile-x86-r2/reference-init')!)!
 rr := object(root+'/reference-x86/receipt.json')!
 passed(rr,'x86_64')!
 artifacts := rr['artifacts']!.as_map()
 for key,path in {'kernel':'linux','probe':'probe','wrapper_elf':'init','initramfs':'initramfs.cpio','serial':'serial.log'} {
  require(artifacts[key]!.str() == digest(root+'/reference-x86/'+path)!,'Linux artifact changed')!
 }
 require(digest(root+'/reference-x86/probe')! == digest(root+'/compile-x86-r2/probe')!,'Different Linux ELF')!
 pollcountcheck.verify(os.read_file(root+'/reference-x86/serial.log')!,'x86_64',false,true)!
 for arch in ['arm','x86'] { require(os.read_file(root+'/build-'+arch+'/build.log.status')!.trim_space() == '0','Kernel build failed')! }
 before := os.read_file(root+'/baseline/blob.c')!
 after := os.read_file(root+'/build-x86/blob.c')!
 old := body(before,'file__syscall_poll')!
 new := body(after,'file__syscall_poll')!
 require(canonical(before.replace(old,new).replace(old.all_before('\n').trim_string_right(' {')+';',new.all_before('\n').trim_string_right(' {')+';')) == canonical(after),'Kernel C changed outside poll entrypoint')!
 require(new.contains('(u32)(nfds_word)') && new.contains('nfds > 4096'),'Missing count normalization/cap')!
 for token in ['__new_array','__free(', 'proc__reserve_kernel(', 'kbudget__release(', 'vinix_stack_alloc('] { require(old.count(token) == new.count(token),'Ownership changed: '+token)! }
 reg := object(root+'/registered-x86/receipt.json')!
 require(reg['kernel_sha256']!.str() == digest(root+'/build-x86/kernel/bin/vinix')!,'Registered kernel changed')!
 mut names := []string{}
 for row in reg['results']!.as_array() {
  r := row.as_map()
  name := r['name']!.str()
  require(name in ['pollcount','ppollargs','selecttimeout'] && name !in names && r['exit_code']!.int() == 0,'Registered failure')!
  names << name
  if name == 'pollcount' {
   frozen := json2.decode[map[string]string](json2.encode(r['source_inputs']!))!
   require(frozen.len == 2,'Incomplete frozen poll fixture')!
   for file in ['core.v','storage.v'] {
    expected := digest(root+'/source/tests/linux-compat/pollcountfixture/'+file)!
    pin(frozen,'/pollcountfixture/'+file,expected)!
    require(digest(root+'/registered-x86/sources/pollcountfixture/'+file)! == expected,'Frozen source changed')!
   }
  }
  require(r['init_sha256']!.str() == digest(root+'/registered-x86/'+name+'/init')! && r['iso_sha256']!.str() == digest(root+'/registered-x86/'+name+'/test.iso')!,'Registered artifacts changed')!
  log := os.read_file(root+'/registered-x86/'+name+'/serial.log')!
  if name == 'pollcount' { pollcountcheck.verify(log,'x86_64',false,false)! }
  else if name == 'ppollargs' { ppollargscheck.verify(log,'x86_64',false,false)! }
  else { selecttimeoutcheck.verify(log,'x86_64',false,false)! }
 }
 require(names.len == 3,'Missing regressions')!
 println('Poll count evidence: PASS ('+manifest.len.str()+' files; original 84 failures, fixed/Linux 350 checks, flat storage, 3/3 regressions, both kernel builds)')
}
fn main() {
 if os.args.len != 2 { panic('Usage: pollcount-evidence BUNDLE') }
 check(os.args[1]) or { panic(err) }
}
