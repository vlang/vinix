// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

// Opt-in until qualified against the repaired adapter. The main EGL probe
// already owns a current context/pbuffer when this balanced worker lease runs.
pub fn install_shared_display_regression(root string) ! {
	path := root + '/smali/EglProbe.smali'
	source := os.read_file(path)!
	needle := 'invoke-static {}, Lorg/vinix/bootstrap/GlesNoContextProbe;->worker()V\n'
	terminated := 'invoke-virtual {v0}, Lcom/google/android/gles_jni/EGLImpl;->eglGetError()I\nmove-result v8\nconst/16 v9, 0x3000\nif-ne v8, v9, :bad\n'
	if source.count(needle) != 1 || source.count(terminated) != 1 {
		return error('one current-context and final-termination probe insertion required')
	}
	os.write_file(path, source.replace(needle, needle +
		'invoke-static {v0, v1, v7}, Lorg/vinix/bootstrap/EglSharedDisplayProbe;->check(Lcom/google/android/gles_jni/EGLImpl;Ljavax/microedition/khronos/egl/EGLDisplay;Ljavax/microedition/khronos/egl/EGLSurface;)V\n')
		.replace(terminated, terminated + 'invoke-static {v0, v1}, Lorg/vinix/bootstrap/EglSharedDisplayProbe;->finished(Lcom/google/android/gles_jni/EGLImpl;Ljavax/microedition/khronos/egl/EGLDisplay;)V\n'))!
	os.write_file(root + '/smali/EglSharedDisplayProbe.smali', r'
.class public final Lorg/vinix/bootstrap/EglSharedDisplayProbe;
.super Ljava/lang/Object;
.implements Ljava/lang/Runnable;
.field private failure:Ljava/lang/Throwable;
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
return-void
.end method
.method public static finished(Lcom/google/android/gles_jni/EGLImpl;Ljavax/microedition/khronos/egl/EGLDisplay;)V
.locals 2
const/16 v0, 0x3053
invoke-virtual {p0, p1, v0}, Lcom/google/android/gles_jni/EGLImpl;->eglQueryString(Ljavax/microedition/khronos/egl/EGLDisplay;I)Ljava/lang/String;
move-result-object v0
if-nez v0, :bad
invoke-virtual {p0}, Lcom/google/android/gles_jni/EGLImpl;->eglGetError()I
move-result v0
const/16 v1, 0x3001
if-ne v0, v1, :bad
invoke-virtual {p0, p1}, Lcom/google/android/gles_jni/EGLImpl;->eglTerminate(Ljavax/microedition/khronos/egl/EGLDisplay;)Z
move-result v0
if-eqz v0, :bad
invoke-virtual {p0}, Lcom/google/android/gles_jni/EGLImpl;->eglGetError()I
move-result v0
const/16 v1, 0x3000
if-ne v0, v1, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "EGL-SHARED-TERMINATE-PASS final-release uninitialized repeat-terminate"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "shared EGL final display release"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.end method
.method public run()V
.locals 4
:begin
invoke-static {}, Ljavax/microedition/khronos/egl/EGLContext;->getEGL()Ljavax/microedition/khronos/egl/EGL;
move-result-object v0
check-cast v0, Lcom/google/android/gles_jni/EGLImpl;
sget-object v1, Ljavax/microedition/khronos/egl/EGL10;->EGL_DEFAULT_DISPLAY:Ljava/lang/Object;
invoke-virtual {v0, v1}, Lcom/google/android/gles_jni/EGLImpl;->eglGetDisplay(Ljava/lang/Object;)Ljavax/microedition/khronos/egl/EGLDisplay;
move-result-object v1
const/4 v2, 2
new-array v2, v2, [I
invoke-virtual {v0, v1, v2}, Lcom/google/android/gles_jni/EGLImpl;->eglInitialize(Ljavax/microedition/khronos/egl/EGLDisplay;[I)Z
move-result v3
if-eqz v3, :bad
invoke-virtual {v0, v1}, Lcom/google/android/gles_jni/EGLImpl;->eglTerminate(Ljavax/microedition/khronos/egl/EGLDisplay;)Z
move-result v3
if-eqz v3, :bad
:end
return-void
.catch Ljava/lang/Throwable; {:begin .. :end} :caught
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "shared EGL worker lease"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
iput-object v0, p0, Lorg/vinix/bootstrap/EglSharedDisplayProbe;->failure:Ljava/lang/Throwable;
return-void
:caught
move-exception v0
iput-object v0, p0, Lorg/vinix/bootstrap/EglSharedDisplayProbe;->failure:Ljava/lang/Throwable;
return-void
.end method
.method public static check(Lcom/google/android/gles_jni/EGLImpl;Ljavax/microedition/khronos/egl/EGLDisplay;Ljavax/microedition/khronos/egl/EGLSurface;)V
.locals 4
new-instance v0, Lorg/vinix/bootstrap/EglSharedDisplayProbe;
invoke-direct {v0}, Lorg/vinix/bootstrap/EglSharedDisplayProbe;-><init>()V
new-instance v1, Ljava/lang/Thread;
invoke-direct {v1, v0}, Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;)V
invoke-virtual {v1}, Ljava/lang/Thread;->start()V
const-wide/16 v2, 10000
invoke-virtual {v1, v2, v3}, Ljava/lang/Thread;->join(J)V
invoke-virtual {v1}, Ljava/lang/Thread;->isAlive()Z
move-result v2
if-nez v2, :bad
iget-object v2, v0, Lorg/vinix/bootstrap/EglSharedDisplayProbe;->failure:Ljava/lang/Throwable;
if-eqz v2, :worker_ok
throw v2
:worker_ok
const/4 v0, 1
new-array v0, v0, [I
const/16 v1, 0x3057
invoke-virtual {p0, p1, p2, v1, v0}, Lcom/google/android/gles_jni/EGLImpl;->eglQuerySurface(Ljavax/microedition/khronos/egl/EGLDisplay;Ljavax/microedition/khronos/egl/EGLSurface;I[I)Z
move-result v1
if-eqz v1, :bad
const/4 v2, 0
aget v1, v0, v2
if-lez v1, :bad
invoke-virtual {p0}, Lcom/google/android/gles_jni/EGLImpl;->eglGetCurrentContext()Ljavax/microedition/khronos/egl/EGLContext;
move-result-object v0
sget-object v1, Ljavax/microedition/khronos/egl/EGL10;->EGL_NO_CONTEXT:Ljavax/microedition/khronos/egl/EGLContext;
if-eq v0, v1, :bad
invoke-virtual {p0, p1, p2}, Lcom/google/android/gles_jni/EGLImpl;->eglSwapBuffers(Ljavax/microedition/khronos/egl/EGLDisplay;Ljavax/microedition/khronos/egl/EGLSurface;)Z
move-result v0
if-eqz v0, :bad
invoke-virtual {p0}, Lcom/google/android/gles_jni/EGLImpl;->eglGetError()I
move-result v0
const/16 v1, 0x3000
if-ne v0, v1, :bad
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "EGL-SHARED-DISPLAY-PASS balanced-worker-lease retained-current-context retained-surface swap"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "shared EGL display lost active surface"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.end method
')!
}
