// SPDX-License-Identifier: GPL-2.0-or-later
// Host transformation/DEX check only. This does not execute Android or verify APK crypto.
module main

import androidtools
import crypto.sha256
import json2
import os
import time

const self = 'tests/native-android-ws/system-package-check.v'
const seal = '17df965baca0c030e1111a9b974410e9594b6e9ccfb814d371df6a53b0ead682'
const header = '.method public static getSystemApplication()Landroid/atl/ATLLoadedApp;'
const collect = '    invoke-virtual {v0, v2, v6}, Landroid/content/pm/PackageParser;->collectCertificates(Landroid/content/pm/PackageParser$Package;I)Z\n'
const null_parser = '    const/4 v1, 0x0\n\n    invoke-direct {v0, v1}, Landroid/content/pm/PackageParser;-><init>(Ljava/lang/String;)V'
const resources = '    invoke-static {}, Landroid/content/res/Resources;->getSystem()Landroid/content/res/Resources;'
const classes = ['android/atl/ATLLoadedApp.smali', 'android/atl/ATLLoadedAppManager.smali',
	'android/atl/VinixApkSignatures.smali', 'android/content/pm/PackageParser.smali']
const jars = ['antlr-2.7.7.jar', 'antlr-3.5.2.jar', 'antlr-runtime-3.5.2.jar',
	'baksmali-2.5.2.jar', 'dexlib2-2.5.2.jar', 'failureaccess-1.0.1.jar',
	'guava-27.1-android.jar', 'jcommander-1.64.jar', 'smali-2.5.2.jar',
	'stringtemplate-3.2.1.jar', 'util-2.5.2.jar']

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn write_json[T](path string, value T) ! {
	os.write_file(path, json2.encode(value, prettify: true) + '\n')!
}

fn inventory(root string, prefix string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + prefix)! {
		key := if prefix == '' { name } else { prefix + '/' + name }
		match os.lstat(root + '/' + key)!.get_filetype() {
			.directory { inventory(root, key, mut pins)! }
			.regular { pins[key] = hash(root + '/' + key)! }
			else { return error('nonregular entry: ' + key) }
		}
	}
}

fn method(source string, declaration string) !string {
	if source.count(declaration) != 1 { return error('nonunique method: ' + declaration) }
	start := source.index(declaration) or { return error('missing method') }
	end := start + (source[start..].index('.end method') or { return error('unterminated method') })
	return source[start..end + '.end method'.len]
}

fn methods(source string) !map[string]string {
	mut result := map[string]string{}
	for block in source.split('\n.method ')[1..] {
		declaration := '.method ' + block.all_before('\n')
		if declaration in result { return error('duplicate disassembled method') }
		result[declaration] = method(source, declaration)!
	}
	return result
}

fn command(out string, name string, argv []string) ! {
	r := os.exec(argv)
	write_json(out + '/commands/' + name + '.json', {
		'argv': json2.Any(argv)
		'exit_code': json2.Any(r.exit_code)
		'output': json2.Any(r.output)
	})!
	if r.exit_code != 0 { return error(name + ' failed: ' + r.output) }
}

fn roundtrip(out string, java string, variant string) !string {
	command(out, variant + '-assemble', [java, '-cp', out + '/tools/*', 'org.jf.smali.Main',
		'assemble', '--jobs', '2', out + '/' + variant + '-smali', '-o', out + '/' + variant + '.dex'])!
	command(out, variant + '-disassemble', [java, '-cp', out + '/tools/*', 'org.jf.baksmali.Main',
		'disassemble', '--jobs', '2', out + '/' + variant + '.dex', '-o', out + '/' + variant + '-roundtrip'])!
	return os.read_file(out + '/' + variant + '-roundtrip/' + classes[0])!
}

fn check() ! {
	if os.args.len !in [4, 5] {
		return error('usage: system-package-check BASELINE_ROOT JAVA FRESH_EXTERNAL_OUT [SOURCE_ROOT]')
	}
	base := os.real_path(os.args[1])
	java := os.real_path(os.args[2])
	out := os.abs_path(os.args[3])
	source_root := os.real_path(if os.args.len == 5 { os.args[4] } else { '.' })
	if os.exists(out) || os.is_link(out) { return error('fresh output required') }
	if out == source_root || out.starts_with(source_root + '/') || out == base || out.starts_with(base + '/') {
		return error('output must be outside baseline and source roots')
	}
	started := time.utc().str()
	if hash(base + '/sha256.json')! != seal { return error('baseline manifest seal mismatch') }
	manifest := json2.decode[map[string]string](os.read_file(base + '/sha256.json')!)!
	mut before := map[string]string{}
	before[base + '/sha256.json'] = seal
	before[java] = hash(java)!
	before[os.executable()] = hash(os.executable())!
	os.mkdir_all(out + '/tools')!
	os.mkdir_all(out + '/commands')!
	os.mkdir_all(out + '/negative')!
	os.cp(base + '/sha256.json', out + '/baseline-sha256.json')!
	os.cp(os.executable(), out + '/checker')!
	for relative in classes {
		key := 'disassembled-325/' + relative
		pin := manifest[key] or { return error('unsealed baseline class: ' + key) }
		if hash(base + '/' + key)! != pin { return error('baseline class changed: ' + key) }
		before[base + '/' + key] = pin
		destination := out + '/reference/' + relative
		os.mkdir_all(os.dir(destination))!
		os.cp(base + '/' + key, destination)!
		before[destination] = hash(destination)!
		if before[destination]! != pin { return error('reference copy changed: ' + key) }
	}
	for name in jars {
		key := 'tools/framework/' + name
		pin := manifest[key] or { return error('unsealed tool: ' + key) }
		if hash(base + '/' + key)! != pin { return error('baseline tool changed: ' + key) }
		before[base + '/' + key] = pin
		os.cp(base + '/' + key, out + '/tools/' + name)!
		before[out + '/tools/' + name] = hash(out + '/tools/' + name)!
		if before[out + '/tools/' + name]! != pin { return error('tool copy changed: ' + key) }
	}
	// These source observations and the executable digest allow the build receipt
	// to bind its consumed closure; source observation alone is not compilation proof.
	mut source_paths := [self]
	module_path := 'tests/native-android-tools/androidtools'
	for name in os.ls(source_root + '/' + module_path)! {
		if name.ends_with('.v') { source_paths << module_path + '/' + name }
	}
	for relative in source_paths {
		path := source_root + '/' + relative
		before[path] = hash(path)!
		os.mkdir_all(os.dir(out + '/sources/' + relative))!
		os.cp(path, out + '/sources/' + relative)!
	}
	write_json(out + '/inputs-before.json', before)!
	original := os.read_file(out + '/reference/' + classes[0])!
	system := method(original, header)!
	changed := androidtools.framework_system_application(original)!
	if original.count(collect) != 1 || changed != original.replace(collect, '') {
		return error('transformation must remove exactly the system collector instruction')
	}
	if method(changed, header)!.contains('->collectCertificates(') {
		return error('system collector survives')
	}
	loader_header := '.method public static loadFromPath(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)Landroid/atl/ATLLoadedApp;'
	loader := method(changed, loader_header)!
	for required in ['invoke-virtual {v2, v1, v7}, Landroid/content/pm/PackageParser;->collectCertificates(',
		'move-result v2', 'if-nez v2,', '"APK signature verification failed"', 'throw v2'] {
		if !loader.contains(required) { return error('authenticated loader missing: ' + required) }
	}
	mut rejected := map[string]string{}
	negative := {
		'missing-method': original.replace(header, header.replace('getSystemApplication', 'otherFactory'))
		'duplicate-method': original + '\n' + system + '\n'
		'unterminated-method': original.all_before(header) + system.all_before('.end method')
		'missing-collector': original.replace(collect, '')
		'duplicate-collector': original.replace(collect, collect + collect)
		'wrong-collector-registers': original.replace(collect, collect.replace('{v0, v2, v6}', '{v1, v2, v6}'))
		'non-null-parser': original.replace(null_parser, null_parser.replace('const/4 v1, 0x0', 'const-string v1, "external.apk"'))
		'wrong-parser-constructor': original.replace(null_parser, null_parser.replace('Ljava/lang/String;', 'Ljava/io/File;'))
		'wrong-resource-origin': original.replace(resources, resources.replace('getSystem()', 'otherResources()'))
		'duplicate-resource-origin': original.replace(resources, resources + '\n' + resources)
	}
	for name, input in negative {
		os.write_file(out + '/negative/' + name + '.smali', input)!
		androidtools.framework_system_application(input) or { rejected[name] = err.msg(); continue }
		return error('accepted negative case: ' + name)
	}
	write_json(out + '/negative-cases.json', rejected)!
	for variant, source in {'original': original, 'changed': changed} {
		path := out + '/' + variant + '-smali/' + classes[0]
		os.mkdir_all(os.dir(path))!
		os.write_file(path, source)!
	}
	old_methods := methods(roundtrip(out, java, 'original')!)!
	new_methods := methods(roundtrip(out, java, 'changed')!)!
	if old_methods.len != new_methods.len { return error('DEX method set changed') }
	for declaration, body in old_methods {
		other := new_methods[declaration] or { return error('DEX method removed: ' + declaration) }
		if declaration != header && body != other { return error('unrelated DEX method changed: ' + declaration) }
	}
	if new_methods[header]!.contains('->collectCertificates(') || !old_methods[header]!.contains('->collectCertificates(') {
		return error('unexpected DEX system collector state')
	}
	for path, pin in before {
		if hash(path)! != pin { return error('input changed during check: ' + path) }
	}
	write_json(out + '/inputs-after.json', before)!
	write_json(out + '/result.json', {
		'scope': json2.Any('HOST transformation and one-class DEX roundtrip only; guest dialog and APK crypto unverified')
		'baseline_manifest_sha256': json2.Any(seal)
		'started_utc': json2.Any(started)
		'completed_utc': json2.Any(time.utc().str())
		'argv': json2.Any(os.args)
		'negative_cases': json2.Any(rejected.len)
		'unchanged_other_dex_methods': json2.Any(new_methods.len - 1)
		'one_system_call_removed': json2.Any(true)
		'external_loader_unchanged': json2.Any(method(original, loader_header)! == loader)
		'reference_verifier_manager_parser_unchanged': json2.Any(true)
		'source_observations_are_compilation_proof': json2.Any(false)
		'exit_code': json2.Any(0)
	})!
	mut pins := map[string]string{}
	inventory(out, '', mut pins)!
	write_json(out + '/sha256.json', pins)!
	println('SYSTEM-PACKAGE-HOST-PASS files=${pins.len} manifest=${hash(out + '/sha256.json')!}')
}

fn main() {
	$if prod { eprintln('requires assertions; compile without -prod'); exit(2) }
	check() or { eprintln(err); exit(1) }
}
