// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import epollchurncheck
import pipereadycheck
import epollkeycheck
import json2
import os

fn require(good bool,reason string) ! { if !good { return error(reason) } }
fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn object(path string) !map[string]json2.Any { return json2.decode[map[string]json2.Any](os.read_file(path)!)! }
fn pin(inputs map[string]string,suffix string,expected string) ! {
 mut found := 0
 for name,value in inputs { if name.ends_with(suffix) {
  require(value == expected,'Different input: '+name)!; found++
 } }
 require(found == 1,'Missing/ambiguous input: '+suffix)!
}
fn inventory(root string,relative string,mut files map[string]string) ! {
 path := if relative == '' { root } else { root+'/'+relative }
 require(!os.is_link(path),'Artifact symlink: '+relative)!
 if os.is_dir(path) { for name in os.ls(path)! {
  child := if relative == '' { name } else { relative+'/'+name }
  if child != 'manifest.json' { inventory(root,child,mut files)! }
 } } else {
  require(os.is_file(path),'Unexpected artifact type: '+relative)!
  files[relative] = digest(path)!
 }
}
fn body(source string) !string {
 mut start := -1; mut offset := 0
 for line in source.split_into_lines() {
  if line.starts_with('string fs__anonymous_descriptor_text(') && line.ends_with(' {') {
   require(start == -1,'Repeated text function')!; start = offset
  }
  offset += line.len+1
  if start >= 0 && line == '}' { return source[start..offset] }
 }
 return error('Missing text function')
}
fn scope(before string,after string) ! {
 old := body(before)!; new := body(after)!
 box := '\tlib__Text __esc_0 = lib__new_text(32);\n\tlib__Text* text = (lib__Text*)(memdup(&__esc_0, sizeof(lib__Text)));'
 require(old.count(box) == 1 && old.count('return lib__Text__str(text);') == 1,'Unexpected escaped builder')!
 wanted := old.replace(box,'\tlib__Text text = lib__new_text(32);')
  .replace('lib__Text__add(text,','lib__Text__add(&text,')
  .replace('lib__Text__add_unsigned(text,','lib__Text__add_unsigned(&text,')
  .replace('lib__Text__add_byte(text,','lib__Text__add_byte(&text,')
  .replace('return lib__Text__str(text);','return lib__finish_text(text);')
 require(old != new && wanted == new && before.replace(old,new) == after,'Kernel C changed outside the exact stack-builder replacement')!
}
fn controls() ! {
 a := 'prefix\nstring fs__anonymous_descriptor_text(resource__Resource* res) {\n\tlib__Text __esc_0 = lib__new_text(32);\n\tlib__Text* text = (lib__Text*)(memdup(&__esc_0, sizeof(lib__Text)));\nlib__Text__add(text, name);\nlib__Text__add_unsigned(text, 42);\nlib__Text__add_byte(text, 93);\nreturn lib__Text__str(text);\n}\nsuffix\n'
 b := a.replace('\tlib__Text __esc_0 = lib__new_text(32);\n\tlib__Text* text = (lib__Text*)(memdup(&__esc_0, sizeof(lib__Text)));','\tlib__Text text = lib__new_text(32);')
  .replace('lib__Text__add(text,','lib__Text__add(&text,').replace('lib__Text__add_unsigned(text,','lib__Text__add_unsigned(&text,')
  .replace('lib__Text__add_byte(text,','lib__Text__add_byte(&text,').replace('return lib__Text__str(text);','return lib__finish_text(text);')
 scope(a,b)!
 mut refused := 0
 for altered in [a,b+'extra',b.replace('prefix','changed'),b.replace('suffix','changed'),b.replace('42','43'),
  b.replace('&text','text'),b.replace('lib__finish_text','lib__Text__str'),b.replace('lib__new_text(32)','lib__new_text(64)')] {
  scope(a,altered) or { refused++; continue }; return error('Changed lifetime/body accepted')
 }
 println('Procfs builder C scope controls: PASS (1 positive, '+refused.str()+' negative)')
 epollchurncheck.self_test()!
}
fn passed(r map[string]json2.Any,arch string) ! {
 require(r['architecture']!.str() == arch && r['finished']!.bool() && r['passed']!.bool()
  && r['status']!.int() == 0,'Unfinished/failed session')!
}
fn check(root string) ! {
 controls()!
 manifest := json2.decode[map[string]string](os.read_file(root+'/manifest.json')!)!
 mut files := map[string]string{}
 inventory(root,'',mut files)!
 require(files == manifest,'Changed/incomplete evidence inventory')!
 require(os.read_file(root+'/revision')!.trim_space().len == 40,'Missing source revision')!
 review := os.read_file(root+'/reviewer-scope.log')!
 require(review.contains('PASS'),'Missing independent review')!
 for path in ['source/kernel/fs/procfs.v','source/tests/linux-compat/epollchurnfixture/core.v','source/tests/linux-compat/epollchurnfixture/storage.v','source/tests/linux-compat/epollchurncheck/core.v','build-arm/blob.c','build-x86/blob.c'] { require(review.contains(digest(root+'/'+path)!), 'Outdated independent review: '+path)! }
 for pair in [['arm','aarch64'],['x86','x86_64']] {
  suffix,arch := pair[0],pair[1]
  base := root+'/baseline-'+suffix
  build := root+'/build-'+suffix
  compile := root+'/compile-'+suffix
  for path in [base,build] { require(os.read_file(path+'/build.log.status')!.trim_space() == '0','Build failed')! }
  base_inputs := json2.decode[map[string]string](os.read_file(base+'/inputs.json')!)!
  inputs := json2.decode[map[string]string](os.read_file(build+'/inputs.json')!)!
  pin(base_inputs,'/kernel/fs/procfs.v',digest(root+'/source/procfs.baseline.v')!)!
  pin(inputs,'/kernel/fs/procfs.v',digest(root+'/source/kernel/fs/procfs.v')!)!
  scope(os.read_file(base+'/blob.c')!,os.read_file(build+'/blob.c')!)!
  for previous in [true,false] {
   state := root+'/'+if previous { 'original-'+suffix } else { 'fixed-'+suffix }
   r := object(state+'/receipt.json')!
   passed(r,arch)!
   kernel := if previous { base } else { build }
   require(r['kernel']!.str() == digest(kernel+'/kernel/bin/vinix')! && r['kernel']!.str() == digest(state+'/kernel/bin/vinix')!
    && r['probe']!.str() == digest(compile+'/probe')! && r['probe']!.str() == digest(state+'/rootfs/sbin/init')!
    && r['serial']!.str() == digest(state+'/serial.log')!,'Changed native ELF/log')!
   epollchurncheck.verify(os.read_file(state+'/serial.log')!,arch,previous,false)!
  }
  cr := object(compile+'/receipt.json')!
  ci := json2.decode[map[string]string](json2.encode(cr['inputs']!))!
  for file in ['core.v','storage.v'] { pin(ci,'/epollchurnfixture/'+file,digest(root+'/source/tests/linux-compat/epollchurnfixture/'+file)!)! }
  pin(ci,'/epollchurnreferenceinit/core.v',digest(root+'/source/tests/linux-compat/epollchurnreferenceinit/core.v')!)!
  co := json2.decode[map[string]string](json2.encode(cr['outputs']!))!
  pin(co,'/probe',digest(compile+'/probe')!)!
  pin(co,'/reference-init',digest(compile+'/reference-init')!)!
  reference := root+'/reference-'+suffix
  rr := object(reference+'/receipt.json')!
  passed(rr,arch)!
  artifacts := rr['artifacts']!.as_map()
  for name,path in {'kernel':'linux','probe':'probe','wrapper_elf':'init','initramfs':'initramfs.cpio','serial':'serial.log'} {
   require(artifacts[name]!.str() == digest(reference+'/'+path)!,'Changed Linux artifact')!
  }
  require(digest(reference+'/probe')! == digest(compile+'/probe')! && digest(reference+'/init')! == digest(compile+'/reference-init')!,'Different Linux ELF')!
  epollchurncheck.verify(os.read_file(reference+'/serial.log')!,arch,false,true)!
  registered := root+'/registered-'+suffix
  reg := object(registered+'/receipt.json')!
  require(reg['kernel_sha256']!.str() == digest(build+'/kernel/bin/vinix')!,'Different registered kernel')!
  mut names := []string{}
  for row in reg['results']!.as_array() {
   r := row.as_map(); name := r['name']!.str()
   require(name in ['epollchurn','pipeready','epollkey'] && name !in names && r['exit_code']!.int() == 0,'Registered failure/repeated case')!
   names << name
   if name == 'epollchurn' {
    frozen := json2.decode[map[string]string](json2.encode(r['source_inputs']!))!
    require(frozen.len == 2,'Incomplete frozen fixture')!
    for file in ['core.v','storage.v'] {
     wanted := digest(root+'/source/tests/linux-compat/epollchurnfixture/'+file)!
     pin(frozen,'/epollchurnfixture/'+file,wanted)!
     require(digest(registered+'/sources/epollchurnfixture/'+file)! == wanted,'Changed frozen fixture')!
    }
   }
   require(r['init_sha256']!.str() == digest(registered+'/'+name+'/init')! && r['iso_sha256']!.str() == digest(registered+'/'+name+'/test.iso')!,'Changed registered artifact')!
   log := os.read_file(registered+'/'+name+'/serial.log')!
   if name == 'epollchurn' { epollchurncheck.verify(log,arch,false,false)! }
   else if name == 'pipeready' { pipereadycheck.verify(log,arch,false,false)! }
   else { epollkeycheck.verify(log,arch,false,false)! }
  }
  require(names.len == 3,'Missing registered suite')!
 }
 trace := root+'/trace-arm'
 tr := object(trace+'/receipt.json')!; passed(tr,'aarch64')!
 require(tr['kernel']!.str() == digest(root+'/track-arm/kernel/bin/vinix')! && tr['kernel']!.str() == digest(trace+'/kernel/bin/vinix')! && tr['probe']!.str() == digest(root+'/compile-arm/probe')! && tr['serial']!.str() == digest(trace+'/serial.log')!,'Changed tracking kernel/ELF/log')!
 epollchurncheck.verify(os.read_file(trace+'/serial.log')!,'aarch64',true,false)!
 require(os.read_file(trace+'/serial.log')!.contains('PERF-SITE program=epollchurn uid=0 7200 48 ') && os.read_file(trace+'/serial.log')!.contains('dropped 0'),'Missing complete allocation attribution')!
 require(os.read_file(root+'/trace-sites-final.log')!.contains('fs__anonymous_descriptor_text <- fs__refresh_fd_directory'),'Missing symbolized call chain')!
 require(os.read_file(root+'/perf-arm-selfcheck.log')!.contains('PERF ARM HOST PASS eighteen checks')
  && os.read_file(root+'/perf-x86-selfcheck.log')!.contains('PERF X86 SELFCHECK PASS 37 checks')
  && os.read_file(root+'/perf-runner-tests.log')!.contains('PASS 100 native PTY owners in one process, flat descriptors'),'Missing host validation')!
 require(os.read_file(root+'/perf-arm-init-link.log')!.contains("field precision should have type 'int'")
  && os.read_file(root+'/perf-x86-prepare-wrapper.log')!.contains('missing guest file: /usr/bin/curl')
  && os.read_file(root+'/allocation-policy.log')!.contains('NEW:'),'Missing retained broader-check refusals')!
 println('Procfs anonymous-descriptor churn evidence: PASS ('+manifest.len.str()+' files; 5760 checks per architecture, original 7200 size-48 objects per credential cohort, flat full-churn cleanup, 3/3 registered suites per architecture, complete generated-C scope and lifetime review)')
}
fn main() {
 if os.args.len == 2 && os.args[1] == 'self-test' { controls() or { panic(err) }; return }
 if os.args.len == 4 && os.args[1] == 'scope' {
  scope(os.read_file(os.args[2]) or { panic(err) },os.read_file(os.args[3]) or { panic(err) }) or { panic(err) }
  println('Procfs anonymous-descriptor churn generated-C scope: PASS'); return
 }
 if os.args.len == 5 && os.args[1] == 'serial' {
  require(os.args[3] in ['baseline','native','reference'],'Invalid profile') or { panic(err) }
  epollchurncheck.verify(os.read_file(os.args[4]) or { panic(err) },os.args[2],os.args[3] == 'baseline',os.args[3] == 'reference') or { panic(err) }
  println('Procfs anonymous-descriptor churn serial: PASS'); return
 }
 if os.args.len != 2 { panic('Usage: epollchurn-evidence BUNDLE | self-test | scope OLD-C NEW-C | serial ARCH baseline|native|reference LOG') }
 check(os.args[1]) or { panic(err) }
}
