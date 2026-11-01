// SPDX-License-Identifier: GPL-2.0-or-later
// Build and preserve the signed ARM resource synchronization regression APK.
module main

import crypto.sha256
import json2
import os
import strings

struct CommandReceipt {
	argv []string
	status int
	output string
}

struct FixtureBuild {
	argv []string
	source_revision string
	inputs_sha256 map[string]string
	artifacts_sha256 map[string]string
	java_version string
	apk_sha256 string
	package_name string
	activity_name string
	pass_marker string
	fail_marker string
	scope string
}

fn file_hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	mut buffer := []u8{len: 1024 * 1024}
	for {
		count := file.read(mut buffer) or { if err is os.Eof { break }; return err }
		if count == 0 { break }
		digest.write(buffer[..count])!
	}
	return digest.sum([]u8{}).hex()
}

fn recorded(out string, name string, argv []string) !string {
	result := os.exec(argv)
	os.write_file(out + '/commands/' + name + '.json', json2.encode(CommandReceipt{
		argv: argv, status: result.exit_code, output: result.output
	}, prettify: true) + '\n')!
	if result.exit_code != 0 { return error(name + ': ' + result.output) }
	return result.output
}

fn java_command(java string, args []string) []string {
	mut command := [java, '-Xmx256m', '-XX:ActiveProcessorCount=2']
	command << args
	return command
}

fn output_files(path string) ![]string {
	mut result := []string{}
	mut names := os.ls(path)!
	names.sort()
	for name in names {
		item := path + '/' + name
		if os.is_link(item) { return error('unexpected output symlink: ' + item) }
		kind := os.lstat(item)!.get_filetype()
		if kind == .directory { result << output_files(item)! }
		else if kind == .regular { result << item }
		else { return error('unexpected output type: ' + item) }
	}
	return result
}

fn relative_files(path string) ![]string {
	mut result := output_files(path)!.map(it.all_after(path + '/'))
	result.sort()
	return result
}

fn manifest() string {
	return '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="${package_name}" android:versionCode="1">' +
		'<uses-sdk android:minSdkVersion="29" android:targetSdkVersion="35"/>' +
		'<application android:label="Resource locking fixture"><activity android:name="${package_name}.Main" android:exported="true"><intent-filter>' +
		'<action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/>' +
		'</intent-filter></activity></application></manifest>'
}

fn source_header_path() string {
	return os.join_path(os.dir(os.real_path(@FILE)), '../../../build/android-native-ws/androidfw_c_api.h')
}

// The retained androidfw header covers Asset/AssetDir. These standard NDK
// wrappers are declared separately, with the exact types in ndk_assets.v.
fn native_ndk_header() string {
	return '#include <stddef.h>\n#include <stdint.h>\n' +
		'void* AAssetManager_fromJava(void*, void*);\n' +
		'void* AAssetManager_open(void*, const char*, int32_t);\n' +
		'int64_t AAsset_getLength64(void*);\n' +
		'int32_t AAsset_read(void*, void*, size_t);\n' +
		'void AAsset_close(void*);\n'
}

// Match the maintained freestanding module tool's identifier-only V lifecycle
// renaming. Otherwise two APK libraries can interpose each other's startup.
fn c_identifier_replace(value string, old string, replacement string) string {
	mut result := strings.new_builder(value.len)
	mut i := 0
	for i < value.len {
		end := i + old.len
		if end <= value.len && value[i..end] == old &&
			(i == 0 || !(value[i - 1].is_alnum() || value[i - 1] == `_`)) &&
			(end == value.len || !(value[end].is_alnum() || value[end] == `_`)) {
			result.write_string(replacement)
			i = end
		} else {
			result.write_u8(value[i])
			i++
		}
	}
	return result.str()
}

fn main() {
	if os.args.len != 11 { panic('OUTPUT AAPT2 FRAMEWORK_RES SMALI_TOOLS JAVA APKSIGNER NATIVE_V CROSS_CC READELF LIBANDROIDFW') }
	$if prod { panic('live assertions required') }
	out := os.abs_path(os.args[1])
	aapt, resources := os.real_path(os.args[2]), os.real_path(os.args[3])
	tools, java, signer := os.real_path(os.args[4]), os.real_path(os.args[5]), os.real_path(os.args[6])
	native_v, cross_cc, readelf := os.real_path(os.args[7]), os.real_path(os.args[8]), os.real_path(os.args[9])
	androidfw := os.real_path(os.args[10])
	native_header := os.real_path(source_header_path())
	if os.exists(out) || os.is_link(out) { panic('fresh output directory required') }
	os.mkdir_all(out + '/commands')!
	os.mkdir(out + '/inputs')!
	source_root, executable := os.dir(os.real_path(@FILE)), os.real_path(os.executable())
	source_names := os.ls(source_root)!.filter(it.ends_with('.v')).sorted()
	assert source_names == ['main.v', 'sources.v'], 'exact fixture generator source closure required'
	keytool := os.dir(java) + '/keytool'
	zip := os.real_path(os.find_abs_path_of_executable('zip')!)
	unzip := os.real_path(os.find_abs_path_of_executable('unzip')!)
	mut inputs := map[string]string{}
	for path in [executable, aapt, resources, java, signer, keytool, zip, unzip, native_v, cross_cc, readelf, androidfw, native_header] {
		assert os.is_file(path), 'missing input: ' + path
		inputs[path] = file_hash(path)!
	}
	assert inputs[native_v] == '109a0bad877cf42cd19382a87d3e3d62e9c153e3d74a566b2b3e650a1aec318e', 'admitted legacy native compiler required'
	assert inputs[androidfw] == '41666cf78396cb4e97c84b365ea23ef95d17a3a047d12a8a97348f1adcb5533e', 'retained libandroidfw required'
	assert inputs[native_header] == 'e233a055133776838b8044ca43eb9e8dfac387a0580918786d60207276d37af4', 'retained native API header required'
	for name in source_names {
		path := source_root + '/' + name
		assert os.is_file(path) && !os.is_link(path), 'regular fixture source required'
		inputs[path] = file_hash(path)!
		os.cp(path, out + '/inputs/' + name)!
		assert file_hash(out + '/inputs/' + name)! == inputs[path]!
	}
	native_source := source_root + '/resourcelockprobe/probe.v'
	assert relative_files(source_root + '/resourcelockprobe')! == ['probe.v'], 'exact native probe source closure required'
	inputs[native_source] = file_hash(native_source)!
	os.mkdir_all(out + '/inputs/resourcelockprobe')!
	os.cp(native_source, out + '/inputs/resourcelockprobe/probe.v')!
	assert file_hash(out + '/inputs/resourcelockprobe/probe.v')! == inputs[native_source]!
	mut tool_names := os.ls(tools)!
	tool_names.sort()
	for name in tool_names { if os.is_file(tools + '/' + name) { inputs[tools + '/' + name] = file_hash(tools + '/' + name)! } }
	os.cp(executable, out + '/inputs/generator')!
	assert file_hash(out + '/inputs/generator')! == inputs[executable]!
	os.cp(native_header, out + '/inputs/androidfw_c_api.h')!
	assert file_hash(out + '/inputs/androidfw_c_api.h')! == inputs[native_header]!
	os.write_file(out + '/inputs-before.json', json2.encode(inputs, prettify: true) + '\n')!
	os.mkdir_all(out + '/res/values')!
	os.mkdir_all(out + '/res/xml')!
	os.mkdir_all(out + '/assets/proof')!
	os.write_file(out + '/res/values/values.xml', resource_values())!
	os.write_file(out + '/res/xml/proof.xml', '<proof answer="locked"/>')!
	os.write_file(out + '/assets/proof/alpha.txt', 'VINIX-RESOURCE-ASSET\n')!
	os.write_file(out + '/assets/proof/beta.txt', 'SECOND-RESOURCE-ASSET\n')!
	os.write_file(out + '/AndroidManifest.xml', manifest())!
	revision := recorded(out, 'source-revision', ['git', 'rev-parse', 'HEAD'])!.trim_space()
	java_version := recorded(out, 'java-version', java_command(java, ['-version']))!
	key := out + '/fixture.p12'
	recorded(out, 'keytool', [keytool, '-J-Xmx256m', '-J-XX:ActiveProcessorCount=2', '-genkeypair', '-keystore', key, '-storetype', 'PKCS12',
		'-storepass', 'android', '-keypass', 'android', '-alias', 'fixture', '-dname', 'CN=Vinix Resource Lock Fixture',
		'-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650'])!
	inputs[key] = file_hash(key)!
	recorded(out, 'compile-resources', [aapt, 'compile', '--dir', out + '/res', '-o', out + '/resources.zip'])!
	recorded(out, 'link', [aapt, 'link', '-I', resources, '--manifest', out + '/AndroidManifest.xml',
		'-A', out + '/assets', '-0', 'txt', '--output-text-symbols', out + '/R.txt', '-o', out + '/unsigned.apk', out + '/resources.zip'])!
	mut ids := map[string]string{}
	for line in os.read_lines(out + '/R.txt')! {
		parts := line.fields()
		assert parts.len == 4 && parts[0] == 'int', 'scalar resource symbol required: ' + line
		name := parts[1] + '/' + parts[2]
		assert name !in ids && parts[3] !in ids.values() && parts[3].starts_with('0x7f') && parts[3].len == 10, 'unique application resource ID required'
		assert parts[3][2..].bytes().all(it.is_hex_digit()), 'hexadecimal resource ID required'
		ids[name] = parts[3]
	}
	assert ids.keys().sorted() == resource_names(), 'exact packaged resource membership required'
	classes := fixture_sources(ids)
	mut expected := classes.keys()
	expected.sort()
	assert expected == ['org/vinix/bootstrap/Main.smali', 'org/vinix/bootstrap/Worker.smali'], 'exact two-class fixture required'
	for name in expected {
		assert name.ends_with('.smali') && !name.starts_with('/') && !name.contains_any('\\\r\n\x00')
		assert !name.split('/').any(it in ['', '.', '..']), 'safe fixture class path required'
		path := out + '/smali/' + name
		os.mkdir_all(os.dir(path))!
		os.write_file(path, classes[name])!
	}
	assert relative_files(out + '/smali')! == expected, 'source class membership differs'
	assembly := recorded(out, 'assemble', java_command(java, ['-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', out + '/smali', '-o', out + '/classes.dex']))!
	assert assembly.trim_space() == '' && os.is_file(out + '/classes.dex'), 'fresh error-free DEX required: ' + assembly
	recorded(out, 'disassemble', java_command(java, ['-cp', tools + '/*', 'org.jf.baksmali.Main', 'disassemble', '--api', '28', '--jobs', '2', out + '/classes.dex', '-o', out + '/roundtrip-smali']))!
	reassembly := recorded(out, 'reassemble', java_command(java, ['-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', '--api', '28', '--jobs', '2', out + '/roundtrip-smali', '-o', out + '/roundtrip.dex']))!
	assert reassembly.trim_space() == '' && os.is_file(out + '/roundtrip.dex'), 'fresh roundtrip DEX required: ' + reassembly
	recorded(out, 'roundtrip-disassemble', java_command(java, ['-cp', tools + '/*', 'org.jf.baksmali.Main', 'disassemble', '--api', '28', '--jobs', '2', out + '/roundtrip.dex', '-o', out + '/roundtrip-checked-smali']))!
	assert relative_files(out + '/roundtrip-smali')! == expected, 'roundtrip class membership differs'
	assert relative_files(out + '/roundtrip-checked-smali')! == expected, 'second roundtrip class membership differs'
	for name in expected {
		assert file_hash(out + '/roundtrip-smali/' + name)! == file_hash(out + '/roundtrip-checked-smali/' + name)!, 'roundtrip changed class: ' + name
	}
	// Same freestanding V and 4 KiB ELF packaging pattern as assetprobe, with
	// explicit compiler identities rather than a nested compiler-selection shell.
	os.mkdir_all(out + '/native-module/resourcelockprobe')!
	os.cp(native_source, out + '/native-module/resourcelockprobe/probe.v')!
	os.write_file(out + '/native-module/v.mod', "Module { name: 'resource_lock_probe' }\n")!
	os.write_file(out + '/native-module/entry.v', 'module main\nimport resourcelockprobe as _\n')!
	os.write_file(out + '/inputs/native-ndk.h', native_ndk_header())!
	recorded(out, 'native-v-version', [native_v, 'version'])!
	recorded(out, 'native-codegen', [native_v, '-shared', '-no-builtin', '-no-closures', '-os', 'vinix', '-arch', 'arm64',
		'-target-libc-headers', '-gc', 'none', '-manualfree', '-o', out + '/native-probe-raw.c', out + '/native-module'])!
	mut native_c := os.read_file(out + '/native-probe-raw.c')!
	for name in ['_vinit', '_vcleanup', '_vinit_caller', '_vcleanup_caller', '_vno_main_init_caller', '_v3_no_main_initialized'] {
		native_c = c_identifier_replace(native_c, name, 'resourcelockprobe_' + name)
	}
	os.write_file(out + '/native-probe.c', native_c)!
	os.mkdir_all(out + '/lib/arm64-v8a')!
	native_library := out + '/lib/arm64-v8a/libresource-lock-probe.so'
	recorded(out, 'native-link', [cross_cc, '-O2', '-fPIC', '-shared', '-nostdlib', '-D_GNU_SOURCE', '-I' + out + '/inputs', '-Wl,-z,max-page-size=4096',
		'-Wl,-z,common-page-size=4096', '-Wl,-soname,libresource-lock-probe.so', out + '/native-probe.c', '-o', native_library])!
	elf_header := recorded(out, 'native-header', [readelf, '-h', native_library])!
	assert elf_header.contains('ELF64') && elf_header.contains('AArch64') && elf_header.contains('DYN'), 'AArch64 shared helper required'
	elf_dynamic := recorded(out, 'native-dynamic', [readelf, '-d', native_library])!
	assert !elf_dynamic.contains('(NEEDED)'), 'helper uses proven loader global-symbol lookup without a new dependency'
	elf_segments := recorded(out, 'native-segments', [readelf, '-l', '--wide', native_library])!
	mut loads := 0
	for line in elf_segments.split_into_lines() {
		fields := line.fields()
		if fields.len > 0 && fields[0] == 'LOAD' {
			assert fields.last() == '0x1000', '4 KiB helper segment alignment required'
			loads++
		}
	}
	assert loads > 0, 'loadable helper segments required'
	elf_symbols := recorded(out, 'native-symbols', [readelf, '--dyn-syms', '--wide', native_library])!
	for name in ['nativeHold', 'nativeHeldClose', 'nativeProbe', 'nativeReplace', 'nativeThemes'] {
		assert elf_symbols.count('Java_org_vinix_bootstrap_Main_' + name + '\n') == 1, 'exact JNI helper export required: ' + name
	}
	provider_symbols := recorded(out, 'androidfw-symbols', [readelf, '--dyn-syms', '--wide', androidfw])!
	for name in ['AssetManager_openDir', 'AssetManager_lock', 'AssetManager_unlock', 'AssetDir_getFileCount', 'AssetDir_getFileName', 'AssetDir_delete'] {
		assert provider_symbols.contains(' ' + name + '\n'), 'retained libandroidfw export required: ' + name
	}
	recorded(out, 'zip', [zip, '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'])!
	// Preserve the ABI directory, matching bootstrap-fixture's native loading path.
	mut zip_native := os.new_process(zip)
	zip_native.set_work_folder(out)
	zip_native.set_args(['-q', 'unsigned.apk', 'lib/arm64-v8a/libresource-lock-probe.so'])
	zip_native.set_redirect_stdio()
	zip_native.run()
	zip_native.wait()
	os.write_file(out + '/commands/zip-native.json', json2.encode(CommandReceipt{
		argv: [zip, '-q', out + '/unsigned.apk', 'lib/arm64-v8a/libresource-lock-probe.so'],
		status: zip_native.code, output: zip_native.stdout_slurp() + zip_native.stderr_slurp()
	}, prettify: true) + '\n')!
	assert zip_native.code == 0, 'native packaging failed'
	apk := out + '/probe.apk'
	recorded(out, 'sign', java_command(java, ['-jar', signer, 'sign', '--ks', key, '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', apk, out + '/unsigned.apk']))!
	verification := recorded(out, 'verify', java_command(java, ['-jar', signer, 'verify', '--verbose', apk]))!
	assert verification.contains('Verified using v3 scheme (APK Signature Scheme v3): true'), 'APK v3 signature missing'
	recorded(out, 'extract-signed-members', [unzip, '-q', apk, 'classes.dex', 'lib/arm64-v8a/libresource-lock-probe.so', 'assets/proof/*', '-d', out + '/signed-members'])!
	assert file_hash(out + '/signed-members/lib/arm64-v8a/libresource-lock-probe.so')! == file_hash(native_library)!, 'signed helper bytes differ'
	assert file_hash(out + '/signed-members/classes.dex')! == file_hash(out + '/classes.dex')!, 'signed DEX differs'
	for name in ['alpha.txt', 'beta.txt'] {
		assert file_hash(out + '/signed-members/assets/proof/' + name)! == file_hash(out + '/assets/proof/' + name)!, 'signed asset differs: ' + name
	}
	resource_dump := recorded(out, 'signed-resource-dump', [aapt, 'dump', 'resources', apk])!
	verify_resource_dump(resource_dump, ids)
	xml_dump := recorded(out, 'signed-xml-dump', [aapt, 'dump', 'xmltree', apk, '--file', 'res/xml/proof.xml'])!
	assert xml_dump.count('E: proof') == 1 && xml_dump.contains('answer="locked"'), 'signed XML proof differs'
	badging := recorded(out, 'badging', [aapt, 'dump', 'badging', apk])!
	assert badging.contains("package: name='${package_name}'") && badging.contains("launchable-activity: name='${package_name}.Main'")
	assert os.ls(source_root)!.filter(it.ends_with('.v')).sorted() == source_names, 'fixture source closure changed'
	assert relative_files(source_root + '/resourcelockprobe')! == ['probe.v'], 'native source closure changed'
	for path, before in inputs { assert file_hash(path)! == before, 'input changed: ' + path }
	mut artifacts := map[string]string{}
	for path in output_files(out)! { artifacts[path.all_after(out + '/')] = file_hash(path)! }
	receipt := FixtureBuild{
		argv: os.args.clone(), source_revision: revision, inputs_sha256: inputs, artifacts_sha256: artifacts,
		java_version: java_version.trim_space(), apk_sha256: file_hash(apk)!, package_name: package_name,
		activity_name: package_name + '.Main', pass_marker: pass_marker, fail_marker: fail_marker,
		scope: 'Bounded ARM resource stress: four barrier-started workers, 64 iterations each, two independent managers, concurrent native asset-set replacement/configuration and literal resource IDs/names/strings/arrays/bags/XML, same-app-copy within one owner and cross-framework-copy across owners through production raw-theme JNI, standard NDK asset opens, and independently owned Asset/AssetDir retained across mutation. Test-only helper uses no unlocked concurrent manager C API. Cross-owner app-attribute copying with separately loaded ApkAssets is not claimed. No Maps causation or authentication claim.'
	}
	os.write_file(out + '/build.json', json2.encode(receipt, prettify: true) + '\n')!
	println('RESOURCE-LOCK-FIXTURE-APK ' + apk)
	println('RESOURCE-LOCK-FIXTURE-APK-SHA256 ' + receipt.apk_sha256)
}
