import os
import json2
import crypto.sha256
import compress.gzip
const base = 'build/android-maps/'
const dest = 'tests/android/results/2026-10-23/maps-ws/'
const run = base + 'attempt219/'
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
 assert log.contains('FindClass(com/google/android/maps/MapsActivity) returning NULL')
 assert log.contains('ANDROID-WS-TRANSITION-FUTURE-DIAGNOSTIC-FAIL')
 assert !log.contains('ANDROID-WS-TRANSITION-FUTURE done=')
 mut messages := 0
 for line in log.split_into_lines() {
  if line.starts_with('ANDROID-WS-QUEUE index=') { assert line.contains('barrier=0'); messages++ }
 }
 assert log.count('ANDROID-WS-QUEUE-BEGIN') == 3 && messages > 0
 mut artifacts := map[string]json2.Any{}
 for source, name in {
  run + 'google-maps/serial.log.gz': 'attempt219-google-maps-serial.log.gz'
  run + 'google-maps/initial.png': 'attempt219-google-maps-initial.png'
  run + 'google-maps/skip.png': 'attempt219-google-maps-skip.png'
  run + 'google-maps/skip-later.png': 'attempt219-google-maps-skip-later.png'
  base + 'attempt219.json': 'attempt219-configuration.json'
  base + 'attempt219-harness.log': 'attempt219-harness.log'
  base + 'interact219.log': 'attempt219-interaction.log'
  base + 'interact219.v': 'attempt219-interaction.v'
  base + 'run219.v': 'attempt219-run.v'
  base + 'prepare219.v': 'attempt219-prepare.v'
  base + 'quit219.v': 'attempt219-quit.v'
  base + 'retain219.v': 'retain219.v'
 } { os.cp(source, dest + name)!; artifacts[name] = hash(dest + name)! }
 mut staged := map[string]json2.Any{}
 for path in ['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so',
  'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar',
  'usr/bin/run-android', 'usr/bin/run-android-calculator', 'usr/bin/vinix-desktop',
  'usr/bin/vinix-session', 'opt/android-test/native-guest'] { staged[path] = hash(run + 'module/' + path)! }
 native := staged['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so']!.str()
 assert native.starts_with('680c') && native.ends_with('03328a')
 assert staged['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar']!.str() == 'acd7c4ca1ab2447f528879b2ecc8533d38129627f50e867cc8a586b557978593'
 prior := json2.decode[map[string]json2.Any](os.read_file(dest + 'attempt218-runtime-identities.json')!)!
 prior_staged := prior['staged_runtime_sha256']!.as_map()
 for path, value in staged { if !path.ends_with('api-impl.jar') && !path.ends_with('libvinix-android-native.so') { assert value.str() == prior_staged[path]!.str() } }
 inputs := prior['input_files_sha256']!.as_map()
 assert row['metadata']!.as_map()['apk_sha256']!.str() == inputs[base + 'GoogleMaps.apk']!.str()
 for entry in row['companion_packages']!.as_array() {
  companion := entry.as_map()
  assert companion['metadata']!.as_map()['apk_sha256']!.str() == inputs[companion['apk']!.str()]!.str()
 }
 row['run'] = 'attempt219'
 row['startup_ui_passed'] = false
 row['search_passed'] = false
 row['manual_review'] = 'Initial, Skip and later screenshots retain onboarding. The Future probe failed app-class lookup; it did not establish Future state. Three bounded queue snapshots contain no synchronization barriers. Operator intentionally quit QEMU via QMP after sample3 and screenshots; there is no final harness screenshot. Map/search remain unverified.'
 row['serial_log'] = 'attempt219-google-maps-serial.log.gz'
 row['initial_screenshot'] = 'attempt219-google-maps-initial.png'
 row['skip_screenshot'] = 'attempt219-google-maps-skip.png'
 row['later_screenshot'] = 'attempt219-google-maps-skip-later.png'
 row['badging_omission'] = 'Only metadata badging strings were recursively omitted; remaining result fields retained.'
 os.write_file(dest + 'attempt219-results.json', json2.encode([json2.Any(row)], prettify: true) + '\n')!
 artifacts['attempt219-results.json'] = hash(dest + 'attempt219-results.json')!
 receipt := {
  'artifacts_sha256': json2.Any(artifacts)
  'staged_runtime_sha256': json2.Any(staged)
  'original_results_sha256': json2.Any(sha256.sum(raw.bytes()).hex())
  'shared_input_identity_receipt': json2.Any('attempt218-runtime-identities.json')
  'shared_input_identity_scope': json2.Any('Same signed Maps/GMS/Store APK identities verified from result metadata against attempt218 verified inputs. Same harness, launcher and other staged launch components. Kernel/base identity remains inherited and unmeasured for this attempt.')
  'native_source_limit': json2.Any('Original native219 is identified directly from the completed attempt219 staged module. libnative219.so, queue219.v and native219-sources.json were subsequently overwritten for corrected attempt220; they are not retained as original219 input/source evidence.')
  'queue_messages_observed': json2.Any(messages)
  'functional_outcome': json2.Any('FAILED: onboarding remains; Future probe failed FindClass and Future state remains unknown. Three bounded queue snapshots show no barriers; this does not prove the queue was barrier-free for the entire run. Intentionally terminated by QMP after diagnostic samples and screenshots.')
 }
 os.write_file(dest + 'attempt219-runtime-identities.json', json2.encode(receipt, prettify: true) + '\n')!
 println('ATTEMPT219-RETENTION PASS serial, staged original native219/full observer2 and shared APK/launcher identities verified; 3 queue snapshots, '+messages.str()+' messages, no observed barriers; Future diagnostic failed; functional outcome FAILED onboarding remains')
}
