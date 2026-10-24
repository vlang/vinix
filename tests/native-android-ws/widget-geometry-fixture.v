// SPDX-License-Identifier: GPL-2.0-or-later
// Same-APK guest regression for native text padding and height constraints.
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
 os.mkdir_all(out + '/res/values')!
 os.write_file(out + '/res/values/styles.xml', '<resources><style name="NeutralButton" parent="android:style/Widget"/></resources>')!
 os.write_file(out + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="23" android:targetSdkVersion="35"/><application android:label="Widget geometry fixture"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
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
const-string v1, "Widget geometry fixture"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
invoke-static {p0}, Lorg/vinix/bootstrap/GeometryProbe;->run(Landroid/content/Context;)V
const-string v0, "BOOTSTRAP-WIDGET-GEOMETRY-PASS"
const-string v1, "relative padding; Canvas offsets; inherited RTL; pixel/line/View minima; measure specs"
invoke-static {v0, v1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
const-string v0, "BOOTSTRAP-READY"
invoke-static {v0, v1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
return-void
.end method
')!
 os.write_file(root + '/MeasuredText.smali', r'.class public Lorg/vinix/bootstrap/MeasuredText;
.super Landroid/widget/TextView;
.field public measures:I
.method public constructor <init>(Landroid/content/Context;)V
.locals 0
invoke-direct {p0, p1}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V
return-void
.end method
.method protected onMeasure(II)V
.locals 1
iget v0, p0, Lorg/vinix/bootstrap/MeasuredText;->measures:I
add-int/lit8 v0, v0, 1
iput v0, p0, Lorg/vinix/bootstrap/MeasuredText;->measures:I
invoke-super {p0, p1, p2}, Landroid/widget/TextView;->onMeasure(II)V
return-void
.end method
')!
 java := '/opt/homebrew/opt/openjdk@25/bin/java'
	resources := '/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/framework-res.apk'
	for name in ['classes.dex', 'unsigned.apk', 'probe.apk', 'resources.zip'] {
		if os.is_file(out + '/' + name) { os.rm(out + '/' + name)! }
	}
	checked([os.abs_path('build/android-native-ws/aapt2'), 'compile', '--dir', out + '/res', '-o', out + '/resources.zip'])
	checked([os.abs_path('build/android-native-ws/aapt2'), 'link', '-I', resources, '--manifest', out + '/AndroidManifest.xml', '--output-text-symbols', out + '/R.txt', '-o', out + '/unsigned.apk', out + '/resources.zip'])
	mut ids := map[string]string{}
	for line in os.read_lines(out + '/R.txt')! {
		parts := line.fields()
		if parts.len == 4 && parts[0] == 'int' { ids[parts[1] + '/' + parts[2]] = parts[3] }
	}
	os.write_file(root + '/GeometryProbe.smali', probe().replace('@NEUTRAL@', ids['style/NeutralButton']!))!
	checked([java, '-cp', os.abs_path('build/android-framework/tools') + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali', '-o', out + '/classes.dex'])
	assert os.is_file(out + '/classes.dex'), 'smali did not produce DEX'
	checked(['zip', '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'])
	key := out + '/fixture.p12'
	if !os.is_file(key) {
		checked(['/opt/homebrew/opt/openjdk@25/bin/keytool', '-genkeypair', '-keystore', key, '-storetype', 'PKCS12', '-alias', 'fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650', '-dname', 'CN=Vinix Widget geometry fixture', '-storepass', 'android', '-keypass', 'android'])
	}
	checked([java, '-jar', os.abs_path('build/android-native-ws/android-15/lib/apksigner.jar'), 'sign', '--ks', key, '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'])
	println('WIDGET-GEOMETRY-APK ' + sha256.sum(os.read_bytes(out + '/probe.apk')!).hex())
}

fn method(signature string, body string) string {
 return '.method ' + signature + '\n.locals 10\n' + body + '\n.end method\n'
}

fn eq(actual string, expected string, label string) string {
 return 'const-string v9, "' + label + '"\ninvoke-static {' + actual + ', ' + expected + ', v9}, Lorg/vinix/bootstrap/GeometryProbe;->equal(IILjava/lang/String;)V\n'
}

fn getter(name string, expected int) string {
 return 'invoke-virtual {v0}, Landroid/view/View;->' + name + '()I\nmove-result v1\nconst v2, ' + expected.str() + '\n' + eq('v1', 'v2', name)
}

fn height(expected int, spec string) string {
 return 'const v1, ' + spec + '\ninvoke-static {v0, v1}, Lorg/vinix/bootstrap/GeometryProbe;->height(Landroid/view/View;I)I\nmove-result v1\nconst v2, ' + expected.str() + '\n' + eq('v1', 'v2', 'measured height')
}

fn min_getter(name string, expected int) string {
 return 'invoke-virtual {v0}, Landroid/widget/TextView;->' + name + '()I\nmove-result v1\nconst v2, ' + expected.str() + '\n' + eq('v1', 'v2', name)
}

fn set_int(owner string, name string, value int) string {
 return 'const v1, ' + value.str() + '\ninvoke-virtual {v0, v1}, Landroid/' + owner + ';->' + name + '(I)V\n'
}

fn marker(name string) string {
 return 'const-string v1, "BOOTSTRAP-' + name + '-PASS"\nconst-string v2, "actual measured dimensions and Canvas geometry"\ninvoke-static {v1, v2}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I\n'
}

fn probe() string {
 mut s := '.class public Lorg/vinix/bootstrap/GeometryProbe;\n.super Ljava/lang/Object;\n'
 s += method('public static run(Landroid/content/Context;)V', 'invoke-static {p0}, Lorg/vinix/bootstrap/GeometryProbe;->padding(Landroid/content/Context;)V\ninvoke-static {p0}, Lorg/vinix/bootstrap/GeometryProbe;->chip(Landroid/content/Context;)V\ninvoke-static {p0}, Lorg/vinix/bootstrap/GeometryProbe;->minimum(Landroid/content/Context;)V\nreturn-void')
 s += method('private static configure(Landroid/widget/TextView;)V', r'
const-string v1, "H"
invoke-virtual {p0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
const v1, 0xffff00ff
invoke-virtual {p0, v1}, Landroid/widget/TextView;->setTextColor(I)V
const v1, 0x41400000
invoke-virtual {p0, v1}, Landroid/widget/TextView;->setTextSize(F)V
const/16 v1, 0x33
invoke-virtual {p0, v1}, Landroid/widget/TextView;->setGravity(I)V
const/4 v1, 0
invoke-virtual {p0, v1, v1, v1, v1}, Landroid/view/View;->setPadding(IIII)V
invoke-virtual {p0, v1}, Landroid/view/View;->setMinimumHeight(I)V
invoke-virtual {p0, v1}, Landroid/view/View;->setMinimumWidth(I)V
invoke-virtual {p0, v1}, Landroid/view/View;->setBackgroundColor(I)V
return-void')
 s += method('private static height(Landroid/view/View;I)I', 'const/4 v0, 0\ninvoke-virtual {p0, v0, p1}, Landroid/view/View;->measure(II)V\ninvoke-virtual {p0}, Landroid/view/View;->getMeasuredHeight()I\nmove-result v0\nreturn v0')
 s += assertion() + ink() + padding_probe() + chip_probe() + minimum_probe()
 return s
}

fn assertion() string {
 return r'.method private static equal(IILjava/lang/String;)V
.locals 2
if-eq p0, p1, :ok
new-instance v0, Ljava/lang/StringBuilder;
const-string v1, "Widget geometry: "
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
return-void
.end method
'
}

fn ink() string {
 return r'.method private static ink(Landroid/view/View;)I
.locals 12
const/16 v1, 240
const/16 v2, 120
sget-object v3, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;
invoke-static {v1, v2, v3}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v8
const/4 v0, 0
invoke-virtual {v8, v0}, Landroid/graphics/Bitmap;->eraseColor(I)V
new-instance v9, Landroid/graphics/Canvas;
invoke-direct {v9, v8}, Landroid/graphics/Canvas;-><init>(Landroid/graphics/Bitmap;)V
invoke-virtual {p0, v9}, Landroid/view/View;->draw(Landroid/graphics/Canvas;)V
const/16 v0, 28800
new-array v10, v0, [I
move-object v0, v8
move-object v1, v10
const/4 v2, 0
const/16 v3, 240
const/4 v4, 0
const/4 v5, 0
const/16 v6, 240
const/16 v7, 120
invoke-virtual/range {v0 .. v7}, Landroid/graphics/Bitmap;->getPixels([IIIIIII)V
const/4 v0, 0
const/16 v1, 240
const v2, 0xffffff
const v3, 0xff00ff
:scan
array-length v4, v10
if-ge v0, v4, :done
aget v4, v10, v0
and-int/2addr v4, v2
if-ne v4, v3, :next
rem-int/lit16 v4, v0, 240
if-ge v4, v1, :next
move v1, v4
:next
add-int/lit8 v0, v0, 1
goto :scan
:done
invoke-virtual {v8}, Landroid/graphics/Bitmap;->recycle()V
const/16 v2, 239
const-string v3, "nonempty Canvas text ink"
if-le v1, v2, :return
const/4 v2, -1
invoke-static {v1, v2, v3}, Lorg/vinix/bootstrap/GeometryProbe;->equal(IILjava/lang/String;)V
:return
return v1
.end method
'
}

fn layout() string {
 return 'const/4 v1, 0\nconst/16 v2, 240\nconst/16 v3, 120\ninvoke-virtual {v0, v1, v1, v2, v3}, Landroid/view/View;->layout(IIII)V\n'
}

fn relative() string {
 return 'const/16 v1, 11\nconst/4 v2, 3\nconst/16 v3, 29\nconst/4 v4, 5\ninvoke-virtual {v0, v1, v2, v3, v4}, Landroid/view/View;->setPaddingRelative(IIII)V\n'
}

fn padding_probe() string {
 mut b := 'new-instance v0, Lorg/vinix/bootstrap/MeasuredText;\ninvoke-direct {v0, p0}, Lorg/vinix/bootstrap/MeasuredText;-><init>(Landroid/content/Context;)V\ninvoke-static {v0}, Lorg/vinix/bootstrap/GeometryProbe;->configure(Landroid/widget/TextView;)V\n'
 b += layout() + 'const/4 v1, 0\ninvoke-virtual {v0, v1, v1}, Landroid/view/View;->measure(II)V\ninvoke-virtual {v0}, Landroid/view/View;->getMeasuredWidth()I\nmove-result v6\ninvoke-static {v0}, Lorg/vinix/bootstrap/GeometryProbe;->ink(Landroid/view/View;)I\nmove-result v7\n'
 b += relative() + 'const/4 v1, 0\ninvoke-virtual {v0, v1, v1}, Landroid/view/View;->measure(II)V\ninvoke-virtual {v0}, Landroid/view/View;->getMeasuredWidth()I\nmove-result v1\nadd-int/lit8 v2, v6, 40\n' + eq('v1', 'v2', 'relative padding measured width')
 b += 'invoke-static {v0}, Lorg/vinix/bootstrap/GeometryProbe;->ink(Landroid/view/View;)I\nmove-result v1\nadd-int/lit8 v2, v7, 11\n' + eq('v1', 'v2', 'LTR native Canvas offset')
 b += getter('getPaddingLeft', 11) + getter('getPaddingRight', 29) + getter('getPaddingTop', 3) + getter('getPaddingBottom', 5) + getter('getPaddingStart', 11) + getter('getPaddingEnd', 29)
 b += 'invoke-virtual {v0}, Landroid/view/View;->isPaddingRelative()Z\nmove-result v1\nconst/4 v2, 1\n' + eq('v1', 'v2', 'relative flag')
 b += set_int('view/View', 'setLayoutDirection', 1) + 'invoke-static {v0}, Lorg/vinix/bootstrap/GeometryProbe;->ink(Landroid/view/View;)I\nmove-result v1\nadd-int/lit8 v2, v7, 29\n' + eq('v1', 'v2', 'draw resolves own RTL before measurement')
 b += getter('getPaddingLeft', 29) + getter('getPaddingRight', 11) + getter('getPaddingStart', 11) + getter('getPaddingEnd', 29)
 b += 'new-instance v8, Landroid/widget/FrameLayout;\ninvoke-direct {v8, p0}, Landroid/widget/FrameLayout;-><init>(Landroid/content/Context;)V\nconst/4 v1, 1\ninvoke-virtual {v8, v1}, Landroid/view/View;->setLayoutDirection(I)V\ninvoke-virtual {v8, v0}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V\n' + set_int('view/View', 'setLayoutDirection', 2)
 b += 'const/4 v1, 0\ninvoke-virtual {v0, v1, v1}, Landroid/view/View;->measure(II)V\niget v5, v0, Lorg/vinix/bootstrap/MeasuredText;->measures:I\ninvoke-virtual {v8, v1}, Landroid/view/View;->setLayoutDirection(I)V\ninvoke-virtual {v0, v1, v1}, Landroid/view/View;->measure(II)V\niget v1, v0, Lorg/vinix/bootstrap/MeasuredText;->measures:I\nadd-int/lit8 v2, v5, 1\n' + eq('v1', 'v2', 'inherited RTL flip remeasures identical specs')
 b += 'invoke-static {v0}, Lorg/vinix/bootstrap/GeometryProbe;->ink(Landroid/view/View;)I\nmove-result v1\nadd-int/lit8 v2, v7, 11\n' + eq('v1', 'v2', 'inherited LTR native Canvas offset')
 b += 'invoke-virtual {v8, v0}, Landroid/view/ViewGroup;->removeView(Landroid/view/View;)V\nnew-instance v8, Landroid/widget/FrameLayout;\ninvoke-direct {v8, p0}, Landroid/widget/FrameLayout;-><init>(Landroid/content/Context;)V\nconst/4 v1, 1\ninvoke-virtual {v8, v1}, Landroid/view/View;->setLayoutDirection(I)V\ninvoke-virtual {v8, v0}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V\ninvoke-static {v0}, Lorg/vinix/bootstrap/GeometryProbe;->ink(Landroid/view/View;)I\nmove-result v1\nadd-int/lit8 v2, v7, 29\n' + eq('v1', 'v2', 'reparented RTL native Canvas offset')
 b += 'const/4 v1, 7\nconst/4 v2, 3\nconst/16 v3, 19\nconst/4 v4, 5\ninvoke-virtual {v0, v1, v2, v3, v4}, Landroid/view/View;->setPadding(IIII)V\n' + set_int('view/View', 'setLayoutDirection', 0) + set_int('view/View', 'setLayoutDirection', 1)
 b += getter('getPaddingLeft', 7) + getter('getPaddingRight', 19) + getter('getPaddingStart', 19) + getter('getPaddingEnd', 7)
 b += 'invoke-virtual {v0}, Landroid/view/View;->isPaddingRelative()Z\nmove-result v1\nconst/4 v2, 0\n' + eq('v1', 'v2', 'absolute padding clears relative flag')
 b += 'invoke-static {v0}, Lorg/vinix/bootstrap/GeometryProbe;->ink(Landroid/view/View;)I\nmove-result v1\nadd-int/lit8 v2, v7, 7\n' + eq('v1', 'v2', 'absolute native Canvas offset')
 b += marker('PADDING-RELATIVE') + 'return-void'
 return method('private static padding(Landroid/content/Context;)V', b)
}

fn chip_probe() string {
 mut b := r'new-instance v0, Landroid/widget/CheckBox;
const/4 v1, 0
const v2, @NEUTRAL@
invoke-direct {v0, p0, v1, v1, v2}, Landroid/widget/CheckBox;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V
invoke-static {v0}, Lorg/vinix/bootstrap/GeometryProbe;->configure(Landroid/widget/TextView;)V
'
 b += layout() + 'const/4 v1, 0\ninvoke-virtual {v0, v1, v1}, Landroid/view/View;->measure(II)V\ninvoke-virtual {v0}, Landroid/view/View;->getMeasuredWidth()I\nmove-result v6\ninvoke-static {v0}, Lorg/vinix/bootstrap/GeometryProbe;->ink(Landroid/view/View;)I\nmove-result v7\n'
 b += relative() + set_int('widget/TextView', 'setMinHeight', 48) + height(48, '0')
 b += 'invoke-virtual {v0}, Landroid/view/View;->getMeasuredWidth()I\nmove-result v1\nadd-int/lit8 v2, v6, 40\n' + eq('v1', 'v2', 'neutral styled chip width reserves app icon padding')
 b += 'invoke-static {v0}, Lorg/vinix/bootstrap/GeometryProbe;->ink(Landroid/view/View;)I\nmove-result v1\nadd-int/lit8 v2, v7, 11\n' + eq('v1', 'v2', 'neutral styled chip native Canvas offset')
 b += min_getter('getMinHeight', 48) + marker('CHIP-GEOMETRY') + 'return-void'
 return method('private static chip(Landroid/content/Context;)V', b)
}

fn minimum_probe() string {
 mut b := 'new-instance v0, Lorg/vinix/bootstrap/MeasuredText;\ninvoke-direct {v0, p0}, Lorg/vinix/bootstrap/MeasuredText;-><init>(Landroid/content/Context;)V\ninvoke-static {v0}, Lorg/vinix/bootstrap/GeometryProbe;->configure(Landroid/widget/TextView;)V\n'
 b += min_getter('getMinHeight', -1) + min_getter('getMinLines', 0) + height(18, '0')
 b += set_int('widget/TextView', 'setMinLines', 5) + min_getter('getMinHeight', -1) + min_getter('getMinLines', 5) + height(78, '0')
 b += relative() + set_int('widget/TextView', 'setMinHeight', 40) + min_getter('getMinHeight', 40) + min_getter('getMinLines', -1) + height(40, '0')
 b += set_int('view/View', 'setMinimumHeight', 100) + set_int('widget/TextView', 'setMinHeight', 40) + getter('getMinimumHeight', 100) + min_getter('getMinHeight', 40) + height(100, '0')
 b += set_int('view/View', 'setMinimumHeight', 10) + set_int('widget/TextView', 'setMinHeight', 40) + getter('getMinimumHeight', 10) + height(40, '0')
 b += height(25, '0x80000019') + height(23, '0x40000017') + height(40, '0')
 b += set_int('widget/TextView', 'setMinLines', 4) + min_getter('getMinHeight', -1) + min_getter('getMinLines', 4) + height(71, '0')
 b += set_int('widget/TextView', 'setMinHeight', 0) + min_getter('getMinLines', -1) + height(26, '0')
 b += set_int('widget/TextView', 'setMinHeight', -7) + min_getter('getMinHeight', -7) + min_getter('getMinLines', -1) + height(26, '0')
 b += set_int('widget/TextView', 'setMinLines', 0) + min_getter('getMinHeight', -1) + min_getter('getMinLines', 0) + height(26, '0')
 b += marker('TEXT-MINHEIGHT') + 'return-void'
 return method('private static minimum(Landroid/content/Context;)V', b)
}
