// SPDX-License-Identifier: BSD-2-Clause
// Independent real OS signal/restart oracle; injected fork failure is shared input.
@[translated]
@[has_globals]
module restartoracle
#include <restart-oracle-native-abi.h>
@[c_extern] __global C.errno i32
fn C.assert(bool)
fn C.fork() i32
fn C.pipe(&i32) i32
fn C.close(i32) i32
fn C.write(i32,voidptr,usize) isize
fn C.read(i32,voidptr,usize) isize
fn C.waitpid(i32,&i32,i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C._exit(i32)
fn C.fflush(voidptr) i32
fn C.puts(&char) i32
fn C.open(&char,i32,...) i32
fn C.dup2(i32,i32) i32
fn C.pause() i32
fn C.original_reap_ok(i32) i32
fn C.original_test_syscall_restart() i32
fn C.test_syscall_restart() i32
__global ( fork_calls i32 fork_failure i32 )
@[export:'vqr_host_fork']
pub fn host_fork() i32 { unsafe {
 fork_calls++;if fork_calls==fork_failure { C.errno=C.EAGAIN;return -1 };return C.fork()
} }
// Share the retained original helper in both host and native comparisons.
@[export:'reap_ok']
pub fn host_reap(child i32) i32 { return C.original_reap_ok(child) }
fn attempt(original bool,failure i32) [4]u64 { unsafe {
 mut endpoints:=[2]i32{};C.assert(C.pipe(&endpoints[0])==0);C.fflush(nil)
 child:=C.fork();C.assert(child>=0)
 if child==0 {
  C.close(endpoints[0]);fork_calls=0;fork_failure=failure;C.errno=C.E2BIG
  result:=if original { C.original_test_syscall_restart() } else { C.test_syscall_restart() }
  mut report:=[u64(result),u64(u32(C.errno)),u64(fork_calls),u64(0)]!
  C.assert(C.write(endpoints[1],&report[0],sizeof(report))==isize(sizeof(report)));C.fflush(nil);C._exit(0)
 }
 C.close(endpoints[1]);mut report:=[4]u64{}
 C.assert(C.read(endpoints[0],&report[0],sizeof(report))==isize(sizeof(report)))
 C.assert(C.close(endpoints[0])==0);mut status:=i32(-1)
 C.assert(C.waitpid(child,&status,0)==child && C.WIFEXITED(status) && C.WEXITSTATUS(status)==0);return report
} }
@[export:'main']
pub fn main_entry() i32 { unsafe {
 $if restart_guest? {
  mut console:=C.open(c'/dev/com1',C.O_WRONLY | C.O_NOCTTY)
  if console<0 { console=C.open(c'/dev/console',C.O_WRONLY | C.O_NOCTTY) }
  if console>=0 { C.dup2(console,1);C.dup2(console,2);C.close(console) }
 }
 for failure:=i32(0);failure<=2;failure++ {
  original:=attempt(true,failure);ported:=attempt(false,failure)
  for field in 0..4 { C.assert(original[field]==ported[field]) }
  C.assert(ported[0]==if failure==0 { u64(0) } else { u64(1) })
 }
 C.puts(c'QEMU CORE RESTART DIFFERENTIAL PASS: three native signal/fork cases');C.fflush(nil)
 $if restart_guest? { for { C.pause() } }
 return 0
} }
