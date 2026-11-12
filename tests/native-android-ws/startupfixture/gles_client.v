// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

// Reuse the complete EGL/GLES regression with the current signed API fixture.
pub fn install_gles_client_regression(root string) ! {
 dir := root + '/smali'
 install_egl_probe(dir)!
 install_gles_probe(dir)!
 install_gles_shader_probe(dir)!
 install_gles_names_probe(dir)!
 install_gles_upload_probe(dir)!
 install_gles_uniform_probe(dir)!
 install_gles_vector_probe(dir)!
 install_gles_attribute_probe(dir)!
 install_glutils_probe(dir)!
 install_alpha8_probe(dir)!
 install_gles_client_probe(dir)!
}

fn install_gles_client_probe(dir string) ! {
 mut body := r'
const v0, 0x8b31
const-string v1, "attribute vec2 pos; void main(){gl_Position=vec4(pos,0.,1.);}"
invoke-static {v0, v1}, Lorg/vinix/bootstrap/GlesShaderProbe;->shader(ILjava/lang/String;)I
move-result v8
const v0, 0x8b30
const-string v1, "precision mediump float; void main(){gl_FragColor=vec4(0.,1.,0.,1.);}"
invoke-static {v0, v1}, Lorg/vinix/bootstrap/GlesShaderProbe;->shader(ILjava/lang/String;)I
move-result v9
invoke-static {}, Landroid/opengl/GLES20;->glCreateProgram()I
move-result v7
invoke-static {v7, v8}, Landroid/opengl/GLES20;->glAttachShader(II)V
invoke-static {v7, v9}, Landroid/opengl/GLES20;->glAttachShader(II)V
const/4 v0, 2
const-string v1, "pos"
invoke-static {v7, v0, v1}, Landroid/opengl/GLES20;->glBindAttribLocation(IILjava/lang/String;)V
invoke-static {v7}, Landroid/opengl/GLES20;->glLinkProgram(I)V
invoke-static {v7}, Landroid/opengl/GLES20;->glUseProgram(I)V
const v0, 0x8892
const/4 v1, 0
invoke-static {v0, v1}, Landroid/opengl/GLES20;->glBindBuffer(II)V
const/16 v0, 36
invoke-static {v0}, Ljava/nio/ByteBuffer;->allocateDirect(I)Ljava/nio/ByteBuffer;
move-result-object v5
invoke-static {}, Ljava/nio/ByteOrder;->nativeOrder()Ljava/nio/ByteOrder;
move-result-object v0
invoke-virtual {v5, v0}, Ljava/nio/ByteBuffer;->order(Ljava/nio/ByteOrder;)Ljava/nio/ByteBuffer;
invoke-virtual {v5}, Ljava/nio/ByteBuffer;->asFloatBuffer()Ljava/nio/FloatBuffer;
move-result-object v5
const/4 v0, 1
invoke-virtual {v5, v0}, Ljava/nio/Buffer;->position(I)Ljava/nio/Buffer;
const/4 v0, 7
invoke-virtual {v5, v0}, Ljava/nio/Buffer;->limit(I)Ljava/nio/Buffer;
move-object v10, v5
const/4 v0, 2
const/4 v1, 2
const/16 v2, 0x1406
const/4 v3, 0
const/4 v4, 0
invoke-static/range {v0 .. v5}, Landroid/opengl/GLES20;->glVertexAttribPointer(IIIZILjava/nio/Buffer;)V
invoke-static {v0}, Landroid/opengl/GLES20;->glEnableVertexAttribArray(I)V
'
 // Populate after pointer registration: a transient upload copy would draw
 // the old degenerate triangle, and an ignored FloatBuffer position misdraws.
 for i, value in [u32(0xbf800000), 0xbf800000, 0x40400000, 0xbf800000, 0xbf800000, 0x40400000] {
  body += 'const/4 v0, ${i+1}\nconst v1, ${value}\ninvoke-virtual {v5, v0, v1}, Ljava/nio/FloatBuffer;->put(IF)Ljava/nio/FloatBuffer;\n'
 }
 body += r'
invoke-static {}, Ljava/lang/System;->gc()V
invoke-virtual {v5}, Ljava/nio/Buffer;->position()I
move-result v0
const/4 v1, 1
if-ne v0, v1, :bad
invoke-virtual {v5}, Ljava/nio/Buffer;->limit()I
move-result v0
const/4 v1, 7
if-ne v0, v1, :bad
const/4 v0, 0
const/4 v1, 0
const/16 v2, 8
const/16 v3, 8
invoke-static {v0, v1, v2, v3}, Landroid/opengl/GLES20;->glViewport(IIII)V
'
 for kind in ['direct', 'readonly', 'heap-rejection'] {
  if kind == 'readonly' {
   body += r'
invoke-virtual {v10}, Ljava/nio/FloatBuffer;->asReadOnlyBuffer()Ljava/nio/FloatBuffer;
move-result-object v5
move-object v10, v5
const/4 v0, 2
const/4 v1, 2
const/16 v2, 0x1406
const/4 v3, 0
const/4 v4, 0
invoke-static/range {v0 .. v5}, Landroid/opengl/GLES20;->glVertexAttribPointer(IIIZILjava/nio/Buffer;)V
'
  } else if kind == 'heap-rejection' {
   body += r'
const/16 v0, 6
invoke-static {v0}, Ljava/nio/FloatBuffer;->allocate(I)Ljava/nio/FloatBuffer;
move-result-object v5
const/4 v0, 2
const/4 v1, 2
const/16 v2, 0x1406
const/4 v3, 0
const/4 v4, 0
:heap_begin
invoke-static/range {v0 .. v5}, Landroid/opengl/GLES20;->glVertexAttribPointer(IIIZILjava/nio/Buffer;)V
:heap_end
goto :bad
.catch Ljava/lang/IllegalArgumentException; {:heap_begin .. :heap_end} :heap_ok
:heap_ok
move-exception v0
'
  }
  body += r'
const/high16 v0, 0x3f800000
const/4 v1, 0
invoke-static {v0, v1, v1, v0}, Landroid/opengl/GLES20;->glClearColor(FFFF)V
const/16 v0, 0x4000
invoke-static {v0}, Landroid/opengl/GLES20;->glClear(I)V
const/4 v0, 4
const/4 v1, 0
const/4 v2, 3
invoke-static {v0, v1, v2}, Landroid/opengl/GLES20;->glDrawArrays(III)V
invoke-static {}, Landroid/opengl/GLES20;->glFinish()V
const/4 v0, 4
invoke-static {v0}, Ljava/nio/ByteBuffer;->allocateDirect(I)Ljava/nio/ByteBuffer;
move-result-object v6
const/4 v0, 3
const/4 v1, 3
const/4 v2, 1
const/4 v3, 1
const/16 v4, 0x1908
const/16 v5, 0x1401
invoke-static/range {v0 .. v6}, Landroid/opengl/GLES20;->glReadPixels(IIIIIILjava/nio/Buffer;)V
'
  for i, value in [0, -1, 0, -1] {
   body += 'const/4 v0, ${i}\ninvoke-virtual {v6, v0}, Ljava/nio/ByteBuffer;->get(I)B\nmove-result v0\nconst/4 v1, ${value}\nif-ne v0, v1, :bad\n'
  }
 }
 body += r'
invoke-virtual {v10}, Ljava/nio/Buffer;->position()I
move-result v0
const/4 v1, 1
if-ne v0, v1, :bad
const/4 v0, 2
invoke-static {v0}, Landroid/opengl/GLES20;->glDisableVertexAttribArray(I)V
const/4 v0, 0
invoke-static {v0}, Landroid/opengl/GLES20;->glUseProgram(I)V
invoke-static {v7}, Landroid/opengl/GLES20;->glDeleteProgram(I)V
invoke-static {v8}, Landroid/opengl/GLES20;->glDeleteShader(I)V
invoke-static {v9}, Landroid/opengl/GLES20;->glDeleteShader(I)V
invoke-static {}, Landroid/opengl/GLES20;->glGetError()I
move-result v0
if-nez v0, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "GLES-CLIENT-POINTER-PASS pixels position limit live-mutations readonly heap-rejection"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "GLES client pointer pixels, position or storage"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
'
 os.write_file(dir + '/GlesClientProbe.smali', '.class public Lorg/vinix/bootstrap/GlesClientProbe;\n.super Ljava/lang/Object;\n' + method('public static check()V', body).replace('.locals 10', '.locals 11'))!
}
