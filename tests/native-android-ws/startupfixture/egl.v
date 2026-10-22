// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_egl_probe(dir string) ! {
	mut check := '
invoke-static {}, Ljavax/microedition/khronos/egl/EGLContext;->getEGL()Ljavax/microedition/khronos/egl/EGL;
move-result-object v0
check-cast v0, Lcom/google/android/gles_jni/EGLImpl;
sget-object v1, Ljavax/microedition/khronos/egl/EGL10;->EGL_DEFAULT_DISPLAY:Ljava/lang/Object;
invoke-virtual {v0, v1}, Lcom/google/android/gles_jni/EGLImpl;->eglGetDisplay(Ljava/lang/Object;)Ljavax/microedition/khronos/egl/EGLDisplay;
move-result-object v1
sget-object v8, Ljavax/microedition/khronos/egl/EGL10;->EGL_NO_DISPLAY:Ljavax/microedition/khronos/egl/EGLDisplay;
if-eq v1, v8, :bad
const/4 v8, 2
new-array v2, v8, [I
invoke-virtual {v0, v1, v2}, Lcom/google/android/gles_jni/EGLImpl;->eglInitialize(Ljavax/microedition/khronos/egl/EGLDisplay;[I)Z
move-result v8
if-eqz v8, :bad
const/4 v8, 0
aget v8, v2, v8
const/4 v9, 1
if-ne v8, v9, :bad
const/4 v2, 0
const/4 v8, 3
new-array v3, v8, [Ljavax/microedition/khronos/egl/EGLConfig;
const/4 v4, 1
new-array v5, v4, [I
invoke-virtual/range {v0 .. v5}, Lcom/google/android/gles_jni/EGLImpl;->eglChooseConfig(Ljavax/microedition/khronos/egl/EGLDisplay;[I[Ljavax/microedition/khronos/egl/EGLConfig;I[I)Z
move-result v8
if-eqz v8, :bad
const/4 v8, 0
aget v9, v5, v8
if-ne v9, v4, :bad
aget-object v2, v3, v8
if-eqz v2, :bad
const/4 v8, 1
aget-object v9, v3, v8
if-nez v9, :bad
const/4 v8, 3
new-array v4, v8, [I
fill-array-data v4, :context_attrs
sget-object v3, Ljavax/microedition/khronos/egl/EGL10;->EGL_NO_CONTEXT:Ljavax/microedition/khronos/egl/EGLContext;
invoke-virtual {v0, v1, v2, v3, v4}, Lcom/google/android/gles_jni/EGLImpl;->eglCreateContext(Ljavax/microedition/khronos/egl/EGLDisplay;Ljavax/microedition/khronos/egl/EGLConfig;Ljavax/microedition/khronos/egl/EGLContext;[I)Ljavax/microedition/khronos/egl/EGLContext;
move-result-object v6
if-eq v6, v3, :bad
const/4 v8, 5
new-array v3, v8, [I
fill-array-data v3, :surface_attrs
invoke-virtual {v0, v1, v2, v3}, Lcom/google/android/gles_jni/EGLImpl;->eglCreatePbufferSurface(Ljavax/microedition/khronos/egl/EGLDisplay;Ljavax/microedition/khronos/egl/EGLConfig;[I)Ljavax/microedition/khronos/egl/EGLSurface;
move-result-object v7
sget-object v8, Ljavax/microedition/khronos/egl/EGL10;->EGL_NO_SURFACE:Ljavax/microedition/khronos/egl/EGLSurface;
if-eq v7, v8, :bad
invoke-virtual {v0, v1, v7, v7, v6}, Lcom/google/android/gles_jni/EGLImpl;->eglMakeCurrent(Ljavax/microedition/khronos/egl/EGLDisplay;Ljavax/microedition/khronos/egl/EGLSurface;Ljavax/microedition/khronos/egl/EGLSurface;Ljavax/microedition/khronos/egl/EGLContext;)Z
move-result v8
if-eqz v8, :bad
invoke-virtual {v0}, Lcom/google/android/gles_jni/EGLImpl;->eglGetCurrentContext()Ljavax/microedition/khronos/egl/EGLContext;
move-result-object v3
iget-wide v8, v3, Ljavax/microedition/khronos/egl/EGLContext;->native_egl_context:J
iget-wide v3, v6, Ljavax/microedition/khronos/egl/EGLContext;->native_egl_context:J
cmp-long v8, v8, v3
if-nez v8, :bad
invoke-virtual {v6}, Ljavax/microedition/khronos/egl/EGLContext;->getGL()Ljavax/microedition/khronos/opengles/GL;
move-result-object v3
check-cast v3, Ljavax/microedition/khronos/opengles/GL10;
const/16 v8, 0x1f02
invoke-interface {v3, v8}, Ljavax/microedition/khronos/opengles/GL10;->glGetString(I)Ljava/lang/String;
move-result-object v3
if-eqz v3, :bad
invoke-static {v8}, Landroid/opengl/GLES20;->glGetString(I)Ljava/lang/String;
move-result-object v8
invoke-virtual {v3, v8}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v8
if-eqz v8, :bad
const/4 v8, 0
invoke-static {v8}, Landroid/opengl/GLES20;->glGetString(I)Ljava/lang/String;
move-result-object v8
if-nez v8, :bad
invoke-static {}, Landroid/opengl/GLES20;->glGetError()I
move-result v8
const/16 v9, 0x500
if-ne v8, v9, :bad
invoke-static {}, Landroid/opengl/GLES20;->glGetError()I
move-result v8
if-nez v8, :bad
'
	for method_name, kind in {'eglQuerySurface': 'EGLSurface', 'eglQueryContext': 'EGLContext', 'eglGetConfigAttrib': 'EGLConfig'} {
		target := if kind == 'EGLSurface' { 'v7' } else if kind == 'EGLContext' { 'v6' } else { 'v2' }
		attribute := if kind == 'EGLSurface' { '0x3057' } else if kind == 'EGLContext' { '0x3098' } else { '0x3033' }
		check += 'const/16 v3, ${attribute}\ninvoke-virtual {v0, v1, ${target}, v3, v5}, Lcom/google/android/gles_jni/EGLImpl;->${method_name}(Ljavax/microedition/khronos/egl/EGLDisplay;Ljavax/microedition/khronos/egl/${kind};I[I)Z\nmove-result v8\nif-eqz v8, :bad\n'
	}
	check += '
invoke-virtual {v0, v1, v7}, Lcom/google/android/gles_jni/EGLImpl;->eglSwapBuffers(Ljavax/microedition/khronos/egl/EGLDisplay;Ljavax/microedition/khronos/egl/EGLSurface;)Z
move-result v8
if-eqz v8, :bad
invoke-virtual {v0, v1, v7}, Lcom/google/android/gles_jni/EGLImpl;->eglDestroySurface(Ljavax/microedition/khronos/egl/EGLDisplay;Ljavax/microedition/khronos/egl/EGLSurface;)Z
move-result v8
if-eqz v8, :bad
invoke-virtual {v0, v1, v6}, Lcom/google/android/gles_jni/EGLImpl;->eglDestroyContext(Ljavax/microedition/khronos/egl/EGLDisplay;Ljavax/microedition/khronos/egl/EGLContext;)Z
move-result v8
if-eqz v8, :bad
invoke-virtual {v0}, Lcom/google/android/gles_jni/EGLImpl;->eglReleaseThread()Z
move-result v8
if-eqz v8, :bad
invoke-virtual {v0}, Lcom/google/android/gles_jni/EGLImpl;->eglGetCurrentContext()Ljavax/microedition/khronos/egl/EGLContext;
move-result-object v8
sget-object v9, Ljavax/microedition/khronos/egl/EGL10;->EGL_NO_CONTEXT:Ljavax/microedition/khronos/egl/EGLContext;
if-ne v8, v9, :bad
const/16 v8, 0x1f02
invoke-static {v8}, Landroid/opengl/GLES20;->glGetString(I)Ljava/lang/String;
move-result-object v8
if-nez v8, :bad
invoke-virtual {v0, v1}, Lcom/google/android/gles_jni/EGLImpl;->eglTerminate(Ljavax/microedition/khronos/egl/EGLDisplay;)Z
move-result v8
if-eqz v8, :bad
invoke-virtual {v0}, Lcom/google/android/gles_jni/EGLImpl;->eglGetError()I
move-result v8
const/16 v9, 0x3000
if-ne v8, v9, :bad
const/4 v2, 0
new-array v2, v2, [I
:short_begin
invoke-virtual {v0, v1, v2}, Lcom/google/android/gles_jni/EGLImpl;->eglInitialize(Ljavax/microedition/khronos/egl/EGLDisplay;[I)Z
:short_end
.catch Ljava/lang/IllegalArgumentException; {:short_begin .. :short_end} :short_ok
goto :bad
:short_ok
move-exception v8
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-JAVA-EGL-PASS config-capacity context surface current GL-string GLES20-errors no-current-context deferred-destroy array-validation"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "Java EGL10"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
:context_attrs
.array-data 4
0x3098
2
0x3038
.end array-data
:surface_attrs
.array-data 4
0x3057
8
0x3056
8
0x3038
.end array-data
'
	mut composition := '
const/16 v0, 32
const/16 v1, 24
sget-object v2, Landroid/graphics/Bitmap$Config;->ARGB_8888:Landroid/graphics/Bitmap$Config;
invoke-static {v0, v1, v2}, Landroid/graphics/Bitmap;->createBitmap(IILandroid/graphics/Bitmap$Config;)Landroid/graphics/Bitmap;
move-result-object v8
new-instance v9, Landroid/graphics/Canvas;
invoke-direct {v9, v8}, Landroid/graphics/Canvas;-><init>(Landroid/graphics/Bitmap;)V
invoke-virtual {p0, v9}, Landroid/view/View;->draw(Landroid/graphics/Canvas;)V
const/4 v0, 1
new-array v1, v0, [I
move-object v0, v8
const/4 v2, 0
const/4 v3, 1
const/4 v6, 1
const/4 v7, 1
'
	for sample in [[30, 1, int(0xff0000ff)], [30, 22, int(0xffff0000)], [1, 22, int(0xff00ff00)]] {
		composition += 'const/16 v4, ${sample[0]}\nconst/16 v5, ${sample[1]}\n' +
			'invoke-virtual/range {v0 .. v7}, Landroid/graphics/Bitmap;->getPixels([IIIIIII)V\n' +
			'const/4 v4, 0\naget v4, v1, v4\nconst v5, ${sample[2]}\nif-ne v4, v5, :bad\n'
	}
	composition += '
invoke-virtual {v8}, Landroid/graphics/Bitmap;->recycle()V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-EGL-COMPOSITION-PASS native-WS pixels flipped-RGBA"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "EGL window composition pixels"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
'
	os.write_file(dir + '/EglProbe.smali', '.class public Lorg/vinix/bootstrap/EglProbe;\n.super Ljava/lang/Object;\n' +
		method('public static check()V', check) + method('public static composition(Landroid/view/SurfaceView;)V', composition))!
}
