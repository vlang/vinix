// SPDX-License-Identifier: GPL-2.0-or-later
module main
#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.dlclose(voidptr)i32
const state_projected_symbol='_$s7SwiftUI5StateV14projectedValueAA7BindingVyxGvg'
const state_projected_diagnostic='iOS: SwiftUI State.projectedValue Binding construction is not implemented'
type StateProjectedProbe=fn(&u64,u64,&u64)
struct StateProjectedResponse { metadata u64 state u64 }
struct StateProjectedWords { first u64 second u64 }
type StateProjectedGeneric=fn(u64,u64)StateProjectedResponse
type StateProjectedLookup=fn(&u8,usize,u64,u64)u64
type StateProjectedCString=fn(&u8)StateProjectedWords
type StateProjectedCopy=fn(u64,u64,u64)u64
type StateProjectedDestroy=fn(u64,u64)
type StateProjectedCount=fn(u64)u64
fn state_projected_call(probe StateProjectedProbe,entry u64,metadata u64,self_value u64,result u64,guard u64){input:=[metadata,guard,guard,guard,guard,guard,guard,guard,guard,guard,result,self_value,u64(0x5021)]!;mut output:=[6]u64{};probe(unsafe{&input[0]},entry,unsafe{&output[0]});assert output[4]==self_value&&output[5]==0x5021}

fn state_projected_native(probe StateProjectedProbe,guard u64){
	ui:=C.dlopen(c'/System/Library/Frameworks/SwiftUI.framework/SwiftUI',2);core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);assert ui!=unsafe{nil}&&core!=unsafe{nil}
	entry:=u64(C.dlsym(ui,unsafe{&char(state_projected_symbol.str+1)}));state_entry:=C.dlsym(ui,c'$s7SwiftUI5StateVMa');binding_entry:=C.dlsym(ui,c'$s7SwiftUI7BindingVMa');getter:=u64(C.dlsym(ui,c'$s7SwiftUI7BindingV12wrappedValuexvg'));lookup_entry:=C.dlsym(core,c'swift_getTypeByMangledNameInContext');cstring_entry:=C.dlsym(core,c'$sSS7cStringSSSPys4Int8VG_tcfC');count_entry:=C.dlsym(core,c'swift_retainCount');assert entry!=0&&getter!=0&&state_entry!=unsafe{nil}&&binding_entry!=unsafe{nil}&&lookup_entry!=unsafe{nil}&&cstring_entry!=unsafe{nil}&&count_entry!=unsafe{nil}
	state_access:=unsafe{StateProjectedGeneric(state_entry)};binding_access:=unsafe{StateProjectedGeneric(binding_entry)};lookup:=unsafe{StateProjectedLookup(lookup_entry)};count:=unsafe{StateProjectedCount(count_entry)};page:=usize(C.getpagesize());base:=u64(C.mmap(unsafe{nil},page*3,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=u64(-1);result:=base+u64(page)+16;copy_result:=base+u64(page)*2+16
	for name in ['yt','Sb','s5UInt8V','Si','SiSg','SS','s5SIMD4VySfG']!{
		value:=lookup(name.str,usize(name.len),0,0);assert value!=0;state:=state_access(0,value);binding:=binding_access(0,value);assert state.state==0&&binding.state==0&&read64(state.metadata+16)==value&&read64(binding.metadata+16)==value;w:=read64(value-8);bw:=read64(binding.metadata-8);size:=read64(w+64);binding_size:=read64(bw+64);stride:=read64(bw+72);assert read32(binding.metadata+24)==0&&read32(binding.metadata+28)==8&&read32(binding.metadata+32)==16&&binding_size==16+size&&stride>=binding_size
		println('NATIVE-SWIFTUI-STATE-PROJECTED-LAYOUT '+name+' value-size='+size.str()+' binding-size='+binding_size.str()+' binding-stride='+stride.str()+' fields=0,8,16')
		assert C.mprotect(voidptr(base),page,C.PROT_READ|C.PROT_WRITE)==0;C.memset(voidptr(base),0,page);C.memset(voidptr(base+u64(page)),0xa5,page*2);mut string_owner:=u64(0);mut string_before:=u64(0)
		if name=='Sb'{unsafe{*(&u8(base))=1}}
		if name=='SS'{words:=unsafe{StateProjectedCString(cstring_entry)(c'an owned native projected State String longer than fifteen bytes')};unsafe{*(&u64(base))=words.first;*(&u64(base+8))=words.second};string_owner=words.second;string_before=count(string_owner);assert string_before>0&&string_before<1000}
		assert read64(base+u64(read32(state.metadata+28)))==0&&C.mprotect(voidptr(base),page,C.PROT_READ)==0;state_projected_call(probe,entry,state.metadata,base,result,guard);assert read64(result)==0;location:=read64(result+8);assert location!=0;before:=count(location);assert before>0&&before<1000
		for i in u64(0)..size{assert unsafe{*(&u8(result+16+i))}==unsafe{*(&u8(base+i))}};for i in u64(0)..8{assert unsafe{*(&u8(result-8+i))}==0xa5&&unsafe{*(&u8(result+stride+i))}==0xa5}
		if name=='SS'{assert count(string_owner)==string_before+2}
		witness_copy:=unsafe{StateProjectedCopy(voidptr(read64(bw+16)))};destroy:=unsafe{StateProjectedDestroy(voidptr(read64(bw+8)))};assert witness_copy(copy_result,result,binding.metadata)==copy_result&&read64(copy_result)==0&&read64(copy_result+8)==location&&count(location)==before+1
		if name=='SS'{assert count(string_owner)==string_before+3}
		destroy(copy_result,binding.metadata);assert count(location)==before;if name=='SS'{assert count(string_owner)==string_before+2}
		if name=='Sb'{assert C.mprotect(voidptr(base),page,C.PROT_READ|C.PROT_WRITE)==0;unsafe{*(&u8(base))=0};assert C.mprotect(voidptr(base),page,C.PROT_READ)==0;mut output:=[u8(0xa5),0,0xa5]!;state_projected_call(probe,getter,binding.metadata,result,u64(unsafe{&output[1]}),guard);assert output==[u8(0xa5),1,0xa5]!;println('NATIVE-SWIFTUI-STATE-PROJECTED-CONSTANT: Binding Bool stays true after source State becomes false')}
		destroy(result,binding.metadata);if name=='SS'{assert count(string_owner)==string_before};assert C.mprotect(voidptr(base),page,C.PROT_READ|C.PROT_WRITE)==0;state_destroy:=unsafe{StateProjectedDestroy(voidptr(read64(read64(state.metadata-8)+8)))};state_destroy(base,state.metadata)
	}
	assert C.munmap(voidptr(base),page*3)==0&&C.dlclose(core)==0&&C.dlclose(ui)==0
	println('NATIVE-SWIFTUI-STATE-PROJECTED: seven Binding layouts, nil transaction and owned constant location, cached Value and location capture own two String references, copy/destroy balances both owners, Bool snapshot independent of State, x20/x21 preserved; no attached locations, graph or application code executed')
}

fn state_projected_resolve()u64{return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI',state_projected_symbol) or {panic(err)}}
fn state_projected_reject(probe StateProjectedProbe,entry u64,metadata u64,guard u64,result u64,self_value u64){
	mut fds:=[2]i32{};assert C.pipe(unsafe{&fds[0]})==0;pid:=C.ios_fork();assert pid>=0
	if pid==0{C.close(fds[0]);assert C.dup2(fds[1],2)==2;C.close(fds[1]);input:=[metadata,guard,guard,guard,guard,guard,guard,guard,guard,guard,result,self_value,guard]!;mut output:=[6]u64{};probe(unsafe{&input[0]},entry,unsafe{&output[0]});C._exit(0)}
	C.close(fds[1]);mut bytes:=[16384]u8{};mut length:=0;for{assert length<bytes.len;n:=C.read(fds[0],unsafe{&bytes[length]},usize(bytes.len-length));if n==0{break};if n<0&&unsafe{*C.ios_errno_address()}==C.EINTR{continue};assert n>0;length+=int(n)};C.close(fds[0]);mut status:=i32(0);assert C.ios_waitpid(pid,&status,0)==pid&&status==256
	output:=unsafe{tos(&bytes[0],length)};assert output.contains(state_projected_diagnostic);for bad in ['runtime error:','AddressSanitizer','Segmentation fault','SIGSEGV','SIGBUS','invalid SwiftUI State location offset','live locations are not implemented']!{assert !output.contains(bad),output}
}
fn state_projected_reader()u64{entry:=state_projected_resolve();for _ in 0..1024{assert state_projected_resolve()==entry};return entry}
__global state_projected_callbacks=0
fn state_projected_callback(object u64,selector &char){assert ios_runtime.swift_concurrency_retired;expected:=swiftui_state_projected_symbol(state_projected_symbol) or {panic('projected binding')};assert state_projected_resolve()==expected;state_projected_callbacks++}

fn test_swiftui_state_projected(){
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));shared_base:=u64(C.mmap(unsafe{nil},page*3,C.PROT_NONE,C.MAP_SHARED|C.MAP_ANONYMOUS,-1,0));assert code!=u64(-1)&&guard!=u64(-1)&&shared_base!=u64(-1);shared:=shared_base+u64(page)
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0003f1,0xaa0103f0,0xaa0203f3,0xd10043ff,0xa9400620,0xa9410e22,0xa9421624,0xa9431e26,0xa9442a29,0xa9002be9,0xf9402a28,0xf9402e34,0xf9403235,0xd63f0200,0xa9000660,0xa9010e62,0xa9025674,0x910043ff,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
	C.__builtin___clear_cache(voidptr(code),voidptr(code+100));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0;probe:=unsafe{StateProjectedProbe(voidptr(code))}
	$if macos{state_projected_native(probe,guard)}
	entry:=state_projected_resolve()
	for wrong in [state_projected_symbol+'Extra',state_projected_symbol.replace('$s7SwiftUI','$s11SwiftUICore'),state_projected_symbol.replace('5State','7Binding'),state_projected_symbol.replace('14projectedValueAA7BindingVyxGvg','12wrappedValuexvg')]!{if _:=swiftui_state_projected_symbol(wrong){assert false}}
	for _ in 0..2{
		objc_start();mut workers:=[]thread u64{};for _ in 0..8{workers<<spawn state_projected_reader()};for worker in workers{assert worker.wait()==entry};unsafe{workers.free()}
		for library in ['/usr/lib/swift/libswiftCore.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']!{if _:=runtime_symbol(library,state_projected_symbol){assert false}}
		for metadata in [u64(0),guard,1,~u64(0)]!{for self_value in [u64(0),guard,~u64(0)]!{
			state_projected_reject(probe,entry,metadata,guard,guard,self_value);assert C.mprotect(voidptr(shared),page,C.PROT_READ|C.PROT_WRITE)==0;C.memset(voidptr(shared),0xa5,page)
			for writable in [true,false]!{assert C.mprotect(voidptr(shared),page,C.PROT_READ|if writable{C.PROT_WRITE}else{0})==0;for result in [shared,shared+u64(page)-128]!{state_projected_reject(probe,entry,metadata,guard,result,self_value);for i in u64(0)..u64(page){assert unsafe{*(&u8(shared+i))}==0xa5}}}
		}}
		assert ios_runtime.swift_heap.len==0&&ios_runtime.swift_arrays.len==0&&ios_runtime.swift_buffers.len==0&&ios_runtime.live==0&&ios_runtime.swiftui_state_value_arena==0&&ios_runtime.swiftui_state_set_arena==0&&ios_runtime.swift_metadata_arena==0
		cls:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixStateProjectedCallback',0);assert cls!=0&&objc_add_method(cls,u64(c'dealloc'),u64(unsafe{voidptr(state_projected_callback)}),c'v16@0:8');objc_register_class(cls);objc_autorelease(objc_new(cls));before:=state_projected_callbacks;ios_runtime.swift_concurrency_retired=true;objc_stop();assert state_projected_callbacks==before+1&&ios_runtime.live==0
		assert state_projected_resolve()==entry;for metadata in [u64(0),guard,1,~u64(0)]!{state_projected_reject(probe,entry,metadata,guard,guard,guard)}
	}
	assert C.munmap(voidptr(code),page)==0&&C.munmap(voidptr(guard),page)==0&&C.munmap(voidptr(shared_base),page*3)==0
	println('IOS-SWIFTUI-STATE-PROJECTED: diagnostic binding only, 128 child calls exit 1, four metadata register patterns, protected metadata/stack/Self/x8, unchanged shared writable/read-only result pages at both guard boundaries, eight readers, exact framework routing, callbacks and two drained runtime lifetimes; Binding metadata, constant/live locations, transactions, graph execution and rendering remain unsupported')
}
