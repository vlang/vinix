// SPDX-License-Identifier: GPL-2.0-or-later
// Protected callback resolution; custom render traversal is outside this probe.
module main

import crypto.sha256
import json2
import net.http
import os
import time

const probe = 'Lorg/vinix/bootstrap/ChildOrderProbe;'
const ordinary = 'Lorg/vinix/bootstrap/DefaultOrderGroup;'
const overriding = 'Lorg/vinix/bootstrap/OverrideOrderGroup;'
const aosp_revision = '57bb140be9e48cf08acba131f7463e461777bb8e'

fn method(signature string, body string, locals int) string {
	return '.method ' + signature + '\n.locals ${locals}\n' + body + '\n.end method\n'
}

fn marker(value string) string {
	return 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\n' +
		'const-string v1, "BOOTSTRAP-CHILD-DRAWING-ORDER-${value}"\n' +
		'invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n'
}

fn equal(actual string, expected string, label string) string {
	return 'const-string v9, "${label}"\ninvoke-static {${actual}, ${expected}, v9}, ${probe}->equal(IILjava/lang/String;)V\n'
}

fn default_group() string {
	return '.class public ${ordinary}\n.super Landroid/widget/FrameLayout;\n' +
		method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, Landroid/widget/FrameLayout;-><init>(Landroid/content/Context;)V\nreturn-void', 0) +
		method('public inheritedOrder(II)I', 'invoke-virtual {p0, p1, p2}, ${ordinary}->getChildDrawingOrder(II)I\nmove-result v0\nreturn v0', 1) +
		method('public superOrder(II)I', 'invoke-super {p0, p1, p2}, Landroid/widget/FrameLayout;->getChildDrawingOrder(II)I\nmove-result v0\nreturn v0', 1)
}

fn override_group() string {
	return '.class public ${overriding}\n.super ${ordinary}\n' +
		'.field public calls:I\n.field public lastCount:I\n.field public lastPosition:I\n' +
		method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, ${ordinary}-><init>(Landroid/content/Context;)V\nreturn-void', 0) +
		method('protected getChildDrawingOrder(II)I', '
iget v0, p0, ${overriding}->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${overriding}->calls:I
iput p1, p0, ${overriding}->lastCount:I
iput p2, p0, ${overriding}->lastPosition:I
invoke-super {p0, p1, p2}, ${ordinary}->getChildDrawingOrder(II)I
move-result v0
add-int/lit8 v0, v0, 100
return v0', 1) +
		method('public directSuperOrder(II)I', 'invoke-super {p0, p1, p2}, ${ordinary}->getChildDrawingOrder(II)I\nmove-result v0\nreturn v0', 1)
}

fn probe_class() string {
	mut s := '.class public ${probe}\n.super Ljava/lang/Object;\n'
	s += method('private static equal(IILjava/lang/String;)V', '
if-eq p0, p1, :ok
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
return-void', 1)
	s += method('private static traceAbsent()V', '
invoke-static {}, Ljava/lang/System;->getenv()Ljava/util/Map;
move-result-object v0
invoke-interface {v0}, Ljava/util/Map;->keySet()Ljava/util/Set;
move-result-object v0
invoke-interface {v0}, Ljava/util/Set;->iterator()Ljava/util/Iterator;
move-result-object v2
:next
invoke-interface {v2}, Ljava/util/Iterator;->hasNext()Z
move-result v0
if-eqz v0, :good
invoke-interface {v2}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v0
check-cast v0, Ljava/lang/String;
const-string v1, "VINIX_ANDROID_TRACE_"
invoke-virtual {v0, v1}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z
move-result v0
if-eqz v0, :next
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "trace variables must be absent"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:good
' + marker('TRACE-ENV-ABSENT-PASS') + 'return-void', 3)
	mut b := 'invoke-static {}, ${probe}->traceAbsent()V\n' + marker('CALL') + '
new-instance v5, ${ordinary}
invoke-direct {v5, p0}, ${ordinary}-><init>(Landroid/content/Context;)V
const/4 v2, 4
const/4 v3, 2
invoke-virtual {v5, v2, v3}, ${ordinary}->inheritedOrder(II)I
move-result v4
' + equal('v4', 'v3', 'inherited default returns drawing position')
	// The callback neither validates the range nor derives count from children.
	for pair in [[0, 0], [1, 0], [4, 0], [4, 3], [0, 8], [2, -1], [-1, 7]] {
		b += 'const v2, ${pair[0]}\nconst v3, ${pair[1]}\n' +
			'invoke-virtual {v5, v2, v3}, ${ordinary}->inheritedOrder(II)I\nmove-result v4\n' +
			equal('v4', 'v3', 'inherited identity ${pair[0]} ${pair[1]}') +
			'invoke-virtual {v5, v2, v3}, ${ordinary}->superOrder(II)I\nmove-result v4\n' +
			equal('v4', 'v3', 'super identity ${pair[0]} ${pair[1]}')
	}
	b += marker('INHERITED-PASS') + '
new-instance v6, ${overriding}
invoke-direct {v6, p0}, ${overriding}-><init>(Landroid/content/Context;)V
const/4 v2, 7
const/4 v3, 3
invoke-virtual {v6, v2, v3}, ${ordinary}->inheritedOrder(II)I
move-result v4
const v7, 103
' + equal('v4', 'v7', 'virtual dispatch reaches override and super') + '
iget v4, v6, ${overriding}->calls:I
const/4 v7, 1
' + equal('v4', 'v7', 'override called once') + '
iget v4, v6, ${overriding}->lastCount:I
' + equal('v4', 'v2', 'override receives childCount') + '
iget v4, v6, ${overriding}->lastPosition:I
' + equal('v4', 'v3', 'override receives drawingPosition') + '
invoke-virtual {v6, v2, v3}, ${ordinary}->superOrder(II)I
move-result v4
' + equal('v4', 'v3', 'inherited super bypasses override') + '
invoke-virtual {v6, v2, v3}, ${overriding}->directSuperOrder(II)I
move-result v4
' + equal('v4', 'v3', 'direct super resolves inherited default') + '
iget v4, v6, ${overriding}->calls:I
' + equal('v4', 'v7', 'super calls do not redispatch override') +
		marker('OVERRIDE-SUPER-PASS') + marker('PASS') + 'return-void'
	s += method('public static run(Landroid/content/Context;)V', b, 10)
	return s
}

fn activity(combined bool) string {
	mut s := '.class public Lorg/vinix/bootstrap/Main;\n.super Landroid/app/Activity;\n'
	if combined {
		s += '.field public static childPassed:Z\n.field private static current:Landroid/app/Activity;\n'
	}
	s += method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void', 0)
	if combined {
		s += method('public onCreate(Landroid/os/Bundle;)V', '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
sput-object p0, Lorg/vinix/bootstrap/Main;->current:Landroid/app/Activity;
const/4 v0, 0
sput-boolean v0, Lorg/vinix/bootstrap/Main;->childPassed:Z
' + marker('ATTEMPT') + '
:child_try
invoke-static {p0}, ${probe}->run(Landroid/content/Context;)V
:child_try_end
.catch Ljava/lang/NoSuchMethodError; {:child_try .. :child_try_end} :child_missing
const/4 v0, 1
sput-boolean v0, Lorg/vinix/bootstrap/Main;->childPassed:Z
goto :child_done
:child_missing
move-exception v0
invoke-virtual {v0}, Ljava/lang/NoSuchMethodError;->getMessage()Ljava/lang/String;
move-result-object v1
const-string v2, "getChildDrawingOrder(II)I"
invoke-virtual {v1, v2}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z
move-result v1
if-nez v1, :expected_missing
throw v0
:expected_missing
' + marker('MISSING') + '
:child_done
invoke-static {p0}, Lorg/vinix/bootstrap/PermissionProbe;->start(Landroid/app/Activity;)V
return-void', 3)
		s += method('public onRequestPermissionsResult(I[Ljava/lang/String;[I)V', '
invoke-static {p1, p2, p3}, Lorg/vinix/bootstrap/PermissionProbe;->result(I[Ljava/lang/String;[I)V
return-void', 0)
		s += method('public static fixturePassed()V', '
sget-boolean v0, Lorg/vinix/bootstrap/Main;->childPassed:Z
if-nez v0, :child_ok
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "child drawing order callback was missing"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:child_ok
sget-object v2, Lorg/vinix/bootstrap/Main;->current:Landroid/app/Activity;
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, v2}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Child order and asynchronous permissions passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {v2, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-CHILD-PERMISSIONS-PASS"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
const-string v1, "BOOTSTRAP-READY"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void', 3)
	} else {
		s += method('public onCreate(Landroid/os/Bundle;)V', 'invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V\ninvoke-static {p0}, ${probe}->run(Landroid/content/Context;)V\nnew-instance v0, Landroid/widget/TextView;\ninvoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V\nconst-string v1, "Child drawing order callback fixture passed"\ninvoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V\ninvoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V\nsget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-READY"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void', 2)
	}
	return s
}

fn write_smali(out string, permission_root string) ! {
	assert !os.exists(out) && !os.is_link(out), 'fresh smali output required'
	root := out + '/org/vinix/bootstrap'
	os.mkdir_all(root)!
	os.write_file(root + '/Main.smali', activity(permission_root != ''))!
	os.write_file(root + '/ChildOrderProbe.smali', probe_class())!
	os.write_file(root + '/DefaultOrderGroup.smali', default_group())!
	os.write_file(root + '/OverrideOrderGroup.smali', override_group())!
	if permission_root != '' {
		for name in ['PermissionProbe', 'PermissionBaseActivity', 'PermissionCompletion'] {
			source := permission_root + '/org/vinix/bootstrap/' + name + '.smali'
			os.cp(source, root + '/' + name + '.smali')!
		}
	}
}

fn file_hash(path string) !string { return sha256.sum(os.read_bytes(path)!).hex() }

fn sourceproof(out string) ! {
	assert !os.exists(out) && !os.is_link(out), 'fresh sourceproof output required'
	os.mkdir_all(out)!
	args := ['git', 'ls-remote', 'https://android.googlesource.com/platform/frameworks/base',
		'refs/tags/android-10.0.0_r1', 'refs/tags/android-10.0.0_r1^{}']
	tags := os.exec(args)
	os.write_file(out + '/tag-resolution.log', tags.output)!
	assert tags.exit_code == 0 && tags.output.contains(aosp_revision + '\trefs/tags/android-10.0.0_r1^{}')
	url := 'https://raw.githubusercontent.com/aosp-mirror/platform_frameworks_base/' +
		aosp_revision + '/core/java/android/view/ViewGroup.java'
	started := time.utc().str()
	response := http.get(url)!
	assert response.status_code == 200
	os.write_file(out + '/AOSP-ViewGroup.java', response.body)!
	compact := response.body.fields().join(' ')
	for expected in [
		'protected int getChildDrawingOrder(int childCount, int drawingPosition) { return drawingPosition; }',
		'protected boolean isChildrenDrawingOrderEnabled() { return (mGroupFlags & FLAG_USE_CHILD_DRAWING_ORDER) == FLAG_USE_CHILD_DRAWING_ORDER; }',
		'protected void setChildrenDrawingOrderEnabled(boolean enabled) { setBooleanFlag(FLAG_USE_CHILD_DRAWING_ORDER, enabled); }',
	] {
		assert compact.contains(expected), expected
	}
	os.write_file(out + '/source-receipt.json', json2.encode({
		'url':              json2.Any(url)
		'revision':         json2.Any(aosp_revision)
		'tag_argv':         json2.Any(args)
		'tag_exit_code':    json2.Any(tags.exit_code)
		'started_utc':      json2.Any(started)
		'completed_utc':    json2.Any(time.utc().str())
		'http_status':      json2.Any(response.status_code)
		'source_sha256':    json2.Any(file_hash(out + '/AOSP-ViewGroup.java')!)
		'generator_sha256': json2.Any(file_hash(os.executable())!)
	}, prettify: true) + '\n')!
	println('CHILD-DRAWING-ORDER-SOURCE ' + file_hash(out + '/AOSP-ViewGroup.java')!)
}

fn checked(out string, name string, args []string, pins map[string]string) ! {
	for path, pin in pins {
		assert file_hash(path)! == pin, path
	}
	started := time.utc().str()
	r := os.exec(args)
	os.write_file(out + '/' + name + '.log', r.output)!
	os.write_file(out + '/' + name + '-receipt.json', json2.encode({
		'argv':             json2.Any(args)
		'started_utc':      json2.Any(started)
		'completed_utc':    json2.Any(time.utc().str())
		'exit_code':        json2.Any(r.exit_code)
		'input_sha256':     json2.decode[json2.Any](json2.encode(pins))!
		'generator_sha256': json2.Any(file_hash(os.executable())!)
	}, prettify: true) + '\n')!
	for path, pin in pins {
		assert file_hash(path)! == pin, path
	}
	assert r.exit_code == 0, name + ': ' + r.output
}

fn main() {
	$if prod {
		panic('assertions required')
	}
	if os.args.len == 3 {
		match os.args[1] {
			'--emit-smali' { write_smali(os.abs_path(os.args[2]), '')! }
			'--sourceproof' { sourceproof(os.abs_path(os.args[2]))! }
			else { panic('unknown mode') }
		}
		return
	}
	assert os.args.len == 2, '[--emit-smali|--sourceproof] OUTPUT'
	out := os.abs_path(os.args[1])
	assert !os.exists(out) && !os.is_link(out), 'fresh output required'
	permission_root := os.getenv('CHILD_DRAWING_ORDER_PERMISSION_SMALI_ROOT')
	write_smali(out + '/smali', permission_root)!
	os.mkdir_all(out + '/res/values')!
	os.write_file(out + '/res/values/values.xml', '<resources><string name="app_name">Child drawing order fixture</string></resources>')!
	os.write_file(out + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="26" android:targetSdkVersion="35"/><application android:label="Child drawing order fixture"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
	tools := os.getenv('CHILD_DRAWING_ORDER_FIXTURE_TOOLS_ROOT')
	aapt := if tools == '' {
		os.abs_path('build/android-native-ws/aapt2')
	} else {
		tools + '/aapt2'
	}
	signer := if tools == '' {
		os.abs_path('build/android-native-ws/android-15/lib/apksigner.jar')
	} else {
		tools + '/apksigner.jar'
	}
	framework := if tools == '' {
		'/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/framework-res.apk'
	} else {
		tools + '/framework-res.apk'
	}
	smali := if tools == '' {
		os.abs_path('build/android-framework/tools')
	} else {
		tools + '/smali'
	}
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	keytool := '/opt/homebrew/opt/openjdk@25/bin/keytool'
	zip := '/usr/bin/zip'
	mut pins := map[string]string{}
	for path in [aapt, signer, framework, java, keytool, zip] { pins[path] = file_hash(path)! }
	for name in os.ls(smali)! {
		if name.ends_with('.jar') { pins[smali + '/' + name] = file_hash(smali + '/' + name)! }
	}
	if permission_root != '' {
		for name in ['PermissionProbe', 'PermissionBaseActivity', 'PermissionCompletion'] {
			source := permission_root + '/org/vinix/bootstrap/' + name + '.smali'
			pins[source] = file_hash(source)!
			assert pins[source] == file_hash(out + '/smali/org/vinix/bootstrap/' + name + '.smali')!
		}
	}
	assert pins.len > 6
	os.write_file(out + '/tool-inputs-before.json', json2.encode(pins, prettify: true) + '\n')!
	checked(out, 'resources', [aapt, 'compile', '--dir', out + '/res', '-o', out + '/resources.zip'], pins)!
	checked(out, 'aapt2', [aapt, 'link', '-I', framework, '--manifest', out + '/AndroidManifest.xml',
		'-o', out + '/unsigned.apk', out + '/resources.zip'], pins)!
	checked(out, 'smali', [java, '-cp', smali + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali',
		'-o', out + '/classes.dex'], pins)!
	assert os.is_file(out + '/classes.dex'), 'smali produced no DEX'
	checked(out, 'zip', [zip, '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'], pins)!
	key := out + '/fixture.p12'
	checked(out, 'keytool', [keytool, '-genkeypair', '-keystore', key, '-storetype', 'PKCS12',
		'-alias', 'fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650', '-dname',
		'CN=Vinix child drawing order fixture', '-storepass', 'android', '-keypass', 'android'], pins)!
	checked(out, 'sign', [java, '-jar', signer, 'sign', '--ks', key, '--ks-key-alias', 'fixture',
		'--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk',
		out + '/unsigned.apk'], pins)!
	checked(out, 'verify', [java, '-jar', signer, 'verify', '--verbose', out + '/probe.apk'], pins)!
	os.write_file(out + '/tool-inputs-after.json', json2.encode(pins, prettify: true) + '\n')!
	println('CHILD-DRAWING-ORDER-APK ' + file_hash(out + '/probe.apk')!)
}
