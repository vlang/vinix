// SPDX-License-Identifier: GPL-2.0-or-later
module main

type ViewListProbe = fn (&u64,u64,&u64)
fn view_list_resolve() u64 {
	return runtime_symbol('/System/Library/Frameworks/SwiftUI.framework/SwiftUI','_$s7SwiftUI19UIViewRepresentablePAAE13_makeViewList4view6inputsAA01_fG7OutputsVAA11_GraphValueVyxG_AA01_fG6InputsVtFZ') or { panic(err) }
}

fn view_list_reject(probe ViewListProbe, entry u64, guard u64, result u64, self_value u64) {
	mut fds := [2]i32{}
	assert C.pipe(unsafe { &fds[0] }) == 0
	pid := C.ios_fork(); assert pid >= 0
	if pid == 0 {
		C.close(fds[0]); assert C.dup2(fds[1],2) == 2; C.close(fds[1])
		input := [guard,guard,guard,guard,result,self_value,guard]!
		mut output := [7]u64{}
		probe(unsafe { &input[0] },entry,unsafe { &output[0] })
		C._exit(0)
	}
	C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
	for {
		assert length < bytes.len
		count := C.read(fds[0],unsafe { &bytes[length] },usize(bytes.len-length))
		if count == 0 { break }
		if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
		assert count > 0; length += int(count)
	}
	C.close(fds[0]); mut status := i32(0)
	assert C.ios_waitpid(pid,&status,0) == pid && status == 256
	output := unsafe { tos(&bytes[0],length) }
	assert output.contains('iOS: SwiftUI UIViewRepresentable view-list graph construction is not implemented')
	for bad in ['runtime error:','AddressSanitizer','Segmentation fault','SIGSEGV','SIGBUS']! { assert !output.contains(bad),output }
}

fn view_list_reader() u64 {
	entry := view_list_resolve()
	for _ in 0..1024 { assert view_list_resolve() == entry }
	return entry
}

__global view_list_callback_calls = 0
fn view_list_callback(object u64, selector &char) {
	assert ios_runtime.swift_concurrency_retired
	assert view_list_resolve() == u64(unsafe { voidptr(swiftui_view_list_unavailable) })
	view_list_callback_calls++
}

fn test_swiftui_view_list() {
	page := usize(C.getpagesize())
	code := u64(C.mmap(unsafe { nil },page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0))
	guard := u64(C.mmap(unsafe { nil },page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0))
	shared := u64(C.mmap(unsafe { nil },page*2,C.PROT_NONE,C.MAP_SHARED|C.MAP_ANONYMOUS,-1,0))
	assert code != u64(-1) && guard != u64(-1) && shared != u64(-1)
	for i,op in [u32(0xa9bd7bfd),0xa90153f3,0xa9025bf5,0xaa0003f1,0xaa0103f0,0xaa0203f3,0xa9400620,0xa9410e22,0xf9401228,0xf9401634,0xf9401a35,0xd63f0200,0xa9000660,0xa9010e62,0xf9001268,0xa902d674,0xa9425bf5,0xa94153f3,0xa8c37bfd,0xd65f03c0]! { write32(code+u64(i*4),op) }
	C.__builtin___clear_cache(voidptr(code),voidptr(code+80))
	assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC) == 0
	probe := unsafe { ViewListProbe(voidptr(code)) }; entry := view_list_resolve()
	for symbol in ['_$s7SwiftUI19UIViewRepresentablePAAE13_makeViewList4view6inputsAA01_fG7OutputsVAA11_GraphValueVyxG_AA01_fG6InputsVtFZExtra','_$s7SwiftUI19NSViewRepresentablePAAE13_makeViewList4view6inputsAA01_fG7OutputsVAA11_GraphValueVyxG_AA01_fG6InputsVtFZ','_$s7SwiftUI19UIViewRepresentablePAAE9_makeView']! { if _ := swiftui_view_list_symbol(symbol) { assert false } }
	for _ in 0..2 {
		objc_start()
		mut workers := []thread u64{}
		for _ in 0..8 { workers << spawn view_list_reader() }
		for worker in workers { assert worker.wait() == entry }; unsafe { workers.free() }
		for library in ['/usr/lib/swift/libswiftCore.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/SwiftUICore.framework/SwiftUICore']! { if _ := runtime_symbol(library,'_$s7SwiftUI19UIViewRepresentablePAAE13_makeViewList4view6inputsAA01_fG7OutputsVAA11_GraphValueVyxG_AA01_fG6InputsVtFZ') { assert false } }
		for self_value in [u64(0),guard,~u64(0)]! {
			view_list_reject(probe,entry,guard,guard,self_value)
			assert C.mprotect(voidptr(shared),page,C.PROT_READ|C.PROT_WRITE) == 0
			C.memset(voidptr(shared),0xa5,page)
			for writable in [true,false]! {
				assert C.mprotect(voidptr(shared),page,C.PROT_READ|if writable { C.PROT_WRITE } else { 0 }) == 0
				view_list_reject(probe,entry,guard,shared+u64(page)-128,self_value)
				for i in u64(0)..u64(page) { assert unsafe { *(&u8(shared+i)) } == 0xa5 }
			}
		}
		assert ios_runtime.swift_heap.len == 0 && ios_runtime.swift_buffers.len == 0 && ios_runtime.live == 0
		cls := objc_allocate_class(ios_runtime.names['NSObject'],c'VinixViewListCallback',0)
		assert cls != 0 && objc_add_method(cls,u64(c'dealloc'),u64(unsafe { voidptr(view_list_callback) }),c'v16@0:8')
		objc_register_class(cls); objc_autorelease(objc_new(cls)); before := view_list_callback_calls
		ios_runtime.swift_concurrency_retired = true; objc_stop()
		assert view_list_callback_calls == before+1 && ios_runtime.live == 0 && view_list_resolve() == entry
		view_list_reject(probe,entry,guard,guard,guard)
	}
	assert C.munmap(voidptr(code),page) == 0 && C.munmap(voidptr(guard),page) == 0 && C.munmap(voidptr(shared),page*2) == 0
	println('IOS-SWIFTUI-VIEW-LIST: diagnostic binding only, eight readers and 16384 concurrent resolutions, 20 child calls exit 1 with the graph diagnostic, protected graph/inputs/metadata/witness/self/x8, unchanged shared read-only/writable result pages at a protected boundary, exact framework routing, callbacks and two drained runtime lifetimes; unary graph construction and application rendering remain unsupported')
}
