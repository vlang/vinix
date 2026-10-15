// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os
#include <dlfcn.h>
fn C.dlopen(&char,i32) voidptr
fn C.dlsym(voidptr,&char) voidptr
type DictionaryProbe = fn (u64,u64,u64,u64,u64,u64,u64,&u64)
type DictionaryAllocate = fn (i64,u64,u64,u64) u64
type DictionarySend = fn (u64,u64,u64) u64
type DictionarySelector = fn (&char) u64
type DictionaryCString = fn (&char) SwiftStringWords
type DictionaryDrop = fn (u64)
type DictionaryPool = fn () u64
type DictionaryCopy = fn (u64,u64,u64) u64
type DictionaryDestroy = fn (u64,u64)
type DictionaryObjMetadata = fn (u64) u64

struct DictionaryApi {
	native bool
	bridge u64
	empty u64
	string_type u64
	int_type u64
	any_type u64
	object_type u64
	hashable u64
	object_class u64
	dictionary_class u64
	probe DictionaryProbe
	allocate DictionaryAllocate
	text DictionaryCString
	send DictionarySend
	selector DictionarySelector
	drop DictionaryDrop
	release DictionaryDrop
	push DictionaryPool
	pop DictionaryDrop
}

fn dictionary_text(text &char) SwiftStringWords {
	scratch := u64(C.__builtin_alloca(16))
	unsafe { *(&SwiftStringWords(scratch)) = swift_interpolation_init(128,0) }
	swift_string_append_bytes(scratch,u64(text),u64(unsafe { text.vstring() }.len))
	return unsafe { *(&SwiftStringWords(scratch)) }
}

fn dictionary_api(native bool,code u64) DictionaryApi {
	symbol := '_$sSD10FoundationE19_bridgeToObjectiveCSo12NSDictionaryCyF'
	mut entry := u64(0)
	for library in ['/System/Library/Frameworks/Foundation.framework/Foundation','/usr/lib/swift/libswiftFoundation.dylib']! {
		mut address := u64(0)
		$if macos { if native { address=u64(C.dlsym(C.dlopen(library.str,2),symbol[1..].str)) } }
		if !native { address=runtime_symbol(library,symbol) or {panic(err)} }
		assert address!=0&&(entry==0||entry==address);entry=address
	}
	$if macos { if native {
		core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);obj:=C.dlopen(c'/usr/lib/libobjc.A.dylib',2)
		cls:=unsafe { DictionarySelector(C.dlsym(obj,c'objc_getClass')) }
		object_class:=cls(c'NSObject')
		return DictionaryApi{native:true,bridge:entry,empty:u64(C.dlsym(core,c'_swiftEmptyDictionarySingleton')),
			string_type:u64(C.dlsym(core,c'$sSSN')),int_type:u64(C.dlsym(core,c'$sSiN')),any_type:u64(C.dlsym(core,c'$sypN'))+8,
			object_type:unsafe { DictionaryObjMetadata(C.dlsym(core,c'swift_getObjCClassMetadata'))(object_class) },hashable:u64(C.dlsym(core,c'$sSSSHsWP')),
			object_class:object_class,dictionary_class:cls(c'NSDictionary'),probe:unsafe { DictionaryProbe(voidptr(code)) },
			allocate:unsafe { DictionaryAllocate(C.dlsym(core,c'$sSD15minimumCapacitySDyxq_GSi_tcfC')) },
			text:unsafe { DictionaryCString(C.dlsym(core,c'$sSS7cStringSSSPys4Int8VG_tcfC')) },
			send:unsafe { DictionarySend(C.dlsym(obj,c'objc_msgSend')) },selector:unsafe { DictionarySelector(C.dlsym(obj,c'sel_registerName')) },
			drop:unsafe { DictionaryDrop(C.dlsym(obj,c'objc_release')) },release:unsafe { DictionaryDrop(C.dlsym(core,c'swift_bridgeObjectRelease')) },
			push:unsafe { DictionaryPool(C.dlsym(obj,c'objc_autoreleasePoolPush')) },pop:unsafe { DictionaryDrop(C.dlsym(obj,c'objc_autoreleasePoolPop')) }}
	} }
	return DictionaryApi{bridge:entry,empty:runtime_symbol('/usr/lib/swift/libswiftCore.dylib','__swiftEmptyDictionarySingleton') or {panic(err)},
		string_type:swift_string_metadata(),int_type:swift_integer_metadata(),any_type:swift_any_full_metadata()+8,
		object_type:swift_objc_metadata(ios_runtime.names['NSObject']),hashable:code+usize(C.getpagesize()),
		object_class:ios_runtime.names['NSObject'],dictionary_class:ios_runtime.names['NSDictionary'],probe:unsafe { DictionaryProbe(voidptr(code)) },
		allocate:dictionary_unused_allocate,text:dictionary_text,send:unsafe { DictionarySend(voidptr(C.ios_objc_msgsend)) },selector:objc_selector,
		drop:objc_release,release:swift_bridge_release,push:objc_pool_push,pop:objc_pool_pop}
}

fn dictionary_unused_allocate(_capacity i64,_key u64,_value u64,_hashable u64) u64 { panic('private test storage requires its own metadata') }

fn dictionary_call(api DictionaryApi,entry u64,a u64,b u64,c u64,d u64,guard u64,self u64) u64 {
	mut output := [u64(0xcafe),0,0,0,0,0xbeef]!
	api.probe(entry,a,b,c,d,self,guard,unsafe { &output[1] })
	assert output[0]==0xcafe&&output[3]==self&&output[4]==0x5021&&output[5]==0xbeef
	return output[1]
}

fn dictionary_type(api DictionaryApi,mode int) u64 {
	return match mode { 0 {api.string_type} 1 {api.int_type} 2 {api.any_type} else {api.object_type} }
}

fn dictionary_test_destroy(owner u64) {
	metadata:=read64(owner);key:=read64(metadata+176);value:=read64(metadata+184)
	stride:=read64(read64(value-8)+72);buckets:=u64(1)<<unsafe { *(&u8(owner+32)) }
	for bucket in u64(0)..buckets { if read64(owner+64+bucket/64*8)&(u64(1)<<(bucket&63))!=0 {
		unsafe { DictionaryDestroy(voidptr(read64(read64(key-8)+8)))(read64(owner+48)+bucket*16,key) }
		unsafe { DictionaryDestroy(voidptr(read64(read64(value-8)+8)))(read64(owner+56)+bucket*stride,value) }
	} }
	C.ios_objc_initialize_lock();storage:=ios_runtime.swift_heap[owner] or {panic('missing Dictionary test owner')};C.ios_objc_initialize_unlock()
	swift_heap_deallocate(owner,storage.size,storage.mask)
}

fn dictionary_test_metadata(api DictionaryApi,value u64,code u64,index int) u64 {
	data:=code+u64(C.getpagesize())+u64(index)*768
	metadata:=data+24;descriptor:=data+400
	unsafe {
		*(&u64(metadata-16))=code+96;*(&u64(metadata))=metadata+256
		*(&u64(metadata+32))=2;*(&u64(metadata+64))=descriptor
		*(&u64(metadata+176))=api.string_type;*(&u64(metadata+184))=value;*(&u64(metadata+192))=api.hashable
	}
	write32(metadata+40,2);write32(metadata+56,232);write32(metadata+60,24)
	write32(descriptor,0xd0);swift_protocol_relative(descriptor+4,data+512);swift_protocol_relative(descriptor+8,data+464)
	write32(descriptor+28,26);write32(descriptor+32,4)
	swift_protocol_relative(data+520,data+544)
	C.memcpy(voidptr(data+464),c'_DictionaryStorage',19);C.memcpy(voidptr(data+544),c'Swift',6)
	return metadata
}

fn dictionary_storage(api DictionaryApi,capacity int,value u64,metadata u64) u64 {
	if api.native { return api.allocate(capacity,api.string_type,value,api.hashable) }
	if capacity==0 { return api.empty }
	mut scale:=u8(1);mut buckets:=u64(2)
	for u64(capacity)>buckets-buckets/4-if buckets==2 {u64(1)}else{u64(0)} {scale++;buckets*=2}
	stride:=read64(read64(value-8)+72);keys:=64+(buckets+63)/64*8;values:=keys+buckets*16;size:=values+buckets*stride
	owner:=swift_heap_allocate(metadata,size,7);C.memset(voidptr(owner+16),0,usize(size-16))
	unsafe { *(&u64(owner+24))=buckets-buckets/4-if buckets==2 {u64(1)}else{u64(0)};*(&u8(owner+32))=scale
		*(&u64(owner+40))=owner;*(&u64(owner+48))=owner+keys;*(&u64(owner+56))=owner+values }
	if buckets<64 {unsafe { *(&u64(owner+64))=~((u64(1)<<buckets)-1) }}
	return owner
}

fn dictionary_key(index int) string { return 'key-${index}-a sufficiently long String key' }
fn dictionary_value(index int) string { return 'value-${index}-an independently owned String payload' }

fn dictionary_fill(api DictionaryApi,owner u64,count int,mode int) []u64 {
	mut objects:=[]u64{len:count}
	if count==0{return objects}
	value_type:=dictionary_type(api,mode);stride:=read64((read64(value_type-8)&0x0000ffffffffffff)+72)
	buckets:=u64(1)<<unsafe { *(&u8(owner+32)) }
	for i in 0..count {
		key_label:=dictionary_key(i);key:=api.text(unsafe { &char(key_label.str) });unsafe {key_label.free()};key_address:=u64(unsafe { &key })
		mut bucket:=(u64(i)*17+3)&(buckets-1)
		if api.native { bucket=dictionary_call(api,read64(api.hashable+32)&0x0000ffffffffffff,read64(owner+40),api.string_type,api.hashable,0,0,key_address)&(buckets-1) }
		for read64(owner+64+bucket/64*8)&(u64(1)<<(bucket&63))!=0 {bucket=(bucket+1)&(buckets-1)}
		key_target:=read64(owner+48)+bucket*16;target:=read64(owner+56)+bucket*stride
		unsafe { *(&SwiftStringWords(key_target))=key }
		kind:=if mode==2 {i%3}else{mode}
		if kind==0 { label:=dictionary_value(i);words:=api.text(unsafe { &char(label.str) });unsafe { label.free();*(&SwiftStringWords(target))=words } }
		else if kind==1 { unsafe { *(&i64(target))=-12345-i64(i) } }
		else { object:=api.send(api.object_class,api.selector(c'new'),0);objects[i]=object;unsafe { *(&u64(target))=object } }
		if mode==2 { unsafe { *(&u64(target+24))=if kind==0 {api.string_type}else if kind==1 {api.int_type}else{api.object_type} } }
		unsafe { *(&u64(owner+64+bucket/64*8))|=u64(1)<<(bucket&63);*(&u64(owner+16))+=1 }
	}
	return objects
}

fn dictionary_check(api DictionaryApi,object u64,count int,mode int,objects []u64) {
	assert api.send(object,api.selector(c'isKindOfClass:'),api.dictionary_class)==1
	assert api.send(object,api.selector(c'count'),0)==u64(count)
	for i in 0..count {
		if count>257 && i !in [0,1,17,48,49,count/2,count-1]! {continue}
		key_words:=api.text(unsafe { &char(dictionary_key(i).str) })
		mut key:=u64(0)
		$if macos { if api.native { library:=C.dlopen(c'/System/Library/Frameworks/Foundation.framework/Foundation',2)
			key=dictionary_call(api,u64(C.dlsym(library,c'$sSS10FoundationE19_bridgeToObjectiveCSo8NSStringCyF')),key_words.first,key_words.second,0,0,0,0)
		} }
		if !api.native {key=swift_foundation_bridge(key_words.first,key_words.second)}
		api.release(key_words.second)
		value:=api.send(object,api.selector(c'objectForKey:'),key);assert value!=0
		kind:=if mode==2 {i%3}else{mode}
		if kind==0 { text:=api.send(value,api.selector(c'UTF8String'),0);assert unsafe { (&char(text)).vstring() }==dictionary_value(i) }
		else if kind==1 { assert i64(api.send(value,api.selector(c'integerValue'),0))==-12345-i64(i) }
		else {assert value==objects[i]}
		api.drop(key)
	}
}

fn dictionary_case(api DictionaryApi,code u64,count int,mode int) {
	metadata:=code+u64(C.getpagesize())+u64(mode)*768+24
	value:=dictionary_type(api,mode);pool:=api.push()
	owner:=dictionary_storage(api,count,value,metadata);mut objects:=dictionary_fill(api,owner,count,mode)
	guard:=code+u64(C.getpagesize())*2
	first:=dictionary_call(api,api.bridge,owner,api.string_type,value,api.hashable,guard,guard)
	second:=dictionary_call(api,api.bridge,owner,api.string_type,value,api.hashable,guard,guard)
	api.release(owner);api.pop(pool)
	pool2:=api.push()
	dictionary_check(api,first,count,mode,objects);api.drop(first)
	dictionary_check(api,second,count,mode,objects);api.drop(second);api.pop(pool2)
	unsafe {objects.free()}
}

fn dictionary_suite(api DictionaryApi,code u64) {
	assert read64(api.empty+8)==0x80000004ffffffff&&read64(api.empty+16)==0&&read64(api.empty+24)==0
	assert read64(api.empty+48)==1&&read64(api.empty+56)==1&&read64(api.empty+64)==~u64(1)
	for count in [0,1,3,48,49,257]! {for mode in 0..4 {dictionary_case(api,code,count,mode)}}
	dictionary_case(api,code,4096,1)
	pool:=api.push();cocoa:=api.send(api.dictionary_class,api.selector(c'new'),0)
	guard:=code+u64(C.getpagesize())*2
	for tag in [u64(1),3,5,7,0x4000000000000000,0x4000000000000001]! {
		result:=dictionary_call(api,api.bridge,cocoa|tag,guard,guard,guard,guard,guard)
		assert result==cocoa;api.drop(result)
	}
	api.drop(cocoa);api.pop(pool)
}

fn dictionary_bridge_worker(api DictionaryApi,owner u64,objects []u64) {
	for _ in 0..16 {
		pool:=api.push()
		result:=dictionary_call(api,api.bridge,owner,api.string_type,api.any_type,api.hashable,0,0)
		dictionary_check(api,result,3,2,objects);api.drop(result);api.pop(pool)
	}
}

fn dictionary_concurrent(api DictionaryApi,code u64) {
	owner:=dictionary_storage(api,3,api.any_type,code+u64(C.getpagesize())+2*768+24)
	mut objects:=dictionary_fill(api,owner,3,2)
	mut workers:=[]thread{}
	for _ in 0..8 {workers<<spawn dictionary_bridge_worker(api,owner,objects)}
	workers.wait();api.release(owner);unsafe {objects.free()}
}

fn dictionary_reject(owner u64,api DictionaryApi,value u64) {
	baseline:=ios_runtime.live
	if result:=swift_foundation_dictionary_bridge_checked(owner,api.string_type,value,api.hashable) {
		objc_release(result);assert false,'unsupported Dictionary was accepted'
	}
	assert ios_runtime.live==baseline
}

fn dictionary_invalid(api DictionaryApi,code u64) {
	guard:=code+u64(C.getpagesize())*2
	owner:=dictionary_storage(api,3,api.string_type,code+u64(C.getpagesize())+24)
	mut objects:=dictionary_fill(api,owner,3,0)
	dictionary_reject(guard,api,api.string_type)
	dictionary_reject(owner,api,api.int_type)
	for offset in [u64(16),24,48,56]! {
		old:=read64(owner+offset)
		unsafe { *(&u64(owner+offset))=if offset==16 {u64(4)}else{u64(0)} }
		dictionary_reject(owner,api,api.string_type)
		unsafe { *(&u64(owner+offset))=old }
	}
	old_scale:=unsafe { *(&u8(owner+32)) }
	for scale in [u8(0),15,255]! {unsafe { *(&u8(owner+32))=scale };dictionary_reject(owner,api,api.string_type)}
	unsafe { *(&u8(owner+32))=old_scale }
	buckets:=u64(1)<<old_scale
	mut first:=u64(-1);mut last:=u64(0);mut hole:=u64(0)
	for bucket in u64(0)..buckets {
		if read64(owner+64+bucket/64*8)&(u64(1)<<(bucket&63))!=0 {if first==u64(-1){first=bucket};last=bucket}else{hole=bucket}
	}
	bitmap:=owner+64+hole/64*8;bits:=read64(bitmap)
	unsafe { *(&u64(bitmap))|=u64(1)<<(hole&63) };dictionary_reject(owner,api,api.string_type);unsafe { *(&u64(bitmap))=bits }
	value:=read64(owner+56)+last*16;original:=unsafe { *(&SwiftStringWords(value)) }
	unsafe { *(&SwiftStringWords(value))=SwiftStringWords{first:32,second:guard} }
	dictionary_reject(owner,api,api.string_type) // Retires a partially converted snapshot.
	unsafe { *(&SwiftStringWords(value))=original }
	key:=read64(owner+48)+last*16;original_key:=unsafe { *(&SwiftStringWords(key)) }
	unsafe { *(&SwiftStringWords(key))=*(&SwiftStringWords(read64(owner+48)+first*16)) }
	dictionary_reject(owner,api,api.string_type)
	unsafe { *(&SwiftStringWords(key))=original_key }
	api.release(owner);unsafe {objects.free()}
	wrong:=objc_allocate(ios_runtime.names['NSObject']);dictionary_reject(wrong|1,api,api.string_type);objc_release(wrong)
	cocoa:=objc_allocate(api.dictionary_class)
	for tag in [u64(1),3,5,7,0x4000000000000001]! {
		word:=cocoa|tag
		assert swift_bridge_retain(word)==word&&obj_header(cocoa).refs==2
		swift_bridge_retain(word);swift_bridge_release_n(word,2);assert obj_header(cocoa).refs==1
	}
	swift_bridge_release_n(guard|1,0)
	objc_release(cocoa)
}

fn test_swift_dictionary_bridge() {
	$if !arm64 { return }
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe {nil},page*3,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=u64(-1)
	assert C.mprotect(voidptr(code),page*2,C.PROT_READ|C.PROT_WRITE)==0
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0003f0,0xaa0703f3,0xaa0503f4,0xaa0603e8,
		0xaa0103e0,0xaa0203e1,0xaa0303e2,0xaa0403e3,0xd28a0435,0xd63f0200,0xa9000660,0xa9015674,
		0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]! {write32(code+u64(i*4),op)}
	write32(code+96,0xaa1403e0);write32(code+100,0x58000070);write32(code+104,0xd61f0200)
	unsafe { *(&u64(code+112))=u64(voidptr(dictionary_test_destroy)) }
	C.__builtin___clear_cache(voidptr(code),voidptr(code+120));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0
	$if macos {api:=dictionary_api(true,code);dictionary_suite(api,code);dictionary_concurrent(api,code);println('IOS-SWIFT-DICTIONARY-BRIDGE-NATIVE: native String-key storage and String/Int/Any/NSObject values, owned NSDictionary results, source/pool teardown, Cocoa identity/tagged fast path and concurrent borrowed-source bridges measured')}
	for _ in 0..2 {
		objc_start();api:=dictionary_api(false,code)
		framework_empty_dictionary();baseline:=ios_runtime.live
		assert swift_bridge_retain(api.empty)==api.empty&&!swift_is_unique_native(api.empty);swift_bridge_release(api.empty)
		assert C.mprotect(voidptr(code+u64(page)),page,C.PROT_READ|C.PROT_WRITE)==0
		C.memset(voidptr(code+u64(page)),0,page)
		for mode in 0..4 {dictionary_test_metadata(api,dictionary_type(api,mode),code,mode)}
		assert C.mprotect(voidptr(code+u64(page)),page,C.PROT_READ)==0
		dictionary_suite(api,code)
		dictionary_concurrent(api,code)
		dictionary_invalid(api,code)
		assert ios_runtime.live==baseline&&ios_runtime.swift_heap.len==0&&ios_runtime.swift_arrays.len==0
		objc_stop();assert ios_runtime.live==0&&ios_runtime.swift_foundation_arena==0
	}
	assert C.munmap(voidptr(code),page*3)==0
	println('IOS-SWIFT-DICTIONARY-BRIDGE: bounded native String-key dictionaries and String/Int/inline Any/NSObject values, owned immutable snapshots, independent source/result lifetimes, Cocoa identity/tagged ARC and untouched generic guards, concurrent borrowed-source bridges, invalid provenance/metadata/fields/occupancy, duplicate keys and partial conversion cleanup, two drained runtimes; Dictionary construction/copy/resize, other key types and boxed/nested Any remain unsupported')
}
