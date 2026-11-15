// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import epollkeycheck
import pipereadycheck
import selectwakecheck
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
fn scope(before string,after string) ! {
 value := 'if (entry.fd == fd) {'
 pointer := 'if (entry->fd == fd) {'
 require(before.count(value) == 2 && before.count(pointer) == 1,'Unexpected baseline predicates')!
 wanted := before.replace(value,'if ((entry.fd == fd) && ((void*)(entry.handle) == (void*)(watched_fd->handle))) {')
  .replace(pointer,'if ((entry->fd == fd) && ((void*)(entry->handle) == (void*)(watched_fd->handle))) {')
 require(before != after && wanted == after,'Kernel C changed outside three address-identity predicates')!
}
fn controls() ! {
 a := 'prefix\nif (entry.fd == fd) {\nif (entry.fd == fd) {\nif (entry->fd == fd) {\nsuffix\n'
 b := a.replace('if (entry.fd == fd) {','if ((entry.fd == fd) && ((void*)(entry.handle) == (void*)(watched_fd->handle))) {')
  .replace('if (entry->fd == fd) {','if ((entry->fd == fd) && ((void*)(entry->handle) == (void*)(watched_fd->handle))) {')
 scope(a,b)!
 mut refused := 0
 for altered in [a,b+'extra',b.replace('prefix','changed'),b.replace('suffix','changed'),
  b.replace('watched_fd->handle','watched_fd->resource'),b.replace('&&','||'),
  b.replace('(void*)(entry.handle)','entry.handle'),b.replace('entry->fd == fd','entry->fd != fd')] {
  scope(a,altered) or { refused++; continue }
  return error('Altered generated C accepted')
 }
 println('Epoll registration key C scope controls: PASS (1 positive, '+refused.str()+' negative)')
 epollkeycheck.self_test()!
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
 for pair in [['arm','aarch64'],['x86','x86_64']] {
  suffix,arch := pair[0],pair[1]
  base := root+'/baseline-'+suffix
  build := root+'/build-'+suffix
  compile := root+'/compile-'+suffix
  for path in [base,build] { require(os.read_file(path+'/build.log.status')!.trim_space() == '0','Build failed')! }
  base_inputs := json2.decode[map[string]string](os.read_file(base+'/inputs.json')!)!
  inputs := json2.decode[map[string]string](os.read_file(build+'/inputs.json')!)!
  pin(base_inputs,'/kernel/file/epoll.v',digest(root+'/source/epoll.baseline.v')!)!
  pin(inputs,'/kernel/file/epoll.v',digest(root+'/source/kernel/file/epoll.v')!)!
  scope(os.read_file(base+'/blob.c')!,os.read_file(build+'/blob.c')!)!
  for previous in [true,false] {
   state := root+'/'+if previous { 'original-'+suffix } else { 'fixed-'+suffix }
   r := object(state+'/receipt.json')!
   passed(r,arch)!
   kernel := if previous { base } else { build }
   require(r['kernel']!.str() == digest(kernel+'/kernel/bin/vinix')! && r['kernel']!.str() == digest(state+'/kernel/bin/vinix')!
    && r['probe']!.str() == digest(compile+'/probe')! && r['probe']!.str() == digest(state+'/rootfs/sbin/init')!
    && r['serial']!.str() == digest(state+'/serial.log')!,'Changed native ELF/log')!
   epollkeycheck.verify(os.read_file(state+'/serial.log')!,arch,previous,false)!
  }
  cr := object(compile+'/receipt.json')!
  ci := json2.decode[map[string]string](json2.encode(cr['inputs']!))!
  for file in ['core.v','storage.v'] { pin(ci,'/epollkeyfixture/'+file,digest(root+'/source/tests/linux-compat/epollkeyfixture/'+file)!)! }
  pin(ci,'/epollkeyreferenceinit/core.v',digest(root+'/source/tests/linux-compat/epollkeyreferenceinit/core.v')!)!
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
  epollkeycheck.verify(os.read_file(reference+'/serial.log')!,arch,false,true)!
  registered := root+'/registered-'+suffix
  reg := object(registered+'/receipt.json')!
  require(reg['kernel_sha256']!.str() == digest(build+'/kernel/bin/vinix')!,'Different registered kernel')!
  mut names := []string{}
  for row in reg['results']!.as_array() {
   r := row.as_map(); name := r['name']!.str()
   require(name in ['epollkey','pipeready','selectwake'] && name !in names && r['exit_code']!.int() == 0,'Registered failure/repeated case')!
   names << name
   if name == 'epollkey' {
    frozen := json2.decode[map[string]string](json2.encode(r['source_inputs']!))!
    require(frozen.len == 2,'Incomplete frozen fixture')!
    for file in ['core.v','storage.v'] {
     wanted := digest(root+'/source/tests/linux-compat/epollkeyfixture/'+file)!
     pin(frozen,'/epollkeyfixture/'+file,wanted)!
     require(digest(registered+'/sources/epollkeyfixture/'+file)! == wanted,'Changed frozen fixture')!
    }
   }
   require(r['init_sha256']!.str() == digest(registered+'/'+name+'/init')! && r['iso_sha256']!.str() == digest(registered+'/'+name+'/test.iso')!,'Changed registered artifact')!
   log := os.read_file(registered+'/'+name+'/serial.log')!
   if name == 'epollkey' { epollkeycheck.verify(log,arch,false,false)! }
   else if name == 'pipeready' { pipereadycheck.verify(log,arch,false,false)! }
   else { selectwakecheck.verify(log,arch,false,false)! }
  }
  require(names.len == 3,'Missing registered suite')!
 }
 println('Epoll registration key evidence: PASS ('+manifest.len.str()+' files; 5760 checks per architecture, 840 matching original failures, flat stable-description cleanup, 3/3 registered suites per architecture, complete generated-C scope)')
}
fn main() {
 if os.args.len == 2 && os.args[1] == 'self-test' { controls() or { panic(err) }; return }
 if os.args.len == 4 && os.args[1] == 'scope' {
  scope(os.read_file(os.args[2]) or { panic(err) },os.read_file(os.args[3]) or { panic(err) }) or { panic(err) }
  println('Epoll registration key generated-C scope: PASS'); return
 }
 if os.args.len == 5 && os.args[1] == 'serial' {
  require(os.args[3] in ['baseline','native','reference'],'Invalid profile') or { panic(err) }
  epollkeycheck.verify(os.read_file(os.args[4]) or { panic(err) },os.args[2],os.args[3] == 'baseline',os.args[3] == 'reference') or { panic(err) }
  println('Epoll registration key serial: PASS'); return
 }
 if os.args.len != 2 { panic('Usage: epollkey-evidence BUNDLE | self-test | scope OLD-C NEW-C | serial ARCH baseline|native|reference LOG') }
 check(os.args[1]) or { panic(err) }
}
