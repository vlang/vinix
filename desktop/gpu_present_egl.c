/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Alexander Medvednikov
 *
 * GPU presenter for the native framebuffer desktop.
 *
 * The M1 display is still a firmware framebuffer rather than a KMS scanout
 * object, so the final image must return to CPU-visible /dev/fb0.  This path
 * nevertheless moves scaling and format-preserving composition to AGX. */
#include "gpu_present.h"

#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>

#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#ifndef EGL_PLATFORM_SURFACELESS_MESA
#define EGL_PLATFORM_SURFACELESS_MESA 0x31dd
#endif

struct gpu_presenter {
    EGLDisplay display;
    EGLSurface surface;
    EGLContext context;
    GLuint program;
    GLuint texture;
    GLint position;
    GLint texcoord;
    int width;
    int height;
    int texture_width;
    int texture_height;
    uint32_t *readback;
};

static const char vertex_shader_source[] =
    "attribute vec2 position;\n"
    "attribute vec2 texcoord;\n"
    "varying vec2 texture_coord;\n"
    "void main(void) {\n"
    "  gl_Position = vec4(position, 0.0, 1.0);\n"
    "  texture_coord = texcoord;\n"
    "}\n";

static const char fragment_shader_source[] =
    "precision mediump float;\n"
    "uniform sampler2D frame;\n"
    "varying vec2 texture_coord;\n"
    "void main(void) {\n"
    "  gl_FragColor = texture2D(frame, texture_coord);\n"
    "}\n";

static GLuint compile_shader(GLenum type, const char *source)
{
    GLuint shader = glCreateShader(type);
    GLint ok = GL_FALSE;

    if (!shader)
        return 0;
    glShaderSource(shader, 1, &source, NULL);
    glCompileShader(shader);
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (ok != GL_TRUE) {
        glDeleteShader(shader);
        return 0;
    }
    return shader;
}

static void destroy_presenter(struct gpu_presenter *presenter)
{
    if (!presenter)
        return;
    if (presenter->display != EGL_NO_DISPLAY) {
        if (presenter->context != EGL_NO_CONTEXT) {
            if (presenter->surface != EGL_NO_SURFACE)
                eglMakeCurrent(presenter->display, presenter->surface,
                               presenter->surface, presenter->context);
            if (presenter->program)
                glDeleteProgram(presenter->program);
            if (presenter->texture)
                glDeleteTextures(1, &presenter->texture);
        }
        eglMakeCurrent(presenter->display, EGL_NO_SURFACE, EGL_NO_SURFACE,
                       EGL_NO_CONTEXT);
        if (presenter->surface != EGL_NO_SURFACE)
            eglDestroySurface(presenter->display, presenter->surface);
        if (presenter->context != EGL_NO_CONTEXT)
            eglDestroyContext(presenter->display, presenter->context);
        eglTerminate(presenter->display);
    }
    free(presenter->readback);
    free(presenter);
}

void *vinix_gpu_present_create(int width, int height)
{
    static const EGLint config_attributes[] = {
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_NONE,
    };
    const EGLint surface_attributes[] = {
        EGL_WIDTH, width,
        EGL_HEIGHT, height,
        EGL_NONE,
    };
    static const EGLint context_attributes[] = {
        EGL_CONTEXT_CLIENT_VERSION, 2,
        EGL_NONE,
    };
    PFNEGLGETPLATFORMDISPLAYEXTPROC get_platform_display;
    struct gpu_presenter *presenter;
    EGLConfig config;
    EGLint config_count = 0;
    GLuint vertex_shader = 0;
    GLuint fragment_shader = 0;
    GLint linked = GL_FALSE;
    const char *renderer;
    int render_fd;

    if (width <= 0 || height <= 0)
        return NULL;
    {
        const char *force_software = getenv("VINIX_FORCE_SOFTWARE_GL");
        if (force_software && !strcmp(force_software, "1"))
            return NULL;
    }

    /* Do not let a software EGL implementation turn the opt-in GPU binary
     * into a slower readback path on QEMU or on a failed AGX probe. */
    render_fd = open("/dev/dri/renderD128", O_RDWR | O_CLOEXEC);
    if (render_fd < 0)
        return NULL;
    close(render_fd);
    if (!getenv("MESA_LOADER_DRIVER_OVERRIDE"))
        setenv("MESA_LOADER_DRIVER_OVERRIDE", "asahi", 0);

    presenter = calloc(1, sizeof(*presenter));
    if (!presenter)
        return NULL;
    presenter->display = EGL_NO_DISPLAY;
    presenter->surface = EGL_NO_SURFACE;
    presenter->context = EGL_NO_CONTEXT;
    presenter->width = width;
    presenter->height = height;

    get_platform_display = (PFNEGLGETPLATFORMDISPLAYEXTPROC)
        eglGetProcAddress("eglGetPlatformDisplayEXT");
    presenter->display = get_platform_display
        ? get_platform_display(EGL_PLATFORM_SURFACELESS_MESA,
                               EGL_DEFAULT_DISPLAY, NULL)
        : eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (presenter->display == EGL_NO_DISPLAY ||
        !eglInitialize(presenter->display, NULL, NULL) ||
        !eglBindAPI(EGL_OPENGL_ES_API) ||
        !eglChooseConfig(presenter->display, config_attributes, &config, 1,
                         &config_count) || config_count != 1)
        goto fail;

    presenter->surface = eglCreatePbufferSurface(presenter->display, config,
                                                  surface_attributes);
    presenter->context = eglCreateContext(presenter->display, config,
                                           EGL_NO_CONTEXT,
                                           context_attributes);
    if (presenter->surface == EGL_NO_SURFACE ||
        presenter->context == EGL_NO_CONTEXT ||
        !eglMakeCurrent(presenter->display, presenter->surface,
                        presenter->surface, presenter->context))
        goto fail;

    renderer = (const char *)glGetString(GL_RENDERER);
    if (!renderer || strstr(renderer, "llvmpipe") ||
        strstr(renderer, "softpipe") || strstr(renderer, "swrast"))
        goto fail;

    vertex_shader = compile_shader(GL_VERTEX_SHADER, vertex_shader_source);
    fragment_shader = compile_shader(GL_FRAGMENT_SHADER,
                                     fragment_shader_source);
    if (!vertex_shader || !fragment_shader)
        goto fail;
    presenter->program = glCreateProgram();
    if (!presenter->program)
        goto fail;
    glAttachShader(presenter->program, vertex_shader);
    glAttachShader(presenter->program, fragment_shader);
    glLinkProgram(presenter->program);
    glGetProgramiv(presenter->program, GL_LINK_STATUS, &linked);
    glDeleteShader(vertex_shader);
    glDeleteShader(fragment_shader);
    vertex_shader = fragment_shader = 0;
    if (linked != GL_TRUE)
        goto fail;

    presenter->position = glGetAttribLocation(presenter->program, "position");
    presenter->texcoord = glGetAttribLocation(presenter->program, "texcoord");
    if (presenter->position < 0 || presenter->texcoord < 0)
        goto fail;

    glGenTextures(1, &presenter->texture);
    if (!presenter->texture)
        goto fail;
    glBindTexture(GL_TEXTURE_2D, presenter->texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glUseProgram(presenter->program);
    glUniform1i(glGetUniformLocation(presenter->program, "frame"), 0);
    fprintf(stderr, "vinix-desktop: GPU presentation enabled on %s\n", renderer);
    return presenter;

fail:
    if (vertex_shader)
        glDeleteShader(vertex_shader);
    if (fragment_shader)
        glDeleteShader(fragment_shader);
    destroy_presenter(presenter);
    return NULL;
}

int vinix_gpu_present_frame(void *opaque,
                            const uint32_t *source,
                            int source_width,
                            int source_height,
                            int source_stride,
                            uint32_t *destination,
                            int destination_width,
                            int destination_height,
                            int destination_stride)
{
    static const GLfloat vertices[] = {
        -1.0f, -1.0f, 0.0f, 0.0f,
         1.0f, -1.0f, 1.0f, 0.0f,
        -1.0f,  1.0f, 0.0f, 1.0f,
         1.0f,  1.0f, 1.0f, 1.0f,
    };
    struct gpu_presenter *presenter = opaque;
    uint32_t *output = destination;
    int row;

    if (!presenter || !source || !destination || source_width <= 0 ||
        source_height <= 0 || source_stride != source_width ||
        destination_width != presenter->width ||
        destination_height != presenter->height ||
        destination_stride < destination_width)
        return 0;
    if (!eglMakeCurrent(presenter->display, presenter->surface,
                        presenter->surface, presenter->context))
        return 0;

    if (destination_stride != destination_width) {
        if (!presenter->readback) {
            presenter->readback = malloc((size_t)destination_width *
                                         destination_height * sizeof(uint32_t));
            if (!presenter->readback)
                return 0;
        }
        output = presenter->readback;
    }

    glViewport(0, 0, destination_width, destination_height);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, presenter->texture);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
    if (presenter->texture_width != source_width ||
        presenter->texture_height != source_height) {
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, source_width, source_height, 0,
                     GL_RGBA, GL_UNSIGNED_BYTE, source);
        presenter->texture_width = source_width;
        presenter->texture_height = source_height;
    } else {
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, source_width, source_height,
                        GL_RGBA, GL_UNSIGNED_BYTE, source);
    }
    glUseProgram(presenter->program);
    glVertexAttribPointer((GLuint)presenter->position, 2, GL_FLOAT, GL_FALSE,
                          4 * sizeof(GLfloat), vertices);
    glVertexAttribPointer((GLuint)presenter->texcoord, 2, GL_FLOAT, GL_FALSE,
                          4 * sizeof(GLfloat), vertices + 2);
    glEnableVertexAttribArray((GLuint)presenter->position);
    glEnableVertexAttribArray((GLuint)presenter->texcoord);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    glPixelStorei(GL_PACK_ALIGNMENT, 4);
    glReadPixels(0, 0, destination_width, destination_height, GL_RGBA,
                 GL_UNSIGNED_BYTE, output);
    if (glGetError() != GL_NO_ERROR)
        return 0;

    if (output != destination) {
        for (row = 0; row < destination_height; ++row) {
            memcpy(destination + (size_t)row * destination_stride,
                   output + (size_t)row * destination_width,
                   (size_t)destination_width * sizeof(uint32_t));
        }
    }
    return 1;
}

void vinix_gpu_present_destroy(void *opaque)
{
    destroy_presenter(opaque);
}
