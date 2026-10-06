// SPDX-License-Identifier: BSD-2-Clause
// Shared real pipe/poll inputs with independent failure and sentinel cases.
@[translated]
@[has_globals]
module polloracle
#include <poll-oracle-native-abi.h>
struct C.pollfd { mut: fd i32 events i16 revents i16 }
@[typedef] struct C.nfds_t {}
@[typedef] struct C.vqp_const_void_p {}
@[c_extern] __global C.errno i32
fn C.assert(bool)
fn C.memcpy(voidptr,voidptr,usize) voidptr
fn C.pipe(&i32) i32
fn C.poll(&C.pollfd,C.nfds_t,i32) i32
fn C.read(i32,voidptr,usize) isize
fn C.write(i32,voidptr,usize) isize
fn C.close(i32) i32
fn C.fork() i32
fn C.waitpid(i32,&i32,i32) i32
fn C.WIFEXITED(i32) i32
fn C.WEXITSTATUS(i32) i32
fn C._exit(i32)
fn C.fflush(voidptr) i32
fn C.puts(&char) i32
fn C.open(&char,i32,...) i32
fn C.dup2(i32,i32) i32
fn C.pause() i32
fn C.original_test_pollfd_abi() i32
fn C.test_pollfd_abi() i32
__global ( poll_fault i32 poll_calls i32 poll_writes i32 poll_reads i32 poll_closes i32 )
@[export:'vqp_host_pipe']
pub fn pipe_input(out &i32) i32 { unsafe { if poll_fault==1 { C.errno=C.EIO;return -1 };return C.pipe(out) } }
@[export:'vqp_host_poll']
pub fn poll_input(fds &C.pollfd,count C.nfds_t,timeout i32) i32 { unsafe {
 mut width_count:=usize(0);C.memcpy(&width_count,&count,sizeof(C.nfds_t));C.assert(width_count==1)
 poll_calls++
 if (poll_fault==2 && poll_calls==1) || (poll_fault==5 && poll_calls==2) { C.errno=C.EIO;return -1 }
 result:=C.poll(fds,count,timeout)
 if poll_fault==3 && poll_calls==1 { fds.revents=i16(C.POLLIN) }
 if poll_fault==6 && poll_calls==2 { fds.revents=0 }
 return result
} }
@[export:'vqp_host_write']
pub fn write_input(fd i32,native_data C.vqp_const_void_p,len usize) isize { unsafe {
 poll_writes++;if poll_fault==4 { C.errno=C.EIO;return -1 }
 mut data:=voidptr(nil);C.memcpy(&data,&native_data,sizeof(C.vqp_const_void_p));return C.write(fd,data,len)
} }
@[export:'vqp_host_read']
pub fn read_input(fd i32,data voidptr,len usize) isize { unsafe {
 poll_reads++;if poll_fault==7 { C.errno=C.EIO;return -1 }
 result:=C.read(fd,data,len);if poll_fault==8 && result==1 { *(&u8(data))=`q` };return result
} }
@[export:'vqp_host_close']
pub fn close_input(fd i32) i32 { unsafe {
 poll_closes++;if (poll_fault==9 && poll_closes==1) || (poll_fault==10 && poll_closes==2) { C.errno=C.EIO;return -1 };return C.close(fd)
} }
fn attempt(original bool,fault i32) [6]u64 { unsafe {
 mut endpoints:=[2]i32{};C.assert(C.pipe(&endpoints[0])==0);C.fflush(nil)
 child:=C.fork();C.assert(child>=0)
 if child==0 {
  C.close(endpoints[0]);poll_fault=fault;poll_calls=0;poll_writes=0;poll_reads=0;poll_closes=0;C.errno=C.E2BIG
  result:=if original { C.original_test_pollfd_abi() } else { C.test_pollfd_abi() }
  mut report:=[u64(result),u64(u32(C.errno)),u64(poll_calls),u64(poll_writes),u64(poll_reads),u64(poll_closes)]!
  C.assert(C.write(endpoints[1],&report[0],sizeof(report))==isize(sizeof(report)));C.fflush(nil);C._exit(0)
 }
 C.close(endpoints[1]);mut report:=[6]u64{}
 C.assert(C.read(endpoints[0],&report[0],sizeof(report))==isize(sizeof(report)));C.assert(C.close(endpoints[0])==0)
 mut status:=i32(-1);C.assert(C.waitpid(child,&status,0)==child && C.WIFEXITED(status)!=0 && C.WEXITSTATUS(status)==0);return report
} }
@[export:'main']
pub fn main_entry() i32 { unsafe {
 $if poll_guest? {
  mut console:=C.open(c'/dev/com1',C.O_WRONLY | C.O_NOCTTY)
  if console<0 { console=C.open(c'/dev/console',C.O_WRONLY | C.O_NOCTTY) }
  if console>=0 { C.dup2(console,1);C.dup2(console,2);C.close(console) }
 }
 for fault:=i32(0);fault<=10;fault++ {
  original:=attempt(true,fault);ported:=attempt(false,fault)
  for field in 0..6 { C.assert(original[field]==ported[field]) }
  C.assert(ported[0]==if fault==0 { u64(0) } else { u64(1) })
  if fault==0 { C.assert(ported[2]==2 && ported[3]==1 && ported[4]==1 && ported[5]==2) }
 }
 C.puts(c'QEMU CORE POLL DIFFERENTIAL PASS: eleven native poll/pipe/failure cases');C.fflush(nil)
 $if poll_guest? { for { C.pause() } }
 return 0
} }
