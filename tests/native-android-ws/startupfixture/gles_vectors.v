// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_gles_vector_probe(dir string) ! {
 mut body := ''
 for integer in [false, true] {
  letter := if integer { 'i' } else { 'f' }
  primitive := if integer { 'I' } else { 'F' }
  buffer := if integer { 'Int' } else { 'Float' }
  for width in [1, 2, 3, 4] {
   function := 'glUniform${width}${letter}v'
   body += 'const-string v0, "${letter}${width}"\ninvoke-static {p0, v0}, Landroid/opengl/GLES20;->glGetUniformLocation(ILjava/lang/String;)I\nmove-result v7\nif-ltz v7, :bad\n' +
    'const/16 v0, ${width + 2}\nnew-array v3, v0, [${primitive}\n' +
    if integer { 'const/4 v0, 1\n' } else { 'const/high16 v0, 0x3f800000\n' }
   for element in 0 .. width { body += 'const/4 v1, ${element + 1}\naput v0, v3, v1\n' }
   body += 'move v0, v7\nconst/4 v1, 1\nconst/4 v4, 1\n' +
    'invoke-static {v0, v1, v3, v4}, Landroid/opengl/GLES20;->${function}(II[${primitive}I)V\n' +
    'invoke-static {v3}, Ljava/nio/${buffer}Buffer;->wrap([${primitive})Ljava/nio/${buffer}Buffer;\nmove-result-object v8\n' +
    'const/4 v0, 1\ninvoke-virtual {v8, v0}, Ljava/nio/Buffer;->position(I)Ljava/nio/Buffer;\n' +
    'const/4 v0, ${width + 1}\ninvoke-virtual {v8, v0}, Ljava/nio/Buffer;->limit(I)Ljava/nio/Buffer;\n' +
    'move v0, v7\ninvoke-static {v0, v1, v8}, Landroid/opengl/GLES20;->${function}(IILjava/nio/${buffer}Buffer;)V\n' +
    'invoke-virtual {v8}, Ljava/nio/Buffer;->position()I\nmove-result v0\nconst/4 v1, 1\nif-ne v0, v1, :bad\n' +
    'const/16 v0, ${(width + 2) * 4}\ninvoke-static {v0}, Ljava/nio/ByteBuffer;->allocateDirect(I)Ljava/nio/ByteBuffer;\nmove-result-object v8\n' +
    'invoke-static {}, Ljava/nio/ByteOrder;->nativeOrder()Ljava/nio/ByteOrder;\nmove-result-object v0\n' +
    'invoke-virtual {v8, v0}, Ljava/nio/ByteBuffer;->order(Ljava/nio/ByteOrder;)Ljava/nio/ByteBuffer;\n' +
    'invoke-virtual {v8}, Ljava/nio/ByteBuffer;->as${buffer}Buffer()Ljava/nio/${buffer}Buffer;\nmove-result-object v8\n' +
    'invoke-virtual {v8, v3}, Ljava/nio/${buffer}Buffer;->put([${primitive})Ljava/nio/${buffer}Buffer;\n' +
    'const/4 v0, 1\ninvoke-virtual {v8, v0}, Ljava/nio/Buffer;->position(I)Ljava/nio/Buffer;\n' +
    'const/4 v0, ${width + 1}\ninvoke-virtual {v8, v0}, Ljava/nio/Buffer;->limit(I)Ljava/nio/Buffer;\n' +
    'invoke-virtual {v8}, Ljava/nio/${buffer}Buffer;->asReadOnlyBuffer()Ljava/nio/${buffer}Buffer;\nmove-result-object v8\n' +
    'move v0, v7\nconst/4 v1, 1\ninvoke-static {v0, v1, v8}, Landroid/opengl/GLES20;->${function}(IILjava/nio/${buffer}Buffer;)V\n' +
    'invoke-virtual {v8}, Ljava/nio/Buffer;->position()I\nmove-result v0\nconst/4 v1, 1\nif-ne v0, v1, :bad\n'
  }
 }
 body += 'invoke-static {}, Landroid/opengl/GLES20;->glGetError()I\nmove-result v0\nif-nez v0, :bad\nreturn-void\n:bad\n' +
  'new-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "vector uniform arrays, heap/direct buffers or positions"\n' +
  'invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
 os.write_file(dir + '/GlesVectorProbe.smali', '.class public Lorg/vinix/bootstrap/GlesVectorProbe;\n.super Ljava/lang/Object;\n' + method('public static check(I)V', body))!
}
