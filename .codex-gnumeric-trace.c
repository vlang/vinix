typedef void (*void_function)(void);
typedef void (*one_pointer_function)(void *);
typedef void *(*workbook_function)(int);
typedef void *(*wbc_function)(void *, void *, void *, const char *);

extern void *dlsym(void *handle, const char *name);
extern long write(int fd, const void *buffer, unsigned long count);

#define NEXT ((void *)-1)
#define LOG(message) write(2, message, sizeof(message) - 1)

__attribute__((constructor)) static void trace_loaded(void) {
    LOG("TRACE preload loaded\n");
}

void gtk_init(int *argc, char ***argv) {
    static void (*real)(int *, char ***);
    if (!real) real = dlsym(NEXT, "gtk_init");
    LOG("TRACE gtk_init begin\n");
    real(argc, argv);
    LOG("TRACE gtk_init end\n");
}

void gnm_session_init(const char *argv0) {
    static void (*real)(const char *);
    if (!real) real = dlsym(NEXT, "gnm_session_init");
    LOG("TRACE gnm_session_init begin\n");
    real(argv0);
    LOG("TRACE gnm_session_init end\n");
}

void gnm_init(void) {
    static void_function real;
    if (!real) real = dlsym(NEXT, "gnm_init");
    LOG("TRACE gnm_init begin\n");
    real();
    LOG("TRACE gnm_init end\n");
}

void gnm_plugins_init(void *context) {
    static one_pointer_function real;
    if (!real) real = dlsym(NEXT, "gnm_plugins_init");
    LOG("TRACE gnm_plugins_init begin\n");
    real(context);
    LOG("TRACE gnm_plugins_init end\n");
}

void *workbook_new_with_sheets(int sheets) {
    static workbook_function real;
    if (!real) real = dlsym(NEXT, "workbook_new_with_sheets");
    LOG("TRACE workbook_new_with_sheets begin\n");
    void *result = real(sheets);
    LOG("TRACE workbook_new_with_sheets end\n");
    return result;
}

void *wbc_gtk_new(void *view, void *workbook, void *existing, const char *geometry) {
    static wbc_function real;
    if (!real) real = dlsym(NEXT, "wbc_gtk_new");
    LOG("TRACE wbc_gtk_new begin\n");
    void *result = real(view, workbook, existing, geometry);
    LOG("TRACE wbc_gtk_new end\n");
    return result;
}

void gtk_main(void) {
    static void_function real;
    if (!real) real = dlsym(NEXT, "gtk_main");
    LOG("TRACE gtk_main begin\n");
    real();
    LOG("TRACE gtk_main end\n");
}
