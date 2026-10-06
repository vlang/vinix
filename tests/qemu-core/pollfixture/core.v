// SPDX-License-Identifier: BSD-2-Clause
// Original independent pollfd ABI checks, lines2404-2425.
@[translated]
module pollfixture
#include <pollfixture_v_contract.h>
struct C.pollfd { mut: fd i32 events i16 revents i16 }
@[c_extern] __global C.errno i32
fn C.printf(&char,...) i32
fn C.puts(&char) i32
fn C.pipe(&i32) i32
fn C.poll(&C.pollfd,usize,i32) i32
fn C.read(i32,voidptr,usize) isize
fn C.write(i32,voidptr,usize) isize
fn C.close(i32) i32
fn check(ok bool,line i32,expression &char) bool {
 if !ok { unsafe { C.printf(c'QEMU CORE FAIL line %d: %s (errno=%d)\n',line,expression,C.errno) } };return ok
}
@[export:'test_pollfd_abi']
pub fn pollfd_abi() i32 { unsafe {
 mut pair:=[2]i32{}
 if !check(C.pipe(&pair[0])==0,2407,c'pipe(pair) == 0') { return 1 }
 mut descriptor:=C.pollfd{fd:pair[0],events:i16(C.POLLIN)}
 if !check(C.poll(&descriptor,1,0)==0,2412,c'poll(&descriptor, 1, 0) == 0') { return 1 }
 if !check(descriptor.revents==0,2413,c'descriptor.revents == 0') { return 1 }
 if !check(C.write(pair[1],c'p',1)==1,2414,c'write(pair[1], "p", 1) == 1') { return 1 }
 if !check(C.poll(&descriptor,1,1000)==1,2415,c'poll(&descriptor, 1, 1000) == 1') { return 1 }
 if !check((descriptor.revents & C.POLLIN)!=0,2416,c'(descriptor.revents & POLLIN) != 0') { return 1 }
 mut byte:=i8(0)
 if !check(C.read(pair[0],&byte,1)==1,2418,c'read(pair[0], &byte, 1) == 1') { return 1 }
 if !check(byte==`p`,2419,c"byte == 'p'") { return 1 }
 if !check(C.close(pair[0])==0,2420,c'close(pair[0]) == 0') { return 1 }
 if !check(C.close(pair[1])==0,2421,c'close(pair[1]) == 0') { return 1 }
 C.puts(c'QEMU CORE PASS: Linux pollfd ABI');return 0
} }
