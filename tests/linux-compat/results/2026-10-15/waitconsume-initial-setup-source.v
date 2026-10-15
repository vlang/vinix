import os
fn main() {
 root := '/Users/alex/code/vinix/'
 mut probe := os.read_file(root+'tests/linux-compat/waitusagefixture/core.v')!.replace('waitusage','waitconsume').replace('WAITUSAGE','WAITCONSUME')
 probe = probe.replace('#include <alloca.h>','#include <alloca.h>\n#include <poll.h>\n#include <sys/resource.h>')
 probe = probe.replace('struct Counts {','struct C.pollfd { mut: fd i32 events i16 revents i16 }\nstruct Counts {')
 probe = probe.replace('fn C.waitpid(i32,&i32,i32) i32','fn C.waitpid(i32,&i32,i32) i32\nfn C.wait4(i32,voidptr,i32,voidptr) i32\nfn C.poll(&C.pollfd,u64,i32) i32')
 start := probe.index('fn value(')!; end := probe.index('fn snapshot(')!
 probe = probe[..start] + '
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
   if kind == 2 {if C.write(state.child.door,c\'X\',1) != 1 {fatal(12)}}
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
  if if keep {!pending} else {!cleared} {good = false}
  // Clean up original kernels too, so a retained event remains a measured
  // semantic failure rather than turning later trials into setup failures.
  if pending {
   mut consumed := C.siginfo_t{}
   result := wait_id(C.P_PID,state.child.pid,event_options(kind),7,&consumed,nil)
   if result.ret != 0 || result.code != 0 || !matches(&consumed,state,kind,true) {fatal(24)}
  }
  if kind < 2 {
   if (kind == 0 && C.kill(state.child.pid,C.SIGCONT) != 0) || C.write(state.child.door,c\'X\',1) != 1 || C.close(state.child.door) != 0 {fatal(25)}
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
  observer := C.open(c\'/proc/slabinfo\',0); if observer < 0 {return false}; defer {C.close(observer)}
  for index in 0 .. 32 {if !cycle(state,ordinary,namespace,i32(index)) {return false}}; C.usleep(13000000)
  before := &Slabs(C.alloca(usize(sizeof(Slabs)))); after := &Slabs(C.alloca(usize(sizeof(Slabs))))
  if !snapshot(observer,before) {return false}
  for index in 0 .. 200 {if !cycle(state,ordinary,namespace,i32(index)) {return false}}; C.usleep(13000000)
  if !snapshot(observer,after) {return false}
  mut good := before.rows == after.rows && before.large == after.large
  for index in 0 .. int(before.rows) {
   if before.sizes[index] != after.sizes[index] || before.live[index] != after.live[index] {good = false}
   C.printf(c\'LINUX WAITCONSUME SLAB: ordinary=%d namespace=%d size=%lu live=%lu/%lu cycles=200\\n\',i32(ordinary),i32(namespace),before.sizes[index],before.live[index],after.live[index])
  }
  C.printf(c\'LINUX WAITCONSUME STORAGE: ordinary=%d namespace=%d cycles=200 big_pages=%lu/%lu %s\\n\',i32(ordinary),i32(namespace),before.large,after.large,if good {&char(c\'PASS\')} else {&char(c\'FAIL\')}); C.fflush(nil); return good
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
  C.printf(c\'LINUX WAITCONSUME COHORT: ordinary=%d namespace=%d self=%d uid=%u page=%lu prepared=%d cleaned=%d pidfds=%d\\n\',i32(ordinary),i32(namespace),state.self,uid,page,prepared,prepared,prepared/2)
  mut good := true; for kind in 0 .. 6 {if counts.failures[kind] != 0 {good = false}}
  if good && !reference && !storage(state,ordinary,namespace) {good = false}
  if C.munmap(base,usize(2*page)) != 0 || C.munmap(readonly,usize(page)) != 0 || C.munmap(inaccessible,usize(page)) != 0 {fatal(20)}
  for kind in 0 .. 6 {C.printf(c\'LINUX WAITCONSUME CASES: ordinary=%d namespace=%d kind=%d calls=%lu failures=%lu\\n\',i32(ordinary),i32(namespace),kind,counts.calls[kind],counts.failures[kind])}
  C.alarm(0); C.fflush(nil); return good
 }
}

' + probe[end..]
 probe = probe.replace('waitid rusage/siginfo ordering or alias controls','wait4/waitid copyout-fault event consumption or WNOWAIT retention controls')
 os.mkdir_all(root+'tests/linux-compat/waitconsumefixture')!
 os.write_file(root+'tests/linux-compat/waitconsumefixture/core.v',probe)!
 os.mkdir_all(root+'tests/linux-compat/waitconsumereferenceinit')!
 os.write_file(root+'tests/linux-compat/waitconsumereferenceinit/core.v',os.read_file(root+'tests/linux-compat/waitusagereferenceinit/core.v')!.replace('waitusage','waitconsume').replace('WAITUSAGE','WAITCONSUME'))!
 mut controller := os.read_file(root+'tests/linux-compat/waitusage-reference.v')!.replace('waitusage','waitconsume').replace('WAITUSAGE','WAITCONSUME')
 for value in ['12288','15360','9984','27648','6144','6176'] {controller = controller.replace('\n\t\t\t'+value+',','\n\t\t\t120,')}
 os.write_file(root+'tests/linux-compat/waitconsume-reference.v',controller)!
 mut runner := os.read_file(root+'tests/linux-compat/run.v')!
 assert runner.count('waitevent,waitusage') == 2 && runner.count("'waitevent', 'waitusage'") == 1
 runner = runner.replace('waitevent,waitusage','waitevent,waitusage,waitconsume').replace("'waitevent', 'waitusage'","'waitevent', 'waitusage', 'waitconsume'")
 os.write_file(root+'tests/linux-compat/run.v',runner)!
}
