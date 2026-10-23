import os
import json2
fn main() {
 baseline := os.args.len > 1 && os.args[1] == 'baseline'
 id := if baseline { 'fixture-lifecycle195-baseline' } else { 'fixture-lifecycle195' }
 os.cp('build/android-maps/framework'+if baseline {'184'} else {'193'}+'/api-impl.jar','build/android-maps/native/api-impl.jar')!
 os.cp('build/android-maps/libnative'+if baseline {'189'} else {'195'}+'.so','build/android-maps/native/libvinix-android-native.so')!
 mut cfg:=json2.decode[map[string]json2.Any](os.read_file('build/android-maps/fixture-diagnostics190.json')!)!
 mut apps:=cfg['applications']!.as_array()
 mut app:=apps[0].as_map()
 app['apk']='build/android-maps/lifecycle193-apk/lifecycle.apk'
 app['id']='lifecycle-fixture'
 app['package']='org.vinix.lifecycle'
 app['source']='tests/native-android-ws/lifecycle-fixture.v'
 apps[0]=app
 cfg['applications']=apps
 cfg['output']='build/android-maps/'+id
 path:='build/android-maps/'+id+'.json'
 os.write_file(path,json2.encode(cfg,prettify:true))!
 r:=os.exec(['build/android-maps/suite159',path]); print(r.output); assert r.exit_code==0,r.output
}
