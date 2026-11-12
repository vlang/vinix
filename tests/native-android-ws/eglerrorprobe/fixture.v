// SPDX-License-Identifier: GPL-2.0-or-later
module eglerrorprobe

import os

pub fn install(root string) ! {
 mut text := '.class public Lorg/vinix/bootstrap/EglErrorProbe;\n.super Ljava/lang/Object;\n.method public static check()V\n.locals 5\n'
 cases := {12288: 'EGL_SUCCESS', 12289: 'EGL_NOT_INITIALIZED', 12290: 'EGL_BAD_ACCESS',
  12291: 'EGL_BAD_ALLOC', 12292: 'EGL_BAD_ATTRIBUTE', 12293: 'EGL_BAD_CONFIG',
  12294: 'EGL_BAD_CONTEXT', 12295: 'EGL_BAD_CURRENT_SURFACE', 12296: 'EGL_BAD_DISPLAY',
  12297: 'EGL_BAD_MATCH', 12298: 'EGL_BAD_NATIVE_PIXMAP', 12299: 'EGL_BAD_NATIVE_WINDOW',
  12300: 'EGL_BAD_PARAMETER', 12301: 'EGL_BAD_SURFACE', 12302: 'EGL_CONTEXT_LOST',
  0: '0x0', 1: '0x1', 12303: '0x300f', 65535: '0xffff', -1: '0xffffffff',
  2147483647: '0x7fffffff', -2147483648: '0x80000000'}
 mut codes := cases.keys()
 codes.sort()
 for code in codes {
  text += 'const v0, ${code}\ninvoke-static {v0}, Landroid/opengl/GLUtils;->getEGLErrorString(I)Ljava/lang/String;\nmove-result-object v0\n' +
   'const-string v1, "${cases[code]}"\ninvoke-virtual {v0, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v0\nconst/4 v1, 1\ninvoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V\n'
 }
 // Set an actual EGL error, format another code, then verify the error queue
 // was neither consumed nor replaced. No new GL objects or surfaces are made.
 text += r'
invoke-static {}, Ljavax/microedition/khronos/egl/EGLContext;->getEGL()Ljavax/microedition/khronos/egl/EGL;
move-result-object v0
check-cast v0, Lcom/google/android/gles_jni/EGLImpl;
invoke-virtual {v0}, Lcom/google/android/gles_jni/EGLImpl;->eglGetError()I
sget-object v1, Ljavax/microedition/khronos/egl/EGL10;->EGL_NO_DISPLAY:Ljavax/microedition/khronos/egl/EGLDisplay;
sget-object v2, Ljavax/microedition/khronos/egl/EGL10;->EGL_NO_SURFACE:Ljavax/microedition/khronos/egl/EGLSurface;
invoke-virtual {v0, v1, v2}, Lcom/google/android/gles_jni/EGLImpl;->eglSwapBuffers(Ljavax/microedition/khronos/egl/EGLDisplay;Ljavax/microedition/khronos/egl/EGLSurface;)Z
move-result v3
const/4 v4, 0
invoke-static {v3, v4}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/16 v3, 0x3000
invoke-static {v3}, Landroid/opengl/GLUtils;->getEGLErrorString(I)Ljava/lang/String;
invoke-virtual {v0}, Lcom/google/android/gles_jni/EGLImpl;->eglGetError()I
move-result v3
const/16 v4, 0x3008
invoke-static {v3, v4}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0}, Lcom/google/android/gles_jni/EGLImpl;->eglGetError()I
move-result v3
const/16 v4, 0x3000
invoke-static {v3, v4}, Lorg/vinix/bootstrap/Main;->expect(II)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "EGL-ERROR-NAMES-PASS standard-codes hex-fallback signed-boundaries preserved-error-queue"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
.end method
'
 os.write_file(root + '/smali/EglErrorProbe.smali', text)!
}
