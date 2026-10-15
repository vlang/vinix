// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
#include <dlfcn.h>
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr
$if macos {
	#flag -framework CoreFoundation
	#include <CoreFoundation/CFString.h>
	#include <CoreFoundation/CFURL.h>
}
fn C.CFStringCreateWithBytes(voidptr,&u8,i64,u32,bool) voidptr
fn C.CFURLCreateFromFileSystemRepresentation(voidptr,&u8,i64,bool) voidptr
fn C.CFURLCreateWithBytes(voidptr,&u8,i64,u32,voidptr) voidptr
type ArrayBridgeProbe = fn (u64,u64,u64,u64,u64,u64,u64,&u64)
type ArrayBridgeSend = fn (u64,u64,u64,u64) u64
type ArrayBridgeName = fn (&char) u64
type ArrayBridgeMetadata = fn (u64) u64
type ArrayBridgeAccess = fn (u64,u64) SwiftAssociatedMetadata
type ArrayBridgeURLAccess = fn (u64) SwiftAssociatedMetadata
type ArrayBridgeLookup = fn (u64,u64,u64) u64
type ArrayBridgeRetain = fn (u64) u64
type ArrayBridgeDrop = fn (u64)
type ArrayBridgePool = fn () u64
type ArrayBridgeBytes = fn (u64,u64) u64
type ArrayBridgeString = fn (u64) SwiftStringWords
type ArrayBridgeCopy = fn (u64,u64,u64) u64
type ArrayBridgeDestroy = fn (u64,u64)

struct ArrayBridgeApi {
	native bool
	code u64
	entry u64
	url_bridge u64
	append u64
	delete u64
	string_type u64
	url_type u64
	object_type u64
	objc_string_type u64
	sequence u64
	root u64
	strings u64
	arrays u64
	mutable_arrays u64
	access ArrayBridgeAccess
	lookup ArrayBridgeLookup
	retain ArrayBridgeRetain
	release ArrayBridgeDrop
	drop ArrayBridgeDrop
	send ArrayBridgeSend
	selector ArrayBridgeName
	push ArrayBridgePool
	pop ArrayBridgeDrop
	bytes ArrayBridgeBytes
}

fn array_bridge_api(native bool, code u64) ArrayBridgeApi {
	symbol := '_$sSa10FoundationE36_unconditionallyBridgeFromObjectiveCySayxGSo7NSArrayCSgFZ'
	mut entry := u64(0)
	for library in ['/System/Library/Frameworks/Foundation.framework/Foundation','/usr/lib/swift/libswiftFoundation.dylib']! {
		mut current := u64(0)
		$if macos { if native { current=u64(C.dlsym(C.dlopen(library.str,2),symbol[1..].str)) } }
		if !native { current=runtime_symbol(library,symbol) or {panic(err)} }
		assert current!=0&&(entry==0||entry==current);entry=current
	}
	$if macos { if native {
		core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);obj:=C.dlopen(c'/usr/lib/libobjc.A.dylib',2)
		foundation:=C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation',2)
		cls:=unsafe { ArrayBridgeName(C.dlsym(obj,c'objc_getClass')) };meta:=unsafe { ArrayBridgeMetadata(C.dlsym(core,c'swift_getObjCClassMetadata')) }
		response:=unsafe { ArrayBridgeURLAccess(C.dlsym(foundation,c'$s10Foundation3URLVMa'))(0) }
		return ArrayBridgeApi{native:true,code:code,entry:entry,
			url_bridge:u64(C.dlsym(foundation,c'$s10Foundation3URLV19_bridgeToObjectiveCSo5NSURLCyF')),
			append:u64(C.dlsym(foundation,c'$s10Foundation3URLV22appendingPathComponent_11isDirectoryACSS_SbtF')),
			delete:u64(C.dlsym(foundation,c'$s10Foundation3URLV25deletingLastPathComponentACyF')),
			string_type:u64(C.dlsym(core,c'$sSSN')),url_type:response.metadata,object_type:meta(cls(c'NSObject')),objc_string_type:meta(cls(c'NSString')),
			sequence:u64(C.dlsym(core,c'$sSayxGSTsMc')),root:cls(c'NSObject'),strings:cls(c'NSString'),arrays:cls(c'NSArray'),mutable_arrays:cls(c'NSMutableArray'),
			access:unsafe { ArrayBridgeAccess(C.dlsym(core,c'$sSaMa')) },lookup:unsafe { ArrayBridgeLookup(C.dlsym(core,c'swift_getWitnessTable')) },
			retain:unsafe { ArrayBridgeRetain(C.dlsym(core,c'swift_bridgeObjectRetain')) },release:unsafe { ArrayBridgeDrop(C.dlsym(core,c'swift_bridgeObjectRelease')) },
			drop:unsafe { ArrayBridgeDrop(C.dlsym(obj,c'objc_release')) },send:unsafe { ArrayBridgeSend(C.dlsym(obj,c'objc_msgSend')) },selector:unsafe { ArrayBridgeName(C.dlsym(obj,c'sel_registerName')) },
			push:unsafe { ArrayBridgePool(C.dlsym(obj,c'objc_autoreleasePoolPush')) },pop:unsafe { ArrayBridgeDrop(C.dlsym(obj,c'objc_autoreleasePoolPop')) },
			bytes:unsafe { ArrayBridgeBytes(C.dlsym(core,c'$sSS11utf8CStrings15ContiguousArrayVys4Int8VGvg')) }}
	} }
	return ArrayBridgeApi{code:code,entry:entry,
		url_bridge:swift_foundation_symbol('_$s10Foundation3URLV19_bridgeToObjectiveCSo5NSURLCyF') or {panic(err)},
		append:swift_foundation_symbol('_$s10Foundation3URLV22appendingPathComponent_11isDirectoryACSS_SbtF') or {panic(err)},
		delete:swift_foundation_symbol('_$s10Foundation3URLV25deletingLastPathComponentACyF') or {panic(err)},
		string_type:swift_string_metadata(),url_type:swift_foundation_arena()+u64(C.getpagesize())+144,
		object_type:swift_objc_metadata(ios_runtime.names['NSObject']),objc_string_type:swift_objc_metadata(ios_runtime.names['NSString']),
		sequence:swift_array_sequence_symbol('_$sSayxGSTsMc') or {panic('missing Array Sequence')},
		root:ios_runtime.names['NSObject'],strings:ios_runtime.names['NSString'],arrays:ios_runtime.names['NSArray'],mutable_arrays:ios_runtime.names['NSMutableArray'],
		access:swift_array_access,lookup:swift_witness_table,retain:swift_bridge_retain,release:swift_bridge_release,drop:objc_release,
		send:unsafe { ArrayBridgeSend(voidptr(C.ios_objc_builtin)) },selector:objc_selector,push:objc_pool_push,pop:objc_pool_pop,bytes:swift_string_utf8_cstring}
}

fn array_bridge_call(api ArrayBridgeApi, entry u64, a u64, b u64, c u64, receiver u64, output u64) u64 {
	mut capture:=[u64(0xcafe),0,0,0,0,0xbeef]!
	unsafe { ArrayBridgeProbe(voidptr(api.code))(entry,a,b,c,0,receiver,output,&capture[1]) }
	assert capture[0]==0xcafe&&capture[3]==receiver&&capture[4]==0&&capture[5]==0xbeef
	return capture[1]
}

fn array_bridge_message(api ArrayBridgeApi, object u64, selector &char, a u64, b u64) u64 { return api.send(object,api.selector(selector),a,b) }
fn array_bridge_element(api ArrayBridgeApi,kind int) u64 { return match kind {0 {api.string_type} 1 {api.url_type} 2 {api.object_type} else {api.objc_string_type}} }
fn array_bridge_label(index int) string { return match index%5 {0 {''} 1 {'Fortnite'} 2 {'é 🎮 owned NSArray bridge String'} 3 {'an independently owned longer String payload'} else {'embedded\x00NUL String'}} }
fn array_bridge_path(index int) string { return '/tmp/FortniteArray/item-${index}' }

fn array_bridge_string(api ArrayBridgeApi, text string) u64 {
	$if macos { if api.native { return u64(C.CFStringCreateWithBytes(unsafe {nil},text.str,i64(text.len),0x08000100,false)) } }
	return owned_string(text)
}
fn array_bridge_url(api ArrayBridgeApi,path string,http bool) u64 {
	$if macos { if api.native {
		return if http {u64(C.CFURLCreateWithBytes(unsafe {nil},path.str,i64(path.len),0x08000100,unsafe {nil}))}else{u64(C.CFURLCreateFromFileSystemRepresentation(unsafe {nil},path.str,i64(path.len),false))}
	} }
	if !http {return ui_file_url(path)}
	url:=objc_allocate(ios_runtime.names['NSURL']);text:=owned_string(path);assert http_url_initialize(url,text);objc_release(text);return url
}
fn array_bridge_source(api ArrayBridgeApi,items []u64,mutable bool) u64 {
	cls:=if mutable {api.mutable_arrays}else{api.arrays}
	$if macos { if api.native {return array_bridge_message(api,array_bridge_message(api,cls,c'alloc',0,0),c'initWithObjects:count:',u64(items.data),u64(items.len))} }
	object:=objc_allocate(cls);mut header:=obj_header(object);header.items=[]u64{len:items.len};header.items.flags|=.noslices
	for i,item in items {header.items[i]=objc_retain(item)}
	return object
}

fn array_bridge_contiguous(api ArrayBridgeApi,owner u64,element u64,guard u64) u64 {
	response:=api.access(0,element);metadata:=response.metadata;table:=api.lookup(api.sequence,metadata,0)
	assert table!=0
	mut receiver:=owner;api.retain(owner)
	return array_bridge_call(api,read64(table+56)&0x0000ffffffffffff,metadata,table,0,u64(unsafe {&receiver}),guard)
}

fn array_bridge_assert_string(api ArrayBridgeApi,value u64,expected string) {
	bytes:=api.bytes(read64(value),read64(value+8));assert read64(bytes+16)==u64(expected.len+1)
	assert C.memcmp(voidptr(bytes+32),expected.str,usize(expected.len))==0&&unsafe { *(&u8(bytes+32+u64(expected.len))) }==0
	api.release(bytes)
}
fn array_bridge_assert_url(api ArrayBridgeApi,value u64,expected string,guard u64) {
	url:=array_bridge_call(api,api.url_bridge,0,0,0,value,guard)
	text:=array_bridge_message(api,url,c'absoluteString',0,0)
	actual:=array_bridge_message(api,text,c'UTF8String',0,0)
	assert unsafe { (&char(actual)).vstring() }==expected
	api.drop(url)
}

fn array_bridge_check(api ArrayBridgeApi,owner u64,kind int,count int,items []u64,guard u64) {
	element:=array_bridge_element(api,kind);contiguous:=array_bridge_contiguous(api,owner,element,guard)
	assert read64(contiguous+16)==u64(count)
	stride:=read64((read64(element-8)&0x0000ffffffffffff)+72)
	for i in 0..count {
		if count>257&&i !in [0,1,17,48,49,count/2,count-1]! {continue}
		value:=contiguous+32+u64(i)*stride
		if kind==0 {array_bridge_assert_string(api,value,array_bridge_label(i))}
		else if kind==1 {path:=array_bridge_path(i);absolute:='file://'+path;array_bridge_assert_url(api,value,absolute,guard);unsafe {path.free();absolute.free()}}
		else {assert read64(value)==items[i]}
	}
	api.release(contiguous)
}

fn array_bridge_case(api ArrayBridgeApi,kind int,count int,mutable bool,guard u64) {
	pool:=api.push();mut items:=[]u64{len:count}
	for i in 0..count {
		if kind in [0,3]! {items[i]=array_bridge_string(api,array_bridge_label(i))}
		else if kind==1 {path:=array_bridge_path(i);items[i]=array_bridge_url(api,path,false);unsafe {path.free()}}
		else {items[i]=array_bridge_message(api,api.root,c'new',0,0)}
	}
	source:=array_bridge_source(api,items,mutable);element:=array_bridge_element(api,kind)
	first:=array_bridge_call(api,api.entry,source,element,0,guard,guard)
	second:=array_bridge_call(api,api.entry,source,element,0,guard,guard)
	if mutable {array_bridge_message(api,source,c'removeAllObjects',0,0)}
	api.drop(source);for item in items {api.drop(item)};api.pop(pool)
	pool2:=api.push()
	response:=api.access(0,element);metadata:=response.metadata;witness:=read64(metadata-8)&0x0000ffffffffffff
	mut receiver:=first;mut copy_value:=u64(0);mut moved:=u64(0)
	unsafe { ArrayBridgeCopy(voidptr(read64(witness+16)&0x0000ffffffffffff))(u64(&copy_value),u64(&receiver),metadata) }
	api.release(first)
	unsafe { ArrayBridgeCopy(voidptr(read64(witness+32)&0x0000ffffffffffff))(u64(&moved),u64(&copy_value),metadata) }
	array_bridge_check(api,moved,kind,count,items,guard);array_bridge_check(api,second,kind,count,items,guard)
	api.release(second)
	array_bridge_check(api,moved,kind,count,items,guard)
	unsafe { ArrayBridgeDestroy(voidptr(read64(witness+8)&0x0000ffffffffffff))(u64(&moved),metadata) }
	api.pop(pool2);unsafe {items.free()}
}

fn array_bridge_worker(api ArrayBridgeApi,source u64,kind int,items []u64,guard u64) {
	for _ in 0..16 {pool:=api.push();owner:=array_bridge_call(api,api.entry,source,array_bridge_element(api,kind),0,guard,guard);array_bridge_check(api,owner,kind,items.len,items,guard);api.release(owner);api.pop(pool)}
}
fn array_bridge_concurrent(api ArrayBridgeApi,guard u64) {
	for kind in [0,1]! {
		pool:=api.push()
		mut items:=[]u64{len:3}
		for i in 0..3 {if kind==0 {items[i]=array_bridge_string(api,array_bridge_label(i))}else{path:=array_bridge_path(i);items[i]=array_bridge_url(api,path,false);unsafe {path.free()}}}
		source:=array_bridge_source(api,items,false);mut workers:=[]thread{}
		for _ in 0..8 {workers<<spawn array_bridge_worker(api,source,kind,items,guard)}
		workers.wait();api.drop(source);for item in items {api.drop(item)};api.pop(pool);unsafe {items.free();workers.free()}
	}
}

fn array_bridge_url_paths(api ArrayBridgeApi,guard u64) {
	for row in [['/tmp/vinix file','game data','0','file:///tmp/vinix%20file/game%20data','file:///tmp/vinix%20file/']!,
		['/','Fortnite','1','file:///Fortnite/','file:///']!,
		['/tmp/base/','π 🎮','0','file:///tmp/base/%CF%80%20%F0%9F%8E%AE','file:///tmp/base/']!,
		['/tmp/a#b','x?y%z','1','file:///tmp/a%23b/x%3Fy%25z/','file:///tmp/a%23b/']!]! {
		pool:=api.push();url:=array_bridge_url(api,row[0],false);source:=array_bridge_source(api,[url],false);api.drop(url)
		owner:=array_bridge_call(api,api.entry,source,api.url_type,0,guard,guard);api.drop(source)
		contiguous:=array_bridge_contiguous(api,owner,api.url_type,guard);api.release(owner)
		string_object:=array_bridge_string(api,row[1]);mut string_words:=SwiftStringWords{second:0xe000000000000000}
		$if macos {if api.native {foundation:=C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation',2);type_call:=unsafe { ArrayBridgeString(C.dlsym(foundation,c'$sSS10FoundationE36_unconditionallyBridgeFromObjectiveCySSSo8NSStringCSgFZ')) };string_words=type_call(string_object)}}
		if !api.native {string_words=swift_foundation_unbridge(string_object)}
		api.drop(string_object);mut appended:=SwiftURLWords{};mut deleted:=SwiftURLWords{}
		array_bridge_call(api,api.append,string_words.first,string_words.second,if row[2]=='1'{u64(1)}else{u64(0)},contiguous+32,u64(unsafe {&appended}))
		api.release(string_words.second);api.release(contiguous)
		array_bridge_assert_url(api,u64(unsafe {&appended}),row[3],guard)
		array_bridge_call(api,api.delete,0,0,0,u64(unsafe {&appended}),u64(unsafe {&deleted}))
		unsafe { ArrayBridgeDestroy(voidptr(read64((read64(api.url_type-8)&0x0000ffffffffffff)+8)&0x0000ffffffffffff))(u64(&appended),api.url_type) }
		array_bridge_assert_url(api,u64(unsafe {&deleted}),row[4],guard)
		unsafe { ArrayBridgeDestroy(voidptr(read64((read64(api.url_type-8)&0x0000ffffffffffff)+8)&0x0000ffffffffffff))(u64(&deleted),api.url_type) }
		api.pop(pool)
	}
}

fn array_bridge_duplicate_and_http(api ArrayBridgeApi,guard u64) {
	pool:=api.push();object:=array_bridge_message(api,api.root,c'new',0,0)
	source:=array_bridge_source(api,[object,object,object],false)
	owner:=array_bridge_call(api,api.entry,source,api.object_type,0,guard,guard)
	api.drop(source);api.drop(object);api.pop(pool)
	pool2:=api.push();array_bridge_check(api,owner,2,3,[object,object,object],guard);api.release(owner);api.pop(pool2)
	pool3:=api.push();text:='https://example.test/fortnite?bridge=owned#result'
	url:=array_bridge_url(api,text,true);urls:=array_bridge_source(api,[url,url],false)
	values:=array_bridge_call(api,api.entry,urls,api.url_type,0,guard,guard);api.drop(urls);api.drop(url);api.pop(pool3)
	pool4:=api.push();contiguous:=array_bridge_contiguous(api,values,api.url_type,guard);api.release(values)
	assert read64(contiguous+16)==2
	for i in 0..2 {array_bridge_assert_url(api,contiguous+32+u64(i*16),text,guard)}
	if !api.native {if result:=swift_array_bridge_url_delete_checked(read64(contiguous+32)){swift_unknown_release(result.owner);assert false}}
	api.release(contiguous);api.pop(pool4)
}

fn array_bridge_write(api ArrayBridgeApi,guard u64) {
	root:=os.temp_dir()+'/vinix-array-unbridge-'+os.getpid().str();assert !os.exists(root);os.mkdir(root) or {panic(err)}
	defer {os.rmdir(root) or {panic(err)};unsafe {root.free()}}
	path:=root+'/payload';defer {unsafe {path.free()}}
	pool:=api.push();url:=ui_file_url(path);source:=array_bridge_source(api,[url],false);objc_release(url)
	owner:=array_bridge_call(api,api.entry,source,api.url_type,0,guard,guard);objc_release(source)
	contiguous:=array_bridge_contiguous(api,owner,api.url_type,guard);swift_bridge_release(owner)
	assert swift_data_write_checked(contiguous+32,0,0x6574696e74726f66,u64(8)<<48) or {panic(err)} == 0
	contents:=os.read_file(path) or {panic(err)};assert contents=='fortnite';unsafe {contents.free()}
	os.rm(path) or {panic(err)};swift_bridge_release(contiguous);api.pop(pool)
}

fn array_bridge_reject(source u64,element u64) {
	baseline:=ios_runtime.live;arrays:=ios_runtime.swift_arrays.len
	if owner:=swift_foundation_array_unbridge_checked(source,element){swift_bridge_release(owner);assert false,'unsupported NSArray accepted'}
	assert ios_runtime.live==baseline&&ios_runtime.swift_arrays.len==arrays
}
fn array_bridge_invalid(api ArrayBridgeApi,guard u64) {
	pool:=api.push();first:=owned_string('a valid long String before conversion failure');wrong:=objc_allocate(api.root)
	source:=array_bridge_source(api,[first,wrong],false)
	array_bridge_reject(source,api.string_type);array_bridge_reject(source,api.url_type);array_bridge_reject(source,api.objc_string_type)
	array_bridge_reject(source,guard);array_bridge_reject(source,swift_integer_metadata());array_bridge_reject(source,swift_any_full_metadata()+8)
	array_bridge_reject(guard,api.string_type);array_bridge_reject(wrong,api.object_type)
	mut header:=obj_header(source);header.cf_raw_values=true;array_bridge_reject(source,api.object_type);header.cf_raw_values=false
	old_count:=header.items.len;unsafe {header.items.len=4097};array_bridge_reject(source,api.object_type);unsafe {header.items.len=old_count}
	old:=header.items[1];header.items[1]=guard;array_bridge_reject(source,api.object_type);header.items[1]=0;array_bridge_reject(source,api.object_type);header.items[1]=old
	api.drop(source);api.drop(first);api.drop(wrong)
	url:=ui_file_url('/tmp/valid-before-error');bad:=owned_string('wrong URL element')
	urls:=array_bridge_source(api,[url,bad],false);array_bridge_reject(urls,api.url_type);api.drop(urls);api.drop(bad)
	for component in ['', '.', '..', 'a/b', 'a\\b', 'a\x00b']! {
		text:=owned_string(component);words:=swift_foundation_unbridge(text);objc_release(text)
		if result:=swift_array_bridge_url_append_checked(words.first,words.second,0,url){swift_unknown_release(result.owner);assert false}
		swift_bridge_release(words.second)
	}
	objc_release(url)
	api.pop(pool)
}

fn test_swift_array_unbridge() {
	$if !arm64 {return}
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe {nil},page*2,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=u64(-1)
	assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_WRITE)==0
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0003f0,0xaa0703f3,0xaa0503f4,0xaa0603e8,
		0xaa0103e0,0xaa0203e1,0xaa0303e2,0xaa0403e3,0xd2800015,0xd63f0200,0xa9000660,0xa9015674,
		0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]! {write32(code+u64(i*4),op)}
	C.__builtin___clear_cache(voidptr(code),voidptr(code+76));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0
	guard:=code+u64(page)
	$if macos {api:=array_bridge_api(true,code);empty:=array_bridge_call(api,api.entry,0,guard,0,guard,guard);api.release(empty)
		for mutable in [false,true]!{for kind in 0..4{for count in [0,1,3,49,257,4096]!{array_bridge_case(api,kind,count,mutable,guard)}}}
		array_bridge_concurrent(api,guard);array_bridge_url_paths(api,guard);array_bridge_duplicate_and_http(api,guard)
		println('IOS-SWIFT-ARRAY-UNBRIDGE-NATIVE: NSArray to String/URL/NSObject/NSString arrays, nil metadata guard, ordered snapshots, source/pool teardown, Array copy/take/destruction, contiguous Sequence consumption, concurrent bridges and file URL append/delete/roundtrip measured')}
	for _ in 0..2 {
		objc_start();api:=array_bridge_api(false,code);baseline:=ios_runtime.live
		empty:=array_bridge_call(api,api.entry,0,guard,0,guard,guard);assert empty==swift_array_empty();api.release(empty)
		for mutable in [false,true]!{for kind in 0..4{for count in [0,1,3,49,257,4096]!{array_bridge_case(api,kind,count,mutable,guard)}}}
		array_bridge_concurrent(api,guard);array_bridge_url_paths(api,guard);array_bridge_duplicate_and_http(api,guard);array_bridge_write(api,guard);array_bridge_invalid(api,guard)
		assert ios_runtime.live==baseline,'live=${ios_runtime.live}, baseline=${baseline}'
		assert ios_runtime.swift_arrays.len==0&&ios_runtime.swift_heap.len==0
		objc_stop();assert ios_runtime.live==0&&ios_runtime.swift_foundation_arena==0
	}
	assert C.munmap(voidptr(code),page*2)==0
	println('IOS-SWIFT-ARRAY-UNBRIDGE: bounded ordered String/URL/NSObject-derived arrays, nil metadata/Self/x8 guards, source/result ownership, mutable snapshots, Array/Sequence compatibility, private NSURL-backed URL roundtrip and bounded file path operations, concurrent readers, invalid provenance/type/members and partial cleanup, two drained runtimes; Any/numeric/custom conversions, arbitrary URL protocol slots and general URL path parsing remain unsupported')
}
