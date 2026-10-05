/* SPDX-License-Identifier: GPL-2.0-or-later */
/* Independent GL/EGL and framebuffer ABI fixture; no GPU is required. */
#include "gl_v.h"
#include <assert.h>
#include <stdarg.h>
static unsigned depth,stencil,draws,allocs,frees,finished;
static unsigned char pixels[800*600*4];
#ifdef VINIX_GLUT_TRIANGLE
static void (*display_callback)(void);
static void (*reshape_callback)(int,int);
#endif
static unsigned mode;
static unsigned bpp=32;
static unsigned char framebuffer[800*600*4];
extern int test_program_main(int,char **);
void *test_malloc(size_t size) { assert(size==sizeof(pixels));allocs++;return pixels; }
void test_free(void *p) { assert(p==pixels);frees++; }
int test_open(const char *path,int flags,...) { (void)flags;assert(!strcmp(path,"/dev/fb0"));return 100; }
int test_close(int fd) { assert(fd==100);return 0; }
int test_ioctl(int fd,unsigned long request,...) {
    va_list args;va_start(args,request);void *out=va_arg(args,void *);va_end(args);assert(fd==100);
    if(request==FBIOGET_FSCREENINFO) { struct fb_fix_screeninfo *p=out;memset(p,0,sizeof(*p));p->line_length=800*(bpp/8);p->smem_len=800*600*(bpp/8); }
    else { assert(request==FBIOGET_VSCREENINFO);struct fb_var_screeninfo *p=out;memset(p,0,sizeof(*p));p->xres=800;p->yres=600;p->bits_per_pixel=bpp; if(bpp==16) { p->red=(struct fb_bitfield){11,5,0};p->green=(struct fb_bitfield){5,6,0};p->blue=(struct fb_bitfield){0,5,0}; } else if(bpp==24) { p->red=(struct fb_bitfield){16,8,0};p->green=(struct fb_bitfield){8,8,0};p->blue=(struct fb_bitfield){0,8,0}; } else { p->red=(struct fb_bitfield){0,8,0};p->green=(struct fb_bitfield){8,8,0};p->blue=(struct fb_bitfield){16,8,0};p->transp=(struct fb_bitfield){24,8,0}; } }
    return 0;
}
void *test_mmap(void *p,size_t size,int protection,int flags,int fd,off_t offset) { (void)p;(void)protection;(void)flags;assert(fd==100&&offset==0&&size<=sizeof(framebuffer));return framebuffer; }
int test_munmap(void *p,size_t size) { assert(p==framebuffer&&size<=sizeof(framebuffer));uint32_t packed=0;for(unsigned i=0;i<bpp/8;i++)packed|=(uint32_t)framebuffer[i]<<(8*i);assert(packed==(bpp==16?0x52ccu:bpp==24?0x505a64u:0xff645a50u));return 0; }
#ifndef VINIX_GLUT_TRIANGLE
static EGLDisplay platform_display(EGLenum platform,void *native,const EGLint *attributes) { assert(platform==0x31dd&&!native&&!attributes);return (void *)1; }
__eglMustCastToProperFunctionPointerType eglGetProcAddress(const char *name) { assert(!strcmp(name,"eglGetPlatformDisplayEXT"));return (__eglMustCastToProperFunctionPointerType)platform_display; }
EGLDisplay eglGetDisplay(EGLNativeDisplayType p) { (void)p;return (void *)1; }
EGLBoolean eglInitialize(EGLDisplay p,EGLint *major,EGLint *minor) { assert(p==(void *)1);*major=1;*minor=5;return 1; }
EGLBoolean eglBindAPI(EGLenum api) { assert(api==EGL_OPENGL_ES_API);return 1; }
EGLBoolean eglChooseConfig(EGLDisplay d,const EGLint *attrs,EGLConfig *c,EGLint n,EGLint *count) { assert(d==(void *)1&&n==1&&attrs[0]==EGL_SURFACE_TYPE&&attrs[12]==EGL_NONE);*c=(void *)2;*count=1;return 1; }
EGLSurface eglCreatePbufferSurface(EGLDisplay d,EGLConfig c,const EGLint *attrs) { assert(d==(void *)1&&c==(void *)2&&attrs[0]==EGL_WIDTH&&attrs[1]==800&&attrs[3]==600&&attrs[4]==EGL_NONE);return (void *)3; }
EGLContext eglCreateContext(EGLDisplay d,EGLConfig c,EGLContext share,const EGLint *attrs) { assert(d==(void *)1&&c==(void *)2&&!share&&attrs[0]==EGL_CONTEXT_CLIENT_VERSION&&attrs[1]==2&&attrs[2]==EGL_NONE);return (void *)4; }
EGLBoolean eglMakeCurrent(EGLDisplay d,EGLSurface draw,EGLSurface read,EGLContext c) { assert(d==(void *)1&&draw==read);assert((draw==(void *)3&&c==(void *)4)||(!draw&&!c));return 1; }
EGLBoolean eglDestroyContext(EGLDisplay d,EGLContext c) { assert(d==(void *)1&&c==(void *)4);return 1; }
EGLBoolean eglDestroySurface(EGLDisplay d,EGLSurface s) { assert(d==(void *)1&&s==(void *)3);return 1; }
EGLBoolean eglTerminate(EGLDisplay d) { assert(d==(void *)1);return 1; }
EGLint eglGetError(void) { return EGL_SUCCESS; }
GLuint glCreateShader(GLenum type) { assert(type==GL_VERTEX_SHADER||type==GL_FRAGMENT_SHADER);return type; }
void glShaderSource(GLuint shader,GLsizei count,const GLchar *const *source,const GLint *length) { (void)shader;assert(count==1&&!length&&strstr(*source,"void main(void)")); }
void glCompileShader(GLuint p) { (void)p; }
void glGetShaderiv(GLuint p,GLenum key,GLint *value) { (void)p;assert(key==GL_COMPILE_STATUS);*value=1; }
void glGetShaderInfoLog(GLuint p,GLsizei n,GLsizei *length,GLchar *text) { (void)p;(void)n;(void)length;(void)text;assert(!"unexpected shader failure"); }
GLuint glCreateProgram(void) { return 5; }
void glAttachShader(GLuint program,GLuint shader) { assert(program==5&&shader); }
void glBindAttribLocation(GLuint p,GLuint at,const GLchar *name) { assert(p==5&&at<=1&&(!strcmp(name,"position")||!strcmp(name,"color"))); }
void glLinkProgram(GLuint p) { assert(p==5); }
void glGetProgramiv(GLuint p,GLenum key,GLint *value) { assert(p==5&&key==GL_LINK_STATUS);*value=1; }
void glGetProgramInfoLog(GLuint p,GLsizei n,GLsizei *length,GLchar *text) { (void)p;(void)n;(void)length;(void)text;assert(!"unexpected link failure"); }
void glDeleteShader(GLuint p) { assert(p); }
void glDeleteProgram(GLuint p) { assert(p==5); }
void glUseProgram(GLuint p) { assert(p==5); }
void glGenBuffers(GLsizei n,GLuint *out) { assert(n==1);*out=6; }
void glBindBuffer(GLenum target,GLuint p) { assert(target==GL_ARRAY_BUFFER&&p==6); }
void glBufferData(GLenum target,GLsizeiptr size,const void *data,GLenum usage) { const float *v=data;assert(target==GL_ARRAY_BUFFER&&size==60&&usage==GL_STATIC_DRAW&&v[0]==-0.72f&&v[14]==1.0f); }
void glDeleteBuffers(GLsizei n,const GLuint *p) { assert(n==1&&*p==6); }
void glGenFramebuffers(GLsizei n,GLuint *p) { assert(n==1);*p=7; }
void glBindFramebuffer(GLenum target,GLuint p) { assert(target==GL_FRAMEBUFFER&&p==7); }
void glGenRenderbuffers(GLsizei n,GLuint *p) { assert(n==1);static unsigned next=8;*p=next++; }
void glBindRenderbuffer(GLenum target,GLuint p) { assert(target==GL_RENDERBUFFER&&p>=8); }
void glRenderbufferStorage(GLenum target,GLenum internal,GLsizei width,GLsizei height) { assert(target==GL_RENDERBUFFER&&width==800&&height==600);if(internal==GL_DEPTH_COMPONENT16)depth=16;else if(internal==GL_STENCIL_INDEX8)stencil=8;else if(internal==GL_DEPTH24_STENCIL8_OES){depth=24;stencil=8;}else assert(internal==GL_RGBA4); }
void glFramebufferRenderbuffer(GLenum target,GLenum attachment,GLenum rt,GLuint p) { (void)attachment;assert(target==GL_FRAMEBUFFER&&rt==GL_RENDERBUFFER&&p>=8); }
GLenum glCheckFramebufferStatus(GLenum target) { assert(target==GL_FRAMEBUFFER);return GL_FRAMEBUFFER_COMPLETE; }
void glDeleteRenderbuffers(GLsizei n,const GLuint *p) { assert(n==1&&(*p==0||*p>=8)); }
void glDeleteFramebuffers(GLsizei n,const GLuint *p) { assert(n==1&&(*p==0||*p==7)); }
void glGetIntegerv(GLenum key,GLint *value) { if(key==GL_DEPTH_BITS)*value=depth;else{assert(key==GL_STENCIL_BITS);*value=stencil;} }
GLenum glGetError(void) { return GL_NO_ERROR; }
void glClearDepthf(GLfloat d) { assert(d==1.0f); }
void glEnable(GLenum p) { assert(p==GL_DEPTH_TEST||p==GL_STENCIL_TEST); }
void glDepthFunc(GLenum p) { assert(p==GL_LESS); }
void glDepthMask(GLboolean p) { assert(p==GL_TRUE); }
void glClearStencil(GLint p) { assert(!p); }
void glStencilMask(GLuint p) { assert(p==255); }
void glStencilFunc(GLenum f,GLint ref,GLuint mask) { assert(f==GL_ALWAYS&&ref==1&&mask==255); }
void glStencilOp(GLenum a,GLenum b,GLenum c) { assert(a==GL_KEEP&&b==GL_KEEP&&c==GL_REPLACE); }
void glVertexAttribPointer(GLuint at,GLint n,GLenum type,GLboolean norm,GLsizei stride,const void *pointer) { assert(at<=1&&n==(at?3:2)&&type==GL_FLOAT&&!norm&&stride==20&&(uintptr_t)pointer==(at?8u:0u)); }
void glEnableVertexAttribArray(GLuint at) { assert(at<=1); }
void glDrawArrays(GLenum m,GLint first,GLsizei n) { assert(m==GL_TRIANGLES&&!first&&n==3);draws++; }
void glReadPixels(GLint x,GLint y,GLsizei width,GLsizei height,GLenum format,GLenum type,void *out) { (void)x;(void)y;assert(format==GL_RGBA&&type==GL_UNSIGNED_BYTE);unsigned char *p=out;for(int i=0;i<width*height;i++){p[i*4]=80;p[i*4+1]=90;p[i*4+2]=100;p[i*4+3]=255;} }
void glPixelStorei(GLenum key,GLint v) { assert(key==GL_PACK_ALIGNMENT&&v==1); }
#else
void glBegin(GLenum m) { assert(m==GL_TRIANGLES);draws++; }
void glEnd(void) {}
void glColor3f(GLfloat a,GLfloat b,GLfloat c) {
    assert(a>=0&&b>=0&&c>=0);
#ifdef VINIX_LEGACY_TRIANGLE
    static unsigned at;static const float colors[3][3]={{1.0f,0.2f,0.2f},{0.2f,1.0f,0.2f},{0.2f,0.4f,1.0f}};
    assert(a==colors[at%3][0]&&b==colors[at%3][1]&&c==colors[at%3][2]);at++;
#endif
}
void glVertex2f(GLfloat a,GLfloat b) {
    assert(a>=-1&&a<=1&&b>=-1&&b<=1);
#ifdef VINIX_LEGACY_TRIANGLE
    static unsigned at;static const float vertices[3][2]={{-0.65f,-0.45f},{0.65f,-0.45f},{0.0f,0.65f}};
    assert(a==vertices[at%3][0]&&b==vertices[at%3][1]);at++;
#endif
}
void glutSwapBuffers(void) {}
void glutInit(int *argc,char **argv) { assert(*argc==1&&argv[0]); }
void glutInitDisplayMode(unsigned int flags) { assert(flags==2); }
void glutInitWindowSize(int w,int h) { assert(w==800&&h==600); }
int glutCreateWindow(const char *name) { assert(!strcmp(name,"Vinix OpenGL Triangle"));return 1; }
void glutDisplayFunc(void (*f)(void)) { display_callback=f; }
void glutReshapeFunc(void (*f)(int,int)) { reshape_callback=f; }
void glutMainLoop(void) {
#ifdef VINIX_LEGACY_TRIANGLE
    assert(display_callback&&!reshape_callback);
#else
    assert(display_callback&&reshape_callback);reshape_callback(800,600);
#endif
    display_callback();display_callback();
}
#endif
const GLubyte *glGetString(GLenum key) { if(key==GL_VENDOR)return (const GLubyte *)"fixture";if(key==GL_VERSION)return (const GLubyte *)"2.0";assert(key==GL_RENDERER);return (const GLubyte *)(mode==1?"llvmpipe":mode==2?"Apple M1":"Vinix Fake G17C (M5 Max ABI)"); }
void glViewport(GLint x,GLint y,GLsizei w,GLsizei h) { assert(!x&&!y&&w==800&&h==600); }
void glClearColor(GLfloat r,GLfloat g,GLfloat b,GLfloat a) {
#ifdef VINIX_LEGACY_TRIANGLE
    assert(r==0.08f&&g==0.08f&&b==0.10f&&a==1.0f);
#else
    assert(r==0.035f&&g==0.045f&&b==0.075f&&a==1.0f);
#endif
}
void glClear(GLbitfield mask) { assert(mask==(GL_COLOR_BUFFER_BIT|(depth?GL_DEPTH_BUFFER_BIT:0)|(stencil?GL_STENCIL_BUFFER_BIT:0))); }
void glFinish(void) { finished++; }
int main(int argc,char **argv) {
    if(getenv("TRIANGLE_FB_BPP"))bpp=(unsigned)atoi(getenv("TRIANGLE_FB_BPP"));if(getenv("TRIANGLE_SOFTWARE"))mode=1;if(getenv("TRIANGLE_APPLE"))mode=2;
    int rc=test_program_main(argc,argv);
    if(mode==1)assert(rc==2&&!draws);else {
#ifdef VINIX_LEGACY_TRIANGLE
        assert(!rc&&draws==2&&!finished&&!allocs&&!frees);
#else
        assert(!rc&&draws&&finished);if(allocs)assert(allocs==1&&frees==1);
#endif
    }
    puts("Triangle native fixture: PASS");return 0;
}
