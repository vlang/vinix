/* Load Valve's unmodified client before Source 2 introduces overlapping
 * Coroutine_* and threading exports into the global lookup scope.
 * RTLD_LOCAL keeps the SDK's implementation private; RTLD_NOW resolves its
 * imports while the global Vinix libc compatibility preloads remain visible.
 */
extern char *getenv(const char *);
extern int unsetenv(const char *);
extern void *dlopen(const char *, int);
extern char *dlerror(void);
extern long write(int, const void *, unsigned long);
extern void _exit(int);

static void emit(const char *text)
{
    unsigned long length = 0;
    while (text[length])
        ++length;
    write(2, text, length);
}

__attribute__((constructor)) static void load_actual_client_before_game(void)
{
    const char *requested = getenv("VINIX_DOTA2_EARLY_STEAMCLIENT");
    if (!requested || !requested[0])
        return;

    /* getenv's storage belongs to libc. Copy it before consuming the marker,
     * so no environment pointer survives unsetenv or subsequent constructors.
     * Children inherit the small preload, but never repeat this client load.
     */
    char filename[4096];
    unsigned long length = 0;
    while (requested[length] && length < sizeof filename - 1) {
        filename[length] = requested[length];
        ++length;
    }
    filename[length] = 0;
    int too_long = requested[length] != 0;
    if (unsetenv("VINIX_DOTA2_EARLY_STEAMCLIENT") != 0 ||
        too_long || filename[0] != '/') {
        emit("dota2: invalid early Steam client path or environment\n");
        _exit(127);
    }

    /* Keep this deliberate process-lifetime reference. Later Steam API
     * dlmopen(BASE) reuses the same actual library; its dlclose cannot unload
     * libnm while GLib retains keys from libnm's static string storage.
     */
    if (!dlopen(filename, 2 | 0x1000)) { /* NOW | LOCAL | NODELETE */
        emit("dota2: could not load Steam's Linux client: ");
        const char *error = dlerror();
        emit(error ? error : "dlopen returned NULL without dlerror");
        emit("\n");
        _exit(127);
    }
    emit("VINIX-DOTA2-EARLY-CLIENT: loaded actual steamclient locally before main\n");
}
