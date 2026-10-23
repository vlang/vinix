@[translated]
module runtimecore

#include <arpa/inet.h>
#include <sys/syscall.h>

fn C.printf(&char, ...voidptr) i32
fn C.fflush(voidptr) i32
fn C.inet_ntop(i32, voidptr, &char, u32) &char
fn C.syscall(isize, ...voidptr) isize

type TraceConnect = fn (i32, C.vandroid_const_sockaddr_p, u32) i32
__global trace_next_connect TraceConnect
__global trace_connect_once i32

fn trace_connect_resolve() {
    unsafe { trace_next_connect = TraceConnect(C.dlsym(voidptr(usize(-1)), c'connect')) }
}

@[export: 'connect']
fn trace_connect(fd i32, address C.vandroid_const_sockaddr_p, length u32) i32 {
    unsafe {
        C.pthread_once(&trace_connect_once, trace_connect_resolve)
        if voidptr(trace_next_connect) == nil { *C.__errno_location() = 38; return -1 }
        bytes := &u8(address)
        mut host := [64]char{}
        mut family := i32(0)
        mut port := u32(0)
        if bytes != nil && length >= 4 {
            family = i32(bytes[0]) | (i32(bytes[1]) << 8)
            port = (u32(bytes[2]) << 8) | u32(bytes[3])
            if family == 2 && length >= 16 { C.inet_ntop(family, &bytes[4], &host[0], 64) }
            if family == 10 && length >= 28 { C.inet_ntop(family, &bytes[8], &host[0], 64) }
        }
        tid := C.syscall(C.SYS_gettid)
        incoming_errno := *C.__errno_location()
        C.printf(c'CONNECT-TRACE begin tid=%ld fd=%d family=%d host=%s port=%u\n', tid, fd, family, &host[0], port)
        C.fflush(nil)
        *C.__errno_location() = incoming_errno
        result := trace_next_connect(fd, address, length)
        saved_errno := *C.__errno_location()
        C.printf(c'CONNECT-TRACE end tid=%ld fd=%d result=%d errno=%d\n', tid, fd, result, saved_errno)
        C.fflush(nil)
        *C.__errno_location() = saved_errno
        return result
    }
}
