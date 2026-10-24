// SPDX-License-Identifier: GPL-2.0-or-later
// Same-APK guest regression for default, removed, and custom button indicators.
module main

import crypto.sha256
import os

fn checked(args []string) {
	r := os.exec(args)
	assert r.exit_code == 0, r.output
}

fn main() {
	if os.args.len != 2 { panic('OUTPUT') }
	out := os.abs_path(os.args[1])
	root := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(root)!
	os.write_file(out + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="23" android:targetSdkVersion="35"/><application android:label="CompoundButton fixture"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
	os.write_file(root + '/Main.smali', r'.class public Lorg/vinix/bootstrap/Main;
.super Landroid/app/Activity;
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Landroid/app/Activity;-><init>()V
return-void
.end method
.method public onCreate(Landroid/os/Bundle;)V
.locals 2
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
new-instance v0, Landroid/widget/TextView;
invoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
const-string v1, "CompoundButton drawable fixture"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
invoke-static {p0}, Lorg/vinix/bootstrap/IndicatorProbe;->run(Landroid/content/Context;)V
const-string v0, "BOOTSTRAP-COMPOUND-BUTTON-PASS"
const-string v1, "default checkbox and radio; explicit null; custom Canvas pixels; restoration; resource zero; subclass; negative intrinsic bounds"
invoke-static {v0, v1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
const-string v0, "BOOTSTRAP-READY"
invoke-static {v0, v1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
return-void
.end method
')!
	os.write_file(root + '/Chip.smali', r'.class public Lorg/vinix/bootstrap/Chip;
.super Landroid/widget/CheckBox;
.method public constructor <init>(Landroid/content/Context;)V
.locals 1
invoke-direct {p0, p1}, Landroid/widget/CheckBox;-><init>(Landroid/content/Context;)V
const/4 v0, 0
invoke-virtual {p0, v0}, Landroid/widget/CompoundButton;->setButtonDrawable(Landroid/graphics/drawable/Drawable;)V
return-void
.end method
')!
	os.write_file(root + '/Indicator.smali', indicator())!
	os.write_file(root + '/IndicatorProbe.smali', probe())!
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	resources := '/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/framework-res.apk'
	for name in ['classes.dex', 'unsigned.apk', 'probe.apk'] {
		if os.is_file(out + '/' + name) { os.rm(out + '/' + name)! }
	}
	checked([os.abs_path('build/android-native-ws/aapt2'), 'link', '-I', resources, '--manifest', out + '/AndroidManifest.xml', '-o', out + '/unsigned.apk'])
	checked([java, '-cp', os.abs_path('build/android-framework/tools') + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali', '-o', out + '/classes.dex'])
	checked(['zip', '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'])
	key := out + '/fixture.p12'
	if !os.is_file(key) {
		checked(['/opt/homebrew/opt/openjdk@25/bin/keytool', '-genkeypair', '-keystore', key, '-storetype', 'PKCS12', '-alias', 'fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650', '-dname', 'CN=Vinix CompoundButton fixture', '-storepass', 'android', '-keypass', 'android'])
	}
	checked([java, '-jar', os.abs_path('build/android-native-ws/android-15/lib/apksigner.jar'), 'sign', '--ks', key, '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'])
	println('COMPOUND-BUTTON-APK ' + sha256.sum(os.read_bytes(out + '/probe.apk')!).hex())
}

fn indicator() string {
	return r'.class public Lorg/vinix/bootstrap/Indicator;
.super Landroid/graphics/drawable/Drawable;
.field public width:I
.field public height:I
.field public calls:I
.method public constructor <init>(II)V
.locals 0
invoke-direct {p0}, Landroid/graphics/drawable/Drawable;-><init>()V
iput p1, p0, Lorg/vinix/bootstrap/Indicator;->width:I
iput p2, p0, Lorg/vinix/bootstrap/Indicator;->height:I
return-void
.end method
.method public getIntrinsicWidth()I
.locals 1
iget v0, p0, Lorg/vinix/bootstrap/Indicator;->width:I
return v0
.end method
.method public getIntrinsicHeight()I
.locals 1
iget v0, p0, Lorg/vinix/bootstrap/Indicator;->height:I
return v0
.end method
.method public draw(Landroid/graphics/Canvas;)V
.locals 6
iget v0, p0, Lorg/vinix/bootstrap/Indicator;->calls:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/Indicator;->calls:I
invoke-virtual {p0}, Landroid/graphics/drawable/Drawable;->getBounds()Landroid/graphics/Rect;
move-result-object v0
iget v1, v0, Landroid/graphics/Rect;->left:I
if-nez v1, :bad
iget v1, v0, Landroid/graphics/Rect;->top:I
if-nez v1, :bad
iget v1, v0, Landroid/graphics/Rect;->right:I
iget v2, p0, Lorg/vinix/bootstrap/Indicator;->width:I
if-ne v1, v2, :bad
iget v1, v0, Landroid/graphics/Rect;->bottom:I
iget v2, p0, Lorg/vinix/bootstrap/Indicator;->height:I
if-ne v1, v2, :bad
new-instance v5, Landroid/graphics/Paint;
invoke-direct {v5}, Landroid/graphics/Paint;-><init>()V
const v1, 0xffff00ff
invoke-virtual {v5, v1}, Landroid/graphics/Paint;->setColor(I)V
move-object v0, p1
const/4 v1, 0
const/4 v2, 0
iget v3, p0, Lorg/vinix/bootstrap/Indicator;->width:I
int-to-float v3, v3
iget v4, p0, Lorg/vinix/bootstrap/Indicator;->height:I
int-to-float v4, v4
invoke-virtual/range {v0 .. v5}, Landroid/graphics/Canvas;->drawRect(FFFFLandroid/graphics/Paint;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "custom button drawable bounds"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.end method
.method public setAlpha(I)V
.locals 0
return-void
.end method
.method public setColorFilter(Landroid/graphics/ColorFilter;)V
.locals 0
return-void
.end method
.method public getOpacity()I
.locals 1
const/4 v0, -1
return v0
.end method
'
}

fn probe() string {
	return r'.class public Lorg/vinix/bootstrap/IndicatorProbe;
.super Ljava/lang/Object;
.method public static run(Landroid/content/Context;)V
.locals 6
new-instance v0, Landroid/widget/CheckBox;
invoke-direct {v0, p0}, Landroid/widget/CheckBox;-><init>(Landroid/content/Context;)V
const/16 v1, 36
const v2, 0xff66736c
invoke-static {v0, v1, v2}, Lorg/vinix/bootstrap/IndicatorProbe;->verify(Landroid/view/View;II)V
new-instance v3, Landroid/widget/RadioButton;
invoke-direct {v3, p0}, Landroid/widget/RadioButton;-><init>(Landroid/content/Context;)V
invoke-static {v3, v1, v2}, Lorg/vinix/bootstrap/IndicatorProbe;->verify(Landroid/view/View;II)V
const-string v4, "BOOTSTRAP-COMPOUND-BUTTON-DEFAULTS-PASS"
const-string v5, "default checkbox and radio widths and pixels"
invoke-static {v4, v5}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
const/4 v1, 0
invoke-virtual {v0, v1}, Landroid/widget/CompoundButton;->setButtonDrawable(Landroid/graphics/drawable/Drawable;)V
const/4 v1, 6
const/4 v2, 0
invoke-static {v0, v1, v2}, Lorg/vinix/bootstrap/IndicatorProbe;->verify(Landroid/view/View;II)V
const-string v4, "BOOTSTRAP-COMPOUND-BUTTON-NULL-PASS"
const-string v5, "explicit null removes indicator and reserved width"
invoke-static {v4, v5}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
new-instance v3, Lorg/vinix/bootstrap/Indicator;
const/16 v1, 12
const/16 v2, 18
invoke-direct {v3, v1, v2}, Lorg/vinix/bootstrap/Indicator;-><init>(II)V
invoke-virtual {v0, v3}, Landroid/widget/CompoundButton;->setButtonDrawable(Landroid/graphics/drawable/Drawable;)V
invoke-virtual {v0}, Landroid/widget/CompoundButton;->getButtonDrawable()Landroid/graphics/drawable/Drawable;
move-result-object v1
if-ne v1, v3, :bad
const/16 v1, 30
const v2, 0xffff00ff
invoke-static {v0, v1, v2}, Lorg/vinix/bootstrap/IndicatorProbe;->verify(Landroid/view/View;II)V
iget v1, v3, Lorg/vinix/bootstrap/Indicator;->calls:I
const/4 v2, 1
if-ne v1, v2, :bad
const/4 v1, 0
invoke-virtual {v0, v1}, Landroid/widget/CompoundButton;->setButtonDrawable(I)V
const/4 v1, 6
const/4 v2, 0
invoke-static {v0, v1, v2}, Lorg/vinix/bootstrap/IndicatorProbe;->verify(Landroid/view/View;II)V
invoke-virtual {v0, v3}, Landroid/widget/CompoundButton;->setButtonDrawable(Landroid/graphics/drawable/Drawable;)V
const/16 v1, 30
const v2, 0xffff00ff
invoke-static {v0, v1, v2}, Lorg/vinix/bootstrap/IndicatorProbe;->verify(Landroid/view/View;II)V
iget v1, v3, Lorg/vinix/bootstrap/Indicator;->calls:I
const/4 v2, 2
if-ne v1, v2, :bad
new-instance v3, Lorg/vinix/bootstrap/Indicator;
const/4 v1, -1
invoke-direct {v3, v1, v1}, Lorg/vinix/bootstrap/Indicator;-><init>(II)V
invoke-virtual {v0, v3}, Landroid/widget/CompoundButton;->setButtonDrawable(Landroid/graphics/drawable/Drawable;)V
const/4 v1, 6
const/4 v2, 0
invoke-static {v0, v1, v2}, Lorg/vinix/bootstrap/IndicatorProbe;->verify(Landroid/view/View;II)V
iget v1, v3, Lorg/vinix/bootstrap/Indicator;->calls:I
if-nez v1, :bad
new-instance v0, Lorg/vinix/bootstrap/Chip;
invoke-direct {v0, p0}, Lorg/vinix/bootstrap/Chip;-><init>(Landroid/content/Context;)V
const/4 v1, 6
const/4 v2, 0
invoke-static {v0, v1, v2}, Lorg/vinix/bootstrap/IndicatorProbe;->verify(Landroid/view/View;II)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "CompoundButton drawable identity or callback count"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.end method
.method private static verify(Landroid/view/View;II)V
.locals 10
const/4 v0, 0
invoke-virtual {p0, v0, v0, v0, v0}, Landroid/view/View;->setPadding(IIII)V
invoke-virtual {p0, v0}, Landroid/view/View;->setMinimumWidth(I)V
invoke-virtual {p0, v0}, Landroid/view/View;->setMinimumHeight(I)V
invoke-virtual {p0, v0}, Landroid/view/View;->setBackgroundColor(I)V
invoke-virtual {p0, v0, v0}, Landroid/view/View;->measure(II)V
invoke-virtual {p0}, Landroid/view/View;->getMeasuredWidth()I
move-result v1
if-ne v1, p1, :bad
const/16 v2, 100
const/16 v3, 40
invoke-virtual {p0, v0, v0, v2, v3}, Landroid/view/View;->layout(IIII)V
sget-object v4, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;
invoke-static {v2, v3, v4}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v8
invoke-virtual {v8, v0}, Landroid/graphics/Bitmap;->eraseColor(I)V
new-instance v9, Landroid/graphics/Canvas;
invoke-direct {v9, v8}, Landroid/graphics/Canvas;-><init>(Landroid/graphics/Bitmap;)V
invoke-virtual {p0, v9}, Landroid/view/View;->draw(Landroid/graphics/Canvas;)V
const/4 v0, 1
new-array v1, v0, [I
move-object v0, v8
const/4 v2, 0
const/4 v3, 1
const/4 v4, 3
const/16 v5, 11
const/4 v6, 1
const/4 v7, 1
invoke-virtual/range {v0 .. v7}, Landroid/graphics/Bitmap;->getPixels([IIIIIII)V
const/4 v0, 0
aget v1, v1, v0
if-ne v1, p2, :bad
invoke-virtual {v8}, Landroid/graphics/Bitmap;->recycle()V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "CompoundButton measured width or bitmap indicator pixel"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.end method
'
}
