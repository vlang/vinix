// SPDX-License-Identifier: GPL-2.0-or-later
// Isolate account providers so a focused check does not compile all Android tools.
module main

import crypto.sha256
import json2
import os

fn digest(path string) !string {
 mut file := os.open(path)!
 defer { file.close() }
 mut sum := sha256.new()
 mut bytes := []u8{len: 1024 * 1024}
 for {
  count := file.read(mut bytes) or { if err is os.Eof { break }; return err }
  if count == 0 { break }
  sum.write(bytes[..count])!
 }
 return sum.sum([]u8{}).hex()
}

fn helper(source string, signature string) !string {
 marker := '\n' + signature
 if source.count(marker) != 1 { return error('unique helper required: ' + signature) }
 start := (source.index(marker) or { return error('missing helper') }) + 1
 tail := source[start..]
 end := tail.index('\n}') or { return error('unterminated helper') }
 return tail[..end + 2] + '\n'
}

fn main() {
 assert os.args.len == 6, 'usage: source-check V ROOT FRESH_OUTPUT TOOLS JAVA'
 compiler, repo := os.real_path(os.args[1]), os.real_path(os.args[2])
 work := os.abs_path(os.args[3])
 tools, java := os.real_path(os.args[4]), os.real_path(os.args[5])
 assert !os.exists(work) && !os.is_link(work), 'output must be fresh'
 os.mkdir_all(work + '/androidtools')!
 os.mkdir(work + '/helper-inputs')!
 base := repo + '/tests/native-android-tools'
 mut pins := map[string]string{}
 for path in [compiler, java, @FILE] { pins[path] = digest(path)! }
 for name in ['framework_authenticator_base.v', 'framework_authenticator_request.v'] {
  path := base + '/androidtools/' + name
  pins[path] = digest(path)!
  os.cp(path, work + '/androidtools/' + name)!
  assert digest(work + '/androidtools/' + name)! == pins[path]!
 }
 checker := base + '/check-authenticator-base.v'
 pins[checker] = digest(checker)!
 os.cp(checker, work + '/check.v')!
 assert digest(work + '/check.v')! == pins[checker]!
 mut helpers := 'module androidtools\nimport os\n'
 for name, signature in {'framework.v': 'pub fn framework_replace_method(',
  'framework_classes.v': 'fn interface_class(', 'framework_accounts.v': 'pub fn framework_account_async_classes('} {
  path := base + '/androidtools/' + name
  pins[path] = digest(path)!
  os.cp(path, work + '/helper-inputs/' + name)!
  assert digest(work + '/helper-inputs/' + name)! == pins[path]!
  helpers += helper(os.read_file(work + '/helper-inputs/' + name)!, signature)!
 }
 helpers += '\npub fn framework_assemble(smali string, dex string, tools string, java string) ! {\n' +
  'if os.exists(dex) { os.rm(dex)! }\n' +
  'result := os.exec([java, "-cp", tools + "/*", "org.jf.smali.Main", "assemble", "--jobs", "2", smali, "-o", dex])\n' +
  'if result.exit_code != 0 || !os.is_file(dex) { return error(result.output) }\n}\n'
 os.write_file(work + '/androidtools/helpers.v', helpers)!
 for name in os.ls(tools)! {
  if name.ends_with('.jar') { pins[tools + '/' + name] = digest(tools + '/' + name)! }
 }
 compile := [compiler, '-nocache', '-cc', 'cc', '-o', work + '/check', work + '/check.v']
 built := os.exec(compile)
 os.write_file(work + '/compile.log', built.output)!
 assert built.exit_code == 0, built.output
 checked := os.exec([work + '/check', tools, java, work + '/assembled'])
 os.write_file(work + '/check.log', checked.output)!
 assert checked.exit_code == 0, checked.output
 for path, pin in pins { assert digest(path)! == pin, 'input changed: ' + path }
 pins[work + '/check'] = digest(work + '/check')!
 pins[work + '/assembled/classes.dex'] = digest(work + '/assembled/classes.dex')!
 os.write_file(work + '/receipt.json', json2.encode(pins, prettify: true) + '\n')!
 print(checked.output)
}
