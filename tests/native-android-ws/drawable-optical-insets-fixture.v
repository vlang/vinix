// SPDX-License-Identifier: GPL-2.0-or-later
// Same-APK regression for the public, virtual Drawable optical-insets API.
module main

import crypto.sha256
import json2
import os
import time

const probe = 'Lorg/vinix/bootstrap/OpticalInsetsProbe;'
const drawable = 'Landroid/graphics/drawable/Drawable;'
const insets = 'Landroid/graphics/Insets;'
const padded = 'Lorg/vinix/bootstrap/PaddedDrawable;'
const override_drawable = 'Lorg/vinix/bootstrap/OverrideDrawable;'

fn method(signature string, body string, locals int) string {
	return '.method ' + signature + '\n.locals ${locals}\n' + body + '\n.end method\n'
}

fn equal(actual string, expected string, label string) string {
	return 'const-string v9, "${label}"\n' +
		'invoke-static {${actual}, ${expected}, v9}, ${probe}->equal(IILjava/lang/String;)V\n'
}

fn same(actual string, expected string, label string) string {
	return 'const-string v9, "${label}"\n' +
		'invoke-static {${actual}, ${expected}, v9}, ${probe}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V\n'
}

fn marker(name string) string {
	return line_marker('BOOTSTRAP-DRAWABLE-OPTICAL-INSETS-${name}PASS')
}

fn line_marker(value string) string {
	return 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\n' +
		'const-string v1, "${value}"\n' +
		'invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n'
}

fn helper_methods() string {
	mut s := method('private static equal(IILjava/lang/String;)V', '
if-eq p0, p1, :ok
new-instance v0, Ljava/lang/StringBuilder;
const-string v1, "Drawable optical insets: "
invoke-direct {v0, v1}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V
invoke-virtual {v0, p2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const-string v1, " actual="
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v0, p0}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
const-string v1, " expected="
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v0, p1}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
move-result-object v1
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
return-void', 2)
	s += method('private static same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V', '
if-eq p0, p1, :ok
const/4 v0, 0
const/4 v1, 1
invoke-static {v0, v1, p2}, ${probe}->equal(IILjava/lang/String;)V
:ok
return-void', 2)
	mut values := ''
	for index, edge in ['left', 'top', 'right', 'bottom'] {
		values += 'iget v0, p0, ${insets}->${edge}:I\nconst-string v1, "${edge}"\n' +
			'invoke-static {v0, p${index + 1}, v1}, ${probe}->equal(IILjava/lang/String;)V\n'
	}
	s += method('private static values(${insets}IIII)V', values + 'return-void', 2)
	// Reflection verifies visibility and extensibility independently of DEX flags
	// in the generated provider; the application also calls and overrides it.
	s += method('private static modifiers()V', '
const-class v0, ${drawable}
const-string v1, "getOpticalInsets"
const/4 v2, 0
new-array v2, v2, [Ljava/lang/Class;
invoke-virtual {v0, v1, v2}, Ljava/lang/Class;->getMethod(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;
move-result-object v0
invoke-virtual {v0}, Ljava/lang/reflect/Method;->getModifiers()I
move-result v0
invoke-static {v0}, Ljava/lang/reflect/Modifier;->isPublic(I)Z
move-result v1
const/4 v2, 1
const-string v3, "public API"
invoke-static {v1, v2, v3}, ${probe}->equal(IILjava/lang/String;)V
invoke-static {v0}, Ljava/lang/reflect/Modifier;->isFinal(I)Z
move-result v1
const/4 v2, 0
const-string v3, "overridable API"
invoke-static {v1, v2, v3}, ${probe}->equal(IILjava/lang/String;)V
invoke-static {v0}, Ljava/lang/reflect/Modifier;->isStatic(I)Z
move-result v1
const-string v3, "virtual API"
invoke-static {v1, v2, v3}, ${probe}->equal(IILjava/lang/String;)V
return-void', 4)
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
const/4 v0, 0
const/4 v1, 1
const-string v3, "trace variables must be absent"
invoke-static {v0, v1, v3}, ${probe}->equal(IILjava/lang/String;)V
:good
' + marker('TRACE-ENV-ABSENT-') + 'return-void', 4)
	return s
}

fn default_probe() string {
	mut s := '
new-instance v6, ${padded}
invoke-direct {v6}, ${padded}-><init>()V
' + line_marker('BOOTSTRAP-DRAWABLE-OPTICAL-INSETS-CALL') + '
# This exact public descriptor is the missing Maps/SwitchCompat entry point.
# Keep this first so the unchanged APK demonstrates the old provider failure.
invoke-virtual {v6}, ${drawable}->getOpticalInsets()${insets}
move-result-object v7
sget-object v8, ${insets}->NONE:${insets}
'
	s += same('v7', 'v8', 'default uses shared NONE')
	s += 'const/4 v0, 0\ninvoke-static {v7, v0, v0, v0, v0}, ${probe}->values(${insets}IIII)V\n'
	s += '
new-instance v0, ${padded}
invoke-direct {v0}, ${padded}-><init>()V
invoke-virtual {v0}, ${drawable}->getOpticalInsets()${insets}
move-result-object v1
' + same('v1', 'v8', 'NONE shared across instances')
	s += '
new-instance v0, Landroid/graphics/drawable/ColorDrawable;
const v1, 0xff446688
invoke-direct {v0, v1}, Landroid/graphics/drawable/ColorDrawable;-><init>(I)V
invoke-virtual {v0}, ${drawable}->getOpticalInsets()${insets}
move-result-object v1
' + same('v1', 'v8', 'ColorDrawable inherits zero')
	s += '
new-instance v5, Landroid/graphics/Rect;
invoke-direct {v5}, Landroid/graphics/Rect;-><init>()V
invoke-virtual {v6, v5}, ${drawable}->getPadding(Landroid/graphics/Rect;)Z
move-result v1
const/4 v2, 1
' + equal('v1', 'v2', 'nonzero padding reported')
	for index, edge in ['left', 'top', 'right', 'bottom'] {
		s += 'iget v1, v5, Landroid/graphics/Rect;->${edge}:I\nconst/16 v2, ${[13, 17, 19, 23][index]}\n' +
			equal('v1', 'v2', 'padding ${edge} remains independent')
	}
	s += '
invoke-virtual {v6}, ${drawable}->getOpticalInsets()${insets}
move-result-object v1
' + same('v1', 'v8', 'padding is not optical inset')
	s += '
const/4 v0, 2
const/4 v1, 3
const/16 v2, 80
const/16 v3, 90
invoke-virtual {v6, v0, v1, v2, v3}, ${drawable}->setBounds(IIII)V
const/4 v0, 2
new-array v0, v0, [I
const/4 v1, 0
const v2, 0x10100a7
aput v2, v0, v1
const/4 v1, 1
const v2, 0x101009e
aput v2, v0, v1
invoke-virtual {v6, v0}, ${drawable}->setState([I)Z
const/4 v5, 0
:repeat
invoke-virtual {v6}, ${drawable}->getOpticalInsets()${insets}
move-result-object v1
' + same('v1', 'v8', 'stable NONE after bounds and state')
	s += '
add-int/lit8 v5, v5, 1
const/16 v0, 16
if-lt v5, v0, :repeat
invoke-static {}, ${probe}->modifiers()V
' + marker('DEFAULT-') + 'return-void'
	return method('private static defaults()V', s, 10)
}

fn dispatch_probe() string {
	mut s := '
new-instance v6, ${override_drawable}
invoke-direct {v6}, ${override_drawable}-><init>()V
# Invoke through the base API exactly as compatibility widget code does.
invoke-virtual {v6}, ${drawable}->getOpticalInsets()${insets}
move-result-object v7
const/4 v0, 3
const/4 v1, 5
const/4 v2, 7
const/16 v3, 11
invoke-static {v7, v0, v1, v2, v3}, ${probe}->values(${insets}IIII)V
invoke-virtual {v6}, ${override_drawable}->superOpticalInsets()${insets}
move-result-object v7
sget-object v8, ${insets}->NONE:${insets}
'
	s += same('v7', 'v8', 'invoke-super default remains NONE')
	s += 'const/4 v0, 0\ninvoke-static {v7, v0, v0, v0, v0}, ${probe}->values(${insets}IIII)V\n'
	// A caller can use all four returned edges for SwitchCompat-style layout.
	s += '
invoke-virtual {v6}, ${drawable}->getOpticalInsets()${insets}
move-result-object v7
iget v0, v7, ${insets}->left:I
iget v1, v7, ${insets}->right:I
add-int/2addr v0, v1
const/16 v1, 100
sub-int/2addr v1, v0
const/16 v2, 90
' + equal('v1', 'v2', 'horizontal content width')
	s += 'iget v0, v7, ${insets}->top:I\niget v1, v7, ${insets}->bottom:I\nadd-int/2addr v0, v1\nconst/16 v1, 50\nsub-int/2addr v1, v0\nconst/16 v2, 34\n' +
		equal('v1', 'v2', 'vertical content height')
	s += marker('DISPATCH-') + 'return-void'
	return method('private static dispatch()V', s, 10)
}

fn probe_class() string {
	return '.class public ${probe}\n.super Ljava/lang/Object;\n' + helper_methods() +
		default_probe() + dispatch_probe() + method('public static run()V',
		'invoke-static {}, ${probe}->traceAbsent()V\ninvoke-static {}, ${probe}->defaults()V\ninvoke-static {}, ${probe}->dispatch()V\n' +
		marker('') + 'return-void', 2)
}

fn padded_class() string {
	mut s := '.class public ${padded}\n.super ${drawable}\n'
	s += method('public constructor <init>()V', 'invoke-direct {p0}, ${drawable}-><init>()V\nreturn-void', 0)
	s += method('public getPadding(Landroid/graphics/Rect;)Z', 'const/16 v0, 13\nconst/16 v1, 17\nconst/16 v2, 19\nconst/16 v3, 23\ninvoke-virtual {p1, v0, v1, v2, v3}, Landroid/graphics/Rect;->set(IIII)V\nconst/4 v0, 1\nreturn v0', 4)
	// Satisfy Drawable's real Android abstract contract as well as this runtime.
	s += method('public draw(Landroid/graphics/Canvas;)V', 'return-void', 0)
	s += method('public setAlpha(I)V', 'return-void', 0)
	s += method('public setColorFilter(Landroid/graphics/ColorFilter;)V', 'return-void', 0)
	s += method('public getOpacity()I', 'const/4 v0, -0x3\nreturn v0', 1)
	return s
}

fn override_class() string {
	return '.class public ${override_drawable}\n.super ${padded}\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, ${padded}-><init>()V\nreturn-void', 0) +
		method('public getOpticalInsets()${insets}', 'const/4 v0, 3\nconst/4 v1, 5\nconst/4 v2, 7\nconst/16 v3, 11\ninvoke-static {v0, v1, v2, v3}, ${insets}->of(IIII)${insets}\nmove-result-object v0\nreturn-object v0', 4) +
		method('public superOpticalInsets()${insets}', 'invoke-super {p0}, ${padded}->getOpticalInsets()${insets}\nmove-result-object v0\nreturn-object v0', 1)
}

fn activity() string {
	return '.class public Lorg/vinix/bootstrap/Main;\n.super Landroid/app/Activity;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void', 0) +
		method('public onCreate(Landroid/os/Bundle;)V', 'invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V\nnew-instance v0, Landroid/widget/TextView;\ninvoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V\nconst-string v1, "Drawable optical insets fixture"\ninvoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V\ninvoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V\ninvoke-static {}, ${probe}->run()V\nsget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-READY"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void', 2)
}

fn file_hash(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn checked(out string, name string, args []string, pins map[string]string) ! {
	for path, pin in pins { assert file_hash(path)! == pin, path }
	started := time.utc().str()
	r := os.exec(args)
	os.write_file(out + '/' + name + '.log', r.output)!
	os.write_file(out + '/' + name + '-receipt.json', json2.encode({'argv': json2.Any(args),
		'started_utc': json2.Any(started), 'completed_utc': json2.Any(time.utc().str()),
		'exit_code': json2.Any(r.exit_code), 'input_sha256': json2.decode[json2.Any](json2.encode(pins))!,
		'generator_sha256': json2.Any(file_hash(os.executable())!)}, prettify: true) + '\n')!
	for path, pin in pins { assert file_hash(path)! == pin, path }
	assert r.exit_code == 0, name + ': ' + r.output
}

fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 2, 'OUTPUT'
	out := os.abs_path(os.args[1])
	assert !os.exists(out) && !os.is_link(out), 'fresh output required'
	root := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(root)!
	os.mkdir_all(out + '/res/values')!
	os.write_file(out + '/res/values/values.xml', '<resources><string name="app_name">Drawable optical insets fixture</string></resources>')!
	os.write_file(out + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="26" android:targetSdkVersion="35"/><application android:label="Drawable optical insets fixture"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
	os.write_file(root + '/Main.smali', activity())!
	os.write_file(root + '/OpticalInsetsProbe.smali', probe_class())!
	os.write_file(root + '/PaddedDrawable.smali', padded_class())!
	os.write_file(root + '/OverrideDrawable.smali', override_class())!
	tools := os.getenv('DRAWABLE_OPTICAL_INSETS_FIXTURE_TOOLS_ROOT')
	aapt := if tools == '' { os.abs_path('build/android-native-ws/aapt2') } else { tools + '/aapt2' }
	signer := if tools == '' { os.abs_path('build/android-native-ws/android-15/lib/apksigner.jar') } else { tools + '/apksigner.jar' }
	framework := if tools == '' { '/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/framework-res.apk' } else { tools + '/framework-res.apk' }
	smali := if tools == '' { os.abs_path('build/android-framework/tools') } else { tools + '/smali' }
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	keytool := '/opt/homebrew/opt/openjdk@25/bin/keytool'
	zip := '/usr/bin/zip'
	mut pins := map[string]string{}
	for path in [aapt, signer, framework, java, keytool, zip] { pins[path] = file_hash(path)! }
	for name in os.ls(smali)! { if name.ends_with('.jar') { pins[smali + '/' + name] = file_hash(smali + '/' + name)! } }
	assert pins.len > 6
	os.write_file(out + '/tool-inputs-before.json', json2.encode(pins, prettify: true) + '\n')!
	checked(out, 'resources', [aapt, 'compile', '--dir', out + '/res', '-o', out + '/resources.zip'], pins)!
	checked(out, 'aapt2', [aapt, 'link', '-I', framework, '--manifest', out + '/AndroidManifest.xml', '-o', out + '/unsigned.apk', out + '/resources.zip'], pins)!
	checked(out, 'smali', [java, '-cp', smali + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali', '-o', out + '/classes.dex'], pins)!
	assert os.is_file(out + '/classes.dex'), 'smali produced no DEX'
	checked(out, 'zip', [zip, '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'], pins)!
	key := out + '/fixture.p12'
	checked(out, 'keytool', [keytool, '-genkeypair', '-keystore', key, '-storetype', 'PKCS12', '-alias', 'fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650', '-dname', 'CN=Vinix Drawable optical insets fixture', '-storepass', 'android', '-keypass', 'android'], pins)!
	checked(out, 'sign', [java, '-jar', signer, 'sign', '--ks', key, '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'], pins)!
	checked(out, 'verify', [java, '-jar', signer, 'verify', '--verbose', out + '/probe.apk'], pins)!
	os.write_file(out + '/tool-inputs-after.json', json2.encode(pins, prettify: true) + '\n')!
	println('DRAWABLE-OPTICAL-INSETS-APK ' + file_hash(out + '/probe.apk')!)
}
