// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.dlclose(voidptr)i32
fn C.mincore(voidptr,usize,&u8)i32
const view_opacity_symbol='_$s7SwiftUI4ViewPAAE7opacityyQrSdF'
const view_opacity_bits=[u64(0),0x8000000000000000,0x3fe0000000000000,0x3ff0000000000000,0xbff0000000000000,0x4000000000000000,0x7ff0000000000000,0xfff0000000000000,0x7ff8000000001234,0x7ff0000000001234]!
type ViewOpacityProbe=fn(&u64,u64,&u64)
struct ViewOpacityResponse { metadata u64 state u64 }
type ViewOpacityAccess=fn(u64)ViewOpacityResponse
type ViewOpacityModified=fn(u64,u64,u64)ViewOpacityResponse
type ViewOpacityLookup=fn(&u8,usize,u64,u64)u64
type ViewOpacityGetter=fn()u64
type ViewOpacityAlpha=fn(f64,u64)u64
type ViewOpacityCount=fn(u64)u64
type ViewOpacityDestroy=fn(u64,u64)

fn view_opacity_resolve()u64{return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI',view_opacity_symbol) or {panic(err)}}
fn view_opacity_call(probe ViewOpacityProbe,entry u64,metadata u64,guard u64,source u64,result u64,bits u64){
	input:=[metadata,guard,source,result,bits,u64(0x5021)]!;mut output:=[u64(0),0]!
	probe(unsafe{&input[0]},entry,unsafe{&output[0]});assert output==[source,u64(0x5021)]!
}

// Exact source/result spans, including the zero-sized source at PROT_NONE.
// Native framework values and generic POD metadata share this ABI harness;
// the unused View table is deliberately protected, never a fake conformance.
fn view_opacity_spans(probe ViewOpacityProbe,entry u64,metadata u64,size u64,guard u64){
	page:=usize(C.getpagesize());input:=u64(C.mmap(unsafe{nil},page*3,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));output:=u64(C.mmap(unsafe{nil},page*3,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert input!=u64(-1)&&output!=u64(-1)
	s:=input+u64(page);r:=output+u64(page);offset:=(size+7)&~u64(7);length:=offset+8;mask:=u64(read32(read64(metadata-8)+80)&255);result_mask:=if mask<7{u64(7)}else{mask}
	for end in [false,true]!{
		assert C.mprotect(voidptr(s),page,C.PROT_READ|C.PROT_WRITE)==0;C.memset(voidptr(s),0,page)
		source:=if size==0{guard}else if end{s+u64(page)-((size+mask)&~mask)}else{s}
		// All-zero POD payload is valid, including Optional<Int>.some(0).
		assert C.mprotect(voidptr(s),page,C.PROT_READ)==0&&C.mprotect(voidptr(r),page,C.PROT_READ|C.PROT_WRITE)==0
		result:=if end{r+u64(page)-((length+result_mask)&~result_mask)}else{r}
		for bits in view_opacity_bits {
			C.memset(voidptr(r),0xa5,page);view_opacity_call(probe,entry,metadata,guard,source,result,bits)
			for i in u64(0)..u64(page){p:=r+i;expected:=if p>=result&&p<result+size{u8(0)}else if p>=result+offset&&p<result+length{u8(bits>>((p-result-offset)*8))}else{u8(0xa5)};assert unsafe{*(&u8(p))}==expected}
		}
	}
	assert C.munmap(voidptr(input),page*3)==0&&C.munmap(voidptr(output),page*3)==0
}

fn view_opacity_native(probe ViewOpacityProbe,guard u64,candidate u64){
	ui:=C.dlopen(c'/System/Library/Frameworks/SwiftUI.framework/SwiftUI',2);core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);assert ui!=unsafe{nil}&&core!=unsafe{nil}
	entry:=u64(C.dlsym(ui,unsafe{&char(view_opacity_symbol.str+1)}));lookup_entry:=C.dlsym(core,c'swift_getTypeByMangledNameInContext');modified_entry:=C.dlsym(ui,c'$s7SwiftUI15ModifiedContentVMa');effect_entry:=C.dlsym(ui,c'$s7SwiftUI14_OpacityEffectVMa');empty_entry:=C.dlsym(ui,c'$s7SwiftUI9EmptyViewVMa');assert entry!=0&&lookup_entry!=unsafe{nil}&&modified_entry!=unsafe{nil}&&effect_entry!=unsafe{nil}&&empty_entry!=unsafe{nil}
	lookup:=unsafe{ViewOpacityLookup(lookup_entry)};effect:=unsafe{ViewOpacityAccess(effect_entry)(0)};empty:=unsafe{ViewOpacityAccess(empty_entry)(0)};assert effect.state==0&&empty.state==0
	for name in ['yt','s5UInt8V','Si','SiSg','s5SIMD4VySfG']!{
		metadata:=lookup(name.str,usize(name.len),0,0);assert metadata!=0;w:=read64(metadata-8);size:=read64(w+64);assert read32(w+80)&0x10000==0
		result:=unsafe{ViewOpacityModified(modified_entry)(0,metadata,effect.metadata)};assert result.state==0&&read32(result.metadata+32)==0&&u64(read32(result.metadata+36))==(size+7)&~u64(7)
		assert read64(read64(result.metadata-8)+64)==((size+7)&~u64(7))+8
		for function in [entry,candidate]!{view_opacity_spans(probe,function,metadata,size,guard)};println('NATIVE-SWIFTUI-VIEW-OPACITY-LAYOUT '+name+' size='+size.str()+' stride='+read64(w+72).str()+' modifier='+read32(result.metadata+36).str())
	}
	for function in [entry,candidate]!{view_opacity_spans(probe,function,empty.metadata,0,guard)}
	// A native opacity Color provider owns its base Color. Verify the method
	// borrows that source and adds exactly one reference for the returned view.
	color_entry:=C.dlsym(ui,c'$s7SwiftUI5ColorVMa');black_entry:=C.dlsym(ui,c'$s7SwiftUI5ColorV5blackACvgZ');alpha_entry:=C.dlsym(ui,c'$s7SwiftUI5ColorV7opacityyACSdF');count_entry:=C.dlsym(core,c'swift_retainCount');assert color_entry!=unsafe{nil}&&black_entry!=unsafe{nil}&&alpha_entry!=unsafe{nil}&&count_entry!=unsafe{nil}
	color:=unsafe{ViewOpacityAccess(color_entry)(0)};assert color.state==0;mut source:=unsafe{ViewOpacityGetter(black_entry)()};base:=source;source=unsafe{ViewOpacityAlpha(alpha_entry)(0.5,source)};assert source!=0&&source!=base
	count:=unsafe{ViewOpacityCount(count_entry)};before:=count(source);assert before>0&&before<1000
	destroy:=unsafe{ViewOpacityDestroy(voidptr(read64(read64(color.metadata-8)+8)))}
	for function in [entry,candidate]!{mut result:=[u64(0xa5a5),0xa5a5,0xa5a5,0xa5a5]!;view_opacity_call(probe,function,color.metadata,guard,u64(unsafe{&source}),u64(unsafe{&result[1]}),0x3fe0000000000000)
		assert result==[u64(0xa5a5),source,0x3fe0000000000000,0xa5a5]!&&count(source)==before+1
		destroy(u64(unsafe{&result[1]}),color.metadata);assert count(source)==before}
	destroy(u64(unsafe{&source}),color.metadata);destroy(u64(unsafe{&base}),color.metadata)
	assert C.dlclose(core)==0&&C.dlclose(ui)==0
	println('NATIVE-SWIFTUI-VIEW-OPACITY: five generic POD layouts, EmptyView and owned Color; exact protected spans and ten IEEE bit patterns, borrowed source, one owned result reference and balanced destruction')
}

__global view_opacity_copies=0
__global view_opacity_destroys=0
__global view_opacity_expected_metadata=u64(0)
__global view_opacity_owned=false
fn view_opacity_copy(destination u64,source u64,metadata u64)u64{
	assert metadata==view_opacity_expected_metadata;view_opacity_copies++;size:=read64(read64(metadata-8)+64)
	if size!=0{C.memcpy(voidptr(destination),voidptr(source),usize(size))}
	if view_opacity_owned{swift_retain(read64(destination))}
	return destination
}
fn view_opacity_destroy(value u64,metadata u64){assert metadata==view_opacity_expected_metadata;view_opacity_destroys++;if view_opacity_owned{swift_release(read64(value))}}
fn view_opacity_reader()u64{mut entry:=u64(0);for _ in 0..256{candidate:=view_opacity_resolve();if entry==0{entry=candidate}else{assert entry==candidate}};return entry}
fn view_opacity_overflow(probe ViewOpacityProbe,entry u64,metadata u64,guard u64){
	mut fds:=[2]i32{};assert C.pipe(unsafe{&fds[0]})==0;pid:=C.ios_fork();assert pid>=0
	if pid==0{C.close(fds[0]);assert C.dup2(fds[1],2)==2;C.close(fds[1]);view_opacity_call(probe,entry,metadata,guard,guard,guard,0);C._exit(0)}
	C.close(fds[1]);mut bytes:=[16384]u8{};mut length:=0;for{assert length<bytes.len;n:=C.read(fds[0],unsafe{&bytes[length]},usize(bytes.len-length));if n==0{break};if n<0&&unsafe{*C.ios_errno_address()}==C.EINTR{continue};assert n>0;length+=int(n)};C.close(fds[0]);mut status:=i32(0);assert C.ios_waitpid(pid,&status,0)==pid&&status==256
	output:=unsafe{tos(&bytes[0],length)};assert output.contains('iOS: SwiftUI View.opacity result size overflow')&&!output.contains('runtime error:')&&!output.contains('AddressSanitizer')
}
__global view_opacity_callbacks=0
fn view_opacity_callback(object u64,selector &char){assert ios_runtime.swift_concurrency_retired&&view_opacity_resolve()==ios_runtime.swiftui_opacity_arena+128;view_opacity_callbacks++}

fn test_swiftui_view_opacity(){
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=u64(-1)&&guard!=u64(-1)
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0003f1,0xaa0103f0,0xaa0203f3,0xa9400620,0xf9400a34,0xf9400e28,0xfd401220,0xf9401635,0xd63f0200,0xa9005674,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
	C.__builtin___clear_cache(voidptr(code),voidptr(code+68));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0;probe:=unsafe{ViewOpacityProbe(voidptr(code))}
	if _:=swiftui_view_opacity_symbol(view_opacity_symbol){assert false}
	for _ in 0..2{
		objc_start();ios_runtime.swift_concurrency_retired=true;if _:=swiftui_view_opacity_symbol(view_opacity_symbol){assert false};ios_runtime.swift_concurrency_retired=false
		for wrong in [view_opacity_symbol+'Extra',view_opacity_symbol.replace('$s7SwiftUI','$s11SwiftUICore'),view_opacity_symbol.replace('4ViewP','12ViewModifierP')]!{if _:=swiftui_view_opacity_symbol(wrong){assert false}};assert ios_runtime.swiftui_opacity_arena==0
		mut workers:=[]thread u64{};for _ in 0..8{workers<<spawn view_opacity_reader()};mut entry:=u64(0);for i,worker in workers{candidate:=worker.wait();if i==0{entry=candidate}else{assert entry==candidate}};unsafe{workers.free()}
		$if macos{view_opacity_native(probe,guard,entry)}
		for library in ['/usr/lib/swift/libswiftCore.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']!{if _:=runtime_symbol(library,view_opacity_symbol){assert false}}
		mut witness:=[12]u64{};witness[2]=u64(unsafe{voidptr(view_opacity_copy)});witness[1]=u64(unsafe{voidptr(view_opacity_destroy)});mut storage:=[u64(unsafe{&witness[0]}),u64(0x200)]!;metadata:=u64(unsafe{&storage[1]});view_opacity_expected_metadata=metadata
		view_opacity_owned=false;before:=view_opacity_copies
		for size in [u64(0),1,7,8,9,15,16,17,24,25,32,63,64,255,2048]!{witness[8]=size;witness[9]=if size==0{u64(1)}else{(size+31)&~u64(31)};witness[10]=31;view_opacity_spans(probe,entry,metadata,size,guard)};assert view_opacity_copies==before+300
		witness[8]=~u64(0);view_opacity_overflow(probe,entry,metadata,guard);assert view_opacity_copies==before+300
		witness[8]=8;witness[9]=32;witness[10]=0x10007;view_opacity_owned=true
		heap_storage:=[guard,u64(0),0x400]!;owner:=swift_heap_allocate(u64(unsafe{&heap_storage[2]}),32,7);mut source:=owner;mut result:=[u64(0xcafe),0,0,0xbeef]!;before_copy:=view_opacity_copies;before_destroy:=view_opacity_destroys
		view_opacity_call(probe,entry,metadata,guard,u64(unsafe{&source}),u64(unsafe{&result[1]}),0x7ff8000000001234)
		assert source==owner&&result==[u64(0xcafe),owner,0x7ff8000000001234,0xbeef]!&&view_opacity_copies==before_copy+1&&view_opacity_destroys==before_destroy&&(swift_buffer_refs(owner,0) or {panic(err)})==2
		view_opacity_destroy(u64(unsafe{&result[1]}),metadata);assert (swift_buffer_refs(owner,0) or {panic(err)})==1;swift_heap_deallocate_uninitialized(owner,32,7);view_opacity_owned=false
		assert ios_runtime.swift_heap.len==0&&ios_runtime.swift_arrays.len==0&&ios_runtime.swift_buffers.len==0&&ios_runtime.live==0&&ios_runtime.swiftui_modified_arena==0
		cls:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixViewOpacityCallback',0);assert cls!=0&&objc_add_method(cls,u64(c'dealloc'),u64(unsafe{voidptr(view_opacity_callback)}),c'v16@0:8');objc_register_class(cls);objc_autorelease(objc_new(cls));base:=ios_runtime.swiftui_opacity_arena;callbacks:=view_opacity_callbacks
		ios_runtime.swift_concurrency_retired=true;assert view_opacity_resolve()==entry;objc_stop();assert view_opacity_callbacks==callbacks+1&&ios_runtime.swiftui_opacity_arena==0&&ios_runtime.swiftui_opacity_retired&&ios_runtime.live==0
		$if macos{assert C.mprotect(voidptr(base),page*2,C.PROT_READ)==-1}$else{mut residency:=[u8(0),0]!;assert C.mincore(voidptr(base),page*2,unsafe{&residency[0]})==-1};if _:=swiftui_view_opacity_symbol(view_opacity_symbol){assert false}
	}
	assert C.munmap(voidptr(code),page)==0&&C.munmap(voidptr(guard),page)==0
	println('IOS-SWIFTUI-VIEW-OPACITY: value construction, fifteen size/stride cases and ten IEEE bit patterns at both protected boundaries, one copy witness and owned result, borrowed source, x20/x21 preservation, unused protected View table, eight readers, exact framework routing, callbacks and two drained/unmapped lifetimes; generic ModifiedContent metadata, graph construction and rendering remain unsupported')
}
