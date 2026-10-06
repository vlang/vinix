// SPDX-License-Identifier: GPL-2.0-or-later
// Native callback identities and exact 32-bit lock-free signal/damage accesses.
@[translated]
module winehost

#include "wine-host-v-abi.h"

@[typedef]
struct C.sigset_t {}
type NativeSignalHandler = fn (i32)
type NativeErrorHandler = fn (&C.Display, &C.XErrorEvent) i32
@[typedef]
struct C.vwh_sigaction { mut: sa_handler NativeSignalHandler sa_mask C.sigset_t }
fn C.sigemptyset(&C.sigset_t) i32
fn C.sigaction(i32, &C.vwh_sigaction, &C.vwh_sigaction) i32
fn C.XSetErrorHandler(NativeErrorHandler) NativeErrorHandler
fn C.vinix_wine_host_stop(i32)
fn C.vinix_wine_host_x_error(&C.Display, &C.XErrorEvent) i32
fn C.vinix_wine_host_main(i32, &&char) i32
@[c: '__atomic_load_n'] fn C.vwh_load32(&i32, i32) i32
@[c: '__atomic_store_n'] fn C.vwh_store32(&i32, i32, i32)
@[c: '__atomic_store_n'] fn C.vwh_store_damage32(&u32, u32, i32)

__global native_running i32 = 1
@[c_extern] __global C.errno i32

@[export: 'vwh_running']
pub fn native_is_running() i32 { unsafe { return C.vwh_load32(&native_running, 0) } }
@[export: 'vwh_set_running']
pub fn native_set_running(value i32) { unsafe { C.vwh_store32(&native_running, value, 0) } }
@[export: 'vwh_errno']
pub fn native_errno() i32 { return i32(C.errno) }
@[export: 'vwh_install_signals']
pub fn native_signals() {
    unsafe {
        mut action := C.vwh_sigaction{sa_handler: C.vinix_wine_host_stop}
        C.sigemptyset(&action.sa_mask)
        C.sigaction(C.SIGHUP, &action, nil)
        C.sigaction(C.SIGINT, &action, nil)
        C.sigaction(C.SIGTERM, &action, nil)
    }
}
@[export: 'vwh_install_x_error']
pub fn native_x_error() { C.XSetErrorHandler(C.vinix_wine_host_x_error) }
@[export: 'vwh_damage_store']
pub fn native_damage_store(pointer voidptr, value u32) { unsafe { C.vwh_store_damage32(&u32(pointer), value, 0) } }

$if wine_host_no_main ? {
} $else {
    @[export: 'main']
    pub fn native_main(argc i32, argv &&char) i32 { return C.vinix_wine_host_main(argc, argv) }
}
