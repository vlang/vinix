// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_gles_names_probe(dir string) ! {
 mut body := ''
 for item in ['Buffers 0x8892 Buffer', 'Textures 0x0de1 Texture', 'Framebuffers 0x8d40 Framebuffer', 'Renderbuffers 0x8d41 Renderbuffer'] {
  parts := item.split(' ')
  plural, target, singular := parts[0], parts[1], parts[2]
  body += '
const/4 v0, 3
new-array v1, v0, [I
fill-array-data v1, :sentinels
const/4 v0, 1
invoke-static {v0, v1, v0}, Landroid/opengl/GLES20;->glGen${plural}(I[II)V
aget v2, v1, v0
if-eqz v2, :bad
const v3, ${target}
invoke-static {v3, v2}, Landroid/opengl/GLES20;->glBind${singular}(II)V
invoke-static {v2}, Landroid/opengl/GLES20;->glIs${singular}(I)Z
move-result v4
if-eqz v4, :bad
const/4 v4, 0
aget v5, v1, v4
const/16 v6, 91
if-ne v5, v6, :bad
const/4 v4, 2
aget v5, v1, v4
const/16 v6, 93
if-ne v5, v6, :bad
invoke-static {v1}, Ljava/nio/IntBuffer;->wrap([I)Ljava/nio/IntBuffer;
move-result-object v4
invoke-virtual {v4, v0}, Ljava/nio/Buffer;->position(I)Ljava/nio/Buffer;
invoke-virtual {v4}, Ljava/nio/IntBuffer;->asReadOnlyBuffer()Ljava/nio/IntBuffer;
move-result-object v4
invoke-static {v0, v4}, Landroid/opengl/GLES20;->glDelete${plural}(ILjava/nio/IntBuffer;)V
invoke-static {v2}, Landroid/opengl/GLES20;->glIs${singular}(I)Z
move-result v5
if-nez v5, :bad
const/16 v4, 12
invoke-static {v4}, Ljava/nio/ByteBuffer;->allocateDirect(I)Ljava/nio/ByteBuffer;
move-result-object v4
invoke-static {}, Ljava/nio/ByteOrder;->nativeOrder()Ljava/nio/ByteOrder;
move-result-object v5
invoke-virtual {v4, v5}, Ljava/nio/ByteBuffer;->order(Ljava/nio/ByteOrder;)Ljava/nio/ByteBuffer;
invoke-virtual {v4}, Ljava/nio/ByteBuffer;->asIntBuffer()Ljava/nio/IntBuffer;
move-result-object v4
invoke-virtual {v4, v0}, Ljava/nio/Buffer;->position(I)Ljava/nio/Buffer;
const/4 v5, 2
invoke-virtual {v4, v5}, Ljava/nio/Buffer;->limit(I)Ljava/nio/Buffer;
invoke-static {v0, v4}, Landroid/opengl/GLES20;->glGen${plural}(ILjava/nio/IntBuffer;)V
invoke-virtual {v4}, Ljava/nio/Buffer;->position()I
move-result v5
if-ne v5, v0, :bad
invoke-virtual {v4}, Ljava/nio/Buffer;->limit()I
move-result v5
const/4 v6, 2
if-ne v5, v6, :bad
invoke-virtual {v4, v0}, Ljava/nio/IntBuffer;->get(I)I
move-result v2
if-eqz v2, :bad
invoke-static {v3, v2}, Landroid/opengl/GLES20;->glBind${singular}(II)V
invoke-static {v2}, Landroid/opengl/GLES20;->glIs${singular}(I)Z
move-result v5
if-eqz v5, :bad
aput v2, v1, v0
invoke-static {v0, v1, v0}, Landroid/opengl/GLES20;->glDelete${plural}(I[II)V
invoke-static {v2}, Landroid/opengl/GLES20;->glIs${singular}(I)Z
move-result v5
if-nez v5, :bad
'
 }
 body += '
invoke-static {}, Landroid/opengl/GLES20;->glGetError()I
move-result v0
if-nez v0, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-JAVA-GL-NAMES-PASS buffers textures framebuffers renderbuffers offsets direct read-only-input cursors lifecycle"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Java GL object names"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:sentinels
.array-data 4
91
92
93
.end array-data
'
 os.write_file(dir + '/GlesNamesProbe.smali', '.class public Lorg/vinix/bootstrap/GlesNamesProbe;\n.super Ljava/lang/Object;\n' + method('public static check()V', body))!
}
