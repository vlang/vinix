// SPDX-License-Identifier: GPL-2.0-or-later
// Discover the emitted producer's actual C inputs and recheck captured copies.
module main

import crypto.sha256
import json2
import os

const max_files = 20000
const max_text = 8 * 1024 * 1024

fn absolute(path string) ! {
 if !os.is_abs_path(path) || path.len > 4096 || path.contains_any('\x00\r\n') {
  return error('bounded absolute input path required')
 }
}

fn directory(path string) ! {
 absolute(path)!
 if os.real_path(path) != path || os.lstat(path)!.get_filetype() != .directory {
  return error('canonical existing directory required')
 }
}

fn regular(path string) ! {
 info := os.lstat(path)!
 if info.get_filetype() != .regular || info.size > u64(8) * 1024 * 1024 * 1024 {
  return error('bounded regular file required: ' + path)
 }
}

fn digest(path string) !string {
 regular(path)!
 mut file := os.open(path)!
 defer { file.close() }
 mut sum := sha256.new()
 mut buffer := []u8{len: 1024 * 1024}
 for {
  n := file.read(mut buffer) or { if err is os.Eof { break }; return err }
  if n == 0 { break }
  if sum.write(buffer[..n])! != n { return error('SHA256 short write') }
 }
 return sum.sum([]u8{}).hex()
}

fn add(path string, mut selected map[string]bool) ! {
 absolute(path)!
 regular(os.real_path(path))!
 selected[path] = true
 if selected.len > max_files { return error('bounded input count required') }
}

fn dependency_argv(project string, text string) ![]string {
 if text.len > 65536 || text.trim_space().contains_any("'\"`\\\n\r;$|&<>(){}*?[]~#") {
  return error('literal unquoted emitted command required')
 }
 tokens := text.fields()
 if tokens.len < 10 || tokens.len > 2048 || tokens[0] != 'cc' {
  return error('expected emitted cc command')
 }
 mut result := ['/usr/bin/cc', '-M']
 mut outputs := 0
 mut index := 1
 for index < tokens.len {
  token := tokens[index]
  if token == '-o' {
   if index + 1 >= tokens.len { return error('truncated output selector') }
   output := tokens[index + 1]
   absolute(output)!
   if os.norm_path(output) != output || os.dir(output) != project || output.ends_with('.c') {
    return error('one absolute project executable output required')
   }
   outputs++
   index += 2
   continue
  }
  if token.starts_with('-o') { return error('split emitted output selector required') }
  result << token
  index++
 }
 if outputs != 1 { return error('exactly one output selector required') }
 return result
}

fn discover(project string, root string) ! {
 directory(project)!
 absolute(root)!
 directory(os.dir(root))!
 if os.exists(root) || os.is_link(root) { return error('fresh discovery output required') }
 emitted := project + '/build_command.txt'
 regular(emitted)!
 if os.file_size(emitted) > 65536 { return error('bounded emitted command required') }
 argv := dependency_argv(project, os.read_file(emitted)!)!
 os.mkdir(root, mode: 0o700)!
 result := os.exec(argv)
 os.write_file(root + '/c-inputs.raw', result.output)!
 os.write_file(root + '/c-inputs.json', json2.encode({'argv': json2.Any(argv), 'exit_code': json2.Any(result.exit_code)}, prettify: true) + '\n')!
 if result.exit_code != 0 || result.output.len > max_text { return error('bounded C dependency discovery failed') }
 mut selected := map[string]bool{}
 for token in argv {
  if token.starts_with('/') && os.is_file(token) { add(token, mut selected)! }
 }
 mut common_crypto := false
 for token in result.output.replace('\\\n', ' ').fields() {
  if token.starts_with('/') && !token.ends_with(':') {
   add(token, mut selected)!
   if token.ends_with('/CommonCrypto/CommonDigest.h') { common_crypto = true }
  }
 }
 if !common_crypto { return error('actual CommonCrypto/CommonDigest.h dependency required') }
 // V's single-C project is flat. Refuse an unexpected directory or inode.
 for name in os.ls(project)! {
  path := project + '/' + name
  regular(path)!
  add(path, mut selected)!
 }
 for path in [os.real_path(os.executable()), os.abs_path(@FILE)] { add(path, mut selected)! }
 os.write_file(root + '/c-inputs.txt', selected.keys().sorted().join('\n') + '\n')!
 println('SDK-PRODUCER-INPUTS DISCOVER PASS files=' + selected.len.str() + ' actual-CommonCrypto')
}

fn manifest(path string) !string {
 regular(path)!
 if os.file_size(path) > max_text { return error('bounded capture manifest required') }
 return os.read_file(path)
}

fn check_capture(root string) ! {
 directory(root)!
 inputs_path, resolved_path := root + '/inputs.json', root + '/resolved.json'
 inputs_text, resolved_text := manifest(inputs_path)!, manifest(resolved_path)!
 before_inputs := sha256.sum(inputs_text.bytes()).hex()
 before_resolved := sha256.sum(resolved_text.bytes()).hex()
 pins := json2.decode[map[string]string](inputs_text)!
 resolved := json2.decode[map[string]string](resolved_text)!
 if pins.len == 0 || pins.len > max_files || pins.keys().sorted() != resolved.keys().sorted() {
  return error('complete bounded capture/resolution membership required')
 }
 for path, pin in pins {
  absolute(path)!
  actual := resolved[path]!
  absolute(actual)!
  copy := root + '/files/' + path.trim_left('/')
  if pin.len != 64 || !pin.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
   || os.norm_path(copy) != copy || os.real_path(copy) != copy
   || os.real_path(actual) != actual || os.real_path(path) != actual {
   return error('captured pin, copy path or original resolution differs: ' + path)
  }
  if digest(actual)! != pin || digest(copy)! != pin
   || digest(actual)! != pin || os.real_path(path) != actual {
   return error('captured original/copy bytes changed: ' + path)
  }
 }
 if digest(inputs_path)! != before_inputs || digest(resolved_path)! != before_resolved {
  return error('capture manifests changed while checking')
 }
 println('SDK-PRODUCER-INPUTS CAPTURE PASS files=' + pins.len.str()
  + ' inputs_sha256=' + before_inputs + ' resolved_sha256=' + before_resolved + ' original-copy-resolution-rechecked')
}

fn self_test() ! {
 good := 'cc -std=gnu11 -o /project/producer -x objective-c /project/producer.c -x none -I /include -lm'
 if dependency_argv('/project', good)! != ['/usr/bin/cc', '-M', '-std=gnu11', '-x', 'objective-c', '/project/producer.c', '-x', 'none', '-I', '/include', '-lm'] {
  return error('emitted arguments changed beyond compiler/-M/output selector')
 }
 mut refused := 0
 for bad in [good.replace('cc ', 'clang '), good.replace('-o /project/producer ', ''),
  good + ' -o /project/second', good.all_before(' -o') + ' -o',
  good.replace('-o /project/producer', '-o relative'), good.replace('-o /project/producer', '-o -x'),
  good.replace('-o /project/producer', '-o /outside/producer'), good.replace('-o /project/producer', '-o /project/producer.c'),
  good.replace('-o /project/producer', '-o/project/producer'), good + '; true', good + ' $(command)',
  good + ' | other', good + ' > output', good + ' "quoted"', good + '\nsecond', good + ' \\escaped'] {
  dependency_argv('/project', bad) or { refused++; continue }
  return error('malformed emitted command accepted')
 }
 println('SDK-PRODUCER-INPUTS SELFTEST PASS refusals=' + refused.str() + ' exact-emitted-argv')
}

fn main() {
 if os.args.len == 2 && os.args[1] == '--self-test' { self_test() or { eprintln(err); exit(1) }; return }
 if os.args.len == 4 && os.args[1] == 'discover' { discover(os.args[2], os.args[3]) or { eprintln(err); exit(1) }; return }
 if os.args.len == 3 && os.args[1] == 'check-capture' { check_capture(os.args[2]) or { eprintln(err); exit(1) }; return }
 eprintln('usage: sdk-producer-inputs discover PROJECT FRESH_OUTPUT | check-capture CAPTURE_ROOT | --self-test')
 exit(2)
}
