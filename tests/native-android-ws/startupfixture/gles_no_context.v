// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_gles_no_context_probe(dir string) ! {
	os.write_file(dir + '/GlesNoContextProbe.smali', r'
.class public Lorg/vinix/bootstrap/GlesNoContextProbe;
.super Ljava/lang/Object;
.implements Ljava/lang/Runnable;
.field public failure:Ljava/lang/Throwable;
.method public constructor <init>()V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
return-void
.end method
.method public static check()V
.locals 5
invoke-static {}, Ljavax/microedition/khronos/egl/EGLContext;->getEGL()Ljavax/microedition/khronos/egl/EGL;
move-result-object v0
check-cast v0, Lcom/google/android/gles_jni/EGLImpl;
invoke-virtual {v0}, Lcom/google/android/gles_jni/EGLImpl;->eglGetCurrentContext()Ljavax/microedition/khronos/egl/EGLContext;
move-result-object v0
iget-wide v1, v0, Ljavax/microedition/khronos/egl/EGLContext;->native_egl_context:J
const-wide/16 v3, 0
cmp-long v0, v1, v3
if-nez v0, :bad
const/16 v0, 0x1f03
invoke-static {v0}, Landroid/opengl/GLES20;->glGetString(I)Ljava/lang/String;
move-result-object v1
if-nez v1, :bad
# Also exercise the GL10/GLImpl JNI entrypoint on the unbound thread.
new-instance v1, Lcom/google/android/gles_jni/GLImpl;
invoke-direct {v1}, Lcom/google/android/gles_jni/GLImpl;-><init>()V
invoke-virtual {v1, v0}, Lcom/google/android/gles_jni/GLImpl;->glGetString(I)Ljava/lang/String;
move-result-object v1
if-nez v1, :bad
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "GL string on an unbound thread"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0
.end method
.method public run()V
.locals 1
:begin
invoke-static {}, Lorg/vinix/bootstrap/GlesNoContextProbe;->check()V
:end
.catch Ljava/lang/Throwable; {:begin .. :end} :failed
return-void
:failed
move-exception v0
iput-object v0, p0, Lorg/vinix/bootstrap/GlesNoContextProbe;->failure:Ljava/lang/Throwable;
return-void
.end method
.method public static worker()V
.locals 3
new-instance v0, Lorg/vinix/bootstrap/GlesNoContextProbe;
invoke-direct {v0}, Lorg/vinix/bootstrap/GlesNoContextProbe;-><init>()V
new-instance v1, Ljava/lang/Thread;
invoke-direct {v1, v0}, Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;)V
invoke-virtual {v1}, Ljava/lang/Thread;->start()V
invoke-virtual {v1}, Ljava/lang/Thread;->join()V
iget-object v2, v0, Lorg/vinix/bootstrap/GlesNoContextProbe;->failure:Ljava/lang/Throwable;
if-eqz v2, :done
throw v2
:done
return-void
.end method
')!
}
