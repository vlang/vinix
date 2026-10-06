// SPDX-License-Identifier: GPL-2.0-or-later
// Native Xlib/POSIX field access preserves the original input bridge ABI.
@[translated]
module xinputcore

#include "xinput_abi.h"

@[typedef]
struct C.Display {}
@[typedef]
struct C.XErrorEvent { error_code u8 request_code u8 minor_code u8 }
@[typedef]
struct C.sigset_t {}
type SignalHandler = fn (i32)
type ErrorHandler = fn (&C.Display, &C.XErrorEvent) i32
@[typedef]
struct C.vxi_sigaction { mut: sa_handler SignalHandler sa_mask C.sigset_t }
// SDK declarations own the actual tcflag_t width; assignments convert values
// without taking a pointer to a field of a different width.
struct C.termios { mut: c_iflag usize c_oflag usize c_cflag usize c_lflag usize c_cc [32]u8 }
struct C.timespec { tv_sec isize tv_nsec isize }
fn C.vinix_xinput_stop_callback(i32)
fn C.vinix_xinput_error_callback(&C.Display, &C.XErrorEvent) i32
fn C.sigemptyset(&C.sigset_t) i32
fn C.sigaction(i32, &C.vxi_sigaction, &C.vxi_sigaction) i32
fn C.XOpenDisplay(voidptr) voidptr
fn C.XCloseDisplay(voidptr) i32
fn C.XSetErrorHandler(ErrorHandler) ErrorHandler
fn C.XTestQueryExtension(voidptr, &i32, &i32, &i32, &i32) i32
fn C.open(&char, i32, ...voidptr) i32
fn C.tcgetattr(i32, &C.termios) i32
fn C.tcsetattr(i32, i32, &C.termios) i32
fn C.nanosleep(&C.timespec, &C.timespec) i32
fn C.strerror(i32) &char
fn C.XGetErrorText(voidptr, i32, &char, i32) i32
fn C.XKeysymToKeycode(voidptr, u64) u8
fn C.XTestFakeKeyEvent(voidptr, u32, i32, u64) i32
fn C.XTestFakeButtonEvent(voidptr, u32, i32, u64) i32
fn C.XQueryPointer(voidptr, u64, &usize, &usize, &i32, &i32, &i32, &i32, &u32) i32
fn C.DefaultRootWindow(voidptr) u64
fn C.XSetInputFocus(voidptr, u64, i32, u64) i32
fn C.DefaultScreen(voidptr) i32
fn C.DisplayWidth(voidptr, i32) i32
fn C.DisplayHeight(voidptr, i32) i32
fn C.XWarpPointer(voidptr, u64, u64, i32, i32, u32, u32, i32, i32) i32
fn C.XFlush(voidptr) i32
fn C.vxi_main() i32
@[c_extern] __global C.errno i32

__global saved_termios C.termios
__global restore_termios i32

@[export: 'vinix_xinput_stop_callback']
pub fn stop_callback(number i32) { stop(number) }
@[export: 'vinix_xinput_error_callback']
pub fn error_callback(display &C.Display, event &C.XErrorEvent) i32 {
    return report_error(voidptr(display), i32(event.error_code), i32(event.request_code), i32(event.minor_code))
}
@[export: 'vxi_handlers']
pub fn native_handlers() {
    unsafe {
        mut action := C.vxi_sigaction{sa_handler: C.vinix_xinput_stop_callback}
        C.sigemptyset(&action.sa_mask)
        C.sigaction(C.SIGHUP, &action, nil)
        C.sigaction(C.SIGINT, &action, nil)
        C.sigaction(C.SIGTERM, &action, nil)
    }
}
@[export: 'vxi_open_display']
pub fn native_open_display() voidptr { return C.XOpenDisplay(unsafe { nil }) }
@[export: 'vxi_close_display']
pub fn native_close_display(display voidptr) { C.XCloseDisplay(display) }
@[export: 'vxi_xtest_available']
pub fn native_xtest(display voidptr) i32 {
    unsafe {
        mut event := i32(0); mut error := i32(0); mut major := i32(0); mut minor := i32(0)
        C.XSetErrorHandler(C.vinix_xinput_error_callback)
        return C.XTestQueryExtension(display, &event, &error, &major, &minor)
    }
}
@[export: 'vxi_open_device']
pub fn native_open_device(path &char) i32 { return C.open(path, C.O_RDONLY | C.O_NONBLOCK) }
@[export: 'vxi_raw_keyboard']
pub fn native_raw_keyboard(fd i32) i32 {
    unsafe {
        if fd < 0 { return 0 }
        if C.tcgetattr(fd, &saved_termios) == 0 {
            mut raw := saved_termios
            raw.c_iflag = usize(raw.c_iflag) & ~usize(C.BRKINT | C.ICRNL | C.INPCK | C.ISTRIP | C.IXON)
            raw.c_oflag = usize(raw.c_oflag) & ~usize(C.OPOST)
            raw.c_cflag = usize(raw.c_cflag) | usize(C.CS8)
            raw.c_lflag = usize(raw.c_lflag) & ~usize(C.ECHO | C.ICANON | C.IEXTEN | C.ISIG)
            raw.c_cc[C.VMIN] = 0
            raw.c_cc[C.VTIME] = 0
            if C.tcsetattr(fd, C.TCSANOW, &raw) == 0 { restore_termios = 1 }
        }
        return restore_termios
    }
}
@[export: 'vxi_restore_keyboard']
pub fn native_restore_keyboard(fd i32) { unsafe { if restore_termios != 0 { C.tcsetattr(fd, C.TCSANOW, &saved_termios) } } }
@[export: 'vxi_delay']
pub fn native_delay() { unsafe { delay := C.timespec{tv_sec: 0, tv_nsec: 10000000}; C.nanosleep(&delay, nil) } }
@[export: 'vxi_error']
pub fn native_error() &char { return C.strerror(i32(C.errno)) }
@[export: 'vxi_error_text']
pub fn native_error_text(display voidptr, code i32, output &char, capacity i32) { C.XGetErrorText(display, code, output, capacity) }
@[export: 'vxi_key']
pub fn native_key(display voidptr, key u64, down i32) { code := C.XKeysymToKeycode(display, key); if code != 0 { C.XTestFakeKeyEvent(display, u32(code), down, C.CurrentTime) } }
@[export: 'vxi_button']
pub fn native_button(display voidptr, button u32, down i32) { C.XTestFakeButtonEvent(display, button, down, C.CurrentTime) }
@[export: 'vxi_pointer_child']
pub fn native_pointer_child(display voidptr) u64 {
    unsafe {
        mut root := usize(0); mut child := usize(0); mut rx := i32(0); mut ry := i32(0); mut wx := i32(0); mut wy := i32(0); mut mask := u32(0)
        if C.XQueryPointer(display, C.DefaultRootWindow(display), &root, &child, &rx, &ry, &wx, &wy, &mask) != 0 { return u64(child) }
        return C.None
    }
}
@[export: 'vxi_focus']
pub fn native_focus(display voidptr, child u64) { C.XSetInputFocus(display, child, C.RevertToPointerRoot, C.CurrentTime) }
@[export: 'vxi_dimensions']
pub fn native_dimensions(display voidptr, width &i32, height &i32) { unsafe { screen := C.DefaultScreen(display); *width = C.DisplayWidth(display, screen); *height = C.DisplayHeight(display, screen) } }
@[export: 'vxi_warp']
pub fn native_warp(display voidptr, x i32, y i32) { C.XWarpPointer(display, C.None, C.DefaultRootWindow(display), 0, 0, 0, 0, x, y) }
@[export: 'vxi_flush']
pub fn native_flush(display voidptr) { C.XFlush(display) }
@[export: 'main']
pub fn native_main() i32 { return C.vxi_main() }
