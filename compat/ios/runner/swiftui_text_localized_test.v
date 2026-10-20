// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.dlclose(voidptr)i32
type TextLocalizedProbe = fn(&u64,u64,&u64)
type TextLocalizedCString = fn(&u8)SwiftStringWords
type TextLocalizedKeep = fn(u64)u64
type TextLocalizedDrop = fn(u64)
type TextLocalizedDestroy = fn(u64,u64)
type TextLocalizedCopy = fn(u64,u64,u64)u64
struct TextLocalizedName { data &char length usize }
type TextLocalizedTypeName = fn(u64,bool)TextLocalizedName

fn text_localized_code(code u64) {
	// x0-x7 and two stack words carry the arguments; x8 is unused result
	// storage. Preserve the C caller's x19-x22 and probe Swift x20/x21.
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0003f1,0xaa0103f0,0xaa0203f3,0xd10043ff,
		0xa9400620,0xa9410e22,0xa9421624,0xa9431e26,0xa9442a29,0xa9002be9,0xf9402a28,0xf9402e34,0xf9403235,
		0xd63f0200,0xa9000660,0xa9010e62,0xa9025674,0x910043ff,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]! { write32(code+u64(i*4),op) }
	C.__builtin___clear_cache(voidptr(code),voidptr(code+100))
}

fn text_localized_native(probe TextLocalizedProbe,guard u64) {
	ui:=C.dlopen(c'/System/Library/Frameworks/SwiftUI.framework/SwiftUI',2);core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);assert ui!=unsafe{nil}&&core!=unsafe{nil}
	entry:=u64(C.dlsym(ui,c'$s7SwiftUI4TextV_9tableName6bundle7commentAcA18LocalizedStringKeyV_SSSgSo8NSBundleCSgs06StaticI0VSgtcfC'))
	key:=u64(C.dlsym(ui,c'$s7SwiftUI18LocalizedStringKeyV13stringLiteralACSS_tcfC'));metadata:=u64(C.dlsym(ui,c'$s7SwiftUI4TextVN'));empty:=u64(C.dlsym(core,c'_swiftEmptyArrayStorage'));assert entry!=0&&key!=0&&metadata!=0&&empty!=0
	native_cstring:=unsafe{TextLocalizedCString(C.dlsym(core,c'$sSS7cStringSSSPys4Int8VG_tcfC'))};keep:=unsafe{TextLocalizedKeep(C.dlsym(core,c'swift_bridgeObjectRetain'))};drop:=unsafe{TextLocalizedDrop(C.dlsym(core,c'swift_bridgeObjectRelease'))};name:=unsafe{TextLocalizedTypeName(C.dlsym(core,c'swift_getTypeName'))}
	witnesses:=read64(metadata-8);destroy:=unsafe{TextLocalizedDestroy(voidptr(read64(witnesses+8)))};witness_copy:=unsafe{TextLocalizedCopy(voidptr(read64(witnesses+16)))}
	for text in ['','Fortnite','owned localized Text key with é 🎮','%@ %d %%']! { for table_case in 0..3 { for comment in [false,true]! {
		words:=native_cstring(text.str);mut table:=SwiftStringWords{};if table_case!=0{table_text:=if table_case==1{''}else{'owned localization table name'};table=native_cstring(table_text.str)}
		heap:=words.second>>63==0;key_owner:=words.second&swift_address_mask;table_owner:=table.second&swift_address_mask
		keep(words.second);if table_case!=0{keep(table.second)}
		mut input:=[words.first,words.second,u64(0),0,table.first,table.second,u64(0),if comment{u64(c'localization note')}else{u64(0)},if comment{u64(17)}else{u64(0)},if comment{u64(2)}else{u64(1)},guard,0x5020,0x5021]!
		mut k:=[u64(0xcafe),0,0,0,0,0,0,0xbeef]!;probe(unsafe{&input[0]},key,unsafe{&k[1]})
		assert k==[u64(0xcafe),words.first,words.second,u64(0),empty,u64(0x5020),u64(0x5021),0xbeef]!
		for i in 0..4{input[i]=k[i+1]};saved:=input
		mut result:=[u64(0xcafe),0,0,0,0,0,0,0xbeef]!;probe(unsafe{&input[0]},entry,unsafe{&result[1]})
		assert input==saved&&result[0]==0xcafe&&result[7]==0xbeef&&result[1]!=0&&result[2]==0&&result[3]&255==1&&result[4]==empty&&result[5]==0x5020&&result[6]==0x5021
		owner:=result[1];provider:=read64(owner);n:=name(provider,true);assert n.length>0&&n.length<1024
		provider_name:=unsafe{tos(n.data,int(n.length))};assert provider_name.starts_with('SwiftUI.')&&provider_name.ends_with('.LocalizedTextStorage')&&read32(provider+48)==72
		assert read64(owner+16)==words.first&&read64(owner+24)==words.second&&unsafe{*(&u8(owner+32))}==0&&read64(owner+40)==empty&&read64(owner+48)==table.first&&read64(owner+56)==table.second&&read64(owner+64)==0
		assert read64(owner+8)==3;if heap{assert read64(key_owner+8)==0x200000003};if table_case==2{assert read64(table_owner+8)==0x200000003}
		mut duplicate:=[4]u64{};assert witness_copy(u64(unsafe{&duplicate[0]}),u64(unsafe{&result[1]}),metadata)==u64(unsafe{&duplicate[0]})&&duplicate[0]==owner&&duplicate[1]==0&&u8(duplicate[2])==1&&duplicate[3]==empty&&read64(owner+8)==0x200000003
		destroy(u64(unsafe{&result[1]}),metadata);assert read64(owner+8)==3;if heap{assert read64(key_owner+8)==0x200000003}
		destroy(u64(unsafe{&duplicate[0]}),metadata);if heap{assert read64(key_owner+8)==3};if table_case==2{assert read64(table_owner+8)==3};drop(words.second);if table_case!=0{drop(table.second)}
		println('NATIVE-SWIFTUI-TEXT-LOCALIZED case='+text+' table='+table_case.str()+' comment='+comment.str()+' provider='+provider_name+' size=72 storage=object modifiers=empty consuming-key-table=true balanced-copy-destroy=true')
	}}}
	assert C.dlclose(core)==0&&C.dlclose(ui)==0
	println('NATIVE-SWIFTUI-TEXT-LOCALIZED: 24 literal key/table/comment cases, nil bundle, x0-x3 owned result, consumed key/table owners, shared provider copies, balanced native destruction and preserved x20/x21; no localization, rendering or application code executed')
}

fn text_localized_resolve()u64 {
	return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI','_$s7SwiftUI4TextV_9tableName6bundle7commentAcA18LocalizedStringKeyV_SSSgSo8NSBundleCSgs06StaticI0VSgtcfC') or {panic(err)}
}

fn text_localized_reject(probe TextLocalizedProbe,entry u64,guard u64,result u64,self_value u64) {
	mut fds:=[2]i32{};assert C.pipe(unsafe{&fds[0]})==0;pid:=C.ios_fork();assert pid>=0
	if pid==0 {
		C.close(fds[0]);assert C.dup2(fds[1],2)==2;C.close(fds[1])
		input:=[guard,guard,guard,guard,guard,guard,guard,guard,guard,guard,result,self_value,guard]!
		mut output:=[6]u64{};probe(unsafe{&input[0]},entry,unsafe{&output[0]});C._exit(0)
	}
	C.close(fds[1]);mut bytes:=[16384]u8{};mut length:=0
	for{assert length<bytes.len;count:=C.read(fds[0],unsafe{&bytes[length]},usize(bytes.len-length));if count==0{break};if count<0&&unsafe{*C.ios_errno_address()}==C.EINTR{continue};assert count>0;length+=int(count)}
	C.close(fds[0]);mut status:=i32(0);assert C.ios_waitpid(pid,&status,0)==pid&&status==256
	output:=unsafe{tos(&bytes[0],length)};assert output.contains('iOS: SwiftUI Text localized storage construction is not implemented')
	for bad in ['runtime error:','AddressSanitizer','Segmentation fault','SIGSEGV','SIGBUS']!{assert !output.contains(bad),output}
}

fn text_localized_reader()u64 {entry:=text_localized_resolve();for _ in 0..1024{assert text_localized_resolve()==entry};return entry}
__global text_localized_callback_calls=0
fn text_localized_callback(object u64,selector &char) {assert ios_runtime.swift_concurrency_retired&&text_localized_resolve()==u64(unsafe{voidptr(swiftui_text_localized_unavailable)});text_localized_callback_calls++}

fn test_swiftui_text_localized() {
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));shared_base:=u64(C.mmap(unsafe{nil},page*3,C.PROT_NONE,C.MAP_SHARED|C.MAP_ANONYMOUS,-1,0));assert code!=u64(-1)&&guard!=u64(-1)&&shared_base!=u64(-1)
	shared:=shared_base+u64(page);text_localized_code(code);assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0;probe:=unsafe{TextLocalizedProbe(voidptr(code))}
	$if macos{text_localized_native(probe,guard)}
	entry:=text_localized_resolve()
	for symbol in ['_$s7SwiftUI4TextV_9tableName6bundle7commentAcA18LocalizedStringKeyV_SSSgSo8NSBundleCSgs06StaticI0VSgtcfCExtra','_$s11SwiftUICore4TextV_9tableName6bundle7commentAcA18LocalizedStringKeyV_SSSgSo8NSBundleCSgs06StaticI0VSgtcfC','_$s7SwiftUI4TextV8verbatimACSS_tcfC']!{if _:=swiftui_text_localized_symbol(symbol){assert false}}
	for _ in 0..2 {
		objc_start();mut workers:=[]thread u64{};for _ in 0..8{workers<<spawn text_localized_reader()};for worker in workers{assert worker.wait()==entry};unsafe{workers.free()}
		for library in ['/usr/lib/swift/libswiftCore.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']!{if _:=runtime_symbol(library,'_$s7SwiftUI4TextV_9tableName6bundle7commentAcA18LocalizedStringKeyV_SSSgSo8NSBundleCSgs06StaticI0VSgtcfC'){assert false}}
		for self_value in [u64(0),guard,~u64(0)]! {
			text_localized_reject(probe,entry,guard,guard,self_value);assert C.mprotect(voidptr(shared),page,C.PROT_READ|C.PROT_WRITE)==0;C.memset(voidptr(shared),0xa5,page)
			for writable in [true,false]! {assert C.mprotect(voidptr(shared),page,C.PROT_READ|if writable{C.PROT_WRITE}else{0})==0;for result in [shared,shared+u64(page)-128]! {text_localized_reject(probe,entry,guard,result,self_value);for i in u64(0)..u64(page){assert unsafe{*(&u8(shared+i))}==0xa5}}}
		}
		assert ios_runtime.swift_heap.len==0&&ios_runtime.swift_buffers.len==0&&ios_runtime.swift_arrays.len==0&&ios_runtime.live==0
		cls:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixTextLocalizedCallback',0);assert cls!=0&&objc_add_method(cls,u64(c'dealloc'),u64(unsafe{voidptr(text_localized_callback)}),c'v16@0:8');objc_register_class(cls);objc_autorelease(objc_new(cls));before:=text_localized_callback_calls
		ios_runtime.swift_concurrency_retired=true;objc_stop();assert text_localized_callback_calls==before+1&&ios_runtime.live==0&&text_localized_resolve()==entry;text_localized_reject(probe,entry,guard,guard,guard)
	}
	assert C.munmap(voidptr(code),page)==0&&C.munmap(voidptr(guard),page)==0&&C.munmap(voidptr(shared_base),page*3)==0
	println('IOS-SWIFTUI-TEXT-LOCALIZED: diagnostic binding only, eight readers and 16384 concurrent resolutions, 32 child calls exit 1 with the localized-storage diagnostic, protected key/table/bundle/comment/stack/self/x8, unchanged shared read-only/writable result pages at both protected boundaries, exact framework routing, callbacks and two drained runtime lifetimes; localized provider construction, localization and rendering remain unsupported')
}
