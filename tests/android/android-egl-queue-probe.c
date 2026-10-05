/* Public Android JNI/window/EGL calls only; loaded as an ordinary APK library. */
#include <jni.h>
#include <EGL/egl.h>
#include <GLES2/gl2.h>
#include <time.h>
#include <unistd.h>

/* Opaque public Android window ABI; no GTK or ATL implementation headers. */
typedef struct ANativeWindow ANativeWindow;
extern ANativeWindow *ANativeWindow_fromSurface(JNIEnv *, jobject);
extern void ANativeWindow_release(ANativeWindow *);

static int phase;

JNIEXPORT void JNICALL Java_org_vinix_tests_AndroidEglQueueProbe_nativePhase(
        JNIEnv *env, jclass type, jint value)
{
    (void)env; (void)type;
    __atomic_store_n(&phase, value, __ATOMIC_RELEASE);
}

JNIEXPORT jint JNICALL Java_org_vinix_tests_AndroidEglQueueProbe_nativeError(
        JNIEnv *env, jclass type)
{
    (void)env; (void)type;
    return eglGetError();
}

static long long milliseconds(void)
{
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return -1;
    return now.tv_sec * 1000LL + now.tv_nsec / 1000000;
}

static int wait_phase(int expected, int timeout)
{
    long long end = milliseconds() + timeout;
    while (__atomic_load_n(&phase, __ATOMIC_ACQUIRE) != expected) {
        if (milliseconds() >= end) return 0;
        usleep(1000);
    }
    return 1;
}

static int green_pixel(void)
{
    unsigned char pixel[4] = {0};
    glReadPixels(0, 0, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, pixel);
    return glGetError() == GL_NO_ERROR && pixel[0] == 0 && pixel[1] == 255
        && pixel[2] == 0 && pixel[3] == 255;
}

static int green_drawable(void)
{
    GLint framebuffer = 0;
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &framebuffer);
    if (framebuffer == 0 || glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE)
        return 0;
    glViewport(0, 0, 2, 2);
    glClearColor(0, 1, 0, 1);
    glClear(GL_COLOR_BUFFER_BIT);
    return green_pixel();
}

JNIEXPORT jint JNICALL Java_org_vinix_tests_AndroidEglQueueProbe_nativeRun(
        JNIEnv *env, jclass type, jobject java_surface, jobject activity)
{
    (void)type;
    ANativeWindow *window = NULL;
    EGLDisplay display = EGL_NO_DISPLAY;
    EGLContext context = EGL_NO_CONTEXT;
    EGLSurface surface = EGL_NO_SURFACE;
    int current = 0, recovered = 0, failures = 0, pending = 0;
    const char *failure = NULL;
    jclass activity_type = (*env)->GetObjectClass(env, activity);
    jmethodID pause = (*env)->GetMethodID(env, activity_type, "pauseConsumer", "(I)V");
    const EGLint attributes[] = {
        EGL_SURFACE_TYPE, EGL_WINDOW_BIT, EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
        EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8, EGL_NONE
    };
    const EGLint context_attributes[] = {EGL_CONTEXT_CLIENT_VERSION, 2, EGL_NONE};
    EGLConfig config = NULL;
    EGLint count = 0;
    EGLint (*get_error)(void) = NULL;
#define REQUIRE(value, message) do { if (!(value)) { failure = message; goto cleanup; } } while (0)
    REQUIRE(pause != NULL && !(*env)->ExceptionCheck(env), "pause callback unavailable");
    window = ANativeWindow_fromSurface(env, java_surface);
    REQUIRE(window != NULL, "production native window unavailable");
    display = eglGetDisplay(EGL_DEFAULT_DISPLAY);
    REQUIRE(display != EGL_NO_DISPLAY && eglInitialize(display, NULL, NULL), "EGL display unavailable");
    REQUIRE(eglBindAPI(EGL_OPENGL_ES_API), "GLES API unavailable");
    REQUIRE(eglChooseConfig(display, attributes, &config, 1, &count) && count == 1, "EGL window config unavailable");
    context = eglCreateContext(display, config, EGL_NO_CONTEXT, context_attributes);
    REQUIRE(context != EGL_NO_CONTEXT, "GLES2 context unavailable");
    surface = eglCreateWindowSurface(display, config, (EGLNativeWindowType)window, NULL);
    REQUIRE(surface != EGL_NO_SURFACE, "production EGL surface unavailable");
    REQUIRE(eglMakeCurrent(display, surface, surface, context), "production EGL make-current failed");
    current = 1;
    REQUIRE(green_drawable(), "initial production framebuffer/pixels invalid");
    REQUIRE(eglGetError() == EGL_SUCCESS, "initial EGL operation failed");
    get_error = (EGLint (*)(void))eglGetProcAddress("eglGetError");
    REQUIRE(get_error != NULL, "EGL error entrypoint unavailable");

    (*env)->CallVoidMethod(env, activity, pause, 1);
    REQUIRE(!(*env)->ExceptionCheck(env) && wait_phase(1, 5000), "main-thread pause not started");
    while (__atomic_load_n(&phase, __ATOMIC_ACQUIRE) == 1) {
        GLint before = 0, after = 0;
        REQUIRE(green_drawable(), "starvation framebuffer/pixels invalid");
        glGetIntegerv(GL_FRAMEBUFFER_BINDING, &before);
        long long started = milliseconds();
        EGLBoolean swapped = eglSwapBuffers(display, surface);
        REQUIRE(milliseconds() - started < 750, "swap blocked beyond its finite wait");
        if (!swapped) {
            failures++;
            glGetIntegerv(GL_FRAMEBUFFER_BINDING, &after);
            REQUIRE(after == before && green_pixel(), "failed swap lost its current framebuffer/pixels");
            glBindFramebuffer(GL_FRAMEBUFFER, 0);
            glGetIntegerv(GL_FRAMEBUFFER_BINDING, &after);
            REQUIRE(after == before && green_pixel(), "default binding lost the retained framebuffer/pixels");
            /* Leave the error pending until the UI thread has checked its own EGL state. */
        }
    }
    REQUIRE(failures > 0, "pause did not exhaust the production buffer queue");
    REQUIRE(get_error() == EGL_BAD_ALLOC && eglGetError() == EGL_SUCCESS,
            "starvation EGL error missing or not cleared");

    long long deadline = milliseconds() + 15000;
    while (recovered < 32 && milliseconds() < deadline) {
        REQUIRE(green_drawable(), "recovered framebuffer/pixels invalid");
        if (eglSwapBuffers(display, surface)) recovered++;
        else REQUIRE(eglGetError() == EGL_BAD_ALLOC, "unexpected recovery EGL error");
    }
    REQUIRE(recovered == 32, "GTK did not release and recycle submitted buffers");

    (*env)->CallVoidMethod(env, activity, pause, 3);
    REQUIRE(!(*env)->ExceptionCheck(env) && wait_phase(3, 5000), "shutdown pause not started");
    for (int i = 0; i < 3; i++) {
        REQUIRE(green_drawable(), "shutdown framebuffer/pixels invalid");
        if (eglSwapBuffers(display, surface)) pending++;
        else REQUIRE(eglGetError() == EGL_BAD_ALLOC, "unexpected shutdown EGL error");
    }
    REQUIRE(pending > 0, "shutdown did not leave a submitted callback pending");

cleanup:
    if (surface != EGL_NO_SURFACE) eglDestroySurface(display, surface);
    if (current) eglMakeCurrent(display, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
    if (context != EGL_NO_CONTEXT) eglDestroyContext(display, context);
    if (window) ANativeWindow_release(window);
    if (!failure && !wait_phase(4, 5000)) failure = "shutdown pause did not resume";
    if (failure && !(*env)->ExceptionCheck(env)) {
        jclass assertion = (*env)->FindClass(env, "java/lang/AssertionError");
        if (assertion) (*env)->ThrowNew(env, assertion, failure);
    }
    (*env)->DeleteLocalRef(env, activity_type);
    return failure ? 0 : recovered;
#undef REQUIRE
}
