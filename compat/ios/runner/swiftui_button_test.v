// SPDX-License-Identifier: GPL-2.0-or-later
module main
#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.dlclose(voidptr)i32
const button_symbol='_$s7SwiftUI6ButtonV6action5labelACyxGyyc_xyXEtcfC'
const button_diagnostic='iOS: SwiftUI Button action/label construction is not implemented'
type ButtonProbe=fn(&u64,u64,&u64)
type ButtonSign=fn(u64,u64)u64
struct ButtonResponse { metadata u64 state u64 }
struct ButtonWords { first u64 second u64 }
type ButtonMetadata=fn(u64,u64,u64)ButtonResponse
type ButtonCString=fn(&u8)ButtonWords
type ButtonCount=fn(u64)u64
type ButtonRetain=fn(u64)u64
type ButtonRelease=fn(u64)
type ButtonCopy=fn(u64,u64,u64)u64
type ButtonDestroy=fn(u64,u64)
__global button_label_calls=0
__global button_action_calls=0
__global button_label_result=u64(0)
__global button_label_context=u64(0)
__global button_action_context=u64(0)
__global button_rejection_marker=u64(0)
fn button_label(context u64,result u64){if button_rejection_marker!=0{unsafe{*(&u64(button_rejection_marker))|=2};return};assert context==button_label_context&&result==button_label_result;button_label_calls++}
fn button_action(context u64){if button_rejection_marker!=0{unsafe{*(&u64(button_rejection_marker))|=1};return};assert context==button_action_context;button_action_calls++}
fn button_call(probe ButtonProbe,entry u64,input [13]u64){mut output:=[6]u64{};probe(unsafe{&input[0]},entry,unsafe{&output[0]});assert output[4]==input[11]&&output[5]==input[12]}

fn button_native(probe ButtonProbe,code u64,guard u64){
	ui:=C.dlopen(c'/System/Library/Frameworks/SwiftUI.framework/SwiftUI',2);core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);assert ui!=unsafe{nil}&&core!=unsafe{nil};entry:=u64(C.dlsym(ui,unsafe{&char(button_symbol.str+1)}));access_entry:=C.dlsym(ui,c'$s7SwiftUI6ButtonVMa');cstring_entry:=C.dlsym(core,c'$sSS7cStringSSSPys4Int8VG_tcfC');count_entry:=C.dlsym(core,c'swift_retainCount');retain_entry:=C.dlsym(core,c'swift_retain');release_entry:=C.dlsym(core,c'swift_release');assert entry!=0&&access_entry!=unsafe{nil}&&cstring_entry!=unsafe{nil}&&count_entry!=unsafe{nil}&&retain_entry!=unsafe{nil}&&release_entry!=unsafe{nil};access:=unsafe{ButtonMetadata(access_entry)};mut metadata:=u64(0)
	for pair in [[c'$s7SwiftUI9EmptyViewVN',c'$s7SwiftUI9EmptyViewVAA0D0AAWP']!,[c'$s7SwiftUI4TextVN',c'$s7SwiftUI4TextVAA4ViewAAWP']!]!{label:=u64(C.dlsym(ui,pair[0]));witness:=u64(C.dlsym(ui,pair[1]));assert label!=0&&witness!=0;response:=access(0,label,witness);assert response.state==0&&read64(response.metadata+16)==label&&read64(response.metadata+24)==witness;vw:=read64(response.metadata-8);assert read32(response.metadata+32)==0&&read32(response.metadata+36)==8&&read32(response.metadata+40)>=24;println('NATIVE-SWIFTUI-BUTTON-LAYOUT '+unsafe{pair[0].vstring()}+' size='+read64(vw+64).str()+' stride='+read64(vw+72).str()+' fields=0,8,'+read32(response.metadata+40).str());if metadata==0{metadata=response.metadata}}
	label:=read64(metadata+16);witness:=read64(metadata+24);vw:=read64(metadata-8);stride:=read64(vw+72);label_offset:=u64(read32(metadata+40));assert read64(vw+64)==label_offset&&stride>=label_offset&&read64(read64(label-8)+64)==0;page:=usize(C.getpagesize());base:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=u64(-1);C.memset(voidptr(base),0xa5,page);result:=base+16;copy_result:=result+stride+16
	words:=unsafe{ButtonCString(cstring_entry)(c'a native owned Button action context longer than fifteen bytes')};owner:=words.second;count:=unsafe{ButtonCount(count_entry)};retain:=unsafe{ButtonRetain(retain_entry)};release:=unsafe{ButtonRelease(release_entry)};before:=count(owner);assert before>0&&before<1000&&retain(owner)==owner&&count(owner)==before+1
	sign:=unsafe{ButtonSign(voidptr(code+224))};action:=sign(code+192,29199);label_function:=sign(code+128,29199);button_label_result=result+label_offset;button_label_context=guard;button_action_context=owner;labels:=button_label_calls;actions:=button_action_calls
	input:=[action,owner,label_function,guard,label,witness,guard,guard,guard,guard,result,guard,u64(0x5021)]!;button_call(probe,entry,input);assert button_label_calls==labels+1&&button_action_calls==actions&&count(owner)==before+1&&read64(result+8)==action&&read64(result+16)==owner&&unsafe{*(&u8(result))}==4
	for i in u64(0)..8{assert unsafe{*(&u8(result-8+i))}==0xa5&&unsafe{*(&u8(result+stride+i))}==0xa5}
	witness_copy:=unsafe{ButtonCopy(voidptr(read64(vw+16)))};destroy:=unsafe{ButtonDestroy(voidptr(read64(vw+8)))};assert witness_copy(copy_result,result,metadata)==copy_result&&read64(copy_result+8)==action&&read64(copy_result+16)==owner&&count(owner)==before+2;destroy(result,metadata);assert count(owner)==before+1&&button_label_calls==labels+1&&button_action_calls==actions
	// Invoke the stored action through its Swift context ABI after the original
	// Button is destroyed; this checks storage lifetime without a UI event loop.
	stored:=read64(copy_result+8)&0x0000ffffffffffff;action_input:=[guard,guard,guard,guard,guard,guard,guard,guard,guard,guard,guard,read64(copy_result+16),u64(0x5021)]!;button_call(probe,stored,action_input);assert button_action_calls==actions+1&&button_label_calls==labels+1&&count(owner)==before+1
	destroy(copy_result,metadata);assert count(owner)==before;release(owner);assert C.munmap(voidptr(base),page)==0&&C.dlclose(core)==0&&C.dlclose(ui)==0
	println('NATIVE-SWIFTUI-BUTTON: two native layouts, label closure evaluated once with borrowed protected context and zero-size result, escaping action context transferred and preserved by copy, balanced destruction, stored action callable after original destruction, x20/x21 preserved; no Button graph, UI events or application code executed')
}

fn button_resolve()u64{return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI',button_symbol) or {panic(err)}}
fn button_reject(probe ButtonProbe,entry u64,pattern u64,guard u64,result u64,self_value u64,code u64,callbacks bool){
	mut fds:=[2]i32{};assert C.pipe(unsafe{&fds[0]})==0;pid:=C.ios_fork();assert pid>=0
	if pid==0{C.close(fds[0]);assert C.dup2(fds[1],2)==2;C.close(fds[1]);input:=[if callbacks{code+192}else{pattern},guard,if callbacks{code+128}else{guard},guard,pattern,guard,guard,guard,guard,guard,result,self_value,guard]!;mut output:=[6]u64{};probe(unsafe{&input[0]},entry,unsafe{&output[0]});C._exit(0)}
	C.close(fds[1]);mut bytes:=[16384]u8{};mut length:=0;for{assert length<bytes.len;n:=C.read(fds[0],unsafe{&bytes[length]},usize(bytes.len-length));if n==0{break};if n<0&&unsafe{*C.ios_errno_address()}==C.EINTR{continue};assert n>0;length+=int(n)};C.close(fds[0]);mut status:=i32(0);assert C.ios_waitpid(pid,&status,0)==pid&&status==256
	output:=unsafe{tos(&bytes[0],length)};assert output.contains(button_diagnostic);for bad in ['runtime error:','AddressSanitizer','Segmentation fault','SIGSEGV','SIGBUS']!{assert !output.contains(bad),output}
}
fn button_reader()u64{entry:=button_resolve();for _ in 0..1024{assert button_resolve()==entry};return entry}
__global button_callbacks=0
fn button_callback(object u64,selector &char){assert ios_runtime.swift_concurrency_retired;expected:=swiftui_button_symbol(button_symbol) or {panic('Button binding')};assert button_resolve()==expected;button_callbacks++}

fn test_swiftui_button(){
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));shared_base:=u64(C.mmap(unsafe{nil},page*3,C.PROT_NONE,C.MAP_SHARED|C.MAP_ANONYMOUS,-1,0));marker:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_SHARED|C.MAP_ANONYMOUS,-1,0));assert code!=u64(-1)&&guard!=u64(-1)&&shared_base!=u64(-1)&&marker!=u64(-1);shared:=shared_base+u64(page)
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0003f1,0xaa0103f0,0xaa0203f3,0xd10043ff,0xa9400620,0xa9410e22,0xa9421624,0xa9431e26,0xa9442a29,0xa9002be9,0xf9402a28,0xf9402e34,0xf9403235,0xd63f0200,0xa9000660,0xa9010e62,0xa9025674,0x910043ff,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
	for i,op in [u32(0xaa1403e0),0xaa0803e1,0x58000090,0xd61f0200]!{write32(code+128+u64(i*4),op)};unsafe{*(&u64(code+152))=u64(voidptr(button_label))}
	for i,op in [u32(0xaa1403e0),0x58000070,0xd61f0200]!{write32(code+192+u64(i*4),op)};unsafe{*(&u64(code+208))=u64(voidptr(button_action))};write32(code+224,0xdac10020);write32(code+228,0xd65f03c0)
	C.__builtin___clear_cache(voidptr(code),voidptr(code+232));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0;probe:=unsafe{ButtonProbe(voidptr(code))}
	$if macos{button_native(probe,code,guard)}
	entry:=button_resolve();button_rejection_marker=marker
	for wrong in [button_symbol+'Extra',button_symbol.replace('$s7SwiftUI','$s11SwiftUICore'),button_symbol.replace('6Button','5Label'),button_symbol.replace('tcfC','tcfU'),'_$s7SwiftUI6ButtonVMa']!{if _:=swiftui_button_symbol(wrong){assert false}}
	for _ in 0..2{
		objc_start();mut workers:=[]thread u64{};for _ in 0..8{workers<<spawn button_reader()};for worker in workers{assert worker.wait()==entry};unsafe{workers.free()}
		for library in ['/usr/lib/swift/libswiftCore.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']!{if _:=runtime_symbol(library,button_symbol){assert false}}
		for pattern in [u64(0),guard,1,~u64(0)]!{for self_value in [u64(0),guard,~u64(0)]!{
			button_reject(probe,entry,pattern,guard,guard,self_value,code,false);assert C.mprotect(voidptr(shared),page,C.PROT_READ|C.PROT_WRITE)==0;C.memset(voidptr(shared),0xa5,page)
			for writable in [true,false]!{assert C.mprotect(voidptr(shared),page,C.PROT_READ|if writable{C.PROT_WRITE}else{0})==0;for result in [shared,shared+u64(page)-128]!{button_reject(probe,entry,pattern,guard,result,self_value,code,false);for i in u64(0)..u64(page){assert unsafe{*(&u8(shared+i))}==0xa5}}}
		}}
		for pattern in [u64(0),guard,1,~u64(0)]!{button_reject(probe,entry,pattern,guard,guard,guard,code,true)};assert read64(marker)==0
		assert ios_runtime.swift_heap.len==0&&ios_runtime.swift_arrays.len==0&&ios_runtime.swift_buffers.len==0&&ios_runtime.live==0&&ios_runtime.swiftui_state_value_arena==0&&ios_runtime.swiftui_state_nominal_arena==0&&ios_runtime.swift_metadata_arena==0
		cls:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixButtonCallback',0);assert cls!=0&&objc_add_method(cls,u64(c'dealloc'),u64(unsafe{voidptr(button_callback)}),c'v16@0:8');objc_register_class(cls);objc_autorelease(objc_new(cls));before:=button_callbacks;ios_runtime.swift_concurrency_retired=true;objc_stop();assert button_callbacks==before+1&&ios_runtime.live==0
		assert button_resolve()==entry;for pattern in [u64(0),guard,1,~u64(0)]!{button_reject(probe,entry,pattern,guard,guard,guard,code,false)}
	}
	assert read64(marker)==0;button_rejection_marker=0;assert C.munmap(voidptr(code),page)==0&&C.munmap(voidptr(guard),page)==0&&C.munmap(voidptr(shared_base),page*3)==0&&C.munmap(voidptr(marker),page)==0
	println('IOS-SWIFTUI-BUTTON: diagnostic binding only, 136 child calls exit 1, protected closures/contexts/Label metadata/View table/stack/Self/x8, valid callbacks never invoked, unchanged shared writable/read-only result pages at both guard boundaries, eight readers, exact routing, callbacks and two drained runtime lifetimes; Button metadata, construction, action storage, graph execution and rendering remain unsupported')
}
