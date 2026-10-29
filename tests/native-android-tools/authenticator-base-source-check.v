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

fn retain(source string, target string, mut pins map[string]string) ! {
 assert os.is_file(source), 'missing input: ' + source
 pins[source] = digest(source)!
 os.mkdir_all(os.dir(target))!
 os.cp(source, target)!
 assert digest(target)! == pins[source]!, 'copy differs: ' + target
 pins[target] = pins[source]!
}

// Preserve production cancellation, capture, status and stale-DEX handling.
fn broker_helpers(repo string, base string, work string, mut pins map[string]string) !string {
 mut source := 'module androidtools\nimport os\nimport cachecli\nimport sourcecommand\n'
 for name, signature in {'framework.v': 'pub fn framework_assemble(', 'generation.v': 'pub fn checked('} {
  path := base + '/androidtools/' + name
  copy := work + '/helper-inputs/' + name
  retain(path, copy, mut pins)!
  source += helper(os.read_file(copy)!, signature)!
 }
 retain(repo + '/build-support/cachecli/guard.v', work + '/cachecli/guard.v', mut pins)!
 mut names := os.ls(repo + '/tools/sourcecommand')!
 names.sort()
 assert 'core.v' in names && 'abi.h' in names, 'sourcecommand closure missing'
 for name in names {
  if (name.ends_with('.v') && !name.ends_with('_test.v')) || name.ends_with('.h') {
   retain(repo + '/tools/sourcecommand/' + name, work + '/sourcecommand/' + name, mut pins)!
  }
 }
 return source
}

fn main() {
 broker := os.args.len > 1 && os.args[1] == '--broker-context'
 assert (broker && os.args.len == 7) || (!broker && os.args.len == 6),
  'usage: source-check [--broker-context] V ROOT FRESH_OUTPUT TOOLS JAVA'
 offset := if broker { 1 } else { 0 }
 compiler, repo := os.real_path(os.args[1 + offset]), os.real_path(os.args[2 + offset])
 requested_work := os.abs_path(os.args[3 + offset])
 work := if broker { os.real_path(os.dir(requested_work)) + '/' + os.file_name(requested_work) } else { requested_work }
 tools, java := os.real_path(os.args[4 + offset]), os.real_path(os.args[5 + offset])
 if broker {
  assert os.is_dir(os.dir(requested_work)), 'output parent must exist'
  assert work != repo && !work.starts_with(repo + '/'), 'broker evidence must be external'
  $if prod { panic('broker source checker requires live assertions; compile without -prod') }
 }
 assert !os.exists(work) && !os.is_link(work), 'output must be fresh'
 os.mkdir_all(work + '/androidtools')!
 os.mkdir(work + '/helper-inputs')!
 base := repo + '/tests/native-android-tools'
 mut pins := map[string]string{}
 for path in [compiler, java, os.real_path(@FILE)] { pins[path] = digest(path)! }
 providers := if broker { ['framework_account_broker_context.v'] } else { ['framework_authenticator_base.v', 'framework_authenticator_request.v'] }
 for name in providers {
  path := base + '/androidtools/' + name
  retain(path, work + '/androidtools/' + name, mut pins)!
 }
 checker := base + if broker { '/check-account-broker-context.v' } else { '/check-authenticator-base.v' }
 retain(checker, work + '/check.v', mut pins)!
 mut helpers := 'module androidtools\nimport os\n'
 if broker {
  helpers = broker_helpers(repo, base, work, mut pins)!
 } else {
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
 }
 os.write_file(work + '/androidtools/helpers.v', helpers)!
 if broker { pins[work + '/androidtools/helpers.v'] = digest(work + '/androidtools/helpers.v')! }
 for name in os.ls(tools)! {
  if name.ends_with('.jar') { pins[tools + '/' + name] = digest(tools + '/' + name)! }
 }
 mut compile := [compiler, '-nocache', '-cc', 'cc']
 if broker {
  compile << ['-enable-globals', '-path', '@vlib|' + work]
  mut discovery_argv := compile.clone()
  discovery_argv << ['-print-v-files', work + '/check.v']
  discovery := os.exec(discovery_argv)
  os.write_file(work + '/compiler-listing.log', discovery.output)!
  os.write_file(work + '/compiler-listing.json', json2.encode({'argv': discovery_argv.str(), 'status': discovery.exit_code.str()}, prettify: true) + '\n')!
  assert discovery.exit_code == 0, discovery.output
  vlib := os.dir(compiler) + '/vlib/'
  mut saw_checker := false
  for line in discovery.output.split_into_lines() {
   if !line.ends_with('.v') { continue }
   path := os.real_path(line)
   if path == work + '/check.v' { saw_checker = true }
   if path.starts_with(work + '/') {
    assert path in pins, 'unretained isolated compiler input: ' + path
   } else {
    assert path.starts_with(vlib), 'unexpected compiler input: ' + path
    retain(path, work + '/compiler-inputs/vlib/' + path[vlib.len..], mut pins)!
   }
  }
  assert saw_checker, 'compiler discovery omitted checker'
  os.write_file(work + '/inputs-before.json', json2.encode(pins, prettify: true) + '\n')!
 }
 compile << ['-o', work + '/check', work + '/check.v']
 built := os.exec(compile)
 os.write_file(work + '/compile.log', built.output)!
 if broker { os.write_file(work + '/compile.json', json2.encode({'argv': compile.str(), 'status': built.exit_code.str()}, prettify: true) + '\n')! }
 assert built.exit_code == 0, built.output
 checked := os.exec([work + '/check', tools, java, work + '/assembled'])
 os.write_file(work + '/check.log', checked.output)!
 if broker { os.write_file(work + '/check.json', json2.encode({'argv': [work + '/check', tools, java, work + '/assembled'].str(), 'status': checked.exit_code.str()}, prettify: true) + '\n')! }
 assert checked.exit_code == 0, checked.output
 for path, pin in pins { assert digest(path)! == pin, 'input changed: ' + path }
 pins[work + '/check'] = digest(work + '/check')!
 pins[work + '/assembled/classes.dex'] = digest(work + '/assembled/classes.dex')!
 os.write_file(work + '/receipt.json', json2.encode(pins, prettify: true) + '\n')!
 print(checked.output)
}
