// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_gles_uniform_probe(dir string) ! {
 mut body := ''
 for dimension in [2, 3, 4] {
  name := if dimension == 4 { 'transform' } else { 'tint${dimension}' }
  elements := dimension * dimension
  body += 'const-string v0, "${name}"\ninvoke-static {p0, v0}, Landroid/opengl/GLES20;->glGetUniformLocation(ILjava/lang/String;)I\nmove-result v7\nif-ltz v7, :bad\n' +
   'const/16 v0, ${elements + 2}\nnew-array v3, v0, [F\nconst/high16 v0, 0x3f800000\n'
  for diagonal in 0 .. dimension {
   body += 'const/16 v1, ${1 + diagonal * (dimension + 1)}\naput v0, v3, v1\n'
  }
  body += 'move v0, v7\nconst/4 v1, 1\nconst/4 v2, 0\nconst/4 v4, 1\n' +
   'invoke-static {v0, v1, v2, v3, v4}, Landroid/opengl/GLES20;->glUniformMatrix${dimension}fv(IIZ[FI)V\n' +
   'invoke-static {v3}, Ljava/nio/FloatBuffer;->wrap([F)Ljava/nio/FloatBuffer;\nmove-result-object v8\n' +
   'const/4 v0, 1\ninvoke-virtual {v8, v0}, Ljava/nio/Buffer;->position(I)Ljava/nio/Buffer;\n' +
   'const/16 v0, ${elements + 1}\ninvoke-virtual {v8, v0}, Ljava/nio/Buffer;->limit(I)Ljava/nio/Buffer;\n' +
   'move-object v9, v8\n' +
   'move v0, v7\nconst/4 v1, 1\nconst/4 v2, 0\n' +
   'invoke-static {v0, v1, v2, v9}, Landroid/opengl/GLES20;->glUniformMatrix${dimension}fv(IIZLjava/nio/FloatBuffer;)V\n' +
   'invoke-virtual {v9}, Ljava/nio/Buffer;->position()I\nmove-result v0\nconst/4 v1, 1\nif-ne v0, v1, :bad\n' +
   'const/16 v0, ${(elements + 2) * 4}\ninvoke-static {v0}, Ljava/nio/ByteBuffer;->allocateDirect(I)Ljava/nio/ByteBuffer;\nmove-result-object v8\n' +
   'invoke-static {}, Ljava/nio/ByteOrder;->nativeOrder()Ljava/nio/ByteOrder;\nmove-result-object v0\n' +
   'invoke-virtual {v8, v0}, Ljava/nio/ByteBuffer;->order(Ljava/nio/ByteOrder;)Ljava/nio/ByteBuffer;\n' +
   'invoke-virtual {v8}, Ljava/nio/ByteBuffer;->asFloatBuffer()Ljava/nio/FloatBuffer;\nmove-result-object v8\n' +
   'invoke-virtual {v8, v3}, Ljava/nio/FloatBuffer;->put([F)Ljava/nio/FloatBuffer;\n' +
   'const/4 v0, 1\ninvoke-virtual {v8, v0}, Ljava/nio/Buffer;->position(I)Ljava/nio/Buffer;\n' +
   'const/16 v0, ${elements + 1}\ninvoke-virtual {v8, v0}, Ljava/nio/Buffer;->limit(I)Ljava/nio/Buffer;\n' +
   'invoke-virtual {v8}, Ljava/nio/FloatBuffer;->asReadOnlyBuffer()Ljava/nio/FloatBuffer;\nmove-result-object v8\n' +
   'move v0, v7\nconst/4 v1, 1\nconst/4 v2, 0\n' +
   'invoke-static {v0, v1, v2, v8}, Landroid/opengl/GLES20;->glUniformMatrix${dimension}fv(IIZLjava/nio/FloatBuffer;)V\n' +
   'invoke-virtual {v8}, Ljava/nio/Buffer;->position()I\nmove-result v0\nconst/4 v1, 1\nif-ne v0, v1, :bad\n'
 }
 body += '
move v0, v7
const/4 v1, 1
const/4 v2, 0
const/4 v4, 3
:short_array_start
invoke-static {v0, v1, v2, v3, v4}, Landroid/opengl/GLES20;->glUniformMatrix4fv(IIZ[FI)V
:short_array_end
goto :bad
.catch Ljava/lang/IllegalArgumentException; {:short_array_start .. :short_array_end} :short_array_caught
:short_array_caught
move-exception v5
const/16 v5, 16
invoke-virtual {v8, v5}, Ljava/nio/Buffer;->position(I)Ljava/nio/Buffer;
:short_buffer_start
invoke-static {v0, v1, v2, v8}, Landroid/opengl/GLES20;->glUniformMatrix4fv(IIZLjava/nio/FloatBuffer;)V
:short_buffer_end
goto :bad
.catch Ljava/lang/IllegalArgumentException; {:short_buffer_start .. :short_buffer_end} :short_buffer_caught
:short_buffer_caught
move-exception v5
const/4 v1, -1
const/4 v4, 0
:negative_start
invoke-static {v0, v1, v2, v3, v4}, Landroid/opengl/GLES20;->glUniformMatrix4fv(IIZ[FI)V
:negative_end
goto :bad
.catch Ljava/lang/IllegalArgumentException; {:negative_start .. :negative_end} :negative_caught
:negative_caught
move-exception v5
const/4 v1, 0
const/16 v4, 18
invoke-static {v0, v1, v2, v3, v4}, Landroid/opengl/GLES20;->glUniformMatrix4fv(IIZ[FI)V
invoke-static {}, Landroid/opengl/GLES20;->glGetError()I
move-result v0
if-nez v0, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "matrix uniforms, offsets, NIO positions or bounds"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0'
 os.write_file(dir + '/GlesUniformProbe.smali', '.class public Lorg/vinix/bootstrap/GlesUniformProbe;\n.super Ljava/lang/Object;\n' + method('public static check(I)V', body))!
}
