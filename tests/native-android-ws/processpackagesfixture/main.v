// SPDX-License-Identifier: GPL-2.0-or-later
// Build the signed ARM process package metadata fixture.
module main

import crypto.sha256
import json2
import os

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
	process_name string
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

fn regular_names(path string) ![]string {
	mut names := os.ls(path)!
	names.sort()
	for name in names {
		assert !os.is_link(path + '/' + name) && os.lstat(path + '/' + name)!.get_filetype() == .regular,
			'regular tool input required: ' + name
	}
	return names
}

fn manifest() string {
	return '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="${package_name}" android:versionCode="1">' +
		'<uses-sdk android:minSdkVersion="28" android:targetSdkVersion="35"/>' +
		'<application android:label="Process packages fixture" android:process=":process_packages"><activity android:name="${package_name}.Main" android:exported="true"><intent-filter>' +
		'<action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/>' +
		'</intent-filter></activity></application></manifest>'
}

fn main() {
	if os.args.len != 7 { panic('OUTPUT AAPT2 FRAMEWORK_RES SMALI_TOOLS JAVA APKSIGNER') }
	$if prod { panic('live assertions required') }
	out := os.abs_path(os.args[1])
	aapt, resources := os.real_path(os.args[2]), os.real_path(os.args[3])
	tools, java, signer := os.real_path(os.args[4]), os.real_path(os.args[5]), os.real_path(os.args[6])
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
	for path in [executable, aapt, resources, java, signer, keytool, zip, unzip] {
		assert os.is_file(path), 'missing input: ' + path
		inputs[path] = file_hash(path)!
	}
	for name in source_names {
		path := source_root + '/' + name
		assert !os.is_link(path) && os.lstat(path)!.get_filetype() == .regular, 'regular fixture source required'
		inputs[path] = file_hash(path)!
		os.cp(path, out + '/inputs/' + name)!
		assert file_hash(out + '/inputs/' + name)! == inputs[path]!
	}
	tool_names := regular_names(tools)!
	for name in tool_names { inputs[tools + '/' + name] = file_hash(tools + '/' + name)! }
	os.cp(executable, out + '/inputs/generator')!
	assert file_hash(out + '/inputs/generator')! == inputs[executable]!
	os.write_file(out + '/inputs-before.json', json2.encode(inputs, prettify: true) + '\n')!
	os.write_file(out + '/tools-membership.json', json2.encode(tool_names) + '\n')!
	classes := fixture_sources()
	expected := expected_classes()
	assert expected == ['org/vinix/bootstrap/Main.smali', 'org/vinix/bootstrap/Worker.smali'],
		'exact Activity and plain worker class closure required'
	assert classes.keys().sorted() == expected, 'exact fixture class membership required'
	for name in expected {
		assert name.ends_with('.smali') && !name.starts_with('/') && !name.contains_any('\\\r\n\x00')
		assert !name.split('/').any(it in ['', '.', '..']), 'safe fixture class path required'
		path := out + '/smali/' + name
		os.mkdir_all(os.dir(path))!
		os.write_file(path, classes[name])!
		verify_source_references(name, classes[name])
	}
	assert relative_files(out + '/smali')! == expected, 'source class membership differs'
	os.write_file(out + '/AndroidManifest.xml', manifest())!
	revision := recorded(out, 'source-revision', ['git', 'rev-parse', 'HEAD'])!.trim_space()
	java_version := recorded(out, 'java-version', java_command(java, ['-version']))!
	key := out + '/fixture.p12'
	recorded(out, 'keytool', [keytool, '-J-Xmx256m', '-J-XX:ActiveProcessorCount=2', '-genkeypair', '-keystore', key, '-storetype', 'PKCS12',
		'-storepass', 'android', '-keypass', 'android', '-alias', 'fixture', '-dname', 'CN=Vinix Process Packages Fixture',
		'-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650'])!
	inputs[key] = file_hash(key)!
	recorded(out, 'link', [aapt, 'link', '-I', resources, '--manifest', out + '/AndroidManifest.xml', '-o', out + '/unsigned.apk'])!
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
		verify_source_references(name, os.read_file(out + '/roundtrip-smali/' + name)!)
		verify_source_references(name, os.read_file(out + '/roundtrip-checked-smali/' + name)!)
	}
	recorded(out, 'zip', [zip, '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'])!
	apk := out + '/probe.apk'
	recorded(out, 'sign', java_command(java, ['-jar', signer, 'sign', '--ks', key, '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', apk, out + '/unsigned.apk']))!
	verification := recorded(out, 'verify', java_command(java, ['-jar', signer, 'verify', '--verbose', apk]))!
	assert verification.contains('Verified using v3 scheme (APK Signature Scheme v3): true'), 'APK v3 signature missing'
	assert verification.split_into_lines().filter(it == 'Number of signers: 1').len == 1, 'exactly one signer required'
	badging := recorded(out, 'badging', [aapt, 'dump', 'badging', apk])!
	assert badging.contains("package: name='${package_name}'") && badging.contains("launchable-activity: name='${package_name}.Main'")
	assert badging.contains("minSdkVersion:'28'"), 'signed fixture must retain API-28 manifest floor'
	manifest_tree := recorded(out, 'signed-manifest-tree', [aapt, 'dump', 'xmltree', apk, '--file', 'AndroidManifest.xml'])!
	process_attribute := 'A: http://schemas.android.com/apk/res/android:process(0x01010011)='
	process_attributes := manifest_tree.split_into_lines().filter(it.contains(process_attribute))
	application_tree := manifest_tree.all_after('E: application ').all_before('E: activity ')
	assert process_attributes.len == 1 && process_attributes[0].contains('":process_packages"') &&
		application_tree.contains(process_attribute + '":process_packages"'),
		'exact inherited application process suffix required in signed manifest'
	entries := recorded(out, 'signed-membership', [unzip, '-Z1', apk])!.trim_space().split_into_lines()
	mut seen := map[string]bool{}
	for entry in entries {
		assert !seen[entry], 'duplicate signed archive member: ' + entry
		assert !entry.starts_with('/') && !entry.contains_any('\\\r\n\x00') && !entry.split('/').any(it in ['.', '..']), 'unsafe signed archive member'
		seen[entry] = true
	}
	assert entries.filter(it.ends_with('.dex')) == ['classes.dex'], 'exact signed DEX membership required'
	recorded(out, 'signed-dex-extract', [unzip, '-q', apk, 'classes.dex', '-d', out + '/signed-extracted'])!
	assert relative_files(out + '/signed-extracted')! == ['classes.dex'], 'exact signed DEX extraction required'
	assert file_hash(out + '/signed-extracted/classes.dex')! == file_hash(out + '/classes.dex')!, 'signed DEX differs from checked production DEX'
	assert regular_names(tools)! == tool_names, 'tool-directory membership changed'
	assert os.ls(source_root)!.filter(it.ends_with('.v')).sorted() == source_names, 'fixture source closure changed'
	for path, before in inputs { assert file_hash(path)! == before, 'input changed: ' + path }
	mut artifacts := map[string]string{}
	for path in output_files(out)! { artifacts[path.all_after(out + '/')] = file_hash(path)! }
	receipt := FixtureBuild{
		argv: os.args.clone(), source_revision: revision, inputs_sha256: inputs, artifacts_sha256: artifacts,
		java_version: java_version.trim_space(), apk_sha256: file_hash(apk)!, package_name: package_name,
		activity_name: package_name + '.Main', process_name: expected_process, pass_marker: pass_marker, fail_marker: fail_marker,
		scope: fixture_scope
	}
	os.write_file(out + '/build.json', json2.encode(receipt, prettify: true) + '\n')!
	println('PROCESS-PACKAGES-FIXTURE-APK ' + apk)
	println('PROCESS-PACKAGES-FIXTURE-APK-SHA256 ' + receipt.apk_sha256)
}
