// SPDX-License-Identifier: GPL-2.0-or-later
// Signed ARM guest fixture for the single-user, absent restrictions contract.
module main

import crypto.sha256
import json2
import os

const owner = 'Lorg/vinix/bootstrap/Main;'
const marker = 'APPLICATION-RESTRICTIONS-PASS own-package nonnull empty fresh-bundles missing-string-array mutation-isolation repeated-32'

fn method(signature string, locals int, body string) string {
	return '.method ${signature}\n.locals ${locals}\n${body}\n.end method\n'
}

fn failure(message string) string {
	return ':bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "${message}"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
}

fn main_class() string {
	mut source := '.class public ${owner}\n.super Landroid/app/Activity;\n'
	source += method('public constructor <init>()V', 0,
		'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void')
	source += method('private static checkEmpty(Landroid/os/Bundle;)V', 2, '
if-eqz p0, :bad
invoke-virtual {p0}, Landroid/os/Bundle;->isEmpty()Z
move-result v0
if-eqz v0, :bad
const-string v0, "vinix_missing_restrictions"
invoke-virtual {p0, v0}, Landroid/os/Bundle;->getStringArray(Ljava/lang/String;)[Ljava/lang/String;
move-result-object v0
if-nez v0, :bad
return-void
' + failure('application restrictions must return a nonnull empty Bundle with no String array'))
	source += method('private static mutate(Landroid/os/Bundle;)V', 3, '
const/4 v0, 1
new-array v0, v0, [Ljava/lang/String;
const/4 v1, 0
const-string v2, "caller-owned"
aput-object v2, v0, v1
const-string v1, "vinix_missing_restrictions"
invoke-virtual {p0, v1, v0}, Landroid/os/Bundle;->putStringArray(Ljava/lang/String;[Ljava/lang/String;)V
invoke-virtual {p0}, Landroid/os/Bundle;->isEmpty()Z
move-result v2
if-nez v2, :bad
invoke-virtual {p0, v1}, Landroid/os/Bundle;->getStringArray(Ljava/lang/String;)[Ljava/lang/String;
move-result-object v1
if-eqz v1, :bad
const/4 v0, 0
aget-object v0, v1, v0
const-string v1, "caller-owned"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
return-void
' + failure('application restrictions fixture mutation must be observable in its own Bundle'))
	source += method('public onCreate(Landroid/os/Bundle;)V', 7, '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
const-string v0, "user"
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
if-eqz v0, :bad
check-cast v0, Landroid/os/UserManager;
invoke-virtual {p0}, Landroid/content/Context;->getPackageName()Ljava/lang/String;
move-result-object v1
const-string v2, "org.vinix.bootstrap"
invoke-virtual {v2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
invoke-virtual {v0, v1}, Landroid/os/UserManager;->getApplicationRestrictions(Ljava/lang/String;)Landroid/os/Bundle;
move-result-object v2
invoke-static {v2}, ${owner}->checkEmpty(Landroid/os/Bundle;)V
invoke-virtual {v0, v1}, Landroid/os/UserManager;->getApplicationRestrictions(Ljava/lang/String;)Landroid/os/Bundle;
move-result-object v3
invoke-static {v3}, ${owner}->checkEmpty(Landroid/os/Bundle;)V
if-eq v2, v3, :bad
invoke-static {v2}, ${owner}->mutate(Landroid/os/Bundle;)V
invoke-static {v3}, ${owner}->checkEmpty(Landroid/os/Bundle;)V
move-object v4, v3
const/4 v5, 0
:repeat
invoke-virtual {v0, v1}, Landroid/os/UserManager;->getApplicationRestrictions(Ljava/lang/String;)Landroid/os/Bundle;
move-result-object v6
invoke-static {v6}, ${owner}->checkEmpty(Landroid/os/Bundle;)V
if-eq v6, v2, :bad
if-eq v6, v3, :bad
if-eq v6, v4, :bad
invoke-static {v6}, ${owner}->mutate(Landroid/os/Bundle;)V
invoke-static {v3}, ${owner}->checkEmpty(Landroid/os/Bundle;)V
move-object v4, v6
add-int/lit8 v5, v5, 1
const/16 v6, 32
if-lt v5, v6, :repeat
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "${marker}"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0}, Ljava/io/PrintStream;->flush()V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Application restrictions contract passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
return-void
' + failure('application restrictions own-package lookup, identity or mutation isolation'))
	return source
}

fn hash(path string) string {
	return sha256.sum(os.read_bytes(path) or { panic(err) }).hex()
}

fn recorded(out string, label string, args []string) string {
	r := os.exec(args)
	os.write_file(out + '/commands/' + label + '.json', json2.encode({
		'argv': json2.Any(args), 'exit_code': json2.Any(r.exit_code), 'output': json2.Any(r.output)
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
		if os.is_dir(path) { inventory(root, key, mut pins)! } else if os.is_file(path) { pins[key] = hash(path) } else { return error('unexpected output file type') }
	}
}

fn main() {
	$if prod { eprintln('requires assertions; compile without -prod'); exit(2) }
	if os.args.len != 7 { panic('OUTPUT AAPT2 FRAMEWORK_RES SMALI_TOOLS JAVA APKSIGNER') }
	out, aapt, resources, tools, java, signer := os.abs_path(os.args[1]), os.real_path(os.args[2]), os.real_path(os.args[3]), os.real_path(os.args[4]), os.real_path(os.args[5]), os.real_path(os.args[6])
	repo := os.real_path(os.dir(@FILE) + '/../..')
	if os.exists(out) || os.is_link(out) || out == repo || out.starts_with(repo + '/') { panic('fresh external output required') }
	os.mkdir_all(out + '/commands')!
	key, keytool := out + '/fixture.p12', os.dir(java) + '/keytool'
	mut inputs := map[string]string{}
	for path in [@FILE, os.executable(), aapt, resources, java, signer, keytool, '/usr/bin/zip'] { inputs[os.real_path(path)] = hash(path) }
	for name in os.ls(tools)! { if name.ends_with('.jar') { inputs[tools + '/' + name] = hash(tools + '/' + name) } }
	os.mkdir_all(out + '/smali/org/vinix/bootstrap')!
	os.write_file(out + '/smali/org/vinix/bootstrap/Main.smali', main_class())!
	os.write_file(out + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="23" android:targetSdkVersion="35"/><application android:label="Application restrictions regression"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
	assembly := recorded(out, 'assemble', [java, '-Xmx512m', '-XX:ActiveProcessorCount=2', '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', '--jobs', '2', out + '/smali', '-o', out + '/classes.dex'])
	assert assembly.trim_space() == '' && os.file_size(out + '/classes.dex') > 112, assembly
	recorded(out, 'roundtrip', [java, '-Xmx512m', '-XX:ActiveProcessorCount=2', '-cp', tools + '/*', 'org.jf.baksmali.Main', 'disassemble', '--jobs', '2', out + '/classes.dex', '-o', out + '/roundtrip'])
	decoded := os.read_file(out + '/roundtrip/org/vinix/bootstrap/Main.smali')!
	for expected in [marker, '->getSystemService(Ljava/lang/String;)', '->getPackageName()',
		'->getApplicationRestrictions(Ljava/lang/String;)Landroid/os/Bundle;', '->isEmpty()Z',
		'->getStringArray(Ljava/lang/String;)[Ljava/lang/String;', '->putStringArray(Ljava/lang/String;[Ljava/lang/String;)V',
		'if-eq', 'const/16 v6, 0x20'] { assert decoded.contains(expected), expected }
	recorded(out, 'link', [aapt, 'link', '--manifest', out + '/AndroidManifest.xml', '-I', resources, '-o', out + '/unsigned.apk'])
	recorded(out, 'manifest', [aapt, 'dump', 'xmltree', out + '/unsigned.apk', '--file', 'AndroidManifest.xml'])
	recorded(out, 'zip', ['/usr/bin/zip', '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'])
	recorded(out, 'keytool', [keytool, '-genkeypair', '-keystore', key, '-storetype', 'PKCS12', '-storepass', 'android', '-keypass', 'android', '-alias', 'fixture', '-dname', 'CN=Vinix Application Restrictions Fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650'])
	recorded(out, 'sign', [java, '-Xmx512m', '-jar', signer, 'sign', '--ks', key, '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'])
	verified := recorded(out, 'verify', [java, '-Xmx512m', '-jar', signer, 'verify', '--verbose', out + '/probe.apk'])
	assert verified.contains('Verified using v3 scheme (APK Signature Scheme v3): true')
	for path, pin in inputs { assert hash(path) == pin, 'input changed: ' + path }
	revision := os.exec(['git', '-C', repo, 'rev-parse', 'HEAD'])
	assert revision.exit_code == 0
	os.write_file(out + '/build.json', json2.encode({
		'argv': json2.Any(os.args), 'source_revision': json2.Any(revision.output.trim_space()),
		'inputs_sha256': json2.decode[json2.Any](json2.encode(inputs))!,
		'apk_sha256': json2.Any(hash(out + '/probe.apk')), 'pass_marker': json2.Any(marker),
		'scope': json2.Any('Single-user absent application restrictions: real own-package UserManager lookup, nonnull empty Bundle, fresh identities, absent String array and caller mutation isolation over 32 repeats. Signed APK assembly and DEX roundtrip only until ART execution. No account or network activity.')
	}, prettify: true) + '\n')!
	os.cp(@FILE, out + '/builder.v')!
	os.cp(os.executable(), out + '/builder')!
	mut pins := map[string]string{}
	inventory(out, '', mut pins)!
	os.write_file(out + '/sha256.json', json2.encode(pins, prettify: true) + '\n')!
	println('APPLICATION-RESTRICTIONS-FIXTURE-APK ' + out + '/probe.apk')
}
