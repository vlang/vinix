import os
import json2

fn main() {
 b := os.abs_path('build/android-maps')
 task := b + '/canvas227'
 output := b + '/canvas227-apk'
 assert !os.exists(output)
 os.cp_all(b + '/paint226-apk', output, false)!
 for file in ['classes.dex', 'bootstrap.apk', 'bootstrap.apk.idsig'] {
  if os.exists(output + '/' + file) { os.rm(output + '/' + file)! }
 }
 sources := task + '/source/startupfixture'
 os.mkdir_all(sources)!
 for file in os.walk_ext('tests/native-android-ws/startupfixture', '.v') {
  os.cp(file, sources + '/' + os.base(file))!
 }
 os.write_file(b + '/finalize-canvas227.v', os.read_file(b + '/finalize-paint226.v')!.replace('paint226-apk', 'canvas227-apk'))!
 for mode in ['baseline', 'fixed'] {
  native := task + '/native-' + mode
  os.mkdir_all(native)!
  for item in os.ls(b + '/paint226/native-fixed')! {
   if item == 'api-impl.jar' { continue }
   os.symlink(b + '/paint226/native-fixed/' + item, native + '/' + item)!
  }
  jar := b + if mode == 'baseline' { '/framework226-filters/api-impl.jar' } else { '/framework227-canvas-z/api-impl.jar' }
  os.symlink(jar, native + '/api-impl.jar')!
  mut config := json2.decode[map[string]json2.Any](os.read_file(b + '/paint226/fixed.json')!)!
  config['native_dir'] = native
  config['output'] = task + '/run-' + mode
  mut apps := config['applications']!.as_array()
  mut app := apps[0].as_map()
  app['apk'] = output + '/bootstrap.apk'
  apps[0] = app
  config['applications'] = apps
  os.write_file(task + '/' + mode + '.json', json2.encode(config, prettify: true) + '\n')!
 }
 os.write_file(task + '/staged-hashes.v', os.read_file(b + '/paint226/staged-hashes.v')!.replace('paint226', 'canvas227'))!
 println('Canvas227 fixture sources frozen')
}
