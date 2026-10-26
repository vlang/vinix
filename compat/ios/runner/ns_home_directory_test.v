// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
#include <dlfcn.h>
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr
type HomeCall = fn () u64
type HomeProbe = fn (u64,u64,&u64)
type HomeSend = fn (u64,u64,u64,u64) u64
type HomeName = fn (&char) u64
type HomeRetain = fn (u64) u64
type HomeDrop = fn (u64)
struct HomeApi {
	native bool
	entry u64
	probe u64
	guard u64
	strings u64
	manager u64
	send HomeSend
	selector HomeName
	retain HomeRetain
	drop HomeDrop
	push HomeCall
	pop HomeDrop
}
fn home_api(native bool,probe u64,guard u64) HomeApi {
	$if macos {if native {
		foundation:=C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation',2);obj:=C.dlopen(c'/usr/lib/libobjc.A.dylib',2)
		cls:=unsafe{HomeName(C.dlsym(obj,c'objc_getClass'))}
		return HomeApi{native:true,entry:u64(C.dlsym(foundation,c'NSHomeDirectory')),probe:probe,guard:guard,strings:cls(c'NSString'),manager:cls(c'NSFileManager'),
			send:unsafe{HomeSend(C.dlsym(obj,c'objc_msgSend'))},selector:unsafe{HomeName(C.dlsym(obj,c'sel_registerName'))},retain:unsafe{HomeRetain(C.dlsym(obj,c'objc_retain'))},drop:unsafe{HomeDrop(C.dlsym(obj,c'objc_release'))},
			push:unsafe{HomeCall(C.dlsym(obj,c'objc_autoreleasePoolPush'))},pop:unsafe{HomeDrop(C.dlsym(obj,c'objc_autoreleasePoolPop'))}}
	}}
	return HomeApi{entry:runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation','_NSHomeDirectory') or {panic(err)},probe:probe,guard:guard,strings:ios_runtime.names['NSString'],manager:ios_runtime.names['NSFileManager'],
		send:unsafe{HomeSend(voidptr(C.ios_objc_builtin))},selector:objc_selector,retain:objc_retain,drop:objc_release,push:objc_pool_push,pop:objc_pool_pop}
}
fn home_probe_emit(code u64) {
	// Ordinary no-argument C call, with protected x0-x8/x20 and a canary in
	// x21. Callee-saved registers occupy a separate frame. Capture x0 and the
	// preserved contexts; x1 is unspecified for this one-word result.
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0203f3,0xaa0003f0,
		0xaa0103e0,0xaa0003e2,0xaa0003e3,0xaa0003e4,0xaa0003e5,0xaa0003e6,0xaa0003e7,0xaa0003e8,0xaa0003f4,0xd2824695,
		0xd63f0200,0xa9000660,0xa9015674,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]! {write32(code+u64(i*4),op)}
}
fn home_message(api HomeApi,object u64,selector &char,a u64) u64 {return api.send(object,api.selector(selector),a,0)}
fn home_text(api HomeApi,object u64) string {return unsafe{(&char(home_message(api,object,c'UTF8String',0))).vstring()}}
fn home_raw(api HomeApi) u64 {
	mut capture:=[u64(0xcafe),0,0,0,0,0xbeef]!
	unsafe{HomeProbe(voidptr(api.probe))(api.entry,api.guard,&capture[1])}
	assert capture[0]==0xcafe&&capture[3]==api.guard&&capture[4]==0x1234&&capture[5]==0xbeef
	return capture[1]
}
fn home_case(api HomeApi,expected string,isolated bool) {
	baseline:=if api.native || !isolated {i64(0)}else{ios_runtime.live}
	pool:=api.push();first:=unsafe{HomeCall(voidptr(api.entry))()};second:=home_raw(api)
	assert first!=0&&second!=0
	assert home_message(api,first,c'isKindOfClass:',api.strings)==1
	assert home_text(api,first)==expected&&home_text(api,second)==expected
	if !api.native && isolated {assert first!=second&&obj_header(first).refs==1&&obj_header(second).refs==1}
	assert api.retain(first)==first
	api.pop(pool)
	if !api.native && isolated {assert first in ios_runtime.objects&&obj_header(first).refs==1&&second !in ios_runtime.objects}
	assert home_text(api,first)==expected;api.drop(first)
	if !api.native && isolated {assert ios_runtime.live==baseline}
}
fn home_worker(api HomeApi,expected string) {pool:=api.push();for _ in 0..32 {home_case(api,expected,false)};api.pop(pool)}
fn home_threads(api HomeApi,expected string) {
	mut workers:=[]thread{};for _ in 0..8 {workers<<spawn home_worker(api,expected)};workers.wait();unsafe{workers.free()}
}
fn home_private_cases(api HomeApi) {
	for item in [
		['/var/mobile/Containers/Bundle/Application/uuid/Fortnite.app','','/var/mobile/Containers/Bundle/Application/uuid']!,
		['/opt/ios/Fortnite.app','/tmp/Data/Documents','/tmp/Data']!,
		['/opt/ios/Fortnite.app','/tmp/π 🎮/Documents','/tmp/π 🎮']!,
		['/opt/ios/Fortnite.app','/tmp/Data/Documents///','/tmp/Data']!,
		['/Fortnite.app','','/']!,['/','','/']!,['/opt/ios/Fortnite.app','/','/']!,
		['/opt/ios/Fortnite.app','/tmp//Data/Documents','/tmp/Data']!
	]! {
		ios_runtime.bundle=item[0];os.setenv('VINIX_IOS_DOCUMENTS',item[1],true);home_case(api,item[2],true)
	}
	name:='a'.repeat(1012);expected:='/'+name;documents:=expected+'/Documents'
	os.setenv('VINIX_IOS_DOCUMENTS',documents,true);assert documents.len==1023;home_case(api,expected,true)
	unsafe{name.free();documents.free();expected.free()}
	// A V string does not imply a readable NUL beyond its byte extent.
	page:=usize(C.getpagesize());mapping:=C.mmap(unsafe{nil},page*2,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0);assert mapping!=voidptr(-1)
	defer{assert C.munmap(mapping,page*2)==0}
	path:='/tmp/guarded Fortnite/Fortnite.app';start:=u64(mapping)+u64(page)-u64(path.len);C.memcpy(voidptr(start),path.str,usize(path.len))
	assert C.mprotect(mapping,page,C.PROT_READ)==0&&C.mprotect(voidptr(u64(mapping)+u64(page)),page,C.PROT_NONE)==0
	os.unsetenv('VINIX_IOS_DOCUMENTS');ios_runtime.bundle=unsafe{tos(&u8(start),path.len)};home_case(api,'/tmp/guarded Fortnite',true);ios_runtime.bundle=''
	for invalid in ['', 'relative/Documents','/tmp/./Documents','/tmp/../Documents','/tmp/embedded\x00NUL/Documents']! {if _:=ns_home_parent_checked(invalid){assert false,invalid}}
	invalid_utf8:=[u8(`/`),0xff]!
	if _:=ns_home_parent_checked(unsafe{tos(&invalid_utf8[0],2)}) {assert false}
	long_name:='a'.repeat(1023);too_long:='/'+long_name;os.setenv('VINIX_IOS_DOCUMENTS',too_long,true)
	if _:=ns_home_directory_checked(){assert false};unsafe{long_name.free();too_long.free()}
	os.unsetenv('VINIX_IOS_DOCUMENTS');ios_runtime.bundle=''
	if _:=ns_home_directory_checked(){assert false}
	// Neither home nor search-path queries create directories.
	pid:=os.getpid().str();base:='/tmp/vinix-home-'+pid;bundle:=base+'/Fortnite.app';docs:=base+'/Documents'
	assert !os.exists(base);ios_runtime.bundle=bundle;home_case(api,base,true);assert !os.exists(base)
	pool:=api.push();paths:=ns_search_paths(9,1,true);assert obj_header(paths).items.len==1&&string_text(obj_header(paths).items[0])==docs;api.pop(pool)
	assert !os.exists(base)
	home_threads(api,base);ios_runtime.bundle='';unsafe{pid.free();base.free();bundle.free();docs.free()}
	if _:=runtime_symbol('/System/Library/Frameworks/UIKit.framework/UIKit','_NSHomeDirectory'){assert false}
	assert ios_runtime.live==0
}
fn test_ns_home_directory() {
	page:=usize(C.getpagesize());code:=C.mmap(unsafe{nil},page*2,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0);assert code!=voidptr(-1)
	defer{assert C.munmap(code,page*2)==0}
	home_probe_emit(u64(code));C.__builtin___clear_cache(code,voidptr(u64(code)+88));assert C.mprotect(code,page,C.PROT_READ|C.PROT_EXEC)==0
	guard:=u64(code)+u64(page);assert C.mprotect(voidptr(guard),page,C.PROT_NONE)==0
	$if macos {
		api:=home_api(true,u64(code),guard);pool:=api.push();manager:=home_message(api,api.manager,c'defaultManager',0);url:=home_message(api,manager,c'homeDirectoryForCurrentUser',0)
		expected:=home_text(api,home_message(api,url,c'path',0)).clone();assert expected.starts_with('/')
		home_case(api,expected,true);home_threads(api,expected);api.pop(pool);unsafe{expected.free()}
		println('IOS-HOME-DIRECTORY-NATIVE: no-argument C ABI, protected argument/x8 registers, preserved x20/x21, NSString path equal to native file-manager home, +0 autorelease/retain lifetime and eight concurrent workers')
	}
	existed:=C.getenv(c'VINIX_IOS_DOCUMENTS')!=unsafe{nil};saved:=os.getenv('VINIX_IOS_DOCUMENTS')
	defer{if existed {os.setenv('VINIX_IOS_DOCUMENTS',saved,true)}else{os.unsetenv('VINIX_IOS_DOCUMENTS')};unsafe{saved.free()}}
	if _:=ns_home_directory_checked(){assert false}
	for _ in 0..2 {
		objc_start();api:=home_api(false,u64(code),guard);home_private_cases(api)
		assert ios_runtime.objects.len==0&&ios_runtime.swift_strings.len==0&&ios_runtime.swift_buffers.len==0&&ios_runtime.live==0
		objc_stop();if _:=ns_home_directory_checked(){assert false}
	}
	println('IOS-HOME-DIRECTORY: Foundation-only C export, bounded borrowed parent paths, existing app Documents convention, copied autoreleased NSString results, Unicode/space/root/trailing-slash/1023-byte/protected-prefix cases, no directory creation, Documents integration, invalid/lifetime rejection, concurrent readers and two drained runtimes')
}
