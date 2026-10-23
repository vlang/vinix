import os
import json2
import crypto.sha256
import compress.gzip

const base = 'build/android-maps/'
const dest = 'tests/android/results/2026-10-23/maps-ws/'

fn hash(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn archive_sources(files map[string]string, filename string) ! {
	os.write_file_array(dest + filename, gzip.compress(json2.encode(files).bytes())!)!
	restored := json2.decode[map[string]string](gzip.decompress(os.read_bytes(dest + filename)!)!.bytestr())!
	assert restored.len == files.len
	for path, contents in files { assert restored[path]! == contents }
}

fn main() {
	mut artifacts := map[string]json2.Any{}
	for source, name in {
		base + 'native221-sources.json': 'native221-sources.json'
		base + 'framework221-content-capture/framework-manifest.json': 'attempt221-framework-manifest.json'
		base + 'build-framework221-content-capture.v': 'attempt221-framework-build.v'
		base + 'build-native221.v': 'attempt221-native-build.v'
		base + 'retain221-inputs.v': 'retain221-inputs.v'
	} {
		os.cp(source, dest + name)!
		artifacts[name] = hash(dest + name)!
	}
	native_manifest := json2.decode[map[string]string](os.read_file(base + 'native221-sources.json')!)!
	mut native_sources := map[string]string{}
	paths := os.walk_ext(base + 'native221/atlframework', '.v')
	assert paths.len == native_manifest.len
	for path in paths {
		assert hash(path)! == native_manifest[os.base(path)]!
		native_sources[os.base(path)] = os.read_file(path)!
	}
	archive_sources(native_sources, 'attempt221-native-sources.json.gz')!
	artifacts['attempt221-native-sources.json.gz'] = hash(dest + 'attempt221-native-sources.json.gz')!
	framework_manifest := json2.decode[map[string]json2.Any](os.read_file(base + 'framework221-content-capture/framework-manifest.json')!)!
	mut framework_sources := map[string]string{}
	mut missing_framework_sources := map[string]json2.Any{}
	for path, digest in framework_manifest['sources']!.as_map() {
		mut source := os.read_file(path)!
		if hash(path)! != digest.str() {
			if path.ends_with('framework_content_capture.v') {
				source = os.read_file(base + 'framework221-capture-exact.v')!
			} else { missing_framework_sources[path] = digest.str(); continue }
		}
		assert sha256.sum(source.bytes()).hex() == digest.str(), path
		framework_sources[path] = source
	}
	archive_sources(framework_sources, 'attempt221-framework-sources.json.gz')!
	artifacts['attempt221-framework-sources.json.gz'] = hash(dest + 'attempt221-framework-sources.json.gz')!
	for name, path in {
		'attempt221-View.dex-smali.gz': 'android/view/View.smali'
		'attempt221-Application.dex-smali.gz': 'android/app/Application.smali'
		'attempt221-ATLLoadedApp.dex-smali.gz': 'android/atl/ATLLoadedApp.smali'
		'attempt221-ContentCaptureSession.dex-smali.gz': 'android/view/contentcapture/ContentCaptureSession.smali'
	} {
		os.write_file_array(dest + name, gzip.compress(os.read_bytes(base + 'retain221-smali/' + path)!)!)!
		artifacts[name] = hash(dest + name)!
	}
	mut staged := map[string]json2.Any{}
	for path in ['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so',
		'opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar',
		'usr/bin/run-android', 'usr/bin/run-android-calculator', 'usr/bin/vinix-desktop',
		'usr/bin/vinix-session', 'opt/android-test/native-guest'] {
		staged[path] = hash(base + 'attempt221/module/' + path)!
	}
	assert staged['opt/vinix-android-aarch64/usr/lib/art/libvinix-android-native.so']!.str() == '4f844e7dcf1b565c1d896b0d3d074da8173e1833a487be636124f627f77f31fb'
	assert hash(base + 'libnative221.so')! == '4f844e7dcf1b565c1d896b0d3d074da8173e1833a487be636124f627f77f31fb'
	assert staged['opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/api-impl.jar']!.str() == 'b68a2228bf00dd24fd01a7da0bc9a66f2026564df4a3f515e15b22cd2b91c75f'
	assert framework_manifest['output_sha256']!.str() == hash(base + 'framework221-content-capture/api-impl.jar')!
	prior := json2.decode[map[string]json2.Any](os.read_file(dest + 'attempt218-runtime-identities.json')!)!
	prior_staged := prior['staged_runtime_sha256']!.as_map()
	for path, value in staged {
		if !path.ends_with('api-impl.jar') && !path.ends_with('libvinix-android-native.so') {
			assert value.str() == prior_staged[path]!.str()
		}
	}
	receipt := {
		'artifacts_sha256': json2.Any(artifacts)
		'staged_runtime_sha256': json2.Any(staged)
		'native_source_files': json2.Any(native_sources.len)
		'framework_source_files': json2.Any(framework_sources.len)
		'framework_source_hashes_without_matching_source': json2.Any(missing_framework_sources)
		'source_scope': json2.Any('Native and retained framework archives are filename/path-to-V-source-text JSON maps, verified against exact manifests, then decoded and checked against original source strings. The framework_application.v build hash is retained in the manifest, but its exact source text was unavailable after concurrent changes; it is excluded from the source archive. Content-capture source text was recovered by reversing whitespace formatting and its exact build hash verified. Four framework classes were freshly disassembled directly from the actual built JAR into isolated retain221-smali before retention; this includes actual View getter and ATLLoadedApp lock implementation.')
		'shared_input_identity_receipt': json2.Any('attempt218-runtime-identities.json')
		'boot_identity_limit': json2.Any('Kernel/base receipts remain inherited; no pre-run attempt221 boot image/kernel hash was captured.')
		'result_scope': json2.Any('Input retention while attempt221 runs. This receipt makes no functional result claim.')
	}
	os.write_file(dest + 'attempt221-input-identities.json', json2.encode(receipt, prettify: true) + '\n')!
	println('ATTEMPT221-INPUT-RETENTION PASS staged native221/framework221 and shared launcher identities; ${native_sources.len} native/${framework_sources.len} framework source files verified+archived; ${missing_framework_sources.len} framework source hash retained without exact source; awaiting result')
}
