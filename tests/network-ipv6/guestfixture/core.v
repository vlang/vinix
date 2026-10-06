// Independent IPv6 socket, netlink and retained-allocation Linux ABI fixture.
@[has_globals]
module guestfixture

#include <ipv6-guest-native-abi.h>
@[typedef]
struct C.FILE {}
@[typedef]
struct C.ipv6_ull {}
@[c_extern]
__global C.stdout &C.FILE
struct C.in6_addr { s6_addr [16]u8 }
struct C.in_addr { s_addr u32 }
struct C.sockaddr_in6 { sin6_family u16 sin6_port u16 sin6_addr C.in6_addr }
struct C.sockaddr_in { sin_family u16 sin_port u16 sin_addr C.in_addr }
fn C.__errno_location() &i32
fn C.socket(i32, i32, i32) i32
fn C.htons(u16) u16
fn C.htonl(u32) u32
fn C.bind(i32, voidptr, u32) i32
fn C.listen(i32, i32) i32
fn C.connect(i32, voidptr, u32) i32
fn C.accept(i32, voidptr, voidptr) i32
fn C.sendto(i32, voidptr, usize, i32, voidptr, u32) isize
fn C.recvfrom(i32, voidptr, usize, i32, voidptr, &u32) isize
fn C.getsockname(i32, voidptr, &u32) i32
fn C.getsockopt(i32, i32, i32, voidptr, &u32) i32
fn C.setsockopt(i32, i32, i32, voidptr, u32) i32
fn C.close(i32) i32
fn C.syscall(isize, ...) isize
fn C.read(i32, voidptr, usize) isize
fn C.send(i32, voidptr, usize, i32) isize
fn C.recv(i32, voidptr, usize, i32) isize
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.strstr(&char, &char) &char
fn C.strchr(&char, i32) &char
fn C.strtol(&char, voidptr, i32) isize
fn C.sscanf(&char, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.setvbuf(&C.FILE, &char, i32, usize) i32
fn C.usleep(u32) i32
fn C.pause() i32

fn check(condition bool, line i32, expression &char) bool {
	if !condition { unsafe { C.printf(c'IPV6 FAIL: line %d: %s errno=%d\n', line, expression, *C.__errno_location()) } }
	return condition
}

fn loop6(port u32) C.sockaddr_in6 {
	mut address := C.sockaddr_in6{}
	address.sin6_family = u16(C.AF_INET6)
	address.sin6_port = C.htons(u16(port))
	unsafe { address.sin6_addr.s6_addr[15] = 1 }
	return address
}

fn exchange(kind i32, mapped bool) i32 {
	unsafe {
		listener := C.socket(C.AF_INET6, kind, 0)
		if !check(listener >= 0, 20, c'listener >= 0') { return 1 }
		client := C.socket(if mapped { C.AF_INET } else { C.AF_INET6 }, kind, 0)
		if !check(client >= 0, 21, c'client >= 0') { return 1 }
		mut local := loop6(u32(39431 + kind))
		if mapped { C.memset(&local.sin6_addr, 0, sizeof(C.in6_addr)) }
		if !check(C.bind(listener, voidptr(&local), u32(sizeof(C.sockaddr_in6))) == 0, 24, c'bind(listener, (struct sockaddr *)&local, sizeof local) == 0') { return 1 }
		mut server := listener
		mut v4 := C.sockaddr_in{}
		v4.sin_family = u16(C.AF_INET)
		v4.sin_port = local.sin6_port
		v4.sin_addr.s_addr = C.htonl(u32(C.INADDR_LOOPBACK))
		mut remote := loop6(u32(39431 + kind))
		destination := if mapped { voidptr(&v4) } else { voidptr(&remote) }
		destination_size := u32(if mapped { sizeof(C.sockaddr_in) } else { sizeof(C.sockaddr_in6) })
		if kind == C.SOCK_STREAM {
			if !check(C.listen(listener, 8) == 0, 32, c'listen(listener, 8) == 0') { return 1 }
			if !check(C.connect(client, destination, destination_size) == 0, 33, c'connect(client, destination, destination_size) == 0') { return 1 }
			server = C.accept(listener, nil, nil)
			if !check(server >= 0, 34, c'server >= 0') { return 1 }
		}
		if !check(C.sendto(client, c'IPv6', 4, 0, if kind == C.SOCK_DGRAM { destination } else { nil }, if kind == C.SOCK_DGRAM { destination_size } else { u32(0) }) == 4, 37, c'sendto(client, "IPv6", 4, 0, type == SOCK_DGRAM ? destination : NULL, type == SOCK_DGRAM ? destination_size : 0) == 4') { return 1 }
		mut bytes := [16]u8{}
		mut peer := C.sockaddr_in6{}
		mut size := u32(sizeof(C.sockaddr_in6))
		if !check(C.recvfrom(server, &bytes[0], 16, 0, voidptr(&peer), &size) == 4, 39, c'recvfrom(server, bytes, sizeof bytes, 0, (struct sockaddr *)&peer, &size) == 4') { return 1 }
		if !check(C.memcmp(&bytes[0], c'IPv6', 4) == 0 && size == sizeof(C.sockaddr_in6) && peer.sin6_family == C.AF_INET6, 40, c'memcmp(bytes, "IPv6", 4) == 0 && size == sizeof peer && peer.sin6_family == AF_INET6') { return 1 }
		if !check(peer.sin6_addr.s6_addr[15] == 1 && peer.sin6_port != 0, 41, c'peer.sin6_addr.s6_addr[15] == 1 && peer.sin6_port != 0') { return 1 }
		if mapped && !check(peer.sin6_addr.s6_addr[10] == 255 && peer.sin6_addr.s6_addr[12] == 127, 42, c'peer.sin6_addr.s6_addr[10] == 255 && peer.sin6_addr.s6_addr[12] == 127') { return 1 }
		size = u32(sizeof(C.sockaddr_in6))
		if !check(C.getsockname(server, voidptr(&peer), &size) == 0 && size == sizeof(C.sockaddr_in6), 44, c'getsockname(server, (struct sockaddr *)&peer, &size) == 0 && size == sizeof peer') { return 1 }
		mut v6only := i32(-1); size = u32(sizeof(i32))
		if !check(C.getsockopt(server, C.IPPROTO_IPV6, C.IPV6_V6ONLY, &v6only, &size) == 0 && v6only == 0, 46, c'getsockopt(server, IPPROTO_IPV6, IPV6_V6ONLY, &v6only, &size) == 0 && v6only == 0') { return 1 }
		mut hops := i32(-1); size = u32(sizeof(i32))
		if !check(C.getsockopt(server, C.IPPROTO_IPV6, C.IPV6_UNICAST_HOPS, &hops, &size) == 0 && hops >= 0, 48, c'getsockopt(server, IPPROTO_IPV6, IPV6_UNICAST_HOPS, &hops, &size) == 0 && hops >= 0') { return 1 }
		mut domain := i32(0); size = u32(sizeof(i32))
		if !check(C.getsockopt(server, C.SOL_SOCKET, C.SO_DOMAIN, &domain, &size) == 0 && domain == C.AF_INET6, 50, c'getsockopt(server, SOL_SOCKET, SO_DOMAIN, &domain, &size) == 0 && domain == AF_INET6') { return 1 }
		if !check(C.close(client) == 0, 51, c'close(client) == 0') { return 1 }
		if !check(C.close(server) == 0, 51, c'close(server) == 0') { return 1 }
		if server != listener && !check(C.close(listener) == 0, 52, c'close(listener) == 0') { return 1 }
		return 0
	}
}

fn slab_kib() isize {
	unsafe {
		fd := i32(C.syscall(isize(C.SYS_openat), C.AT_FDCWD, c'/proc/meminfo', 0, 0))
		if fd < 0 { return -1 }
		mut text := [8192]char{}
		n := C.read(fd, &text[0], 8191); C.close(fd)
		if n <= 0 { return -1 }
		text[n] = 0
		p := C.strstr(&text[0], c'Slab:')
		return if p != nil { C.strtol(p + 5, nil, 10) } else { isize(-1) }
	}
}

struct HeapClass { size u32 live u64 }
fn native_ull(value u64) C.ipv6_ull {
	mut result := C.ipv6_ull{}
	unsafe { C.memcpy(&result, &value, sizeof(u64)) }
	return result
}
fn heap_snapshot(classes &HeapClass) i32 {
	unsafe {
		fd := i32(C.syscall(isize(C.SYS_openat), C.AT_FDCWD, c'/proc/slabinfo', 0, 0))
		if fd < 0 { return -1 }
		mut text := [8192]char{}
		n := C.read(fd, &text[0], 8191); C.close(fd)
		if n <= 0 { return -1 }
		text[n] = 0
		mut count := i32(0)
		mut line := &text[0]
		for line != nil && *line != 0 {
			mut next := C.strchr(line, i32(`\n`))
			if next != nil { *next = 0; next++ }
			mut size := u32(0)
			mut live := C.ipv6_ull{}
			if C.sscanf(line, c'size-%u %*u %llu', &size, &live) == 2 {
				if count == 32 { return -1 }
				mut value := u64(0); C.memcpy(&value, &live, sizeof(u64))
				classes[count] = HeapClass{size, value}; count++
			}
			line = next
		}
		return count
	}
}

struct Header { len u32 kind u16 flags u16 seq u32 pid u32 }
struct Address { family u8 prefix u8 flags u8 scope u8 index u32 }
struct Request { h Header a Address }

fn netlink_addresses() i32 {
	unsafe {
		mut request := Request{Header{u32(sizeof(Request)), 22, 0x301, 701, 0}, Address{u8(C.AF_INET6), 0, 0, 0, 0}}
		fd := C.socket(16, C.SOCK_RAW, 0)
		if !check(fd >= 0, 85, c'fd >= 0') { return 1 }
		if !check(C.send(fd, &request, sizeof(Request), 0) == isize(sizeof(Request)), 86, c'send(fd, &request, sizeof request, 0) == (ssize_t)sizeof request') { return 1 }
		mut answer := [2048]u8{}
		n := i32(C.recv(fd, &answer[0], 2048, 0))
		if !check(n > 16, 87, c'n > 16') { return 1 }
		mut found := false
		for off := i32(0); off + 16 <= n; {
			mut h := Header{}; C.memcpy(&h, &answer[0] + off, sizeof(Header))
			if !check(h.len >= 16 && h.len <= u32(n - off), 91, c'h.len >= 16 && h.len <= (unsigned)(n - off)') { return 1 }
			if h.kind == 20 {
				mut a := Address{}
				if !check(h.len >= 24, 93, c'h.len >= 24') { return 1 }
				C.memcpy(&a, &answer[0] + off + 16, sizeof(Address))
				if !check(a.family == C.AF_INET6, 94, c'a.family == AF_INET6') { return 1 }
				if a.index == 1 && a.prefix == 128 {
					for at := u32(24); at + 4 <= h.len; {
						mut len := u16(0); mut kind := u16(0)
						C.memcpy(&len, &answer[0] + off + at, 2); C.memcpy(&kind, &answer[0] + off + at + 2, 2)
						if !check(len >= 4 && at + len <= h.len, 98, c'len >= 4 && at + len <= h.len') { return 1 }
						if kind == 1 && len == 20 && answer[off + at + 19] == 1 { found = true }
						at += (u32(len) + 3) & ~u32(3)
					}
				}
			}
			off += i32((h.len + 3) & ~u32(3))
		}
		if !check(found, 106, c'found') { return 1 }
		if !check(C.close(fd) == 0, 106, c'close(fd) == 0') { return 1 }
		return 0
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		C.setvbuf(C.stdout, nil, C._IONBF, 0)
		s := C.socket(C.AF_INET6, C.SOCK_DGRAM, 0)
		if !check(s >= 0, 111, c's >= 0') { return 1 }
		mut value := i32(-1); mut size := u32(sizeof(i32))
		if !check(C.getsockopt(s, C.IPPROTO_IPV6, C.IPV6_V6ONLY, &value, &size) == 0 && value == 0, 113, c'getsockopt(s, IPPROTO_IPV6, IPV6_V6ONLY, &value, &size) == 0 && value == 0') { return 1 }
		value = 1
		if !check(C.setsockopt(s, C.IPPROTO_IPV6, C.IPV6_V6ONLY, &value, u32(sizeof(i32))) == 0, 114, c'setsockopt(s, IPPROTO_IPV6, IPV6_V6ONLY, &value, sizeof value) == 0') { return 1 }
		mut remote := loop6(9)
		remote.sin6_addr.s6_addr[10] = 255; remote.sin6_addr.s6_addr[11] = 255; remote.sin6_addr.s6_addr[12] = 127
		if !check(C.connect(s, voidptr(&remote), u32(sizeof(C.sockaddr_in6))) == -1 && *C.__errno_location() == C.ENETUNREACH, 117, c'connect(s, (struct sockaddr *)&remote, sizeof remote) == -1 && errno == ENETUNREACH') { return 1 }
		remote = loop6(0)
		if !check(C.bind(s, voidptr(&remote), u32(sizeof(C.sockaddr_in6))) == 0, 118, c'bind(s, (struct sockaddr *)&remote, sizeof remote) == 0') { return 1 }
		value = 0
		if !check(C.setsockopt(s, C.IPPROTO_IPV6, C.IPV6_V6ONLY, &value, u32(sizeof(i32))) == -1 && *C.__errno_location() == C.EINVAL, 119, c'setsockopt(s, IPPROTO_IPV6, IPV6_V6ONLY, &value, sizeof value) == -1 && errno == EINVAL') { return 1 }
		if !check(C.close(s) == 0, 120, c'close(s) == 0') { return 1 }
		if !check(exchange(C.SOCK_DGRAM, false) == 0, 121, c'exchange(SOCK_DGRAM, 0) == 0') { return 1 }
		if !check(exchange(C.SOCK_DGRAM, true) == 0, 121, c'exchange(SOCK_DGRAM, 1) == 0') { return 1 }
		if !check(exchange(C.SOCK_STREAM, false) == 0, 122, c'exchange(SOCK_STREAM, 0) == 0') { return 1 }
		if !check(exchange(C.SOCK_STREAM, true) == 0, 122, c'exchange(SOCK_STREAM, 1) == 0') { return 1 }
		C.puts(c'IPV6 PASS: TCP UDP dual-stack socket ABI')
		if !check(netlink_addresses() == 0, 124, c'netlink_addresses() == 0') { return 1 }
		C.puts(c'IPV6 PASS: rtnetlink IPv6 loopback reporting')
		for i in 0 .. 20 {
			if !check(exchange(C.SOCK_DGRAM, (i & 1) != 0) == 0, 126, c'exchange(SOCK_DGRAM, i & 1) == 0') { return 1 }
			if !check(netlink_addresses() == 0, 126, c'netlink_addresses() == 0') { return 1 }
		}
		mut baseline := [32]HeapClass{}; mut measured := [32]HeapClass{}
		if !check(heap_snapshot(&baseline[0]) > 0, 128, c'heap_snapshot(baseline) > 0') { return 1 }
		if !check(slab_kib() >= 0, 128, c'slab_kib() >= 0') { return 1 }
		C.usleep(2500000)
		classes := heap_snapshot(&baseline[0])
		if !check(classes > 0, 130, c'classes > 0') { return 1 }
		before := slab_kib()
		for i in 0 .. 500 {
			if !check(exchange(C.SOCK_DGRAM, (i & 1) != 0) == 0, 132, c'exchange(SOCK_DGRAM, i & 1) == 0') { return 1 }
			if !check(netlink_addresses() == 0, 132, c'netlink_addresses() == 0') { return 1 }
		}
		after := slab_kib()
		if !check(heap_snapshot(&measured[0]) == classes, 134, c'heap_snapshot(measured) == classes') { return 1 }
		mut grew := false
		for i := i32(0); i < classes; i++ {
			if !check(measured[i].size == baseline[i].size, 137, c'measured[i].size == baseline[i].size') { return 1 }
			delta := isize(measured[i].live) - isize(baseline[i].live)
			C.printf(c'IPV6 CLASS: size=%u before=%llu after=%llu delta=%ld objects\n', measured[i].size, native_ull(baseline[i].live), native_ull(measured[i].live), delta)
			if delta > 0 { grew = true }
		}
		if !check(!grew, 143, c'!grew') { return 1 }
		C.printf(c'IPV6 SLAB: before=%ld KiB after=%ld KiB delta=%ld KiB operations=500\n', before, after, after - before)
		if !check(before >= 0 && after <= before + 16, 145, c'before >= 0 && after <= before + 16') { return 1 }
		C.puts(c'IPV6 PASS: repeated socket path allocation measurement')
		for { C.pause() }
		return 0
	}
}
