// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

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
const-string v1, "BOOTSTRAP-GLUTILS-PASS bitmap RGBA texels FBO readback preserved-error unpack-alignment null recycled"
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
