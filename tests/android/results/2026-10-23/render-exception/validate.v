import os
import json2
import crypto.sha256
import compress.gzip

fn main() {
 root := os.dir(@FILE) + '/'
 receipt := json2.decode[map[string]json2.Any](os.read_file(root + 'identities.json')!)!
 artifacts := receipt['artifacts_sha256']!.as_map()
 for name, digest in artifacts {
  assert sha256.sum(os.read_bytes(root + name)!).hex() == digest.str(), name
 }
 assert sha256.sum(gzip.decompress(os.read_bytes(root + 'fixture-classes.dex.gz')!)!).hex() == receipt['dex_sha256']!.str()
 mut native := map[string]map[string]string{}
 for variant in ['228', '230'] {
  manifest := json2.decode[map[string]string](os.read_file(root + 'native' + variant + '-sources.json')!)!
  sources := json2.decode[map[string]string](gzip.decompress(os.read_bytes(root + 'native' + variant + '-sources.json.gz')!)!.bytestr())!
  assert sources.len == 81 && sources.len == manifest.len
  for name, content in sources { assert sha256.sum(content.bytes()).hex() == manifest[name]!, name }
  native[variant] = sources
 }
 for name, source in native['228']! {
  if name == 'runtime.v' {
   expected := source.replace('\t\t\tws_input(e)\n', '\t\t\t// Rendering may leave the original Java exception pending. Input\n\t\t\t// dispatch uses JNI calls that are forbidden until it is reported.\n\t\t\tif !pending(e) { ws_input(e) }\n')
   assert expected != source && expected == native['230']![name]!
  } else { assert source == native['230']![name]!, name }
 }
 framework := json2.decode[map[string]string](gzip.decompress(os.read_bytes(root + 'framework-sources.json.gz')!)!.bytestr())!
 manifest := json2.decode[map[string]json2.Any](os.read_file(root + 'framework-manifest.json')!)!['sources']!.as_map()
 assert framework.len == 104 && manifest.len == 104
 for name, content in framework { assert sha256.sum(content.bytes()).hex() == manifest[name]!.str(), name }
 runtime := receipt['staged_runtime_sha256']!.as_map()
 baseline := runtime['baseline']!.as_map()
 fixed := runtime['fixed']!.as_map()
 assert baseline.len == 7 && fixed.len == 7
 native_path := 'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'
 assert baseline[native_path]!.str() == '37d54bcc10b6ada24bdfb71bd54442fc582edf5a536478bd31006d40a15c7137'
 assert fixed[native_path]!.str() == 'befb00a26f77a2b2674eea0590fb0e3880f0c5161fc717ab572b3d4117616d7b'
 for name, digest in baseline { if name != native_path { assert digest.str() == fixed[name]!.str(), name } }
 for mode in ['baseline', 'fixed'] {
  row := json2.decode[[]json2.Any](os.read_file(root + mode + '-results.json')!)![0].as_map()
  serial := gzip.decompress(os.read_bytes(root + mode + '-serial.log.gz')!)!
  log := serial.bytestr()
  assert sha256.sum(serial).hex() == row['serial_sha256']!.str()
  assert row['metadata']!.as_map()['apk_sha256']!.str() == receipt['apk_sha256']!.str()
  assert row['outcome']!.str() == 'startup_failed' && row['backend_ready']!.bool()
  assert log.contains('RENDER-EXCEPTION-POSITION-WINDOW') && log.contains('RENDER-EXCEPTION-DRAW-ENTER')
  assert log.contains('java.lang.IllegalStateException: expected queued-input render failure')
  assert log.contains('org.vinix.bootstrap.DrawFailureView.onDraw')
  assert !log.contains('RENDER-EXCEPTION-UNEXPECTED-TOUCH')
  expected := '1'
  assert log.contains('APK-SUITE-EXIT id=render-exception code=' + expected + ' native_observed=true gtk_x11_absent=true')
  if mode == 'baseline' {
   assert log.contains('JNI DETECTED ERROR IN APPLICATION') && log.contains('in call to NewLocalRef')
   assert log.contains('Fatal signal 6 (SIGABRT)') && log.contains('HandleUnexpectedSignal reentered')
  } else {
   assert log.contains('ANDROID-WS-FAIL input or render')
   assert !log.contains('JNI DETECTED ERROR IN APPLICATION') && !log.contains('Aborting thread')
   assert !log.contains('Fatal signal') && !log.contains('HandleUnexpectedSignal reentered')
  }
  interaction := os.read_file(root + mode + '-interaction.log')!
  assert interaction.contains('POINTER-POSITIONED at=') && interaction.contains('BUTTON-DOWN-QUEUED at=')
 }
 println('RENDER-EXCEPTION PASS ${artifacts.len} artifact hashes;162 native sources/only runtime guard differs;104 framework sources;identical APK/framework/common runtime;baseline original render exception + JNI fatal/SIGABRT then launcher exit1;fixed original render exception exit1 without input JNI fatal')
}
