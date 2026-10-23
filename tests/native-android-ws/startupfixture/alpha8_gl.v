// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

// GlUtilsProbe calls this while its RGBA texture is attached to a complete FBO.
fn alpha8_gl_methods() string {
	mut body := '
const/4 v0, 3
const/4 v1, 2
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Alpha8Probe;->alpha(II)Landroid/graphics/Bitmap;
move-result-object v8
const v0, 0x40123456
invoke-virtual {v8, v0}, Landroid/graphics/Bitmap;->eraseColor(I)V
const/4 v0, 3
new-array v1, v0, [I
fill-array-data v1, :mask_colors
invoke-static {v8, v1}, Lorg/vinix/bootstrap/Alpha8Probe;->putRow(Landroid/graphics/Bitmap;[I)V
const/4 v0, 2
new-array v9, v0, [I
const/4 v0, 1
const/4 v1, 0
invoke-static {v0, v9, v1}, Landroid/opengl/GLES20;->glGenTextures(I[II)V
const v0, 0x84c0
invoke-static {v0}, Landroid/opengl/GLES20;->glActiveTexture(I)V
aget v1, v9, v1
const/16 v0, 0xde1
invoke-static {v0, v1}, Landroid/opengl/GLES20;->glBindTexture(II)V
const/16 v0, 0xcf5
const/16 v1, 8
invoke-static {v0, v1}, Landroid/opengl/GLES20;->glPixelStorei(II)V
:unpack_start
const/16 v0, 0xde1
const/4 v1, 0
invoke-static {v0, v1, v8, v1}, Landroid/opengl/GLUtils;->texImage2D(IILandroid/graphics/Bitmap;I)V
:unpack_end
goto :bad
.catch Ljava/lang/IllegalArgumentException; {:unpack_start .. :unpack_end} :unpack_caught
:unpack_caught
move-exception v0
const/4 v0, 1
new-array v1, v0, [I
const/16 v0, 0xcf5
const/4 v2, 0
invoke-static {v0, v1, v2}, Landroid/opengl/GLES20;->glGetIntegerv(I[II)V
aget v0, v1, v2
const/16 v1, 8
if-ne v0, v1, :bad
const/16 v0, 0xcf5
const/4 v1, 4
invoke-static {v0, v1}, Landroid/opengl/GLES20;->glPixelStorei(II)V
const/16 v0, 0xde1
const/4 v1, 0
invoke-static {v0, v1, v8, v1}, Landroid/opengl/GLUtils;->texImage2D(IILandroid/graphics/Bitmap;I)V
const/16 v1, 0x2801
const/16 v2, 0x2600
invoke-static {v0, v1, v2}, Landroid/opengl/GLES20;->glTexParameteri(III)V
const/16 v1, 0x2800
invoke-static {v0, v1, v2}, Landroid/opengl/GLES20;->glTexParameteri(III)V
const/16 v1, 0x2802
const v2, 0x812f
invoke-static {v0, v1, v2}, Landroid/opengl/GLES20;->glTexParameteri(III)V
const/16 v1, 0x2803
invoke-static {v0, v1, v2}, Landroid/opengl/GLES20;->glTexParameteri(III)V
const v0, 0x8b31
const-string v1, "attribute vec2 pos; void main(){gl_Position=vec4(pos,0.,1.);}"
invoke-static {v0, v1}, Lorg/vinix/bootstrap/GlesShaderProbe;->shader(ILjava/lang/String;)I
move-result v2
const v0, 0x8b30
const-string v1, "precision mediump float; uniform sampler2D mask; uniform vec2 uv; void main(){gl_FragColor=vec4(texture2D(mask,uv).a,0.,0.,1.);}"
invoke-static {v0, v1}, Lorg/vinix/bootstrap/GlesShaderProbe;->shader(ILjava/lang/String;)I
move-result v3
invoke-static {}, Landroid/opengl/GLES20;->glCreateProgram()I
move-result v7
invoke-static {v7, v2}, Landroid/opengl/GLES20;->glAttachShader(II)V
invoke-static {v7, v3}, Landroid/opengl/GLES20;->glAttachShader(II)V
invoke-static {v2}, Landroid/opengl/GLES20;->glDeleteShader(I)V
invoke-static {v3}, Landroid/opengl/GLES20;->glDeleteShader(I)V
const/4 v0, 0
const-string v1, "pos"
invoke-static {v7, v0, v1}, Landroid/opengl/GLES20;->glBindAttribLocation(IILjava/lang/String;)V
invoke-static {v7}, Landroid/opengl/GLES20;->glLinkProgram(I)V
const/4 v0, 1
new-array v2, v0, [I
const v1, 0x8b82
const/4 v3, 0
invoke-static {v7, v1, v2, v3}, Landroid/opengl/GLES20;->glGetProgramiv(II[II)V
aget v1, v2, v3
if-ne v1, v0, :bad
invoke-static {v7}, Landroid/opengl/GLES20;->glUseProgram(I)V
const-string v0, "mask"
invoke-static {v7, v0}, Landroid/opengl/GLES20;->glGetUniformLocation(ILjava/lang/String;)I
move-result v0
const/4 v1, 0
invoke-static {v0, v1}, Landroid/opengl/GLES20;->glUniform1i(II)V
const/16 v0, 24
invoke-static {v0}, Ljava/nio/ByteBuffer;->allocateDirect(I)Ljava/nio/ByteBuffer;
move-result-object v5
invoke-static {}, Ljava/nio/ByteOrder;->nativeOrder()Ljava/nio/ByteOrder;
move-result-object v0
invoke-virtual {v5, v0}, Ljava/nio/ByteBuffer;->order(Ljava/nio/ByteOrder;)Ljava/nio/ByteBuffer;
invoke-virtual {v5}, Ljava/nio/ByteBuffer;->asFloatBuffer()Ljava/nio/FloatBuffer;
move-result-object v5
const/4 v0, 6
new-array v0, v0, [F
fill-array-data v0, :vertices
invoke-virtual {v5, v0}, Ljava/nio/FloatBuffer;->put([F)Ljava/nio/FloatBuffer;
const/4 v0, 0
invoke-virtual {v5, v0}, Ljava/nio/Buffer;->position(I)Ljava/nio/Buffer;
const/4 v0, 1
const/4 v1, 1
invoke-static {v0, v9, v1}, Landroid/opengl/GLES20;->glGenBuffers(I[II)V
aget v1, v9, v1
const v0, 0x8892
invoke-static {v0, v1}, Landroid/opengl/GLES20;->glBindBuffer(II)V
const/16 v1, 24
const v2, 0x88e4
invoke-static {v0, v1, v5, v2}, Landroid/opengl/GLES20;->glBufferData(IILjava/nio/Buffer;I)V
const/4 v0, 0
const/4 v1, 2
const/16 v2, 0x1406
const/4 v3, 0
const/4 v4, 0
const/4 v5, 0
invoke-static/range {v0 .. v5}, Landroid/opengl/GLES20;->glVertexAttribPointer(IIIZII)V
invoke-static {v0}, Landroid/opengl/GLES20;->glEnableVertexAttribArray(I)V
const/4 v1, 0
const/4 v2, 2
const/4 v3, 2
invoke-static {v0, v1, v2, v3}, Landroid/opengl/GLES20;->glViewport(IIII)V
const v0, 0x8892
const/4 v1, 0
invoke-static {v0, v1}, Landroid/opengl/GLES20;->glBindBuffer(II)V
'
	for sample in [[0x3e2aaaab, 0x3e800000, 16], [0x3f000000, 0x3e800000, 128],
		[0x3f555555, 0x3e800000, 255], [0x3e2aaaab, 0x3f400000, 64]] {
		body += 'const v0, ${sample[0]}\nconst v1, ${sample[1]}\nconst/16 v2, ${sample[2]}\n' +
			'invoke-static {v7, v0, v1, v2}, Lorg/vinix/bootstrap/Alpha8Probe;->sample(IFFI)V\n'
	}
	body += '
invoke-virtual {v8}, Landroid/graphics/Bitmap;->recycle()V
const/4 v0, 3
const/4 v1, 1
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Alpha8Probe;->alpha(II)Landroid/graphics/Bitmap;
move-result-object v8
const v0, 0x20abcdef
invoke-virtual {v8, v0}, Landroid/graphics/Bitmap;->eraseColor(I)V
const/16 v0, 0xde1
const/4 v1, 0
const/4 v2, 0
const/4 v3, 1
move-object v4, v8
const/16 v5, 0x1906
const/16 v6, 0x1401
invoke-static/range {v0 .. v6}, Landroid/opengl/GLUtils;->texSubImage2D(IIIILandroid/graphics/Bitmap;II)V
const v0, 0x3f555555
const v1, 0x3f400000
const/16 v2, 32
invoke-static {v7, v0, v1, v2}, Lorg/vinix/bootstrap/Alpha8Probe;->sample(IFFI)V
const/4 v0, 1
new-array v1, v0, [I
const/16 v0, 0xcf5
const/4 v2, 0
invoke-static {v0, v1, v2}, Landroid/opengl/GLES20;->glGetIntegerv(I[II)V
aget v0, v1, v2
const/4 v1, 4
if-ne v0, v1, :bad
const/4 v0, 0
invoke-static {v0}, Landroid/opengl/GLES20;->glDisableVertexAttribArray(I)V
invoke-static {v0}, Landroid/opengl/GLES20;->glUseProgram(I)V
invoke-static {v7}, Landroid/opengl/GLES20;->glDeleteProgram(I)V
const/4 v0, 1
const/4 v1, 1
invoke-static {v0, v9, v1}, Landroid/opengl/GLES20;->glDeleteBuffers(I[II)V
const/4 v1, 0
invoke-static {v0, v9, v1}, Landroid/opengl/GLES20;->glDeleteTextures(I[II)V
invoke-virtual {v8}, Landroid/graphics/Bitmap;->recycle()V
invoke-static {}, Landroid/opengl/GLES20;->glGetError()I
move-result v0
if-nez v0, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-ALPHA8-GL-PASS alpha-texture odd-width padded-rows shader-readback subimage unpack-state rejected-overrun"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "ALPHA_8 GL texture or padded row upload"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:mask_colors
.array-data 4
0x10010203
0x80abcdef
0xff336699
.end array-data
:vertices
.array-data 4
0xbf800000
0xbf800000
0x40400000
0xbf800000
0xbf800000
0x40400000
.end array-data
'
	return method('public static checkGl()V', body) + method('private static sample(IFFI)V', '
const-string v0, "uv"
invoke-static {p0, v0}, Landroid/opengl/GLES20;->glGetUniformLocation(ILjava/lang/String;)I
move-result v0
invoke-static {v0, p1, p2}, Landroid/opengl/GLES20;->glUniform2f(IFF)V
const/4 v0, 4
const/4 v1, 0
const/4 v2, 3
invoke-static {v0, v1, v2}, Landroid/opengl/GLES20;->glDrawArrays(III)V
const/4 v0, 4
invoke-static {v0}, Ljava/nio/ByteBuffer;->allocateDirect(I)Ljava/nio/ByteBuffer;
move-result-object v6
const/4 v0, 0
const/4 v1, 0
const/4 v2, 1
const/4 v3, 1
const/16 v4, 0x1908
const/16 v5, 0x1401
invoke-static/range {v0 .. v6}, Landroid/opengl/GLES20;->glReadPixels(IIIIIILjava/nio/Buffer;)V
const/4 v0, 0
invoke-virtual {v6, v0}, Ljava/nio/ByteBuffer;->get(I)B
move-result v0
and-int/lit16 v0, v0, 0xff
if-ne v0, p3, :bad
const/4 v0, 1
invoke-virtual {v6, v0}, Ljava/nio/ByteBuffer;->get(I)B
move-result v0
if-nez v0, :bad
const/4 v0, 2
invoke-virtual {v6, v0}, Ljava/nio/ByteBuffer;->get(I)B
move-result v0
if-nez v0, :bad
const/4 v0, 3
invoke-virtual {v6, v0}, Ljava/nio/ByteBuffer;->get(I)B
move-result v0
const/4 v1, -1
if-ne v0, v1, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "ALPHA_8 shader texel alpha readback"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0')
}
