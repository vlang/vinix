import os
import json2
import crypto.sha256
import compress.gzip

const base = 'build/android-maps/'
const dest = 'tests/android/results/2026-10-23/render-exception/'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn main() {
 os.mkdir_all(dest)!
 mut artifacts := map[string]string{}
 for source, target in {
  'tests/native-android-ws/render-exception-fixture.v': 'fixture.v'
  base + 'build-native230.v': 'build-native230.v'
  base + 'prepare-render230.v': 'prepare.v'
  base + 'interact-render230.v': 'interact.v'
  base + 'run-render230.v': 'run.v'
  base + 'retain-render230.v': 'retain.v'
  base + 'native230-sources.json': 'native230-sources.json'
  base + 'native228-sources.json': 'native228-sources.json'
 } { os.cp(source, dest + target)!; artifacts[target] = hash(dest + target)! }
 // Preserve the resource/manifest template and the three support classes
 // consumed by fixture.v; no startupfixture implementation is implicit.
 os.mkdir_all(dest + 'fixture-inputs/smali/org/vinix/bootstrap')!
 for name in ['App', 'High', 'Low'] {
  target := 'fixture-inputs/smali/org/vinix/bootstrap/' + name + '.smali'
  os.cp(base + 'canvas227-apk/smali/org/vinix/bootstrap/' + name + '.smali', dest + target)!
  artifacts[target] = hash(dest + target)!
 }
 for name in ['unsigned.apk', 'fixture.p12'] {
  target := 'fixture-inputs/' + name
  os.cp(base + 'canvas227-apk/' + name, dest + target)!
  artifacts[target] = hash(dest + target)!
 }
 os.write_file_array(dest + 'fixture-classes.dex.gz', gzip.compress(os.read_bytes(base + 'render230-apk/classes.dex')!)!)!
 artifacts['fixture-classes.dex.gz'] = hash(dest + 'fixture-classes.dex.gz')!
 for variant in ['228', '230'] {
  manifest := json2.decode[map[string]string](os.read_file(base + 'native' + variant + '-sources.json')!)!
  mut sources := map[string]string{}
  for name, digest in manifest {
   path := base + 'native' + variant + '/atlframework/' + name
   assert hash(path)! == digest, name
   sources[name] = os.read_file(path)!
  }
  assert sources.len == 81
  target := 'native' + variant + '-sources.json.gz'
  os.write_file_array(dest + target, gzip.compress(json2.encode(sources).bytes())!)!
  artifacts[target] = hash(dest + target)!
 }
 framework := base + 'framework228-outline/'
 for name, target in {
  'framework-manifest.json': 'framework-manifest.json'
  'exact-sources.json.gz': 'framework-sources.json.gz'
 } { os.cp(framework + name, dest + target)!; artifacts[target] = hash(dest + target)! }
 os.write_file_array(dest + 'native230-build.log.gz', gzip.compress(os.read_bytes(base + 'native230-build.log')!)!)!
 artifacts['native230-build.log.gz'] = hash(dest + 'native230-build.log.gz')!
 mut staged := map[string]map[string]string{}
 for mode in ['baseline', 'fixed'] {
  run := base + 'render230/run-' + mode + '/'
  raw := os.read_file(run + 'results.json')!
  row := json2.decode[[]json2.Any](raw)![0].as_map()
  assert row['outcome']!.str() == 'startup_failed' && row['backend_ready']!.bool()
  serial := gzip.decompress(os.read_bytes(run + 'render-exception/serial.log.gz')!)!
  log := serial.bytestr()
  assert sha256.sum(serial).hex() == row['serial_sha256']!.str()
  assert log.contains('RENDER-EXCEPTION-DRAW-ENTER')
  assert log.contains('java.lang.IllegalStateException: expected queued-input render failure')
  assert log.contains('org.vinix.bootstrap.DrawFailureView.onDraw')
  assert !log.contains('RENDER-EXCEPTION-UNEXPECTED-TOUCH')
  expected_code := '1'
  assert log.contains('APK-SUITE-EXIT id=render-exception code=' + expected_code + ' native_observed=true gtk_x11_absent=true')
  if mode == 'baseline' {
   assert log.contains('JNI DETECTED ERROR IN APPLICATION') && log.contains('in call to NewLocalRef')
   assert log.contains('Fatal signal 6 (SIGABRT)') && log.contains('HandleUnexpectedSignal reentered')
  } else {
   assert log.contains('ANDROID-WS-FAIL input or render')
   assert !log.contains('JNI DETECTED ERROR IN APPLICATION') && !log.contains('Aborting thread')
   assert !log.contains('Fatal signal') && !log.contains('HandleUnexpectedSignal reentered')
  }
  for source, target in {
   run + 'results.json': mode + '-results.json'
   run + 'render-exception/serial.log.gz': mode + '-serial.log.gz'
   run + 'render-exception/application.png': mode + '-application.png'
   base + 'render230/' + mode + '.json': mode + '-configuration.json'
   base + 'render230/' + mode + '-harness.log': mode + '-harness.log'
   base + 'render230/' + mode + '-interaction.log': mode + '-interaction.log'
  } { os.cp(source, dest + target)!; artifacts[target] = hash(dest + target)! }
  interaction := os.read_file(dest + mode + '-interaction.log')!
  assert interaction.contains('DRAW-ENTER-OBSERVED at=')
  assert interaction.contains('POINTER-POSITIONED at=') && interaction.contains('BUTTON-DOWN-QUEUED at=')
  mut runtime := map[string]string{}
  for name in ['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so',
   'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar',
   'usr/bin/run-android', 'usr/bin/run-android-calculator', 'usr/bin/vinix-desktop',
   'usr/bin/vinix-session', 'opt/android-test/native-guest'] {
   runtime[name] = hash(run + 'module/' + name)!
  }
  staged[mode] = runtime
 }
 native_path := 'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'
 assert staged['baseline']![native_path]! == '37d54bcc10b6ada24bdfb71bd54442fc582edf5a536478bd31006d40a15c7137'
 assert staged['fixed']![native_path]! == 'befb00a26f77a2b2674eea0590fb0e3880f0c5161fc717ab572b3d4117616d7b'
 for name, digest in staged['baseline']! {
  if name != native_path { assert digest == staged['fixed']![name]!, name }
 }
 assert staged['fixed']!['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar']! == '26b21262b67e92c77bcf57b9480bc881b0683ac0e8d6f97dba105ef453f3fe5a'
 mut artifact_values := map[string]json2.Any{}
 for name, digest in artifacts { artifact_values[name] = digest }
 mut tools := map[string]string{}
 for path in ['build-support/compile-v-module',
  'build/android-maps/suite159', 'tests/native-android-ws/suite.v',
  'build/android-native-ws/android-15/lib/apksigner.jar'] {
  if os.is_file(path) { tools[path] = hash(path)! }
 }
 for name in os.ls('build/android-framework/tools')! {
  if name.ends_with('.jar') {
   path := 'build/android-framework/tools/' + name
   tools[path] = hash(path)!
  }
 }
 mut tool_values := map[string]json2.Any{}
 for name, digest in tools { tool_values[name] = digest }
 mut staged_values := map[string]json2.Any{}
 for mode, runtime in staged {
  mut values := map[string]json2.Any{}
  for name, digest in runtime { values[name] = digest }
  staged_values[mode] = values
 }
 os.write_file(dest + 'identities.json', json2.encode({
  'artifacts_sha256': json2.Any(artifact_values)
  'staged_runtime_sha256': json2.Any(staged_values)
  'build_tool_sha256': json2.Any(tool_values)
  'apk_sha256': json2.Any(hash(base + 'render230-apk/probe.apk')!)
  'dex_sha256': json2.Any(hash(base + 'render230-apk/classes.dex')!)
  'boot_identity_limit': json2.Any('No preboot shared-image/kernel hash captured. Actual VM paths are retained in configuration; base/kernel identities remain inherited from prior fixture receipts.')
  'result_scope': json2.Any('Expected negative guest failures: baseline NewLocalRef JNI fatal/SIGABRT with ART signal-handler reentry and launcher exit1; guarded original render exception exit1 without JNI fatal. Both raw startup_failed harness results are intentional; they do not claim successful app startup. The exit codes happen to match; the fatal trace distinguishes behavior. All81 native source identities per build and104 framework sources are archived.')
 }, prettify: true) + '\n')!
 println('RENDER-EXCEPTION-RETENTION PASS baseline JNI fatal/SIGABRT then launcher exit1; fixed original exception exit1; staged runtime and exact native/framework source identities')
}
