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
		base + 'framework222-autofill/framework-manifest.json': 'attempt222-framework-manifest.json'
		base + 'build-framework222-autofill.v': 'attempt222-framework-build.v'
		base + 'retain222-inputs.v': 'retain222-inputs.v'
	} { os.cp(source, dest + name)!; artifacts[name] = hash(dest + name)! }
	manifest := json2.decode[map[string]json2.Any](os.read_file(base + 'framework222-autofill/framework-manifest.json')!)!
	mut sources := map[string]string{}
	for path, digest in manifest['sources']!.as_map() {
		mut snapshot := base + 'framework222-autofill/sources/androidtools/' + os.base(path)
		if !os.exists(snapshot) { snapshot = path }
		assert hash(snapshot)! == digest.str(), path
		sources[path] = os.read_file(snapshot)!
	}
	archive := 'attempt222-framework-sources.json.gz'
	os.write_file_array(dest + archive, gzip.compress(json2.encode(sources).bytes())!)!
	restored := json2.decode[map[string]string](gzip.decompress(os.read_bytes(dest + archive)!)!.bytestr())!
	assert restored.len == sources.len
	for path, source in restored { assert sha256.sum(source.bytes()).hex() == manifest['sources']!.as_map()[path]!.str() }
	artifacts[archive] = hash(dest + archive)!
	mut staged := map[string]json2.Any{}
	for path in ['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so',
		'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar',
		'usr/bin/run-android', 'usr/bin/run-android-calculator', 'usr/bin/vinix-desktop',
		'usr/bin/vinix-session', 'opt/android-test/native-guest'] {
		staged[path] = hash(base + 'attempt222/module/' + path)!
	}
	assert staged['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so']!.str() == '4f844e7dcf1b565c1d896b0d3d074da8173e1833a487be636124f627f77f31fb'
	assert staged['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar']!.str() == 'fa6bd91691f7e96d2db407746d1dee0bba9f9b3465318f24850d88d68dd6412f'
	assert manifest['output_sha256']!.str() == hash(base + 'framework222-autofill/api-impl.jar')!
	prior := json2.decode[map[string]json2.Any](os.read_file(dest + 'attempt221-input-identities.json')!)!
	for path, digest in staged { if !path.ends_with('api-impl.jar') { assert digest.str() == prior['staged_runtime_sha256']!.as_map()[path]!.str() } }
	result := os.exec(['/opt/homebrew/opt/openjdk@25/bin/java', '-cp', 'build/android-framework/tools/*', 'org.jf.baksmali.Main', 'disassemble', '--classes', 'Landroid/view/autofill/AutofillValue;', '-o', base + 'retain222-smali', base + 'framework222-autofill/api-impl.jar'])
	assert result.exit_code == 0, result.output
	name := 'attempt222-AutofillValue.dex-smali.gz'
	os.write_file_array(dest + name, gzip.compress(os.read_bytes(base + 'retain222-smali/android/view/autofill/AutofillValue.smali')!)!)!
	artifacts[name] = hash(dest + name)!
	receipt := {
		'artifacts_sha256': json2.Any(artifacts)
		'staged_runtime_sha256': json2.Any(staged)
		'framework_source_files': json2.Any(sources.len)
		'source_scope': json2.Any('Every framework source snapshot file matches its declared build-manifest hash, archived as path-to-V-source-text JSON and checked after decoding. AutofillValue was freshly disassembled from the actual built JAR. Native221 binary matches the previously retained staged identity; its exact80-source archive is in attempt221-native-sources.json.gz, verified by validate-retained.v.')
		'native_source_identity_receipt': json2.Any('attempt221-input-identities.json')
		'shared_input_identity_receipt': json2.Any('attempt218-runtime-identities.json')
		'boot_identity_limit': json2.Any('Kernel/base receipts remain inherited; no pre-run attempt222 boot image/kernel hash was captured.')
		'result_scope': json2.Any('Input identities only; no functional result claim. Interaction222 changes settle to0.15 seconds per input phase and waits10 seconds explicitly after the click.')
	}
	os.write_file(dest + 'attempt222-input-identities.json', json2.encode(receipt, prettify: true) + '\n')!
	println('ATTEMPT222-INPUT-RETENTION PASS staged native221/framework222 and launch identities; ${sources.len} exact framework sources archived+decoded; actualDEX AutofillValue retained')
}
