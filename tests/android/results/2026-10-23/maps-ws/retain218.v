import os
import json2
import crypto.sha256
import compress.gzip

const base = 'build/android-maps/'
const dest = 'tests/android/results/2026-10-23/maps-ws/'
const run = base + 'attempt218/'
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
 os.mkdir_all(dest)!
 raw := os.read_file(run + 'results.json')!
 mut row := without_badging(json2.decode[[]json2.Any](raw)![0]).as_map()
 serial := gzip.decompress(os.read_bytes(run + 'google-maps/serial.log.gz')!)!
 assert sha256.sum(serial).hex() == row['serial_sha256']!.str()
 assert row['outcome']!.str() == 'startup_failed'
 assert row['backend_ready']!.bool()
 mut artifacts := map[string]json2.Any{}
 for source, name in {
  run + 'google-maps/serial.log.gz': 'attempt218-google-maps-serial.log.gz'
  run + 'google-maps/application.png': 'attempt218-google-maps-application.png'
  run + 'google-maps/initial.png': 'attempt218-google-maps-initial.png'
  run + 'google-maps/skip.png': 'attempt218-google-maps-skip.png'
  run + 'google-maps/skip-later.png': 'attempt218-google-maps-skip-later.png'
  base + 'attempt218.json': 'attempt218-configuration.json'
  base + 'attempt218-harness.log': 'attempt218-harness.log'
  base + 'interact218.log': 'attempt218-interaction.log'
  base + 'interact218.v': 'attempt218-interaction.v'
  base + 'run218.v': 'attempt218-run.v'
  base + 'prepare218.v': 'attempt218-prepare.v'
  base + 'suite-low-disk.v': 'attempt218-suite.v'
  base + 'trace200-launcher.v': 'attempt218-launcher.v'
  base + 'build-native216.v': 'build-native216.v'
  base + 'graph216.v': 'graph216.v'
  base + 'native216-sources.json': 'native216-sources.json'
  base + 'framework217/framework-manifest.json': 'observer217-framework-manifest.json'
  base + 'retain218.v': 'retain218.v'
  'tests/android/results/2026-10-22/maps-ws/arp-kernels.json': 'inherited-arp-kernels.json'
  'tests/android/results/2026-10-22/maps-ws/boot-base161.json': 'inherited-boot-base161.json'
 } {
  os.cp(source, dest + name)!
  artifacts[name] = hash(dest + name)!
 }
 for source, name in {
  base + 'native216-build.log': 'native216-build.log.gz'
  base + 'framework217/smali/android/view/View.smali': 'observer217-View.smali.gz'
  base + 'framework217/smali/android/view/ViewTreeObserver.smali': 'observer217-ViewTreeObserver.smali.gz'
 } {
  os.write_file_array(dest + name, gzip.compress(os.read_bytes(source)!)!)!
  artifacts[name] = hash(dest + name)!
 }
 mut staged := map[string]json2.Any{}
 for path in [
  'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so',
  'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar',
  'usr/bin/run-android', 'usr/bin/run-android-calculator', 'usr/bin/vinix-desktop',
  'usr/bin/vinix-session', 'opt/android-test/native-guest',
 ] { staged[path] = hash(run + 'module/' + path)! }
 assert staged['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so']!.str() == hash(base + 'libnative216.so')!
 assert staged['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar']!.str() == 'b544bd1b332feb6d7bcb43cbbc7e2ae73498da8eb6626ca4046aa78d89f888ab'
 assert staged['usr/bin/run-android-calculator']!.str() == hash(base + 'launcher200')!
 mut inputs := map[string]json2.Any{}
 cfg := json2.decode[map[string]json2.Any](os.read_file(base + 'attempt218.json')!)!
 for path in [base + 'libnative216.so', base + 'framework217/api-impl.jar', base + 'launcher200',
  base + 'GoogleMaps.apk', base + 'GooglePlayServices.apk', base + 'GooglePlayStore.apk',
  cfg['base_module']!.str(), cfg['firmware']!.str(), cfg['qemu']!.str(), cfg['input_tool']!.str(), base + 'suite159'] {
  inputs[path] = hash(path)!
 }
 assert row['metadata']!.as_map()['apk_sha256']!.str() == inputs[base + 'GoogleMaps.apk']!.str()
 for entry in row['companion_packages']!.as_array() {
  companion := entry.as_map()
  assert companion['metadata']!.as_map()['apk_sha256']!.str() == inputs[companion['apk']!.str()]!.str()
 }
 row['run'] = 'attempt218'
 row['startup_ui_passed'] = false
 row['search_passed'] = false
 row['manual_review'] = 'Initial, Skip and later screenshots still show Make it your map onboarding. The interaction clicked Skip at (556,134), settled 10 seconds, then waited 15 seconds before the later capture. The pending Future was not inspected in this run. Map display and search remain unverified.'
 row['screenshot'] = 'attempt218-google-maps-application.png'
 row['serial_log'] = 'attempt218-google-maps-serial.log.gz'
 row['initial_screenshot'] = 'attempt218-google-maps-initial.png'
 row['skip_screenshot'] = 'attempt218-google-maps-skip.png'
 row['later_screenshot'] = 'attempt218-google-maps-skip-later.png'
 row['badging_omission'] = 'Only metadata badging strings were recursively omitted from the original result; signing checks, package identities, failure markers and remaining fields are retained.'
 os.write_file(dest + 'attempt218-results.json', json2.encode([json2.Any(row)], prettify: true) + '\n')!
 artifacts['attempt218-results.json'] = hash(dest + 'attempt218-results.json')!
 receipt := {
  'artifacts_sha256': json2.Any(artifacts)
  'staged_runtime_sha256': json2.Any(staged)
  'input_files_sha256': json2.Any(inputs)
  'original_results_sha256': json2.Any(sha256.sum(raw.bytes()).hex())
  'kernel_sha256_inherited': json2.Any('f8d86366353da19545fa6814b7b54d53973e59fdbafe2575c96c13594284b352')
  'kernel_receipt_source': json2.Any('tests/android/results/2026-10-22/maps-ws/arp-kernels.json')
  'boot_base_receipt_source': json2.Any('tests/android/results/2026-10-22/maps-ws/boot-base161.json')
  'boot_identity_limit': json2.Any('Inherited prior kernel/base receipts; no pre-run attempt218 boot image or extracted kernel hash was recorded. The shared boot image and efivars are mutable and are not rehashed as attempt218 inputs.')
  'native_identity_note': json2.Any('Native218 directory has since been reused; attempt218 staged library directly matches retained libnative216.so. Its diagnostic source hash list, graph216.v and build helper are retained.')
  'observer_scope': json2.Any('This run used observer217 b544bd1b…, the first observer fix. It did not use framework217-observer2 acd7c4ca… containing the subsequent OnDraw listener merge.')
  'functional_outcome': json2.Any('FAILED: onboarding remains visible after Skip. Native WS readiness is not a functional Maps pass; pending Future not inspected; map/search unverified.')
 }
 os.write_file(dest + 'attempt218-runtime-identities.json', json2.encode(receipt, prettify: true) + '\n')!
 println('ATTEMPT218-RETENTION PASS serial hash, APK identities and staged native216/observer217/launcher200 verified; functional outcome FAILED onboarding remains; inherited kernel identity explicitly limited')
}
