import os
import json2
import crypto.sha256
import compress.gzip
const base='build/android-maps/'
fn hash(path string)!string{return sha256.sum(os.read_bytes(path)!).hex()}
fn log(run string)!string{return gzip.decompress(os.read_bytes(base+run+'/bootstrap-fixture/serial.log.gz')!)!.bytestr()}
fn main(){
 b:=log('fixture-layout208-baseline')!
 f:=log('fixture-layout208-fixed')!
 marker:='BOOTSTRAP-LAYOUT-CANVAS-PASS virtual-text utf16 multiline wrap empty baselines 12288-pixels picture render-node paint-snapshot target transform clip'
 assert b.contains('UnsatisfiedLinkError: No implementation found for void android.text.Layout.native_draw_custom_canvas') && !b.contains(marker)
 assert f.count(marker)==1
 assert !f.contains('java.lang.AssertionError') && !f.contains('ANDROID-WS-FAIL') && !f.contains('APK-SUITE-EXIT')
 assert f.contains('ANDROID-WS-READY backend=vinix-native gtk=absent x11=absent')
 old:=log('fixture-render207-fixed6')!
 mut count:=0
 for line in old.split_into_lines(){
  if !line.starts_with('BOOTSTRAP-') || !line.contains('-PASS'){continue}
  marker2:=line.all_before(' ')
  assert f.contains(marker2),marker2
  count++
 }
 for mode in ['baseline','fixed']{
  run:='fixture-layout208-'+mode
  row:=json2.decode[[]map[string]json2.Any](os.read_file(base+run+'/results.json')!)![0]
  assert row['metadata']!.as_map()['apk_sha256']!.str()==hash(base+'layout208-apk/bootstrap.apk')!
  runtime:=json2.decode[map[string]string](os.read_file(base+run+'/runtime-sha256.json')!)!
  fw:=if mode=='baseline' {'207'} else {'208'}
  assert runtime['usr/lib/java/dex/android_translation_layer/api-impl.jar']! ==hash(base+'framework'+fw+'/api-impl.jar')!
  assert runtime['usr/lib/art/libvinix-android-native.so']! ==hash(base+'libnative204.so')!
 }
 println('LAYOUT-CANVAS-VALIDATION PASS same signed APK against old and fixed runtimes; virtual text dispatch with UTF16, multiline, wrapping, empty lines and independent baselines; 12288 pixels for Picture/RenderNode recording, Paint snapshots and translated/clipped bitmap targets; '+count.str()+' previous pass markers retained; staged framework/native hashes verified')
}
