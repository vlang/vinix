/* Test-only preload: stop GTK examples at deterministic Xorg/UI boundaries. */
typedef void (*present_function)(void *);
typedef int (*xmap_window_function)(void *, unsigned long);
typedef void *(*builder_from_resource_function)(const char *);

extern void *dlsym(void *handle, const char *name);
extern char *getenv(const char *name);
extern void *gdk_display_get_default(void);
extern void gdk_display_sync(void *display);
extern void *gtk_widget_get_toplevel(void *widget);
extern void *gtk_widget_get_window(void *widget);
extern int XSync(void *display, int discard);

__attribute__((noreturn)) static void exit_success(void) {
    register long status asm("x0") = 0;
    register long syscall_number asm("x8") = 94; /* Linux aarch64 exit_group */
    asm volatile("svc #0"
                 : "+r"(status)
                 : "r"(syscall_number)
                 : "memory");
    __builtin_unreachable();
}

static void sync_and_exit(void) {
    void *display = gdk_display_get_default();
    if (display) {
        gdk_display_sync(display);
        exit_success();
    }
}

void gtk_window_present(void *window) {
    static present_function present;
    if (!present)
        present = (present_function)dlsym((void *)-1, "gtk_window_present");
    if (!present)
        return;

    present(window);
    sync_and_exit();
}

void gtk_widget_show_all(void *widget) {
    static present_function show_all;
    if (!show_all)
        show_all = (present_function)dlsym((void *)-1, "gtk_widget_show_all");
    if (!show_all)
        return;

    show_all(widget);
    sync_and_exit();
}

void gtk_widget_show(void *widget) {
    static present_function show;
    if (!show)
        show = (present_function)dlsym((void *)-1, "gtk_widget_show");
    if (!show)
        return;

    show(widget);
    void *toplevel = gtk_widget_get_toplevel(widget);
    if (toplevel && gtk_widget_get_window(toplevel))
        sync_and_exit();
}

int XMapWindow(void *display, unsigned long window) {
    static xmap_window_function map_window;
    if (!map_window)
        map_window = (xmap_window_function)dlsym((void *)-1, "XMapWindow");
    if (!map_window)
        return 0;

    map_window(display, window);
    XSync(display, 0);
    exit_success();
}

void *gtk_builder_new_from_resource(const char *resource_path) {
    static builder_from_resource_function builder_from_resource;
    if (!builder_from_resource)
        builder_from_resource = (builder_from_resource_function)dlsym(
            (void *)-1, "gtk_builder_new_from_resource");
    if (!builder_from_resource)
        return (void *)0;

    char *builder_boundary = getenv("VINIX_GTK_SMOKE_BUILDER_BOUNDARY");
    if (builder_boundary && builder_boundary[0] == '1') {
        /* The widget factory's large embedded UI currently monopolises Vinix's
           single QEMU CPU inside this call. Reaching it with a live X display
           is the deterministic integration boundary for that example. */
        sync_and_exit();
    }
    return builder_from_resource(resource_path);
}
