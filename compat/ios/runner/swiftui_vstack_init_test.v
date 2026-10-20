// SPDX-License-Identifier: GPL-2.0-or-later
module main
#include <dlfcn.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.dlclose(voidptr)i32
const vstack_init_symbol='_$s7SwiftUI6VStackV9alignment7spacing7contentACyxGAA19HorizontalAlignmentV_12CoreGraphics7CGFloatVSgxyXEtcfC'
type VStackInitProbe=fn(&u64,u64,&u64)
type VStackInitSign=fn(u64,u64)u64
struct VStackInitResponse { metadata u64 state u64 }
struct VStackInitWords { first u64 second u64 }
type VStackInitMetadata=fn(u64,u64,u64)VStackInitResponse
type VStackInitCString=fn(&u8)VStackInitWords
type VStackInitCount=fn(u64)u64
type VStackInitKeep=fn(u64)u64
type VStackInitDrop=fn(u64)
type VStackInitCopy=fn(u64,u64,u64)u64
type VStackInitDestroy=fn(u64,u64)
type VStackInitCenter=fn()u64
__global vstack_init_calls=0
__global vstack_init_context=u64(0)
__global vstack_init_result=u64(0)
__global vstack_init_source=u64(0)
__global vstack_init_content_metadata=u64(0)
__global vstack_init_marker=u64(0)
fn vstack_init_content(context u64,result u64){if vstack_init_marker!=0{unsafe{*(&u64(vstack_init_marker))|=1};return};assert context==vstack_init_context&&result!=0;vstack_init_result=result;vstack_init_calls++;if vstack_init_source!=0{transfer:=unsafe{VStackInitCopy(voidptr(read64(read64(vstack_init_content_metadata-8)+16)))};assert transfer(result,vstack_init_source,vstack_init_content_metadata)==result}}
fn vstack_init_call(probe VStackInitProbe,entry u64,input [13]u64)[6]u64{mut output:=[6]u64{};probe(unsafe{&input[0]},entry,unsafe{&output[0]});assert output[4]==input[11]&&output[5]==input[12];return output}
fn vstack_init_native(probe VStackInitProbe,code u64,guard u64){
	ui:=C.dlopen(c'/System/Library/Frameworks/SwiftUI.framework/SwiftUI',2);core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);assert ui!=unsafe{nil}&&core!=unsafe{nil};entry:=u64(C.dlsym(ui,unsafe{&char(vstack_init_symbol.str+1)}));access_entry:=C.dlsym(ui,c'$s7SwiftUI6VStackVMa');center_entry:=C.dlsym(ui,c'$s7SwiftUI19HorizontalAlignmentV6centerACvgZ');assert entry!=0&&access_entry!=unsafe{nil}&&center_entry!=unsafe{nil};access:=unsafe{VStackInitMetadata(access_entry)};center:=unsafe{VStackInitCenter(center_entry)()};sign:=unsafe{VStackInitSign(voidptr(code+224))};builder:=sign(code+128,29199)
	cstring_entry:=C.dlsym(core,c'$sSS7cStringSSSPys4Int8VG_tcfC');count_entry:=C.dlsym(core,c'swift_retainCount');keep_entry:=C.dlsym(core,c'swift_retain');drop_entry:=C.dlsym(core,c'swift_release');text_entry:=u64(C.dlsym(ui,c'$s7SwiftUI4TextV8verbatimACSS_tcfC'));assert cstring_entry!=unsafe{nil}&&count_entry!=unsafe{nil}&&keep_entry!=unsafe{nil}&&drop_entry!=unsafe{nil}&&text_entry!=0;count:=unsafe{VStackInitCount(count_entry)};keep:=unsafe{VStackInitKeep(keep_entry)};drop:=unsafe{VStackInitDrop(drop_entry)}
	for index,pair in [[c'$s7SwiftUI9EmptyViewVN',c'$s7SwiftUI9EmptyViewVAA0D0AAWP']!,[c'$s7SwiftUI4TextVN',c'$s7SwiftUI4TextVAA4ViewAAWP']!]!{
		content:=u64(C.dlsym(ui,pair[0]));witness:=u64(C.dlsym(ui,pair[1]));assert content!=0&&witness!=0;response:=access(0,content,witness);assert response.state==0&&read64(response.metadata+16)==content&&read64(response.metadata+24)==witness&&read32(response.metadata+32)==0;vw:=read64(response.metadata-8);cw:=read64(content-8);stride:=read64(vw+72);offset:=(u64(17)+u64(read32(cw+80)&0xffff))&~u64(read32(cw+80)&0xffff);assert read64(vw+64)==offset+read64(cw+64)
		println('NATIVE-VSTACK-INIT-LAYOUT '+unsafe{pair[0].vstring()}+' size='+read64(vw+64).str()+' stride='+stride.str()+' content-offset='+offset.str())
		page:=usize(C.getpagesize());base:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert base!=u64(-1);result:=base+16;duplicate:=result+stride+16;mut source:=[4]u64{};mut owner:=u64(0)
		if index==1{words:=unsafe{VStackInitCString(cstring_entry)(c'an owned native VStack Content value longer than fifteen bytes')};owner=words.second&0x0fffffffffffffff;assert owner!=0&&count(owner)>0&&count(owner)<1000&&keep(owner)==owner;input:=[words.first,words.second,guard,guard,guard,guard,guard,guard,guard,guard,guard,u64(0x5020),u64(0x5021)]!;native_text:=vstack_init_call(probe,text_entry,input);for i in 0..4{source[i]=native_text[i]};assert source[0]==words.first&&source[1]==words.second&&u8(source[2])==0;vstack_init_source=u64(unsafe{&source[0]})}
		vstack_init_content_metadata=content;vstack_init_context=guard;transfer:=unsafe{VStackInitCopy(voidptr(read64(vw+16)))};destroy:=unsafe{VStackInitDestroy(voidptr(read64(vw+8)))}
		for spacing in [[u64(0x4020000000000000),0]!,[u64(0xc004000000000000),0]!,[u64(0x7ff8000000000042),1]!]!{
			C.memset(voidptr(base),0xa5,page);before:=if owner!=0{count(owner)}else{u64(0)};calls:=vstack_init_calls;vstack_init_result=0;input:=[center,spacing[0],spacing[1],builder,guard,content,witness,guard,guard,guard,result,u64(0x5020),u64(0x5021)]!;vstack_init_call(probe,entry,input);assert vstack_init_result!=0;println('NATIVE-VSTACK-INIT-CONSTRUCTION content='+index.str()+' tag='+spacing[1].str()+' builder-result-is-field='+(vstack_init_result==result+offset).str())
			assert vstack_init_calls==calls+1&&read64(result)==center&&read64(result+8)==spacing[0]&&unsafe{*(&u8(result+16))}==u8(spacing[1]);if owner!=0{assert count(owner)==before+1&&read64(result+offset)==source[0]&&read64(result+offset+8)==source[1]&&unsafe{*(&u8(result+offset+16))}==0&&read64(result+offset+24)==source[3]}
			for i in u64(0)..8{assert unsafe{*(&u8(result-8+i))}==0xa5&&unsafe{*(&u8(result+stride+i))}==0xa5};assert transfer(duplicate,result,response.metadata)==duplicate;if owner!=0{assert count(owner)==before+2};destroy(result,response.metadata);if owner!=0{assert count(owner)==before+1};destroy(duplicate,response.metadata);if owner!=0{assert count(owner)==before};assert vstack_init_calls==calls+1
		}
		if owner!=0{destroy_content:=unsafe{VStackInitDestroy(voidptr(read64(cw+8)))};destroy_content(vstack_init_source,content);assert count(owner)==1;drop(owner)};vstack_init_source=0;assert C.munmap(voidptr(base),page)==0
	}
	vstack_init_content_metadata=0;assert C.dlclose(core)==0&&C.dlclose(ui)==0
	println('NATIVE-SWIFTUI-VSTACK-INIT: seven integer arguments and indirect x8 result, two dependent layouts and six constructions, borrowed protected builder context evaluated once, exact alignment/spacing payload/tag storage, owned Text content copied and balanced across VStack copies/destruction, x20/x21 preserved; no graph, rendering or application code executed')
}
fn vstack_init_resolve()u64{return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI',vstack_init_symbol) or {panic(err)}}
fn vstack_init_reject(probe VStackInitProbe,entry u64,pattern u64,guard u64,result u64,self_value u64,code u64,callback bool){
	mut fds:=[2]i32{};assert C.pipe(unsafe{&fds[0]})==0;pid:=C.ios_fork();assert pid>=0
	if pid==0{C.close(fds[0]);assert C.dup2(fds[1],2)==2;C.close(fds[1]);input:=[pattern,pattern,pattern,if callback{code+128}else{guard},guard,pattern,guard,guard,guard,guard,result,self_value,guard]!;vstack_init_call(probe,entry,input);C._exit(0)}
	C.close(fds[1]);mut bytes:=[16384]u8{};mut length:=0;for{assert length<bytes.len;n:=C.read(fds[0],unsafe{&bytes[length]},usize(bytes.len-length));if n==0{break};if n<0&&unsafe{*C.ios_errno_address()}==C.EINTR{continue};assert n>0;length+=int(n)};C.close(fds[0]);mut status:=i32(0);assert C.ios_waitpid(pid,&status,0)==pid&&status==256
	output:=unsafe{tos(&bytes[0],length)};assert output.contains('iOS: SwiftUI VStack content construction is not implemented');for bad in ['runtime error:','AddressSanitizer','Segmentation fault','SIGSEGV','SIGBUS']!{assert !output.contains(bad),output}
}
fn vstack_init_reader()u64{entry:=vstack_init_resolve();for _ in 0..1024{assert vstack_init_resolve()==entry};return entry}
__global vstack_init_callbacks=0
fn vstack_init_callback(object u64,selector &char){assert ios_runtime.swift_concurrency_retired;expected:=swiftui_vstack_init_symbol(vstack_init_symbol) or {panic('VStack initializer binding')};assert vstack_init_resolve()==expected;vstack_init_callbacks++}
fn test_swiftui_vstack_init(){
	page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));shared_base:=u64(C.mmap(unsafe{nil},page*3,C.PROT_NONE,C.MAP_SHARED|C.MAP_ANONYMOUS,-1,0));marker:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_SHARED|C.MAP_ANONYMOUS,-1,0));assert code!=u64(-1)&&guard!=u64(-1)&&shared_base!=u64(-1)&&marker!=u64(-1);shared:=shared_base+u64(page)
	for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0003f1,0xaa0103f0,0xaa0203f3,0xd10043ff,0xa9400620,0xa9410e22,0xa9421624,0xa9431e26,0xa9442a29,0xa9002be9,0xf9402a28,0xf9402e34,0xf9403235,0xd63f0200,0xa9000660,0xa9010e62,0xa9025674,0x910043ff,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
	for i,op in [u32(0xaa1403e0),0xaa0803e1,0x58000090,0xd61f0200]!{write32(code+128+u64(i*4),op)};unsafe{*(&u64(code+152))=u64(voidptr(vstack_init_content))};write32(code+224,0xdac10020);write32(code+228,0xd65f03c0)
	C.__builtin___clear_cache(voidptr(code),voidptr(code+232));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0;probe:=unsafe{VStackInitProbe(voidptr(code))}
	$if macos{vstack_init_native(probe,code,guard)}
	entry:=vstack_init_resolve();vstack_init_marker=marker
	for wrong in [vstack_init_symbol+'Extra',vstack_init_symbol.replace('$s7SwiftUI','$s11SwiftUICore'),vstack_init_symbol.replace('6VStack','6HStack'),vstack_init_symbol.replace('tcfC','tcfU'),'_$s7SwiftUI6VStackVMa']!{if _:=swiftui_vstack_init_symbol(wrong){assert false}}
	for _ in 0..2{
		objc_start();mut workers:=[]thread u64{};for _ in 0..8{workers<<spawn vstack_init_reader()};for worker in workers{assert worker.wait()==entry};unsafe{workers.free()}
		for library in ['/usr/lib/swift/libswiftCore.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']!{if _:=runtime_symbol(library,vstack_init_symbol){assert false}}
		for pattern in [u64(0),guard,1,~u64(0)]!{for self_value in [u64(0),guard,~u64(0)]!{vstack_init_reject(probe,entry,pattern,guard,guard,self_value,code,false);assert C.mprotect(voidptr(shared),page,C.PROT_READ|C.PROT_WRITE)==0;C.memset(voidptr(shared),0xa5,page);for writable in [true,false]!{assert C.mprotect(voidptr(shared),page,C.PROT_READ|if writable{C.PROT_WRITE}else{0})==0;for result in [shared,shared+u64(page)-128]!{vstack_init_reject(probe,entry,pattern,guard,result,self_value,code,false);for i in u64(0)..u64(page){assert unsafe{*(&u8(shared+i))}==0xa5}}}}}
		for pattern in [u64(0),guard,1,~u64(0)]!{vstack_init_reject(probe,entry,pattern,guard,guard,guard,code,true)};assert read64(marker)==0
		assert ios_runtime.swift_heap.len==0&&ios_runtime.swift_arrays.len==0&&ios_runtime.swift_buffers.len==0&&ios_runtime.live==0&&ios_runtime.swiftui_vstack_arena==0&&ios_runtime.swiftui_tree_arena==0&&ios_runtime.swift_metadata_arena==0
		cls:=objc_allocate_class(ios_runtime.names['NSObject'],c'VinixVStackInitCallback',0);assert cls!=0&&objc_add_method(cls,u64(c'dealloc'),u64(unsafe{voidptr(vstack_init_callback)}),c'v16@0:8');objc_register_class(cls);objc_autorelease(objc_new(cls));before:=vstack_init_callbacks;ios_runtime.swift_concurrency_retired=true;objc_stop();assert vstack_init_callbacks==before+1&&ios_runtime.live==0&&vstack_init_resolve()==entry;for pattern in [u64(0),guard,1,~u64(0)]!{vstack_init_reject(probe,entry,pattern,guard,guard,guard,code,false)}
	}
	assert read64(marker)==0;vstack_init_marker=0;assert C.munmap(voidptr(code),page)==0&&C.munmap(voidptr(guard),page)==0&&C.munmap(voidptr(shared_base),page*3)==0&&C.munmap(voidptr(marker),page)==0
	println('IOS-SWIFTUI-VSTACK-INIT: diagnostic binding only, 136 child calls exit 1, protected builder/context/Content metadata/View witness/stack/Self/x8, arbitrary alignment/spacing bits, valid builder never invoked, unchanged shared writable/read-only result pages at both guard boundaries, eight readers, exact routing, callbacks and two drained runtime lifetimes; VStack construction, Tree specialization, graph execution and rendering remain unsupported')
}
