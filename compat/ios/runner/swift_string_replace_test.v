// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
#include <dlfcn.h>
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr
$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFString.h>
}
fn C.CFStringCreateWithBytes(voidptr,&u8,i64,u32,bool) voidptr
fn C.CFRelease(voidptr)
type ReplaceProbe = fn (u64,u64,u64,&u64)
type ReplaceLiteral = fn (&u8,i64,bool) SwiftStringWords
type ReplaceUnbridge = fn (u64) SwiftStringWords
type ReplaceBytes = fn (u64,u64) u64
type ReplaceDrop = fn (u64)
type ReplacePool = fn () u64
type ReplaceWitness = fn (u64,u64,u64) u64
struct ReplaceApi {
	native bool
	entry u64
	metadata u64
	table u64
	probe u64
	guard u64
	literal ReplaceLiteral
	unbridge ReplaceUnbridge
	bytes ReplaceBytes
	drop ReplaceDrop
	push ReplacePool
	pop ReplaceDrop
}
struct ReplaceCase { source string needle string replacement string expected string options u64 }
fn replace_api(native bool,probe u64,guard u64) ReplaceApi {
	symbol := '_$sSy10FoundationE20replacingOccurrences2of4with7options5rangeSSqd___qd_0_So22NSStringCompareOptionsVSnySS5IndexVGSgtSyRd__SyRd_0_r0_lF'
	mut entry:=u64(0)
	for library in ['/System/Library/Frameworks/Foundation.framework/Foundation','/usr/lib/swift/libswiftFoundation.dylib']! {
		mut current:=u64(0)
		$if macos { if native { current=u64(C.dlsym(C.dlopen(library.str,2),symbol[1..].str)) } }
		if !native {current=runtime_symbol(library,symbol) or {panic(err)}}
		assert current!=0&&(entry==0||entry==current);entry=current
	}
	$if macos { if native {
		core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);foundation:=C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation',2);obj:=C.dlopen(c'/usr/lib/libobjc.A.dylib',2)
		metadata:=u64(C.dlsym(core,c'$sSSN'))
		table:=unsafe{ReplaceWitness(C.dlsym(core,c'swift_getWitnessTable'))(u64(C.dlsym(core,c'$sSSSysMc')),metadata,0)};assert table!=0
		return ReplaceApi{native:true,entry:entry,metadata:u64(C.dlsym(core,c'$sSSN')),table:table,probe:probe,guard:guard,
			literal:unsafe{ReplaceLiteral(C.dlsym(core,c'$sSS21_builtinStringLiteral17utf8CodeUnitCount7isASCIISSBp_BwBi1_tcfC'))},
			unbridge:unsafe{ReplaceUnbridge(C.dlsym(foundation,c'$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ'))},
			bytes:unsafe{ReplaceBytes(C.dlsym(core,c'$sSS11utf8CStrings15ContiguousArrayVys4Int8VGvg'))},drop:unsafe{ReplaceDrop(C.dlsym(core,c'swift_bridgeObjectRelease'))},
			push:unsafe{ReplacePool(C.dlsym(obj,c'objc_autoreleasePoolPush'))},pop:unsafe{ReplaceDrop(C.dlsym(obj,c'objc_autoreleasePoolPop'))}}
	} }
	return ReplaceApi{entry:entry,metadata:swift_string_metadata(),table:guard,probe:probe,guard:guard,
		literal:swift_string_literal,unbridge:swift_foundation_unbridge,bytes:swift_string_utf8_cstring,drop:swift_bridge_release,push:objc_pool_push,pop:objc_pool_pop}
}
fn replace_pair(load bool,first u32,second u32,base u32,offset u32) u32 {return (if load {u32(0xa9400000)}else{u32(0xa9000000)}) | (offset/8)<<15 | second<<10 | base<<5 | first}
fn replace_probe_emit(code u64) {
	// Ordinary (entry, frame, protected x8, capture) -> measured Swift call.
	// Outgoing generic arguments occupy the original SP+0..31, separately
	// from the saved C callee registers. Capture the two result registers and
	// unchanged x20/x21. All other argument registers come from the frame.
	for i,op in [u32(0xd10183ff),replace_pair(false,29,30,31,32),replace_pair(false,19,20,31,48),replace_pair(false,21,22,31,64),
		0xaa0303f3,0xaa0003f0,0xaa0103e9,0xaa0203e8,
		replace_pair(true,10,11,9,72),replace_pair(false,10,11,31,0),replace_pair(true,10,11,9,88),replace_pair(false,10,11,31,16),
		0xf9402134,0xd2824695,replace_pair(true,0,1,9,0),replace_pair(true,2,3,9,16),replace_pair(true,4,5,9,32),replace_pair(true,6,7,9,48),
		0xd63f0200,replace_pair(false,0,1,19,0),replace_pair(false,20,21,19,16),replace_pair(true,29,30,31,32),replace_pair(true,19,20,31,48),replace_pair(true,21,22,31,64),0x910183ff,0xd65f03c0]! {write32(code+u64(i*4),op)}
}
fn replace_words(api ReplaceApi,text string,owned bool) SwiftStringWords {
	if !owned {mut ascii:=true;for byte in text {if byte>=128{ascii=false}};return api.literal(text.str,i64(text.len),ascii)}
	mut object:=u64(0)
	$if macos { if api.native {object=u64(C.CFStringCreateWithBytes(unsafe{nil},text.str,i64(text.len),0x08000100,false))} }
	if !api.native {object=owned_string(text)}
	words:=api.unbridge(object)
	$if macos {if api.native {C.CFRelease(voidptr(object))}}
	if !api.native {objc_release(object)}
	return words
}
fn replace_frame(api ReplaceApi,source u64,needle u64,replacement u64,options u64) [13]u64 {
	return [needle,replacement,options,api.guard,api.guard,u64(0xdead0001),api.metadata,api.metadata,source,api.metadata,api.table,api.table,api.table]!
}
fn replace_call(api ReplaceApi,frame u64,self u64) SwiftStringWords {
	mut capture:=[u64(0xcafe),0,0,0,0,0xbeef]!
	unsafe {ReplaceProbe(voidptr(api.probe))(api.entry,frame,api.guard,&capture[1])}
	assert capture[0]==0xcafe&&capture[3]==self&&capture[4]==0x1234&&capture[5]==0xbeef
	return SwiftStringWords{capture[1],capture[2]}
}
fn replace_assert(api ReplaceApi,words SwiftStringWords,expected string) {
	bytes:=api.bytes(words.first,words.second);assert read64(bytes+16)==u64(expected.len+1)
	assert C.memcmp(voidptr(bytes+32),expected.str,usize(expected.len))==0,expected
	assert unsafe{*(&u8(bytes+32+u64(expected.len)))}==0
	api.drop(bytes)
}
fn replace_case(api ReplaceApi,item ReplaceCase,owned bool) {
	pool:=api.push()
	mut source:=replace_words(api,item.source,owned);mut needle:=replace_words(api,item.needle,owned);mut replacement:=replace_words(api,item.replacement,owned)
	saved:=[source.first,source.second,needle.first,needle.second,replacement.first,replacement.second]!
	mut frame:=replace_frame(api,u64(unsafe{&source}),u64(unsafe{&needle}),u64(unsafe{&replacement}),item.options)
	first:=replace_call(api,u64(unsafe{&frame[0]}),frame[8]);second:=replace_call(api,u64(unsafe{&frame[0]}),frame[8])
	assert saved==[source.first,source.second,needle.first,needle.second,replacement.first,replacement.second]!
	api.drop(source.second);api.drop(needle.second);api.drop(replacement.second);api.pop(pool)
	replace_assert(api,first,item.expected);api.drop(first.second);replace_assert(api,second,item.expected);api.drop(second.second)
}
fn replace_cases(api ReplaceApi) {
	for item in [
		ReplaceCase{'','','x','',0},ReplaceCase{'abc','','X','abc',0},ReplaceCase{'','a','x','',0},ReplaceCase{'abc','z','x','abc',0},
		ReplaceCase{'aaaaa','aa','b','bba',0},ReplaceCase{'abababa','aba','x','xbx',0},ReplaceCase{'aaaa','a','aa','aaaaaaaa',0},
		ReplaceCase{'abcabc','abc','','',0},ReplaceCase{'abcabc','abc','abc','abcabc',0},ReplaceCase{'abc','abcd','x','abc',0},
		ReplaceCase{'Fortnite+/==','+','-','Fortnite-/==',0},ReplaceCase{'Fortnite-/==','/','_','Fortnite-_==',0},ReplaceCase{'Fortnite-_==','=','', 'Fortnite-_',0},
		ReplaceCase{'a\x00a\x00b','\x00','--','a--a--b',0},ReplaceCase{'a\x00b','a\x00','π\x00','π\x00b',0},ReplaceCase{'line\nline\r\n','\n','','lineline\r',0},
		ReplaceCase{'ababababac','ababac','X','ababX',0},ReplaceCase{'abaaba','aba','ababa','ababaababa',0},
		ReplaceCase{'π/🎮/é','/','_','π_🎮_é',2},ReplaceCase{'é é é','é','x','x é x',2},ReplaceCase{'a🎮b🎮','🎮','π','aπbπ',2},
		ReplaceCase{'éé','é','é','éé',2},ReplaceCase{'long Unicode αβγδεζηθικλμνξοπ','αβγ','🎮','long Unicode 🎮δεζηθικλμνξοπ',2},
		ReplaceCase{'AAAA','a','x','AAAA',2},ReplaceCase{'ASCII','I','é 🎮','ASCé 🎮é 🎮',0}
	]! { for owned in [false,true]! {replace_case(api,item,owned)} }
	for count in [0,1,14,15,16,17,31,32,4096,65536]! {
		text:='a'.repeat(count);pairs:='b'.repeat(count/2);tail:='a'.repeat(count%2);expected:=pairs+tail
		replace_case(api,ReplaceCase{text,'aa','b',expected,0},true)
		unsafe{text.free();pairs.free();tail.free();expected.free()}
	}
	// Full 4096-byte pattern and an adversarial shared prefix exercise the
	// bounded linear search, including a late match after many failed starts.
	prefix:='a'.repeat(4095);needle:=prefix+'b';run:='a'.repeat(16384);source:=run+'b';left:='a'.repeat(12289);expected:=left+'x'
	replace_case(api,ReplaceCase{source,needle,'x',expected,0},true)
	unsafe{prefix.free();needle.free();run.free();source.free();left.free();expected.free()}
}
fn replace_worker(api ReplaceApi) {for _ in 0..16 {replace_case(api,ReplaceCase{'concurrent Fortnite+/==','+','π','concurrent Fortniteπ/==',0},true)}}
fn replace_private_storage(api ReplaceApi) {
	// All three borrowed arguments may alias the same value. Results own a
	// copy even after the sole source reference and the other result die.
	mut value:=replace_words(api,'aliased Fortnite String owner',true)
	address:=u64(unsafe{&value});mut alias:=replace_frame(api,address,address,address,0)
	result:=replace_call(api,u64(unsafe{&alias[0]}),address);api.drop(value.second)
	replace_assert(api,result,'aliased Fortnite String owner');api.drop(result.second)
	for text in ['foreign Fortnite string / suffix','π/🎮/é']! {
		object:=owned_string(text);mut units:=u64(0);for byte in text {if byte&0xc0!=0x80 {units+=if byte>=0xf0 {u64(2)}else{u64(1)}}}
		mut source:=SwiftStringWords{units,object|u64(0x5000000000000000)}
		mut needle:=replace_words(api,'/',false);mut replacement:=replace_words(api,'_',false)
		mut frame:=replace_frame(api,u64(unsafe{&source}),u64(unsafe{&needle}),u64(unsafe{&replacement}),2)
		first:=replace_call(api,u64(unsafe{&frame[0]}),frame[8]);objc_release(object)
		expected:=text.replace('/','_');replace_assert(api,first,expected);api.drop(first.second);unsafe{expected.free()}
	}
	page:=usize(C.getpagesize());mapping:=C.mmap(unsafe{nil},page*2,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0);assert mapping!=voidptr(-1)
	defer{assert C.munmap(mapping,page*2)==0}
	text:='bounded-Fortnite!/';start:=u64(mapping)+u64(page)-u64(text.len);C.memcpy(voidptr(start),text.str,usize(text.len))
	assert C.mprotect(mapping,page,C.PROT_READ)==0&&C.mprotect(voidptr(u64(mapping)+u64(page)),page,C.PROT_NONE)==0
	mut source:=swift_string_literal(unsafe{&u8(start)},i64(text.len),true);mut needle:=replace_words(api,'/',false);mut replacement:=replace_words(api,'X',false)
	mut frame:=replace_frame(api,u64(unsafe{&source}),u64(unsafe{&needle}),u64(unsafe{&replacement}),0)
	first:=replace_call(api,u64(unsafe{&frame[0]}),frame[8]);replace_assert(api,first,'bounded-Fortnite!X');api.drop(first.second)
}
fn replace_invalid(api ReplaceApi) {
	mut source:=replace_words(api,'original Fortnite String',true);mut needle:=replace_words(api,'i',false);mut replacement:=replace_words(api,'replacement',true)
	mut frame:=replace_frame(api,u64(unsafe{&source}),u64(unsafe{&needle}),u64(unsafe{&replacement}),0)
	baseline:=ios_runtime.swift_strings.len
	for slot in [6,7,9]! {old:=frame[slot];frame[slot]=api.guard;if _:=swift_string_replace_checked(u64(unsafe{&frame[0]})){assert false};frame[slot]=old}
	for options in [u64(1),3,4,8,16,128,1024,~u64(0)]! {frame[2]=options;if _:=swift_string_replace_checked(u64(unsafe{&frame[0]})){assert false}};frame[2]=0
	for tag in [u64(0),2,255]! {frame[5]=tag;if _:=swift_string_replace_checked(u64(unsafe{&frame[0]})){assert false}};frame[5]=1
	for slot in [0,1,8]! {old:=frame[slot];frame[slot]=0;if _:=swift_string_replace_checked(u64(unsafe{&frame[0]})){assert false};frame[slot]=old}
	for malformed in [SwiftStringWords{0,u64(0x2000000000000000)},SwiftStringWords{1048577|u64(0x1000000000000000),api.guard|u64(0x8000000000000000)},SwiftStringWords{u64(0x1000000000000000),api.guard},SwiftStringWords{0,api.guard|u64(0x5000000000000000)},SwiftStringWords{0xff,u64(0xa100000000000000)}]! {
		mut value:=malformed;frame[8]=u64(unsafe{&value});if _:=swift_string_replace_checked(u64(unsafe{&frame[0]})){assert false}
	};frame[8]=u64(unsafe{&source})
	for item in [ReplaceCase{'é','é','x','',0},ReplaceCase{'x','a'.repeat(4097),'b','',0},ReplaceCase{'x'.repeat(1048576),'x','yy','',0}]! {
		mut a:=replace_words(api,item.source,true);mut b:=replace_words(api,item.needle,true);mut c:=replace_words(api,item.replacement,true)
		mut invalid:=replace_frame(api,u64(unsafe{&a}),u64(unsafe{&b}),u64(unsafe{&c}),item.options)
		if _:=swift_string_replace_checked(u64(unsafe{&invalid[0]})){assert false};api.drop(a.second);api.drop(b.second);api.drop(c.second)
		// Only generated case text is owned by this fixture.
		if item.source.len==1048576 {unsafe{item.source.free()}};if item.needle.len==4097 {unsafe{item.needle.free()}}
	}
	assert ios_runtime.swift_strings.len==baseline
	api.drop(source.second);api.drop(needle.second);api.drop(replacement.second)
}
fn test_swift_string_replacement() {
	page:=usize(C.getpagesize());code:=C.mmap(unsafe{nil},page*2,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0);assert code!=voidptr(-1)
	defer{assert C.munmap(code,page*2)==0}
	replace_probe_emit(u64(code));C.__builtin___clear_cache(code,voidptr(u64(code)+104));assert C.mprotect(code,page,C.PROT_READ|C.PROT_EXEC)==0
	guard:=u64(code)+u64(page);assert C.mprotect(voidptr(guard),page,C.PROT_NONE)==0
	$if macos {
		api:=replace_api(true,u64(code),guard);replace_cases(api)
		mut workers:=[]thread{};for _ in 0..8 {workers<<spawn replace_worker(api)};workers.wait();unsafe{workers.free()}
		println('IOS-SWIFT-STRING-REPLACE-NATIVE: measured generic register/stack ABI, borrowed Self, nil range tag, owned two-word result, default ASCII/literal Unicode, NUL, empty and overlapping patterns, long prefix search, concurrency')
		if os.getenv('VINIX_REPLACE_NATIVE_ONLY')=='1' {return}
	}
	for _ in 0..2 {
		objc_start();api:=replace_api(false,u64(code),guard);replace_cases(api);replace_private_storage(api);replace_invalid(api)
		mut workers:=[]thread{};for _ in 0..8 {workers<<spawn replace_worker(api)};workers.wait();unsafe{workers.free()}
		assert ios_runtime.swift_strings.len==0&&ios_runtime.swift_buffers.len==0&&ios_runtime.swift_heap.len==0&&ios_runtime.live==0
		objc_stop();assert ios_runtime.swift_foundation_arena==0
	}
	println('IOS-SWIFT-STRING-REPLACE: concrete String specialization, bounded linear nonoverlapping replacement, independent owned results, protected nil payload/x8/witnesses, rejected unsupported options/ranges/metadata/Unicode default/owners/limits, concurrent calls and two drained lifetimes')
}
