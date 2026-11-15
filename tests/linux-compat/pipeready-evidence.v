// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import selectwakecheck
import pollcopycheck
import pipereadycheck
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

// Compiler-owned ignored locals include absolute-path hashes and generated
// counters, which shift when a callback parameter is added. Alpha-rename each
// complete identifier consistently; preserve distinct bindings and all uses.
fn canonical(source string) string {
	mut result := strings.new_builder(source.len)
	mut position := 0
	mut names := map[string]string{}
	for position < source.len {
		if source[position] == `"` || source[position] == `'` {
			quote := source[position]
			start := position
			position++
			for position < source.len {
				if source[position] == `\\` { position += if position+1 < source.len { 2 } else { 1 }; continue }
				last := source[position]; position++
				if last == quote { break }
			}
			result.write_string(source[start..position])
		} else if position+1 < source.len && source[position..position+2] in ['//','/*'] {
			block := source[position+1] == `*`
			start := position
			position += 2
			for position < source.len {
				if !block && source[position] == `\n` { break }
				if block && position+1 < source.len && source[position..position+2] == '*/' { position += 2; break }
				position++
			}
			result.write_string(source[start..position])
		} else if source[position].is_letter() || source[position] == `_` {
			start := position
			position++
			for position < source.len && (source[position].is_alnum() || source[position] == `_`) { position++ }
			identifier := source[start..position]
			if identifier.starts_with('__discard_') && identifier.len > 10 && identifier[10..].bytes().all((it >= `0` && it <= `9`) || it == `_`) {
				if identifier !in names { names[identifier] = '__discard_alpha_'+names.len.str() }
				result.write_string(names[identifier])
			} else { result.write_string(identifier) }
		} else {
			result.write_u8(source[position])
			position++
		}
	}
	return result.str()
}

fn canonical_controls() ! {
 a := 'int __discard_1_2 = 0; int __discard_1_3 = 1; __discard_1_2 += __discard_1_3;'
 b := 'int __discard_99_7 = 0; int __discard_99_8 = 1; __discard_99_7 += __discard_99_8;'
 require(canonical(a) == canonical(b) && canonical(canonical(a)) == canonical(a),'Valid compiler-local renaming refused')!
 for bad in [b.replace('= 1','= 2'),b.replace('__discard_99_8','__discard_99_7'),b.replace('+= __discard_99_8','+= __discard_99_7')] {
  require(canonical(a) != canonical(bad),'Binding, use or constant change hidden')!
 }
 for pair in [
  ['int __discard_1=0; puts("__discard_1");','int __discard_9=0; puts("__discard_9");'],
  ['/* __discard_1 */ int __discard_1=0;','/* __discard_9 */ int __discard_9=0;'],
  ['// __discard_1\nint __discard_1=0;','// __discard_9\nint __discard_9=0;'],
  [r'int __discard_1=0; puts("\"__discard_1\"");',r'int __discard_9=0; puts("\"__discard_9\"");'],
  [r"int __discard_1=0; int c='__discard_1';",r"int __discard_9=0; int c='__discard_9';"],
  ['int other__discard_1=0;','int other__discard_9=0;']
 ] { require(canonical(pair[0]) != canonical(pair[1]),'Literal/comment/nonlocal identifier change hidden')! }
 println('C alpha-renaming controls: PASS (2 positive, 9 negative)')
}

fn scope(before string, after string) ! {
 base := canonical(before)
 candidate := canonical(after)
 mut replaced := base
 adapters := ['drm__GemPrimeResource__poll_status','file__MemoryPressureFile__poll_status',
  'fs__CGroupPressureFile__poll_status','fs__CGroupResource__poll_status','fs__ProcFSResource__poll_status',
  'fs__SysFSResource__poll_status','proc__PidFile__poll_status','userland__SignalFD__poll_status']
 mut changed := adapters.clone()
 changed << ['file__ppoll','file__EpollResource__collect_ready','file__epoll_ready_events',
  'file__syscall_epoll_ctl','resource__poll_status','resource__PollableResource__poll_status']
 for name in changed {
  old := body(base,name)!
  new := body(candidate,name)!
  require(old != new,'Missing expected function change: '+name)!
  for token in ['__new_array','__free(', 'proc__reserve_kernel(', 'kbudget__release(', 'vinix_stack_alloc(', 'usercopy__copy_to_pagemap(', 'resource__poll_status('] {
   require(old.count(token) == new.count(token),'Ownership/copy changed in '+name+': '+token)!
  }
  if name in adapters { require(old.all_after('\n') == new.all_after('\n'),'Existing callback body changed: '+name)! }
  if name == 'file__syscall_epoll_ctl' {
   anchor := '|| (target->_typ == 593652764) || (target->_typ == 1031062005)'
   require(old.count(anchor) == 1 && old.replace(anchor,'|| (target->_typ == 1253457481) '+anchor) == new,'Unexpected epoll admission change')!
  }
  replaced = replaced.replace(old,new)
  old_proto := old.all_before('\n').trim_string_right(' {')+';'
  new_proto := new.all_before('\n').trim_string_right(' {')+';'
  replaced = replaced.replace(old_proto,new_proto)
 }
 pipe := body(candidate,'pipe__Pipe__poll_status')!
 prototype := pipe.all_before('\n').trim_string_right(' {')+';\n'
 require(candidate.count(prototype) == 1,'Missing pipe callback prototype')!
 stripped := candidate.replace(pipe+'\n','').replace(prototype,'')
 require(replaced == stripped,'Kernel C changed outside pipe readiness, callback ABI and epoll forwarding')!
 for token in ['__new_array','__malloc','__calloc','__free(','memdup('] { require(!pipe.contains(token),'Pipe callback allocated/freed: '+token)! }
 require(pipe.contains('klock__Lock__acquire(') && pipe.count('klock__Lock__release(') >= 2,'Missing pipe lock cleanup')!
 require(pipe.contains('->used') && pipe.contains('->capacity') && pipe.contains('->readers') && pipe.contains('->writers') && pipe.contains('->fifo'),'Incomplete pipe state query')!
}

fn check(root string) ! {
 canonical_controls()!
 manifest := json2.decode[map[string]string](os.read_file(root+'/manifest.json')!)!
 mut found := map[string]string{}
 inventory(root,'',mut found)!
 require(found == manifest,'Incomplete or changed evidence inventory')!
 review := os.read_file(root+'/review.txt')!
 require(review.contains('Independent pipe-readiness lifetime/ABI review: PASS.'),'Missing independent review')!
 require(review.contains(digest(root+'/source/tests/linux-compat/pipereadycheck/core.v')!),'Outdated checker review')!
 for file in ['core.v','storage.v'] {
  require(review.contains(digest(root+'/source/tests/linux-compat/pipereadyfixture/'+file)!),'Outdated fixture review')!
 }
 paths := json2.decode[[]string](os.read_file(root+'/kernel-paths.json')!)!
 require(paths.len == 12,'Incomplete kernel path inventory')!
 for path in paths { require(review.contains(digest(root+'/source/kernel/'+path)!),'Outdated kernel review: '+path)! }
 pipereadycheck.self_test()!
 for pair in [['arm','aarch64'],['x86','x86_64']] {
 suffix, arch := pair[0],pair[1]
 build := root+'/build-'+suffix
 original := root+'/baseline-'+suffix
 compile := root+'/compile-'+suffix
 kernel := digest(build+'/kernel/bin/vinix')!
 require(os.read_file(build+'/build.log.status')!.trim_space() == '0','Kernel build failed')!
 build_inputs := json2.decode[map[string]string](os.read_file(build+'/inputs.json')!)!
 for path in paths { pin(build_inputs,'/kernel/'+path,digest(root+'/source/kernel/'+path)!)! }
 for path in [compile+'/fixture.c',build+'/blob.c'] { require(review.contains(digest(path)!),'Outdated generated-C review')! }
 for previous in [true,false] {
  state := root+'/'+if previous { 'original-'+suffix } else { 'fixed-'+suffix }
  r := object(state+'/receipt.json')!
  passed(r,arch)!
  require(r['probe']!.str() == digest(compile+'/probe')! && digest(state+'/rootfs/sbin/init')! == r['probe']!.str()
   && r['kernel']!.str() == digest(state+'/kernel/bin/vinix')! && r['serial']!.str() == digest(state+'/serial.log')!,'Native executable or log changed')!
  expected_kernel := if previous { original } else { build }
  require(r['kernel']!.str() == digest(expected_kernel+'/kernel/bin/vinix')!,'Different native kernel')!
  pipereadycheck.verify(os.read_file(state+'/serial.log')!,arch,previous,false)!
 }
 c := object(compile+'/receipt.json')!
 inputs := json2.decode[map[string]string](json2.encode(c['inputs']!))!
 for file in ['core.v','storage.v'] { pin(inputs,'/pipereadyfixture/'+file,digest(root+'/source/tests/linux-compat/pipereadyfixture/'+file)!)! }
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
 pipereadycheck.verify(os.read_file(reference+'/serial.log')!,arch,false,true)!
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
  require(name in ['pipeready','selectwake','pollcopy'] && name !in names && r['exit_code']!.int() == 0,'Registered failure')!
  names << name
  if name == 'pipeready' {
   frozen := json2.decode[map[string]string](json2.encode(r['source_inputs']!))!
   require(frozen.len == 2,'Incomplete frozen pipe readiness fixture')!
   for file in ['core.v','storage.v'] {
    expected := digest(root+'/source/tests/linux-compat/pipereadyfixture/'+file)!
    pin(frozen,'/pipereadyfixture/'+file,expected)!
    require(digest(registered+'/sources/pipereadyfixture/'+file)! == expected,'Frozen source changed')!
   }
  }
  require(r['init_sha256']!.str() == digest(registered+'/'+name+'/init')! && r['iso_sha256']!.str() == digest(registered+'/'+name+'/test.iso')!,'Registered artifacts changed')!
  log := os.read_file(registered+'/'+name+'/serial.log')!
  if name == 'pipeready' { pipereadycheck.verify(log,arch,false,false)! }
  else if name == 'pollcopy' { pollcopycheck.verify(log,arch,false,false)! }
  else { selectwakecheck.verify(log,arch,false,false)! }
 }
 require(names.len == 3,'Missing regressions')!
 }
 println('Pipe readiness evidence: PASS ('+manifest.len.str()+' files; original failures 2616 ARM / 3342 x86, fixed/Linux 24180 ARM / 30960 x86 checks, flat storage, 3/3 regressions per architecture, generated-C and review)')
}
fn main() {
 if os.args.len == 2 && os.args[1] == 'self-test' { canonical_controls() or { panic(err) }; pipereadycheck.self_test() or { panic(err) }; return }
 if os.args.len == 4 && os.args[1] == 'scope' {
  scope(os.read_file(os.args[2]) or { panic(err) },os.read_file(os.args[3]) or { panic(err) }) or { panic(err) }
  println('Pipe readiness generated-C scope: PASS'); return
 }
 if os.args.len == 5 && os.args[1] == 'serial' {
  if os.args[3] !in ['baseline','native','reference'] { panic('Invalid execution profile') }
  pipereadycheck.verify(os.read_file(os.args[4]) or { panic(err) },os.args[2],os.args[3] == 'baseline',os.args[3] == 'reference') or { panic(err) }
  println('Pipe readiness serial: PASS'); return
 }
 if os.args.len != 2 { panic('Usage: pipeready-evidence BUNDLE | self-test | scope OLD-C NEW-C | serial ARCH baseline|native|reference LOG') }
 check(os.args[1]) or { panic(err) }
}
