import os
import json2
import crypto.sha256
import compress.gzip

const base = 'build/android-maps/'
const task = base + 'content-capture221/'
const dest = 'tests/android/results/2026-10-23/content-capture/'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn read_serial(mode string) !string {
 return gzip.decompress(os.read_bytes(task + 'run-' + mode + '/bootstrap-fixture/serial.log.gz')!)!.bytestr()
}

fn main() {
 b := read_serial('baseline')!
 f := read_serial('fixed')!
 marker := 'BOOTSTRAP-CONTENT-CAPTURE-PASS unavailable detached attach-callback remove reattach'
 assert b.contains('java.lang.NoSuchMethodError: No virtual method getContentCaptureSession()Landroid/view/contentcapture/ContentCaptureSession;')
 assert !b.contains(marker)
 assert f.count(marker) >= 1
 assert f.contains('ANDROID-WS-READY backend=vinix-native gtk=absent x11=absent')
 assert !f.contains('java.lang.AssertionError') && !f.contains('ANDROID-WS-FAIL') && !f.contains('APK-SUITE-EXIT')
 old := gzip.decompress(os.read_bytes(base + 'observer-verify/fixed2/bootstrap-fixture/serial.log.gz')!)!.bytestr()
 mut markers := []string{}
 for line in old.split_into_lines() {
  if !line.starts_with('BOOTSTRAP-') || !line.contains('-PASS') { continue }
  name := line.all_before(' ')
  if name in markers { continue }
  assert f.contains(name), name
  markers << name
 }
 os.mkdir_all(dest)!
 mut artifacts := map[string]json2.Any{}
 for mode in ['baseline', 'fixed'] {
  for name in ['results.json', 'bootstrap-fixture/serial.log.gz', 'bootstrap-fixture/application.png', 'staged-runtime-sha256.json'] {
   out := mode + '-' + os.base(name)
   os.cp(task + 'run-' + mode + '/' + name, dest + out)!
   artifacts[out] = hash(dest + out)!
  }
  for name in ['-harness.log', '.json'] {
   out := mode + if name == '.json' { '-configuration.json' } else { name }
   os.cp(task + mode + name, dest + out)!
   artifacts[out] = hash(dest + out)!
  }
  row := json2.decode[[]map[string]json2.Any](os.read_file(task + 'run-' + mode + '/results.json')!)![0]
  assert row['metadata']!.as_map()['apk_sha256']!.str() == hash(base + 'content-capture221-apk/bootstrap.apk')!
  runtime := json2.decode[map[string]string](os.read_file(task + 'run-' + mode + '/staged-runtime-sha256.json')!)!
  jar := if mode == 'baseline' { task + 'baseline.jar' } else { base + 'framework221-content-capture/api-impl.jar' }
  assert runtime['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar']! == hash(jar)!
  assert runtime['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so']! == hash(base + 'libnative204.so')!
  assert runtime['usr/bin/run-android-calculator']! == hash(base + 'launcher200')!
 }
 for source, out in {
  'validate-content-capture221.v': 'validate.v'
  'prepare-content-capture221.v': 'prepare.v'
  'content-capture221/staged-hashes.v': 'staged-hashes.v'
  'content-capture221/controlled-baseline.v': 'controlled-baseline.v'
  'build-framework221-content-capture.v': 'build-framework.v'
  'framework221-content-capture/framework-manifest.json': 'fixed-framework-manifest.json'
  'framework221-content-capture-build.log': 'framework-build.log'
  'bootstrap221-content-capture-build.log': 'fixture-build.log'
  'suite-low-disk.v': 'suite.v'
 } {
  os.cp(base + source, dest + out)!
  artifacts[out] = hash(dest + out)!
 }
 for source, out in {
  'build-framework221-content-capture-compile.log': 'framework-compile.log.gz'
  'bootstrap221-content-capture-compile.log': 'fixture-compile.log.gz'
 } {
  os.write_file_array(dest + out, gzip.compress(os.read_bytes(base + source)!)!)!
  artifacts[out] = hash(dest + out)!
 }
 for entry in [
  ['fixture-sources.tar.gz', base + 'content-capture221-apk', 'smali', 'res'],
  ['fixed-framework-generated.tar.gz', base + 'framework221-content-capture/smali', 'android/view/View.smali', 'android/view/contentcapture/ContentCaptureSession.smali'],
  ['baseline-framework-generated.tar.gz', base + 'framework221-content-capture-verify-smali', 'android/view/View.smali', 'android/view/contentcapture/ContentCaptureSession.smali'],
 ] {
  mut args := ['tar', '-czf', os.abs_path(dest + entry[0]), '-C', entry[1]]
  args << entry[2..]
  r := os.exec(args)
  assert r.exit_code == 0, r.output
  artifacts[entry[0]] = hash(dest + entry[0])!
 }
 mut sources := map[string]json2.Any{}
 for path in ['tests/native-android-tools/androidtools/framework_content_capture.v', 'tests/native-android-ws/startupfixture/content_capture.v'] {
  sources[path] = hash(path)!
 }
 receipt := {
  'artifacts_sha256': json2.Any(artifacts)
  'sources_sha256': json2.Any(sources)
  'baseline_framework_sha256': json2.Any(hash(task + 'baseline.jar')!)
  'fixed_framework_sha256': json2.Any(hash(base + 'framework221-content-capture/api-impl.jar')!)
  'fixture_apk_sha256': json2.Any(hash(base + 'content-capture221-apk/bootstrap.apk')!)
  'native204_sha256': json2.Any(hash(base + 'libnative204.so')!)
  'harness_binary_sha256': json2.Any(hash(base + 'suite159')!)
  'content_capture_pass_count': json2.Any(f.count(marker))
  'previous_pass_markers_retained': json2.Any(markers.len)
  'scope': json2.Any('Native WS synthetic regression. One identical signed APK fails on a controlled baseline missing only View.getContentCaptureSession, then passes with that method available. It checks null while detached, in an attachment callback, on an attached parent and child, after removal, and after reattachment. Both use native204 and launcher200. Baseline was constructed by disassembling the exact fixed JAR, removing only this getter, reassembling DEX and replacing classes.dex. It retains the ContentCaptureSession type. The fixed JAR also contains the separately tested application-init lock and observer fixes. Maps behavior is retained separately.')
 }
 os.write_file(dest + 'receipt.json', json2.encode(receipt, prettify: true) + '\n')!
 println('CONTENT-CAPTURE-VALIDATION PASS identical signed APK; baseline exact missing method; fixed null contract through attachment lifecycle; ' + markers.len.str() + ' previous probe markers retained; staged hashes verified')
}
