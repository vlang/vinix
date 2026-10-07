// SPDX-License-Identifier: GPL-2.0-or-later
// Native PID 1 supervisor. The unchanged workload receives actual argc/argv.
@[has_globals]
module hostguest
#include <hostguest_v_contract.h>
fn C.vmh_host_entry(i32,&&char) i32
fn C.fork() i32
fn C.pipe(&i32) i32
fn C.dup2(i32,i32) i32
fn C.close(i32) i32
fn C.read(i32,voidptr,usize) isize
fn C.waitpid(i32,&i32,i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C.WIFSIGNALED(i32) bool
fn C.WTERMSIG(i32) i32
fn C.strstr(&char,&char) &char
fn C.printf(&char,...) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C._Exit(i32)
fn C.__errno_location() &i32
fn check(condition bool) { if !condition { unsafe { C.printf(c'HOST MODEL GUEST FAIL: errno=%d\n',*C.__errno_location());C.fflush(nil);C._Exit(1) } } }
fn child_case(name &char,negative bool) { unsafe {
 mut descriptors:=[2]i32{};check(C.pipe(&descriptors[0])==0);child:=C.fork();check(child>=0)
 if child==0 {
  C.close(descriptors[0]);if negative { check(C.dup2(descriptors[1],2)==2) };C.close(descriptors[1])
  mut arguments:=[&char(c'linuxkpi-host'),name,&char(nil)]!
  argc:=if name==nil { i32(1) } else { i32(2) };result:=C.vmh_host_entry(argc,&arguments[0]);C.fflush(nil);C._Exit(result)
 }
 C.close(descriptors[1]);mut capture:=[4096]char{};mut used:=usize(0)
 for used<sizeof(capture)-1 {
  got:=C.read(descriptors[0],&capture[used],sizeof(capture)-1-used)
  if got<0 && *C.__errno_location()==C.EINTR { continue };check(got>=0);if got==0 { break };used+=usize(got)
 }
 check(used<sizeof(capture)-1);C.close(descriptors[0]);mut status:=i32(0);check(C.waitpid(child,&status,0)==child)
 if negative {
  if !(C.WIFSIGNALED(status) && C.WTERMSIG(status)==C.SIGABRT) { C.printf(c'HOST MODEL CHILD STATUS: case=%s status=%d expected=SIGABRT\n',name,status) }
  check(C.WIFSIGNALED(status) && C.WTERMSIG(status)==C.SIGABRT);check(C.strstr(&capture[0],c'usleep boundary BUG with no published records or pages')!=nil)
 } else {
  if !(C.WIFEXITED(status) && C.WEXITSTATUS(status)==0) { C.printf(c'HOST MODEL CHILD STATUS: case=%s status=%d expected=0\n',if name==nil { &char(c'full workload') } else { name },status) }
  check(C.WIFEXITED(status) && C.WEXITSTATUS(status)==0)
 }
 if name!=nil { C.printf(c'HOST MODEL BOUNDARY PASS: %s\n',name) };C.fflush(nil)
} }
@[export:'main']
pub fn run() i32 { unsafe {
 child_case(nil,false)
 cases:=[&char(c'reversed'),&char(c'huge'),&char(c'clock-horizon'),&char(c'absolute-overflow'),&char(c'state'),&char(c'atomic'),&char(c'valid-horizon')]!
 for i:=usize(0);i<cases.len;i++ { child_case(cases[i],i<6) }
 C.printf(c'HOST MODEL GUEST PASS: original workload and all seven boundary cases\n');C.fflush(nil)
 for { C.pause() };return 0
} }
