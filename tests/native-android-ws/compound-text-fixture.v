// SPDX-License-Identifier: GPL-2.0-or-later
// Same-APK guest regression for CompoundButton text dispatch and Canvas gravity.
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
 os.mkdir_all(out + '/res/xml')!
 os.write_file(out + '/res/xml/constructor.xml', '<Button xmlns:android="http://schemas.android.com/apk/res/android" android:text="Ctor" android:button="@null"/>')!
 os.write_file(out + '/res/xml/neutral.xml', '<Button style="@style/NeutralButton"/>')!
 os.write_file(out + '/res/values/styles.xml', '<resources><style name="NeutralButton" parent="android:style/Widget"/><style name="ConstructorButton" parent="NeutralButton"><item name="android:text">Ctor</item></style></resources>')!
 os.write_file(out + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="23" android:targetSdkVersion="35"/><application android:label="Compound text fixture"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
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
const-string v1, "Compound text fixture"
invoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
invoke-static {p0}, Lorg/vinix/bootstrap/TextProbe;->run(Landroid/content/Context;)V
const-string v0, "BOOTSTRAP-COMPOUND-TEXT-PASS"
const-string v1, "virtual overload dispatch; Java CharSequence state; styled Canvas gravity"
invoke-static {v0, v1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
const-string v0, "BOOTSTRAP-READY"
invoke-static {v0, v1}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I
return-void
.end method
')!
 for class in ['Button', 'CompoundButton', 'CheckBox', 'RadioButton'] {
  os.write_file(root + '/Label' + class + '.smali', subclass(class))!
 }
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
 os.write_file(root + '/TextProbe.smali', probe().replace('@NEUTRAL@', ids['style/NeutralButton']!).replace('@CTOR@', ids['xml/constructor']!).replace('@NEUTRALXML@', ids['xml/neutral']!))!
 checked([java, '-cp', os.abs_path('build/android-framework/tools') + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali', '-o', out + '/classes.dex'])
 assert os.is_file(out + '/classes.dex'), 'smali did not produce DEX'
 checked(['zip', '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'])
 key := out + '/fixture.p12'
 if !os.is_file(key) {
  checked(['/opt/homebrew/opt/openjdk@25/bin/keytool', '-genkeypair', '-keystore', key, '-storetype', 'PKCS12', '-alias', 'fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650', '-dname', 'CN=Vinix Compound text fixture', '-storepass', 'android', '-keypass', 'android'])
 }
 checked([java, '-jar', os.abs_path('build/android-native-ws/android-15/lib/apksigner.jar'), 'sign', '--ks', key, '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'])
 println('COMPOUND-TEXT-APK ' + sha256.sum(os.read_bytes(out + '/probe.apk')!).hex())
}

fn subclass(class string) string {
 owner := 'Lorg/vinix/bootstrap/Label' + class + ';'
 parent := 'Landroid/widget/' + class + ';'
 return '.class public ' + owner + '\n.super ' + parent + '\n.field public calls:I\n.field public last:Ljava/lang/CharSequence;\n.field public buffer:Landroid/widget/TextView$BufferType;\n' +
 '.method public constructor <init>(Landroid/content/Context;I)V\n.locals 2\ninvoke-virtual {p1}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;\nmove-result-object v0\ninvoke-virtual {v0, p2}, Landroid/content/res/Resources;->getXml(I)Landroid/content/res/XmlResourceParser;\nmove-result-object v0\n:find_tag\ninvoke-interface {v0}, Lorg/xmlpull/v1/XmlPullParser;->next()I\nmove-result v1\nconst/4 p2, 2\nif-eq v1, p2, :start_tag\nconst/4 p2, 1\nif-ne v1, p2, :find_tag\nnew-instance v1, Ljava/lang/AssertionError;\nconst-string p2, "Compound text XML has no start tag"\ninvoke-direct {v1, p2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v1\n:start_tag\nconst/4 v1, 0\ninvoke-direct {p0, p1, v0, v1, v1}, ' + parent + '-><init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V\ninvoke-interface {v0}, Landroid/content/res/XmlResourceParser;->close()V\nreturn-void\n.end method\n' +
 '.method public setText(Ljava/lang/CharSequence;Landroid/widget/TextView$BufferType;)V\n.locals 4\n' +
 'iget v0, p0, ' + owner + '->calls:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ' + owner + '->calls:I\niput-object p1, p0, ' + owner + '->last:Ljava/lang/CharSequence;\niput-object p2, p0, ' + owner + '->buffer:Landroid/widget/TextView$BufferType;\n' +
 'invoke-super {p0, p1, p2}, ' + parent + '->setText(Ljava/lang/CharSequence;Landroid/widget/TextView$BufferType;)V\n' +
 // Model a styled chip reserving space for its own leading icon in its override.
 'const/16 v0, 31\nconst/4 v1, 7\nconst/16 v2, 17\nconst/16 v3, 13\ninvoke-virtual {p0, v0, v1, v2, v3}, Landroid/view/View;->setPaddingRelative(IIII)V\nreturn-void\n.end method\n'
}

fn method(signature string, body string) string {
 return '.method ' + signature + '\n.locals 10\n' + body + '\n.end method\n'
}
fn eq(actual string, expected string, label string) string {
 return 'const-string v9, "' + label + '"\ninvoke-static {' + actual + ', ' + expected + ', v9}, Lorg/vinix/bootstrap/TextProbe;->equal(IILjava/lang/String;)V\n'
}
fn marker(name string) string {
 return 'const-string v1, "BOOTSTRAP-' + name + '-PASS"\nconst-string v2, "actual virtual dispatch and Canvas bounds"\ninvoke-static {v1, v2}, Landroid/util/Log;->i(Ljava/lang/String;Ljava/lang/String;)I\n'
}
fn probe() string {
 mut s := '.class public Lorg/vinix/bootstrap/TextProbe;\n.super Ljava/lang/Object;\n'
 s += method('public static run(Landroid/content/Context;)V', 'invoke-static {p0}, Lorg/vinix/bootstrap/TextProbe;->dispatch(Landroid/content/Context;)V\ninvoke-static {p0}, Lorg/vinix/bootstrap/TextProbe;->gravity(Landroid/content/Context;)V\nreturn-void')
 s += method('private static configure(Landroid/widget/TextView;)V', r'
const v1, 0xffff00ff
invoke-virtual {p0, v1}, Landroid/widget/TextView;->setTextColor(I)V
const v1, 0x41400000
invoke-virtual {p0, v1}, Landroid/widget/TextView;->setTextSize(F)V
const/4 v1, 1
invoke-virtual {p0, v1}, Landroid/widget/TextView;->setSingleLine(Z)V
const/4 v1, 0
invoke-virtual {p0, v1}, Landroid/view/View;->setBackgroundColor(I)V
const/16 v2, 240
const/16 v3, 120
invoke-virtual {p0, v1, v1, v2, v3}, Landroid/view/View;->layout(IIII)V
return-void')
 s += assertion() + bounds() + dispatch_probe() + gravity_probe()
 return s
}
fn assertion() string {
 return r'.method private static equal(IILjava/lang/String;)V
.locals 2
if-eq p0, p1, :ok
new-instance v0, Ljava/lang/StringBuilder;
const-string v1, "Compound text: "
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
fn bounds() string {
 return r'.method private static bounds(Landroid/view/View;)[I
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
const/4 v0, 4
new-array v11, v0, [I
const/4 v0, 0
const/16 v1, 240
aput v1, v11, v0
const/4 v0, 1
const/16 v1, 120
aput v1, v11, v0
const/4 v0, 2
const/4 v1, -1
aput v1, v11, v0
const/4 v0, 3
aput v1, v11, v0
const/4 v0, 0
const v9, 0xffffff
:scan
array-length v1, v10
if-ge v0, v1, :done
aget v5, v10, v0
and-int/2addr v5, v9
const v1, 0xff00ff
if-ne v5, v1, :next
rem-int/lit16 v6, v0, 240
div-int/lit16 v7, v0, 240
const/4 v1, 0
aget v2, v11, v1
if-ge v6, v2, :min_y
aput v6, v11, v1
:min_y
const/4 v1, 1
aget v2, v11, v1
if-ge v7, v2, :max_x
aput v7, v11, v1
:max_x
const/4 v1, 2
aget v2, v11, v1
if-le v6, v2, :max_y
aput v6, v11, v1
:max_y
const/4 v1, 3
aget v2, v11, v1
if-le v7, v2, :next
aput v7, v11, v1
:next
add-int/lit8 v0, v0, 1
goto :scan
:done
invoke-virtual {v8}, Landroid/graphics/Bitmap;->recycle()V
const/4 v0, 2
aget v1, v11, v0
if-gez v1, :return
const/4 v2, 0
const-string v3, "nonempty Canvas text ink"
invoke-static {v1, v2, v3}, Lorg/vinix/bootstrap/TextProbe;->equal(IILjava/lang/String;)V
:return
return-object v11
.end method
.method private static same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V
.locals 2
if-eq p0, p1, :ok
const/4 v0, 0
const/4 v1, 1
invoke-static {v0, v1, p2}, Lorg/vinix/bootstrap/TextProbe;->equal(IILjava/lang/String;)V
:ok
return-void
.end method
'
}

fn dispatch_probe() string {
 mut b := ''
 for class in ['Button', 'CompoundButton', 'CheckBox', 'RadioButton'] {
  owner := 'Lorg/vinix/bootstrap/Label' + class + ';'
  b += 'new-instance v0, ' + owner + '\nconst v1, @CTOR@\ninvoke-direct {v0, p0, v1}, ' + owner + '-><init>(Landroid/content/Context;I)V\n'
  b += 'iget v1, v0, ' + owner + '->calls:I\nif-gtz v1, :ctor_' + class + '\nconst/4 v2, 1\n' + eq('v1', 'v2', class + ' constructor invokes overload') + ':ctor_' + class + '\n'
  b += 'invoke-virtual {v0}, Landroid/widget/TextView;->getText()Ljava/lang/CharSequence;\nmove-result-object v1\ninvoke-interface {v1}, Ljava/lang/CharSequence;->toString()Ljava/lang/String;\nmove-result-object v1\nconst-string v2, "Ctor"\ninvoke-virtual {v1, v2}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v1\nconst/4 v2, 1\n' + eq('v1', 'v2', class + ' constructor text retained')
  b += 'const/4 v1, 0\niput v1, v0, ' + owner + '->calls:I\nnew-instance v2, Landroid/text/SpannableString;\nconst-string v1, "H"\ninvoke-direct {v2, v1}, Landroid/text/SpannableString;-><init>(Ljava/lang/CharSequence;)V\ninvoke-virtual {v0, v2}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V\n'
  b += 'iget v1, v0, ' + owner + '->calls:I\nconst/4 v3, 1\n' + eq('v1', 'v3', class + ' one-arg invokes two-arg once')
  b += 'iget-object v1, v0, ' + owner + '->last:Ljava/lang/CharSequence;\nconst-string v9, "' + class + ' overload receives original Spanned"\ninvoke-static {v1, v2, v9}, Lorg/vinix/bootstrap/TextProbe;->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V\n'
  b += 'invoke-virtual {v0}, Landroid/widget/TextView;->getText()Ljava/lang/CharSequence;\nmove-result-object v1\nconst-string v9, "' + class + ' getText retains Spanned identity"\ninvoke-static {v1, v2, v9}, Lorg/vinix/bootstrap/TextProbe;->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V\n'
  b += 'iget-object v1, v0, ' + owner + '->buffer:Landroid/widget/TextView$BufferType;\nsget-object v2, Landroid/widget/TextView$BufferType;->NORMAL:Landroid/widget/TextView$BufferType;\nconst-string v9, "' + class + ' default buffer NORMAL"\ninvoke-static {v1, v2, v9}, Lorg/vinix/bootstrap/TextProbe;->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V\n'
  b += 'const/4 v1, 0\niput v1, v0, ' + owner + '->calls:I\ninvoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V\niget v1, v0, ' + owner + '->calls:I\nconst/4 v2, 1\n' + eq('v1', 'v2', class + ' null invokes overload once')
  b += 'iget-object v1, v0, ' + owner + '->last:Ljava/lang/CharSequence;\nconst/4 v2, 0\nconst-string v9, "' + class + ' overload receives null"\ninvoke-static {v1, v2, v9}, Lorg/vinix/bootstrap/TextProbe;->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V\n'
  b += 'invoke-virtual {v0}, Landroid/widget/TextView;->getText()Ljava/lang/CharSequence;\nmove-result-object v1\ninvoke-interface {v1}, Ljava/lang/CharSequence;->length()I\nmove-result v1\nconst/4 v2, 0\n' + eq('v1', 'v2', class + ' null normalizes to empty')
 }
 b += marker('TEXT-OVERLOAD-DISPATCH') + 'return-void'
 return method('private static dispatch(Landroid/content/Context;)V', b)
}

fn padding(left int, right int) string {
 return 'const/16 v1, ' + left.str() + '\nconst/4 v2, 7\nconst/16 v3, ' + right.str() + '\nconst/16 v4, 13\ninvoke-virtual {v0, v1, v2, v3, v4}, Landroid/view/View;->setPadding(IIII)V\n'
}
fn compare_bounds(label string) string {
 mut b := 'invoke-static {v0}, Lorg/vinix/bootstrap/TextProbe;->bounds(Landroid/view/View;)[I\nmove-result-object v6\ninvoke-static {v5}, Lorg/vinix/bootstrap/TextProbe;->bounds(Landroid/view/View;)[I\nmove-result-object v7\n'
 for i in 0 .. 4 {
  b += 'const/4 v1, ' + i.str() + '\naget v2, v6, v1\naget v3, v7, v1\n'
  if i == 0 || i == 2 { b += 'add-int/lit8 v3, v3, -3\n' }
  b += eq('v2', 'v3', label + ' bounds[' + i.str() + ']')
 }
 return b
}
fn gravity_probe() string {
 mut b := ''
 for class in ['CheckBox', 'RadioButton'] {
  for styled in [true, false] {
   label := class + if styled { ' neutral styled' } else { ' default indicator' }
   b += 'new-instance v0, Landroid/widget/' + class + ';\n'
   if styled {
    b += 'const/4 v1, 0\nconst v2, @NEUTRAL@\ninvoke-direct {v0, p0, v1, v1, v2}, Landroid/widget/' + class + ';-><init>(Landroid/content/Context;Landroid/util/AttributeSet;II)V\n'
   } else {
    b += 'invoke-direct {v0, p0}, Landroid/widget/' + class + ';-><init>(Landroid/content/Context;)V\n'
   }
   b += 'invoke-static {v0}, Lorg/vinix/bootstrap/TextProbe;->configure(Landroid/widget/TextView;)V\nconst-string v1, "H"\ninvoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V\n' + padding(11, 29)
   b += 'move-object v8, v0\nnew-instance v0, Landroid/widget/TextView;\ninvoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V\ninvoke-static {v0}, Lorg/vinix/bootstrap/TextProbe;->configure(Landroid/widget/TextView;)V\nconst-string v1, "H"\ninvoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V\n' + padding(if styled { 11 } else { 41 }, 29)
   b += 'move-object v5, v0\nmove-object v0, v8\n'
   for gravity in [0x33, 0x13, 0x53, 0x11, 0x55] {
    b += 'const/16 v1, ' + gravity.str() + '\ninvoke-virtual {v0, v1}, Landroid/widget/TextView;->setGravity(I)V\ninvoke-virtual {v5, v1}, Landroid/widget/TextView;->setGravity(I)V\n' + compare_bounds(label + ' gravity ' + gravity.str())
   }
   b += 'const/16 v1, 0x33\ninvoke-virtual {v0, v1}, Landroid/widget/TextView;->setGravity(I)V\ninvoke-virtual {v5, v1}, Landroid/widget/TextView;->setGravity(I)V\nconst/4 v1, 4\ninvoke-virtual {v0, v1}, Landroid/view/View;->setTextAlignment(I)V\ninvoke-virtual {v5, v1}, Landroid/view/View;->setTextAlignment(I)V\n' + compare_bounds(label + ' textAlignment center overrides left')
   if styled {
    b += 'const/4 v1, 0\ninvoke-virtual {v0, v1}, Landroid/view/View;->setTextAlignment(I)V\ninvoke-virtual {v0, v1}, Landroid/widget/TextView;->setSingleLine(Z)V\nconst-string v1, "H H H H H H H H"\ninvoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V\ninvoke-static {v0}, Lorg/vinix/bootstrap/TextProbe;->bounds(Landroid/view/View;)[I\nmove-result-object v6\nconst/4 v1, 0\nconst/16 v2, 60\nconst/16 v3, 120\ninvoke-virtual {v0, v1, v1, v2, v3}, Landroid/view/View;->layout(IIII)V\ninvoke-static {v0}, Lorg/vinix/bootstrap/TextProbe;->bounds(Landroid/view/View;)[I\nmove-result-object v7\n'
    for i in [1, 3] {
     b += 'const/4 v1, ' + i.str() + '\naget v2, v6, v1\naget v3, v7, v1\n' + eq('v2', 'v3', label + ' narrow multiword retains one line ink')
    }
    b += 'const v1, 0x8000003c\nconst/4 v2, 0\ninvoke-virtual {v0, v1, v2}, Landroid/view/View;->measure(II)V\ninvoke-virtual {v0}, Landroid/view/View;->getMeasuredHeight()I\nmove-result v1\nconst/16 v2, 38\n' + eq('v1', 'v2', label + ' narrow one line measured height')
   }
  }
 }
 b += marker('COMPOUND-GRAVITY')
 // The subclass reserves a leading app-icon slot only through its two-arg override.
 b += 'new-instance v0, Lorg/vinix/bootstrap/LabelCheckBox;\nconst v1, @NEUTRALXML@\ninvoke-direct {v0, p0, v1}, Lorg/vinix/bootstrap/LabelCheckBox;-><init>(Landroid/content/Context;I)V\ninvoke-static {v0}, Lorg/vinix/bootstrap/TextProbe;->configure(Landroid/widget/TextView;)V\nconst-string v1, "H"\ninvoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V\nconst/16 v1, 0x13\ninvoke-virtual {v0, v1}, Landroid/widget/TextView;->setGravity(I)V\ninvoke-virtual {v0}, Landroid/view/View;->getPaddingStart()I\nmove-result v1\nconst/16 v2, 31\n' + eq('v1', 'v2', 'styled subclass reserves app icon via overload')
 b += 'move-object v8, v0\nnew-instance v0, Landroid/widget/TextView;\ninvoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V\ninvoke-static {v0}, Lorg/vinix/bootstrap/TextProbe;->configure(Landroid/widget/TextView;)V\nconst-string v1, "H"\ninvoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V\n' + padding(31, 17)
 b += 'const/16 v1, 0x13\ninvoke-virtual {v0, v1}, Landroid/widget/TextView;->setGravity(I)V\nmove-object v5, v0\nmove-object v0, v8\n' + compare_bounds('centered styled subclass app icon reservation')
 b += 'const/4 v1, 0\ninvoke-virtual {v0, v1, v1}, Landroid/view/View;->measure(II)V\ninvoke-virtual {v0}, Landroid/view/View;->getMeasuredWidth()I\nmove-result v6\ninvoke-virtual {v5, v1, v1}, Landroid/view/View;->measure(II)V\ninvoke-virtual {v5}, Landroid/view/View;->getMeasuredWidth()I\nmove-result v7\n' + eq('v6', 'v7', 'styled subclass native text and padding measured width')
 b += marker('STYLED-COMPOUND-TEXT') + 'return-void'
 return method('private static gravity(Landroid/content/Context;)V', b)
}
