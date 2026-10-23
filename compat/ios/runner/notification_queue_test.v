// SPDX-License-Identifier: GPL-2.0-or-later
module main

$if macos {
	#flag -framework Foundation
	#flag -framework CoreFoundation
	#include <objc/runtime.h>
	#define dispatch_sync vinix_native_header_dispatch_sync
	#include <CoreFoundation/CFRunLoop.h>
	#undef dispatch_sync
}

#include <dlfcn.h>

fn C.objc_getClass(&char) voidptr
fn C.sel_registerName(&char) voidptr
fn C.dlsym(voidptr, &char) voidptr
fn C.objc_allocateClassPair(voidptr, &char, usize) voidptr
fn C.objc_registerClassPair(voidptr)
fn C.class_addMethod(voidptr, voidptr, voidptr, &char) bool
fn C.class_getInstanceMethod(voidptr, voidptr) voidptr
fn C.method_getTypeEncoding(voidptr) &char
fn C.class_getInstanceSize(voidptr) usize
fn C.class_getSuperclass(voidptr) voidptr
fn C.class_getInstanceVariable(voidptr, &char) voidptr
fn C.class_copyIvarList(voidptr, &u32) voidptr
fn C.ivar_getOffset(voidptr) isize
fn C.ivar_getTypeEncoding(voidptr) &char
fn C.objc_storeWeak(&u64, voidptr) voidptr
fn C.CFRunLoopRunInMode(voidptr, f64, bool) i32

type NotificationQueueSend = fn (u64, u64, u64, u64, u64, u64) u64
type NotificationQueueWeakLoad = fn (&u64) u64

struct NotificationQueueApi {
	native bool
	send   u64
}

fn (api NotificationQueueApi) cls(name string) u64 {
	$if macos {
		if api.native { return u64(C.objc_getClass(name.str)) }
	}
	return ios_runtime.names[name]
}

fn (api NotificationQueueApi) sel(name &char) u64 {
	$if macos {
		if api.native { return u64(C.sel_registerName(name)) }
	}
	return u64(name)
}

fn (api NotificationQueueApi) msg(object u64, name &char, a u64, b u64, c u64, d u64) u64 {
	return unsafe { NotificationQueueSend(voidptr(api.send))(object, api.sel(name), a, b, c, d) }
}

fn (api NotificationQueueApi) retain(object u64) u64 {
	return api.msg(object, c'retain', 0, 0, 0, 0)
}

fn (api NotificationQueueApi) release(object u64) { api.msg(object, c'release', 0, 0, 0, 0) }

fn (api NotificationQueueApi) string(value string) u64 {
	return api.msg(api.cls('NSString'), c'stringWithUTF8String:', u64(value.str), 0, 0, 0)
}

fn (api NotificationQueueApi) pool() u64 {
	$if macos {
		if api.native { return api.msg(api.cls('NSAutoreleasePool'), c'new', 0, 0, 0, 0) }
	}
	return objc_pool_push()
}

fn (api NotificationQueueApi) pop(pool u64) {
	$if macos {
		if api.native {
			api.msg(pool, c'drain', 0, 0, 0, 0)
			return
		}
	}
	objc_pool_pop(pool)
}

fn (api NotificationQueueApi) checkpoint() {
	$if macos {
		if api.native {
			cell := C.dlsym(unsafe { voidptr(-2) }, c'kCFRunLoopDefaultMode')
			assert cell != unsafe { nil }
			C.CFRunLoopRunInMode(unsafe { voidptr(*(&u64(cell))) }, 0.01, false)
			return
		}
	}
	ns_notification_queues_drain()
}

fn (api NotificationQueueApi) weak(slot &u64, object u64) {
	$if macos {
		if api.native {
			C.objc_storeWeak(slot, unsafe { voidptr(object) })
			return
		}
	}
	objc_store_weak(slot, object)
}

fn (api NotificationQueueApi) weak_alive(slot &u64) bool {
	mut value := u64(0)
	$if macos {
		if api.native {
			load := C.dlsym(unsafe { voidptr(-2) }, c'objc_loadWeakRetained')
			assert load != unsafe { nil }
			value = unsafe { NotificationQueueWeakLoad(load)(slot) }
		}
	}
	if !api.native { value = objc_load_weak(slot) }
	alive := value != 0
	api.release(value)
	return alive
}

fn (api NotificationQueueApi) weak_destroy(slot &u64) {
	$if macos {
		if api.native {
			C.objc_storeWeak(slot, unsafe { nil })
			return
		}
	}
	objc_destroy_weak(slot)
}

fn (api NotificationQueueApi) note(name u64, sender u64, info u64) u64 {
	return api.msg(api.cls('NSNotification'), c'notificationWithName:object:userInfo:', name, sender, info, 0)
}

fn (api NotificationQueueApi) queue(center u64) u64 {
	return api.msg(api.msg(api.cls('NSNotificationQueue'), c'alloc', 0, 0, 0, 0), c'initWithNotificationCenter:', center, 0, 0, 0)
}

fn (api NotificationQueueApi) enqueue(queue u64, note u64, style u64, mask u64) {
	api.msg(queue, c'enqueueNotification:postingStyle:coalesceMask:forModes:', note, style, mask, 0)
}

__global notification_queue_api = NotificationQueueApi{}
__global notification_queue_calls = [128]u64{}
__global notification_queue_call_count = 0
__global notification_queue_callback_mode = ''
__global notification_queue_callback_queue = u64(0)
__global notification_queue_callback_note = u64(0)
__global notification_queue_callback_fired = false

fn notification_queue_receive(_object u64, _selector &char, note u64) {
	assert notification_queue_call_count < notification_queue_calls.len
	notification_queue_calls[notification_queue_call_count] = note
	notification_queue_call_count++
	if notification_queue_callback_fired || notification_queue_callback_mode == '' { return }
	notification_queue_callback_fired = true
	api := notification_queue_api
	match notification_queue_callback_mode {
		'enqueue' {
			api.enqueue(notification_queue_callback_queue, notification_queue_callback_note, 2, 0)
		}
		'dequeue' {
			api.msg(notification_queue_callback_queue, c'dequeueNotificationsMatching:coalesceMask:', notification_queue_callback_note, 3, 0, 0)
		}
		'release' { api.release(notification_queue_callback_queue) }
		'reenter' { api.checkpoint() }
		else {
			assert false
		}
	}
}

fn notification_queue_observer(api NotificationQueueApi, center u64) u64 {
	mut cls := u64(0)
	action := api.sel(c'vinixNotificationQueueReceived:')
	$if macos {
		if api.native {
			cls = u64(C.objc_getClass(c'VinixNotificationQueueObserver'))
			if cls == 0 {
				cls = u64(C.objc_allocateClassPair(unsafe { voidptr(api.cls('NSObject')) }, c'VinixNotificationQueueObserver', 0))
				assert cls != 0 && C.class_addMethod(unsafe { voidptr(cls) }, unsafe { voidptr(action) }, unsafe { voidptr(notification_queue_receive) }, c'v24@0:8@16')
				C.objc_registerClassPair(unsafe { voidptr(cls) })
			}
		}
	}
	if !api.native {
		cls = ios_runtime.names['VinixNotificationQueueObserver']
		if cls == 0 {
			cls = objc_allocate_class(api.cls('NSObject'), c'VinixNotificationQueueObserver', 0)
			assert cls != 0 && objc_add_method(cls, action, u64(unsafe { voidptr(notification_queue_receive) }), c'v24@0:8@16')
			objc_register_class(cls)
		}
	}
	object := api.msg(cls, c'new', 0, 0, 0, 0)
	api.msg(center, c'addObserver:selector:name:object:', object, action, 0, 0)
	return object
}

fn notification_queue_expect(expected []u64) {
	assert notification_queue_call_count == expected.len
	for i, value in expected {
		assert notification_queue_calls[i] == value
	}
	notification_queue_call_count = 0
}

fn notification_queue_metadata(api NotificationQueueApi) {
	cls := api.cls('NSNotificationQueue')
	assert cls != 0
	mut count := u32(99)
	$if macos {
		if api.native {
			assert C.class_getInstanceSize(unsafe { voidptr(cls) }) == 32 && u64(C.class_getSuperclass(unsafe { voidptr(cls) })) == api.cls('NSObject')
			list := C.class_copyIvarList(unsafe { voidptr(cls) }, &count)
			assert count == 3
			unsafe { C.free(list) }
		}
	}
	if !api.native {
		assert objc_class_size(cls) == 32 && objc_class_parent(cls) == api.cls('NSObject')
		list := objc_copy_ivars(cls, &count)
		assert count == 3
		unsafe { C.free(list) }
	}
	for i, name in ['_notificationCenter', '_asapQueue', '_idleQueue']! {
		types := if i == 0 { '@"NSNotificationCenter"' } else { '@"NSMutableArray"' }
		$if macos {
			if api.native {
				ivar := C.class_getInstanceVariable(unsafe { voidptr(cls) }, name.str)
				assert ivar != unsafe { nil } && C.ivar_getOffset(ivar) == 8 + i * 8 && unsafe { C.ivar_getTypeEncoding(ivar).vstring() } == types
			}
		}
		if !api.native {
			ivar := objc_find_ivar(cls, name.str)
			assert ivar != 0 && objc_ivar_offset(ivar) == 8 + i * 8 && ctext(u64(objc_ivar_types(ivar))) == types
		}
	}
	for name, types in {
		'initWithNotificationCenter:':                             '@24@0:8@16'
		'enqueueNotification:postingStyle:':                       'v32@0:8@16Q24'
		'enqueueNotification:postingStyle:coalesceMask:forModes:': 'v48@0:8@16Q24Q32@40'
		'dequeueNotificationsMatching:coalesceMask:':              'v32@0:8@16Q24'
	} {
		$if macos {
			if api.native {
				method := C.class_getInstanceMethod(unsafe { voidptr(cls) }, unsafe { voidptr(api.sel(name.str)) })
				assert method != unsafe { nil } && unsafe { C.method_getTypeEncoding(method).vstring() } == types
			}
		}
		if !api.native {
			method := objc_instance_method(cls, u64(name.str))
			assert method != 0 && ctext(u64(objc_method_types(method))) == types
		}
	}
}

fn notification_queue_shared(api NotificationQueueApi) {
	notification_queue_api = api
	notification_queue_callback_mode = ''
	notification_queue_call_count = 0
	pool := api.pool()
	notification_queue_metadata(api)
	cls := api.cls('NSNotificationQueue')
	default_queue := api.msg(cls, c'defaultQueue', 0, 0, 0, 0)
	assert default_queue != 0 && api.msg(cls, c'defaultQueue', 0, 0, 0, 0) == default_queue
	center := api.msg(api.cls('NSNotificationCenter'), c'new', 0, 0, 0, 0)
	observer := notification_queue_observer(api, center)
	queue := api.queue(center)
	a := api.string('Vinix.Queue.A')
	b := api.string('Vinix.Queue.B')
	s1 := api.msg(api.cls('NSObject'), c'new', 0, 0, 0, 0)
	s2 := api.msg(api.cls('NSObject'), c'new', 0, 0, 0, 0)
	n1 := api.note(a, s1, 0)
	n2 := api.note(a, s2, 0)
	n3 := api.note(b, s1, 0)
	n4 := api.note(a, s1, 0)
	n5 := api.note(b, s2, 0)
	n6 := api.note(b, s2, 0)
	notes := [n1, n2, n3, n4, n5, n6]!
	api.enqueue(queue, n1, 3, 0)
	notification_queue_expect([n1])
	for note in notes { api.msg(queue, c'enqueueNotification:postingStyle:', note, 2, 0, 0) }
	notification_queue_expect([]u64{})
	api.checkpoint()
	notification_queue_expect([n1, n2, n3, n5])
	for mask in 0 .. 4 {
		for note in notes { api.enqueue(queue, note, 2, u64(mask)) }
		notification_queue_expect([]u64{})
		api.checkpoint()
		match mask {
			0 { notification_queue_expect([n1, n2, n3, n4, n5, n6]) }
			1 { notification_queue_expect([n1, n3]) }
			2 { notification_queue_expect([n1, n2]) }
			3 { notification_queue_expect([n1, n2, n3, n5]) }
			else {
				assert false
			}
		}
	}
	for mask in 0 .. 4 {
		for note in notes { api.enqueue(queue, note, 2, 0) }
		api.msg(queue, c'dequeueNotificationsMatching:coalesceMask:', n1, u64(mask), 0, 0)
		api.checkpoint()
		match mask {
			0 { notification_queue_expect([n1, n2, n3, n4, n5, n6]) }
			1 { notification_queue_expect([n3, n5, n6]) }
			2 { notification_queue_expect([n2, n5, n6]) }
			3 { notification_queue_expect([n2, n3, n5, n6]) }
			else {
				assert false
			}
		}
	}
	api.enqueue(queue, n1, 2, 0)
	api.enqueue(queue, n5, 2, 0)
	api.enqueue(queue, n4, 3, 3)
	notification_queue_expect([n4])
	api.checkpoint()
	notification_queue_expect([n5])
	api.msg(queue, c'dequeueNotificationsMatching:coalesceMask:', 0, 3, 0, 0)
	// Sender coalescing compares identity even when collection values are equal.
	first_array := api.msg(api.cls('NSMutableArray'), c'new', 0, 0, 0, 0)
	second_array := api.msg(api.cls('NSMutableArray'), c'new', 0, 0, 0, 0)
	array_note1 := api.note(a, first_array, 0)
	array_note2 := api.note(a, second_array, 0)
	api.enqueue(queue, array_note1, 2, 2)
	api.enqueue(queue, array_note2, 2, 2)
	api.checkpoint()
	notification_queue_expect([array_note1, array_note2])
	api.release(first_array)
	api.release(second_array)
	// Delivery preserves the notification and its mutable userInfo identity.
	info := api.msg(api.cls('NSMutableDictionary'), c'new', 0, 0, 0, 0)
	key := api.string('payload')
	value := api.string('changed before pump')
	info_note := api.note(a, s1, info)
	api.enqueue(queue, info_note, 2, 0)
	api.msg(info, c'setObject:forKey:', value, key, 0, 0)
	api.checkpoint()
	notification_queue_expect([info_note])
	assert api.msg(info_note, c'userInfo', 0, 0, 0, 0) == info
	assert api.msg(info, c'objectForKey:', key, 0, 0, 0) == value
	api.release(info)
	nil_sender := api.note(a, 0, 0)
	for mask in 0 .. 4 {
		api.enqueue(queue, nil_sender, 2, 0)
		api.enqueue(queue, n5, 2, 0)
		api.msg(queue, c'dequeueNotificationsMatching:coalesceMask:', 0, u64(mask), 0, 0)
		api.checkpoint()
		if mask == 2 {
			notification_queue_expect([n5])
		} else {
			notification_queue_expect([nil_sender, n5])
		}
	}
	nilqueue := api.queue(0)
	api.enqueue(nilqueue, n1, 3, 0)
	api.enqueue(nilqueue, n1, 2, 0)
	api.checkpoint()
	notification_queue_expect([]u64{})
	api.release(nilqueue)
	default_center := api.msg(api.cls('NSNotificationCenter'), c'defaultCenter', 0, 0, 0, 0)
	default_observer := notification_queue_observer(api, default_center)
	for operation in 0 .. 2 {
		plain := if operation == 0 {
			api.msg(cls, c'new', 0, 0, 0, 0)
		} else {
			api.msg(api.msg(cls, c'alloc', 0, 0, 0, 0), c'init', 0, 0, 0, 0)
		}
		api.enqueue(plain, n1, 3, 0)
		notification_queue_expect([n1])
		api.release(plain)
	}
	api.enqueue(default_queue, n2, 2, 0)
	notification_queue_expect([]u64{})
	api.checkpoint()
	notification_queue_expect([n2])
	api.msg(default_center, c'removeObserver:', default_observer, 0, 0, 0)
	api.release(default_observer)
	// Pending work owns both queue and exact original notification after all
	// caller ownership and setup autoreleases have disappeared.
	inner := api.pool()
	pending := api.queue(center)
	original := api.retain(api.note(a, s1, 0))
	mut weak_queue := u64(0)
	mut weak_note := u64(0)
	api.weak(unsafe { &weak_queue }, pending)
	api.weak(unsafe { &weak_note }, original)
	api.enqueue(pending, original, 2, 0)
	api.release(original)
	api.release(pending)
	api.pop(inner)
	assert api.weak_alive(unsafe { &weak_queue }) && api.weak_alive(unsafe { &weak_note })
	api.checkpoint()
	notification_queue_expect([original])
	assert !api.weak_alive(unsafe { &weak_queue }) && !api.weak_alive(unsafe { &weak_note })
	api.weak_destroy(unsafe { &weak_queue })
	api.weak_destroy(unsafe { &weak_note })
	// Removing all records releases the note immediately, while the run loop
	// retains the now-empty scheduled queue until its next checkpoint.
	setup := api.pool()
	cancelled := api.queue(center)
	cancel_note := api.retain(api.note(a, s1, 0))
	api.weak(unsafe { &weak_queue }, cancelled)
	api.weak(unsafe { &weak_note }, cancel_note)
	api.enqueue(cancelled, cancel_note, 2, 0)
	api.msg(cancelled, c'dequeueNotificationsMatching:coalesceMask:', cancel_note, 3, 0, 0)
	api.release(cancel_note)
	api.release(cancelled)
	api.pop(setup)
	assert api.weak_alive(unsafe { &weak_queue }) && !api.weak_alive(unsafe { &weak_note })
	api.checkpoint()
	notification_queue_expect([]u64{})
	assert !api.weak_alive(unsafe { &weak_queue })
	api.weak_destroy(unsafe { &weak_queue })
	api.weak_destroy(unsafe { &weak_note })
	// Dequeuing during a delivery does not retract the detached ready batch.
	notification_queue_callback_mode = 'dequeue'
	notification_queue_callback_fired = false
	notification_queue_callback_queue = queue
	notification_queue_callback_note = n5
	api.enqueue(queue, n1, 2, 0)
	api.enqueue(queue, n5, 2, 0)
	api.checkpoint()
	notification_queue_callback_mode = ''
	assert notification_queue_callback_fired
	notification_queue_expect([n1, n5])
	// A callback can append another batch, which is delivered by this pump.
	notification_queue_callback_mode = 'enqueue'
	notification_queue_callback_fired = false
	notification_queue_callback_queue = queue
	notification_queue_callback_note = n5
	api.enqueue(queue, n1, 2, 0)
	api.checkpoint()
	notification_queue_callback_mode = ''
	assert notification_queue_callback_fired
	notification_queue_expect([n1, n5])
	// The detached batch pins the queue across release of its last caller owner.
	callback_queue := api.queue(center)
	api.weak(unsafe { &weak_queue }, callback_queue)
	notification_queue_callback_mode = 'release'
	notification_queue_callback_fired = false
	notification_queue_callback_queue = callback_queue
	api.enqueue(callback_queue, n1, 2, 0)
	api.enqueue(callback_queue, n5, 2, 0)
	api.checkpoint()
	notification_queue_callback_mode = ''
	assert notification_queue_callback_fired
	notification_queue_expect([n1, n5])
	assert !api.weak_alive(unsafe { &weak_queue })
	api.weak_destroy(unsafe { &weak_queue })
	api.msg(center, c'removeObserver:', observer, 0, 0, 0)
	api.release(observer)
	api.release(s1)
	api.release(s2)
	api.release(queue)
	api.release(center)
	api.pop(pool)
}

fn notification_queue_runtime_api() NotificationQueueApi {
	return NotificationQueueApi{false, u64(unsafe { voidptr(C.ios_objc_msgsend) })}
}

__global notification_queue_fixture_mode = ''
__global notification_queue_fixture_target = u64(0)
__global notification_queue_fixture_receiver = u64(0)
__global notification_queue_fixture_note = u64(0)
__global notification_queue_fixture_fired = false
__global notification_queue_fixture_weak_result = u64(0)
__global notification_queue_fixture_weak_property = u64(0)
__global notification_queue_fixture_override_calls = 0

fn notification_queue_fixture_worker() {
	C.ios_objc_initialize_lock()
	C.ios_objc_initialize_unlock()
	if notification_queue_fixture_mode == 'receiver-release' {
		objc_release(notification_queue_fixture_receiver)
	}
}

fn notification_queue_fixture_constructor(object u64, _selector &char) u64 {
	if notification_queue_fixture_mode == '' || notification_queue_fixture_fired || read64(object) != notification_queue_fixture_target {
		return object
	}
	notification_queue_fixture_fired = true
	match notification_queue_fixture_mode {
		'fail' {
			objc_store_weak(unsafe { &notification_queue_fixture_weak_result }, object)
			property := objc_new(ios_runtime.names['NSObject'])
			obj_header(object).fields[3] = property
			objc_store_weak(unsafe { &notification_queue_fixture_weak_property }, property)
			return 0
		}
		'unlocked', 'receiver-release' {
			worker := spawn notification_queue_fixture_worker()
			worker.wait()
		}
		'constructor-isa' { objc_set_class(object, ios_runtime.names['NSObject']) }
		'constructor-storage' { obj_header(object).notification_queue.initialized = true }
		'recursive-default' { ns_notification_queue_default() }
		'recursive-center' {
			notification_queue_runtime_api().msg(ios_runtime.names['NSNotificationQueue'], c'new', 0, 0, 0, 0)
		}
		'receiver-opaque' {
			unsafe { *(&u64(voidptr(notification_queue_fixture_receiver + 8))) = 1 }
		}
		'dispose-initializer' { objc_destruct_instance(notification_queue_fixture_receiver) }
		else {
			assert false
		}
	}
	return object
}

fn notification_queue_fixture_destructor(object u64, _selector &char) {
	if notification_queue_fixture_mode != 'removed-reenter' || notification_queue_fixture_fired || object != notification_queue_fixture_target {
		return
	}
	notification_queue_fixture_fired = true
	// A worker taking the lock proves the release occurs after the queue's
	// structural mutation has committed and the runtime lock is available.
	worker := spawn notification_queue_fixture_worker()
	worker.wait()
	api := notification_queue_runtime_api()
	api.enqueue(notification_queue_fixture_receiver, notification_queue_fixture_note, 2, 0)
	api.release(notification_queue_fixture_receiver)
}

fn notification_queue_fixture_override(_object u64, _selector &char, _note u64, _style u64) {
	notification_queue_fixture_override_calls++
}

fn notification_queue_fixture_activate(mode string, target u64) {
	notification_queue_fixture_mode = mode
	notification_queue_fixture_target = target
	notification_queue_fixture_fired = false
}

fn notification_queue_runtime_lifetimes(api NotificationQueueApi) {
	pool := api.pool()
	cls := api.cls('NSNotificationQueue')
	library := '/System/Library/Frameworks/Foundation.framework/Foundation'
	assert runtime_symbol(library, '_OBJC_CLASS_$_NSNotificationQueue') or { panic(err) } == cls
	assert runtime_symbol(library, '_OBJC_METACLASS_$_NSNotificationQueue') or { panic(err) } == read64(cls)
	// The default center's constructor is an external callback from queue init.
	assert ios_runtime.notification_center == 0
	assert objc_add_method(api.cls('NSNotificationCenter'), u64(c'.cxx_construct'), u64(unsafe { voidptr(notification_queue_fixture_constructor) }), c'@16@0:8')
	notification_queue_fixture_activate('unlocked', api.cls('NSNotificationCenter'))
	initial := api.msg(cls, c'new', 0, 0, 0, 0)
	notification_queue_fixture_mode = ''
	assert notification_queue_fixture_fired
	api.release(initial)
	assert objc_add_method(cls, u64(c'.cxx_construct'), u64(unsafe { voidptr(notification_queue_fixture_constructor) }), c'@16@0:8')
	before_default := ios_runtime.objects.len
	notification_queue_fixture_activate('fail', cls)
	assert api.msg(cls, c'defaultQueue', 0, 0, 0, 0) == 0
	notification_queue_fixture_mode = ''
	assert notification_queue_fixture_fired && ios_runtime.notification_queue == 0 && !ios_runtime.notification_queue_initializing
	assert notification_queue_fixture_weak_result == 0 && notification_queue_fixture_weak_property == 0 && ios_runtime.objects.len == before_default
	objc_destroy_weak(unsafe { &notification_queue_fixture_weak_result })
	objc_destroy_weak(unsafe { &notification_queue_fixture_weak_property })
	center := api.msg(api.cls('NSNotificationCenter'), c'new', 0, 0, 0, 0)
	queue := api.queue(center)
	name := api.string('runtime.queue')
	note := api.note(name, 0, 0)
	// A void built-in leaves argument, floating and stack registers intact.
	mut frame := RegisterFrame{}
	for i in 0 .. frame.x.len { frame.x[i] = u64(0x1000 + i) }
	for i in 0 .. frame.q.len { frame.q[i] = u64(0x2000 + i) }
	frame.stack = 0x33445566
	frame.x[0] = queue
	frame.x[1] = u64(c'enqueueNotification:postingStyle:coalesceMask:forModes:')
	frame.x[2] = note
	frame.x[3] = 2
	frame.x[4] = 0
	frame.x[5] = 0
	saved := frame
	assert ns_notification_queue_dispatch(queue, 'enqueueNotification:postingStyle:coalesceMask:forModes:', mut frame)
	assert frame.x == saved.x && frame.q == saved.q && frame.stack == saved.stack
	assert ns_notification_queues_drain()
	// A getter changes only its result register.
	for i in 0 .. frame.x.len { frame.x[i] = u64(0x5000 + i) }
	getter_saved := frame
	assert ns_notification_queue_dispatch(cls, 'defaultQueue', mut frame) && frame.x[0] != 0
	for i in 1 .. frame.x.len {
		assert frame.x[i] == getter_saved.x[i]
	}
	assert frame.q == getter_saved.q && frame.stack == getter_saved.stack
	// Caller-owned bytes remain guarded and can be destroyed after an isa change.
	mut guarded := [u64(0x1122334455667788), 0, 0, 0, 0, 0x8877665544332211]!
	caller := u64(unsafe { &guarded[1] })
	assert objc_construct_instance(cls, caller) == caller
	assert api.msg(caller, c'initWithNotificationCenter:', center, 0, 0, 0) == caller
	assert read64(caller + 8) == 0 && read64(caller + 16) == 0 && read64(caller + 24) == 0
	objc_set_class(caller, api.cls('NSObject'))
	assert objc_destruct_instance(caller) == caller
	assert caller !in ios_runtime.objects && guarded[0] == 0x1122334455667788 && guarded[5] == 0x8877665544332211
	for _ in 0 .. 32 {
		item := api.queue(center)
		objc_set_class(item, api.cls('NSObject'))
		api.release(item)
	}
	// Failed constructors retire sidecars, owned fields, weak slots and headers.
	for operation in 0 .. 2 {
		before := ios_runtime.objects.len
		notification_queue_fixture_activate('fail', cls)
		result := if operation == 0 {
			api.msg(cls, c'alloc', 0, 0, 0, 0)
		} else {
			objc_construct_instance(cls, caller)
		}
		notification_queue_fixture_mode = ''
		assert result == 0 && notification_queue_fixture_fired && notification_queue_fixture_weak_result == 0 && notification_queue_fixture_weak_property == 0
		assert ios_runtime.objects.len == before && guarded[0] == 0x1122334455667788 && guarded[5] == 0x8877665544332211
		objc_destroy_weak(unsafe { &notification_queue_fixture_weak_result })
		objc_destroy_weak(unsafe { &notification_queue_fixture_weak_property })
	}
	// The removed note's final release can reenter, append new pending work and
	// consume the caller's queue ownership. The operation pin remains alive.
	assert objc_add_method(api.cls('NSNotification'), u64(c'.cxx_destruct'), u64(unsafe { voidptr(notification_queue_fixture_destructor) }), c'v16@0:8')
	observer := notification_queue_observer(api, center)
	inner := api.pool()
	reentrant := api.queue(center)
	old := api.retain(api.note(name, 0, 0))
	replacement := api.retain(api.note(name, 0, 0))
	api.enqueue(reentrant, old, 2, 0)
	api.pop(inner)
	mut weak_queue := u64(0)
	mut weak_old := u64(0)
	api.weak(unsafe { &weak_queue }, reentrant)
	api.weak(unsafe { &weak_old }, old)
	notification_queue_fixture_receiver = reentrant
	notification_queue_fixture_note = replacement
	notification_queue_fixture_activate('removed-reenter', old)
	api.release(old)
	api.msg(reentrant, c'dequeueNotificationsMatching:coalesceMask:', old, 3, 0, 0)
	notification_queue_fixture_mode = ''
	assert notification_queue_fixture_fired && weak_old == 0 && api.weak_alive(unsafe { &weak_queue })
	api.checkpoint()
	notification_queue_expect([replacement])
	assert weak_queue == 0
	api.release(replacement)
	api.weak_destroy(unsafe { &weak_queue })
	api.weak_destroy(unsafe { &weak_old })
	api.msg(center, c'removeObserver:', observer, 0, 0, 0)
	api.release(observer)
	// Concrete application methods keep their usual dispatch precedence.
	assert objc_replace_method(cls, u64(c'enqueueNotification:postingStyle:'), u64(unsafe { voidptr(notification_queue_fixture_override) }), c'v32@0:8@16Q24') != 0
	notification_queue_fixture_override_calls = 0
	api.msg(queue, c'enqueueNotification:postingStyle:', note, 2, 0, 0)
	assert notification_queue_fixture_override_calls == 1 && obj_header(queue).notification_queue.pending.len == 0
	api.release(queue)
	api.release(center)
	api.pop(pool)
}

fn notification_queue_shutdown_pending(api NotificationQueueApi) {
	pool := api.pool()
	center := api.msg(api.cls('NSNotificationCenter'), c'new', 0, 0, 0, 0)
	observer := notification_queue_observer(api, center)
	queue := api.queue(center)
	note := api.note(api.string('cancelled at shutdown'), 0, 0)
	api.enqueue(queue, note, 2, 0)
	api.release(queue)
	api.release(observer)
	api.release(center)
	api.pop(pool)
	assert ios_runtime.notification_queues.len == 1 && notification_queue_call_count == 0
	objc_stop()
	assert notification_queue_call_count == 0 && ios_runtime.notification_queue == 0 && ios_runtime.notification_queues.len == 0
	assert ios_runtime.objects.len == 0 && ios_runtime.live == 0
}

fn test_notification_queue_runtime() {
	for _ in 0 .. 2 {
		notification_queue_fixture_mode = ''
		notification_queue_callback_mode = ''
		notification_queue_call_count = 0
		objc_start()
		api := notification_queue_runtime_api()
		notification_queue_shared(api)
		// The lifetime suite needs the fresh center constructor path. Run it in a
		// separate drained runtime, retaining no state between repetitions.
		objc_stop()
		assert ios_runtime.objects.len == 0 && ios_runtime.live == 0
		objc_start()
		notification_queue_runtime_lifetimes(api)
		notification_queue_shutdown_pending(api)
	}
	println('IOS-NOTIFICATION-QUEUE: metadata, exact FIFO/coalescing identities, synchronous Now and deferred ASAP, nil filters/center, callback batches, pending ownership, unlocked constructor/removal callbacks, rollback, guarded storage, frame/native precedence, isa disposal and repeated drained shutdown cancellation')
}

fn notification_queue_reject_worker(queue u64) {
	notification_queue_runtime_api().enqueue(queue, 0, 2, 0)
}

fn test_notification_queue_rejections() {
	objc_start()
	api := notification_queue_runtime_api()
	cls := api.cls('NSNotificationQueue')
	modes := ['raw', 'repeat-init', 'subclass', 'caller-subclass', 'spoof', 'isa-change',
		'copy-provenance', 'tombstone', 'opaque-center', 'opaque-asap', 'opaque-idle', 'center-object',
		'center-class', 'center-spoof', 'center-isa', 'note-nil', 'note-object', 'note-class',
		'note-raw', 'note-spoof', 'note-isa', 'name-object', 'name-mutable', 'name-isa', 'name-utf8',
		'name-limit', 'idle', 'style-zero', 'style-high', 'mask-high', 'dequeue-mask', 'modes',
		'copy', 'coding', 'hash', 'description', 'worker', 'active-destruct', 'default-destruct',
		'reentrant-drain', 'pending-limit', 'scheduled-limit', 'constructor-isa', 'constructor-storage',
		'recursive-default', 'recursive-center', 'receiver-release', 'receiver-opaque',
		'dispose-initializer']!
	for mode in modes {
		mut fds := [2]i32{}
		assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.ios_fork()
		assert pid >= 0
		if pid == 0 {
			C.close(fds[0])
			assert C.dup2(fds[1], 2) == 2
			C.close(fds[1])
			pool := api.pool()
			center := api.msg(api.cls('NSNotificationCenter'), c'new', 0, 0, 0, 0)
			queue := api.queue(center)
			name := api.string('reject.queue')
			note := api.note(name, 0, 0)
			notification_queue_fixture_mode = ''
			notification_queue_callback_mode = ''
			match mode {
				'raw' { api.enqueue(objc_allocate(cls), note, 2, 0) }
				'repeat-init' { api.msg(queue, c'initWithNotificationCenter:', center, 0, 0, 0) }
				'subclass', 'caller-subclass' {
					custom := objc_allocate_class(cls, c'VinixUnsupportedNotificationQueue', 0)
					objc_register_class(custom)
					if mode == 'subclass' {
						objc_allocate(custom)
					} else {
						mut bytes := [4]u64{}
						objc_construct_instance(custom, u64(unsafe { &bytes[0] }))
					}
				}
				'spoof' {
					wrong := objc_new(api.cls('NSObject'))
					objc_set_class(wrong, cls)
					api.enqueue(wrong, note, 2, 0)
				}
				'isa-change' {
					objc_set_class(queue, api.cls('NSObject'))
					api.enqueue(queue, note, 2, 0)
				}
				'copy-provenance' {
					objc_set_class(queue, api.cls('NSURLRequest'))
					objc_copy_value(queue, false)
				}
				'tombstone' {
					mut bytes := [4]u64{}
					caller := objc_construct_instance(cls, u64(unsafe { &bytes[0] }))
					api.msg(caller, c'initWithNotificationCenter:', center, 0, 0, 0)
					objc_destruct_instance(caller)
					api.enqueue(caller, note, 2, 0)
				}
				'opaque-center', 'opaque-asap', 'opaque-idle' {
					offset := if mode == 'opaque-center' {
						u64(8)
					} else if mode == 'opaque-asap' {
						u64(16)
					} else {
						u64(24)
					}
					unsafe { *(&u64(voidptr(queue + offset))) = 1 }
					api.enqueue(queue, note, 2, 0)
				}
				'center-object', 'center-class', 'center-spoof', 'center-isa' {
					mut value := if mode == 'center-class' {
						api.cls('NSNotificationCenter')
					} else if mode == 'center-object' {
						objc_new(api.cls('NSObject'))
					} else {
						api.msg(api.cls('NSNotificationCenter'), c'new', 0, 0, 0, 0)
					}
					if mode == 'center-spoof' {
						value = objc_new(api.cls('NSObject'))
						objc_set_class(value, api.cls('NSNotificationCenter'))
					}
					if mode == 'center-isa' { objc_set_class(value, api.cls('NSObject')) }
					api.queue(value)
				}
				'note-nil', 'note-object', 'note-class', 'note-raw', 'note-spoof', 'note-isa' {
					mut value := if mode == 'note-nil' {
						u64(0)
					} else if mode == 'note-object' {
						objc_new(api.cls('NSObject'))
					} else if mode == 'note-class' {
						api.cls('NSNotification')
					} else if mode == 'note-raw' {
						objc_allocate(api.cls('NSNotification'))
					} else {
						note
					}
					if mode == 'note-spoof' {
						value = objc_new(api.cls('NSObject'))
						objc_set_class(value, api.cls('NSNotification'))
					}
					if mode == 'note-isa' { objc_set_class(value, api.cls('NSObject')) }
					api.enqueue(queue, value, 2, 0)
				}
				'name-object', 'name-mutable', 'name-isa', 'name-utf8', 'name-limit' {
					mut value := if mode == 'name-object' {
						objc_new(api.cls('NSObject'))
					} else if mode == 'name-mutable' {
						api.msg(api.msg(api.cls('NSMutableString'), c'alloc', 0, 0, 0, 0), c'initWithString:', name, 0, 0, 0)
					} else if mode == 'name-limit' {
						api.string('x'.repeat(65537))
					} else {
						owned_string('name')
					}
					if mode == 'name-isa' { objc_set_class(value, api.cls('NSObject')) }
					if mode == 'name-utf8' { unsafe { obj_header(value).text[0] = char(0xff) } }
					api.enqueue(queue, api.note(value, 0, 0), 2, 0)
				}
				'idle', 'style-zero', 'style-high' {
					api.enqueue(queue, note, if mode == 'idle' {
						u64(1)
					} else if mode == 'style-zero' {
						u64(0)
					} else {
						u64(0x100000002)
					}, 0)
				}
				'mask-high' { api.enqueue(queue, note, 2, 4) }
				'dequeue-mask' {
					api.msg(queue, c'dequeueNotificationsMatching:coalesceMask:', note, 4, 0, 0)
				}
				'modes' {
					api.msg(queue, c'enqueueNotification:postingStyle:coalesceMask:forModes:', note, 2, 0, api.msg(api.cls('NSArray'), c'array', 0, 0, 0, 0))
				}
				'copy' { api.msg(queue, c'copy', 0, 0, 0, 0) }
				'coding' { api.msg(queue, c'encodeWithCoder:', 0, 0, 0, 0) }
				'hash' { api.msg(queue, c'hash', 0, 0, 0, 0) }
				'description' { api.msg(queue, c'description', 0, 0, 0, 0) }
				'worker' {
					worker := spawn notification_queue_reject_worker(queue)
					worker.wait()
				}
				'active-destruct' {
					api.enqueue(queue, note, 2, 0)
					objc_destruct_instance(queue)
				}
				'default-destruct' {
					objc_destruct_instance(api.msg(cls, c'defaultQueue', 0, 0, 0, 0))
				}
				'reentrant-drain' {
					notification_queue_observer(api, center)
					notification_queue_callback_mode = 'reenter'
					notification_queue_callback_fired = false
					api.enqueue(queue, note, 2, 0)
					api.checkpoint()
				}
				'pending-limit' {
					for _ in 0 .. 4097 { api.enqueue(queue, note, 2, 0) }
				}
				'scheduled-limit' {
					for _ in 0 .. 257 {
						other := api.queue(center)
						api.enqueue(other, note, 2, 0)
					}
				}
				'constructor-isa', 'constructor-storage', 'recursive-default' {
					assert objc_add_method(cls, u64(c'.cxx_construct'), u64(unsafe { voidptr(notification_queue_fixture_constructor) }), c'@16@0:8')
					notification_queue_fixture_activate(mode, cls)
					if mode == 'recursive-default' {
						api.msg(cls, c'defaultQueue', 0, 0, 0, 0)
					} else {
						api.msg(cls, c'new', 0, 0, 0, 0)
					}
				}
				'recursive-center', 'receiver-release', 'receiver-opaque', 'dispose-initializer' {
					assert objc_add_method(api.cls('NSNotificationCenter'), u64(c'.cxx_construct'), u64(unsafe { voidptr(notification_queue_fixture_constructor) }), c'@16@0:8')
					receiver := api.msg(cls, c'alloc', 0, 0, 0, 0)
					notification_queue_fixture_receiver = receiver
					notification_queue_fixture_activate(mode, api.cls('NSNotificationCenter'))
					api.msg(receiver, c'init', 0, 0, 0, 0)
				}
				else {
					assert false
				}
			}
			api.pop(pool)
			C.exit(73)
		}
		C.close(fds[1])
		mut bytes := [16384]u8{}
		mut length := 0
		for {
			assert length < bytes.len
			count := C.read(fds[0], unsafe { &bytes[length] }, usize(bytes.len - length))
			if count == 0 { break }
			if count < 0 && unsafe { *C.ios_errno_address() } == C.EINTR { continue }
			assert count > 0
			length += int(count)
		}
		C.close(fds[0])
		mut status := i32(0)
		assert C.ios_waitpid(pid, &status, 0) == pid
		output := unsafe { tos(&bytes[0], length) }
		assert status == 256 && output.contains('iOS:') && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
	}
	objc_stop()
	assert ios_runtime.live == 0
	println('IOS-NOTIFICATION-QUEUE-REJECT:' + modes.len.str() + ' storage/provenance, opaque slots, payload/mode/style/domain, worker/recursive drain, active destruction, constructor mutation and bounded scheduling failures are explicit')
}

fn test_notification_queue_native() {
	$if macos {
		api := NotificationQueueApi{true, u64(C.dlsym(unsafe { voidptr(-2) }, c'objc_msgSend'))}
		assert api.send != 0
		notification_queue_shared(api)
		println('IOS-NOTIFICATION-QUEUE-NATIVE: layout/encodings, main default queue, exact synchronous/deferred note identity, coalescing/dequeue matrices, sender/info identities, pending/cancelled ownership and callback batches')
	}
}
