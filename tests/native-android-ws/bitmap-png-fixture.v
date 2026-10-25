// SPDX-License-Identifier: GPL-2.0-or-later
// One signed APK exercises both the missing-native baseline and PNG encoder.
module main

import crypto.sha256
import json2
import os
import time

const probe = 'Lorg/vinix/bootstrap/PngProbe;'
const decoder = 'Lorg/vinix/bootstrap/PngDecode;'
const bitmap = 'Landroid/graphics/Bitmap;'
const config = 'Landroid/graphics/Bitmap$Config;'
const format = 'Landroid/graphics/Bitmap$CompressFormat;'
const stream = 'Lorg/vinix/bootstrap/ThrowStream;'

fn method(signature string, body string, locals int) string {
	return '.method ' + signature + '\n.locals ${locals}\n' + body + '\n.end method\n'
}

fn marker(name string) string {
	return 'sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;\nconst-string v1, "BOOTSTRAP-BITMAP-PNG-${name}-PASS"\ninvoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V\n'
}

fn fail(message string) string {
	return 'const-string v0, "${message}"\ninvoke-static {v0}, ${probe}->fail(Ljava/lang/String;)V\n'
}

fn decoder_source() string {
	mut text := '.class public ${decoder}\n.super Ljava/lang/Object;\n'
	text += method('private static word([BI)I', '
aget-byte v0, p0, p1
and-int/lit16 v0, v0, 255
shl-int/lit8 v0, v0, 24
add-int/lit8 v1, p1, 1
aget-byte v2, p0, v1
and-int/lit16 v2, v2, 255
shl-int/lit8 v2, v2, 16
or-int/2addr v0, v2
add-int/lit8 v1, p1, 2
aget-byte v2, p0, v1
and-int/lit16 v2, v2, 255
shl-int/lit8 v2, v2, 8
or-int/2addr v0, v2
add-int/lit8 v1, p1, 3
aget-byte v2, p0, v1
and-int/lit16 v2, v2, 255
or-int/2addr v0, v2
return v0', 3)
	text += method('private static crc([BIII)V', '
new-instance v0, Ljava/util/zip/CRC32;
invoke-direct {v0}, Ljava/util/zip/CRC32;-><init>()V
invoke-virtual {v0, p0, p1, p2}, Ljava/util/zip/CRC32;->update([BII)V
invoke-virtual {v0}, Ljava/util/zip/CRC32;->getValue()J
move-result-wide v0
int-to-long v2, p3
const-wide v4, 0xffffffffL
and-long/2addr v2, v4
cmp-long v0, v0, v2
if-eqz v0, :good
' + fail('independent decoder: PNG chunk CRC mismatch') + '
:good
return-void', 6)
	text += method('private static header([BIII)V', '
invoke-static {p0, p1}, ${decoder}->word([BI)I
move-result v0
if-ne v0, p2, :bad
add-int/lit8 v1, p1, 4
invoke-static {p0, v1}, ${decoder}->word([BI)I
move-result v0
if-ne v0, p3, :bad
add-int/lit8 v1, p1, 8
aget-byte v0, p0, v1
const/16 v2, 8
if-ne v0, v2, :bad
add-int/lit8 v1, p1, 9
aget-byte v0, p0, v1
const/4 v2, 6
if-ne v0, v2, :bad
add-int/lit8 v1, p1, 10
aget-byte v0, p0, v1
if-nez v0, :bad
add-int/lit8 v1, p1, 11
aget-byte v0, p0, v1
if-nez v0, :bad
add-int/lit8 v1, p1, 12
aget-byte v0, p0, v1
if-nez v0, :bad
return-void
:bad
' + fail('independent decoder: dimensions or RGBA8 header mismatch') + '
return-void', 3)
	// Standard PNG Paeth predictor, including its specified tie order.
	text += method('private static paeth(III)I', '
add-int v0, p0, p1
sub-int/2addr v0, p2
sub-int v1, v0, p0
invoke-static {v1}, Ljava/lang/Math;->abs(I)I
move-result v1
sub-int v2, v0, p1
invoke-static {v2}, Ljava/lang/Math;->abs(I)I
move-result v2
sub-int v0, v0, p2
invoke-static {v0}, Ljava/lang/Math;->abs(I)I
move-result v0
if-gt v1, v2, :not_left
if-gt v1, v0, :not_left
return p0
:not_left
if-gt v2, v0, :upper_left
return p1
:upper_left
return p2', 3)
	text += method('private static prediction(IIII)I', '
if-eqz p0, :none
const/4 v0, 1
if-eq p0, v0, :left
const/4 v0, 2
if-eq p0, v0, :up
const/4 v0, 3
if-eq p0, v0, :average
const/4 v0, 4
if-eq p0, v0, :paeth
' + fail('independent decoder: invalid PNG row filter') + '
:none
const/4 v0, 0
return v0
:left
return p1
:up
return p2
:average
add-int v0, p1, p2
ushr-int/lit8 v0, v0, 1
return v0
:paeth
invoke-static {p1, p2, p3}, ${decoder}->paeth(III)I
move-result v0
return v0', 1)
	// Decode with the VM's zlib implementation, never BitmapFactory or native WS.
	text += method('private static pixels([BII[I)V', '
mul-int v0, p1, p2
array-length v1, p3
if-ne v0, v1, :bad
shl-int/lit8 v0, p1, 2
add-int/lit8 v1, v0, 1
mul-int/2addr v1, p2
new-array v2, v1, [B
new-instance v3, Ljava/io/ByteArrayInputStream;
invoke-direct {v3, p0}, Ljava/io/ByteArrayInputStream;-><init>([B)V
new-instance v4, Ljava/util/zip/InflaterInputStream;
invoke-direct {v4, v3}, Ljava/util/zip/InflaterInputStream;-><init>(Ljava/io/InputStream;)V
new-instance v3, Ljava/io/DataInputStream;
invoke-direct {v3, v4}, Ljava/io/DataInputStream;-><init>(Ljava/io/InputStream;)V
invoke-virtual {v3, v2}, Ljava/io/DataInputStream;->readFully([B)V
invoke-virtual {v3}, Ljava/io/DataInputStream;->read()I
move-result v1
const/4 v4, -1
if-ne v1, v4, :bad
invoke-virtual {v3}, Ljava/io/DataInputStream;->close()V
mul-int v1, v0, p2
new-array v3, v1, [B
const/4 v4, 0
:row
if-ge v4, p2, :compare
add-int/lit8 v5, v0, 1
mul-int/2addr v5, v4
aget-byte v6, v2, v5
const/4 v7, 0
:column
if-ge v7, v0, :next_row
const/4 v8, 0
const/4 v9, 0
const/4 v10, 0
mul-int v11, v4, v0
add-int/2addr v11, v7
const/4 v1, 4
if-lt v7, v1, :no_left
add-int/lit8 v1, v11, -4
aget-byte v8, v3, v1
and-int/lit16 v8, v8, 255
:no_left
if-eqz v4, :no_above
sub-int v1, v11, v0
aget-byte v9, v3, v1
and-int/lit16 v9, v9, 255
const/4 v1, 4
if-lt v7, v1, :no_above
sub-int v1, v11, v0
add-int/lit8 v1, v1, -4
aget-byte v10, v3, v1
and-int/lit16 v10, v10, 255
:no_above
invoke-static {v6, v8, v9, v10}, ${decoder}->prediction(IIII)I
move-result v8
add-int v1, v5, v7
add-int/lit8 v1, v1, 1
aget-byte v1, v2, v1
and-int/lit16 v1, v1, 255
add-int/2addr v1, v8
int-to-byte v1, v1
aput-byte v1, v3, v11
add-int/lit8 v7, v7, 1
goto :column
:next_row
add-int/lit8 v4, v4, 1
goto :row
:compare
const/4 v4, 0
array-length v5, p3
:pixel
if-ge v4, v5, :good
shl-int/lit8 v6, v4, 2
invoke-static {v3, v6}, ${decoder}->word([BI)I
move-result v7
ushr-int/lit8 v8, v7, 8
shl-int/lit8 v7, v7, 24
or-int/2addr v7, v8
aget v8, p3, v4
if-ne v7, v8, :bad
add-int/lit8 v4, v4, 1
goto :pixel
:good
return-void
:bad
' + fail('independent decoder: PNG pixel, alpha, or inflated length mismatch') + '
return-void', 12)
	text += method('public static decode([BII[I)V', '
array-length v0, p0
const/16 v1, 45
if-lt v0, v1, :bad
const/4 v0, 0
invoke-static {p0, v0}, ${decoder}->word([BI)I
move-result v0
const v1, 0x89504e47
if-ne v0, v1, :bad
const/4 v0, 4
invoke-static {p0, v0}, ${decoder}->word([BI)I
move-result v0
const v1, 0x0d0a1a0a
if-ne v0, v1, :bad
new-instance v8, Ljava/io/ByteArrayOutputStream;
invoke-direct {v8}, Ljava/io/ByteArrayOutputStream;-><init>()V
const/4 v9, 0
const/16 v0, 8
:chunk
array-length v1, p0
add-int/lit8 v2, v0, 12
if-gt v2, v1, :bad
invoke-static {p0, v0}, ${decoder}->word([BI)I
move-result v1
if-ltz v1, :bad
const v2, 0x100000
if-gt v1, v2, :bad
add-int/lit8 v2, v0, 4
invoke-static {p0, v2}, ${decoder}->word([BI)I
move-result v2
add-int/lit8 v3, v0, 8
add-int/2addr v3, v1
add-int/lit8 v4, v3, 4
array-length v5, p0
if-gt v4, v5, :bad
invoke-static {p0, v3}, ${decoder}->word([BI)I
move-result v4
add-int/lit8 v5, v0, 4
add-int/lit8 v6, v1, 4
invoke-static {p0, v5, v6, v4}, ${decoder}->crc([BIII)V
const v4, 0x49484452
if-eq v2, v4, :header
if-eqz v9, :bad
const v4, 0x49444154
if-eq v2, v4, :data
const v4, 0x49454e44
if-eq v2, v4, :end
const v4, 0x20000000
and-int/2addr v4, v2
if-eqz v4, :bad
goto :advance
:header
if-nez v9, :bad
const/16 v4, 13
if-ne v1, v4, :bad
add-int/lit8 v4, v0, 8
invoke-static {p0, v4, p1, p2}, ${decoder}->header([BIII)V
const/4 v9, 1
goto :advance
:data
add-int/lit8 v4, v0, 8
invoke-virtual {v8, p0, v4, v1}, Ljava/io/ByteArrayOutputStream;->write([BII)V
:advance
add-int/lit8 v0, v3, 4
goto :chunk
:end
if-nez v1, :bad
add-int/lit8 v0, v3, 4
array-length v1, p0
if-ne v0, v1, :bad
invoke-virtual {v8}, Ljava/io/ByteArrayOutputStream;->size()I
move-result v0
if-eqz v0, :bad
invoke-virtual {v8}, Ljava/io/ByteArrayOutputStream;->toByteArray()[B
move-result-object v0
invoke-static {v0, p1, p2, p3}, ${decoder}->pixels([BII[I)V
return-void
:bad
' + fail('independent decoder: invalid PNG structure') + '
return-void', 10)
	return text
}

fn throw_stream() string {
	return '.class public ${stream}\n.super Ljava/io/OutputStream;\n.field public sentinel:Ljava/io/IOException;\n' + method('public constructor <init>()V', '
invoke-direct {p0}, Ljava/io/OutputStream;-><init>()V
new-instance v0, Ljava/io/IOException;
const-string v1, "PNG output sentinel"
invoke-direct {v0, v1}, Ljava/io/IOException;-><init>(Ljava/lang/String;)V
iput-object v0, p0, ${stream}->sentinel:Ljava/io/IOException;
return-void', 2) + method('public write(I)V', 'iget-object v0, p0, ${stream}->sentinel:Ljava/io/IOException;\nthrow v0', 1) + method('public write([B)V', 'iget-object v0, p0, ${stream}->sentinel:Ljava/io/IOException;\nthrow v0', 1)
}

fn contracts() string {
	return method('private static contracts(${bitmap})V', '
new-instance v2, Ljava/io/ByteArrayOutputStream;
invoke-direct {v2}, Ljava/io/ByteArrayOutputStream;-><init>()V
const/4 v3, 0
:null_format_start
invoke-virtual {p0, v3, v3, v2}, ${bitmap}->compress(${format}ILjava/io/OutputStream;)Z
:null_format_end
' + fail('null format must throw NullPointerException') + '
return-void
:null_format
move-exception v0
sget-object v4, ${format}->PNG:${format}
:null_stream_start
invoke-virtual {p0, v4, v3, v3}, ${bitmap}->compress(${format}ILjava/io/OutputStream;)Z
:null_stream_end
' + fail('null output must throw NullPointerException') + '
return-void
:null_stream
move-exception v0
new-instance v5, ${stream}
invoke-direct {v5}, ${stream}-><init>()V
:io_start
invoke-virtual {p0, v4, v3, v5}, ${bitmap}->compress(${format}ILjava/io/OutputStream;)Z
:io_end
' + fail('output IOException must propagate') + '
return-void
:io
move-exception v0
iget-object v1, v5, ${stream}->sentinel:Ljava/io/IOException;
if-eq v0, v1, :io_identity
' + fail('compress must preserve output IOException identity') + '
:io_identity
sget-object v6, ${config}->ARGB_8888:${config}
const/4 v7, 1
:empty_start
invoke-static {v3, v7, v6}, ${bitmap}->createBitmap(II${config})${bitmap}
move-result-object v8
invoke-virtual {v8, v4, v3, v2}, ${bitmap}->compress(${format}ILjava/io/OutputStream;)Z
:empty_end
' + fail('empty bitmap compression must reject dimensions') + '
return-void
:empty
move-exception v0
invoke-static {v7, v7, v6}, ${bitmap}->createBitmap(II${config})${bitmap}
move-result-object v8
invoke-static {v8, v3}, ${probe}->encode(${bitmap}I)[B
invoke-virtual {v8}, ${bitmap}->recycle()V
invoke-virtual {v8}, ${bitmap}->isRecycled()Z
move-result v0
if-nez v0, :recycled_flag
' + fail('recycle must set isRecycled') + '
:recycled_flag
:recycled_start
invoke-virtual {v8, v4, v3, v2}, ${bitmap}->compress(${format}ILjava/io/OutputStream;)Z
:recycled_end
' + fail('recycled bitmap compression must throw IllegalStateException') + '
return-void
:recycled
move-exception v0
' + marker('CONTRACTS') + '
return-void
.catch Ljava/lang/NullPointerException; {:null_format_start .. :null_format_end} :null_format
.catch Ljava/lang/NullPointerException; {:null_stream_start .. :null_stream_end} :null_stream
.catch Ljava/io/IOException; {:io_start .. :io_end} :io
.catch Ljava/lang/IllegalArgumentException; {:empty_start .. :empty_end} :empty
.catch Ljava/lang/IllegalStateException; {:recycled_start .. :recycled_end} :recycled', 9)
}

fn probe_source() string {
	mut text := '.class public ${probe}\n.super Ljava/lang/Object;\n'
	text += method('public static fail(Ljava/lang/String;)V', 'new-instance v0, Ljava/lang/AssertionError;\ninvoke-direct {v0, p0}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0', 1)
	text += method('private static traceAbsent()V', '
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
' + fail('guest VINIX_ANDROID_TRACE environment must be absent') + '
:good
' + marker('TRACE-ENV-ABSENT') + '
return-void', 3)
	text += method('private static make([III${config})${bitmap}', '
invoke-static {p1, p2, p3}, ${bitmap}->createBitmap(II${config})${bitmap}
move-result-object v0
move-object v1, p0
const/4 v2, 0
move v3, p1
const/4 v4, 0
const/4 v5, 0
move v6, p1
move v7, p2
invoke-virtual/range {v0 .. v7}, ${bitmap}->setPixels([IIIIIII)V
return-object v0', 8)
	text += method('private static encode(${bitmap}I)[B', '
new-instance v2, Ljava/io/ByteArrayOutputStream;
invoke-direct {v2}, Ljava/io/ByteArrayOutputStream;-><init>()V
sget-object v3, ${format}->PNG:${format}
invoke-virtual {p0, v3, p1, v2}, ${bitmap}->compress(${format}ILjava/io/OutputStream;)Z
move-result v0
if-nez v0, :success
' + fail('Bitmap.compress PNG must return true') + '
:success
invoke-virtual {v2}, Ljava/io/ByteArrayOutputStream;->toByteArray()[B
move-result-object v0
return-object v0', 4)
	text += contracts()
	text += method('public static check()V', '
invoke-static {}, ${probe}->traceAbsent()V
const/4 v0, 4
new-array v4, v0, [I
fill-array-data v4, :rgba_pixels
const/4 v5, 2
sget-object v0, ${config}->ARGB_8888:${config}
invoke-static {v4, v5, v5, v0}, ${probe}->make([III${config})${bitmap}
move-result-object v6
const/4 v7, 0
:initial_start
invoke-static {v6, v7}, ${probe}->encode(${bitmap}I)[B
move-result-object v8
:initial_end
invoke-static {v8, v5, v5, v4}, ${decoder}->decode([BII[I)V
' + marker('RGBA') + '
const/16 v7, 100
invoke-static {v6, v7}, ${probe}->encode(${bitmap}I)[B
move-result-object v9
invoke-static {v9, v5, v5, v4}, ${decoder}->decode([BII[I)V
invoke-static {v8, v9}, Ljava/util/Arrays;->equals([B[B)Z
move-result v0
if-nez v0, :quality
' + fail('PNG quality must not change lossless output') + '
:quality
' + marker('QUALITY') + '
const/4 v0, 1
new-array v4, v0, [I
const v1, 0x12345678
const/4 v2, 0
aput v1, v4, v2
const/4 v5, 1
sget-object v0, ${config}->ARGB_8888:${config}
invoke-static {v4, v5, v5, v0}, ${probe}->make([III${config})${bitmap}
move-result-object v0
const/4 v1, 0
invoke-static {v0, v1}, ${probe}->encode(${bitmap}I)[B
move-result-object v0
invoke-static {v0, v5, v5, v4}, ${decoder}->decode([BII[I)V
' + marker('ONE-PIXEL') + '
const/4 v0, 6
new-array v4, v0, [I
fill-array-data v4, :alpha_input
const/4 v5, 3
const/4 v7, 2
sget-object v0, ${config}->ALPHA_8:${config}
invoke-static {v4, v5, v7, v0}, ${probe}->make([III${config})${bitmap}
move-result-object v0
const/4 v1, 0
invoke-static {v0, v1}, ${probe}->encode(${bitmap}I)[B
move-result-object v0
const/4 v1, 6
new-array v4, v1, [I
fill-array-data v4, :alpha_expected
invoke-static {v0, v5, v7, v4}, ${decoder}->decode([BII[I)V
' + marker('ALPHA8-PADDED') + '
invoke-static {v6}, ${probe}->contracts(${bitmap})V
' + marker('POSITIVE') + '
return-void
:missing
move-exception v0
invoke-virtual {v0}, Ljava/lang/UnsatisfiedLinkError;->getMessage()Ljava/lang/String;
move-result-object v2
if-eqz v2, :wrong_missing
const-string v1, "native_save_to_png"
invoke-virtual {v2, v1}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z
move-result v0
if-eqz v0, :wrong_missing
const-string v1, "android.graphics.Bitmap"
invoke-virtual {v2, v1}, Ljava/lang/String;->contains(Ljava/lang/CharSequence;)Z
move-result v0
if-eqz v0, :wrong_missing
' + marker('EXPECTED-MISSING-NATIVE') + '
return-void
:wrong_missing
' + fail('baseline failed with an unrelated missing native') + '
return-void
.catch Ljava/lang/UnsatisfiedLinkError; {:initial_start .. :initial_end} :missing
:rgba_pixels
.array-data 4
0xff123456
0x8078abcd
0x00112233
0x01020304
.end array-data
:alpha_input
.array-data 4
0x00112233
0x01123456
0x7f789abc
0x80abcdef
0xfe112233
0xff445566
.end array-data
:alpha_expected
.array-data 4
0x00000000
0x01000000
0x7f000000
0x80000000
0xfe000000
0xff000000
.end array-data', 10)
	return text
}

fn activity() string {
	return '.class public Lorg/vinix/bootstrap/Main;\n.super Landroid/app/Activity;\n' + method('public constructor <init>()V', 'invoke-direct {p0}, Landroid/app/Activity;-><init>()V\nreturn-void', 0) + method('public onCreate(Landroid/os/Bundle;)V', '
invoke-super {p0, p1}, Landroid/app/Activity;->onCreate(Landroid/os/Bundle;)V
invoke-static {}, ${probe}->check()V
new-instance v0, Landroid/view/View;
invoke-direct {v0, p0}, Landroid/view/View;-><init>(Landroid/content/Context;)V
invoke-virtual {p0, v0}, Landroid/app/Activity;->setContentView(Landroid/view/View;)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-READY"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void', 2)
}

fn file_hash(path string) !string {
	return sha256.sum(os.read_bytes(path)!).hex()
}

fn checked(out string, name string, args []string, pins map[string]string) ! {
	for path, pin in pins { assert file_hash(path)! == pin, path }
	started := time.utc().str()
	r := os.exec(args)
	mut encoded_pins := map[string]json2.Any{}
	for path, pin in pins { encoded_pins[path] = pin }
	os.write_file(out + '/' + name + '.log', r.output)!
	os.write_file(out + '/' + name + '-receipt.json', json2.encode({'argv': json2.Any(args), 'started_utc': json2.Any(started), 'completed_utc': json2.Any(time.utc().str()), 'exit_code': json2.Any(r.exit_code), 'input_sha256': json2.Any(encoded_pins), 'generator_sha256': json2.Any(file_hash(os.executable())!)}, prettify: true) + '\n')!
	for path, pin in pins { assert file_hash(path)! == pin, path }
	assert r.exit_code == 0, name + ': ' + r.output
}

fn main() {
	$if prod { panic('assertions required') }
	assert os.args.len == 2, 'OUTPUT'
	out := os.abs_path(os.args[1])
	assert !os.exists(out), 'fresh output required'
	root := out + '/smali/org/vinix/bootstrap'
	os.mkdir_all(root)!
	os.write_file(out + '/AndroidManifest.xml', '<manifest xmlns:android="http://schemas.android.com/apk/res/android" package="org.vinix.bootstrap"><uses-sdk android:minSdkVersion="26" android:targetSdkVersion="35"/><application android:label="Bitmap PNG fixture"><activity android:name=".Main" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN"/><category android:name="android.intent.category.LAUNCHER"/></intent-filter></activity></application></manifest>')!
	os.write_file(root + '/Main.smali', activity())!
	os.write_file(root + '/PngProbe.smali', probe_source())!
	os.write_file(root + '/PngDecode.smali', decoder_source())!
	os.write_file(root + '/ThrowStream.smali', throw_stream())!
	tools := os.getenv('BITMAP_FIXTURE_TOOLS_ROOT')
	aapt := if tools == '' { os.abs_path('build/android-native-ws/aapt2') } else { tools + '/aapt2' }
	signer := if tools == '' { os.abs_path('build/android-native-ws/android-15/lib/apksigner.jar') } else { tools + '/apksigner.jar' }
	framework := if tools == '' { '/Users/alex/code/vinix-android-native/build-aarch64-android/aarch64/staging/opt/vinix-android-aarch64/usr/lib/java/dex/android_translation_layer/framework-res.apk' } else { tools + '/framework-res.apk' }
	smali := if tools == '' { os.abs_path('build/android-framework/tools') } else { tools + '/smali' }
	java := '/opt/homebrew/opt/openjdk@25/bin/java'
	keytool := '/opt/homebrew/opt/openjdk@25/bin/keytool'
	zip := '/usr/bin/zip'
	mut pins := map[string]string{}
	for path in [aapt, signer, framework, java, keytool, zip] { pins[path] = file_hash(path)! }
	for name in os.ls(smali)! { if name.ends_with('.jar') { pins[smali + '/' + name] = file_hash(smali + '/' + name)! } }
	assert pins.len > 6
	os.write_file(out + '/tool-inputs-before.json', json2.encode(pins, prettify: true) + '\n')!
	checked(out, 'aapt2', [aapt, 'link', '-I', framework, '--manifest', out + '/AndroidManifest.xml', '-o', out + '/unsigned.apk'], pins)!
	checked(out, 'smali', [java, '-cp', smali + '/*', 'org.jf.smali.Main', 'assemble', out + '/smali', '-o', out + '/classes.dex'], pins)!
	assert os.is_file(out + '/classes.dex'), 'smali produced no DEX'
	checked(out, 'zip', [zip, '-q', '-j', out + '/unsigned.apk', out + '/classes.dex'], pins)!
	key := out + '/fixture.p12'
	checked(out, 'keytool', [keytool, '-genkeypair', '-keystore', key, '-storetype', 'PKCS12', '-alias', 'fixture', '-keyalg', 'RSA', '-keysize', '2048', '-validity', '3650', '-dname', 'CN=Vinix Bitmap PNG fixture', '-storepass', 'android', '-keypass', 'android'], pins)!
	checked(out, 'sign', [java, '-jar', signer, 'sign', '--ks', key, '--ks-key-alias', 'fixture', '--ks-pass', 'pass:android', '--key-pass', 'pass:android', '--out', out + '/probe.apk', out + '/unsigned.apk'], pins)!
	checked(out, 'verify', [java, '-jar', signer, 'verify', '--verbose', out + '/probe.apk'], pins)!
	os.write_file(out + '/tool-inputs-after.json', json2.encode(pins, prettify: true) + '\n')!
	println('BITMAP-PNG-APK ' + file_hash(out + '/probe.apk')!)
}
