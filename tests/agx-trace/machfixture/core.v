// SPDX-License-Identifier: GPL-2.0-only
// Map the immutable C baseline's Mach read to the independent driver model.
@[translated]
module machfixture
@[c_extern] fn C.vagt_read(voidptr, usize, voidptr, &u64) i32
@[export: 'vagt_mock_read']
pub fn mock_read(_task u32, source u64, bytes u64, destination u64, copied &u64) i32 {
    unsafe {
        mut count := u64(0)
        status := C.vagt_read(voidptr(usize(source)), usize(bytes), voidptr(usize(destination)), &count)
        *copied = count
        return status
    }
}
