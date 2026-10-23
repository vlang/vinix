import os
import json2
fn main() {
 baseline := os.args.len > 1 && os.args[1] == 'baseline'
 run := 'fixture-lifecycle198' + if baseline {'-baseline'} else {'-fixed'}
 framework := if baseline {'193'} else {'198'}
 native := if baseline {'195'} else {'198'}
 os.cp('build/android-maps/framework'+framework+'/api-impl.jar','build/android-maps/native/api-impl.jar')!
 os.cp('build/android-maps/libnative'+native+'.so','build/android-maps/native/libvinix-android-native.so')!
 mut cfg:=json2.decode[map[string]json2.Any](os.read_file('build/android-maps/fixture-diagnostics190.json')!)!
 mut app:=cfg['applications']!.as_array()[0].as_map().clone()
 app['apk']='build/android-maps/lifecycle198-apk/lifecycle.apk'
 app['id']='lifecycle-fixture'
 app['package']='org.vinix.lifecycle'
 app['source']='tests/native-android-ws/lifecycle-fixture.v'
 cfg['applications']=[json2.Any(app)]
 cfg['output']='build/android-maps/'+run
 path:='build/android-maps/'+run+'.json'
 os.write_file(path,json2.encode(cfg,prettify:true))!
 r:=os.exec(['build/android-maps/suite159',path]); print(r.output); assert r.exit_code==0,r.output
}
