// SPDX-License-Identifier: GPL-2.0-or-later
// Generate a small DEX regression APK. All native test behavior is V.
// Usage: v run bootstrap-fixture.v OUTPUT AAPT2 FRAMEWORK_RES SMALI_TOOLS JAVA APKSIGNER
module main

import os
import encoding.base64

fn checked(args []string) {
	result := os.exec(args)
	if result.exit_code != 0 { panic(result.output) }
}

fn method(signature string, body string) string {
	return '.method ' + signature + '\n.locals 8\n' + body + '\n.end method\n'
}

fn constructor(parent string, body string) string {
	return method('public constructor <init>()V', 'invoke-direct {p0}, L' + parent + ';-><init>()V\n' + body + '\nreturn-void')
}

fn stage(expected int, next int) string {
	return 'const/4 v0, ${expected}\ninvoke-static {v0}, Lorg/vinix/bootstrap/App;->check(I)V\nconst/4 v0, ${next}\nsput v0, Lorg/vinix/bootstrap/App;->stage:I\n'
}

fn main() {
	if os.args.len != 7 { panic('OUTPUT AAPT2 FRAMEWORK_RES SMALI_TOOLS JAVA APKSIGNER') }
	output, aapt, resources, tools, java := os.abs_path(os.args[1]), os.abs_path(os.args[2]), os.abs_path(os.args[3]), os.abs_path(os.args[4]), os.args[5]
	smali := output + '/smali/org/vinix/bootstrap'
	os.mkdir_all(smali)!
	os.mkdir_all(output + '/lib/arm64-v8a')!
	os.mkdir_all(output + '/assets')!
	os.write_file(output + '/assets/probe.txt', 'VINIX-ASSET-OK\n')!
	// Lossless 2x1 red/green image, generated from our own PPM test pixels.
	os.write_file_array(output + '/assets/probe.webp', base64.decode('UklGRh4AAABXRUJQVlA4TBEAAAAvAQAAAA+w//Mf8x8VMqL/AQA='))!
	app := '.class public Lorg/vinix/bootstrap/App;\n.super Landroid/app/Application;\n.field public static stage:I\n' +
		constructor('android/app/Application', '') +
		method('public static check(I)V', '
sget v0, Lorg/vinix/bootstrap/App;->stage:I
if-eq v0, p0, :ok
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Application/provider/Activity initialization order"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
return-void') +
		method('protected attachBaseContext(Landroid/content/Context;)V', '
invoke-super {p0, p1}, Landroid/content/ContextWrapper;->attachBaseContext(Landroid/content/Context;)V
invoke-virtual {p1}, Landroid/content/Context;->getApplicationInfo()Landroid/content/pm/ApplicationInfo;
move-result-object v0
iget-object v2, v0, Landroid/content/pm/ApplicationInfo;->sourceDir:Ljava/lang/String;
invoke-virtual {p1}, Landroid/content/Context;->getPackageManager()Landroid/content/pm/PackageManager;
move-result-object v1
invoke-virtual {p1}, Landroid/content/Context;->getPackageName()Ljava/lang/String;
move-result-object v3
const/4 v4, 0
invoke-virtual {v1, v3, v4}, Landroid/content/pm/PackageManager;->getApplicationInfo(Ljava/lang/String;I)Landroid/content/pm/ApplicationInfo;
move-result-object v1
iget-object v3, v1, Landroid/content/pm/ApplicationInfo;->sourceDir:Ljava/lang/String;
invoke-virtual {v2, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :bad
iget-object v2, v0, Landroid/content/pm/ApplicationInfo;->dataDir:Ljava/lang/String;
invoke-virtual {p1}, Landroid/content/Context;->getDataDir()Ljava/io/File;
move-result-object v3
invoke-virtual {v3}, Ljava/io/File;->getPath()Ljava/lang/String;
move-result-object v3
invoke-virtual {v2, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :bad
const/4 v0, 1
sput v0, Lorg/vinix/bootstrap/App;->stage:I
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Inconsistent PackageManager/Application paths"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
		method('public onCreate()V', stage(3, 4) + 'return-void')
	os.write_file(smali + '/App.smali', app)!
	for name, expected in {'High': 1, 'Low': 2} {
		mut source := '.class public Lorg/vinix/bootstrap/' + name + ';\n.super Landroid/content/ContentProvider;\n' + constructor('android/content/ContentProvider', '')
		source += method('public onCreate()Z', stage(expected, expected + 1) + 'const/4 v0, 1\nreturn v0')
		for signature in ['query(Landroid/net/Uri;[Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;Ljava/lang/String;)Landroid/database/Cursor;',
			'insert(Landroid/net/Uri;Landroid/content/ContentValues;)Landroid/net/Uri;'] {
			source += method('public ' + signature, 'const/4 v0, 0\nreturn-object v0')
		}
		source += method('public getType(Landroid/net/Uri;)Ljava/lang/String;', 'const-string v0, "fixture/type"\nreturn-object v0')
		for signature in ['delete(Landroid/net/Uri;Ljava/lang/String;[Ljava/lang/String;)I', 'update(Landroid/net/Uri;Landroid/content/ContentValues;Ljava/lang/String;[Ljava/lang/String;)I'] {
			source += method('public ' + signature, 'const/4 v0, 0\nreturn v0')
		}
		os.write_file(smali + '/' + name + '.smali', source)!
	}
	main_class := '.class public Lorg/vinix/bootstrap/Main;\n.super Landroid/app/Activity;\n' +
		constructor('android/app/Activity', 'const/4 v0, 4\ninvoke-static {v0}, Lorg/vinix/bootstrap/App;->check(I)V') +
		'.method public static native nativeCheck(Landroid/content/res/AssetManager;)Z\n.end method\n' +
		'.method public static native nativeBitmap(Landroid/graphics/Bitmap;)Z\n.end method\n' +
		'.method public static native nativeGraphics()Z\n.end method\n' +
		method('protected onCreate(Landroid/os/Bundle;)V', '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
invoke-static {}, Landroid/os/Process;->is64Bit()Z
move-result v0
if-eqz v0, :bad
new-instance v0, Landroid/graphics/Matrix;
invoke-direct {v0}, Landroid/graphics/Matrix;-><init>()V
const v1, 0x42b40000
const v2, 0x41200000
const v3, 0x41a00000
invoke-virtual {v0, v1, v2, v3}, Landroid/graphics/Matrix;->postRotate(FFF)Z
const/4 v1, 4
new-array v1, v1, [F
const/4 v4, 0
aput v2, v1, v4
const/4 v4, 1
aput v3, v1, v4
invoke-virtual {v0, v1}, Landroid/graphics/Matrix;->mapPoints([F)V
const/4 v4, 0
aget v4, v1, v4
sub-float/2addr v4, v2
invoke-static {v4}, Ljava/lang/Math;->abs(F)F
move-result v4
const v5, 0x3a83126f
cmpl-float v4, v4, v5
if-gtz v4, :bad
const/4 v4, 1
aget v4, v1, v4
sub-float/2addr v4, v3
invoke-static {v4}, Ljava/lang/Math;->abs(F)F
move-result v4
cmpl-float v4, v4, v5
if-gtz v4, :bad
const/4 v4, 2
aget v4, v1, v4
const v6, 0x41f00000
sub-float/2addr v4, v6
invoke-static {v4}, Ljava/lang/Math;->abs(F)F
move-result v4
cmpl-float v4, v4, v5
if-gtz v4, :bad
const/4 v4, 3
aget v4, v1, v4
sub-float/2addr v4, v2
invoke-static {v4}, Ljava/lang/Math;->abs(F)F
move-result v4
cmpl-float v4, v4, v5
if-gtz v4, :bad
invoke-virtual {p0}, Landroid/app/Activity;->getContentResolver()Landroid/content/ContentResolver;
move-result-object v0
const-string v1, "content://fixture.missing/item"
invoke-static {v1}, Landroid/net/Uri;->parse(Ljava/lang/String;)Landroid/net/Uri;
move-result-object v1
invoke-virtual {v0, v1}, Landroid/content/ContentResolver;->acquireUnstableContentProviderClient(Landroid/net/Uri;)Landroid/content/ContentProviderClient;
move-result-object v2
if-nez v2, :bad
const-string v1, "content://fixture.alias/item"
invoke-static {v1}, Landroid/net/Uri;->parse(Ljava/lang/String;)Landroid/net/Uri;
move-result-object v1
invoke-virtual {v0, v1}, Landroid/content/ContentResolver;->acquireUnstableContentProviderClient(Landroid/net/Uri;)Landroid/content/ContentProviderClient;
move-result-object v2
if-eqz v2, :bad
invoke-virtual {v2, v1}, Landroid/content/ContentProviderClient;->getType(Landroid/net/Uri;)Ljava/lang/String;
move-result-object v3
const-string v4, "fixture/type"
invoke-virtual {v4, v3}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v3
if-eqz v3, :bad
invoke-virtual {v2}, Landroid/content/ContentProviderClient;->close()V
new-instance v0, Landroid/net/ConnectivityManager;
invoke-direct {v0}, Landroid/net/ConnectivityManager;-><init>()V
invoke-virtual {v0}, Landroid/net/ConnectivityManager;->getActiveNetworkInfo()Landroid/net/NetworkInfo;
move-result-object v0
invoke-virtual {v0}, Landroid/net/NetworkInfo;->isConnected()Z
move-result v0
if-eqz v0, :bad
new-instance v0, Landroid/widget/LinearLayout;
invoke-direct {v0, p0}, Landroid/widget/LinearLayout;-><init>(Landroid/content/Context;)V
new-instance v1, Landroid/view/View;
invoke-direct {v1, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
invoke-virtual {v1}, Landroid/view/View;->canResolveLayoutDirection()Z
move-result v2
if-nez v2, :bad
const/4 v2, 1
invoke-virtual {v0, v2}, Landroid/view/View;->setLayoutDirection(I)V
invoke-virtual {v0, v1}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
invoke-virtual {v1}, Landroid/view/View;->getLayoutDirection()I
move-result v3
if-ne v2, v3, :bad
const/4 v2, 0
invoke-virtual {v0, v2}, Landroid/view/View;->setLayoutDirection(I)V
invoke-virtual {v1}, Landroid/view/View;->getLayoutDirection()I
move-result v3
if-ne v2, v3, :bad
invoke-virtual {v1}, Landroid/view/View;->canResolveLayoutDirection()Z
move-result v2
if-eqz v2, :bad
invoke-static {}, Landroid/os/SystemClock;->elapsedRealtimeNanos()J
move-result-wide v0
invoke-static {}, Landroid/os/SystemClock;->elapsedRealtime()J
move-result-wide v2
const-wide/32 v4, 1000000
mul-long/2addr v2, v4
sub-long/2addr v2, v0
const-wide/32 v4, 1000000000
cmp-long v6, v2, v4
if-gtz v6, :bad
const-wide/32 v4, -1000000
cmp-long v6, v2, v4
if-ltz v6, :bad
const-string v0, "fixture"
invoke-static {v0}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V
invoke-static {}, Lorg/vinix/bootstrap/Main;->nativeGraphics()Z
move-result v0
if-eqz v0, :bad
invoke-virtual {p0}, Landroid/app/Activity;->getAssets()Landroid/content/res/AssetManager;
move-result-object v0
invoke-static {v0}, Lorg/vinix/bootstrap/Main;->nativeCheck(Landroid/content/res/AssetManager;)Z
move-result v0
if-eqz v0, :bad
invoke-virtual {p0}, Landroid/app/Activity;->getAssets()Landroid/content/res/AssetManager;
move-result-object v0
const-string v1, "probe.webp"
invoke-virtual {v0, v1}, Landroid/content/res/AssetManager;->open(Ljava/lang/String;)Ljava/io/InputStream;
move-result-object v0
invoke-static {v0}, Landroid/graphics/BitmapFactory;->decodeStream(Ljava/io/InputStream;)Landroid/graphics/Bitmap;
move-result-object v1
invoke-virtual {v0}, Ljava/io/InputStream;->close()V
if-eqz v1, :bad
invoke-virtual {v1}, Landroid/graphics/Bitmap;->getWidth()I
move-result v2
const/4 v3, 2
if-ne v2, v3, :bad
invoke-virtual {v1}, Landroid/graphics/Bitmap;->getHeight()I
move-result v2
const/4 v3, 1
if-ne v2, v3, :bad
invoke-static {v1}, Lorg/vinix/bootstrap/Main;->nativeBitmap(Landroid/graphics/Bitmap;)Z
move-result v2
if-eqz v2, :bad
invoke-virtual {v1}, Landroid/graphics/Bitmap;->recycle()V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Application bootstrap and NDK assets passed"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-NDK-PASS order paths clocks is64bit assets rtl webp matrix network bitmap clients graphics-unavailable"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Native clock/ABI/asset regression"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0')
	os.write_file(smali + '/Main.smali', main_class)!
	manifest := '<?xml version="1.0"?><manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap" android:versionCode="1" android:versionName="1"><uses-sdk android:minSdkVersion="23"/><application android:name=".App" android:label="Runtime fixture"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity><provider android:name=".Low" android:authorities="fixture.low" android:initOrder="10"/><provider android:name=".High" android:authorities="fixture.high;fixture.alias" android:initOrder="100"/><provider android:name=".MustNotLoadDisabled" android:authorities="fixture.disabled" android:enabled="false"/><provider android:name=".MustNotLoadOtherProcess" android:authorities="fixture.other" android:process=":other"/></application></manifest>'
	os.write_file(output + '/AndroidManifest.xml', manifest)!
	checked([java, '-cp', tools + '/*', 'org.jf.smali.Main', 'assemble', output + '/smali', '-o', output + '/classes.dex'])
	checked([aapt, 'link', '-I', resources, '--manifest', output + '/AndroidManifest.xml', '-A', output + '/assets', '-o', output + '/unsigned.apk'])
	checked(['build-support/compile-v-module', os.abs_path('tests/native-android-ws/assetprobe'), output + '/assetprobe.c', '--arch', 'arm64'])
	checked(['aarch64-linux-musl-gcc', '-O2', '-fPIC', '-shared', '-nostdlib', '-Wl,-z,max-page-size=65536', output + '/assetprobe.c', '-o', output + '/lib/arm64-v8a/libfixture.so'])
	checked(['zip', '-q', '-j', output + '/unsigned.apk', output + '/classes.dex'])
	// zip's -j would discard the ABI directory. Run in the fixture directory.
	mut zip := os.new_process('zip')
	zip.set_work_folder(output)
	zip.set_args(['-q', 'unsigned.apk', 'lib/arm64-v8a/libfixture.so'])
	zip.run()
	zip.wait()
	assert zip.code == 0
	key := output + '/fixture.p12'
	if !os.is_file(key) {
		checked([os.join_path(os.dir(os.real_path(java)), 'keytool'), '-genkeypair', '-keystore', key,
			'-storetype', 'PKCS12', '-storepass', 'android', '-keypass', 'android', '-alias', 'fixture',
			'-dname', 'CN=Vinix Runtime Fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650'])
	}
	checked([java, '-jar', os.abs_path(os.args[6]), 'sign', '--ks', key, '--ks-key-alias', 'fixture',
		'--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', output + '/bootstrap.apk', output + '/unsigned.apk'])
	println(output + '/bootstrap.apk')
}
