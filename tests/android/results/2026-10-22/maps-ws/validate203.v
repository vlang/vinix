import os
import json2
import compress.gzip
fn log(run string)!string{return gzip.decompress(os.read_bytes('build/android-maps/'+run+'/bootstrap-fixture/serial.log.gz')!)!.bytestr()}
fn main(){
 b:=log('fixture-order203-baseline')!
 f:=log('fixture-order203-fixed')!
 marker:='BOOTSTRAP-CHILD-ORDER-PASS view parent already-top foreign orphan stable-order parent params token attachment hierarchy layout invalidate all-pixels touch'
 assert b.contains('java.lang.AssertionError: child stacking order or preserved hierarchy')
 assert !b.contains(marker)
 assert f.count(marker)==1
 assert !f.contains('java.lang.AssertionError') && !f.contains('ANDROID-WS-FAIL') && !f.contains('APK-SUITE-EXIT')
 assert f.contains('ANDROID-WS-READY backend=vinix-native gtk=absent x11=absent')
 for name in ['AFFINE','CLIPPING','TRANSLATED-VISIBLE','TRANSLATED-LOCATION','GEOMETRY','TRANSLATIONS','SCROLL','EDITOR','WINDOW','DRAWABLE','PATH-BOUNDS','MATRIX-RECT','MATRIX-INVERSE','MATRIX-FIT','PICTURE','TEXT-METRICS','FONT-METRICS','CHARACTER-STYLES','SHADOW-COLORS','CHILD-STATES','FRAME-BOUNDS','LAYOUT-SUPPRESSION','NDK','EGL-COMPOSITION','TOUCH','TRAVERSAL','SCROLL-FRAMES','TIME-ANIMATOR','PATH-ANIMATOR-FRAMES','CONNECTIVITY'] {
  assert f.contains('BOOTSTRAP-'+name+'-PASS'),name
 }
 mut rows:=[]map[string]json2.Any{}
 for run in ['fixture-order203-baseline','fixture-order203-fixed']{rows<<json2.decode[[]map[string]json2.Any](os.read_file('build/android-maps/'+run+'/results.json')!)![0]}
 assert rows[0]['metadata']!.as_map()['apk_sha256']!.str()==rows[1]['metadata']!.as_map()['apk_sha256']!.str()
 for run in ['fixture-order203-baseline','fixture-order203-fixed']{runtime:=json2.decode[map[string]string](os.read_file('build/android-maps/'+run+'/runtime-sha256.json')!)!;for file,value in runtime{if file.ends_with('/api-impl.jar') || file.ends_with('/libvinix-android-native.so'){println(run+' '+file+' '+value)}}}
 println('CHILD-ORDER-VALIDATION PASS same signed APK: expected baseline assertion; fixed stable child order, four 1024-pixel and touch cases, attachment/parent/params/token preservation, hierarchy silence, layout/invalidate, foreign/orphan no-ops; prior bootstrap controls complete')
}
