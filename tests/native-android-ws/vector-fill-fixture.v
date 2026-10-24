// SPDX-License-Identifier: GPL-2.0-or-later
// Inflate compiled vector XML and inspect real Canvas pixels through ARM/JNI.
module main

import crypto.sha256
import os

const owner = 'Lorg/vinix/bootstrap/VectorFillProbe;'
const drawable = 'Landroid/graphics/drawable/Drawable;'
const bitmap = 'Landroid/graphics/Bitmap;'
const purple = '0xff336699'

fn checked(args []string) {
 r := os.exec(args)
 assert r.exit_code == 0, r.output
}

fn method(signature string, body string, locals int) string {
 return '.method ' + signature + '\n.locals ${locals}\n' + body + '\n.end method\n'
}

fn marker(name string) string {
 return 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-${name}-PASS"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n'
}

fn vector(paths string) string {
 return '<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="24dp" android:height="24dp" android:viewportWidth="24" android:viewportHeight="24">' + paths + '</vector>'
}

fn ring(rule string, opposite bool) string {
 inner := if opposite { 'M8,8V16H16V8Z' } else { 'M8,8H16V16H8Z' }
 return '<path android:fillColor="#ff336699" android:pathData="M2,2H22V22H2Z' + inner + '"' + if rule == '' { '/>' } else { ' android:fillType="' + rule + '"/>' }
}

fn resources() map[string]string {
 // Matching winding in the white ring must still reveal the blue center.
 circle := 'M12,0A12,12 0,0 1,24 12A12,12 0,0 1,12 24A12,12 0,0 1,0 12A12,12 0,0 1,12 0Z'
 dot := 'M15.75,12C15.75,14.071 14.071,15.75 12,15.75C9.929,15.75 8.25,14.071 8.25,12C8.25,9.929 9.929,8.25 12,8.25C14.071,8.25 15.75,9.929 15.75,12Z'
 outer := 'M17.25,12C17.25,14.899 14.899,17.25 12,17.25C9.101,17.25 6.75,14.899 6.75,12C6.75,9.101 9.101,6.75 12,6.75C14.899,6.75 17.25,9.101 17.25,12Z'
 return {
  'even_odd': vector(ring('evenOdd', false))
  'non_zero': vector(ring('nonZero', false))
  'default_rule': vector(ring('', false))
  'opposite': vector(ring('', true))
  'mixed': vector('<group android:scaleX="0.3">' + ring('evenOdd', false) + '</group><group android:translateX="8" android:scaleX="0.3">' + ring('', false) + '</group><group android:translateX="16" android:scaleX="0.3">' + ring('evenOdd', false) + '</group>')
  'transformed': vector('<group android:translateX="4" android:translateY="3" android:scaleX="0.5" android:scaleY="0.5">' + ring('evenOdd', false) + '</group>')
  'clip_after_even_odd': vector('<group>' + ring('evenOdd', false) + '</group><clip-path android:pathData="M2,2H22V22H2ZM8,8H16V16H8Z"/><path android:fillColor="#ff336699" android:pathData="M0,0H24V24H0Z"/>')
  'location': vector('<path android:fillColor="#ffe2eaff" android:pathData="' + circle + '"/><path android:fillColor="#ff0f53ff" android:pathData="' + dot + '"/><path android:fillColor="#ffffffff" android:fillType="evenOdd" android:pathData="' + outer + dot + '"/>')
 }
}

fn pixel(x int, y int, color string, label string) string {
 return 'const/16 v0, ${x}\nconst/16 v1, ${y}\nconst v2, ${color}\nconst-string v3, "${label}"\ninvoke-static {v7, v0, v1, v2, v3}, ${owner}->pixel(${bitmap}IIILjava/lang/String;)V\n'
}

fn render(size int) string {
 return 'const/16 v0, ${size}\ninvoke-static {v6, v0}, ${owner}->draw(${drawable}I)${bitmap}\nmove-result-object v7\n'
}

fn load(id string) string {
 return 'const v0, ${id}\ninvoke-virtual {p0, v0}, Landroid/content/Context;->getDrawable(I)${drawable}\nmove-result-object v6\n'
}

fn probe(ids map[string]string) string {
 mut source := '.class public ${owner}\n.super Ljava/lang/Object;\n'
 mut run := ''
 for name in ['even_odd', 'non_zero', 'default_rule', 'opposite', 'clip_after_even_odd'] {
  center := if name in ['even_odd', 'opposite'] { '0' } else { purple }
  body := load(ids[name]) + render(24) + pixel(12, 12, center, name + ' center') + pixel(4, 12, purple, name + ' outer') + pixel(0, 0, '0', name + ' outside') + 'invoke-virtual {v7}, ${bitmap}->recycle()V\nreturn-void'
  source += method('private static ${name}(Landroid/content/Context;)V', body, 8)
  run += 'invoke-static {p0}, ${owner}->${name}(Landroid/content/Context;)V\n'
 }
 run += marker('VECTOR-FILL-RULES')
 mut mixed := load(ids['mixed']) + render(24)
 for point in [[3, 12, 0], [11, 12, 1], [19, 12, 0], [1, 12, 1], [9, 12, 1], [17, 12, 1]] {
  mixed += pixel(point[0], point[1], if point[2] == 1 { purple } else { '0' }, 'mixed path rule')
 }
 source += method('private static mixed(Landroid/content/Context;)V', mixed + 'invoke-virtual {v7}, ${bitmap}->recycle()V\nreturn-void', 8)
 run += 'invoke-static {p0}, ${owner}->mixed(Landroid/content/Context;)V\n'
 source += method('private static transformed(Landroid/content/Context;)V', load(ids['transformed']) + render(24) + pixel(10, 9, '0', 'transformed hole') + pixel(6, 9, purple, 'transformed outer') + pixel(2, 2, '0', 'transformed outside') + 'invoke-virtual {v7}, ${bitmap}->recycle()V\nreturn-void', 8)
 run += 'invoke-static {p0}, ${owner}->transformed(Landroid/content/Context;)V\n'
 mut copies := load(ids['even_odd'])
 for operation in ['cached', 'newDrawable', 'mutate'] {
  if operation == 'newDrawable' {
   copies += 'invoke-virtual {v6}, ${drawable}->getConstantState()Landroid/graphics/drawable/Drawable$ConstantState;\nmove-result-object v0\ninvoke-virtual {v0}, Landroid/graphics/drawable/Drawable$ConstantState;->newDrawable()${drawable}\nmove-result-object v6\n'
  }
  if operation == 'mutate' { copies += 'invoke-virtual {v6}, ${drawable}->mutate()${drawable}\nmove-result-object v6\n' }
  for size in [24, 24, 48, 48] {
   copies += render(size) + pixel(size / 2, size / 2, '0', operation + ' hole') + pixel(size / 6, size / 2, purple, operation + ' outer') + 'invoke-virtual {v7}, ${bitmap}->recycle()V\n'
  }
 }
 source += method('private static copies(Landroid/content/Context;)V', copies + 'return-void', 8)
 run += 'invoke-static {p0}, ${owner}->copies(Landroid/content/Context;)V\n' + marker('VECTOR-FILL-STATE')
 mut location := load(ids['location'])
 for size in [24, 48] {
  location += render(size) + pixel(size / 2, size / 2, '0xff0f53ff', 'location blue center') + pixel(size * 2 / 3, size / 2, '0xffffffff', 'location white ring') + pixel(size / 6, size / 2, '0xffe2eaff', 'location pale background') + 'invoke-virtual {v7}, ${bitmap}->recycle()V\n'
 }
 source += method('private static location(Landroid/content/Context;)V', location + 'return-void', 8)
 run += 'invoke-static {p0}, ${owner}->location(Landroid/content/Context;)V\n' + marker('VECTOR-LOCATION-GLYPH') + 'return-void'
 return source + method('public static run(Landroid/content/Context;)V', run, 2) + helpers()
}

fn helpers() string {
 return method('private static draw(${drawable}I)${bitmap}', 'sget-object v0, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;\ninvoke-static {p1, p1, v0}, ${bitmap}->createBitmap(IILandroid/graphics/Bitmap$Config;)${bitmap}\nmove-result-object v1\nconst/4 v0, 0\ninvoke-virtual {v1, v0}, ${bitmap}->eraseColor(I)V\nnew-instance v2, Landroid/graphics/Canvas;\ninvoke-direct {v2, v1}, Landroid/graphics/Canvas;-><init>(${bitmap})V\ninvoke-virtual {p0, v0, v0, p1, p1}, ${drawable}->setBounds(IIII)V\ninvoke-virtual {p0, v2}, ${drawable}->draw(Landroid/graphics/Canvas;)V\nreturn-object v1', 3) + method('private static pixel(${bitmap}IIILjava/lang/String;)V', 'move-object v0, p0\nconst/4 v2, 1\nnew-array v1, v2, [I\nconst/4 v2, 0\nconst/4 v3, 1\nmove v4, p1\nmove v5, p2\nconst/4 v6, 1\nconst/4 v7, 1\ninvoke-virtual/range {v0 .. v7}, ${bitmap}->getPixels([IIIIIII)V\nconst/4 v0, 0\naget v1, v1, v0\nif-eq v1, p3, :ok\ninvoke-static {p4, p1, p2, v1, p3}, ${owner}->fail(Ljava/lang/String;IIII)V\n:ok\nreturn-void', 8) + method('private static fail(Ljava/lang/String;IIII)V', r'new-instance v0, Ljava/lang/StringBuilder;
const-string v1, "Vector fill: "
invoke-direct {v0, v1}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V
invoke-virtual {v0, p0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const-string v1, " x="
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v0, p1}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
const-string v1, " y="
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v0, p2}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
const-string v1, " actual="
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v0, p3}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
const-string v1, " expected="
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v0, p4}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
move-result-object v1
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0', 2)
}

fn main() {
 $if prod { panic('assertions required') }
 assert os.args.len == 2, 'OUTPUT'
 out := os.abs_path(os.args[1])
 root := out + '/smali/org/vinix/bootstrap'
 os.mkdir_all(root)!
 os.mkdir_all(out + '/res/drawable')!
 os.write_file(out + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="23" android:targetSdkVersion="35"/><application android:label="Vector fill fixture"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
 for name, xml in resources() { os.write_file(out + '/res/drawable/' + name + '.xml', xml)! }
 java := '/opt/homebrew/opt/openjdk@25/bin/java'
 framework := '/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/framework-res.apk'
 aapt := os.abs_path('build/android-native-ws/aapt2')
 checked([aapt, 'compile', '--dir', out + '/res', '-o', out + '/resources.zip'])
 checked([aapt, 'link', '-I', framework, '--manifest', out + '/AndroidManifest.xml', '--output-text-symbols', out + '/R.txt', '-o', out + '/unsigned.apk', out + '/resources.zip'])
 mut ids := map[string]string{}
 for line in os.read_lines(out + '/R.txt')! {
  parts := line.fields()
  if parts.len == 4 && parts[1] == 'drawable' { ids[parts[2]] = parts[3] }
 }
 assert ids.len == resources().len
 os.write_file(root + '/VectorFillProbe.smali', probe(ids))!
 os.write_file(root + '/Main.smali', '.class public Lorg/vinix/bootstrap/Main;\n.super Landroid/app/Activity;\n' + method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void', 0) + method('public onCreate(Landroid/os/Bundle;)V', 'invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V\nnew-instance v0, Landroid/widget/TextView;\ninvoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V\nconst-string v1, "Vector fill JNI fixture"\ninvoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V\ninvoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V\ninvoke-static {p0}, ' + owner + '->run(Landroid/content/Context;)V\nsget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-READY"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void', 2))!
 checked([java, '-cp', os.abs_path('build/android-framework/tools') + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali', '-o', out + '/classes.dex'])
 checked(['zip', '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'])
 key := out + '/fixture.p12'
 if !os.is_file(key) { checked(['/opt/homebrew/opt/openjdk@25/bin/keytool', '-genkeypair', '-keystore', key, '-storetype', 'PKCS12', '-alias', 'fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650', '-dname', 'CN=Vinix Vector Fill fixture', '-storepass', 'android', '-keypass', 'android']) }
 checked([java, '-jar', os.abs_path('build/android-native-ws/android-15/lib/apksigner.jar'), 'sign', '--ks', key, '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'])
 println('VECTOR-FILL-APK ' + sha256.sum(os.read_bytes(out + '/probe.apk')!).hex())
}
