// SPDX-License-Identifier: GPL-2.0-or-later
module main

import math.bits

type SnapshotConfigurationSend = fn (u64, u64, u64, u64) u64
type SnapshotConfigurationGet = fn (u64, u64) ObjRect
type SnapshotConfigurationSet = fn (u64, u64, ObjRect)

fn snapshot_msg(object u64, selector &char, argument u64) u64 {
	return unsafe { SnapshotConfigurationSend(voidptr(C.ios_objc_msgsend))(object, u64(selector), argument, 0) }
}

fn snapshot_rect(object u64) ObjRect {
	return unsafe { SnapshotConfigurationGet(voidptr(C.ios_objc_msgsend))(object, u64(c'rect')) }
}

fn snapshot_set_rect(object u64, rect ObjRect) {
	unsafe { SnapshotConfigurationSet(voidptr(C.ios_objc_msgsend))(object, u64(c'setRect:'), rect) }
}

fn snapshot_assert_default(object u64) {
	value := snapshot_rect(object)
	assert bits.f64_bits(value.x) == 0x7ff0000000000000 && bits.f64_bits(value.y) == 0x7ff0000000000000
	assert bits.f64_bits(value.width) == 0 && bits.f64_bits(value.height) == 0
	assert snapshot_msg(object, c'afterScreenUpdates', 0) == 1
}

fn test_snapshot_configuration_objects() {
	for _ in 0 .. 2 {
		objc_start()
		pool := objc_pool_push()
		cls := ios_runtime.names['WKSnapshotConfiguration']
		assert objc_class_size(cls) == 56 && objc_class_parent(cls) == ios_runtime.names['NSObject']
		assert !objc_class_meta(cls) && objc_class_meta(read64(cls))
		assert snapshot_configuration_family(cls) && snapshot_configuration_family(read64(cls))
		for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
			symbol := prefix + 'WKSnapshotConfiguration'
			assert runtime_symbol('/System/Library/Frameworks/WebKit.framework/WebKit', symbol)! == if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
			for wrong in ['/usr/lib/libobjc.A.dylib', '/System/Library/Frameworks/Foundation.framework/Foundation', '/System/Library/Frameworks/UIKit.framework/UIKit']! {
				if _ := runtime_symbol(wrong, symbol) { assert false, wrong }
			}
		}
		for i, name in ['_usesTransparentBackground', '_afterScreenUpdates', '_snapshotWidth', '_rect']! {
			ivar := objc_find_ivar(cls, name.str)
			assert ivar != 0 && objc_ivar_offset(ivar) == [i64(8), 9, 16, 24]![i]
			assert ctext(u64(objc_ivar_types(ivar))) == ['B', 'B', '@"NSNumber"', '{CGRect="origin"{CGPoint="x"d"y"d}"size"{CGSize="width"d"height"d}}']![i]
		}
		for i, selector in ['init', 'copy', 'copyWithZone:', 'rect', 'setRect:', 'snapshotWidth', 'setSnapshotWidth:', 'afterScreenUpdates', 'setAfterScreenUpdates:']! {
			method := objc_instance_method(cls, u64(selector.str))
			assert method != 0
			assert ctext(u64(objc_method_types(method))) == ['@16@0:8', '@16@0:8', '@24@0:8^{_NSZone=}16', '{CGRect={CGPoint=dd}{CGSize=dd}}16@0:8', 'v48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16', '@16@0:8', 'v24@0:8@16', 'B16@0:8', 'v20@0:8B16']![i]
		}
		baseline := ios_runtime.live
		object := snapshot_msg(cls, c'new', 0)
		snapshot_assert_default(object)
		assert snapshot_msg(object, c'snapshotWidth', 0) == 0
		allocated := snapshot_msg(cls, c'alloc', 0)
		init_method := objc_instance_method(ios_runtime.names['NSObject'], u64(c'init'))
		assert unsafe { SnapshotConfigurationSend(voidptr(objc_method_imp(init_method)))(allocated, u64(c'init'), 0, 0) } == allocated
		snapshot_assert_default(allocated)
		objc_release(allocated)
		value := ObjRect{1.25, -2.5, 320.5, 240.25}
		snapshot_set_rect(object, value)
		assert snapshot_rect(object) == value
		mut width_value := i64(640)
		width := cf_number_create(0, 4, u64(&width_value))
		assert obj_header(width).refs == 1
		snapshot_msg(object, c'setSnapshotWidth:', width)
		snapshot_msg(object, c'setSnapshotWidth:', width)
		assert obj_header(width).refs == 2 && read64(object + 16) == width
		snapshot_msg(object, c'setAfterScreenUpdates:', 0)
		assert snapshot_msg(object, c'afterScreenUpdates', 0) == 0 && unsafe { *(&u8(object + 9)) } == 0
		for mode in 0 .. 5 {
			copy_method := objc_instance_method(ios_runtime.names['NSObject'], u64(c'copy'))
			duplicate := match mode {
				0 { snapshot_msg(object, c'copy', 0) }
				1 { snapshot_msg(object, c'copyWithZone:', 0) }
				2 { objc_copy_value(object, false) }
				3 { objc_copy_value(object, true) }
				else { unsafe { SnapshotConfigurationSend(voidptr(objc_method_imp(copy_method)))(object, u64(c'copy'), 0, 0) } }
			}
			assert duplicate != 0 && duplicate != object && snapshot_rect(duplicate) == value
			assert snapshot_msg(duplicate, c'snapshotWidth', 0) == width && obj_header(width).refs == 3
			assert snapshot_msg(duplicate, c'afterScreenUpdates', 0) == 0
			snapshot_msg(object, c'setSnapshotWidth:', 0)
			assert snapshot_msg(duplicate, c'snapshotWidth', 0) == width && obj_header(width).refs == 2
			snapshot_set_rect(duplicate, ObjRect{9, 8, 7, 6})
			snapshot_msg(duplicate, c'setAfterScreenUpdates:', 1)
			assert snapshot_rect(object) == value && snapshot_msg(object, c'afterScreenUpdates', 0) == 0
			snapshot_msg(object, c'setSnapshotWidth:', width)
			objc_release(duplicate)
			assert obj_header(width).refs == 2
		}
		for raw in [u64(0), 0x8000000000000000, 0xbff0000000000000, 0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000000001234]! {
			v := bits.f64_from_bits(raw)
			snapshot_set_rect(object, ObjRect{v, v, v, v})
			got := snapshot_rect(object)
			assert bits.f64_bits(got.x) == raw && bits.f64_bits(got.y) == raw
			assert bits.f64_bits(got.width) == raw && bits.f64_bits(got.height) == raw
			duplicate := objc_copy_value(object, false)
			for i in 0 .. 4 { assert read64(duplicate + 24 + u64(i * 8)) == raw }
			objc_release(duplicate)
		}
		assert snapshot_msg(object, c'init', 0) == object
		snapshot_assert_default(object)
		assert snapshot_msg(object, c'snapshotWidth', 0) == width && obj_header(width).refs == 2
		mut replacement_value := i64(1280)
		replacement := cf_number_create(0, 4, u64(&replacement_value))
		snapshot_msg(object, c'setSnapshotWidth:', replacement)
		assert obj_header(width).refs == 1 && obj_header(replacement).refs == 2
		objc_release(width)
		objc_release(replacement)
		assert width !in ios_runtime.objects
		for selector in ['mutableCopy', 'mutableCopyWithZone:', 'initWithCoder:', 'encodeWithCoder:', 'supportsSecureCoding', 'classForCoder', '_usesTransparentBackground', '_setUsesTransparentBackground:']! {
			assert objc_instance_method(cls, u64(selector.str)) == 0 && !objc_responds(object, selector.str)
			assert objc_class_method(cls, u64(selector.str)) == 0 && !objc_responds(cls, selector.str)
		}
		objc_autorelease(object)
		objc_pool_pop(pool)
		assert replacement !in ios_runtime.objects && ios_runtime.live == baseline
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	}
	println('IOS-WKSNAPSHOT: scoped imports, native metadata, CGRect HFA bits, copied widths, independent copies and two drained runtimes')
}

fn test_snapshot_configuration_rejections() {
	objc_start()
	cls := ios_runtime.names['WKSnapshotConfiguration']
	sub := objc_allocate_class(cls, c'BlockedSnapshotConfiguration', 0)
	objc_register_class(sub)
	for mode in ['subclass', 'metaclass', 'caller', 'install', 'isa-in', 'isa-out', 'raw-getter', 'raw-copy', 'direct-copy', 'invalid-storage', 'forged-isa', 'invalid-width', 'mutableCopy', 'initWithCoder:', '_usesTransparentBackground']! {
		mut fds := [2]i32{}
		assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork()
		assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			match mode {
				'subclass' { objc_allocate(sub) }
				'metaclass' { objc_allocate(read64(cls)) }
				'caller' { mut storage := [7]u64{}; objc_construct_instance(cls, u64(unsafe { &storage[0] })) }
				'install' { mut storage := [7]u64{}; objc_install_storage(cls, u64(unsafe { &storage[0] }), true) }
				'isa-in' { objc_set_class(objc_allocate(ios_runtime.names['NSObject']), cls) }
				'isa-out' { objc_set_class(objc_allocate(cls), ios_runtime.names['NSObject']) }
				'raw-getter' { snapshot_rect(objc_allocate(cls)) }
				'raw-copy' { snapshot_msg(objc_allocate(cls), c'copy', 0) }
				'direct-copy' { objc_copy_value(objc_allocate(cls), true) }
				'invalid-storage' {
					object := snapshot_msg(cls, c'new', 0)
					obj_header(object).caller_storage = true
					snapshot_rect(object)
				}
				'forged-isa' {
					object := objc_allocate(ios_runtime.names['NSObject'])
					unsafe { *(&u64(object)) = cls }
					snapshot_rect(object)
				}
				'invalid-width' { snapshot_msg(snapshot_msg(cls, c'new', 0), c'setSnapshotWidth:', owned_string('640')) }
				else { snapshot_msg(snapshot_msg(cls, c'new', 0), mode.str, 0) }
			}
			C._exit(0)
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
		assert C.ios_waitpid(pid, &status, 0) == pid && status == 256, mode
		output := unsafe { tos(&bytes[0], length) }
		reason := if mode in ['subclass', 'metaclass']! { 'subclass or metaclass construction is not implemented' } else if mode in ['caller', 'install']! { 'caller storage is not implemented' } else if mode.starts_with('isa-') { 'changing WKSnapshotConfiguration storage isa is not implemented' } else if mode in ['raw-getter', 'raw-copy', 'direct-copy']! { 'requires initialization' } else if mode in ['invalid-storage', 'forged-isa']! { 'requires live owned configuration storage' } else if mode == 'invalid-width' { 'snapshotWidth requires a live builtin NSNumber' } else { 'unsupported WKSnapshotConfiguration method:' }
		assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:') && !output.contains('> assert '), mode + ': ' + output
	}
	objc_stop()
	assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
	println('IOS-WKSNAPSHOT-REJECT: 15 subclass, metaclass, caller storage, isa, initialization, copying, width and unsupported method cases fail explicitly')
}
