// SPDX-License-Identifier: GPL-2.0-or-later
// One signed APK checks decoded nine-patch geometry on both framework versions.
module main

import compress.zlib
import crypto.sha256
import encoding.binary
import hash.crc32
import json2
import os
import time

const probe = 'Lorg/vinix/bootstrap/NinePatchProbe;'
const drawable = 'Landroid/graphics/drawable/Drawable;'
const nine_patch = 'Landroid/graphics/drawable/NinePatchDrawable;'
const bitmap = 'Landroid/graphics/Bitmap;'
const view = 'Lorg/vinix/bootstrap/NinePatchView;'

fn method(signature string, body string, locals int) string {
	return '.method ' + signature + '\n.locals ${locals}\n' + body + '\n.end method\n'
}

fn line_marker(value string) string {
	return 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\n' +
		'const-string v1, "${value}"\n' +
		'invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n'
}

fn marker(name string) string {
	return line_marker('BOOTSTRAP-NINE-PATCH-DIMENSIONS-${name}PASS')
}

fn helper_methods(chunk []u8) string {
	mut s := method('private static equal(IILjava/lang/String;)V', '
if-eq p0, p1, :ok
new-instance v0, Ljava/lang/StringBuilder;
const-string v1, "NinePatch dimensions: "
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
return-void', 2)
	s += method('private static dimensions(${drawable}IILjava/lang/String;)V', '
invoke-virtual {p0}, ${drawable}->getIntrinsicWidth()I
move-result v0
const-string v1, " width"
invoke-virtual {p3, v1}, Ljava/lang/String;->concat(Ljava/lang/String;)Ljava/lang/String;
move-result-object v1
invoke-static {v0, p1, v1}, ${probe}->equal(IILjava/lang/String;)V
invoke-virtual {p0}, ${drawable}->getIntrinsicHeight()I
move-result v0
const-string v1, " height"
invoke-virtual {p3, v1}, Ljava/lang/String;->concat(Ljava/lang/String;)Ljava/lang/String;
move-result-object v1
invoke-static {v0, p2, v1}, ${probe}->equal(IILjava/lang/String;)V
return-void', 2)
	s += method('private static traceAbsent()V', '
invoke-static {}, Ljava/lang/System;->getenv()Ljava/util/Map;
move-result-object v0
invoke-interface {v0}, Ljava/util/Map;->keySet()Ljava/util/Set;
move-result-object v0
invoke-interface {v0}, Ljava/util/Set;->iterator()Ljava/util/Iterator;
move-result-object v2
:next
invoke-interface {v2}, Ljava/util/Iterator;->hasNext()Z
move-result v0
if-eqz v0, :good
invoke-interface {v2}, Ljava/util/Iterator;->next()Ljava/lang/Object;
move-result-object v0
check-cast v0, Ljava/lang/String;
const-string v1, "VINIX_ANDROID_TRACE_"
invoke-virtual {v0, v1}, Ljava/lang/String;->startsWith(Ljava/lang/String;)Z
move-result v0
if-eqz v0, :next
const/4 v0, 0
const/4 v1, 1
const-string v3, "trace variables must be absent"
invoke-static {v0, v1, v3}, ${probe}->equal(IILjava/lang/String;)V
:good
' + marker('TRACE-ENV-ABSENT-') + 'return-void', 4)
	mut bytes := ''
	for b in chunk { bytes += '${int(i8(b))}\n' }
	// This is the real npTc chunk extracted from the aapt2-compiled thumb PNG.
	s += method('private static chunk()[B', 'const/16 v0, ${chunk.len}\nnew-array v0, v0, [B\nfill-array-data v0, :data\nreturn-object v0\n:data\n.array-data 1\n' + bytes + '.end array-data', 1)
	return s
}

fn resources_probe() string {
	return method('private static resources(Landroid/content/Context;)V', '
invoke-virtual {p0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;
move-result-object v6
const-string v0, "thumb"
const-string v1, "drawable"
const-string v2, "org.vinix.bootstrap"
invoke-virtual {v6, v0, v1, v2}, Landroid/content/res/Resources;->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I
move-result v7
sput v7, ${probe}->thumbId:I
invoke-virtual {v6, v7}, Landroid/content/res/Resources;->getDrawable(I)${drawable}
move-result-object v8
instance-of v0, v8, ${nine_patch}
const/4 v1, 1
const-string v2, "resource decodes as NinePatchDrawable"
invoke-static {v0, v1, v2}, ${probe}->equal(IILjava/lang/String;)V
' + line_marker('BOOTSTRAP-NINE-PATCH-DIMENSIONS-CALL') + '
const/16 v0, 21
const/16 v1, 15
const-string v2, "resource thumb"
invoke-static {v8, v0, v1, v2}, ${probe}->dimensions(${drawable}IILjava/lang/String;)V
sput-object v8, ${probe}->thumb:${drawable}
# Independent bitmap decode establishes the same raw PNG dimensions.
invoke-static {v6, v7}, Landroid/graphics/BitmapFactory;->decodeResource(Landroid/content/res/Resources;I)${bitmap}
move-result-object v8
invoke-virtual {v8}, ${bitmap}->getWidth()I
move-result v0
const/16 v1, 21
const-string v2, "decoded thumb bitmap width"
invoke-static {v0, v1, v2}, ${probe}->equal(IILjava/lang/String;)V
invoke-virtual {v8}, ${bitmap}->getHeight()I
move-result v0
const/16 v1, 15
const-string v2, "decoded thumb bitmap height"
invoke-static {v0, v1, v2}, ${probe}->equal(IILjava/lang/String;)V
invoke-virtual {v8}, ${bitmap}->recycle()V
const-string v0, "track"
const-string v1, "drawable"
const-string v2, "org.vinix.bootstrap"
invoke-virtual {v6, v0, v1, v2}, Landroid/content/res/Resources;->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I
move-result v7
invoke-virtual {v6, v7}, Landroid/content/res/Resources;->getDrawable(I)${drawable}
move-result-object v8
const/16 v0, 29
const/16 v1, 9
const-string v2, "resource track"
invoke-static {v8, v0, v1, v2}, ${probe}->dimensions(${drawable}IILjava/lang/String;)V
sput-object v8, ${probe}->track:${drawable}
new-instance v8, Landroid/graphics/drawable/ColorDrawable;
const v0, 0xff123456
invoke-direct {v8, v0}, Landroid/graphics/drawable/ColorDrawable;-><init>(I)V
const/4 v0, -1
const-string v2, "base drawable default"
invoke-static {v8, v0, v0, v2}, ${probe}->dimensions(${drawable}IILjava/lang/String;)V
' + marker('RESOURCE-') + 'return-void', 9)
}

fn file_probe() string {
	return method('private static file(Landroid/content/Context;)V', '
invoke-virtual {p0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;
move-result-object v0
sget v1, ${probe}->thumbId:I
invoke-virtual {v0, v1}, Landroid/content/res/Resources;->openRawResource(I)Ljava/io/InputStream;
move-result-object v6
invoke-virtual {p0}, Landroid/content/Context;->getCacheDir()Ljava/io/File;
move-result-object v0
new-instance v7, Ljava/io/File;
const-string v1, "copied-thumb.9.png"
invoke-direct {v7, v0, v1}, Ljava/io/File;-><init>(Ljava/io/File;Ljava/lang/String;)V
new-instance v8, Ljava/io/FileOutputStream;
invoke-direct {v8, v7}, Ljava/io/FileOutputStream;-><init>(Ljava/io/File;)V
const/16 v0, 1024
new-array v5, v0, [B
:copy
invoke-virtual {v6, v5}, Ljava/io/InputStream;->read([B)I
move-result v2
if-ltz v2, :copied
const/4 v0, 0
invoke-virtual {v8, v5, v0, v2}, Ljava/io/FileOutputStream;->write([BII)V
goto :copy
:copied
invoke-virtual {v8}, Ljava/io/FileOutputStream;->close()V
invoke-virtual {v6}, Ljava/io/InputStream;->close()V
invoke-virtual {v7}, Ljava/io/File;->getPath()Ljava/lang/String;
move-result-object v0
invoke-static {v0}, ${drawable}->createFromPath(Ljava/lang/String;)${drawable}
move-result-object v6
instance-of v0, v6, ${nine_patch}
const/4 v1, 1
const-string v2, "file path selects NinePatchDrawable"
invoke-static {v0, v1, v2}, ${probe}->equal(IILjava/lang/String;)V
const/16 v0, 21
const/16 v1, 15
const-string v2, "copied compiled file"
invoke-static {v6, v0, v1, v2}, ${probe}->dimensions(${drawable}IILjava/lang/String;)V
' + marker('FILE-') + 'return-void', 9)
}

fn bitmap_probe() string {
	return method('private static bitmap(Landroid/content/Context;)V', '
invoke-virtual {p0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;
move-result-object v6
sget v0, ${probe}->thumbId:I
invoke-static {v6, v0}, Landroid/graphics/BitmapFactory;->decodeResource(Landroid/content/res/Resources;I)${bitmap}
move-result-object v7
new-instance v0, ${nine_patch}
move-object v1, v6
move-object v2, v7
invoke-static {}, ${probe}->chunk()[B
move-result-object v3
const/4 v4, 0
const-string v5, "actual compiled npTc"
invoke-direct/range {v0 .. v5}, ${nine_patch}-><init>(Landroid/content/res/Resources;${bitmap}[BLandroid/graphics/Rect;Ljava/lang/String;)V
move-object v8, v0
const/16 v0, 21
const/16 v1, 15
const-string v2, "bitmap and compiled chunk"
invoke-static {v8, v0, v1, v2}, ${probe}->dimensions(${drawable}IILjava/lang/String;)V
# A null chunk does not create a native image handle.
new-instance v0, ${nine_patch}
move-object v1, v6
move-object v2, v7
const/4 v3, 0
const/4 v4, 0
const/4 v5, 0
invoke-direct/range {v0 .. v5}, ${nine_patch}-><init>(Landroid/content/res/Resources;${bitmap}[BLandroid/graphics/Rect;Ljava/lang/String;)V
const/4 v1, -1
const-string v2, "null chunk has no intrinsic size"
invoke-static {v0, v1, v1, v2}, ${probe}->dimensions(${drawable}IILjava/lang/String;)V
# A drawable retains its native bitmap reference after the source is recycled.
invoke-virtual {v7}, ${bitmap}->recycle()V
const/16 v0, 21
const/16 v1, 15
const-string v2, "retained image after recycle"
invoke-static {v8, v0, v1, v2}, ${probe}->dimensions(${drawable}IILjava/lang/String;)V
new-instance v0, ${nine_patch}
move-object v1, v6
const/4 v2, 0
invoke-static {}, ${probe}->chunk()[B
move-result-object v3
const/4 v4, 0
const/4 v5, 0
invoke-direct/range {v0 .. v5}, ${nine_patch}-><init>(Landroid/content/res/Resources;${bitmap}[BLandroid/graphics/Rect;Ljava/lang/String;)V
const/4 v1, -1
const-string v2, "null bitmap has no intrinsic size"
invoke-static {v0, v1, v1, v2}, ${probe}->dimensions(${drawable}IILjava/lang/String;)V
' + marker('BITMAP-') + 'return-void', 9)
}

fn selector_probe() string {
	return method('private static selector()V', '
new-instance v6, Landroid/graphics/drawable/StateListDrawable;
invoke-direct {v6}, Landroid/graphics/drawable/StateListDrawable;-><init>()V
const/4 v0, 1
new-array v7, v0, [I
const/4 v0, 0
const v1, 0x010100a0
aput v1, v7, v0
sget-object v1, ${probe}->thumb:${drawable}
invoke-virtual {v6, v7, v1}, Landroid/graphics/drawable/StateListDrawable;->addState([I${drawable})V
const/4 v0, 0
new-array v8, v0, [I
sget-object v1, ${probe}->track:${drawable}
invoke-virtual {v6, v8, v1}, Landroid/graphics/drawable/StateListDrawable;->addState([I${drawable})V
const/16 v0, 29
const/16 v1, 9
const-string v2, "selector default track"
invoke-static {v6, v0, v1, v2}, ${probe}->dimensions(${drawable}IILjava/lang/String;)V
invoke-virtual {v6, v7}, ${drawable}->setState([I)Z
const/16 v0, 21
const/16 v1, 15
const-string v2, "selector checked thumb"
invoke-static {v6, v0, v1, v2}, ${probe}->dimensions(${drawable}IILjava/lang/String;)V
invoke-virtual {v6, v8}, ${drawable}->setState([I)Z
const/16 v0, 29
const/16 v1, 9
const-string v2, "selector restored track"
invoke-static {v6, v0, v1, v2}, ${probe}->dimensions(${drawable}IILjava/lang/String;)V
' + marker('SELECTOR-') + 'return-void', 9)
}

fn geometry_probe() string {
	return method('private static geometry()V', '
sget-object v0, ${probe}->thumb:${drawable}
invoke-virtual {v0}, ${drawable}->getIntrinsicWidth()I
move-result v1
const/4 v2, 0
invoke-static {v2, v1}, Ljava/lang/Math;->max(II)I
move-result v6
invoke-virtual {v0}, ${drawable}->getIntrinsicHeight()I
move-result v1
sget-object v0, ${probe}->track:${drawable}
invoke-virtual {v0}, ${drawable}->getIntrinsicHeight()I
move-result v2
invoke-static {v1, v2}, Ljava/lang/Math;->max(II)I
move-result v7
const/16 v0, 21
const-string v1, "switch-like G max of zero and thumb width"
invoke-static {v6, v0, v1}, ${probe}->equal(IILjava/lang/String;)V
const/16 v0, 15
const-string v1, "switch-like F max of thumb and track heights"
invoke-static {v7, v0, v1}, ${probe}->equal(IILjava/lang/String;)V
sput v6, ${probe}->switchWidth:I
sput v7, ${probe}->switchHeight:I
' + marker('GEOMETRY-') + 'return-void', 8)
}

fn probe_class(chunk []u8) string {
	return '.class public ${probe}\n.super Ljava/lang/Object;\n' +
		'.field private static thumbId:I\n.field public static thumb:${drawable}\n.field public static track:${drawable}\n' +
		'.field public static switchWidth:I\n.field public static switchHeight:I\n' +
		helper_methods(chunk) + resources_probe() + file_probe() + bitmap_probe() +
		selector_probe() + geometry_probe() + method('public static run(Landroid/content/Context;)V',
		'invoke-static {}, ${probe}->traceAbsent()V\n' +
			'invoke-static {p0}, ${probe}->resources(Landroid/content/Context;)V\n' +
			'invoke-static {p0}, ${probe}->file(Landroid/content/Context;)V\n' +
			'invoke-static {p0}, ${probe}->bitmap(Landroid/content/Context;)V\n' +
			'invoke-static {}, ${probe}->selector()V\ninvoke-static {}, ${probe}->geometry()V\n' +
			marker('') + 'return-void', 2)
}

fn view_class() string {
	// Draw into the real guest View Canvas. Drawable.draw currently does not use
	// a Canvas(bitmap) destination, so an offscreen pixel oracle would be false.
	return '.class public ${view}\n.super Landroid/view/View;\n.field private drawn:Z\n' +
		method('public constructor <init>(Landroid/content/Context;)V',
			'invoke-direct {p0, p1}, Landroid/view/View;-><init>(Landroid/content/Context;)V\n' +
				'const/4 v0, 0\ninvoke-virtual {p0, v0}, Landroid/view/View;->setWillNotDraw(Z)V\nreturn-void', 1) +
		method('protected onDraw(Landroid/graphics/Canvas;)V', '
const v0, 0xffffffff
invoke-virtual {p1, v0}, Landroid/graphics/Canvas;->drawColor(I)V
# Fourfold scale preserves the same positive G/F rectangle for screenshot checks.
sget v0, ${probe}->switchWidth:I
mul-int/lit8 v0, v0, 8
add-int/lit8 v2, v0, 24
sget v0, ${probe}->switchHeight:I
mul-int/lit8 v0, v0, 4
add-int/lit8 v3, v0, 48
const/16 v0, 24
const/16 v1, 48
sget-object v5, ${probe}->track:${drawable}
invoke-virtual {v5, v0, v1, v2, v3}, ${drawable}->setBounds(IIII)V
invoke-virtual {v5, p1}, ${drawable}->draw(Landroid/graphics/Canvas;)V
sget v0, ${probe}->switchWidth:I
mul-int/lit8 v0, v0, 4
add-int/lit8 v0, v0, 24
sget-object v5, ${probe}->thumb:${drawable}
invoke-virtual {v5, v0, v1, v2, v3}, ${drawable}->setBounds(IIII)V
invoke-virtual {v5, p1}, ${drawable}->draw(Landroid/graphics/Canvas;)V
iget-boolean v0, p0, ${view}->drawn:Z
if-nez v0, :done
const/4 v0, 1
iput-boolean v0, p0, ${view}->drawn:Z
' + marker('DRAW-') + ':done\nreturn-void', 6)
}

fn activity() string {
	return '.class public Lorg/vinix/bootstrap/Main;\n.super Landroid/app/Activity;\n' +
		method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void', 0) +
		method('public onCreate(Landroid/os/Bundle;)V',
			'invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V\n' +
				'invoke-static {p0}, ${probe}->run(Landroid/content/Context;)V\n' +
				'new-instance v0, ${view}\ninvoke-direct {v0, p0}, ${view}-><init>(Landroid/content/Context;)V\n' +
				'invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V\n' +
				line_marker('BOOTSTRAP-READY') + 'return-void', 2)
}

fn put_word(mut out []u8, value u32) {
	mut b := []u8{len: 4}
	binary.big_endian_put_u32(mut b, value)
	out << b
}

fn png_chunk(mut out []u8, kind string, body []u8) {
	put_word(mut out, u32(body.len))
	start := out.len
	out << kind.bytes()
	out << body
	put_word(mut out, crc32.sum(out[start..]))
}

fn source_png(width int, height int, rgb u32) ![]u8 {
	// One-pixel transparent frame with legal black stretch/padding markers.
	w, h := width + 2, height + 2
	mut rows := []u8{}
	for y in 0 .. h {
		rows << u8(0)
		for x in 0 .. w {
			if x > 0 && x < w - 1 && y > 0 && y < h - 1 {
				rows << [u8(rgb >> 16), u8(rgb >> 8), u8(rgb), u8(255)]
			} else if (y == 0 && x > 1 && x < w - 2)
				|| (y == h - 1 && x > 0 && x < w - 1)
				|| (x == 0 && y > 1 && y < h - 2)
				|| (x == w - 1 && y > 0 && y < h - 1) {
				rows << [u8(0), 0, 0, 255]
			} else {
				rows << [u8(0), 0, 0, 0]
			}
		}
	}
	mut out := [u8(137), 80, 78, 71, 13, 10, 26, 10]
	mut ihdr := []u8{}
	put_word(mut ihdr, u32(w))
	put_word(mut ihdr, u32(h))
	ihdr << [u8(8), 6, 0, 0, 0]
	png_chunk(mut out, 'IHDR', ihdr)
	png_chunk(mut out, 'IDAT', zlib.compress(rows)!)
	png_chunk(mut out, 'IEND', []u8{})
	return out
}

fn compiled_png(path string, width int, height int) ![]u8 {
	b := os.read_bytes(path)!
	assert b.len > 33 && b[..8] == [u8(137), 80, 78, 71, 13, 10, 26, 10]
	assert b[12..16].bytestr() == 'IHDR'
	assert binary.big_endian_u32(b[16..20]) == u32(width)
	assert binary.big_endian_u32(b[20..24]) == u32(height)
	mut offset := 8
	mut chunk := []u8{}
	for offset + 12 <= b.len {
		size := int(binary.big_endian_u32(b[offset..offset + 4]))
		assert size >= 0 && size <= b.len - offset - 12
		end := offset + 8 + size
		assert crc32.sum(b[offset + 4..end]) == binary.big_endian_u32(b[end..end + 4])
		if b[offset + 4..offset + 8].bytestr() == 'npTc' {
			assert chunk.len == 0
			chunk = b[offset + 8..end].clone()
		}
		offset = end + 4
	}
	assert offset == b.len
	assert chunk.len >= 32 && chunk[1] == 2 && chunk[2] == 2 && chunk[3] == 9
	assert chunk.len == 32 + 4 * (int(chunk[1]) + int(chunk[2]) + int(chunk[3]))
	return chunk
}

fn file_hash(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn checked(out string, name string, args []string, pins map[string]string) ! {
	for path, pin in pins {
		assert file_hash(path)! == pin, path
	}
	started := time.utc().str()
	r := os.exec(args)
	os.write_file(out + '/' + name + '.log', r.output)!
	os.write_file(out + '/' + name + '-receipt.json', json2.encode({
		'argv':             json2.Any(args)
		'started_utc':      json2.Any(started)
		'completed_utc':    json2.Any(time.utc().str())
		'exit_code':        json2.Any(r.exit_code)
		'input_sha256':     json2.decode[json2.Any](json2.encode(pins))!
		'generator_sha256': json2.Any(file_hash(os.executable())!)
	},
		prettify: true
	) + '\n')!
	for path, pin in pins {
		assert file_hash(path)! == pin, path
	}
	assert r.exit_code == 0, name + ': ' + r.output
}

fn main() {
	$if prod {
		panic('assertions required')
	}
	assert os.args.len == 2, 'OUTPUT'
	out := os.abs_path(os.args[1])
	assert !os.exists(out) && !os.is_link(out), 'fresh output required'
	root := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(root)!
	os.mkdir_all(out + '/res/values')!
	os.mkdir_all(out + '/res/drawable-nodpi')!
	os.write_file(out + '/res/values/values.xml', '<resources><string name="app_name">Nine patch dimensions fixture</string></resources>')!
	os.write_file_array(out + '/res/drawable-nodpi/thumb.9.png', source_png(21, 15, 0xe53935)!)!
	os.write_file_array(out + '/res/drawable-nodpi/track.9.png', source_png(29, 9, 0x2471c4)!)!
	os.write_file(out + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="26" android:targetSdkVersion="35"/><application android:label="Nine patch dimensions fixture"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
	tools := os.getenv('NINE_PATCH_DIMENSIONS_FIXTURE_TOOLS_ROOT')
	aapt := if tools == '' {
		os.abs_path('build/android-native-ws/aapt2')
	} else {
		tools + '/aapt2'
	}
	signer := if tools == '' {
		os.abs_path('build/android-native-ws/android-15/lib/apksigner.jar')
	} else {
		tools + '/apksigner.jar'
	}
	framework := if tools == '' {
		'/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/framework-res.apk'
	} else {
		tools + '/framework-res.apk'
	}
	smali := if tools == '' {
		os.abs_path('build/android-framework/tools')
	} else {
		tools + '/smali'
	}
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	keytool := '/opt/homebrew/opt/openjdk@25/bin/keytool'
	zip := '/usr/bin/zip'
	unzip := '/usr/bin/unzip'
	mut pins := map[string]string{}
	for path in [aapt, signer, framework, java, keytool, zip, unzip] {
		pins[path] = file_hash(path)!
	}
	for name in os.ls(smali)! {
		if name.ends_with('.jar') { pins[smali + '/' + name] = file_hash(smali + '/' + name)! }
	}
	assert pins.len > 7
	os.write_file(out + '/tool-inputs-before.json', json2.encode(pins, prettify: true) + '\n')!
	checked(out, 'resources', [aapt, 'compile', '--dir', out + '/res', '-o', out + '/resources.zip'], pins)!
	checked(out, 'aapt2', [aapt, 'link', '-I', framework, '--manifest', out + '/AndroidManifest.xml',
		'-o', out + '/unsigned.apk', out + '/resources.zip'], pins)!
	checked(out, 'extract-png', [unzip, '-q', out + '/unsigned.apk', 'res/*/*.9.png', '-d',
		out + '/compiled'], pins)!
	mut chunk := []u8{}
	mut assets := map[string]json2.Any{}
	for path in os.walk_ext(out + '/compiled', '.png') {
		if os.base(path) == 'thumb.9.png' {
			chunk = compiled_png(path, 21, 15)!
			assets['thumb'] = json2.Any({
				'path':   json2.Any(path)
				'width':  json2.Any(21)
				'height': json2.Any(15)
				'sha256': json2.Any(file_hash(path)!)
			})
		} else if os.base(path) == 'track.9.png' {
			compiled_png(path, 29, 9)!
			assets['track'] = json2.Any({
				'path':   json2.Any(path)
				'width':  json2.Any(29)
				'height': json2.Any(9)
				'sha256': json2.Any(file_hash(path)!)
			})
		} else {
			panic('unexpected compiled PNG: ' + path)
		}
	}
	assert assets.len == 2 && chunk.len > 0
	os.write_file(out + '/compiled-png-inputs.json', json2.encode(assets, prettify: true) + '\n')!
	os.write_file_array(out + '/thumb.npTc', chunk)!
	os.write_file(root + '/Main.smali', activity())!
	os.write_file(root + '/NinePatchProbe.smali', probe_class(chunk))!
	os.write_file(root + '/NinePatchView.smali', view_class())!
	checked(out, 'smali', [java, '-cp', smali + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali',
		'-o', out + '/classes.dex'], pins)!
	assert os.is_file(out + '/classes.dex'), 'smali produced no DEX'
	checked(out, 'zip', [zip, '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'], pins)!
	key := out + '/fixture.p12'
	checked(out, 'keytool', [keytool, '-genkeypair', '-keystore', key, '-storetype', 'PKCS12',
		'-alias', 'fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650', '-dname',
		'CN=Vinix Nine patch dimensions fixture', '-storepass', 'android', '-keypass', 'android'], pins)!
	checked(out, 'sign', [java, '-jar', signer, 'sign', '--ks', key, '--ks-key-alias', 'fixture',
		'--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk',
		out + '/unsigned.apk'], pins)!
	checked(out, 'verify', [java, '-jar', signer, 'verify', '--verbose', out + '/probe.apk'], pins)!
	os.write_file(out + '/tool-inputs-after.json', json2.encode(pins, prettify: true) + '\n')!
	println('NINE-PATCH-DIMENSIONS-APK ' + file_hash(out + '/probe.apk')!)
}
