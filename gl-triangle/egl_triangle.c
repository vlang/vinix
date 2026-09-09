#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>

#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/fb.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <unistd.h>

#ifndef EGL_PLATFORM_SURFACELESS_MESA
#define EGL_PLATFORM_SURFACELESS_MESA 0x31DD
#endif

#define TRIANGLE_WIDTH 800
#define TRIANGLE_HEIGHT 600

enum attachment_mode {
    ATTACHMENT_COLOR_ONLY,
    ATTACHMENT_DEPTH,
    ATTACHMENT_STENCIL,
    ATTACHMENT_DEPTH_STENCIL,
};

static const char *attachment_mode_name(enum attachment_mode mode) {
    switch (mode) {
    case ATTACHMENT_DEPTH:
        return "depth";
    case ATTACHMENT_STENCIL:
        return "stencil";
    case ATTACHMENT_DEPTH_STENCIL:
        return "depth-stencil";
    case ATTACHMENT_COLOR_ONLY:
        return "color";
    }
    return "unknown";
}

static void fail_egl(const char *operation) {
    fprintf(stderr, "gl-triangle-agx: %s failed (EGL 0x%04x)\n",
            operation, eglGetError());
    exit(1);
}

static GLuint compile_shader(GLenum type, const char *source) {
    GLuint shader = glCreateShader(type);
    GLint ok = GL_FALSE;
    glShaderSource(shader, 1, &source, NULL);
    glCompileShader(shader);
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[1024];
        GLsizei length = 0;
        glGetShaderInfoLog(shader, sizeof(log), &length, log);
        fprintf(stderr, "gl-triangle-agx: shader compile failed: %.*s\n",
                (int)length, log);
        exit(1);
    }
    return shader;
}

static GLuint create_program(void) {
    static const char vertex_source[] =
        "attribute vec2 position;\n"
        "attribute vec3 color;\n"
        "varying vec3 vertex_color;\n"
        "void main(void) {\n"
        "  vertex_color = color;\n"
        "  gl_Position = vec4(position, 0.0, 1.0);\n"
        "}\n";
    static const char fragment_source[] =
        "precision mediump float;\n"
        "varying vec3 vertex_color;\n"
        "void main(void) {\n"
        "  gl_FragColor = vec4(vertex_color, 1.0);\n"
        "}\n";
    GLuint vertex = compile_shader(GL_VERTEX_SHADER, vertex_source);
    GLuint fragment = compile_shader(GL_FRAGMENT_SHADER, fragment_source);
    GLuint program = glCreateProgram();
    GLint ok = GL_FALSE;
    glAttachShader(program, vertex);
    glAttachShader(program, fragment);
    glBindAttribLocation(program, 0, "position");
    glBindAttribLocation(program, 1, "color");
    glLinkProgram(program);
    glGetProgramiv(program, GL_LINK_STATUS, &ok);
    if (!ok) {
        char log[1024];
        GLsizei length = 0;
        glGetProgramInfoLog(program, sizeof(log), &length, log);
        fprintf(stderr, "gl-triangle-agx: program link failed: %.*s\n",
                (int)length, log);
        exit(1);
    }
    glDeleteShader(vertex);
    glDeleteShader(fragment);
    return program;
}

static int contains_ignoring_case(const char *text, const char *needle) {
    size_t needle_length = strlen(needle);
    if (!needle_length)
        return 1;
    for (; *text; ++text) {
        size_t i = 0;
        while (i < needle_length && text[i] &&
               tolower((unsigned char)text[i]) ==
                   tolower((unsigned char)needle[i]))
            ++i;
        if (i == needle_length)
            return 1;
    }
    return 0;
}

static uint32_t framebuffer_component(uint8_t value,
                                      struct fb_bitfield field) {
    uint64_t maximum;
    if (!field.length || field.offset >= 32)
        return 0;
    maximum = field.length >= 32 ? UINT32_MAX : ((UINT64_C(1) << field.length) - 1);
    return (uint32_t)(((value * maximum + 127) / 255) << field.offset);
}

static int copy_to_framebuffer(const uint8_t *pixels, int width, int height) {
    struct fb_fix_screeninfo fixed;
    struct fb_var_screeninfo variable;
    uint8_t *framebuffer;
    int fd = open("/dev/fb0", O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        fprintf(stderr, "gl-triangle-agx: /dev/fb0 unavailable: %s\n",
                strerror(errno));
        return 0;
    }
    if (ioctl(fd, FBIOGET_FSCREENINFO, &fixed) < 0 ||
        ioctl(fd, FBIOGET_VSCREENINFO, &variable) < 0) {
        fprintf(stderr, "gl-triangle-agx: framebuffer query failed: %s\n",
                strerror(errno));
        close(fd);
        return 0;
    }
    if (!fixed.smem_len || !fixed.line_length ||
        (variable.bits_per_pixel != 16 && variable.bits_per_pixel != 24 &&
         variable.bits_per_pixel != 32) ||
        variable.red.msb_right || variable.green.msb_right ||
        variable.blue.msb_right || variable.transp.msb_right ||
        variable.red.offset + variable.red.length > variable.bits_per_pixel ||
        variable.green.offset + variable.green.length > variable.bits_per_pixel ||
        variable.blue.offset + variable.blue.length > variable.bits_per_pixel ||
        variable.transp.offset + variable.transp.length > variable.bits_per_pixel) {
        fprintf(stderr, "gl-triangle-agx: unsupported framebuffer layout\n");
        close(fd);
        return 0;
    }

    framebuffer = mmap(NULL, fixed.smem_len, PROT_READ | PROT_WRITE,
                       MAP_SHARED, fd, 0);
    if (framebuffer == MAP_FAILED) {
        fprintf(stderr, "gl-triangle-agx: framebuffer mmap failed: %s\n",
                strerror(errno));
        close(fd);
        return 0;
    }

    int copy_width = width < (int)variable.xres ? width : (int)variable.xres;
    int copy_height = height < (int)variable.yres ? height : (int)variable.yres;
    int origin_x = ((int)variable.xres - copy_width) / 2;
    int origin_y = ((int)variable.yres - copy_height) / 2;
    unsigned bytes_per_pixel = variable.bits_per_pixel / 8;
    uint64_t last_row = (uint64_t)variable.yoffset + origin_y + copy_height - 1;
    uint64_t last_column = (uint64_t)variable.xoffset + origin_x + copy_width;
    if (last_row * fixed.line_length + last_column * bytes_per_pixel >
        fixed.smem_len) {
        fprintf(stderr, "gl-triangle-agx: framebuffer bounds are invalid\n");
        munmap(framebuffer, fixed.smem_len);
        close(fd);
        return 0;
    }

    for (int y = 0; y < copy_height; ++y) {
        const uint8_t *source = pixels +
            ((size_t)(height - 1 - y) * width) * 4;
        uint8_t *destination = framebuffer +
            (size_t)(variable.yoffset + origin_y + y) * fixed.line_length +
            (size_t)(variable.xoffset + origin_x) * bytes_per_pixel;
        for (int x = 0; x < copy_width; ++x) {
            uint32_t packed =
                framebuffer_component(source[0], variable.red) |
                framebuffer_component(source[1], variable.green) |
                framebuffer_component(source[2], variable.blue) |
                framebuffer_component(source[3], variable.transp);
            for (unsigned byte = 0; byte < bytes_per_pixel; ++byte)
                destination[byte] = (uint8_t)(packed >> (byte * 8));
            source += 4;
            destination += bytes_per_pixel;
        }
    }

    munmap(framebuffer, fixed.smem_len);
    close(fd);
    return 1;
}

static void destroy_render_state(GLuint program, EGLDisplay display,
                                 EGLSurface surface, EGLContext context) {
    glDeleteProgram(program);
    eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    eglDestroyContext(display, context);
    eglDestroySurface(display, surface);
    eglTerminate(display);
}

int main(int argc, char **argv) {
    int submit_only = 0;
    enum attachment_mode attachment_mode = ATTACHMENT_COLOR_ONLY;
    for (int argument = 1; argument < argc; ++argument) {
        enum attachment_mode requested_mode = ATTACHMENT_COLOR_ONLY;
        if (strcmp(argv[argument], "--submit-only") == 0) {
            if (submit_only)
                goto usage;
            submit_only = 1;
            continue;
        } else if (strcmp(argv[argument], "--depth") == 0) {
            requested_mode = ATTACHMENT_DEPTH;
        } else if (strcmp(argv[argument], "--stencil") == 0) {
            requested_mode = ATTACHMENT_STENCIL;
        } else if (strcmp(argv[argument], "--depth-stencil") == 0) {
            requested_mode = ATTACHMENT_DEPTH_STENCIL;
        } else {
            goto usage;
        }
        if (attachment_mode != ATTACHMENT_COLOR_ONLY)
            goto usage;
        attachment_mode = requested_mode;
    }

    static const GLfloat vertices[] = {
        -0.72f, -0.58f, 1.00f, 0.18f, 0.16f,
         0.72f, -0.58f, 0.16f, 1.00f, 0.30f,
         0.00f,  0.72f, 0.18f, 0.42f, 1.00f,
    };
    static const EGLint config_attributes[] = {
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT,
        EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_RED_SIZE, 8,
        EGL_GREEN_SIZE, 8,
        EGL_BLUE_SIZE, 8,
        EGL_ALPHA_SIZE, 8,
        EGL_NONE,
    };
    static const EGLint surface_attributes[] = {
        EGL_WIDTH, TRIANGLE_WIDTH,
        EGL_HEIGHT, TRIANGLE_HEIGHT,
        EGL_NONE,
    };
    static const EGLint context_attributes[] = {
        EGL_CONTEXT_CLIENT_VERSION, 2,
        EGL_NONE,
    };

    PFNEGLGETPLATFORMDISPLAYEXTPROC get_platform_display =
        (PFNEGLGETPLATFORMDISPLAYEXTPROC)
            eglGetProcAddress("eglGetPlatformDisplayEXT");
    EGLDisplay display = get_platform_display
        ? get_platform_display(EGL_PLATFORM_SURFACELESS_MESA,
                               EGL_DEFAULT_DISPLAY, NULL)
        : eglGetDisplay(EGL_DEFAULT_DISPLAY);
    EGLint major = 0, minor = 0, config_count = 0;
    EGLConfig config;
    EGLSurface surface;
    EGLContext context;

    if (display == EGL_NO_DISPLAY)
        fail_egl("surfaceless display creation");
    if (!eglInitialize(display, &major, &minor))
        fail_egl("eglInitialize");
    if (!eglBindAPI(EGL_OPENGL_ES_API))
        fail_egl("eglBindAPI");
    if (!eglChooseConfig(display, config_attributes, &config, 1, &config_count)
        || config_count != 1)
        fail_egl("eglChooseConfig");
    surface = eglCreatePbufferSurface(display, config, surface_attributes);
    if (surface == EGL_NO_SURFACE)
        fail_egl("eglCreatePbufferSurface");
    context = eglCreateContext(display, config, EGL_NO_CONTEXT,
                               context_attributes);
    if (context == EGL_NO_CONTEXT)
        fail_egl("eglCreateContext");
    if (!eglMakeCurrent(display, surface, surface, context))
        fail_egl("eglMakeCurrent");

    const char *vendor = (const char *)glGetString(GL_VENDOR);
    const char *renderer = (const char *)glGetString(GL_RENDERER);
    const char *version = (const char *)glGetString(GL_VERSION);
    printf("gl-triangle-agx: EGL %d.%d\n", major, minor);
    printf("gl-triangle-agx: GL_VENDOR=%s\n", vendor ? vendor : "unknown");
    printf("gl-triangle-agx: GL_RENDERER=%s\n", renderer ? renderer : "unknown");
    printf("gl-triangle-agx: GL_VERSION=%s\n", version ? version : "unknown");
    if (!renderer || contains_ignoring_case(renderer, "softpipe") ||
        contains_ignoring_case(renderer, "llvmpipe") ||
        contains_ignoring_case(renderer, "software rasterizer")) {
        fprintf(stderr, "gl-triangle-agx: refusing a software renderer\n");
        return 2;
    }

    GLuint framebuffer = 0;
    GLuint color_renderbuffer = 0;
    GLuint depth_stencil_renderbuffer = 0;
    if (attachment_mode != ATTACHMENT_COLOR_ONLY) {
        glGenFramebuffers(1, &framebuffer);
        glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);

        glGenRenderbuffers(1, &color_renderbuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, color_renderbuffer);
        glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA4,
                              TRIANGLE_WIDTH, TRIANGLE_HEIGHT);
        glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0,
                                  GL_RENDERBUFFER, color_renderbuffer);

        glGenRenderbuffers(1, &depth_stencil_renderbuffer);
        glBindRenderbuffer(GL_RENDERBUFFER, depth_stencil_renderbuffer);
        if (attachment_mode == ATTACHMENT_DEPTH) {
            glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH_COMPONENT16,
                                  TRIANGLE_WIDTH, TRIANGLE_HEIGHT);
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT,
                                      GL_RENDERBUFFER,
                                      depth_stencil_renderbuffer);
        } else if (attachment_mode == ATTACHMENT_STENCIL) {
            glRenderbufferStorage(GL_RENDERBUFFER, GL_STENCIL_INDEX8,
                                  TRIANGLE_WIDTH, TRIANGLE_HEIGHT);
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT,
                                      GL_RENDERBUFFER,
                                      depth_stencil_renderbuffer);
        } else {
            glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8_OES,
                                  TRIANGLE_WIDTH, TRIANGLE_HEIGHT);
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT,
                                      GL_RENDERBUFFER,
                                      depth_stencil_renderbuffer);
            glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_STENCIL_ATTACHMENT,
                                      GL_RENDERBUFFER,
                                      depth_stencil_renderbuffer);
        }

        GLenum framebuffer_status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
        GLenum setup_error = glGetError();
        if (setup_error != GL_NO_ERROR ||
            framebuffer_status != GL_FRAMEBUFFER_COMPLETE) {
            fprintf(stderr,
                    "gl-triangle-agx: %s framebuffer setup failed "
                    "(GL 0x%04x, status 0x%04x)\n",
                    attachment_mode_name(attachment_mode), setup_error,
                    framebuffer_status);
            return 1;
        }
    }

    GLint depth_bits = 0;
    GLint stencil_bits = 0;
    glGetIntegerv(GL_DEPTH_BITS, &depth_bits);
    glGetIntegerv(GL_STENCIL_BITS, &stencil_bits);
    if ((attachment_mode == ATTACHMENT_DEPTH &&
         (depth_bits < 16 || stencil_bits != 0)) ||
        (attachment_mode == ATTACHMENT_STENCIL &&
         (depth_bits != 0 || stencil_bits < 8)) ||
        (attachment_mode == ATTACHMENT_DEPTH_STENCIL &&
         (depth_bits < 16 || stencil_bits < 8))) {
        fprintf(stderr,
                "gl-triangle-agx: %s attachment mismatch "
                "(depth=%d stencil=%d)\n",
                attachment_mode_name(attachment_mode), depth_bits,
                stencil_bits);
        return 1;
    }
    printf("gl-triangle-agx: attachment mode=%s depth=%d stencil=%d\n",
           attachment_mode_name(attachment_mode), depth_bits, stencil_bits);

    GLuint program = create_program();
    glUseProgram(program);
    GLuint vertex_buffer = 0;
    glGenBuffers(1, &vertex_buffer);
    glBindBuffer(GL_ARRAY_BUFFER, vertex_buffer);
    glBufferData(GL_ARRAY_BUFFER, sizeof(vertices), vertices, GL_STATIC_DRAW);
    glViewport(0, 0, TRIANGLE_WIDTH, TRIANGLE_HEIGHT);
    glClearColor(0.035f, 0.045f, 0.075f, 1.0f);
    GLbitfield clear_mask = GL_COLOR_BUFFER_BIT;
    if (attachment_mode == ATTACHMENT_DEPTH ||
        attachment_mode == ATTACHMENT_DEPTH_STENCIL) {
        glClearDepthf(1.0f);
        glEnable(GL_DEPTH_TEST);
        glDepthFunc(GL_LESS);
        glDepthMask(GL_TRUE);
        clear_mask |= GL_DEPTH_BUFFER_BIT;
    }
    if (attachment_mode == ATTACHMENT_STENCIL ||
        attachment_mode == ATTACHMENT_DEPTH_STENCIL) {
        glClearStencil(0);
        glEnable(GL_STENCIL_TEST);
        glStencilMask(0xff);
        glStencilFunc(GL_ALWAYS, 1, 0xff);
        glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE);
        clear_mask |= GL_STENCIL_BUFFER_BIT;
    }
    glClear(clear_mask);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 5 * sizeof(GLfloat),
                          (const void *)0);
    glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, 5 * sizeof(GLfloat),
                          (const void *)(2 * sizeof(GLfloat)));
    glEnableVertexAttribArray(0);
    glEnableVertexAttribArray(1);
    glDrawArrays(GL_TRIANGLES, 0, 3);
    glFinish();
    if (glGetError() != GL_NO_ERROR) {
        fprintf(stderr, "gl-triangle-agx: render submit or wait failed\n");
        return 1;
    }

    // Fake G17 intentionally validates command generation and fence completion
    // without rasterizing. This mode proves the Mesa/DRM lifecycle while keeping
    // the normal test's rendered-pixel check intact for real hardware and VirGL.
    if (submit_only) {
        // An otherwise private renderbuffer has no externally observable result,
        // so Gallium may discard its batch even after glFinish().  A one-pixel
        // readback makes Mesa submit and wait without treating fake pixels as a
        // rendering correctness result.
        uint8_t probe[4];
        glReadPixels(TRIANGLE_WIDTH / 2, TRIANGLE_HEIGHT / 2, 1, 1,
                     GL_RGBA, GL_UNSIGNED_BYTE, probe);
        if (glGetError() != GL_NO_ERROR) {
            fprintf(stderr, "gl-triangle-agx: submit probe readback failed\n");
            return 1;
        }
        printf("gl-triangle-agx: render submit and fence completed successfully; pixels unchecked\n");
        glDeleteBuffers(1, &vertex_buffer);
        glDeleteRenderbuffers(1, &depth_stencil_renderbuffer);
        glDeleteRenderbuffers(1, &color_renderbuffer);
        glDeleteFramebuffers(1, &framebuffer);
        destroy_render_state(program, display, surface, context);
        return 0;
    }

    size_t image_size = (size_t)TRIANGLE_WIDTH * TRIANGLE_HEIGHT * 4;
    uint8_t *pixels = malloc(image_size);
    if (!pixels) {
        fprintf(stderr, "gl-triangle-agx: image allocation failed\n");
        return 1;
    }
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glReadPixels(0, 0, TRIANGLE_WIDTH, TRIANGLE_HEIGHT,
                 GL_RGBA, GL_UNSIGNED_BYTE, pixels);
    if (glGetError() != GL_NO_ERROR) {
        fprintf(stderr, "gl-triangle-agx: glReadPixels failed\n");
        return 1;
    }

    const uint8_t *center = pixels +
        ((size_t)(TRIANGLE_HEIGHT / 2) * TRIANGLE_WIDTH + TRIANGLE_WIDTH / 2) * 4;
    if (center[0] < 30 || center[1] < 30 || center[2] < 30) {
        fprintf(stderr, "gl-triangle-agx: rendered image validation failed\n");
        return 1;
    }

    int displayed = copy_to_framebuffer(pixels, TRIANGLE_WIDTH, TRIANGLE_HEIGHT);
    printf("gl-triangle-agx: hardware frame rendered successfully%s\n",
           displayed ? " and copied to /dev/fb0" : "");
    // This marker is deliberately hardware-specific. VirGL, software Mesa and
    // the fake G17 backend must never be reported as an M1 hardware pass.
    if (renderer && contains_ignoring_case(renderer, "apple m1"))
        printf("VINIX M1 AGX RENDER TEST: PASS\n");
    fflush(stdout);

    free(pixels);
    glDeleteBuffers(1, &vertex_buffer);
    glDeleteRenderbuffers(1, &depth_stencil_renderbuffer);
    glDeleteRenderbuffers(1, &color_renderbuffer);
    glDeleteFramebuffers(1, &framebuffer);
    destroy_render_state(program, display, surface, context);
    return 0;

usage:
    fprintf(stderr,
            "usage: %s [--submit-only] "
            "[--depth|--stencil|--depth-stencil]\n",
            argv[0]);
    return 2;
}
