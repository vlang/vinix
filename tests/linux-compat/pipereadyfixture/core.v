// SPDX-License-Identifier: GPL-2.0-or-later
module pipereadyfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <stdio.h>
#include <string.h>
#include <sys/epoll.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

struct C.timespec { mut: tv_sec i64 tv_nsec i64 }
@[typedef]
struct C.fd_set {}
@[typedef]
struct C.sigset_t {}
struct Poll { mut: fd i32 events i16 revents i16 }
struct PollGuard { mut: before u64 polls [2]Poll after u64 }
struct SetGuard { mut: before u64 words [16]u64 after u64 }
struct Totals { mut: checks int failures int }
struct Targets { mut: fds [10]i32 aliases [10]i32 queued [10]i32 }

fn C.alloca(usize) voidptr
fn C.syscall(isize,...) isize
fn C.__errno_location() &i32
fn C.open(&char,i32,...) i32
fn C.close(i32) i32
fn C.fcntl(i32,i32,...) i32
fn C.pipe2(&i32,i32) i32
fn C.pipe(&i32) i32
fn C.write(i32,voidptr,usize) isize
fn C.read(i32,voidptr,usize) isize
fn C.pread(i32,voidptr,usize,i64) isize
fn C.ioctl(i32,u64,...) i32
fn C.memcmp(voidptr,voidptr,usize) i32
fn C.memset(voidptr,i32,usize) voidptr
fn C.memcpy(voidptr,voidptr,usize) voidptr
fn C.sscanf(&char,&char,...) i32
fn C.printf(&char,...) i32
fn C.strcmp(&char,&char) i32
fn C.chmod(&char,u32) i32
fn C.fflush(voidptr) i32
fn C.fork() i32
fn C.waitpid(i32,&i32,i32) i32
fn C._exit(i32)
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.getuid() u32
fn C.getgid() u32
fn C.alarm(u32) u32
fn C.pause() i32
fn C.usleep(u32) i32
fn C.poll(voidptr,u64,i32) i32
fn C.ppoll(voidptr,u64,&C.timespec,voidptr) i32
fn C.select(i32,&C.fd_set,&C.fd_set,&C.fd_set,voidptr) i32
fn C.pselect(i32,&C.fd_set,&C.fd_set,&C.fd_set,&C.timespec,&C.sigset_t) i32
fn C.epoll_create1(i32) i32
fn C.epoll_ctl(i32,i32,i32,voidptr) i32
fn C.epoll_wait(i32,voidptr,i32,i32) i32

fn fatal(stage int) {
 C.printf(c'LINUX PIPEREADY FAIL: setup=%d errno=%d\n',stage,unsafe { *C.__errno_location() })
 C.fflush(unsafe { nil }); C._exit(90)
}
fn check(mut sum Totals, good bool) { sum.checks++; if !good { sum.failures++ } }
fn status(kind int) int {
 return match kind { 0,5 { 0 } 1,3 { 0x104 } 2,4 { 0x41 } 6 { 16 } 7 { 0x51 } 8 { 0x10c } else { 8 } }
}
fn events(profile int) int {
 return match profile { 0 { 0 } 1 { 1 } 2 { 2 } 3 { 4 } 4 { 5 } 5 { 0x40 } 6 { 0x80 } 7 { 0x100 } 8 { 0x200 } 9 { 0x41 } 10 { 0x104 } 11 { 0x145 } 12 { 0x7fff } 13 { 8 } 14 { 16 } else { 0x2000 } }
}
fn targets() Targets { unsafe {
 mut t := Targets{}
 data := C.alloca(65536); C.memset(data,0x51,65536)
 for state in 0 .. 7 {
  pair := &i32(C.alloca(usize(2*sizeof(i32))))
  if C.pipe2(pair,C.O_NONBLOCK) != 0 { fatal(1) }
  // Linux poll requires a free pipe-buffer slot: a single queued byte fills
  // a one-slot pipe for readiness even if later writes could merge into it.
  // Request two 4KiB slots so the queued/spare-capacity state is unambiguous.
  capacity := C.fcntl(pair[1],C.F_SETPIPE_SZ,8192)
  if capacity < 8192 || capacity > 65536 { fatal(2) }
  amount := if state in [2,6] { capacity } else if state in [1,4] { i32(1) } else { i32(0) }
  if amount > 0 && C.write(pair[1],data,usize(amount)) != amount { fatal(3) }
  if state < 3 {
   t.fds[state*2] = pair[0]; t.fds[state*2+1] = pair[1]
   t.queued[state*2] = amount; t.queued[state*2+1] = amount
  } else {
   index := state+3
   t.fds[index] = pair[if state < 5 { 0 } else { 1 }]
   t.queued[index] = amount
   if C.close(pair[if state < 5 { 1 } else { 0 }]) != 0 { fatal(4) }
  }
 }
 for kind in 0 .. 10 {
  t.aliases[kind] = C.fcntl(t.fds[kind],C.F_DUPFD_CLOEXEC,70)
  if t.aliases[kind] < 70 || t.aliases[kind] >= 1024 { fatal(5) }
 }
 return t
} }
fn intact(t &Targets,kind int) bool { unsafe {
 count := &i32(C.alloca(usize(sizeof(i32))))
 mode := if kind in [1,3,5,8,9] { C.O_WRONLY } else { C.O_RDONLY }
 return C.ioctl(t.fds[kind],u64(C.FIONREAD),count) == 0 && *count == t.queued[kind]
  && C.fcntl(t.fds[kind],C.F_GETFL) & (C.O_ACCMODE|C.O_NONBLOCK) == mode|C.O_NONBLOCK
} }
fn selected(t &Targets,kind int,layout int,out &i32) int { unsafe {
 out[0] = if layout == 1 { t.aliases[kind] } else { t.fds[kind] }
 out[1] = t.aliases[kind]
 return if layout == 2 { 2 } else { 1 }
} }
fn poll_call(api int,polls &Poll,count int) isize { unsafe {
 zero := &C.timespec(C.alloca(usize(sizeof(C.timespec)))); *zero = C.timespec{}
 match api {
  0 { return C.syscall(isize(C.SYS_ppoll),polls,u64(count),zero,nil,u64(8)) }
  1 { return C.ppoll(voidptr(polls),u64(count),zero,nil) }
  2 { return C.poll(voidptr(polls),u64(count),0) }
  else { $if amd64 { return C.syscall(isize(C.SYS_poll),polls,u64(count),u64(0)) } $else { fatal(6); return -1 } }
 }
} }
fn poll_probe(t &Targets,api int,kind int,layout int,profile int) Totals { unsafe {
 fds := &i32(C.alloca(usize(2*sizeof(i32)))); count := selected(t,kind,layout,fds)
 input := &PollGuard(C.alloca(usize(sizeof(PollGuard))))
 *input = PollGuard{before:0x1234432156788765,after:0x8765567812344321}
 for i in 0 .. 2 { input.polls[i] = Poll{fd:fds[i],events:i16(events(profile)),revents:123} }
 wanted := &PollGuard(C.alloca(usize(sizeof(PollGuard)))); *wanted = *input
 mask := (status(kind)&events(profile)) | (status(kind)&24)
 for i in 0 .. count { wanted.polls[i].revents = i16(mask) }
 slot := C.__errno_location(); *slot = 0
 ret := poll_call(api,&input.polls[0],count)
 code := *slot
 mut sum := Totals{}
 check(mut sum,ret == if mask == 0 { 0 } else { count })
 check(mut sum,code == 0)
 check(mut sum,C.memcmp(input,wanted,sizeof(PollGuard)) == 0)
 check(mut sum,intact(t,kind))
 return sum
} }
fn select_call(api int,nfds int,r &SetGuard,w &SetGuard,e &SetGuard,sets int,timer &C.timespec) isize { unsafe {
 rp := if sets&1 != 0 { &C.fd_set(&r.words[0]) } else { &C.fd_set(nil) }
 wp := if sets&2 != 0 { &C.fd_set(&w.words[0]) } else { &C.fd_set(nil) }
 ep := if sets&4 != 0 { &C.fd_set(&e.words[0]) } else { &C.fd_set(nil) }
 match api {
  0 { return C.syscall(isize(C.SYS_pselect6),nfds,rp,wp,ep,timer,nil) }
  1 { return C.pselect(nfds,rp,wp,ep,timer,nil) }
  2 { return C.select(nfds,rp,wp,ep,voidptr(timer)) }
  else { $if amd64 { return C.syscall(isize(C.SYS_select),nfds,rp,wp,ep,timer) } $else { fatal(7); return -1 } }
 }
} }
fn select_probe(t &Targets,api int,kind int,layout int,sets int) Totals { unsafe {
 fds := &i32(C.alloca(usize(2*sizeof(i32)))); count := selected(t,kind,layout,fds)
 nfds := int(fds[count-1])+1
 input := &SetGuard(C.alloca(usize(sizeof(SetGuard))))
 *input = SetGuard{before:0x1234432156788765,after:0x8765567812344321}
 for i in 0 .. count { input.words[fds[i]/64] |= u64(1)<<u64(fds[i]%64) }
 empty := &SetGuard(C.alloca(usize(sizeof(SetGuard)))); *empty = *input
 for i in 0 .. (nfds+63)/64 { empty.words[i] = 0 }
 r := &SetGuard(C.alloca(usize(sizeof(SetGuard)))); *r = *input
 w := &SetGuard(C.alloca(usize(sizeof(SetGuard)))); *w = *input
 e := &SetGuard(C.alloca(usize(sizeof(SetGuard)))); *e = *input
 readable := status(kind)&0xf9 != 0
 writable := status(kind)&0x30c != 0
 wanted := count*(if sets&1 != 0 && readable { 1 } else { 0 }) + count*(if sets&2 != 0 && writable { 1 } else { 0 })
 zero := &C.timespec(C.alloca(usize(sizeof(C.timespec)))); *zero = C.timespec{}
 slot := C.__errno_location(); *slot = 0
 ret := select_call(api,nfds,r,w,e,sets,zero)
 code := *slot
 mut sum := Totals{}
 check(mut sum,ret == wanted)
 check(mut sum,code == 0)
 check(mut sum,C.memcmp(r,if sets&1 == 0 || readable { input } else { empty },sizeof(SetGuard)) == 0)
 check(mut sum,C.memcmp(w,if sets&2 == 0 || writable { input } else { empty },sizeof(SetGuard)) == 0)
 check(mut sum,C.memcmp(e,if sets&4 == 0 { input } else { empty },sizeof(SetGuard)) == 0)
 check(mut sum,intact(t,kind))
 check(mut sum,zero.tv_sec == 0 && zero.tv_nsec == 0)
 return sum
} }
fn epoll_probe(t &Targets,kind int,layout int,profile int) Totals { unsafe {
 fds := &i32(C.alloca(usize(2*sizeof(i32)))); count := selected(t,kind,layout,fds)
 fd := C.epoll_create1(C.EPOLL_CLOEXEC)
 if fd < 0 { fatal(8) }
 mut size := 16; mut offset := 8
 $if amd64 { size = 12; offset = 4 }
 input := &u8(C.alloca(16)); tag := &u64(C.alloca(8))
 for i in 0 .. count {
  C.memset(input,0,16)
  *&u32(input) = u32(events(profile)); *tag = u64(i+1)
  C.memcpy(input+offset,tag,8)
  if C.epoll_ctl(fd,1,fds[i],voidptr(input)) != 0 { fatal(9) }
 }
 output := &u8(C.alloca(64)); C.memset(output,0xa5,64)
 slot := C.__errno_location(); *slot = 0
 ret := C.epoll_wait(fd,voidptr(output+8),2,0)
 code := *slot
 mask := (status(kind)&events(profile)) | (status(kind)&24)
 expected := if mask == 0 { 0 } else { count }
 mut good := ret == expected
 mut seen := u64(0)
 event := &u32(C.alloca(4)); data := &u64(C.alloca(8))
 if ret >= 0 && ret <= 2 { for i in 0 .. int(ret) {
  C.memcpy(event,output+8+i*size,4); C.memcpy(data,output+8+i*size+offset,8)
  if *event != u32(mask) || *data < 1 || *data > u64(count) || seen&(u64(1)<<*data) != 0 { good = false }
  else { seen |= u64(1)<<*data }
 } } else { good = false }
 for i in 0 .. 8 { if output[i] != 0xa5 { good = false } }
 for i in 8+int(if ret > 0 && ret <= 2 { ret } else { 0 })*size .. 64 { if output[i] != 0xa5 { good = false } }
 closed := C.close(fd)
 mut sum := Totals{}
 check(mut sum,ret == expected)
 check(mut sum,code == 0)
 check(mut sum,good)
 check(mut sum,closed == 0 && intact(t,kind))
 return sum
} }
fn qualify(t &Targets,apis int) Totals {
 mut total := Totals{}
 for family in 0 .. 3 { for api in 0 .. if family == 2 { 1 } else { apis } { for kind in 0 .. 10 {
 mut group := Totals{}
 for layout in 0 .. 3 { for profile in if family == 1 { 1 } else { 0 } .. if family == 1 { 8 } else { 16 } {
 result := if family == 0 { poll_probe(t,api,kind,layout,profile) } else if family == 1 { select_probe(t,api,kind,layout,profile) } else { epoll_probe(t,kind,layout,profile) }
 group.checks += result.checks; group.failures += result.failures
 } }
 C.printf(c'LINUX PIPEREADY CASE: uid=%u gid=%u family=%d api=%d kind=%d checks=%d failures=%d\n',C.getuid(),C.getgid(),family,api,kind,group.checks,group.failures)
 total.checks += group.checks; total.failures += group.failures
 } } }
 return total
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		C.alarm(600)
		if C.chmod(c'/tmp',0o1777) != 0 { fatal(20) }
		reference := argc == 2 && C.strcmp(argv[1],c'--reference') == 0
		mut apis := 3
		$if amd64 { apis = 4 }
		mut total := Totals{}
		mut storage_good := true
		for ordinary in [false,true]! {
			mut channel := [2]i32{}
			if C.pipe(&channel[0]) != 0 { fatal(8) }
			C.fflush(nil); pid := C.fork()
			if pid < 0 { fatal(9) }
			if pid == 0 {
				C.close(channel[0])
				if ordinary && (C.setgid(2000) != 0 || C.setuid(1000) != 0) { fatal(10) }
				t := &Targets(C.alloca(usize(sizeof(Targets))))
				*t = targets()
				sum := qualify(t,apis)
				good := if reference { C.printf(c'LINUX PIPEREADY STORAGE: uid=%u SKIP reference\n',C.getuid()); true } else { storage(t,apis) }
				mut answer := [3]int{}
				answer[0] = sum.checks; answer[1] = sum.failures; answer[2] = if good { 0 } else { 1 }
				if C.write(channel[1],&answer[0],sizeof(answer)) != isize(sizeof(answer)) { fatal(11) }
				C.fflush(nil); C._exit(0)
			}
			C.close(channel[1]); mut answer := [3]int{}
			if C.read(channel[0],&answer[0],sizeof(answer)) != isize(sizeof(answer)) { fatal(12) }
			C.close(channel[0]); mut status := i32(0)
			if C.waitpid(pid,&status,0) != pid || status != 0 { fatal(13) }
			total.checks += answer[0]; total.failures += answer[1]
			if answer[2] != 0 { storage_good = false }
		}
		C.printf(c'LINUX PIPEREADY SUMMARY: checks=%d failures=%d\n',total.checks,total.failures)
		C.printf(c'LINUX PIPEREADY: %s\n',if total.failures == 0 && storage_good { &char(c'PASS') } else { &char(c'FAIL') })
		C.fflush(nil); C.alarm(0)
		for { C.pause() }
	}
	return 0
}
