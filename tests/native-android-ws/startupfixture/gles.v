// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_gles_probe(dir string) ! {
	mut check := '
const/4 v0, 2
const/4 v1, 3
const/4 v2, 5
const/4 v3, 7
invoke-static {v0, v1, v2, v3}, Landroid/opengl/GLES20;->glViewport(IIII)V
const/4 v0, 6
new-array v1, v0, [I
fill-array-data v1, :sentinels
const/16 v0, 0xba2
const/4 v2, 1
invoke-static {v0, v1, v2}, Landroid/opengl/GLES20;->glGetIntegerv(I[II)V
'
	for i, value in [91, 2, 3, 5, 7, 96] {
		check += 'const/4 v2, ${i}\naget v3, v1, v2\nconst/16 v4, ${value}\ninvoke-static {v3, v4}, Lorg/vinix/bootstrap/GlesProbe;->equal(II)V\n'
	}
	// Both heap-backed and direct buffers use their current position and
	// limit, without changing either or overwriting the surrounding values.
	for kind in ['heap', 'direct'] {
		check += if kind == 'heap' {
			'const/4 v1, 6\ninvoke-static {v1}, Ljava/nio/IntBuffer;->allocate(I)Ljava/nio/IntBuffer;\nmove-result-object v1\n'
		} else {
			'const/16 v1, 24\ninvoke-static {v1}, Ljava/nio/ByteBuffer;->allocateDirect(I)Ljava/nio/ByteBuffer;\nmove-result-object v1\ninvoke-virtual {v1}, Ljava/nio/ByteBuffer;->asIntBuffer()Ljava/nio/IntBuffer;\nmove-result-object v1\n'
		}
		for i in [0, 5] {
			check += 'const/4 v2, ${i}\nconst/16 v3, 99\ninvoke-virtual {v1, v2, v3}, Ljava/nio/IntBuffer;->put(II)Ljava/nio/IntBuffer;\n'
		}
		check += '
const/4 v2, 1
invoke-virtual {v1, v2}, Ljava/nio/Buffer;->position(I)Ljava/nio/Buffer;
const/4 v2, 5
invoke-virtual {v1, v2}, Ljava/nio/Buffer;->limit(I)Ljava/nio/Buffer;
invoke-static {v0, v1}, Landroid/opengl/GLES20;->glGetIntegerv(ILjava/nio/IntBuffer;)V
invoke-virtual {v1}, Ljava/nio/Buffer;->position()I
move-result v2
const/4 v3, 1
if-ne v2, v3, :bad
const/4 v2, 6
invoke-virtual {v1, v2}, Ljava/nio/Buffer;->limit(I)Ljava/nio/Buffer;
'
		for i, value in [99, 2, 3, 5, 7, 99] {
			check += 'const/4 v2, ${i}\ninvoke-virtual {v1, v2}, Ljava/nio/IntBuffer;->get(I)I\nmove-result v3\nconst/16 v4, ${value}\ninvoke-static {v3, v4}, Lorg/vinix/bootstrap/GlesProbe;->equal(II)V\n'
		}
	}
	check += '
invoke-virtual {v1}, Ljava/nio/IntBuffer;->asReadOnlyBuffer()Ljava/nio/IntBuffer;
move-result-object v1
:readonly_begin
invoke-static {v0, v1}, Landroid/opengl/GLES20;->glGetIntegerv(ILjava/nio/IntBuffer;)V
:readonly_end
.catch Ljava/nio/ReadOnlyBufferException; {:readonly_begin .. :readonly_end} :readonly_ok
goto :bad
:readonly_ok
move-exception v2
const/4 v1, 3
invoke-static {v1}, Ljava/nio/IntBuffer;->allocate(I)Ljava/nio/IntBuffer;
move-result-object v1
:short_buffer_begin
invoke-static {v0, v1}, Landroid/opengl/GLES20;->glGetIntegerv(ILjava/nio/IntBuffer;)V
:short_buffer_end
.catch Ljava/lang/IllegalArgumentException; {:short_buffer_begin .. :short_buffer_end} :short_buffer_ok
goto :bad
:short_buffer_ok
move-exception v2
'
	for i, input in ['const/4 v1, 0\nconst/4 v2, 0', 'const/4 v1, 4\nnew-array v1, v1, [I\nconst/4 v2, -1', 'const/4 v1, 4\nnew-array v1, v1, [I\nconst/4 v2, 1'] {
		check += '${input}\n:invalid_${i}_begin\ninvoke-static {v0, v1, v2}, Landroid/opengl/GLES20;->glGetIntegerv(I[II)V\n:invalid_${i}_end\n.catch Ljava/lang/IllegalArgumentException; {:invalid_${i}_begin .. :invalid_${i}_end} :invalid_${i}_ok\ngoto :bad\n:invalid_${i}_ok\nmove-exception v3\n'
	}
	check += '
const/4 v1, 2
new-array v1, v1, [I
const/4 v2, 0
const/16 v0, 0xd3a
invoke-static {v0, v1, v2}, Landroid/opengl/GLES20;->glGetIntegerv(I[II)V
aget v3, v1, v2
if-lez v3, :bad
const/4 v2, 1
aget v3, v1, v2
if-lez v3, :bad
const/4 v2, 0
const v0, 0x86a2
invoke-static {v0, v1, v2}, Landroid/opengl/GLES20;->glGetIntegerv(I[II)V
aget v3, v1, v2
if-ltz v3, :bad
new-array v3, v3, [I
const v0, 0x86a3
invoke-static {v0, v3, v2}, Landroid/opengl/GLES20;->glGetIntegerv(I[II)V
invoke-static {}, Landroid/opengl/GLES20;->glGetError()I
move-result v0
if-nez v0, :bad
const/16 v3, 99
aput v3, v1, v2
const/4 v0, 0
invoke-static {v0, v1, v2}, Landroid/opengl/GLES20;->glGetIntegerv(I[II)V
aget v4, v1, v2
if-ne v3, v4, :bad
invoke-static {}, Landroid/opengl/GLES20;->glGetError()I
move-result v0
const/16 v1, 0x500
if-ne v0, v1, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-JAVA-GLES-PASS viewport offsets heap direct position limit bounds read-only format-count GL-errors"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Java GLES integer state"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:sentinels
.array-data 4
91
92
93
94
95
96
.end array-data
'
	os.write_file(dir + '/GlesProbe.smali', '.class public Lorg/vinix/bootstrap/GlesProbe;\n.super Ljava/lang/Object;\n' + method('public static check()V', check) + method('private static equal(II)V', '
if-eq p0, p1, :ok
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "GLES value mismatch: actual, expected"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-virtual {v0, p0}, Ljava/io/PrintStream;->println(I)V
invoke-virtual {v0, p1}, Ljava/io/PrintStream;->println(I)V
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "GLES integer result"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:ok
return-void'))!
}
