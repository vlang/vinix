// SPDX-License-Identifier: GPL-2.0-or-later
// Same-APK ART comparison of virtual ViewParent requestLayout dispatch.
module main

import androidtools
import json2
import os
import startupfixture
import time

#include <CommonCrypto/CommonDigest.h>
@[typedef]
struct C.CC_SHA256_CTX {}
fn C.CC_SHA256_Init(voidptr) i32
fn C.CC_SHA256_Update(voidptr, voidptr, u32) i32
fn C.CC_SHA256_Final(&u8, voidptr) i32

const state = '/Users/alex/.local/state/vinix/android/layout-parent-dispatch336-v3-2026-10-25'
const baseline = '/Users/alex/.local/state/vinix/android/system-package330-fixture-2026-10-25'
const baseline_seal = '65cc180e2298fd76ea1d1dbffebe626f2c290b9ba33b8811c9b367ffa5c73c17'
const framework = '/Users/alex/.local/state/vinix/android/layout-request332-framework-build-2026-10-25'
const framework_seal = '6f3d2a9ebcffa24cb61b4a765abb866d90914e96363af241e7cd67a5387d20cf'
const framework329 = '/Users/alex/.local/state/vinix/android/system-package329-framework-build-2026-10-25'
const framework329_seal = '4f526669c32b91db3da92d3508b6aa97297d8a8b48b89fef29f6cd3f1f64559e'
const old_framework = '0229315058b2d24f1f84d886fc47b3fab6fd3b0b7cc7c32f0b9771908276d9ca'
const launcher = '406b187bb0ef8f42c57cc26532abae6599b837b5b0226da7afd23fcda8ca67a0'
const compiler = '/Users/alex/code/vinix/build/android-maps/queue284-tools/v_old276'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const source_name = 'layout-parent-dispatch-run.v'
const java = '/opt/homebrew/Cellar/openjdk@25/25.0.4.1/libexec/openjdk.jdk/Contents/Home/bin/java'
const manual_pass = 'BOOTSTRAP-LAYOUT-REQUESTS-PASS measure size layout listener next-measure stable-cache pending-child-propagation'
const view_key = 'android/view/View.smali'

fn hash(path string) !string {
 mut input := os.open(path)!
 defer { input.close() }
 mut buffer := []u8{len: 1024 * 1024}
 mut digest := C.CC_SHA256_CTX{}
 assert C.CC_SHA256_Init(unsafe { &digest }) == 1
 for {
  n := input.read(mut buffer) or { if err is os.Eof { break }; return err }
  if n == 0 { break }
  assert C.CC_SHA256_Update(unsafe { &digest }, buffer.data, u32(n)) == 1
 }
 mut sum := [32]u8{}
 assert C.CC_SHA256_Final(unsafe { &sum[0] }, unsafe { &digest }) == 1
 return sum[..].hex()
}

fn write_json[T](path string, value T) ! {
 os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn clone(from string, to string) ! {
 assert !os.exists(to) && !os.is_link(to), to
 os.mkdir_all(os.dir(to))!
 r := os.exec(['/bin/cp', '-c', '-R', os.real_path(from), to])
 assert r.exit_code == 0, r.output
}

fn inventory(root string, prefix string, mut files map[string]string) ! {
 for name in os.ls(root + '/' + prefix)! {
  key := if prefix == '' { name } else { prefix + '/' + name }
  match os.lstat(root + '/' + key)!.get_filetype() {
   .directory { inventory(root, key, mut files)! }
   .regular { files[key] = hash(root + '/' + key)! }
   else { return error('nonregular evidence entry: ' + key) }
  }
 }
}

fn manifest(root string, seal string) !map[string]string {
 assert hash(root + '/sha256.json')! == seal, root
 return json2.decode[map[string]string](os.read_file(root + '/sha256.json')!)!
}

fn reference(root string, pins map[string]string, key string, target string) ! {
 assert hash(root + '/' + key)! == pins[key]!, key
 clone(root + '/' + key, target)!
 assert hash(target)! == pins[key]!, target
}

fn tree(root string, pins map[string]string, key string, target string) ! {
 mut expected := map[string]string{}
 for name, pin in pins {
  if name.starts_with(key + '/') { expected[name.all_after(key + '/')] = pin }
 }
 mut actual := map[string]string{}
 inventory(root + '/' + key, '', mut actual)!
 assert actual == expected && expected.len > 0, key
 clone(root + '/' + key, target)!
 actual.clear()
 inventory(target, '', mut actual)!
 assert actual == expected, target
}

fn record(label string, argv []string) ! {
 assert !os.exists(state + '/commands/' + label + '.json'), label
 pin := hash(os.real_path(argv[0]))!
 started := time.utc().str()
 r := os.exec(argv)
 os.write_file(state + '/commands/' + label + '.log', r.output)!
 write_json(state + '/commands/' + label + '.json', {
  'argv': json2.Any(argv)
  'started_utc': json2.Any(started)
  'completed_utc': json2.Any(time.utc().str())
  'exit_code': json2.Any(r.exit_code)
  'executable_sha256': json2.Any(pin)
 })!
 assert hash(os.real_path(argv[0]))! == pin
 if !label.ends_with('-closure') { print(r.output) }
 assert r.exit_code == 0, label
}

fn paths() string {
 return state + '/source|tests/host-policy|tests/linuxkpi|tests/native-generators|tests/native-guest-tools|build-support|tools|@vlib|@vmodules'
}

fn closure(label string) !map[string]string {
 record(label + '-closure', [compiler, '-path', paths(), '-print-v-files', state + '/source/' + source_name])!
 mut pins := map[string]string{}
 for path in os.read_lines(state + '/commands/' + label + '-closure.log')!.filter(it.ends_with('.v')) {
  pins[path] = hash(path)!
  target := state + '/closure-inputs/' + path.trim_left('/')
  if os.exists(target) { assert hash(target)! == pins[path]!, path }
  else { clone(path, target)! }
 }
 assert pins.len > 0
 write_json(state + '/' + label + '-v-files.json', pins)!
 return pins
}

fn disk(label string, minimum_mib u64) ! {
 r := os.exec(['/bin/df', '-k', state])
 assert r.exit_code == 0
 available := r.output.trim_space().split_into_lines().last().fields()[3].u64()
 write_json(state + '/disk-' + label + '.json', {'minimum_mib': json2.Any(minimum_mib),
  'available_kib': json2.Any(available), 'utc': json2.Any(time.utc().str()), 'raw': json2.Any(r.output)})!
 assert available >= minimum_mib * 1024
}

fn host_inputs(config map[string]json2.Any) !map[string]string {
 mut pins := map[string]string{}
 for key in ['aapt2', 'apksigner', 'firmware', 'input_tool', 'java', 'qemu'] {
  path := os.real_path(config[key]!.str())
  pins[path] = hash(path)!
 }
 pins[compiler] = hash(compiler)!
 assert pins[compiler]! == compiler_pin
 pins[os.real_path('/usr/bin/cc')] = hash(os.real_path('/usr/bin/cc'))!
 return pins
}

fn stable() !map[string]string {
 mut pins := map[string]string{}
 for dir in ['native-old', 'native-new', 'fixture-inputs', 'tools', 'source',
  'closure-inputs', 'generated-c', 'apk', 'framework'] {
  mut files := map[string]string{}
  inventory(state + '/' + dir, '', mut files)!
  for key, pin in files { pins[dir + '/' + key] = pin }
 }
 for key in ['base-runtime.tar', 'config.json', 'host-inputs.json', 'initial-media.json',
  'initial-media/boot.img', 'initial-media/efivars.fd'] { pins[key] = hash(state + '/' + key)! }
 return pins
}

fn runtime_delta() ! {
 mut old := map[string]string{}
 mut new := map[string]string{}
 inventory(state + '/native-old', '', mut old)!
 inventory(state + '/native-new', '', mut new)!
 assert old['popular-launcher']! == launcher
 assert old['api-impl.jar']! == old_framework
 assert new['api-impl.jar']! == hash(state + '/framework/api-impl.jar')!
 old.delete('api-impl.jar')
 new.delete('api-impl.jar')
 assert old == new, 'framework JAR must be the only guest runtime delta'
 write_json(state + '/native-common.json', old)!
}

fn prepare() ! {
 assert !os.exists(state) && !os.is_link(state), 'fresh external output required'
 os.mkdir_all(state + '/commands')!
 disk('prepare', 1536)!
 bp := manifest(baseline, baseline_seal)!
 fp := manifest(framework, framework_seal)!
 p329 := manifest(framework329, framework329_seal)!
 clone(baseline + '/sha256.json', state + '/qualified330-sha256.json')!
 clone(framework + '/sha256.json', state + '/qualified332-sha256.json')!
 clone(framework329 + '/sha256.json', state + '/qualified329-sha256.json')!
 clone('tests/native-android-ws/' + source_name, state + '/source/' + source_name)!
 clone('tests/native-android-ws/startupfixture', state + '/source/startupfixture')!
 tree(framework, fp, 'framework/sources/androidtools', state + '/source/androidtools')!
 for name in ['framework_layout_requests.v', 'framework_layout_listeners.v'] {
  os.rm(state + '/source/androidtools/' + name)!
  clone('tests/native-android-tools/androidtools/' + name, state + '/source/androidtools/' + name)!
 }
 clone(os.executable(), state + '/tools/bootstrap')!
 for name in ['tools/suite', 'tools/inflater-trace-seal', 'source/inflater-trace-seal.v',
  'source/suite.v', 'base-runtime.tar', 'initial-media.json', 'initial-media/boot.img',
  'initial-media/efivars.fd'] { reference(baseline, bp, name, state + '/' + name)! }
 for name in ['source/suite-support', 'fixture-inputs'] { tree(baseline, bp, name, state + '/' + name)! }
 for kind in ['old', 'new'] { tree(baseline, bp, 'native-new', state + '/native-' + kind)! }
 tree(framework, fp, 'framework/smali', state + '/framework/smali')!
 tree(framework, fp, 'tools/framework', state + '/tools/framework')!
 reference(framework, fp, 'framework/api-impl.jar', state + '/framework/api-impl.jar')!
 reference(framework329, p329, 'framework/smali/' + view_key, state + '/framework/View329.smali')!
 reference(framework, fp, 'framework/smali/' + view_key, state + '/framework/View332.smali')!
 reference(baseline, bp, 'config.json', state + '/qualified330-config.json')!
 mut config := json2.decode[map[string]json2.Any](os.read_file(state + '/qualified330-config.json')!)!
 config['java'] = java
 config['applications'] = json2.Any([json2.Any({
  'apk': json2.Any(state + '/apk/probe.apk'), 'distribution': json2.Any('Vinix regression fixture'),
  'id': json2.Any('bootstrap-fixture'), 'name': json2.Any('Virtual parent layout request fixture'),
  'package': json2.Any('org.vinix.bootstrap'), 'source': json2.Any(state + '/source/' + source_name),
  'startup_seconds': json2.Any(45),
 })])
 config['base_module'] = state + '/base-runtime.tar'
 write_json(state + '/config.json', config)!
 write_json(state + '/host-inputs.json', host_inputs(config)!)!
 os.mkdir_all(state + '/generated-c')!
 os.setenv('VTMP', state + '/generated-c', true)
 before := closure('runner-before')!
 record('compile-runner', [compiler, '-nocache', '-keepc', '-showcc', '-cc', 'cc', '-enable-globals',
  '-path', paths(), '-o', state + '/tools/checked-runner', state + '/source/' + source_name])!
 after := closure('runner-after')!
 assert before == after
 record('build-framework', [state + '/tools/checked-runner', 'framework'])!
 record('build-apk', [state + '/tools/checked-runner', 'apk'])!
 for kind in ['old', 'new'] {
  os.rm(state + '/native-' + kind + '/api-impl.jar')!
  clone(if kind == 'old' { state + '/framework-old.jar' } else { state + '/framework/api-impl.jar' }, state + '/native-' + kind + '/api-impl.jar')!
 }
 runtime_delta()!
 write_json(state + '/shared-inputs.json', stable()!)!
 println('PARENT-DISPATCH-PREPARED')
}

fn methods(text string) !map[string]string {
 mut result := map[string]string{}
 for block in text.split('\n.method ')[1..] {
  declaration := '.method ' + block.all_before('\n')
  assert declaration !in result
  end := block.index('.end method') or { return error('unterminated method') }
  result[declaration] = '.method ' + block[..end + '.end method'.len]
 }
 return result
}

fn build_framework() ! {
 original := os.read_file(state + '/framework/View329.smali')!
 old := os.read_file(state + '/framework/View332.smali')!
 generated := androidtools.framework_layout_requests(original)!
 om := methods(old)!
 gm := methods(generated)!
 request := '.method public requestLayout()V'
 assert gm.len == om.len && gm.len == 429
 mut delta := []string{}
 for key, body in om {
  assert key in gm
  if gm[key]! != body { delta << key }
 }
 assert delta == [request], delta.str()
 assert generated == old.replace(om[request]!, gm[request]!), 'non-method change in View'
 os.write_file(state + '/framework/smali/' + view_key, generated)!
 parent_guards()!
 androidtools.framework_layout_request_parents(state + '/framework/smali')!
 clone(state + '/framework/api-impl.jar', state + '/framework-old.jar')!
 record('framework-assemble', [java, '-cp', state + '/tools/framework/*', 'org.jf.smali.Main',
  'assemble', '--jobs', '2', state + '/framework/smali', '-o', state + '/framework/classes.dex'])!
 record('framework-zip', ['/usr/bin/zip', '-q', '-j', state + '/framework/api-impl.jar', state + '/framework/classes.dex'])!
 for kind in ['old', 'new'] {
  jar := if kind == 'old' { state + '/framework-old.jar' } else { state + '/framework/api-impl.jar' }
  record('framework-' + kind + '-disassemble', [java, '-cp', state + '/tools/framework/*', 'org.jf.baksmali.Main',
   'disassemble', '--jobs', '2', jar, '-o', state + '/framework/' + kind + '-dex'])!
 }
 mut old_classes := map[string]string{}
 mut new_classes := map[string]string{}
 inventory(state + '/framework/old-dex', '', mut old_classes)!
 inventory(state + '/framework/new-dex', '', mut new_classes)!
 assert old_classes.len == 2068 && old_classes.len == new_classes.len
 mut changed := []string{}
 for key, pin in old_classes {
  assert key in new_classes
  if new_classes[key]! != pin { changed << key }
 }
 changed.sort()
 assert changed == [view_key, 'android/view/ViewParent.smali', 'android/view/WindowManagerImpl$WindowViewParent.smali'], changed.str()
 old_methods := methods(os.read_file(state + '/framework/old-dex/' + view_key)!)!
 new_methods := methods(os.read_file(state + '/framework/new-dex/' + view_key)!)!
 assert old_methods.len == new_methods.len
 mut changed_methods := []string{}
 for key, body in old_methods { if new_methods[key]! != body { changed_methods << key } }
 assert changed_methods == [request], changed_methods.str()
 assert new_methods[request]!.contains('invoke-interface')
 for key in ['android/view/ViewParent.smali', 'android/view/WindowManagerImpl$WindowViewParent.smali'] {
  old_source := os.read_file(state + '/framework/old-dex/' + key)!
  new_source := os.read_file(state + '/framework/new-dex/' + key)!
  before := methods(old_source)!
  after := methods(new_source)!
  assert after.len == before.len + 1
  added := if key.ends_with('/ViewParent.smali') { '.method public abstract requestLayout()V' } else { request }
  assert added in after
  for signature, body in before { assert after[signature]! == body, key + ' ' + signature }
  assert new_source.replace(after[added]!, '').split_into_lines().filter(it.trim_space() != '').join('\n') ==
   old_source.split_into_lines().filter(it.trim_space() != '').join('\n'), 'unexpected parent class changes: ' + key
 }
 write_json(state + '/framework/dex-delta.json', {
  'old_jar_sha256': json2.Any(hash(state + '/framework-old.jar')!),
  'new_jar_sha256': json2.Any(hash(state + '/framework/api-impl.jar')!),
  'class_count': json2.Any(old_classes.len), 'changed_classes': json2.Any(changed),
  'view_method_count': json2.Any(new_methods.len), 'changed_methods': json2.Any(changed_methods),
  'scope': json2.Any('Complete assembled framework DEX compared after disassembly. View.requestLayout changes; ViewParent and the window parent each add requestLayout. No other methods/classes change. No ART execution asserted here.'),
 })!
}

fn parent_guards() ! {
 parent_key := 'android/view/ViewParent.smali'
 root_key := 'android/view/WindowManagerImpl$WindowViewParent.smali'
 parent := os.read_file(state + '/framework/smali/' + parent_key)!
 root := os.read_file(state + '/framework/smali/' + root_key)!
 mut rejected := []string{}
 for name in ['duplicate', 'bad-interface', 'bad-root', 'missing-root-interface'] {
  dir := state + '/framework/guards/' + name
  os.mkdir_all(dir + '/android/view')!
  first := if name == 'bad-interface' { parent.replace('.class public interface abstract', '.class public abstract') } else { parent }
  second := if name == 'bad-root' { root.replace('.class Landroid/view/WindowManagerImpl$WindowViewParent;', '.class Landroid/view/OtherParent;') }
   else if name == 'missing-root-interface' { root.replace('.implements Landroid/view/ViewParent;\n', '') } else { root }
  os.write_file(dir + '/' + parent_key, first)!
  os.write_file(dir + '/' + root_key, second)!
  if name == 'duplicate' { androidtools.framework_layout_request_parents(dir)! }
  before := [hash(dir + '/' + parent_key)!, hash(dir + '/' + root_key)!]
  mut failed := false
  androidtools.framework_layout_request_parents(dir) or { failed = true }
  assert failed, name
  assert before == [hash(dir + '/' + parent_key)!, hash(dir + '/' + root_key)!], 'guard partially mutated files: ' + name
  rejected << name
 }
 write_json(state + '/framework/parent-guard-check.json', {'rejected_without_mutation': rejected})!
}

fn method(signature string, body string, locals int) string {
 return '.method ' + signature + '\n.locals ' + locals.str() + '\n' + body + '\n.end method\n'
}

fn build_apk() ! {
 dir := state + '/apk'
 root := dir + '/smali/org/vinix/bootstrap'
 os.mkdir_all(root)!
 startupfixture.install_layout_request_probe(root)!
 startupfixture.install_layout_parent_dispatch_probe(root)!
 os.write_file(root + '/Main.smali', '.class public Lorg/vinix/bootstrap/Main;\n.super Landroid/app/Activity;\n' +
  method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void', 0) +
  method('public onCreate(Landroid/os/Bundle;)V', '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
invoke-static {p0}, Lorg/vinix/bootstrap/LayoutRequestProbe;->check(Landroid/content/Context;)V
:try_start
invoke-static {p0}, Lorg/vinix/bootstrap/LayoutParentDispatchProbe;->check(Landroid/content/Context;)V
:try_end
.catch Ljava/lang/Throwable; {:try_start .. :try_end} :failed
new-instance v0, Landroid/view/View;
invoke-direct {v0, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "PARENT-DISPATCH-PASS"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:failed
move-exception v2
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "PARENT-DISPATCH-FAIL"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
throw v2', 3))!
 os.mkdir_all(dir + '/res/values')!
 os.write_file(dir + '/res/values/values.xml', '<resources><string name="app_name">Parent dispatch fixture</string></resources>')!
 os.write_file(dir + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="26" android:targetSdkVersion="35"/><application android:label="Parent dispatch fixture"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
 tools := state + '/fixture-inputs'
 record('apk-resources', [tools + '/aapt2', 'compile', '--dir', dir + '/res', '-o', dir + '/resources.zip'])!
 record('apk-link', [tools + '/aapt2', 'link', '-I', tools + '/framework-res.apk', '--manifest', dir + '/AndroidManifest.xml', '-o', dir + '/unsigned.apk', dir + '/resources.zip'])!
 record('apk-smali', [java, '-cp', tools + '/smali/*', 'org.jf.smali.Main', 'assemble', '--jobs', '2', dir + '/smali', '-o', dir + '/classes.dex'])!
 record('apk-zip', ['/usr/bin/zip', '-q', '-j', dir + '/unsigned.apk', dir + '/classes.dex'])!
 record('apk-key', [os.dir(java) + '/keytool', '-genkeypair', '-keystore', dir + '/fixture.p12', '-storetype', 'PKCS12', '-alias', 'fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650', '-dname', 'CN=Vinix parent dispatch fixture', '-storepass', 'android', '-keypass', 'android'])!
 record('apk-sign', [java, '-jar', tools + '/apksigner.jar', 'sign', '--ks', dir + '/fixture.p12', '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', dir + '/probe.apk', dir + '/unsigned.apk'])!
 record('apk-verify', [java, '-jar', tools + '/apksigner.jar', 'verify', '--verbose', dir + '/probe.apk'])!
 record('apk-disassemble', [java, '-cp', tools + '/smali/*', 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', dir + '/probe.apk', '-o', dir + '/signed-dex'])!
 mut classes := map[string]string{}
 inventory(dir + '/signed-dex', '', mut classes)!
 assert classes.len == 6
 write_json(dir + '/executed-fixture-dex.json', {'signed_apk_sha256': json2.Any(hash(dir + '/probe.apk')!),
  'signed_dex_classes': json2.decode[json2.Any](json2.encode(classes))!,
  'scope': json2.Any('All six classes disassembled from actual signed APK; assembly alone does not assert ART execution.')})!
}

fn run(kind string) ! {
 assert kind in ['old', 'new']
 assert !os.exists(state + '/sha256.json'), 'sealed evidence is immutable'
 assert hash(os.executable())! == hash(state + '/tools/checked-runner')!
 before := stable()!
 assert before == json2.decode[map[string]string](os.read_file(state + '/shared-inputs.json')!)!
 runtime_delta()!
 disk(kind, 1024)!
 mut removed := []string{}
 for key, _ in os.environ() {
  if key.starts_with('VINIX_ANDROID_TRACE_') || key == 'ATL_UGLY_ENABLE_LOCATION' { removed << key; os.unsetenv(key) }
 }
 write_json(state + '/' + kind + '-environment.json', {'removed_host_variables': removed})!
 output := state + '/run-' + kind
 alias := os.abs_path('build/android-maps/lp336v3-' + kind)
 assert !os.exists(alias) && !os.is_link(alias) && !os.exists(output)
 os.mkdir_all(output)!
 os.symlink(output, alias)!
 media := json2.decode[map[string]string](os.read_file(state + '/initial-media.json')!)!
 for file in ['boot.img', 'efivars.fd'] {
  assert hash(state + '/initial-media/' + file)! == media[file]!
  clone(state + '/initial-media/' + file, state + '/vm-' + kind + '/' + file)!
 }
 mut config := json2.decode[map[string]json2.Any](os.read_file(state + '/config.json')!)!
 assert host_inputs(config)! == json2.decode[map[string]string](os.read_file(state + '/host-inputs.json')!)!
 config['output'] = alias
 config['native_dir'] = state + '/native-' + kind
 config['boot_image'] = state + '/vm-' + kind + '/boot.img'
 config['efivars'] = state + '/vm-' + kind + '/efivars.fd'
 write_json(state + '/' + kind + '.json', config)!
 write_json(state + '/' + kind + '-inputs-before.json', before)!
 record('suite-' + kind, [state + '/tools/suite', state + '/' + kind + '.json'])!
 assert stable()! == before
 assert host_inputs(config)! == json2.decode[map[string]string](os.read_file(state + '/host-inputs.json')!)!
 write_json(state + '/' + kind + '-inputs-after.json', stable()!)!
 check(kind, state + '/' + kind + '-semantic-check.json')!
}

fn check(kind string, receipt string) ! {
 assert kind in ['old', 'new']
 assert !os.exists(state + '/sha256.json') && !os.exists(receipt)
 expected_inputs := json2.decode[map[string]string](os.read_file(state + '/shared-inputs.json')!)!
 assert stable()! == expected_inputs
 for phase in ['before', 'after'] {
  assert json2.decode[map[string]string](os.read_file(state + '/' + kind + '-inputs-' + phase + '.json')!)! == expected_inputs
 }
 output := state + '/run-' + kind
 log := os.read_file(output + '/bootstrap-fixture/serial.log')!
 lines := log.split_into_lines().map(it.trim_space())
 raw := json2.decode[[]map[string]json2.Any](os.read_file(output + '/results.json')!)!
 assert raw.len == 1 && raw[0]['id']!.str() == 'bootstrap-fixture'
 assert raw[0]['container_sha256']!.str() == hash(state + '/apk/probe.apk')!
 assert raw[0]['launcher_entered']!.bool() && raw[0]['native_maps_observed']!.bool()
 assert lines.filter(it == manual_pass).len == 1, '332 callback and pending-child tests must pass first'
 assert raw[0]['functional_passed']! is json2.Null
 if kind == 'old' {
  assert lines.filter(it == 'PARENT-DISPATCH-FAIL').len == 1 && !log.contains('PARENT-DISPATCH-PASS')
  assert log.count('java.lang.AssertionError:') == 1
  assert log.contains('descendant request bypassed parent override'), log
  assert raw[0]['outcome']!.str() == 'startup_failed' && raw[0]['process_exited']!.bool()
 } else {
  assert lines.filter(it == 'PARENT-DISPATCH-PASS').len == 1 && !log.contains('PARENT-DISPATCH-FAIL')
  assert lines.filter(it == 'BOOTSTRAP-LAYOUT-PARENT-DISPATCH-PASS intercept repeated-pending forward ancestor next-measure window-root').len == 1
  assert !log.contains('AssertionError') && !log.contains('ANDROID-WS-FAIL')
  assert raw[0]['outcome']!.str() == 'window_observed' && !raw[0]['process_exited']!.bool()
 }
 for bad in ['NoSuchMethodError', 'NoSuchFieldError', 'NoClassDefFoundError', 'ClassNotFoundException',
  'UnsatisfiedLinkError', 'VerifyError', 'JNI DETECTED ERROR', 'ExceptionInInitializerError', 'AbstractMethodError'] { assert !log.contains(bad), bad }
 write_json(receipt, {
  'variant': kind, 'status': 'expected-result-pass', 'serial_sha256': hash(output + '/bootstrap-fixture/serial.log')!,
  'raw_results_sha256': hash(output + '/results.json')!, 'raw_outcome': raw[0]['outcome']!.str(),
  'checker_binary_sha256': hash(os.executable())!, 'scope': 'Focused actual ART parent override dispatch, interception, forwarding and repeated pending-child regression; prior332 callback probe also executes. No Maps route qualification.',
 })!
 println('PARENT-DISPATCH-' + kind.to_upper() + '-EXPECTED-RESULT-PASS')
}

fn main() {
 $if prod { panic('assertions required') }
 os.setenv('VROOT', '/Users/alex/code/v', true)
 assert os.args.len == 2
 match os.args[1] {
  'prepare' { prepare()! }
  'framework' { build_framework()! }
  'apk' { build_apk()! }
  'old', 'new' { run(os.args[1])! }
  'qualify' {
   for kind in ['old', 'new'] { check(kind, state + '/qualification/' + kind + '-semantic-check.json')! }
   clone(state + '/qualification/new-semantic-check.json', state + '/new-semantic-check.json')!
  }
  'seal' {
   assert !os.exists(state + '/sha256.json')
   for kind in ['old', 'new'] { assert os.exists(state + '/' + kind + '-semantic-check.json') }
   assert stable()! == json2.decode[map[string]string](os.read_file(state + '/shared-inputs.json')!)!
   runtime_delta()!
   r := os.exec([state + '/tools/inflater-trace-seal', 'seal', state])
   print(r.output)
   assert r.exit_code == 0
  }
  else { panic('prepare | framework | apk | old | new | qualify | seal') }
 }
}
