// SPDX-License-Identifier: GPL-2.0-or-later
// Guest API regression; fixture values only, no Google credentials or network.
module main

import crypto.sha256
import json2
import os

const owner = 'Lorg/vinix/bootstrap/Main;'
const context = 'Landroid/content/Context;'
const info = 'Landroid/content/pm/ApplicationInfo;'
const prefs = 'Landroid/content/SharedPreferences;'
const editor = 'Landroid/content/SharedPreferences$Editor;'
const pass_marker = 'PROTECTED-STORAGE-PASS direct-fields copy-null metadata paths preferences wrapper configuration package-context'

fn method(signature string, locals int, body string) string {
	return '.method ' + signature + '\n.locals ${locals}\n' + body + '\n.end method\n'
}

fn failure(message string) string {
	return ':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "${message}"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
}

fn check(expected string, actual string, stage string) string {
	return 'const-string v6, "${stage}"\ninvoke-static {${expected}, ${actual}, v6}, ${owner}->checkEqual(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V\n'
}

fn field_checks(first string, second string) string {
	mut body := ''
	for field in ['dataDir', 'credentialProtectedDataDir', 'deviceProtectedDataDir'] {
		body += 'iget-object v4, ${first}, ${info}->${field}:Ljava/lang/String;\n' +
			'iget-object v5, ${second}, ${info}->${field}:Ljava/lang/String;\n' +
			check('v4', 'v5', 'metadata ' + field)
	}
	return body
}

fn checks() string {
	return method('private static checkEqual(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V', 1, '
if-eq p0, p1, :ok
if-eqz p0, :bad
invoke-virtual {p0, p1}, Ljava/lang/Object;->equals(Ljava/lang/Object;)Z
move-result v0
if-nez v0, :ok
:bad
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
return-void') + method('private static checkDirectory(Ljava/io/File;Ljava/io/File;Ljava/lang/String;)V', 1, '
invoke-static {p0, p1, p2}, ${owner}->checkEqual(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
invoke-virtual {p1}, Ljava/io/File;->isDirectory()Z
move-result v0
if-nez v0, :ok
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
return-void')
}

fn path_checks() string {
	mut body := '
invoke-virtual {p0}, ${context}->isDeviceProtectedStorage()Z
move-result v0
if-ne v0, p2, :bad
new-instance v0, Ljava/io/File;
invoke-direct {v0, p1}, Ljava/io/File;-><init>(Ljava/lang/String;)V
invoke-virtual {p0}, ${context}->getDataDir()Ljava/io/File;
move-result-object v1
const-string v2, "context data root"
invoke-static {v0, v1, v2}, ${owner}->checkDirectory(Ljava/io/File;Ljava/io/File;Ljava/lang/String;)V
'
	for signature, child in {'getFilesDir()': 'files', 'getCacheDir()': 'cache'} {
		body += 'new-instance v1, Ljava/io/File;\nconst-string v2, "${child}"\n' +
			'invoke-direct {v1, v0, v2}, Ljava/io/File;-><init>(Ljava/io/File;Ljava/lang/String;)V\n' +
			'invoke-virtual {p0}, ${context}->${signature}Ljava/io/File;\nmove-result-object v3\n' +
			'invoke-static {v1, v3, v2}, ${owner}->checkDirectory(Ljava/io/File;Ljava/io/File;Ljava/lang/String;)V\n'
	}
	body += '
new-instance v1, Ljava/io/File;
const-string v2, "app_storage_probe"
invoke-direct {v1, v0, v2}, Ljava/io/File;-><init>(Ljava/io/File;Ljava/lang/String;)V
const-string v2, "storage_probe"
const/4 v3, 0
invoke-virtual {p0, v2, v3}, ${context}->getDir(Ljava/lang/String;I)Ljava/io/File;
move-result-object v3
invoke-static {v1, v3, v2}, ${owner}->checkDirectory(Ljava/io/File;Ljava/io/File;Ljava/lang/String;)V
new-instance v1, Ljava/io/File;
const-string v2, "databases/storage_probe.db"
invoke-direct {v1, v0, v2}, Ljava/io/File;-><init>(Ljava/io/File;Ljava/lang/String;)V
const-string v2, "storage_probe.db"
invoke-virtual {p0, v2}, ${context}->getDatabasePath(Ljava/lang/String;)Ljava/io/File;
move-result-object v3
invoke-static {v1, v3, v2}, ${owner}->checkEqual(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
return-void
' + failure('device flag or storage path')
	return method('private static checkPaths(${context}Ljava/lang/String;Z)V', 4, body)
}

fn preferences_check() string {
	mut body := '
const-string v2, "protected_storage_probe"
const/4 v3, 0
invoke-virtual {p0, v2, v3}, ${context}->getSharedPreferences(Ljava/lang/String;I)${prefs}
move-result-object v0
invoke-virtual {p1, v2, v3}, ${context}->getSharedPreferences(Ljava/lang/String;I)${prefs}
move-result-object v1
if-eq v0, v1, :bad
'
	for register, value in {'v0': 'credential', 'v1': 'device'} {
		body += 'invoke-interface {${register}}, ${prefs}->edit()${editor}\nmove-result-object v2\n' +
			'const-string v3, "storage"\nconst-string v4, "${value}"\n' +
			'invoke-interface {v2, v3, v4}, ${editor}->putString(Ljava/lang/String;Ljava/lang/String;)${editor}\n' +
			'invoke-interface {v2}, ${editor}->commit()Z\nmove-result v2\nif-eqz v2, :bad\n'
	}
	for register, value in {'v0': 'credential', 'v1': 'device'} {
		body += 'const-string v2, "storage"\nconst/4 v3, 0\n' +
			'invoke-interface {${register}, v2, v3}, ${prefs}->getString(Ljava/lang/String;Ljava/lang/String;)Ljava/lang/String;\nmove-result-object v2\n' +
			'const-string v3, "${value}"\nconst-string v4, "isolated preferences"\n' +
			'invoke-static {v3, v2, v4}, ${owner}->checkEqual(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V\n'
	}
	for register in ['p0', 'p1'] {
		body += 'invoke-virtual {${register}}, ${context}->getDataDir()Ljava/io/File;\nmove-result-object v0\n' +
			'new-instance v1, Ljava/io/File;\nconst-string v2, "shared_prefs/protected_storage_probe.xml"\n' +
			'invoke-direct {v1, v0, v2}, Ljava/io/File;-><init>(Ljava/io/File;Ljava/lang/String;)V\n' +
			'invoke-virtual {v1}, Ljava/io/File;->isFile()Z\nmove-result v0\nif-eqz v0, :bad\n'
	}
	body += 'return-void\n' + failure('CE and DE preference storage must be isolated and committed')
	return method('private static checkPreferences(${context}${context})V', 5, body)
}

fn main_class() string {
	mut source := '.class public ${owner}\n.super Landroid/app/Activity;\n'
	source += method('public constructor <init>()V', 0, 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void')
	source += checks() + path_checks() + preferences_check()
	mut body := '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
invoke-virtual {p0}, ${context}->getApplicationInfo()${info}
move-result-object v0
# Direct field resolution must happen before any reflection or Context calls.
iget-object v1, v0, ${info}->credentialProtectedDataDir:Ljava/lang/String;
iget-object v2, v0, ${info}->deviceProtectedDataDir:Ljava/lang/String;
if-eqz v1, :bad
if-eqz v2, :bad
iget-object v4, v0, ${info}->dataDir:Ljava/lang/String;
' + check('v1', 'v4', 'default credential directory') + '
invoke-virtual {v1, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v4
if-nez v4, :bad
new-instance v3, Ljava/io/File;
const-string v4, "device_protected"
invoke-direct {v3, v1, v4}, Ljava/io/File;-><init>(Ljava/lang/String;Ljava/lang/String;)V
invoke-virtual {v3}, Ljava/io/File;->getAbsolutePath()Ljava/lang/String;
move-result-object v5
' + check('v5', 'v2', 'private device directory namespace') + '
new-instance v3, ${info}
invoke-direct {v3, v0}, ${info}-><init>(${info})V
' + field_checks('v0', 'v3') + '
new-instance v0, ${info}
invoke-direct {v0}, ${info}-><init>()V
const/4 v4, 0
iget-object v5, v0, ${info}->credentialProtectedDataDir:Ljava/lang/String;
' + check('v4', 'v5', 'null credential default') + '
iget-object v5, v0, ${info}->deviceProtectedDataDir:Ljava/lang/String;
' + check('v4', 'v5', 'null device default') + '
const-string v4, "copy-only-device-value"
iput-object v4, v0, ${info}->deviceProtectedDataDir:Ljava/lang/String;
new-instance v3, ${info}
invoke-direct {v3, v0}, ${info}-><init>(${info})V
' + field_checks('v0', 'v3') + '
invoke-virtual {p0}, Landroid/app/Activity;->getApplication()Landroid/app/Application;
move-result-object v0
invoke-virtual {v0}, ${context}->getApplicationInfo()${info}
move-result-object v0
invoke-virtual {p0}, ${context}->getApplicationInfo()${info}
move-result-object v3
if-ne v0, v3, :bad
invoke-virtual {p0}, ${context}->getPackageManager()Landroid/content/pm/PackageManager;
move-result-object v3
invoke-virtual {p0}, ${context}->getPackageName()Ljava/lang/String;
move-result-object v4
const/4 v5, 0
invoke-virtual {v3, v4, v5}, Landroid/content/pm/PackageManager;->getApplicationInfo(Ljava/lang/String;I)${info}
move-result-object v3
' + field_checks('v0', 'v3') + '
const/4 v4, 0
invoke-static {p0, v1, v4}, ${owner}->checkPaths(${context}Ljava/lang/String;Z)V
invoke-virtual {p0}, ${context}->createDeviceProtectedStorageContext()${context}
move-result-object v3
const/4 v4, 1
invoke-static {v3, v2, v4}, ${owner}->checkPaths(${context}Ljava/lang/String;Z)V
invoke-static {p0, v3}, ${owner}->checkPreferences(${context}${context})V
# Nested wrappers must route inherited file methods through the device context.
new-instance v0, Landroid/content/ContextWrapper;
invoke-direct {v0, v3}, Landroid/content/ContextWrapper;-><init>(${context})V
new-instance v5, Landroid/content/ContextWrapper;
invoke-direct {v5, v0}, Landroid/content/ContextWrapper;-><init>(${context})V
invoke-static {v5, v2, v4}, ${owner}->checkPaths(${context}Ljava/lang/String;Z)V
invoke-virtual {v3}, ${context}->getResources()Landroid/content/res/Resources;
move-result-object v0
invoke-virtual {v0}, Landroid/content/res/Resources;->getConfiguration()Landroid/content/res/Configuration;
move-result-object v0
invoke-virtual {v3, v0}, ${context}->createConfigurationContext(Landroid/content/res/Configuration;)${context}
move-result-object v5
invoke-static {v5, v2, v4}, ${owner}->checkPaths(${context}Ljava/lang/String;Z)V
invoke-virtual {p0}, ${context}->getPackageName()Ljava/lang/String;
move-result-object v0
const/4 v4, 0
invoke-virtual {p0, v0, v4}, ${context}->createPackageContext(Ljava/lang/String;I)${context}
move-result-object v5
invoke-static {v5, v1, v4}, ${owner}->checkPaths(${context}Ljava/lang/String;Z)V
invoke-virtual {v5}, ${context}->createDeviceProtectedStorageContext()${context}
move-result-object v5
const/4 v4, 1
invoke-static {v5, v2, v4}, ${owner}->checkPaths(${context}Ljava/lang/String;Z)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${pass_marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(${context})V
const-string v1, "Protected storage API regression passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
return-void
' + failure('protected storage metadata, defaults, identity or flags')
	source += method('public onCreate(Landroid/os/Bundle;)V', 7, body)
	return source
}

fn recorded(out string, name string, args []string) string {
	r := os.exec(args)
	os.write_file(out + '/commands/' + name + '.json', json2.encode({
		'argv': json2.Any(args)
		'exit_code': json2.Any(r.exit_code)
		'output': json2.Any(r.output)
	}, prettify: true) + '\n') or { panic(err) }
	if r.exit_code != 0 { panic(r.output) }
	return r.output
}

fn inventory(root string, relative string, mut pins map[string]string) ! {
	for name in os.ls(root + '/' + relative)! {
		key := if relative == '' { name } else { relative + '/' + name }
		if key == 'sha256.json' { continue }
		path := root + '/' + key
		if os.is_link(path) { return error('unexpected output symlink') }
		if os.is_dir(path) {
			inventory(root, key, mut pins)!
		} else if os.is_file(path) {
			pins[key] = sha256.sum(os.read_bytes(path)!).hex()
		} else { return error('unexpected output file type') }
	}
}

fn main() {
	smali_only := os.args.len == 5 && os.args[1] == '--smali-check'
	if !smali_only && os.args.len != 6 { panic('OUTPUT FIXTURE_DIR SMALI_TOOLS JAVA APKSIGNER | --smali-check OUTPUT SMALI_TOOLS JAVA') }
	out := os.abs_path(os.args[if smali_only { 2 } else { 1 }])
	tools, java := os.real_path(os.args[3]), os.real_path(os.args[4])
	repo := os.real_path(os.dir(@FILE) + '/../..')
	if os.exists(out) || out == repo || out.starts_with(repo + '/') { panic('fresh external output required') }
	root := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(root)!
	os.mkdir_all(out + '/commands')!
	os.write_file(root + '/Main.smali', main_class())!
	mut inputs := map[string]string{}
	for path in [@FILE, os.executable(), java] { inputs[os.real_path(path)] = sha256.sum(os.read_bytes(path)!).hex() }
	for name in os.ls(tools)! {
		if name.ends_with('.jar') { inputs[tools + '/' + name] = sha256.sum(os.read_bytes(tools + '/' + name)!).hex() }
	}
	if !smali_only {
		fixture := os.real_path(os.args[2])
		for name in ['App', 'High', 'Low'] {
			path := fixture + '/smali/org/vinix/bootstrap/' + name + '.smali'
			inputs[path] = sha256.sum(os.read_bytes(path)!).hex()
			os.cp(path, root + '/' + name + '.smali')!
		}
	}
	dex := out + '/classes.dex'
	assembly := recorded(out, 'assemble', [java, '-Xmx512m', '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', '--jobs', '2', out + '/smali', '-o', dex])
	assert assembly.trim_space() == '', assembly
	assert os.is_file(dex)
	recorded(out, 'roundtrip', [java, '-Xmx512m', '-cp', tools + '/*', 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', dex, '-o', out + '/roundtrip'])
	decoded := os.read_file(out + '/roundtrip/org/vinix/bootstrap/Main.smali')!
	for expected in ['->deviceProtectedDataDir:Ljava/lang/String;', '->credentialProtectedDataDir:Ljava/lang/String;', pass_marker, '->createConfigurationContext(', '->commit()Z'] {
		assert decoded.contains(expected), 'DEX roundtrip missing: ' + expected
	}
	mut apk_hash := ''
	if !smali_only {
		fixture, signer := os.real_path(os.args[2]), os.real_path(os.args[5])
		for path in [fixture + '/unsigned.apk', fixture + '/fixture.p12', signer] { inputs[path] = sha256.sum(os.read_bytes(path)!).hex() }
		os.cp(fixture + '/unsigned.apk', out + '/unsigned.apk')!
		recorded(out, 'zip', ['zip', '-q', '-j', out + '/unsigned.apk', dex])
		recorded(out, 'sign', [java, '-Xmx512m', '-jar', signer, 'sign', '--ks', fixture + '/fixture.p12', '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'])
		verification := recorded(out, 'verify', [java, '-Xmx512m', '-jar', signer, 'verify', '--verbose', out + '/probe.apk'])
		assert verification.contains('Verified using v3 scheme (APK Signature Scheme v3): true'), 'APK v3 signature verification missing'
		apk_hash = sha256.sum(os.read_bytes(out + '/probe.apk')!).hex()
	}
	for path, pin in inputs { assert sha256.sum(os.read_bytes(path)!).hex() == pin, 'input changed: ' + path }
	revision := os.exec(['git', '-C', repo, 'rev-parse', 'HEAD'])
	assert revision.exit_code == 0
	mut input_pins := map[string]json2.Any{}
	for path, pin in inputs { input_pins[path] = pin }
	os.write_file(out + '/build.json', json2.encode({
		'argv': json2.Any(os.args)
		'source_revision': json2.Any(revision.output.trim_space())
		'inputs_sha256': json2.Any(input_pins)
		'apk_sha256': json2.Any(apk_hash)
		'pass_marker': json2.Any(pass_marker)
		'scope': json2.Any('Direct ApplicationInfo fields, null-preserving copies, CE/DE context paths and preferences, nested wrappers, configuration and same-package contexts. Vinix uses distinct private storage subdirectories, without separate encryption or unlock states. APK assembly and DEX roundtrip are not ART execution; no account credentials/network.')
	}, prettify: true) + '\n')!
	os.cp(@FILE, out + '/builder.v')!
	os.cp(os.executable(), out + '/builder')!
	mut pins := map[string]string{}
	inventory(out, '', mut pins)!
	os.write_file(out + '/sha256.json', json2.encode(pins, prettify: true) + '\n')!
	println(if smali_only { 'PROTECTED-STORAGE-SMALI-PASS source generation and DEX roundtrip; ART not executed' } else { 'PROTECTED-STORAGE-APK ' + out + '/probe.apk' })
	println('PROTECTED-STORAGE-SEAL ' + sha256.sum(os.read_bytes(out + '/sha256.json')!).hex())
}
