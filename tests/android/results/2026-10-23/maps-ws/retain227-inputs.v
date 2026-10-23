import os
import json2
import crypto.sha256

const base = 'build/android-maps/'
const dest = 'tests/android/results/2026-10-23/maps-ws/'
fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }
fn main() {
 mut artifacts := map[string]json2.Any{}
 for source, name in {
  base + 'framework227-canvas-z/framework-manifest.json': 'attempt227-framework-manifest.json'
  base + 'framework227-canvas-z/exact-sources.json.gz': 'attempt227-framework-sources.json.gz'
  base + 'build-framework227-canvas-z.v': 'attempt227-framework-build.v'
  base + 'snapshot-framework227.v': 'attempt227-framework-snapshot.v'
  base + 'framework227-source-check.log': 'attempt227-framework-source-check.log'
  base + 'retain227-inputs.v': 'retain227-inputs.v'
 } { os.cp(source, dest + name)!; artifacts[name] = hash(dest + name)! }
 mut staged := map[string]json2.Any{}
 for path in ['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so',
  'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar',
  'usr/bin/run-android', 'usr/bin/run-android-calculator', 'usr/bin/vinix-desktop',
  'usr/bin/vinix-session', 'opt/android-test/native-guest'] {
  staged[path] = hash(base + 'attempt227/module/' + path)!
 }
 prior := json2.decode[map[string]json2.Any](os.read_file(dest + 'attempt225-input-identities.json')!)!
 for path, digest in staged {
  if !path.ends_with('api-impl.jar') { assert digest.str() == prior['staged_runtime_sha256']!.as_map()[path]!.str(), path }
 }
 jar_path := 'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar'
 assert staged[jar_path]!.str() == '635add658c93d2a93e5e4fc597fe5981afdddc3d88192c698036a7a55c712a26'
 assert hash(base + 'framework227-canvas-z/api-impl.jar')! == staged[jar_path]!.str()
 receipt := {
  'artifacts_sha256': json2.Any(artifacts)
  'staged_runtime_sha256': json2.Any(staged)
  'framework_source_files': json2.Any(103)
  'source_scope': json2.Any('All 103 framework sources match the build manifest and are archived as exact filename-to-source JSON; the generator module was compiled from its frozen snapshot. Generator snapshots226/227 differ only in framework_render_nodes.v. Native225 and all other staged runtime files match attempt225; its exact 80-source native archive and additional build identities are reused by receipt hash.')
  'native_input_identity_receipt': json2.Any('attempt225-input-identities.json')
  'native_input_identity_receipt_sha256': json2.Any(hash(dest + 'attempt225-input-identities.json')!)
  'shared_input_identity_receipt': json2.Any('attempt218-runtime-identities.json')
  'boot_identity_limit': json2.Any('This run uses an independent maps-live-vm boot image and efivars, cloned before launch. No pre-run clone boot-image/kernel hash was captured; kernel/base identities remain inherited under the prior receipts. The run configuration records the actual VM paths.')
  'result_scope': json2.Any('Input identities only; no functional result claim. Framework227 adds software Canvas.enableZ/disableZ no-ops; RecordingCanvas elevation reordering and shadows remain unsupported.')
 }
 os.write_file(dest + 'attempt227-input-identities.json', json2.encode(receipt, prettify: true) + '\n')!
 println('ATTEMPT227-INPUT-RETENTION PASS staged framework227/native225/launch identities; exact103 framework sources archived; native source receipt reused')
}
