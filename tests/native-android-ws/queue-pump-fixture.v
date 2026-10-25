// SPDX-License-Identifier: GPL-2.0-or-later
// A finite due-message chain must yield to a real pre-draw before it drains.
module main

import crypto.sha256
import os

const main_class = 'Lorg/vinix/bootstrap/Main;'
const task_class = 'Lorg/vinix/bootstrap/QueueTask;'
const complete_class = 'Lorg/vinix/bootstrap/QueueComplete;'

fn checked(args []string) {
	r := os.exec(args)
	assert r.exit_code == 0, r.output
}

fn method(signature string, body string, locals int) string {
	return '.method ' + signature + '\n.locals ${locals}\n' + body + '\n.end method\n'
}

fn marker(text string) string {
	return 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "${text}"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n'
}

fn activity() string {
	mut text := '.class public ${main_class}\n.super Landroid/app/Activity;\n.implements Landroid/view/ViewTreeObserver$OnPreDrawListener;\n'
	text += '.field private handler:Landroid/os/Handler;\n.field private view:Landroid/view/View;\n.field private pending:Ljava/lang/Runnable;\n.field private count:I\n.field private firstFrameCount:I\n.field private completeDue:J\n.field private completed:Z\n'
	text += method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void', 0)
	text += method('public onCreate(Landroid/os/Bundle;)V', '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
new-instance v0, Landroid/os/Handler;
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
invoke-direct {v0, v1}, Landroid/os/Handler;-><init>(Landroid/os/Looper;)V
iput-object v0, p0, ${main_class}->handler:Landroid/os/Handler;
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Main queue frame progress fixture"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
const v1, -0xcc9967
invoke-virtual {v0, v1}, Landroid/view/View;->setBackgroundColor(I)V
iput-object v0, p0, ${main_class}->view:Landroid/view/View;
invoke-virtual {v0}, Landroid/view/View;->getViewTreeObserver()Landroid/view/ViewTreeObserver;
move-result-object v1
invoke-virtual {v1, p0}, Landroid/view/ViewTreeObserver;->addOnPreDrawListener(Landroid/view/ViewTreeObserver$OnPreDrawListener;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
const/4 v0, 1
invoke-virtual {p0, v0}, ${main_class}->enqueue(I)V
iget v0, p0, ${main_class}->count:I
if-nez v0, :bad
return-void
:bad
const-string v0, "Handler.post must not dispatch inline"
invoke-static {v0}, ${main_class}->fail(Ljava/lang/String;)V
return-void', 2)
	text += method('public enqueue(I)V', '
new-instance v0, ${task_class}
invoke-direct {v0, p0, p1}, ${task_class}-><init>(${main_class}I)V
iput-object v0, p0, ${main_class}->pending:Ljava/lang/Runnable;
iget-object v1, p0, ${main_class}->handler:Landroid/os/Handler;
invoke-virtual {v1, v0}, Landroid/os/Handler;->post(Ljava/lang/Runnable;)Z
move-result v0
if-nez v0, :posted
const-string v0, "immediate queue task was rejected"
invoke-static {v0}, ${main_class}->fail(Ljava/lang/String;)V
:posted
return-void', 2)
	text += method('public step(I)V', '
invoke-static {}, ${main_class}->mainThread()V
iget-boolean v0, p0, ${main_class}->completed:Z
if-nez v0, :bad
iget v0, p0, ${main_class}->count:I
add-int/lit8 v0, v0, 1
if-ne v0, p1, :bad
const/16 v1, 1024
if-gt v0, v1, :bad
iput v0, p0, ${main_class}->count:I
if-eq v0, v1, :drained
add-int/lit8 v0, v0, 1
invoke-virtual {p0, v0}, ${main_class}->enqueue(I)V
return-void
:drained
const/4 v0, 0
iput-object v0, p0, ${main_class}->pending:Ljava/lang/Runnable;
# A future message permits the old unbounded pump to return: its first
# pre-draw must then fail the strict partial-chain assertion below.
invoke-static {}, Landroid/os/SystemClock;->uptimeMillis()J
move-result-wide v0
const-wide/16 v2, 100
add-long/2addr v0, v2
iput-wide v0, p0, ${main_class}->completeDue:J
new-instance v0, ${complete_class}
invoke-direct {v0, p0}, ${complete_class}-><init>(${main_class})V
iget-object v1, p0, ${main_class}->handler:Landroid/os/Handler;
invoke-virtual {v1, v0, v2, v3}, Landroid/os/Handler;->postDelayed(Ljava/lang/Runnable;J)Z
move-result v0
if-eqz v0, :bad
return-void
:bad
const-string v0, "queue tasks must execute exactly once in sequence 1..1024"
invoke-static {v0}, ${main_class}->fail(Ljava/lang/String;)V
return-void', 4)
	text += method('public onPreDraw()Z', '
invoke-static {}, ${main_class}->mainThread()V
iget v2, p0, ${main_class}->count:I
if-lez v2, :bad
const/16 v0, 1024
if-ge v2, v0, :bad
iget v0, p0, ${main_class}->firstFrameCount:I
if-nez v0, :bad
iget-object v0, p0, ${main_class}->pending:Ljava/lang/Runnable;
if-eqz v0, :bad
iget-object v1, p0, ${main_class}->handler:Landroid/os/Handler;
invoke-virtual {v1, v0}, Landroid/os/Handler;->hasCallbacks(Ljava/lang/Runnable;)Z
move-result v0
if-eqz v0, :bad
iput v2, p0, ${main_class}->firstFrameCount:I
iget-object v0, p0, ${main_class}->view:Landroid/view/View;
invoke-virtual {v0}, Landroid/view/View;->getViewTreeObserver()Landroid/view/ViewTreeObserver;
move-result-object v0
invoke-virtual {v0, p0}, Landroid/view/ViewTreeObserver;->removeOnPreDrawListener(Landroid/view/ViewTreeObserver$OnPreDrawListener;)V
' + marker('BOOTSTRAP-QUEUE-PUMP-PASS') + '
const/4 v0, 1
return v0
:bad
const-string v0, "first pre-draw must run during pending chain: 0 < count < 1024"
invoke-static {v0}, ${main_class}->fail(Ljava/lang/String;)V
const/4 v0, 0
return v0', 3)
	text += method('public complete()V', '
invoke-static {}, ${main_class}->mainThread()V
iget-boolean v0, p0, ${main_class}->completed:Z
if-nez v0, :bad
iget v0, p0, ${main_class}->count:I
const/16 v1, 1024
if-ne v0, v1, :bad
iget v0, p0, ${main_class}->firstFrameCount:I
if-lez v0, :bad
if-ge v0, v1, :bad
iget-object v0, p0, ${main_class}->pending:Ljava/lang/Runnable;
if-nez v0, :bad
invoke-static {}, Landroid/os/SystemClock;->uptimeMillis()J
move-result-wide v0
iget-wide v2, p0, ${main_class}->completeDue:J
cmp-long v0, v0, v2
if-ltz v0, :bad
const/4 v0, 1
iput-boolean v0, p0, ${main_class}->completed:Z
' + marker('BOOTSTRAP-QUEUE-PUMP-COMPLETE-PASS') + marker('BOOTSTRAP-READY') + '
return-void
:bad
const-string v0, "completion requires all 1024 ordered tasks, an earlier partial frame and elapsed delay"
invoke-static {v0}, ${main_class}->fail(Ljava/lang/String;)V
return-void', 4)
	text += method('private static mainThread()V', '
invoke-static {}, Landroid/os/Looper;->myLooper()Landroid/os/Looper;
move-result-object v0
invoke-static {}, Landroid/os/Looper;->getMainLooper()Landroid/os/Looper;
move-result-object v1
if-eq v0, v1, :main
const-string v0, "queue and pre-draw callbacks must run on the main Looper"
invoke-static {v0}, ${main_class}->fail(Ljava/lang/String;)V
:main
return-void', 2)
	text += method('private static fail(Ljava/lang/String;)V', 'new-instance v0, Ljava/lang/AssertionError;\ninvoke-direct {v0, p0}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0', 1)
	return text
}

fn runnable(name string, call string, expected bool) string {
	mut text := '.class public ${name}\n.super Ljava/lang/Object;\n.implements Ljava/lang/Runnable;\n.field private owner:${main_class}\n'
	if expected {
		text += '.field private expected:I\n'
		text += method('public constructor <init>(${main_class}I)V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, ${name}->owner:${main_class}\niput p2, p0, ${name}->expected:I\nreturn-void', 0)
		text += method('public run()V', 'iget-object v0, p0, ${name}->owner:${main_class}\niget v1, p0, ${name}->expected:I\ninvoke-virtual {v0, v1}, ${main_class}->${call}(I)V\nreturn-void', 2)
	} else {
		text += method('public constructor <init>(${main_class})V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, ${name}->owner:${main_class}\nreturn-void', 0)
		text += method('public run()V', 'iget-object v0, p0, ${name}->owner:${main_class}\ninvoke-virtual {v0}, ${main_class}->${call}()V\nreturn-void', 1)
	}
	return text
}

fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 2, 'OUTPUT'
	out := os.abs_path(os.args[1])
	root := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(root)!
	os.write_file(out + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="26" android:targetSdkVersion="35"/><application android:label="Queue pump fixture"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
	os.write_file(root + '/Main.smali', activity())!
	os.write_file(root + '/QueueTask.smali', runnable(task_class, 'step', true))!
	os.write_file(root + '/QueueComplete.smali', runnable(complete_class, 'complete', false))!
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	framework := '/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/framework-res.apk'
	aapt := os.abs_path('build/android-native-ws/aapt2')
	for name in ['classes.dex', 'unsigned.apk', 'probe.apk'] {
		if os.is_file(out + '/' + name) { os.rm(out + '/' + name)! }
	}
	checked([aapt, 'link', '-I', framework, '--manifest', out + '/AndroidManifest.xml', '-o', out + '/unsigned.apk'])
	checked([java, '-cp', os.abs_path('build/android-framework/tools') + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali', '-o', out + '/classes.dex'])
	assert os.is_file(out + '/classes.dex'), 'smali produced no DEX'
	checked(['zip', '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'])
	key := out + '/fixture.p12'
	if !os.is_file(key) { checked(['/opt/homebrew/opt/openjdk@25/bin/keytool', '-genkeypair', '-keystore', key, '-storetype', 'PKCS12', '-alias', 'fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650', '-dname', 'CN=Vinix Queue pump fixture', '-storepass', 'android', '-keypass', 'android']) }
	checked([java, '-jar', os.abs_path('build/android-native-ws/android-15/lib/apksigner.jar'), 'sign', '--ks', key, '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'])
	println('QUEUE-PUMP-APK ' + sha256.sum(os.read_bytes(out + '/probe.apk')!).hex())
}
