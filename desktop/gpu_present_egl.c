// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

/* SPDX-License-Identifier: GPL-2.0-or-later
 * Copyright (c) 2026 Alexander Medvednikov
 *
 * GPU presenter for the native framebuffer desktop.
 *
 * The display is still a firmware framebuffer rather than a KMS scanout
 * object, so the final image must return to CPU-visible /dev/fb0.  This path
 * nevertheless moves scaling and format-preserving composition to the GPU. */
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
    int first_frame_started;
    uint32_t *readback;
};

void vinix_gpu_present_startup_stage(const char *stage)
{
    fprintf(stderr, "vinix-desktop: GPU init: %s\n", stage);
    fflush(stderr);
}

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

    vinix_gpu_present_startup_stage("presenter creation entered");
    if (width <= 0 || height <= 0)
        return NULL;
    {
        const char *force_software = getenv("VINIX_FORCE_SOFTWARE_GL");
        if (force_software && !strcmp(force_software, "1"))
            return NULL;
    }
    vinix_gpu_present_startup_stage("presenter arguments validated");

    /* Do not let a software EGL implementation turn the opt-in GPU binary
     * into a slower readback path on QEMU or on a failed AGX probe. */
    vinix_gpu_present_startup_stage("opening render node");
    render_fd = open("/dev/dri/renderD128", O_RDWR | O_CLOEXEC);
    if (render_fd < 0)
        return NULL;
    close(render_fd);
    vinix_gpu_present_startup_stage("render node opened");
    vinix_gpu_present_startup_stage("allocating presenter state");
    presenter = calloc(1, sizeof(*presenter));
    if (!presenter)
        return NULL;
    presenter->display = EGL_NO_DISPLAY;
    presenter->surface = EGL_NO_SURFACE;
    presenter->context = EGL_NO_CONTEXT;
    presenter->width = width;
    presenter->height = height;
    vinix_gpu_present_startup_stage("presenter state allocated");

    vinix_gpu_present_startup_stage("resolving EGL platform display entrypoint");
    get_platform_display = (PFNEGLGETPLATFORMDISPLAYEXTPROC)
        eglGetProcAddress("eglGetPlatformDisplayEXT");
    vinix_gpu_present_startup_stage("acquiring surfaceless EGL display");
    presenter->display = get_platform_display
        ? get_platform_display(EGL_PLATFORM_SURFACELESS_MESA,
                               EGL_DEFAULT_DISPLAY, NULL)
        : eglGetDisplay(EGL_DEFAULT_DISPLAY);
    if (presenter->display == EGL_NO_DISPLAY)
        goto fail;
    vinix_gpu_present_startup_stage("surfaceless EGL display acquired");
    vinix_gpu_present_startup_stage("initializing EGL");
    if (!eglInitialize(presenter->display, NULL, NULL))
        goto fail;
    vinix_gpu_present_startup_stage("EGL initialized");
    vinix_gpu_present_startup_stage("binding OpenGL ES");
    if (!eglBindAPI(EGL_OPENGL_ES_API))
        goto fail;
    vinix_gpu_present_startup_stage("OpenGL ES bound");
    vinix_gpu_present_startup_stage("choosing EGL config");
    if (!eglChooseConfig(presenter->display, config_attributes, &config, 1,
                         &config_count) || config_count != 1)
        goto fail;
    vinix_gpu_present_startup_stage("EGL config chosen");

    vinix_gpu_present_startup_stage("creating pbuffer surface");
    presenter->surface = eglCreatePbufferSurface(presenter->display, config,
                                                  surface_attributes);
    if (presenter->surface == EGL_NO_SURFACE)
        goto fail;
    vinix_gpu_present_startup_stage("pbuffer surface created");
    vinix_gpu_present_startup_stage("creating EGL context");
    presenter->context = eglCreateContext(presenter->display, config,
                                           EGL_NO_CONTEXT,
                                           context_attributes);
    if (presenter->context == EGL_NO_CONTEXT)
        goto fail;
    vinix_gpu_present_startup_stage("EGL context created");
    vinix_gpu_present_startup_stage("making EGL context current");
    if (!eglMakeCurrent(presenter->display, presenter->surface,
                        presenter->surface, presenter->context))
        goto fail;
    vinix_gpu_present_startup_stage("EGL context current");

    vinix_gpu_present_startup_stage("querying renderer");
    renderer = (const char *)glGetString(GL_RENDERER);
    if (!renderer || strstr(renderer, "llvmpipe") ||
        strstr(renderer, "softpipe") || strstr(renderer, "swrast"))
        goto fail;
    vinix_gpu_present_startup_stage("hardware renderer accepted");

    vinix_gpu_present_startup_stage("compiling vertex shader");
    vertex_shader = compile_shader(GL_VERTEX_SHADER, vertex_shader_source);
    if (!vertex_shader)
        goto fail;
    vinix_gpu_present_startup_stage("vertex shader compiled");
    vinix_gpu_present_startup_stage("compiling fragment shader");
    fragment_shader = compile_shader(GL_FRAGMENT_SHADER,
                                     fragment_shader_source);
    if (!fragment_shader)
        goto fail;
    vinix_gpu_present_startup_stage("fragment shader compiled");
    vinix_gpu_present_startup_stage("creating shader program");
    presenter->program = glCreateProgram();
    if (!presenter->program)
        goto fail;
    glAttachShader(presenter->program, vertex_shader);
    glAttachShader(presenter->program, fragment_shader);
    vinix_gpu_present_startup_stage("linking shader program");
    glLinkProgram(presenter->program);
    glGetProgramiv(presenter->program, GL_LINK_STATUS, &linked);
    glDeleteShader(vertex_shader);
    glDeleteShader(fragment_shader);
    vertex_shader = fragment_shader = 0;
    if (linked != GL_TRUE)
        goto fail;
    vinix_gpu_present_startup_stage("shader program linked");

    vinix_gpu_present_startup_stage("querying shader attributes");
    presenter->position = glGetAttribLocation(presenter->program, "position");
    presenter->texcoord = glGetAttribLocation(presenter->program, "texcoord");
    if (presenter->position < 0 || presenter->texcoord < 0)
        goto fail;
    vinix_gpu_present_startup_stage("shader attributes ready");

    vinix_gpu_present_startup_stage("creating frame texture");
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
    vinix_gpu_present_startup_stage("frame texture configured");
    fprintf(stderr, "vinix-desktop: GPU presentation enabled on %s\n", renderer);
    fflush(stderr);
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
    int trace_first_frame;
    int row;

    if (!presenter || !source || !destination || source_width <= 0 ||
        source_height <= 0 || source_stride != source_width ||
        destination_width != presenter->width ||
        destination_height != presenter->height ||
        destination_stride < destination_width)
        return 0;
    trace_first_frame = !presenter->first_frame_started;
    presenter->first_frame_started = 1;
    if (trace_first_frame)
        vinix_gpu_present_startup_stage("first frame begin");
    if (trace_first_frame)
        vinix_gpu_present_startup_stage("making first-frame context current");
    if (!eglMakeCurrent(presenter->display, presenter->surface,
                        presenter->surface, presenter->context))
        return 0;
    if (trace_first_frame)
        vinix_gpu_present_startup_stage("first-frame context current");

    if (destination_stride != destination_width) {
        if (!presenter->readback) {
            if (trace_first_frame)
                vinix_gpu_present_startup_stage("allocating packed readback buffer");
            presenter->readback = malloc((size_t)destination_width *
                                         destination_height * sizeof(uint32_t));
            if (!presenter->readback)
                return 0;
        }
        output = presenter->readback;
    }

    if (trace_first_frame)
        vinix_gpu_present_startup_stage("configuring first-frame viewport");
    glViewport(0, 0, destination_width, destination_height);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, presenter->texture);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 4);
    if (trace_first_frame)
        vinix_gpu_present_startup_stage("uploading first frame");
    if (presenter->texture_width != source_width ||
        presenter->texture_height != source_height) {
        if (trace_first_frame)
            vinix_gpu_present_startup_stage("allocating and uploading first texture");
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, source_width, source_height, 0,
                     GL_RGBA, GL_UNSIGNED_BYTE, source);
        presenter->texture_width = source_width;
        presenter->texture_height = source_height;
    } else {
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, source_width, source_height,
                        GL_RGBA, GL_UNSIGNED_BYTE, source);
    }
    if (trace_first_frame)
        vinix_gpu_present_startup_stage("first texture upload returned");
    if (trace_first_frame)
        vinix_gpu_present_startup_stage("configuring first-frame shader inputs");
    glUseProgram(presenter->program);
    glVertexAttribPointer((GLuint)presenter->position, 2, GL_FLOAT, GL_FALSE,
                          4 * sizeof(GLfloat), vertices);
    glVertexAttribPointer((GLuint)presenter->texcoord, 2, GL_FLOAT, GL_FALSE,
                          4 * sizeof(GLfloat), vertices + 2);
    glEnableVertexAttribArray((GLuint)presenter->position);
    glEnableVertexAttribArray((GLuint)presenter->texcoord);
    if (trace_first_frame)
        vinix_gpu_present_startup_stage("submitting first draw");
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    if (trace_first_frame)
        vinix_gpu_present_startup_stage("first draw returned");
    glPixelStorei(GL_PACK_ALIGNMENT, 4);
    if (trace_first_frame)
        vinix_gpu_present_startup_stage("reading back first frame");
    glReadPixels(0, 0, destination_width, destination_height, GL_RGBA,
                 GL_UNSIGNED_BYTE, output);
    if (trace_first_frame)
        vinix_gpu_present_startup_stage("first readback returned");
    if (trace_first_frame)
        vinix_gpu_present_startup_stage("checking first-frame GL status");
    if (glGetError() != GL_NO_ERROR)
        return 0;

    if (output != destination) {
        if (trace_first_frame)
            vinix_gpu_present_startup_stage("copying packed readback to framebuffer");
        for (row = 0; row < destination_height; ++row) {
            memcpy(destination + (size_t)row * destination_stride,
                   output + (size_t)row * destination_width,
                   (size_t)destination_width * sizeof(uint32_t));
        }
    }
    if (trace_first_frame)
        vinix_gpu_present_startup_stage("first frame complete");
    return 1;
}

void vinix_gpu_present_destroy(void *opaque)
{
    destroy_presenter(opaque);
}
