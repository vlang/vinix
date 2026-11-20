// SPDX-License-Identifier: GPL-2.0-or-later
// Unprivileged user namespaces as bubblewrap uses them for WebKit's sandbox:
// one clone into new user, mount, pid, IPC, UTS and network namespaces, the
// identity id maps, a private tmpfs root reached by pivot_root, /proc and the
// loopback; and what the capabilities held there must still not do on the
// host: read root's files, make devices, set the clock, loosen or unmount
// inherited mounts (lazily either), mount device filesystems, mount a proc
// over a masked one, give a tmpfs an owner it does not map, reach the host's
// abstract sockets, or start from a chroot.
// The same ELF runs as Vinix's init and, given --reference, under Linux.
// Vinix maps only the creator's own id, gives a network namespace of its own
// no IP sockets and has a wxallowed mount option; those three checks are
// skipped under --reference. So is
// the check that a user and a network namespace keep nothing allocated beyond
// themselves once their sandbox exits, which reads Vinix's /proc/slabinfo.
module usernsfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <sched.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mount.h>
#include <sys/prctl.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <unistd.h>

fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.mkdir(&char, u32) i32
fn C.chmod(&char, u32) i32
fn C.chdir(&char) i32
fn C.chroot(&char) i32
fn C.access(&char, i32) i32
fn C.alloca(usize) voidptr
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.strcmp(&char, &char) i32
fn C.strlen(&char) usize
fn C.setgroups(usize, voidptr) i32
fn C.prctl(i32, ...) i32
fn C.mount(&char, &char, &char, u64, voidptr) i32
fn C.umount2(&char, i32) i32
fn C.mknod(&char, u32, u64) i32
fn C.sethostname(&char, usize) i32
fn C.gethostname(&char, usize) i32
fn C.getpid() i32
fn C.getuid() u32
fn C.settimeofday(voidptr, voidptr) i32
fn C.socket(i32, i32, i32) i32
fn C.bind(i32, voidptr, u32) i32
fn C.listen(i32, i32) i32
fn C.connect(i32, voidptr, u32) i32
fn C.ioctl(i32, u64, ...) i32
fn C.send(i32, voidptr, usize, i32) isize
fn C.recv(i32, voidptr, usize, i32) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.sscanf(&char, &char, ...) i32
fn C.usleep(u32) i32
fn C.malloc(usize) voidptr
fn C.free(voidptr)

const clone_namespaces = u64(0x10000000) | 0x00020000 | 0x20000000 | 0x08000000 | 0x04000000 | 0x40000000
const abstract_length = 20

struct State {
mut:
	checks   int
	failures int
}

fn check(mut s State, label &char, ok bool, got i64) {
	s.checks++
	if !ok {
		s.failures++
		C.printf(c'LINUX USERNS FAIL: %s value=%ld errno=%d\n', label, got, unsafe { *C.__errno_location() })
		C.fflush(nil)
	}
}

fn errno_value() i32 {
	return unsafe { *C.__errno_location() }
}

// The result of a call that should fail: -errno, or the value on success.
fn failure(result i64) i64 {
	return if result < 0 { -i64(errno_value()) } else { result }
}

fn write_file(path &char, text &char) i64 {
	fd := C.open(path, C.O_WRONLY)
	if fd < 0 {
		return -i64(errno_value())
	}
	written := C.write(fd, text, C.strlen(text))
	code := errno_value()
	C.close(fd)
	return if written < 0 { -i64(code) } else { i64(written) }
}

// Whether the file holds exactly `expected`.
fn file_is(path &char, expected &char) bool {
	unsafe {
		buffer := &u8(C.alloca(128))
		C.memset(buffer, 0, 128)
		fd := C.open(path, C.O_RDONLY)
		if fd < 0 {
			return false
		}
		size := C.read(fd, buffer, 127)
		C.close(fd)
		return size >= 0 && C.strcmp(&char(buffer), expected) == 0
	}
}

// Fill `address` (110 bytes) with the abstract sockaddr_un the host listens on.
fn fill_abstract_address(address &u8) {
	unsafe {
		C.memset(address, 0, 110)
		address[0] = u8(C.AF_UNIX)
		C.memcpy(&address[2], voidptr(c'\0vinix-userns-probe'), abstract_length)
	}
}

fn connect_abstract() i64 {
	unsafe {
		address := C.alloca(110)
		fill_abstract_address(&u8(address))
		fd := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
		result := C.connect(fd, address, u32(2 + abstract_length))
		code := errno_value()
		C.close(fd)
		return if result < 0 { -i64(code) } else { 0 }
	}
}

// if_nametoindex through SIOCGIFINDEX, as musl implements it.
fn interface_index(name &char) i64 {
	unsafe {
		request := &u8(C.alloca(40))
		C.memset(request, 0, 40)
		C.memcpy(request, name, C.strlen(name))
		fd := C.socket(C.AF_UNIX, C.SOCK_DGRAM, 0)
		result := C.ioctl(fd, u64(0x8933), request)
		code := errno_value()
		C.close(fd)
		if result < 0 {
			return -i64(code)
		}
		return i64(*(&i32(&request[16])))
	}
}

// RTM_NEWLINK bringing interface 1 up, with NLM_F_ACK: the netlink error code.
fn loopback_up() i64 {
	unsafe {
		message := &u8(C.alloca(32))
		C.memset(message, 0, 32)
		*(&u32(&message[0])) = 32
		*(&u16(&message[4])) = 16 // RTM_NEWLINK
		*(&u16(&message[6])) = 5 // NLM_F_REQUEST | NLM_F_ACK
		*(&u32(&message[8])) = 1
		*(&i32(&message[20])) = 1 // ifi_index
		*(&u32(&message[24])) = 1 // IFF_UP
		*(&u32(&message[28])) = 1
		fd := C.socket(16, C.SOCK_RAW, 0) // AF_NETLINK, NETLINK_ROUTE
		if fd < 0 {
			return -i64(errno_value())
		}
		if C.send(fd, message, 32, 0) != 32 {
			C.close(fd)
			return -1000
		}
		reply := &u8(C.alloca(256))
		C.memset(reply, 0, 256)
		size := C.recv(fd, reply, 256, 0)
		C.close(fd)
		if size < 20 || *(&u16(&reply[4])) != 2 { // NLMSG_ERROR
			return -1001
		}
		return i64(*(&i32(&reply[16])))
	}
}

fn capability_effective_has(bit int) bool {
	unsafe {
		header := &u32(C.alloca(8))
		header[0] = 0x20080522
		header[1] = 0
		data := &u32(C.alloca(24))
		C.memset(data, 0, 24)
		if C.syscall(isize(C.SYS_capget), header, data) != 0 {
			return false
		}
		word := if bit < 32 { data[0] } else { data[3] }
		return word & (u32(1) << (bit % 32)) != 0
	}
}

// Inside the new namespaces, before and after the pivot into a private root.
fn sandboxed(reference bool) i32 {
	unsafe {
		mut s := State{}
		check(mut s, c'first in its pid namespace', C.getpid() == 1, i64(C.getpid()))
		check(mut s, c'no uid map yet', file_is(c'/proc/self/uid_map', c''), 0)
		check(mut s, c'setgroups allowed initially', file_is(c'/proc/self/setgroups', c'allow\n'), 0)
		denied := write_file(c'/proc/self/gid_map', c'1000 1000 1')
		check(mut s, c'gid map needs setgroups deny', denied == -C.EPERM, denied)
		if !reference {
			other := write_file(c'/proc/self/uid_map', c'0 1000 1')
			check(mut s, c'only the identity map', other == -C.EPERM, other)
		}
		check(mut s, c'own uid map', write_file(c'/proc/self/uid_map', c'1000 1000 1') > 0, 0)
		again := write_file(c'/proc/self/uid_map', c'1000 1000 1')
		check(mut s, c'uid map written once', again == -C.EPERM, again)
		check(mut s, c'setgroups deny', write_file(c'/proc/self/setgroups', c'deny') > 0, 0)
		check(mut s, c'own gid map', write_file(c'/proc/self/gid_map', c'1000 1000 1') > 0, 0)
		check(mut s, c'uid map text', file_is(c'/proc/self/uid_map', c'      1000       1000          1\n'), 0)
		check(mut s, c'setgroups now deny', file_is(c'/proc/self/setgroups', c'deny\n'), 0)
		check(mut s, c'uid kept', C.getuid() == 1000, i64(C.getuid()))
		check(mut s, c'namespace CAP_SYS_ADMIN', capability_effective_has(21), 0)
		// Namespace capabilities give nothing over the host.
		secret := failure(i64(C.open(c'/tmp/ns/secret', C.O_RDONLY)))
		check(mut s, c'root file still private', secret == -C.EACCES, secret)
		device := failure(i64(C.mknod(c'/tmp/ns/open/null', 0o20666, 0x103)))
		check(mut s, c'no devices', device == -C.EPERM, device)
		time := C.alloca(16)
		C.memset(time, 0, 16)
		clock := failure(i64(C.settimeofday(time, nil)))
		check(mut s, c'no clock', clock == -C.EPERM, clock)
		check(mut s, c'own hostname', C.sethostname(c'sandbox', 7) == 0, 0)
		// The mount namespace is its own to rearrange, within what it inherited.
		check(mut s, c'slave propagation', C.mount(nil, c'/', nil, u64(C.MS_SLAVE | C.MS_REC), nil) == 0, 0)
		devices := failure(i64(C.mount(c'none', c'/tmp/ns/open', c'devtmpfs', 0, nil)))
		check(mut s, c'no device filesystem', devices == -C.EPERM, devices)
		loosen := failure(i64(C.mount(nil, c'/tmp/ns/ro', nil, u64(C.MS_REMOUNT | C.MS_BIND), nil)))
		check(mut s, c'locked read-only kept', loosen == -C.EPERM, loosen)
		superblock := failure(i64(C.mount(nil, c'/tmp/ns/ro', nil, u64(C.MS_REMOUNT | C.MS_RDONLY), nil)))
		check(mut s, c'no superblock remount', superblock == -C.EPERM, superblock)
		check(mut s, c'read-only remount', C.mount(nil, c'/tmp/ns/ro', nil,
			u64(C.MS_REMOUNT | C.MS_BIND | C.MS_RDONLY), nil) == 0, 0)
		reveal := failure(i64(C.umount2(c'/tmp/ns/cover', 0)))
		check(mut s, c'locked mount stays', reveal == -C.EINVAL, reveal)
		reveal_lazy := failure(i64(C.umount2(c'/tmp/ns/cover', C.MNT_DETACH)))
		check(mut s, c'locked mount stays lazily', reveal_lazy == -C.EINVAL, reveal_lazy)
		check(mut s, c'private tmpfs', C.mount(c'tmpfs', c'/tmp/ns/open', c'tmpfs',
			u64(C.MS_NOSUID | C.MS_NODEV), nil) == 0, 0)
		// A tmpfs root may belong only to an id the namespace maps.
		C.mkdir(c'/tmp/ns/open/owner', 0o755)
		foreign := failure(i64(C.mount(c'tmpfs', c'/tmp/ns/open/owner', c'tmpfs', 0, c'uid=0')))
		check(mut s, c'no unmapped tmpfs owner', foreign == -C.EINVAL, foreign)
		if !reference {
			// W^X exceptions are the administrator's (a Vinix mount option).
			wx := failure(i64(C.mount(c'tmpfs', c'/tmp/ns/open/owner', c'tmpfs', 0, c'wxallowed')))
			check(mut s, c'no W^X exception', wx == -C.EPERM, wx)
		}
		check(mut s, c'mapped tmpfs owner', C.mount(c'tmpfs', c'/tmp/ns/open/owner', c'tmpfs', 0,
			c'uid=1000,gid=1000') == 0, 0)
		C.mkdir(c'/tmp/ns/open/bound', 0o755)
		check(mut s, c'bind', C.mount(c'/tmp/ns/ro', c'/tmp/ns/open/bound', nil,
			u64(C.MS_BIND | C.MS_REC), nil) == 0, 0)
		copy := failure(i64(C.mount(nil, c'/tmp/ns/open/bound', nil, u64(C.MS_REMOUNT | C.MS_BIND), nil)))
		check(mut s, c'bind keeps read-only lock', copy == -C.EPERM, copy)
		// mount_setattr(2), as bubblewrap 0.13 sets its mount flags.
		attr := &u64(C.alloca(32))
		C.memset(attr, 0, 32)
		attr[1] = 0x1 // attr_clr: MOUNT_ATTR_RDONLY
		unlock := failure(i64(C.syscall(442, C.AT_FDCWD, c'/tmp/ns/open/bound', 0, attr, 32)))
		check(mut s, c'setattr keeps read-only lock', unlock == -C.EPERM, unlock)
		attr[1] = 0
		attr[0] = 0x2 | 0x4 // attr_set: MOUNT_ATTR_NOSUID | MOUNT_ATTR_NODEV
		check(mut s, c'setattr nosuid nodev', C.syscall(442, C.AT_FDCWD, c'/tmp/ns/open/bound',
			0x8000, attr, 32) == 0, 0) // AT_RECURSIVE
		inner := failure(i64(C.syscall(442, C.AT_FDCWD, c'/tmp/ns', 0, attr, 32)))
		check(mut s, c'setattr needs a mount root', inner == -C.EINVAL, inner)
		// bubblewrap makes files such as /proc/sysrq-trigger read-only so: a bind
		// of the file onto itself, then its descriptor with AT_EMPTY_PATH.
		single := C.open(c'/tmp/ns/open/single', C.O_CREAT | C.O_WRONLY, 0o644)
		C.close(single)
		C.mount(c'/tmp/ns/open/single', c'/tmp/ns/open/single', nil, u64(C.MS_BIND), nil)
		pinned := C.open(c'/tmp/ns/open/single', C.O_PATH)
		attr[0] = 0x1 // MOUNT_ATTR_RDONLY
		check(mut s, c'setattr on a file mount', pinned >= 0
			&& C.syscall(442, pinned, c'', C.AT_EMPTY_PATH, attr, 32) == 0, 0)
		C.close(pinned)
		// bubblewrap's two pivots.
		C.mkdir(c'/tmp/ns/open/newroot', 0o755)
		C.mkdir(c'/tmp/ns/open/oldroot', 0o755)
		check(mut s, c'newroot bind', C.mount(c'/tmp/ns/open/newroot', c'/tmp/ns/open/newroot', nil,
			u64(C.MS_BIND | C.MS_REC), nil) == 0, 0)
		check(mut s, c'enter base', C.chdir(c'/tmp/ns/open') == 0, 0)
		check(mut s, c'pivot to base', C.syscall(isize(C.SYS_pivot_root), c'/tmp/ns/open', c'oldroot') == 0, 0)
		C.chdir(c'/')
		C.mkdir(c'/newroot/proc', 0o555)
		check(mut s, c'proc of its own', C.mount(c'proc', c'/newroot/proc', c'proc',
			u64(C.MS_NOSUID | C.MS_NOEXEC | C.MS_NODEV), nil) == 0, 0)
		held := C.open(c'/oldroot/tmp/ns', C.O_PATH | C.O_DIRECTORY)
		check(mut s, c'drop old root', C.umount2(c'/oldroot', C.MNT_DETACH) == 0, 0)
		// The detached tree keeps its locked mounts: a descriptor into it must
		// not find what they cover.
		covered := C.syscall(isize(C.SYS_faccessat), held, c'cover/hidden', C.F_OK, 0)
		check(mut s, c'detached tree stays covered', held >= 0 && covered != 0, i64(covered))
		C.close(held)
		check(mut s, c'enter newroot', C.chdir(c'/newroot') == 0, 0)
		check(mut s, c'pivot to newroot', C.syscall(isize(C.SYS_pivot_root), c'.', c'.') == 0, 0)
		check(mut s, c'detach stacked root', C.umount2(c'.', C.MNT_DETACH) == 0, 0)
		C.chdir(c'/')
		check(mut s, c'host tree gone', C.access(c'/tmp', C.F_OK) != 0, 0)
		check(mut s, c'own proc', C.access(c'/proc/self/status', C.R_OK) == 0, 0)
		// The network namespace has its loopback and nothing of the host's.
		check(mut s, c'loopback index', interface_index(c'lo') == 1, interface_index(c'lo'))
		ether := interface_index(c'eth0')
		check(mut s, c'no host interface', ether == -C.ENODEV, ether)
		up := loopback_up()
		check(mut s, c'loopback up', up == 0, up)
		host := connect_abstract()
		check(mut s, c'host abstract socket hidden', host == -C.ECONNREFUSED, host)
		if !reference {
			ip := failure(i64(C.socket(C.AF_INET, C.SOCK_STREAM, 0)))
			check(mut s, c'no IP stack', ip == -C.EAFNOSUPPORT, ip)
		}
		C.printf(c'LINUX USERNS SANDBOX: checks=%d failures=%d\n', s.checks, s.failures)
		C.fflush(nil)
		return if s.failures == 0 { 0 } else { 1 }
	}
}

fn drop_to_user() {
	unsafe {
		C.setgroups(0, nil)
		C.syscall(isize(C.SYS_setresgid), 1000, 1000, 1000)
		C.syscall(isize(C.SYS_setresuid), 1000, 1000, 1000)
		// Changing ids leaves a process undumpable, its /proc files root's;
		// a sandbox launcher (bubblewrap) is an ordinary exec and dumpable.
		C.prctl(C.PR_SET_DUMPABLE, 1, 0, 0, 0)
		C.prctl(C.PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0)
	}
}

fn unprivileged(reference bool) i32 {
	unsafe {
		mut s := State{}
		drop_to_user()
		plain := failure(i64(C.syscall(isize(C.SYS_unshare), u64(0x00020000))))
		check(mut s, c'mount namespace needs privilege', plain == -C.EPERM, plain)
		check(mut s, c'host abstract socket reachable', connect_abstract() == 0, connect_abstract())
		child := i32(C.syscall(isize(C.SYS_clone), clone_namespaces | u64(C.SIGCHLD), nil, nil, nil, nil))
		if child == 0 {
			C._exit(sandboxed(reference))
		}
		check(mut s, c'clone into new namespaces', child > 0, i64(child))
		mut status := i32(0)
		C.waitpid(child, &status, 0)
		check(mut s, c'sandbox passed', status == 0, i64(status))
		name := &char(C.alloca(64))
		C.memset(name, 0, 64)
		C.gethostname(name, 63)
		check(mut s, c'host hostname kept', C.strcmp(name, c'host') == 0, 0)
		check(mut s, c'host mounts kept', C.access(c'/tmp/ns/cover/hidden', C.F_OK) != 0, 0)
		C.printf(c'LINUX USERNS CHILD: checks=%d failures=%d\n', s.checks, s.failures)
		C.fflush(nil)
		return if s.failures == 0 { 0 } else { 1 }
	}
}

// A chrooted process could pivot out of its jail with namespace capabilities.
fn chrooted() i32 {
	unsafe {
		mut s := State{}
		check(mut s, c'jail', C.chroot(c'/tmp/ns/jail') == 0 && C.chdir(c'/') == 0, 0)
		drop_to_user()
		jailed := failure(i64(C.syscall(isize(C.SYS_unshare), u64(0x10000000))))
		check(mut s, c'no user namespace from a chroot', jailed == -C.EPERM, jailed)
		C.printf(c'LINUX USERNS JAIL: checks=%d failures=%d\n', s.checks, s.failures)
		C.fflush(nil)
		return if s.failures == 0 { 0 } else { 1 }
	}
}

// A proc mount must not uncover what a runtime masked in the inherited one:
// Linux allows it only while the namespace shows some proc in full.
fn masked_proc() i32 {
	unsafe {
		mut s := State{}
		check(mut s, c'own mount namespace', C.syscall(isize(C.SYS_unshare), u64(0x00020000)) == 0, 0)
		check(mut s, c'mask /proc/sys', C.mount(c'tmpfs', c'/proc/sys', c'tmpfs', 0, nil) == 0, 0)
		drop_to_user()
		child := i32(C.syscall(isize(C.SYS_clone), u64(0x10000000 | 0x00020000 | 0x20000000) | u64(C.SIGCHLD),
			nil, nil, nil, nil))
		if child == 0 {
			revealed := failure(i64(C.mount(c'proc', c'/proc', c'proc', 0, nil)))
			C._exit(if revealed == -C.EPERM { 0 } else if revealed == 0 { 100 } else { i32(-revealed) })
		}
		mut status := i32(-1)
		C.waitpid(child, &status, 0)
		check(mut s, c'no proc over a masked one', child > 0 && status == 0, i64(status))
		C.printf(c'LINUX USERNS MASK: checks=%d failures=%d\n', s.checks, s.failures)
		C.fflush(nil)
		return if s.failures == 0 { 0 } else { 1 }
	}
}

// Before any switch_root: a process whose root is the boot root is not in a
// chroot and may make a user namespace.
fn boot_root() i32 {
	unsafe {
		drop_to_user()
		return if C.syscall(isize(C.SYS_unshare), u64(0x10000000)) == 0 { 0 } else { 1 }
	}
}

fn run_child(mut s State, label &char, which int, reference bool) {
	unsafe {
		child := C.fork()
		if child == 0 {
			C._exit(match which {
				0 { unprivileged(reference) }
				1 { chrooted() }
				2 { masked_proc() }
				else { boot_root() }
			})
		}
		mut status := i32(0)
		C.waitpid(child, &status, 0)
		check(mut s, label, status == 0, i64(status))
	}
}

fn prepare(mut s State) i32 {
	unsafe {
		check(mut s, c'tmpfs', C.mount(c'tmpfs', c'/tmp', c'tmpfs', 0, nil) == 0, 0)
		C.mkdir(c'/tmp/ns', 0o755)
		C.mkdir(c'/tmp/ns/ro', 0o755)
		C.mkdir(c'/tmp/ns/cover', 0o755)
		C.mkdir(c'/tmp/ns/jail', 0o755)
		C.mkdir(c'/tmp/ns/open', 0o777)
		C.chmod(c'/tmp/ns/open', 0o777)
		secret := C.open(c'/tmp/ns/secret', C.O_WRONLY | C.O_CREAT, 0o600)
		C.write(secret, c'root only', 9)
		C.close(secret)
		hidden := C.open(c'/tmp/ns/cover/hidden', C.O_WRONLY | C.O_CREAT, 0o644)
		C.close(hidden)
		check(mut s, c'read-only mount', C.mount(c'tmpfs', c'/tmp/ns/ro', c'tmpfs', u64(C.MS_RDONLY), nil) == 0, 0)
		check(mut s, c'covering mount', C.mount(c'tmpfs', c'/tmp/ns/cover', c'tmpfs', 0, nil) == 0, 0)
		check(mut s, c'host hostname', C.sethostname(c'host', 4) == 0, 0)
		address := C.alloca(110)
		fill_abstract_address(&u8(address))
		listener := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
		check(mut s, c'host abstract listener', C.bind(listener, address, u32(2 + abstract_length)) == 0
			&& C.listen(listener, 8) == 0, 0)
		return listener
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		reference := argc > 1 && C.strcmp(argv[1], c'--reference') == 0
		mut s := State{}
		run_child(mut s, c'user namespace from the boot root', 3, reference)
		// Before the switch the namespace has one proc, the one this masks.
		run_child(mut s, c'masked proc child', 2, reference)
		// pivot_root cannot leave the initramfs root (Linux rootfs). Switch to
		// a tmpfs root first, as init systems do.
		C.mkdir(c'/switch', 0o755)
		check(mut s, c'new root', C.mount(c'tmpfs', c'/switch', c'tmpfs', 0, nil) == 0, 0)
		C.mkdir(c'/switch/proc', 0o555)
		C.mkdir(c'/switch/tmp', 0o1777)
		check(mut s, c'enter new root', C.chdir(c'/switch') == 0, 0)
		check(mut s, c'move onto /', C.mount(c'.', c'/', nil, u64(C.MS_MOVE), nil) == 0, 0)
		check(mut s, c'switch root', C.chroot(c'.') == 0 && C.chdir(c'/') == 0, 0)
		C.mount(c'proc', c'/proc', c'proc', 0, nil)
		listener := prepare(mut s)
		run_child(mut s, c'unprivileged child', 0, reference)
		run_child(mut s, c'chrooted child', 1, reference)
		C.close(listener)
		if !reference {
			retention(mut s)
		}
		C.printf(c'LINUX USERNS SUMMARY: checks=%d failures=%d\n', s.checks, s.failures)
		if s.failures == 0 {
			C.puts(if reference { c'LINUX USERNS REFERENCE: PASS' } else { c'LINUX USERNS: PASS' })
		}
		C.fflush(nil)
		for { C.pause() }
	}
	return 0
}

// Slab classes and large pages, from /proc/slabinfo.
struct Slabs {
mut:
	sizes [32]u64
	live  [32]u64
	rows  i32
	large u64
}

fn snapshot(fd i32, destination &Slabs) bool {
	unsafe {
		mut counts := &Slabs(destination)
		*counts = Slabs{}
		data := &char(C.alloca(4096))
		length := C.pread(fd, data, 4095, 0)
		if length <= 0 || length >= 4096 { return false }
		data[int(length)] = 0
		mut position := 0
		mut large := false
		for position < int(length) {
			mut size := u64(0)
			mut duplicate := u64(0)
			mut live := u64(0)
			mut pages := u64(0)
			if C.sscanf(&data[position], c'size-%lu %lu %lu %lu', &size, &duplicate, &live, &pages) == 4 {
				if counts.rows >= 32 || size != duplicate { return false }
				counts.sizes[counts.rows] = size
				counts.live[counts.rows] = live
				counts.rows++
			} else if C.sscanf(&data[position], c'large - - %lu', &counts.large) == 1 {
				large = true
			}
			for position < int(length) && data[position] != char(10) { position++ }
			position++
		}
		return large && counts.rows > 0
	}
}

// One sandbox, then everything in it exits. `user`: as bubblewrap makes it, an
// unprivileged process cloning into every namespace and mapping its ids.
// Otherwise root clones into the same namespaces but user and network. Both
// mount a tmpfs, make a directory, set a hostname, bind an abstract socket
// and send a loopback request.
fn sandbox_cycle(user bool) bool {
	unsafe {
		child := C.fork()
		if child == 0 {
			mut flags := clone_namespaces & ~u64(0x10000000 | 0x40000000)
			if user {
				drop_to_user()
				flags = clone_namespaces
			}
			inner := i32(C.syscall(isize(C.SYS_clone), flags | u64(C.SIGCHLD), nil, nil, nil, nil))
			if inner == 0 {
				mapped := !user || (write_file(c'/proc/self/uid_map', c'1000 1000 1') > 0
					&& write_file(c'/proc/self/setgroups', c'deny') > 0
					&& write_file(c'/proc/self/gid_map', c'1000 1000 1') > 0)
				ok := mapped && C.mount(c'tmpfs', c'/tmp/ns/open', c'tmpfs', 0, nil) == 0
					&& C.mkdir(c'/tmp/ns/open/dir', 0o755) == 0
					&& C.sethostname(c'sandbox', 7) == 0
				address := C.alloca(110)
				fill_abstract_address(&u8(address))
				listener := C.socket(C.AF_UNIX, C.SOCK_STREAM, 0)
				bound := C.bind(listener, address, u32(2 + abstract_length)) == 0
				C.close(listener)
				// The host refuses to change its loopback; only the result differs.
				up := loopback_up()
				C._exit(if ok && bound && (!user || up == 0) { 0 } else { 1 })
			}
			mut status := i32(-1)
			C.waitpid(inner, &status, 0)
			C._exit(if inner > 0 && status == 0 { 0 } else { 1 })
		}
		mut status := i32(-1)
		C.waitpid(child, &status, 0)
		return child > 0 && status == 0
	}
}

// What 100 sandboxes leave allocated in each slab class.
fn sandbox_growth(observer i32, user bool, growth &Slabs) bool {
	unsafe {
		mut good := true
		for _ in 0 .. 16 { good = sandbox_cycle(user) && good }
		C.usleep(13000000)
		before := &Slabs(C.alloca(usize(sizeof(Slabs))))
		mut after := &Slabs(growth)
		good = snapshot(observer, before) && good
		allocation_sites(false)
		for _ in 0 .. 100 { good = sandbox_cycle(user) && good }
		C.usleep(13000000)
		good = snapshot(observer, after) && good
		allocation_sites(true)
		if before.rows != after.rows { return false }
		for index in 0 .. int(after.rows) {
			if before.sizes[index] != after.sizes[index] { return false }
			after.live[index] -= before.live[index]
		}
		after.large -= before.large
		return good
	}
}

// What a user and a network namespace cost once their sandbox has exited.
// Vinix frees no namespace and no mount tree yet (fs.release_namespace drops
// only references), so a sandbox is not free; but one with a user and a
// network namespace may keep exactly those two namespace objects (192-byte
// class) more than the same sandbox made by root without them. Anything else
// -- id maps, socket names, netlink, credentials -- would grow for good.
fn retention(mut s State) {
	unsafe {
		observer := C.open(c'/proc/slabinfo', C.O_RDONLY)
		if observer < 0 {
			check(mut s, c'slabinfo', false, -i64(errno_value()))
			return
		}
		defer { C.close(observer) }
		plain := &Slabs(C.alloca(usize(sizeof(Slabs))))
		sandboxed := &Slabs(C.alloca(usize(sizeof(Slabs))))
		good := sandbox_growth(observer, false, plain) && sandbox_growth(observer, true, sandboxed)
		check(mut s, c'sandbox cycles', good && plain.rows == sandboxed.rows, 0)
		mut kept := good && i64(sandboxed.large) - i64(plain.large) <= 1
		for index in 0 .. int(plain.rows) {
			allowed := if plain.sizes[index] == 192 { i64(200) } else { i64(0) }
			// Other work in the guest (procfs nodes of earlier processes going, for
			// one) moves a class by up to a dozen objects either way; a leak per
			// sandbox moves it by at least 100.
			extra := i64(sandboxed.live[index]) - i64(plain.live[index]) - allowed
			if extra > 25 || extra < -25 {
				kept = false
				C.printf(c'LINUX USERNS SLAB: size=%lu root=%ld user=%ld cycles=100\n', plain.sizes[index],
					plain.live[index], sandboxed.live[index])
			}
		}
		C.printf(c'LINUX USERNS STORAGE: cycles=100 big_pages=%ld/%ld %s\n', plain.large, sandboxed.large,
			if kept { &char(c'PASS') } else { &char(c'FAIL') })
		C.fflush(nil)
		check(mut s, c'user and network namespaces keep only themselves', kept, 0)
	}
}

// On a kernel built with ALLOC_TRACK=1, start the allocation-site table over
// (`report` false) or print what is still live as PERF-SITE lines for
// tests/kernel-allocs/sites (`report` true). Other kernels have no such file.
fn allocation_sites(report bool) {
	unsafe {
		mut path := &char(c'/proc/allocstart')
		if report {
			path = &char(c'/proc/allocsites')
		}
		fd := C.open(path, C.O_RDONLY)
		if fd < 0 { return }
		defer { C.close(fd) }
		buffer := &char(C.malloc(262145))
		defer { C.free(buffer) }
		mut length := 0
		for length < 262144 {
			got := C.read(fd, &buffer[length], usize(262144 - length))
			if got <= 0 { break }
			length += int(got)
		}
		if !report {
			return
		}
		buffer[length] = 0
		mut start := 0
		for index in 0 .. length {
			if buffer[index] == char(10) {
				buffer[index] = 0
				C.printf(c'PERF-SITE userns %s\n', &buffer[start])
				start = index + 1
			}
		}
		C.fflush(nil)
	}
}
