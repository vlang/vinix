// SPDX-License-Identifier: BSD-2-Clause
// Independent fork/pipe/exec inputs; reference bodies are recovered externally.
@[translated]
@[has_globals]
module blockedoracle
#include <blocked-oracle-native-abi.h>
@[typedef] struct C.pthread_t {}
@[typedef] struct C.pthread_attr_t {}
@[typedef] struct C.vqb_const_attr_p {}
@[typedef] struct C.vqb_const_char_p {}
@[typedef] struct C.vqb_const_argv_p {}
@[c_extern] __global C.errno i32
fn C.assert(bool)
fn C.memcpy(voidptr,voidptr,usize) voidptr
fn C.fork() i32
fn C.pipe(&i32) i32
fn C.pthread_create(&C.pthread_t,&C.pthread_attr_t,fn(voidptr)voidptr,voidptr) i32
fn C.execv(&char,&&char) i32
fn C.waitpid(i32,&i32,i32) i32
fn C.close(i32) i32
fn C.read(i32,voidptr,usize) isize
fn C.write(i32,voidptr,usize) isize
fn C._exit(i32)
fn C.fflush(voidptr) i32
fn C.puts(&char) i32
fn C.open(&char,i32,...) i32
fn C.sysconf(i32) i64
fn C.dup2(i32,i32) i32
fn C.pause() i32
fn C.strcmp(&char,&char) i32
fn C.original_reap_ok(i32) i32
fn C.original_exec_probe(&&char) i32
fn C.original_test_exit_takes_down_blocked_threads() i32
fn C.test_exit_takes_down_blocked_threads() i32
__global ( blocked_fault i32 blocked_forks i32 blocked_wait_status i32 blocked_program &char )
@[export:'vqb_host_fork']
pub fn fork_input() i32 { unsafe {
 blocked_forks++
 if (blocked_fault==1 && blocked_forks==1) || (blocked_fault==2 && blocked_forks==2) { C.errno=C.EAGAIN;return -1 }
 return C.fork()
} }
@[export:'vqb_host_pipe']
pub fn pipe_input(out &i32) i32 { unsafe { if blocked_fault==3 { C.errno=C.EIO;return -1 };return C.pipe(out) } }
@[export:'vqb_host_pthread_create']
pub fn thread_input(thread &C.pthread_t,native_attr C.vqb_const_attr_p,callback fn(voidptr)voidptr,arg voidptr) i32 { unsafe {
 if blocked_fault==4 { return C.EAGAIN }
 mut attr:=&C.pthread_attr_t(nil);C.memcpy(&attr,&native_attr,sizeof(C.vqb_const_attr_p));return C.pthread_create(thread,attr,callback,arg)
} }
@[export:'vqb_host_execv']
pub fn exec_input(native_path C.vqb_const_char_p,native_argv C.vqb_const_argv_p) i32 { unsafe {
 if blocked_fault==5 { C.errno=C.EIO;return -1 }
 mut path:=&char(nil);mut argv:=&&char(nil)
 C.memcpy(&path,&native_path,sizeof(C.vqb_const_char_p));C.memcpy(&argv,&native_argv,sizeof(C.vqb_const_argv_p))
 $if blocked_guest? { return C.execv(path,argv) } $else { return C.execv(blocked_program,argv) }
} }
@[export:'vqb_host_waitpid']
pub fn wait_input(child i32,status &i32,options i32) i32 { unsafe {
 result:=C.waitpid(child,status,options);if result==child && status!=nil { blocked_wait_status=*status };return result
} }
@[export:'vqb_host_probe_open']
pub fn probe_open(native_path C.vqb_const_char_p,flags i32) i32 { unsafe {
 mut path:=&char(nil);C.memcpy(&path,&native_path,sizeof(C.vqb_const_char_p))
 $if blocked_guest? { return C.open(path,flags) } $else { return C.open(c'/dev/zero',flags) }
} }
@[export:'vqb_host_getauxval']
pub fn auxv_input(tag usize) usize { unsafe {
 if tag==C.AT_PAGESZ { return usize(C.sysconf(C._SC_PAGESIZE)) }
 return if tag==C.AT_RANDOM { usize(1) } else { usize(0) }
} }
@[export:'reap_ok']
pub fn reap_input(child i32) i32 { return C.original_reap_ok(child) }
fn attempt(original bool,fault i32) [4]u64 { unsafe {
 mut endpoints:=[2]i32{};C.assert(C.pipe(&endpoints[0])==0);C.fflush(nil)
 child:=C.fork();C.assert(child>=0)
 if child==0 {
  C.close(endpoints[0]);blocked_fault=fault;blocked_forks=0;blocked_wait_status= -1;C.errno=C.E2BIG
  result:=if original { C.original_test_exit_takes_down_blocked_threads() } else { C.test_exit_takes_down_blocked_threads() }
  mut report:=[u64(result),u64(u32(C.errno)),u64(blocked_forks),u64(u32(blocked_wait_status))]!
  C.assert(C.write(endpoints[1],&report[0],sizeof(report))==isize(sizeof(report)));C.fflush(nil);C._exit(0)
 }
 C.close(endpoints[1]);mut report:=[4]u64{}
 C.assert(C.read(endpoints[0],&report[0],sizeof(report))==isize(sizeof(report)))
 C.assert(C.close(endpoints[0])==0 && C.original_reap_ok(child)==0);return report
} }
@[export:'main']
pub fn main_entry(argc i32,argv &&char) i32 { unsafe {
 if argc==2 && C.strcmp(argv[1],c'--exec-memory-probe')==0 { return C.original_exec_probe(argv) }
 blocked_program=argv[0]
 $if blocked_guest? {
  mut console:=C.open(c'/dev/com1',C.O_WRONLY | C.O_NOCTTY)
  if console<0 { console=C.open(c'/dev/console',C.O_WRONLY | C.O_NOCTTY) }
  if console>=0 { C.dup2(console,1);C.dup2(console,2);C.close(console) }
 }
 for fault:=i32(0);fault<=5;fault++ {
  original:=attempt(true,fault);ported:=attempt(false,fault)
  for field in 0..4 { C.assert(original[field]==ported[field]) }
  C.assert(ported[0]==if fault==0 { u64(0) } else { u64(1) })
  if fault==0 { C.assert(ported[2]==2 && ported[3]==0) }
  if fault>=3 { C.assert(ported[3]==u64((fault-1)<<8)) }
 }
 C.puts(c'QEMU CORE BLOCKED DIFFERENTIAL PASS: six native exit/exec/failure cases');C.fflush(nil)
 $if blocked_guest? { for { C.pause() } }
 return 0
} }
