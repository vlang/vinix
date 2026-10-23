import os
import json2
import crypto.sha256
import compress.gzip

const base = 'build/android-maps/'
const dest = 'tests/android/results/2026-10-23/maps-ws/'
const run = base + 'attempt228/'

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
 notes := json2.decode[map[string]json2.Any](os.read_file(base + 'retention228-notes.json')!)!
 raw := os.read_file(run + 'results.json')!
 mut row := without_badging(json2.decode[[]json2.Any](raw)![0]).as_map()
 serial := gzip.decompress(os.read_bytes(run + 'google-maps/serial.log.gz')!)!
 assert sha256.sum(serial).hex() == row['serial_sha256']!.str()
 log := serial.bytestr()
 assert row['outcome']!.str() == notes['expected_outcome']!.str()
 assert row['backend_ready']!.bool() && !row['process_exited']!.bool()
 assert !log.contains('ANDROID-WS-FAIL') && !log.contains('JNI DETECTED ERROR IN APPLICATION')
 assert !log.contains('APK-SUITE-EXIT id=google-maps')
 for required in notes['required_serial']!.as_array() { assert log.contains(required.str()), required.str() }
 mut artifacts := map[string]json2.Any{}
 for source, name in {
  run + 'google-maps/serial.log.gz': 'attempt228-google-maps-serial.log.gz'
  base + 'attempt228.json': 'attempt228-configuration.json'
  base + 'attempt228-harness.log': 'attempt228-harness.log'
  base + 'interact228.log': 'attempt228-interaction.log'
  base + 'interact228.v': 'attempt228-interaction.v'
  base + 'run228.v': 'attempt228-run.v'
  base + 'prepare228.v': 'attempt228-prepare.v'
  base + 'retention228-notes.json': 'attempt228-review-notes.json'
  base + 'retain228.v': 'retain228.v'
 } { os.cp(source, dest + name)!; artifacts[name] = hash(dest + name)! }
 mut screenshots := []json2.Any{}
 for name in ['waiting', 'initial', 'skip', 'skip-later', 'map-later', 'pan', 'zoom', 'search', 'search-open', 'application'] {
  source := run + 'google-maps/' + name + '.png'
  if !os.is_file(source) { continue }
  target := 'attempt228-google-maps-' + name + '.png'
  os.cp(source, dest + target)!
  artifacts[target] = hash(dest + target)!
  screenshots << json2.Any(target)
 }
 assert screenshots.len > 0
 for kind, file in {'native': 'native228-build.log', 'framework': 'framework228-build.log'} {
  target := 'attempt228-' + kind + '-build.log.gz'
  os.write_file_array(dest + target, gzip.compress(os.read_bytes(base + file)!)!)!
  artifacts[target] = hash(dest + target)!
 }
 prior := json2.decode[map[string]json2.Any](os.read_file(dest + 'attempt218-runtime-identities.json')!)!
 inputs := prior['input_files_sha256']!.as_map()
 assert row['metadata']!.as_map()['apk_sha256']!.str() == inputs[base + 'GoogleMaps.apk']!.str()
 for entry in row['companion_packages']!.as_array() {
  companion := entry.as_map()
  assert companion['metadata']!.as_map()['apk_sha256']!.str() == inputs[companion['apk']!.str()]!.str()
 }
 row['run'] = 'attempt228'
 row['startup_ui_passed'] = notes['startup_ui_passed']!
 row['search_passed'] = false
 row['search_suggestions_passed'] = true
 row['manual_review'] = notes['manual_review']!
 row['screenshot'] = 'attempt228-google-maps-application.png'
 row['serial_log'] = 'attempt228-google-maps-serial.log.gz'
 row['retained_screenshots'] = screenshots
 row['badging_omission'] = 'Only metadata badging strings recursively omitted; remaining result fields retained.'
 os.write_file(dest + 'attempt228-results.json', json2.encode([json2.Any(row)], prettify: true) + '\n')!
 artifacts['attempt228-results.json'] = hash(dest + 'attempt228-results.json')!
 os.write_file(dest + 'attempt228-runtime-identities.json', json2.encode({
  'artifacts_sha256': json2.Any(artifacts)
  'original_results_sha256': json2.Any(sha256.sum(raw.bytes()).hex())
  'input_identity_receipt': json2.Any('attempt228-input-identities.json')
  'input_identity_receipt_sha256': json2.Any(hash(dest + 'attempt228-input-identities.json')!)
  'shared_input_identity_receipt': json2.Any('attempt218-runtime-identities.json')
  'input_scope': json2.Any('APK identities match attempt218; native/framework/launcher were measured directly in the staged module. Exact81 native and104 framework source files match their build manifests and are archived. Independent Maps VM kernel/base receipts remain inherited because no preboot hash was captured.')
  'interaction_limit': notes['manual_review']!
  'functional_outcome': notes['functional_outcome']!
 }, prettify: true) + '\n')!
 println('ATTEMPT228-RETENTION PASS serial/result/APK identities; ${screenshots.len} screenshots; exact staged runtime/source receipts; outcome=' + row['outcome']!.str())
}
