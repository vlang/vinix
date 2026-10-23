import os
import json2
import crypto.sha256

fn checked(args []string) ! {
 r := os.exec(args)
 if r.exit_code != 0 { return error(r.output) }
}

fn main() {
 b := 'build/android-maps/'
 fixture := b + 'content-capture221'
 os.mkdir_all(fixture)!
 assert os.is_file(fixture + '/baseline.jar')
 for mode in ['baseline', 'fixed'] {
  native := fixture + '/native-' + mode
  os.mkdir_all(native)!
  for item in os.ls(b + 'native')! {
   source := b + 'native/' + item
   if item in ['api-impl.jar', 'libvinix-android-native.so', 'popular-launcher'] { continue }
   os.symlink(os.abs_path(source), native + '/' + item)!
  }
  jar := if mode == 'baseline' { fixture + '/baseline.jar' } else { b + 'framework221-content-capture/api-impl.jar' }
  os.symlink(os.abs_path(jar), native + '/api-impl.jar')!
  os.symlink(os.abs_path(b + 'libnative204.so'), native + '/libvinix-android-native.so')!
  os.symlink(os.abs_path(b + 'launcher200'), native + '/popular-launcher')!
  mut config := json2.decode[map[string]json2.Any](os.read_file(b + 'fixture-observer217-fixed.json')!)!
  config['native_dir'] = native
  config['output'] = fixture + '/run-' + mode
  mut apps := config['applications']!.as_array()
  mut app := apps[0].as_map()
  app['apk'] = b + 'content-capture221-apk/bootstrap.apk'
  app['startup_seconds'] = 40
  apps[0] = app
  config['applications'] = apps
  os.write_file(fixture + '/' + mode + '.json', json2.encode(config, prettify:true))!
  println(mode + ' ' + sha256.sum(os.read_bytes(jar)!).hex())
 }
}
