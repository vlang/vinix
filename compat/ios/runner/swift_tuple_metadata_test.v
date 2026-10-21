// SPDX-License-Identifier: GPL-2.0-or-later
module main
#include <dlfcn.h>
$if macos {
 #flag -framework CoreFoundation
 #include <CoreFoundation/CFString.h>
}
fn C.dlopen(&char,i32)voidptr
fn C.dlsym(voidptr,&char)voidptr
fn C.CFStringCreateMutable(voidptr,i64)voidptr
fn C.CFGetRetainCount(voidptr)i64
fn C.CFRelease(voidptr)
fn C.mincore(voidptr,usize,&u8)i32
type TmProbe=fn(u64,u64,u64,u64,u64,u64,&u64,u64)
struct TmApi { native bool entry u64 code u64 guard u64 types [5]u64 }
fn tm_symbol(native bool,name string)u64{
 $if macos{if native{core:=C.dlopen(c'/usr/lib/swift/libswiftCore.dylib',2);entry:=u64(C.dlsym(core,name[1..].str));assert entry!=0,name;return entry}}
 return runtime_symbol('/usr/lib/swift/libswiftCore.dylib',name) or {panic(err)}
}
fn tm_api(native bool,code u64,guard u64)TmApi{
 mut types:=[5]u64{};for i,name in ['_$sytN','_$sSiN','_$ss5UInt8VN','_$sSbN','_$sSSN']!{types[i]=tm_symbol(native,name)}
 // The exported Void nominal is the full record, unlike other metadata.
 types[0]+=8
 return TmApi{native,tm_symbol(native,'_swift_getTupleTypeMetadata'),code,guard,types}
}
fn tm_call(api TmApi,request u64,count u64,elements u64,labels u64,proposed u64)SwiftAssociatedMetadata{
 mut words:=[u64(0xcafe),0,0,0,0,0,0xbeef]!
 unsafe{TmProbe(voidptr(api.code))(request,count,elements,labels,proposed,api.entry,&words[1],api.guard)}
 assert words[0]==0xcafe&&words[6]==0xbeef&&words[3]==api.guard&&words[4]==0x5121&&words[5]==0x5222
 return SwiftAssociatedMetadata{words[1],words[2]}
}
fn tm_get(api TmApi,types []u64)u64{return tm_call(api,0,u64(types.len),u64(types.data),0,0).metadata}
fn tm_witness(metadata u64)u64{return read64(metadata-8)&0x0000ffffffffffff}
fn tm_entry(metadata u64,slot u64)u64{return read64(tm_witness(metadata)+slot*8)&0x0000ffffffffffff}
fn tm_mix(hash u64,value u64)u64{return (hash^value)*u64(1099511628211)}
fn tm_matrix(api TmApi)u64{
 mut hash:=u64(14695981039346656037)
 for request in [u64(0),1,0x3f,0xff,0x100,0x101,0x13f,0x1ff]!{r:=tm_call(api,request,0,api.guard,api.guard,api.guard);assert r.metadata==api.types[0]&&r.state==0}
 for profile in [[0],[1],[2,1,2],[3,2,3],[1,1,1],[4,1],[3,4],[0,0,0]]!{
  mut types:=[]u64{};for i in profile{types<<api.types[i]};metadata:=tm_get(api,types);w:=tm_witness(metadata)
  assert read64(metadata)==0x301&&read64(metadata+8)==u64(types.len)&&read64(metadata+16)==0
  mut size:=u64(0);mut mask:=u64(0);mut pod:=true;mut extra:=u32(0)
  for i,child in types{cw:=tm_witness(child);bits:=read32(cw+80);cm:=u64(bits&255);size=(size+cm)&~cm
   assert read64(metadata+24+u64(i*16))==child&&read64(metadata+32+u64(i*16))==size;hash=tm_mix(hash,size)
   size+=read64(cw+64);if cm>mask{mask=cm};if bits&0x10000!=0{pod=false};if read32(cw+84)>extra{extra=read32(cw+84)}
  }
  stride:=(size+mask)&~mask;assert read64(w+64)==size&&read64(w+72)==if stride==0{u64(1)}else{stride}
  assert read32(w+80)==u32(mask)|if pod{u32(0)}else{u32(0x10000)};assert read32(w+84)==extra
  for request in [u64(0),1,0x3f,0xff,0x100,0x101,0x13f,0x1ff]!{r:=tm_call(api,request,u64(types.len),u64(types.data),0,0);assert r.metadata==metadata&&r.state==0}
  if !api.native{assert (swift_metadata_state_checked(0,metadata) or {panic(err)}).metadata==metadata}
  // Tag operations never destroy the deliberately invalid enum payloads.
  for cases in [u32(0),1,254,255,256,65535,65536,0x7fffffff,0xffffffff]!{
   for which in [u32(0),1,cases]!{if which>cases{continue};mut bytes:=[40]u8{};value:=u64(unsafe{&bytes[8]});C.memset(voidptr(value),0x55,32)
    store:=unsafe{SwiftOptionalStore(voidptr(tm_entry(metadata,7)))};get:=unsafe{SwiftSequenceTag(voidptr(tm_entry(metadata,6)))}
    store(value,which,cases,metadata);tag:=get(value,cases,metadata);hash=tm_mix(hash,tag)
    if which!=0&&cases<=0x7fffffff{assert tag==which}
    for i in 0..8{assert bytes[i]==0}
   }
  }
  hash=tm_mix(tm_mix(tm_mix(hash,size),u64(read32(w+80))),u64(extra));unsafe{types.free()}
 }
 // POD copy/take includes interior padding and preserves tail canaries.
 metadata:=tm_get(api,[api.types[2],api.types[1],api.types[2]])
 for slot in [u64(0),2,3,4,5]!{mut source:=[40]u8{};mut dest:=[40]u8{};for i in 0..40{source[i]=u8(i+1);dest[i]=0xaa}
  operation:=unsafe{SwiftDynamicCastCopy(voidptr(tm_entry(metadata,slot)))};d:=u64(unsafe{&dest[8]});s:=u64(unsafe{&source[8]});assert operation(d,s,metadata)==d
  for i in 0..40{assert dest[i]==if i>=8&&i<25{source[i]}else{u8(0xaa)}}
 }
 // Real foreign String ARC verifies composed field witnesses, assignment,
 // take consumption and destruction, including inline buffer initialization.
 owned:=tm_get(api,[api.types[4],api.types[1]])
 for slot in [u64(0),2,3,4,5]!{
  owner:=tm_owner(api);other:=tm_owner(api);mut src:=[u64(0),owner|0x5000000000000000,0x1234]!
  mut dst:=[u64(0),other|0x5000000000000000,0x5678]!
  if slot !in [u64(3),5]!{tm_drop(api,other);dst=[u64(0),0,0]!}
  operation:=unsafe{SwiftDynamicCastCopy(voidptr(tm_entry(owned,slot)))};s:=u64(unsafe{&src[0]});d:=u64(unsafe{&dst[0]});assert operation(d,s,owned)==d&&dst==src
  assert tm_refs(api,owner)==if slot in [u64(4),5]!{i64(1)}else{i64(2)}
  destroy:=unsafe{SwiftDynamicCastDestroy(voidptr(tm_entry(owned,1)))};destroy(d,owned)
  if slot !in [u64(4),5]!{assert tm_refs(api,owner)==1;destroy(s,owned)}
 }
 return hash
}
fn tm_owner(api TmApi)u64{$if macos{if api.native{return u64(C.CFStringCreateMutable(unsafe{nil},0))}};return owned_string('tuple owned field')}
fn tm_refs(api TmApi,owner u64)i64{$if macos{if api.native{return C.CFGetRetainCount(voidptr(owner))}};return obj_header(owner).refs}
fn tm_drop(api TmApi,owner u64){$if macos{if api.native{C.CFRelease(voidptr(owner));return}};objc_release(owner)}
fn tm_worker(api TmApi)u64{return tm_get(api,[api.types[1],api.types[3]])}
fn tm_bad(request u64,count u64,elements u64,labels u64,proposed u64){if _:=swift_tuple_metadata_checked(request,count,elements,labels,proposed){assert false,'unsupported tuple accepted'}}
fn tm_invalid(api TmApi){
 for request in [u64(2),0x40,0x200,~u64(0)]!{tm_bad(request,1,api.guard,0,0)}
 for count in [u64(65),0x10001,~u64(0)]!{tm_bad(0,count,api.guard,0,0)}
 tm_bad(0,1,api.guard,api.guard,0);tm_bad(0,1,api.guard,0,api.guard)
 for pointer in [u64(0),1,~u64(7)]!{tm_bad(0,1,pointer,0,0)}
 mut types:=[api.types[1],api.types[1],api.types[1],api.types[1]]!;tm_bad(0,4,u64(unsafe{&types[0]}),0,0)
 types[0]=0;tm_bad(0,1,u64(unsafe{&types[0]}),0,0)
 // Distinct external nonempty tuples are not declared complete from layout.
 mut record:=[u64(0),0x301,1,0]!;types[0]=u64(unsafe{&record[1]});tm_bad(0,1,u64(unsafe{&types[0]}),0,0)
 ios_runtime.swift_tuple_metadata_retired=true;tm_bad(0,0,api.guard,0,0);ios_runtime.swift_tuple_metadata_retired=false
 // 64 elements fit when their values have zero size. Permutations and arity
 // remain distinct even when layouts are identical; capacity is bounded.
 mut zeroes:=[64]u64{};for i in 0..64{zeroes[i]=api.types[0]}
 wide:=tm_call(api,0,64,u64(unsafe{&zeroes[0]}),0,0);assert read64(wide.metadata+8)==64
 for count in u64(1)..65{if ios_runtime.swift_tuple_metadata_count==64{tm_bad(0,count,u64(unsafe{&zeroes[0]}),0,0);break};r:=tm_call(api,0,count,u64(unsafe{&zeroes[0]}),0,0);assert r.state==0&&read64(tm_witness(r.metadata)+64)==0}
 assert ios_runtime.swift_tuple_metadata_count==64
}
fn test_swift_tuple_metadata(){
 page:=usize(C.getpagesize());code:=u64(C.mmap(unsafe{nil},page,C.PROT_READ|C.PROT_WRITE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));guard:=u64(C.mmap(unsafe{nil},page,C.PROT_NONE,C.MAP_PRIVATE|C.MAP_ANONYMOUS,-1,0));assert code!=~u64(0)&&guard!=~u64(0)
 defer{assert C.munmap(voidptr(code),page)==0&&C.munmap(voidptr(guard),page)==0}
 for i,op in [u32(0xa9bc7bfd),0xa90153f3,0xa9025bf5,0xaa0603f3,0xaa0503f0,0xaa0703f4,u32(0xd2800000|(0x5121<<5)|21),u32(0xd2800000|(0x5222<<5)|22),0xaa0703e8,0xd63f0200,0xa9000660,0xa9015674,0xf9001276,0xa9425bf5,0xa94153f3,0xa8c47bfd,0xd65f03c0]!{write32(code+u64(i*4),op)}
 C.__builtin___clear_cache(voidptr(code),voidptr(code+68));assert C.mprotect(voidptr(code),page,C.PROT_READ|C.PROT_EXEC)==0
 mut native_hash:=u64(0);$if macos{native_hash=tm_matrix(tm_api(true,code,guard));println('NATIVE-TUPLE-METADATA: scalar request/flags/vector/labels/VWT and x0/x1 response, all eight request modes, ordered padded layouts, POD and String ARC copy/assign/take/destroy, Bool/String extra inhabitants and UInt32 enum transitions, preserved x20/x21/x22')}
 tm_bad(0,0,guard,0,0)
 for _ in 0..2{objc_start();api:=tm_api(false,code,guard);hash:=tm_matrix(api);$if macos{assert hash==native_hash}
  mut workers:=[]thread u64{};for _ in 0..8{workers<<spawn tm_worker(api)};results:=workers.wait();for result in results{assert result==results[0]};unsafe{workers.free();results.free()}
  tm_invalid(api);pages:=ios_runtime.swift_tuple_metadata_pages;objc_stop();assert ios_runtime.swift_tuple_metadata_count==0
  for base in pages{$if macos{assert C.mprotect(voidptr(base),page,C.PROT_READ)==-1}$else{mut resident:=u8(0);assert C.mincore(voidptr(base),page,&resident)==-1}}
  tm_bad(0,0,guard,0,0)
 }
 println('IOS-TUPLE-METADATA: bounded unlabelled inline tuple layout and composed value witnesses, native ABI/layout/tag/ARC agreement, canonical concurrent cache and metadata-state recognition, guarded invalid inputs and capacity, sealed pages and two drained/unmapped lifetimes')
}
