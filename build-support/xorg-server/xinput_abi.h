/* Native Xlib, POSIX signal and termios ABI bindings for the V input bridge. */
#ifndef VINIX_XINPUT_V_ABI_H
#define VINIX_XINPUT_V_ABI_H
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>
void *vxi_open_display(void);
void vxi_close_display(void *);
int vxi_xtest_available(void *);
void vxi_handlers(void);
int vxi_open_device(const char *);
int vxi_raw_keyboard(int);
void vxi_restore_keyboard(int);
void vxi_delay(void);
const char *vxi_error(void);
void vxi_error_text(void *, int, char *, int);
void vxi_key(void *, uint64_t, int);
void vxi_button(void *, unsigned int, int);
uint64_t vxi_pointer_child(void *);
void vxi_focus(void *, uint64_t);
void vxi_dimensions(void *, int *, int *);
void vxi_warp(void *, int, int);
void vxi_flush(void *);
int vxi_main(void);
void vxi_stop(int);
int vxi_report_error(void *, int, int, int);
#endif
