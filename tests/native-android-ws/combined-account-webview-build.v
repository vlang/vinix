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
const store_manifest = '7cc408299a3a7d37578735e79b31c5c2ff96dbd1de00a2d7dd0d1e149b156690'
const store_jar = '9e89db595defb905b0322183f176613f2b42f951ec1b51d4ceb91431876c3c8e'
const auth_manifest = '1299ddd064ebe89bae35cafd4c509794894c7466fda0bfaee2dfb85cf404d309'
const auth_jar = 'c677808eb55f58845b4ce3dd5c72be481d4ca585fd4980cec18266271d4740bf'
const cache_manifest = 'f37e13b84b5dfb2c71ad852e2bae5b03fed04e8ee319f44e77fc7605f3b1994a'
const cache_jar = '3a590476c53e3f05533c327c5935e395c55694eacb7895b02940feaf888c56d0'
const descriptions_manifest = 'd898fdcca66df0c32b9863dca99c7185d10f8e3b3fb5ab7708999b3619803021'
const descriptions_jar = '71d05c6e6288978de66a5c71279e8cb27d92c9166950813ddbf0c33ff86e1d0d'
const java = '/opt/homebrew/opt/openjdk@25/bin/java'
const tools = repo + '/build/android-framework/tools'
const source_file = repo + '/tests/native-android-ws/combined-account-webview-build.v'
const providers = ['framework_accounts.v', 'framework_account_client.v',
 'framework_account_broker_context.v', 'framework_account_native_response.v', 'framework_webview.v',
 'framework_account_interaction.v', 'framework_account_store.v', 'framework_cookie_clear.v',
 'framework_account_token.v']
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
const clear_methods = ['removeAllCookie()V', 'removeAllCookies(Landroid/webkit/ValueCallback;)V',
 'removeSessionCookie()V', 'removeSessionCookies(Landroid/webkit/ValueCallback;)V', 'nativeClear(Z)Z']
const token_methods = ['getAuthToken(Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;Landroid/app/Activity;Landroid/accounts/AccountManagerCallback;Landroid/os/Handler;)Landroid/accounts/AccountManagerFuture;',
 'getAuthToken(Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;ZLandroid/accounts/AccountManagerCallback;Landroid/os/Handler;)Landroid/accounts/AccountManagerFuture;',
 'getAuthToken(Landroid/accounts/Account;Ljava/lang/String;ZLandroid/accounts/AccountManagerCallback;Landroid/os/Handler;)Landroid/accounts/AccountManagerFuture;',
 'blockingGetAuthToken(Landroid/accounts/Account;Ljava/lang/String;Z)Ljava/lang/String;',
 'vinixStartToken(Landroid/accounts/Account;Ljava/lang/String;Landroid/os/Bundle;Landroid/app/Activity;Landroid/atl/VinixAccountFuture;)Z']
const cache_methods = ['peekAuthToken(Landroid/accounts/Account;Ljava/lang/String;)Ljava/lang/String;',
 'setAuthToken(Landroid/accounts/Account;Ljava/lang/String;Ljava/lang/String;)V',
 'invalidateAuthToken(Ljava/lang/String;Ljava/lang/String;)V',
 'clearPassword(Landroid/accounts/Account;)V']
const description_methods = ['getAuthenticatorTypes()[Landroid/accounts/AuthenticatorDescription;']
const description_classes = ['android/accounts/AuthenticatorDescription.smali',
 'android/accounts/AuthenticatorDescription$Creator.smali']

struct StoreClassParts {
 methods map[string]string
 metadata string
}

struct NarrowProfile {
 name string
 baseline_name string
 manifest_pin string
 jar_pin string
 providers []string
 calls map[string]string
 methods map[string][]string
 changed map[string]int
 added map[string]int
 class_provider string
 extra_classes []string
 baseline_classes int = 2102
 directory_provider string
 fields map[string][]string
}

fn storage_profile() NarrowProfile {
 return NarrowProfile{
  name: 'store'
  baseline_name: 'combined-account-webview-interaction-framework-2026-10-26'
  manifest_pin: interaction_manifest
  jar_pin: interaction_jar
  providers: ['framework_account_store.v']
  calls: {'android/accounts/AccountManager.smali': 'framework_account_store'}
  methods: {'android/accounts/AccountManager.smali': store_methods}
  changed: {'android/accounts/AccountManager.smali': 4}
  added: {'android/accounts/AccountManager.smali': 8}
 }
}

fn auth_profile() NarrowProfile {
 return NarrowProfile{
  name: 'auth'
  baseline_name: 'combined-account-webview-store-framework-2026-10-26'
  manifest_pin: store_manifest
  jar_pin: store_jar
  providers: ['framework_cookie_clear.v', 'framework_account_token.v']
  calls: {'android/accounts/AccountManager.smali': 'framework_account_token',
   'android/webkit/CookieManager.smali': 'framework_webview_cookie_clear'}
  methods: {'android/accounts/AccountManager.smali': token_methods,
   'android/webkit/CookieManager.smali': clear_methods}
  changed: {'android/accounts/AccountManager.smali': 0, 'android/webkit/CookieManager.smali': 4}
  added: {'android/accounts/AccountManager.smali': 5, 'android/webkit/CookieManager.smali': 1}
 }
}

fn cache_profile() NarrowProfile {
 return NarrowProfile{
  name: 'cache'
  baseline_name: 'combined-account-webview-auth-framework-2026-10-26'
  manifest_pin: auth_manifest
  jar_pin: auth_jar
  providers: ['framework_account_token_cache.v']
  calls: {'android/accounts/AccountManager.smali': 'framework_account_token_cache'}
  methods: {'android/accounts/AccountManager.smali': cache_methods}
  changed: {'android/accounts/AccountManager.smali': 0}
  added: {'android/accounts/AccountManager.smali': 4}
 }
}

fn descriptions_profile() NarrowProfile {
 return NarrowProfile{
  name: 'descriptions'
  baseline_name: 'combined-account-webview-cache-framework-2026-10-26-r3'
  manifest_pin: cache_manifest
  jar_pin: cache_jar
  providers: ['framework_authenticator_descriptions.v']
  calls: {'android/accounts/AccountManager.smali': 'framework_authenticator_descriptions'}
  methods: {'android/accounts/AccountManager.smali': description_methods}
  changed: {'android/accounts/AccountManager.smali': 0}
  added: {'android/accounts/AccountManager.smali': 1}
  class_provider: 'framework_authenticator_description_classes'
  extra_classes: description_classes
 }
}

fn protected_storage_profile() NarrowProfile {
 return NarrowProfile{
  name: 'protected-storage'
  baseline_name: 'combined-account-webview-descriptions-framework-2026-10-26-r1'
  manifest_pin: descriptions_manifest
  jar_pin: descriptions_jar
  baseline_classes: 2104
  providers: ['framework_protected_storage.v']
  directory_provider: 'framework_protected_storage'
  methods: {
   'android/content/pm/ApplicationInfo.smali': ['<init>(Landroid/content/pm/ApplicationInfo;)V', 'vinixSetDataDirectory(Ljava/lang/String;)V']
   'android/content/Context.smali': ['getDataDirFile()Ljava/io/File;', '<clinit>()V']
   'android/atl/ATLLoadedAppManager.smali': ['loadApplication(Ljava/lang/String;)Landroid/atl/ATLLoadedApp;', 'vinixLoadActivityApplication(Ljava/lang/String;)Landroid/atl/ATLLoadedApp;']
   'android/app/ContextImpl.smali': ['createConfigurationContext(Landroid/content/res/Configuration;)Landroid/content/Context;']
  }
  changed: {'android/content/pm/ApplicationInfo.smali': 1, 'android/content/Context.smali': 2,
   'android/atl/ATLLoadedAppManager.smali': 2, 'android/app/ContextImpl.smali': 1}
  added: {'android/content/pm/ApplicationInfo.smali': 1, 'android/content/Context.smali': 0,
   'android/atl/ATLLoadedAppManager.smali': 0, 'android/app/ContextImpl.smali': 0}
  fields: {'android/content/pm/ApplicationInfo.smali': ['.field public credentialProtectedDataDir:Ljava/lang/String;',
   '.field public deviceProtectedDataDir:Ljava/lang/String;']}
 }
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

fn narrow_method_delta(old string, new string, allowed []string, expected_changed int, expected_added int) ! {
 narrow_member_delta(old, new, allowed, expected_changed, expected_added, []string{})!
}

fn narrow_member_delta(old string, new string, allowed []string, expected_changed int, expected_added int, fields []string) ! {
 before := store_parts(old)!
 after := store_parts(new)!
 mut metadata := after.metadata.split_into_lines()
 mut seen := map[string]bool{}
 for field in fields {
  if !field.starts_with('.field ') || field in seen || field in before.metadata.split_into_lines()
   || metadata.filter(it == field).len != 1 {
   return error('missing, duplicate or preexisting required field: ' + field)
  }
  seen[field] = true
  metadata = metadata.filter(it != field)
 }
 if before.metadata != metadata.join('\n') { return error('provider changed class/field metadata') }
 mut changed := 0
 mut added := 0
 for name, method in before.methods {
  if name !in after.methods { return error('provider removed method: ' + name) }
  if method != after.methods[name]! {
   if name !in allowed { return error('provider changed unrelated method: ' + name) }
   changed++
  }
 }
 for name in after.methods.keys() {
  if name !in before.methods {
   if name !in allowed { return error('provider added unrelated method: ' + name) }
   added++
  }
 }
 for name in allowed {
  if name !in after.methods { return error('missing required method: ' + name) }
 }
 if changed != expected_changed || added != expected_added { return error('unexpected provider changed/added method count') }
}

fn store_method_self_test() ! {
 narrow_method_self_test(store_methods, 4, 8)!
 narrow_method_self_test(clear_methods, 4, 1)!
 narrow_method_self_test(token_methods, 0, 5)!
 narrow_method_self_test(cache_methods, 0, 4)!
 narrow_method_self_test(description_methods, 0, 1)!
}

fn narrow_method_self_test(allowed []string, changed int, added int) ! {
 metadata := '.class public Landroid/accounts/AccountManager;\n.super Ljava/lang/Object;\n'
 unrelated := '.method public unrelated()V\n.locals 0\nreturn-void\n.end method\n'
 mut before := metadata + unrelated
 mut after := metadata + unrelated
 for i, name in allowed {
  method := '.method public ' + name + '\n.locals 1\nreturn-void\n.end method\n'
  if i < changed { before += method }
  after += method.replace('.locals 1', '.locals 2')
 }
 narrow_method_delta(before, after, allowed, changed, added)!
 mut count_rejected := false
 narrow_method_delta(before, after, allowed, changed, added + 1) or { count_rejected = true }
 if !count_rejected { return error('incorrect expected method count accepted') }
 for bad in [after.replace('.super Ljava/lang/Object;', '.super LOther;'),
  after.replace('public unrelated()V', 'public renamed()V'),
  after.replace('.locals 0', '.locals 3'), after + unrelated,
  after.replace('public ' + allowed.last(), 'public extra()V'),
  after + '.method public broken()V\n',
  after.replace('public ' + allowed[0], 'public renamed_target()V')] {
  narrow_method_delta(before, bad, allowed, changed, added) or { continue }
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
 narrow_class_delta(old, new, ['android/accounts/AccountManager.smali'])!
}

fn narrow_class_delta(old map[string]string, new map[string]string, targets []string) ! {
 narrow_added_class_delta(old, new, targets, []string{})!
}

fn narrow_added_class_delta(old map[string]string, new map[string]string, targets []string, extras []string) ! {
 narrow_profile_class_delta(old, new, targets, extras, 2102)!
}

fn narrow_profile_class_delta(old map[string]string, new map[string]string, targets []string, extras []string, baseline_classes int) ! {
 if old.len != baseline_classes || new.len != old.len + extras.len || targets.len == 0 {
  return error('narrow profile requires exactly ' + baseline_classes.str() + ' baseline classes and explicit targets/additions')
 }
 mut seen := map[string]bool{}
 for name in extras {
  if name in seen || name in old || name !in new || !name.ends_with('.smali') {
   return error('missing, duplicate or preexisting narrow addition: ' + name)
  }
  seen[name] = true
 }
 for name, pin in old {
  if name !in new || ((name in targets) == (pin == new[name]!)) {
   return error('unexpected narrow profile class delta: ' + name)
  }
 }
 for name in targets { if name !in old { return error('missing narrow baseline class: ' + name) } }
}

fn protected_storage_self_test() ! {
 profile := protected_storage_profile()
 targets := profile.methods.keys()
 for target in targets { narrow_method_self_test(profile.methods[target]!, profile.changed[target]!, profile.added[target]!)! }
 mut old := map[string]string{}
 for target in targets { old[target] = 'old' }
 for i in 0 .. profile.baseline_classes - targets.len { old['other/' + i.str() + '.smali'] = 'same' }
 mut good := old.clone()
 for target in targets { good[target] = 'new' }
 narrow_profile_class_delta(old, good, targets, []string{}, profile.baseline_classes)!
 for case in 0 .. targets.len + 4 {
  mut before := old.clone()
  mut bad := good.clone()
  match case {
   targets.len { bad['other/0.smali'] = 'changed' }
   targets.len + 1 { bad.delete('other/0.smali'); bad['extra.smali'] = 'new' }
   targets.len + 2 { before.delete('other/0.smali'); bad.delete('other/0.smali') }
   targets.len + 3 { bad['extra.smali'] = 'new' }
   else { bad[targets[case]] = 'old' }
  }
  narrow_profile_class_delta(before, bad, targets, []string{}, profile.baseline_classes) or { continue }
  return error('invalid protected storage class delta accepted: ' + case.str())
 }
 metadata := '.class public LExample;\n.super Ljava/lang/Object;\n.field public dataDir:Ljava/lang/String;\n'
 method := '.method public existing()V\n.locals 0\nreturn-void\n.end method\n'
 fields := profile.fields['android/content/pm/ApplicationInfo.smali']!
 before := metadata + method
 after := metadata + fields.join('\n') + '\n' + method
 narrow_member_delta(before, after, []string{}, 0, 0, fields)!
 for bad in [before, after + fields[0] + '\n', after.replace('public deviceProtectedDataDir:', 'private deviceProtectedDataDir:'),
  after + '.field public unexpected:I\n', after.replace('public dataDir:', 'private dataDir:'),
  after.replace('Ljava/lang/Object;', 'LOther;')] {
  narrow_member_delta(before, bad, []string{}, 0, 0, fields) or { continue }
  return error('invalid protected storage field delta accepted')
 }
 narrow_member_delta(after, after, []string{}, 0, 0, fields) or {
  narrow_member_delta(before, after, []string{}, 0, 0, [fields[0], fields[0]]) or { return }
  return error('duplicate required storage field accepted')
 }
 return error('preexisting required storage fields accepted')
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
 targets := ['android/accounts/AccountManager.smali', 'other/0.smali']
 mut two := good.clone()
 two[targets[1]] = 'new'
 narrow_class_delta(old, two, targets)!
 for bad in [good, old] {
  narrow_class_delta(old, bad, targets) or { continue }
  return error('missing one of multiple required class deltas accepted')
 }
 mut extended := good.clone()
 for name in description_classes { extended[name] = 'new class' }
 narrow_added_class_delta(old, extended, ['android/accounts/AccountManager.smali'], description_classes)!
 for case in 0 .. 5 {
  mut bad := extended.clone()
  match case {
   0 { bad.delete(description_classes[0]) }
   1 { bad.delete(description_classes[0]); bad['extra.smali'] = 'new class' }
   2 { bad['other/0.smali'] = 'changed' }
   3 { bad['android/accounts/AccountManager.smali'] = 'old' }
   else { bad.delete('other/0.smali'); bad['extra.smali'] = 'new class' }
  }
  narrow_added_class_delta(old, bad, ['android/accounts/AccountManager.smali'], description_classes) or { continue }
  return error('invalid descriptions class delta accepted')
 }
 for invalid in [[description_classes[0], description_classes[0]],
  ['android/accounts/AccountManager.smali', description_classes[0]]] {
  narrow_added_class_delta(old, extended, ['android/accounts/AccountManager.smali'], invalid) or { continue }
  return error('duplicate or preexisting descriptions class addition accepted')
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
 protected_storage_self_test()!
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

// Narrow follow-ups retain the complete pinned class set and allow only their
// named method deltas. The original combined build keeps its historical ABI.
fn build_narrow(profile NarrowProfile, baseline string, manifest_pin string, jar_pin string, root string) ! {
 if baseline != state + profile.baseline_name
  || manifest_pin != profile.manifest_pin || jar_pin != profile.jar_pin
  || os.real_path(baseline) != baseline || !root.starts_with(state + 'combined-account-webview-' + profile.name + '-')
  || os.real_path(os.dir(root)) != os.dir(root) || os.exists(root) || os.is_link(root)
  || root.contains_any(' \n\t') {
  return error('exact sealed baseline and fresh external narrow output required')
 }
 if digest(store_compiler)! != store_compiler_pin || digest(baseline + '/api-impl.jar')! != jar_pin {
  return error('store compiler or interaction JAR pin differs')
 }
 sealed_baseline(baseline, manifest_pin)!
 os.mkdir_all(root + '/commands')!
 command(root, 'builder-self-test', [os.executable(), '--self-test'])!
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
 helper := repo + '/tests/native-android-tools/androidtools/framework.v'
 inputs[helper] = digest(helper)!
 for name in profile.providers {
  provider := repo + '/tests/native-android-tools/androidtools/' + name
  inputs[provider] = digest(provider)!
  os.cp(provider, root + '/provider-source/androidtools/' + name)!
  if digest(root + '/provider-source/androidtools/' + name)! != inputs[provider]! {
   return error('provider copy differs: ' + name)
  }
 }
 os.cp(helper, root + '/provider-helper-inputs/framework.v')!
 if digest(root + '/provider-helper-inputs/framework.v')! != inputs[helper]! {
  return error('provider helper copy differs')
 }
 os.write_file(root + '/provider-source/androidtools/framework_account_helpers.v',
  'module androidtools\n' + helper_function(os.read_file(root + '/provider-helper-inputs/framework.v')!, 'pub fn framework_replace_method(')!)!
 mut application := 'module main\nimport androidtools\nimport os\nfn main() {\n'
 mut targets := profile.methods.keys()
 targets.sort()
 if profile.directory_provider != '' {
  if profile.calls.len != 0 { return error('directory provider cannot also have per-class calls') }
  application += 'androidtools.' + profile.directory_provider + '(os.args[1])!\n'
 } else {
  if profile.calls.len != targets.len { return error('narrow calls differ from explicit method targets') }
  for i, target in targets {
   name := 'path' + i.str()
   application += name + ' := os.args[1] + "/' + target + '"\n' +
    'os.write_file(' + name + ',androidtools.' + profile.calls[target]! + '(os.read_file(' + name + ')!)!)!\n'
  }
 }
 if profile.class_provider != '' {
  application += 'classes := androidtools.' + profile.class_provider + '()\n' +
   'expected := ' + json2.encode(profile.extra_classes.map(it.all_before_last('.smali'))) + '\n' +
   'if classes.len != expected.len { panic("unexpected added class count") }\n' +
   'for name, source in classes {\nif name !in expected { panic("unexpected added class") }\n' +
   'path := os.args[1] + "/" + name + ".smali"\n' +
   'if os.exists(path) { panic("added class already exists") }\n' +
   'os.mkdir_all(os.dir(path))!\nos.write_file(path, source)!\n}\n'
 } else if profile.extra_classes.len != 0 { return error('class additions require an explicit provider') }
 os.write_file(root + '/provider-source/main.v', application + '}\n')!
 os.setenv('VROOT', os.dir(store_compiler), true)
 os.setenv('V', store_compiler, true)
 os.setenv('VINIX_V_COMPILER', store_compiler, true)
 command(root, 'java-version', [java, '--version'])!
 command(root, 'v-version', [store_compiler, 'version'])!
 driver_closure := freeze_closure(root, command(root, 'builder-closure', [store_compiler, '-print-v-files', source_file])!, 'builder-closure-inputs')!
 // Smali has a small worker pool and fixed heap even on hosts with large RAM.
 command(root, 'old-disassemble', [java, '-Xmx512m', '-XX:ActiveProcessorCount=2', '-cp', classpath.join(':'), 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', baseline + '/api-impl.jar', '-o', root + '/old-dex'])!
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
 narrow_profile_class_delta(old, applied, targets, profile.extra_classes, profile.baseline_classes)!
 for target in targets {
  narrow_member_delta(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/smali/' + target)!,
   profile.methods[target]!, profile.changed[target]!, profile.added[target]!, profile.fields[target] or { []string{} })!
 }
 command(root, 'assemble', [java, '-Xmx512m', '-XX:ActiveProcessorCount=2', '-cp', classpath.join(':'), 'org.jf.smali.Main', 'assemble', '--jobs', '2', root + '/smali', '-o', root + '/classes.dex'])!
 if !os.is_file(root + '/classes.dex') || os.file_size(root + '/classes.dex') < 112 { return error('store assembly produced no fresh DEX') }
 command(root, 'replace-dex', ['/usr/bin/zip', '-q', '-j', root + '/api-impl.jar', root + '/classes.dex'])!
 command(root, 'new-disassemble', [java, '-Xmx512m', '-XX:ActiveProcessorCount=2', '-cp', classpath.join(':'), 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', root + '/api-impl.jar', '-o', root + '/new-dex'])!
 mut new := map[string]string{}
 inventory(root + '/new-dex', '', mut new)!
 narrow_profile_class_delta(old, new, targets, profile.extra_classes, profile.baseline_classes)!
 for target in targets {
  narrow_member_delta(os.read_file(root + '/old-dex/' + target)!, os.read_file(root + '/new-dex/' + target)!,
   profile.methods[target]!, profile.changed[target]!, profile.added[target]!, profile.fields[target] or { []string{} })!
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
 for path, pin in driver_closure { if digest(path)! != pin { return error('store builder source changed: ' + path) } }
 for path, pin in inputs { if digest(path)! != pin { return error('store input changed: ' + path) } }
 write_json(root + '/build.json', {
  'scope': json2.Any('Narrow ' + profile.name + ' provider delta over exact sealed framework; host assembly only, no guest or Google login proof'),
  'profile': json2.Any(profile.name + '-' + new.len.str()),
  'source_revision': json2.Any(command(root, 'revision', ['/usr/bin/git', '-C', repo, 'rev-parse', 'HEAD'])!.trim_space()),
  'input_sha256': json2.decode[json2.Any](json2.encode(inputs))!,
  'baseline_path': json2.Any(baseline), 'baseline_manifest_sha256': json2.Any(manifest_pin),
  'baseline_api_impl_sha256': json2.Any(jar_pin), 'api_impl_sha256': json2.Any(digest(root + '/api-impl.jar')!),
  'classes_dex_sha256': json2.Any(digest(root + '/classes.dex')!),
  'changed_classes': json2.Any(targets), 'added_classes': json2.Any(profile.extra_classes),
  'class_count': json2.Any(new.len), 'compiler_sha256': json2.Any(store_compiler_pin),
  'changed_method_counts': json2.decode[json2.Any](json2.encode(profile.changed))!,
  'added_method_counts': json2.decode[json2.Any](json2.encode(profile.added))!,
  'added_fields': json2.decode[json2.Any](json2.encode(profile.fields))!,
  'environmental_inputs': json2.Any('Host SDK and dynamic libraries are environmental dependencies; exact V source closures, compiler and smali tool JARs retained and checked')
 })!
 mut pins := map[string]string{}
 inventory(root, '', mut pins)!
 write_json(root + '/sha256.json', pins)!
 sealed_baseline(root, digest(root + '/sha256.json')!)!
 println('NARROW-FRAMEWORK-BUILD-PASS profile=' + profile.name + ' classes=' + new.len.str() + ' jar=' + root + '/api-impl.jar')
 println('NARROW-FRAMEWORK-BUILD-MANIFEST-SHA256 ' + digest(root + '/sha256.json')!)
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
 if os.args.len == 6 && os.args[1] in ['--store', '--auth', '--cache', '--descriptions', '--protected-storage'] {
  profile := match os.args[1] { '--store' { storage_profile() } '--auth' { auth_profile() } '--cache' { cache_profile() } '--descriptions' { descriptions_profile() } else { protected_storage_profile() } }
  build_narrow(profile, os.abs_path(os.args[2]), os.args[3], os.args[4], os.abs_path(os.args[5])) or { eprintln(err); exit(1) }
  return
 }
 if os.args.len != 5 { eprintln('usage: combined-account-webview-build [--store|--auth|--cache|--descriptions|--protected-storage] BASELINE BASELINE_MANIFEST_SHA256 BASELINE_JAR_SHA256 FRESH_OUTPUT | --self-test'); exit(2) }
 build(os.abs_path(os.args[1]), os.args[2], os.args[3], os.abs_path(os.args[4])) or { eprintln(err); exit(1) }
}
