// SPDX-License-Identifier: GPL-2.0-or-later
module tidfaultfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <pthread.h>
#include <signal.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <sys/uio.h>
#include <unistd.h>

@[typedef]
struct C.pthread_t {}
@[typedef]
struct C.sigset_t {}
struct Counts {mut: calls [6]u64 failures [6]u64}
struct Slabs {mut: sizes [32]u64 live [32]u64 rows i32 large u64}
struct State {self i32 page u64 shared u64 alias u64 fd i32}
struct Reply {mut: pid i32 tid i32 parent i32 uid u32 count i32 returned [3]i64}
struct Owner {target u64 abandoned u64 alias u64 class i32 ready i32 door i32}
struct Wait {park u64 private bool mut: result isize code i32}
struct Joined {mut: value u64}

fn C.alloca(usize) voidptr
fn C.syscall(isize,...) isize
fn C.__errno_location() &i32
fn C.pthread_create(&C.pthread_t,voidptr,fn(voidptr) voidptr,voidptr) i32
fn C.pthread_join(C.pthread_t,voidptr) i32
fn C.sigemptyset(&C.sigset_t) i32
fn C.sigaddset(&C.sigset_t,i32) i32
fn C.pthread_sigmask(i32,&C.sigset_t,&C.sigset_t) i32
fn C.getpid() i32
fn C.getppid() i32
fn C.getuid() u32
fn C.geteuid() u32
fn C.setsid() i32
fn C.setgroups(usize,voidptr) i32
fn C.setgid(u32) i32
fn C.setresuid(u32,u32,u32) i32
fn C.sysconf(i32) isize
fn C.mmap(voidptr,usize,i32,i32,i32,isize) voidptr
fn C.munmap(voidptr,usize) i32
fn C.mprotect(voidptr,usize,i32) i32
struct C.iovec {mut: iov_base voidptr iov_len usize}
fn C.ftruncate(i32,i64) i32
fn C.memset(voidptr,i32,usize) voidptr
fn C.memcpy(voidptr,voidptr,usize) voidptr
fn C.memcmp(voidptr,voidptr,usize) i32
fn C.printf(&char,...) i32
fn C.puts(&char) i32
fn C.fflush(voidptr) i32
fn C.strcmp(&char,&char) i32
fn C.alarm(u32) u32
fn C.usleep(u32) i32
fn C.pause() i32
fn C.open(&char,i32,...) i32
fn C.close(i32) i32
fn C.read(i32,voidptr,usize) isize
fn C.write(i32,voidptr,usize) isize
fn C.pread(i32,voidptr,usize,i64) isize
fn C.sscanf(&char,&char,...) i32
fn C.pipe2(&i32,i32) i32
fn C.fork() i32
fn C.unshare(i32) i32
fn C.waitpid(i32,&i32,i32) i32
fn C._exit(i32)

fn fatal(stage i32) {C.printf(c'LINUX TIDFAULT FAIL: setup stage=%d errno=%d\n',stage,unsafe{*C.__errno_location()}); C.fflush(unsafe{nil}); C._exit(90)}
fn futex(address u64,operation i32,count i32,move i32,other u64) isize {return C.syscall(C.SYS_futex,voidptr(address),isize(operation),isize(count),isize(move),voidptr(other),isize(0))}
fn waiter(argument voidptr) voidptr {
 unsafe {
  mut request := &Wait(argument); mut code := C.__errno_location(); *code = 0
  request.result = C.syscall(C.SYS_futex,voidptr(request.park),isize(if request.private {128} else {0}),isize(0),voidptr(nil),isize(0),isize(0)); request.code = *code; return nil
 }
}
// Positive requeue counts prove queue admission before the owner is released.
fn queue(park u64,target u64,count i32,private bool) {
 mut moved := i32(0)
 for _ in 0 .. 20000 {
  n := futex(park,if private {132} else {4},0,count-moved,target)
  if n < 0 || n > count-moved {fatal(1)}
  moved += i32(n); if moved == count {return}; C.usleep(1000)
 }; fatal(2)
}
fn record(counts &Counts,class i32,good bool,ordinary bool,namespace bool,index i32,actual isize,expected isize,changed bool) {
 if counts == unsafe{nil} {return}
 unsafe {
  mut output := &Counts(counts); output.calls[class]++
  if !good {output.failures[class]++; if output.failures[class] <= 3 {C.printf(c'LINUX TIDFAULT DETAIL: ordinary=%d namespace=%d kind=%d index=%d remaining=%ld expected=%ld changed=%d\n',i32(ordinary),i32(namespace),class,index,actual,expected,i32(changed))}}
 }
}
struct Access {mut: read_result i64 read_error i32 write_result i64 write_error i32 value u8 guarded bool}
struct Outcome {mut: tid i32 good bool changed bool remaining i64 expected i64 access Access}

fn access(address u64) Access {
 unsafe {
  mut local := [8]u8{}; C.memset(&local[0],0x5a,8)
  mut here := C.iovec{iov_base:voidptr(&local[3]),iov_len:1}; mut there := C.iovec{iov_base:voidptr(address),iov_len:1}
  mut code := C.__errno_location(); *code = 0
  read_result := C.syscall(C.SYS_process_vm_readv,isize(C.getpid()),&here,u64(1),&there,u64(1),u64(0)); read_error := *code
  *code = 0; write_result := C.syscall(C.SYS_process_vm_writev,isize(C.getpid()),&here,u64(1),&there,u64(1),u64(0)); write_error := *code
  mut guarded := true; for position in 0 .. 8 {if position != 3 && local[position] != 0x5a {guarded = false}}
  return Access{read_result:i64(read_result),read_error:read_error,write_result:i64(write_result),write_error:write_error,value:local[3],guarded:guarded}
 }
}
fn owner(argument voidptr) voidptr {
 unsafe {
  state := &Owner(argument); reply := &Reply(C.alloca(usize(sizeof(Reply)))); *reply = Reply{pid:C.getpid(),tid:i32(C.syscall(C.SYS_gettid)),parent:C.getppid(),uid:C.getuid(),count:1}
  pointer := if state.class == 1 {state.alias} else {state.target}
  reply.returned[0] = C.syscall(C.SYS_set_tid_address,voidptr(pointer))
  if C.write(state.ready,reply,sizeof(Reply)) != isize(sizeof(Reply)) {fatal(3)}
  mut release := u8(0); if C.read(state.door,&release,1) != 1 || release != `X` {fatal(4)}
  // Replacing musl's clear-tid registration requires raw exit, with no libc
  // join of this worker. The enclosing conductor owns its complete image.
  C.syscall(C.SYS_exit,isize(37)); fatal(5); return nil
 }
}
fn word(choice i32,tid i32) u32 {return match choice {0 {u32(0)} 1 {u32(0xffffffff)} 2 {u32(0xa5a55a5a)} else {u32(tid)}}}
fn initialize(address u64,page u64) {unsafe {C.memset(voidptr(address),0xa5,usize(2*page)); for at in [u64(32),36,40]! {*(&u32(address+at)) = 0}}}
fn conduct(state &State,index i32,measure bool) Outcome {
 unsafe {
  class := index/16; within := index%16; offset := if (within/4)%2 == 0 {u64(128)} else {state.page-4}; address := state.shared+offset
  if class == 5 {
   mapped := C.mmap(voidptr(state.shared),usize(2*state.page),C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS|C.MAP_FIXED,-1,0)
   if u64(mapped) != state.shared {fatal(6)}; initialize(state.shared,state.page)
  }
  mut ready := [i32(-1),i32(-1)]!; mut door := [i32(-1),i32(-1)]!
  if C.pipe2(&ready[0],0) != 0 || C.pipe2(&door[0],0) != 0 {fatal(7)}
  request := &Owner(C.alloca(usize(sizeof(Owner)))); *request = Owner{target:address,alias:state.alias+offset,class:class,ready:ready[1],door:door[0]}; mut handle := C.pthread_t{}
  if C.pthread_create(&handle,nil,owner,request) != 0 {fatal(8)}
  reply := &Reply(C.alloca(usize(sizeof(Reply)))); *reply = Reply{}
  if C.read(ready[0],reply,sizeof(Reply)) != isize(sizeof(Reply)) || reply.pid != C.getpid() || reply.tid <= 0 || reply.tid == reply.pid || reply.parent != state.self || C.close(ready[0]) != 0 || C.close(ready[1]) != 0 {fatal(9)}
  initial := word(within%4,reply.tid); *(&u32(address)) = initial
  expected := &u8(C.alloca(usize(2*state.page))); C.memcpy(expected,voidptr(state.shared),usize(2*state.page)); if class == 2 {zero := u32(0); C.memcpy(expected+offset,&zero,4)}
  sharing := if measure || within >= 8 {3} else {1}; total := if measure {sharing} else {sharing+2}
  handles := &C.pthread_t(C.alloca(usize(5*sizeof(C.pthread_t)))); requests := &Wait(C.alloca(usize(5*sizeof(Wait))))
  for number in 0 .. total {
   requests[number] = Wait{park:state.shared+if number < sharing {u64(32)} else if number == sharing {u64(36)} else {u64(40)},private:number == sharing}
   if C.pthread_create(&handles[number],nil,waiter,&requests[number]) != 0 {fatal(10)}
  }
  queue(state.shared+32,address,i32(sharing),false)
  neighbor := state.shared+state.page+256
  if !measure {queue(state.shared+36,address,1,true); queue(state.shared+40,neighbor,1,false)}
  registered := if class == 1 {state.alias+offset} else {address}; base := registered-offset
  if class == 4 {if C.munmap(voidptr(base),usize(state.page)) != 0 {fatal(11)}}
  else if class != 2 {if C.mprotect(voidptr(base),usize(state.page),if class == 3 {C.PROT_NONE} else {C.PROT_READ}) != 0 {fatal(12)}}
  observed := access(registered)
  readable := class !in [3,4]!
  mut good := reply.count == 1 && reply.returned[0] == i64(reply.tid) && observed.guarded
  good = good && observed.read_result == if readable {i64(1)} else {i64(-1)} && observed.read_error == if readable {i32(0)} else {i32(C.EFAULT)}
  good = good && observed.write_result == if class == 2 {i64(1)} else {i64(-1)} && observed.write_error == if class == 2 {i32(0)} else {i32(C.EFAULT)}
  if readable {good = good && observed.value == u8(initial)}
  if C.write(door[1],c'X',1) != 1 || C.close(door[1]) != 0 {fatal(13)}
  mut retired := false
  for _ in 0 .. 20000 {
   mut slot := C.__errno_location(); *slot = 0; result := C.syscall(C.SYS_tgkill,isize(C.getpid()),isize(reply.tid),isize(0))
   if result == -1 && *slot == C.ESRCH {retired = true; break}; if result != 0 {fatal(14)}; C.usleep(1000)
  }
  if !retired || C.syscall(C.SYS_tgkill,isize(C.getpid()),isize(C.getpid()),isize(0)) != 0 || C.close(door[0]) != 0 {fatal(15)}
  // Restore access only after retirement, to count the original queued nodes.
  if class == 4 {if u64(C.mmap(voidptr(base),usize(state.page),C.PROT_READ|C.PROT_WRITE,C.MAP_SHARED|C.MAP_FIXED,state.fd,0)) != base {fatal(16)}}
  else if class != 2 {if C.mprotect(voidptr(base),usize(state.page),C.PROT_READ|C.PROT_WRITE) != 0 {fatal(17)}}
  remaining := futex(address,1,8,0,0); wanted := isize(sharing)-if class in [0,1,2]! {isize(1)} else {isize(0)}; good = good && remaining == wanted
  if futex(state.shared+32,1,8,0,0) != 0 {fatal(18)}
  if !measure {good = futex(address,129,8,0,0) == 1 && good; good = futex(neighbor,1,8,0,0) == 1 && good; good = futex(state.shared+36,129,8,0,0) == 0 && good; good = futex(state.shared+40,1,8,0,0) == 0 && good}
  for number in 0 .. total {if C.pthread_join(handles[number],nil) != 0 || requests[number].result != 0 || requests[number].code != 0 {fatal(19)}}
  changed := C.memcmp(expected,voidptr(state.shared),usize(2*state.page)) != 0
  if class != 5 {good = C.memcmp(expected,voidptr(state.alias),usize(2*state.page)) == 0 && good}
  good = good && !changed
  if C.munmap(voidptr(state.shared),usize(2*state.page)) != 0 || C.munmap(voidptr(state.alias),usize(2*state.page)) != 0 || C.close(state.fd) != 0 {fatal(20)}
  return Outcome{tid:reply.tid,good:good,changed:changed,remaining:i64(remaining),expected:i64(wanted),access:observed}
 }
}
fn trial(counts &Counts,state &State,ordinary bool,namespace bool,index i32,measure bool,announce bool) bool {
 unsafe {
  initialize(state.shared,state.page)
  mut replies := [i32(-1),i32(-1)]!; if C.pipe2(&replies[0],0) != 0 {fatal(21)}
  child := C.fork(); if child < 0 {fatal(22)}
  if child == 0 {
   C.close(replies[0]); result := &Outcome(C.alloca(usize(sizeof(Outcome)))); *result = conduct(state,index,measure)
   if C.write(replies[1],result,sizeof(Outcome)) != isize(sizeof(Outcome)) || C.close(replies[1]) != 0 {fatal(23)}; C._exit(43)
  }
  C.close(replies[1]); result := &Outcome(C.alloca(usize(sizeof(Outcome)))); *result = Outcome{}
  if C.read(replies[0],result,sizeof(Outcome)) != isize(sizeof(Outcome)) || C.close(replies[0]) != 0 {fatal(24)}
  mut status := i32(-1); if C.waitpid(child,&status,0) != child || status != 43<<8 {fatal(25)}
  class := index/16; within := index%16; offset := if (within/4)%2 == 0 {u64(128)} else {state.page-4}
  expected := &u8(C.alloca(usize(2*state.page))); C.memset(expected,0xa5,usize(2*state.page)); for at in [u64(32),36,40]! {*(&u32(expected+at)) = 0}
  if class != 5 {value := if class == 2 {u32(0)} else {word(within%4,result.tid)}; C.memcpy(expected+offset,&value,4)}
  changed := C.memcmp(expected,voidptr(state.shared),usize(2*state.page)) != 0 || C.memcmp(expected,voidptr(state.alias),usize(2*state.page)) != 0
  good := result.good && !changed && result.tid > 1 && result.tid != child
  if announce {C.printf(c'LINUX TIDFAULT TOPOLOGY: ordinary=%d namespace=%d self=%d child=%d worker=%d uid=%u leader_alive=1 observed_ESRCH=1 queued=3 private=1 neighbor=1\n',i32(ordinary),i32(namespace),state.self,child,result.tid,C.getuid()); C.fflush(nil)}
  if counts != nil {C.printf(c'LINUX TIDFAULT ACCESS: ordinary=%d namespace=%d kind=%d index=%d read=%ld/%d write=%ld/%d guarded=%d\n',i32(ordinary),i32(namespace),class,index,result.access.read_result,result.access.read_error,result.access.write_result,result.access.write_error,i32(result.access.guarded)); C.fflush(nil)}
  record(counts,class,good,ordinary,namespace,index,isize(result.remaining),isize(result.expected),result.changed || changed); return good
 }
}
fn storage(state &State,ordinary bool,namespace bool) bool {
 unsafe {
  observer := C.open(c'/proc/slabinfo',0); if observer < 0 {return false}; defer {C.close(observer)}
  for index in 0 .. 96 {if !trial(nil,state,ordinary,namespace,i32(index),true,false) {return false}}; C.usleep(13000000)
  before := &Slabs(C.alloca(usize(sizeof(Slabs)))); after := &Slabs(C.alloca(usize(sizeof(Slabs))))
  if !snapshot(observer,before) {return false}
  for index in 0 .. 200 {if !trial(nil,state,ordinary,namespace,i32(index%96),true,false) {return false}}; C.usleep(13000000)
  if !snapshot(observer,after) {return false}
  mut good := before.rows == after.rows && before.large == after.large
  for index in 0 .. int(before.rows) {if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] {good = false}; C.printf(c'LINUX TIDFAULT SLAB: ordinary=%d namespace=%d size=%lu live=%lu/%lu cycles=200\n',i32(ordinary),i32(namespace),before.sizes[index],before.live[index],after.live[index])}
  C.printf(c'LINUX TIDFAULT STORAGE: ordinary=%d namespace=%d cycles=200 big_pages=%lu/%lu %s\n',i32(ordinary),i32(namespace),before.large,after.large,if good {&char(c'PASS')} else {&char(c'FAIL')}); C.fflush(nil); return good
 }
}
fn qualify(counts &Counts,ordinary bool,namespace bool,reference bool) bool {
 unsafe {
  C.alarm(1400)
  if ordinary && (C.setgroups(0,nil) != 0 || C.setgid(1000) != 0 || C.setresuid(1000,1000,1000) != 0) {fatal(26)}
  uid := if ordinary {u32(1000)} else {u32(0)}; if C.getuid() != uid || C.geteuid() != uid || C.setsid() != C.getpid() {fatal(27)}
  mut blocked := C.sigset_t{}; mut previous := C.sigset_t{}
  if C.sigemptyset(&blocked) != 0 || C.sigaddset(&blocked,C.SIGCHLD) != 0 || C.pthread_sigmask(C.SIG_BLOCK,&blocked,&previous) != 0 {fatal(28)}
  page := u64(C.sysconf(C._SC_PAGESIZE)); if page != 4096 && page != 16384 {fatal(29)}
  fd := i32(C.syscall(C.SYS_memfd_create,c'tidfault',isize(1))); if fd < 0 || C.ftruncate(fd,i64(2*page)) != 0 {fatal(30)}
  shared := C.mmap(nil,usize(2*page),C.PROT_READ|C.PROT_WRITE,C.MAP_SHARED,fd,0); alias := C.mmap(nil,usize(2*page),C.PROT_READ|C.PROT_WRITE,C.MAP_SHARED,fd,0)
  if u64(shared) == ~u64(0) || u64(alias) == ~u64(0) || shared == alias {fatal(31)}
  state := &State(C.alloca(usize(sizeof(State)))); *state = State{self:C.getpid(),page:page,shared:u64(shared),alias:u64(alias),fd:fd}
  for index in 0 .. 96 {trial(counts,state,ordinary,namespace,i32(index),false,index == 15)}
  C.printf(c'LINUX TIDFAULT COHORT: ordinary=%d namespace=%d self=%d uid=%u page=%lu raw=96 classes=6 access_checks=192 measured_shared=3\n',i32(ordinary),i32(namespace),state.self,uid,page); C.fflush(nil)
  mut good := true; for kind in 0 .. 6 {if counts.failures[kind] != 0 {good = false}}
  if good && !reference && !storage(state,ordinary,namespace) {good = false}
  if C.munmap(shared,usize(2*page)) != 0 || C.munmap(alias,usize(2*page)) != 0 || C.close(fd) != 0 {fatal(32)}
  if C.pthread_sigmask(C.SIG_SETMASK,&previous,nil) != 0 {fatal(33)}
  for kind in 0 .. 6 {C.printf(c'LINUX TIDFAULT CASES: ordinary=%d namespace=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),i32(namespace),kind,counts.calls[kind],counts.failures[kind])}
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
    C.printf(c'LINUX TIDFAULT FINAL: ordinary=%d namespace=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),i32(namespace),kind,counts.calls[kind],counts.failures[kind])
    if counts.failures[kind] != 0 { good = false }
   } }; C.fflush(nil)
  } }
  if !good { C.puts(c'LINUX TIDFAULT FAIL: clear-child-tid store-fault notification, permissions, queue counts or retained storage'); C.fflush(nil); return 1 }
  C.puts(if reference {c'LINUX TIDFAULT REFERENCE: PASS'} else {c'LINUX TIDFAULT: PASS'}); C.fflush(nil); for { C.pause() }
 }; return 0
}
