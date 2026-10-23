import os
import json2
import crypto.sha256
import compress.gzip
const base='build/android-maps/'
fn log(run string)!string{return gzip.decompress(os.read_bytes(base+run+'/bootstrap-fixture/serial.log.gz')!)!.bytestr()}
fn main(){
 b:=log('fixture-locales205-baseline')!
 f:=log('fixture-locales205-fixed')!
 marker:='BOOTSTRAP-TEXT-LOCALES-PASS defaults ordered-list primary copy set self reset textview paint layout invalidate invalid'
 assert b.contains('NoSuchMethodError: No virtual method getTextLocales()Landroid/os/LocaleList; in class Landroid/graphics/Paint;')
 assert !b.contains(marker)
 assert f.count(marker)==1
 assert !f.contains('java.lang.AssertionError') && !f.contains('ANDROID-WS-FAIL') && !f.contains('APK-SUITE-EXIT')
 assert f.contains('ANDROID-WS-READY backend=vinix-native gtk=absent x11=absent')
 old:=log('fixture-font204-fixed')!
 mut count:=0
 for line in old.split_into_lines(){
  if !line.starts_with('BOOTSTRAP-') || !line.contains('-PASS'){continue}
  marker2:=line.all_before(' ')
  assert f.contains(marker2),marker2
  count++
 }
 mut hashes:=[]string{}
 for run in ['fixture-locales205-baseline','fixture-locales205-fixed']{
  row:=json2.decode[[]map[string]json2.Any](os.read_file(base+run+'/results.json')!)![0]
  hashes<<row['metadata']!.as_map()['apk_sha256']!.str()
  runtime:=json2.decode[map[string]string](os.read_file(base+run+'/runtime-sha256.json')!)!
  fw:=if run.ends_with('baseline'){'204'}else{'205'}
  assert runtime['usr/lib/java/dex/android_translation_layer/api-impl.jar']! == sha256.sum(os.read_bytes(base+'framework'+fw+'/api-impl.jar')!).hex()
  assert runtime['usr/lib/art/libvinix-android-native.so']! == sha256.sum(os.read_bytes(base+'libnative204.so')!).hex()
 }
 assert hashes[0]==hashes[1]
 println('TEXT-LOCALES-VALIDATION PASS same signed APK, expected old-runtime missing-method failure; default snapshots, ordered list, primary locale, copy/set/self-set/reset, TextView Paint propagation, layout/invalidate and invalid inputs; '+count.str()+' previous pass markers retained; staged native/framework hashes verified')
}
