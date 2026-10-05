/* Exercise the EGLImage -> GDK texture path used by ATL, with real GL pixels. */
#include <gtk/gtk.h>
#include <gdk/x11/gdkx.h>
#include <EGL/egl.h>
#include <EGL/eglext.h>
#include <GLES2/gl2.h>
#include <GLES2/gl2ext.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void require(int condition, const char *phase)
{
    if (!condition) {
        fprintf(stderr, "ANDROID-EGL-FAIL phase=%s egl=0x%x gl=0x%x\n",
                phase, eglGetError(), glGetError());
        exit(1);
    }
}

static void green_pixels(const unsigned char *pixels, const char *phase)
{
    for (size_t i = 0; i < 4; i++) {
        const unsigned char *p = pixels + i * 4;
        if (p[0] != 0 || p[1] != 255 || p[2] != 0 || p[3] != 255) {
            fprintf(stderr, "ANDROID-EGL-FAIL phase=%s pixel=%zu rgba=%u,%u,%u,%u\n",
                    phase, i, p[0], p[1], p[2], p[3]);
            exit(1);
        }
    }
}

int main(void)
{
    g_setenv("GDK_BACKEND", "x11", FALSE);
    g_setenv("GDK_DISABLE", "glx", FALSE);
    g_setenv("GSK_RENDERER", "cairo", FALSE);
    g_setenv("GTK_A11Y", "none", FALSE);
    require(gtk_init_check(), "gtk-init");
    GtkWidget *window = gtk_window_new();
    gtk_window_set_default_size(GTK_WINDOW(window), 64, 64);
    gtk_widget_realize(window);
    GdkSurface *surface = gtk_native_get_surface(GTK_NATIVE(window));
    require(surface != NULL, "gtk-surface");
    GdkDisplay *gdk_display = gdk_surface_get_display(surface);
    require(GDK_IS_X11_DISPLAY(gdk_display), "x11-display");
#pragma GCC diagnostic push
#pragma GCC diagnostic ignored "-Wdeprecated-declarations"
    Display *xdisplay = gdk_x11_display_get_xdisplay(gdk_display);
#pragma GCC diagnostic pop
    EGLDisplay display = eglGetPlatformDisplay(EGL_PLATFORM_X11_KHR, xdisplay, NULL);
    require(display != EGL_NO_DISPLAY, "egl-display");
    EGLint major = 0, minor = 0;
    require(eglInitialize(display, &major, &minor), "egl-initialize");
    require(eglBindAPI(EGL_OPENGL_ES_API), "egl-bind-api");
    const EGLint attributes[] = {
        EGL_SURFACE_TYPE, EGL_PBUFFER_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
        EGL_NONE
    };
    EGLConfig config;
    EGLint count = 0;
    require(eglChooseConfig(display, attributes, &config, 1, &count) && count == 1,
            "egl-config");
    const EGLint size[] = {EGL_WIDTH, 2, EGL_HEIGHT, 2, EGL_NONE};
    EGLSurface pbuffer = eglCreatePbufferSurface(display, config, size);
    require(pbuffer != EGL_NO_SURFACE, "egl-pbuffer");
    const EGLint context_attributes[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE};
    EGLContext context = eglCreateContext(display, config, EGL_NO_CONTEXT,
                                          context_attributes);
    require(context != EGL_NO_CONTEXT, "egl-es2-context");
    require(eglMakeCurrent(display, pbuffer, pbuffer, context), "egl-current");
    const char *renderer = (const char *)glGetString(GL_RENDERER);
    require(renderer != NULL, "gl-renderer");
    printf("ANDROID-EGL-INFO version=%d.%d renderer=%s\n", major, minor, renderer);
    GLuint source_texture = 0, framebuffer = 0;
    glGenTextures(1, &source_texture);
    glBindTexture(GL_TEXTURE_2D, source_texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 2, 2, 0, GL_RGBA, GL_UNSIGNED_BYTE, NULL);
    glGenFramebuffers(1, &framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
                           source_texture, 0);
    require(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE,
            "gl-fbo");
    glViewport(0, 0, 2, 2);
    glClearColor(0, 1, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    unsigned char pixels[16] = {0};
    glReadPixels(0, 0, 2, 2, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
    require(glGetError() == GL_NO_ERROR, "gl-readback");
    green_pixels(pixels, "gl-readback");
    glFinish();
    const EGLAttrib image_attributes[] = {EGL_IMAGE_PRESERVED_KHR, EGL_TRUE, EGL_NONE};
    EGLImage image = eglCreateImage(display, context, EGL_GL_TEXTURE_2D_KHR,
                                   (EGLClientBuffer)(uintptr_t)source_texture,
                                   image_attributes);
    require(image != EGL_NO_IMAGE, "egl-image-export");
    require(eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT),
            "egl-release");
    GError *error = NULL;
    GdkGLContext *gtk_context = gdk_surface_create_gl_context(surface, &error);
    if (error) fprintf(stderr, "GDK create: %s\n", error->message);
    require(gtk_context != NULL, "gdk-context");
    gdk_gl_context_set_allowed_apis(gtk_context, GDK_GL_API_GLES);
    gdk_gl_context_set_required_version(gtk_context, 2, 0);
    require(gdk_gl_context_realize(gtk_context, &error), "gdk-context-realize");
    gdk_gl_context_make_current(gtk_context);
    require(gdk_gl_context_get_current() == gtk_context, "gdk-current");
    require(eglGetCurrentDisplay() == display, "gdk-egl-same-display");
    PFNGLEGLIMAGETARGETTEXTURE2DOESPROC import_image =
        (PFNGLEGLIMAGETARGETTEXTURE2DOESPROC)eglGetProcAddress("glEGLImageTargetTexture2DOES");
    require(import_image != NULL, "egl-image-import-function");
    GLuint gtk_texture = 0, gtk_framebuffer = 0;
    glGenTextures(1, &gtk_texture);
    glBindTexture(GL_TEXTURE_2D, gtk_texture);
    import_image(GL_TEXTURE_2D, image);
    require(glGetError() == GL_NO_ERROR, "egl-image-import");
    glGenFramebuffers(1, &gtk_framebuffer);
    glBindFramebuffer(GL_FRAMEBUFFER, gtk_framebuffer);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
                           gtk_texture, 0);
    require(glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE,
            "gdk-image-fbo");
    memset(pixels, 0, sizeof pixels);
    glReadPixels(0, 0, 2, 2, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
    require(glGetError() == GL_NO_ERROR, "gdk-image-readback");
    green_pixels(pixels, "gdk-image-readback");
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glBindTexture(GL_TEXTURE_2D, 0);
    require(eglDestroyImage(display, image), "egl-image-destroy");
    GdkGLTextureBuilder *builder = gdk_gl_texture_builder_new();
    gdk_gl_texture_builder_set_context(builder, gtk_context);
    gdk_gl_texture_builder_set_id(builder, gtk_texture);
    gdk_gl_texture_builder_set_width(builder, 2);
    gdk_gl_texture_builder_set_height(builder, 2);
    gdk_gl_texture_builder_set_format(builder, GDK_MEMORY_R8G8B8A8_PREMULTIPLIED);
    GdkTexture *texture = gdk_gl_texture_builder_build(builder, NULL, NULL);
    require(texture != NULL, "gdk-texture-build");
    gdk_gl_context_clear_current();
    memset(pixels, 0, sizeof pixels);
    gdk_texture_download(texture, pixels, 8);
    green_pixels(pixels, "gdk-texture-download");
    g_object_unref(texture);
    g_object_unref(builder);
    gdk_gl_context_make_current(gtk_context);
    glDeleteFramebuffers(1, &gtk_framebuffer);
    glDeleteTextures(1, &gtk_texture);
    gdk_gl_context_clear_current();
    g_object_unref(gtk_context);
    require(eglMakeCurrent(display, pbuffer, pbuffer, context), "egl-cleanup-current");
    glDeleteFramebuffers(1, &framebuffer);
    glDeleteTextures(1, &source_texture);
    require(eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT),
            "egl-cleanup-release");
    require(eglDestroyContext(display, context), "egl-context-destroy");
    require(eglDestroySurface(display, pbuffer), "egl-pbuffer-destroy");
    gtk_window_destroy(GTK_WINDOW(window));
    puts("ANDROID-EGL-PASS es2-readback=green egl-image=gtk-import gdk-texture=green");
    return 0;
}
