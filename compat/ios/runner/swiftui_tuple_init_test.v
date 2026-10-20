// SPDX-License-Identifier: GPL-2.0-or-later
module main
import os
import strconv
#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.dlclose(voidptr)i32
fn C.mincore(voidptr,usize,&u8)i32
$if macos {
	#include <mach/mach.h>
	fn C.mach_task_self()u32
	fn C.vm_region_64(u32,&u64,&u64,i32,&i32,&u32,&u32)i32
	fn C.mach_port_deallocate(u32,u32)i32
}
const tuple_init_symbol='_$s7SwiftUI9TupleViewVyACyxGxcfC'
type TupleInitProbe=fn(&u64,u64,&u64)
struct TupleInitResponse { metadata u64 state u64 }
struct TupleInitWords { first u64 second u64 }
type TupleInitGeneric=fn(u64,u64)TupleInitResponse
type TupleInitLookup=fn(&u8,usize,u64,u64)u64
type TupleInitCString=fn(&u8)TupleInitWords
type TupleInitCount=fn(u64)u64
type TupleInitKeep=fn(u64)u64
type TupleInitDrop=fn(u64)
type TupleInitCopy=fn(u64,u64,u64)u64
type TupleInitDestroy=fn(u64,u64)
fn tuple_init_call(probe TupleInitProbe,entry u64,metadata u64,source u64,result u64,guard u64){input:=[source,metadata,guard,guard,guard,guard,guard,guard,guard,guard,result,guard,u64(0x5021)]!;mut output:=[6]u64{};probe(unsafe{&input[0]},entry,unsafe{&output[0]});assert output[4]==guard&&output[5]==0x5021}
fn tuple_init_protection(address u64){
	$if macos{mut start:=address;mut size:=u64(0);mut info:=[16]i32{};mut count:=u32(C.VM_REGION_BASIC_INFO_COUNT_64);mut object:=u32(0);task:=C.mach_task_self();assert C.vm_region_64(task,&start,&size,C.VM_REGION_BASIC_INFO_64,unsafe{&info[0]},&count,&object)==0&&start<=address&&address+32<=start+size&&info[0]==(C.PROT_READ|C.PROT_EXEC);if object!=0{assert C.mach_port_deallocate(task,object)==0}}
	$else{mut found:=false;for line in (os.read_file('/proc/self/maps') or {panic(err)}).split_into_lines(){fields:=line.fields();if fields.len<2{continue};range:=fields[0].split('-');if range.len!=2{continue};start:=strconv.parse_uint(range[0],16,64) or {panic(err)};end:=strconv.parse_uint(range[1],16,64) or {panic(err)};if address>=start&&address<end{assert address+32<=end&&fields[1]=='r-xp';found=true;break}};assert found}
}
fn tuple_init_spans(probe TupleInitProbe,entry u64,metadata u64,guard u64){
	w:=read64(metadata-8);size:=read64(w+64);mask:=u64(read32(w+80)&255);page:=usize(C.getpagesize());input:=u64(C.mmap(unsafe{nil},page*3,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));output:=u64(C.mmap(unsafe{nil},page*3,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert input!=u64(-1)&&output!=u64(-1);s:=input+u64(page);r:=output+u64(page)
	for end in [false,true]!{for seed in [u64(0),1]!{
		assert C.mprotect(voidptr(s),page,C.PROT_READ|C.PROT_WRITE)==0&&C.mprotect(voidptr(r),page,C.PROT_READ|C.PROT_WRITE)==0;C.memset(voidptr(s),0xa5,page);C.memset(voidptr(r),0xa5,page)
		source:=if size==0{guard}else if end{s+u64(page)-((size+mask)&~mask)}else{s};result:=if size==0{guard}else if end{r+u64(page)-((size+mask)&~mask)}else{r}
		for i in u64(0)..size{unsafe{*(&u8(source+i))=if size==1{u8(seed)}else if size==9&&i==8{u8(0)}else{u8(i*37+seed)}}};assert C.mprotect(voidptr(s),page,C.PROT_READ)==0
		tuple_init_call(probe,entry,metadata,source,result,guard)
		for i in u64(0)..u64(page){p:=r+i;expected:=if size!=0&&p>=result&&p<result+size{unsafe{*(&u8(source+p-result))}}else{u8(0xa5)};assert unsafe{*(&u8(p))}==expected}
	}}
	assert C.munmap(voidptr(input),page*3)==0&&C.munmap(voidptr(output),page*3)==0
}
fn tuple_init_native(probe TupleInitProbe,candidate u64,guard u64){
	ui:=C.dlopen(c'/System/Library/Frameworks/SwiftUI.framework/SwiftUI',2);core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);assert ui!=unsafe{nil}&&core!=unsafe{nil};entry:=u64(C.dlsym(ui,unsafe{&char(tuple_init_symbol.str+1)}));access_entry:=C.dlsym(ui,c'$s7SwiftUI9TupleViewVMa');lookup_entry:=C.dlsym(core,c'swift_getTypeByMangledNameInContext');cstring_entry:=C.dlsym(core,c'$sSS7cStringSSSPys4Int8VG_tcfC');count_entry:=C.dlsym(core,c'swift_retainCount');keep_entry:=C.dlsym(core,c'swift_retain');drop_entry:=C.dlsym(core,c'swift_release');assert entry!=0&&access_entry!=unsafe{nil}&&lookup_entry!=unsafe{nil}&&cstring_entry!=unsafe{nil}&&count_entry!=unsafe{nil}&&keep_entry!=unsafe{nil}&&drop_entry!=unsafe{nil};access:=unsafe{TupleInitGeneric(access_entry)};lookup:=unsafe{TupleInitLookup(lookup_entry)}
	for name in ['yt','Sb','s5UInt8V','Si','SiSg','SS','s5SIMD4VySfG']!{
		value:=lookup(name.str,usize(name.len),0,0);assert value!=0;tuple:=access(0,value);assert tuple.state==0&&read64(tuple.metadata+16)==value&&read32(tuple.metadata+24)==0;w:=read64(value-8);tw:=read64(tuple.metadata-8);assert read64(w+64)==read64(tw+64)&&read64(w+72)==read64(tw+72);println('NATIVE-TUPLE-INIT-CONSTRUCTION '+name+' size='+read64(w+64).str()+' stride='+read64(w+72).str()+' field=0')
		if name!='SS'{for function in [entry,candidate]!{tuple_init_spans(probe,function,value,guard)};continue}
		count:=unsafe{TupleInitCount(count_entry)};keep:=unsafe{TupleInitKeep(keep_entry)};drop:=unsafe{TupleInitDrop(drop_entry)};transfer:=unsafe{TupleInitCopy(voidptr(read64(tw+16)))};destroy:=unsafe{TupleInitDestroy(voidptr(read64(tw+8)))};page:=usize(C.getpagesize());base:=u64(C.mmap(unsafe{nil},page*2,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=u64(-1);result:=base+u64(page)
		for function in [entry,candidate]!{
			assert C.mprotect(voidptr(base),page,C.PROT_READ|C.PROT_WRITE)==0;text:='a native consumed TupleView String longer than fifteen bytes';words:=unsafe{TupleInitCString(cstring_entry)(text.str)};owner:=words.second;before:=count(owner);assert before==1&&keep(owner)==owner;unsafe{*(&u64(base))=words.first;*(&u64(base+8))=words.second};assert C.mprotect(voidptr(base),page,C.PROT_READ)==0;C.memset(voidptr(result),0xa5,page)
			tuple_init_call(probe,function,value,base,result,guard);assert read64(result)==words.first&&read64(result+8)==words.second&&count(owner)==before+1;for i in u64(16)..u64(page){assert unsafe{*(&u8(result+i))}==0xa5}
			assert transfer(result+32,result,tuple.metadata)==result+32&&count(owner)==before+2;destroy(result,tuple.metadata);assert count(owner)==before+1;destroy(result+32,tuple.metadata);assert count(owner)==before;drop(owner)
		}
		assert C.munmap(voidptr(base),page*2)==0
	}
	assert C.dlclose(core)==0&&C.dlclose(ui)==0;println('NATIVE-SWIFTUI-TUPLE-INIT: two integer arguments and indirect x8 result, seven native/Vinix layouts and constructions, guarded POD spans and consumed owned String without retain, native TupleView copies and destruction balanced, x20/x21 preserved; no graph, rendering or application code executed')
}
fn tuple_init_resolve()u64{return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI',tuple_init_symbol) or {panic(err)}}
fn tuple_init_reader()u64{entry:=tuple_init_resolve();for _ in 0..256{assert tuple_init_resolve()==entry};return entry}
__global tuple_init_expected=u64(0)
__global tuple_init_takes=0
__global tuple_init_reenter=false
__global tuple_init_callback_metadata=u64(0)
__global tuple_init_callback_source=u64(0)
__global tuple_init_callbacks=0
fn tuple_init_copy_forbidden(destination u64,source u64,metadata u64)u64{panic('TupleView initializer must consume through initializeWithTake')}
fn tuple_init_take(destination u64,source u64,metadata u64)u64{assert metadata==tuple_init_expected;tuple_init_takes++;if tuple_init_reenter{tuple_init_reenter=false;worker:=spawn tuple_init_reader();assert worker.wait()==tuple_init_resolve()};size:=read64(read64(metadata-8)+64);if size!=0{C.memcpy(voidptr(destination),voidptr(source),usize(size))};return destination}
fn tuple_init_callback(object u64,selector &char){assert ios_runtime.swift_concurrency_retired;assert tuple_init_resolve()==ios_runtime.swiftui_tuple_init_arena;mut result:=[u8(0xa5),0,0xa5]!;swiftui_tuple_init(u64(unsafe{&result[1]}),tuple_init_callback_source,tuple_init_callback_metadata);assert result==[u8(0xa5),0x5a,0xa5]!;tuple_init_callbacks++}
fn test_swiftui_tuple_init(){
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=u64(-1)&&guard!=u64(-1)
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0003f1,0xaa0103f0,0xaa0203f3,0xd10043ff,0xa9400620,0xa9410e22,0xa9421624,0xa9431e26,0xa9442a29,0xa9002be9,0xf9402a28,0xf9402e34,0xf9403235,0xd63f0200,0xa9000660,0xa9010e62,0xa9025674,0x910043ff,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]!{write32(code+u64(i*4),op)};C.__builtin___clear_cache(voidptr(code),voidptr(code+100));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0;probe:=unsafe{TupleInitProbe(voidptr(code))}
	if _:=swiftui_tuple_init_arena_checked(){assert false}
	for lifetime in 0..2{
		objc_start();assert ios_runtime.swiftui_tuple_init_arena==0&&!ios_runtime.swiftui_tuple_init_retired;ios_runtime.swift_concurrency_retired=true;if _:=swiftui_tuple_init_symbol(tuple_init_symbol){assert false};ios_runtime.swift_concurrency_retired=false
		for wrong in [tuple_init_symbol+'Extra',tuple_init_symbol.replace('$s7SwiftUI','$s11SwiftUICore'),tuple_init_symbol.replace('9TupleView','6ZStack'),tuple_init_symbol.replace('cfC','cfU'),'_$s7SwiftUI9TupleViewVMa']!{assert wrong!=tuple_init_symbol;if _:=swiftui_tuple_init_symbol(wrong){assert false}};assert ios_runtime.swiftui_tuple_init_arena==0
		mut workers:=[]thread u64{};for _ in 0..8{workers<<spawn tuple_init_reader()};mut entry:=u64(0);for i,worker in workers{candidate:=worker.wait();if i==0{entry=candidate}else{assert entry==candidate}};unsafe{workers.free()};tuple_init_protection(entry);assert read32(entry)==0xaa0103e2&&read32(entry+4)==0xaa0003e1&&read32(entry+8)==0xaa0803e0&&read64(entry+24)==u64(unsafe{voidptr(swiftui_tuple_init)})
		for library in ['/usr/lib/swift/libswiftCore.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']!{if _:=runtime_symbol(library,tuple_init_symbol){assert false}}
		$if macos{if lifetime==0{tuple_init_native(probe,entry,guard)}}
		mut witness:=[12]u64{};witness[2]=u64(unsafe{voidptr(tuple_init_copy_forbidden)});witness[4]=u64(unsafe{voidptr(tuple_init_take)});mut storage:=[u64(unsafe{&witness[0]}),u64(0x200)]!;metadata:=u64(unsafe{&storage[1]});tuple_init_expected=metadata;before:=tuple_init_takes
		for size in [u64(0),1,7,8,9,15,16,17,24,25,32,63,64,255,2048]!{witness[8]=size;witness[9]=if size==0{u64(1)}else{(size+31)&~u64(31)};witness[10]=31;tuple_init_spans(probe,entry,metadata,guard)};assert tuple_init_takes==before+60
		witness[8]=8;witness[9]=8;witness[10]=0x10007;heap_storage:=[guard,u64(0),0x400]!;owner:=swift_heap_allocate(u64(unsafe{&heap_storage[2]}),32,7);source:=[owner]!;mut result:=[u64(0xcafe),0,0xbeef]!;tuple_init_reenter=true;takes:=tuple_init_takes;tuple_init_call(probe,entry,metadata,u64(unsafe{&source[0]}),u64(unsafe{&result[1]}),guard);assert result==[u64(0xcafe),owner,0xbeef]!&&tuple_init_takes==takes+1&&!tuple_init_reenter&&(swift_buffer_refs(owner,0) or {panic(err)})==1;swift_heap_deallocate_uninitialized(result[1],32,7)
		witness[8]=1;witness[9]=1;witness[10]=0;callback_source:=[u64(0x5a)]!;tuple_init_callback_metadata=metadata;tuple_init_callback_source=u64(unsafe{&callback_source[0]});assert ios_runtime.swift_heap.len==0&&ios_runtime.swift_arrays.len==0&&ios_runtime.swift_buffers.len==0&&ios_runtime.live==0&&ios_runtime.swiftui_tuple_nominal_arena==0
		cls:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixTupleInitCallback',0);assert cls!=0&&objc_add_method(cls,u64(c'dealloc'),u64(unsafe{voidptr(tuple_init_callback)}),c'v16@0:8');objc_register_class(cls);objc_autorelease(objc_new(cls));callbacks:=tuple_init_callbacks;base:=ios_runtime.swiftui_tuple_init_arena;ios_runtime.swift_concurrency_retired=true;assert tuple_init_resolve()==entry;objc_stop();assert tuple_init_callbacks==callbacks+1&&ios_runtime.swiftui_tuple_init_arena==0&&ios_runtime.swiftui_tuple_init_retired&&ios_runtime.live==0
		$if macos{assert C.mprotect(voidptr(base),page,C.PROT_READ)==-1}$else{mut residency:=u8(0);assert C.mincore(voidptr(base),page,&residency)==-1};if _:=swiftui_tuple_init_symbol(tuple_init_symbol){assert false}
	}
	assert C.munmap(voidptr(code),page)==0&&C.munmap(voidptr(guard),page)==0
	println('IOS-SWIFTUI-TUPLE-INIT: consuming value construction through initializeWithTake, fifteen size/stride cases, exact protected source/result spans including zero-size guards, copy witness never used, owned reference moved without retain, reentrant take witness, eight cold readers, sealed adapter, x20/x21 and unused protected registers/stack, exact routing, warm callbacks and two drained/unmapped lifetimes; TupleView metadata instantiation, View graph execution and rendering remain unsupported')
}
