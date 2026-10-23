import os
import compress.gzip
fn main() {
 base := 'build/android-maps/'
 before := gzip.decompress(os.read_bytes(base+'fixture-affine196-baseline/bootstrap-fixture/serial.log.gz')!)!.bytestr()
 after := gzip.decompress(os.read_bytes(base+'fixture-affine196-fixed/bootstrap-fixture/serial.log.gz')!)!.bytestr()
 assert before.contains('Canvas concat requires translation and scaling')
 assert !before.contains('BOOTSTRAP-AFFINE-PASS')
 for name in ['AFFINE','CLIPPING','TRANSLATED-VISIBLE','TRANSLATED-LOCATION','GEOMETRY','TRANSLATIONS','SCROLL','EDITOR','WINDOW','DRAWABLE','PATH-BOUNDS','MATRIX-RECT','MATRIX-INVERSE','MATRIX-FIT','PICTURE','TEXT-METRICS','FONT-METRICS','CHARACTER-STYLES','SHADOW-COLORS','CHILD-STATES','FRAME-BOUNDS','LAYOUT-SUPPRESSION','NDK','EGL-COMPOSITION','TOUCH','TRAVERSAL','SCROLL-FRAMES','TIME-ANIMATOR','PATH-ANIMATOR-FRAMES','CONNECTIVITY'] {
  assert after.contains('BOOTSTRAP-'+name+'-PASS'),name
 }
 assert !after.contains('java.lang.AssertionError')
 assert !after.contains('APK-SUITE-EXIT id=')
 println('AFFINE196-REGRESSION-PASS: baseline rejects concat; fixed native passes seven 1024-pixel affine cases and 29 existing controls')
}
