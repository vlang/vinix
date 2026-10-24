// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#flag -framework UserNotifications
	#include <objc/runtime.h>
}
#include <dlfcn.h>
fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.class_getInstanceVariable(voidptr, &char) voidptr
fn C.ivar_getOffset(voidptr) isize
fn C.ivar_getTypeEncoding(voidptr) &char
fn C.objc_storeWeak(&u64, voidptr) voidptr
type CacheSend = fn (u64, u64, u64, u64, u64, u64) u64
struct CacheApi { native bool send u64 }
fn cache_api() CacheApi { return CacheApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })} }
fn (api CacheApi) cls(name string) u64 {
	$if macos { if api.native { return u64(C.objc_getClass(name.str)) } }
	return ios_runtime.names[name]
}
fn (api CacheApi) sel(name &char) u64 {
	$if macos { if api.native { return u64(C.sel_registerName(name)) } }
	return u64(name)
}
fn (api CacheApi) msg(object u64, name &char, a u64, b u64, c u64, d u64) u64 {
	return unsafe { CacheSend(voidptr(api.send))(object, api.sel(name), a, b, c, d) }
}
fn (api CacheApi) release(object u64) { api.msg(object, c'release', 0, 0, 0, 0) }
fn (api CacheApi) pool() u64 {
	$if macos { if api.native { return api.msg(api.cls('NSAutoreleasePool'), c'new', 0, 0, 0, 0) } }
	return objc_pool_push()
}
fn (api CacheApi) pop(pool u64) {
	$if macos { if api.native { api.msg(pool, c'drain', 0, 0, 0, 0); return } }
	objc_pool_pop(pool)
}
fn (api CacheApi) weak(slot &u64, object u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { voidptr(object) }); return } }
	objc_store_weak(slot, object)
}
fn (api CacheApi) weak_destroy(slot &u64) {
	$if macos { if api.native { C.objc_storeWeak(slot, unsafe { nil }); return } }
	objc_destroy_weak(slot)
}
fn (api CacheApi) string(value string, mutable bool) u64 {
	return api.msg(api.msg(api.cls(if mutable { 'NSMutableString' } else { 'NSString' }), c'alloc', 0, 0, 0, 0), c'initWithBytes:length:encoding:', u64(value.str), u64(value.len), 4, 0)
}
fn (api CacheApi) text(object u64) string {
	assert object != 0
	length := api.msg(object, c'lengthOfBytesUsingEncoding:', 4, 0, 0, 0)
	bytes := api.msg(object, c'UTF8String', 0, 0, 0, 0); assert bytes != 0
	return if length == 0 { '' } else { unsafe { tos(&u8(voidptr(bytes)), int(length)) } }
}
fn cache_metadata(api CacheApi) {
 cls := api.cls('NSCache'); assert cls != 0
 $if macos { if api.native { assert C.class_getInstanceSize(voidptr(cls)) == 48 && u64(C.class_getSuperclass(voidptr(cls))) == api.cls('NSObject') } }
 if !api.native { assert objc_class_size(cls) == 48 && objc_class_parent(cls) == api.cls('NSObject') }
 for i, key in ns_cache_ivars() {
  expected := ns_cache_ivar_types()[i]
  $if macos { if api.native {
   ivar := C.class_getInstanceVariable(voidptr(cls), key.str)
   assert ivar != unsafe { nil } && C.ivar_getOffset(ivar) == isize(ns_cache_offsets()[i])
   assert unsafe { C.ivar_getTypeEncoding(ivar).vstring() } == expected
  } }
  if !api.native { ivar := objc_find_ivar(cls, key.str); assert ivar != 0 && objc_ivar_offset(ivar) == ns_cache_offsets()[i] && ctext(u64(objc_ivar_types(ivar))) == expected }
 }
 for selector in ['init', 'name', 'setName:', 'delegate', 'setDelegate:', 'objectForKey:', 'setObject:forKey:', 'setObject:forKey:cost:', 'removeObjectForKey:', 'removeAllObjects', 'countLimit', 'setCountLimit:', 'totalCostLimit', 'setTotalCostLimit:', 'evictsObjectsWithDiscardedContent', 'setEvictsObjectsWithDiscardedContent:']! {
  expected := ns_cache_types('NSCache', false, selector) or { panic(selector) }; mut actual := ''
  $if macos { if api.native { method := C.class_getInstanceMethod(voidptr(cls), voidptr(api.sel(selector.str))); assert method != unsafe { nil }; actual = unsafe { C.method_getTypeEncoding(method).vstring() } } }
  if !api.native { method := objc_instance_method(cls, u64(selector.str)); assert method != 0; actual = ctext(u64(objc_method_types(method))) }
  assert actual == expected, selector + ': ' + actual
 }
}
fn cache_shared(api CacheApi) {
 pool := api.pool(); cache_metadata(api)
 cache := api.msg(api.cls('NSCache'), c'new', 0, 0, 0, 0); assert cache != 0
 assert api.text(api.msg(cache, c'name', 0, 0, 0, 0)) == ''
 for selector in [c'delegate', c'countLimit', c'totalCostLimit']! { assert api.msg(cache, selector, 0, 0, 0, 0) == 0 }
 assert api.msg(cache, c'evictsObjectsWithDiscardedContent', 0, 0, 0, 0) == 1
 for value in ['', 'cache', 'é😀', 'a\x00' + 'b']! {
  input := api.string(value, true); replacement := api.string('changed', false)
  api.msg(cache, c'setName:', input, 0, 0, 0); api.msg(input, c'setString:', replacement, 0, 0, 0)
  end := value.index_u8(0)
  expected := if end >= 0 { value[..end] } else { value }
  api.release(input); api.release(replacement); assert api.text(api.msg(cache, c'name', 0, 0, 0, 0)) == expected
 }
 api.msg(cache, c'setName:', 0, 0, 0, 0); assert api.text(api.msg(cache, c'name', 0, 0, 0, 0)) == ''
 api.msg(cache, c'setDelegate:', 0, 0, 0, 0)
 for flag in [u64(0), 1]! { api.msg(cache, c'setEvictsObjectsWithDiscardedContent:', flag, 0, 0, 0); assert api.msg(cache, c'evictsObjectsWithDiscardedContent', 0, 0, 0, 0) == flag }
 // NSObject has no copy method: keys and values must be retained directly.
 key := api.msg(api.cls('NSObject'), c'new', 0, 0, 0, 0); value := api.msg(api.cls('NSObject'), c'new', 0, 0, 0, 0)
 mut wk := u64(0); mut wv := u64(0); api.weak(unsafe { &wk }, key); api.weak(unsafe { &wv }, value)
 api.msg(cache, c'setObject:forKey:cost:', value, key, 2, 0); api.release(key); api.release(value)
 assert wk != 0 && wv != 0 && api.msg(cache, c'objectForKey:', key, 0, 0, 0) == value
 api.pop(pool)
 assert wk != 0 && wv != 0
 api.msg(cache, c'removeObjectForKey:', key, 0, 0, 0); assert wk == 0 && wv == 0
 api.weak_destroy(unsafe { &wk }); api.weak_destroy(unsafe { &wv })
 inner := api.pool()
 a := api.string('equal key', false); b := api.string('equal key', false)
 first := api.msg(api.cls('NSObject'), c'new', 0, 0, 0, 0); second := api.msg(api.cls('NSObject'), c'new', 0, 0, 0, 0)
 api.msg(cache, c'setObject:forKey:', first, a, 0, 0); assert api.msg(cache, c'objectForKey:', b, 0, 0, 0) == first
 api.msg(cache, c'setObject:forKey:', second, b, 0, 0); assert api.msg(cache, c'objectForKey:', a, 0, 0, 0) == second
 api.msg(cache, c'removeObjectForKey:', a, 0, 0, 0); assert api.msg(cache, c'objectForKey:', b, 0, 0, 0) == 0
 assert api.msg(cache, c'objectForKey:', 0, 0, 0, 0) == 0; api.msg(cache, c'removeObjectForKey:', 0, 0, 0, 0)
 api.msg(cache, c'setCountLimit:', 17, 0, 0, 0); api.msg(cache, c'setTotalCostLimit:', 23, 0, 0, 0)
 assert api.msg(cache, c'countLimit', 0, 0, 0, 0) == 17 && api.msg(cache, c'totalCostLimit', 0, 0, 0, 0) == 23
 api.msg(cache, c'setCountLimit:', 0, 0, 0, 0); api.msg(cache, c'setTotalCostLimit:', 0, 0, 0, 0)
 api.msg(cache, c'setObject:forKey:', first, a, 0, 0); api.msg(cache, c'removeAllObjects', 0, 0, 0, 0); assert api.msg(cache, c'objectForKey:', a, 0, 0, 0) == 0
 for item in [a, b, first, second, cache]! { api.release(item) }; api.pop(inner)
}
fn cache_thread(api CacheApi, cache u64, index int) {
 pool := api.pool(); key := api.string('thread-' + index.str(), false); value := api.msg(api.cls('NSObject'), c'new', 0, 0, 0, 0)
 for _ in 0 .. 100 { api.msg(cache, c'setObject:forKey:cost:', value, key, 2, 0); assert api.msg(cache, c'objectForKey:', key, 0, 0, 0) == value; api.msg(cache, c'removeObjectForKey:', key, 0, 0, 0) }
 api.release(key); api.release(value); api.pop(pool)
}
__global cache_callback_mode = ''
__global cache_callback_destination = u64(0)
__global cache_callback_source = u64(0)
__global cache_callback_count = 0
__global cache_callback_mutate = false
__global cache_callback_deallocs = 0
fn cache_lock_worker() { C.ios_objc_initialize_lock(); C.ios_objc_initialize_unlock() }
fn cache_callback_worker() {
 cache_lock_worker()
 if cache_callback_source != 0 { api := cache_api(); value := api.string('changed', false); api.msg(cache_callback_source, c'setString:', value, 0, 0, 0); api.release(value); api.release(cache_callback_source) }
}
fn cache_constructor(object u64, _selector &char) u64 {
 if cache_callback_mode == '' { return object }
 cache_callback_count++
 if cache_callback_count == 1 {
  match cache_callback_mode {
   'isa' { objc_set_class(cache_callback_destination, ios_runtime.names['NSObject']) }
   'body' { unsafe { *(&u8(cache_callback_destination + 40)) = 1 } }
   'state' { obj_header(cache_callback_destination).cache.initialized = true }
   'busy' { obj_header(cache_callback_destination).cache.initializing = false }
   'destroy' { objc_destruct_instance(cache_callback_destination) }
   'reinit' { ns_cache_initialize(cache_callback_destination) }
   else { mode := cache_callback_mode; cache_callback_mode = ''; worker := spawn cache_callback_worker(); worker.wait(); cache_callback_mode = mode }
  }
 }
 return if cache_callback_mode == 'fail' { u64(0) } else { object }
}
fn cache_hash(_object u64, _selector &char) u64 { worker := spawn cache_lock_worker(); worker.wait(); return 7 }
fn cache_equal(_object u64, _selector &char, _other u64) bool {
 worker := spawn cache_lock_worker(); worker.wait()
 if cache_callback_mutate { cache_callback_mutate = false; cache_api().msg(cache_callback_destination, c'removeAllObjects', 0, 0, 0, 0) }
 return true
}
fn cache_dealloc(_object u64, _selector &char) {
 worker := spawn cache_lock_worker(); worker.wait(); cache_callback_deallocs++
 if cache_callback_destination != 0 { assert cache_api().msg(cache_callback_destination, c'countLimit', 0, 0, 0, 0) == 0 }
}
fn cache_override(_object u64, _selector &char) u64 { return 99 }
fn cache_runtime(api CacheApi) {
 cls := api.cls('NSCache'); library := '/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation'
 assert runtime_symbol(library, '_OBJC_CLASS_$_NSCache') or { panic(err) } == cls
 assert runtime_symbol(library, '_OBJC_METACLASS_$_NSCache') or { panic(err) } == read64(cls)
 assert objc_add_method(api.cls('NSString'), u64(c'.cxx_construct'), u64(unsafe { voidptr(cache_constructor) }), c'@16@0:8')
 for mode in ['success', 'fail']! {
  before := ios_runtime.live; object := objc_allocate(cls); mut weak := u64(0); api.weak(unsafe { &weak }, object)
  cache_callback_mode = mode; cache_callback_count = 0; cache_callback_destination = object
  result := ns_cache_initialize(object); cache_callback_mode = ''; cache_callback_destination = 0
  if mode == 'success' { assert result == object; api.release(object) } else { assert result == 0 }
  assert weak == 0; api.weak_destroy(unsafe { &weak }); assert ios_runtime.live == before
 }
 pool := api.pool(); cache := api.msg(cls, c'new', 0, 0, 0, 0)
 input := api.string('snapshot', true); cache_callback_source = input; cache_callback_mode = 'success'; cache_callback_count = 0
 api.msg(cache, c'setName:', input, 0, 0, 0); cache_callback_mode = ''; cache_callback_source = 0
 assert api.text(api.msg(cache, c'name', 0, 0, 0, 0)) == 'snapshot'
 mut threads := []thread{}
 for i in 0 .. 4 { threads << spawn cache_thread(api, cache, i) }; threads.wait()
 keys := [api.string('a', false), api.string('b', false), api.string('c', false)]!
 value := api.msg(api.cls('NSObject'), c'new', 0, 0, 0, 0)
 api.msg(cache, c'setCountLimit:', 2, 0, 0, 0)
 for key in keys { api.msg(cache, c'setObject:forKey:', value, key, 0, 0) }
 assert api.msg(cache, c'objectForKey:', keys[0], 0, 0, 0) == 0 && obj_header(cache).cache.entries.len == 2
 api.msg(cache, c'setCountLimit:', 0, 0, 0, 0); api.msg(cache, c'removeAllObjects', 0, 0, 0, 0)
 api.msg(cache, c'setTotalCostLimit:', 3, 0, 0, 0)
 for key in keys { api.msg(cache, c'setObject:forKey:cost:', value, key, 2, 0) }
 assert obj_header(cache).cache.entries.len == 1 && obj_header(cache).cache.cost == 2
 api.msg(cache, c'setTotalCostLimit:', 0, 0, 0, 0); api.msg(cache, c'removeAllObjects', 0, 0, 0, 0)
 api.msg(cache, c'setObject:forKey:cost:', value, keys[0], ~u64(0), 0); api.msg(cache, c'setObject:forKey:cost:', value, keys[1], 1, 0)
 assert obj_header(cache).cache.entries.len == 1 && obj_header(cache).cache.cost == 1
 api.msg(cache, c'removeAllObjects', 0, 0, 0, 0)
 for i in 0 .. 4097 { key := api.msg(api.cls('NSObject'), c'new', 0, 0, 0, 0); api.msg(cache, c'setObject:forKey:', value, key, 0, 0); api.release(key) }
 assert obj_header(cache).cache.entries.len == 4096; api.msg(cache, c'removeAllObjects', 0, 0, 0, 0)
 probe := objc_allocate_class(api.cls('NSObject'), c'CacheCallbackProbe', 0); assert probe != 0
 assert objc_add_method(probe, u64(c'hash'), u64(unsafe { voidptr(cache_hash) }), c'Q16@0:8')
 assert objc_add_method(probe, u64(c'isEqual:'), u64(unsafe { voidptr(cache_equal) }), c'B24@0:8@16')
 assert objc_add_method(probe, u64(c'dealloc'), u64(unsafe { voidptr(cache_dealloc) }), c'v16@0:8'); objc_register_class(probe)
 cache_callback_destination = cache; cache_callback_deallocs = 0
 a := objc_new(probe); b := objc_new(probe)
 api.msg(cache, c'setObject:forKey:', a, a, 0, 0); cache_callback_mutate = true
 assert api.msg(cache, c'objectForKey:', b, 0, 0, 0) == 0
 api.msg(cache, c'setObject:forKey:', a, a, 0, 0); api.release(a); api.release(b)
 api.msg(cache, c'removeAllObjects', 0, 0, 0, 0); assert cache_callback_deallocs == 2
 cache_callback_destination = 0
 for item in keys { api.release(item) }; api.release(value)
 for selector in [c'copy', c'mutableCopy', c'initWithCoder:', c'encodeWithCoder:', c'allObjects', c'minimumObjectCount']! { assert !objc_responds(cache, selector) && objc_instance_method(cls, u64(selector)) == 0 }
 objc_set_class(cache, api.cls('NSObject')); api.release(cache); api.pop(pool)
 mut guarded := [8]u64{}; guarded[0] = 0x1122334455667788; guarded[7] = 0x8877665544332211
 caller := u64(unsafe { &guarded[1] }); assert objc_construct_instance(cls, caller) == caller && ns_cache_initialize(caller) == caller
 assert objc_destruct_instance(caller) == caller && caller !in ios_runtime.objects
 assert guarded[0] == 0x1122334455667788 && guarded[7] == 0x8877665544332211
 assert objc_add_method(cls, u64(c'allObjects'), u64(unsafe { voidptr(cache_override) }), c'@16@0:8')
 override := api.msg(cls, c'new', 0, 0, 0, 0); assert objc_responds(override, c'allObjects') && api.msg(override, c'allObjects', 0, 0, 0, 0) == 99; api.release(override)
 assert ios_runtime.live == 0 && ios_runtime.objects.len == 0 && ios_runtime.weak.len == 0
}
fn test_ns_cache() {
 $if macos { native_send := C.dlsym(voidptr(i64(-2)), c'objc_msgSend'); assert native_send != unsafe { nil }; cache_shared(CacheApi{true, u64(native_send)}); println('IOS-CACHE-NATIVE: layout, encodings, defaults, copied names, retained keys and values, equality and removal PASS') }
 for _ in 0 .. 2 { objc_start(); system_data_start()!; api := cache_api(); cache_shared(api); cache_runtime(api); objc_stop(); assert ios_runtime.live == 0; system_data_stop() }
 println('IOS-CACHE: native parity, concurrency, bounded count and cost eviction, callbacks, constructors, caller storage, isa cleanup and two balanced lifetimes PASS')
}
fn test_ns_cache_rejections() {
 objc_start(); system_data_start()!; api := cache_api()
 modes := ['raw', 'spoof', 'isa', 'raw-isa', 'body', 'padding', 'subclass', 'caller-subclass', 'wrong-string', 'raw-string', 'oversize', 'invalid-utf8', 'nil-key', 'nil-value', 'delegate', 'discardable', 'reinit', 'associated-copy', 'active-destroy', 'constructor-isa', 'constructor-body', 'constructor-state', 'constructor-busy', 'constructor-destroy', 'constructor-reinit', 'caller-failure', 'copy', 'mutableCopy', 'encodeWithCoder:', 'allObjects', 'minimumObjectCount']!
 for mode in modes {
  mut fds := [2]i32{}; assert C.pipe(unsafe { &fds[0] }) == 0; pid := C.ios_fork(); assert pid >= 0
  if pid == 0 {
   C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1]); cls := api.cls('NSCache'); object := api.msg(cls, c'new', 0, 0, 0, 0)
   match mode {
    'raw' { api.msg(objc_allocate(cls), c'name', 0, 0, 0, 0) }
    'spoof' { fake := objc_new(api.cls('NSObject')); objc_set_class(fake, cls); api.msg(fake, c'name', 0, 0, 0, 0) }
    'isa', 'raw-isa' { if mode == 'isa' { objc_set_class(object, api.cls('NSObject')) } else { unsafe { *(&u64(object)) = api.cls('NSObject') } }; api.msg(object, c'name', 0, 0, 0, 0) }
    'body', 'padding' { unsafe { *(&u8(object + if mode == 'body' { u64(8) } else { u64(47) })) = 1 }; api.msg(object, c'name', 0, 0, 0, 0) }
    'subclass', 'caller-subclass' { custom := objc_allocate_class(cls, c'UnsupportedCache', 0); objc_register_class(custom); if mode == 'subclass' { objc_allocate(custom) } else { mut storage := [6]u64{}; objc_construct_instance(custom, u64(unsafe { &storage[0] })) } }
    'wrong-string', 'raw-string', 'oversize', 'invalid-utf8' { input := match mode { 'wrong-string' { objc_new(api.cls('NSObject')) } 'raw-string' { objc_allocate(api.cls('NSMutableString')) } 'oversize' { api.string('x'.repeat(65537), false) } else { owned_string('\xff') } }; api.msg(object, c'setName:', input, 0, 0, 0) }
    'nil-key', 'nil-value' { api.msg(object, c'setObject:forKey:', if mode == 'nil-value' { u64(0) } else { object }, if mode == 'nil-key' { u64(0) } else { object }, 0, 0) }
    'delegate' { api.msg(object, c'setDelegate:', object, 0, 0, 0) }
    'discardable' { custom := objc_allocate_class(api.cls('NSObject'), c'DiscardableProbe', 0); assert objc_add_method(custom, u64(c'beginContentAccess'), u64(unsafe { voidptr(cache_override) }), c'B16@0:8'); objc_register_class(custom); api.msg(object, c'setObject:forKey:', objc_new(custom), object, 0, 0) }
    'reinit' { ns_cache_initialize(object) }
    'associated-copy' { objc_copy_value(object, false) }
    'active-destroy' { ns_cache_enter(object); objc_destruct_instance(object) }
    'caller-failure' { mut storage := [6]u64{}; caller := objc_construct_instance(cls, u64(unsafe { &storage[0] })); assert objc_add_method(api.cls('NSString'), u64(c'.cxx_construct'), u64(unsafe { voidptr(cache_constructor) }), c'@16@0:8'); cache_callback_mode = 'fail'; cache_callback_count = 0; ns_cache_initialize(caller) }
    else {
     if mode.starts_with('constructor-') { assert objc_add_method(api.cls('NSString'), u64(c'.cxx_construct'), u64(unsafe { voidptr(cache_constructor) }), c'@16@0:8'); cache_callback_destination = objc_allocate(cls); cache_callback_count = 0; cache_callback_mode = mode.all_after('constructor-'); ns_cache_initialize(cache_callback_destination) }
     else { api.msg(object, mode.str, 0, 0, 0, 0) }
    }
   }
   C._exit(0)
  }
  C.close(fds[1]); mut bytes := [16384]u8{}; mut length := 0
  for { assert length < bytes.len; count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length)); if count == 0 { break }; if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }; assert count > 0; length += int(count) }
  C.close(fds[0]); mut status := i32(0); assert C.ios_waitpid(pid, &status, 0) == pid
  output := unsafe { tos(&bytes[0], length) }; assert status == 256 && output.contains('iOS:') && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
 }
 objc_stop(); assert ios_runtime.live == 0; system_data_stop()
 println('IOS-CACHE-REJECT: ' + modes.len.str() + ' invalid storage, values, constructors, copies and unsupported API cases PASS')
}
