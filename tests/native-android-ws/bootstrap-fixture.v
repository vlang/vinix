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
	os.mkdir_all(output + '/assets/nested')!
	os.write_file(output + '/assets/nested/item.txt', 'nested asset\n')!
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
		'.implements Landroid/widget/CompoundButton$OnCheckedChangeListener;\n.field private changes:I\n.field private static surface:Landroid/view/SurfaceView;\n' +
		constructor('android/app/Activity', 'const/4 v0, 4\ninvoke-static {v0}, Lorg/vinix/bootstrap/App;->check(I)V') +
		method('public onCheckedChanged(Landroid/widget/CompoundButton;Z)V', 'iget v0, p0, Lorg/vinix/bootstrap/Main;->changes:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, Lorg/vinix/bootstrap/Main;->changes:I\nreturn-void') +
		method('private checkWidget()V', '
new-instance v0, Landroid/widget/CheckBox;
invoke-direct {v0, p0}, Landroid/widget/CheckBox;-><init>(Landroid/content/Context;)V
invoke-virtual {v0, p0}, Landroid/widget/CheckBox;->setOnCheckedChangeListener(Landroid/widget/CompoundButton$OnCheckedChangeListener;)V
invoke-virtual {v0}, Landroid/widget/CheckBox;->performClick()Z
invoke-virtual {v0}, Landroid/widget/CheckBox;->isChecked()Z
move-result v1
if-eqz v1, :bad
const/4 v1, 1
invoke-virtual {v0, v1}, Landroid/widget/CheckBox;->setChecked(Z)V
iget v1, p0, Lorg/vinix/bootstrap/Main;->changes:I
const/4 v2, 1
if-ne v1, v2, :bad
invoke-virtual {v0}, Landroid/widget/CheckBox;->performClick()Z
invoke-virtual {v0}, Landroid/widget/CheckBox;->isChecked()Z
move-result v1
if-nez v1, :bad
iget v1, p0, Lorg/vinix/bootstrap/Main;->changes:I
const/4 v2, 2
if-ne v1, v2, :bad
new-instance v0, Landroid/widget/RadioButton;
invoke-direct {v0, p0}, Landroid/widget/RadioButton;-><init>(Landroid/content/Context;)V
invoke-virtual {v0}, Landroid/widget/RadioButton;->performClick()Z
invoke-virtual {v0}, Landroid/widget/RadioButton;->performClick()Z
invoke-virtual {v0}, Landroid/widget/RadioButton;->isChecked()Z
move-result v1
if-eqz v1, :bad
new-instance v0, Landroid/widget/ProgressBar;
invoke-direct {v0, p0}, Landroid/widget/ProgressBar;-><init>(Landroid/content/Context;)V
const/16 v1, 200
invoke-virtual {v0, v1}, Landroid/widget/ProgressBar;->setMax(I)V
const/16 v1, 50
invoke-virtual {v0, v1}, Landroid/widget/ProgressBar;->setProgress(I)V
invoke-virtual {v0}, Landroid/widget/ProgressBar;->getProgress()I
move-result v2
if-ne v1, v2, :bad
const/4 v1, 1
invoke-virtual {v0, v1}, Landroid/widget/ProgressBar;->setIndeterminate(Z)V
invoke-virtual {v0}, Landroid/widget/ProgressBar;->isIndeterminate()Z
move-result v1
if-eqz v1, :bad
const/4 v1, 0
invoke-virtual {v0, v1}, Landroid/widget/ProgressBar;->setIndeterminate(Z)V
invoke-virtual {v0}, Landroid/widget/ProgressBar;->isIndeterminate()Z
move-result v1
if-nez v1, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "CheckBox/RadioButton state, clicks and change callbacks"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
		'.method public static native nativeCheck(Landroid/content/res/AssetManager;)Z\n.end method\n' +
		'.method public static native nativeBitmap(Landroid/graphics/Bitmap;)Z\n.end method\n' +
		'.method public static native nativeGraphics()Z\n.end method\n' +
		'.method public static native nativeWindow(Landroid/view/Surface;)Z\n.end method\n' +
		'.method public static native nativeLibc()Z\n.end method\n' +
		'.method public static native nativeDependency()I\n.end method\n' +
		method('private static timezoneCheck()V', '
invoke-static {}, Ljava/util/TimeZone;->getAvailableIDs()[Ljava/lang/String;
move-result-object v0
array-length v0, v0
const/16 v1, 400
if-lt v0, v1, :bad
const-string v0, "UTC"
invoke-static {v0}, Ljava/util/TimeZone;->getTimeZone(Ljava/lang/String;)Ljava/util/TimeZone;
move-result-object v0
const-wide v1, 1767225600000L
invoke-virtual {v0, v1, v2}, Ljava/util/TimeZone;->getOffset(J)I
move-result v3
if-nez v3, :bad
const-string v0, "America/New_York"
invoke-static {v0}, Ljava/util/TimeZone;->getTimeZone(Ljava/lang/String;)Ljava/util/TimeZone;
move-result-object v0
invoke-virtual {v0, v1, v2}, Ljava/util/TimeZone;->getOffset(J)I
move-result v3
const v4, -18000000
if-ne v3, v4, :bad
const-wide v5, 1782864000000L
invoke-virtual {v0, v5, v6}, Ljava/util/TimeZone;->getOffset(J)I
move-result v3
const v4, -14400000
if-ne v3, v4, :bad
const-string v0, "Australia/Sydney"
invoke-static {v0}, Ljava/util/TimeZone;->getTimeZone(Ljava/lang/String;)Ljava/util/TimeZone;
move-result-object v0
invoke-virtual {v0, v1, v2}, Ljava/util/TimeZone;->getOffset(J)I
move-result v3
const v4, 39600000
if-ne v3, v4, :bad
invoke-virtual {v0, v5, v6}, Ljava/util/TimeZone;->getOffset(J)I
move-result v3
const v4, 36000000
if-ne v3, v4, :bad
const-string v0, "Asia/Kathmandu"
invoke-static {v0}, Ljava/util/TimeZone;->getTimeZone(Ljava/lang/String;)Ljava/util/TimeZone;
move-result-object v0
invoke-virtual {v0, v1, v2}, Ljava/util/TimeZone;->getOffset(J)I
move-result v3
const v4, 20700000
if-ne v3, v4, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-TIMEZONES-PASS utc north-dst south-dst fractional"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "IANA timezone database offsets"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
		method('private static assetListCheck(Landroid/content/Context;)V', '
invoke-virtual {p0}, Landroid/content/Context;->getAssets()Landroid/content/res/AssetManager;
move-result-object v0
const-string v1, ""
invoke-virtual {v0, v1}, Landroid/content/res/AssetManager;->list(Ljava/lang/String;)[Ljava/lang/String;
move-result-object v1
array-length v2, v1
const/4 v3, 3
if-lt v2, v3, :bad
invoke-static {v1}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;
move-result-object v1
const-string v2, "probe.txt"
invoke-interface {v1, v2}, Ljava/util/List;->contains(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
const-string v2, "probe.webp"
invoke-interface {v1, v2}, Ljava/util/List;->contains(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
const-string v2, "nested"
invoke-interface {v1, v2}, Ljava/util/List;->contains(Ljava/lang/Object;)Z
move-result v2
if-eqz v2, :bad
const-string v1, "nested"
invoke-virtual {v0, v1}, Landroid/content/res/AssetManager;->list(Ljava/lang/String;)[Ljava/lang/String;
move-result-object v1
array-length v2, v1
const/4 v3, 1
if-ne v2, v3, :bad
const/4 v2, 0
aget-object v1, v1, v2
const-string v2, "item.txt"
invoke-virtual {v2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad
const-string v1, "absent"
invoke-virtual {v0, v1}, Landroid/content/res/AssetManager;->list(Ljava/lang/String;)[Ljava/lang/String;
move-result-object v1
array-length v1, v1
if-nez v1, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-ASSETS-PASS root nested absent"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "APK asset directory enumeration"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
		method('private static textCheck(Landroid/content/Context;)V', '
const-string v7, "HTML decoded text"
const-string v0, "&#128512; Read <a href=\\\"privacy&amp;policy\\\">Privacy &amp; Policy</a>."
const/4 v1, 0
invoke-static {v0, v1}, Landroid/text/Html;->fromHtml(Ljava/lang/String;I)Landroid/text/Spanned;
move-result-object v0
invoke-virtual {v0}, Ljava/lang/Object;->toString()Ljava/lang/String;
move-result-object v1
const-string v2, "😀 Read Privacy & Policy."
invoke-virtual {v2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad
const-string v7, "HTML URL span count"
const/4 v1, 0
const/16 v2, 25
const-class v3, Landroid/text/style/URLSpan;
invoke-interface {v0, v1, v2, v3}, Landroid/text/Spanned;->getSpans(IILjava/lang/Class;)[Ljava/lang/Object;
move-result-object v1
array-length v2, v1
const/4 v3, 1
if-ne v2, v3, :bad
const-string v7, "HTML URL span UTF-16 start"
const/4 v2, 0
aget-object v1, v1, v2
invoke-interface {v0, v1}, Landroid/text/Spanned;->getSpanStart(Ljava/lang/Object;)I
move-result v2
const/16 v3, 8
if-ne v2, v3, :bad
const-string v7, "HTML URL span UTF-16 end"
invoke-interface {v0, v1}, Landroid/text/Spanned;->getSpanEnd(Ljava/lang/Object;)I
move-result v2
const/16 v3, 24
if-ne v2, v3, :bad
const-string v7, "HTML URL decoded attribute"
check-cast v1, Landroid/text/style/URLSpan;
invoke-virtual {v1}, Landroid/text/style/URLSpan;->getURL()Ljava/lang/String;
move-result-object v1
const-string v2, "privacy&policy"
invoke-virtual {v2, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v1
if-eqz v1, :bad
const-string v7, "TextView multiline measurement"
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "Native widgets wrap long words and sentences across several lines."
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
const/high16 v1, 0x41a00000
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setTextSize(F)V
const v1, 0x40000078
const v2, 0x800003e8
invoke-virtual {v0, v1, v2}, Landroid/view/View;->measure(II)V
invoke-virtual {v0}, Landroid/view/View;->getMeasuredHeight()I
move-result v3
const/16 v4, 35
if-le v3, v4, :bad
const-string v7, "TextView single line measurement"
const/4 v3, 1
invoke-virtual {v0, v3}, Landroid/widget/TextView;->setSingleLine(Z)V
invoke-virtual {v0, v1, v2}, Landroid/view/View;->measure(II)V
invoke-virtual {v0}, Landroid/view/View;->getMeasuredHeight()I
move-result v3
if-gt v3, v4, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, v7}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0') +
		method('private static bitmapCanvasCheck()V', '
const/4 v1, 4
const/4 v2, 4
sget-object v3, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;
invoke-static {v1, v2, v3}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v8
const/4 v1, 0
invoke-virtual {v8, v1}, Landroid/graphics/Bitmap;->eraseColor(I)V
new-instance v9, Landroid/graphics/Canvas;
invoke-direct {v9, v8}, Landroid/graphics/Canvas;-><init>(Landroid/graphics/Bitmap;)V
new-instance v5, Landroid/graphics/Paint;
invoke-direct {v5}, Landroid/graphics/Paint;-><init>()V
const v1, 0xffff0000
invoke-virtual {v5, v1}, Landroid/graphics/Paint;->setColor(I)V
move-object v0, v9
const v1, 0x3f800000
const v2, 0x3f800000
const v3, 0x40400000
const v4, 0x40400000
invoke-virtual/range {v0 .. v5}, Landroid/graphics/Canvas;->drawRect(FFFFLandroid/graphics/Paint;)V
invoke-virtual {v9}, Landroid/graphics/Canvas;->save()I
const v1, 0x3f800000
const v2, 0x3f800000
invoke-virtual {v9, v1, v2}, Landroid/graphics/Canvas;->translate(FF)V
const v1, 0xff0000ff
invoke-virtual {v5, v1}, Landroid/graphics/Paint;->setColor(I)V
const/4 v1, 0
const/4 v2, 0
const v3, 0x3f800000
const v4, 0x3f800000
invoke-virtual/range {v0 .. v5}, Landroid/graphics/Canvas;->drawRect(FFFFLandroid/graphics/Paint;)V
invoke-virtual {v9}, Landroid/graphics/Canvas;->restore()V
const/4 v1, 4
const/4 v2, 4
sget-object v3, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;
invoke-static {v1, v2, v3}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v7
const v1, 0x7f00ff00
invoke-virtual {v7, v1}, Landroid/graphics/Bitmap;->eraseColor(I)V
new-instance v0, Landroid/graphics/Canvas;
invoke-direct {v0, v7}, Landroid/graphics/Canvas;-><init>(Landroid/graphics/Bitmap;)V
const/4 v1, 0
const/4 v2, 0
const v3, 0x3f800000
const v4, 0x3f800000
invoke-virtual/range {v0 .. v5}, Landroid/graphics/Canvas;->drawRect(FFFFLandroid/graphics/Paint;)V
move-object v0, v7
const/16 v1, 16
new-array v1, v1, [I
const/4 v2, 0
const/4 v3, 4
const/4 v4, 0
const/4 v5, 0
const/4 v6, 4
const/4 v7, 4
invoke-virtual/range {v0 .. v7}, Landroid/graphics/Bitmap;->getPixels([IIIIIII)V
const/4 v2, 0
aget v2, v1, v2
const v3, 0xff0000ff
if-ne v2, v3, :bad
const/16 v2, 15
aget v2, v1, v2
const v3, 0x7f00ff00
if-ne v2, v3, :bad
new-instance v5, Landroid/graphics/Paint;
invoke-direct {v5}, Landroid/graphics/Paint;-><init>()V
const v1, 0xff00ff00
invoke-virtual {v5, v1}, Landroid/graphics/Paint;->setColor(I)V
move-object v0, v9
const/4 v1, 0
const/4 v2, 0
const v3, 0x3f800000
const v4, 0x3f800000
invoke-virtual/range {v0 .. v5}, Landroid/graphics/Canvas;->drawRect(FFFFLandroid/graphics/Paint;)V
move-object v0, v8
const/16 v1, 16
new-array v1, v1, [I
const/4 v2, 0
const/4 v3, 4
const/4 v4, 0
const/4 v5, 0
const/4 v6, 4
const/4 v7, 4
invoke-virtual/range {v0 .. v7}, Landroid/graphics/Bitmap;->getPixels([IIIIIII)V
const/4 v2, 0
aget v2, v1, v2
const v3, 0xff00ff00
if-ne v2, v3, :bad
const/4 v2, 5
aget v2, v1, v2
const v3, 0xff0000ff
if-ne v2, v3, :bad
const/4 v2, 6
aget v2, v1, v2
const v3, 0xffff0000
if-ne v2, v3, :bad
const/16 v2, 15
aget v2, v1, v2
if-nez v2, :bad
invoke-virtual {v8}, Landroid/graphics/Bitmap;->recycle()V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Bitmap Canvas pixels, alpha, save/restore or target isolation"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0').replace('.locals 8', '.locals 10') +
		method('protected onCreate(Landroid/os/Bundle;)V', '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
const-string v0, "bootstrap-async"
const/16 v1, 42
invoke-static {v0, v1}, Landroid/os/Trace;->beginAsyncSection(Ljava/lang/String;I)V
invoke-static {v0, v1}, Landroid/os/Trace;->endAsyncSection(Ljava/lang/String;I)V
invoke-static {}, Landroid/os/Trace;->isEnabled()Z
move-result v0
if-nez v0, :bad
const/4 v0, -1
invoke-static {v0}, Landroid/os/Process;->isApplicationUid(I)Z
move-result v0
if-nez v0, :bad
const/4 v0, 0
invoke-static {v0}, Landroid/os/Process;->isApplicationUid(I)Z
move-result v0
if-nez v0, :bad
const/16 v0, 9999
invoke-static {v0}, Landroid/os/Process;->isApplicationUid(I)Z
move-result v0
if-nez v0, :bad
const/16 v0, 10000
invoke-static {v0}, Landroid/os/Process;->isApplicationUid(I)Z
move-result v0
if-eqz v0, :bad
const/16 v0, 19999
invoke-static {v0}, Landroid/os/Process;->isApplicationUid(I)Z
move-result v0
if-eqz v0, :bad
const/16 v0, 20000
invoke-static {v0}, Landroid/os/Process;->isApplicationUid(I)Z
move-result v0
if-nez v0, :bad
const v0, 110000
invoke-static {v0}, Landroid/os/Process;->isApplicationUid(I)Z
move-result v0
if-eqz v0, :bad
const v0, 120000
invoke-static {v0}, Landroid/os/UserHandle;->isApp(I)Z
move-result v0
if-nez v0, :bad
invoke-static {}, Landroid/os/Process;->is64Bit()Z
move-result v0
if-eqz v0, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-API-PASS async-trace application-uids"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-static {p0}, Lorg/vinix/bootstrap/Main;->assetListCheck(Landroid/content/Context;)V
invoke-static {}, Lorg/vinix/bootstrap/Main;->timezoneCheck()V
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
:missing_dependency_begin
const-string v0, "fixture-broken"
invoke-static {v0}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V
:missing_dependency_end
.catch Ljava/lang/UnsatisfiedLinkError; {:missing_dependency_begin .. :missing_dependency_end} :missing_dependency_rejected
goto :bad
:missing_dependency_rejected
move-exception v0
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-MISSING-DEPENDENCY-PASS rejected"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
const-string v0, "fixture"
invoke-static {v0}, Ljava/lang/System;->loadLibrary(Ljava/lang/String;)V
invoke-static {}, Lorg/vinix/bootstrap/Main;->nativeDependency()I
move-result v0
const/16 v1, 0x5744
if-ne v0, v1, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-DEPENDENCIES-PASS jni-through-needed"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-static {}, Lorg/vinix/bootstrap/Main;->nativeGraphics()Z
move-result v0
if-eqz v0, :bad
invoke-static {}, Lorg/vinix/bootstrap/Main;->nativeLibc()Z
move-result v0
if-eqz v0, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-LIBC-PASS pread checked-offset short-read api-level allocator-options shared-memory"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
new-instance v0, Landroid/view/SurfaceView;
invoke-direct {v0, p0}, Landroid/view/SurfaceView;-><init>(Landroid/content/Context;)V
sput-object v0, Lorg/vinix/bootstrap/Main;->surface:Landroid/view/SurfaceView;
const/4 v1, 0
const/16 v2, 32
const/16 v3, 24
invoke-virtual {v0, v1, v1, v2, v3}, Landroid/view/View;->layout(IIII)V
invoke-virtual {v0}, Landroid/view/SurfaceView;->getHolder()Landroid/view/SurfaceHolder;
move-result-object v0
invoke-interface {v0}, Landroid/view/SurfaceHolder;->getSurface()Landroid/view/Surface;
move-result-object v0
invoke-static {v0}, Lorg/vinix/bootstrap/Main;->nativeWindow(Landroid/view/Surface;)Z
move-result v0
if-eqz v0, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-NATIVE-WINDOW-PASS geometry cpu-post hardware-buffer refs"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-static {}, Lorg/vinix/bootstrap/Main;->bitmapCanvasCheck()V
invoke-static {p0}, Lorg/vinix/bootstrap/Main;->textCheck(Landroid/content/Context;)V
invoke-direct {p0}, Lorg/vinix/bootstrap/Main;->checkWidget()V
new-instance v0, Landroid/app/Notification$Builder;
invoke-direct {v0, p0}, Landroid/app/Notification$Builder;-><init>(Landroid/content/Context;)V
const-string v1, "Vinix Android runtime"
invoke-virtual {v0, v1}, Landroid/app/Notification$Builder;->setContentTitle(Ljava/lang/CharSequence;)Landroid/app/Notification$Builder;
const-string v1, "Native WS notification probe"
invoke-virtual {v0, v1}, Landroid/app/Notification$Builder;->setContentText(Ljava/lang/CharSequence;)Landroid/app/Notification$Builder;
invoke-virtual {v0}, Landroid/app/Notification$Builder;->build()Landroid/app/Notification;
move-result-object v1
const-string v0, "notification"
invoke-virtual {p0, v0}, Landroid/app/Activity;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/app/NotificationManager;
const/16 v2, 42
invoke-virtual {v0, v2, v1}, Landroid/app/NotificationManager;->notify(ILandroid/app/Notification;)V
invoke-virtual {v0, v2}, Landroid/app/NotificationManager;->cancel(I)V
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
new-instance v2, Landroid/widget/LinearLayout;
invoke-direct {v2, p0}, Landroid/widget/LinearLayout;-><init>(Landroid/content/Context;)V
const/4 v1, 1
invoke-virtual {v2, v1}, Landroid/widget/LinearLayout;->setOrientation(I)V
invoke-virtual {v2, v0}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V
sget-object v0, Lorg/vinix/bootstrap/Main;->surface:Landroid/view/SurfaceView;
new-instance v3, Landroid/view/ViewGroup$LayoutParams;
const/4 v4, -1
const/16 v5, 96
invoke-direct {v3, v4, v5}, Landroid/view/ViewGroup$LayoutParams;-><init>(II)V
invoke-virtual {v2, v0, v3}, Landroid/view/ViewGroup;->addView(Landroid/view/View;Landroid/view/ViewGroup$LayoutParams;)V
invoke-virtual {p0, v2}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-NDK-PASS order paths clocks is64bit assets rtl webp matrix network bitmap clients graphics-unavailable bitmap-canvas notifications-queued"
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
	checked(['build-support/compile-v-module', os.abs_path('tests/native-android-ws/dependencyprobe'), output + '/dependencyprobe.c', '--arch', 'arm64'])
	checked(['aarch64-linux-musl-gcc', '-O2', '-fPIC', '-shared', '-nostdlib', '-Wl,-z,max-page-size=4096',
		'-Wl,-soname,libfixture-dependency.so', output + '/dependencyprobe.c', '-o', output + '/lib/arm64-v8a/libfixture-dependency.so'])
	// Link against a dependency deliberately excluded from the APK. Loading
	// this parent must fail even though its own JNI exports could be resolved.
	checked(['aarch64-linux-musl-gcc', '-O2', '-fPIC', '-shared', '-nostdlib', '-Wl,-z,max-page-size=4096',
		'-Wl,-soname,libfixture-absent.so', output + '/dependencyprobe.c', '-o', output + '/libfixture-absent.so'])
	checked(['aarch64-linux-musl-gcc', '-O2', '-fPIC', '-shared', '-nostdlib', '-Wl,-z,max-page-size=4096',
		output + '/assetprobe.c', '-Wl,--no-as-needed', '-L' + output, '-lfixture-absent',
		'-o', output + '/lib/arm64-v8a/libfixture-broken.so'])
	// Exercise the legacy NDK mapping path on a real 16 KiB Vinix guest as
	// well as the Java framework APIs. This ELF intentionally uses 4 KiB pages.
	checked(['aarch64-linux-musl-gcc', '-O2', '-fPIC', '-shared', '-nostdlib', '-Wl,-z,max-page-size=4096',
		'-Wl,-z,common-page-size=4096', output + '/assetprobe.c', '-Wl,--no-as-needed', '-L' + output + '/lib/arm64-v8a',
		'-lfixture-dependency', '-o', output + '/lib/arm64-v8a/libfixture.so'])
	checked(['zip', '-q', '-j', output + '/unsigned.apk', output + '/classes.dex'])
	// zip's -j would discard the ABI directory. Run in the fixture directory.
	mut zip := os.new_process('zip')
	zip.set_work_folder(output)
	zip.set_args(['-q', 'unsigned.apk', 'lib/arm64-v8a/libfixture.so', 'lib/arm64-v8a/libfixture-dependency.so',
		'lib/arm64-v8a/libfixture-broken.so'])
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
