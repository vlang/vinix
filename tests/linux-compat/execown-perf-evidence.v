// SPDX-License-Identifier: GPL-2.0-or-later
// Audit the preserved exec qualification desktop and retention guards on macOS.
module main
import crypto.sha256
import json2
import os
import perfreport
import strconv
#include <CommonCrypto/CommonDigest.h>
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(&C.CC_SHA256_CTX) i32
fn C.CC_SHA256_Update(&C.CC_SHA256_CTX, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, &C.CC_SHA256_CTX) i32
fn hash(path string) !string {
 mut file := os.open(path)!
 defer { file.close() }
 mut state := C.CC_SHA256_CTX{}
 if C.CC_SHA256_Init(&state) != 1 { return error('SHA initialization') }
 mut buffer := []u8{len:1048576}
 mut size := u64(0)
 for {
  n := file.read(mut buffer) or { if file.eof() { break }; return err }
  if n == 0 { break }
  size += u64(n)
  if C.CC_SHA256_Update(&state,buffer.data,u32(n)) != 1 { return error('SHA update') }
 }
 if size != os.file_size(path) { return error('Changed input size') }
 mut digest := [32]u8{}
 if C.CC_SHA256_Final(unsafe { &digest[0] },&state) != 1 { return error('SHA final') }
 alphabet := '0123456789abcdef'
 mut encoded := []u8{len:64}
 for index in 0 .. 32 {
  encoded[index*2] = alphabet[int(digest[index] >> 4)]
  encoded[index*2+1] = alphabet[int(digest[index] & 15)]
 }
 return encoded.bytestr()
}
fn inventory(root string, rel string, mut entries map[string]string) ! {
 path := root+'/'+rel
 mode := (u32(os.lstat(path)!.mode) & 0o7777).str()
 if os.is_link(path) { entries[rel] = 'link\t'+mode+'\t'+os.readlink(path)!.bytes().hex() }
 else if os.is_dir(path) {
  entries[rel] = 'directory\t'+mode
  mut names := os.ls(path)!; names.sort()
  for name in names { inventory(root,rel+'/'+name,mut entries)! }
 } else if os.is_file(path) { entries[rel] = 'file\t'+mode+'\t'+os.file_size(path).str()+'\t'+hash(path)! }
 else { return error('Unsupported artifact type: '+path) }
}
fn operations(text string) ! {
 mut wanted := map[string]bool{}
 for op in perfreport.general_ops { wanted[op+'/tmp'] = true }
 for dir in ['/tmp','/root'] { for op in perfreport.file_ops { wanted[op+dir] = true } }
 mut seen := map[string]bool{}
 for raw in text.split_into_lines() {
  line := raw.trim_space()
  if !line.starts_with('PERF-OPS ') { continue }
  f := line.fields()
  if f.len != 8 || f[1] != 'variant=new' || f[2] != 'scenario=ops' || f[3] != 'round=1'
   || f[6] != 'count=200' || f[7] != 'bytes_per_op=0' { return error('Non-flat/malformed operation: '+line) }
  key := f[4].all_after('=')+f[5].all_after('=')
  if key !in wanted || key in seen { return error('Unknown/repeated operation: '+key) }
  seen[key] = true
 }
 if seen != wanted { return error('Incomplete operations') }
}
fn main() {
 if os.args.len != 3 || os.args[1] !in ['record','check'] { panic('Usage: execown-perf-evidence record|check WORKSPACE') }
 mode := os.args[1]
 root := os.real_path(os.args[2])
 if !os.is_dir(root) || os.is_link(root) { panic('Regular workspace directory required') }
 if hash(@FILE)! != sha256.sum(os.read_bytes(@FILE)!).hex() { panic('Hash implementation control failed') }
 if mode == 'record' && (os.exists(root+'/performance-manifest.json') || os.exists(root+'/performance-summary.json')) { panic('Refusing to overwrite an inventory') }
 mut summary := map[string]json2.Any{}
 for suffix in ['arm','x86'] {
  name := if suffix == 'arm' { 'perf-native-arm-ops-r2' } else { 'perf-native-x86-ops' }
  operations(os.read_file(root+'/'+name+'/serial.log')!)!
 }
 failed := root+'/perf-native-arm-ops-r2'
 if os.read_file(failed+'/status')!.trim_space() != '1'
  || !os.read_file(failed+'/serial.log')!.contains('PERF-ERROR program="/usr/bin/curl"') {
  panic('Original ARM curl fixture failure differs')
 }
 foreign := os.read_bytes(failed+'/overlay/usr/bin/curl')!
 if foreign.len < 20 || foreign[..6] != [u8(127),`E`,`L`,`F`,2,1]
  || foreign[18] != 62 || foreign[19] != 0 { panic('Expected x86-only curl fixture was not retained') }
 for name, selected in {
  'perf-native-x86-ops':['ops','churn','cache','idle','apps']
  'perf-native-arm-ops-r4':['churn','cache','idle','apps']
  'perf-native-arm-ops-r5':['idle','apps']
  'perf-native-arm-ops-r6':['idle','apps']
  'perf-native-arm-drag-r3':['drag']
  'perf-native-x86-drag-r2':['drag']
 } {
  raw := os.read_bytes(root+'/'+name+'/serial.log')!
  suffix := if name.contains('-arm-') { 'arm' } else { 'x86' }
  kernel := hash(root+'/bundle/build-'+suffix+'-r1/kernel/bin/vinix')!
  if hash(root+'/'+name+'/kernel/bin/vinix')! != kernel { panic('Different performance kernel: '+name) }
  verdict := perfreport.inspect_policy(raw,['new'],selected,1,false,perfreport.Value(perfreport.Number{'0'}),false)
  if verdict.errors.len != 0 || os.read_file(root+'/'+name+'/status')!.trim_space() != '0' { panic(name+': '+verdict.errors.str()) }
  mut slabs := []string{}
  mut churn := 0
  mut live_apps := map[string]bool{}
  for raw_line in raw.bytestr().split_into_lines() {
   line := raw_line.trim_space()
   if line.starts_with('PERF-CHURN ') {
    if !line.contains(' runs=300 retained_kb=0 per_run_bytes=0') { panic('Retained program memory: '+line) }
    churn++
   }
   if name.ends_with('-r6') && line.starts_with('PERF-PROC ') && line.contains(' scenario=apps ') {
    mut process := ''
    mut threads := i64(0)
    for field in line.fields() {
     if field.starts_with('name=') { process = field.all_after('=').all_before('[') }
     if field.starts_with('threads=') { threads = strconv.parse_int(field.all_after('='),10,64)! }
    }
    if threads > 0 { live_apps[process] = true }
   }
   if line.starts_with('PERF-SLAB ') {
    slabs << line
    for field in line.fields() {
     if field.starts_with('objects=') || field.starts_with('pages=') {
      if strconv.parse_int(field.all_after('='),10,64)! > 0 { panic('Growing slab: '+line) }
     }
    }
   }
  }
  if name.ends_with('-r6') {
   for app in ['vinix-files','vinix-terminal','vinix-clock','vinix-calculator','vinix-activity'] {
    if '/usr/bin/'+app !in live_apps { panic('Requested application did not start: '+app) }
   }
  }
  summary[name] = {'rows':json2.Any(verdict.rows.len),'churn_rows':json2.Any(churn),'slab_changes':json2.Any(slabs),'complete':json2.Any(true),'five_live_client_names_checked':json2.Any(name.ends_with('-r6'))}
 }
 summary['arm-ops-r2-composite'] = {'complete':json2.Any(false),'operation_rows':json2.Any(36),'operations_flat':json2.Any(true),'failure':json2.Any('The later curl churn used the x86-only overlay; failed run preserved. ARM-native churn/cache/idle/apps rerun in r4.')}
 if mode == 'record' { os.write_file(root+'/performance-summary.json',json2.encode(summary,prettify:true)+'\n')! }
 else {
  retained := json2.decode[map[string]json2.Any](os.read_file(root+'/performance-summary.json')!)!
  if json2.encode(retained) != json2.encode(summary) { panic('Changed performance summary') }
 }
 names := ['perf-arm','perf-native-arm-ops','perf-native-arm-ops-r1','perf-native-arm-ops-r2','perf-native-arm-ops-r4','perf-native-arm-ops-r5','perf-native-arm-ops-r6','perf-native-arm-drag-r2','perf-native-arm-drag-r3','perf-native-x86-ops','perf-native-x86-drag-r2']
 mut first := map[string]string{}
 mut second := map[string]string{}
 for name in names { inventory(root,name,mut first)! }
 for name in names { inventory(root,name,mut second)! }
 if first != second { panic('Performance artifacts changed during inventory') }
 if mode == 'record' {
  os.write_file(root+'/performance-manifest.json',json2.encode({'entries':json2.decode[json2.Any](json2.encode(first))!,'producer':json2.Any(hash(@FILE)!), 'summary':json2.Any(hash(root+'/performance-summary.json')!), 'kernel_manifest':json2.Any(hash(root+'/bundle/manifest.json')!)},prettify:true)+'\n')!
 } else {
  manifest := (json2.decode[json2.Any](os.read_file(root+'/performance-manifest.json')!)!).as_map()
  expected := json2.decode[map[string]string](json2.encode(manifest['entries']!))!
  if first != expected || manifest['producer']!.str() != hash(@FILE)! || manifest['summary']!.str() != hash(root+'/performance-summary.json')! || manifest['kernel_manifest']!.str() != hash(root+'/bundle/manifest.json')! { panic('Changed performance inventory, producer, kernel or summary') }
 }
 println('Performance observations checked; complete stable typed inventory: '+hash(root+'/performance-manifest.json')!)
}
