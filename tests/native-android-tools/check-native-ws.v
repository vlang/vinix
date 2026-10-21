// SPDX-License-Identifier: GPL-2.0-or-later
// JNI widths and mangling must agree with ART, including overloaded methods.
module main

import androidtools

fn main() {
	assert androidtools.native_ws_abi('IIJFFFF')! == ['i32', 'i32', 'i64', 'f32', 'f32', 'f32',
		'f32']
	assert androidtools.native_ws_abi('ZBCSIJFD')! == ['u8', 'u8', 'u16', 'i16', 'i32', 'i64',
		'f32', 'f64']
	assert androidtools.native_ws_abi('[[ILjava/lang/String;[B')! == ['voidptr', 'voidptr', 'voidptr']
	assert androidtools.native_ws_abi('V')! == ['']
	assert androidtools.native_ws_abi('')! == []string{}
	assert androidtools.native_ws_jni_escape('android/view/View$Listener') == 'android_view_View_00024Listener'
	assert androidtools.native_ws_jni_escape('native_create') == 'native_1create'
	assert androidtools.native_ws_jni_escape('[Ljava/lang/String;') == '_3Ljava_lang_String_2'
	assert androidtools.native_ws_jni_escape('ö') == '_000f6'
	assert androidtools.native_ws_jni_escape('😀') == '_0d83d_0de00'
	for descriptor in ['L', 'L;', '[', '[[', '[V', '?', 'VI', '[Lfoo'] {
		mut rejected := false
		androidtools.native_ws_abi(descriptor) or { rejected = true }
		assert rejected, descriptor
	}
	println('ANDROID-WS-ABI-PASS widths mangling overloads invalid-descriptors')
}
