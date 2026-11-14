// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module ppollsignalfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <poll.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

@[typedef]
struct C.pthread_t {}
@[typedef]
struct C.sigset_t {}
@[typedef]
struct C.fd_set {}
struct C.timespec { mut: tv_sec i64 tv_nsec i64 }
struct C.sigaction {
mut:
	sa_handler fn (i32)
	sa_mask C.sigset_t
	sa_flags i32
}
struct Totals { mut: checks int failures int }
struct Guard { mut: before u64 words [16]u64 after u64 }
struct TimeGuard { mut: before u64 value C.timespec after u64 }
struct MaskArg { mut: mask voidptr size u64 }
struct PackGuard { mut: before u64 value MaskArg after u64 }
struct State {
mut:
	tid int
	pid int
	entered i32
	done i32
	slept int
	sent int
	calls int
	observed u64
	timeout &TimeGuard = unsafe { nil }
	seen C.timespec
}
struct Targets { source i32 peer i32 quiet i32 page voidptr page_size usize scratch &State }
__global ( active &State )

fn C.alloca(usize) voidptr
fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.dup3(i32, i32, i32) i32
fn C.socketpair(i32, i32, i32, &i32) i32
fn C.write(i32, voidptr, usize) isize
fn C.read(i32, voidptr, usize) isize
fn C.pread(i32, voidptr, usize, i64) isize
fn C.recv(i32, voidptr, usize, i32) isize
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.mprotect(voidptr, usize, i32) i32
fn C.sysconf(i32) isize
fn C.strcmp(&char, &char) i32
fn C.sscanf(&char, &char, ...) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.printf(&char, ...) i32
fn C.fflush(voidptr) i32
fn C.fork() i32
fn C.waitpid(i32, &i32, i32) i32
fn C._exit(i32)
fn C.setgid(u32) i32
fn C.setuid(u32) i32
fn C.getuid() u32
fn C.getgid() u32
fn C.alarm(u32) u32
fn C.pause() i32
fn C.usleep(u32) i32
fn C.pipe(&i32) i32
fn C.sigaction(i32, &C.sigaction, &C.sigaction) i32
fn C.sigemptyset(&C.sigset_t) i32
fn C.sigaddset(&C.sigset_t, i32) i32
fn C.pthread_create(&C.pthread_t, voidptr, fn (voidptr) voidptr, voidptr) i32
fn C.pthread_join(C.pthread_t, voidptr) i32
fn C.__atomic_load_n(&i32, i32) i32
fn C.__atomic_store_n(&i32, i32, i32)
fn C.clock_gettime(i32, &C.timespec) i32
fn C.pselect(i32, &C.fd_set, &C.fd_set, &C.fd_set, &C.timespec, &C.sigset_t) i32

fn fatal(stage int) {
	C.printf(c'LINUX PPOLLSIGNAL FAIL: setup=%d errno=%d\n', stage, unsafe { *C.__errno_location() })
	C.fflush(unsafe { nil }); C._exit(90)
}
fn check(mut total Totals, good bool, stage int, report bool) {
	total.checks++
	if !good {
		total.failures++
		if report { C.printf(c'LINUX PPOLLSIGNAL MISMATCH: stage=%d\n',stage) }
	}
}
fn stamp() C.timespec {
	mut value := C.timespec{}
	if C.clock_gettime(C.CLOCK_MONOTONIC,&value) != 0 { fatal(1) }
	return value
}
fn mask() u64 {
	mut value := u64(0)
	if C.syscall(isize(C.SYS_rt_sigprocmask),2,unsafe { nil },&value,8) != 0 { fatal(2) }
	return value
}
fn setmask(value u64) {
	if C.syscall(isize(C.SYS_rt_sigprocmask),2,&value,unsafe { nil },8) != 0 { fatal(3) }
}
fn handler(_signal i32) {
	unsafe { active.calls++; active.observed = mask(); active.seen = active.timeout.value }
}
fn sleeping(tid int) bool {
	mut path := [96]char{}
	if C.snprintf(&path[0],sizeof(path),c'/proc/self/task/%d/stat',tid) <= 0 { fatal(4) }
	fd := C.open(&path[0],C.O_RDONLY)
	if fd < 0 { fatal(5) }
	mut text := [1024]u8{}
	n := int(C.read(fd,&text[0],sizeof(text))); C.close(fd)
	if n < 4 { fatal(6) }
	for i := n - 3; i >= 0; i-- {
		if unsafe { (&u8(&text[0]))[i] } == `)` { return unsafe { (&u8(&text[0]))[i+2] } == `S` }
	}
	fatal(7); return false
}
fn observer(argument voidptr) voidptr {
	unsafe {
		mut s := &State(argument)
		for {
			if C.__atomic_load_n(&s.done,5) != 0 { return nil }
			if C.__atomic_load_n(&s.entered,5) == 0 || !sleeping(s.tid) {
				C.syscall(isize(C.SYS_sched_yield)); continue
			}
			if C.__atomic_load_n(&s.done,5) != 0 { return nil }
			before := stamp()
			if C.usleep(5000) != 0 { fatal(35) }
			after := stamp()
			if (after.tv_sec-before.tv_sec)*1_000_000_000+after.tv_nsec-before.tv_nsec < 1_000_000 { fatal(36) }
			s.slept = 1
			s.sent = int(C.syscall(isize(C.SYS_tgkill),s.pid,s.tid,C.SIGUSR1))
			return nil
		}
	}
}
fn targets(scratch &State) Targets {
	unsafe {
		mut pair := [4]i32{}
		if C.socketpair(C.AF_UNIX,C.SOCK_STREAM|C.SOCK_NONBLOCK,0,&pair[0]) != 0
			|| C.socketpair(C.AF_UNIX,C.SOCK_STREAM|C.SOCK_NONBLOCK,0,&pair[2]) != 0 { fatal(8) }
		if C.dup3(pair[0],1023,C.O_CLOEXEC) != 1023 || C.write(pair[1],c'Q',1) != 1 { fatal(9) }
		size := usize(C.sysconf(C._SC_PAGESIZE))
		page := C.mmap(nil,size,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0)
		if page == voidptr(-1) { fatal(10) }
		return Targets{pair[0],pair[1],pair[2],page,size,scratch}
	}
}
struct Poll { mut: fd i32 events i16 revents i16 }
struct PollGuard { mut: before u64 value Poll after u64 }
struct C.pollfd {}
fn C.ppoll(&C.pollfd,u64,&C.timespec,&C.sigset_t) i32
fn C.poll(&C.pollfd,u64,i32) i32
fn included(api int, mode int, ro int) bool { return api != 2 || (mode != 0 && ro == 0) }
// pthread_join may finish without entering FUTEX_WAIT during the warmup
// cycles. Initialize its kernel table explicitly so first contention cannot
// appear as retained poll storage. The temporary futex itself is released.
fn warm_join_futex() {
 unsafe {
 word := &i32(C.alloca(usize(sizeof(i32))))
 duration := &C.timespec(C.alloca(usize(sizeof(C.timespec))))
 *word = 0
 *duration = C.timespec{tv_nsec:1}
 // FUTEX_WAIT | FUTEX_PRIVATE_FLAG, with a positive relative timeout.
 result := C.syscall(isize(C.SYS_futex),word,isize(128),u32(0),duration,nil,u32(0))
 code := *C.__errno_location()
 if result != -1 || code != C.ETIMEDOUT || *word != 0 { fatal(37) }
 }
}
fn probe(t &Targets, api int, mode int, ro int, restart int, report bool) Totals {
 unsafe {
 mut s := t.scratch
 *s = State{tid:int(C.syscall(isize(C.SYS_gettid))),pid:int(C.syscall(isize(C.SYS_getpid))),sent:-99,timeout:&TimeGuard(t.page)}
 active = s
 mut action := C.sigaction{sa_handler:handler,sa_flags:if restart == 1 { C.SA_RESTART } else { 0 }}
 if C.sigemptyset(&action.sa_mask) != 0 || C.sigaddset(&action.sa_mask,C.SIGTERM) != 0 || C.sigaction(C.SIGUSR1,&action,nil) != 0 { fatal(12) }
 original_mask := u64(1)<<14 | if api == 2 { u64(0) } else { u64(1)<<9 }
 setmask(original_mask)
 wanted := &u64(C.alloca(usize(sizeof(u64))))
 *wanted = u64(1)<<12
 if C.mprotect(t.page,t.page_size,C.PROT_READ|C.PROT_WRITE) != 0 { fatal(13) }
 mut timer := &TimeGuard(t.page)
 *timer = TimeGuard{before:0x1234432156788765,after:0x8765567812344321,value:C.timespec{tv_sec:5}}
 if ro == 1 && C.mprotect(t.page,t.page_size,C.PROT_READ) != 0 { fatal(14) }
 buffer := &PollGuard(C.alloca(usize(sizeof(PollGuard))))
 *buffer = PollGuard{before:timer.before,after:timer.after,value:Poll{fd:t.quiet,events:1,revents:123}}
 desired := &PollGuard(C.alloca(usize(sizeof(PollGuard))))
 *desired = *buffer
 if mode == 2 { desired.value.revents = 0 }
 mut worker := C.pthread_t{}
 if mode == 0 {
  if C.syscall(isize(C.SYS_tgkill),s.pid,s.tid,C.SIGUSR1) != 0 || s.calls != 0 { fatal(15) }
 } else if C.pthread_create(&worker,nil,observer,s) != 0 { fatal(16) }
 started := stamp()
 C.__atomic_store_n(&s.entered,1,5)
 errno_slot := C.__errno_location(); *errno_slot = 0
 nfds := if mode == 2 { u64(1) } else { u64(0) }
 ret := if api == 0 { C.syscall(isize(C.SYS_ppoll),&buffer.value,nfds,&timer.value,wanted,u64(8)) } else if api == 1 { isize(C.ppoll(&C.pollfd(voidptr(&buffer.value)),nfds,&timer.value,&C.sigset_t(voidptr(wanted)))) } else { isize(C.poll(&C.pollfd(voidptr(&buffer.value)),nfds,5000)) }
 code := *errno_slot
 C.__atomic_store_n(&s.done,1,5)
 stopped := stamp()
 if mode != 0 && C.pthread_join(worker,nil) != 0 { fatal(17) }
 mut total := Totals{}
 check(mut total,ret == -1,1,report)
 check(mut total,code == C.EINTR,2,report)
 check(mut total,C.memcmp(buffer,desired,sizeof(PollGuard)) == 0,3,report)
 check(mut total,timer.before == buffer.before && timer.after == buffer.after,4,report)
 elapsed := (stopped.tv_sec-started.tv_sec)*1_000_000_000+stopped.tv_nsec-started.tv_nsec
 time_good := if ro == 1 || api != 0 { timer.value.tv_sec == 5 && timer.value.tv_nsec == 0 } else { remaining_within_bounds(timer.value.tv_sec,timer.value.tv_nsec,5_000_000_000,elapsed,1) && (mode == 0 || timer.value.tv_sec < 5) }
 check(mut total,time_good,5,report)
 check(mut total,mask() == original_mask,6,report)
 mut byte := u8(0)
 check(mut total,C.recv(t.source,&byte,1,C.MSG_PEEK|C.MSG_DONTWAIT) == 1 && byte == `Q`,7,report)
 check(mut total,s.calls == 1,8,report)
 expected_mask := (if api == 2 { original_mask } else { u64(1)<<12 }) | u64(1)<<9 | u64(1)<<14
 check(mut total,s.observed == expected_mask,9,report)
 check(mut total,s.seen.tv_sec == timer.value.tv_sec && s.seen.tv_nsec == timer.value.tv_nsec,10,report)
 check(mut total,if mode == 0 { s.slept == 0 && s.sent == -99 } else { s.slept == 1 && s.sent == 0 },11,report)
 mut pending := u64(0)
 check(mut total,C.syscall(isize(C.SYS_rt_sigpending),&pending,8) == 0 && pending & (u64(1)<<9) == 0 && *wanted == u64(1)<<12,12,report)
 return total
 }
}
fn qualify(t &Targets, apis int) Totals {
 mut total := Totals{}
 for api in 0 .. apis { for mode in 0 .. 3 { for ro in 0 .. 2 { for restart in 0 .. 2 {
 if !included(api,mode,ro) { continue }
 sum := probe(t,api,mode,ro,restart,true)
 C.printf(c'LINUX PPOLLSIGNAL CASE: uid=%u gid=%u api=%d mode=%d readonly=%d restart=%d checks=%d failures=%d\n',C.getuid(),C.getgid(),api,mode,ro,restart,sum.checks,sum.failures)
 total.checks += sum.checks; total.failures += sum.failures
 } } } }
 return total
}
@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
	unsafe {
		C.alarm(600)
		reference := argc == 2 && C.strcmp(argv[1],c'--reference') == 0
		apis := 3
		mut total := Totals{}
		mut storage_good := true
		for ordinary in [false,true]! {
			mut channel := [2]i32{}
			if C.pipe(&channel[0]) != 0 { fatal(21) }
			C.fflush(nil); pid := C.fork()
			if pid < 0 { fatal(22) }
			if pid == 0 {
				C.close(channel[0])
				if ordinary && (C.setgid(2000) != 0 || C.setuid(1000) != 0) { fatal(23) }
				// Entry-frame state outlives handlers, observer joins and reporting.
				scratch := &State(C.alloca(usize(sizeof(State))))
				t := targets(scratch)
				warm_join_futex()
				sum := qualify(&t,apis)
				good := if reference { C.printf(c'LINUX PPOLLSIGNAL STORAGE: uid=%u SKIP reference\n',C.getuid()); true } else { storage(&t,apis) }
				mut answer := [3]int{}
				answer[0] = sum.checks; answer[1] = sum.failures; answer[2] = if good { 0 } else { 1 }
				if C.write(channel[1],&answer[0],sizeof(answer)) != isize(sizeof(answer)) { fatal(24) }
				C.fflush(nil); C._exit(0)
			}
			C.close(channel[1]); mut answer := [3]int{}
			if C.read(channel[0],&answer[0],sizeof(answer)) != isize(sizeof(answer)) { fatal(25) }
			C.close(channel[0]); mut status := i32(0)
			if C.waitpid(pid,&status,0) != pid || status != 0 { fatal(26) }
			total.checks += answer[0]; total.failures += answer[1]
			if answer[2] != 0 { storage_good = false }
		}
		C.printf(c'LINUX PPOLLSIGNAL SUMMARY: checks=%d failures=%d\n',total.checks,total.failures)
		C.printf(c'LINUX PPOLLSIGNAL: %s\n',if total.failures == 0 && storage_good { &char(c'PASS') } else { &char(c'FAIL') })
		C.fflush(nil); C.alarm(0)
		for { C.pause() }
	}
	return 0
}
