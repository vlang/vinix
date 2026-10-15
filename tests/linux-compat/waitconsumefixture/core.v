// SPDX-License-Identifier: GPL-2.0-or-later
module waitconsumefixture

#include <alloca.h>
#include <poll.h>
#include <sys/resource.h>
#include <errno.h>
#include <grp.h>
#include <signal.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.siginfo_t { mut: si_signo i32 si_errno i32 si_code i32 si_pid i32 si_uid u32 si_status i32 }
struct C.pollfd { mut: fd i32 events i16 revents i16 }
struct Counts { mut: calls [6]u64 failures [6]u64 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
struct Result { ret isize code i32 }
struct Reply { pid i32 parent i32 group i32 session i32 real u32 effective u32 saved u32 }
struct Child { pid i32 door i32 uid u32 }
struct State { self i32 child Child page u64 base u64 readonly u64 inaccessible u64 }

fn C.alloca(usize) voidptr
fn C.__errno_location() &i32
fn C.syscall(isize, ...) isize
fn C.getpid() i32
fn C.getppid() i32
fn C.getpgid(i32) i32
fn C.getsid(i32) i32
fn C.setpgid(i32,i32) i32
fn C.setsid() i32
fn C.getuid() u32
fn C.geteuid() u32
fn C.setgroups(usize,voidptr) i32
fn C.setgid(u32) i32
fn C.setresuid(u32,u32,u32) i32
fn C.getresuid(&u32,&u32,&u32) i32
fn C.pipe2(&i32,i32) i32
fn C.read(i32,voidptr,usize) isize
fn C.write(i32,voidptr,usize) isize
fn C.pread(i32,voidptr,usize,i64) isize
fn C.open(&char,i32,...) i32
fn C.close(i32) i32
fn C.fork() i32
fn C.waitpid(i32,&i32,i32) i32
fn C.wait4(i32,voidptr,i32,voidptr) i32
fn C.poll(&C.pollfd,u64,i32) i32
fn C.waitid(i32,u32,&C.siginfo_t,i32) i32
fn C.kill(i32,i32) i32
fn C._exit(i32)
fn C.alarm(u32) u32
fn C.usleep(u32) i32
fn C.pause() i32
fn C.strcmp(&char,&char) i32
fn C.sscanf(&char,&char,...) i32
fn C.printf(&char,...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.memset(voidptr,i32,usize) voidptr
fn C.unshare(i32) i32

fn fatal(stage i32) {
 C.printf(c'LINUX WAITCONSUME FAIL: setup stage=%d errno=%d\n',stage,unsafe{*C.__errno_location()})
 C.fflush(unsafe{nil}); C._exit(1)
}
fn word(value i32, form i32) u64 {
 if form == 0 {return u64(u32(value))}
 if form == 1 || form == 7 {return u64(i64(value))}
 if form == 2 {return u64(u32(value)) | 0x0000000100000000}
 if form == 3 {return u64(u32(value)) | 0x1234567800000000}
 if form == 4 {return u64(u32(value)) | 0x8000000000000000}
 if form == 5 {return u64(u32(value)) | 0x7fffffff00000000}
 return u64(u32(value)) | 0xffffffff00000000
}
fn wait_id(which i32,pid i32,options i32,form i32,info voidptr,usage voidptr) Result {
 unsafe {
  slot := C.__errno_location(); *slot = 0
  ret := if form == 7 && usage == nil {isize(C.waitid(which,u32(pid),&C.siginfo_t(info),options))}
   else {C.syscall(isize(C.SYS_waitid),word(which,form),word(pid,form),info,word(options,form),usage)}
  return Result{ret,*slot}
 }
}
fn credentials(ordinary bool,profile i32) (u32,u32,u32) {
 if ordinary {return 1000,if profile%2 == 0 {u32(1000)} else {u32(1002)},1002}
 if profile == 0 {return 0,0,0}
 if profile == 1 {return 1001,0,1002}
 if profile == 2 {return 0,1003,0}
 return 0xfffffffe,1004,0
}
fn launch(ordinary bool,namespace bool,profile i32,killed bool,announce bool) Child {
 unsafe {
  mut ready := [i32(-1),i32(-1)]!; mut door := [i32(-1),i32(-1)]!
  if C.pipe2(&ready[0],0) != 0 || C.pipe2(&door[0],0) != 0 {fatal(1)}
  real,effective,saved := credentials(ordinary,profile)
  pid := C.fork(); if pid < 0 {fatal(2)}
  if pid == 0 {
   C.close(ready[0]); C.close(door[1])
   if C.setpgid(0,0) != 0 || C.setresuid(real,effective,saved) != 0 {fatal(3)}
   mut reply := Reply{pid:C.getpid(),parent:C.getppid(),group:C.getpgid(0),session:C.getsid(0)}
   if C.getresuid(&reply.real,&reply.effective,&reply.saved) != 0 || C.write(ready[1],&reply,sizeof(Reply)) != isize(sizeof(Reply)) || C.close(ready[1]) != 0 {fatal(4)}
   mut token := u8(0); good := C.read(door[0],&token,1) == 1 && token == `X` && C.close(door[0]) == 0
   C._exit(if good {37} else {1})
  }
  C.close(ready[1]); C.close(door[0]); mut reply := Reply{}
  if C.read(ready[0],&reply,sizeof(Reply)) != isize(sizeof(Reply)) || C.close(ready[0]) != 0 {fatal(5)}
  if reply.pid != pid || reply.parent != C.getpid() || reply.group != pid || reply.session != C.getsid(0) || reply.real != real || reply.effective != effective || reply.saved != saved {fatal(6)}
  if announce {C.printf(c'LINUX WAITCONSUME TOPOLOGY: ordinary=%d namespace=%d profile=%d killed=%d self=%d pid=%d real=%u effective=%u saved=%u\n',i32(ordinary),i32(namespace),profile,i32(killed),C.getpid(),pid,real,effective,saved); C.fflush(nil)}
  return Child{pid,door[1],real}
 }
}
fn selector(state &State,index i32) (i32,i32) {
 if index == 0 {return i32(C.P_ALL),0}
 if index == 1 {return i32(C.P_PID),state.child.pid}
 return i32(C.P_PGID),state.child.pid
}
fn event_options(kind i32) i32 {return if kind == 0 {i32(C.WSTOPPED)} else if kind == 1 {i32(C.WCONTINUED)} else {i32(C.WEXITED)}}
fn event_code(kind i32) i32 {return if kind == 0 {i32(C.CLD_STOPPED)} else if kind == 1 {i32(C.CLD_CONTINUED)} else if kind == 2 {i32(C.CLD_EXITED)} else {i32(C.CLD_KILLED)}}
fn event_status(kind i32) i32 {return if kind == 0 {i32(C.SIGSTOP)} else if kind == 1 {i32(C.SIGCONT)} else if kind == 2 {i32(37)} else {i32(C.SIGKILL)}}
fn matches(info &C.siginfo_t,state &State,kind i32,uid bool) bool {
 return info.si_signo == C.SIGCHLD && info.si_errno == 0 && info.si_code == event_code(kind) && info.si_pid == state.child.pid && info.si_status == event_status(kind) && (!uid || info.si_uid == state.child.uid)
}
fn canaries(data voidptr,total int,start int,length int) bool {
 unsafe {for index in 0 .. total {if (index < start || index >= start+length) && (&u8(data))[index] != 0xa5 {return false}}}; return true
}
#include <sys/mman.h>
fn C.mmap(voidptr,usize,i32,i32,i32,i64) voidptr
fn C.mprotect(voidptr,usize,i32) i32
fn C.munmap(voidptr,usize) i32
fn C.sysconf(i32) isize

fn record(counts &Counts,kind i32,good bool,event i32,profile i32,form i32,actual Result,available i32,bad i32) {
 unsafe {
  counts.calls[kind]++
  if !good {counts.failures[kind]++; if counts.failures[kind] <= 6 {C.printf(c'LINUX WAITCONSUME DETAIL: kind=%d event=%d profile=%d form=%d actual=%ld/%d available=%d bad_byte=%d\n',kind,event,profile,form,actual.ret,actual.code,available,bad); C.fflush(nil)}}
 }
}
fn observe(state &State,kind i32) {
 unsafe {
  mut info := C.siginfo_t{}
  result := wait_id(C.P_PID,state.child.pid,event_options(kind)|C.WNOWAIT,0,&info,nil)
  if result.ret != 0 || result.code != 0 || !matches(&info,state,kind,true) {fatal(7)}
 }
}

fn unchanged(data voidptr,length int) bool {return canaries(data,length,0,0)}
fn usage_valid(data voidptr) bool {
 unsafe {
  for index in 0 .. 18 {
   mut word := u64(0); for byte in 0 .. 8 {word |= u64((&u8(data))[index*8+byte]) << (u32(byte)*8)}
   if i64(word) < 0 || ((index == 1 || index == 3) && word >= 1000000) {return false}
  }; return true
 }
}
fn wait_four(pid i32,status voidptr,options i32,form i32,usage voidptr) Result {
 unsafe {
  slot := C.__errno_location(); *slot = 0
  ret := if form == 7 {isize(C.wait4(pid,status,options,usage))}
   else {C.syscall(isize(C.SYS_wait4),word(pid,form),status,word(options,form),usage)}
  return Result{ret,*slot}
 }
}
// Each fault selects a fresh event. Readiness is observed without consuming it;
// exit trials additionally wait for pidfd POLLIN before attempting the fault.
fn trial(counts &Counts,state &State,ordinary bool,namespace bool,class i32,kind i32,choice i32,form i32,position i32,announce bool) bool {
 unsafe {
  state.child = launch(ordinary,namespace,1,kind == 3,announce)
  mut pidfd := i32(-1)
  if kind >= 2 {
   pidfd = i32(C.syscall(isize(C.SYS_pidfd_open),u64(state.child.pid),u64(0)))
   if pidfd < 0 {fatal(21)}
  }
  if kind <= 1 {
   if C.kill(state.child.pid,C.SIGSTOP) != 0 {fatal(10)}; observe(state,0)
   if kind == 1 {
    mut info := C.siginfo_t{}
    consumed := wait_id(C.P_PID,state.child.pid,C.WSTOPPED,7,&info,nil)
    if consumed.ret != 0 || consumed.code != 0 || !matches(&info,state,0,true) || C.kill(state.child.pid,C.SIGCONT) != 0 {fatal(11)}
    observe(state,1)
   }
  } else {
   if kind == 2 {if C.write(state.child.door,c'X',1) != 1 {fatal(12)}}
   else if C.kill(state.child.pid,C.SIGKILL) != 0 {fatal(13)}
   if C.close(state.child.door) != 0 {fatal(22)}; observe(state,kind)
   mut ready := C.pollfd{fd:pidfd,events:i16(C.POLLIN)}
   if C.poll(&ready,1,5000) != 1 || ready.revents & i16(C.POLLIN) == 0 || ready.revents & i16(C.POLLNVAL|C.POLLERR) != 0 {fatal(23)}
  }
  info_fault := class == 0 || class == 2 || class == 4
  keep := class >= 4
  // Vectors intentionally do not specify the architecture-dependent number
  // of bytes committed by a faulting status/rusage bulk copy.
  cut := if !info_fault {143} else if class == 0 {2} else {25}
  C.memset(voidptr(state.base),0xa5,usize(state.page))
  guard := state.base+state.page-u64(cut)
  bad := if position == 0 {~u64(0)} else if position == 1 {u64(1)} else if position == 2 {state.readonly} else if position == 3 {state.inaccessible} else {guard}
  mut data := [160]u8{}; mut usage := [176]u8{}; mut status := i32(0xa5a5a5a5)
  C.memset(&data[0],0xa5,160); C.memset(&usage[0],0xa5,176)
  info := if info_fault {voidptr(bad)} else if class == 1 {voidptr(&status)} else {voidptr(&data[17])}
  rup := if !info_fault {voidptr(bad)} else if position%2 == 0 {voidptr(nil)} else {voidptr(&usage[17])}
  nonblock := if position%2 == 0 {i32(0)} else {i32(C.WNOHANG)}
  which,pid := selector(state,choice)
  waitpid := if choice == 0 {i32(-1)} else if choice == 1 {state.child.pid} else {-state.child.pid}
  options := event_options(kind)|nonblock|if keep {i32(C.WNOWAIT)} else {i32(0)}
  actual := if class < 2 {wait_four(waitpid,info,(if kind >= 2 {i32(0)} else {event_options(kind)})|nonblock,form,rup)}
   else {wait_id(which,pid,options,form,info,rup)}
  mut good := actual.ret == -1 && actual.code == C.EFAULT && unchanged(voidptr(state.readonly),128)
  if position == 4 && !unchanged(voidptr(guard-16),16) {good = false}
  if !info_fault {
   wanted := if kind == 0 {(i32(C.SIGSTOP)<<8)|0x7f} else if kind == 1 {i32(0xffff)} else if kind == 2 {i32(37<<8)} else {i32(C.SIGKILL)}
   if (class == 1 && status != wanted) || (class != 1 && !unchanged(&data[0],160)) {good = false}
  } else if rup != nil {
   if class == 0 {if !unchanged(&usage[0],176) {good = false}}
   else if !usage_valid(&usage[17]) || !canaries(&usage[0],176,17,144) {good = false}
  }
  mut after := C.siginfo_t{}; C.memset(&after,0xa5,sizeof(C.siginfo_t))
  checked := wait_id(C.P_PID,state.child.pid,event_options(kind)|C.WNOWAIT|C.WNOHANG,7,&after,nil)
  pending := checked.ret == 0 && checked.code == 0 && matches(&after,state,kind,true)
  cleared := checked.ret == if kind >= 2 {isize(-1)} else {isize(0)} && checked.code == if kind >= 2 {i32(C.ECHILD)} else {i32(0)} && after.si_pid == 0 && after.si_uid == 0
  if (keep && !pending) || (!keep && !cleared) {good = false}
  // Clean up original kernels too, so a retained event remains a measured
  // semantic failure rather than turning later trials into setup failures.
  if pending {
   mut consumed := C.siginfo_t{}
   result := wait_id(C.P_PID,state.child.pid,event_options(kind),7,&consumed,nil)
   if result.ret != 0 || result.code != 0 || !matches(&consumed,state,kind,true) {fatal(24)}
  }
  if kind < 2 {
   if (kind == 0 && C.kill(state.child.pid,C.SIGCONT) != 0) || C.write(state.child.door,c'X',1) != 1 || C.close(state.child.door) != 0 {fatal(25)}
   mut result := i32(-1)
   if C.waitpid(state.child.pid,&result,0) != state.child.pid || result != 37<<8 {fatal(26)}
  }
  if pidfd >= 0 && C.close(pidfd) != 0 {fatal(27)}
  if counts != nil {record(counts,class,good,kind,choice,form,actual,position,if pending {1} else if cleared {0} else {-1})}
  return good
 }
}
fn cycle(state &State,ordinary bool,namespace bool,index i32) bool {
 return trial(unsafe{nil},state,ordinary,namespace,index%6,(index/6)%4,(index/24)%3,if index%2 == 0 {3} else {7},(index/3)%5,false)
}
fn storage(state &State,ordinary bool,namespace bool) bool {
 unsafe {
  observer := C.open(c'/proc/slabinfo',0); if observer < 0 {return false}; defer {C.close(observer)}
  for index in 0 .. 32 {if !cycle(state,ordinary,namespace,i32(index)) {return false}}; C.usleep(13000000)
  before := &Slabs(C.alloca(usize(sizeof(Slabs)))); after := &Slabs(C.alloca(usize(sizeof(Slabs))))
  if !snapshot(observer,before) {return false}
  for index in 0 .. 200 {if !cycle(state,ordinary,namespace,i32(index)) {return false}}; C.usleep(13000000)
  if !snapshot(observer,after) {return false}
  mut good := before.rows == after.rows && before.large == after.large
  for index in 0 .. int(before.rows) {
   if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] {good = false}
   C.printf(c'LINUX WAITCONSUME SLAB: ordinary=%d namespace=%d size=%lu live=%lu/%lu cycles=200\n',i32(ordinary),i32(namespace),before.sizes[index],before.live[index],after.live[index])
  }
  C.printf(c'LINUX WAITCONSUME STORAGE: ordinary=%d namespace=%d cycles=200 big_pages=%lu/%lu %s\n',i32(ordinary),i32(namespace),before.large,after.large,if good {&char(c'PASS')} else {&char(c'FAIL')}); C.fflush(nil); return good
 }
}
fn qualify(counts &Counts,ordinary bool,namespace bool,reference bool) bool {
 unsafe {
  C.alarm(1400)
  if ordinary && (C.setgroups(0,nil) != 0 || C.setgid(1000) != 0 || C.setresuid(1000,1000,1002) != 0) {fatal(8)}
  uid := if ordinary {u32(1000)} else {u32(0)}
  if C.getuid() != uid || C.geteuid() != uid || C.setsid() != C.getpid() {fatal(9)}
  page := u64(C.sysconf(C._SC_PAGESIZE)); if page != 4096 && page != 16384 {fatal(17)}
  flags := i32(C.MAP_PRIVATE|C.MAP_ANONYMOUS)
  base := C.mmap(nil,usize(2*page),C.PROT_READ|C.PROT_WRITE,flags,-1,0)
  readonly := C.mmap(nil,usize(page),C.PROT_READ|C.PROT_WRITE,flags,-1,0)
  inaccessible := C.mmap(nil,usize(page),C.PROT_NONE,flags,-1,0)
  if u64(base) == ~u64(0) || u64(readonly) == ~u64(0) || u64(inaccessible) == ~u64(0) {fatal(18)}
  C.memset(readonly,0xa5,usize(page))
  if C.mprotect(voidptr(u64(base)+page),usize(page),C.PROT_NONE) != 0 || C.mprotect(readonly,usize(page),C.PROT_READ) != 0 {fatal(19)}
  state := &State(C.alloca(usize(sizeof(State)))); *state = State{self:C.getpid(),page:page,base:u64(base),readonly:u64(readonly),inaccessible:u64(inaccessible)}
  mut prepared := 0
  for class in 0 .. 6 {for kind in 0 .. 4 {for choice in 0 .. 3 {for form in [i32(3),i32(7)]! {for position in 0 .. 5 {
   trial(counts,state,ordinary,namespace,i32(class),i32(kind),i32(choice),form,i32(position),prepared == 0); prepared++
  }}}}}
  C.printf(c'LINUX WAITCONSUME COHORT: ordinary=%d namespace=%d self=%d uid=%u page=%lu prepared=%d cleaned=%d pidfds=%d\n',i32(ordinary),i32(namespace),state.self,uid,page,prepared,prepared,prepared/2)
  mut good := true; for kind in 0 .. 6 {if counts.failures[kind] != 0 {good = false}}
  if good && !reference && !storage(state,ordinary,namespace) {good = false}
  if C.munmap(base,usize(2*page)) != 0 || C.munmap(readonly,usize(page)) != 0 || C.munmap(inaccessible,usize(page)) != 0 {fatal(20)}
  for kind in 0 .. 6 {C.printf(c'LINUX WAITCONSUME CASES: ordinary=%d namespace=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),i32(namespace),kind,counts.calls[kind],counts.failures[kind])}
  C.alarm(0); C.fflush(nil); return good
 }
}

fn snapshot(fd i32, destination &Slabs) bool {
	unsafe {
		mut counts := &Slabs(destination)
		*counts = Slabs{}
		mut data := [4096]char{}
		length := C.pread(fd, &data[0], 4095, 0)
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
		return counts.rows > 0 && large
	}
}

@[export: 'main']
pub fn run(argc i32, argv &&char) i32 {
 unsafe {
  if sizeof(Counts) != 96 { fatal(14) }
  reference := argc == 2 && C.strcmp(argv[1],c'--reference') == 0; mut good := true
  for namespace in [false,true]! { for ordinary in [false,true]! {
   mut pipe := [i32(-1),i32(-1)]!; if C.pipe2(&pipe[0],0) != 0 { fatal(15) }
   outer := C.fork(); if outer < 0 { fatal(16) }
   if outer == 0 {
    C.close(pipe[0])
    if namespace {
     if C.unshare(C.CLONE_NEWPID) != 0 { fatal(17) }
     init := C.fork(); if init < 0 { fatal(18) }
     if init > 0 { C.close(pipe[1]); mut status := i32(-1); C._exit(if C.waitpid(init,&status,0) == init && status == 0 {0} else {1}) }
     if C.getpid() != 1 { fatal(19) }
     cohort := C.fork(); if cohort < 0 { fatal(20) }
     if cohort > 0 { C.close(pipe[1]); mut status := i32(-1); C._exit(if C.waitpid(cohort,&status,0) == cohort && status == 0 {0} else {1}) }
    }
    counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{}
    passed := qualify(counts,ordinary,namespace,reference)
    sent := C.write(pipe[1],counts,sizeof(Counts)) == isize(sizeof(Counts)); C.close(pipe[1]); C._exit(if passed && sent {0} else {1})
   }
   C.close(pipe[1]); counts := &Counts(C.alloca(usize(sizeof(Counts)))); *counts = Counts{}
   received := C.read(pipe[0],counts,sizeof(Counts)) == isize(sizeof(Counts)); C.close(pipe[0])
   mut status := i32(-1); completed := C.waitpid(outer,&status,0) == outer && status == 0
   if !received || !completed { good = false }
   if received { for kind in 0 .. 6 {
    C.printf(c'LINUX WAITCONSUME FINAL: ordinary=%d namespace=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),i32(namespace),kind,counts.calls[kind],counts.failures[kind])
    if counts.failures[kind] != 0 { good = false }
   } }; C.fflush(nil)
  } }
  if !good { C.puts(c'LINUX WAITCONSUME FAIL: wait4/waitid copyout-fault event consumption or WNOWAIT retention controls'); C.fflush(nil); return 1 }
  C.puts(if reference {c'LINUX WAITCONSUME REFERENCE: PASS'} else {c'LINUX WAITCONSUME: PASS'}); C.fflush(nil); for { C.pause() }
 }; return 0
}
