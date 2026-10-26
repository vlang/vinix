// SPDX-License-Identifier: GPL-2.0-or-later
// Account Parcelable plus request ABI only, over the sealed 2090-class Activity
// framework. Canonical input comes from the pinned JAR, never a parallel tree.
module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android/'
const compiler = '/Users/alex/code/v/v'
const java = '/opt/homebrew/opt/openjdk@25/bin/java'
const tools = repo + '/build/android-framework/tools'
const source_file = repo + '/tests/native-android-ws/authenticator-request-build.v'
const providers = ['framework_account_parcel.v', 'framework_authenticator_request.v']
const additions = ['android/accounts/Account$Creator.smali',
 'android/accounts/IAccountAuthenticator.smali', 'android/accounts/IAccountAuthenticator$Stub.smali',
 'android/accounts/IAccountAuthenticator$Stub$Proxy.smali']
const changed = 'android/accounts/Account.smali'

fn digest(path string) !string {
 if os.lstat(path)!.get_filetype() != .regular { return error('regular input required: ' + path) }
 mut file := os.open(path)!
 defer { file.close() }
 mut sum := sha256.new()
 mut bytes := []u8{len: 1024 * 1024}
 for {
  n := file.read(mut bytes) or { if err is os.Eof { break }; return err }
  if n == 0 { break }
  sum.write(bytes[..n])!
 }
 return sum.sum([]u8{}).hex()
}

fn write_json[T](path string, value T) ! {
 os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn command(root string, label string, argv []string) !string {
 executable := if argv[0].contains('/') { os.real_path(argv[0]) } else { os.find_abs_path_of_executable(argv[0])! }
 pin := digest(executable)!
 started := time.utc().str()
 r := os.exec(argv)
 os.write_file(root + '/commands/' + label + '.log', r.output)!
 write_json(root + '/commands/' + label + '.json', {
  'argv': json2.Any(argv), 'started_utc': json2.Any(started),
  'completed_utc': json2.Any(time.utc().str()), 'exit_code': json2.Any(r.exit_code),
  'executable': json2.Any(executable), 'executable_sha256': json2.Any(pin)
 })!
 if r.exit_code != 0 { return error(label + ': ' + r.output) }
 if digest(executable)! != pin { return error('executable changed: ' + executable) }
 return r.output
}

fn inventory(root string, prefix string, mut pins map[string]string) ! {
 mut names := os.ls(root + '/' + prefix)!
 names.sort()
 for name in names {
  key := if prefix == '' { name } else { prefix + '/' + name }
  match os.lstat(root + '/' + key)!.get_filetype() {
   .directory { inventory(root, key, mut pins)! }
   .regular { pins[key] = digest(root + '/' + key)! }
   else { return error('nonregular build entry: ' + key) }
  }
 }
}

fn class_delta(old map[string]string, new map[string]string) ! {
 if old.len != 2090 || new.len != old.len + additions.len || changed !in old || changed !in new {
  return error('unexpected framework class set')
 }
 for name in additions {
  if name in old || name !in new { return error('unexpected added class: ' + name) }
 }
 for name, pin in old {
  if name !in new || ((name == changed) == (pin == new[name]!)) {
   return error('unexpected existing class delta: ' + name)
  }
 }
}

fn jar_delta(old map[string]string, new map[string]string) ! {
 if old.len != 3 || new.len != old.len || 'classes.dex' !in old { return error('unexpected JAR members') }
 for name, pin in old {
  if name !in new || ((name == 'classes.dex') == (pin == new[name]!)) {
   return error('unexpected JAR member delta: ' + name)
  }
 }
}

fn self_test() ! {
 mut old := {changed: 'old'}
 for i in 0 .. 2089 { old['other/' + i.str() + '.smali'] = 'old' }
 mut good := old.clone()
 good[changed] = 'new'
 for name in additions { good[name] = 'new' }
 class_delta(old, good)!
 for case in 0 .. 8 {
  mut before := old.clone()
  mut bad := good.clone()
  match case {
   0 { bad['other/0.smali'] = 'changed' }
   1 { bad.delete('other/0.smali') }
   2 { bad['surprise.smali'] = 'new' }
   3 { bad[changed] = 'old' }
   4 { bad.delete(additions[0]) }
   5 { bad.delete(additions[0]); bad['surprise.smali'] = 'new' }
   6 { before.delete(changed); before['surprise.smali'] = 'old' }
   else { before.delete('other/0.smali'); before[additions[0]] = 'old' }
  }
  class_delta(before, bad) or { continue }
  return error('invalid class delta accepted: ' + case.str())
 }
 jar_old := {'classes.dex': 'old', 'manifest': 'same', 'resources': 'same'}
 jar_good := {'classes.dex': 'new', 'manifest': 'same', 'resources': 'same'}
 jar_delta(jar_old, jar_good)!
 for case in 0 .. 4 {
  mut bad := jar_good.clone()
  match case {
   0 { bad['classes.dex'] = 'old' }
   1 { bad['manifest'] = 'changed' }
   2 { bad.delete('manifest') }
   else { bad['extra'] = 'new' }
  }
  jar_delta(jar_old, bad) or { continue }
  return error('invalid JAR delta accepted: ' + case.str())
 }
 println('AUTHENTICATOR-REQUEST-BUILD-SELF-TEST-PASS eight invalid class deltas and four invalid JAR deltas rejected')
}

fn freeze_closure(root string, listing string, destination string) !map[string]string {
 mut pins := map[string]string{}
 for path in listing.split_into_lines().filter(it.ends_with('.v')) {
  pins[path] = digest(path)!
  target := root + '/' + destination + '/' + path.trim_left('/')
  os.mkdir_all(os.dir(target))!
  os.cp(path, target)!
  if digest(target)! != pins[path]! { return error('closure copy differs: ' + path) }
 }
 if pins.len == 0 { return error('empty V source closure') }
 write_json(root + '/' + destination + '.json', pins)!
 return pins
}

fn valid_pin(pin string) bool {
 return pin.len == 64 && pin.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
}

fn build(baseline string, manifest_pin string, jar_pin string, root string) ! {
 if !valid_pin(manifest_pin) || !valid_pin(jar_pin) { return error('SHA256 pins required') }
 if !baseline.starts_with(state + 'account-contract-') || os.real_path(baseline) != baseline
  || !root.starts_with(state + 'account-contract-') || os.real_path(os.dir(root)) != os.dir(root)
  || os.exists(root) || os.is_link(root) || root.contains_any(' \n\t') {
  return error('canonical baseline and fresh external account-contract output required')
 }
 if digest(baseline + '/sha256.json')! != manifest_pin || digest(baseline + '/api-impl.jar')! != jar_pin {
  return error('sealed framework baseline differs')
 }
 os.mkdir_all(root + '/commands')!
 os.mkdir_all(root + '/provider-source/androidtools')!
 os.mkdir_all(root + '/smali-tools')!
 mut inputs := map[string]string{}
 for path in [source_file, compiler, os.real_path(java), os.executable(),
  baseline + '/api-impl.jar', baseline + '/build.json', baseline + '/sha256.json'] {
  inputs[path] = digest(path)!
 }
 command(root, 'check-baseline', [repo + '/build/android-maps/account-contract-retain', 'check', baseline, manifest_pin])!
 os.cp(source_file, root + '/builder-source.v')!
 os.cp(os.executable(), root + '/builder')!
 os.cp(baseline + '/sha256.json', root + '/baseline-sha256.json')!
 os.cp(baseline + '/build.json', root + '/baseline-build.json')!
 mut jars := os.ls(tools)!.filter(it.ends_with('.jar'))
 jars.sort()
 if jars.len == 0 { return error('no smali tool JARs') }
 mut classpath := []string{}
 for name in jars {
  path := tools + '/' + name
  inputs[path] = digest(path)!
  target := root + '/smali-tools/' + name
  os.cp(path, target)!
  if digest(target)! != inputs[path]! { return error('smali tool copy differs') }
  classpath << target
 }
 for name in providers {
  path := repo + '/tests/native-android-tools/androidtools/' + name
  inputs[path] = digest(path)!
  os.cp(path, root + '/provider-source/androidtools/' + name)!
 }
 os.write_file(root + '/provider-source/main.v', 'module main\nimport androidtools\nimport os\nfn main() {\nr := os.args[1]\n' +
  'account := r + "/android/accounts/Account.smali"\ncreator := r + "/android/accounts/Account$Creator.smali"\n' +
  'if os.exists(creator) { panic("Account creator already exists") }\n' +
  'text := androidtools.framework_account_parcel_source(os.read_file(account)!)!\n' +
  'classes := androidtools.framework_authenticator_request_classes()\n' +
  'for name,_ in classes { if os.exists(r + "/" + name + ".smali") { panic("request class already exists") } }\n' +
  'os.write_file(account,text)!\nos.write_file(creator,androidtools.framework_account_parcel_creator_source())!\n' +
  'for name,source in classes { os.write_file(r + "/" + name + ".smali",source)! }\n}\n')!
 os.setenv('VROOT', '/Users/alex/code/v', true)
 os.setenv('V', compiler, true)
 os.setenv('VINIX_V_COMPILER', compiler, true)
 command(root, 'java-version', [java, '--version'])!
 command(root, 'v-version', [compiler, 'version'])!
 driver_closure := freeze_closure(root, command(root, 'builder-closure', [compiler, '-print-v-files', source_file])!, 'builder-closure-inputs')!
 command(root, 'old-disassemble', [java, '-cp', classpath.join(':'), 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', baseline + '/api-impl.jar', '-o', root + '/old-dex'])!
 command(root, 'clone-canonical-smali', ['/bin/cp', '-c', '-R', root + '/old-dex', root + '/smali'])!
 os.cp(baseline + '/api-impl.jar', root + '/api-impl.jar')!
 mut old := map[string]string{}
 inventory(root + '/old-dex', '', mut old)!
 provider_closure := freeze_closure(root, command(root, 'provider-closure', [compiler, '-print-v-files', '-path', root + '/provider-source|@vlib', root + '/provider-source'])!, 'provider-closure-inputs')!
 command(root, 'compile-provider', [compiler, '-cc', 'cc', '-path', root + '/provider-source|@vlib', '-o', root + '/provider', root + '/provider-source'])!
 for path, pin in provider_closure { if digest(path)! != pin { return error('provider input changed: ' + path) } }
 command(root, 'apply-provider', [root + '/provider', root + '/smali'])!
 mut applied := map[string]string{}
 inventory(root + '/smali', '', mut applied)!
 class_delta(old, applied)!
 command(root, 'assemble', [java, '-cp', classpath.join(':'), 'org.jf.smali.Main', 'assemble', '--jobs', '2', root + '/smali', '-o', root + '/classes.dex'])!
 if !os.is_file(root + '/classes.dex') || os.file_size(root + '/classes.dex') < 112 { return error('assembly produced no fresh DEX') }
 command(root, 'replace-dex', ['/usr/bin/zip', '-q', '-j', root + '/api-impl.jar', root + '/classes.dex'])!
 command(root, 'new-disassemble', [java, '-cp', classpath.join(':'), 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', root + '/api-impl.jar', '-o', root + '/new-dex'])!
 mut new := map[string]string{}
 inventory(root + '/new-dex', '', mut new)!
 class_delta(old, new)!
 write_json(root + '/framework-dex-before.json', old)!
 write_json(root + '/framework-dex-after.json', new)!
 for pair in [[baseline + '/api-impl.jar', 'old'], [root + '/api-impl.jar', 'new']] {
  command(root, pair[1] + '-unzip', ['/usr/bin/unzip', '-q', pair[0], '-d', root + '/' + pair[1] + '-jar'])!
 }
 mut old_jar := map[string]string{}
 mut new_jar := map[string]string{}
 inventory(root + '/old-jar', '', mut old_jar)!
 inventory(root + '/new-jar', '', mut new_jar)!
 jar_delta(old_jar, new_jar)!
 for path, pin in driver_closure { if digest(path)! != pin { return error('builder source changed: ' + path) } }
 for path, pin in inputs { if digest(path)! != pin { return error('input changed: ' + path) } }
 write_json(root + '/build.json', {
  'scope': json2.Any('Account Parcelable and authenticator request Binder ABI only; no broker, account storage, tokens or Google login claim'),
  'source_revision': json2.Any(command(root, 'revision', ['/usr/bin/git', '-C', repo, 'rev-parse', 'HEAD'])!.trim_space()),
  'input_sha256': json2.decode[json2.Any](json2.encode(inputs))!,
  'baseline_path': json2.Any(baseline), 'baseline_manifest_sha256': json2.Any(manifest_pin),
  'baseline_api_impl_sha256': json2.Any(jar_pin), 'api_impl_sha256': json2.Any(digest(root + '/api-impl.jar')!),
  'classes_dex_sha256': json2.Any(digest(root + '/classes.dex')!),
  'changed_classes': json2.Any([changed]), 'added_classes': json2.Any(additions), 'class_count': json2.Any(new.len),
  'environmental_inputs': json2.Any('Host SDK and dynamic libraries are environmental dependencies; V source closures and smali tool JARs retained and checked')
 })!
 mut pins := map[string]string{}
 inventory(root, '', mut pins)!
 write_json(root + '/sha256.json', pins)!
 println('AUTHENTICATOR-REQUEST-BUILD-PASS classes=' + new.len.str() + ' jar=' + root + '/api-impl.jar')
 println('AUTHENTICATOR-REQUEST-BUILD-MANIFEST-SHA256 ' + digest(root + '/sha256.json')!)
}

fn main() {
 if os.args.len == 2 && os.args[1] == '--self-test' { self_test() or { eprintln(err); exit(1) }; return }
 if os.args.len != 5 { eprintln('usage: authenticator-request-build BASELINE BASELINE_MANIFEST_SHA256 BASELINE_JAR_SHA256 FRESH_OUTPUT | --self-test'); exit(2) }
 build(os.abs_path(os.args[1]), os.args[2], os.args[3], os.abs_path(os.args[4])) or { eprintln(err); exit(1) }
}
