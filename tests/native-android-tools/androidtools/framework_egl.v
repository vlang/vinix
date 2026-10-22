// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_egl(smali string) ! {
	mut text := '.class public Lcom/google/android/gles_jni/EGLImpl;\n.super Ljava/lang/Object;\n.implements Ljavax/microedition/khronos/egl/EGL10;\n' +
		'.method public constructor <init>()V\n.locals 0\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void\n.end method\n'
	for signature in [
		'eglChooseConfig(Ljavax/microedition/khronos/egl/EGLDisplay;[I[Ljavax/microedition/khronos/egl/EGLConfig;I[I)Z',
		'eglGetConfigs(Ljavax/microedition/khronos/egl/EGLDisplay;[Ljavax/microedition/khronos/egl/EGLConfig;I[I)Z',
		'eglGetDisplay(Ljava/lang/Object;)Ljavax/microedition/khronos/egl/EGLDisplay;',
		'eglInitialize(Ljavax/microedition/khronos/egl/EGLDisplay;[I)Z',
		'eglTerminate(Ljavax/microedition/khronos/egl/EGLDisplay;)Z',
		'eglGetConfigAttrib(Ljavax/microedition/khronos/egl/EGLDisplay;Ljavax/microedition/khronos/egl/EGLConfig;I[I)Z',
		'eglCreateContext(Ljavax/microedition/khronos/egl/EGLDisplay;Ljavax/microedition/khronos/egl/EGLConfig;Ljavax/microedition/khronos/egl/EGLContext;[I)Ljavax/microedition/khronos/egl/EGLContext;',
		'eglCreatePbufferSurface(Ljavax/microedition/khronos/egl/EGLDisplay;Ljavax/microedition/khronos/egl/EGLConfig;[I)Ljavax/microedition/khronos/egl/EGLSurface;',
		'eglCreateWindowSurface(Ljavax/microedition/khronos/egl/EGLDisplay;Ljavax/microedition/khronos/egl/EGLConfig;Ljava/lang/Object;[I)Ljavax/microedition/khronos/egl/EGLSurface;',
		'eglCreatePixmapSurface(Ljavax/microedition/khronos/egl/EGLDisplay;Ljavax/microedition/khronos/egl/EGLConfig;Ljava/lang/Object;[I)Ljavax/microedition/khronos/egl/EGLSurface;',
		'eglCopyBuffers(Ljavax/microedition/khronos/egl/EGLDisplay;Ljavax/microedition/khronos/egl/EGLSurface;Ljava/lang/Object;)Z',
		'eglDestroyContext(Ljavax/microedition/khronos/egl/EGLDisplay;Ljavax/microedition/khronos/egl/EGLContext;)Z',
		'eglDestroySurface(Ljavax/microedition/khronos/egl/EGLDisplay;Ljavax/microedition/khronos/egl/EGLSurface;)Z',
		'eglMakeCurrent(Ljavax/microedition/khronos/egl/EGLDisplay;Ljavax/microedition/khronos/egl/EGLSurface;Ljavax/microedition/khronos/egl/EGLSurface;Ljavax/microedition/khronos/egl/EGLContext;)Z',
		'eglSwapBuffers(Ljavax/microedition/khronos/egl/EGLDisplay;Ljavax/microedition/khronos/egl/EGLSurface;)Z',
		'eglQueryContext(Ljavax/microedition/khronos/egl/EGLDisplay;Ljavax/microedition/khronos/egl/EGLContext;I[I)Z',
		'eglQuerySurface(Ljavax/microedition/khronos/egl/EGLDisplay;Ljavax/microedition/khronos/egl/EGLSurface;I[I)Z',
		'eglQueryString(Ljavax/microedition/khronos/egl/EGLDisplay;I)Ljava/lang/String;',
		'eglGetCurrentDisplay()Ljavax/microedition/khronos/egl/EGLDisplay;',
		'eglGetCurrentContext()Ljavax/microedition/khronos/egl/EGLContext;',
		'eglGetCurrentSurface(I)Ljavax/microedition/khronos/egl/EGLSurface;',
		'eglGetError()I', 'eglReleaseThread()Z', 'eglWaitGL()Z', 'eglWaitNative(ILjava/lang/Object;)Z',
	] { text += '.method public native ' + signature + '\n.end method\n' }
	os.write_file(smali + '/com/google/android/gles_jni/EGLImpl.smali', text)!
}
