// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// Host one Wine application on an off-screen Xvfb display. vinix-desktop maps
// Xvfb's XWD framebuffer into a normal compositor window and sends compact
// input records here; XTEST turns them back into ordinary X11 events.

#include <X11/Xlib.h>
#include <X11/keysym.h>
#include <X11/extensions/XTest.h>
#include <X11/extensions/Xdamage.h>

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/un.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#define WINE_HOST_EVENT_MAGIC UINT32_C(0x56574831) /* VWH1 */
#define WINE_HOST_MAX_KEYS 4096

enum wine_host_event_kind {
    WINE_HOST_MOTION = 1,
    WINE_HOST_BUTTON_DOWN,
    WINE_HOST_BUTTON_UP,
    WINE_HOST_KEYS,
};

struct wine_host_event {
    uint32_t magic;
    uint32_t kind;
    int32_t x;
    int32_t y;
    uint32_t length;
};

_Static_assert(sizeof(struct wine_host_event) == 20,
               "Wine host event ABI changed");

static volatile sig_atomic_t running = 1;

static void stop_running(int signal_number) {
    (void)signal_number;
    running = 0;
}

static int ignore_x_error(Display *display, XErrorEvent *event) {
    (void)display;
    (void)event;
    return 0;
}

static void sleep_10ms(void) {
    const struct timespec delay = { 0, 10000000 };
    nanosleep(&delay, NULL);
}

/* The desktop names each hosted display after the process that asked for it,
 * and a process id is released the moment that process exits — while the host
 * it started is still stopping its X server. Relaunching an application then
 * lands on a display number whose old server is alive, or whose lock file it
 * left behind names a process id that has since been reused, and Xvfb refuses
 * to start: "Server is already active for display N".
 *
 * So the number the desktop asks for is a starting point, not a promise. Take
 * the first display from there that nothing is serving and nothing holds, and
 * clear whatever a killed server left behind on it. */
static int display_number(const char *display_name) {
    const char *digit = display_name;
    int number = 0;

    while (*digit == ':')
        ++digit;
    if (*digit == '\0')
        return -1;
    for (; *digit != '\0'; ++digit) {
        if (*digit < '0' || *digit > '9')
            return -1;
        number = number * 10 + (*digit - '0');
        if (number > 65535)
            return -1;
    }
    return number;
}

/* Remove what a killed X server left on a display. Xvfb cleans these up when
 * it is asked to stop, but not when it has to be killed. */
static void remove_display_files(int number) {
    char path[64];

    if (number < 0)
        return;
    snprintf(path, sizeof(path), "/tmp/.X11-unix/X%d", number);
    unlink(path);
    snprintf(path, sizeof(path), "/tmp/.X%d-lock", number);
    unlink(path);
}

/* True when nothing answers on this display. A lock file whose server is gone
 * is removed on the way: its recorded process id is no help, because the id
 * has usually been handed to something unrelated by the time anyone looks. */
static int claim_display_number(int number) {
    char socket_path[64];
    struct sockaddr_un address;
    int probe;

    snprintf(socket_path, sizeof(socket_path), "/tmp/.X11-unix/X%d", number);
    memset(&address, 0, sizeof(address));
    address.sun_family = AF_UNIX;
    snprintf(address.sun_path, sizeof(address.sun_path), "%s", socket_path);

    probe = socket(AF_UNIX, SOCK_STREAM, 0);
    if (probe >= 0) {
        int connected = connect(probe, (struct sockaddr *)&address,
                                sizeof(address)) == 0;
        close(probe);
        if (connected)
            return 0; /* Somebody is serving this display. */
    }
    remove_display_files(number);
    return 1;
}

/* Fill `storage` with the display to use and return it, or NULL if every
 * candidate is busy. */
static const char *claim_display(const char *requested, char *storage,
                                 size_t size) {
    int base = display_number(requested);

    if (base < 0)
        return requested;
    for (int offset = 0; offset < 64; ++offset) {
        int number = base + offset;
        if (number > 65535)
            break;
        if (claim_display_number(number)) {
            snprintf(storage, size, ":%d", number);
            return storage;
        }
    }
    return NULL;
}

static pid_t spawn_xvfb(const char *display_name, const char *directory,
                        const char *geometry) {
    pid_t pid = fork();
    const char *xvfb;
    if (pid != 0)
        return pid;

    setenv("LD_LIBRARY_PATH", "/usr/lib:/usr/lib/xorg/modules", 1);
    setenv("LIBGL_ALWAYS_SOFTWARE", "1", 1);
    setenv("LIBGL_DRIVERS_PATH", "/usr/lib/xorg/modules/dri", 1);
    setenv("GALLIUM_DRIVER", "softpipe", 1);
    xvfb = access("/usr/bin/Xvfb-glx", X_OK) == 0
               ? "/usr/bin/Xvfb-glx" : "/usr/bin/Xvfb";
    /* Vinix does not provide SysV shared memory. Do not advertise MIT-SHM to
     * clients only to make every attachment fail with ENOSYS; ordinary X11
     * image transport is reliable for this private local display. */
    execl(xvfb, "Xvfb", display_name, "-screen", "0", geometry,
          "-fbdir", directory, "-nolisten", "tcp", "-noreset", "-ac",
          "-extension", "MIT-SHM", "+extension", "GLX", "+iglx",
          (char *)NULL);
    _exit(127);
}

static Display *open_display(const char *display_name, pid_t xvfb_pid) {
    int attempt;

    for (attempt = 0; attempt < 300 && running; ++attempt) {
        int status;
        Display *display = XOpenDisplay(display_name);
        if (display != NULL)
            return display;
        if (waitpid(xvfb_pid, &status, WNOHANG) == xvfb_pid)
            return NULL;
        sleep_10ms();
    }
    return NULL;
}

static pid_t spawn_wine(const char *display_name, const char *command) {
    pid_t pid = fork();
    if (pid != 0)
        return pid;

    setenv("DISPLAY", display_name, 1);
    setenv("LIBGL_ALWAYS_SOFTWARE", "1", 1);
    unsetenv("LIBGL_ALWAYS_INDIRECT");
    setenv("GALLIUM_DRIVER", "llvmpipe", 1);
    setenv("WINEDEBUG", "-all", 0);
    execl(command, command, (char *)NULL);
    _exit(127);
}

static void fake_key(Display *display, KeySym symbol, Bool pressed) {
    KeyCode code = XKeysymToKeycode(display, symbol);
    if (code != 0)
        XTestFakeKeyEvent(display, code, pressed, CurrentTime);
}

static void tap_key(Display *display, KeySym symbol, int shift, int control) {
    if (control)
        fake_key(display, XK_Control_L, True);
    if (shift)
        fake_key(display, XK_Shift_L, True);
    fake_key(display, symbol, True);
    fake_key(display, symbol, False);
    if (shift)
        fake_key(display, XK_Shift_L, False);
    if (control)
        fake_key(display, XK_Control_L, False);
}

static void type_ascii(Display *display, unsigned char byte) {
    static const char shifted[] = "!@#$%^&*()_+{}|:\"~<>?";
    static const char bases[] = "1234567890-=[]\\;'\x60,./";
    const char *position;

    if (byte >= 1 && byte <= 26) {
        tap_key(display, (KeySym)('a' + byte - 1), 0, 1);
        return;
    }
    if (byte == '\n' || byte == '\r') {
        tap_key(display, XK_Return, 0, 0);
        return;
    }
    if (byte == '\t') {
        tap_key(display, XK_Tab, 0, 0);
        return;
    }
    if (byte == '\b' || byte == 0x7f) {
        tap_key(display, XK_BackSpace, 0, 0);
        return;
    }
    if (byte >= 'A' && byte <= 'Z') {
        tap_key(display, (KeySym)(byte - 'A' + 'a'), 1, 0);
        return;
    }
    position = strchr(shifted, byte);
    if (position != NULL) {
        tap_key(display, (KeySym)bases[position - shifted], 1, 0);
        return;
    }
    if (byte >= 0x20 && byte <= 0x7e)
        tap_key(display, (KeySym)byte, 0, 0);
}

static void send_keys(Display *display, const unsigned char *keys,
                      size_t length) {
    size_t index = 0;

    while (index < length) {
        if (keys[index] == 0x1b && index + 2 < length &&
            keys[index + 1] == '[') {
            KeySym symbol = NoSymbol;
            switch (keys[index + 2]) {
            case 'A': symbol = XK_Up; break;
            case 'B': symbol = XK_Down; break;
            case 'C': symbol = XK_Right; break;
            case 'D': symbol = XK_Left; break;
            case 'H': symbol = XK_Home; break;
            case 'F': symbol = XK_End; break;
            default: break;
            }
            if (symbol != NoSymbol) {
                tap_key(display, symbol, 0, 0);
                index += 3;
                continue;
            }
            if (keys[index + 2] == '3' && index + 3 < length &&
                keys[index + 3] == '~') {
                tap_key(display, XK_Delete, 0, 0);
                index += 4;
                continue;
            }
        }
        if (keys[index] == 0x1b)
            tap_key(display, XK_Escape, 0, 0);
        else
            type_ascii(display, keys[index]);
        ++index;
    }
}

static void focus_pointer_window(Display *display) {
    Window root = DefaultRootWindow(display);
    Window root_return;
    Window child_return;
    int root_x;
    int root_y;
    int window_x;
    int window_y;
    unsigned int mask;

    if (XQueryPointer(display, root, &root_return, &child_return, &root_x,
                      &root_y, &window_x, &window_y, &mask) &&
        child_return != None)
        XSetInputFocus(display, child_return, RevertToPointerRoot, CurrentTime);
}

static Window topmost_substantial_child(Display *display, Window parent) {
    Window root_return;
    Window parent_return;
    Window *children = NULL;
    unsigned int count = 0;
    unsigned int index;
    Window result = None;

    if (!XQueryTree(display, parent, &root_return, &parent_return, &children,
                    &count))
        return None;
    for (index = count; index > 0; --index) {
        XWindowAttributes attributes;
        Window candidate = children[index - 1];
        if (XGetWindowAttributes(display, candidate, &attributes) &&
            attributes.map_state == IsViewable &&
            attributes.class == InputOutput && attributes.width >= 32 &&
            attributes.height >= 32 &&
            attributes.width <= DisplayWidth(display, DefaultScreen(display)) * 2 &&
            attributes.height <= DisplayHeight(display, DefaultScreen(display)) * 2) {
            result = candidate;
            break;
        }
    }
    if (children != NULL)
        XFree(children);
    return result;
}

static Window topmost_input_window(Display *display, Window parent) {
    Window candidate = topmost_substantial_child(display, parent);
    Window descendant;

    if (candidate == None)
        return None;
    descendant = topmost_input_window(display, candidate);
    return descendant == None ? candidate : descendant;
}

static void focus_top_window(Display *display) {
    Window root = DefaultRootWindow(display);
    Window target;

    /* Xvfb has no window manager to assign keyboard focus. Wine nests its
     * application windows and dialogs below Explorer's virtual-desktop root
     * child. Tiny IME, device and decoration windows can sit above them; they
     * must not receive focus. Descend through substantial input/output
     * children until the real application control or modal dialog is reached.
     */
    target = topmost_input_window(display, root);
    if (target != None)
        XSetInputFocus(display, target, RevertToPointerRoot, CurrentTime);
}

static int process_event(Display *display, const struct wine_host_event *event,
                         const unsigned char *payload) {
    switch (event->kind) {
    case WINE_HOST_MOTION:
        XWarpPointer(display, None, DefaultRootWindow(display), 0, 0, 0, 0,
                     event->x, event->y);
        break;
    case WINE_HOST_BUTTON_DOWN:
        focus_pointer_window(display);
        XTestFakeButtonEvent(display, 1, True, CurrentTime);
        break;
    case WINE_HOST_BUTTON_UP:
        XTestFakeButtonEvent(display, 1, False, CurrentTime);
        break;
    case WINE_HOST_KEYS:
        focus_top_window(display);
        send_keys(display, payload, event->length);
        break;
    default:
        return 0;
    }
    XFlush(display);
    return 1;
}

/* The compositor cannot see when Xvfb touched its shared framebuffer: the
 * application draws straight into the mapping, so neither its size nor its
 * timestamps move. Left to guess, vinix-desktop rescales the whole surface
 * twenty times a second whether or not anything changed, and on an emulated
 * core that starves the very browser it is displaying.
 *
 * So report drawing as it happens. A counter file next to the framebuffer
 * carries the damage sequence; the desktop blits only when it advances. */
/* The counter is shared the same way the framebuffer is — through the file's
 * pages — so that publishing costs a store and reading it costs a load. The
 * desktop polls this twenty times a second while the machine is busy paging a
 * browser in; a read() there would queue behind that. */
static volatile uint32_t *map_damage_counter(const char *directory) {
    char path[PATH_MAX];
    void *mapping;
    int fd;

    if (snprintf(path, sizeof(path), "%s/damage", directory) >= (int)sizeof(path))
        return NULL;
    fd = open(path, O_RDWR | O_CREAT | O_TRUNC, 0600);
    if (fd < 0)
        return NULL;
    if (ftruncate(fd, (off_t)sizeof(uint32_t)) != 0) {
        close(fd);
        return NULL;
    }
    mapping = mmap(NULL, sizeof(uint32_t), PROT_READ | PROT_WRITE, MAP_SHARED,
                   fd, 0);
    close(fd);
    if (mapping == MAP_FAILED)
        return NULL;
    return mapping;
}

/* Xvfb has no compositing, so every window draws into the root's own pixmap
 * and damage on the root covers the whole session. Report only that the
 * screen changed: the desktop rescales the entire surface anyway. */
static Damage watch_root_damage(Display *display, int *event_base) {
    int error_base;
    int major;
    int minor;

    if (!XDamageQueryExtension(display, event_base, &error_base))
        return None;
    if (!XDamageQueryVersion(display, &major, &minor))
        return None;
    return XDamageCreate(display, DefaultRootWindow(display),
                         XDamageReportNonEmpty);
}

static void stop_child(pid_t pid) {
    int status;
    int attempt;

    if (pid <= 0 || waitpid(pid, &status, WNOHANG) == pid)
        return;
    kill(pid, SIGTERM);
    for (attempt = 0; attempt < 100; ++attempt) {
        if (waitpid(pid, &status, WNOHANG) == pid)
            return;
        sleep_10ms();
    }
    kill(pid, SIGKILL);
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR)
        ;
}

int main(int argc, char **argv) {
    struct sigaction action;
    unsigned char input[8192];
    size_t used = 0;
    const char *display_name;
    char chosen_display[16];
    const char *directory;
    const char *geometry;
    const char *command;
    Display *display;
    pid_t xvfb_pid;
    pid_t wine_pid = -1;
    int stdin_flags;
    int status;
    int xtest_event_base;
    int xtest_error_base;
    int xtest_major;
    int xtest_minor;
    int damage_event_base = 0;
    volatile uint32_t *damage_counter = NULL;
    uint32_t damage_sequence = 0;
    Damage damage;

    if (argc != 5) {
        fprintf(stderr, "usage: %s DISPLAY FBDIR GEOMETRY COMMAND\n", argv[0]);
        return 2;
    }
    display_name = argv[1];
    directory = argv[2];
    geometry = argv[3];
    command = argv[4];

    memset(&action, 0, sizeof(action));
    action.sa_handler = stop_running;
    sigemptyset(&action.sa_mask);
    sigaction(SIGHUP, &action, NULL);
    sigaction(SIGINT, &action, NULL);
    sigaction(SIGTERM, &action, NULL);

    if (mkdir(directory, 0700) != 0 && errno != EEXIST) {
        perror("vinix-wine-host: mkdir");
        return 1;
    }
    display_name = claim_display(display_name, chosen_display,
                                 sizeof(chosen_display));
    if (display_name == NULL) {
        fprintf(stderr, "vinix-wine-host: no free display near %s\n", argv[1]);
        rmdir(directory);
        return 1;
    }
    xvfb_pid = spawn_xvfb(display_name, directory, geometry);
    if (xvfb_pid < 0) {
        perror("vinix-wine-host: fork Xvfb");
        rmdir(directory);
        return 1;
    }
    display = open_display(display_name, xvfb_pid);
    if (display == NULL) {
        fprintf(stderr, "vinix-wine-host: Xvfb did not become ready\n");
        stop_child(xvfb_pid);
        rmdir(directory);
        return 1;
    }
    XSetErrorHandler(ignore_x_error);
    if (!XTestQueryExtension(display, &xtest_event_base, &xtest_error_base,
                             &xtest_major, &xtest_minor)) {
        fprintf(stderr, "vinix-wine-host: XTEST extension is unavailable\n");
        XCloseDisplay(display);
        stop_child(xvfb_pid);
        rmdir(directory);
        return 1;
    }

    // A Windows program that chooses a smaller initial size gets a neutral
    // Vinix-like surface around it, never the opaque black X root window.
    XSetWindowBackground(display, DefaultRootWindow(display), 0xf3f4f6);
    XClearWindow(display, DefaultRootWindow(display));
    XFlush(display);

    damage = watch_root_damage(display, &damage_event_base);
    if (damage != None) {
        damage_counter = map_damage_counter(directory);
        if (damage_counter == NULL) {
            XDamageDestroy(display, damage);
            damage = None;
        } else {
            /* The first frame is the one the desktop is waiting for. */
            *damage_counter = ++damage_sequence;
        }
    }

    wine_pid = spawn_wine(display_name, command);
    if (wine_pid < 0) {
        perror("vinix-wine-host: fork Wine");
        running = 0;
    }

    stdin_flags = fcntl(STDIN_FILENO, F_GETFL);
    if (stdin_flags >= 0)
        fcntl(STDIN_FILENO, F_SETFL, stdin_flags | O_NONBLOCK);

    while (running) {
        ssize_t count = read(STDIN_FILENO, input + used, sizeof(input) - used);
        if (count > 0)
            used += (size_t)count;
        else if (count == 0)
            running = 0;
        else if (errno != EAGAIN && errno != EWOULDBLOCK && errno != EINTR)
            running = 0;

        while (used >= sizeof(struct wine_host_event)) {
            struct wine_host_event event;
            size_t record_size;
            memcpy(&event, input, sizeof(event));
            if (event.magic != WINE_HOST_EVENT_MAGIC ||
                event.length > WINE_HOST_MAX_KEYS ||
                (event.kind != WINE_HOST_KEYS && event.length != 0)) {
                running = 0;
                break;
            }
            record_size = sizeof(event) + event.length;
            if (used < record_size)
                break;
            process_event(display, &event, input + sizeof(event));
            memmove(input, input + record_size, used - record_size);
            used -= record_size;
        }
        if (used == sizeof(input))
            running = 0;

        if (damage != None) {
            int drawn = 0;
            /* XDamageReportNonEmpty stays quiet until the region is taken
             * back, so one subtract per pass is enough however much was
             * drawn in it. */
            while (XPending(display) > 0) {
                XEvent event;
                XNextEvent(display, &event);
                if (event.type == damage_event_base + XDamageNotify)
                    drawn = 1;
            }
            if (drawn) {
                XDamageSubtract(display, damage, None, None);
                XFlush(display);
                *damage_counter = ++damage_sequence;
            }
        }

        if (wine_pid > 0 && waitpid(wine_pid, &status, WNOHANG) == wine_pid) {
            wine_pid = -1;
            running = 0;
        }
        sleep_10ms();
    }

    stop_child(wine_pid);
    if (damage_counter != NULL)
        munmap((void *)damage_counter, sizeof(uint32_t));
    XCloseDisplay(display);
    stop_child(xvfb_pid);
    /* Xvfb removes these when it is asked to stop, but not when it has to be
     * killed. Leave nothing behind for the next server on this number. */
    remove_display_files(display_number(display_name));
    rmdir(directory);
    return 0;
}
