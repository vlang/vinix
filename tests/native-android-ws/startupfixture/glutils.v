// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn glutils_pixel(x int, y int, rgba []int) string {
 mut text := '\nconst/16 v0, ${x}\nconst/16 v1, ${y}\nconst/4 v2, 1\nconst/4 v3, 1\nconst/16 v4, 0x1908\nconst/16 v5, 0x1401\ninvoke-static/range {v0 .. v6}, Landroid/opengl/GLES20;->glReadPixels(IIIIIILjava/nio/Buffer;)V\n'
 for index,value in rgba { text += 'const/4 v0, ${index}\ninvoke-virtual {v6, v0}, Ljava/nio/ByteBuffer;->get(I)B\nmove-result v0\nconst/16 v1, ${value}\nif-ne v0, v1, :bad\n' }
 return text
}

// GlesUploadProbe supplies a bound texture attached to the current FBO.
fn install_glutils_probe(dir string) ! {
 mut body := '
const/4 v0, 2
sget-object v1, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;
invoke-static {v0, v0, v1}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v8
const v0, 0xff12a4e6
invoke-virtual {v8, v0}, Landroid/graphics/Bitmap;->eraseColor(I)V
const/16 v0, 0xcf5
const/16 v1, 8
invoke-static {v0, v1}, Landroid/opengl/GLES20;->glPixelStorei(II)V
const/4 v0, 0
invoke-static {v0}, Landroid/opengl/GLES20;->glEnable(I)V
const/16 v0, 0xde1
const/4 v1, 0
invoke-static {v0, v1, v8, v1}, Landroid/opengl/GLUtils;->texImage2D(IILandroid/graphics/Bitmap;I)V
invoke-static {}, Landroid/opengl/GLES20;->glGetError()I
move-result v0
const/16 v1, 0x500
if-ne v0, v1, :bad
invoke-static {}, Landroid/opengl/GLES20;->glGetError()I
move-result v0
if-nez v0, :bad
const/4 v0, 1
new-array v1, v0, [I
const/16 v0, 0xcf5
const/4 v2, 0
invoke-static {v0, v1, v2}, Landroid/opengl/GLES20;->glGetIntegerv(I[II)V
aget v0, v1, v2
const/16 v1, 8
if-ne v0, v1, :bad
const/4 v0, 4
invoke-static {v0}, Ljava/nio/ByteBuffer;->allocateDirect(I)Ljava/nio/ByteBuffer;
move-result-object v6
const/4 v0, 1
const/4 v1, 1
const/4 v2, 1
const/4 v3, 1
const/16 v4, 0x1908
const/16 v5, 0x1401
invoke-static/range {v0 .. v6}, Landroid/opengl/GLES20;->glReadPixels(IIIIIILjava/nio/Buffer;)V
'
 for index, value in [18, -92, -26, -1] {
  body += 'const/4 v0, ${index}\ninvoke-virtual {v6, v0}, Ljava/nio/ByteBuffer;->get(I)B\nmove-result v0\nconst/16 v1, ${value}\nif-ne v0, v1, :bad\n'
 }
 body += '
const/4 v0, 1
sget-object v1, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;
invoke-static {v0, v0, v1}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v9
const v0, 0xff35c27a
invoke-virtual {v9, v0}, Landroid/graphics/Bitmap;->eraseColor(I)V
const/4 v0, 0
invoke-static {v0}, Landroid/opengl/GLES20;->glEnable(I)V
const/16 v0, 0xde1
const/4 v1, 0
const/4 v2, 1
const/4 v3, 0
move-object v4, v9
invoke-static/range {v0 .. v4}, Landroid/opengl/GLUtils;->texSubImage2D(IIIILandroid/graphics/Bitmap;)V
invoke-static {}, Landroid/opengl/GLES20;->glGetError()I
move-result v0
const/16 v1, 0x500
if-ne v0, v1, :bad
invoke-static {}, Landroid/opengl/GLES20;->glGetError()I
move-result v0
if-nez v0, :bad
'
 body += glutils_pixel(1, 0, [53, -62, 122, -1])
 body += glutils_pixel(0, 1, [18, -92, -26, -1])
 body += '
const v0, 0xffe15329
invoke-virtual {v9, v0}, Landroid/graphics/Bitmap;->eraseColor(I)V
const/16 v0, 0xde1
const/4 v1, 0
const/4 v2, 0
const/4 v3, 1
move-object v4, v9
const/16 v5, 0x1908
const/16 v6, 0x1401
invoke-static/range {v0 .. v6}, Landroid/opengl/GLUtils;->texSubImage2D(IIIILandroid/graphics/Bitmap;II)V
const/4 v0, 4
invoke-static {v0}, Ljava/nio/ByteBuffer;->allocateDirect(I)Ljava/nio/ByteBuffer;
move-result-object v6
'
 body += glutils_pixel(0, 1, [-31, 83, 41, -1])
 body += glutils_pixel(1, 0, [53, -62, 122, -1])
 body += '
const/4 v0, 1
new-array v1, v0, [I
const/16 v0, 0xcf5
const/4 v2, 0
invoke-static {v0, v1, v2}, Landroid/opengl/GLES20;->glGetIntegerv(I[II)V
aget v0, v1, v2
const/16 v1, 8
if-ne v0, v1, :bad
:format_start
const/16 v0, 0xde1
const/4 v1, 0
const/4 v2, 0
const/4 v3, 0
move-object v4, v9
const/16 v5, 0x1907
const/16 v6, 0x1401
invoke-static/range {v0 .. v6}, Landroid/opengl/GLUtils;->texSubImage2D(IIIILandroid/graphics/Bitmap;II)V
:format_end
goto :bad
.catch Ljava/lang/IllegalArgumentException; {:format_start .. :format_end} :format_caught
:format_caught
move-exception v0
:sub_null_start
const/16 v0, 0xde1
const/4 v1, 0
const/4 v2, 0
const/4 v3, 0
const/4 v4, 0
invoke-static/range {v0 .. v4}, Landroid/opengl/GLUtils;->texSubImage2D(IIIILandroid/graphics/Bitmap;)V
:sub_null_end
goto :bad
.catch Ljava/lang/NullPointerException; {:sub_null_start .. :sub_null_end} :sub_null_caught
:sub_null_caught
move-exception v0
invoke-virtual {v9}, Landroid/graphics/Bitmap;->recycle()V
:sub_recycled_start
const/16 v0, 0xde1
const/4 v1, 0
const/4 v2, 0
const/4 v3, 0
move-object v4, v9
invoke-static/range {v0 .. v4}, Landroid/opengl/GLUtils;->texSubImage2D(IIIILandroid/graphics/Bitmap;)V
:sub_recycled_end
goto :bad
.catch Ljava/lang/IllegalStateException; {:sub_recycled_start .. :sub_recycled_end} :sub_recycled_caught
:sub_recycled_caught
move-exception v0
'
 body += '
:null_start
const/16 v0, 0xde1
const/4 v1, 0
const/4 v2, 0
invoke-static {v0, v1, v2, v1}, Landroid/opengl/GLUtils;->texImage2D(IILandroid/graphics/Bitmap;I)V
:null_end
goto :bad
.catch Ljava/lang/NullPointerException; {:null_start .. :null_end} :null_caught
:null_caught
move-exception v0
invoke-virtual {v8}, Landroid/graphics/Bitmap;->recycle()V
:recycled_start
const/16 v0, 0xde1
const/4 v1, 0
invoke-static {v0, v1, v8, v1}, Landroid/opengl/GLUtils;->texImage2D(IILandroid/graphics/Bitmap;I)V
:recycled_end
goto :bad
.catch Ljava/lang/IllegalStateException; {:recycled_start .. :recycled_end} :recycled_caught
:recycled_caught
move-exception v0
const/16 v0, 0xcf5
const/4 v1, 4
invoke-static {v0, v1}, Landroid/opengl/GLES20;->glPixelStorei(II)V
invoke-static {}, Landroid/opengl/GLES20;->glGetError()I
move-result v0
if-nez v0, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-GLUTILS-PASS bitmap RGBA texels subimage-auto-explicit offsets unchanged-neighbors FBO readback preserved-error unpack-alignment invalid-format null recycled"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "GLUtils bitmap texture upload"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
'
 os.write_file(dir+'/GlUtilsProbe.smali', '.class public Lorg/vinix/bootstrap/GlUtilsProbe;\n.super Ljava/lang/Object;\n'+method('public static check()V',body))!
}
