// SPDX-License-Identifier: GPL-2.0-or-later
// Same-APK ART regression for media exceptions and the original Maps player classes.
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

const state = '/Users/alex/.local/state/vinix/android/media-codec-exceptions349-2026-10-25'
const baseline = '/Users/alex/.local/state/vinix/android/superscript-span346-2026-10-25'
const baseline_seal = '6d5205fce48faea0c406efb68ec9134c039aa106e591d20e4501f2826d65064b'
const old_framework = 'b33472257a59c9b8dffca155c2f1ecd77e0f10c3dae230a23a3afafee9e7c840'
const launcher = '406b187bb0ef8f42c57cc26532abae6599b837b5b0226da7afd23fcda8ca67a0'
const compiler = state + '/frozen/vroot/v'
const compiler_pin = '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e'
const source_name = 'media-codec-exceptions-run.v'
const java = '/opt/homebrew/Cellar/openjdk@25/25.0.4.1/libexec/openjdk.jdk/Contents/Home/bin/java'
const added_classes = ['android/media/MediaCodec$CryptoException.smali', 'android/media/MediaCodec$CodecException.smali', 'android/media/MediaCryptoException.smali']
const changed_class = 'android/media/MediaCodec.smali'
const maps_apk = '/Users/alex/.local/state/vinix/android/maps347-2026-10-25/prelaunch/maps347/module/opt/android-test/application.apk'
const maps_pin = '6218d72f48b184eb71f68879bce48cb9ebb2b510be7f7cff88217ea3fd592bb2'

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
 return state + '/frozen/vroot/source|' + state + '/frozen/checkout/tests/host-policy|' + state + '/frozen/checkout/tests/linuxkpi|' + state + '/frozen/checkout/tests/native-generators|' + state + '/frozen/checkout/tests/native-guest-tools|' + state + '/frozen/checkout/tests/qemu-core|' + state + '/frozen/checkout/tests/native-policy-tools|' + state + '/frozen/checkout/build-support|' + state + '/frozen/checkout/build-support/android|' + state + '/frozen/checkout/tools|' + state + '/frozen/vroot/vlib'
}


fn closure(label string) !map[string]string {
 record(label + '-closure', [compiler, '-path', paths(), '-print-v-files', state + '/frozen/vroot/source/' + source_name])!
 mut pins := map[string]string{}
 for path in os.read_lines(state + '/commands/' + label + '-closure.log')!.filter(it.ends_with('.v')) {
  assert os.real_path(path).starts_with(state + '/'), 'nonfrozen V input: ' + path
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
  'closure-inputs', 'frozen', 'generated-c', 'apk', 'framework', 'maps-sidecar', 'maps-sidecar-readback'] {
  mut files := map[string]string{}
  inventory(state + '/' + dir, '', mut files)!
  for key, pin in files { pins[dir + '/' + key] = pin }
 }
 for key in ['base-runtime.tar', 'base-runtime-qualified346.tar', 'maps-sidecar.json', 'config.json', 'host-inputs.json', 'initial-media.json',
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
 clone(baseline + '/sha256.json', state + '/qualified346-sha256.json')!
 freeze_sources(bp)!
 clone(os.executable(), state + '/tools/bootstrap')!
 for name in ['tools/suite', 'tools/inflater-trace-seal', 'source/inflater-trace-seal.v',
  'source/suite.v', 'base-runtime.tar', 'initial-media.json', 'initial-media/boot.img',
  'initial-media/efivars.fd'] { reference(baseline, bp, name, state + '/' + name)! }
 for name in ['source/suite-support', 'fixture-inputs'] { tree(baseline, bp, name, state + '/' + name)! }
 add_maps_sidecar()!
 for kind in ['old', 'new'] { tree(baseline, bp, 'native-new', state + '/native-' + kind)! }
 tree(baseline, bp, 'framework/smali', state + '/framework/smali')!
 tree(baseline, bp, 'tools/framework', state + '/tools/framework')!
 reference(baseline, bp, 'framework/api-impl.jar', state + '/framework/api-impl.jar')!
 reference(baseline, bp, 'config.json', state + '/qualified346-config.json')!
 mut config := json2.decode[map[string]json2.Any](os.read_file(state + '/qualified346-config.json')!)!
 config['java'] = java
 config['aapt2'] = state + '/fixture-inputs/aapt2'
 config['apksigner'] = state + '/fixture-inputs/apksigner.jar'
 config['applications'] = json2.Any([json2.Any({
  'apk': json2.Any(state + '/apk/probe.apk'), 'distribution': json2.Any('Vinix regression fixture'),
  'id': json2.Any('bootstrap-fixture'), 'name': json2.Any('Media codec exceptions fixture'),
  'package': json2.Any('org.vinix.bootstrap'), 'source': json2.Any(state + '/frozen/vroot/source/' + source_name),
  'startup_seconds': json2.Any(35),
 })])
 config['base_module'] = state + '/base-runtime.tar'
 write_json(state + '/config.json', config)!
 write_json(state + '/host-inputs.json', host_inputs(config)!)!
 os.mkdir_all(state + '/generated-c')!
 os.setenv('VTMP', state + '/generated-c', true)
 os.setenv('VROOT', state + '/frozen/vroot', true)
 os.setenv('VEXE', compiler, true)
 before := closure('runner-before')!
 assert before.len == 642, 'qualified346 closure plus media codec exceptions provider and fixture'
 record('compile-runner', [compiler, '-nocache', '-keepc', '-showcc', '-cc', 'cc', '-enable-globals',
  '-path', paths(), '-o', state + '/tools/checked-runner', state + '/frozen/vroot/source/' + source_name])!
 cc_lines := os.read_lines(state + '/commands/compile-runner.log')!.filter(it.trim_space().starts_with('> cc '))
 assert cc_lines.len > 0
 for line in cc_lines { assert !line.contains('/Users/alex/code/'), 'nonfrozen C compilation input' }
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
 println('MEDIA-CODEC-EXCEPTIONS-PREPARED')
}

fn add_maps_sidecar() ! {
 assert hash(maps_apk)! == maps_pin
 clone(state + '/base-runtime.tar', state + '/base-runtime-qualified346.tar')!
 root := state + '/maps-sidecar'
 key := 'opt/android-test/maps-application.apk'
 clone(maps_apk, root + '/' + key)!
 record('base-module-append-maps', ['/usr/bin/tar', '-rf', state + '/base-runtime.tar', '-C', root, key])!
 record('base-module-list', ['/usr/bin/tar', '-tf', state + '/base-runtime.tar'])!
 lines := os.read_lines(state + '/commands/base-module-list.log')!
 assert lines.filter(it == key).len == 1
 os.mkdir_all(state + '/maps-sidecar-readback')!
 record('base-module-extract-maps', ['/usr/bin/tar', '-xf', state + '/base-runtime.tar', '-C', state + '/maps-sidecar-readback', key])!
 assert hash(state + '/maps-sidecar-readback/' + key)! == maps_pin
 assert hash(maps_apk)! == maps_pin
 write_json(state + '/maps-sidecar.json', {
  'original_maps_apk_sha256': maps_pin,
  'guest_path': '/' + key,
  'qualified346_base_module_sha256': hash(state + '/base-runtime-qualified346.tar')!,
  'base_module_with_maps_sha256': hash(state + '/base-runtime.tar')!,
  'extracted_maps_apk_sha256': hash(state + '/maps-sidecar-readback/' + key)!,
  'scope': 'One original unchanged Maps APK appended to the qualified base module; identical sidecar supplied to old and new framework boots.',
 })!
}

fn media_codec_metadata_only(before string, after string) {
 assert before.count('.annotation system Ldalvik/annotation/MemberClasses;') == 1
 mut restored := after
 for name in ['CodecException', 'CryptoException'] {
  entry := '        Landroid/media/MediaCodec$' + name + ';,\n'
  assert !before.contains(entry) && after.count(entry) == 1, name
  restored = restored.replace(entry, '')
 }
 assert restored == before, 'MediaCodec must differ only by the two member-class annotation entries'
}

fn build_framework() ! {
 root := state + '/framework/smali'
 original_codec := os.read_file(root + '/' + changed_class)!
 mut before := map[string]string{}
 inventory(root, '', mut before)!
 assert before.len == 2070
 for name in added_classes { assert name !in before }
 androidtools.framework_media_codec_exceptions(root)!
 mut after := map[string]string{}
 inventory(root, '', mut after)!
 assert after.len == before.len + 3
 for name in added_classes { assert name in after }
 for key, pin in before {
  if key == changed_class { assert after[key]! != pin; continue }
  assert after[key]! == pin, key
 }
 media_codec_metadata_only(original_codec, os.read_file(root + '/' + changed_class)!)
 mut rejected := false
 androidtools.framework_media_codec_exceptions(root) or { rejected = true }
 mut duplicate := map[string]string{}
 inventory(root, '', mut duplicate)!
 assert rejected && duplicate == after
 write_json(state + '/framework/duplicate-guard.json', {'rejected_without_mutation': rejected})!
 clone(state + '/framework/api-impl.jar', state + '/framework-old.jar')!
 record('framework-assemble', [java, '-cp', state + '/tools/framework/*', 'org.jf.smali.Main',
  'assemble', '--jobs', '2', root, '-o', state + '/framework/classes.dex'])!
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
 assert old_classes.len == 2070 && new_classes.len == 2073
 for name in added_classes { assert name !in old_classes && name in new_classes }
 for key, pin in old_classes {
  if key == changed_class { assert new_classes[key]! != pin; continue }
  assert new_classes[key]! == pin, key
 }
 media_codec_metadata_only(os.read_file(state + '/framework/old-dex/' + changed_class)!,
  os.read_file(state + '/framework/new-dex/' + changed_class)!)
 write_json(state + '/framework/dex-delta.json', {
  'old_jar_sha256': json2.Any(hash(state + '/framework-old.jar')!),
  'new_jar_sha256': json2.Any(hash(state + '/framework/api-impl.jar')!),
  'old_class_count': json2.Any(old_classes.len), 'new_class_count': json2.Any(new_classes.len),
  'added_classes': json2.Any(added_classes), 'changed_existing_classes': json2.Any([changed_class]),
  'scope': json2.Any('Complete framework DEX comparison: three media exception classes added; only existing MediaCodec nested-class metadata changes; other 2069 existing classes remain byte-identical after disassembly.'),
 })!
}


fn freeze_sources(bp map[string]string) ! {
 // Reuse the complete qualified closure, compiler and non-V assets. Nothing
 // beneath frozen support comes from the current checkout or current V tree.
 tree(baseline, bp, 'frozen', state + '/frozen')!
 registry := os.read_file('tests/native-android-tools/androidtools/framework_classes.v')!
 previous_registry := os.read_file(baseline + '/frozen/vroot/source/androidtools/framework_classes.v')!
 assert registry.count('framework_media_codec_exceptions(smali)!') == 1
 assert registry.replace('\n framework_media_codec_exceptions(smali)!', '') == previous_registry,
  'the registry must differ only by the media codec exceptions provider call'
 for name in ['framework_classes.v', 'framework_media_codec_exceptions.v'] {
  target := state + '/frozen/vroot/source/androidtools/' + name
  if os.exists(target) { os.rm(target)! }
  clone('tests/native-android-tools/androidtools/' + name, target)!
 }
 clone('tests/native-android-ws/startupfixture/media_codec_exceptions.v', state + '/frozen/vroot/source/startupfixture/media_codec_exceptions.v')!
 clone('tests/native-android-ws/' + source_name, state + '/frozen/vroot/source/' + source_name)!
 assert hash(baseline + '/runner-before-v-files.json')! == bp['runner-before-v-files.json']!
 originals := json2.decode[map[string]string](os.read_file(baseline + '/runner-before-v-files.json')!)!
 assert originals.len == 640
 for original, pin in originals {
  assert original.starts_with(baseline + '/frozen/'), original
  key := original.all_after(baseline + '/')
  assert bp[key]! == pin
  if key == 'frozen/vroot/source/androidtools/framework_classes.v' { continue }
  assert hash(state + '/' + key)! == pin, key
 }
 assert hash(compiler)! == compiler_pin
 reference(baseline, bp, 'qualified344-frozen-host-assets.json', state + '/qualified346-frozen-host-assets.json')!
}


fn method(signature string, body string, locals int) string {
 return '.method ' + signature + '\n.locals ' + locals.str() + '\n' + body + '\n.end method\n'
}

fn build_apk() ! {
 dir := state + '/apk'
 root := dir + '/smali/org/vinix/bootstrap'
 os.mkdir_all(root)!
 startupfixture.install_media_codec_exceptions_probe(root)!
 os.write_file(root + '/Main.smali', '.class public Lorg/vinix/bootstrap/Main;\n.super Landroid/app/Activity;\n' +
  method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void', 0) +
  method('public onCreate(Landroid/os/Bundle;)V', '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
invoke-static {p0}, Lorg/vinix/bootstrap/MapsMediaVerifier;->check(Landroid/content/Context;)V
invoke-static {}, Lorg/vinix/bootstrap/MediaCodecExceptionProbe;->check()V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Media codec exceptions regression passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
return-void', 2))!
 os.mkdir_all(dir + '/res/values')!
 os.write_file(dir + '/res/values/values.xml', '<resources><string name="app_name">Media codec exceptions fixture</string></resources>')!
 os.write_file(dir + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="26" android:targetSdkVersion="35"/><application android:label="Media codec exceptions fixture"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
 tools := state + '/fixture-inputs'
 record('apk-resources', [tools + '/aapt2', 'compile', '--dir', dir + '/res', '-o', dir + '/resources.zip'])!
 record('apk-link', [tools + '/aapt2', 'link', '-I', tools + '/framework-res.apk', '--manifest', dir + '/AndroidManifest.xml', '-o', dir + '/unsigned.apk', dir + '/resources.zip'])!
 record('apk-smali', [java, '-cp', tools + '/smali/*', 'org.jf.smali.Main', 'assemble', '--jobs', '2', dir + '/smali', '-o', dir + '/classes.dex'])!
 record('apk-zip', ['/usr/bin/zip', '-q', '-j', dir + '/unsigned.apk', dir + '/classes.dex'])!
 record('apk-key', [os.dir(java) + '/keytool', '-genkeypair', '-keystore', dir + '/fixture.p12', '-storetype', 'PKCS12', '-alias', 'fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650', '-dname', 'CN=Vinix media codec exceptions fixture', '-storepass', 'android', '-keypass', 'android'])!
 record('apk-sign', [java, '-jar', tools + '/apksigner.jar', 'sign', '--ks', dir + '/fixture.p12', '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', dir + '/probe.apk', dir + '/unsigned.apk'])!
 record('apk-verify', [java, '-jar', tools + '/apksigner.jar', 'verify', '--verbose', dir + '/probe.apk'])!
 record('apk-disassemble', [java, '-cp', tools + '/smali/*', 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', dir + '/probe.apk', '-o', dir + '/signed-dex'])!
 mut classes := map[string]string{}
 inventory(dir + '/signed-dex', '', mut classes)!
 assert classes.len == 3
 for name in ['Main', 'MapsMediaVerifier', 'MediaCodecExceptionProbe'] {
  assert 'org/vinix/bootstrap/' + name + '.smali' in classes, name
 }
 write_json(dir + '/executed-fixture-dex.json', {'signed_apk_sha256': json2.Any(hash(dir + '/probe.apk')!),
  'signed_dex_classes': json2.decode[json2.Any](json2.encode(classes))!,
  'scope': json2.Any('All three classes disassembled from actual signed APK; assembly alone does not assert ART execution.')})!
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
 alias := os.abs_path('build/android-maps/media-codec349-' + kind)
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
 apk_pin := hash(state + '/apk/probe.apk')!
 assert raw[0]['container_sha256']!.str() == apk_pin
 metadata := raw[0]['metadata']!.as_map()
 assert metadata['apk_sha256']!.str() == apk_pin
 assert raw[0]['staged_apk']!.str() == state + '/apk/probe.apk'
 assert raw[0]['launcher_entered']!.bool() && raw[0]['native_maps_observed']!.bool()
 assert raw[0]['functional_passed']! is json2.Null
 assert raw[0]['startup_seconds']!.int() == 35
 assert lines.filter(it == 'MAPS-PLAYER-VERIFY-BEGIN').len == 1
 if kind == 'old' {
  assert !log.contains('MEDIA-CODEC-EXCEPTIONS-')
  for marker in ['MAPS-PLAYER-HQA-VERIFY-PASS', 'MAPS-PLAYER-HWV-VERIFY-PASS', 'MAPS-PLAYER-VERIFY-PASS'] {
   assert !log.contains(marker), marker
  }
  rejection := 'java.lang.VerifyError: Verifier rejected class hqa: void hqa.V(long, long) failed to verify: void hqa.V(long, long): [0x4CF] copy1 v5<-v3 type=Undefined cat=1'
  assert log.count(rejection) == 1
  assert log.count('java.lang.VerifyError:') == 1
  assert log.contains("(declaration of 'hqa' appears in /opt/android-test/maps-application.apk!classes4.dex)")
  assert lines.filter(it == 'ANDROID-WS-FAIL start activity').len == 1
  assert log.count('ANDROID-WS-FAIL') == 1
  assert raw[0]['outcome']!.str() == 'startup_failed' && raw[0]['process_exited']!.bool()
 } else {
  mut position := log.index('MAPS-PLAYER-VERIFY-BEGIN') or { panic('missing Maps verification start') }
  for marker in ['MAPS-PLAYER-HQA-VERIFY-PASS', 'MAPS-PLAYER-HWV-VERIFY-PASS', 'MAPS-PLAYER-VERIFY-PASS',
   'MEDIA-CODEC-EXCEPTIONS-METADATA-PASS', 'MEDIA-CODEC-EXCEPTIONS-CRYPTO-PASS',
   'MEDIA-CODEC-EXCEPTIONS-CODECCASES-PASS', 'MEDIA-CODEC-EXCEPTIONS-PASS'] {
   assert lines.filter(it == marker).len == 1, marker
   next := log.index(marker) or { panic('missing marker: ' + marker) }
   assert next > position, marker
   position = next
  }
  assert !log.contains('VerifyError')
  assert !log.contains('ANDROID-WS-FAIL')
  assert raw[0]['outcome']!.str() == 'window_observed' && !raw[0]['process_exited']!.bool()
  assert raw[0]['observation_elapsed_seconds']!.int() >= 35
  assert raw[0]['qemu_alive_before_capture']!.bool()
  assert raw[0]['failure_markers']!.as_array().len == 0
 }
 for bad in ['AssertionError', 'NoClassDefFoundError', 'ClassNotFoundException', 'NoSuchFieldError', 'NoSuchMethodError',
  'UnsatisfiedLinkError', 'JNI DETECTED ERROR', 'ExceptionInInitializerError', 'AbstractMethodError'] { assert !log.contains(bad), bad }
 os.mkdir_all(os.dir(receipt))!
 write_json(receipt, {
  'variant': kind, 'status': 'expected-result-pass', 'serial_sha256': hash(output + '/bootstrap-fixture/serial.log')!,
  'raw_results_sha256': hash(output + '/results.json')!, 'raw_outcome': raw[0]['outcome']!.str(),
  'checker_binary_sha256': hash(os.executable())!,
  'signed_apk_sha256': apk_pin,
  'original_maps_apk_sha256': maps_pin,
  'scope': 'Same signed fixture APK and original unchanged Maps sidecar on actual ART: old rejects original hqa.V at 0x4CF before API checks; fixed verifies original hqa and hwv and passes media exception metadata, constructor, message, hierarchy, code, diagnostic and action semantics. No native media decoding or Maps replay qualification.',
 })!
 println('MEDIA-CODEC-EXCEPTIONS-' + kind.to_upper() + '-EXPECTED-RESULT-PASS')
}


fn main() {
 $if prod { panic('assertions required') }
 if os.args.len == 2 && os.args[1] != 'prepare' { os.setenv('VROOT', state + '/frozen/vroot', true) }
 assert os.args.len == 2
 match os.args[1] {
  'prepare' { prepare()! }
  'framework' { build_framework()! }
  'apk' { build_apk()! }
  'old', 'new' { run(os.args[1])! }
  'qualify' {
   for kind in ['old', 'new'] { check(kind, state + '/qualification/' + kind + '-semantic-check.json')! }

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
