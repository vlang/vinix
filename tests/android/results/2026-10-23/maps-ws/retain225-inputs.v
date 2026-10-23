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
		base + 'native225-sources.json': 'native225-sources.json'
		base + 'build-native225.v': 'attempt225-native-build.v'
		base + 'retain225-inputs.v': 'retain225-inputs.v'
	} { os.cp(source, dest + name)!; artifacts[name] = hash(dest + name)! }
	manifest := json2.decode[map[string]string](os.read_file(base + 'native225-sources.json')!)!
	mut sources := map[string]string{}
	for name, digest in manifest {
		path := base + 'native225/atlframework/' + name
		assert hash(path)! == digest, name
		sources[name] = os.read_file(path)!
	}
	assert sources.len == 80
	archive := 'attempt225-native-sources.json.gz'
	os.write_file_array(dest + archive, gzip.compress(json2.encode(sources).bytes())!)!
	restored := json2.decode[map[string]string](gzip.decompress(os.read_bytes(dest + archive)!)!.bytestr())!
	assert restored.len == sources.len
	for name, source in restored { assert sha256.sum(source.bytes()).hex() == manifest[name]! }
	artifacts[archive] = hash(dest + archive)!
	mut staged := map[string]json2.Any{}
	for path in ['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so',
		'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar',
		'usr/bin/run-android', 'usr/bin/run-android-calculator', 'usr/bin/vinix-desktop',
		'usr/bin/vinix-session', 'opt/android-test/native-guest'] {
		staged[path] = hash(base + 'attempt225/module/' + path)!
	}
	assert staged['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so']!.str() == '592cef0d9d52b9a2795ba78724b6b1b514299511a897996a0d994e7fb56c5f3a'
	assert hash(base + 'libnative225.so')! == staged['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so']!.str()
	prior := json2.decode[map[string]json2.Any](os.read_file(dest + 'attempt223-input-identities.json')!)!
	for path, digest in staged {
		if !path.ends_with('libvinix-android-native.so') { assert digest.str() == prior['staged_runtime_sha256']!.as_map()[path]!.str(), path }
	}
	mut native_build_inputs := map[string]json2.Any{}
	for name in ['androidfw_c_api.h', 'sqlite3.h', 'stb_image.h', 'stb_truetype.h', 'android-native.c'] {
		native_build_inputs[name] = hash(base + 'native225/' + name)!
	}
	receipt := {
		'artifacts_sha256': json2.Any(artifacts)
		'staged_runtime_sha256': json2.Any(staged)
		'native_source_files': json2.Any(sources.len)
		'native_additional_build_inputs_sha256': json2.Any(native_build_inputs)
		'source_scope': json2.Any('All 80 native V source snapshot files match the declared source manifest; their exact text was archived as filename-to-source JSON and checked again after decoding. Native225 adds ALPHA_8 storage and rendering. The staged framework and all other measured runtime files exactly match attempt223; its exact 102-source framework archive and actual-DEX evidence remain in attempt223. Header and generated-C hashes are recorded as additional build identities, without claiming those files are archived here.')
		'framework_input_identity_receipt': json2.Any('attempt223-input-identities.json')
		'framework_input_identity_receipt_sha256': json2.Any(hash(dest + 'attempt223-input-identities.json')!)
		'shared_input_identity_receipt': json2.Any('attempt218-runtime-identities.json')
		'boot_identity_limit': json2.Any('Kernel/base receipts remain inherited; no pre-run attempt225 boot image/kernel hash was captured.')
		'result_scope': json2.Any('Input identities only; no functional result claim. Attempt224 was not booted; the reviewed row-stride implementation was built as native225.')
	}
	os.write_file(dest + 'attempt225-input-identities.json', json2.encode(receipt, prettify: true) + '\n')!
	println('ATTEMPT225-INPUT-RETENTION PASS staged native225/framework223 and launch identities; ${sources.len} exact native sources archived and decoded; framework sources reuse verified attempt223 receipt')
}
