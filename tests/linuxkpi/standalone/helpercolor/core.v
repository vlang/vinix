// SPDX-License-Identifier: GPL-2.0-only
@[translated]
module helpercolor

#include "helpercolor_v_contract.h"
@[typedef]
struct C.vks_volatile_u32 {}
@[typedef]
struct C.vks_volatile_int {}
fn C.assert(bool)
fn C.__atomic_store_n(voidptr, ...)
fn C.drm_color_lut_extract(...) u32
struct Case { input u32, precision i32, expected u32 }

@[export: 'main']
pub fn run() i32 {
    unsafe {
        cases := [
            Case{0x0000, 1, 0}, Case{0x3fff, 1, 0}, Case{0x4000, 1, 1},
            Case{0x8000, 1, 1}, Case{0xc000, 1, 1}, Case{0xffff, 1, 1},
            Case{0x0000, 8, 0}, Case{0x007f, 8, 0}, Case{0x0080, 8, 1},
            Case{0x8000, 8, 128}, Case{0xff7f, 8, 255}, Case{0xff80, 8, 255},
            Case{0xffff, 8, 255},
            Case{0x0000, 10, 0}, Case{0x001f, 10, 0}, Case{0x0020, 10, 1},
            Case{0x8000, 10, 512}, Case{0xffdf, 10, 1023}, Case{0xffe0, 10, 1023},
            Case{0xffff, 10, 1023},
            Case{0x0000, 12, 0}, Case{0x0007, 12, 0}, Case{0x0008, 12, 1},
            Case{0x8000, 12, 2048}, Case{0xfff7, 12, 4095}, Case{0xfff8, 12, 4095},
            Case{0xffff, 12, 4095},
            Case{0x0000, 16, 0}, Case{0x0001, 16, 1}, Case{0x8000, 16, 32768},
            Case{0xffff, 16, 65535}, Case{0x10000, 16, 65535}, Case{0xffffffff, 16, 65535},
        ]!
        for index in 0 .. cases.len {
            test := cases[index]
            mut input := C.vks_volatile_u32{}
            mut precision := C.vks_volatile_int{}
            C.__atomic_store_n(&input, test.input, i32(0))
            C.__atomic_store_n(&precision, test.precision, i32(0))
            C.assert(C.drm_color_lut_extract(input, precision) == test.expected)
        }
        mut input := u32(0)
        for input <= 0xffff {
            C.assert(C.drm_color_lut_extract(input, i32(16)) == input)
            input++
        }
        return 0
    }
}
