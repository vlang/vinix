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
const state_set_symbol='_$s7SwiftUI5StateV12wrappedValuexvs'
type StateSetProbe=fn(&u64,u64,&u64)
struct StateSetResponse { metadata u64 state u64 }
struct StateSetWords { first u64 second u64 }
type StateSetGeneric=fn(u64,u64)StateSetResponse
type StateSetLookup=fn(&u8,usize,u64,u64)u64
type StateSetCString=fn(&u8)StateSetWords
type StateSetCount=fn(u64)u64
type StateSetRetain=fn(u64)u64
type StateSetRelease=fn(u64)
type StateSetDestroy=fn(u64,u64)
fn state_set_resolve()u64{return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI',state_set_symbol) or {panic(err)}}
fn state_set_call(probe StateSetProbe,entry u64,metadata u64,self_value u64,value u64,guard u64){state_set_argument=value;input:=[value,metadata,guard,guard,guard,guard,guard,guard,guard,guard,guard,self_value,u64(0x5021)]!;mut output:=[6]u64{};probe(unsafe{&input[0]},entry,unsafe{&output[0]});assert output[4]==self_value&&output[5]==0x5021}
fn state_set_protection(address u64){
	$if macos{mut start:=address;mut size:=u64(0);mut info:=[16]i32{};mut count:=u32(C.VM_REGION_BASIC_INFO_COUNT_64);mut object:=u32(0);task:=C.mach_task_self();assert C.vm_region_64(task,&start,&size,C.VM_REGION_BASIC_INFO_64,unsafe{&info[0]},&count,&object)==0&&start<=address&&address+24<=start+size&&info[0]==(C.PROT_READ|C.PROT_EXEC);if object!=0{assert C.mach_port_deallocate(task,object)==0}}
	$else{mut found:=false;for line in (os.read_file('/proc/self/maps') or {panic(err)}).split_into_lines(){fields:=line.fields();if fields.len<2{continue};range:=fields[0].split('-');if range.len!=2{continue};start:=strconv.parse_uint(range[0],16,64) or {panic(err)};end:=strconv.parse_uint(range[1],16,64) or {panic(err)};if address>=start&&address<end{assert address+24<=end&&fields[1]=='r-xp';found=true;break}};assert found}
}

// Both inputs are read-only, with guard pages at each end. A nil location does
// not write cached State, padding, or even the consumed argument's POD bytes.
fn state_set_spans(probe StateSetProbe,entry u64,metadata u64,guard u64){
	value:=read64(metadata+16);w:=read64(value-8);size:=read64(w+64);mask:=u64(read32(w+80)&255);location:=u64(read32(metadata+28));state_mask:=if mask<7{u64(7)}else{mask};length:=location+8;page:=usize(C.getpagesize());input:=u64(C.mmap(unsafe{nil},page*3,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));cached:=u64(C.mmap(unsafe{nil},page*3,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert input!=u64(-1)&&cached!=u64(-1);n:=input+u64(page);s:=cached+u64(page)
	for end in [false,true]!{for seed in [u64(0),1]!{
		assert C.mprotect(voidptr(s),page,C.PROT_READ|C.PROT_WRITE)==0&&C.mprotect(voidptr(n),page,C.PROT_READ|C.PROT_WRITE)==0;C.memset(voidptr(s),0xa5,page);C.memset(voidptr(n),0x5a,page)
		self_value:=if end{s+u64(page)-((length+state_mask)&~state_mask)}else{s};new_value:=if size==0{guard}else if end{n+u64(page)-((size+mask)&~mask)}else{n}
		for i in u64(0)..size{unsafe{*(&u8(self_value+i))=if size==1{u8(1-seed)}else if size==9&&i==8{u8(0)}else{u8(i*37+seed)};*(&u8(new_value+i))=if size==1{u8(seed)}else if size==9&&i==8{u8(0)}else{u8(i*19+seed)}}};unsafe{*(&u64(self_value+location))=0}
		before_state:=unsafe{tos(&u8(s),int(page))}.clone();before_value:=unsafe{tos(&u8(n),int(page))}.clone();assert C.mprotect(voidptr(s),page,C.PROT_READ)==0&&C.mprotect(voidptr(n),page,C.PROT_READ)==0
		state_set_call(probe,entry,metadata,self_value,new_value,guard)
		assert before_state==unsafe{tos(&u8(s),int(page))}&&before_value==unsafe{tos(&u8(n),int(page))};unsafe{before_state.free();before_value.free()}
	}}
	assert C.munmap(voidptr(input),page*3)==0&&C.munmap(voidptr(cached),page*3)==0
}

fn state_set_native(probe StateSetProbe,candidate u64,guard u64){
	ui:=C.dlopen(c'/System/Library/Frameworks/SwiftUI.framework/SwiftUI',2);core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);assert ui!=unsafe{nil}&&core!=unsafe{nil};entry:=u64(C.dlsym(ui,unsafe{&char(state_set_symbol.str+1)}));access_entry:=C.dlsym(ui,c'$s7SwiftUI5StateVMa');lookup_entry:=C.dlsym(core,c'swift_getTypeByMangledNameInContext');cstring_entry:=C.dlsym(core,c'$sSS7cStringSSSPys4Int8VG_tcfC');count_entry:=C.dlsym(core,c'swift_retainCount');retain_entry:=C.dlsym(core,c'swift_retain');release_entry:=C.dlsym(core,c'swift_release');assert entry!=0&&access_entry!=unsafe{nil}&&lookup_entry!=unsafe{nil}&&cstring_entry!=unsafe{nil}&&count_entry!=unsafe{nil}&&retain_entry!=unsafe{nil}&&release_entry!=unsafe{nil};access:=unsafe{StateSetGeneric(access_entry)};lookup:=unsafe{StateSetLookup(lookup_entry)}
	for name in ['yt','Sb','s5UInt8V','Si','SiSg','SS','s5SIMD4VySfG']!{
		value:=lookup(name.str,usize(name.len),0,0);assert value!=0;state:=access(0,value);assert state.state==0&&read64(state.metadata+16)==value&&read32(state.metadata+24)==0;w:=read64(value-8);sw:=read64(state.metadata-8);size:=read64(w+64);location:=(size+7)&~u64(7);assert u64(read32(state.metadata+28))==location&&read64(sw+64)==location+8;println('NATIVE-SWIFTUI-STATE-SET-LAYOUT '+name+' value-size='+size.str()+' value-stride='+read64(w+72).str()+' state-size='+read64(sw+64).str()+' location='+location.str())
		if name!='SS'{for function in [entry,candidate]!{state_set_spans(probe,function,state.metadata,guard)};continue}
		count:=unsafe{StateSetCount(count_entry)};retain:=unsafe{StateSetRetain(retain_entry)};release:=unsafe{StateSetRelease(release_entry)};cstring:=unsafe{StateSetCString(cstring_entry)};cached:=cstring(c'a cached native State String longer than fifteen bytes');cached_count:=count(cached.second);assert cached_count>0&&cached_count<1000;page:=usize(C.getpagesize());base:=u64(C.mmap(unsafe{nil},page*2,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=u64(-1);new_value:=base+u64(page);unsafe{*(&u64(base))=cached.first;*(&u64(base+8))=cached.second;*(&u64(base+16))=0};assert C.mprotect(voidptr(base),page,C.PROT_READ)==0
		for function in [entry,candidate]!{
			assert C.mprotect(voidptr(new_value),page,C.PROT_READ|C.PROT_WRITE)==0;C.memset(voidptr(new_value),0x5a,page);incoming:=cstring(c'an incoming native String consumed by a nil State setter');owner:=incoming.second;before:=count(owner);assert before>0&&before<1000&&owner!=cached.second;assert retain(owner)==owner&&count(owner)==before+1;unsafe{*(&u64(new_value))=incoming.first;*(&u64(new_value+8))=incoming.second};assert C.mprotect(voidptr(new_value),page,C.PROT_READ)==0
			state_set_call(probe,function,state.metadata,base,new_value,guard);assert count(owner)==before&&count(cached.second)==cached_count&&read64(base)==cached.first&&read64(base+8)==cached.second&&read64(base+16)==0&&read64(new_value)==incoming.first&&read64(new_value+8)==owner;for i in u64(16)..u64(page){assert unsafe{*(&u8(new_value+i))}==0x5a};release(owner)
		}
		assert C.mprotect(voidptr(base),page,C.PROT_READ|C.PROT_WRITE)==0;state_destroy:=unsafe{StateSetDestroy(voidptr(read64(sw+8)))};state_destroy(base,state.metadata);assert C.munmap(voidptr(base),page*2)==0
	}
	assert C.dlclose(core)==0&&C.dlclose(ui)==0;println('NATIVE-SWIFTUI-STATE-SET: seven State layouts, native/Vinix nil-location setters leave cached values unchanged, consume one owned String reference, preserve read-only input bytes and x20/x21; no attached locations, graph or application code executed')
}

__global state_set_expected=u64(0)
__global state_set_argument=u64(0)
__global state_set_destroys=0
__global state_set_owned=false
__global state_set_reenter=false
__global state_set_callback_meta=u64(0)
__global state_set_callback_self=u64(0)
__global state_set_callbacks=0
fn state_set_destroy(value u64,metadata u64){assert metadata==state_set_expected&&value==state_set_argument;state_set_destroys++;if state_set_reenter{state_set_reenter=false;worker:=spawn state_set_reader();assert worker.wait()==state_set_resolve()};if state_set_owned{swift_release(read64(value))}}
fn state_set_reader()u64{entry:=state_set_resolve();for _ in 0..256{assert state_set_resolve()==entry};return entry}
fn state_set_callback(object u64,selector &char){assert ios_runtime.swift_concurrency_retired;assert state_set_resolve()==ios_runtime.swiftui_state_set_arena;value:=u8(0x5a);before:=state_set_destroys;state_set_argument=u64(unsafe{&value});swiftui_state_set(state_set_argument,state_set_callback_meta,state_set_callback_self);assert state_set_destroys==before+1&&value==0x5a;state_set_callbacks++}

fn state_set_reject(probe StateSetProbe,entry u64,metadata u64,self_value u64,value u64,guard u64,negative bool){
	mut fds:=[2]i32{};assert C.pipe(unsafe{&fds[0]})==0;pid:=C.ios_fork();assert pid>=0;if pid==0{C.close(fds[0]);assert C.dup2(fds[1],2)==2;C.close(fds[1]);state_set_call(probe,entry,metadata,self_value,value,guard);C._exit(0)};C.close(fds[1]);mut bytes:=[16384]u8{};mut length:=0;for{assert length<bytes.len;n:=C.read(fds[0],unsafe{&bytes[length]},usize(bytes.len-length));if n==0{break};if n<0&&unsafe{*C.ios_errno_address()}==C.EINTR{continue};assert n>0;length+=int(n)};C.close(fds[0]);mut status:=i32(0);assert C.ios_waitpid(pid,&status,0)==pid&&status==256;output:=unsafe{tos(&bytes[0],length)};message:=if negative{'iOS: invalid SwiftUI State setter location offset'}else{'iOS: SwiftUI State.wrappedValue live location writes are not implemented'};assert output.contains(message);for bad in ['runtime error:','AddressSanitizer','Segmentation fault','SIGSEGV','SIGBUS']!{assert !output.contains(bad),output}
}
fn state_set_rejections(probe StateSetProbe,entry u64,guard u64){
	page:=usize(C.getpagesize());source_base:=u64(C.mmap(unsafe{nil},page*3,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));value_base:=u64(C.mmap(unsafe{nil},page*3,C.PROT_NONE,C.MAP_SHARED|C.MAP_ANONYMOUS,-1,0));assert source_base!=u64(-1)&&value_base!=u64(-1);location:=source_base+u64(page);value_page:=value_base+u64(page);mut state:=[u64(0x200),0,guard+8,u64(32)<<32]!;metadata:=u64(unsafe{&state[0]})
	for live in [u64(1),guard,~u64(0)]!{assert C.mprotect(voidptr(location),page,C.PROT_READ|C.PROT_WRITE)==0;unsafe{*(&u64(location))=live};assert C.mprotect(voidptr(location),page,C.PROT_READ)==0;state_set_reject(probe,entry,metadata,location-32,guard,guard,false);assert C.mprotect(voidptr(value_page),page,C.PROT_READ|C.PROT_WRITE)==0;C.memset(voidptr(value_page),0xa5,page);for writable in [true,false]!{assert C.mprotect(voidptr(value_page),page,C.PROT_READ|if writable{C.PROT_WRITE}else{0})==0;for value in [value_page,value_page+u64(page)-128]!{state_set_reject(probe,entry,metadata,location-32,value,guard,false);for i in u64(0)..u64(page){assert unsafe{*(&u8(value_page+i))}==0xa5}}}}
	for offset in [u32(0x80000000),0xffffffff]!{state[3]=u64(offset)<<32;state_set_reject(probe,entry,metadata,guard,guard,guard,true)};assert C.munmap(voidptr(source_base),page*3)==0&&C.munmap(voidptr(value_base),page*3)==0
}

fn test_swiftui_state_set(){
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=u64(-1)&&guard!=u64(-1)
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0003f1,0xaa0103f0,0xaa0203f3,0xd10043ff,0xa9400620,0xa9410e22,0xa9421624,0xa9431e26,0xa9442a29,0xa9002be9,0xf9402a28,0xf9402e34,0xf9403235,0xd63f0200,0xa9000660,0xa9010e62,0xa9025674,0x910043ff,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]!{write32(code+u64(i*4),op)};C.__builtin___clear_cache(voidptr(code),voidptr(code+100));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0;probe:=unsafe{StateSetProbe(voidptr(code))}
	if _:=swiftui_state_set_arena_checked(){assert false}
	for lifetime in 0..2{
		objc_start();assert ios_runtime.swiftui_state_set_arena==0&&!ios_runtime.swiftui_state_set_retired;ios_runtime.swift_concurrency_retired=true;if _:=swiftui_state_set_symbol(state_set_symbol){assert false};ios_runtime.swift_concurrency_retired=false
		for wrong in [state_set_symbol+'Extra',state_set_symbol.replace('$s7SwiftUI','$s11SwiftUICore'),state_set_symbol.replace('5State','7Binding'),state_set_symbol.replace('xvs','xvg'),'_$s7SwiftUI5StateVMa']!{if _:=swiftui_state_set_symbol(wrong){assert false}};assert ios_runtime.swiftui_state_set_arena==0
		mut workers:=[]thread u64{};for _ in 0..8{workers<<spawn state_set_reader()};mut entry:=u64(0);for i,worker in workers{candidate:=worker.wait();if i==0{entry=candidate}else{assert entry==candidate}};unsafe{workers.free()};state_set_protection(entry);assert read32(entry)==0xaa1403e2&&read64(entry+16)==u64(unsafe{voidptr(swiftui_state_set)})
		for library in ['/usr/lib/swift/libswiftCore.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']!{if _:=runtime_symbol(library,state_set_symbol){assert false}}
		$if macos{if lifetime==0{state_set_native(probe,entry,guard)}}
		mut witness:=[12]u64{};witness[1]=u64(unsafe{voidptr(state_set_destroy)});mut value_storage:=[u64(unsafe{&witness[0]}),u64(0x200)]!;value:=u64(unsafe{&value_storage[1]});state_set_expected=value;mut state:=[u64(0x200),0,value,u64(0)]!;metadata:=u64(unsafe{&state[0]});before:=state_set_destroys;state_set_owned=false
		for size in [u64(0),1,7,8,9,15,16,17,24,25,32,63,64,255,2048]!{witness[8]=size;witness[9]=if size==0{u64(1)}else{(size+31)&~u64(31)};witness[10]=31;state[3]=((size+7)&~u64(7))<<32;state_set_spans(probe,entry,metadata,guard)};assert state_set_destroys==before+60
		state_set_rejections(probe,entry,guard)
		witness[8]=8;witness[9]=8;witness[10]=0x10007;state[3]=u64(8)<<32;heap_storage:=[guard,u64(0),0x400]!;owner:=swift_heap_allocate(u64(unsafe{&heap_storage[2]}),32,7);swift_retain(owner);incoming:=[u64(0xcafe),owner,0xbeef]!;source:=[u64(0x55),0]!;state_set_owned=true;state_set_reenter=true;destroys:=state_set_destroys;state_set_call(probe,entry,metadata,u64(unsafe{&source[0]}),u64(unsafe{&incoming[1]}),guard);assert incoming==[u64(0xcafe),owner,0xbeef]!&&source==[u64(0x55),0]!&&state_set_destroys==destroys+1&&!state_set_reenter&&(swift_buffer_refs(owner,0) or {panic(err)})==1;swift_heap_deallocate_uninitialized(owner,32,7);state_set_owned=false
		// Even the cached Value may be inaccessible on the nil-location path.
		location_page:=u64(C.mmap(unsafe{nil},page*2,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert location_page!=u64(-1)&&C.mprotect(voidptr(location_page+u64(page)),page,C.PROT_READ|C.PROT_WRITE)==0;unsafe{*(&u64(location_page+u64(page)))=0};assert C.mprotect(voidptr(location_page+u64(page)),page,C.PROT_READ)==0;witness[8]=0;state[3]=u64(32)<<32;state_set_call(probe,entry,metadata,location_page+u64(page)-32,guard,guard);assert C.munmap(voidptr(location_page),page*2)==0
		witness[8]=1;witness[9]=1;witness[10]=0;state[3]=u64(8)<<32;callback_source:=[u64(0x55),0]!;state_set_callback_meta=metadata;state_set_callback_self=u64(unsafe{&callback_source[0]});assert ios_runtime.swift_heap.len==0&&ios_runtime.swift_arrays.len==0&&ios_runtime.swift_buffers.len==0&&ios_runtime.live==0
		cls:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixStateSetCallback',0);assert cls!=0&&objc_add_method(cls,u64(c'dealloc'),u64(unsafe{voidptr(state_set_callback)}),c'v16@0:8');objc_register_class(cls);objc_autorelease(objc_new(cls));callbacks:=state_set_callbacks;base:=ios_runtime.swiftui_state_set_arena;ios_runtime.swift_concurrency_retired=true;assert state_set_resolve()==entry;objc_stop();assert state_set_callbacks==callbacks+1&&ios_runtime.swiftui_state_set_arena==0&&ios_runtime.swiftui_state_set_retired&&ios_runtime.live==0
		$if macos{assert C.mprotect(voidptr(base),page,C.PROT_READ)==-1}$else{mut residency:=u8(0);assert C.mincore(voidptr(base),page,&residency)==-1};if _:=swiftui_state_set_symbol(state_set_symbol){assert false}
	}
	assert C.munmap(voidptr(code),page)==0&&C.munmap(voidptr(guard),page)==0
	println('IOS-SWIFTUI-STATE-SET: nil-location setters consume the new Value and leave cached State unchanged, fifteen size/stride cases and protected input spans, exactly one owned reference destroyed and reentrant destroy witness, 34 live-location/negative-offset child diagnostics before value/owner access, eight cold readers, sealed adapter, x20/x21 and unused protected registers/stack, exact routing, warm callbacks and two drained/unmapped lifetimes; live locations, State construction/metadata instantiation, graph execution and rendering remain unsupported')
}
