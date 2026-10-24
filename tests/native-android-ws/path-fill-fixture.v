// SPDX-License-Identifier: GPL-2.0-or-later
// Android/ARM JNI regression: exact Canvas pixels and Java Path fill state.
module main

import crypto.sha256
import os

const owner = 'Lorg/vinix/bootstrap/PathFillProbe;'
const path_class = 'Landroid/graphics/Path;'
const canvas_class = 'Landroid/graphics/Canvas;'
const fill_class = 'Landroid/graphics/Path$FillType;'
const fills = ['WINDING', 'EVEN_ODD', 'INVERSE_WINDING', 'INVERSE_EVEN_ODD']

fn checked(args []string) {
	r := os.exec(args)
	assert r.exit_code == 0, r.output
}

fn method(signature string, body string, locals int) string {
	return '.method ' + signature + '\n.locals ${locals}\n' + body + '\n.end method\n'
}

fn scalar(register string, value f32) string {
	return 'const ${register}, 0x' + unsafe { *(&u32(&value)) }.hex() + '\n'
}

// Explicit vertices test orientation without depending on addRect(Direction).
fn contour(points [][]f32, closed bool) string {
	mut body := ''
	for i, point in points {
		body += scalar('v0', point[0]) + scalar('v1', point[1])
		body += 'invoke-virtual {v6, v0, v1}, ${path_class}->' + if i == 0 { 'moveTo' } else { 'lineTo' } + '(FF)V\n'
	}
	if closed { body += 'invoke-virtual {v6}, ${path_class}->close()V\n' }
	return body
}

fn rectangle(left f32, top f32, right f32, bottom f32, opposite bool, closed bool) string {
	return contour(if opposite { [[left, top], [left, bottom], [right, bottom], [right, top]] } else { [[left, top], [right, top], [right, bottom], [left, bottom]] }, closed)
}

fn set_fill(index int) string {
	return 'sget-object v0, ${fill_class}->${fills[index]}:${fill_class}\ninvoke-virtual {v6, v0}, ${path_class}->setFillType(${fill_class})V\n'
}

fn target() string {
	return 'const/16 v0, 16\nsget-object v1, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;\ninvoke-static {v0, v0, v1}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;\nmove-result-object v8\nconst/4 v0, 0\ninvoke-virtual {v8, v0}, Landroid/graphics/Bitmap;->eraseColor(I)V\nnew-instance v7, ${canvas_class}\ninvoke-direct {v7, v8}, ${canvas_class}-><init>(Landroid/graphics/Bitmap;)V\nconst/4 v0, 1\nconst/16 v1, 15\ninvoke-virtual {v7, v0, v0, v1, v1}, ${canvas_class}->clipRect(IIII)Z\nnew-instance v9, Landroid/graphics/Paint;\ninvoke-direct {v9}, Landroid/graphics/Paint;-><init>()V\nconst v0, 0xff336699\ninvoke-virtual {v9, v0}, Landroid/graphics/Paint;->setColor(I)V\nconst/4 v0, 0\ninvoke-virtual {v9, v0}, Landroid/graphics/Paint;->setAntiAlias(Z)V\n'
}

fn verify(rows []u32, label string) string {
	assert rows.len == 16
	mut body := 'const/16 v0, 16\nnew-array v10, v0, [I\n'
	for i, row in rows { body += 'const/16 v0, ${i}\nconst v1, ${row}\naput v1, v10, v0\n' }
	return body + 'const-string v0, "${label}"\ninvoke-static {v8, v10, v0}, ${owner}->verify(Landroid/graphics/Bitmap;[ILjava/lang/String;)V\ninvoke-virtual {v8}, Landroid/graphics/Bitmap;->recycle()V\nreturn-void'
}

fn mask(kind string, fill int, opposite bool, shifted bool) []u32 {
	mut rows := []u32{len: 16}
	for y in 0 .. 16 {
		for x in 0 .. 16 {
			outer := if shifted { x >= 3 && x < 13 && y >= 3 && y < 8 } else { x >= 2 && x < 14 && y >= 2 && y < 14 }
			inner := if shifted { x >= 5 && x < 11 && y >= 4 && y < 7 } else { x >= 5 && x < 11 && y >= 5 && y < 11 }
			inside := match kind {
				'empty' { false }
				'triangle' { x >= 2 && y >= 2 && x + y <= 15 }
				'multiple' { (x >= 2 && x < 7 && y >= 2 && y < 7) || (x >= 9 && x < 14 && y >= 9 && y < 14) }
				else { outer && (!(opposite || fill & 1 == 1) || !inner) }
			}
			if x >= 1 && x < 15 && y >= 1 && y < 15 && inside != (fill >= 2) { rows[y] |= u32(1) << x }
		}
	}
	return rows
}

fn draw() string { return 'invoke-virtual {v7, v6, v9}, ${canvas_class}->drawPath(${path_class}Landroid/graphics/Paint;)V\n' }
fn new_path() string { return 'new-instance v6, ${path_class}\ninvoke-direct {v6}, ${path_class}-><init>()V\n' }
fn marker(name string) string { return 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-${name}-PASS"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n' }

fn probe() string {
	mut source := '.class public ${owner}\n.super Ljava/lang/Object;\n'
	mut run := ''
	for kind in ['nested', 'empty', 'triangle', 'multiple', 'affine'] {
		for fill in 0 .. 4 {
			for opposite in if kind == 'nested' { [false, true] } else { [false] } {
				name := '${kind}${fill}' + if opposite { 'Opposite' } else { '' }
				mut body := target() + new_path()
				body += match kind {
					'empty' { '' }
					'triangle' { contour([[f32(2), 2], [f32(14.25), 2], [f32(2), 14.25]], false) }
					'multiple' { rectangle(2, 2, 7, 7, false, false) + rectangle(9, 9, 14, 14, false, false) }
					'affine' { rectangle(1, 1, 6, 6, false, true) + rectangle(2, 2, 5, 5, false, true) }
					else { rectangle(2, 2, 14, 14, false, true) + rectangle(5, 5, 11, 11, opposite, true) }
				}
				body += set_fill(fill)
				if kind == 'affine' {
					body += scalar('v0', 1) + scalar('v1', 2) + 'invoke-virtual {v7, v0, v1}, ${canvas_class}->translate(FF)V\n' + scalar('v0', 2) + scalar('v1', 1) + 'invoke-virtual {v7, v0, v1}, ${canvas_class}->scale(FF)V\n'
				}
				body += draw() + verify(mask(kind, fill, opposite, kind == 'affine'), name)
				source += method('private static ${name}()V', body, 11)
				run += 'invoke-static {}, ${owner}->${name}()V\n'
			}
		}
		if kind == 'empty' { run += marker('PATH-FILL-RULES') }
	}
	run += 'invoke-static {}, ${owner}->stroke()V\n' + marker('PATH-CONTOURS')
	for operation in ['copy', 'copyResetSource', 'set', 'self', 'transform', 'transformSelf', 'add', 'reset', 'rewind'] {
		for fill in 0 .. 4 {
			name := '${operation}${fill}'
			mut body := target() + new_path() + rectangle(2, 2, 14, 14, false, true) + rectangle(5, 5, 11, 11, false, true) + set_fill(fill)
			if operation in ['copy', 'copyResetSource'] {
				body += 'new-instance v5, ${path_class}\ninvoke-direct {v5, v6}, ${path_class}-><init>(${path_class})V\n'
				if operation == 'copyResetSource' { body += 'invoke-virtual {v6}, ${path_class}->reset()V\n' }
				body += 'move-object v6, v5\n'
			}
			if operation in ['set', 'add', 'transform'] {
				body += 'move-object v5, v6\n' + new_path() + set_fill((fill + 1) % 4)
				if operation == 'set' { body += 'invoke-virtual {v6, v5}, ${path_class}->set(${path_class})V\n' }
				if operation == 'add' { body += 'invoke-virtual {v6, v5}, ${path_class}->addPath(${path_class})V\n' }
				if operation == 'transform' { body += 'new-instance v4, Landroid/graphics/Matrix;\ninvoke-direct {v4}, Landroid/graphics/Matrix;-><init>()V\ninvoke-virtual {v5, v4, v6}, ${path_class}->transform(Landroid/graphics/Matrix;${path_class})V\n' }
			}
			if operation == 'self' { body += 'invoke-virtual {v6, v6}, ${path_class}->set(${path_class})V\n' }
			if operation == 'transformSelf' { body += 'new-instance v4, Landroid/graphics/Matrix;\ninvoke-direct {v4}, Landroid/graphics/Matrix;-><init>()V\ninvoke-virtual {v6, v4, v6}, ${path_class}->transform(Landroid/graphics/Matrix;${path_class})V\n' }
			if operation in ['reset', 'rewind'] { body += 'invoke-virtual {v6}, ${path_class}->${operation}()V\n' }
			expected := if operation == 'add' { (fill + 1) % 4 } else { fill }
			body += 'invoke-virtual {v6}, ${path_class}->getFillType()${fill_class}\nmove-result-object v0\nsget-object v1, ${fill_class}->${fills[expected]}:${fill_class}\nconst-string v2, "${name} fill state"\ninvoke-static {v0, v1, v2}, ${owner}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V\n'
			body += draw() + verify(mask(if operation in ['reset', 'rewind'] { 'empty' } else { 'nested' }, expected, false, false), name)
			source += method('private static ${name}()V', body, 11)
			run += 'invoke-static {}, ${owner}->${name}()V\n'
		}
	}
	run += 'invoke-static {}, ${owner}->nulls()V\n' + marker('PATH-FILL-STATE') + 'return-void'
	source += method('public static run()V', run, 2)
	source += helpers()
	return source
}

fn helpers() string {
	return method('private static verify(Landroid/graphics/Bitmap;[ILjava/lang/String;)V', r'const/16 v0, 256
new-array v8, v0, [I
move-object v0, p0
move-object v1, v8
const/4 v2, 0
const/16 v3, 16
const/4 v4, 0
const/4 v5, 0
const/16 v6, 16
const/16 v7, 16
invoke-virtual/range {v0 .. v7}, Landroid/graphics/Bitmap;->getPixels([IIIIIII)V
const/4 v9, 0
:loop
shr-int/lit8 v0, v9, 4
aget v1, p1, v0
and-int/lit8 v2, v9, 15
ushr-int/2addr v1, v2
and-int/lit8 v1, v1, 1
const/4 v4, 0
if-eqz v1, :expected
const v4, 0xff336699
:expected
aget v3, v8, v9
if-eq v3, v4, :next
invoke-static {p2, v9, v3, v4}, Lorg/vinix/bootstrap/PathFillProbe;->fail(Ljava/lang/String;III)V
:next
add-int/lit8 v9, v9, 1
const/16 v0, 256
if-lt v9, v0, :loop
return-void', 10) + method('private static fail(Ljava/lang/String;III)V', r'new-instance v0, Ljava/lang/StringBuilder;
const-string v1, "Path fill: "
invoke-direct {v0, v1}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V
invoke-virtual {v0, p0}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
const-string v1, " pixel="
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v0, p1}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
const-string v1, " actual="
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v0, p2}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
const-string v1, " expected="
invoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;
invoke-virtual {v0, p3}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;
invoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;
move-result-object v1
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0', 2) + method('private static same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V', 'if-eq p0, p1, :ok\nconst/4 v0, -1\nconst/4 v1, 0\nconst/4 v2, 1\ninvoke-static {p2, v0, v1, v2}, ${owner}->fail(Ljava/lang/String;III)V\n:ok\nreturn-void', 3) + stroke() + method('private static nulls()V', 'new-instance v6, ${path_class}\nconst/4 v0, 0\ninvoke-direct {v6, v0}, ${path_class}-><init>(${path_class})V\ninvoke-virtual {v6}, ${path_class}->getFillType()${fill_class}\nmove-result-object v0\nsget-object v1, ${fill_class}->WINDING:${fill_class}\nconst-string v2, "null copy fill"\ninvoke-static {v0, v1, v2}, ${owner}->same(Ljava/lang/Object;Ljava/lang/Object;Ljava/lang/String;)V\ninvoke-virtual {v6}, ${path_class}->isEmpty()Z\nmove-result v0\nif-nez v0, :empty\nconst/4 v1, -1\nconst/4 v2, 0\nconst/4 v3, 1\nconst-string v0, "null copy geometry"\ninvoke-static {v0, v1, v2, v3}, ${owner}->fail(Ljava/lang/String;III)V\n:empty\n:try_start\nconst/4 v0, 0\ninvoke-virtual {v6, v0}, ${path_class}->setFillType(${fill_class})V\n:try_end\nconst-string v0, "null fill must throw immediately"\nconst/4 v1, -1\nconst/4 v2, 0\nconst/4 v3, 1\ninvoke-static {v0, v1, v2, v3}, ${owner}->fail(Ljava/lang/String;III)V\nreturn-void\n:catch\nmove-exception v0\nreturn-void\n.catch Ljava/lang/NullPointerException; {:try_start .. :try_end} :catch', 7)
}

fn stroke() string {
	mut body := target() + new_path() + contour([[f32(3), 3], [f32(12), 3], [f32(12), 12]], false)
	body += 'sget-object v0, Landroid/graphics/Paint$Style;->STROKE:Landroid/graphics/Paint$Style;\ninvoke-virtual {v9, v0}, Landroid/graphics/Paint;->setStyle(Landroid/graphics/Paint$Style;)V\n' + scalar('v0', 1) + 'invoke-virtual {v9, v0}, Landroid/graphics/Paint;->setStrokeWidth(F)V\n' + draw()
	for point in [[7, 3, 1], [12, 7, 1], [7, 7, 0]] {
		body += 'const/16 v0, ${point[0]}\nconst/16 v1, ${point[1]}\nconst v2, ' + if point[2] == 1 { '0xff336699' } else { '0' } + '\ninvoke-static {v8, v0, v1, v2}, ${owner}->pixel(Landroid/graphics/Bitmap;III)V\n'
	}
	body += 'invoke-virtual {v6}, ${path_class}->close()V\n' + draw() + 'const/4 v0, 7\nconst v1, 0xff336699\ninvoke-static {v8, v0, v0, v1}, ${owner}->pixel(Landroid/graphics/Bitmap;III)V\ninvoke-virtual {v8}, Landroid/graphics/Bitmap;->recycle()V\nreturn-void'
	return method('private static stroke()V', body, 11) + method('private static pixel(Landroid/graphics/Bitmap;III)V', 'move-object v0, p0\nconst/4 v2, 1\nnew-array v1, v2, [I\nconst/4 v2, 0\nconst/4 v3, 1\nmove v4, p1\nmove v5, p2\nconst/4 v6, 1\nconst/4 v7, 1\ninvoke-virtual/range {v0 .. v7}, Landroid/graphics/Bitmap;->getPixels([IIIIIII)V\nconst/4 v0, 0\naget v1, v1, v0\nif-eq v1, p3, :ok\nconst-string v0, "stroke closure"\ninvoke-static {v0, p1, v1, p3}, ${owner}->fail(Ljava/lang/String;III)V\n:ok\nreturn-void', 8)
}

fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 2, 'OUTPUT'
	out := os.abs_path(os.args[1])
	root := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(root)!
	os.write_file(out + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="23" android:targetSdkVersion="35"/><application android:label="Path fill fixture"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
	os.write_file(root + '/PathFillProbe.smali', probe())!
	os.write_file(root + '/Main.smali', '.class public Lorg/vinix/bootstrap/Main;\n.super Landroid/app/Activity;\n' + method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void', 0) + method('public onCreate(Landroid/os/Bundle;)V', 'invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V\nnew-instance v0, Landroid/widget/TextView;\ninvoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V\nconst-string v1, "Path fill JNI fixture"\ninvoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V\ninvoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V\ninvoke-static {}, ${owner}->run()V\n' + marker('PATH-FILL') + 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-READY"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void', 2))!
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	resources := '/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/framework-res.apk'
	checked([os.abs_path('build/android-native-ws/aapt2'), 'link', '-I', resources, '--manifest', out + '/AndroidManifest.xml', '-o', out + '/unsigned.apk'])
	checked([java, '-cp', os.abs_path('build/android-framework/tools') + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali', '-o', out + '/classes.dex'])
	checked(['zip', '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'])
	key := out + '/fixture.p12'
	if !os.is_file(key) { checked(['/opt/homebrew/opt/openjdk@25/bin/keytool', '-genkeypair', '-keystore', key, '-storetype', 'PKCS12', '-alias', 'fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650', '-dname', 'CN=Vinix Path fill fixture', '-storepass', 'android', '-keypass', 'android']) }
	checked([java, '-jar', os.abs_path('build/android-native-ws/android-15/lib/apksigner.jar'), 'sign', '--ks', key, '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'])
	println('PATH-FILL-APK ' + sha256.sum(os.read_bytes(out + '/probe.apk')!).hex())
}
