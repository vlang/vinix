import os
import json2
import crypto.sha256
import compress.gzip

struct Receipt {
 artifacts map[string]string
 inputs map[string]string
 scope string
}

fn main() {
 out := os.dir(@FILE)
 receipt := json2.decode[Receipt](os.read_file(out + '/receipt.json')!)!
 for name, expected in receipt.artifacts {
  assert sha256.sum(os.read_bytes(out + '/' + name)!).hex() == expected, name
 }
 sources := json2.decode[map[string]string](gzip.decompress(os.read_bytes(out + '/fixture-sources.json.gz')!)!.bytestr())!
 hashes := json2.decode[map[string]string](os.read_file(out + '/fixture-sources-sha256.json')!)!
 assert sources.len == hashes.len
 for name, source in sources { assert sha256.sum(source.bytes()).hex() == hashes[name], name }
 manifest := json2.decode[map[string]json2.Any](os.read_file(out + '/framework-manifest.json')!)!
 framework := json2.decode[map[string]string](gzip.decompress(os.read_bytes(out + '/framework-sources.json.gz')!)!.bytestr())!
 assert framework.len == 103
 for path, source in framework { assert sha256.sum(source.bytes()).hex() == manifest['sources']!.as_map()[path]!.str(), path }
 baseline := gzip.decompress(os.read_bytes(out + '/baseline-serial.log.gz')!)!.bytestr()
 fixed := gzip.decompress(os.read_bytes(out + '/fixed-serial.log.gz')!)!.bytestr()
 assert baseline.contains('No virtual method enableZ()V in class Landroid/graphics/Canvas;')
 assert baseline.contains('org.vinix.bootstrap.CanvasZProbe.check')
 assert !baseline.contains('BOOTSTRAP-CANVAS-Z-PASS')
 for marker in ['BOOTSTRAP-ALPHA8-PASS', 'BOOTSTRAP-ALPHA8-GL-PASS', 'BOOTSTRAP-PAINT-FILTERS-PASS',
  'BOOTSTRAP-CANVAS-Z-PASS', 'ANDROID-WS-READY backend=vinix-native gtk=absent x11=absent'] { assert fixed.contains(marker), marker }
 assert !fixed.contains('ANDROID-WS-FAIL') && !fixed.contains('java.lang.AssertionError')
 assert !fixed.contains('APK-SUITE-EXIT id=bootstrap-fixture')
 for variant, serial in {'baseline': baseline, 'fixed': fixed} {
  rows := json2.decode[[]json2.Any](os.read_file(out + '/' + variant + '-results.json')!)!
  row := rows[0].as_map()
  assert sha256.sum(serial.bytes()).hex() == row['serial_sha256']!.str()
  assert row['metadata']!.as_map()['apk_sha256']!.str() == receipt.inputs['build/android-maps/canvas227-apk/bootstrap.apk']
  if variant == 'fixed' {
   assert row['backend_ready']!.bool() && !row['process_exited']!.bool()
   for value in row['failure_markers']!.as_array() {
    line := value.str()
    assert (line.contains('NoSuchFieldError:') && line.contains('Lnge;') && line.contains('Lorg/vinix/bootstrap/Main;')) || line == 'Caused by: java.lang.ClassNotFoundException: nge', line
   }
  }
 }
 previous := gzip.decompress(os.read_bytes(out + '/../paint-filters/fixed-serial.log.gz')!)!.bytestr()
 mut markers := []string{}
 for line in previous.split_into_lines() {
  if !line.starts_with('BOOTSTRAP-') || !line.contains('-PASS') { continue }
  name := line.all_before(' ')
  if name in markers { continue }
  assert fixed.contains(name), name
  markers << name
 }
 native_path := '/staged/opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'
 assert receipt.inputs['baseline' + native_path] == receipt.inputs['fixed' + native_path]
 assert receipt.inputs['fixed' + native_path] == '592cef0d9d52b9a2795ba78724b6b1b514299511a897996a0d994e7fb56c5f3a'
 for path in ['usr/bin/run-android-calculator', 'opt/android-test/native-guest'] {
  assert receipt.inputs['baseline/staged/' + path] == receipt.inputs['fixed/staged/' + path]
 }
 for variant in ['baseline', 'fixed'] {
  expected := receipt.inputs['build/android-maps/' + if variant == 'baseline' { 'framework226-filters' } else { 'framework227-canvas-z' } + '/api-impl.jar']
  assert receipt.inputs[variant + '/staged/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'] == expected
  actual := gzip.decompress(os.read_bytes(out + '/' + variant + '-Canvas.smali.gz')!)!.bytestr()
  for name in ['enableZ', 'disableZ'] {
   assert actual.contains('.method public ' + name + '()V') == (variant == 'fixed')
  }
 }
 assert sources['canvas_z.v'].contains('translated-clip 16-pixels recording-inherited-api playback')
 println('CANVAS-Z-VALIDATION PASS baseline missing API reproduced; fixed pixels/state/recording inherited API +${markers.len} prior probes +READY; exact source and staged runtime hashes; raw harness diagnostic limitation retained')
}
