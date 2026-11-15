// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module selectwakefixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/select.h>
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
struct Poll { mut: fd i32 events i16 revents i16 }
struct Totals { mut: checks int failures int }
struct Guard { mut: before u64 words [16]u64 after u64 }
struct TimeGuard { mut: before u64 value C.timespec after u64 }
struct MaskArg { mut: mask voidptr size u64 }
struct State {
mut:
 pid int
 tid int
 entered i32
 done i32
 sleeps int
 sent int
 calls int
 observed u64
}
struct Targets { mut: fds [4]i32 aliases [4]i32 peer i32 scratch &State }
__global ( active &State )

fn C.alloca(usize) voidptr
fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.open(&char,i32,...) i32
fn C.close(i32) i32
fn C.fcntl(i32,i32,...) i32
fn C.chmod(&char,u32) i32
fn C.pipe(&i32) i32
fn C.read(i32,voidptr,usize) isize
fn C.pread(i32,voidptr,usize,i64) isize
fn C.write(i32,voidptr,usize) isize
fn C.ioctl(i32,u64,...) i32
fn C.memcmp(voidptr,voidptr,usize) i32
fn C.memset(voidptr,i32,usize) voidptr
fn C.snprintf(&char,usize,&char,...) i32
fn C.sscanf(&char,&char,...) i32
fn C.printf(&char,...) i32
fn C.fflush(voidptr) i32
fn C.strcmp(&char,&char) i32
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
fn C.sigaction(i32,&C.sigaction,&C.sigaction) i32
fn C.sigemptyset(&C.sigset_t) i32
fn C.pthread_create(&C.pthread_t,voidptr,fn (voidptr) voidptr,voidptr) i32
fn C.pthread_join(C.pthread_t,voidptr) i32
fn C.__atomic_load_n(&i32,i32) i32
fn C.__atomic_store_n(&i32,i32,i32)
fn C.pselect(i32,&C.fd_set,&C.fd_set,&C.fd_set,&C.timespec,&C.sigset_t) i32
fn C.select(i32,&C.fd_set,&C.fd_set,&C.fd_set,voidptr) i32

fn fatal(stage int) {
 C.printf(c'LINUX SELECTWAKE FAIL: setup=%d errno=%d\n',stage,unsafe { *C.__errno_location() })
 C.fflush(unsafe { nil }); C._exit(90)
}
fn check(mut t Totals, good bool) { t.checks++; if !good { t.failures++ } }
fn mask() u64 { unsafe {
 value := &u64(C.alloca(8))
 if C.syscall(isize(C.SYS_rt_sigprocmask),2,nil,value,u64(8)) != 0 { fatal(1) }
 return *value
} }
fn handler(_signal i32) { unsafe { active.calls++; active.observed = mask() } }
fn sleeping(tid int) bool { unsafe {
 path := &char(C.alloca(96))
 text := &u8(C.alloca(1024))
 if C.snprintf(path,96,c'/proc/self/task/%d/stat',tid) <= 0 { fatal(2) }
 fd := C.open(path,C.O_RDONLY)
 if fd < 0 { fatal(3) }
 n := int(C.read(fd,text,1024))
 if C.close(fd) != 0 || n < 4 { fatal(4) }
 for i := n-3; i >= 0; i-- { if text[i] == `)` { return text[i+2] == `S` } }
 fatal(5); return false
} }
fn observer(argument voidptr) voidptr { unsafe {
 mut s := &State(argument)
 for {
  if C.__atomic_load_n(&s.done,5) != 0 { return nil }
  if C.__atomic_load_n(&s.entered,5) == 0 || !sleeping(s.tid) { C.syscall(isize(C.SYS_sched_yield)); continue }
  if C.__atomic_load_n(&s.done,5) != 0 { return nil }
  if s.sleeps == 0 {
   s.sleeps = 1
   C.usleep(5000)
   continue
  }
  s.sleeps = 2
  s.sent = int(C.syscall(isize(C.SYS_tgkill),s.pid,s.tid,C.SIGUSR1))
  return nil
 }
} }
fn targets(scratch &State) Targets { unsafe {
 mut t := Targets{scratch:scratch}
 for kind in 0 .. 4 {
  pair := &i32(C.alloca(usize(2*sizeof(i32))))
  if C.pipe(pair) != 0 { fatal(6) }
  if kind == 1 && C.write(pair[1],c'Q',1) != 1 { fatal(7) }
  if kind == 2 { t.fds[kind] = pair[1]; if C.close(pair[0]) != 0 { fatal(8) } }
  else { t.fds[kind] = pair[0]; if kind < 2 { if C.close(pair[1]) != 0 { fatal(9) } } else { t.peer = pair[1] } }
  t.aliases[kind] = C.fcntl(t.fds[kind],C.F_DUPFD_CLOEXEC,70)
  if t.aliases[kind] < 70 || t.aliases[kind] >= 1024 { fatal(10) }
 }
 // Joins need not contend during qualification. Warm lazy futex-map capacity
 // before either cohort measures repeated pthread creation and teardown.
 word := &i32(C.alloca(usize(sizeof(i32))))
 timeout := &C.timespec(C.alloca(usize(sizeof(C.timespec))))
 *word = 0; *timeout = C.timespec{tv_nsec:1}
 if C.syscall(isize(C.SYS_futex),word,isize(128),u32(0),timeout,nil,u32(0)) != -1 || *C.__errno_location() != C.ETIMEDOUT { fatal(11) }
 return t
} }
fn kind_for(mode int) int { return match mode { 0,3,6 { 0 } 1,4 { 1 } 2,5,7 { 2 } else { 3 } } }
fn interrupted(mode int) bool { return mode !in [3,4,5] }
fn make_set(low i32, high i32, layout int) Guard { unsafe {
 mut g := Guard{before:0xabcddcba12344321,after:0x87654321fedcba98}
 if layout != 1 { g.words[low/64] |= u64(1)<<u64(low%64) }
 if layout != 0 { g.words[high/64] |= u64(1)<<u64(high%64) }
 return g
} }
fn call(api int,nfds int,reads &Guard,writes &Guard,excepts &Guard,mode int,timeout &C.timespec,temporary &u64) isize { unsafe {
 r := if mode in [3,4] { &C.fd_set(&reads.words[0]) } else { &C.fd_set(nil) }
 w := if mode == 5 { &C.fd_set(&writes.words[0]) } else { &C.fd_set(nil) }
 e := &C.fd_set(&excepts.words[0])
 pack := &MaskArg(C.alloca(usize(sizeof(MaskArg))))
 *pack = MaskArg{mask:temporary,size:8}
 match api {
  0 { return C.syscall(isize(C.SYS_pselect6),nfds,r,w,e,timeout,pack) }
  1 { return C.pselect(nfds,r,w,e,timeout,&C.sigset_t(temporary)) }
  2 { return C.select(nfds,r,w,e,voidptr(timeout)) }
  else { $if amd64 { return C.syscall(isize(C.SYS_select),nfds,r,w,e,timeout) } $else { fatal(12); return -1 } }
 }
} }
fn probe(t &Targets,api int,mode int,layout int,restart int) Totals { unsafe {
 C.alarm(30)
 mut s := t.scratch
 *s = State{pid:int(C.syscall(isize(C.SYS_getpid))),tid:int(C.syscall(isize(C.SYS_gettid))),sent:-99}
 active = s
 action := &C.sigaction(C.alloca(usize(sizeof(C.sigaction))))
 *action = C.sigaction{sa_handler:handler,sa_flags:if restart == 1 { C.SA_RESTART } else { 0 }}
 if C.sigemptyset(&action.sa_mask) != 0 || C.sigaction(C.SIGUSR1,action,nil) != 0 { fatal(13) }
 original := u64(1)<<11
 if C.syscall(isize(C.SYS_rt_sigprocmask),2,&original,nil,u64(8)) != 0 { fatal(14) }
 temporary := &u64(C.alloca(128)); C.memset(temporary,0,128); *temporary = original | u64(1)<<14
 input := &Guard(C.alloca(usize(sizeof(Guard))))
 kind := kind_for(mode)
 fd := t.fds[kind]
 high := t.aliases[kind]
 nfds := int(if layout == 0 { fd } else { high })+1
 *input = make_set(fd,high,layout)
 reads := &Guard(C.alloca(usize(sizeof(Guard))))
 writes := &Guard(C.alloca(usize(sizeof(Guard))))
 excepts := &Guard(C.alloca(usize(sizeof(Guard))))
 *reads = *input; *writes = *input; *excepts = *input
 timer := &TimeGuard(C.alloca(usize(sizeof(TimeGuard))))
 *timer = TimeGuard{before:0x1234432156788765,after:0x8765567812344321,value:C.timespec{tv_sec:5}}
 timeout := if mode in [6,7,9] { &C.timespec(nil) } else { &timer.value }
 worker := &C.pthread_t(C.alloca(usize(sizeof(C.pthread_t))))
 if interrupted(mode) && C.pthread_create(worker,nil,observer,s) != 0 { fatal(15) }
 errno_slot := C.__errno_location(); *errno_slot = 0
 C.__atomic_store_n(&s.entered,1,5)
 result := call(api,nfds,reads,writes,excepts,mode,timeout,temporary)
 code := *C.__errno_location()
 C.__atomic_store_n(&s.done,1,5)
 if interrupted(mode) && C.pthread_join(*worker,nil) != 0 { fatal(16) }
 expected := if interrupted(mode) { isize(-1) } else if layout == 2 { isize(2) } else { isize(1) }
 empty := &Guard(C.alloca(usize(sizeof(Guard)))); *empty = *input
 for i in 0 .. (nfds+63)/64 { empty.words[i] = 0 }
 mut sum := Totals{}
 check(mut sum,result == expected)
 check(mut sum,code == if interrupted(mode) { C.EINTR } else { 0 })
 check(mut sum,C.memcmp(reads,input,sizeof(Guard)) == 0)
 check(mut sum,C.memcmp(writes,input,sizeof(Guard)) == 0)
 check(mut sum,C.memcmp(excepts,if interrupted(mode) { input } else { empty },sizeof(Guard)) == 0)
 check(mut sum,mask() == original)
 check(mut sum,s.calls == if interrupted(mode) { 1 } else { 0 })
 check(mut sum,s.sleeps == if interrupted(mode) { 2 } else { 0 })
 check(mut sum,s.sent == if interrupted(mode) { 0 } else { -99 })
 expected_mask := (if api < 2 { *temporary } else { original }) | u64(1)<<9
 check(mut sum,s.observed == if interrupted(mode) { expected_mask } else { u64(0) })
 unit := if api < 2 { i64(1_000_000_000) } else { i64(1_000_000) }
 check(mut sum,timer.before == 0x1234432156788765 && timer.after == 0x8765567812344321 && timer.value.tv_sec >= 0 && timer.value.tv_sec <= 5 && timer.value.tv_nsec >= 0 && timer.value.tv_nsec < unit && (api != 1 || (timer.value.tv_sec == 5 && timer.value.tv_nsec == 0)))
 queued := &i32(C.alloca(usize(sizeof(i32))))
 check(mut sum,C.ioctl(t.fds[1],u64(C.FIONREAD),queued) == 0 && *queued == 1)
 check(mut sum,C.fcntl(fd,C.F_GETFL) & C.O_ACCMODE == if kind == 2 { C.O_WRONLY } else { C.O_RDONLY })
 poll := &Poll(C.alloca(usize(sizeof(Poll)))); *poll = Poll{fd:fd,events:2,revents:123}
 zero := &C.timespec(C.alloca(usize(sizeof(C.timespec)))); *zero = C.timespec{}
 raw := C.syscall(isize(C.SYS_ppoll),poll,u64(1),zero,nil,u64(8))
 check(mut sum,raw == if kind == 3 { 0 } else { 1 } && poll.fd == fd && poll.events == 2 && poll.revents == if kind == 3 { 0 } else if kind == 2 { 8 } else { 16 })
 return sum
} }
fn qualify(t &Targets,apis int) Totals {
 mut total := Totals{}
 for api in 0 .. apis { for mode in 0 .. 10 {
 mut group := Totals{}
 for layout in 0 .. 3 { for restart in 0 .. 2 { result := probe(t,api,mode,layout,restart); group.checks += result.checks; group.failures += result.failures } }
 C.printf(c'LINUX SELECTWAKE CASE: uid=%u gid=%u api=%d mode=%d checks=%d failures=%d\n',C.getuid(),C.getgid(),api,mode,group.checks,group.failures)
 total.checks += group.checks; total.failures += group.failures
 } }
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
				scratch := &State(C.alloca(usize(sizeof(State))))
				t := &Targets(C.alloca(usize(sizeof(Targets))))
				*t = targets(scratch)
				sum := qualify(t,apis)
				good := if reference { C.printf(c'LINUX SELECTWAKE STORAGE: uid=%u SKIP reference\n',C.getuid()); true } else { storage(t,apis) }
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
		C.printf(c'LINUX SELECTWAKE SUMMARY: checks=%d failures=%d\n',total.checks,total.failures)
		C.printf(c'LINUX SELECTWAKE: %s\n',if total.failures == 0 && storage_good { &char(c'PASS') } else { &char(c'FAIL') })
		C.fflush(nil); C.alarm(0)
		for { C.pause() }
	}
	return 0
}
