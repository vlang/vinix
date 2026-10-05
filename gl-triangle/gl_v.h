/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_GL_TRIANGLE_V_H
#define VINIX_GL_TRIANGLE_V_H
#if defined(VINIX_TRIANGLE_HOST_TEST) && defined(VINIX_GLUT_TRIANGLE)
#include <GLES2/gl2.h>
#define GLUT_DOUBLE 2
#define GLUT_RGB 0
void glBegin(GLenum); void glEnd(void); void glColor3f(GLfloat,GLfloat,GLfloat); void glVertex2f(GLfloat,GLfloat);
void glutSwapBuffers(void); void glutInit(int *, char **); void glutInitDisplayMode(unsigned int); void glutInitWindowSize(int,int); int glutCreateWindow(const char *); void glutDisplayFunc(void (*)(void)); void glutReshapeFunc(void (*)(int,int)); void glutMainLoop(void);
#elif defined(VINIX_GLUT_TRIANGLE)
#if defined(__has_include)
#if __has_include(<GL/freeglut.h>)
#include <GL/freeglut.h>
#else
#include <GL/glut.h>
#endif
#else
#include <GL/glut.h>
#endif
#else
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#endif
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#ifdef VINIX_TRIANGLE_HOST_TEST
#include "native_fb.h"
#ifndef O_CLOEXEC
#define O_CLOEXEC 0x80000
#endif
#else
#include <linux/fb.h>
#endif
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>
#ifndef VINIX_GLUT_TRIANGLE
static inline void vkg_shader_source(unsigned int shader, int count, void *strings, void *length) { glShaderSource(shader,count,(const GLchar *const *)strings,(const GLint *)length); }
static inline EGLDisplay vkg_default_display(void) { return eglGetDisplay(EGL_DEFAULT_DISPLAY); }
static inline void *vkg_get_platform_display(void) { return (void *)eglGetProcAddress("eglGetPlatformDisplayEXT"); }
#endif
static inline int *vkg_errno_pointer(void) { return &errno; }
static inline FILE *vkg_stderr(void) { return stderr; }
static inline FILE *vkg_stdout(void) { return stdout; }
#endif
