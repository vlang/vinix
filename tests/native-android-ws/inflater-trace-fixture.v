// SPDX-License-Identifier: GPL-2.0-or-later
// Same APK for trace on/off; the runner independently requires skipped/present.
module main

import crypto.sha256
import os

const probe = 'Lorg/vinix/bootstrap/InflaterProbe;'
const view = 'Lorg/vinix/bootstrap/ProbeView;'
const factory = 'Lorg/vinix/bootstrap/ProbeFactory;'
const inflater = 'Landroid/view/LayoutInflater;'
const factory2 = 'Landroid/view/LayoutInflater$Factory2;'

fn checked(args []string) {
	r := os.exec(args)
	assert r.exit_code == 0, r.output
}

fn method(signature string, body string, locals int) string {
	return '.method ' + signature + '\n.locals ${locals}\n' + body + '\n.end method\n'
}

fn marker(name string) string {
	return 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-INFLATER-TRACE-${name}-PASS"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n'
}

fn probe_view() string {
	mut text := '.class public ${view}\n.super Landroid/view/View;\n'
	for field in ['strings', 'ids', 'names'] {
		text += '.field public ${field}:I\n'
	}
	text += method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, Landroid/view/View;-><init>(Landroid/content/Context;)V\nreturn-void', 0)
	mut reset := 'const/4 v0, 0\n'
	for field in ['strings', 'ids', 'names'] {
		reset += 'iput v0, p0, ${view}->${field}:I\n'
	}
	text += method('public reset()V', reset + 'return-void', 1)
	for spec in [['toString()Ljava/lang/String;', 'strings', 'const-string v0, "probe-view"\nreturn-object v0'], ['getId()I', 'ids', 'const/16 v0, 123\nreturn v0'], ['getIdName()Ljava/lang/String;', 'names', 'const-string v0, "probe/result"\nreturn-object v0']] {
		text += method('public ' + spec[0], 'iget v0, p0, ${view}->${spec[1]}:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${view}->${spec[1]}:I\n' + spec[2], 1)
	}
	return text
}

fn probe_factory() string {
	mut text := '.class public ${factory}\n.super Ljava/lang/Object;\n.implements ${factory2}\n.field public calls:I\n.field public order:I\n'
	text += method('public constructor <init>(I)V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput p1, p0, ${factory}->order:I\nreturn-void', 0)
	text += method('public onCreateView(Landroid/view/View;Ljava/lang/String;Landroid/content/Context;Landroid/util/AttributeSet;)Landroid/view/View;', '
sget-object v0, ${probe}->parent:${view}
if-ne p1, v0, :bad
sget-object v0, ${probe}->context:Landroid/content/Context;
if-ne p3, v0, :bad
if-nez p4, :bad
const-string v0, "Probe"
invoke-virtual {v0, p2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-eqz v0, :bad
sget v0, ${probe}->sequence:I
iget v1, p0, ${factory}->order:I
if-ne v0, v1, :bad
add-int/lit8 v0, v0, 1
sput v0, ${probe}->sequence:I
iget v0, p0, ${factory}->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, ${factory}->calls:I
if-eqz v1, :null
sget-boolean v0, ${probe}->throwing:Z
if-eqz v0, :result
sget-object v0, ${probe}->sentinel:Ljava/lang/RuntimeException;
throw v0
:result
sget-object v0, ${probe}->result:${view}
return-object v0
:null
const/4 v0, 0
return-object v0
:bad
const-string v0, "factory arguments or callback ordering changed"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
const/4 v0, 0
return-object v0', 2)
	return text
}

fn test_probe() string {
	mut text := '.class public ${probe}\n.super Ljava/lang/Object;\n.field public static parent:${view}\n.field public static result:${view}\n.field public static context:Landroid/content/Context;\n.field public static sequence:I\n.field public static throwing:Z\n.field public static sentinel:Ljava/lang/RuntimeException;\n'
	text += method('public static fail(Ljava/lang/String;)V', 'new-instance v0, Ljava/lang/AssertionError;\ninvoke-direct {v0, p0}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0', 1)
	// Reflection preserves the framework method's package-private visibility.
	text += method('private static invoke(${inflater}Landroid/view/View;)Landroid/view/View;', '
const-class v0, ${inflater}
const/4 v1, 3
new-array v1, v1, [Ljava/lang/Class;
const/4 v2, 0
const-class v3, Landroid/view/View;
aput-object v3, v1, v2
const/4 v2, 1
const-class v3, Ljava/lang/String;
aput-object v3, v1, v2
const/4 v2, 2
const-class v3, Landroid/util/AttributeSet;
aput-object v3, v1, v2
const-string v2, "createViewFromTag"
invoke-virtual {v0, v2, v1}, Ljava/lang/Class;->getDeclaredMethod(Ljava/lang/String;[Ljava/lang/Class;)Ljava/lang/reflect/Method;
move-result-object v0
const/4 v1, 1
invoke-virtual {v0, v1}, Ljava/lang/reflect/Method;->setAccessible(Z)V
const/4 v1, 3
new-array v1, v1, [Ljava/lang/Object;
const/4 v2, 0
aput-object p1, v1, v2
const/4 v2, 1
const-string v3, "Probe"
aput-object v3, v1, v2
const/4 v2, 2
const/4 v3, 0
aput-object v3, v1, v2
invoke-virtual {v0, p0, v1}, Ljava/lang/reflect/Method;->invoke(Ljava/lang/Object;[Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/view/View;
return-object v0', 4)
	mut counters := 'const/4 v1, 0\n'
	for i, spec in [['p0', 'strings', 'p2'], ['p0', 'ids', 'v1'], ['p0', 'names', 'v1'], ['p1', 'strings', 'p2'], ['p1', 'ids', 'p2'], ['p1', 'names', 'p2']] {
		counters += 'iget v0, ${spec[0]}, ${view}->${spec[1]}:I\nif-eq v0, ${spec[2]}, :counter_${i}\nconst-string v0, "${spec[0]}.${spec[1]} diagnostic counter"\ninvoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V\n:counter_${i}\n'
	}
	text += method('private static counters(${view}${view}I)V', counters + 'return-void', 2)
	text += check_method()
	text += method('private static callbacks(${factory}${factory}${factory})V', '
const/4 v1, 1
iget v0, p0, ${factory}->calls:I
if-ne v0, v1, :bad
iget v0, p1, ${factory}->calls:I
if-ne v0, v1, :bad
iget v0, p2, ${factory}->calls:I
if-nez v0, :bad
sget v0, ${probe}->sequence:I
const/4 v1, 2
if-ne v0, v1, :bad
return-void
:bad
const-string v0, "factory callback counts changed"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
return-void', 2)
	return text
}

fn check_method() string {
	return method('public static check(Landroid/content/Context;)V', '
sput-object p0, ${probe}->context:Landroid/content/Context;
new-instance v2, ${inflater}
invoke-direct {v2, p0}, ${inflater}-><init>(Landroid/content/Context;)V
new-instance v3, ${view}
invoke-direct {v3, p0}, ${view}-><init>(Landroid/content/Context;)V
sput-object v3, ${probe}->parent:${view}
new-instance v4, ${view}
invoke-direct {v4, p0}, ${view}-><init>(Landroid/content/Context;)V
sput-object v4, ${probe}->result:${view}
new-instance v5, ${factory}
const/4 v0, 0
invoke-direct {v5, v0}, ${factory}-><init>(I)V
new-instance v6, ${factory}
const/4 v0, 1
invoke-direct {v6, v0}, ${factory}-><init>(I)V
new-instance v7, ${factory}
const/4 v0, 2
invoke-direct {v7, v0}, ${factory}-><init>(I)V
invoke-virtual {v2, v7}, ${inflater}->setFactory2(${factory2})V
invoke-virtual {v2, v6}, ${inflater}->setFactory2(${factory2})V
invoke-virtual {v2, v5}, ${inflater}->setFactory2(${factory2})V
invoke-virtual {v3}, ${view}->reset()V
invoke-virtual {v4}, ${view}->reset()V
invoke-static {v2, v3}, ${probe}->invoke(${inflater}Landroid/view/View;)Landroid/view/View;
move-result-object v0
if-eq v0, v4, :identity
const-string v0, "inflater must preserve factory result identity"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
:identity
invoke-static {v5, v6, v7}, ${probe}->callbacks(${factory}${factory}${factory})V
' + marker('CALLBACKS') + '
iget v8, v3, ${view}->strings:I
const/4 v0, 1
if-le v8, v0, :bounded
const-string v0, "diagnostic callback count exceeds one"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
:bounded
invoke-static {v3, v4, v8}, ${probe}->counters(${view}${view}I)V
if-eqz v8, :skipped
' + marker('WORK-PRESENT') + '
goto :environment
:skipped
' + marker('WORK-SKIPPED') + '
:environment
const-string v0, "VINIX_ANDROID_TRACE_INFLATER"
invoke-static {v0}, Ljava/lang/System;->getenv(Ljava/lang/String;)Ljava/lang/String;
move-result-object v0
if-eqz v0, :absent
const-string v1, "1"
invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
if-nez v0, :one
const-string v0, "unexpected trace environment value"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
:one
' + marker('TRACE-ENV-ONE') + '
goto :exceptions
:absent
' + marker('TRACE-ENV-ABSENT') + '
:exceptions
const/4 v0, 0
sput v0, ${probe}->sequence:I
iput v0, v5, ${factory}->calls:I
iput v0, v6, ${factory}->calls:I
new-instance v9, Ljava/lang/RuntimeException;
const-string v0, "factory sentinel"
invoke-direct {v9, v0}, Ljava/lang/RuntimeException;-><init>(Ljava/lang/String;)V
sput-object v9, ${probe}->sentinel:Ljava/lang/RuntimeException;
const/4 v0, 1
sput-boolean v0, ${probe}->throwing:Z
:throw_start
invoke-static {v2, v3}, ${probe}->invoke(${inflater}Landroid/view/View;)Landroid/view/View;
:throw_end
const-string v0, "factory exception must escape inflation"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
return-void
:expected
move-exception v0
invoke-virtual {v0}, Ljava/lang/reflect/InvocationTargetException;->getCause()Ljava/lang/Throwable;
move-result-object v0
if-eq v0, v9, :cause
const-string v0, "inflation changed factory exception identity"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
:cause
invoke-static {v5, v6, v7}, ${probe}->callbacks(${factory}${factory}${factory})V
' + marker('THROWABLE') + '
const-string v0, "LayoutInflater"
const-string v1, "BOOTSTRAP-INFLATER-TRACE-WARNING-PASS"
invoke-static {v0, v1}, Landroid/util/Slog;->w(Ljava/lang/String;Ljava/lang/String;)I
const-string v1, "BOOTSTRAP-INFLATER-TRACE-ERROR-PASS"
invoke-static {v0, v1}, Landroid/util/Slog;->e(Ljava/lang/String;Ljava/lang/String;)I
return-void
.catch Ljava/lang/reflect/InvocationTargetException; {:throw_start .. :throw_end} :expected', 10)
}

fn activity() string {
	return '.class public Lorg/vinix/bootstrap/Main;\n.super Landroid/app/Activity;\n' + method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void', 0) + method('public onCreate(Landroid/os/Bundle;)V', '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
invoke-static {p0}, ${probe}->check(Landroid/content/Context;)V
new-instance v0, Landroid/view/View;
invoke-direct {v0, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-READY"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void', 2)
}

fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 2, 'OUTPUT'
	out := os.abs_path(os.args[1])
	root := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(root)!
	os.write_file(out + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="26" android:targetSdkVersion="35"/><application android:label="Inflater trace fixture"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
	os.write_file(root + '/Main.smali', activity())!
	os.write_file(root + '/InflaterProbe.smali', test_probe())!
	os.write_file(root + '/ProbeView.smali', probe_view())!
	os.write_file(root + '/ProbeFactory.smali', probe_factory())!
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	framework := '/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/framework-res.apk'
	checked([os.abs_path('build/android-native-ws/aapt2'), 'link', '-I', framework, '--manifest', out + '/AndroidManifest.xml', '-o', out + '/unsigned.apk'])
	checked([java, '-cp', os.abs_path('build/android-framework/tools') + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali', '-o', out + '/classes.dex'])
	assert os.is_file(out + '/classes.dex'), 'smali produced no DEX'
	checked(['zip', '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'])
	key := out + '/fixture.p12'
	checked(['/opt/homebrew/opt/openjdk@25/bin/keytool', '-genkeypair', '-keystore', key, '-storetype', 'PKCS12', '-alias', 'fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650', '-dname', 'CN=Vinix Inflater trace fixture', '-storepass', 'android', '-keypass', 'android'])
	checked([java, '-jar', os.abs_path('build/android-native-ws/android-15/lib/apksigner.jar'), 'sign', '--ks', key, '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'])
	println('INFLATER-TRACE-APK ' + sha256.sum(os.read_bytes(out + '/probe.apk')!).hex())
}
