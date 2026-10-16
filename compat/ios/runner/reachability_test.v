// SPDX-License-Identifier: GPL-2.0-or-later
module main
import time
#include <dlfcn.h>
fn C.dlopen(&char,int)voidptr
fn C.dlsym(voidptr,&char)voidptr
struct ReachAPI { native bool sc u64 cf u64 }
type ReachMake=fn(u64,voidptr)u64
type ReachFlags=fn(u64,&u32)bool
type ReachSet=fn(u64,u64,voidptr)bool
type ReachQueue=fn(u64,u64)bool
type ReachDrop=fn(u64)
type ReachType=fn()u64
struct ReachProbe {
mut:
	retains i64
	releases i64
	calls i64
	flags u64
	target u64
	thread u64
	replace bool
	replacement &ReachProbe = unsafe { nil }
	queue_label &char = unsafe { nil }
}
fn reach_test_symbol(api ReachAPI, name string, framework string) u64 {
	if api.native { return u64(C.dlsym(unsafe{voidptr(if framework=='CoreFoundation'{api.cf}else{api.sc})},unsafe{&char(name.str+1)})) }
	return runtime_symbol('/System/Library/Frameworks/'+framework+'.framework/'+framework,name) or {panic(err)}
}
fn reach_test_hold(info voidptr) voidptr {
	mut probe:=unsafe{&ReachProbe(info)};C.ios_ref_change(unsafe{&probe.retains},1);return info
}
fn reach_test_drop(info voidptr) {
	mut probe:=unsafe{&ReachProbe(info)};C.ios_ref_change(unsafe{&probe.releases},1)
}
fn reach_test_context(probe &ReachProbe) ReachabilityContext {
	return ReachabilityContext{0,unsafe{voidptr(probe)},u64(unsafe{voidptr(reach_test_hold)}),u64(unsafe{voidptr(reach_test_drop)}),0}
}
fn reach_test_callback(target u64, flags u32, info voidptr) {
	if info==unsafe{nil} { return };mut probe:=unsafe{&ReachProbe(info)}
	if probe.queue_label!=unsafe{nil} { assert C.strcmp(darwin_dispatch_queue_get_label(0),probe.queue_label)==0 }
	C.ios_store_pointer(unsafe{&probe.flags},u64(flags));C.ios_store_pointer(unsafe{&probe.target},target);C.ios_store_pointer(unsafe{&probe.thread},u64(C.pthread_self()))
	if probe.replace {
		context:=reach_test_context(probe.replacement)
		assert reachability_callback(target,u64(unsafe{voidptr(reach_test_callback)}),unsafe{&context})
		assert probe.releases==0 // Executing callback keeps old info alive.
	}
	C.ios_ref_change(unsafe{&probe.calls},1)
}
fn reach_test_barrier(_info voidptr) {}
fn reach_test_api(api ReachAPI) {
	make:=unsafe{ReachMake(voidptr(reach_test_symbol(api,'_SCNetworkReachabilityCreateWithAddress','SystemConfiguration')))}
	name:=unsafe{ReachMake(voidptr(reach_test_symbol(api,'_SCNetworkReachabilityCreateWithName','SystemConfiguration')))}
	flags:=unsafe{ReachFlags(voidptr(reach_test_symbol(api,'_SCNetworkReachabilityGetFlags','SystemConfiguration')))}
	set:=unsafe{ReachSet(voidptr(reach_test_symbol(api,'_SCNetworkReachabilitySetCallback','SystemConfiguration')))}
	drop:=unsafe{ReachDrop(voidptr(reach_test_symbol(api,'_CFRelease','CoreFoundation')))}
	type_id:=unsafe{ReachType(voidptr(reach_test_symbol(api,'_SCNetworkReachabilityGetTypeID','SystemConfiguration')))}
	assert type_id()!=0
	for family in [u8(2),30,1,0]! { for size in [u8(0),1,2,15,16,28,32]! {
		mut bytes:=[32]u8{};bytes[0]=size;bytes[1]=family;target:=make(0,unsafe{&bytes[0]})
		assert (target!=0)==((family==2 && size>=16)||(family==30 && size>=28))
		if target!=0 { drop(target) }
	} }
	assert name(0,c'')==0
	for text in [c'localhost',c'127.0.0.1',c'::1',c'no-such-host.invalid',c'bad name']! {
		target:=name(0,text);assert target!=0;drop(target)
	}
	mut input:=[16]u8{};input[0]=16;input[1]=2;input[4]=127;input[7]=1
	target:=make(0,unsafe{&input[0]});assert target!=0
	// Constructors snapshot the address; subsequent caller changes do not retarget it.
	input[4]=192;input[5]=0;input[6]=2;input[7]=1
	mut value:=u32(0xdeadbeef);assert flags(target,unsafe{&value})&&value==0x30002
	mut first:=ReachProbe{};mut second:=ReachProbe{}
	mut context:=reach_test_context(unsafe{&first});callout:=u64(unsafe{voidptr(reach_test_callback)})
	assert set(target,callout,unsafe{&context});assert first.retains==1&&first.releases==0
	context=reach_test_context(unsafe{&second});assert set(target,callout,unsafe{&context});assert first.releases==1&&second.retains==1
	context=ReachabilityContext{};assert set(target,0,unsafe{&context});assert second.releases==1
	drop(target)
}
fn reach_test_private() {
	mut bytes:=[16]u8{};bytes[0]=16;bytes[1]=2;bytes[4]=127;bytes[7]=1
	target:=reachability_address(0,unsafe{&bytes[0]});assert target!=0
	mut default_address:=[16]u8{};default_address[0]=16;default_address[1]=2
	default_target:=reachability_address(0,unsafe{&default_address[0]});mut default_flags:=u32(0xdeadbeef)
	assert reachability_flags(default_target,unsafe{&default_flags})&&default_flags in [u32(0),2]!
	$if macos {
		api:=ReachAPI{true,u64(C.dlopen(c'/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration',2)),u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',2))}
		make:=unsafe{ReachMake(voidptr(reach_test_symbol(api,'_SCNetworkReachabilityCreateWithAddress','SystemConfiguration')))};query:=unsafe{ReachFlags(voidptr(reach_test_symbol(api,'_SCNetworkReachabilityGetFlags','SystemConfiguration')))};drop:=unsafe{ReachDrop(voidptr(reach_test_symbol(api,'_CFRelease','CoreFoundation')))}
		reference:=make(0,unsafe{&default_address[0]});mut native_flags:=u32(0);assert reference!=0&&query(reference,unsafe{&native_flags});drop(reference);assert default_flags==native_flags
	}
	objc_release(default_target)
	mut value:=u32(0xdeadbeef);assert !reachability_flags(0,unsafe{&value})&&value==0xdeadbeef;assert !reachability_flags(target,unsafe{nil})
	assert reachability_address(0,unsafe{nil})==0&&reachability_name(0,unsafe{nil})==0
	for lib in ['/usr/lib/libSystem.B.dylib','/System/Library/Frameworks/Foundation.framework/Foundation','/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation']! { if _:=runtime_symbol(lib,'_SCNetworkReachabilityGetFlags') { assert false } }
	queue:=darwin_dispatch_get_main_queue();mut probe:=ReachProbe{};context:=reach_test_context(unsafe{&probe})
	assert reachability_callback(target,u64(unsafe{voidptr(reach_test_callback)}),unsafe{&context})
	assert reachability_queue(target,queue)&&!reachability_queue(target,queue)
	// An unchanged snapshot does not synthesize an initial notification.
	time.sleep(150*time.millisecond);dispatch_main_drain();assert probe.calls==0
	C.ios_objc_initialize_lock()
	state:=obj_header(target).reachability;generation:=state.generation
	reachability_observe(target,generation,0);reachability_observe(target,generation,2)
	assert state.pending;assert dispatch_main_drain();assert probe.calls==1&&probe.flags==2&&probe.thread==ios_runtime.main_thread
	// Cancellation invalidates queued notifications; their owned contexts still drain.
	reachability_observe(target,generation,0);assert reachability_queue(target,0);assert dispatch_main_drain();assert probe.calls==1
	C.ios_objc_initialize_unlock()
	assert probe.releases==0;objc_release(target);assert probe.releases==1
	// Replacement from within a callback must defer the old context's final release.
	second_target:=reachability_address(0,unsafe{&bytes[0]});mut replacement:=ReachProbe{};mut old:=ReachProbe{replace:true,replacement:unsafe{&replacement}};old_context:=reach_test_context(unsafe{&old})
	assert reachability_callback(second_target,u64(unsafe{voidptr(reach_test_callback)}),unsafe{&old_context})&&reachability_queue(second_target,queue)
	C.ios_objc_initialize_lock();reachability_observe(second_target,obj_header(second_target).reachability.generation,0);assert dispatch_main_drain();assert old.calls==1&&old.releases==1&&replacement.retains==1;C.ios_objc_initialize_unlock()
	assert reachability_queue(second_target,0);objc_release(second_target);assert replacement.releases==1
	// A background dispatch queue owns delivery; the polling thread never calls app code.
	background:=darwin_dispatch_queue_create(c'vinix.reachability.worker',0);background_target:=reachability_address(0,unsafe{&bytes[0]});mut background_probe:=ReachProbe{queue_label:c'vinix.reachability.worker'};background_context:=reach_test_context(unsafe{&background_probe})
	assert reachability_callback(background_target,u64(unsafe{voidptr(reach_test_callback)}),unsafe{&background_context})&&reachability_queue(background_target,background)
	C.ios_objc_initialize_lock();reachability_observe(background_target,obj_header(background_target).reachability.generation,0);C.ios_objc_initialize_unlock()
	deadline:=darwin_mach_absolute_time()+2000000000
	for C.ios_load_pointer(unsafe{&u64(&background_probe.calls)})==0 { assert darwin_mach_absolute_time()<deadline;time.sleep(time.millisecond) }
	assert reachability_queue(background_target,0);darwin_dispatch_sync_f(background,unsafe{nil},reach_test_barrier)
	assert background_probe.thread!=ios_runtime.main_thread;objc_release(background_target);darwin_dispatch_release(background);assert background_probe.releases==1
	// A scheduled reference outlives its caller until unscheduled.
	owned:=reachability_address(0,unsafe{&bytes[0]});mut lifetime:=ReachProbe{};life_context:=reach_test_context(unsafe{&lifetime});assert reachability_callback(owned,0,unsafe{&life_context})&&reachability_queue(owned,queue);objc_release(owned);assert lifetime.releases==0;assert reachability_queue(owned,0);assert lifetime.releases==1
	// Run-loop scheduling is exclusive with dispatch scheduling and respects its mode.
	loop:=objc_allocate(ios_runtime.names['NSRunLoop']);ios_runtime.run_loop=loop;normal:=owned_string('kCFRunLoopDefaultMode');common:=owned_string('kCFRunLoopCommonModes')
	loop_target:=reachability_address(0,unsafe{&bytes[0]});assert reachability_schedule(loop_target,loop,normal)&&!reachability_queue(loop_target,queue)&&!reachability_unschedule(loop_target,loop,common)&&reachability_unschedule(loop_target,loop,normal);objc_release(loop_target);objc_release(normal);objc_release(common)
	// Generic DNS monitoring fails explicitly; numeric names use address monitoring.
	host:=reachability_name(0,c'no-such-host.invalid');assert !reachability_queue(host,queue);objc_release(host)
	// Pending framework work must release its context even when dispatch stops.
	pending:=reachability_address(0,unsafe{&bytes[0]});mut cancelled:=ReachProbe{};cancel_context:=reach_test_context(unsafe{&cancelled});assert reachability_callback(pending,u64(unsafe{voidptr(reach_test_callback)}),unsafe{&cancel_context})&&reachability_queue(pending,queue)
	C.ios_objc_initialize_lock();reachability_observe(pending,obj_header(pending).reachability.generation,0);objc_release(pending);C.ios_objc_initialize_unlock()
	reachability_stop();dispatch_stop();reachability_free();assert cancelled.calls==0&&cancelled.releases==1
}
fn test_reachability() {
	$if macos {
		api:=ReachAPI{true,u64(C.dlopen(c'/System/Library/Frameworks/SystemConfiguration.framework/SystemConfiguration',2)),u64(C.dlopen(c'/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation',2))};reach_test_api(api)
		println('IOS-REACHABILITY-NATIVE: address validation,loopback flags,immutable targets,names and callback context ownership')
	}
	for _ in 0..2 {
		objc_start();system_data_start() or {panic(err)};reach_test_api(ReachAPI{});reach_test_private();objc_stop();system_data_stop()
		assert ios_runtime.live==0&&ios_runtime.objects.len==0&&reachability_runtime==unsafe{nil}&&dispatch_runtime==unsafe{nil}
	}
	println('IOS-REACHABILITY: actual routes/interfaces,immutable targets,coalesced dispatch changes,cancellation,reentrant context replacement,scheduled ownership,main-run-loop modes and joined shutdown;DNS monitoring remains outside this profile')
}
