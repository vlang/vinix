import os
import json2
import crypto.sha256
import compress.gzip

const base = 'build/android-maps/'
const task = base + 'observer-verify/'
const dest = 'tests/android/results/2026-10-23/observer-verify/'
fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn log(run string) !string { return gzip.decompress(os.read_bytes(task + run + '/bootstrap-fixture/serial.log.gz')!)!.bytestr() }

fn main() {
 b := log('baseline2')!
 f := log('fixed2')!
 marker := 'BOOTSTRAP-TRAVERSAL-PASS native-WS floating-observer-identity attachment-merge global-layout pre-draw-cancel draw-order draw-invalidation'
 assert b.contains('java.lang.AssertionError: global layout must see attached, laid-out views')
 assert !b.contains(marker)
 assert f.count(marker) == 2
 assert f.contains('ANDROID-WS-READY backend=vinix-native gtk=absent x11=absent')
 assert !f.contains('java.lang.AssertionError') && !f.contains('ANDROID-WS-FAIL') && !f.contains('APK-SUITE-EXIT')
 old := gzip.decompress(os.read_bytes(base + 'fixture-layout208-fixed/bootstrap-fixture/serial.log.gz')!)!.bytestr()
 mut previous := 0
 for line in old.split_into_lines() {
  if !line.starts_with('BOOTSTRAP-') || !line.contains('-PASS') { continue }
  assert f.contains(line.all_before(' ')), line.all_before(' ')
  previous++
 }
 os.mkdir_all(dest)!
 mut artifacts := map[string]json2.Any{}
 for run in ['baseline', 'fixed', 'baseline2', 'fixed2'] {
  for name in ['results.json', 'bootstrap-fixture/serial.log.gz', 'bootstrap-fixture/application.png'] {
   out := run + '-' + os.base(name)
   os.cp(task + run + '/' + name, dest + out)!
   artifacts[out] = hash(dest + out)!
  }
  os.cp(task + run + '-harness.log', dest + run + '-harness.log')!
  artifacts[run + '-harness.log'] = hash(dest + run + '-harness.log')!
 }
 for mode in ['baseline2', 'fixed2'] {
  row := json2.decode[[]map[string]json2.Any](os.read_file(task + mode + '/results.json')!)![0]
  assert row['metadata']!.as_map()['apk_sha256']!.str() == hash(base + 'observer2-apk/bootstrap.apk')!
  runtime := json2.decode[map[string]string](os.read_file(task + mode + '/staged-runtime-sha256.json')!)!
  fw := if mode == 'baseline2' { '211' } else { '217-observer2' }
  assert runtime['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar']! == hash(base + 'framework' + fw + '/api-impl.jar')!
  assert runtime['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so']! == hash(base + 'libnative204.so')!
  assert runtime['usr/bin/run-android-calculator']! == hash(base + 'launcher200')!
  for name in ['staged-runtime-sha256.json'] {
   os.cp(task + mode + '/' + name, dest + mode + '-' + name)!
   artifacts[mode + '-' + name] = hash(dest + mode + '-' + name)!
  }
 }
 for source, out in {
  'observer-verify.v': 'run.v'
  'validate-observer.v': 'validate.v'
  'build-framework217-observer2.v': 'build-framework.v'
  'framework217-observer2/framework-manifest.json': 'fixed-framework-manifest.json'
  'framework217-observer2-build.log': 'framework-build.log'
  'observer2-apk-build.log': 'fixture-build.log'
  'suite-low-disk.v': 'suite.v'
  'trace200-launcher.v': 'launcher.v'
 } {
  os.cp(base + source, dest + out)!
  artifacts[out] = hash(dest + out)!
 }
 for source, out in {
  'build-framework217-observer2-compile.log': 'framework-compile.log.gz'
  'bootstrap-observer2-compile.log': 'fixture-compile.log.gz'
 } {
  os.write_file_array(dest + out, gzip.compress(os.read_bytes(base + source)!)!)!
  artifacts[out] = hash(dest + out)!
 }
 for run in ['baseline2', 'fixed2'] {
  os.cp(task + run + '.json', dest + run + '-configuration.json')!
  artifacts[run + '-configuration.json'] = hash(dest + run + '-configuration.json')!
 }
 for entry in [
  ['fixture-sources.tar.gz', base + 'observer2-apk', 'smali', 'res'],
  ['framework-generated.tar.gz', base + 'framework217-observer2/smali', 'android/view/View.smali', 'android/view/ViewTreeObserver.smali'],
  ['baseline-framework-generated.tar.gz', base + 'framework211/smali', 'android/view/View.smali', 'android/view/ViewTreeObserver.smali'],
 ] {
  name := entry[0]
  cwd := entry[1]
  paths := entry[2..]
  mut args := ['tar', '-czf', os.abs_path(dest + name), '-C', cwd]
  args << paths
  r := os.exec(args)
  assert r.exit_code == 0, r.output
  artifacts[name] = hash(dest + name)!
 }
 mut source_hashes := map[string]json2.Any{}
 for path in ['tests/native-android-tools/androidtools/framework_traversal.v', 'tests/native-android-ws/startupfixture/traversal.v'] {
  source_hashes[path] = hash(path)!
 }
 receipt := {
  'artifacts_sha256': json2.Any(artifacts)
  'sources_sha256': json2.Any(source_hashes)
  'baseline_framework_sha256': json2.Any(hash(base + 'framework211/api-impl.jar')!)
  'first_fixed_framework_sha256': json2.Any(hash(base + 'framework217/api-impl.jar')!)
  'fixed_framework_sha256': json2.Any(hash(base + 'framework217-observer2/api-impl.jar')!)
  'final_fixture_apk_sha256': json2.Any(hash(base + 'observer2-apk/bootstrap.apk')!)
  'first_fixture_apk_sha256': json2.Any(hash(base + 'observer217-apk/bootstrap.apk')!)
  'native204_sha256': json2.Any(hash(base + 'libnative204.so')!)
  'harness_binary_sha256': json2.Any(hash(base + 'suite159')!)
  'previous_pass_markers_retained': json2.Any(previous)
  'scope': json2.Any('Native WS synthetic regression only. Final identical signed APK fails on framework211/native204 and passes twice on fixed framework217-observer2/native204. Two detached probes test stable floating observer identity and liveness, attachment merge and old observer death, global layout, canceled first pre-draw, OnDraw ordering and invalidation-driven redraw. First fixed run exposed missing OnDraw merge; both preliminary runs are retained with their separate APK/framework hashes. Actual Google Maps behavior is outside this fixture result.')
 }
 os.write_file(dest + 'receipt.json', json2.encode(receipt, prettify: true) + '\n')!
 println('OBSERVER-VALIDATION PASS identical final signed APK; baseline attachment/merge failure; fixed two probes pass identity, attachment, callback preservation and traversal ordering; ' + previous.str() + ' previous pass markers retained; staged framework/native/launcher hashes verified')
}
