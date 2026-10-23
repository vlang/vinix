import os
import json2
import crypto.sha256
import compress.gzip

const base = 'build/android-maps/'
const dest = 'tests/android/results/2026-10-23/maps-ws/'

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn main() {
 mut artifacts := map[string]json2.Any{}
 for source, name in {
  base + 'native228-sources.json': 'native228-sources.json'
  base + 'build-native228.v': 'attempt228-native-build.v'
  base + 'rebuild-native228.v': 'attempt228-native-rebuild.v'
  base + 'native228-identity.txt': 'attempt228-native-identity.txt'
  base + 'framework228-outline/framework-manifest.json': 'attempt228-framework-manifest.json'
  base + 'framework228-outline/exact-sources.json.gz': 'attempt228-framework-sources.json.gz'
  base + 'build-framework228-outline.v': 'attempt228-framework-build.v'
  base + 'prepare-framework228.v': 'attempt228-framework-prepare.v'
  base + 'retain228-inputs.v': 'retain228-inputs.v'
 } { os.cp(source, dest + name)!; artifacts[name] = hash(dest + name)! }
 native_manifest := json2.decode[map[string]string](os.read_file(base + 'native228-sources.json')!)!
 mut native_sources := map[string]string{}
 for name, digest in native_manifest {
  path := base + 'native228/atlframework/' + name
  assert hash(path)! == digest, name
  native_sources[name] = os.read_file(path)!
 }
 assert native_sources.len == 81
 native_archive := 'attempt228-native-sources.json.gz'
 os.write_file_array(dest + native_archive, gzip.compress(json2.encode(native_sources).bytes())!)!
 restored := json2.decode[map[string]string](gzip.decompress(os.read_bytes(dest + native_archive)!)!.bytestr())!
 assert restored.len == native_manifest.len
 for name, source in restored { assert sha256.sum(source.bytes()).hex() == native_manifest[name]!, name }
 artifacts[native_archive] = hash(dest + native_archive)!
 framework_manifest := json2.decode[map[string]json2.Any](os.read_file(dest + 'attempt228-framework-manifest.json')!)!['sources']!.as_map()
 framework_sources := json2.decode[map[string]string](gzip.decompress(os.read_bytes(dest + 'attempt228-framework-sources.json.gz')!)!.bytestr())!
 assert framework_sources.len == framework_manifest.len
 for name, source in framework_sources { assert sha256.sum(source.bytes()).hex() == framework_manifest[name]!.str(), name }
 mut staged := map[string]json2.Any{}
 for path in ['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so',
  'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar',
  'usr/bin/run-android', 'usr/bin/run-android-calculator', 'usr/bin/vinix-desktop',
  'usr/bin/vinix-session', 'opt/android-test/native-guest'] {
  staged[path] = hash(base + 'attempt228/module/' + path)!
 }
 native_path := 'opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so'
 jar_path := 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
 assert staged[native_path]!.str() == '37d54bcc10b6ada24bdfb71bd54442fc582edf5a536478bd31006d40a15c7137'
 assert hash(base + 'libnative228.so')! == staged[native_path]!.str()
 assert staged[jar_path]!.str() == '26b21262b67e92c77bcf57b9480bc881b0683ac0e8d6f97dba105ef453f3fe5a'
 assert hash(base + 'framework228-outline/api-impl.jar')! == staged[jar_path]!.str()
 prior := json2.decode[map[string]json2.Any](os.read_file(dest + 'attempt227-input-identities.json')!)!['staged_runtime_sha256']!.as_map()
 for path, digest in staged {
  if path != native_path && path != jar_path { assert digest.str() == prior[path]!.str(), path }
 }
 mut build_inputs := map[string]json2.Any{}
 for name in ['androidfw_c_api.h', 'sqlite3.h', 'stb_image.h', 'stb_truetype.h', 'android-native.c'] {
  build_inputs[name] = hash(base + 'native228/' + name)!
 }
 receipt := {
  'artifacts_sha256': json2.Any(artifacts)
  'staged_runtime_sha256': json2.Any(staged)
  'native_source_files': json2.Any(native_sources.len)
  'framework_source_files': json2.Any(framework_sources.len)
  'native_additional_build_inputs_sha256': json2.Any(build_inputs)
  'source_scope': json2.Any('All 81 native V sources match the declared native228 manifest; their exact text is archived and checked again after decoding. Native228 was built from native225 plus graphics.v, canvases.v, ws_views.v, new path_clipping.v and an explicit generated JNI clipPath wrapper. The tracked ws_views copy removes old WS-DIAG209-only functions; other inherited diagnostics remain. The initial native228 build was superseded before this run. Every archived framework source matches its manifest. Header and generated-C hashes identify additional inputs without claiming their text is archived here.')
  'shared_input_identity_receipt': json2.Any('attempt218-runtime-identities.json')
  'prior_input_identity_receipt': json2.Any('attempt227-input-identities.json')
  'prior_input_identity_receipt_sha256': json2.Any(hash(dest + 'attempt227-input-identities.json')!)
  'boot_identity_limit': json2.Any('The independent maps-live-vm boot image and efivars are reused. No pre-run clone boot-image/kernel hash was captured; kernel/base identities remain inherited under prior receipts. The actual VM paths are retained in the run configuration.')
  'result_scope': json2.Any('Input identities only; no functional result claim. Framework228 and native228 add rounded/path RenderNode outline clipping.')
 }
 os.write_file(dest + 'attempt228-input-identities.json', json2.encode(receipt, prettify: true) + '\n')!
 println('ATTEMPT228-INPUT-RETENTION PASS staged native228/framework228/launch hashes; ${native_sources.len} native and ${framework_sources.len} framework exact source identities')
}
