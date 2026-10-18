// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlsym(voidptr,&char)voidptr

// Independent of the adapter's result declaration; the raw ARM64 probe below
// also checks the actual register returned to Fortnite's LSR x8,x0,#32 caller.
struct DivTestResult {quotient i32;remainder i32}
type DivTestCall = fn(i32,i32)DivTestResult
type DivTestProbe = fn(u64,u64,u64,u64,u64)

fn div_test_property(call DivTestCall,numerator i32,denominator i32){
	result:=call(numerator,denominator)
	assert i64(result.quotient)*i64(denominator)+i64(result.remainder)==i64(numerator)
	rem:=if result.remainder<0{-i64(result.remainder)}else{i64(result.remainder)}
	den:=if denominator<0{-i64(denominator)}else{i64(denominator)}
	assert rem<den
	assert result.remainder==0||(result.remainder<0)==(numerator<0)
	$if macos{
		native:=unsafe{DivTestCall(C.dlsym(voidptr(-2),c'div'))};expected:=native(numerator,denominator)
		assert result.quotient==expected.quotient&&result.remainder==expected.remainder
	}
}

fn div_test_corpus(call DivTestCall){
	values:=[i32(-2147483648),-2147483647,-65536,-32769,-257,-10,-7,-3,-1,0,1,3,7,10,257,32769,65536,2147483646,2147483647]!
	for numerator in values{for denominator in values{if denominator==0||(numerator==i32(-2147483648)&&denominator== -1){continue};div_test_property(call,numerator,denominator)}}
	for n in 0..257{for d in 0..131{if d==65{continue};div_test_property(call,i32(n-128),i32(d-65))}}
	mut bits:=u32(0x97e5_120b)
	for _ in 0..32768{
		bits^=bits<<13;bits^=bits>>17;bits^=bits<<5;numerator:=i32(bits)
		bits^=bits<<13;bits^=bits>>17;bits^=bits<<5;denominator:=i32(bits)
		if denominator==0||(numerator==i32(-2147483648)&&denominator== -1){continue};div_test_property(call,numerator,denominator)
	}
}

fn div_test_state(call DivTestCall){
	mut environment:=[32]u64{};assert C.fegetenv(unsafe{voidptr(&environment[0])})==0;previous:=unsafe{*C.ios_errno_address()}
	defer{C.fesetenv(unsafe{voidptr(&environment[0])});darwin_set_errno(previous)}
	for rounding in [i32(C.FE_TONEAREST),C.FE_UPWARD,C.FE_DOWNWARD,C.FE_TOWARDZERO]!{
		assert C.fesetround(rounding)==0;C.feclearexcept(C.FE_ALL_EXCEPT);C.feraiseexcept(C.FE_DIVBYZERO|C.FE_INEXACT);flags:=C.fetestexcept(C.FE_ALL_EXCEPT);darwin_set_errno(42)
		div_test_corpus(call)
		zero:=call(7,0);assert zero.quotient==0&&zero.remainder==7
		overflow:=call(i32(-2147483648),-1);assert overflow.quotient==i32(-2147483648)&&overflow.remainder==0
		assert C.fegetround()==rounding&&C.fetestexcept(C.FE_ALL_EXCEPT)==flags&&unsafe{*C.ios_errno_address()}==42
	}
}

fn div_test_worker(call DivTestCall,id int){
	mut environment:=[32]u64{};assert C.fegetenv(unsafe{voidptr(&environment[0])})==0;defer{C.fesetenv(unsafe{voidptr(&environment[0])})}
	assert C.fesetround(i32(C.FE_DOWNWARD))==0;C.feclearexcept(C.FE_ALL_EXCEPT);C.feraiseexcept(C.FE_DIVBYZERO);flags:=C.fetestexcept(C.FE_ALL_EXCEPT);darwin_set_errno(70+id)
	for i in 0..4096{div_test_property(call,i32((i-2048)*(id+1)),i32(id+1))}
	assert C.fegetround()==C.FE_DOWNWARD&&C.fetestexcept(C.FE_ALL_EXCEPT)==flags&&unsafe{*C.ios_errno_address()}==70+id
}

fn div_test_registers(address u64,code u64,guard u64){
	probe:=unsafe{DivTestProbe(voidptr(code))}
	for pair in [[i32(7),3]!,[-7,3]!,[7,-3]!,[-7,-3]!,[i32(-2147483648),1]!,[i32(-2147483648),2147483647]!]!{
		n:=i64(pair[0]);d:=i64(pair[1]);expected:=u64(u32(i32(n/d)))|(u64(u32(i32(n%d)))<<32)
		mut result:=[u64(0xcafe),0,0,0xbeef]!
		probe(address,(u64(0x76543210)<<32)|u64(u32(pair[0])),(u64(0x87654321)<<32)|u64(u32(pair[1])),u64(unsafe{&result[1]}),guard)
		assert result==[u64(0xcafe),expected,0x5121,0xbeef]!
	}
}

fn test_integer_division(){
	assert sizeof(DivTestResult)==8
	page:=usize(C.getpagesize());guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert guard!=u64(-1)
	code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=u64(-1)
	for i,op in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0x910003fd,0xaa0003f0,0xaa0103e0,0xaa0203e1,0xaa0303f4,0xaa0403e8,0xd28a2433,0xd63f0200,0xf9000280,0xf9000693,0xa9425bf5,0xa94153f3,0xa8c37bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
	C.__builtin___clear_cache(voidptr(code),voidptr(code+68));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0
	$if macos{
		native:=u64(C.dlsym(voidptr(-2),c'div'));assert native!=0;div_test_state(unsafe{DivTestCall(voidptr(native))});div_test_registers(native,code,guard)
	}
	address:=runtime_symbol('/usr/lib/libSystem.B.dylib','_div') or {panic(err)};call:=unsafe{DivTestCall(voidptr(address))}
	div_test_state(call);div_test_registers(address,code,guard)
	mut workers:=[]thread{cap:8};for id in 0..8{workers<<spawn div_test_worker(call,id)};workers.wait();unsafe{workers.free()}
	for library in ['/usr/lib/libobjc.A.dylib','/usr/lib/libz.1.dylib','/System/Library/Frameworks/Foundation.framework/Foundation']!{mut rejected:=false;runtime_symbol(library,'_div') or {rejected=true};assert rejected}
	assert C.munmap(voidptr(code),page)==0&&C.munmap(voidptr(guard),page)==0
	println('IOS-INTEGER-DIVISION: signed quotient/remainder properties, native oracle, exhaustive small operands, 32768 full-width pairs, packed x0/dirty upper inputs/protected x8/callee-saved register ABI, four rounding modes, unchanged errno/sticky flags and eight concurrent callers passed')
}
