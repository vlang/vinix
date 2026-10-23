// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_gles_attribute_probe(dir string) ! {
 mut body := ''
 for width in [1,2,3,4] {
  function := 'glVertexAttrib${width}fv'
  body += 'const/16 v0, ${width+2}\nnew-array v3, v0, [F\nconst/high16 v0, 0x3f800000\n'
  for element in 0 .. width { body += 'const/4 v1, ${element+1}\naput v0, v3, v1\n' }
  body += 'const/4 v0, 1\nconst/4 v4, 1\n' +
   'invoke-static {v0, v3, v4}, Landroid/opengl/GLES20;->${function}(I[FI)V\n' +
   'invoke-static {v3}, Ljava/nio/FloatBuffer;->wrap([F)Ljava/nio/FloatBuffer;\nmove-result-object v8\n' +
   'const/4 v0, 1\ninvoke-virtual {v8, v0}, Ljava/nio/Buffer;->position(I)Ljava/nio/Buffer;\n' +
   'const/4 v0, ${width+1}\ninvoke-virtual {v8, v0}, Ljava/nio/Buffer;->limit(I)Ljava/nio/Buffer;\n' +
   'const/4 v0, 1\ninvoke-static {v0, v8}, Landroid/opengl/GLES20;->${function}(ILjava/nio/FloatBuffer;)V\n' +
   'invoke-virtual {v8}, Ljava/nio/Buffer;->position()I\nmove-result v0\nconst/4 v1, 1\nif-ne v0, v1, :bad\n' +
   'const/16 v0, ${(width+2)*4}\ninvoke-static {v0}, Ljava/nio/ByteBuffer;->allocateDirect(I)Ljava/nio/ByteBuffer;\nmove-result-object v8\n' +
   'invoke-static {}, Ljava/nio/ByteOrder;->nativeOrder()Ljava/nio/ByteOrder;\nmove-result-object v0\n' +
   'invoke-virtual {v8, v0}, Ljava/nio/ByteBuffer;->order(Ljava/nio/ByteOrder;)Ljava/nio/ByteBuffer;\n' +
   'invoke-virtual {v8}, Ljava/nio/ByteBuffer;->asFloatBuffer()Ljava/nio/FloatBuffer;\nmove-result-object v8\n' +
   'invoke-virtual {v8, v3}, Ljava/nio/FloatBuffer;->put([F)Ljava/nio/FloatBuffer;\n' +
   'const/4 v0, 1\ninvoke-virtual {v8, v0}, Ljava/nio/Buffer;->position(I)Ljava/nio/Buffer;\n' +
   'const/4 v0, ${width+1}\ninvoke-virtual {v8, v0}, Ljava/nio/Buffer;->limit(I)Ljava/nio/Buffer;\n' +
   'invoke-virtual {v8}, Ljava/nio/FloatBuffer;->asReadOnlyBuffer()Ljava/nio/FloatBuffer;\nmove-result-object v8\n' +
   'const/4 v0, 1\ninvoke-static {v0, v8}, Landroid/opengl/GLES20;->${function}(ILjava/nio/FloatBuffer;)V\n' +
   'invoke-virtual {v8}, Ljava/nio/Buffer;->position()I\nmove-result v0\nconst/4 v1, 1\nif-ne v0, v1, :bad\n'
 }
 body += '
const/4 v0, 1
const/4 v4, 3
:short_start
invoke-static {v0, v3, v4}, Landroid/opengl/GLES20;->glVertexAttrib4fv(I[FI)V
:short_end
goto :bad
.catch Ljava/lang/IllegalArgumentException; {:short_start .. :short_end} :short_caught
:short_caught
move-exception v0
invoke-static {}, Landroid/opengl/GLES20;->glGetError()I
move-result v0
if-nez v0, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "vertex attribute arrays, buffers, positions or bounds"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
 os.write_file(dir+'/GlesAttributeProbe.smali','.class public Lorg/vinix/bootstrap/GlesAttributeProbe;\n.super Ljava/lang/Object;\n'+method('public static check()V',body))!
}
