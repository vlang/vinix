// SPDX-License-Identifier: GPL-2.0-or-later
// Same-APK guest regression for default, removed, custom and styled indicators.
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
	os.mkdir_all(out + '/res/drawable')!
	os.mkdir_all(out + '/res/layout')!
	os.write_file(out + '/res/values/styles.xml', r'<resources>
<attr name="fixtureButtonStyle" format="reference"/>
<style name="NeutralButton" parent="android:style/Widget"/>
<style name="NullButton" parent="android:style/Widget"><item name="android:button">@null</item></style>
<style name="StyledButton" parent="android:style/Widget"><item name="android:button">@drawable/indicator</item></style>
<style name="CheckedButton" parent="StyledButton"><item name="android:checked">true</item></style>
<style name="NeutralTheme"><item name="fixtureButtonStyle">@style/NeutralButton</item></style>
<style name="NeutralDefaultsTheme"><item name="android:checkboxStyle">@style/NeutralButton</item><item name="android:radioButtonStyle">@style/NeutralButton</item></style>
<style name="NullTheme"><item name="android:checkboxStyle">@style/NullButton</item><item name="android:radioButtonStyle">@style/NullButton</item></style>
<style name="StyledTheme"><item name="android:checkboxStyle">@style/StyledButton</item><item name="android:radioButtonStyle">@style/StyledButton</item></style>
<style name="CheckedTheme"><item name="android:checkboxStyle">@style/CheckedButton</item></style>
</resources>')!
	os.write_file(out + '/res/drawable/indicator.xml', r'<selector xmlns:android="http://schemas.android.com/apk/res/android">
<item android:state_checked="true" android:drawable="@drawable/checked"/>
<item android:drawable="@drawable/unchecked"/>
</selector>')!
	os.write_file(out + '/res/layout/neutral.xml', '<CheckBox xmlns:android="http://schemas.android.com/apk/res/android" style="@style/NeutralButton" android:layout_width="wrap_content" android:layout_height="wrap_content"/>')!
	os.write_file(out + '/res/layout/removed.xml', '<CheckBox xmlns:android="http://schemas.android.com/apk/res/android" android:button="@null" android:layout_width="wrap_content" android:layout_height="wrap_content"/>')!
	for name, color in {'checked': '#ff00ff00', 'unchecked': '#ffff00ff'} {
		os.write_file(out + '/res/drawable/' + name + '.xml', '<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle"><size android:width="12dp" android:height="18dp"/><solid android:color="' + color + '"/></shape>')!
	}
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
const-string v1, "defaults; explicit null; custom Canvas pixels; restoration; resource zero; subclass; negative bounds; neutral/null styles; stateful styled defaults"
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
	os.write_file(root + '/StyledChip.smali', r'.class public Lorg/vinix/bootstrap/StyledChip;
.super Landroid/widget/CheckBox;
.method public constructor <init>(Landroid/content/Context;I)V
.locals 2
const/4 v0, 0
const/4 v1, 0
invoke-direct {p0, p1, v0, v1, p2}, Landroid/widget/CheckBox;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V
return-void
.end method
')!
	os.write_file(root + '/AttrChip.smali', r'.class public Lorg/vinix/bootstrap/AttrChip;
.super Landroid/widget/CheckBox;
.method public constructor <init>(Landroid/content/Context;I)V
.locals 1
const/4 v0, 0
invoke-direct {p0, p1, v0, p2}, Landroid/widget/CheckBox;-><init>(Landroid/content/Context;Landroid/util/AttributeSet;I)V
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
	os.write_file(root + '/IndicatorProbe.smali', probe() + styled_probe(ids))!
	checked([java, '-cp', os.abs_path('build/android-framework/tools') + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali', '-o', out + '/classes.dex'])
	assert os.is_file(out + '/classes.dex'), 'smali did not produce DEX'
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

fn styled_probe(ids map[string]string) string {
	mut source := r'
.method private static styled(Landroid/content/Context;)V
.locals 6
const/4 v3, 6
const/4 v4, 0
new-instance v0, Lorg/vinix/bootstrap/StyledChip;
const v1, @NEUTRAL@
invoke-direct {v0, p0, v1}, Lorg/vinix/bootstrap/StyledChip;-><init>(Landroid/content/Context;I)V
invoke-static {v0, v3, v4}, Lorg/vinix/bootstrap/IndicatorProbe;->verify(Landroid/view/View;II)V
new-instance v0, Lorg/vinix/bootstrap/StyledChip;
const v1, @NULL@
invoke-direct {v0, p0, v1}, Lorg/vinix/bootstrap/StyledChip;-><init>(Landroid/content/Context;I)V
invoke-static {v0, v3, v4}, Lorg/vinix/bootstrap/IndicatorProbe;->verify(Landroid/view/View;II)V
new-instance v5, Landroid/view/ContextThemeWrapper;
const v1, @NEUTRAL_THEME@
invoke-direct {v5, p0, v1}, Landroid/view/ContextThemeWrapper;-><init>(Landroid/content/Context;I)V
new-instance v0, Lorg/vinix/bootstrap/AttrChip;
const v1, @STYLE_ATTR@
invoke-direct {v0, v5, v1}, Lorg/vinix/bootstrap/AttrChip;-><init>(Landroid/content/Context;I)V
invoke-static {v0, v3, v4}, Lorg/vinix/bootstrap/IndicatorProbe;->verify(Landroid/view/View;II)V
new-instance v5, Landroid/view/ContextThemeWrapper;
const v1, @NEUTRAL_DEFAULTS_THEME@
invoke-direct {v5, p0, v1}, Landroid/view/ContextThemeWrapper;-><init>(Landroid/content/Context;I)V
new-instance v0, Landroid/widget/CheckBox;
invoke-direct {v0, v5}, Landroid/widget/CheckBox;-><init>(Landroid/content/Context;)V
invoke-static {v0, v3, v4}, Lorg/vinix/bootstrap/IndicatorProbe;->verify(Landroid/view/View;II)V
new-instance v0, Landroid/widget/RadioButton;
invoke-direct {v0, v5}, Landroid/widget/RadioButton;-><init>(Landroid/content/Context;)V
invoke-static {v0, v3, v4}, Lorg/vinix/bootstrap/IndicatorProbe;->verify(Landroid/view/View;II)V
invoke-static {p0}, Landroid/view/LayoutInflater;->from(Landroid/content/Context;)Landroid/view/LayoutInflater;
move-result-object v5
const/4 v2, 0
const v1, @NEUTRAL_LAYOUT@
invoke-virtual {v5, v1, v2}, Landroid/view/LayoutInflater;->inflate(ILandroid/view/ViewGroup;)Landroid/view/View;
move-result-object v0
invoke-static {v0, v3, v4}, Lorg/vinix/bootstrap/IndicatorProbe;->verify(Landroid/view/View;II)V
const v1, @REMOVED_LAYOUT@
invoke-virtual {v5, v1, v2}, Landroid/view/LayoutInflater;->inflate(ILandroid/view/ViewGroup;)Landroid/view/View;
move-result-object v0
invoke-static {v0, v3, v4}, Lorg/vinix/bootstrap/IndicatorProbe;->verify(Landroid/view/View;II)V
const-string v1, "BOOTSTRAP-COMPOUND-BUTTON-NEUTRAL-STYLES-PASS"
const-string v2, "neutral absent/null styles, no setter; custom default style attr"
invoke-static {v1, v2}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
new-instance v5, Landroid/view/ContextThemeWrapper;
const v1, @NULL_THEME@
invoke-direct {v5, p0, v1}, Landroid/view/ContextThemeWrapper;-><init>(Landroid/content/Context;I)V
new-instance v0, Landroid/widget/CheckBox;
invoke-direct {v0, v5}, Landroid/widget/CheckBox;-><init>(Landroid/content/Context;)V
invoke-static {v0, v3, v4}, Lorg/vinix/bootstrap/IndicatorProbe;->verify(Landroid/view/View;II)V
new-instance v0, Landroid/widget/RadioButton;
invoke-direct {v0, v5}, Landroid/widget/RadioButton;-><init>(Landroid/content/Context;)V
invoke-static {v0, v3, v4}, Lorg/vinix/bootstrap/IndicatorProbe;->verify(Landroid/view/View;II)V
const-string v1, "BOOTSTRAP-COMPOUND-BUTTON-NULL-DEFAULT-STYLES-PASS"
const-string v2, "standard checkbox and radio default attrs honor styled @null"
invoke-static {v1, v2}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
new-instance v5, Landroid/view/ContextThemeWrapper;
const v1, @STYLED_THEME@
invoke-direct {v5, p0, v1}, Landroid/view/ContextThemeWrapper;-><init>(Landroid/content/Context;I)V
new-instance v0, Landroid/widget/CheckBox;
invoke-direct {v0, v5}, Landroid/widget/CheckBox;-><init>(Landroid/content/Context;)V
const/16 v3, 30
const v4, 0xffff00ff
invoke-static {v0, v3, v4}, Lorg/vinix/bootstrap/IndicatorProbe;->verify(Landroid/view/View;II)V
const/4 v1, 1
invoke-virtual {v0, v1}, Landroid/widget/CompoundButton;->setChecked(Z)V
const v4, 0xff00ff00
invoke-static {v0, v3, v4}, Lorg/vinix/bootstrap/IndicatorProbe;->verify(Landroid/view/View;II)V
const/4 v1, 0
invoke-virtual {v0, v1}, Landroid/widget/CompoundButton;->setChecked(Z)V
const v4, 0xffff00ff
invoke-static {v0, v3, v4}, Lorg/vinix/bootstrap/IndicatorProbe;->verify(Landroid/view/View;II)V
new-instance v0, Landroid/widget/RadioButton;
invoke-direct {v0, v5}, Landroid/widget/RadioButton;-><init>(Landroid/content/Context;)V
invoke-static {v0, v3, v4}, Lorg/vinix/bootstrap/IndicatorProbe;->verify(Landroid/view/View;II)V
const/4 v1, 1
invoke-virtual {v0, v1}, Landroid/widget/CompoundButton;->setChecked(Z)V
const v4, 0xff00ff00
invoke-static {v0, v3, v4}, Lorg/vinix/bootstrap/IndicatorProbe;->verify(Landroid/view/View;II)V
new-instance v0, Lorg/vinix/bootstrap/StyledChip;
const v1, @STYLED@
invoke-direct {v0, p0, v1}, Lorg/vinix/bootstrap/StyledChip;-><init>(Landroid/content/Context;I)V
const v4, 0xffff00ff
invoke-static {v0, v3, v4}, Lorg/vinix/bootstrap/IndicatorProbe;->verify(Landroid/view/View;II)V
new-instance v5, Landroid/view/ContextThemeWrapper;
const v1, @CHECKED_THEME@
invoke-direct {v5, p0, v1}, Landroid/view/ContextThemeWrapper;-><init>(Landroid/content/Context;I)V
new-instance v0, Landroid/widget/CheckBox;
invoke-direct {v0, v5}, Landroid/widget/CheckBox;-><init>(Landroid/content/Context;)V
const v4, 0xff00ff00
invoke-static {v0, v3, v4}, Lorg/vinix/bootstrap/IndicatorProbe;->verify(Landroid/view/View;II)V
const-string v1, "BOOTSTRAP-COMPOUND-BUTTON-STATEFUL-STYLES-PASS"
const-string v2, "styled checkbox/radio selectors paint unchecked/checked pixels; checked XML style"
invoke-static {v1, v2}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
return-void
.end method
'
	for token, name in {
		'@NEUTRAL@': 'style/NeutralButton'
		'@NULL@': 'style/NullButton'
		'@STYLED@': 'style/StyledButton'
		'@NEUTRAL_THEME@': 'style/NeutralTheme'
		'@NEUTRAL_DEFAULTS_THEME@': 'style/NeutralDefaultsTheme'
		'@NULL_THEME@': 'style/NullTheme'
		'@STYLED_THEME@': 'style/StyledTheme'
		'@CHECKED_THEME@': 'style/CheckedTheme'
		'@STYLE_ATTR@': 'attr/fixtureButtonStyle'
		'@NEUTRAL_LAYOUT@': 'layout/neutral'
		'@REMOVED_LAYOUT@': 'layout/removed'
	} {
		source = source.replace(token, ids[name] or { panic('missing resource ' + name) })
	}
	return source
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
invoke-static {p0}, Lorg/vinix/bootstrap/IndicatorProbe;->styled(Landroid/content/Context;)V
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
if-ne v1, p1, :bad_width
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
if-ne v1, p2, :bad_pixel
invoke-virtual {v8}, Landroid/graphics/Bitmap;->recycle()V
return-void
:bad_width
const-string v0, "width"
invoke-static {p0, v0, v1, p1}, Lorg/vinix/bootstrap/IndicatorProbe;->fail(Landroid/view/View;Ljava/lang/String;II)V
return-void
:bad_pixel
const-string v0, "pixel"
invoke-static {p0, v0, v1, p2}, Lorg/vinix/bootstrap/IndicatorProbe;->fail(Landroid/view/View;Ljava/lang/String;II)V
return-void
.end method
.method private static fail(Landroid/view/View;Ljava/lang/String;II)V
.locals 6
new-instance v0, Ljava/lang/StringBuilder;
const-string v1, "CompoundButton measured width or bitmap indicator pixel: "
invoke-direct {v0, v1}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V
invoke-virtual {v0, p1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const-string v1, " actual="
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v0, p2}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
const-string v1, " expected="
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v0, p3}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
const-string v1, " view="
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v0, p0}, Ljava/lang/StringBuilder;->append(Ljava/lang/Object;)Ljava/lang/StringBuilder;
instance-of v2, p0, Landroid/widget/CompoundButton;
if-eqz v2, :theme
move-object v2, p0
check-cast v2, Landroid/widget/CompoundButton;
const-string v1, " custom="
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
iget v1, v2, Landroid/widget/CompoundButton;->vinixWsButtonDrawableSet:I
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
const-string v1, " drawable="
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v2}, Landroid/widget/CompoundButton;->getButtonDrawable()Landroid/graphics/drawable/Drawable;
move-result-object v2
invoke-virtual {v0, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/Object;)Ljava/lang/StringBuilder;
:theme
invoke-virtual {p0}, Landroid/view/View;->getContext()Landroid/content/Context;
move-result-object v4
invoke-virtual {v4}, Landroid/content/Context;->getTheme()Landroid/content/res/Resources$Theme;
move-result-object v4
new-instance v3, Landroid/util/TypedValue;
invoke-direct {v3}, Landroid/util/TypedValue;-><init>()V
const v5, 0x101006c
const/4 v1, 1
invoke-virtual {v4, v5, v3, v1}, Landroid/content/res/Resources$Theme;->resolveAttribute(ILandroid/util/TypedValue;Z)Z
const-string v1, " checkboxStyle="
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v0, v3}, Ljava/lang/StringBuilder;->append(Ljava/lang/Object;)Ljava/lang/StringBuilder;
invoke-virtual {p0}, Landroid/view/View;->getContext()Landroid/content/Context;
move-result-object v2
const/4 v4, 0
sget-object v5, Lcom/android/internal/R$styleable;->CompoundButton:[I
const v3, 0x101006c
const/4 v1, 0
invoke-virtual {v2, v4, v5, v3, v1}, Landroid/content/Context;->obtainStyledAttributes(Landroid/util/AttributeSet;[III)Landroid/content/res/TypedArray;
move-result-object v2
const-string v1, " buttonHasValueOrEmpty="
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const/4 v3, 1
invoke-virtual {v2, v3}, Landroid/content/res/TypedArray;->hasValueOrEmpty(I)Z
move-result v1
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Z)Ljava/lang/StringBuilder;
const-string v1, " buttonSource="
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const/4 v1, 0
invoke-virtual {v2, v3, v1}, Landroid/content/res/TypedArray;->getSourceStyleResourceId(II)I
move-result v1
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
const-string v1, " buttonResource="
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const/4 v1, 0
invoke-virtual {v2, v3, v1}, Landroid/content/res/TypedArray;->getResourceId(II)I
move-result v1
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
const-string v1, " buttonValue="
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v2, v3}, Landroid/content/res/TypedArray;->peekValue(I)Landroid/util/TypedValue;
move-result-object v1
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/Object;)Ljava/lang/StringBuilder;
invoke-virtual {v2}, Landroid/content/res/TypedArray;->recycle()V
invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
move-result-object v1
const-string v2, "BOOTSTRAP-COMPOUND-BUTTON-FAIL"
invoke-static {v2, v1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.end method
'
}
