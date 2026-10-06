// SPDX-License-Identifier: GPL-2.0-or-later
// This fixture executes as an iOS ARM64 Mach-O, using Mesa through Vinix's
// EAGL/GLKit bridge. No Apple implementation is linked or copied.
#import "../../examples/ios-calculator/api/UIKit.h"
#include <GLES3/gl3.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

@interface EAGLContext : NSObject
- (instancetype)initWithAPI:(NSUInteger)api;
+ (BOOL)setCurrentContext:(EAGLContext *)context;
+ (EAGLContext *)currentContext;
@property(readonly) NSUInteger API;
@end
@interface GLKView : UIView
- (instancetype)initWithFrame:(CGRect)frame context:(EAGLContext *)context;
- (void)bindDrawable;
- (void)deleteDrawable;
- (void)display;
@property(nonatomic, strong) EAGLContext *context;
@property(nonatomic, weak) id delegate;
@property(nonatomic) NSUInteger drawableDepthFormat, drawableStencilFormat;
@property(nonatomic) BOOL enableSetNeedsDisplay;
@property(nonatomic) CGFloat contentScaleFactor;
@property(readonly) NSInteger drawableWidth, drawableHeight;
@end

static GLuint program, vao;
static int drawn;
static void check(int condition, const char *message) {
    if (!condition) { puts(message); abort(); }
}

static GLuint shader(GLenum type, const char *source) {
    GLuint object = glCreateShader(type);
    glShaderSource(object, 1, &source, NULL);
    glCompileShader(object);
    GLint compiled;
    glGetShaderiv(object, GL_COMPILE_STATUS, &compiled);
    if (!compiled) {
        char log[1024];
        glGetShaderInfoLog(object, sizeof(log), NULL, log);
        puts(log);
        abort();
    }
    return object;
}

@interface DrawDelegate : NSObject @end
@implementation DrawDelegate
- (void)glkView:(GLKView *)view drawInRect:(CGRect)rect {
    check(rect.origin.x == 0 && rect.origin.y == 0 &&
        rect.size.width == view.bounds.size.width && rect.size.height == view.bounds.size.height,
        "GLES: native CGRect callback ABI");
    check([EAGLContext currentContext] == view.context, "GLES: callback current context");
    GLint viewport[4];
    glGetIntegerv(GL_VIEWPORT, viewport);
    check(viewport[2] == view.drawableWidth && viewport[3] == view.drawableHeight,
        "GLES: drawable viewport");
    glClearColor(1, 0, 0, 1);
    glClearDepthf(1);
    glClearStencil(0);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT | GL_STENCIL_BUFFER_BIT);
    glUseProgram(program);
    glBindVertexArray(vao);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    unsigned char pixel[4];
    glReadPixels(viewport[2] / 2, viewport[3] / 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
    check(pixel[0] == 0 && pixel[1] == 255 && pixel[2] == 0 && pixel[3] == 255,
        "GLES: shader triangle pixel");
    glReadPixels(0, viewport[3] - 1, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
    check(pixel[0] == 255 && pixel[1] == 0 && pixel[2] == 0, "GLES: clear pixel");
    check(glGetError() == GL_NO_ERROR, "GLES: drawing error");
    ++drawn;
}
@end

static void *thread_context(void *pointer) {
    @autoreleasepool {
        void *aligned = NULL;
        check(!posix_memalign(&aligned, 64, 257) && ((uintptr_t)aligned % 64) == 0, "GLES: native aligned allocation");
        memset(aligned, 0xa5, 257);
        free(aligned);
        EAGLContext *context = (__bridge EAGLContext *)pointer;
        check([EAGLContext currentContext] == nil, "GLES: thread context must start empty");
        check([EAGLContext setCurrentContext:context], "GLES: thread context binding");
        check([EAGLContext currentContext] == context && glGetString(GL_VERSION), "GLES: thread GL state");
        glClearColor(0, 0, 1, 1);
        // Leave the context bound: the runtime's pthread TLS destructor must
        // unbind and release it before pthread_join returns.
    }
    return NULL;
}

int main(void) {
    @autoreleasepool {
        EAGLContext *context = [[EAGLContext alloc] initWithAPI:3];
        check(context && context.API == 3 && [EAGLContext setCurrentContext:context], "GLES: ES3 context");
        printf("IOS-GLES renderer: %s; %s\n", glGetString(GL_RENDERER), glGetString(GL_VERSION));
        check(strstr((const char *)glGetString(GL_VERSION), "OpenGL ES 3.") != NULL, "GLES: genuine ES3 version");
        __weak EAGLContext *retained = context;
        context = nil;
        check(retained != nil && [EAGLContext currentContext] == retained, "GLES: current context retains object");
        context = retained;
        EAGLContext *other = [[EAGLContext alloc] initWithAPI:2];
        pthread_t worker = NULL;
        check(other && !pthread_create(&worker, NULL, thread_context, (__bridge void *)other), "GLES: worker creation");
        check(!pthread_join(worker, NULL), "GLES: worker join");
        check([EAGLContext currentContext] == context, "GLES: per-thread context isolation");
        GLuint vertex = shader(GL_VERTEX_SHADER,
            "#version 300 es\nconst vec2 p[3]=vec2[3](vec2(-1,-1),vec2(1,-1),vec2(0,1));"
            "void main(){gl_Position=vec4(p[gl_VertexID],0,1);}");
        GLuint fragment = shader(GL_FRAGMENT_SHADER,
            "#version 300 es\nprecision highp float;out vec4 c;void main(){c=vec4(0,1,0,1);}");
        program = glCreateProgram();
        glAttachShader(program, vertex);
        glAttachShader(program, fragment);
        glLinkProgram(program);
        GLint linked;
        glGetProgramiv(program, GL_LINK_STATUS, &linked);
        check(linked, "GLES: program linking");
        glDeleteShader(vertex);
        glDeleteShader(fragment);
        glGenVertexArrays(1, &vao);
        __weak DrawDelegate *weakDelegate;
        GLKView *view = [[GLKView alloc] initWithFrame:CGRectMake(0, 0, 32, 24) context:context];
        @autoreleasepool {
            DrawDelegate *delegate = [DrawDelegate new];
            weakDelegate = delegate;
            view.delegate = delegate;
            view.drawableDepthFormat = 2; // GLKViewDrawableDepthFormat24
            view.drawableStencilFormat = 1; // GLKViewDrawableStencilFormat8
            view.enableSetNeedsDisplay = NO;
            for (int i = 0; i < 64; ++i) {
                view.frame = CGRectMake(0, 0, 32 + i % 3, 24 + i % 5);
                view.contentScaleFactor = i % 2 + 1;
                [view display];
                check(view.drawableWidth == (32 + i % 3) * (i % 2 + 1), "GLES: resize width");
                check(view.drawableHeight == (24 + i % 5) * (i % 2 + 1), "GLES: resize height");
            }
            GLint depthBits, stencilBits;
            glGetIntegerv(GL_DEPTH_BITS, &depthBits);
            glGetIntegerv(GL_STENCIL_BITS, &stencilBits);
            check(depthBits == 24 && stencilBits == 8, "GLES: real depth and stencil attachment");
        }
        check(weakDelegate == nil && view.delegate == nil, "GLES: delegate is weak");
        [view deleteDrawable];
        [view bindDrawable];
        check(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE, "GLES: drawable recreation");
        view = nil;
        glDeleteProgram(program);
        glDeleteVertexArrays(1, &vao);
        check([EAGLContext setCurrentContext:nil], "GLES: unbind context");
        context = nil;
        check(retained == nil && [EAGLContext currentContext] == nil, "GLES: context teardown");
        check(drawn == 64, "GLES: native callback count");
    }
    puts("IOS-GLES: native ES3 shader pixels, GLKView resize, depth/stencil, TLS and ARC teardown");
    return 0;
}
