// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module runtimecore

@[typedef]
struct C.vinix_malloc_stats {
    mapped_bytes usize
    live_bytes usize
    free_bytes usize
    peak_mapped_bytes usize
    peak_live_bytes usize
    live_blocks usize
    free_blocks usize
    mapped_blocks usize
}
@[typedef]
struct C.android_mallinfo {
    arena usize
    ordblks usize
    smblks usize
    hblks usize
    hblkhd usize
    usmblks usize
    fsmblks usize
    uordblks usize
    fordblks usize
    keepcost usize
}
struct C.sockaddr {}
@[typedef]
struct C.vandroid_const_void_p {}
@[typedef]
struct C.vandroid_const_char_p {}
@[typedef]
struct C.vandroid_const_sockaddr_p {}
fn C.__vinix_malloc_stats(&C.vinix_malloc_stats, usize) i32
fn C.fputs(&char, &C.FILE) i32
fn C.fprintf(&C.FILE, &char, ...voidptr) i32
fn C.abort()
fn C.flockfile(&C.FILE)
fn C.funlockfile(&C.FILE)
fn C.__fseterr(&C.FILE)
fn C.fread(voidptr, usize, usize, &C.FILE) usize
fn C.readlink(&char, &char, usize) isize
@[c_extern]
fn C.sendto(i32, C.vandroid_const_void_p, usize, i32, C.vandroid_const_sockaddr_p, u32) isize
@[c_extern]
fn C.strlcpy(&char, C.vandroid_const_char_p, usize) usize

@[c_extern] __global C.stdin &C.FILE
@[c_extern] __global C.stdout &C.FILE
@[c_extern] __global C.stderr &C.FILE

$if arm64 {
    @[export: 'bionic_mallinfo']
    pub fn mallinfo() C.android_mallinfo {
        unsafe {
            mut statistics := C.vinix_malloc_stats{}
            if voidptr(C.__vinix_malloc_stats) == nil ||
                C.__vinix_malloc_stats(&statistics, sizeof(C.vinix_malloc_stats)) != 0 {
                C.fputs(c'Android allocator statistics ABI mismatch\n', C.stderr)
                C.abort()
            }
            return C.android_mallinfo{ordblks: statistics.free_blocks,
                hblks: statistics.mapped_blocks, hblkhd: statistics.mapped_bytes,
                usmblks: statistics.peak_mapped_bytes, uordblks: statistics.live_bytes,
                fordblks: statistics.free_bytes}
        }
    }

    fn buffer_overflow(function &char, action &char, requested usize, available usize) {
        unsafe {
            C.fprintf(C.stderr, c'FORTIFY: %s: prevented %zu-byte %s %zu-byte buffer\n', function, requested, action, available)
            C.abort()
        }
    }

    @[export: 'bionic___assert']
    pub fn assertion(file &char, line i32, expression &char) {
        unsafe {
            C.fprintf(C.stderr, c'%s:%d: assertion "%s" failed\n', file, line, expression)
            C.abort()
        }
    }

    fn host_stream(stream &C.FILE) &C.FILE {
        unsafe {
            saved_errno := *C.__errno_location()
            standard := &u8(C.dlsym(nil, c'bionic___sF'))
            *C.__errno_location() = saved_errno
            if standard != nil {
                if voidptr(stream) == voidptr(standard) { return C.stdin }
                if voidptr(stream) == voidptr(standard + 152) { return C.stdout }
                if voidptr(stream) == voidptr(standard + 304) { return C.stderr }
            }
            return stream
        }
    }

    @[export: 'bionic___fread_chk']
    pub fn checked_fread(buffer voidptr, size usize, count usize, stream &C.FILE, buffer_size usize) usize {
        unsafe {
            if size != 0 && count > usize(-1) / size {
                native_stream := host_stream(stream)
                C.flockfile(native_stream)
                C.__fseterr(native_stream)
                C.funlockfile(native_stream)
                *C.__errno_location() = 75
                return 0
            }
            total := size * count
            if total > buffer_size { buffer_overflow(c'fread', c'write into', total, buffer_size) }
            return C.fread(buffer, size, count, host_stream(stream))
        }
    }

    @[export: 'bionic___readlink_chk']
    pub fn checked_readlink(path &char, buffer &char, size usize, buffer_size usize) isize {
        unsafe {
            if size > usize(0x7fffffffffffffff) {
                C.fprintf(C.stderr, c'FORTIFY: readlink: size %zu > SSIZE_MAX\n', size)
                C.abort()
            }
            if size > buffer_size { buffer_overflow(c'readlink', c'write into', size, buffer_size) }
            return C.readlink(path, buffer, size)
        }
    }

    @[export: 'bionic___sendto_chk']
    pub fn checked_sendto(socket i32, buffer C.vandroid_const_void_p, size usize, buffer_size usize,
        flags i32, address C.vandroid_const_sockaddr_p, address_size u32) isize {
        if size > buffer_size { buffer_overflow(c'sendto', c'read from', size, buffer_size) }
        return C.sendto(socket, buffer, size, flags, address, address_size)
    }

    @[export: 'bionic___strlcpy_chk']
    pub fn checked_strlcpy(destination &char, source C.vandroid_const_char_p, size usize, destination_size usize) usize {
        if size > destination_size { buffer_overflow(c'strlcpy', c'write into', size, destination_size) }
        return C.strlcpy(destination, source, size)
    }
}
