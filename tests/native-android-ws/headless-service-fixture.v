// SPDX-License-Identifier: GPL-2.0-or-later
// Host-built lifecycle probe for the headless Android Service entry point.
module main

import crypto.sha256
import json2
import os

const prefix = 'Lorg/vinix/headless/'
const package_name = 'org.vinix.headless'
const service_name = package_name + '.ProbeService'
const bind_action = package_name + '.BIND'
const ready_marker = 'HEADLESS-SERVICE-READY application-once main-looper context-order create bind delayed-binder'
const closed_marker = 'HEADLESS-SERVICE-CLOSED unbind destroy main-looper'

struct FixtureBuild {
	argv             []string
	source_revision  string
	inputs_sha256    map[string]string
	artifacts_sha256 map[string]string
	java_version     string
	apk_sha256       string
	package_name     string
	service_name     string
	bind_action      string
	binder_descriptor string
	ready_marker     string
	closed_marker    string
}

struct CommandReceipt {
	argv   []string
	status int
	output string
}

fn checked(args []string) string {
	r := os.exec(args)
	if r.exit_code != 0 { panic(r.output) }
	return r.output
}

fn recorded(out string, name string, args []string) string {
	r := os.exec(args)
	os.write_file(out + '/commands/' + name + '.json', json2.encode(CommandReceipt{args, r.exit_code, r.output},
		prettify: true
	)) or { panic(err) }
	if r.exit_code != 0 { panic(r.output) }
	return r.output
}

fn file_hash(path string) string {
	return sha256.sum(os.read_bytes(path) or { panic(err) }).hex()
}

fn output_files(path string) []string {
	mut files := []string{}
	for name in os.ls(path) or { panic(err) } {
		item := os.join_path(path, name)
		if os.is_link(item) { panic('unexpected output symlink: ' + item) }
		kind := (os.lstat(item) or { panic(err) }).get_filetype()
		if kind == .directory {
			files << output_files(item)
		} else if kind == .regular {
			files << item
		} else {
			panic('unexpected output type: ' + item)
		}
	}
	return files
}

fn method(signature string, body string) string {
	return '.method ${signature}\n.locals 8\n${body}\n.end method\n'
}

fn print_marker(marker string) string {
	return 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "${marker}"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\ninvoke-virtual {v0}, Ljava/io/PrintStream;->flush()V\n'
}

fn failure(stage string) string {
	return ':bad\n' + print_marker('HEADLESS-SERVICE-FAIL ' + stage) + 'new-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "headless service: ${stage}"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
}

fn main_looper() string {
	return 'invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;\nmove-result-object v0\nif-eqz v0, :bad\ninvoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;\nmove-result-object v1\nif-ne v0, v1, :bad\n'
}

fn phase(expected int) string {
	return 'sget v0, ${prefix}ProbeApplication;->phase:I\nconst/16 v1, ${expected}\nif-ne v0, v1, :bad\nsget v0, ${prefix}ProbeApplication;->starts:I\nconst/4 v1, 1\nif-ne v0, v1, :bad\n'
}

fn set_phase(value int) string {
	return 'const/16 v0, ${value}\nsput v0, ${prefix}ProbeApplication;->phase:I\n'
}

fn action_check() string {
	return 'if-eqz p1, :bad\ninvoke-virtual {p1}, Landroid/content/Intent;->getAction()Ljava/lang/String;\nmove-result-object v0\nconst-string v1, "${bind_action}"\ninvoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v0\nif-eqz v0, :bad\n'
}

fn application_source() string {
	mut source := '.class public ${prefix}ProbeApplication;\n.super Landroid/app/Application;\n.field public static starts:I\n.field public static phase:I\n.field public static instance:${prefix}ProbeApplication;\n'
	source += method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Application;-><init>()V\nreturn-void')
	source += method('public onCreate()V', '
invoke-super {p0}, Landroid/app/Application;->onCreate()V
' + main_looper() + '
sget v0, ${prefix}ProbeApplication;->phase:I
if-nez v0, :bad
sget v0, ${prefix}ProbeApplication;->starts:I
add-int/lit8 v0, v0, 1
sput v0, ${prefix}ProbeApplication;->starts:I
const/4 v1, 1
if-ne v0, v1, :bad
invoke-virtual {p0}, Landroid/content/ContextWrapper;->getBaseContext()Landroid/content/Context;
move-result-object v0
if-eqz v0, :bad
invoke-virtual {p0}, Landroid/content/ContextWrapper;->getPackageName()Ljava/lang/String;
move-result-object v0
const-string v1, "${package_name}"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
sput-object p0, ${prefix}ProbeApplication;->instance:${prefix}ProbeApplication;
' + set_phase(1) + 'return-void\n' + failure('application-onCreate'))
	return source
}

fn service_source() string {
	mut source := '.class public ${prefix}ProbeService;\n.super Landroid/app/Service;\n.implements Ljava/lang/Runnable;\n.field private binder:Landroid/os/Binder;\n'
	// Service.getApplication delegates through its context in this runtime, so only
	// getBaseContext is valid before the framework attaches the service context.
	source += method('public constructor <init>()V', '
invoke-direct {p0}, Landroid/app/Service;-><init>()V
' + main_looper() + phase(1) + '
invoke-virtual {p0}, Landroid/content/ContextWrapper;->getBaseContext()Landroid/content/Context;
move-result-object v0
if-nez v0, :bad
' + set_phase(2) + 'return-void\n' + failure('service-constructor'))
	source += method('public onCreate()V', '
invoke-super {p0}, Landroid/app/Service;->onCreate()V
' + main_looper() + phase(2) + '
invoke-virtual {p0}, Landroid/app/Service;->getApplication()Landroid/app/Application;
move-result-object v0
sget-object v1, ${prefix}ProbeApplication;->instance:${prefix}ProbeApplication;
if-eqz v1, :bad
if-ne v0, v1, :bad
invoke-virtual {p0}, Landroid/content/ContextWrapper;->getBaseContext()Landroid/content/Context;
move-result-object v0
if-eqz v0, :bad
invoke-virtual {v0}, Landroid/content/Context;->getPackageName()Ljava/lang/String;
move-result-object v0
const-string v1, "${package_name}"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
' + set_phase(3) + 'return-void\n' + failure('service-onCreate'))
	source += method('public onBind(Landroid/content/Intent;)Landroid/os/IBinder;', main_looper() + phase(3) + action_check() + '
new-instance v0, Landroid/os/Binder;
invoke-direct {v0}, Landroid/os/Binder;-><init>()V
const/4 v1, 0
const-string v2, "${service_name}"
invoke-virtual {v0, v1, v2}, Landroid/os/Binder;->attachInterface(Landroid/os/IInterface;Ljava/lang/String;)V
iput-object v0, p0, ${prefix}ProbeService;->binder:Landroid/os/Binder;
' + set_phase(4) + '
new-instance v0, Landroid/os/Handler;
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
invoke-direct {v0, v1}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
const-wide/16 v1, 20
invoke-virtual {v0, p0, v1, v2}, Landroid/os/Handler;->postDelayed(Ljava/lang/Runnable;J)Z
move-result v0
if-eqz v0, :bad
iget-object v0, p0, ${prefix}ProbeService;->binder:Landroid/os/Binder;
return-object v0
' + failure('service-onBind'))
	source += method('public run()V', main_looper() + phase(4) + '
iget-object v0, p0, ${prefix}ProbeService;->binder:Landroid/os/Binder;
if-eqz v0, :bad
invoke-virtual {v0}, Landroid/os/Binder;->getInterfaceDescriptor()Ljava/lang/String;
move-result-object v0
const-string v1, "${service_name}"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
' + set_phase(5) + print_marker(ready_marker) + 'return-void\n' + failure('delayed-callback'))
	source += method('public onUnbind(Landroid/content/Intent;)Z', main_looper() + phase(5) + action_check() + set_phase(6) + 'const/4 v0, 0\nreturn v0\n' + failure('service-onUnbind'))
	source += method('public onDestroy()V', main_looper() + phase(6) + '
invoke-super {p0}, Landroid/app/Service;->onDestroy()V
' + set_phase(7) + print_marker(closed_marker) + 'return-void\n' + failure('service-onDestroy'))
	return source
}

fn trap_source() string {
	mut source := '.class public ${prefix}TrapActivity;\n.super Landroid/app/Activity;\n'
	source += method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\ngoto :bad\n' + failure('unexpected-activity-constructor'))
	source += method('protected onCreate(Landroid/os/Bundle;)V', 'goto :bad\n' + failure('unexpected-activity-onCreate'))
	return source
}

fn manifest() string {
	return '<?xml version="1.0"?><manifest xmlns:android="http://schemas.android.com/apk/res/android" package="${package_name}" android:versionCode="1"><uses-sdk android:minSdkVersion="29" android:targetSdkVersion="35"/><application android:name="${package_name}.ProbeApplication" android:label="Headless service fixture"><service android:name="${service_name}" android:enabled="true" android:exported="true"><intent-filter><action android:name="${bind_action}"/></intent-filter></service><activity android:name="${package_name}.TrapActivity" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>'
}

fn main() {
	if os.args.len != 7 { panic('OUTPUT AAPT2 FRAMEWORK_RES SMALI_TOOLS JAVA APKSIGNER') }
	out, aapt, resources, tools, java, signer := os.abs_path(os.args[1]), os.abs_path(os.args[2]), os.abs_path(os.args[3]), os.abs_path(os.args[4]), os.abs_path(os.args[5]), os.abs_path(os.args[6])
	if os.exists(out) { panic('output must be fresh: ' + out) }
	os.mkdir_all(out + '/commands')!
	os.mkdir_all(out + '/inputs')!
	os.cp(os.abs_path(@FILE), out + '/inputs/headless-service-fixture.v')!
	os.cp(os.executable(), out + '/inputs/generator')!
	key := out + '/fixture.p12'
	keytool := os.join_path(os.dir(os.real_path(java)), 'keytool')
	zip := checked(['which', 'zip']).trim_space()
	recorded(out, 'keytool', [keytool, '-genkeypair', '-keystore', key, '-storetype', 'PKCS12',
		'-storepass', 'android', '-keypass', 'android', '-alias', 'fixture', '-dname',
		'CN=Vinix Headless Service Fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650'])
	mut inputs := map[string]string{}
	for path in [os.abs_path(@FILE), os.executable(), aapt, resources, java, signer, keytool, zip,
		key] {
		inputs[path] = file_hash(path)
	}
	for name in os.ls(tools)! {
		path := os.join_path(tools, name)
		if os.is_file(path) { inputs[path] = file_hash(path) }
	}
	smali := out + '/smali/org/vinix/headless/'
	os.mkdir_all(smali)!
	os.mkdir_all(out + '/res/values')!
	os.write_file(smali + 'ProbeApplication.smali', application_source())!
	os.write_file(smali + 'ProbeService.smali', service_source())!
	os.write_file(smali + 'TrapActivity.smali', trap_source())!
	os.write_file(out + '/res/values/values.xml', '<resources><string name="fixture_name">Headless service fixture</string></resources>')!
	os.write_file(out + '/AndroidManifest.xml', manifest())!
	recorded(out, 'compile', [aapt, 'compile', '--dir', out + '/res', '-o', out + '/resources.zip'])
	recorded(out, 'link', [aapt, 'link', '-I', resources, out + '/resources.zip', '--manifest',
		out + '/AndroidManifest.xml', '-o', out + '/unsigned.apk'])
	assembly := recorded(out, 'assemble', [java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble',
		'--jobs', '2', out + '/smali', '-o', out + '/classes.dex'])
	if assembly.trim_space() != '' { panic('unexpected assembler diagnostics: ' + assembly) }
	recorded(out, 'zip', [zip, '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'])
	apk := out + '/probe.apk'
	recorded(out, 'sign', [java, '-jar', signer, 'sign', '--ks', key, '--ks-key-alias', 'fixture',
		'--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', apk, out + '/unsigned.apk'])
	verification := recorded(out, 'verify', [java, '-jar', signer, 'verify', '--verbose', apk])
	if !verification.contains('Verified using v3 scheme (APK Signature Scheme v3): true') {
		panic('APK v3 signature verification missing')
	}
	badging := recorded(out, 'badging', [aapt, 'dump', 'badging', apk])
	if !badging.contains("package: name='${package_name}'")
		|| !badging.contains("launchable-activity: name='${package_name}.TrapActivity'") {
		panic('APK package or trap launcher mismatch')
	}
	manifest_dump := recorded(out, 'manifest', [aapt, 'dump', 'xmltree', apk, '--file', 'AndroidManifest.xml'])
	for text in [service_name, bind_action, package_name + '.ProbeApplication'] {
		if !manifest_dump.contains(text) { panic('compiled manifest missing: ' + text) }
	}
	for path, before in inputs {
		if file_hash(path) != before { panic('input changed during build: ' + path) }
	}
	mut artifacts := map[string]string{}
	for path in output_files(out) { artifacts[path.all_after(out + '/')] = file_hash(path) }
	receipt := FixtureBuild{
		argv:              os.args.clone()
		source_revision:   checked(['git', 'rev-parse', 'HEAD']).trim_space()
		inputs_sha256:     inputs
		artifacts_sha256:  artifacts
		java_version:      checked([java, '-version'])
		apk_sha256:        file_hash(apk)
		package_name:      package_name
		service_name:      service_name
		bind_action:       bind_action
		binder_descriptor: service_name
		ready_marker:      ready_marker
		closed_marker:     closed_marker
	}
	os.write_file(out + '/build.json', json2.encode(receipt, prettify: true))!
	println('HEADLESS-SERVICE-FIXTURE-APK ' + apk + ' ' + receipt.apk_sha256)
}
