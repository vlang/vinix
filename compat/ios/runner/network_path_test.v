// SPDX-License-Identifier: GPL-2.0-or-later
module main
#include <dlfcn.h>
#include <unistd.h>
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.usleep(u32)i32
fn C.__atomic_fetch_add(&u64,u64,int)u64
fn C.__atomic_load_n(&u64,int)u64
fn C.__atomic_store_n(&u64,u64,int)
type NWTMake=fn()u64
type NWTHold=fn(u64)u64
type NWTDrop=fn(u64)
type NWTSet=fn(u64,u64)
type NWTQuery=fn(u64)u32
type NWTCheck=fn(u64)bool
type NWTUses=fn(u64,u32)bool
type NWTName=fn(u64)&char
type NWTQueue=fn(&char,u64)u64
struct NWTDescriptor {reserved u64 size u64 copy u64 dispose u64}
struct NWTBlock {isa u64 flags u32 reserved u32 invoke u64 descriptor u64 info u64}
struct NWTProbe {mut: copies u64 drops u64 calls u64 path u64 interface u64 names u64 limit u64}
__global nwt_native_network=u64(0)
__global nwt_native=false
fn nwt_sym(name &char)voidptr{if nwt_native{return C.dlsym(unsafe{voidptr(nwt_native_network)},name)};return unsafe{voidptr(nw_symbol('_'+ctext(u64(name)))or{panic('missing Network symbol')})}}
fn nwt_block_copy_probe(destination u64,source u64){info:=unsafe{*(&u64(source+32))};unsafe{*(&u64(destination+32))=info};mut p:=unsafe{&NWTProbe(info)};C.__atomic_fetch_add(unsafe{&p.copies},1,5)}
fn nwt_block_drop_probe(block u64){mut p:=unsafe{&NWTProbe(*(&u64(block+32)))};C.__atomic_fetch_add(unsafe{&p.drops},1,5)}
fn nwt_updated(block u64,path u64){mut p:=unsafe{&NWTProbe(*(&u64(block+32)))};held:=unsafe{NWTHold(nwt_sym(c'nw_retain'))(path)};old:=C.__atomic_load_n(unsafe{&p.path},5);C.__atomic_store_n(unsafe{&p.path},held,5);if old!=0{unsafe{NWTDrop(nwt_sym(c'nw_release'))(old)}};C.__atomic_fetch_add(unsafe{&p.calls},1,5)}
fn nwt_enumerate(block u64,link u64)bool{
 mut p:=unsafe{&NWTProbe(*(&u64(block+32)))};count:=C.__atomic_fetch_add(unsafe{&p.names},1,5)+1
 name:=unsafe{NWTName(nwt_sym(c'nw_interface_get_name'))(link)};assert name!=unsafe{nil};index:=unsafe{NWTQuery(nwt_sym(c'nw_interface_get_index'))(link)};kind:=unsafe{NWTQuery(nwt_sym(c'nw_interface_get_type'))(link)}
 println('INTERFACE name='+unsafe{name.vstring()}+' index='+index.str()+' type='+kind.str())
 if p.interface==0{p.interface=unsafe{NWTHold(nwt_sym(c'nw_retain'))(link)}}
 return p.limit==0||count<p.limit
}
fn nwt_report(label string,p &NWTProbe){println(label+' copies='+C.__atomic_load_n(unsafe{&p.copies},5).str()+' drops='+C.__atomic_load_n(unsafe{&p.drops},5).str()+' calls='+C.__atomic_load_n(unsafe{&p.calls},5).str())}
fn nwt_shared(native bool){
 nwt_native=native
 mut dispatch:=unsafe{voidptr(nil)};mut objc:=unsafe{voidptr(nil)}
 if native{nwt_native_network=u64(C.dlopen(c'/System/Library/Frameworks/Network.framework/Network',2));dispatch=C.dlopen(c'/usr/lib/system/libdispatch.dylib',2);objc=C.dlopen(c'/usr/lib/libobjc.A.dylib',2);assert nwt_native_network!=0&&dispatch!=unsafe{nil}&&objc!=unsafe{nil}}
 for name in [c'nw_path_get_status',c'nw_path_has_dns',c'nw_path_has_ipv4',c'nw_path_has_ipv6',c'nw_path_is_expensive',c'nw_path_is_constrained']!{value:=unsafe{NWTQuery(nwt_sym(name))(0)};println('NULL '+unsafe{name.vstring()}+'='+value.str());assert value==0}
 assert unsafe{NWTName(nwt_sym(c'nw_interface_get_name'))(0)}==unsafe{nil}
 monitor:=unsafe{NWTMake(nwt_sym(c'nw_path_monitor_create'))()};assert monitor!=0
 q:=if native{unsafe{NWTQueue(C.dlsym(dispatch,c'dispatch_queue_create'))(c'vinix.native.network-path',0)}}else{darwin_dispatch_queue_create(c'vinix.network-path',0)};assert q!=0
 mut first:=NWTProbe{};mut next:=NWTProbe{}
 descriptor:=NWTDescriptor{0,sizeof(NWTBlock),u64(unsafe{voidptr(nwt_block_copy_probe)}),u64(unsafe{voidptr(nwt_block_drop_probe)})}
 stack:=if native{u64(C.dlsym(objc,c'_NSConcreteStackBlock'))}else{block_isa(0)};assert stack!=0
 block:=NWTBlock{stack,u32(1)<<25,0,u64(unsafe{voidptr(nwt_updated)}),u64(unsafe{&descriptor}),u64(unsafe{&first})}
 replacement:=NWTBlock{stack,u32(1)<<25,0,u64(unsafe{voidptr(nwt_updated)}),u64(unsafe{&descriptor}),u64(unsafe{&next})}
 unsafe{NWTSet(nwt_sym(c'nw_path_monitor_set_queue'))(monitor,q);NWTSet(nwt_sym(c'nw_path_monitor_set_update_handler'))(monitor,u64(&block))};nwt_report('SET',unsafe{&first})
 unsafe{NWTSet(nwt_sym(c'nw_path_monitor_set_update_handler'))(monitor,u64(&replacement))};nwt_report('REPLACED-OLD',unsafe{&first});nwt_report('BEFORE-START',unsafe{&next});assert first.copies==1&&first.drops==1&&next.calls==0
 unsafe{NWTDrop(nwt_sym(c'nw_path_monitor_start'))(monitor)}
 for _ in 0..500 {if C.__atomic_load_n(unsafe{&next.calls},5)>0{break};C.usleep(10000)};nwt_report('STARTED',unsafe{&next});assert next.calls>0
 unsafe{NWTDrop(nwt_sym(c'nw_path_monitor_cancel'))(monitor);NWTDrop(nwt_sym(c'nw_release'))(monitor)}
 for _ in 0..500{if C.__atomic_load_n(unsafe{&next.drops},5)==1{break};C.usleep(10000)}
 nwt_report('CANCELLED',unsafe{&next});assert next.copies==1&&next.drops==1
 path:=next.path;assert path!=0
 for name in [c'nw_path_get_status',c'nw_path_has_dns',c'nw_path_has_ipv4',c'nw_path_has_ipv6',c'nw_path_is_expensive',c'nw_path_is_constrained']!{println('PATH '+unsafe{name.vstring()}+'='+unsafe{NWTQuery(nwt_sym(name))(path)}.str())}
 for kind in u32(0)..5{println('USES '+kind.str()+'='+unsafe{NWTUses(nwt_sym(c'nw_path_uses_interface_type'))(path,kind)}.str())}
 mut all:=NWTProbe{};names:=NWTBlock{stack,u32(1)<<25,0,u64(unsafe{voidptr(nwt_enumerate)}),u64(unsafe{&descriptor}),u64(unsafe{&all})};unsafe{NWTSet(nwt_sym(c'nw_path_enumerate_interfaces'))(path,u64(&names))};println('ENUMERATED '+all.names.str());assert all.copies==0&&all.drops==0
 mut early:=NWTProbe{limit:1};stop:=NWTBlock{stack,u32(1)<<25,0,u64(unsafe{voidptr(nwt_enumerate)}),u64(unsafe{&descriptor}),u64(unsafe{&early})};unsafe{NWTSet(nwt_sym(c'nw_path_enumerate_interfaces'))(path,u64(&stop))};assert early.names<=1;println('EARLY-STOP '+early.names.str())
 assert unsafe{NWTQuery(nwt_sym(c'nw_path_get_status'))(path)}>0;unsafe{NWTDrop(nwt_sym(c'nw_release'))(path)}
 for link in [all.interface,early.interface]!{if link!=0{name:=unsafe{NWTName(nwt_sym(c'nw_interface_get_name'))(link)};assert name!=unsafe{nil};println('RETAINED-INTERFACE '+unsafe{name.vstring()});unsafe{NWTDrop(nwt_sym(c'nw_release'))(link)}}}
 if native{unsafe{NWTDrop(C.dlsym(dispatch,c'dispatch_release'))(q)}}else{darwin_dispatch_release(q)}
 if native{println('IOS-NETWORK-PATH-NATIVE: initial delivery,copied/replaced blocks,immutable retained paths,interface names/types,early enumeration stop,cancellation and retained interface lifetime')}else{assert ios_runtime.live==0&&ios_runtime.objects.len==0&&ios_runtime.block_refs.len==0}
}

fn nwt_fixture() NWSnapshot {
 mut value:=NWSnapshot{status:1,ipv4:true,ipv6:true,count:2}
 mut first:=[64]u8{};mut second:=[64]u8{}
 unsafe{C.memcpy(&first[0],c'fixture-wifi',12);C.memcpy(&second[0],c'fixture-wired',13)}
 value.links[0]=NWLink{first,11,1,1};value.links[1]=NWLink{second,12,3,2}
 return value
}
fn nwt_manual(queue u64,block u64)u64{
 monitor:=nw_monitor_create();assert monitor!=0;nw_monitor_queue(monitor,queue);nw_monitor_handler(monitor,block)
 nw_monitor_state(monitor)or{panic('monitor')}.started=true
 return monitor
}
fn nwt_read(path u64){
 for _ in 0..64{
  assert nw_path_status(path)==1&&nw_path_ipv4(path)&&nw_path_ipv6(path)&&nw_path_dns(path)
  assert nw_path_uses(path,1)&&nw_path_uses(path,3)&&!nw_path_uses(path,2)&&!nw_path_uses(path,99)
  state:=nw_path_state(path)or{panic('path')};assert C.strcmp(nw_interface_name(state.links[0]),c'fixture-wifi')==0
  assert nw_interface_index(state.links[1])==12&&nw_interface_kind(state.links[1])==3
  assert objc_retain(path)==path;objc_release(path)
 }
}
fn nwt_changes(){
 mut probe:=NWTProbe{};descriptor:=NWTDescriptor{0,sizeof(NWTBlock),u64(unsafe{voidptr(nwt_block_copy_probe)}),u64(unsafe{voidptr(nwt_block_drop_probe)})}
 block:=NWTBlock{block_isa(0),u32(1)<<25,0,u64(unsafe{voidptr(nwt_updated)}),u64(unsafe{&descriptor}),u64(unsafe{&probe})}
 monitor:=nwt_manual(darwin_dispatch_get_main_queue(),u64(unsafe{&block}))
 mut snapshot:=nwt_fixture();nw_observe(monitor,unsafe{&snapshot});snapshot.dns=true;nw_observe(monitor,unsafe{&snapshot})
 assert probe.calls==0&&dispatch_main_drain()&&probe.calls==1
 first:=objc_retain(probe.path);assert nw_path_dns(first)&&nw_path_status(first)==1
 live:=ios_runtime.live;objects:=ios_runtime.objects.len
 for _ in 0..256{nw_observe(monitor,unsafe{&snapshot})}
 assert ios_runtime.live==live&&ios_runtime.objects.len==objects&&!dispatch_main_drain()
 mut readers:=[]thread{}
 for _ in 0..8{readers<<spawn nwt_read(first)}
 for reader in readers{reader.wait()};unsafe{readers.free()}
 empty:=NWSnapshot{};nw_observe(monitor,unsafe{&empty});assert dispatch_main_drain()&&probe.calls==2
 assert nw_path_status(probe.path)==2&&!nw_path_dns(probe.path)&&!nw_path_ipv4(probe.path)&&!nw_path_ipv6(probe.path)
 assert nw_path_status(first)==1&&nw_path_dns(first)&&nw_path_ipv6(first)
 nw_observe(monitor,unsafe{&snapshot});nw_monitor_cancel(monitor);objc_release(monitor)
 assert probe.drops==1&&dispatch_main_drain()&&probe.calls==2
 objc_release(probe.path);objc_release(first)
 assert ios_runtime.live==0&&ios_runtime.objects.len==0&&ios_runtime.block_refs.len==0
}
struct NWTGate {mut: probe NWTProbe entered u64 leave u64}
fn nwt_blocking(block u64,path u64){
 nwt_updated(block,path);mut gate:=unsafe{&NWTGate(*(&u64(block+32)))}
 C.__atomic_store_n(unsafe{&gate.entered},1,5)
 for C.__atomic_load_n(unsafe{&gate.leave},5)==0{C.usleep(1000)}
}
fn nwt_inflight(){
 mut gate:=NWTGate{};mut replacement:=NWTProbe{}
 descriptor:=NWTDescriptor{0,sizeof(NWTBlock),u64(unsafe{voidptr(nwt_block_copy_probe)}),u64(unsafe{voidptr(nwt_block_drop_probe)})}
 block:=NWTBlock{block_isa(0),u32(1)<<25,0,u64(unsafe{voidptr(nwt_blocking)}),u64(unsafe{&descriptor}),u64(unsafe{&gate})}
 next:=NWTBlock{block_isa(0),u32(1)<<25,0,u64(unsafe{voidptr(nwt_updated)}),u64(unsafe{&descriptor}),u64(unsafe{&replacement})}
 queue:=darwin_dispatch_queue_create(c'vinix.network.inflight',0);monitor:=nwt_manual(queue,u64(unsafe{&block}));darwin_dispatch_release(queue)
 snapshot:=nwt_fixture();nw_observe(monitor,unsafe{&snapshot})
 for _ in 0..3000{if C.__atomic_load_n(unsafe{&gate.entered},5)!=0{break};C.usleep(1000)}
 assert gate.entered==1&&gate.probe.calls==1
 nw_monitor_handler(monitor,u64(unsafe{&next}));assert gate.probe.drops==0&&replacement.copies==1
 nw_monitor_cancel(monitor);objc_release(monitor);assert gate.probe.drops==0&&replacement.drops==1&&replacement.calls==0
 C.__atomic_store_n(unsafe{&gate.leave},1,5)
 for _ in 0..3000{if C.__atomic_load_n(unsafe{&gate.probe.drops},5)!=0{break};C.usleep(1000)}
 assert gate.probe.drops==1;objc_release(gate.probe.path)
 // The dispatch job drops its monitor immediately after the callback returns.
 for _ in 0..3000{C.ios_objc_initialize_lock();done:=ios_runtime.live==0;C.ios_objc_initialize_unlock();if done{break};C.usleep(1000)}
 assert ios_runtime.live==0&&ios_runtime.objects.len==0&&ios_runtime.block_refs.len==0
}
fn nwt_shutdown_drop(block u64){
 assert ios_runtime.network_retired
 cell:=devicecheck_symbol('_DCErrorDomain')or{panic('domain retired before Network capture')};assert string_text(read64(cell))=='com.apple.devicecheck.error'
 nwt_block_drop_probe(block)
}
fn nwt_shutdown(){
 cell:=devicecheck_symbol('_DCErrorDomain')or{panic('domain')};assert string_text(read64(cell))=='com.apple.devicecheck.error'
 mut probe:=NWTProbe{};descriptor:=NWTDescriptor{0,sizeof(NWTBlock),u64(unsafe{voidptr(nwt_block_copy_probe)}),u64(unsafe{voidptr(nwt_shutdown_drop)})}
 block:=NWTBlock{block_isa(0),u32(1)<<25,0,u64(unsafe{voidptr(nwt_updated)}),u64(unsafe{&descriptor}),u64(unsafe{&probe})}
 monitor:=nw_monitor_create();nw_monitor_queue(monitor,darwin_dispatch_get_main_queue());nw_monitor_handler(monitor,u64(unsafe{&block}));nw_monitor_start(monitor)
 for _ in 0..500{
  C.ios_objc_initialize_lock();pending:=(nw_monitor_state(monitor)or{panic('monitor')}).pending;C.ios_objc_initialize_unlock()
  if pending{break};C.usleep(10000)
 }
 assert (nw_monitor_state(monitor)or{panic('monitor')}).pending
 objc_release(monitor);objc_stop()
 assert probe.calls==0&&probe.copies==1&&probe.drops==1&&nw_runtime==unsafe{nil}
 assert ios_runtime.live==0&&ios_runtime.objects.len==0&&ios_runtime.block_refs.len==0
 assert nw_monitor_create()==0
}
fn test_network_path(){
 $if macos{nwt_shared(true)}
 for _ in 0..2{
  objc_start();system_data_start()or{panic(err)};nwt_shared(false);nwt_changes();nwt_inflight()
  for library in ['/System/Library/Frameworks/Foundation.framework/Foundation','/usr/lib/libSystem.B.dylib']!{if _:=runtime_symbol(library,'_nw_interface_get_name'){assert false}}
  if _:=nw_symbol('_nw_invented'){assert false}
  nwt_shutdown();system_data_stop()
 }
 println('IOS-NETWORK-PATH: real route/interface snapshots,initial delivery,stable names/types,retained immutable paths,concurrent readers,unchanged suppression,coalescing,early enumeration stop,queued cancellation,inflight replacement,owned dispatch cleanup and two drained runtimes')
}
