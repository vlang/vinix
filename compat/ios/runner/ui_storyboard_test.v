// SPDX-License-Identifier: GPL-2.0-or-later
module main

import os

type StoryboardSend = fn (u64, u64, u64, u64) u64

fn storyboard_msg(object u64, selector &char, a u64, b u64) u64 {
	return unsafe { StoryboardSend(voidptr(C.ios_objc_msgsend))(object, u64(selector), a, b) }
}

const storyboard_test_source = '<?xml version="1.0"?><document initialViewController="xml-first"><scenes><scene><objects>
<viewController id="xml-first" storyboardIdentifier="First"><view><rect key="frame" x="1" y="2" width="320" height="480"/>
<color key="backgroundColor" white="1"/><subviews><button><rect x="3" y="4" width="100" height="40"/>
<state key="normal" title="Play &amp; &quot;Go&quot;"/><connections><action selector="play:" destination="xml-first" eventType="touchUpInside"/></connections>
</button></subviews></view></viewController>
<viewController id="xml-second" storyboardIdentifier="Second" customClass="VinixStoryboardController"><view/></viewController>
</objects></scene></scenes></document>'

fn storyboard_test_bundle() string {
	path := os.join_path(os.temp_dir(), 'vinix-storyboard-' + os.getpid().str())
	os.mkdir_all(path + '/Base.lproj') or { panic(err) }
	os.write_file(path + '/Base.lproj/Main.storyboard', storyboard_test_source) or { panic(err) }
	return path
}

fn storyboard_test_graph(controller u64) {
	assert read64(controller) == ios_runtime.names['UIViewController']
	view := obj_header(controller).fields[6]
	assert view != 0 && obj_header(view).frame == ObjRect{1, 2, 320, 480}
	assert obj_header(obj_header(view).fields[2]).color == 0xffffff
	assert obj_header(view).child_count == 1
	button := obj_header(view).children[0]
	assert read64(button) == ios_runtime.names['UIButton']
	assert obj_header(button).target == controller
	assert ctext(obj_header(button).action) == 'play:'
	assert string_text(obj_header(obj_header(button).fields[5]).fields[0]) == 'Play & "Go"'
}

fn storyboard_nil_init(object u64, _ u64) u64 {
	objc_release(object)
	return 0
}

fn storyboard_wrong_init(object u64, _ u64) u64 {
	objc_release(object)
	return objc_new(ios_runtime.names['NSObject'])
}

fn storyboard_unmanaged_init(object u64, _ u64) u64 {
	objc_release(object)
	return ios_runtime.names['UIViewController']
}

fn test_ui_storyboard() {
	for _ in 0 .. 2 {
		objc_start()
		path := storyboard_test_bundle()
		ios_runtime.bundle = path
		pool := objc_pool_push()
		cls := ios_runtime.names['UIStoryboard']
		sub := objc_allocate_class(ios_runtime.names['UIViewController'], c'VinixStoryboardController', 0)
		objc_register_class(sub)
		for prefix in ['_OBJC_CLASS_$_', '_OBJC_METACLASS_$_']! {
			symbol := prefix + 'UIStoryboard'
			assert runtime_symbol('/System/Library/Frameworks/UIKit.framework/UIKit', symbol)! == if prefix == '_OBJC_CLASS_$_' { cls } else { read64(cls) }
			if _ := runtime_symbol('/System/Library/Frameworks/Foundation.framework/Foundation', symbol) { assert false }
		}
		assert objc_class_size(cls) == 8 && objc_class_parent(cls) == ios_runtime.names['NSObject']
		name := owned_string('Main')
		object := storyboard_msg(cls, c'storyboardWithName:bundle:', name, 0)
		assert object != 0 && obj_header(object).refs == 1
		bundle := storyboard_msg(ios_runtime.names['NSBundle'], c'mainBundle', 0, 0)
		second_storyboard := storyboard_msg(cls, c'storyboardWithName:bundle:', name, bundle)
		assert second_storyboard != object
		objc_release(name)
		for meta in [false, true]! {
			for selector in ['storyboardWithName:bundle:', 'instantiateInitialViewController', 'instantiateViewControllerWithIdentifier:']! {
				method := if meta { objc_class_method(cls, u64(selector.str)) } else { objc_instance_method(cls, u64(selector.str)) }
				receiver := if meta { cls } else { object }
				if types := storyboard_types('UIStoryboard', meta, selector) {
					assert method != 0 && ctext(u64(objc_method_types(method))) == types
					assert objc_responds(receiver, selector.str)
					signature := storyboard_msg(receiver, c'methodSignatureForSelector:', u64(selector.str), 0)
					assert storyboard_msg(signature, c'numberOfArguments', 0, 0) == u64(2 + selector.count(':'))
				} else { assert method == 0 && !objc_responds(receiver, selector.str) }
			}
		}
		for selector in [c'alloc', c'new', c'init', c'copy', c'mutableCopy', c'initWithCoder:', c'encodeWithCoder:', c'supportsSecureCoding', c'classForCoder', c'instantiateInitialViewControllerWithCreator:', c'instantiateViewControllerWithIdentifier:creator:']! {
			assert !objc_responds(object, selector) && !objc_responds(cls, selector)
			assert objc_instance_method(cls, u64(selector)) == 0 && objc_class_method(cls, u64(selector)) == 0
		}
		// Instances own immutable snapshots, even after their source is removed.
		os.rm(path + '/Base.lproj/Main.storyboard')!
		controller := storyboard_msg(object, c'instantiateInitialViewController', 0, 0)
		storyboard_test_graph(controller)
		first_name := owned_string('First')
		fresh := storyboard_msg(object, c'instantiateViewControllerWithIdentifier:', first_name, 0)
		objc_release(first_name)
		assert fresh != controller && obj_header(fresh).fields[6] != obj_header(controller).fields[6]
		storyboard_test_graph(fresh)
		second_name := owned_string('Second')
		custom := storyboard_msg(object, c'instantiateViewControllerWithIdentifier:', second_name, 0)
		objc_release(second_name)
		assert read64(custom) == sub && obj_header(custom).fields[6] != 0
		// Keep one independent graph after the resource/parser has been destroyed.
		objc_retain(controller)
		objc_pool_pop(pool)
		storyboard_test_graph(controller)
		objc_release(controller)
		assert ios_runtime.live == 1 // Cached main bundle.
		// Root fallback and no initial controller are supported.
		os.write_file(path + '/Empty.storyboard', '<document/>')!
		empty := storyboard_open('Empty', 0)!
		assert storyboard_msg(empty, c'instantiateInitialViewController', 0, 0) == 0
		objc_release(empty)
		objc_stop()
		assert ios_runtime.live == 0 && ios_runtime.objects.len == 0
		os.rmdir_all(path)!
	}
	println('IOS-STORYBOARD: scoped imports, typed reflection, main-bundle factories, immutable snapshots, fresh and custom controllers, views/actions, root fallback and two drained runtimes')
}

fn test_ui_storyboard_xml() {
	for text in ['<document title="&amp;&lt;&gt;&quot;&apos;"/>', '<!--comment--><document><scene/></document>']! {
		root := storyboard_parse(text)!
		if root.attributes.len > 0 { assert root.attributes['title'] == '&<>"\'' }
		storyboard_node_free(root)
	}
	for text in ['', '<document>', '<document a="x" a="y"/>', '<document a=x/>',
		'<document><a></b></document>', '<document/>tail', '<wrong/>',
		'<!DOCTYPE document SYSTEM "file:///etc/passwd"><document/>',
		'<document a="&unknown;"/>', '<document a="&#65;"/>', '<document><![CDATA[x]]></document>',
		'<document a="<"/>', '<document>text</document>', '<!--unfinished',
		'<document a="unfinished', '<document a="x"b="y"/>',
		'<document>' + '<a>'.repeat(66) + '</a>'.repeat(66) + '</document>',
		'<document>' + '<a/>'.repeat(4096) + '</document>'] {
		if node := storyboard_parse(text) { storyboard_node_free(node); assert false, text }
	}
	objc_start()
	pool := objc_pool_push()
	for index, implementation in [u64(unsafe { voidptr(storyboard_nil_init) }),
		u64(unsafe { voidptr(storyboard_wrong_init) }), u64(unsafe { voidptr(storyboard_unmanaged_init) })]! {
		name := 'VinixStoryboardBadInit' + index.str()
		cls := objc_allocate_class(ios_runtime.names['UIViewController'], name.str, 0)
		assert objc_add_method(cls, u64(c'init'), implementation, c'@16@0:8')
		objc_register_class(cls)
		root := storyboard_parse('<document><viewController id="bad" customClass="' + name + '"><view/></viewController></document>')!
		if controller := storyboard_controller(root, 'id', 'bad') { objc_release(controller); assert false }
		storyboard_node_free(root)
		assert ios_runtime.live == 0
	}
	for view in ['<view><subviews><view/><unsupported/></subviews></view>', '<view customClass="Unknown"/>',
		'<view><subviews>' + '<view/>'.repeat(65) + '</subviews></view>'] {
		root := storyboard_parse('<document><viewController id="bad">' + view + '</viewController></document>')!
		if controller := storyboard_controller(root, 'id', 'bad') { objc_release(controller); assert false }
		storyboard_node_free(root)
	}
	objc_pool_pop(pool)
	objc_stop()
	assert ios_runtime.live == 0
	println('IOS-STORYBOARD-XML: bounded parser rejects malformed XML, DTDs/entities, text, depth/nodes; partial view failures release their graphs')
}

fn test_ui_storyboard_rejections() {
	objc_start()
	path := storyboard_test_bundle()
	ios_runtime.bundle = path
	cls := ios_runtime.names['UIStoryboard']
	object := storyboard_open('Main', 0)!
	for mode in ['alloc', 'new', 'init', 'copy', 'initWithCoder:', 'instantiateInitialViewControllerWithCreator:',
		'allocate', 'caller', 'subclass', 'isa-out', 'isa-in', 'nil-name', 'wrong-name', 'wrong-bundle',
		'escape', 'missing', 'xml-id', 'empty-id', 'nil-id', 'corrupt-storage']! {
		mut fds := [2]i32{}
		assert C.pipe(unsafe { &fds[0] }) == 0
		pid := C.fork()
		assert pid >= 0
		if pid == 0 {
			C.close(fds[0]); assert C.dup2(fds[1], 2) == 2; C.close(fds[1])
			match mode {
				'allocate' { objc_allocate(cls) }
				'caller' { mut storage := [1]u64{}; objc_construct_instance(cls, u64(unsafe { &storage[0] })) }
				'subclass' {
					sub := objc_allocate_class(cls, c'VinixStoryboard', 0); objc_register_class(sub)
					storyboard_msg(sub, c'storyboardWithName:bundle:', owned_string('Main'), 0)
				}
				'isa-out' { objc_set_class(object, ios_runtime.names['NSObject']) }
				'isa-in' { objc_set_class(objc_allocate(ios_runtime.names['NSObject']), cls) }
				'nil-name', 'wrong-name', 'wrong-bundle', 'escape', 'missing' {
					name := match mode {
						'nil-name' { u64(0) }
						'wrong-name' { objc_allocate(ios_runtime.names['NSObject']) }
						'escape' { owned_string('../Main') }
						'missing' { owned_string('Compiled') }
						else { owned_string('Main') }
					}
					storyboard_msg(cls, c'storyboardWithName:bundle:', name, if mode == 'wrong-bundle' { objc_allocate(ios_runtime.names['NSBundle']) } else { u64(0) })
				}
				'xml-id', 'empty-id', 'nil-id' {
					storyboard_msg(object, c'instantiateViewControllerWithIdentifier:', if mode == 'nil-id' { u64(0) } else { owned_string(if mode == 'xml-id' { 'xml-first' } else { '' }) }, 0)
				}
				'corrupt-storage' { obj_header(object).native_size = 16; storyboard_msg(object, c'instantiateInitialViewController', 0, 0) }
				'alloc', 'new' { storyboard_msg(cls, mode.str, 0, 0) }
				else { storyboard_msg(object, mode.str, 0, 0) }
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
		reason := match mode {
			'allocate', 'caller' { 'requires storyboardWithName:bundle:' }
			'subclass' { 'custom storyboard subclasses are unsupported' }
			'isa-in', 'isa-out' { 'changing storyboard storage isa' }
			'nil-name', 'wrong-name', 'nil-id' { 'requires an NSString argument' }
			'wrong-bundle' { 'requires the main bundle' }
			'escape' { 'invalid storyboard resource name' }
			'missing' { 'compiled storyboardc resources are unsupported' }
			'xml-id' { 'controller identifier is missing or ambiguous' }
			'empty-id' { 'controller identifier is empty' }
			'corrupt-storage' { 'requires live built-in storage' }
			else { 'unsupported storyboard construction, coding or creator method' }
		}
		assert output.contains(reason) && !output.contains('AddressSanitizer') && !output.contains('runtime error:'), mode + ': ' + output
	}
	objc_release(object)
	objc_stop()
	assert ios_runtime.live == 0
	os.rmdir_all(path)!
	println('IOS-STORYBOARD-REJECT: 20 construction, subclass, caller/isa, argument, resource, identifier and corrupt-storage cases fail explicitly')
}
