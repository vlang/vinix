// SPDX-License-Identifier: GPL-2.0-or-later
// Public Window registration/removal contracts; no synthetic frame timings.
module main

import crypto.sha256
import os

const probe = 'Lorg/vinix/bootstrap/MetricsProbe;'
const listener = 'Lorg/vinix/bootstrap/MetricsListener;'
const callback = 'Landroid/view/Window$OnFrameMetricsAvailableListener;'
const window = 'Landroid/view/Window;'
const metrics = 'Landroid/view/FrameMetrics;'
const handler = 'Landroid/os/Handler;'
const add_signature = 'addOnFrameMetricsAvailableListener(${callback}${handler})V'
const remove_signature = 'removeOnFrameMetricsAvailableListener(${callback})V'

fn checked(args []string) {
	r := os.exec(args)
	assert r.exit_code == 0, r.output
}

fn method(signature string, body string, locals int) string {
	return '.method ' + signature + '\n.locals ${locals}\n' + body + '\n.end method\n'
}

fn marker(name string) string {
	return 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-FRAME-METRICS-${name}-PASS"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n'
}

fn expect(name string, args string, body string, exception string) string {
	return method('private static ${name}(${args})V', ':start\n${body}\n:end\nconst-string v0, "${name} must throw ${exception}"\ninvoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V\nreturn-void\n:expected\nmove-exception v0\nreturn-void\n.catch Ljava/lang/${exception}; {:start .. :end} :expected', 1)
}

fn test_probe() string {
	mut text := '.class public ${probe}\n.super Ljava/lang/Object;\n'
	text += method('public static detached(Landroid/content/Context;)V', '
new-instance v2, ${window}
const/4 v0, 0
invoke-direct {v2, p0, v0}, ${window}-><init>(Landroid/content/Context;Landroid/view/Window$Callback;)V
invoke-virtual {v2}, ${window}->getDecorView()Landroid/view/View;
move-result-object v0
invoke-virtual {v0}, Landroid/view/View;->isAttachedToWindow()Z
move-result v0
if-eqz v0, :detached
const-string v0, "standalone Window decor must be detached"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
:detached
new-instance v3, ${listener}
invoke-direct {v3}, ${listener}-><init>()V
new-instance v4, ${listener}
invoke-direct {v4}, ${listener}-><init>()V
new-instance v5, ${handler}
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v0
invoke-direct {v5, v0}, ${handler}-><init>(Landroid/os/Looper;)V
const/4 v6, 0
invoke-static {v2, v6, v5}, ${probe}->nullListener(${window}${callback}${handler})V
invoke-static {v2, v3, v6}, ${probe}->nullHandler(${window}${callback}${handler})V
invoke-static {v2, v3}, ${probe}->missing(${window}${callback})V
invoke-virtual {v2, v3, v5}, ${window}->${add_signature}
invoke-virtual {v2, v3, v5}, ${window}->${add_signature}
# These listener instances deliberately compare equal: removal uses identity.
invoke-static {v2, v4}, ${probe}->missing(${window}${callback})V
invoke-virtual {v2, v3}, ${window}->${remove_signature}
invoke-virtual {v2, v3}, ${window}->${remove_signature}
invoke-static {v2, v3}, ${probe}->missing(${window}${callback})V
invoke-static {v2, v6}, ${probe}->missing(${window}${callback})V
new-instance v7, ${window}
invoke-direct {v7, p0, v6}, ${window}-><init>(Landroid/content/Context;Landroid/view/Window$Callback;)V
invoke-virtual {v2, v3, v5}, ${window}->${add_signature}
invoke-static {v7, v3}, ${probe}->missing(${window}${callback})V
invoke-virtual {v2, v3}, ${window}->${remove_signature}
new-instance v7, Lorg/vinix/bootstrap/EmptyWindow;
invoke-direct {v7, p0}, Lorg/vinix/bootstrap/EmptyWindow;-><init>(Landroid/content/Context;)V
invoke-static {v7, v3, v5}, ${probe}->noDecor(${window}${callback}${handler})V
invoke-virtual {v7, v3}, ${window}->${remove_signature}
iget v0, v3, ${listener}->calls:I
if-eqz v0, :quiet
const-string v0, "registration and removal must not fabricate timing callbacks"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
:quiet
' + marker('DETACHED') + '
invoke-static {}, ${probe}->metrics()V
return-void', 8)
	text += expect('nullListener', window + callback + handler, 'invoke-virtual {p0, p1, p2}, ${window}->${add_signature}', 'NullPointerException')
	text += expect('nullHandler', window + callback + handler, 'invoke-virtual {p0, p1, p2}, ${window}->${add_signature}', 'NullPointerException')
	text += expect('missing', window + callback, 'invoke-virtual {p0, p1}, ${window}->${remove_signature}', 'IllegalArgumentException')
	text += expect('noDecor', window + callback + handler, 'invoke-virtual {p0, p1, p2}, ${window}->${add_signature}', 'IllegalStateException')
	text += expect('nullCopy', metrics, 'new-instance v0, ${metrics}\ninvoke-direct {v0, p0}, ${metrics}-><init>(${metrics})V', 'NullPointerException')
	mut values := 'new-instance v2, ${metrics}\ninvoke-direct {v2}, ${metrics}-><init>()V\nconst/4 v0, 0\ninvoke-static {v0}, ${probe}->nullCopy(${metrics})V\n'
	for i, name in ['UNKNOWN_DELAY_DURATION', 'INPUT_HANDLING_DURATION', 'ANIMATION_DURATION', 'LAYOUT_MEASURE_DURATION', 'DRAW_DURATION', 'SYNC_DURATION', 'COMMAND_ISSUE_DURATION', 'SWAP_BUFFERS_DURATION', 'TOTAL_DURATION', 'FIRST_DRAW_FRAME', 'INTENDED_VSYNC_TIMESTAMP', 'VSYNC_TIMESTAMP', 'GPU_DURATION', 'DEADLINE'] {
		values += 'sget v0, ${metrics}->${name}:I\nconst/16 v1, ${i}\nif-eq v0, v1, :constant_${i}\nconst-string v0, "FrameMetrics.${name}"\ninvoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V\n:constant_${i}\n'
	}
	values += 'new-instance v3, ${metrics}\ninvoke-direct {v3, v2}, ${metrics}-><init>(${metrics})V\nconst/4 v4, -1\n:next\ninvoke-virtual {v2, v4}, ${metrics}->getMetric(I)J\nmove-result-wide v0\nconst-wide/16 v5, -1\ncmp-long v7, v0, v5\nif-nez v7, :bad\ninvoke-virtual {v3, v4}, ${metrics}->getMetric(I)J\nmove-result-wide v0\ncmp-long v7, v0, v5\nif-nez v7, :bad\nadd-int/lit8 v4, v4, 1\nconst/16 v0, 15\nif-lt v4, v0, :next\n' + marker('VALUES') + 'new-instance v3, ${listener}\ninvoke-direct {v3}, ${listener}-><init>()V\nconst/4 v4, 0\nconst/4 v5, 7\ninvoke-interface {v3, v4, v2, v5}, ${callback}->onFrameMetricsAvailable(${window}${metrics}I)V\niget v0, v3, ${listener}->calls:I\nconst/4 v1, 1\nif-ne v0, v1, :bad\n' + marker('SIGNATURE') + 'return-void\n:bad\nconst-string v0, "unavailable metrics, copies and listener callback descriptor"\ninvoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V\nreturn-void'
	text += method('private static metrics()V', values, 8)
	text += method('public static fail(Ljava/lang/String;)V', 'new-instance v0, Ljava/lang/AssertionError;\ninvoke-direct {v0, p0}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0', 1)
	return text
}

fn activity() string {
	mut text := '.class public Lorg/vinix/bootstrap/Main;\n.super Landroid/app/Activity;\n.implements Landroid/view/ViewTreeObserver$OnPreDrawListener;\n.field private listener:${listener}\n.field private frames:I\n'
	text += method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void', 0)
	text += method('public onCreate(Landroid/os/Bundle;)V', '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
invoke-static {p0}, ${probe}->detached(Landroid/content/Context;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Window frame metrics registration fixture"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {v0}, Landroid/view/View;->getViewTreeObserver()Landroid/view/ViewTreeObserver;
move-result-object v1
invoke-virtual {v1, p0}, Landroid/view/ViewTreeObserver;->addOnPreDrawListener(Landroid/view/ViewTreeObserver$OnPreDrawListener;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
return-void', 2)
	text += method('public onPreDraw()Z', '
invoke-virtual {p0}, Landroid/app/Activity;->getWindow()Landroid/view/Window;
move-result-object v2
invoke-virtual {v2}, ${window}->getDecorView()Landroid/view/View;
move-result-object v3
invoke-virtual {v3}, Landroid/view/View;->isAttachedToWindow()Z
move-result v0
if-nez v0, :attached
const-string v0, "pre-draw must use an attached Window"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
:attached
iget v0, p0, Lorg/vinix/bootstrap/Main;->frames:I
if-nez v0, :remove
new-instance v4, ${listener}
invoke-direct {v4}, ${listener}-><init>()V
iput-object v4, p0, Lorg/vinix/bootstrap/Main;->listener:${listener}
new-instance v5, ${handler}
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v0
invoke-direct {v5, v0}, ${handler}-><init>(Landroid/os/Looper;)V
invoke-virtual {v2, v4, v5}, ${window}->${add_signature}
const/4 v0, 1
iput v0, p0, Lorg/vinix/bootstrap/Main;->frames:I
invoke-virtual {v3}, Landroid/view/View;->invalidate()V
return v0
:remove
iget-object v4, p0, Lorg/vinix/bootstrap/Main;->listener:${listener}
invoke-virtual {v2, v4}, ${window}->${remove_signature}
iget v0, v4, ${listener}->calls:I
if-eqz v0, :quiet
const-string v0, "software backend must not fabricate metrics after a frame"
invoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V
:quiet
invoke-virtual {v3}, Landroid/view/View;->getViewTreeObserver()Landroid/view/ViewTreeObserver;
move-result-object v0
invoke-virtual {v0, p0}, Landroid/view/ViewTreeObserver;->removeOnPreDrawListener(Landroid/view/ViewTreeObserver$OnPreDrawListener;)V
' + marker('ATTACHED') + '
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-READY"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
const/4 v0, 1
return v0', 6)
	return text
}

fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 2, 'OUTPUT'
	out := os.abs_path(os.args[1])
	root := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(root)!
	os.write_file(out + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="26" android:targetSdkVersion="35"/><application android:label="Frame metrics fixture"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
	os.write_file(root + '/Main.smali', activity())!
	os.write_file(root + '/MetricsProbe.smali', test_probe())!
	os.write_file(root + '/EmptyWindow.smali', '.class public Lorg/vinix/bootstrap/EmptyWindow;\n.super ${window}\n' + method('public constructor <init>(Landroid/content/Context;)V', 'const/4 v0, 0\ninvoke-direct {p0, p1, v0}, ${window}-><init>(Landroid/content/Context;Landroid/view/Window$Callback;)V\nreturn-void', 1) + method('public getDecorView()Landroid/view/View;', 'const/4 v0, 0\nreturn-object v0', 1))!
	os.write_file(root + '/MetricsListener.smali', '.class public ${listener}\n.super Ljava/lang/Object;\n.implements ${callback}\n.field public calls:I\n' + method('public constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void', 0) + method('public equals(Ljava/lang/Object;)Z', 'const/4 v0, 1\nreturn v0', 1) + method('public onFrameMetricsAvailable(${window}${metrics}I)V', 'iget v0, p0, ${listener}->calls:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${listener}->calls:I\nreturn-void', 1))!
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	framework := '/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/framework-res.apk'
	checked([os.abs_path('build/android-native-ws/aapt2'), 'link', '-I', framework, '--manifest', out + '/AndroidManifest.xml', '-o', out + '/unsigned.apk'])
	checked([java, '-cp', os.abs_path('build/android-framework/tools') + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali', '-o', out + '/classes.dex'])
	assert os.is_file(out + '/classes.dex'), 'smali produced no DEX'
	checked(['zip', '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'])
	key := out + '/fixture.p12'
	checked(['/opt/homebrew/opt/openjdk@25/bin/keytool', '-genkeypair', '-keystore', key, '-storetype', 'PKCS12', '-alias', 'fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650', '-dname', 'CN=Vinix Frame metrics fixture', '-storepass', 'android', '-keypass', 'android'])
	checked([java, '-jar', os.abs_path('build/android-native-ws/android-15/lib/apksigner.jar'), 'sign', '--ks', key, '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'])
	println('FRAME-METRICS-APK ' + sha256.sum(os.read_bytes(out + '/probe.apk')!).hex())
}
