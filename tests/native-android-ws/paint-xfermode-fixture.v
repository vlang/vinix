// SPDX-License-Identifier: GPL-2.0-or-later
// JNI pixels for Maps' layered child followed by a black DST_IN oval mask.
module main

import crypto.sha256
import os

const probe_class = 'Lorg/vinix/bootstrap/PaintXfermodeProbe;'
const bitmap_class = 'Landroid/graphics/Bitmap;'
const paint_class = 'Landroid/graphics/Paint;'
const canvas_class = 'Landroid/graphics/Canvas;'

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

fn marker(name string) string {
	return 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-${name}-PASS"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n'
}

fn target(width int, height int, color u32) string {
	return target_config(width, height, color, 'ARGB_8888')
}

fn target_config(width int, height int, color u32, config string) string {
	return 'const/16 v0, ${width}\nconst/16 v1, ${height}\nsget-object v2, Landroid/graphics/Bitmap\$Config;->${config}:Landroid/graphics/Bitmap\$Config;\ninvoke-static {v0, v1, v2}, ${bitmap_class}->createBitmap(IILandroid/graphics/Bitmap\$Config;)${bitmap_class}\nmove-result-object v8\nconst v0, 0x${color.hex()}\ninvoke-virtual {v8, v0}, ${bitmap_class}->eraseColor(I)V\nnew-instance v9, ${canvas_class}\ninvoke-direct {v9, v8}, ${canvas_class}-><init>(${bitmap_class})V\n'
}

fn mask_source(config string) string {
	// Upload explicitly: the frozen provider's source-array createBitmap overload
	// allocates a bitmap without copying the supplied colors.
	return 'const/4 v0, 5\nconst/4 v1, 1\nsget-object v2, Landroid/graphics/Bitmap\$Config;->${config}:Landroid/graphics/Bitmap\$Config;\ninvoke-static {v0, v1, v2}, ${bitmap_class}->createBitmap(IILandroid/graphics/Bitmap\$Config;)${bitmap_class}\nmove-result-object v10\nconst/4 v1, 5\nnew-array v1, v1, [I\nfill-array-data v1, :mask\nmove-object v0, v10\nconst/4 v2, 0\nconst/4 v3, 5\nconst/4 v4, 0\nconst/4 v5, 0\nconst/4 v6, 5\nconst/4 v7, 1\ninvoke-virtual/range {v0 .. v7}, ${bitmap_class}->setPixels([IIIIIII)V\n'
}

fn mask_data() string {
	// Nonblack RGB proves DST_IN uses alpha alone, including alpha-zero pixels.
	return '\n:mask\n.array-data 4\n0x00123456\n0x01123456\n0x7fabcdef\n0x80ff00ff\n0xff00ffff\n.end array-data'
}

fn xfermode() string {
	return 'new-instance v11, ${paint_class}\ninvoke-direct {v11}, ${paint_class}-><init>()V\nnew-instance v0, Landroid/graphics/PorterDuffXfermode;\nsget-object v1, Landroid/graphics/PorterDuff\$Mode;->DST_IN:Landroid/graphics/PorterDuff\$Mode;\ninvoke-direct {v0, v1}, Landroid/graphics/PorterDuffXfermode;-><init>(Landroid/graphics/PorterDuff\$Mode;)V\ninvoke-virtual {v11, v0}, ${paint_class}->setXfermode(Landroid/graphics/Xfermode;)Landroid/graphics/Xfermode;\nmove-result-object v1\nif-eq v0, v1, :identity\nconst-string v0, "setXfermode return identity"\ninvoke-static {v0}, ${probe_class}->fail(Ljava/lang/String;)V\n:identity\ninvoke-virtual {v11}, ${paint_class}->getXfermode()Landroid/graphics/Xfermode;\nmove-result-object v1\nif-eq v0, v1, :state\nconst-string v0, "getXfermode identity"\ninvoke-static {v0}, ${probe_class}->fail(Ljava/lang/String;)V\n:state\n'
}

fn draw_mask() string {
	return 'const/4 v0, 0\ninvoke-virtual {v9, v10, v0, v0, v11}, ${canvas_class}->drawBitmap(${bitmap_class}FF${paint_class})V\n'
}

fn verify(width int, colors []u32, name string) string {
	mut body := 'const/16 v0, ${colors.len}\nnew-array v0, v0, [I\n'
	for i, color in colors {
		body += 'const/16 v1, ${i}\nconst v2, 0x${color.hex()}\naput v2, v0, v1\n'
	}
	return body + 'const/16 v1, ${width}\nconst-string v2, "${name}"\ninvoke-static {v8, v0, v1, v2}, ${probe_class}->verify(${bitmap_class}[IILjava/lang/String;)V\n'
}

fn probe() string {
	mut source := '.class public ${probe_class}\n.super Ljava/lang/Object;\n'
	mut run := ''
	for operation in ['direct', 'copy', 'set', 'self', 'alpha0', 'alpha1', 'alpha127', 'alpha128', 'alpha255', 'null', 'reset', 'src_over'] {
		mut body := target(5, 1, 0x80336699) + mask_source('ARGB_8888') + xfermode()
		if operation in ['copy', 'set', 'self'] {
			body += 'move-object v12, v0\n'
		}
		if operation == 'copy' {
			body += 'new-instance v0, ${paint_class}\ninvoke-direct {v0, v11}, ${paint_class}-><init>(${paint_class})V\nmove-object v11, v0\n'
		}
		if operation == 'set' {
			body += 'new-instance v0, ${paint_class}\ninvoke-direct {v0}, ${paint_class}-><init>()V\ninvoke-virtual {v0, v11}, ${paint_class}->set(${paint_class})V\nmove-object v11, v0\n'
		}
		if operation == 'self' {
			body += 'invoke-virtual {v11, v11}, ${paint_class}->set(${paint_class})V\n'
		}
		if operation in ['copy', 'set', 'self'] {
			body += 'invoke-virtual {v11}, ${paint_class}->getXfermode()Landroid/graphics/Xfermode;\nmove-result-object v0\nif-eq v0, v12, :retained\nconst-string v0, "${operation} Xfermode identity"\ninvoke-static {v0}, ${probe_class}->fail(Ljava/lang/String;)V\n:retained\n'
		}
		if operation.starts_with('alpha') {
			alpha := operation[5..].int()
			body += 'const/16 v0, ${alpha}\ninvoke-virtual {v11, v0}, ${paint_class}->setAlpha(I)V\n'
		}
		if operation == 'null' {
			body += 'const/4 v0, 0\ninvoke-virtual {v11, v0}, ${paint_class}->setXfermode(Landroid/graphics/Xfermode;)Landroid/graphics/Xfermode;\nmove-result-object v0\nif-eqz v0, :cleared\nconst-string v0, "null setter return"\ninvoke-static {v0}, ${probe_class}->fail(Ljava/lang/String;)V\n:cleared\n'
		}
		if operation == 'reset' { body += 'invoke-virtual {v11}, ${paint_class}->reset()V\n' }
		if operation == 'src_over' {
			body += 'new-instance v0, Landroid/graphics/PorterDuffXfermode;\nsget-object v1, Landroid/graphics/PorterDuff\$Mode;->SRC_OVER:Landroid/graphics/PorterDuff\$Mode;\ninvoke-direct {v0, v1}, Landroid/graphics/PorterDuffXfermode;-><init>(Landroid/graphics/PorterDuff\$Mode;)V\ninvoke-virtual {v11, v0}, ${paint_class}->setXfermode(Landroid/graphics/Xfermode;)Landroid/graphics/Xfermode;\nmove-result-object v1\nif-eq v0, v1, :default_return\nconst-string v0, "SRC_OVER setter return identity"\ninvoke-static {v0}, ${probe_class}->fail(Ljava/lang/String;)V\n:default_return\ninvoke-virtual {v11}, ${paint_class}->getXfermode()Landroid/graphics/Xfermode;\nmove-result-object v1\nif-eq v0, v1, :default_state\nconst-string v0, "SRC_OVER getter identity"\ninvoke-static {v0}, ${probe_class}->fail(Ljava/lang/String;)V\n:default_state\n'
		}
		if operation in ['null', 'reset'] {
			body += 'invoke-virtual {v11}, ${paint_class}->getXfermode()Landroid/graphics/Xfermode;\nmove-result-object v0\nif-eqz v0, :empty\nconst-string v0, "${operation} Xfermode clearing"\ninvoke-static {v0}, ${probe_class}->fail(Ljava/lang/String;)V\n:empty\n'
		}
		body += draw_mask()
		if operation in ['null', 'reset', 'src_over'] {
			// Clearing or resetting native mode must match untouched source-over.
			body += 'move-object v12, v8\n' + target(5, 1, 0x80336699) + 'new-instance v11, ${paint_class}\ninvoke-direct {v11}, ${paint_class}-><init>()V\n' + draw_mask() + 'const-string v0, "${operation} source-over restoration"\ninvoke-static {v8, v12, v0}, ${probe_class}->same(${bitmap_class}${bitmap_class}Ljava/lang/String;)V\ninvoke-virtual {v12}, ${bitmap_class}->recycle()V\n'
		} else {
			colors := match operation {
				'alpha0', 'alpha1' { [u32(0), 0, 0, 0, 0] }
				'alpha127' { [u32(0), 0, 0x1f336699, 0x1f336699, 0x3f336699] }
				'alpha128' { [u32(0), 0, 0x1f336699, 0x20336699, 0x40336699] }
				else { [u32(0), 0, 0x3f336699, 0x40336699, 0x80336699] }
			}
			body += verify(5, colors, operation)
		}
		body += 'invoke-virtual {v8}, ${bitmap_class}->recycle()V\ninvoke-virtual {v10}, ${bitmap_class}->recycle()V\nreturn-void' + mask_data()
		source += method('private static ${operation}()V', body, 13)
		run += 'invoke-static {}, ${probe_class}->${operation}()V\n'
	}
	for source_config in ['ARGB_8888', 'ALPHA_8'] {
		for destination_config in ['ARGB_8888', 'ALPHA_8'] {
			name := source_config + '_' + destination_config
			mut body := target_config(5, 1, 0x80336699, destination_config) + mask_source(source_config) + xfermode() + draw_mask()
			body += verify(5, if destination_config == 'ALPHA_8' { [u32(0), 0, 0x3f000000, 0x40000000, 0x80000000] } else { [u32(0), 0, 0x3f336699, 0x40336699, 0x80336699] }, name)
			body += 'invoke-virtual {v8}, ${bitmap_class}->recycle()V\ninvoke-virtual {v10}, ${bitmap_class}->recycle()V\nreturn-void' + mask_data()
			source += method('private static ${name}()V', body, 13)
			run += 'invoke-static {}, ${probe_class}->${name}()V\n'
		}
	}
	source += affine()
	run += 'invoke-static {}, ${probe_class}->affine()V\n' + marker('PAINT-DST-IN')
	run += 'invoke-static {p0}, ${probe_class}->layer(Landroid/content/Context;)V\n' + marker('PAINT-DST-IN-LAYER') + 'return-void'
	source += method('public static run(Landroid/content/Context;)V', run, 2)
	source += helpers() + layer()
	return source
}

fn affine() string {
	mut body := target(8, 6, 0x80336699) + mask_source('ARGB_8888') + xfermode()
	body += 'const/4 v0, 2\nconst/4 v1, 6\nconst/4 v2, 4\ninvoke-virtual {v9, v0, v0, v1, v2}, ${canvas_class}->clipRect(IIII)Z\n'
	body += scalar('v0', 1) + scalar('v1', 2) + 'invoke-virtual {v9, v0, v1}, ${canvas_class}->translate(FF)V\n'
	body += scalar('v0', 2) + 'invoke-virtual {v9, v0, v0}, ${canvas_class}->scale(FF)V\n' + draw_mask()
	mut colors := []u32{len: 48, init: 0x80336699}
	for y in 2 .. 4 {
		colors[y * 8 + 2] = 0
		colors[y * 8 + 3] = 0
		colors[y * 8 + 4] = 0
		colors[y * 8 + 5] = 0x3f336699
	}
	body += verify(8, colors, 'affine clip') + 'invoke-virtual {v8}, ${bitmap_class}->recycle()V\ninvoke-virtual {v10}, ${bitmap_class}->recycle()V\nreturn-void' + mask_data()
	return method('private static affine()V', body, 13)
}

fn helpers() string {
	return method('private static fail(Ljava/lang/String;)V', 'new-instance v0, Ljava/lang/AssertionError;\ninvoke-direct {v0, p0}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0', 1) +
		method('private static pixels(${bitmap_class})[I', 'invoke-virtual {p0}, ${bitmap_class}->getWidth()I\nmove-result v3\ninvoke-virtual {p0}, ${bitmap_class}->getHeight()I\nmove-result v7\nmul-int v0, v3, v7\nnew-array v1, v0, [I\nmove-object v0, p0\nconst/4 v2, 0\nconst/4 v4, 0\nconst/4 v5, 0\nmove v6, v3\ninvoke-virtual/range {v0 .. v7}, ${bitmap_class}->getPixels([IIIIIII)V\nreturn-object v1', 8) +
		method('private static verify(${bitmap_class}[IILjava/lang/String;)V', 'invoke-static {p0}, ${probe_class}->pixels(${bitmap_class})[I\nmove-result-object v0\nconst/4 v1, 0\narray-length v2, v0\n:loop\naget v3, v0, v1\naget v4, p1, v1\nif-ne v3, v4, :bad\nadd-int/lit8 v1, v1, 1\nif-lt v1, v2, :loop\nreturn-void\n:bad\nnew-instance v0, Ljava/lang/StringBuilder;\ninvoke-direct {v0, p3}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V\nconst-string v2, " pixel="\ninvoke-virtual {v0, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\ninvoke-virtual {v0, v1}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;\nconst-string v2, " actual="\ninvoke-virtual {v0, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\ninvoke-virtual {v0, v3}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;\nconst-string v2, " expected="\ninvoke-virtual {v0, v2}, Ljava/lang/StringBuilder;->append(Ljava/lang/String;)Ljava/lang/StringBuilder;\ninvoke-virtual {v0, v4}, Ljava/lang/StringBuilder;->append(I)Ljava/lang/StringBuilder;\ninvoke-virtual {v0}, Ljava/lang/StringBuilder;->toString()Ljava/lang/String;\nmove-result-object v0\ninvoke-static {v0}, ${probe_class}->fail(Ljava/lang/String;)V\nreturn-void', 5) +
		method('private static same(${bitmap_class}${bitmap_class}Ljava/lang/String;)V', 'invoke-static {p1}, ${probe_class}->pixels(${bitmap_class})[I\nmove-result-object v0\ninvoke-virtual {p1}, ${bitmap_class}->getWidth()I\nmove-result v1\ninvoke-static {p0, v0, v1, p2}, ${probe_class}->verify(${bitmap_class}[IILjava/lang/String;)V\nreturn-void', 2)
}

fn layer() string {
	mut body := 'new-instance v10, Landroid/widget/FrameLayout;\ninvoke-direct {v10, p0}, Landroid/widget/FrameLayout;-><init>(Landroid/content/Context;)V\nnew-instance v11, Lorg/vinix/bootstrap/MaskLayer;\ninvoke-direct {v11, p0}, Lorg/vinix/bootstrap/MaskLayer;-><init>(Landroid/content/Context;)V\ninvoke-virtual {v10, v11}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V\nconst/4 v0, 0\nconst/16 v1, 8\ninvoke-virtual {v10, v0, v0, v1, v1}, Landroid/view/View;->layout(IIII)V\ninvoke-virtual {v11, v0, v0, v1, v1}, Landroid/view/View;->layout(IIII)V\nnew-instance v12, Landroid/view/View;\ninvoke-direct {v12, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V\nconst v0, 0xff336699\ninvoke-virtual {v12, v0}, Landroid/view/View;->setBackgroundColor(I)V\ninvoke-virtual {v11, v12}, Landroid/view/ViewGroup;->addView(Landroid/view/View;)V\nconst/4 v0, 0\nconst/16 v1, 8\ninvoke-virtual {v12, v0, v0, v1, v1}, Landroid/view/View;->layout(IIII)V\n'
	body += target(8, 8, 0xffeecc88) + 'invoke-virtual {v10, v9}, Landroid/view/View;->draw(${canvas_class})V\n'
	// Validate the complete oval raster, so the transparent corners must retain
	// the destination background rather than black or a cleared screen pixel.
	mut colors := []u32{len: 64}
	for y in 0 .. 8 {
		for x in 0 .. 8 {
			xx := f32(x) + 0.5 - 4
			yy := f32(y) + 0.5 - 4
			colors[y * 8 + x] = if xx * xx + yy * yy <= 16 { u32(0xff336699) } else { u32(0xffeecc88) }
		}
	}
	body += verify(8, colors, 'Maps layered oval mask')
	// Draw again using the retained layer and mask: no stale opaque corner.
	body += 'const v0, 0xffeecc88\ninvoke-virtual {v8, v0}, ${bitmap_class}->eraseColor(I)V\ninvoke-virtual {v10, v9}, Landroid/view/View;->draw(${canvas_class})V\n' + verify(8, colors, 'Maps layered oval mask reuse') + 'invoke-virtual {v8}, ${bitmap_class}->recycle()V\nreturn-void'
	return method('private static layer(Landroid/content/Context;)V', body, 13)
}

fn mask_layer() string {
	return '.class public Lorg/vinix/bootstrap/MaskLayer;\n.super Landroid/widget/FrameLayout;\n.field private mask:${bitmap_class}\n.field private paint:${paint_class}\n' +
		method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, Landroid/widget/FrameLayout;-><init>(Landroid/content/Context;)V\nconst/4 v0, 2\nconst/4 v1, 0\ninvoke-virtual {p0, v0, v1}, Landroid/view/View;->setLayerType(I${paint_class})V\nnew-instance v0, ${paint_class}\ninvoke-direct {v0}, ${paint_class}-><init>()V\nnew-instance v1, Landroid/graphics/PorterDuffXfermode;\nsget-object v2, Landroid/graphics/PorterDuff\$Mode;->DST_IN:Landroid/graphics/PorterDuff\$Mode;\ninvoke-direct {v1, v2}, Landroid/graphics/PorterDuffXfermode;-><init>(Landroid/graphics/PorterDuff\$Mode;)V\ninvoke-virtual {v0, v1}, ${paint_class}->setXfermode(Landroid/graphics/Xfermode;)Landroid/graphics/Xfermode;\niput-object v0, p0, Lorg/vinix/bootstrap/MaskLayer;->paint:${paint_class}\nreturn-void', 3) +
		method('protected dispatchDraw(${canvas_class})V', 'invoke-super {p0, p1}, Landroid/widget/FrameLayout;->dispatchDraw(${canvas_class})V\niget-object v6, p0, Lorg/vinix/bootstrap/MaskLayer;->mask:${bitmap_class}\nif-nez v6, :draw\nconst/16 v0, 8\nsget-object v1, Landroid/graphics/Bitmap\$Config;->ARGB_8888:Landroid/graphics/Bitmap\$Config;\ninvoke-static {v0, v0, v1}, ${bitmap_class}->createBitmap(IILandroid/graphics/Bitmap\$Config;)${bitmap_class}\nmove-result-object v6\nnew-instance v0, ${canvas_class}\ninvoke-direct {v0, v6}, ${canvas_class}-><init>(${bitmap_class})V\nnew-instance v2, ${paint_class}\ninvoke-direct {v2}, ${paint_class}-><init>()V\nnew-instance v1, Landroid/graphics/RectF;\nconst/4 v3, 0\nconst/high16 v4, 0x41000000\ninvoke-direct {v1, v3, v3, v4, v4}, Landroid/graphics/RectF;-><init>(FFFF)V\ninvoke-virtual {v0, v1, v2}, ${canvas_class}->drawOval(Landroid/graphics/RectF;${paint_class})V\niput-object v6, p0, Lorg/vinix/bootstrap/MaskLayer;->mask:${bitmap_class}\n:draw\niget-object v0, p0, Lorg/vinix/bootstrap/MaskLayer;->paint:${paint_class}\nconst/4 v1, 0\ninvoke-virtual {p1, v6, v1, v1, v0}, ${canvas_class}->drawBitmap(${bitmap_class}FF${paint_class})V\nreturn-void', 7)
}

fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 2, 'OUTPUT'
	out := os.abs_path(os.args[1])
	root := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(root)!
	os.write_file(out + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="23" android:targetSdkVersion="35"/><application android:label="Paint DST_IN fixture"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
	os.write_file(root + '/PaintXfermodeProbe.smali', probe())!
	os.write_file(root + '/MaskLayer.smali', mask_layer())!
	os.write_file(root + '/Main.smali', '.class public Lorg/vinix/bootstrap/Main;\n.super Landroid/app/Activity;\n' + method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void', 0) + method('public onCreate(Landroid/os/Bundle;)V', 'invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V\nnew-instance v0, Landroid/widget/TextView;\ninvoke-direct {v0, p0}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V\nconst-string v1, "Paint DST_IN JNI fixture"\ninvoke-virtual {v0, v1}, Landroid/widget/TextView;->setText(Ljava/lang/CharSequence;)V\ninvoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V\ninvoke-static {p0}, ${probe_class}->run(Landroid/content/Context;)V\n' + marker('PAINT-XFERMODE') + 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-READY"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\nreturn-void', 2))!
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	resources := '/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/framework-res.apk'
	checked([os.abs_path('build/android-native-ws/aapt2'), 'link', '-I', resources, '--manifest', out + '/AndroidManifest.xml', '-o', out + '/unsigned.apk'])
	checked([java, '-cp', os.abs_path('build/android-framework/tools') + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali', '-o', out + '/classes.dex'])
	checked(['zip', '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'])
	key := out + '/fixture.p12'
	if !os.is_file(key) { checked(['/opt/homebrew/opt/openjdk@25/bin/keytool', '-genkeypair', '-keystore', key, '-storetype', 'PKCS12', '-alias', 'fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650', '-dname', 'CN=Vinix Paint Xfermode fixture', '-storepass', 'android', '-keypass', 'android']) }
	checked([java, '-jar', os.abs_path('build/android-native-ws/android-15/lib/apksigner.jar'), 'sign', '--ks', key, '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'])
	println('PAINT-XFERMODE-APK ' + sha256.sum(os.read_bytes(out + '/probe.apk')!).hex())
}
