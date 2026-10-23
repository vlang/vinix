import os
import json2
import crypto.sha256
import compress.gzip

const base = 'build/android-maps/'
const dest = 'tests/android/results/2026-10-23/maps-ws/'
const run = base + 'attempt227/'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn without_badging(value json2.Any) json2.Any {
 if value is map[string]json2.Any {
  mut result := map[string]json2.Any{}
  for key, item in value { if key != 'badging' { result[key] = without_badging(item) } }
  return result
 }
 if value is []json2.Any {
  mut result := []json2.Any{}
  for item in value { result << without_badging(item) }
  return result
 }
 return value
}

fn main() {
 raw := os.read_file(run + 'results.json')!
 mut row := without_badging(json2.decode[[]json2.Any](raw)![0]).as_map()
 serial := gzip.decompress(os.read_bytes(run + 'google-maps/serial.log.gz')!)!
 assert sha256.sum(serial).hex() == row['serial_sha256']!.str()
 log := serial.bytestr()
 assert row['outcome']!.str() == 'startup_failed' && row['backend_ready']!.bool()
 assert log.contains('java.lang.UnsupportedOperationException: Native WS RenderNode supports rectangular outline clipping only')
 assert log.contains('in call to NewLocalRef')
 assert log.contains('APK-SUITE-EXIT id=google-maps code=134 native_observed=true gtk_x11_absent=true')
 mut artifacts := map[string]json2.Any{}
 for source, name in {
  run + 'google-maps/serial.log.gz': 'attempt227-google-maps-serial.log.gz'
  base + 'attempt227.json': 'attempt227-configuration.json'
  base + 'attempt227-harness.log': 'attempt227-harness.log'
  base + 'interact227.log': 'attempt227-interaction.log'
  base + 'interact227.v': 'attempt227-interaction.v'
  base + 'run227.v': 'attempt227-run.v'
  base + 'prepare227.v': 'attempt227-prepare.v'
  base + 'wait-onboarding227.v': 'attempt227-wait-onboarding.v'
  base + 'clone-maps-live-vm.v': 'attempt227-clone-vm.v'
  base + 'retain227.v': 'retain227.v'
 } {
  os.cp(source, dest + name)!
  artifacts[name] = hash(dest + name)!
 }
 for name in ['initial', 'skip', 'skip-later', 'map-later', 'onboarding-presented', 'current', 'application'] {
  target := 'attempt227-google-maps-' + name + '.png'
  os.cp(run + 'google-maps/' + name + '.png', dest + target)!
  artifacts[target] = hash(dest + target)!
 }
 os.write_file_array(dest + 'attempt227-framework-build.log.gz', gzip.compress(os.read_bytes(base + 'framework227-canvas-z-build.log')!)!)!
 artifacts['attempt227-framework-build.log.gz'] = hash(dest + 'attempt227-framework-build.log.gz')!
 for name in ['Canvas', 'RecordingCanvas'] {
  target := 'attempt227-' + name + '.smali.gz'
  os.write_file_array(dest + target, gzip.compress(os.read_bytes(base + 'canvas227/verify-fixed-smali/android/graphics/' + name + '.smali')!)!)!
  artifacts[target] = hash(dest + target)!
 }
 prior := json2.decode[map[string]json2.Any](os.read_file(dest + 'attempt218-runtime-identities.json')!)!
 inputs := prior['input_files_sha256']!.as_map()
 assert row['metadata']!.as_map()['apk_sha256']!.str() == inputs[base + 'GoogleMaps.apk']!.str()
 for entry in row['companion_packages']!.as_array() {
  companion := entry.as_map()
  assert companion['metadata']!.as_map()['apk_sha256']!.str() == inputs[companion['apk']!.str()]!.str()
 }
 row['run'] = 'attempt227'
 row['startup_ui_passed'] = false
 row['search_passed'] = false
 row['manual_review'] = 'Onboarding is visible in presented/current captures. The original black-button-only detector accepted an all-black window and issued an early click at 14:21:11 local; its ONBOARDING-PRESENTED marker is a false positive. A second helper requires both white background and black sign-in button, captures actual onboarding, and clicks Skip. Root reported white=124823 black=4744 at 14:22:20 local and real Skip at 14:22:21 local (11:22:21 UTC); its stdout was observed in-session, not saved as a tool log. The real transition throws UnsupportedOperationException for rectangular-only RenderNode outline clipping; a pending exception then reaches JNI NewLocalRef and aborts the APK, exit 134. Map display and search remain unverified.'
 row['screenshot'] = 'attempt227-google-maps-application.png'
 row['serial_log'] = 'attempt227-google-maps-serial.log.gz'
 row['initial_screenshot'] = 'attempt227-google-maps-initial.png'
 row['skip_screenshot'] = 'attempt227-google-maps-skip.png'
 row['later_screenshot'] = 'attempt227-google-maps-map-later.png'
 row['onboarding_presented_screenshot'] = 'attempt227-google-maps-onboarding-presented.png'
 row['badging_omission'] = 'Only metadata badging strings recursively omitted; remaining result fields retained.'
 os.write_file(dest + 'attempt227-results.json', json2.encode([json2.Any(row)], prettify: true) + '\n')!
 artifacts['attempt227-results.json'] = hash(dest + 'attempt227-results.json')!
 os.write_file(dest + 'attempt227-runtime-identities.json', json2.encode({
  'artifacts_sha256': json2.Any(artifacts)
  'original_results_sha256': json2.Any(sha256.sum(raw.bytes()).hex())
  'input_identity_receipt': json2.Any('attempt227-input-identities.json')
  'input_identity_receipt_sha256': json2.Any(hash(dest + 'attempt227-input-identities.json')!)
  'shared_input_identity_receipt': json2.Any('attempt218-runtime-identities.json')
  'input_scope': json2.Any('APK metadata identities match attempt218 inputs; actual staged runtime hashes and exact framework227 sources retained in input receipt; native225 exact source receipt reused. Independent Maps VM cloned the shared image without a preboot hash: kernel/base source receipts remain inherited.')
  'interaction_limit': json2.Any(row['manual_review']!.str())
  'functional_outcome': json2.Any('FAILED: visible onboarding reaches unsupported RenderNode outline clipping after real Skip; pending exception triggers JNI NewLocalRef abort, exit134, harness startup_failed. Map display and search remain unverified.')
 }, prettify: true) + '\n')!
 println('ATTEMPT227-RETENTION PASS serial/result/APK identities;7 screenshots;actual runtime inputs and103 exact framework sources; FAILED unsupported outline/JNI abort134')
}
