// SPDX-License-Identifier: GPL-2.0-or-later
// Account client, broker response/context/interaction and real WebView delta over the sealed
// 2098-class framework. The pinned JAR is the only canonical class input.
module main

import crypto.sha256
import json2
import os
import time

const repo = '/Users/alex/code/vinix'
const state = '/Users/alex/.local/state/vinix/android/'
const compiler = '/Users/alex/code/v/v'
const store_compiler = '/Users/alex/code/v-tccbin-bootstrap-20261026/v'
const store_compiler_pin = '0cc6c1d34c1811a818e4ae89853116861a4b067d4251af257851a7714f0d11fe'
const interaction_manifest = 'dc5c0470c4cdc7a075ded61680e4ac89cef056dbcb515ce55a32f74bf82aef87'
const interaction_jar = '86278c9cbe1f25904b760250f34f859206d719cbb23cf5ff5411a75c480ac36f'
const java = '/opt/homebrew/opt/openjdk@25/bin/java'
const tools = repo + '/build/android-framework/tools'
const source_file = repo + '/tests/native-android-ws/combined-account-webview-build.v'
const providers = ['framework_accounts.v', 'framework_account_client.v',
 'framework_account_broker_context.v', 'framework_account_native_response.v', 'framework_webview.v',
 'framework_account_interaction.v']
const changes = ['android/accounts/AccountManager.smali', 'android/atl/VinixAccountFuture.smali',
 'android/os/Binder.smali', 'android/content/Context.smali', 'android/webkit/WebView.smali',
 'android/webkit/WebSettings.smali', 'android/webkit/WebViewClient.smali', 'android/webkit/CookieManager.smali',
 'android/app/PendingIntent.smali', 'android/accounts/AccountAuthenticatorResponse.smali', 'android/os/Bundle.smali']
const additions = ['android/atl/VinixAccountBrokerContext.smali',
 'android/atl/VinixAuthenticatorResponse.smali', 'android/webkit/VinixCookieCallback.smali',
 'android/atl/VinixAccountInteraction.smali']
const accessors = {
 'android/app/PendingIntent.smali': 'public final vinixAccountActivityIntent()Landroid/content/Intent;'
 'android/accounts/AccountAuthenticatorResponse.smali': 'public final vinixMatchesResponse(Landroid/accounts/IAccountAuthenticatorResponse;)Z'
 'android/os/Bundle.smali': 'public final declared-synchronized vinixAccountInteractionValue(Ljava/lang/String;)Ljava/lang/Object;'
}
const store_methods = ['addAccountExplicitly(Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;)Z',
 'addAccountExplicitly(Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;Ljava/util/Map;)Z',
 'getAccounts()[Landroid/accounts/Account;', 'getAccountsByType(Ljava/lang/String;)[Landroid/accounts/Account;',
 'getAccountsByTypeForPackage(Ljava/lang/String;Ljava/lang/String;)[Landroid/accounts/Account;',
 'vinixAddExplicitly(Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;Ljava/util/Map;)Z',
 'vinixAccounts(Ljava/lang/String;Ljava/lang/String;)[Landroid/accounts/Account;',
 'getUserData(Landroid/accounts/Account;Ljava/lang/String;)Ljava/lang/String;',
 'setUserData(Landroid/accounts/Account;Ljava/lang/String;Ljava/lang/String;)V',
 'setAccountVisibility(Landroid/accounts/Account;Ljava/lang/String;I)Z',
 'getPassword(Landroid/accounts/Account;)Ljava/lang/String;',
 'setPassword(Landroid/accounts/Account;Ljava/lang/String;)V']

struct StoreClassParts {
 methods map[string]string
 metadata string
}

fn store_parts(source string) !StoreClassParts {
 mut methods := map[string]string{}
 mut metadata := []string{}
 mut current := []string{}
 mut signature := ''
 for line in source.split_into_lines() {
  trimmed := line.trim_space()
  if trimmed.starts_with('.method ') {
   if signature != '' { return error('nested store method') }
   signature = trimmed.all_after_last(' ')
   if signature in methods { return error('duplicate store method: ' + signature) }
  }
  if signature != '' {
   current << line
   if trimmed == '.end method' {
    methods[signature] = current.join('\n')
    current = []string{}
    signature = ''
   }
  } else if trimmed != '' && !trimmed.starts_with('#') {
   if trimmed == '.end method' { return error('stray store method terminator') }
   metadata << line
  }
 }
 if signature != '' { return error('unterminated store method') }
 return StoreClassParts{methods, metadata.join('\n')}
}

fn store_method_delta(old string, new string) ! {
 before := store_parts(old)!
 after := store_parts(new)!
 if before.metadata != after.metadata { return error('store provider changed class/field metadata') }
 mut changed := 0
 mut added := 0
 for name, method in before.methods {
  if name !in after.methods { return error('store provider removed method: ' + name) }
  if method != after.methods[name]! {
   if name !in store_methods { return error('store provider changed unrelated method: ' + name) }
   changed++
  }
 }
 for name in after.methods.keys() {
  if name !in before.methods {
   if name !in store_methods { return error('store provider added unrelated method: ' + name) }
   added++
  }
 }
 for name in store_methods {
  if name !in after.methods { return error('missing store method: ' + name) }
 }
 if changed != 4 || added != 8 { return error('store provider requires exactly four changed and eight added methods') }
}

fn store_method_self_test() ! {
 metadata := '.class public Landroid/accounts/AccountManager;\n.super Ljava/lang/Object;\n'
 unrelated := '.method public unrelated()V\n.locals 0\nreturn-void\n.end method\n'
 mut before := metadata + unrelated
 mut after := metadata + unrelated
 for i, name in store_methods {
  method := '.method public ' + name + '\n.locals 1\nreturn-void\n.end method\n'
  if i < 4 { before += method }
  after += method.replace('.locals 1', '.locals 2')
 }
 store_method_delta(before, after)!
 for bad in [after.replace('.super Ljava/lang/Object;', '.super LOther;'),
  after.replace('public unrelated()V', 'public renamed()V'),
  after.replace('.locals 0', '.locals 3'), after + unrelated,
  after.replace('public ' + store_methods[11], 'public extra()V'),
  after + '.method public broken()V\n',
  after.replace('public ' + store_methods[0] + '\n.locals 2', 'public ' + store_methods[0] + '\n.locals 1')] {
  store_method_delta(before, bad) or { continue }
  return error('invalid store method delta accepted')
 }
}

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
 if old.len != 2098 || new.len != old.len + additions.len {
  return error('unexpected framework class set')
 }
 for name in additions {
  if name in old || name !in new { return error('unexpected added class: ' + name) }
 }
 for name in changes {
  if name !in old || name !in new || old[name]! == new[name]! {
   return error('missing required class change: ' + name)
  }
 }
 for name, pin in old {
  if name !in new || ((name in changes) == (pin == new[name]!)) {
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

fn store_class_delta(old map[string]string, new map[string]string) ! {
 if old.len != 2102 || new.len != old.len { return error('store profile requires exactly 2102 classes') }
 for name, pin in old {
  if name !in new || ((name == 'android/accounts/AccountManager.smali') == (pin == new[name]!)) {
   return error('unexpected store profile class delta: ' + name)
  }
 }
 if 'android/accounts/AccountManager.smali' !in old { return error('missing AccountManager baseline') }
}

fn store_delta_self_test() ! {
 mut old := {'android/accounts/AccountManager.smali': 'old'}
 for i in 0 .. 2101 { old['other/' + i.str() + '.smali'] = 'same' }
 mut good := old.clone()
 good['android/accounts/AccountManager.smali'] = 'new'
 store_class_delta(old, good)!
 for case in 0 .. 6 {
  mut before := old.clone()
  mut bad := good.clone()
  match case {
   0 { bad['android/accounts/AccountManager.smali'] = 'old' }
   1 { bad['other/0.smali'] = 'new' }
   2 { bad.delete('other/0.smali') }
   3 { bad['extra.smali'] = 'new' }
   4 { bad.delete('other/0.smali'); bad['extra.smali'] = 'new' }
   else {
    before.delete('android/accounts/AccountManager.smali')
    bad.delete('android/accounts/AccountManager.smali')
    before['substitution.smali'] = 'same'; bad['substitution.smali'] = 'same'
   }
  }
  store_class_delta(before, bad) or { continue }
  return error('invalid store profile class delta accepted: ' + case.str())
 }
}

fn accessor_delta(old string, new string, declaration string) ! {
 marker := '.method ' + declaration + '\n'
 if old.contains(marker) || new.count(marker) != 1 {
  return error('missing, duplicate or preexisting interaction accessor: ' + declaration)
 }
 start := new.index(marker) or { return error('missing accessor') }
 tail := new[start..]
 end := tail.index('.end method') or { return error('unterminated interaction accessor') }
 block := tail[..end + '.end method'.len]
 if block.count('.method ') != 1 { return error('nested interaction accessor') }
 stripped := new[..start] + new[start + block.len..]
 if old.split_into_lines().filter(it.trim_space() != '').join('\n') !=
  stripped.split_into_lines().filter(it.trim_space() != '').join('\n') {
  return error('interaction accessor changed existing class code: ' + declaration)
 }
}

fn self_test() ! {
 store_delta_self_test()!
 store_method_self_test()!
 mut old := map[string]string{}
 for name in changes { old[name] = 'old' }
 for i in 0 .. 2098 - changes.len { old['other/' + i.str() + '.smali'] = 'old' }
 mut good := old.clone()
 for name in changes { good[name] = 'changed' }
 for name in additions { good[name] = 'new' }
 class_delta(old, good)!
 for case in 0 .. 8 {
  mut before := old.clone()
  mut bad := good.clone()
  match case {
   0 { bad['other/0.smali'] = 'changed' }
   1 { bad.delete('other/0.smali') }
   2 { bad['surprise.smali'] = 'new' }
   3 { before.delete('other/0.smali'); bad.delete('other/0.smali') }
   4 { bad.delete(additions[0]) }
   5 { bad.delete(additions[0]); bad['surprise.smali'] = 'new' }
   6 { before['surprise.smali'] = 'old'; bad['surprise.smali'] = 'old' }
   else { before.delete('other/0.smali'); before[additions[0]] = 'old' }
  }
  class_delta(before, bad) or { continue }
  return error('invalid class delta accepted: ' + case.str())
 }
 for name in additions {
  mut bad := good.clone()
  bad.delete(name)
  bad['surprise.smali'] = 'new'
  class_delta(old, bad) or { continue }
  return error('missing required addition accepted: ' + name)
 }
 for name in changes {
  mut bad := good.clone()
  bad[name] = 'old'
  class_delta(old, bad) or { continue }
  return error('missing required change accepted: ' + name)
 }
 for name in changes {
  mut before := old.clone()
  mut bad := good.clone()
  before.delete(name)
  bad.delete(name)
  before['substitution.smali'] = 'old'
  bad['substitution.smali'] = 'old'
  class_delta(before, bad) or { continue }
  return error('substituted baseline change accepted: ' + name)
 }
 accessor_old := '.class public LExample;\n.super Ljava/lang/Object;\n.method public existing()V\n.locals 0\nreturn-void\n.end method\n'
 accessor := '.method public added()V\n.locals 0\nreturn-void\n.end method\n'
 accessor_delta(accessor_old, accessor_old + '\n' + accessor, 'public added()V')!
 for bad in [accessor_old, accessor_old + accessor + accessor,
  (accessor_old + accessor).replace('public existing()V', 'public changed()V'),
  (accessor_old + accessor).replace('.super Ljava/lang/Object;', '.super LOther;'),
  accessor_old + accessor.all_before('.end method'),
  accessor_old + accessor.replace('return-void', '.method private injected()V\nreturn-void')] {
  accessor_delta(accessor_old, bad, 'public added()V') or { continue }
  return error('invalid accessor-only class delta accepted')
 }
 accessor_delta(accessor_old + accessor, accessor_old + accessor, 'public added()V') or {
  jar_self_test()!
  return
 }
 return error('preexisting accessor accepted')
}

// Apply only the committed storage provider to the sealed interaction profile.
// The original combined build remains available with its historical input ABI.
fn build_store(baseline string, manifest_pin string, jar_pin string, root string) ! {
 if baseline != state + 'combined-account-webview-interaction-framework-2026-10-26'
  || manifest_pin != interaction_manifest || jar_pin != interaction_jar
  || os.real_path(baseline) != baseline || !root.starts_with(state + 'combined-account-webview-store-')
  || os.real_path(os.dir(root)) != os.dir(root) || os.exists(root) || os.is_link(root)
  || root.contains_any(' \n\t') {
  return error('exact sealed interaction baseline and fresh external store output required')
 }
 if digest(store_compiler)! != store_compiler_pin || digest(baseline + '/api-impl.jar')! != jar_pin {
  return error('store compiler or interaction JAR pin differs')
 }
 sealed_baseline(baseline, manifest_pin)!
 os.mkdir_all(root + '/commands')!
 os.mkdir_all(root + '/provider-source/androidtools')!
 os.mkdir_all(root + '/smali-tools')!
 os.mkdir_all(root + '/tools')!
 os.mkdir_all(root + '/provider-helper-inputs')!
 mut inputs := map[string]string{}
 for path in [source_file, store_compiler, os.real_path(java), os.executable(),
  baseline + '/api-impl.jar', baseline + '/build.json', baseline + '/sha256.json'] {
  inputs[path] = digest(path)!
 }
 os.cp(source_file, root + '/builder-source.v')!
 os.cp(os.executable(), root + '/builder')!
 os.cp(store_compiler, root + '/tools/v')!
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
 provider := repo + '/tests/native-android-tools/androidtools/framework_account_store.v'
 helper := repo + '/tests/native-android-tools/androidtools/framework.v'
 for path in [provider, helper] { inputs[path] = digest(path)! }
 os.cp(provider, root + '/provider-source/androidtools/framework_account_store.v')!
 os.cp(helper, root + '/provider-helper-inputs/framework.v')!
 if digest(root + '/provider-source/androidtools/framework_account_store.v')! != inputs[provider]!
  || digest(root + '/provider-helper-inputs/framework.v')! != inputs[helper]! {
  return error('store provider/helper copy differs')
 }
 os.write_file(root + '/provider-source/androidtools/framework_account_helpers.v',
  'module androidtools\n' + helper_function(os.read_file(root + '/provider-helper-inputs/framework.v')!, 'pub fn framework_replace_method(')!)!
 os.write_file(root + '/provider-source/main.v',
  'module main\nimport androidtools\nimport os\nfn main() {\n' +
  'path := os.args[1] + "/android/accounts/AccountManager.smali"\n' +
  'os.write_file(path,androidtools.framework_account_store(os.read_file(path)!)!)!\n}\n')!
 os.setenv('VROOT', os.dir(store_compiler), true)
 os.setenv('V', store_compiler, true)
 os.setenv('VINIX_V_COMPILER', store_compiler, true)
 command(root, 'java-version', [java, '--version'])!
 command(root, 'v-version', [store_compiler, 'version'])!
 driver_closure := freeze_closure(root, command(root, 'builder-closure', [store_compiler, '-print-v-files', source_file])!, 'builder-closure-inputs')!
 command(root, 'old-disassemble', [java, '-cp', classpath.join(':'), 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', baseline + '/api-impl.jar', '-o', root + '/old-dex'])!
 command(root, 'clone-canonical-smali', ['/bin/cp', '-c', '-R', root + '/old-dex', root + '/smali'])!
 os.cp(baseline + '/api-impl.jar', root + '/api-impl.jar')!
 mut old := map[string]string{}
 inventory(root + '/old-dex', '', mut old)!
 provider_closure := freeze_closure(root, command(root, 'provider-closure', [store_compiler, '-print-v-files', '-path', root + '/provider-source|@vlib', root + '/provider-source'])!, 'provider-closure-inputs')!
 command(root, 'compile-provider', [store_compiler, '-nocache', '-cc', 'cc', '-path', root + '/provider-source|@vlib', '-o', root + '/provider', root + '/provider-source'])!
 for path, pin in provider_closure { if digest(path)! != pin { return error('store provider input changed: ' + path) } }
 command(root, 'apply-provider', [root + '/provider', root + '/smali'])!
 mut applied := map[string]string{}
 inventory(root + '/smali', '', mut applied)!
 store_class_delta(old, applied)!
 store_method_delta(os.read_file(root + '/old-dex/android/accounts/AccountManager.smali')!,
  os.read_file(root + '/smali/android/accounts/AccountManager.smali')!)!
 command(root, 'assemble', [java, '-cp', classpath.join(':'), 'org.jf.smali.Main', 'assemble', '--jobs', '2', root + '/smali', '-o', root + '/classes.dex'])!
 if !os.is_file(root + '/classes.dex') || os.file_size(root + '/classes.dex') < 112 { return error('store assembly produced no fresh DEX') }
 command(root, 'replace-dex', ['/usr/bin/zip', '-q', '-j', root + '/api-impl.jar', root + '/classes.dex'])!
 command(root, 'new-disassemble', [java, '-cp', classpath.join(':'), 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', root + '/api-impl.jar', '-o', root + '/new-dex'])!
 mut new := map[string]string{}
 inventory(root + '/new-dex', '', mut new)!
 store_class_delta(old, new)!
 store_method_delta(os.read_file(root + '/old-dex/android/accounts/AccountManager.smali')!,
  os.read_file(root + '/new-dex/android/accounts/AccountManager.smali')!)!
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
 sealed_baseline(baseline, manifest_pin)!
 for path, pin in driver_closure { if digest(path)! != pin { return error('store builder source changed: ' + path) } }
 for path, pin in inputs { if digest(path)! != pin { return error('store input changed: ' + path) } }
 write_json(root + '/build.json', {
  'scope': json2.Any('AccountManager storage provider over exact sealed interaction framework; host assembly only, no guest or Google login proof'),
  'profile': json2.Any('account-store-interaction-2102'),
  'source_revision': json2.Any(command(root, 'revision', ['/usr/bin/git', '-C', repo, 'rev-parse', 'HEAD'])!.trim_space()),
  'input_sha256': json2.decode[json2.Any](json2.encode(inputs))!,
  'baseline_path': json2.Any(baseline), 'baseline_manifest_sha256': json2.Any(manifest_pin),
  'baseline_api_impl_sha256': json2.Any(jar_pin), 'api_impl_sha256': json2.Any(digest(root + '/api-impl.jar')!),
  'classes_dex_sha256': json2.Any(digest(root + '/classes.dex')!),
  'changed_classes': json2.Any(['android/accounts/AccountManager.smali']), 'added_classes': json2.Any([]string{}),
  'class_count': json2.Any(new.len), 'compiler_sha256': json2.Any(store_compiler_pin),
  'account_manager_changed_method_count': json2.Any(4), 'account_manager_added_method_count': json2.Any(8),
  'environmental_inputs': json2.Any('Host SDK and dynamic libraries are environmental dependencies; exact V source closures, compiler and smali tool JARs retained and checked')
 })!
 mut pins := map[string]string{}
 inventory(root, '', mut pins)!
 write_json(root + '/sha256.json', pins)!
 sealed_baseline(root, digest(root + '/sha256.json')!)!
 println('STORE-FRAMEWORK-BUILD-PASS classes=' + new.len.str() + ' jar=' + root + '/api-impl.jar')
 println('STORE-FRAMEWORK-BUILD-MANIFEST-SHA256 ' + digest(root + '/sha256.json')!)
}

fn jar_self_test() ! {
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
 helper := '\nfn exact() string {\n return "retained"\n}\n'
 if helper_function(helper, 'fn exact(')! != helper.trim_left('\n') { return error('helper extraction differs') }
 helper_function(helper + helper, 'fn exact(') or {
  helper_function('\nfn exact() string {\n', 'fn exact(') or {
   println('COMBINED-FRAMEWORK-SELF-TEST-PASS strict class/JAR mutations, accessor-only deltas, missing required deltas, substituted baseline classes and malformed/duplicate helpers rejected')
   return
  }
  return error('unterminated helper accepted')
 }
 return error('duplicate helper accepted')
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

fn sealed_baseline(root string, pin string) ! {
 if !valid_pin(pin) || digest(root + '/sha256.json')! != pin {
  return error('sealed baseline manifest differs')
 }
 expected := json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
 mut actual := map[string]string{}
 inventory(root, '', mut actual)!
 actual.delete('sha256.json')
 if actual != expected { return error('sealed baseline file set or checksums differ') }
}

fn helper_function(source string, signature string) !string {
 marker := '\n' + signature
 if source.count(marker) != 1 { return error('unique helper required: ' + signature) }
 start := (source.index(marker) or { return error('missing helper: ' + signature) }) + 1
 tail := source[start..]
 end := tail.index('\n}') or { return error('unterminated helper: ' + signature) }
 return tail[..end + 2] + '\n'
}

fn provider_main() string {
 return 'module main\nimport androidtools\nimport os\nfn main() {\nr := os.args[1]\n' +
  'classes := androidtools.framework_account_client_classes()\n' +
  'for name,source in classes {\npath := r + "/" + name + ".smali"\n' +
  'if !os.is_file(path) { panic("missing baseline account class " + name) }\nos.write_file(path,source)!\n}\n' +
  'manager := r + "/android/accounts/AccountManager.smali"\n' +
  'os.write_file(manager, androidtools.framework_account_client_addition(os.read_file(manager)!)!)!\n' +
  'androidtools.framework_account_broker_context(r)!\n' +
  'for name,source in androidtools.framework_account_native_response_classes() {\n' +
  'path := r + "/" + name + ".smali"\nif os.exists(path) { panic("native response already exists") }\n' +
  'os.write_file(path,source)!\n}\n' +
  'web := r + "/android/webkit/"\n' +
  'patched := androidtools.framework_webview_sources(os.read_file(web + "WebView.smali")!,\n' +
  'os.read_file(web + "WebSettings.smali")!,os.read_file(web + "WebViewClient.smali")!,\n' +
  'os.read_file(web + "CookieManager.smali")!)!\n' +
  'for name,source in patched { os.write_file(web + name + ".smali",source)! }\n' +
  'if os.exists(web + "VinixCookieCallback.smali") { panic("cookie callback already exists") }\n' +
  'os.write_file(web + "VinixCookieCallback.smali",androidtools.framework_webview_callback())!\n' +
  'for name,accessor in {\n' +
  '"android/app/PendingIntent": androidtools.framework_account_interaction_pending_accessor()\n' +
  '"android/accounts/AccountAuthenticatorResponse": androidtools.framework_account_interaction_response_accessor()\n' +
  '"android/os/Bundle": androidtools.framework_account_interaction_bundle_accessor()\n} {\n' +
  'path := r + "/" + name + ".smali"\nsource := os.read_file(path)!\n' +
  'declaration := accessor.all_before("\\n")\n' +
  'if !declaration.starts_with(".method ") || source.contains(declaration + "\\n") { panic("preexisting or invalid accessor " + name) }\n' +
  'os.write_file(path,source + "\\n" + accessor)!\n}\n' +
  'for name,source in androidtools.framework_account_interaction_classes() {\n' +
  'path := r + "/" + name + ".smali"\nif os.exists(path) { panic("interaction helper already exists") }\n' +
  'os.write_file(path,source)!\n}\n}\n'
}

fn build(baseline string, manifest_pin string, jar_pin string, root string) ! {
 if !valid_pin(manifest_pin) || !valid_pin(jar_pin) { return error('SHA256 pins required') }
 if !baseline.starts_with(state + 'account-contract-') || os.real_path(baseline) != baseline
  || !root.starts_with(state + 'combined-account-webview-') || os.real_path(os.dir(root)) != os.dir(root)
  || os.exists(root) || os.is_link(root) || root.contains_any(' \n\t') {
  return error('canonical baseline and fresh external combined-account-webview output required')
 }
 if digest(baseline + '/sha256.json')! != manifest_pin || digest(baseline + '/api-impl.jar')! != jar_pin {
  return error('sealed framework baseline differs')
 }
 sealed_baseline(baseline, manifest_pin)!
 os.mkdir_all(root + '/commands')!
 os.mkdir_all(root + '/provider-source/androidtools')!
 os.mkdir_all(root + '/smali-tools')!
 mut inputs := map[string]string{}
 for path in [source_file, compiler, os.real_path(java), os.executable(),
  baseline + '/api-impl.jar', baseline + '/build.json', baseline + '/sha256.json'] {
  inputs[path] = digest(path)!
 }
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
  if digest(root + '/provider-source/androidtools/' + name)! != inputs[path]! {
   return error('provider copy differs: ' + name)
  }
 }
 // Providers share these self-contained helpers with the full framework
 // generator. Retain their complete originals and compile exact
 // function bytes without importing the unrelated framework generators.
 mut helpers := 'module androidtools\n'
 os.mkdir_all(root + '/provider-helper-inputs')!
 for pair in [['framework.v', 'pub fn framework_replace_method('],
  ['framework_classes.v', 'fn interface_class('],
  ['framework_signatures.v', 'fn signature_method('],
  ['framework_bundle_parcel.v', 'fn bundle_parcel_method('],
  ['framework_bundle_parcel.v', 'fn bundle_parcel_lock(']] {
  name := pair[0]
  signature := pair[1]
  path := repo + '/tests/native-android-tools/androidtools/' + name
  target := root + '/provider-helper-inputs/' + name
  if path !in inputs {
   inputs[path] = digest(path)!
   os.cp(path, target)!
  }
  if digest(path)! != inputs[path]! || digest(target)! != inputs[path]! { return error('helper copy differs') }
  helpers += '\n' + helper_function(os.read_file(target)!, signature)!
 }
 os.write_file(root + '/provider-source/androidtools/framework_account_helpers.v', helpers)!
 os.write_file(root + '/provider-source/main.v', provider_main())!
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
 // Raw generated formatting can differ from baksmali. The canonical delta is
 // checked after assembly/disassembly; no non-smali input is accepted here.
 if applied.len != 2098 + additions.len || applied.keys().any(!it.ends_with('.smali')) {
  return error('unexpected provider class set')
 }
 command(root, 'assemble', [java, '-cp', classpath.join(':'), 'org.jf.smali.Main', 'assemble', '--jobs', '2', root + '/smali', '-o', root + '/classes.dex'])!
 if !os.is_file(root + '/classes.dex') || os.file_size(root + '/classes.dex') < 112 { return error('assembly produced no fresh DEX') }
 command(root, 'replace-dex', ['/usr/bin/zip', '-q', '-j', root + '/api-impl.jar', root + '/classes.dex'])!
 command(root, 'new-disassemble', [java, '-cp', classpath.join(':'), 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', root + '/api-impl.jar', '-o', root + '/new-dex'])!
 mut new := map[string]string{}
 inventory(root + '/new-dex', '', mut new)!
 class_delta(old, new)!
 for name, declaration in accessors {
  accessor_delta(os.read_file(root + '/old-dex/' + name)!,
   os.read_file(root + '/new-dex/' + name)!, declaration)!
 }
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
 sealed_baseline(baseline, manifest_pin)!
 for path, pin in driver_closure { if digest(path)! != pin { return error('builder source changed: ' + path) } }
 for path, pin in inputs { if digest(path)! != pin { return error('input changed: ' + path) } }
 write_json(root + '/build.json', {
  'scope': json2.Any('Combined account client, broker context/response/interaction and WebView framework; source and assembly validation only, no Google login success claim'),
  'source_revision': json2.Any(command(root, 'revision', ['/usr/bin/git', '-C', repo, 'rev-parse', 'HEAD'])!.trim_space()),
  'input_sha256': json2.decode[json2.Any](json2.encode(inputs))!,
  'baseline_path': json2.Any(baseline), 'baseline_manifest_sha256': json2.Any(manifest_pin),
  'baseline_api_impl_sha256': json2.Any(jar_pin), 'api_impl_sha256': json2.Any(digest(root + '/api-impl.jar')!),
  'classes_dex_sha256': json2.Any(digest(root + '/classes.dex')!),
  'changed_classes': json2.Any(changes), 'added_classes': json2.Any(additions), 'class_count': json2.Any(new.len),
  'accessor_only_classes': json2.decode[json2.Any](json2.encode(accessors))!,
  'environmental_inputs': json2.Any('Host SDK and dynamic libraries are environmental dependencies; V source closures and smali tool JARs retained and checked')
 })!
 mut pins := map[string]string{}
 inventory(root, '', mut pins)!
 write_json(root + '/sha256.json', pins)!
 sealed_baseline(root, digest(root + '/sha256.json')!)!
 println('COMBINED-FRAMEWORK-BUILD-PASS classes=' + new.len.str() + ' jar=' + root + '/api-impl.jar')
 println('COMBINED-FRAMEWORK-BUILD-MANIFEST-SHA256 ' + digest(root + '/sha256.json')!)
}

fn main() {
 if os.args.len == 2 && os.args[1] == '--self-test' { self_test() or { eprintln(err); exit(1) }; return }
 if os.args.len == 4 && os.args[1] == '--check' {
  sealed_baseline(os.abs_path(os.args[2]), os.args[3]) or { eprintln(err); exit(1) }
  println('COMBINED-FRAMEWORK-INTEGRITY-PASS ' + os.args[3])
  return
 }
 if os.args.len == 6 && os.args[1] == '--store' {
  build_store(os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len != 5 { eprintln('usage: combined-account-webview-build [--store] BASELINE BASELINE_MANIFEST_SHA256 BASELINE_JAR_SHA256 FRESH_OUTPUT | --self-test'); exit(2) }
 build(os.abs_path(os.args[1]), os.args[2], os.args[3], os.abs_path(os.args[4])) or { eprintln(err); exit(1) }
}
