// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.dlclose(voidptr)i32
const view_defaults_symbols = [
	'_$s7SwiftUI4ViewPAAE05_makeC04view6inputsAA01_C7OutputsVAA11_GraphValueVyxG_AA01_C6InputsVtFZ',
	'_$s7SwiftUI4ViewPAAE05_makeC4List4view6inputsAA01_cE7OutputsVAA11_GraphValueVyxG_AA01_cE6InputsVtFZ',
	'_$s7SwiftUI4ViewPAAE14_viewListCount6inputsSiSgAA01_ceF6InputsV_tFZ',
]!
const view_defaults_diagnostics = [
	'iOS: SwiftUI View._makeView graph construction is not implemented',
	'iOS: SwiftUI View._makeViewList graph construction is not implemented',
	'iOS: SwiftUI View._viewListCount graph traversal is not implemented',
]!
type ViewDefaultsProbe = fn(&u64,u64,&u64)
struct ViewDefaultsResponse { metadata u64 state u64 }
type ViewDefaultsAccess = fn(u64)ViewDefaultsResponse
type ViewDefaultsGeneric = fn(u64,u64)ViewDefaultsResponse
type ViewDefaultsLookup = fn(&u8,usize,u64,u64)u64
struct ViewDefaultsLayout { label string size u64 stride u64 flags u32 extra u32 }

fn view_defaults_native() {
	ui:=C.dlopen(c'/System/Library/Frameworks/SwiftUI.framework/SwiftUI',2);core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);assert ui!=unsafe{nil}&&core!=unsafe{nil}
	for symbol in view_defaults_symbols {assert C.dlsym(ui,unsafe{&char(symbol.str+1)})!=unsafe{nil}}
	for layout in [ViewDefaultsLayout{'_ViewInputs',84,88,0x02030007,0x7fffffff},ViewDefaultsLayout{'_ViewOutputs',16,16,0x02010007,0x7fffffff},ViewDefaultsLayout{'_ViewListInputs',129,136,0x02130007,0x7fffffff},ViewDefaultsLayout{'_ViewListOutputs',65,72,0x02030007,254},ViewDefaultsLayout{'_ViewListCountInputs',80,80,0x02030007,0x7ffffffe},ViewDefaultsLayout{'_GraphValue<Int>',4,4,0x02000003,0},ViewDefaultsLayout{'Optional<Int>',9,16,0x00200007,0}]! {
		mut metadata:=u64(0)
		if layout.label=='_GraphValue<Int>' {entry:=C.dlsym(ui,c'$s7SwiftUI11_GraphValueVMa');integer:=u64(C.dlsym(core,c'$sSiN'));assert entry!=unsafe{nil}&&integer!=0;r:=unsafe{ViewDefaultsGeneric(entry)(0,integer)};assert r.state==0;metadata=r.metadata}
		else if layout.label=='Optional<Int>' {entry:=C.dlsym(core,c'swift_getTypeByMangledNameInContext');assert entry!=unsafe{nil};lookup:=unsafe{ViewDefaultsLookup(entry)};name:='SiSg';metadata=lookup(name.str,usize(name.len),0,0)}
		else {symbol:='$s7SwiftUI'+layout.label.len.str()+layout.label+'VMa';entry:=C.dlsym(ui,unsafe{&char(symbol.str)});assert entry!=unsafe{nil};r:=unsafe{ViewDefaultsAccess(entry)(0)};assert r.state==0;metadata=r.metadata}
		assert metadata!=0;w:=read64(metadata-8);assert read64(w+64)==layout.size&&read64(w+72)==layout.stride&&read32(w+80)==layout.flags&&read32(w+84)==layout.extra
		println('NATIVE-SWIFTUI-VIEW-DEFAULTS-LAYOUT '+layout.label+' size='+layout.size.str()+' stride='+layout.stride.str()+' flags='+layout.flags.hex()+' extra='+layout.extra.str())
	}
	assert C.dlclose(core)==0&&C.dlclose(ui)==0
	println('NATIVE-SWIFTUI-VIEW-DEFAULTS: three exports and seven resilient graph/input/output/count metadata layouts inspected; graph factories, count traversal and application code were not executed')
}

fn view_defaults_resolve(index int)u64 {return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI',view_defaults_symbols[index]) or {panic(err)}}
fn view_defaults_reject(probe ViewDefaultsProbe,index int,entry u64,guard u64,result u64,self_value u64) {
	mut fds:=[2]i32{};assert C.pipe(unsafe{&fds[0]})==0;pid:=C.ios_fork();assert pid>=0
	if pid==0 {
		C.close(fds[0]);assert C.dup2(fds[1],2)==2;C.close(fds[1])
		input:=[guard,guard,guard,guard,guard,guard,guard,guard,guard,guard,result,self_value,guard]!
		mut output:=[6]u64{};probe(unsafe{&input[0]},entry,unsafe{&output[0]});C._exit(0)
	}
	C.close(fds[1]);mut bytes:=[16384]u8{};mut length:=0
	for {assert length<bytes.len;count:=C.read(fds[0],unsafe{&bytes[length]},usize(bytes.len-length));if count==0{break};if count<0&&unsafe{*C.ios_errno_address()}==C.EINTR{continue};assert count>0;length+=int(count)}
	C.close(fds[0]);mut status:=i32(0);assert C.ios_waitpid(pid,&status,0)==pid&&status==256
	output:=unsafe{tos(&bytes[0],length)};assert output.contains(view_defaults_diagnostics[index])
	for i,message in view_defaults_diagnostics {if i!=index{assert !output.contains(message)}}
	for bad in ['runtime error:','AddressSanitizer','Segmentation fault','SIGSEGV','SIGBUS']!{assert !output.contains(bad),output}
}
fn view_defaults_reader()u64 {entries:=[view_defaults_resolve(0),view_defaults_resolve(1),view_defaults_resolve(2)]!;for _ in 0..1024{for i in 0..3{assert view_defaults_resolve(i)==entries[i]}};return entries[0]}
__global view_defaults_callback_calls=0
fn view_defaults_callback(object u64,selector &char) {assert ios_runtime.swift_concurrency_retired;for i in 0..3{expected:=swiftui_view_defaults_symbol(view_defaults_symbols[i]) or {panic('default binding')};assert view_defaults_resolve(i)==expected};view_defaults_callback_calls++}

fn test_swiftui_view_defaults() {
	$if macos{view_defaults_native()}
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));shared_base:=u64(C.mmap(unsafe{nil},page*3,C.PROT_NONE,C.MAP_SHARED|C.MAP_ANONYMOUS,-1,0));assert code!=u64(-1)&&guard!=u64(-1)&&shared_base!=u64(-1)
	shared:=shared_base+u64(page)
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0003f1,0xaa0103f0,0xaa0203f3,0xd10043ff,0xa9400620,0xa9410e22,0xa9421624,0xa9431e26,0xa9442a29,0xa9002be9,0xf9402a28,0xf9402e34,0xf9403235,0xd63f0200,0xa9000660,0xa9010e62,0xa9025674,0x910043ff,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
	C.__builtin___clear_cache(voidptr(code),voidptr(code+100));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0;probe:=unsafe{ViewDefaultsProbe(voidptr(code))}
	entries:=[view_defaults_resolve(0),view_defaults_resolve(1),view_defaults_resolve(2)]!;assert entries[0]!=entries[1]&&entries[0]!=entries[2]&&entries[1]!=entries[2]
	for symbol in view_defaults_symbols {for wrong in [symbol+'Extra',symbol.replace('$s7SwiftUI','$s11SwiftUICore'),symbol.replace('$s7SwiftUI4ViewP','$s7SwiftUI12ViewModifierP')]!{if _:=swiftui_view_defaults_symbol(wrong){assert false}}}
	for _ in 0..2 {
		objc_start();mut workers:=[]thread u64{};for _ in 0..8{workers<<spawn view_defaults_reader()};for worker in workers{assert worker.wait()==entries[0]};unsafe{workers.free()}
		for symbol in view_defaults_symbols {for library in ['/usr/lib/swift/libswiftCore.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']!{if _:=runtime_symbol(library,symbol){assert false}}}
		for index,entry in entries {for self_value in [u64(0),guard,~u64(0)]! {
			view_defaults_reject(probe,index,entry,guard,guard,self_value);assert C.mprotect(voidptr(shared),page,C.PROT_READ|C.PROT_WRITE)==0;C.memset(voidptr(shared),0xa5,page)
			for writable in [true,false]! {assert C.mprotect(voidptr(shared),page,C.PROT_READ|if writable{C.PROT_WRITE}else{0})==0;for result in [shared,shared+u64(page)-128]!{view_defaults_reject(probe,index,entry,guard,result,self_value);for i in u64(0)..u64(page){assert unsafe{*(&u8(shared+i))}==0xa5}}}
		}}
		assert ios_runtime.swift_heap.len==0&&ios_runtime.swift_buffers.len==0&&ios_runtime.swift_arrays.len==0&&ios_runtime.live==0
		cls:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixViewDefaultsCallback',0);assert cls!=0&&objc_add_method(cls,u64(c'dealloc'),u64(unsafe{voidptr(view_defaults_callback)}),c'v16@0:8');objc_register_class(cls);objc_autorelease(objc_new(cls));before:=view_defaults_callback_calls
		ios_runtime.swift_concurrency_retired=true;objc_stop();assert view_defaults_callback_calls==before+1&&ios_runtime.live==0
		for index,entry in entries{assert view_defaults_resolve(index)==entry;view_defaults_reject(probe,index,entry,guard,guard,guard)}
	}
	assert C.munmap(voidptr(code),page)==0&&C.munmap(voidptr(guard),page)==0&&C.munmap(voidptr(shared_base),page*3)==0
	println('IOS-SWIFTUI-VIEW-DEFAULTS: three diagnostic bindings only, eight readers and 49152 concurrent resolutions, 96 child calls exit 1 with distinct make/list/count diagnostics, protected graph/inputs/metadata/witness/stack/Self/x8, unchanged shared read-only/writable result pages at both protected boundaries, exact framework routing, callbacks and two drained runtime lifetimes; graph construction, count traversal and rendering remain unsupported')
}
