// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#include <sys/sysctl.h>
	#include <net/route.h>
}
struct C.rt_msghdr2 {
	rtm_msglen u16
	rtm_flags i32
	rtm_addrs i32
}
fn C.sysctl(&i32,u32,voidptr,&usize,voidptr,usize)i32

struct ReachabilityContext { version i64 info voidptr retain u64 release u64 description u64 }
type ReachabilityRetain = fn (voidptr) voidptr
type ReachabilityRelease = fn (voidptr)
type ReachabilityCallback = fn (u64,u32,voidptr)
@[heap]
struct ReachabilityClient {
mut:
	refs int = 1
	callback u64
	info voidptr
	release u64
}
@[heap]
struct ReachabilityState {
mut:
	address [28]u8
	name &char = unsafe { nil }
	client &ReachabilityClient = unsafe { nil }
	queue u64
	run_loop bool
	common_mode bool
	generation u64
	flags u32
	known bool
	pending bool
}
@[heap]
struct ReachabilityRuntime {
mut:
	targets [64]u64 // Each scheduled slot owns one reference, independent of work.
	worker usize
	started bool
	stopping bool
}
@[heap]
struct ReachabilityWork { target u64 generation u64 flags u32 }
__global reachability_runtime = unsafe { &ReachabilityRuntime(nil) }

// These readers also accept unaligned caller and route-message bytes.
fn reachability_word(bytes u64, offset u64, size u32) u32 {
	mut result:=u32(0)
	for i in u32(0)..size { result|=u32(unsafe{*(&u8(bytes+offset+i))})<<(i*8) }
	return result
}
fn reachability_zero(bytes u64, offset u32, size u32) bool {
	for i in u32(0)..size { if unsafe{*(&u8(bytes+offset+i))}!=0 { return false } }
	return true
}
fn reachability_interface_up(index u32) bool {
	mut list:=unsafe{&C.ifaddrs(nil)}
	if C.getifaddrs(unsafe{&list})!=0 { return false }
	defer { C.freeifaddrs(list) }
	mut current:=list
	for current!=unsafe{nil} {
		if current.ifa_flags&u32(C.IFF_UP)!=0 && C.if_nametoindex(current.ifa_name)==index { return true }
		current=current.ifa_next
	}
	return false
}
// Default-address queries inspect the actual route table, without DNS or a
// probe packet. Ordinary UDP connect below likewise sends no application data.
fn reachability_default() ?u32 {
	$if linux {
		fd:=C.socket(16,2,0) // AF_NETLINK, SOCK_DGRAM, NETLINK_ROUTE
		if fd<0 { return none }
		defer { C.close(fd) }
		mut request:=[28]u8{}
		request[0]=28;request[4]=26;request[6]=1;request[7]=3;request[8]=1
		mut destination:=[12]u8{};destination[0]=16
		if C.sendto(fd,unsafe{&request[0]},28,C.MSG_DONTWAIT,unsafe{voidptr(&destination[0])},12)!=28 { return none }
		mut buffer:=[4096]u64{}
		base:=u64(unsafe{&buffer[0]});mut result:=u32(0);deadline:=darwin_mach_absolute_time()+1000000000
		for _ in 0..64 {
			now:=darwin_mach_absolute_time();if now>=deadline { return none }
			mut wait:=C.pollfd{fd:fd,events:1}
			if C.poll(unsafe{&wait},1,i32((deadline-now+999999)/1000000))!=1 || wait.revents&1==0 { return none }
			received:=C.recv(fd,unsafe{&buffer[0]},sizeof(buffer),C.MSG_TRUNC|C.MSG_DONTWAIT)
			if received<16 || received>isize(sizeof(buffer)) { return none }
			mut cursor:=u64(0)
			for cursor+16<=u64(received) {
				length:=u64(reachability_word(base,cursor,4));kind:=reachability_word(base,cursor+4,2)
				if length<16 || length>u64(received)-cursor { return none }
				if kind==3 { return result }
				if kind==2 { return none }
				if kind==24 && length>=28 && reachability_word(base,cursor+17,2)==0 && reachability_word(base,cursor+23,1)==1 {
					family:=reachability_word(base,cursor+16,1);mut table:=reachability_word(base,cursor+20,1);mut index:=u32(0);mut default_route:=true
					mut at:=cursor+28
					for at+4<=cursor+length {
						size:=u64(reachability_word(base,at,2));tag:=reachability_word(base,at+2,2)
						if size<4 || size>cursor+length-at { return none }
						if tag==4 && size>=8 { index=reachability_word(base,at+4,4) }
						if tag==15 && size>=8 { table=reachability_word(base,at+4,4) }
						if tag==1 && !reachability_zero(base+at,4,u32(size-4)) { default_route=false }
						at+=(size+3)&~u64(3)
					}
					if family in [u32(2),10]! && table==254 && default_route && index!=0 && reachability_interface_up(index) { result=2 }
				}
				cursor+=(length+3)&~u64(3)
			}
		}
		return none
	}
	$if macos {
		mut mib:=[i32(C.CTL_NET),i32(C.PF_ROUTE),i32(0),i32(0),i32(C.NET_RT_DUMP2),i32(0)]!
		mut size:=usize(0)
		if C.sysctl(unsafe{&mib[0]},6,unsafe{nil},unsafe{&size},unsafe{nil},0)!=0 || size>4194304 { return none }
		if size==0 { return u32(0) }
		data:=C.malloc(size);if data==unsafe{nil} { return none };defer { C.free(data) }
		if C.sysctl(unsafe{&mib[0]},6,data,unsafe{&size},unsafe{nil},0)!=0 { return none }
		base:=u64(data);mut cursor:=u64(0)
		for cursor+sizeof(C.rt_msghdr2)<=size {
			header:=unsafe{&C.rt_msghdr2(base+cursor)};length:=u64(header.rtm_msglen)
			if length<sizeof(C.rt_msghdr2) || length>size-cursor { return none }
			if header.rtm_flags&1!=0 && header.rtm_flags&(4|8|0x1000)==0 && header.rtm_addrs&5==5 {
				mut at:=cursor+sizeof(C.rt_msghdr2);mut destination:=false;mut mask:=false
				for bit in 0..8 {
					if header.rtm_addrs&(1<<bit)==0 { continue }
					if at+2>cursor+length { return none }
					bytes:=reachability_word(base,at,1);family:=reachability_word(base,at+1,1)
					if u64(bytes)>cursor+length-at { return none }
					if bit==0 { destination=(family==2 && bytes>=8 && reachability_zero(base+at,4,4)) || (family==30 && bytes>=24 && reachability_zero(base+at,8,16)) }
					if bit==2 { mask=bytes<=2 || reachability_zero(base+at,2,bytes-2) }
					at+=if bytes==0{u64(4)}else{u64((bytes+3)&~u32(3))}
				}
				if destination && mask { return u32(2) }
			}
			cursor+=length
		}
		return u32(0)
	}
	return none
}
fn reachability_mask_byte(mask u64, offset u32) u8 {
	$if macos { if offset>=reachability_word(mask,0,1) { return 0 } }
	return unsafe{*(&u8(mask+offset))}
}
fn reachability_address_flags(address &u8) ?u32 {
	family:=unsafe{address[1]};offset:=if family==2{u32(4)}else{u32(8)};size:=if family==2{u32(4)}else{u32(16)}
	if reachability_zero(u64(address),offset,size) { return reachability_default() }
	mut storage:=[4]u64{}
	length:=if family==2{u32(16)}else{u32(28)}
	if !socket_address_in(address,length,unsafe{&storage[0]}) { return none }
	// A nonzero port avoids platform-specific treatment of port zero.
	unsafe { (&u8(&storage[0]))[2]=0;(&u8(&storage[0]))[3]=9 }
	fd:=C.socket(socket_native_family(int(family)),C.SOCK_DGRAM,0)
	if fd<0 {
		err:=unsafe{*C.ios_errno_address()}
		if err==C.EAFNOSUPPORT || err==C.EPROTONOSUPPORT { return u32(0) }
		return none
	}
	defer { C.close(fd) }
	if C.connect(fd,unsafe{voidptr(&storage[0])},length)!=0 {
		err:=unsafe{*C.ios_errno_address()}
		if err==C.ENETUNREACH || err==C.EHOSTUNREACH || err==C.EADDRNOTAVAIL { return u32(0) }
		return none
	}
	mut result:=u32(2);mut list:=unsafe{&C.ifaddrs(nil)}
	if C.getifaddrs(unsafe{&list})!=0 { return none }
	defer { C.freeifaddrs(list) }
	mut current:=list
	for current!=unsafe{nil} {
		pointer:=current.ifa_addr;mask:=current.ifa_netmask
		if pointer!=unsafe{nil} && current.ifa_flags&u32(C.IFF_UP)!=0 {
			mut native_family:=u32(0)
			$if macos { native_family=reachability_word(u64(pointer),1,1) }
			$if linux { native_family=reachability_word(u64(pointer),0,2) }
			if native_family==u32(socket_native_family(int(family))) {
				mut local:=true;mut direct:=mask!=unsafe{nil}
				$if macos { if direct && reachability_word(u64(mask),0,1)==0 { direct=false } }
				for i in u32(0)..size {
					remote:=unsafe{address[offset+i]};own:=unsafe{*(&u8(u64(pointer)+offset+i))}
					if own!=remote { local=false }
					if direct && (own^remote)&reachability_mask_byte(u64(mask),offset+i)!=0 { direct=false }
				}
				if local { result|=0x10000 }
				if direct { result|=0x20000 }
			}
		}
		current=current.ifa_next
	}
	return result
}
fn reachability_header(target u64) ?&ObjHeader {
	if target==0 || target !in ios_runtime.objects { return none }
	header:=obj_header(target)
	if header.cls!=ios_runtime.names['VinixReachability'] || header.reachability==unsafe{nil} { return none }
	return header
}
fn reachability_allocate() u64 {
	if reachability_runtime==unsafe{nil} { reachability_runtime=&ReachabilityRuntime{} }
	if reachability_runtime.stopping { return 0 }
	target:=objc_allocate(ios_runtime.names['VinixReachability']);obj_header(target).reachability=&ReachabilityState{}
	return target
}
fn reachability_address(_allocator u64, address &u8) u64 {
	if address==unsafe{nil} { return 0 }
	family:=unsafe{address[1]};length:=if family==2{u8(16)}else if family==30{u8(28)}else{return 0}
	if unsafe{address[0]}<length { return 0 }
	C.ios_objc_initialize_lock();defer { C.ios_objc_initialize_unlock() }
	target:=reachability_allocate();if target==0 { return 0 }
	mut state:=obj_header(target).reachability
	unsafe { C.memcpy(&state.address[0],address,length);state.address[0]=length }
	return target
}
fn reachability_name(_allocator u64, name &char) u64 {
	if name==unsafe{nil} { return 0 }
	length:=C.strnlen(name,1025);if length==0 || length>1024 { return 0 }
	C.ios_objc_initialize_lock();defer { C.ios_objc_initialize_unlock() }
	target:=reachability_allocate();if target==0 { return 0 };mut state:=obj_header(target).reachability
	state.address[0]=16;state.address[1]=2
	if C.inet_pton(C.AF_INET,name,unsafe{&state.address[4]})==1 { return target }
	state.address[0]=28;state.address[1]=30
	if C.inet_pton(C.AF_INET6,name,unsafe{&state.address[8]})==1 { return target }
	if C.strcasecmp(name,c'localhost')==0 || C.strcasecmp(name,c'localhost.')==0 {
		state.address=[28]u8{};state.address[0]=16;state.address[1]=2;state.address[4]=127;state.address[7]=1;return target
	}
	state.name=C.strdup(name);if state.name==unsafe{nil} { objc_release(target);return 0 };return target
}
fn reachability_flags(target u64, flags &u32) bool {
	if flags==unsafe{nil} { return false }
	C.ios_objc_initialize_lock()
	header:=reachability_header(target) or { C.ios_objc_initialize_unlock();return false }
	state:=header.reachability
	if state.name!=unsafe{nil} && state.queue!=0 && state.known { unsafe{*flags=state.flags};C.ios_objc_initialize_unlock();return true }
	objc_retain(target);C.ios_objc_initialize_unlock();defer { objc_release(target) }
	value:=if state.name==unsafe{nil}{reachability_address_flags(unsafe{&state.address[0]})}else{reachability_default()} or { return false }
	unsafe { *flags=value };return true
}
fn reachability_client_drop(client &ReachabilityClient) {
	if client==unsafe{nil} { return }
	C.ios_objc_initialize_lock();mut owned:=unsafe{&ReachabilityClient(client)};owned.refs--;last:=owned.refs==0;C.ios_objc_initialize_unlock()
	if last { if client.release!=0 { unsafe{ReachabilityRelease(voidptr(client.release))(client.info)} };unsafe{free(client)} }
}
fn reachability_callback(target u64, callback u64, context &ReachabilityContext) bool {
	C.ios_objc_initialize_lock()
	header:=reachability_header(target) or { C.ios_objc_initialize_unlock();return false }
	objc_retain(target);C.ios_objc_initialize_unlock()
	mut client:=&ReachabilityClient{callback:callback}
	if context!=unsafe{nil} {
		mut snapshot:=ReachabilityContext{};unsafe{C.memcpy(&snapshot,context,sizeof(snapshot))}
		client.info=snapshot.info;client.release=snapshot.release
		if snapshot.retain!=0 { client.info=unsafe{ReachabilityRetain(voidptr(snapshot.retain))(snapshot.info)} }
	}
	C.ios_objc_initialize_lock();mut state:=header.reachability;previous:=state.client;state.client=client;state.generation++;state.pending=false;C.ios_objc_initialize_unlock()
	reachability_client_drop(previous);objc_release(target);return true
}
fn reachability_work_drop(context voidptr) {
	work:=unsafe{&ReachabilityWork(context)};objc_release(work.target);unsafe{free(work)}
}
fn reachability_deliver(context voidptr) {
	work:=unsafe{&ReachabilityWork(context)};C.ios_objc_initialize_lock()
	header:=reachability_header(work.target) or { C.ios_objc_initialize_unlock();return }
	mut state:=header.reachability;client:=state.client
	if state.queue==0 || state.generation!=work.generation || client==unsafe{nil} || client.callback==0 { C.ios_objc_initialize_unlock();return }
	state.pending=false;value:=state.flags;mut owned:=unsafe{&ReachabilityClient(client)};owned.refs++;C.ios_objc_initialize_unlock()
	unsafe { ReachabilityCallback(voidptr(client.callback))(work.target,value,client.info) }
	reachability_client_drop(client)
}
fn reachability_poll_target(target u64) {
	C.ios_objc_initialize_lock();header:=reachability_header(target) or { C.ios_objc_initialize_unlock();return };state:=header.reachability;generation:=state.generation;C.ios_objc_initialize_unlock()
	// Address monitoring is independent of remote server availability. Hostname
	// DNS monitoring is not yet supported, so such scheduling fails explicitly.
	value:=reachability_address_flags(unsafe{&state.address[0]}) or { return }
	reachability_observe(target,generation,value)
}
fn reachability_observe(target u64, generation u64, value u32) {
	C.ios_objc_initialize_lock();defer { C.ios_objc_initialize_unlock() }
	header:=reachability_header(target) or { return }
	mut current:=header.reachability
	if current.queue==0 || generation!=current.generation { return }
	changed:=current.known && current.flags!=value
	current.flags=value;current.known=true
	if changed && !current.pending && current.client!=unsafe{nil} && current.client.callback!=0 {
		current.pending=true
		work:=&ReachabilityWork{objc_retain(target),generation,value}
		dispatch_submit_owned(current.queue,unsafe{voidptr(work)},reachability_deliver,reachability_work_drop)
	}
}
fn reachability_worker(_argument voidptr) voidptr {
	for {
		for i in 0..64 {
			C.ios_objc_initialize_lock()
			if reachability_runtime.stopping { C.ios_objc_initialize_unlock();return unsafe{nil} }
			target:=objc_retain(reachability_runtime.targets[i]);C.ios_objc_initialize_unlock()
			if target!=0 { reachability_poll_target(target);objc_release(target) }
		}
		C.usleep(100000)
	}
	return unsafe{nil}
}
fn reachability_queue(target u64, queue u64) bool {
	mut release_target:=u64(0);mut release_queue:=u64(0)
	C.ios_objc_initialize_lock()
	defer {
		C.ios_objc_initialize_unlock()
		if release_queue!=0 { darwin_dispatch_release(release_queue) }
		objc_release(release_target)
	}
	header:=reachability_header(target) or { return false };mut state:=header.reachability
	if reachability_runtime==unsafe{nil} { return false }
	if reachability_runtime.stopping || state.run_loop { return false }
	if queue==0 {
		if state.queue==0 { return false }
		release_queue=state.queue;release_target=target;state.queue=0;state.generation++;state.pending=false
		for i,item in reachability_runtime.targets { if item==target { reachability_runtime.targets[i]=0;break } }
		return true
	}
	if state.queue!=0 || state.name!=unsafe{nil} || !dispatch_objc_is_queue(queue) { return false }
	mut slot:=-1;for i,item in reachability_runtime.targets { if item==0 { slot=i;break } };if slot<0 { return false }
	// Establish the baseline before the watcher can observe a change.
	value:=reachability_address_flags(unsafe{&state.address[0]}) or { return false }
	state.flags=value;state.known=true;state.queue=queue;state.generation++;darwin_dispatch_retain(queue)
	reachability_runtime.targets[slot]=objc_retain(target)
	if !reachability_runtime.started {
		if darwin_pthread_create(unsafe{voidptr(&reachability_runtime.worker)},unsafe{nil},unsafe{voidptr(reachability_worker)},unsafe{nil})!=0 {
			reachability_runtime.targets[slot]=0;state.queue=0;release_queue=queue;release_target=target;return false
		}
		reachability_runtime.started=true
	}
	return true
}
fn reachability_schedule(target u64, loop u64, mode u64) bool {
	C.ios_objc_initialize_lock();defer { C.ios_objc_initialize_unlock() }
	if loop==0 || loop!=ios_runtime.run_loop || mode==0 || !objc_is_kind(mode,ios_runtime.names['NSString']) { return false }
	if string_text(mode) !in ['kCFRunLoopDefaultMode','kCFRunLoopCommonModes']! { return false }
	if !reachability_queue(target,darwin_dispatch_get_main_queue()) { return false }
	mut state:=obj_header(target).reachability;state.run_loop=true;state.common_mode=string_text(mode)=='kCFRunLoopCommonModes';return true
}
fn reachability_unschedule(target u64, loop u64, mode u64) bool {
	C.ios_objc_initialize_lock()
	header:=reachability_header(target) or { C.ios_objc_initialize_unlock();return false };mut state:=header.reachability
	if !state.run_loop || loop==0 || loop!=ios_runtime.run_loop || mode==0 || !objc_is_kind(mode,ios_runtime.names['NSString']) { C.ios_objc_initialize_unlock();return false }
	if string_text(mode) !in ['kCFRunLoopDefaultMode','kCFRunLoopCommonModes']! || state.common_mode!=(string_text(mode)=='kCFRunLoopCommonModes') { C.ios_objc_initialize_unlock();return false }
	state.run_loop=false;objc_retain(target);C.ios_objc_initialize_unlock()
	result:=reachability_queue(target,0);objc_release(target);return result
}
fn reachability_dispose(mut header ObjHeader) {
	state:=header.reachability;if state==unsafe{nil} { return }
	if state.queue!=0 { panic('iOS: scheduled reachability lost its owner') }
	header.reachability=unsafe{nil};reachability_client_drop(state.client);C.free(state.name);unsafe{free(state)}
}
fn reachability_stop() {
	if reachability_runtime==unsafe{nil} { return }
	C.ios_objc_initialize_lock();reachability_runtime.stopping=true;C.ios_objc_initialize_unlock()
	if reachability_runtime.started && C.pthread_join(unsafe{voidptr(reachability_runtime.worker)},unsafe{nil})!=0 { panic('iOS: cannot join reachability monitor') }
	reachability_runtime.started=false
	for i in 0..64 {
		mut queue:=u64(0);C.ios_objc_initialize_lock();target:=reachability_runtime.targets[i]
		if target!=0 {
			mut state:=obj_header(target).reachability;queue=state.queue;state.queue=0;state.run_loop=false;state.generation++;state.pending=false;reachability_runtime.targets[i]=0
		}
		C.ios_objc_initialize_unlock()
		if queue!=0 { darwin_dispatch_release(queue) }
		objc_release(target)
	}
}
fn reachability_free() {
	if reachability_runtime==unsafe{nil} { return }
	unsafe{free(reachability_runtime)};reachability_runtime=unsafe{nil}
}
fn reachability_id() u64 { return ios_runtime.names['VinixReachability'] }
fn reachability_symbol(symbol string) ?u64 {
	return match symbol {
		'_SCNetworkReachabilityCreateWithAddress' { u64(unsafe{voidptr(reachability_address)}) }
		'_SCNetworkReachabilityCreateWithName' { u64(unsafe{voidptr(reachability_name)}) }
		'_SCNetworkReachabilityGetFlags' { u64(unsafe{voidptr(reachability_flags)}) }
		'_SCNetworkReachabilityGetTypeID' { u64(unsafe{voidptr(reachability_id)}) }
		'_SCNetworkReachabilitySetCallback' { u64(unsafe{voidptr(reachability_callback)}) }
		'_SCNetworkReachabilitySetDispatchQueue' { u64(unsafe{voidptr(reachability_queue)}) }
		'_SCNetworkReachabilityScheduleWithRunLoop' { u64(unsafe{voidptr(reachability_schedule)}) }
		'_SCNetworkReachabilityUnscheduleFromRunLoop' { u64(unsafe{voidptr(reachability_unschedule)}) }
		else { none }
	}
}
