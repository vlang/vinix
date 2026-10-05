// SPDX-License-Identifier: GPL-2.0-or-later
// The small Apple boot image's PID1 reports the machine and stays available.
@[translated]
module reportcore

#include <fcntl.h>
#include <string.h>
#include <sys/utsname.h>
#include <unistd.h>

// Field metadata is for type checking; the native header owns the layout.
// Linux has 65-byte fields, Darwin 256; only each field's first address escapes.
struct C.utsname { sysname [65]char, release [65]char, machine [65]char }
fn C.open(&char, i32, ...voidptr) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.strlen(&char) usize
fn C.uname(&C.utsname) i32
fn C.pause() i32
@[cinit]
__global report_console = i32(1)

fn say(text &char) { C.write(report_console, text, C.strlen(text)) }
fn show(path &char, lines i32) {
    unsafe {
        mut buffer := [4096]char{}
        file := C.open(path, C.O_RDONLY)
        if file < 0 { return }
        say(c'--- '); say(path); say(c' ---\n')
        length := C.read(file, voidptr(&buffer[0]), sizeof(buffer))
        C.close(file)
        mut remaining := lines
        for index := isize(0); index < length && remaining > 0; index++ {
            C.write(report_console, voidptr(&buffer[index]), 1)
            if buffer[index] == `\n` { remaining-- }
        }
    }
}
@[export: 'main']
pub fn report() i32 {
    unsafe {
        mut name := C.utsname{}
        fd := C.open(c'/dev/console', C.O_WRONLY)
        if fd >= 0 { report_console = fd }
        say(c'APPLE-BOOT: init reached user space\n')
        if C.uname(&name) == 0 {
            say(&name.sysname[0]); say(c' '); say(&name.release[0]); say(c' ')
            say(&name.machine[0]); say(c'\n')
        }
        show(c'/proc/meminfo', 3)
        show(c'/proc/cpuinfo', 12)
        for { C.pause() }
        return 0
    }
}
