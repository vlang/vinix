// SPDX-License-Identifier: GPL-2.0-or-later
// Guest linkage and write-contract regression; does not claim SettingsProvider persistence.
module main

import crypto.sha256
import json2
import os

struct BuildReceipt {
	argv []string
	inputs_sha256 map[string]string
	apk_sha256 string
	pass_marker string
	scope string
}

fn checked(args []string) {
	r := os.exec(args)
	if r.exit_code != 0 { panic(r.output) }
}

fn main() {
	assert os.args.len == 7, 'OUTPUT AAPT2 FRAMEWORK_RES SMALI_TOOLS JAVA APKSIGNER'
	out, aapt, resources := os.abs_path(os.args[1]), os.real_path(os.args[2]), os.real_path(os.args[3])
	tools, java, signer := os.real_path(os.args[4]), os.real_path(os.args[5]), os.real_path(os.args[6])
	keytool := os.dir(java) + '/keytool'
	mut inputs := map[string]string{}
	for path in [os.executable(), aapt, resources, java, keytool, signer] {
		inputs[path] = sha256.sum(os.read_bytes(path)!).hex()
	}
	for name in os.ls(tools)!.filter(it.ends_with('.jar')) {
		path := tools + '/' + name
		inputs[path] = sha256.sum(os.read_bytes(path)!).hex()
	}
	assert !os.exists(out) && !os.is_link(out), 'fresh output required'
	root := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(root)!
	os.write_file(root + '/SettingsResolver.smali', '.class public Lorg/vinix/bootstrap/SettingsResolver;
.super Landroid/content/ContentResolver;
.field public calls:I
.field public uri:Landroid/net/Uri;
.field public values:Landroid/content/ContentValues;
.field public nullResult:Z
.field public failure:Ljava/lang/RuntimeException;
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Landroid/content/ContentResolver;-><init>()V
return-void
.end method
.method public insert(Landroid/net/Uri;Landroid/content/ContentValues;)Landroid/net/Uri;
.locals 1
iget v0, p0, Lorg/vinix/bootstrap/SettingsResolver;->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/SettingsResolver;->calls:I
iput-object p1, p0, Lorg/vinix/bootstrap/SettingsResolver;->uri:Landroid/net/Uri;
iput-object p2, p0, Lorg/vinix/bootstrap/SettingsResolver;->values:Landroid/content/ContentValues;
iget-object v0, p0, Lorg/vinix/bootstrap/SettingsResolver;->failure:Ljava/lang/RuntimeException;
if-eqz v0, :result
throw v0
:result
iget-boolean v0, p0, Lorg/vinix/bootstrap/SettingsResolver;->nullResult:Z
if-eqz v0, :accepted
const/4 v0, 0
return-object v0
:accepted
return-object p1
.end method
')!
	mut body := '.class public Lorg/vinix/bootstrap/Main;
.super Landroid/app/Activity;
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Landroid/app/Activity;-><init>()V
return-void
.end method
.method private static checkWrite(Lorg/vinix/bootstrap/SettingsResolver;Ljava/lang/String;ILjava/lang/String;)V
.locals 4
invoke-static {p0, p1, p2}, Landroid/provider/Settings$Global;->putInt(Landroid/content/ContentResolver;Ljava/lang/String;I)Z
move-result v0
if-eqz v0, :bad
iget-object v0, p0, Lorg/vinix/bootstrap/SettingsResolver;->uri:Landroid/net/Uri;
invoke-virtual {v0}, Landroid/net/Uri;->toString()Ljava/lang/String;
move-result-object v0
const-string v1, "content://settings/global"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
iget-object v0, p0, Lorg/vinix/bootstrap/SettingsResolver;->values:Landroid/content/ContentValues;
invoke-virtual {v0}, Landroid/content/ContentValues;->size()I
move-result v1
const/4 v2, 2
if-ne v1, v2, :bad
const-string v1, "name"
invoke-virtual {v0, v1}, Landroid/content/ContentValues;->get(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v1
instance-of v2, v1, Ljava/lang/String;
if-eqz v2, :bad
invoke-virtual {p1, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad
const-string v1, "value"
invoke-virtual {v0, v1}, Landroid/content/ContentValues;->get(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v1
instance-of v2, v1, Ljava/lang/String;
if-eqz v2, :bad
invoke-virtual {p3, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Global.putInt lost URI, exact String values or provider result"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.end method
.method public onCreate(Landroid/os/Bundle;)V
.locals 7
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
# This fixture declares no settings provider: the real resolver must not claim success.
new-instance v0, Landroid/content/ContentResolver;
invoke-direct {v0}, Landroid/content/ContentResolver;-><init>()V
const-string v1, "vinix_missing_settings_provider"
const/4 v2, 0
invoke-static {v0, v1, v2}, Landroid/provider/Settings$Global;->putInt(Landroid/content/ContentResolver;Ljava/lang/String;I)Z
move-result v0
if-nez v0, :bad
new-instance v6, Lorg/vinix/bootstrap/SettingsResolver;
invoke-direct {v6}, Lorg/vinix/bootstrap/SettingsResolver;-><init>()V
const-string v1, "vinix_global_int"
'
	for pair in [['0x0', '0'], ['-0x1', '-1'], ['0x80000000', '-2147483648'],
		['0x7fffffff', '2147483647'], ['0x2a', '42'], ['0x7', '7']] {
		body += 'const v2, ' + pair[0] + '\nconst-string v3, "' + pair[1] + '"\n' +
			'invoke-static {v6, v1, v2, v3}, Lorg/vinix/bootstrap/Main;->checkWrite(Lorg/vinix/bootstrap/SettingsResolver;Ljava/lang/String;ILjava/lang/String;)V\n'
	}
	body += 'const/4 v0, 1
iput-boolean v0, v6, Lorg/vinix/bootstrap/SettingsResolver;->nullResult:Z
invoke-static {v6, v1, v2}, Landroid/provider/Settings$Global;->putInt(Landroid/content/ContentResolver;Ljava/lang/String;I)Z
move-result v0
if-nez v0, :bad
const/4 v0, 0
iput-boolean v0, v6, Lorg/vinix/bootstrap/SettingsResolver;->nullResult:Z
new-instance v0, Landroid/database/SQLException;
invoke-direct {v0}, Landroid/database/SQLException;-><init>()V
iput-object v0, v6, Lorg/vinix/bootstrap/SettingsResolver;->failure:Ljava/lang/RuntimeException;
invoke-static {v6, v1, v2}, Landroid/provider/Settings$Global;->putInt(Landroid/content/ContentResolver;Ljava/lang/String;I)Z
move-result v0
if-nez v0, :bad
new-instance v5, Ljava/lang/SecurityException;
const-string v0, "settings denied"
invoke-direct {v5, v0}, Ljava/lang/SecurityException;-><init>(Ljava/lang/String;)V
iput-object v5, v6, Lorg/vinix/bootstrap/SettingsResolver;->failure:Ljava/lang/RuntimeException;
:security_start
invoke-static {v6, v1, v2}, Landroid/provider/Settings$Global;->putInt(Landroid/content/ContentResolver;Ljava/lang/String;I)Z
:security_end
goto :bad
:security_caught
move-exception v0
if-ne v0, v5, :bad
iget v0, v6, Lorg/vinix/bootstrap/SettingsResolver;->calls:I
const/16 v1, 9
if-ne v0, v1, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "SETTINGS-GLOBAL-PASS linkage virtual-insert URI exact-string-values zero negative min max repeated-key null-result SQLException SecurityException-identity absent-provider"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Settings global integer write contract passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Global.putInt failure contract or dispatch count"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.catch Ljava/lang/SecurityException; {:security_start .. :security_end} :security_caught
.end method
'
	os.write_file(root + '/Main.smali', body)!
	dex := out + '/classes.dex'
	checked([java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', '--jobs', '2', out + '/smali', '-o', dex])
	assert os.file_size(dex) > 112
	manifest := out + '/AndroidManifest.xml'
	os.write_file(manifest, '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="23" android:targetSdkVersion="35"/><application android:label="Settings global regression"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
	checked([aapt, 'link', '--manifest', manifest, '-I', resources, '-o', out + '/unsigned.apk'])
	checked(['zip', '-q', '-j', out + '/unsigned.apk', dex])
	key := out + '/fixture.p12'
	checked([keytool, '-genkeypair', '-keystore', key, '-storepass', 'android', '-keypass', 'android', '-alias',
		'fixture', '-dname', 'CN=Vinix Settings Global Fixture', '-keyalg', 'RSA', '-validity', '3650', '-storetype', 'PKCS12'])
	checked([java, '-jar', signer, 'sign', '--ks', key, '--ks-key-alias',
		'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out',
		out + '/probe.apk', out + '/unsigned.apk'])
	checked([java, '-jar', signer, 'verify', '--verbose', out + '/probe.apk'])
	for path, pin in inputs { assert sha256.sum(os.read_bytes(path)!).hex() == pin, path }
	os.write_file(out + '/build.json', json2.encode(BuildReceipt{
		argv: os.args
		inputs_sha256: inputs
		apk_sha256: sha256.sum(os.read_bytes(out + '/probe.apk')!).hex()
		pass_marker: 'SETTINGS-GLOBAL-PASS'
		scope: 'Signed APK assembly only; ART execution and SettingsProvider persistence not established'
	}, prettify: true) + '\n')!
	println('SETTINGS-GLOBAL-APK ' + out + '/probe.apk')
}
