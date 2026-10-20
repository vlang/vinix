// SPDX-License-Identifier: GPL-2.0-or-later
// Retain measured files and separately authored visual workflow verdicts.
import compress.gzip
import crypto.sha256
import json2
import os

fn digest(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn main() {
 if os.args.len != 2 { panic('usage: retain CHECKS.json (run from repository root)') }
 output := 'tests/android/results/2026-10-21'
 mut report := json2.decode[map[string]json2.Any](os.read_file(os.args[1])!)!
 mut apps := []json2.Any{}
 for value in report['applications']!.as_array() {
  mut app := value.as_map()
  state := app['state_dir']!.str()
  name := app['id']!.str()
  app['apk_sha256'] = digest(app['apk']!.str())!
  app['kernel_sha256'] = digest(state + '/kernel/bin/vinix')!
  serial := os.read_bytes(state + '/serial.log')!
  app['serial_sha256'] = sha256.sum(serial).hex()
  os.write_file_array(output + '/' + name + '.serial.log.gz', gzip.compress(serial)!)!
  app['serial_log'] = name + '.serial.log.gz'
  if os.exists(state + '/result.json') {
   app['runner_result'] = json2.decode[json2.Any](os.read_file(state + '/result.json')!)!
  }
  mut frames := []json2.Any{}
  for frame in app['screenshots']!.as_array() {
   path := frame.str()
   frames << json2.Any({'path': json2.Any(path), 'sha256': json2.Any(digest(path)!)})
  }
  app['screenshots'] = frames
  apps << json2.Any(app)
 }
 report['applications'] = apps
 mut artifacts := map[string]json2.Any{}
 for path in ['build/android-framework/api-impl.jar', 'build/android-framework/libvinix-android-framework.so',
  'build/android-framework/editor/overlay/usr/bin/vinix-desktop', 'tests/android/results/2026-10-21/application-driver.v'] {
  artifacts[path] = digest(path)!
 }
 report['artifacts_sha256'] = artifacts
 report['framework'] = json2.decode[json2.Any](os.read_file('build/android-framework/extended/framework-manifest.json')!)!
 os.write_file(output + '/apk-workflows.json', json2.encode(report, prettify: true) + '\n')!
}
