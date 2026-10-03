/* Unit test: compile the production dispatcher unchanged with checked JNI doubles. */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#ifndef ATL_ACTIVITY_DISPATCHER_FILE
#error Set ATL_ACTIVITY_DISPATCHER_FILE to the actual patched production C file
#endif
#include ATL_ACTIVITY_DISPATCHER_FILE

struct handle_cache handle_cache;
GtkWindow *window;
struct model {
    int id, finishing, paused, destroyed;
    int creates, starts, resumes, post_resumes, pauses, stops, destroys;
};
struct reference { struct model *object; int live, pin, global; };
static struct reference references[2048];
static size_t used;
static int pins, pending, scenario, ran;
static int describes, local_calls, fail_local_at, fail_method;
static struct model *secondary;
static JNIEnv fixture_env;
static jobject make_ref(struct model *object, int pin) {
    assert(used < sizeof references / sizeof references[0]);
    struct reference *r = &references[used++];
    *r = (struct reference){ .object = object, .live = 1, .pin = pin, .global = !pin };
    pins += pin;
    return (jobject)r;
}
static struct model *checked(jobject object) {
    assert(!pending);
    assert(object && ((struct reference *)object)->live);
    return ((struct reference *)object)->object;
}
static jboolean exception_check(JNIEnv *env) { (void)env; return pending; }
/* Models JNI's specified print-and-clear behavior. The pinned ART restores its
   pending exception after printing; describes == 0 rejects logging in either VM. */
static void exception_describe(JNIEnv *env) { (void)env; assert(pending); describes++; pending = 0; }
static jobject new_local(JNIEnv *env, jobject object) {
    (void)env; struct model *m = checked(object);
    if (++local_calls == fail_local_at) { pending = 1; return NULL; }
    return make_ref(m, 1);
}
static jobject new_global(JNIEnv *env, jobject object) { (void)env; return make_ref(checked(object), 0); }
static void delete_ref(JNIEnv *env, jobject object) {
    (void)env;
    struct reference *r = (struct reference *)object;
    assert(r && r->live);
    r->live = 0;
    pins -= r->pin;
}
static void delete_local(JNIEnv *env, jobject object) {
    assert(!((struct reference *)object)->global); delete_ref(env, object);
}
static void delete_global(JNIEnv *env, jobject object) {
    assert(((struct reference *)object)->global); delete_ref(env, object);
}
static jclass get_class(JNIEnv *env, jobject object) {
    (void)env; checked(object);
    struct reference *r = (struct reference *)make_ref(NULL, 0);
    r->global = 0;
    return (jclass)r;
}
static jfieldID get_field(JNIEnv *env, jclass clazz, const char *name, const char *type) {
    (void)env; checked((jobject)clazz); assert(!strcmp(type, "Z"));
    if (!strcmp(name, "finishing")) return (jfieldID)(uintptr_t)1;
    if (!strcmp(name, "paused")) return (jfieldID)(uintptr_t)2;
    if (!strcmp(name, "destroyed")) return (jfieldID)(uintptr_t)3;
    assert(!"unexpected field"); return NULL;
}
static jboolean get_boolean(JNIEnv *env, jobject object, jfieldID field) {
    (void)env; struct model *m = checked(object);
    if ((uintptr_t)field == 1) return m->finishing;
    if ((uintptr_t)field == 2) return m->paused;
    if ((uintptr_t)field == 3) return m->destroyed;
    assert(!"unexpected field id"); return 0;
}
static jmethodID get_method(JNIEnv *env, jclass clazz, const char *name, const char *descriptor) {
    (void)env; checked((jobject)clazz); assert(!strcmp(name, "onBackPressed") && !strcmp(descriptor, "()V"));
    if (fail_method) { pending = 1; return NULL; }
    return handle_cache.activity.onBackPressed;
}
static jboolean same_object(JNIEnv *env, jobject a, jobject b) { (void)env; return checked(a) == checked(b); }
static void call_void(JNIEnv *env, jobject object, jmethodID method, ...) {
    struct model *m = checked(object);
    uintptr_t id = (uintptr_t)method;
    if (id == 1) m->creates++;
    if (id == 2) {
        m->starts++;
        if (!ran && m->id == 1 && (scenario == 1 || scenario == 2 || scenario == 4)) {
            ran = 1;
            if (scenario == 1) {
                m->finishing = 1;
                Java_android_app_Activity_nativeFinish(env, object, 0);
            } else if (scenario == 2) pending = 1;
            else {
                jobject next = make_ref(secondary, 0);
                activity_start(env, next);
                delete_ref(env, next);
            }
        }
    }
    if (id == 3) m->resumes++;
    if (id == 4) m->post_resumes++;
    if (id == 5) {
        m->pauses++; m->paused = 1;
        if (!ran && m->id == 1 && (scenario == 3 || scenario == 5)) {
            ran = 1;
            if (scenario == 5) {
                m->finishing = 1;
                Java_android_app_Activity_nativeFinish(env, object, 0);
            } else {
                jobject next = make_ref(secondary, 0);
                activity_start(env, next);
                delete_ref(env, next);
            }
        }
    }
    if (id == 6) m->stops++;
    if (id == 7) { m->destroys++; m->destroyed = 1; }
}
static const struct JNINativeInterface_ table = {
    .ExceptionCheck = exception_check, .ExceptionDescribe = exception_describe,
    .NewLocalRef = new_local, .NewGlobalRef = new_global,
    .DeleteLocalRef = delete_local, .DeleteGlobalRef = delete_global,
    .GetObjectClass = get_class, .GetFieldID = get_field,
    .GetBooleanField = get_boolean, .GetMethodID = get_method,
    .IsSameObject = same_object, .CallVoidMethod = call_void,
};
JNIEnv *get_jni_env(void) { return &fixture_env; }
void back_button_set_sensitive(bool sensitive) { (void)sensitive; }

static void reset(int kind) {
    /* Explicit dispatcher pins must be released; JNI frame class locals are
       released by the VM at native return and are not counted as pins. */
    assert(pins == 0);
    for (GList *l = activity_backlog; l; l = l->next) delete_global(&fixture_env, l->data);
    g_list_free(activity_backlog);
    for (size_t i = 0; i < used; i++) assert(!references[i].live || !references[i].global);
    activity_backlog = NULL; activity_current = NULL; activity_revision = 0;
    used = 0; pending = 0; scenario = kind; ran = 0;
    describes = 0; local_calls = 0; fail_local_at = 0; fail_method = 0;
    fixture_env = &table;
    handle_cache.activity.onCreate = (jmethodID)(uintptr_t)1;
    handle_cache.activity.onStart = (jmethodID)(uintptr_t)2;
    handle_cache.activity.onResume = (jmethodID)(uintptr_t)3;
    handle_cache.activity.onPostResume = (jmethodID)(uintptr_t)4;
    handle_cache.activity.onPause = (jmethodID)(uintptr_t)5;
    handle_cache.activity.onStop = (jmethodID)(uintptr_t)6;
    handle_cache.activity.onDestroy = (jmethodID)(uintptr_t)7;
    handle_cache.activity.onWindowFocusChanged = (jmethodID)(uintptr_t)8;
    handle_cache.activity.onBackPressed = (jmethodID)(uintptr_t)9;
}
static void head(struct model *m) {
    activity_backlog = g_list_prepend(activity_backlog, make_ref(m, 0)); activity_revision++;
}
int main(void) {
    reset(1);
    struct model a = { .id = 1 };
    struct model b = { .id = 2 }, c = { .id = 3 };
    head(&a); activity_update_current(&fixture_env);
    assert(a.starts == 1 && a.resumes == 0 && a.destroys == 1 && !activity_current && !pending && pins == 0);

    reset(2); a = (struct model){ .id = 1 };
    head(&a); activity_update_current(&fixture_env);
    assert(pending && a.starts == 1 && a.resumes == 0 && pins == 0 && describes == 0);
    /* Entry guard must preserve the exception without performing another JNI query. */
    activity_update_current(&fixture_env); assert(pending && pins == 0 && describes == 0);

    reset(5); a = (struct model){ .id = 1 }; b = (struct model){ .id = 2 };
    head(&a); activity_current = activity_backlog->data;
    jobject previous_global = activity_current;
    head(&b); activity_update_current(&fixture_env);
    /* onPause removes the backlog global while activity_unfocus still reads its
       destroyed field: only the previous local pin can keep that handle valid. */
    assert(!((struct reference *)previous_global)->live && checked(activity_current) == &b);
    assert(a.pauses == 1 && a.destroys == 1 && a.stops == 0 && b.starts == 1 && b.resumes == 1 && pins == 0);

    reset(3); a = (struct model){ .id = 1 };
    b = (struct model){ .id = 2 }; c = (struct model){ .id = 3 };
    head(&a); activity_current = activity_backlog->data; head(&b); secondary = &c;
    activity_update_current(&fixture_env);
    assert(checked(activity_current) == &c && a.pauses == 1 && a.stops == 1 && b.starts == 0 && c.resumes == 1 && pins == 0);

    reset(4); a = (struct model){ .id = 1 }; c = (struct model){ .id = 3 };
    head(&a); secondary = &c; activity_update_current(&fixture_env);
    assert(checked(activity_current) == &c && a.starts == 1 && a.resumes == 0 && a.post_resumes == 0 && c.resumes == 1 && pins == 0);
    reset(0); a = (struct model){ .id = 1 }; b = (struct model){ .id = 2 };
    head(&a); activity_current = activity_backlog->data; head(&b); fail_local_at = 1;
    activity_update_current(&fixture_env);
    assert(pending && pins == 0 && a.pauses == 0 && b.starts == 0);

    reset(0); a = (struct model){ .id = 1 }; b = (struct model){ .id = 2 };
    head(&a); activity_current = activity_backlog->data; head(&b); fail_local_at = 2;
    activity_update_current(&fixture_env);
    assert(pending && pins == 0 && a.pauses == 0 && b.starts == 0);

    reset(0); a = (struct model){ .id = 1 }; head(&a); fail_method = 1;
    activity_update_current(&fixture_env);
    assert(pending && pins == 0 && a.resumes == 1 && !references[used - 1].live);
    reset(0);
    printf("ATL-ACTIVITY-DISPATCH-PASS finish=local-pin pause-finish=local-pin exceptions=preserved epochs=reentrant ref-failures=clean pins=0\n");
    return 0;
}
