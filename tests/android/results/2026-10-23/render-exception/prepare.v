import os
import json2

fn main() {
 b := os.abs_path('build/android-maps')
 task := b + '/render230'
 os.mkdir_all(task)!
 for mode in ['baseline', 'fixed'] {
  native := task + '/native-' + mode
  os.mkdir_all(native)!
  for name in os.ls(b + '/canvas227/native-fixed')! {
   if name in ['api-impl.jar', 'libvinix-android-native.so'] { continue }
   os.symlink(b + '/canvas227/native-fixed/' + name, native + '/' + name)!
  }
  os.symlink(b + '/framework228-outline/api-impl.jar', native + '/api-impl.jar')!
  library := b + if mode == 'baseline' { '/libnative228.so' } else { '/libnative230.so' }
  os.symlink(library, native + '/libvinix-android-native.so')!
  mut cfg := json2.decode[map[string]json2.Any](os.read_file(b + '/canvas227/fixed.json')!)!
  cfg['native_dir'] = native
  cfg['output'] = task + '/run-' + mode
  mut apps := cfg['applications']!.as_array()
  mut app := apps[0].as_map()
  app['apk'] = b + '/render230-apk/probe.apk'
  app['id'] = 'render-exception'
  app['name'] = 'Render exception regression'
  app['source'] = 'tests/native-android-ws/render-exception-fixture.v'
  app['startup_seconds'] = 30
  apps[0] = app
  cfg['applications'] = apps
  os.write_file(task + '/' + mode + '.json', json2.encode(cfg, prettify: true) + '\n')!
 }
}
