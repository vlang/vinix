// SPDX-License-Identifier: GPL-2.0-or-later
// Linux UDP connect/getsockname source selection, without sending packets.
module udpsourcefixture

#include <ipv6-guest-native-abi.h>
struct C.in6_addr { s6_addr [16]u8 }
struct C.in_addr { s_addr u32 }
struct C.sockaddr_in6 { sin6_family u16 sin6_port u16 sin6_addr C.in6_addr }
struct C.sockaddr_in { sin_family u16 sin_port u16 sin_addr C.in_addr }
fn C.socket(i32, i32, i32) i32
fn C.htons(u16) u16
fn C.htonl(u32) u32
fn C.bind(i32, voidptr, u32) i32
fn C.connect(i32, voidptr, u32) i32
fn C.getsockname(i32, voidptr, &u32) i32
fn C.close(i32) i32
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.calloc(usize, usize) voidptr
fn C.free(voidptr)
fn C.dprintf(i32, &char, ...) i32
fn C.__errno_location() &i32
fn C.pause() i32

fn check(condition bool, expression &char) bool {
 if !condition { unsafe { C.dprintf(1, c'UDP-SOURCE FAIL: %s errno=%d\n', expression, *C.__errno_location()) } }
 return condition
}

fn connected_source(family i32, mapped bool, explicit_bind bool) bool {
 fd := C.socket(family, C.SOCK_DGRAM, 0)
 if !check(fd >= 0, c'socket') { return false }
 defer { C.close(fd) }
 mut remote4 := C.sockaddr_in{sin_family: u16(C.AF_INET), sin_port: C.htons(65535), sin_addr: C.in_addr{C.htonl(0x7f000001)}}
 mut remote6 := unsafe { &C.sockaddr_in6(C.calloc(1, sizeof(C.sockaddr_in6))) }
 if !check(remote6 != unsafe { nil }, c'remote address allocation') { return false }
 defer { unsafe { C.free(remote6) } }
 remote6.sin6_family = u16(C.AF_INET6)
 remote6.sin6_port = C.htons(65535)
 remote6.sin6_addr.s6_addr[15] = 1
 if mapped {
  remote6.sin6_addr.s6_addr[10] = 255
  remote6.sin6_addr.s6_addr[11] = 255
  remote6.sin6_addr.s6_addr[12] = 127
 }
 mut remote := voidptr(remote6)
 if family == C.AF_INET { remote = voidptr(unsafe { &remote4 }) }
 length := if family == C.AF_INET { u32(sizeof(C.sockaddr_in)) } else { u32(sizeof(C.sockaddr_in6)) }
 mut local4 := remote4
 mut local6 := unsafe { &C.sockaddr_in6(C.calloc(1, sizeof(C.sockaddr_in6))) }
 if !check(local6 != unsafe { nil }, c'local address allocation') { return false }
 defer { unsafe { C.free(local6) } }
 unsafe { C.memcpy(local6, remote6, sizeof(C.sockaddr_in6)) }
 local4.sin_port = 0
 local6.sin6_port = 0
 mut local := voidptr(local6)
 if family == C.AF_INET { local = voidptr(unsafe { &local4 }) }
 if explicit_bind && !check(C.bind(fd, local, length) == 0, c'explicit bind') { return false }
 if !check(C.connect(fd, remote, length) == 0, c'connect') { return false }
 mut size := length
 if !check(C.getsockname(fd, local, &size) == 0 && size == length, c'getsockname length') { return false }
 if family == C.AF_INET {
  if !check(local4.sin_family == family && local4.sin_addr.s_addr == remote4.sin_addr.s_addr && local4.sin_port != 0, c'IPv4 selected loopback source') { return false }
 } else {
  same := unsafe { C.memcmp(&local6.sin6_addr, &remote6.sin6_addr, 16) == 0 }
  if !check(local6.sin6_family == family && same && local6.sin6_port != 0, c'IPv6 or mapped selected loopback source') { return false }
 }
 return true
}

@[export: 'main']
pub fn run() i32 {
 for mode in 0 .. 2 {
  if !connected_source(C.AF_INET, false, mode != 0) { return 1 }
  if !connected_source(C.AF_INET6, false, mode != 0) { return 1 }
  if !connected_source(C.AF_INET6, true, mode != 0) { return 1 }
 }
 C.dprintf(1, c'UDP-SOURCE PASS: connected IPv4 IPv6 mapped bound and unbound source addresses\n')
 for { C.pause() }
 return 0
}
