// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_gles_shader_probe(dir string) ! {
	os.write_file(dir + '/GlesShaderProbe.smali', '.class public Lorg/vinix/bootstrap/GlesShaderProbe;\n.super Ljava/lang/Object;\n' + method('public static shader(ILjava/lang/String;)I', '
invoke-static {p0}, Landroid/opengl/GLES20;->glCreateShader(I)I
move-result v0
if-eqz v0, :bad
invoke-static {v0, p1}, Landroid/opengl/GLES20;->glShaderSource(ILjava/lang/String;)V
invoke-static {v0}, Landroid/opengl/GLES20;->glCompileShader(I)V
const/4 v1, 1
new-array v1, v1, [I
const v2, 0x8b81
const/4 v3, 0
invoke-static {v0, v2, v1, v3}, Landroid/opengl/GLES20;->glGetShaderiv(II[II)V
aget v1, v1, v3
if-eqz v1, :bad
return v0
:bad
invoke-static {v0}, Landroid/opengl/GLES20;->glGetShaderInfoLog(I)Ljava/lang/String;
move-result-object v1
sget-object v2, Ljava/lang/System;->out:Ljava/io/PrintStream;
invoke-virtual {v2, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
new-instance v1, Ljava/lang/AssertionError;
const-string v2, "Java shader compilation"
invoke-direct {v1, v2}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v1') + method('public static check()V', '
const v0, 0x8b31
const-string v1, "attribute vec2 pos; void main(){gl_Position=vec4(pos,0.,1.);}"
invoke-static {v0, v1}, Lorg/vinix/bootstrap/GlesShaderProbe;->shader(ILjava/lang/String;)I
move-result v0
const v1, 0x8b30
const-string v2, "precision mediump float; uniform vec4 color; void main(){gl_FragColor=color;}"
invoke-static {v1, v2}, Lorg/vinix/bootstrap/GlesShaderProbe;->shader(ILjava/lang/String;)I
move-result v1
invoke-static {}, Landroid/opengl/GLES20;->glCreateProgram()I
move-result v2
if-eqz v2, :bad
invoke-static {v2, v0}, Landroid/opengl/GLES20;->glAttachShader(II)V
invoke-static {v2, v1}, Landroid/opengl/GLES20;->glAttachShader(II)V
const/4 v3, 2
const-string v4, "pos"
invoke-static {v2, v3, v4}, Landroid/opengl/GLES20;->glBindAttribLocation(IILjava/lang/String;)V
invoke-static {v2}, Landroid/opengl/GLES20;->glLinkProgram(I)V
const/4 v3, 3
new-array v3, v3, [I
fill-array-data v3, :sentinels
const v4, 0x8b82
const/4 v5, 1
invoke-static {v2, v4, v3, v5}, Landroid/opengl/GLES20;->glGetProgramiv(II[II)V
aget v4, v3, v5
if-ne v4, v5, :bad
const/4 v5, 0
aget v4, v3, v5
const/16 v6, 91
if-ne v4, v6, :bad
const/4 v5, 2
aget v4, v3, v5
const/16 v6, 93
if-ne v4, v6, :bad
const-string v4, "pos"
invoke-static {v2, v4}, Landroid/opengl/GLES20;->glGetAttribLocation(ILjava/lang/String;)I
move-result v4
if-ne v4, v5, :bad
const-string v4, "color"
invoke-static {v2, v4}, Landroid/opengl/GLES20;->glGetUniformLocation(ILjava/lang/String;)I
move-result v4
if-ltz v4, :bad
invoke-static {v2}, Landroid/opengl/GLES20;->glUseProgram(I)V
const/4 v5, 0
const/high16 v6, 0x3f800000
invoke-static {v4, v5, v6, v5, v6}, Landroid/opengl/GLES20;->glUniform4f(IFFFF)V
invoke-static {v2, v0}, Landroid/opengl/GLES20;->glDetachShader(II)V
invoke-static {v0}, Landroid/opengl/GLES20;->glIsShader(I)Z
move-result v4
if-eqz v4, :bad
invoke-static {v0}, Landroid/opengl/GLES20;->glDeleteShader(I)V
invoke-static {v0}, Landroid/opengl/GLES20;->glIsShader(I)Z
move-result v4
if-nez v4, :bad
invoke-static {v2, v1}, Landroid/opengl/GLES20;->glDetachShader(II)V
invoke-static {v1}, Landroid/opengl/GLES20;->glDeleteShader(I)V
const/4 v0, 0
invoke-static {v0}, Landroid/opengl/GLES20;->glUseProgram(I)V
invoke-static {v2}, Landroid/opengl/GLES20;->glDeleteProgram(I)V
const/16 v0, 0xbe2
invoke-static {v0}, Landroid/opengl/GLES20;->glEnable(I)V
invoke-static {v0}, Landroid/opengl/GLES20;->glIsEnabled(I)Z
move-result v1
if-eqz v1, :bad
invoke-static {v0}, Landroid/opengl/GLES20;->glDisable(I)V
invoke-static {v0}, Landroid/opengl/GLES20;->glIsEnabled(I)Z
move-result v1
if-nez v1, :bad
const v0, 0x8b31
invoke-static {v0}, Landroid/opengl/GLES20;->glCreateShader(I)I
move-result v0
const-string v1, "invalid shader source"
invoke-static {v0, v1}, Landroid/opengl/GLES20;->glShaderSource(ILjava/lang/String;)V
invoke-static {v0}, Landroid/opengl/GLES20;->glCompileShader(I)V
const v1, 0x8b81
const/4 v2, 0
invoke-static {v0, v1, v3, v2}, Landroid/opengl/GLES20;->glGetShaderiv(II[II)V
aget v1, v3, v2
if-nez v1, :bad
invoke-static {v0}, Landroid/opengl/GLES20;->glGetShaderInfoLog(I)Ljava/lang/String;
move-result-object v1
invoke-virtual {v1}, Ljava/lang/String;->isEmpty()Z
move-result v1
if-nez v1, :bad
invoke-static {v0}, Landroid/opengl/GLES20;->glDeleteShader(I)V
invoke-static {}, Landroid/opengl/GLES20;->glGetError()I
move-result v0
if-nez v0, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-JAVA-SHADERS-PASS compile link locations uniform offsets lifecycle booleans compiler-errors"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Java GLES shaders"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:sentinels
.array-data 4
91
92
93
.end array-data
'))!
}
