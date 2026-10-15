// SPDX-License-Identifier: GPL-2.0-or-later
module robustqueryfixture

#include <alloca.h>
#include <errno.h>
#include <fcntl.h>
#include <grp.h>
#include <pthread.h>
#include <sched.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <sys/syscall.h>
#include <sys/wait.h>
#include <unistd.h>

@[typedef]
struct C.pthread_t {}
struct Result { ret isize code i32 }
struct Counts { mut: calls [6]u64 failures [6]u64 }
struct Slabs { mut: sizes [32]u64 live [32]u64 rows i32 large u64 }
struct Worker { mut: tid i32 input i32 output i32 command i32 ack i32 }
struct State { self i32 thread i32 page u64 head_guard u64 len_guard u64 readonly u64 inaccessible u64 both u64 }

fn C.alloca(usize) voidptr
fn C.syscall(isize, ...) isize
fn C.__errno_location() &i32
fn C.pthread_create(&C.pthread_t,voidptr,fn(voidptr) voidptr,voidptr) i32
fn C.pthread_join(C.pthread_t,voidptr) i32
fn C.getpid() i32
fn C.getuid() u32
fn C.geteuid() u32
fn C.setsid() i32
fn C.setgroups(usize,voidptr) i32
fn C.setgid(u32) i32
fn C.setresuid(u32,u32,u32) i32
fn C.sysconf(i32) isize
fn C.mmap(voidptr,usize,i32,i32,i32,isize) voidptr
fn C.mprotect(voidptr,usize,i32) i32
fn C.munmap(voidptr,usize) i32
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

fn fatal(stage i32) {
 C.printf(c'LINUX ROBUSTQUERY FAIL: setup stage=%d errno=%d\n',stage,unsafe{*C.__errno_location()}); C.fflush(unsafe{nil}); C._exit(90)
}
fn head_value(profile i32,worker bool) u64 {
 if worker {return match profile {0 {u64(0x8877665544332211)} 1 {u64(0)} 2 {~u64(0)} else {u64(0x0102030405060708)}}}
 return match profile {0 {u64(0)} 1 {~u64(0)} 2 {u64(0x1122334455667788)} else {u64(24)}}
}
fn get(pid i32,form i32,head u64,len u64) Result {
 unsafe {
  word := u64(u32(pid)) | if form == 0 {u64(0)} else {u64(0xd35ab79100000000)}
  mut code := C.__errno_location(); *code = 0
  ret := C.syscall(C.SYS_get_robust_list,isize(word),voidptr(head),voidptr(len))
  return Result{ret,*C.__errno_location()}
 }
}
fn register(head u64) {if C.syscall(C.SYS_set_robust_list,head,u64(24)) != 0 {fatal(1)}}
fn saved_head() u64 {
 mut head := u64(0); mut len := u64(0)
 result := get(0,0,u64(unsafe{&head}),u64(unsafe{&len}))
 if result.ret != 0 || result.code != 0 || len != 24 {fatal(2)}
 return head
}
fn worker_entry(argument voidptr) voidptr {
 unsafe {
  mut worker := &Worker(argument); original := saved_head(); worker.tid = i32(C.syscall(C.SYS_gettid))
  mut ready := u8(127); if C.write(worker.output,&ready,1) != 1 {fatal(15)}
  for {
   mut command := u8(0); if C.read(worker.input,&command,1) != 1 {fatal(16)}
   if command == 5 {break}
   if command < 1 || command > 4 {fatal(17)}
   register(head_value(i32(command)-1,true))
   if C.write(worker.output,&command,1) != 1 {fatal(18)}
  }
  register(original); if saved_head() != original {fatal(3)}
  return nil
 }
}
fn await_ready(worker &Worker,ready i32) {
 mut received := u8(0)
 if C.read(worker.ack,unsafe{&received},1) != 1 || received != u8(ready) {fatal(4)}
}
fn command(worker &Worker,value u8) {
 if C.write(worker.command,unsafe{&value},1) != 1 {fatal(19)}
}
fn target(state &State,choice i32) i32 {return if choice == 0 {i32(0)} else if choice == 1 {state.self} else {state.thread}}
fn difference(data voidptr,length int,start int,value u64,written bool) i32 {
 unsafe {
  for index in 0 .. length {
   local := index-start
   wanted := if written && local >= 0 && local < 8 {u8(value >> (u32(local)*8))} else {u8(0xa5)}
   if (&u8(data))[index] != wanted {return i32(index)}
  }; return -1
 }
}
fn bad(state &State,head bool,position i32) u64 {
 return match position {0 {u64(0)} 1 {u64(1)} 2 {~u64(0)} 3 {state.readonly} 4 {state.inaccessible} else {if head {state.head_guard} else {state.len_guard}+state.page-u64(position-4)}}
}
fn record(counts &Counts,class i32,good bool,ordinary bool,namespace bool,profile i32,choice i32,form i32,position i32,result Result,byte i32) {
 if counts == unsafe{nil} {return}
 unsafe {
  mut output := &Counts(counts); output.calls[class]++
  if !good {
   output.failures[class]++
   if output.failures[class] <= 3 {C.printf(c'LINUX ROBUSTQUERY DETAIL: ordinary=%d namespace=%d kind=%d profile=%d choice=%d form=%d position=%d ret=%ld errno=%d byte=%d\n',i32(ordinary),i32(namespace),class,profile,choice,form,position,result.ret,result.code,byte)}
  }
 }
}
fn trial(counts &Counts,state &State,ordinary bool,namespace bool,profile i32,class i32,choice i32,form i32,position i32) bool {
 unsafe {
  mut first := [64]u8{}; mut second := [64]u8{}; mut expected := [64]u8{}
  C.memset(&first[0],0xa5,64); C.memset(&second[0],0xa5,64); C.memset(&expected[0],0xa5,64)
  C.memset(voidptr(state.head_guard+state.page-32),0xa5,32); C.memset(voidptr(state.len_guard+state.page-32),0xa5,32)
  value := head_value(profile,choice == 2); size := u64(24)
  mut head := u64(&first[24]); mut len := u64(&second[24]); mut head_data := u64(&first[0]); mut len_data := u64(&second[0])
  if class == 0 && position >= 4 {
   cut := u64(position-3); head = state.both+state.page-cut; len = state.both+3*state.page-cut
   head_data = head-24; len_data = len-24; C.memset(voidptr(head_data),0xa5,64); C.memset(voidptr(len_data),0xa5,64)
  } else if class == 0 {
   offset := [i32(8),9,11,15]![position]; head = u64(&first[offset]); len = u64(&second[offset])
  } else if class == 1 {
   len = u64(&first[24]); head = u64(&first[17+position])
   C.memcpy(&expected[24],&size,8); C.memcpy(&expected[17+position],&value,8)
  } else if class == 2 {len = bad(state,false,position)}
  else if class == 3 {head = bad(state,true,position)}
  else if class == 4 {head = state.head_guard+state.page-3; len = bad(state,false,position)}
  result := get(target(state,choice),form,head,len)
  fault := class >= 2
  mut byte := i32(-1)
  if class == 1 {if C.memcmp(&first[0],&expected[0],64) != 0 || difference(&second[0],64,0,0,false) != -1 {byte = -2}}
  else {
   head_written := class == 0; len_written := class == 0 || class == 3
   byte = difference(voidptr(head_data),64,if class == 0 {int(head-head_data)} else {24},value,head_written)
   len_byte := difference(voidptr(len_data),64,if class == 0 {int(len-len_data)} else {24},size,len_written)
   if byte == -1 && len_byte != -1 {byte = 64+len_byte}
  }
  if difference(voidptr(state.head_guard+state.page-32),32,0,0,false) != -1 || difference(voidptr(state.len_guard+state.page-32),32,0,0,false) != -1 || difference(voidptr(state.readonly),32,0,0,false) != -1 {byte = -3}
  good := result.ret == if fault {isize(-1)} else {isize(0)} && result.code == if fault {i32(C.EFAULT)} else {i32(0)} && byte == -1
  record(counts,class,good,ordinary,namespace,profile,choice,form,position,result,byte); return good
 }
}
fn missing(counts &Counts,state &State,ordinary bool,namespace bool,retired i32) {
 unsafe {
  for pid in [i32(-1),i32(-2147483648),i32(2147483647),retired]! {for form in 0 .. 2 {for position in 0 .. 3 {
   mut head := u64(0xa5a5a5a5a5a5a5a5); mut len := head
   head_ptr := if position == 0 {u64(&head)} else if position == 1 {u64(0)} else {state.head_guard+state.page-3}
   len_ptr := if position == 0 {u64(&len)} else if position == 1 {~u64(0)} else {state.len_guard+state.page-5}
   C.memset(voidptr(state.head_guard+state.page-32),0xa5,32); C.memset(voidptr(state.len_guard+state.page-32),0xa5,32)
   result := get(pid,i32(form),head_ptr,len_ptr)
   good := result.ret == -1 && result.code == C.ESRCH && head == 0xa5a5a5a5a5a5a5a5 && len == head && difference(voidptr(state.head_guard+state.page-32),32,0,0,false) == -1 && difference(voidptr(state.len_guard+state.page-32),32,0,0,false) == -1
   record(counts,5,good,ordinary,namespace,3,pid,i32(form),i32(position),result,-1)
  }}}
 }
}
fn cycle(state &State,ordinary bool,namespace bool,index i32) bool {
 class := index%5; span := if class == 0 {11} else if class == 1 {15} else {12}
 return trial(unsafe{nil},state,ordinary,namespace,3,class,(index/5)%3,index%2,(index/2)%span)
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
   C.printf(c'LINUX ROBUSTQUERY SLAB: ordinary=%d namespace=%d size=%lu live=%lu/%lu cycles=200\n',i32(ordinary),i32(namespace),before.sizes[index],before.live[index],after.live[index])
  }
  C.printf(c'LINUX ROBUSTQUERY STORAGE: ordinary=%d namespace=%d cycles=200 big_pages=%lu/%lu %s\n',i32(ordinary),i32(namespace),before.large,after.large,if good {&char(c'PASS')} else {&char(c'FAIL')}); C.fflush(nil); return good
 }
}
fn qualify(counts &Counts,ordinary bool,namespace bool,reference bool) bool {
 unsafe {
  C.alarm(600)
  if ordinary && (C.setgroups(0,nil) != 0 || C.setgid(1000) != 0 || C.setresuid(1000,1000,1000) != 0) {fatal(5)}
  uid := if ordinary {u32(1000)} else {u32(0)}
  if C.getuid() != uid || C.geteuid() != uid || C.setsid() != C.getpid() {fatal(6)}
  page := u64(C.sysconf(C._SC_PAGESIZE)); if page != 4096 && page != 16384 {fatal(7)}
  flags := i32(C.MAP_PRIVATE|C.MAP_ANONYMOUS)
  head_guard := C.mmap(nil,usize(2*page),C.PROT_READ|C.PROT_WRITE,flags,-1,0)
  len_guard := C.mmap(nil,usize(2*page),C.PROT_READ|C.PROT_WRITE,flags,-1,0)
  readonly := C.mmap(nil,usize(page),C.PROT_READ|C.PROT_WRITE,flags,-1,0)
  inaccessible := C.mmap(nil,usize(page),C.PROT_NONE,flags,-1,0)
  both := C.mmap(nil,usize(4*page),C.PROT_READ|C.PROT_WRITE,flags,-1,0)
  if u64(head_guard) == ~u64(0) || u64(len_guard) == ~u64(0) || u64(readonly) == ~u64(0) || u64(inaccessible) == ~u64(0) || u64(both) == ~u64(0) {fatal(8)}
  C.memset(readonly,0xa5,usize(page))
  if C.mprotect(voidptr(u64(head_guard)+page),usize(page),C.PROT_NONE) != 0 || C.mprotect(voidptr(u64(len_guard)+page),usize(page),C.PROT_NONE) != 0 || C.mprotect(readonly,usize(page),C.PROT_READ) != 0 {fatal(9)}
  original := saved_head()
  mut commands := [i32(-1),i32(-1)]!; mut acknowledgements := [i32(-1),i32(-1)]!
  if C.pipe2(&commands[0],0) != 0 || C.pipe2(&acknowledgements[0],0) != 0 {fatal(20)}
  worker := &Worker(C.alloca(usize(sizeof(Worker)))); *worker = Worker{input:commands[0],output:acknowledgements[1],command:commands[1],ack:acknowledgements[0]}
  mut pthread := C.pthread_t{}
  if C.pthread_create(&pthread,nil,worker_entry,worker) != 0 {fatal(10)}; await_ready(worker,127)
  if worker.tid <= 0 || worker.tid == C.getpid() {fatal(11)}
  state := &State(C.alloca(usize(sizeof(State)))); *state = State{self:C.getpid(),thread:worker.tid,page:page,head_guard:u64(head_guard),len_guard:u64(len_guard),readonly:u64(readonly),inaccessible:u64(inaccessible),both:u64(both)}
  for profile in 0 .. 4 {
   register(head_value(i32(profile),false)); command(worker,u8(profile+1)); await_ready(worker,i32(profile+1))
   for class in 0 .. 5 {for choice in 0 .. 3 {for form in 0 .. 2 {
    span := if class == 0 {11} else if class == 1 {15} else {12}
    for position in 0 .. span {trial(counts,state,ordinary,namespace,i32(profile),i32(class),i32(choice),i32(form),i32(position))}
   }}}
  }
  C.printf(c'LINUX ROBUSTQUERY COHORT: ordinary=%d namespace=%d self=%d thread=%d uid=%u page=%lu profiles=4 targets=3 forms=2\n',i32(ordinary),i32(namespace),state.self,state.thread,uid,page)
  mut good := true; for kind in 0 .. 6 {if counts.failures[kind] != 0 {good = false}}
  if good && !reference && !storage(state,ordinary,namespace) {good = false}
  register(original); if saved_head() != original {fatal(12)}
  command(worker,5); if C.pthread_join(pthread,nil) != 0 {fatal(13)}
  if C.close(commands[0]) != 0 || C.close(commands[1]) != 0 || C.close(acknowledgements[0]) != 0 || C.close(acknowledgements[1]) != 0 {fatal(21)}
  missing(counts,state,ordinary,namespace,worker.tid)
  if C.munmap(head_guard,usize(2*page)) != 0 || C.munmap(len_guard,usize(2*page)) != 0 || C.munmap(readonly,usize(page)) != 0 || C.munmap(inaccessible,usize(page)) != 0 || C.munmap(both,usize(4*page)) != 0 {fatal(14)}
  for kind in 0 .. 6 {C.printf(c'LINUX ROBUSTQUERY CASES: ordinary=%d namespace=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),i32(namespace),kind,counts.calls[kind],counts.failures[kind]); if counts.failures[kind] != 0 {good = false}}
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
    C.printf(c'LINUX ROBUSTQUERY FINAL: ordinary=%d namespace=%d kind=%d calls=%lu failures=%lu\n',i32(ordinary),i32(namespace),kind,counts.calls[kind],counts.failures[kind])
    if counts.failures[kind] != 0 { good = false }
   } }; C.fflush(nil)
  } }
  if !good { C.puts(c'LINUX ROBUSTQUERY FAIL: robust-list PID import, ordered scalar output or retained storage'); C.fflush(nil); return 1 }
  C.puts(if reference {c'LINUX ROBUSTQUERY REFERENCE: PASS'} else {c'LINUX ROBUSTQUERY: PASS'}); C.fflush(nil); for { C.pause() }
 }; return 0
}
