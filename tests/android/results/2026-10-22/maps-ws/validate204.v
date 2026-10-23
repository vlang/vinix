import os
import json2
import crypto.sha256
import compress.gzip
fn log(run string)!string{return gzip.decompress(os.read_bytes('build/android-maps/'+run+'/bootstrap-fixture/serial.log.gz')!)!.bytestr()}
fn main(){
 b:=log('fixture-font204-baseline')!
 f:=log('fixture-font204-fixed')!
 marker:='BOOTSTRAP-FONT-BUILDERS-PASS resource weight slant immutable reuse duplicate selection all-pixels xml range unsupported'
 assert b.contains('NoClassDefFoundError: Failed resolution of: Landroid/graphics/fonts/Font$Builder;')
 assert !b.contains(marker)
 assert f.count(marker)==1
 assert !f.contains('java.lang.AssertionError') && !f.contains('ANDROID-WS-FAIL') && !f.contains('APK-SUITE-EXIT')
 assert f.contains('ANDROID-WS-READY backend=vinix-native gtk=absent x11=absent')
 // Every earlier bootstrap pass remains present, including asynchronous probes.
 old:=gzip.decompress(os.read_bytes('build/android-maps/fixture-order203-fixed/bootstrap-fixture/serial.log.gz')!)!.bytestr()
 mut count:=0
 for line in old.split_into_lines(){
  if !line.starts_with('BOOTSTRAP-') || !line.contains('-PASS'){continue}
  marker2:=line.all_before(' ')
  assert f.contains(marker2),marker2
  count++
 }
 mut hashes:=[]string{}
 for run in ['fixture-font204-baseline','fixture-font204-fixed'] {
  row:=json2.decode[[]map[string]json2.Any](os.read_file('build/android-maps/'+run+'/results.json')!)![0]
  hashes<<row['metadata']!.as_map()['apk_sha256']!.str()
  runtime:=json2.decode[map[string]string](os.read_file('build/android-maps/'+run+'/runtime-sha256.json')!)!
  fw:=if run.ends_with('baseline'){'201'}else{'204'}
  native:=if run.ends_with('baseline'){'200'}else{'204'}
  assert runtime['usr/lib/java/dex/android_translation_layer/api-impl.jar']! == sha256.sum(os.read_bytes('build/android-maps/framework'+fw+'/api-impl.jar')!).hex()
  assert runtime['usr/lib/art/libvinix-android-native.so']! == sha256.sum(os.read_bytes('build/android-maps/libnative'+native+'.so')!).hex()
 }
 assert hashes[0]==hashes[1]
 println('FONT-BUILDERS-VALIDATION PASS same signed APK, expected old-runtime missing-class failure; metadata, immutable builders/families, nearest style selection with all 8192 pixels, invalid/XML/unsupported rejection; '+count.str()+' previous pass markers retained; staged native/framework hashes verified')
}
