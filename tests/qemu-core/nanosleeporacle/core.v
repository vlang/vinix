// SPDX-License-Identifier: BSD-2-Clause
// Independent real signal/fork inputs; original/V cases have private child state.
@[translated]
@[has_globals]
module nanosleeporacle
#include <nanosleep-oracle-native-abi.h>
@[typedef] struct C.vqn_const_action_p {}
struct C.sigaction {}
@[c_extern] __global C.errno i32
fn C.assert(bool)
fn C.memcpy(voidptr,voidptr,usize) voidptr
fn C.sigaction(i32,&C.sigaction,&C.sigaction) i32
fn C.fork() i32
fn C.pipe(&i32) i32
fn C.close(i32) i32
fn C.read(i32,voidptr,usize) isize
fn C.write(i32,voidptr,usize) isize
fn C._exit(i32)
fn C.fflush(voidptr) i32
fn C.puts(&char) i32
fn C.open(&char,i32,...) i32
fn C.dup2(i32,i32) i32
fn C.pause() i32
fn C.original_reap_ok(i32) i32
fn C.original_test_interrupted_nanosleep_remaining() i32
fn C.test_interrupted_nanosleep_remaining() i32
__global ( remainder_fault i32 remainder_forks i32 remainder_actions i32 )

@[export:'vqn_host_fork']
pub fn fork_input() i32 { unsafe {
 remainder_forks++
 if remainder_fault==2 { C.errno=C.EAGAIN;return -1 }
 return C.fork()
} }
@[export:'vqn_host_sigaction']
pub fn action_input(signal i32,native_action C.vqn_const_action_p,old &C.sigaction) i32 { unsafe {
 remainder_actions++
 if remainder_fault==1 { C.errno=C.EIO;return -1 }
 mut action:=&C.sigaction(nil);C.memcpy(&action,&native_action,sizeof(C.vqn_const_action_p))
 return C.sigaction(signal,action,old)
} }
@[export:'reap_ok']
pub fn reap_input(child i32) i32 { return C.original_reap_ok(child) }

fn attempt(original bool,fault i32) [4]u64 { unsafe {
 mut endpoints:=[2]i32{};C.assert(C.pipe(&endpoints[0])==0);C.fflush(nil)
 child:=C.fork();C.assert(child>=0)
 if child==0 {
  C.close(endpoints[0]);remainder_fault=fault;remainder_forks=0;remainder_actions=0;C.errno=C.E2BIG
  result:=if original { C.original_test_interrupted_nanosleep_remaining() } else { C.test_interrupted_nanosleep_remaining() }
  mut report:=[u64(result),u64(u32(C.errno)),u64(remainder_forks),u64(remainder_actions)]!
  C.assert(C.write(endpoints[1],&report[0],sizeof(report))==isize(sizeof(report)));C.fflush(nil);C._exit(0)
 }
 C.close(endpoints[1]);mut report:=[4]u64{}
 C.assert(C.read(endpoints[0],&report[0],sizeof(report))==isize(sizeof(report)))
 C.assert(C.close(endpoints[0])==0 && C.original_reap_ok(child)==0);return report
} }
@[export:'main']
pub fn main_entry() i32 { unsafe {
 $if nanosleep_guest? {
  mut console:=C.open(c'/dev/com1',C.O_WRONLY | C.O_NOCTTY)
  if console<0 { console=C.open(c'/dev/console',C.O_WRONLY | C.O_NOCTTY) }
  if console>=0 { C.dup2(console,1);C.dup2(console,2);C.close(console) }
 }
 for fault:=i32(0);fault<=2;fault++ {
  original:=attempt(true,fault);ported:=attempt(false,fault)
  for field in 0..4 { C.assert(original[field]==ported[field]) }
  C.assert(ported[0]==if fault==0 { u64(0) } else { u64(1) })
 }
 C.puts(c'QEMU CORE NANOSLEEP DIFFERENTIAL PASS: three native interruption/failure cases');C.fflush(nil)
 $if nanosleep_guest? { for { C.pause() } }
 return 0
} }
