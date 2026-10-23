import os
import json2
import crypto.sha256

fn main() {
 assert os.args.len == 2 && os.args[1] in ['setup', 'baseline', 'fixed', 'baseline2', 'fixed2']
 base := 'build/android-maps/'
 task := base + 'observer-verify/'
 if os.args[1] == 'setup' {
  os.mkdir_all(task)!
  os.cp_all(base + 'native', task + 'native', true)!
  for name in ['boot.img', 'efivars.fd'] {
   r := os.exec(['cp', '-c', 'build/android-native-ws/vm/' + name, task + name])
   assert r.exit_code == 0, r.output
  }
  os.cp(base + 'libnative204.so', task + 'native/libvinix-android-native.so')!
  os.cp(base + 'launcher200', task + 'native/popular-launcher')!
  for mode in ['baseline', 'fixed'] {
   mut cfg := json2.decode[map[string]json2.Any](os.read_file(base + 'fixture-observer217-' + mode + '.json')!)!
   cfg['native_dir'] = task + 'native'
   cfg['output'] = task + mode
   cfg['boot_image'] = task + 'boot.img'
   cfg['efivars'] = task + 'efivars.fd'
   os.write_file(task + mode + '.json', json2.encode(cfg, prettify: true))!
  }
  return
 }
 mode := os.args[1]
 final_run := mode.ends_with('2')
 fw := if mode.starts_with('baseline') { '211' } else if final_run { '217-observer2' } else { '217' }
 if final_run {
  if !os.exists(task + 'boot.img') {
   for name in ['boot.img', 'efivars.fd'] {
    r := os.exec(['cp', '-c', 'build/android-native-ws/vm/' + name, task + name])
    assert r.exit_code == 0, r.output
   }
  }
  original_mode := mode.trim_right('2')
  mut cfg := json2.decode[map[string]json2.Any](os.read_file(task + original_mode + '.json')!)!
  cfg['output'] = task + mode
  mut apps := cfg['applications']!.as_array()
  mut app := apps[0].as_map()
  app['apk'] = base + 'observer2-apk/bootstrap.apk'
  apps[0] = app
  cfg['applications'] = apps
  os.write_file(task + mode + '.json', json2.encode(cfg, prettify: true))!
 }
 os.cp(base + 'framework' + fw + '/api-impl.jar', task + 'native/api-impl.jar')!
 println('FRAMEWORK ' + sha256.sum(os.read_bytes(task + 'native/api-impl.jar')!).hex())
 r := os.exec([base + 'suite159', task + mode + '.json'])
 print(r.output)
 assert r.exit_code == 0, r.output
 mut hashes := map[string]string{}
 for name in ['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar',
  'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so', 'usr/bin/run-android',
  'usr/bin/run-android-calculator', 'usr/bin/vinix-desktop', 'opt/android-test/native-guest'] {
  hashes[name] = sha256.sum(os.read_bytes(task + mode + '/module/' + name)!).hex()
 }
 os.write_file(task + mode + '/staged-runtime-sha256.json', json2.encode(hashes, prettify: true))!
 os.rmdir_all(task + mode + '/module')!
}
