import os
import json2
import crypto.sha256
import compress.gzip
const base='build/android-maps/'
fn log(run string)!string{return gzip.decompress(os.read_bytes(base+run+'/bootstrap-fixture/serial.log.gz')!)!.bytestr()}
fn main(){
 b:=log('fixture-drawing206-baseline')!
 f:=log('fixture-drawing206-fixed')!
 marker:='BOOTSTRAP-DRAWING-IDS-PASS concurrent-shared 256-unique stable layout reparent constructors resource-id-independent'
 assert b.contains('NoSuchMethodError: No virtual method getUniqueDrawingId()J in class Landroid/view/View;')
 assert !b.contains(marker)
 assert f.count(marker)==1
 assert !f.contains('java.lang.AssertionError') && !f.contains('ANDROID-WS-FAIL') && !f.contains('APK-SUITE-EXIT')
 assert f.contains('ANDROID-WS-READY backend=vinix-native gtk=absent x11=absent')
 old:=log('fixture-locales205-fixed')!
 mut count:=0
 for line in old.split_into_lines(){
  if !line.starts_with('BOOTSTRAP-') || !line.contains('-PASS'){continue}
  marker2:=line.all_before(' ')
  assert f.contains(marker2),marker2
  count++
 }
 mut hashes:=[]string{}
 for run in ['fixture-drawing206-baseline','fixture-drawing206-fixed']{
  row:=json2.decode[[]map[string]json2.Any](os.read_file(base+run+'/results.json')!)![0]
  hashes<<row['metadata']!.as_map()['apk_sha256']!.str()
  runtime:=json2.decode[map[string]string](os.read_file(base+run+'/runtime-sha256.json')!)!
  fw:=if run.ends_with('baseline'){'205'}else{'206'}
  assert runtime['usr/lib/java/dex/android_translation_layer/api-impl.jar']! == sha256.sum(os.read_bytes(base+'framework'+fw+'/api-impl.jar')!).hex()
  assert runtime['usr/lib/art/libvinix-android-native.so']! == sha256.sum(os.read_bytes(base+'libnative204.so')!).hex()
 }
 assert hashes[0]==hashes[1]
 println('DRAWING-IDS-VALIDATION PASS same signed APK, expected old-runtime missing-method failure; concurrent shared first access, 256 unique objects, stable layout/reparent, all constructors and duplicate resource IDs; '+count.str()+' previous pass markers retained; staged native/framework hashes verified')
}
