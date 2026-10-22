// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_gles_upload_probe(dir string) ! {
 mut body := '
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
const/4 v0, 2
new-array v6, v0, [I
const/4 v1, 0
invoke-static {v0, v6, v1}, Landroid/opengl/GLES20;->glGenBuffers(I[II)V
aget v1, v6, v1
const v0, 0x8892
invoke-static {v0, v1}, Landroid/opengl/GLES20;->glBindBuffer(II)V
const/16 v1, 8
new-array v2, v1, [F
invoke-static {v2}, Ljava/nio/FloatBuffer;->wrap([F)Ljava/nio/FloatBuffer;
move-result-object v2
const/4 v1, 1
invoke-virtual {v2, v1}, Ljava/nio/Buffer;->position(I)Ljava/nio/Buffer;
const/4 v1, 7
invoke-virtual {v2, v1}, Ljava/nio/Buffer;->limit(I)Ljava/nio/Buffer;
const/16 v1, 24
const v3, 0x88e4
invoke-static {v0, v1, v2, v3}, Landroid/opengl/GLES20;->glBufferData(IILjava/nio/Buffer;I)V
const/4 v1, 1
new-array v3, v1, [I
const v1, 0x8764
const/4 v4, 0
invoke-static {v0, v1, v3, v4}, Landroid/opengl/GLES20;->glGetBufferParameteriv(II[II)V
aget v1, v3, v4
const/16 v3, 24
if-ne v1, v3, :bad
:too_short_start
const/16 v1, 25
const v3, 0x88e4
invoke-static {v0, v1, v2, v3}, Landroid/opengl/GLES20;->glBufferData(IILjava/nio/Buffer;I)V
:too_short_end
goto :bad
.catch Ljava/lang/IllegalArgumentException; {:too_short_start .. :too_short_end} :too_short_caught
:too_short_caught
move-exception v1
const/16 v1, 32
invoke-static {v1}, Ljava/nio/ByteBuffer;->allocateDirect(I)Ljava/nio/ByteBuffer;
move-result-object v2
invoke-static {}, Ljava/nio/ByteOrder;->nativeOrder()Ljava/nio/ByteOrder;
move-result-object v1
invoke-virtual {v2, v1}, Ljava/nio/ByteBuffer;->order(Ljava/nio/ByteOrder;)Ljava/nio/ByteBuffer;
invoke-virtual {v2}, Ljava/nio/ByteBuffer;->asFloatBuffer()Ljava/nio/FloatBuffer;
move-result-object v2
const/16 v1, 8
new-array v1, v1, [F
fill-array-data v1, :vertices
invoke-virtual {v2, v1}, Ljava/nio/FloatBuffer;->put([F)Ljava/nio/FloatBuffer;
const/4 v1, 1
invoke-virtual {v2, v1}, Ljava/nio/Buffer;->position(I)Ljava/nio/Buffer;
const/4 v1, 7
invoke-virtual {v2, v1}, Ljava/nio/Buffer;->limit(I)Ljava/nio/Buffer;
const/4 v1, 0
const/16 v3, 24
invoke-static {v0, v1, v3, v2}, Landroid/opengl/GLES20;->glBufferSubData(IIILjava/nio/Buffer;)V
invoke-virtual {v2}, Ljava/nio/Buffer;->position()I
move-result v0
const/4 v1, 1
if-ne v0, v1, :bad
aget v1, v6, v1
const v0, 0x8893
invoke-static {v0, v1}, Landroid/opengl/GLES20;->glBindBuffer(II)V
const/4 v1, 5
new-array v2, v1, [B
fill-array-data v2, :indices
invoke-static {v2}, Ljava/nio/ByteBuffer;->wrap([B)Ljava/nio/ByteBuffer;
move-result-object v2
const/4 v1, 1
invoke-virtual {v2, v1}, Ljava/nio/Buffer;->position(I)Ljava/nio/Buffer;
const/4 v1, 4
invoke-virtual {v2, v1}, Ljava/nio/Buffer;->limit(I)Ljava/nio/Buffer;
const/4 v1, 3
const v3, 0x88e4
invoke-static {v0, v1, v2, v3}, Landroid/opengl/GLES20;->glBufferData(IILjava/nio/Buffer;I)V
const/4 v0, 2
const/4 v1, 2
const/16 v2, 0x1406
const/4 v3, 0
const/4 v4, 0
const/4 v5, 0
invoke-static/range {v0 .. v5}, Landroid/opengl/GLES20;->glVertexAttribPointer(IIIZII)V
invoke-static {v0}, Landroid/opengl/GLES20;->glEnableVertexAttribArray(I)V
const/4 v0, 0
const/4 v1, 0
const/16 v2, 8
const/16 v3, 8
invoke-static {v0, v1, v2, v3}, Landroid/opengl/GLES20;->glViewport(IIII)V
const/high16 v0, 0x3f800000
const/4 v1, 0
invoke-static {v0, v1, v1, v0}, Landroid/opengl/GLES20;->glClearColor(FFFF)V
const/16 v0, 0x4000
invoke-static {v0}, Landroid/opengl/GLES20;->glClear(I)V
const/4 v0, 4
const/4 v1, 3
const/16 v2, 0x1401
const/4 v3, 0
invoke-static {v0, v1, v2, v3}, Landroid/opengl/GLES20;->glDrawElements(IIII)V
invoke-static {}, Landroid/opengl/GLES20;->glFinish()V
const/4 v0, 2
invoke-static {v0}, Landroid/opengl/GLES20;->glDisableVertexAttribArray(I)V
const/4 v1, 0
invoke-static {v0, v6, v1}, Landroid/opengl/GLES20;->glDeleteBuffers(I[II)V
const/4 v0, 3
new-array v0, v0, [F
fill-array-data v0, :float_sentinels
invoke-static {v0}, Ljava/nio/FloatBuffer;->wrap([F)Ljava/nio/FloatBuffer;
move-result-object v6
const/4 v0, 1
invoke-virtual {v6, v0}, Ljava/nio/Buffer;->position(I)Ljava/nio/Buffer;
const/4 v0, 2
invoke-virtual {v6, v0}, Ljava/nio/Buffer;->limit(I)Ljava/nio/Buffer;
const/4 v0, 3
const/4 v1, 3
const/4 v2, 1
const/4 v3, 1
const/16 v4, 0x1908
const/16 v5, 0x1401
invoke-static/range {v0 .. v6}, Landroid/opengl/GLES20;->glReadPixels(IIIIIILjava/nio/Buffer;)V
const/4 v0, 1
invoke-virtual {v6}, Ljava/nio/Buffer;->position()I
move-result v1
if-ne v0, v1, :bad
invoke-virtual {v6, v0}, Ljava/nio/FloatBuffer;->get(I)F
move-result v0
invoke-static {v0}, Ljava/lang/Float;->floatToRawIntBits(F)I
move-result v0
const v1, 0xff00ff00
if-ne v0, v1, :bad
const/4 v0, 3
invoke-virtual {v6, v0}, Ljava/nio/Buffer;->limit(I)Ljava/nio/Buffer;
const/4 v0, 0
invoke-virtual {v6, v0}, Ljava/nio/FloatBuffer;->get(I)F
move-result v0
const/high16 v1, 0x42b60000
cmpl-float v0, v0, v1
if-nez v0, :bad
const/4 v0, 2
invoke-virtual {v6, v0}, Ljava/nio/FloatBuffer;->get(I)F
move-result v0
const/high16 v1, 0x42ba0000
cmpl-float v0, v0, v1
if-nez v0, :bad
const/4 v0, 0
invoke-static {v0}, Landroid/opengl/GLES20;->glUseProgram(I)V
invoke-static {v7}, Landroid/opengl/GLES20;->glDeleteProgram(I)V
invoke-static {v8}, Landroid/opengl/GLES20;->glDeleteShader(I)V
invoke-static {v9}, Landroid/opengl/GLES20;->glDeleteShader(I)V
const/4 v0, 2
invoke-static {v0}, Landroid/opengl/GLES20;->glDisableVertexAttribArray(I)V
'
 // Exercise texture upload and a direct-buffer subimage independently of
 // shaders: attach the texture to an FBO and read the actual texel back.
 body += '
const/4 v0, 2
new-array v9, v0, [I
const/4 v0, 1
const/4 v1, 0
invoke-static {v0, v9, v1}, Landroid/opengl/GLES20;->glGenTextures(I[II)V
aget v1, v9, v1
const/16 v0, 0x0de1
invoke-static {v0, v1}, Landroid/opengl/GLES20;->glBindTexture(II)V
const/16 v0, 24
invoke-static {v0}, Ljava/nio/ByteBuffer;->allocate(I)Ljava/nio/ByteBuffer;
move-result-object v8
'
 for i in 0 .. 4 {
  for channel in 0 .. 4 {
   at := 4 + i * 4 + channel
   value := if channel in [0, 3] { -1 } else { 0 }
   body += 'const/16 v0, ${at}\nconst/16 v1, ${value}\ninvoke-virtual {v8, v0, v1}, Ljava/nio/ByteBuffer;->put(IB)Ljava/nio/ByteBuffer;\n'
  }
 }
 body += '
const/4 v0, 4
invoke-virtual {v8, v0}, Ljava/nio/Buffer;->position(I)Ljava/nio/Buffer;
const/16 v0, 20
invoke-virtual {v8, v0}, Ljava/nio/Buffer;->limit(I)Ljava/nio/Buffer;
const/16 v0, 0x0de1
const/4 v1, 0
const/16 v2, 0x1908
const/4 v3, 2
const/4 v4, 2
const/4 v5, 0
const/16 v6, 0x1908
const/16 v7, 0x1401
invoke-static/range {v0 .. v8}, Landroid/opengl/GLES20;->glTexImage2D(IIIIIIIILjava/nio/Buffer;)V
const/4 v0, 4
invoke-static {v0}, Ljava/nio/ByteBuffer;->allocateDirect(I)Ljava/nio/ByteBuffer;
move-result-object v8
const/4 v0, 2
const/4 v1, -1
invoke-virtual {v8, v0, v1}, Ljava/nio/ByteBuffer;->put(IB)Ljava/nio/ByteBuffer;
const/4 v0, 3
invoke-virtual {v8, v0, v1}, Ljava/nio/ByteBuffer;->put(IB)Ljava/nio/ByteBuffer;
const/16 v0, 0x0de1
const/4 v1, 0
const/4 v2, 1
const/4 v3, 1
const/4 v4, 1
const/4 v5, 1
const/16 v6, 0x1908
const/16 v7, 0x1401
invoke-static/range {v0 .. v8}, Landroid/opengl/GLES20;->glTexSubImage2D(IIIIIIIILjava/nio/Buffer;)V
const/4 v0, 1
invoke-static {v0, v9, v0}, Landroid/opengl/GLES20;->glGenFramebuffers(I[II)V
aget v1, v9, v0
const v0, 0x8d40
invoke-static {v0, v1}, Landroid/opengl/GLES20;->glBindFramebuffer(II)V
const v1, 0x8ce0
const/16 v2, 0x0de1
const/4 v4, 0
aget v3, v9, v4
invoke-static {v0, v1, v2, v3, v4}, Landroid/opengl/GLES20;->glFramebufferTexture2D(IIIII)V
invoke-static {v0}, Landroid/opengl/GLES20;->glCheckFramebufferStatus(I)I
move-result v0
const v1, 0x8cd5
if-ne v0, v1, :bad
const/16 v0, 12
invoke-static {v0}, Ljava/nio/ByteBuffer;->allocateDirect(I)Ljava/nio/ByteBuffer;
move-result-object v6
const/4 v0, 0
const/16 v1, 91
invoke-virtual {v6, v0, v1}, Ljava/nio/ByteBuffer;->put(IB)Ljava/nio/ByteBuffer;
const/16 v0, 8
const/16 v1, 93
invoke-virtual {v6, v0, v1}, Ljava/nio/ByteBuffer;->put(IB)Ljava/nio/ByteBuffer;
const/4 v0, 4
invoke-virtual {v6, v0}, Ljava/nio/Buffer;->position(I)Ljava/nio/Buffer;
const/16 v0, 8
invoke-virtual {v6, v0}, Ljava/nio/Buffer;->limit(I)Ljava/nio/Buffer;
const/4 v0, 1
const/4 v1, 1
const/4 v2, 1
const/4 v3, 1
const/16 v4, 0x1908
const/16 v5, 0x1401
invoke-static/range {v0 .. v6}, Landroid/opengl/GLES20;->glReadPixels(IIIIIILjava/nio/Buffer;)V
invoke-virtual {v6}, Ljava/nio/Buffer;->position()I
move-result v0
const/4 v1, 4
if-ne v0, v1, :bad
invoke-virtual {v6}, Ljava/nio/Buffer;->limit()I
move-result v0
const/16 v1, 8
if-ne v0, v1, :bad
const/16 v0, 12
invoke-virtual {v6, v0}, Ljava/nio/Buffer;->limit(I)Ljava/nio/Buffer;
'
 for at, value in {0: 91, 4: 0, 5: 0, 6: -1, 7: -1, 8: 93} {
  body += 'const/16 v0, ${at}\ninvoke-virtual {v6, v0}, Ljava/nio/ByteBuffer;->get(I)B\nmove-result v0\nconst/16 v1, ${value}\nif-ne v0, v1, :bad\n'
 }
 body += '
const/4 v0, 1
const/4 v1, 1
invoke-static {v0, v9, v1}, Landroid/opengl/GLES20;->glDeleteFramebuffers(I[II)V
const/4 v1, 0
invoke-static {v0, v9, v1}, Landroid/opengl/GLES20;->glDeleteTextures(I[II)V
invoke-static {}, Landroid/opengl/GLES20;->glGetError()I
move-result v0
if-nez v0, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-JAVA-GL-UPLOADS-PASS heap direct typed-buffer positions bounds VBO EBO indexed-draw green-pixel texture subimage FBO blue-texel"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Java GLES buffer uploads, drawing or texture pixels"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:vertices
.array-data 4
0x42c60000
0xbf800000
0xbf800000
0x40400000
0xbf800000
0xbf800000
0x40400000
0x42c60000
.end array-data
:indices
.array-data 1
91
0
1
2
93
.end array-data
:float_sentinels
.array-data 4
0x42b60000
0x42b80000
0x42ba0000
.end array-data
'
 os.write_file(dir + '/GlesUploadProbe.smali', '.class public Lorg/vinix/bootstrap/GlesUploadProbe;\n.super Ljava/lang/Object;\n' + method('public static check()V', body))!
}
