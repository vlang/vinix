// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What an ordinary account is refused. The sweep below is run as Sam, after
// the session's own drop of privilege, and tries what only an administrator
// of the machine should be able to do, one system call each. Every line of
// it must be a refusal.
//
// The same calls are first made as root, where the harmless ones must
// succeed: a sweep that passes because the kernel has none of these calls
// would prove nothing.
module main

import os

#include <sys/mount.h>
#include <sys/swap.h>
#include <sys/time.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <sched.h>
#include <signal.h>
#include <time.h>

fn C.mount(source &char, target &char, kind &char, flags u64, data voidptr) int
fn C.umount2(target &char, flags int) int
fn C.sethostname(name &char, length usize) int
fn C.setdomainname(name &char, length usize) int
fn C.clock_settime(clock int, time voidptr) int
fn C.clock_gettime(clock int, time voidptr) int
fn C.mknod(path &char, mode u32, device u64) int
fn C.chroot(path &char) int
fn C.setuid(uid u32) int
fn C.setgid(gid u32) int
fn C.setgroups(count usize, list &u32) int
fn C.setresuid(real u32, effective u32, saved u32) int
fn C.lchown(path &char, owner u32, group u32) int
fn C.kill(pid int, signal int) int
fn C.bind(fd int, address voidptr, length u32) int
fn C.setpriority(which int, who u32, priority int) int
fn C.setrlimit(resource int, limit voidptr) int
fn C.getrlimit(resource int, limit voidptr) int
fn C.link(old &char, new &char) int
fn C.rename(old &char, new &char) int
fn C.unlink(path &char) int
fn C.swapon(path &char, flags int) int
fn C.syscall(number i64, ...voidptr) i64

struct TimeSpec {
mut:
	seconds     i64
	nanoseconds i64
}

struct RLimit {
mut:
	soft u64
	hard u64
}

struct SockaddrIn {
mut:
	family  u16
	port    u16
	address u32
	zero    [8]u8
}

fn outcome(result i64) string {
	return if result >= 0 { 'allowed' } else { C.errno.str() }
}

fn line(name string, result i64) {
	println('SWEEP ${name} ${outcome(result)}')
}

// `others` are pids of processes that are not the caller's: one of root's
// and one of another account's.
fn probe_sweep(others []string) int {
	root_pid := if others.len > 0 { others[0].int() } else { 1 }
	other_pid := if others.len > 1 { others[1].int() } else { 1 }
	control := others.len > 2 && others[2] == 'control'

	line('mount', C.mount(c'none', c'/mnt', c'tmpfs', 0, unsafe { nil }))
	if !control {
		line('umount', C.umount2(c'/proc', 0))
		line('umount-mnt', C.umount2(c'/mnt', 0))
	}
	line('sethostname', C.sethostname(c'swept', 5))
	line('setdomainname', C.setdomainname(c'swept', 5))
	mut now := TimeSpec{}
	C.clock_gettime(0, voidptr(&now))
	line('clock_settime', C.clock_settime(0, voidptr(&now)))
	// A character device: /dev/null's numbers, which would be harmless, and
	// a disk's, which would not.
	line('mknod-char', C.mknod(c'/tmp/swept-null', 0o020666, u64((1 << 8) | 3)))
	line('mknod-block', C.mknod(c'/tmp/swept-disk', 0o060666, u64((8 << 8) | 0)))
	if !control {
		line('chroot', C.chroot(c'/tmp'))
		line('setuid-0', C.setuid(0))
		line('setgid-0', C.setgid(0))
		line('setresuid-0', C.setresuid(u32(-1), 0, u32(-1)))
		line('setgroups', C.setgroups(0, unsafe { nil }))
		line('chown-passwd', C.lchown(c'/etc/passwd', C.getuid(), C.getgid()))
		line('chown-give-away', C.lchown(c'/tmp/swept-own', 0, 0))
		line('chmod-shadow', C.chmod(c'/etc/shadow', 0o644))
		line('unlink-passwd', C.unlink(c'/etc/passwd'))
		line('rename-passwd', C.rename(c'/etc/passwd', c'/etc/passwd.swept'))
		line('link-shadow', C.link(c'/etc/shadow', c'/tmp/swept-shadow'))
		line('kill-init', C.kill(1, C.SIGTERM))
		line('kill-root', C.kill(root_pid, C.SIGKILL))
		line('kill-other', C.kill(other_pid, C.SIGKILL))
		line('signal-0-other', C.kill(other_pid, 0))
		for path in ['/proc/1/environ', '/proc/1/mem', '/proc/1/maps', '/proc/${other_pid}/environ',
			'/proc/${other_pid}/mem', '/proc/${other_pid}/maps'] {
			fd := C.open(&char(path.str), C.O_RDONLY)
			mut result := i64(fd)
			if fd >= 0 {
				mut buffer := [64]u8{}
				result = i64(C.read(fd, &buffer[0], 64))
				C.close(fd)
				// Nothing to read is as good as not being let in.
				if result == 0 {
					C.errno = 13
					result = -1
				}
			}
			line('read ${path.replace(other_pid.str(), 'OTHER')}', result)
		}
		for path in ['/proc/sys/kernel/hostname', '/proc/sys/kernel/securelevel', '/sys/power/state',
			'/sys/power/pm_test', '/proc/sysrq-trigger'] {
			fd := C.open(&char(path.str), C.O_WRONLY)
			mut result := i64(fd)
			if fd >= 0 {
				// Nothing that would do anything if it were let through.
				result = i64(C.write(fd, c'none\n', 5))
				C.close(fd)
			} else if C.errno == 2 {
				continue
			}
			line('write ${path}', result)
		}
		// Every disk and every other block device there is.
		for entry in os.ls('/dev') or { []string{} } {
			path := '/dev/${entry}'
			info := os.lstat(path) or { continue }
			if info.get_filetype() != .block_device {
				continue
			}
			fd := C.open(&char(path.str), C.O_RDONLY)
			line('open-disk ${path}', fd)
			if fd >= 0 {
				C.close(fd)
			}
			wfd := C.open(&char(path.str), C.O_WRONLY)
			line('open-disk-write ${path}', wfd)
			if wfd >= 0 {
				C.close(wfd)
			}
		}
		for path in ['/dev/mem', '/dev/kmem', '/dev/port'] {
			fd := C.open(&char(path.str), C.O_RDONLY)
			if fd < 0 && C.errno == 2 {
				continue
			}
			line('open ${path}', fd)
		}
		line('swapon', C.swapon(c'/tmp/swept-own', 0))
		mut limit := RLimit{}
		C.getrlimit(7, voidptr(&limit))
		limit.hard += 1
		line('setrlimit-raise', C.setrlimit(7, voidptr(&limit)))
		// PTRACE_ATTACH to init; a kernel without ptrace refuses as well.
		$if amd64 {
			line('ptrace-init', C.syscall(101, voidptr(16), voidptr(1), voidptr(0), voidptr(0)))
			line('ioperm', C.syscall(173, voidptr(0), voidptr(1024), voidptr(1)))
			line('iopl', C.syscall(172, voidptr(3)))
			line('reboot-halt', C.syscall(169, voidptr(0xfee1dead), voidptr(0x28121969), voidptr(0xcdef0123),
				voidptr(0)))
			line('syslog-read', C.syscall(103, voidptr(3), voidptr(0), voidptr(0)))
			line('kexec_load', C.syscall(246, voidptr(0), voidptr(0), voidptr(0), voidptr(0)))
			line('init_module', C.syscall(175, voidptr(0), voidptr(0), voidptr(0)))
		} $else {
			line('ptrace-init', C.syscall(117, voidptr(16), voidptr(1), voidptr(0), voidptr(0)))
			line('reboot-halt', C.syscall(142, voidptr(0xfee1dead), voidptr(0x28121969), voidptr(0xcdef0123),
				voidptr(0)))
			line('syslog-read', C.syscall(116, voidptr(3), voidptr(0), voidptr(0)))
			line('kexec_load', C.syscall(104, voidptr(0), voidptr(0), voidptr(0), voidptr(0)))
			line('init_module', C.syscall(105, voidptr(0), voidptr(0), voidptr(0)))
		}
	}
	// Sockets a program does not get to have without asking the system.
	low := C.socket(C.AF_INET, C.SOCK_STREAM, 0)
	mut address := SockaddrIn{
		family: u16(C.AF_INET)
		port:   u16(80 << 8) // port 80, network order
	}
	line('bind-80', C.bind(low, voidptr(&address), u32(sizeof(SockaddrIn))))
	C.close(low)
	raw := C.socket(C.AF_INET, C.SOCK_RAW, 1)
	line('raw-socket', raw)
	if raw >= 0 {
		C.close(raw)
	}
	packet := C.socket(17, C.SOCK_RAW, 0x0300)
	line('packet-socket', packet)
	if packet >= 0 {
		C.close(packet)
	}
	// Taking the processor from everyone else.
	line('nice-raise', C.setpriority(0, 0, -10))
	mut priority := i32(10)
	// The system call itself: musl's sched_setscheduler() refuses without
	// asking the kernel.
	$if amd64 {
		line('realtime', C.syscall(144, voidptr(0), voidptr(1), voidptr(&priority)))
	} $else {
		line('realtime', C.syscall(119, voidptr(0), voidptr(1), voidptr(&priority)))
	}
	return 0
}

// The lines of a sweep by name.
fn sweep_results(output string) map[string]string {
	mut results := map[string]string{}
	for text in output.split_into_lines() {
		if !text.starts_with('SWEEP ') {
			continue
		}
		rest := text[6..]
		split := rest.last_index(' ') or { continue }
		results[rest[..split]] = rest[split + 1..]
	}
	return results
}

fn scenario_unprivileged(mut t Test) {
	db := t.make_accounts()
	alex := must_user(db, 'alex')
	sam := must_user(db, 'sam')
	os.mkdir_all('/mnt') or {}
	os.write_file('/tmp/swept-own', 'sam\'s\n') or {}
	os.chown('/tmp/swept-own', int(sam.uid), int(sam.gid)) or {}

	// Someone else's processes to aim at: one of root's, one of Alex's.
	root_child := C.fork()
	if root_child == 0 {
		C.usleep(60_000_000)
		C._exit(0)
	}
	alex_child := C.fork()
	if alex_child == 0 {
		probe(['sleep', '60'], db, alex)
		C._exit(0)
	}
	C.usleep(300_000)
	// probe() forks once more before it becomes Alex: find that process.
	mut alex_pid := 0
	for entry in os.ls('/proc') or { []string{} } {
		pid := entry.int()
		if pid <= 1 || pid == alex_child {
			continue
		}
		for text in read_text('/proc/${entry}/status').split_into_lines() {
			if text.starts_with('Uid:') && text.all_after(':').trim_space().starts_with(alex.uid.str()) {
				alex_pid = pid
			}
		}
	}
	if alex_pid == 0 {
		// Not to be aimed at: pid 0 is the caller's own process group.
		alex_pid = root_child
	}
	t.check(alex_pid != 0, 'no process of alex was found in /proc')

	// As root, the harmless calls work: the sweep means something.
	control := sweep_results(run(['/sbin/init', 'probe', 'sweep', root_child.str(), alex_pid.str(),
		'control'], '', none, none).output)
	for name in ['mount', 'sethostname', 'setdomainname', 'clock_settime', 'mknod-char', 'bind-80',
		'nice-raise', 'realtime'] {
		t.check(control[name] == 'allowed', 'as root, ${name}: ${control[name]}')
	}
	t.info('as root: raw-socket ${control['raw-socket']}, packet-socket ${control['packet-socket']}, mknod-block ${control['mknod-block']}')
	C.umount2(c'/mnt', 0)
	os.rm('/tmp/swept-null') or {}
	os.rm('/tmp/swept-disk') or {}

	swept := run(['/sbin/init', 'probe', 'sweep', root_child.str(), alex_pid.str()], '',
		db, sam)
	results := sweep_results(swept.output)
	t.check(results.len >= 40, 'the sweep made only ${results.len} attempts: ${swept.output}')
	// EPERM and EACCES are refusals. A call the kernel does not have at all
	// (ENOSYS), or a family it does not speak, cannot be misused either.
	absent_ok := ['ptrace-init', 'ioperm', 'iopl', 'kexec_load', 'init_module', 'syslog-read',
		'packet-socket', 'raw-socket', 'swapon']
	mut names := results.keys()
	names.sort()
	for name in names {
		result := results[name]
		refused := result == '1' || result == '13'
		// /proc/<pid>/mem does not exist on this kernel.
		absent := (name in absent_ok && result in ['38', '97', '22', '93', '94'])
			|| (name.ends_with('/mem') && result == '2')
		t.check(refused || absent, 'sam: ${name}: ${if result == 'allowed' {
			'ALLOWED'
		} else {
			'errno ' + result
		}}')
	}
	// And nothing of it happened.
	t.check((os.hostname() or { '' }) != 'swept' || control['sethostname'] == 'allowed', 'the host name changed')
	t.check(os.exists('/etc/passwd') && owner_of('/etc/passwd') == 0 && mode_of('/etc/shadow') == 0o600,
		'the account files were touched')
	t.check(!os.exists('/tmp/swept-shadow') && !os.exists('/tmp/swept-disk') && !os.exists('/tmp/swept-null'),
		'the sweep left something in /tmp')
	t.check(owner_of('/tmp/swept-own') == int(sam.uid), 'sam gave a file away to root')
	t.check(C.kill(root_child, 0) == 0 && C.kill(alex_pid, 0) == 0, 'a process that was not sam\'s is gone')
	C.kill(root_child, C.SIGKILL)
	C.kill(alex_pid, C.SIGKILL)
}
