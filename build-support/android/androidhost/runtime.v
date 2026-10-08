module androidhost

import os

const art_elfs = ['usr/lib/art/libandroidfw.so', 'usr/lib/art/libart.so',
	'usr/lib/art/libart-compiler.so', 'usr/lib/art/libart-dexlayout.so', 'usr/lib/art/libartbase.so',
	'usr/lib/art/libartpalette.so', 'usr/lib/art/libbacktrace.so', 'usr/lib/art/libbase.so',
	'usr/lib/art/libcutils.so', 'usr/lib/art/libdexfile.so', 'usr/lib/art/liblog.so',
	'usr/lib/art/libnativebridge.so', 'usr/lib/art/libprofile.so', 'usr/lib/art/libsigchain.so',
	'usr/lib/art/libunwind.so', 'usr/lib/art/libutils.so', 'usr/lib/art/libziparchive.so',
	'usr/lib/java/dex/art/natives/libjavacore.so', 'usr/lib/java/dex/art/natives/libnativehelper.so',
	'usr/lib/java/dex/art/natives/libopenjdk.so', 'usr/lib/java/dex/art/natives/libopenjdkjvm.so',
	'usr/bin/dalvikvm', 'usr/bin/dex2oat']
const art_headers = ['usr/include/androidfw/androidfw_c_api.h']
const art_boot_jars = ['usr/lib/java/dex/art/core-oj-hostdex.jar',
	'usr/lib/java/dex/art/core-libart-hostdex.jar']
const bionic_libraries = ['usr/lib/libc_bio.so', 'usr/lib/libc_bio.so.0', 'usr/lib/libdl_bio.so',
	'usr/lib/libdl_bio.so.0', 'usr/lib/libdl_bio.so.0.0.1', 'usr/lib/libpthread_bio.so',
	'usr/lib/libpthread_bio.so.0', 'usr/lib/libstdc++_bio.so', 'usr/lib/libstdc++_bio.so.0']
const atl_elfs = ['usr/bin/android-translation-layer', 'usr/lib/libandroid.so',
	'usr/lib/libandroid.so.0', 'usr/libexec/vinix-android/atl-configuration-test',
	'usr/lib/java/dex/android_translation_layer/natives/libtranslation_layer_main.so']
const atl_jars = ['usr/lib/java/dex/android_translation_layer/api-impl.jar',
	'usr/lib/java/dex/android_translation_layer/gstub.jar',
	'usr/lib/java/dex/android_translation_layer/ghax.jar']
const atl_resources = 'usr/lib/java/dex/android_translation_layer/framework-res.apk'
const atl_fonts = 'usr/share/atl/system/etc/fonts.xml'

struct RuntimePolicy {
	label  string
	commit string
	sha256 string
	sha512 string
	patch  string
	flag   string
}

fn runtime_policy(bionic bool, atl bool) RuntimePolicy {
	if atl {
		return RuntimePolicy{'ATL', 'aa80e7405436fb4b442b7c90abefd2d526f8543a', '20c1ce3890d416099fd446d299eb58069ee41d38c1a412e2e331b91c07aca9f1', '3e274fd63f3eec25fd83efddc8c5135c494bb978c0a481a75ca703779e63a85ffe8d50047d73a29fdf68a4fb08c0c283339517afe8f82214e289b64037e88221', 'atl-configuration.patch', '-Wl,-z,max-page-size=65536'}
	}
	if bionic {
		return RuntimePolicy{'Bionic', 'ee37eb21c91409fe0eed833d0a5a0aa6b931bb7b', 'b1b2fa762485c1f33e71c0de6a4cbf4ca7006cfaec9c4c9cc20949393cbf49ef', '713f3a7c147e06781eb60f352d2c801b1b661e52bd33aa627ec1bbcb3587f15af33393f8068d9e341f6869777ac008bee6c8ef8a26f0826049a9fa226dcdbeac', 'bionic16k.patch', '-DBIONIC_PAGE_SIZE=16384'}
	}
	return RuntimePolicy{'ART', 'e78bf68917bcaaf58fef3960cd88793b3b7f39cc', '2efcaf77d1c3e08dc738b7d1d38ad789b0a0fc729612fb67169d0b2c250b61d7', '75ef56d63dfc7661a7928191441d4672d612b6a8d27c3957764d324e4f622a42c132c34540f6a89556b1971964df8be2eced0b8a599d5a793ab3039cfb9c48a2', 'art16k.patch', '-DART_PAGE_SIZE=16384'}
}

fn same_text(row map[string]Value, name string, expected string) bool {
	value := field(row, name)
	return value is string && value == expected
}

pub fn validate_runtime(overlay string, support string, manifest Value, bionic bool, atl bool) ![]string {
	policy := runtime_policy(bionic, atl)
	label := policy.label
	if manifest !is map[string]Value { return error('${label} runtime manifest must be an object') }
	row := manifest.object()
	format := integer(field(row, 'format')) or { u64(0) }
	if format != 1 || !same_text(row, 'architecture', 'aarch64') || !number_equals(field(row, 'page_size'), 16384) {
		return error('${label} runtime must be format 1, native ARM64, and built for 16 KiB pages')
	}
	if !same_text(row, 'source_commit', policy.commit) || !same_text(row, 'source_sha512', policy.sha512) || !same_text(row, 'source_sha256', policy.sha256) {
		return error('${label} runtime source does not match the pinned source archive')
	}
	if !same_text(row, 'patch_sha256', digest(path_join(support, policy.patch))!) {
		return error('${label} runtime was built with a different Vinix patch; rebuild ${label}')
	}
	if !bionic && !number_equals(field(row, 'androidfw_configuration_api'), 1) {
		return error('${label} runtime lacks the native androidfw configuration API')
	}
	flags := field(row, 'build_flags')
	if flags !is []Value || !flags.items().all(it is string) || Value(policy.flag) !in flags.items() {
		return error('${label} runtime manifest is missing its 16 KiB compiler flag')
	}
	files := field(row, 'files')
	if files !is []Value || files.items().len == 0 {
		return error('ART runtime manifest has no files')
	}
	mut seen := []string{cap: files.items().len}
	for value in files.items() {
		if value !is map[string]Value { return error('ART runtime file record must be an object') }
		record := value.object()
		name := relative(field(record, 'path'))!
		if name in seen { return error('duplicate ART runtime file: ${name}') }
		seen << name
		if !nonnegative_integer(field(record, 'size')) {
			return error('invalid ART runtime file size or hash: ${name}')
		}
		if !is_hash(field(record, 'sha256')) {
			return error('invalid ART runtime file size or hash: ${name}')
		}
		path := inside(overlay, name)!
		regular(path)!
		state := os.stat(path) or { return file_error(path) }
		if !size_matches(field(record, 'size'), state.size) {
			return error('ART runtime file checksum mismatch: ${name}')
		}
		if digest(path)! != field(record, 'sha256').text() {
			return error('ART runtime file checksum mismatch: ${name}')
		}
		check_elf(path, bionic || name in (if atl { atl_elfs } else { art_elfs }))!
		if atl {
			mut input := open_reader(path)!
			magic := read_part(mut input, 4, '') or {
				input.close()
				return err
			}
			input.close()
			kind := if magic == [u8(0x7f), `E`, `L`, `F`] {
				'elf'
			} else if name.ends_with('.jar') {
				'dex'
			} else {
				'data'
			}
			if !same_text(record, 'kind', kind) {
				return error('ATL runtime file kind does not match its payload: ${name}')
			}
		}
	}
	if atl { return seen }
	if bionic {
		if seen.len != bionic_libraries.len || !seen.all(it in bionic_libraries) {
			return error('Bionic runtime must contain all nine loader libraries and SONAME aliases')
		}
		return seen
	}
	mut missing := []string{}
	for name in art_elfs { if name !in seen { missing << name } }
	for name in art_headers { if name !in seen { missing << name } }
	mut unexpected := seen.filter(it !in art_elfs && it !in art_headers && it !in art_boot_jars)
	missing.sort()
	unexpected.sort()
	if missing.len > 0 {
		return error('ART runtime is missing required native outputs: ' + missing.join(', '))
	}
	if unexpected.len > 0 {
		return error('ART runtime has unexpected outputs: ' + unexpected.join(', '))
	}
	return seen
}

fn records_by_path(manifest Value) map[string]Value {
	mut records := map[string]Value{}
	for value in field(manifest.object(), 'files').items() {
		records[field(value.object(), 'path').text()] = value
	}
	return records
}

pub fn validate_bionic_aliases(manifest Value, seen []string) ! {
	records := records_by_path(manifest)
	for name in seen {
		canonical := name.split('.so')[0] + '.so'
		for key in ['sha256', 'size'] {
			if encode(field(field(records, name).object(), key)) != encode(field(field(records, canonical).object(), key)) {
				return error('Bionic SONAME alias differs from its canonical library: ${name}')
			}
		}
	}
}

pub fn validate_atl_required(seen []string) ! {
	if seen.len != atl_elfs.len + atl_jars.len + 2 || !seen.all(it in atl_elfs || it in atl_jars || it in [
		atl_resources,
		atl_fonts,
	]) {
		return error('ATL runtime is missing part of its coherent native/framework/resource output')
	}
}

pub fn validate_atl_metadata(support string, manifest Value, seen []string) ! {
	validate_atl_required(seen)!
	if !atl_metadata_matches(support, manifest.object())! {
		return error('ATL runtime does not match the pinned builder and Java compiler inputs')
	}
	records := records_by_path(manifest)
	for key in ['size', 'sha256'] {
		if encode(field(field(records, 'usr/lib/libandroid.so').object(), key)) != encode(field(field(records, 'usr/lib/libandroid.so.0').object(), key)) {
			return error('ATL libandroid SONAME alias differs from its canonical library')
		}
	}
}

// Keep I/O calls in separate statements: an error-result expression within
// a compound condition can be emitted before its short-circuit operands.
fn atl_metadata_matches(support string, row map[string]Value) !bool {
	if Value('--buildtype=release') !in field(row, 'build_flags').items() { return false }
	if !same_text(row, 'androidfw_patch_sha256', digest(path_join(support, 'art16k.patch'))!) {
		return false
	}
	if !is_hash(field(row, 'androidfw_header_sha256')) || !is_hash(field(row, 'androidfw_library_sha256')) {
		return false
	}
	if !same_text(row, 'configuration_probe_sha256', configuration_probe_digest(support)!) {
		return false
	}
	if !same_text(row, 'builder_sha256', digest(path_join(support, 'build-atl.sh'))!) {
		return false
	}
	if !same_text(row, 'dex_adapter_sha256', digest(path_join(support, 'atl-dex.py'))!) {
		return false
	}
	if !same_text(row, 'dex_compiler_sha256', '900dfbc649519969fc5a4c7520d6b7355338e565fa1249874e0190b8d61b1199')
		|| !same_text(row, 'java_core_classes_sha256', 'f47736d9d410766a20ae1f60d679607d8e85241e8cdeb5a0c040ab260ba68f42') {
		return false
	}
	compiler_arguments := field(row, 'dex_compiler_arguments')
	expected_arguments := ['--release', '--min-api', '26', '--android-platform-build',
		'--force-passthrough-assertions']
	if compiler_arguments !is []Value || compiler_arguments.items() != expected_arguments.map(Value(it))
		|| !field(row, 'dex_compiler').text().starts_with('D8 8.3.37 (build ') {
		return false
	}
	return true
}

pub fn validate_atl_dex_receipt(name string, record Value, classes u64, callsites u64) ! {
	if classes == 0 || callsites != 0 {
		return error('ATL framework retained unsupported Java bootstrap calls: ${name}')
	}
	for key, measured in {
		'class_count':         classes
		'bootstrap_callsites': callsites
	} {
		actual := integer(field(record.object(), key)) or { return error('ATL framework DEX does not match its compiler receipt: ${name}') }
		if actual != measured {
			return error('ATL framework DEX does not match its compiler receipt: ${name}')
		}
	}
}

pub fn manifest_path(overlay string, bionic bool, atl bool) !string {
	label := runtime_policy(bionic, atl).label
	if overlay.contains('\x00') || os.is_link(overlay) || !os.is_dir(overlay) {
		return error('${label} runtime overlay must be a directory: ${overlay}')
	}
	name := if atl {
		'atl-runtime-manifest.json'
	} else if bionic {
		'bionic-runtime-manifest.json'
	} else {
		'art-runtime-manifest.json'
	}
	path := path_join(overlay, name)
	regular(path)!
	return path
}
