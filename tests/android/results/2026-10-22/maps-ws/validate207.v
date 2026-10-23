import os
import json2
import crypto.sha256
import compress.gzip
const base='build/android-maps/'
fn log(run string)!string{return gzip.decompress(os.read_bytes(base+run+'/bootstrap-fixture/serial.log.gz')!)!.bytestr()}
fn main(){
 b:=log('fixture-render207-baseline')!
 broken:=log('fixture-render207-fixed')!
 missing_equals:=log('fixture-render207-fixed2')!
 assert missing_equals.contains('UnsatisfiedLinkError: No implementation found for boolean android.graphics.Matrix.native_equals')
 final_baseline:=log('fixture-render207-baseline2')!
 assert final_baseline.contains('NoClassDefFoundError: Failed resolution of: Landroid/graphics/RenderNode;')
 null_matrix:=log('fixture-render207-fixed3')!
 assert null_matrix.contains('NullPointerException') && null_matrix.contains('android.graphics.Canvas.setMatrix')
 clip_stub:=log('fixture-render207-fixed4')!
 assert clip_stub.contains('STUB: clipPath') && clip_stub.contains('RenderNodeProbe.pixels5')
 nested_expectation:=log('fixture-render207-fixed5')!
 assert nested_expectation.contains('RenderNodeProbe.pixels7') && nested_expectation.contains('java.lang.AssertionError')
 final_baseline2:=log('fixture-render207-baseline3')!
 assert final_baseline2.contains('NoClassDefFoundError: Failed resolution of: Landroid/graphics/RenderNode;')
 f:=log('fixture-render207-fixed6')!
 marker:='BOOTSTRAP-RENDER-NODE-PASS recording-state stable-identity 13312-pixels paint-snapshot transforms bounds clip-rect outline group-alpha live-child replace discard canvas-state cycle-recovery'
 assert b.contains('NoClassDefFoundError: Failed resolution of: Landroid/graphics/RenderNode;') && !b.contains(marker)
 assert broken.contains('VerifyError: Verifier rejected class android.graphics.RenderNode') && !broken.contains(marker)
 assert f.count(marker)==1
 assert !f.contains('java.lang.AssertionError') && !f.contains('ANDROID-WS-FAIL') && !f.contains('APK-SUITE-EXIT')
 assert f.contains('ANDROID-WS-READY backend=vinix-native gtk=absent x11=absent')
 old:=log('fixture-drawing206-fixed')!
 mut count:=0
 for line in old.split_into_lines(){
  if !line.starts_with('BOOTSTRAP-') || !line.contains('-PASS'){continue}
  marker2:=line.all_before(' ')
  assert f.contains(marker2),marker2
  count++
 }
 mut hashes:=[]string{}
 for run in ['fixture-render207-baseline','fixture-render207-fixed','fixture-render207-fixed2','fixture-render207-baseline2','fixture-render207-fixed3','fixture-render207-fixed4','fixture-render207-fixed5','fixture-render207-baseline3','fixture-render207-fixed6']{
  row:=json2.decode[[]map[string]json2.Any](os.read_file(base+run+'/results.json')!)![0]
  hashes<<row['metadata']!.as_map()['apk_sha256']!.str()
  runtime:=json2.decode[map[string]string](os.read_file(base+run+'/runtime-sha256.json')!)!
  fw:=match run {'fixture-render207-baseline', 'fixture-render207-baseline2', 'fixture-render207-baseline3' {'framework206/api-impl.jar'} 'fixture-render207-fixed' {'framework207-initial.jar'} 'fixture-render207-fixed2', 'fixture-render207-fixed3' {'framework207-null-matrix.jar'} 'fixture-render207-fixed4' {'framework207-clip-stub.jar'} else {'framework207/api-impl.jar'}}
  assert runtime['usr/lib/java/dex/android_translation_layer/api-impl.jar']! == sha256.sum(os.read_bytes(base+fw)!).hex()
  assert runtime['usr/lib/art/libvinix-android-native.so']! == sha256.sum(os.read_bytes(base+'libnative204.so')!).hex()
 }
 assert hashes[0]=='9c7acb735123ee589f7a4971279406a96a45b31f89a8ceee35e3c677f095aa91'
 assert hashes[1]==hashes[2]
 assert hashes[1]==sha256.sum(os.read_bytes(base+'render207-initial.apk')!).hex()
 assert hashes[3..7].all(it==hashes[3]) && hashes[3]==sha256.sum(os.read_bytes(base+'render207-final-apk/bootstrap.apk')!).hex()
 assert hashes[7]==hashes[8] && hashes[7]==sha256.sum(os.read_bytes(base+'render207-final2-apk/bootstrap.apk')!).hex()
 println('RENDER-NODE-VALIDATION PASS same final signed APK against old and fixed runtimes; all initial and intermediate failures retained; recording lifecycle and stable identity; 13312 independently expected pixels for command snapshots, affine transforms, bounds, rectangular outline, clip rect, group opacity and compositing Paint snapshot; live child updates, list replacement/discard; canvas restoration and recovery after direct and offscreen cycle errors; '+count.str()+' previous pass markers retained; staged framework/native hashes verified')
}
