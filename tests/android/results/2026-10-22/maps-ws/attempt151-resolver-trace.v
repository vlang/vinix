@[translated]
module runtimecore

#include <netdb.h>

@[typedef]
struct C.vandroid_const_addrinfo_p {}

struct C.addrinfo {
mut:
    ai_flags i32
    ai_family i32
    ai_socktype i32
    ai_protocol i32
    ai_addrlen u32
    ai_addr &u8
    ai_canonname &char
    ai_next &C.addrinfo
}

type TraceResolve = fn (C.vandroid_const_char_p, C.vandroid_const_char_p, C.vandroid_const_addrinfo_p, &&C.addrinfo) i32
__global trace_next_resolve TraceResolve
__global trace_resolve_once i32

fn trace_resolve_init() {
    unsafe { trace_next_resolve = TraceResolve(C.dlsym(voidptr(usize(-1)), c'getaddrinfo')) }
}

@[export: 'getaddrinfo']
fn trace_getaddrinfo(host C.vandroid_const_char_p, service C.vandroid_const_char_p, raw_hints C.vandroid_const_addrinfo_p, result &&C.addrinfo) i32 {
    unsafe {
        hints := &C.addrinfo(raw_hints)
        C.pthread_once(&trace_resolve_once, trace_resolve_init)
        if voidptr(trace_next_resolve) == nil { return -11 }
        tid := C.syscall(C.SYS_gettid)
        incoming_errno := *C.__errno_location()
        C.printf(c'RESOLVER-TRACE begin tid=%ld host=%s family=%d flags=%d type=%d\n',
            tid, host, if hints == nil { -1 } else { hints.ai_family },
            if hints == nil { -1 } else { hints.ai_flags }, if hints == nil { -1 } else { hints.ai_socktype })
        C.fflush(nil)
        *C.__errno_location() = incoming_errno
        status := trace_next_resolve(host, service, raw_hints, result)
        if status == 0 && result != nil {
            mut v4 := &C.addrinfo(nil)
            mut v4_tail := &C.addrinfo(nil)
            mut other := &C.addrinfo(nil)
            mut other_tail := &C.addrinfo(nil)
            mut item := *result
            for item != nil {
                next := item.ai_next
                item.ai_next = nil
                if item.ai_family == 2 {
                    if v4 == nil { v4 = item } else { v4_tail.ai_next = item }
                    v4_tail = item
                } else {
                    if other == nil { other = item } else { other_tail.ai_next = item }
                    other_tail = item
                }
                item = next
            }
            if v4 != nil { v4_tail.ai_next = other; *result = v4 }
            else { *result = other }
        }
        saved_errno := *C.__errno_location()
        C.printf(c'RESOLVER-TRACE end tid=%ld host=%s status=%d\n', tid, host, status)
        if status == 0 && result != nil {
            mut item := *result
            for item != nil {
                mut address := [64]char{}
                offset := if item.ai_family == 2 { 4 } else { 8 }
                if item.ai_addr != nil && item.ai_addrlen >= u32(offset + 4) {
                    bytes := &u8(item.ai_addr)
                    C.inet_ntop(item.ai_family, &bytes[offset], &address[0], 64)
                }
                C.printf(c'RESOLVER-TRACE address tid=%ld family=%d host=%s\n', tid, item.ai_family, &address[0])
                item = item.ai_next
            }
        }
        C.fflush(nil)
        *C.__errno_location() = saved_errno
        return status
    }
}
