// SPDX-License-Identifier: GPL-2.0-or-later
// Ordinary explicit Service access only, over the sealed 2098-class framework.
// Canonical input comes from the pinned JAR, never a parallel smali tree.
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
const source_file = repo + '/tests/native-android-ws/service-access-build.v'
const provider = repo + '/tests/native-android-tools/androidtools/framework_service_access.v'
const companion_helpers = repo + '/tests/native-android-tools/androidtools/framework_companion_activity.v'
const replace_helper = repo + '/tests/native-android-tools/androidtools/framework.v'
const changed_class = 'android/app/ContextImpl.smali'
const class_count = 2098
const retain = repo + '/build/android-maps/account-contract-retain'
const native_reference = state + 'account-contract-companion-build-2026-10-26'
const native_manifest_pin = '0ee86be7fd8168eb5dd14d8e6672fb9d54424a7da449dd91945140b75ca736ae'
const native_pin = 'aa460c06686e2d1f60ea6dd27ab8f158a3b9794440499c6cdc5e7840cafda0cb'

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
 if old.len != class_count || new.len != old.len || changed_class !in old {
  return error('unexpected framework class set')
 }
 for name, pin in old {
  if name !in new || ((name == changed_class) == (pin == new[name]!)) {
   return error('unexpected framework class delta: ' + name)
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
 mut old := map[string]string{}
 for i in 0 .. class_count - 1 { old['other/' + i.str() + '.smali'] = 'old' }
 old[changed_class] = 'old'
 mut good := old.clone()
 good[changed_class] = 'new'
 class_delta(old, good)!
 for case in 0 .. 8 {
  mut before := old.clone()
  mut bad := good.clone()
  match case {
   0 { bad['other/0.smali'] = 'changed' }
   1 { bad.delete('other/0.smali') }
   2 { bad['surprise.smali'] = 'new' }
   3 { before.delete('other/0.smali'); bad.delete('other/0.smali') }
   4 { bad[changed_class] = 'old' }
   5 { bad.delete(changed_class); bad['surprise.smali'] = 'new' }
   6 { before['surprise.smali'] = 'old'; bad['surprise.smali'] = 'old' }
   else { before.delete(changed_class); before['surprise.smali'] = 'old' }
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
 println('SERVICE-ACCESS-BUILD-SELF-TEST-PASS eight invalid class deltas and four invalid JAR deltas rejected')
}

fn function_source(source string, signature string) !string {
 anchor := '\n' + signature
 if source.count(anchor) != 1 { return error('unexpected helper declaration: ' + signature) }
 body := source.all_after(anchor)
 end := body.index('\n}') or { return error('unterminated helper: ' + signature) }
 return signature + body[..end + '\n}'.len] + '\n'
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

fn driver_source() string {
 return 'module main
import androidtools
import os
fn method(source string, signature string) string {
 mut found := ""
 for block in source.split(".method ")[1..] {
  if !block.all_before("\\n").ends_with(" " + signature) { continue }
  assert found == "", "duplicate method " + signature
  found = ".method " + block.all_before(".end method") + ".end method"
 }
 assert found != "", "missing method " + signature
 return found
}
fn at(source string, needle string) int {
 return source.index(needle) or { panic("missing instruction " + needle) }
}
fn reject(source string, label string) {
 if _ := androidtools.framework_service_access_sources(source) {
  panic("accepted malformed service source: " + label)
 }
}
fn guards(source string, manager string) ! {
 patched := androidtools.framework_service_access_sources(source)!
 assert patched != source
 helper := method(patched, "vinixGetServiceTarget(Landroid/content/Intent;)Landroid/atl/ATLLoadedApp;")
 for needle in ["Landroid/content/pm/ApplicationInfo;->enabled:Z",
  "Landroid/content/pm/ComponentInfo;->enabled:Z", "Landroid/content/pm/ComponentInfo;->exported:Z",
  "Landroid/content/pm/ServiceInfo;->permission:Ljava/lang/String;"] {
  assert at(helper, needle) < at(helper, "\\n:allowed\\n")
 }
 assert helper.contains("new-instance v0, Ljava/lang/SecurityException;")
 assert !helper.contains("->requestedPermissions:")
 assert !helper.contains("->startOrBindService(") && !helper.contains("->vinixEnsureApplicationStarted(")
 lookup := method(manager, "vinixGetActivityApplication(Landroid/atl/ATLLoadedApp;Ljava/lang/String;)Landroid/atl/ATLLoadedApp;")
 assert at(lookup, "->vinixActivityPackageVisible(") < at(lookup, "->peekAppFromPackageName(")
 bind_sig := "bindService(Landroid/content/Intent;Landroid/content/ServiceConnection;I)Z"
 start_sig := "startService(Landroid/content/Intent;)Landroid/content/ComponentName;"
 bind := method(patched, bind_sig)
 assert at(bind, "->vinixGetServiceTarget(") < at(bind, "->register(")
 branch := bind.all_after("->vinixGetServiceTarget(").all_after("if-eqz v0, ").all_before("\\n").trim_space()
 assert branch.starts_with(":")
 assert at(bind, "if-eqz v0, " + branch) < at(bind, "->register(")
 missing_body := bind.all_after("\\n    " + branch + "\\n").trim_space()
 assert missing_body.starts_with("const/4 v0, 0") && missing_body.contains("return v0")
 start := method(patched, start_sig)
 legacy := "    :vinix_explicit_service_legacy\\n"
 assert start.all_after(legacy) == method(source, start_sig).all_after("    .registers 6\\n")
 reject(source.replace(".class public final Landroid/app/ContextImpl;", ".class public Landroid/app/Wrong;"), "class")
 reject(source.replace(".super Landroid/content/Context;", ".super Ljava/lang/Object;"), "superclass")
 reject(source + "\\n.class public Landroid/app/Extra;\\n", "duplicate class")
 owner := ".field private final atl_loaded_app:Landroid/atl/ATLLoadedApp;"
 reject(source.replace(owner, ""), "missing owner")
 reject(source + "\\n" + owner + "\\n", "duplicate owner")
 for signature in [bind_sig, start_sig, "atl_get_intent_target(Landroid/content/Intent;)Landroid/atl/ATLLoadedApp;"] {
  reject(source.replace(" " + signature + "\\n", " missing" + signature + "\\n"), "missing " + signature)
  reject(source + "\\n" + method(source, signature), "duplicate " + signature)
 }
 reject(source + "\\n.method public unfinished()V\\n", "unbalanced method")
 reject(source + "\\n.method public vinixGetServiceTarget()V\\n.locals 0\\nreturn-void\\n.end method\\n", "helper overload")
 reject(source.replace("Landroid/atl/VinixServiceBinding;->register(", "Landroid/atl/VinixServiceBinding;->wrong("), "bind anchor")
 reject(source.replace("if-eqz v0, " + branch, "if-nez v0, " + branch), "bind missing branch")
 original_bind := method(source, bind_sig)
 reject(source.replace(original_bind, original_bind.replace("\\n    " + branch + "\\n", "\\n    :lost_service_false\\n")), "missing false label")
 reject(source.replace(original_bind, original_bind.replace(missing_body.all_before("\\n"), "const/4 v0, 0x1")), "changed false return")
 reject(source.replace("->nativeStartExternalService(", "->wrongExternalService("), "start anchor")
 reject(source.replace(method(source, start_sig), method(source, start_sig).replace("    .registers 6\\n", "    .registers 7\\n")), "register drift")
 reject(patched, "reapplication")
 println("SERVICE-ACCESS-PROVIDER-GUARDS-PASS manifest/access checks, visibility before cached app lookup, registration ordering, unchanged implicit start, malformed/reapplied rejection")
}
fn main() {
 assert os.args.len == 3
 assert androidtools.framework_service_access_class_names() == ["android/app/ContextImpl"]
 path := os.args[2] + "/android/app/ContextImpl.smali"
 source := os.read_file(path)!
 match os.args[1] {
  "guards" { guards(source, os.read_file(os.args[2] + "/android/atl/ATLLoadedAppManager.smali")!)! }
  "apply" { os.write_file(path, androidtools.framework_service_access_sources(source)!)! }
  "reject-reapply" { reject(source, "applied ContextImpl"); println("SERVICE-ACCESS-PROVIDER-REAPPLY-REJECT-PASS") }
  else { panic("unexpected provider command") }
 }
}
'
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
 if digest(native_reference + '/sha256.json')! != native_manifest_pin
  || digest(native_reference + '/native/libvinix-android-native.so')! != native_pin {
  return error('sealed companion native reference differs')
 }
 os.mkdir_all(root + '/commands')!
 os.mkdir_all(root + '/provider-source/androidtools')!
 os.mkdir_all(root + '/smali-tools')!
 mut inputs := map[string]string{}
 for path in [source_file, compiler, os.real_path(java), os.executable(), retain,
  baseline + '/api-impl.jar', baseline + '/build.json', baseline + '/sha256.json',
  native_reference + '/build.json', native_reference + '/sha256.json',
  native_reference + '/native/libvinix-android-native.so', provider, companion_helpers,
  replace_helper] {
  inputs[path] = digest(path)!
 }
 command(root, 'check-baseline', [retain, 'check', baseline, manifest_pin])!
 command(root, 'check-native-reference', [retain, 'check', native_reference, native_manifest_pin])!
 os.cp(source_file, root + '/builder-source.v')!
 os.cp(os.executable(), root + '/builder')!
 command(root, 'self-test', [root + '/builder', '--self-test'])!
 os.cp(baseline + '/sha256.json', root + '/baseline-sha256.json')!
 os.cp(baseline + '/build.json', root + '/baseline-build.json')!
 os.cp(native_reference + '/sha256.json', root + '/native-reference-sha256.json')!
 os.cp(native_reference + '/build.json', root + '/native-reference-build.json')!
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
 os.cp(provider, root + '/provider-source/androidtools/framework_service_access.v')!
 os.cp(companion_helpers, root + '/companion-helper-source.v')!
 os.cp(replace_helper, root + '/framework-helper-source.v')!
 mut helpers := 'module androidtools\n'
 for signature in ['fn companion_activity_method(', 'fn companion_activity_original(',
  'fn companion_activity_validate_class('] {
  helpers += function_source(os.read_file(companion_helpers)!, signature)!
 }
 helpers += function_source(os.read_file(replace_helper)!, 'pub fn framework_replace_method(')!
 os.write_file(root + '/provider-source/androidtools/framework_methods.v', helpers)!
 os.write_file(root + '/provider-source/main.v', driver_source())!
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
 command(root, 'provider-guards', [root + '/provider', 'guards', root + '/old-dex'])!
 mut guarded := map[string]string{}
 inventory(root + '/old-dex', '', mut guarded)!
 if guarded != old { return error('source guards mutated canonical input') }
 command(root, 'apply-provider', [root + '/provider', 'apply', root + '/smali'])!
 mut applied := map[string]string{}
 inventory(root + '/smali', '', mut applied)!
 class_delta(old, applied)!
 command(root, 'reject-reapply', [root + '/provider', 'reject-reapply', root + '/smali'])!
 mut rejected := map[string]string{}
 inventory(root + '/smali', '', mut rejected)!
 if rejected != applied { return error('reapplication rejection mutated transformed input') }
 write_json(root + '/framework-source-before.json', old)!
 write_json(root + '/framework-source-after.json', applied)!
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
 write_json(root + '/framework-jar-before.json', old_jar)!
 write_json(root + '/framework-jar-after.json', new_jar)!
 command(root, 'check-baseline-after', [retain, 'check', baseline, manifest_pin])!
 command(root, 'check-native-reference-after', [retain, 'check', native_reference, native_manifest_pin])!
 for path, pin in driver_closure { if digest(path)! != pin { return error('builder source changed: ' + path) } }
 for path, pin in inputs { if digest(path)! != pin { return error('input changed: ' + path) } }
 write_json(root + '/build.json', {
  'scope': json2.Any('Ordinary explicit Service declaration/access checks only; Context loaded-app owner is the compatibility identity model; no broker, permission grant or Google login claim'),
  'source_revision': json2.Any(command(root, 'revision', ['/usr/bin/git', '-C', repo, 'rev-parse', 'HEAD'])!.trim_space()),
  'input_sha256': json2.decode[json2.Any](json2.encode(inputs))!,
  'baseline_path': json2.Any(baseline), 'baseline_manifest_sha256': json2.Any(manifest_pin),
  'baseline_api_impl_sha256': json2.Any(jar_pin), 'api_impl_sha256': json2.Any(digest(root + '/api-impl.jar')!),
  'classes_dex_sha256': json2.Any(digest(root + '/classes.dex')!),
  'changed_classes': json2.Any([changed_class]), 'added_classes': json2.Any([]string{}),
  'removed_classes': json2.Any([]string{}), 'class_count': json2.Any(new.len),
  'native_reference_path': json2.Any(native_reference),
  'native_reference_manifest_sha256': json2.Any(native_manifest_pin),
  'native_sha256': json2.Any(native_pin),
  'environmental_inputs': json2.Any('Host SDK and dynamic libraries are environmental dependencies; V source closures and smali tool JARs retained and checked')
 })!
 mut pins := map[string]string{}
 inventory(root, '', mut pins)!
 write_json(root + '/sha256.json', pins)!
 seal := digest(root + '/sha256.json')!
 // Readback receipts stay adjacent to the bundle so the sealed tree is immutable.
 readback_checker_pin := digest(retain)!
 if readback_checker_pin != inputs[retain]! { return error('readback checker changed before final verification') }
 readback := os.exec([retain, 'check', root, seal])
 write_json(root + '-readback.json', {
  'bundle': json2.Any(root), 'manifest_sha256': json2.Any(seal),
  'checker': json2.Any(retain), 'checker_sha256': json2.Any(readback_checker_pin),
  'checked_utc': json2.Any(time.utc().str()), 'exit_code': json2.Any(readback.exit_code),
  'output': json2.Any(readback.output)
 })!
 if readback.exit_code != 0 { return error('sealed output readback failed: ' + readback.output) }
 if digest(retain)! != readback_checker_pin { return error('readback checker changed during final verification') }
 if digest(root + '/sha256.json')! != seal { return error('output seal changed during readback') }
 println('SERVICE-ACCESS-BUILD-PASS classes=' + new.len.str() + ' jar=' + root + '/api-impl.jar')
 println('SERVICE-ACCESS-BUILD-MANIFEST-SHA256 ' + seal)
}

fn main() {
 if os.args.len == 2 && os.args[1] == '--self-test' { self_test() or { eprintln(err); exit(1) }; return }
 if os.args.len != 5 { eprintln('usage: service-access-build BASELINE BASELINE_MANIFEST_SHA256 BASELINE_JAR_SHA256 FRESH_OUTPUT | --self-test'); exit(2) }
 build(os.abs_path(os.args[1]), os.args[2], os.args[3], os.abs_path(os.args[4])) or { eprintln(err); exit(1) }
}
