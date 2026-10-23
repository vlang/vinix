import os
import json2
import crypto.sha256
fn main() {
 b:=os.abs_path('build/android-maps/lookup237')
 assert !os.exists(b)
 os.mkdir_all(b)!
 os.cp('tests/native-android-ws/lookup-trace-fixture.v',b+'/lookup-trace-fixture.v')!
 for mode in ['baseline','off','on'] {
  dir:=b+'/native-'+mode
  os.mkdir_all(dir)!
  for name in os.ls('build/android-maps/interpolators234/native-fixed235')! {
   if name in ['api-impl.jar','popular-launcher'] { continue }
   os.symlink(os.abs_path('build/android-maps/interpolators234/native-fixed235/'+name),dir+'/'+name)!
  }
  jar:=if mode=='baseline' {'framework236-texture'} else {'framework237-lookup'}
  os.symlink(os.abs_path('build/android-maps/'+jar+'/api-impl.jar'),dir+'/api-impl.jar')!
  env:= if mode=='on' { "os.setenv('VINIX_ANDROID_TRACE_VIEW_LOOKUP', '1', true)\n" } else { "os.unsetenv('VINIX_ANDROID_TRACE_VIEW_LOOKUP')\n" }
  expect:=if mode=='off' {'0'} else {'1'}
  old:=os.read_file('tests/native-android-ws/launcher.v')!
  launcher:=old.replace_once('fn main() {\n', 'fn main() {\n'+env+"os.setenv('LOOKUP_EXPECT_TRACE', '"+expect+"', true)\n")
  os.write_file(b+'/launcher-'+mode+'.v',launcher)!
  mut config:=json2.decode[map[string]json2.Any](os.read_file('build/android-maps/texture236/fixed.json')!)!
  mut apps:=config['applications']!.as_array()
  mut app:=apps[0].as_map()
  app['apk']=os.abs_path('build/android-maps/lookup237-apk/probe.apk')
  app['source']='tests/native-android-ws/lookup-trace-fixture.v'
  app['startup_seconds']=45
  apps[0]=json2.Any(app)
  config['applications']=json2.Any(apps)
  config['native_dir']=dir
  config['output']=b+'/run-'+mode
  os.write_file(b+'/'+mode+'.json',json2.encode(config,prettify:true)+'\n')!
 }
 os.write_file(b+'/apk-sha256.txt',sha256.sum(os.read_bytes('build/android-maps/lookup237-apk/probe.apk')!).hex()+'\n')!
 println('LOOKUP237 PREPARED baseline/off/on same signed APK native235')
}
