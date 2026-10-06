// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module runtimecore

type MapFunction = fn (voidptr, usize, i32, i32, i32, isize) voidptr
type UnmapFunction = fn (voidptr, usize) i32

const low_alignment = usize(16384)
const low_begin = usize(0x10000)
const low_end = usize(0x80000000)

$if amd64 {
    __global next_map MapFunction
    __global next_unmap UnmapFunction
    __global mapping_once i32
    __global low_mutex C.pthread_mutex_t
    __global low_cursor usize = usize(0x10000000)

    fn low_fork_prepare() { unsafe { C.pthread_mutex_lock(&low_mutex) } }
    fn low_fork_release() { unsafe { C.pthread_mutex_unlock(&low_mutex) } }
    fn mapping_resolve() {
        unsafe {
            next_map = MapFunction(C.dlsym(voidptr(usize(-1)), c'mmap'))
            next_unmap = UnmapFunction(C.dlsym(voidptr(usize(-1)), c'munmap'))
        }
    }

    fn align_low(address usize) usize { return (address + low_alignment - 1) & ~(low_alignment - 1) }

    fn find_low_hint(start usize, span usize, hint &usize) i32 {
        unsafe {
            maps := C.fopen(c'/proc/self/maps', c'r')
            if maps == nil { return *C.__errno_location() }
            mut candidate := align_low(start)
            mut line := &char(nil)
            mut capacity := usize(0)
            for C.getline(&line, &capacity, maps) >= 0 {
                mut begin := usize(0)
                mut end := usize(0)
                if C.sscanf(line, c'%lx-%lx', &begin, &end) != 2 || end <= candidate { continue }
                if candidate > low_end - span || begin >= candidate + span { break }
                candidate = align_low(end)
            }
            mut result := if C.ferror(maps) != 0 { i32(5) } else { i32(0) }
            C.free(line)
            C.fclose(maps)
            if result == 0 && (candidate < low_begin || candidate > low_end - span) { result = 12 }
            if result == 0 { *hint = candidate }
            return result
        }
    }

    @[export: 'mmap']
    pub fn native_map(address voidptr, length usize, protection i32, flags i32, fd i32, offset isize) voidptr {
        unsafe {
            C.pthread_once(&mapping_once, mapping_resolve)
            if voidptr(next_map) == nil || voidptr(next_unmap) == nil {
                *C.__errno_location() = 38; return voidptr(usize(-1))
            }
            if flags & 0x40 == 0 || flags & (0x10 | 0x100000) != 0 ||
                length == 0 || offset < 0 || offset % 4096 != 0 {
                return next_map(address, length, protection, flags, fd, offset)
            }
            if length > low_end - low_begin { *C.__errno_location() = 12; return voidptr(usize(-1)) }
            span := align_low(length)
            if span > low_end - low_begin { *C.__errno_location() = 12; return voidptr(usize(-1)) }
            saved_errno := *C.__errno_location()
            mut previous_cancel := i32(0)
            mut error := C.pthread_setcancelstate(C.PTHREAD_CANCEL_DISABLE, &previous_cancel)
            if error != 0 { *C.__errno_location() = error; return voidptr(usize(-1)) }
            error = C.pthread_mutex_lock(&low_mutex)
            if error != 0 {
                C.pthread_setcancelstate(previous_cancel, nil)
                *C.__errno_location() = error
                return voidptr(usize(-1))
            }
            mut start := low_cursor
            if usize(address) >= low_begin && usize(address) <= low_end - span { start = usize(address) & ~(low_alignment - 1) }
            mut mapping := voidptr(usize(-1))
            mut wrapped := false
            error = 12
            for attempt := u32(0); attempt < 128; attempt++ {
                mut hint := usize(0)
                error = find_low_hint(start, span, &hint)
                if error == 12 && !wrapped && start != low_begin { start = low_begin; wrapped = true; continue }
                if error != 0 { break }
                mapping = next_map(voidptr(hint), length, protection, flags & ~i32(0x40), fd, offset)
                if mapping == voidptr(usize(-1)) { error = *C.__errno_location(); break }
                actual := usize(mapping)
                if actual >= low_begin && actual <= low_end - span {
                    low_cursor = align_low(actual + span)
                    if low_cursor >= low_end { low_cursor = low_begin }
                    error = 0
                    break
                }
                if next_unmap(mapping, length) != 0 { error = *C.__errno_location(); mapping = voidptr(usize(-1)); break }
                mapping = voidptr(usize(-1))
                start = hint + low_alignment
                error = 12
            }
            C.pthread_mutex_unlock(&low_mutex)
            C.pthread_setcancelstate(previous_cancel, nil)
            *C.__errno_location() = if error == 0 { saved_errno } else { error }
            return mapping
        }
    }

    @[export: 'mmap64']
    pub fn native_map64(address voidptr, length usize, protection i32, flags i32, fd i32, offset isize) voidptr {
        return native_map(address, length, protection, flags, fd, offset)
    }
}
