// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
import encoding.hex
import json2
import fixturehost
import hosttest

struct BindingError {
 row map[string]json2.Any
}
fn (e BindingError) msg() string { return 'binding callback failed' }
fn (e BindingError) code() int { return 0 }

fn callback(name string, arguments json2.Any) !json2.Any {
 println(json2.encode(json2.Any({'callback': json2.Any(name), 'arguments': arguments})))
 row := hosttest.decode_json(os.input(''))!.as_map()
 if 'error' in row { return BindingError{row['error']!.as_map()} }
 return row['value']!
}
fn field(row map[string]json2.Any, name string) string { return row[name]!.str() }
fn raw(row map[string]json2.Any, name string) !string { return hex.decode(field(row,name))!.bytestr() }
fn quoted(value string) json2.Any { return json2.Any(value.bytes().hex()) }
fn strings(items []string) json2.Any { return json2.Any(items.map(json2.Any(it))) }

// The original subprocess/text decoder retains the invoking stdin, buffered
// stream decoder order and standard descriptor behavior. V owns argv and join.
fn debugfs(tool string, disk string, request string) !string {
 result := callback('capture_debugfs', strings([tool, '-R', request, disk].map(it.bytes().hex())))!.as_array()
 return result[0].str() + result[1].str()
}
fn inode(tool string, disk string, path string) !json2.Any {
 text := debugfs(tool, disk, 'stat ' + path)!
 if text.contains('File not found') { return json2.Null{} }
 mut fields := map[string]json2.Any{}
 for name in ['Type', 'Mode', 'Links'] {
  // Matching remains the upstream interpreter regex engine. Native policy owns
  // the field loop, exact patterns, optional captures and publication order.
  matched := callback('search_group', strings(['\\b' + name + ':\\s+(\\S+)', text]))!
  if matched !is json2.Null { fields[name] = matched }
 }
 return fields
}
fn expect(tool string, disk string, path string, wanted map[string]string, order []string) ![]string {
 found := inode(tool, disk, path)!
 if found is json2.Null { return [path + ' is not on the disk'] }
 fields := found.as_map()
 mut failures := []string{}
 for name in order {
  value := wanted[name]
  actual := if name in fields { fields[name]!.str() } else { 'None' }
  if actual != value { failures << path + ' has ' + name + ' ' + actual + ', not ' + value }
 }
 return failures
}
fn absent(tool string, disk string, path string) ![]string {
 found := inode(tool, disk, path)!
 return if found is json2.Null { []string{} } else { [path + ' is still on the disk'] }
}
fn freed(tool string, disk string, number string) ![]string {
 text := debugfs(tool, disk, 'testi <' + number + '>')!
 return if text.contains('not in use') { []string{} } else { ['inode ' + number + ' is still in use'] }
}
fn combine(first []string, second []string) []string {
 mut result := first.clone()
 result << second
 return result
}
fn check(tool string, disk string, step string, number string) ![]string {
 match step {
  'mkdir' { return expect(tool, disk, '/made', {'Type':'directory'}, ['Type'])! }
  'create' { return expect(tool, disk, '/named', {'Type':'regular'}, ['Type'])! }
  'rename' { return combine(absent(tool, disk, '/named')!, expect(tool, disk, '/renamed', {'Type':'regular'}, ['Type'])!) }
  'link' { return expect(tool, disk, '/linked', {'Type':'regular', 'Links':'2'}, ['Type','Links'])! }
  'unlink' { return combine(absent(tool, disk, '/renamed')!, expect(tool, disk, '/linked', {'Links':'1'}, ['Links'])!) }
  'chmod' { return expect(tool, disk, '/linked', {'Mode':'0600'}, ['Mode'])! }
  'exit' { return combine(absent(tool, disk, '/made/exited')!, freed(tool, disk, number)!) }
  'exec' { return combine(absent(tool, disk, '/made/execed')!, freed(tool, disk, number)!) }
  else { return ['no check for ' + step] }
 }
}

fn find_debugfs() !json2.Any {
 found := callback('which', json2.Any('debugfs'))!
 mut candidates := []json2.Any{cap:4}
 candidates << found
 for value in ['/opt/homebrew/opt/e2fsprogs/sbin/debugfs','/usr/local/opt/e2fsprogs/sbin/debugfs','/sbin/debugfs'] { candidates << quoted(value) }
 for candidate in candidates {
  if candidate is json2.Null { continue }
  if candidate.str() == '' { continue }
  if callback('access', candidate)!.bool() { return candidate }
 }
 return json2.Null{}
}
fn command(root string, init string, build bool) []string {
 mut result := [unix_path(root,'scripts/run-aarch64.sh'), '--serial','--mem=2048','--guest-init=' + init]
 if !build { result.insert(1,'--no-build') }
 return result
}
fn report(args map[string]json2.Any) !json2.Any {
 transcript := raw(args,'transcript')!
 step := field(args,'step')
 mut message := ''
 if ['VINIX NO SYNC: FAIL','FATAL EXCEPTION','KERNEL PANIC'].any(transcript.contains(it)) {
  message = 'ERROR: the guest reported a failure at ' + step
 } else if !transcript.contains('VINIX NO SYNC: START') {
  message = 'ERROR: the guest never started ' + step
 } else {
  done := args['done']!
  if done is json2.Null { message = 'ERROR: the guest never finished ' + step }
  else if callback('decode_done', done.as_array()[0])!.str() != step { message = 'ERROR: the guest never finished ' + step }
  else { return json2.Any([json2.Any(true),done.as_array()[1]]) }
 }
 callback('print', json2.Any({'message':json2.Any(message),'error':json2.Any(true)}))!
 return json2.Any([json2.Any(false),json2.Any('0')])
}
fn unix_path(base string, name string) string {
 if base == '.' || base == '' { return name }
 return base + (if base.ends_with('/') { '' } else { '/' }) + name
}
fn environment(paths map[string]json2.Any) !map[string]string {
 mut env := current_environment()!
 for entry in [['VINIX_INITRAMFS','initramfs'],['VINIX_BOOT_DISK','boot'],['VINIX_EFIVARS','efivars'],['VINIX_QEMU_PACKAGE_STORE','packages'],['VINIX_QEMU_PERSIST_DISK','disk']] {
  env[entry[0]] = raw(paths,entry[1])!
 }
 env['VINIX_QEMU_PERSIST_SIZE_MB'] = '64'
 env.delete('VINIX_QEMU_PERSIST')
 env['VINIX_KEEP_TEMP_BOOT_DISK'] = '1'
 // setdefault's argument is eager even when the port already exists.
 port := callback('port',json2.Null{})!.str()
 if 'VINIX_QEMU_PACKAGE_STORE_PORT' !in env { env['VINIX_QEMU_PACKAGE_STORE_PORT'] = port }
 if callback('platform',json2.Null{})!.str() != 'Darwin' && 'USE_TCG' !in env { env['USE_TCG'] = '1' }
 return env
}
fn current_environment() !map[string]string {
 rows := callback('process_environment',json2.Null{})!.as_array()
 mut result := map[string]string{}
 for row in rows { fields := row.as_array(); result[hex.decode(fields[0].str())!.bytestr()] = hex.decode(fields[1].str())!.bytestr() }
 return result
}
fn encoded_environment(env map[string]string) json2.Any {
 mut result := []json2.Any{cap:env.len}
 for key,value in env { result << json2.Any([quoted(key),quoted(value)]) }
 return json2.Any(result)
}
fn workflow() !json2.Any {
 tool := find_debugfs()!
 if tool is json2.Null {
  callback('print',json2.Any({'message':json2.Any('ERROR: reading the volume needs debugfs (install e2fsprogs)'),'error':json2.Any(true)}))!
  return json2.Any(1)
 }
 context := callback('paths',json2.Null{})!.as_array()
 state := hex.decode(context[1].str())!.bytestr()
 mut paths := map[string]json2.Any{}
 for key,name in {'disk':'root.ext2','initramfs':'initramfs.tar','boot':'boot.img','efivars':'efivars.fd','packages':'packages.tar'} { paths[key] = quoted(unix_path(state,name)) }
 env := environment(paths)!
 mut build := callback('build',json2.Null{})!.bool()
 for step in ['mkdir','create','rename','link','unlink','chmod','exit','exec'] {
  callback('initramfs',json2.Any({'path':paths['initramfs']!,'step':json2.Any(step)}))!
  result := callback('boot',json2.Any({'root':context[0],'environment':encoded_environment(env),'build':json2.Any(build),'step':json2.Any(step)}))!.as_array()
  build = false
  if !result[0].bool() { return json2.Any(1) }
  problems := check(hex.decode(tool.str())!.bytestr(),raw(paths,'disk')!,step,result[1].str())!
  if problems.len != 0 {
   for problem in problems { callback('print',json2.Any({'message':json2.Any('ERROR: after ' + step + ' with no sync: ' + problem),'error':json2.Any(true)}))! }
   return json2.Any(1)
  }
  callback('print',json2.Any({'message':json2.Any('==> ' + step + ' was on the disk when its call returned'),'error':json2.Any(false)}))!
 }
 callback('print',json2.Any({'message':json2.Any('==> AArch64 changes reached the disk with no sync'),'error':json2.Any(false)}))!
 return json2.Any(0)
}
fn execute(row map[string]json2.Any) !json2.Any {
 args := row['arguments']!.as_map()
 return match field(row, 'operation') {
  'debugfs' { json2.Any(debugfs(raw(args,'tool')!,raw(args,'disk')!,raw(args,'request')!)!) }
  'inode' { inode(raw(args,'tool')!,raw(args,'disk')!,raw(args,'path')!)! }
  'check' { strings(check(raw(args,'tool')!,raw(args,'disk')!,field(args,'step'),field(args,'number'))!) }
  'find' { find_debugfs()! }
  'command' { strings(command(raw(args,'root')!,raw(args,'init')!,args['build']!.bool()).map(it.bytes().hex())) }
  'report' { report(args)! }
  'main' { workflow()! }
  else { return error('unknown disk no-sync controller operation') }
 }
}
fn failure(err IError) json2.Any {
 if err is BindingError { return json2.Any(err.row) }

 return json2.Any({'kind':json2.Any(if err.msg() == 'embedded null byte' { 'ValueError' } else { 'RuntimeError' }),'message':json2.Any(err.msg())})
}
fn main() {
 if os.args.len == 3 && os.args[1] == '--install-query' {
  fixturehost.install(os.args[2]) or { eprintln(err); exit(1) }
  return
 }
 row := hosttest.decode_json(os.input('')) or { println(json2.encode(json2.Any({'error':failure(err)}))); return }
 result := execute(row.as_map()) or { println(json2.encode(json2.Any({'error':failure(err)}))); return }
 println(json2.encode(json2.Any({'value':result})))
}
