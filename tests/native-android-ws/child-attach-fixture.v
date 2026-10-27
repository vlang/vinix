// SPDX-License-Identifier: GPL-2.0-or-later
// Same APK can be run against the old and corrected frameworks.
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

fn method(signature string, body string) string {
	return '.method ' + signature + '\n.locals 10\n' + body + '\n.end method\n'
}

fn checked(args []string) ! {
	r := os.exec(args)
	if r.exit_code != 0 { return error(r.output) }
}

fn group_class() string {
	return '.class public Lorg/vinix/bootstrap/AttachGroup;\n.super Landroid/widget/FrameLayout;\n' +
		method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, Landroid/widget/FrameLayout;-><init>(Landroid/content/Context;)V\nreturn-void') +
		method('public attach(Landroid/view/View;ILandroid/view/ViewGroup$LayoutParams;)V', 'invoke-super {p0, p1, p2, p3}, Landroid/widget/FrameLayout;->attachViewToParent(Landroid/view/View;ILandroid/view/ViewGroup$LayoutParams;)V\nreturn-void') +
		method('public detach(Landroid/view/View;)V', 'invoke-super {p0, p1}, Landroid/widget/FrameLayout;->detachViewFromParent(Landroid/view/View;)V\nreturn-void')
}

fn main_class() string {
	mut body := '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
new-instance v0, Lorg/vinix/bootstrap/AttachGroup;
invoke-direct {v0, p0}, Lorg/vinix/bootstrap/AttachGroup;-><init>(Landroid/content/Context;)V
new-instance v1, Landroid/view/View;
invoke-direct {v1, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
new-instance v2, Landroid/view/View;
invoke-direct {v2, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
new-instance v3, Landroid/view/View;
invoke-direct {v3, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
new-instance v4, Landroid/widget/FrameLayout$LayoutParams;
const/16 v5, 32
invoke-direct {v4, v5, v5}, Landroid/widget/FrameLayout$LayoutParams;-><init>(II)V
invoke-virtual {v0, v1, v4}, Landroid/view/ViewGroup;->addView(Landroid/view/View;Landroid/view/ViewGroup$LayoutParams;)V
invoke-virtual {v0, v2, v4}, Landroid/view/ViewGroup;->addView(Landroid/view/View;Landroid/view/ViewGroup$LayoutParams;)V
'
	// Assert before removal as well, so an attach that does nothing cannot pass.
	for phase in 0 .. 3 {
		if phase < 2 {
			body += 'const/4 v5, 1\ninvoke-virtual {v0, v3, v5, v4}, Lorg/vinix/bootstrap/AttachGroup;->attach(Landroid/view/View;ILandroid/view/ViewGroup$LayoutParams;)V\n'
		} else {
			body += 'invoke-virtual {v0, v3}, Landroid/view/ViewGroup;->removeView(Landroid/view/View;)V\n'
		}
		order := if phase < 2 { [1, 3, 2] } else { [1, 2] }
		body += children(order)
		body += 'invoke-virtual {v3}, Landroid/view/View;->getParent()Landroid/view/ViewParent;\nmove-result-object v6\n'
		body += if phase < 2 { 'if-ne v6, v0, :bad\n' } else { 'if-nez v6, :bad\n' }
		body += 'invoke-virtual {v3}, Landroid/view/View;->getLayoutParams()Landroid/view/ViewGroup$LayoutParams;\nmove-result-object v6\nif-ne v6, v4, :bad\n'
	}
	// A genuine temporary detach must restore only one entry at the new index.
	body += 'invoke-virtual {v0, v1}, Lorg/vinix/bootstrap/AttachGroup;->detach(Landroid/view/View;)V\n' + children([2]) + '
invoke-virtual {v1}, Landroid/view/View;->getParent()Landroid/view/ViewParent;
move-result-object v6
if-nez v6, :bad
const/4 v5, 1
invoke-virtual {v0, v1, v5, v4}, Lorg/vinix/bootstrap/AttachGroup;->attach(Landroid/view/View;ILandroid/view/ViewGroup$LayoutParams;)V
' + children([2, 1]) + '
invoke-virtual {v1}, Landroid/view/View;->getParent()Landroid/view/ViewParent;
move-result-object v6
if-ne v6, v0, :bad
invoke-virtual {v1}, Landroid/view/View;->getLayoutParams()Landroid/view/ViewGroup$LayoutParams;
move-result-object v6
if-ne v6, v4, :bad
invoke-virtual {v0, v1}, Landroid/view/ViewGroup;->removeView(Landroid/view/View;)V
' + children([2]) + '
invoke-virtual {v1}, Landroid/view/View;->getParent()Landroid/view/ViewParent;
move-result-object v6
if-nez v6, :bad
invoke-virtual {v0, v2}, Landroid/view/ViewGroup;->removeView(Landroid/view/View;)V
' + children([]) + '
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "CHILD-ATTACH-PASS fresh-once repeated-once remove-no-orphan detached-reattach-order params-parent"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Child attach regression passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-READY"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "child attach count, identity, order, parent or params"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
	return '.class public Lorg/vinix/bootstrap/Main;\n.super Landroid/app/Activity;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void') +
		method('public onCreate(Landroid/os/Bundle;)V', body)
}

fn children(order []int) string {
	mut body := 'invoke-virtual {v0}, Landroid/view/ViewGroup;->getChildCount()I\nmove-result v6\nconst/4 v7, ${order.len}\nif-ne v6, v7, :bad\n'
	for index, child in order {
		body += 'const/4 v5, ${index}\ninvoke-virtual {v0, v5}, Landroid/view/ViewGroup;->getChildAt(I)Landroid/view/View;\nmove-result-object v6\nif-ne v6, v${child}, :bad\n'
	}
	return body
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
	os.write_file(root + '/AttachGroup.smali', group_class())!
	os.write_file(root + '/Main.smali', main_class())!
	dex := out + '/classes.dex'
	checked([java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', '--jobs', '2', out + '/smali', '-o', dex])!
	assert os.file_size(dex) > 112
	manifest := out + '/AndroidManifest.xml'
	os.write_file(manifest, '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="23" android:targetSdkVersion="35"/><application android:label="Child attach regression"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
	checked([aapt, 'link', '--manifest', manifest, '-I', resources, '-o', out + '/unsigned.apk'])!
	checked(['zip', '-q', '-j', out + '/unsigned.apk', dex])!
	key := out + '/fixture.p12'
	checked([keytool, '-genkeypair', '-keystore', key, '-storepass', 'android', '-keypass', 'android', '-alias',
		'fixture', '-dname', 'CN=Vinix Child Attach Fixture', '-keyalg', 'RSA', '-validity', '3650', '-storetype', 'PKCS12'])!
	checked([java, '-jar', signer, 'sign', '--ks', key, '--ks-key-alias', 'fixture',
		'--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'])!
	checked([java, '-jar', signer, 'verify', '--verbose', out + '/probe.apk'])!
	for path, pin in inputs { assert sha256.sum(os.read_bytes(path)!).hex() == pin, path }
	os.write_file(out + '/build.json', json2.encode(BuildReceipt{
		argv: os.args
		inputs_sha256: inputs
		apk_sha256: sha256.sum(os.read_bytes(out + '/probe.apk')!).hex()
		pass_marker: 'CHILD-ATTACH-PASS'
		scope: 'Signed APK assembly only; ART execution pending'
	}, prettify: true) + '\n')!
	println('CHILD-ATTACH-APK ' + out + '/probe.apk')
}
