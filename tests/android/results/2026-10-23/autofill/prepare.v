import os
import json2
import crypto.sha256

fn main() {
 b := 'build/android-maps/'
 task := b + 'autofill222/'
 os.mkdir_all(task)!
 for mode in ['baseline', 'fixed'] {
  native := task + 'native-' + mode
  os.mkdir_all(native)!
  for item in os.ls(b + 'native')! {
   if item in ['api-impl.jar', 'libvinix-android-native.so', 'popular-launcher'] { continue }
   os.symlink(os.abs_path(b + 'native/' + item), native + '/' + item)!
  }
  jar := b + if mode == 'baseline' { 'framework221-content-capture/api-impl.jar' } else { 'framework222-autofill/api-impl.jar' }
  os.symlink(os.abs_path(jar), native + '/api-impl.jar')!
  os.symlink(os.abs_path(b + 'libnative204.so'), native + '/libvinix-android-native.so')!
  os.symlink(os.abs_path(b + 'launcher200'), native + '/popular-launcher')!
  mut config := json2.decode[map[string]json2.Any](os.read_file(b + 'fixture-observer217-fixed.json')!)!
  config['native_dir'] = native
  config['output'] = task + 'run-' + mode
  mut apps := config['applications']!.as_array()
  mut app := apps[0].as_map()
  app['apk'] = b + 'autofill222-apk/bootstrap.apk'
  app['startup_seconds'] = 40
  apps[0] = app
  config['applications'] = apps
  os.write_file(task + mode + '.json', json2.encode(config, prettify:true))!
  println(mode + ' ' + sha256.sum(os.read_bytes(jar)!).hex())
 }
 os.write_file(task + 'staged-hashes.v', os.read_file(b + 'content-capture221/staged-hashes.v')!.replace('content-capture221', 'autofill222'))!
}
