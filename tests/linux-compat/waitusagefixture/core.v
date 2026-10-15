// SPDX-License-Identifier: GPL-2.0-or-later
module waitusagefixture

#include <alloca.h>
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
 C.printf(c'LINUX WAITUSAGE FAIL: setup stage=%d errno=%d\n',stage,unsafe{*C.__errno_location()})
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
  if announce {C.printf(c'LINUX WAITUSAGE TOPOLOGY: ordinary=%d namespace=%d profile=%d killed=%d self=%d pid=%d real=%u effective=%u saved=%u\n',i32(ordinary),i32(namespace),profile,i32(killed),C.getpid(),pid,real,effective,saved); C.fflush(nil)}
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
  if !good {counts.failures[kind]++; if counts.failures[kind] <= 6 {C.printf(c'LINUX WAITUSAGE DETAIL: kind=%d event=%d profile=%d form=%d actual=%ld/%d available=%d bad_byte=%d\n',kind,event,profile,form,actual.ret,actual.code,available,bad); C.fflush(nil)}}
 }
}
fn observe(state &State,kind i32) {
 unsafe {
  mut info := C.siginfo_t{}
  result := wait_id(C.P_PID,state.child.pid,event_options(kind)|C.WNOWAIT,0,&info,nil)
  if result.ret != 0 || result.code != 0 || !matches(&info,state,kind,true) {fatal(7)}
 }
}
fn value(state &State,kind i32,index int) u32 {
 if index == 0 {return u32(C.SIGCHLD)}
 if index == 1 {return 0}
 if index == 2 {return u32(event_code(kind))}
 if index == 4 {return u32(state.child.pid)}
 if index == 5 {return state.child.uid}
 return u32(event_status(kind))
}
// Linux writes six 32-bit fields in order, preserving padding/tail and all
// bytes of a stable split-field fault. Both reference architectures are LE.
fn difference(data voidptr,total int,start int,available int,state &State,kind i32) i32 {
 unsafe {
  for index in 0 .. total {
   local := index-start; mut wanted := u8(0xa5)
   if local >= 0 && local < available && (local < 12 || (local >= 16 && local < 28)) && (local/4)*4+4 <= available {
    wanted = u8(value(state,kind,local/4) >> (u32(local%4)*8))
   }
   if (&u8(data))[index] != wanted {return i32(index)}
  }; return -1
 }
}
fn guard(state &State,kind i32,which i32,pid i32,form i32,cut i32,options i32) (Result,i32) {
 unsafe {
  C.memset(voidptr(state.base),0xa5,usize(state.page))
  address := state.base+state.page-u64(cut)
  actual := wait_id(which,pid,options,form,voidptr(address),nil)
  bad := difference(voidptr(address-16),int(cut)+16,16,int(cut),state,kind)
  return actual,bad
 }
}
fn unchanged(data voidptr,length int) bool {return canaries(data,length,0,0)}
// Decode the LP64 rusage without aligned C loads. Poisoned/uncopied storage
// fails these basic field-domain checks; exact accounting stays separate.
fn usage_valid(data voidptr) bool {
 unsafe {
  for index in 0 .. 18 {
   mut word := u64(0); for byte in 0 .. 8 {word |= u64((&u8(data))[index*8+byte]) << (u32(byte)*8)}
   if i64(word) < 0 || ((index == 1 || index == 3) && word >= 1000000) {return false}
  }; return true
 }
}
fn alias_layout(index int) (int,int) {
 if index == 0 {return 16,16}
 if index == 1 {return 17,17}
 if index == 2 {return 56,16}
 if index == 3 {return 57,17}
 if index == 4 {return 80,16}
 if index == 5 {return 81,17}
 if index == 6 {return 16,20}
 return 16,144
}
fn alias_difference(data voidptr,total int,ip int,up int,state &State,kind i32) i32 {
 unsafe {
  for index in 0 .. total {
   local := index-ip; mut wanted := u8(0xa5)
   field := local >= 0 && (local < 12 || (local >= 16 && local < 28))
   if field {wanted = u8(value(state,kind,local/4) >> (u32(local%4)*8))}
   else if index >= up && index < up+144 {continue}
   if (&u8(data))[index] != wanted {return i32(index)}
  }; return -1
 }
}
fn matrix(counts &Counts,state &State,kind i32,profile i32) {
 unsafe {
  for index in 0 .. 3 {which,pid := selector(state,i32(index)); for form in 0 .. 8 {for nonblock in [0,i32(C.WNOHANG)]! {
   options := event_options(kind)|C.WNOWAIT|nonblock
   // A refused rusage copy must return before the first siginfo write.
   for offset in [0,1,3,7]! {for position in 0 .. 4 {
    mut data := [160]u8{}; C.memset(&data[0],0xa5,160)
    address := if position == 0 {~u64(0)} else if position == 1 {u64(1)} else if position == 2 {state.readonly} else {state.inaccessible}
    actual := wait_id(which,pid,options,i32(form),&data[16+offset],voidptr(address))
    good := actual.ret == -1 && actual.code == C.EFAULT && unchanged(&data[0],160) && unchanged(voidptr(state.readonly),128)
    record(counts,0,good,kind,profile,i32(form),actual,i32(position),-1)
   }}
   // A later siginfo fault must leave the preceding complete rusage visible.
   for offset in [0,1,3,7]! {for position in 0 .. 5 {
    mut usage := [176]u8{}; C.memset(&usage[0],0xa5,176); start := 16+offset
    address := if position == 0 {~u64(0)} else if position == 1 {~u64(0)-63} else if position == 2 {u64(1)} else if position == 3 {state.readonly} else {state.inaccessible}
    actual := wait_id(which,pid,options,i32(form),voidptr(address),&usage[start])
    good := actual.ret == -1 && actual.code == C.EFAULT && usage_valid(&usage[start]) && canaries(&usage[0],176,start,144) && unchanged(voidptr(state.readonly),128)
    record(counts,1,good,kind,profile,i32(form),actual,i32(position),-1)
   }}
   // Do not impose architecture-specific partial rusage copy counts.
   for cut in [0,1,7,8,15,16,31,32,63,64,127,128,143]! {
    mut data := [160]u8{}; C.memset(&data[0],0xa5,160); C.memset(voidptr(state.base),0xa5,usize(state.page))
    address := state.base+state.page-u64(cut)
    actual := wait_id(which,pid,options,i32(form),&data[19],voidptr(address))
    good := actual.ret == -1 && actual.code == C.EFAULT && unchanged(&data[0],160) && unchanged(voidptr(address-16),16)
    record(counts,2,good,kind,profile,i32(form),actual,i32(cut),-1)
   }
   for position in 0 .. 36 {
    cut := if position <= 32 {i32(position)} else if position == 33 {i32(64)} else if position == 34 {i32(127)} else {i32(128)}
    mut usage := [176]u8{}; C.memset(&usage[0],0xa5,176); C.memset(voidptr(state.base),0xa5,usize(state.page))
    address := state.base+state.page-u64(cut)
    actual := wait_id(which,pid,options,i32(form),voidptr(address),&usage[19])
    bad := difference(voidptr(address-16),int(cut)+16,16,int(cut),state,kind)
    code := if cut < 28 {i32(C.EFAULT)} else {i32(0)}
    good := actual.ret == if code == 0 {isize(0)} else {isize(-1)} && actual.code == code && bad == -1 && usage_valid(&usage[19]) && canaries(&usage[0],176,19,144)
    record(counts,3,good,kind,profile,i32(form),actual,cut,bad)
   }
   for position in 0 .. 8 {
    ip,up := alias_layout(position); mut data := [320]u8{}; C.memset(&data[0],0xa5,320)
    actual := wait_id(which,pid,options,i32(form),&data[ip],&data[up])
    bad := alias_difference(&data[0],320,ip,up,state,kind)
    record(counts,4,actual.ret == 0 && actual.code == 0 && bad == -1,kind,profile,i32(form),actual,i32(position),bad)
   }
   for offset in [0,1,3,7]! {for use in 0 .. 2 {
    mut data := [160]u8{}; mut usage := [176]u8{}; C.memset(&data[0],0xa5,160); C.memset(&usage[0],0xa5,176)
    ip := 16+offset; up := 23-offset; usage_pointer := if use == 0 {voidptr(nil)} else {voidptr(&usage[up])}
    actual := wait_id(which,pid,options,i32(form),&data[ip],usage_pointer)
    bad := difference(&data[0],160,ip,128,state,kind)
    good := actual.ret == 0 && actual.code == 0 && bad == -1 && if use == 0 {unchanged(&usage[0],176)} else {usage_valid(&usage[up]) && canaries(&usage[0],176,up,144)}
    record(counts,5,good,kind,profile,i32(form),actual,128,bad)
   }}
  }}}
  mut info := C.siginfo_t{}
  actual := wait_id(C.P_PID,state.child.pid,event_options(kind),7,&info,nil)
  record(counts,5,actual.ret == 0 && actual.code == 0 && matches(&info,state,kind,true),kind,profile,7,actual,0,-1)
  C.memset(&info,0xa5,sizeof(C.siginfo_t))
  empty := wait_id(C.P_PID,state.child.pid,event_options(kind)|C.WNOHANG,7,&info,voidptr(~u64(0)))
  gone := kind >= 2; correct := empty.ret == if gone {isize(-1)} else {isize(0)} && empty.code == if gone {i32(C.ECHILD)} else {i32(0)} && info.si_pid == 0 && info.si_uid == 0
  record(counts,5,correct,kind,profile,7,empty,0,-1)
 }
}
fn cycle(state &State,index i32) bool {
 unsafe {
  for selector_index in 0 .. 3 {which,pid := selector(state,i32(selector_index)); for form in 0 .. 8 {
   options := i32(C.WSTOPPED|C.WNOWAIT|C.WNOHANG); mode := index%4
   mut data := [320]u8{}; mut usage := [176]u8{}; C.memset(&data[0],0xa5,320); C.memset(&usage[0],0xa5,176)
   if mode == 0 {
    actual := wait_id(which,pid,options,i32(form),&data[17],voidptr(~u64(0)))
    if actual.ret != -1 || actual.code != C.EFAULT || !unchanged(&data[0],320) {return false}
   } else if mode == 1 {
    actual := wait_id(which,pid,options,i32(form),voidptr(state.readonly),&usage[17])
    if actual.ret != -1 || actual.code != C.EFAULT || !usage_valid(&usage[17]) || !canaries(&usage[0],176,17,144) {return false}
   } else if mode == 2 {
    C.memset(voidptr(state.base),0xa5,usize(state.page)); address := state.base+state.page-25
    actual := wait_id(which,pid,options,i32(form),voidptr(address),&usage[17])
    if actual.ret != -1 || actual.code != C.EFAULT || difference(voidptr(address-16),41,16,25,state,0) != -1 || !usage_valid(&usage[17]) || !canaries(&usage[0],176,17,144) {return false}
   } else {
    actual := wait_id(which,pid,options,i32(form),&data[56],&data[16])
    if actual.ret != 0 || actual.code != 0 || alias_difference(&data[0],320,56,16,state,0) != -1 {return false}
   }
  }}; return true
 }
}

fn storage(state &State,ordinary bool,namespace bool) bool {
 unsafe {
  observer := C.open(c'/proc/slabinfo',0); if observer < 0 {return false}; defer {C.close(observer)}
  for index in 0 .. 32 {if !cycle(state,i32(index)) {return false}}; C.usleep(13000000)
  before := &Slabs(C.alloca(usize(sizeof(Slabs)))); after := &Slabs(C.alloca(usize(sizeof(Slabs))))
  if !snapshot(observer,before) {return false}
  for index in 0 .. 200 {if !cycle(state,i32(index)) {return false}}; C.usleep(13000000)
  if !snapshot(observer,after) {return false}
  mut good := before.rows == after.rows && before.large == after.large
  for index in 0 .. int(before.rows) {
   if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] {good = false}
   C.printf(c'LINUX WAITUSAGE SLAB: ordinary=%d namespace=%d size=%lu live=%lu/%lu cycles=200\n',i32(ordinary),i32(namespace),before.sizes[index],before.live[index],after.live[index])
  }
  C.printf(c'LINUX WAITUSAGE STORAGE: ordinary=%d namespace=%d cycles=200 big_pages=%lu/%lu %s\n',i32(ordinary),i32(namespace),before.large,after.large,if good {&char(c'PASS')} else {&char(c'FAIL')}); C.fflush(nil); return good
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
  for profile in 0 .. 4 {
   state.child = launch(ordinary,namespace,i32(profile),false,true)
   if C.kill(state.child.pid,C.SIGSTOP) != 0 {fatal(10)}; observe(state,0); matrix(counts,state,0,i32(profile))
   if C.kill(state.child.pid,C.SIGCONT) != 0 {fatal(11)}; observe(state,1); matrix(counts,state,1,i32(profile))
   if C.write(state.child.door,c'X',1) != 1 || C.close(state.child.door) != 0 {fatal(12)}; observe(state,2); matrix(counts,state,2,i32(profile))
   state.child = launch(ordinary,namespace,i32(profile),true,true)
   if C.kill(state.child.pid,C.SIGKILL) != 0 || C.close(state.child.door) != 0 {fatal(13)}; observe(state,3); matrix(counts,state,3,i32(profile))
  }
  mut good := true; for kind in 0 .. 6 {if counts.failures[kind] != 0 {good = false}}
  if good && !reference {
   state.child = launch(ordinary,namespace,1,false,false)
   if C.kill(state.child.pid,C.SIGSTOP) != 0 {fatal(14)}; observe(state,0)
   if !storage(state,ordinary,namespace) {good = false}
   if C.kill(state.child.pid,C.SIGCONT) != 0 || C.write(state.child.door,c'X',1) != 1 || C.close(state.child.door) != 0 {fatal(15)}
   mut status := i32(-1); if C.waitpid(state.child.pid,&status,0) != state.child.pid || status != 37<<8 {fatal(16)}
  }
  if C.munmap(base,usize(2*page)) != 0 || C.munmap(readonly,usize(page)) != 0 || C.munmap(inaccessible,usize(page)) != 0 {fatal(20)}
  for kind in 0 .. 6 {C.printf(c'LINUX WAITUSAGE CASES: ordinary=%d namespace=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),i32(namespace),kind,counts.calls[kind],counts.failures[kind])}
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
    C.printf(c'LINUX WAITUSAGE FINAL: ordinary=%d namespace=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),i32(namespace),kind,counts.calls[kind],counts.failures[kind])
    if counts.failures[kind] != 0 { good = false }
   } }; C.fflush(nil)
  } }
  if !good { C.puts(c'LINUX WAITUSAGE FAIL: waitid rusage/siginfo ordering or alias controls'); C.fflush(nil); return 1 }
  C.puts(if reference {c'LINUX WAITUSAGE REFERENCE: PASS'} else {c'LINUX WAITUSAGE: PASS'}); C.fflush(nil); for { C.pause() }
 }; return 0
}
