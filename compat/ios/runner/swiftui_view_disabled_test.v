// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.dlclose(voidptr)i32
const view_disabled_symbol='_$s7SwiftUI4ViewPAAE8disabledyQrSbF'
const view_disabled_diagnostic='iOS: SwiftUI View.disabled environment transform construction is not implemented'
type ViewDisabledProbe=fn(&u64,u64,&u64)
type ViewDisabledClosure=fn(u64,u64,u64)
struct ViewDisabledResponse { metadata u64 state u64 }
type ViewDisabledAccess=fn(u64)ViewDisabledResponse
type ViewDisabledGeneric=fn(u64,u64)ViewDisabledResponse
type ViewDisabledModified=fn(u64,u64,u64)ViewDisabledResponse
type ViewDisabledCopy=fn(u64,u64,u64)u64
type ViewDisabledDestroy=fn(u64,u64)
type ViewDisabledCount=fn(u64)u64

fn view_disabled_native(probe ViewDisabledProbe,call ViewDisabledClosure,guard u64){
	ui:=C.dlopen(c'/System/Library/Frameworks/SwiftUI.framework/SwiftUI',2);core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);assert ui!=unsafe{nil}&&core!=unsafe{nil}
	entry:=u64(C.dlsym(ui,unsafe{&char(view_disabled_symbol.str+1)}));empty_entry:=C.dlsym(ui,c'$s7SwiftUI9EmptyViewVMa');environment_entry:=C.dlsym(ui,c'$s7SwiftUI17EnvironmentValuesVMa');transform_entry:=C.dlsym(ui,c'$s7SwiftUI32_EnvironmentKeyTransformModifierVMa');modified_entry:=C.dlsym(ui,c'$s7SwiftUI15ModifiedContentVMa');boolean:=u64(C.dlsym(core,c'$sSbN'));count_entry:=C.dlsym(core,c'swift_retainCount');assert entry!=0&&empty_entry!=unsafe{nil}&&environment_entry!=unsafe{nil}&&transform_entry!=unsafe{nil}&&modified_entry!=unsafe{nil}&&boolean!=0&&count_entry!=unsafe{nil}
	empty:=unsafe{ViewDisabledAccess(empty_entry)(0)};environment:=unsafe{ViewDisabledAccess(environment_entry)(0)};transform:=unsafe{ViewDisabledGeneric(transform_entry)(0,boolean)};modified:=unsafe{ViewDisabledModified(modified_entry)(0,empty.metadata,transform.metadata)};assert empty.state==0&&environment.state==0&&transform.state==0&&modified.state==0
	for i,metadata in [environment.metadata,transform.metadata,modified.metadata]!{w:=read64(metadata-8);assert read64(w+64)==if i==0{u64(16)}else{u64(24)}&&read64(w+72)==read64(w+64)&&read32(w+80)==if i==0{u32(0x02010007)}else{u32(0x10007)}&&read32(w+84)==if i==0{u32(0x7ffffffe)}else{u32(0x7fffffff)};println('NATIVE-SWIFTUI-VIEW-DISABLED-LAYOUT '+i.str()+' size='+read64(w+64).str()+' stride='+read64(w+72).str())}
	assert read32(transform.metadata+24)==0&&read32(transform.metadata+28)==8&&read32(modified.metadata+32)==0&&read32(modified.metadata+36)==0
	witness:=read64(modified.metadata-8);witness_copy:=unsafe{ViewDisabledCopy(voidptr(read64(witness+16)))};destroy:=unsafe{ViewDisabledDestroy(voidptr(read64(witness+8)))};count:=unsafe{ViewDisabledCount(count_entry)};mut canonical:=u64(0)
	for disabled in [u64(0),1]!{
		mut result:=[u64(0xcafe),0,0,0,0xbeef]!;input:=[disabled,empty.metadata,guard,guard,guard,guard,guard,guard,guard,guard,u64(unsafe{&result[1]}),guard,u64(0x5021)]!;mut output:=[6]u64{};probe(unsafe{&input[0]},entry,unsafe{&output[0]});assert output[4]==guard&&output[5]==0x5021&&result[0]==0xcafe&&result[4]==0xbeef
		key:=result[1];function:=result[2]&0x0000ffffffffffff;context:=result[3];assert key!=0&&function!=0&&context!=0;if canonical==0{canonical=key}else{assert key==canonical};before:=count(context);assert before>0&&before<1000
		for enabled in [u8(0),1]!{mut value:=[u8(0xa5),enabled,0xa5]!;call(u64(unsafe{&value[1]}),context,function);assert value==[u8(0xa5),if disabled==1{u8(0)}else{enabled},0xa5]!;println('NATIVE-SWIFTUI-VIEW-DISABLED-TRUTH disabled='+disabled.str()+' enabled='+enabled.str()+' result='+value[1].str())}
		mut other:=[u64(0xcafe),0,0,0,0xbeef]!;assert witness_copy(u64(unsafe{&other[1]}),u64(unsafe{&result[1]}),modified.metadata)==u64(unsafe{&other[1]})&&count(context)==before+1&&other==result;destroy(u64(unsafe{&other[1]}),modified.metadata);assert count(context)==before;destroy(u64(unsafe{&result[1]}),modified.metadata)
	}
	assert C.dlclose(core)==0&&C.dlclose(ui)==0
	println('NATIVE-SWIFTUI-VIEW-DISABLED: owned writable key path and captured transform, three native layouts, four inherited-enabled truth cases, canonical key identity, balanced copy/destroy ownership and x20/x21 preservation; no graph or application code executed')
}

fn view_disabled_resolve()u64{return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI',view_disabled_symbol) or {panic(err)}}
fn view_disabled_reject(probe ViewDisabledProbe,entry u64,raw_bool u64,guard u64,result u64,self_value u64){
	mut fds:=[2]i32{};assert C.pipe(unsafe{&fds[0]})==0;pid:=C.ios_fork();assert pid>=0
	if pid==0{C.close(fds[0]);assert C.dup2(fds[1],2)==2;C.close(fds[1]);input:=[raw_bool,guard,guard,guard,guard,guard,guard,guard,guard,guard,result,self_value,guard]!;mut output:=[6]u64{};probe(unsafe{&input[0]},entry,unsafe{&output[0]});C._exit(0)}
	C.close(fds[1]);mut bytes:=[16384]u8{};mut length:=0;for{assert length<bytes.len;n:=C.read(fds[0],unsafe{&bytes[length]},usize(bytes.len-length));if n==0{break};if n<0&&unsafe{*C.ios_errno_address()}==C.EINTR{continue};assert n>0;length+=int(n)};C.close(fds[0]);mut status:=i32(0);assert C.ios_waitpid(pid,&status,0)==pid&&status==256
	output:=unsafe{tos(&bytes[0],length)};assert output.contains(view_disabled_diagnostic);for bad in ['runtime error:','AddressSanitizer','Segmentation fault','SIGSEGV','SIGBUS','View.opacity result size overflow','environment transform generic instantiation is not implemented']!{assert !output.contains(bad),output}
}
fn view_disabled_reader()u64{entry:=view_disabled_resolve();for _ in 0..1024{assert view_disabled_resolve()==entry};return entry}
__global view_disabled_callbacks=0
fn view_disabled_callback(object u64,selector &char){assert ios_runtime.swift_concurrency_retired;expected:=swiftui_view_disabled_symbol(view_disabled_symbol) or {panic('disabled binding')};assert view_disabled_resolve()==expected;view_disabled_callbacks++}

fn test_swiftui_view_disabled(){
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));shared_base:=u64(C.mmap(unsafe{nil},page*3,C.PROT_NONE,C.MAP_SHARED|C.MAP_ANONYMOUS,-1,0));assert code!=u64(-1)&&guard!=u64(-1)&&shared_base!=u64(-1);shared:=shared_base+u64(page)
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0003f1,0xaa0103f0,0xaa0203f3,0xd10043ff,0xa9400620,0xa9410e22,0xa9421624,0xa9431e26,0xa9442a29,0xa9002be9,0xf9402a28,0xf9402e34,0xf9403235,0xd63f0200,0xa9000660,0xa9010e62,0xa9025674,0x910043ff,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
	for i,op in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0xaa0103f4,0xaa0203f0,0xd63f0200,0xa94153f3,0xa9425bf5,0xa8c37bfd,0xd65f03c0]!{write32(code+128+u64(i*4),op)}
	C.__builtin___clear_cache(voidptr(code),voidptr(code+168));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0;probe:=unsafe{ViewDisabledProbe(voidptr(code))};call:=unsafe{ViewDisabledClosure(voidptr(code+128))}
	$if macos{view_disabled_native(probe,call,guard)}
	entry:=view_disabled_resolve()
	for wrong in [view_disabled_symbol+'Extra',view_disabled_symbol.replace('$s7SwiftUI','$s11SwiftUICore'),view_disabled_symbol.replace('4ViewP','12ViewModifierP'),view_disabled_symbol.replace('8disabled','7opacity')]!{if _:=swiftui_view_disabled_symbol(wrong){assert false}}
	for _ in 0..2{
		objc_start();mut workers:=[]thread u64{};for _ in 0..8{workers<<spawn view_disabled_reader()};for worker in workers{assert worker.wait()==entry};unsafe{workers.free()}
		for library in ['/usr/lib/swift/libswiftCore.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']!{if _:=runtime_symbol(library,view_disabled_symbol){assert false}}
		for raw_bool in [u64(0),1,255,~u64(0)]!{for self_value in [u64(0),guard,~u64(0)]!{
			view_disabled_reject(probe,entry,raw_bool,guard,guard,self_value);assert C.mprotect(voidptr(shared),page,C.PROT_READ|C.PROT_WRITE)==0;C.memset(voidptr(shared),0xa5,page)
			for writable in [true,false]!{assert C.mprotect(voidptr(shared),page,C.PROT_READ|if writable{C.PROT_WRITE}else{0})==0;for result in [shared,shared+u64(page)-128]!{view_disabled_reject(probe,entry,raw_bool,guard,result,self_value);for i in u64(0)..u64(page){assert unsafe{*(&u8(shared+i))}==0xa5}}}
		}}
		assert ios_runtime.swift_heap.len==0&&ios_runtime.swift_arrays.len==0&&ios_runtime.swift_buffers.len==0&&ios_runtime.live==0&&ios_runtime.swiftui_environment_transform_arena==0&&ios_runtime.swiftui_modified_arena==0&&ios_runtime.swiftui_opacity_arena==0
		cls:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixViewDisabledCallback',0);assert cls!=0&&objc_add_method(cls,u64(c'dealloc'),u64(unsafe{voidptr(view_disabled_callback)}),c'v16@0:8');objc_register_class(cls);objc_autorelease(objc_new(cls));before:=view_disabled_callbacks;ios_runtime.swift_concurrency_retired=true;objc_stop();assert view_disabled_callbacks==before+1&&ios_runtime.live==0
		assert view_disabled_resolve()==entry;for raw_bool in [u64(0),1,255,~u64(0)]!{view_disabled_reject(probe,entry,raw_bool,guard,guard,guard)}
	}
	assert C.munmap(voidptr(code),page)==0&&C.munmap(voidptr(guard),page)==0&&C.munmap(voidptr(shared_base),page*3)==0
	println('IOS-SWIFTUI-VIEW-DISABLED: diagnostic binding only, 128 child calls exit 1, four Bool register patterns, protected metadata/View table/stack/Self/x8, unchanged shared writable/read-only result pages at both guard boundaries, eight readers, exact framework routing, callbacks and two drained runtime lifetimes; key paths, environment transform construction and rendering remain unsupported')
}
