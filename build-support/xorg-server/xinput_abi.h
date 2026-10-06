/* Native Xlib, POSIX signal and termios ABI bindings for the V input bridge. */
#ifndef VINIX_XINPUT_V_ABI_H
#define VINIX_XINPUT_V_ABI_H
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include <X11/Xlib.h>
#include <X11/extensions/XTest.h>
#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <termios.h>
#include <time.h>
typedef struct sigaction vxi_sigaction;
typedef const char *vxi_const_char_p;
_Static_assert(sizeof(sig_atomic_t) == sizeof(int32_t), "V signal state width");
_Static_assert(__atomic_always_lock_free(sizeof(int32_t), 0), "signal atomics are lock free");
#ifdef VINIX_XINPUT_V_RUNTIME
#define VINIX_XINPUT_WORD u64
#else
#define VINIX_XINPUT_WORD uint64_t
#endif
void *vxi_open_display(void);
void vxi_close_display(void *);
int vxi_xtest_available(void *);
void vxi_handlers(void);
#ifndef VINIX_XINPUT_V_RUNTIME
int vxi_open_device(const char *);
#endif
int vxi_raw_keyboard(int);
void vxi_restore_keyboard(int);
void vxi_delay(void);
#ifndef VINIX_XINPUT_V_RUNTIME
const char *vxi_error(void);
#endif
void vxi_error_text(void *, int, char *, int);
void vxi_key(void *, VINIX_XINPUT_WORD, int);
void vxi_button(void *, unsigned int, int);
VINIX_XINPUT_WORD vxi_pointer_child(void *);
void vxi_focus(void *, VINIX_XINPUT_WORD);
void vxi_dimensions(void *, int *, int *);
void vxi_warp(void *, int, int);
void vxi_flush(void *);
int vxi_main(void);
void vxi_stop(int);
int vxi_report_error(void *, int, int, int);
void vinix_xinput_stop_callback(int);
int vinix_xinput_error_callback(Display *, XErrorEvent *);
#undef VINIX_XINPUT_WORD
#endif
