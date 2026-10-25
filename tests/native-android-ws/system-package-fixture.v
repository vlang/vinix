// SPDX-License-Identifier: GPL-2.0-or-later
// Resource-only system application and AlertDialog construction in guest ART.
// Both old and fixed frameworks complete this probe; the paired runner must
// separately check the old caught certificate error and its absence after the fix.
module main

import crypto.sha256
import json2
import os
import time

const probe = 'Lorg/vinix/bootstrap/SystemPackageProbe;'
const java_default = '/opt/homebrew/Cellar/openjdk@25/25.0.4.1/libexec/openjdk.jdk/Contents/Home/bin/java'

fn method(signature string, body string, locals int) string {
	return '.method ' + signature + '\n.locals ${locals}\n' + body + '\n.end method\n'
}

fn marker(value string) string {
	return 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\n' +
		'const-string v1, "SYSTEM-PACKAGE-FIXTURE-${value}"\n' +
		'invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n'
}

fn require_nonnull(register string, label string) string {
	return 'const-string v7, "${label}"\ninvoke-static {${register}, v7}, ${probe}->nonnull(Ljava/lang/Object;Ljava/lang/String;)V\n'
}

fn require_same(actual string, expected string, label string) string {
	return 'const-string v7, "${label}"\ninvoke-static {${actual}, ${expected}, v7}, ${probe}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V\n'
}

fn require_null(register string, label string) string {
	return 'const-string v7, "${label}"\ninvoke-static {${register}, v7}, ${probe}->unset(Ljava/lang/Object;Ljava/lang/String;)V\n'
}

fn probe_class() string {
	mut source := '.class public ${probe}\n.super Ljava/lang/Object;\n'
	source += method('private static nonnull(Ljava/lang/Object;Ljava/lang/String;)V', '
if-nez p0, :ok
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
return-void', 1)
	source += method('private static same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V', '
if-eq p0, p1, :ok
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
return-void', 1)
	source += method('private static unset(Ljava/lang/Object;Ljava/lang/String;)V', '
if-eqz p0, :ok
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
return-void', 1)
	source += method('private static traceAbsent()V', '
invoke-static {}, Ljava/lang/System;->getenv()Ljava/util/Map;
move-result-object v0
invoke-interface {v0}, Ljava/util/Map;->keySet()Ljava/util/Set;
move-result-object v0
invoke-interface {v0}, Ljava/util/Set;->iterator()Ljava/util/Iterator;
move-result-object v2
:next
invoke-interface {v2}, Ljava/util/Iterator;->hasNext()Z
move-result v0
if-eqz v0, :location
invoke-interface {v2}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v0
check-cast v0, Ljava/lang/String;
const-string v1, "VINIX_ANDROID_TRACE_"
invoke-virtual {v0, v1}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z
move-result v0
if-eqz v0, :next
goto :bad
:location
const-string v0, "ATL_UGLY_ENABLE_LOCATION"
invoke-static {v0}, Ljava/lang/System;->getenv(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
if-nez v0, :bad
' + marker('TRACE-ENV-ABSENT-PASS') + '
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "trace variables and location override must be absent"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0', 3)
	source += method('public static run(Landroid/content/Context;)V', 'invoke-static {}, ${probe}->traceAbsent()V\n' + marker('CALL') + '
invoke-static {}, Landroid/atl/ATLLoadedApp;->getSystemApplication()Landroid/atl/ATLLoadedApp;
move-result-object v2
' + require_nonnull('v2', 'system application must exist') + '
invoke-static {}, Landroid/atl/ATLLoadedApp;->getSystemApplication()Landroid/atl/ATLLoadedApp;
move-result-object v3
' + require_same('v2', 'v3', 'system application must be cached') + marker('CACHE-PASS') + '
iget-object v4, v2, Landroid/atl/ATLLoadedApp;->pkg:Landroid/content/pm/PackageParser$Package;
' + require_nonnull('v4', 'system package must exist') + '
iget-object v5, v2, Landroid/atl/ATLLoadedApp;->default_resources:Landroid/content/res/Resources;
' + require_nonnull('v5', 'system resources must exist') + '
invoke-static {}, Landroid/content/res/Resources;->getSystem()Landroid/content/res/Resources;
move-result-object v6
' + require_same('v5', 'v6', 'system application must use Resources.getSystem') + marker('RESOURCES-PASS') + '
iget-object v5, v4, Landroid/content/pm/PackageParser$Package;->mSignatures:[Landroid/content/pm/Signature;
' + require_null('v5', 'resource-only system package must not acquire APK signatures') + '
iget-object v5, v4, Landroid/content/pm/PackageParser$Package;->vinixSigningInfo:Landroid/content/pm/SigningInfo;
' + require_null('v5', 'resource-only system package must not acquire verified signing info') + marker('UNSIGNED-METADATA-PASS') + '
new-instance v5, Landroid/app/AlertDialog$Builder;
invoke-direct {v5, p0}, Landroid/app/AlertDialog$Builder;-><init>(Landroid/content/Context;)V
invoke-virtual {v5}, Landroid/app/AlertDialog$Builder;->create()Landroid/app/AlertDialog;
move-result-object v6
' + require_nonnull('v6', 'AlertDialog.Builder.create must return a dialog') + '
invoke-virtual {v6}, Landroid/app/AlertDialog;->getContext()Landroid/content/Context;
move-result-object v5
' + require_nonnull('v5', 'created dialog must retain a context') + marker('DIALOG-CREATE-PASS') + marker('PASS') + 'return-void', 8)
	return source
}

fn activity() string {
	return '.class public Lorg/vinix/bootstrap/Main;\n.super Landroid/app/Activity;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void', 0) +
		method('public onCreate(Landroid/os/Bundle;)V', '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
invoke-static {p0}, ${probe}->run(Landroid/content/Context;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "System resource package and dialog creation passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-READY"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void', 2)
}

fn write_smali(out string) ! {
	assert !os.exists(out) && !os.is_link(out), 'fresh smali output required'
	root := out + '/org/vinix/bootstrap'
	os.mkdir_all(root)!
	os.write_file(root + '/Main.smali', activity())!
	os.write_file(root + '/SystemPackageProbe.smali', probe_class())!
}

fn hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn checked(out string, label string, argv []string, pins map[string]string) ! {
	for path, pin in pins { assert hash(path)! == pin, path }
	started := time.utc().str()
	r := os.exec(argv)
	os.write_file(out + '/' + label + '.log', r.output)!
	os.write_file(out + '/' + label + '-receipt.json', json2.encode({
		'argv':             json2.Any(argv)
		'started_utc':      json2.Any(started)
		'completed_utc':    json2.Any(time.utc().str())
		'exit_code':        json2.Any(r.exit_code)
		'input_sha256':     json2.decode[json2.Any](json2.encode(pins))!
		'generator_sha256': json2.Any(hash(os.executable())!)
	}, prettify: true) + '\n')!
	for path, pin in pins { assert hash(path)! == pin, path }
	assert r.exit_code == 0, label + ': ' + r.output
}

fn main() {
	$if prod { panic('assertions required') }
	if os.args.len == 3 && os.args[1] == '--emit-smali' {
		write_smali(os.abs_path(os.args[2]))!
		return
	}
	assert os.args.len == 2, '[--emit-smali] FRESH_OUTPUT'
	out := os.abs_path(os.args[1])
	assert !os.exists(out) && !os.is_link(out), 'fresh output required'
	write_smali(out + '/smali')!
	os.mkdir_all(out + '/res/values')!
	os.write_file(out + '/res/values/values.xml', '<resources><string name="app_name">System package fixture</string></resources>')!
	os.write_file(out + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="26" android:targetSdkVersion="35"/><application android:label="System package fixture"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
	tools := os.getenv('SYSTEM_PACKAGE_FIXTURE_TOOLS_ROOT')
	assert tools != '', 'SYSTEM_PACKAGE_FIXTURE_TOOLS_ROOT must name retained fixture tools'
	aapt := tools + '/aapt2'
	signer := tools + '/apksigner.jar'
	framework := tools + '/framework-res.apk'
	smali := tools + '/smali'
	java_setting := os.getenv('SYSTEM_PACKAGE_FIXTURE_JAVA')
	java := if java_setting == '' { java_default } else { java_setting }
	keytool := os.dir(java) + '/keytool'
	zip := '/usr/bin/zip'
	mut pins := map[string]string{}
	for path in [aapt, signer, framework, java, keytool, zip] { pins[path] = hash(path)! }
	for name in os.ls(smali)! {
		if name.ends_with('.jar') { pins[smali + '/' + name] = hash(smali + '/' + name)! }
	}
	assert pins.len > 6, 'smali dependency JARs required'
	os.write_file(out + '/tool-inputs-before.json', json2.encode(pins, prettify: true) + '\n')!
	checked(out, 'resources', [aapt, 'compile', '--dir', out + '/res', '-o', out + '/resources.zip'], pins)!
	checked(out, 'aapt2', [aapt, 'link', '-I', framework, '--manifest', out + '/AndroidManifest.xml',
		'-o', out + '/unsigned.apk', out + '/resources.zip'], pins)!
	checked(out, 'smali', [java, '-cp', smali + '/*', 'org.jf.smali.Main', 'assemble', '--jobs', '2',
		out + '/smali', '-o', out + '/classes.dex'], pins)!
	assert os.is_file(out + '/classes.dex'), 'smali produced no DEX'
	checked(out, 'zip', [zip, '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'], pins)!
	key := out + '/fixture.p12'
	checked(out, 'keytool', [keytool, '-genkeypair', '-keystore', key, '-storetype', 'PKCS12',
		'-alias', 'fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650', '-dname',
		'CN=Vinix system package fixture', '-storepass', 'android', '-keypass', 'android'], pins)!
	checked(out, 'sign', [java, '-jar', signer, 'sign', '--ks', key, '--ks-key-alias', 'fixture',
		'--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk',
		out + '/unsigned.apk'], pins)!
	checked(out, 'verify', [java, '-jar', signer, 'verify', '--verbose', out + '/probe.apk'], pins)!
	os.write_file(out + '/tool-inputs-after.json', json2.encode(pins, prettify: true) + '\n')!
	println('SYSTEM-PACKAGE-FIXTURE-APK ' + hash(out + '/probe.apk')!)
}
