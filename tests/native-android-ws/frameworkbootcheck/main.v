// SPDX-License-Identifier: GPL-2.0-or-later
module main

#include <stdio.h>
fn C.snprintf(&char, usize, &char, ...) i32

const sentinel = u8(0xa5)

// This list is the independently stated runtime contract. The function under
// test is extracted verbatim from nativews/bootstrap.v by the source checker.
fn expected(root string) string {
	paths := [
		'/usr/lib/java/dex/art/core-oj-hostdex.jar',
		'/usr/lib/java/dex/art/apachehttp-hostdex.jar',
		'/usr/lib/java/dex/art/apache-xml-hostdex.jar',
		'/usr/lib/java/dex/art/bouncycastle-hostdex.jar',
		'/usr/lib/java/dex/art/core-junit-hostdex.jar',
		'/usr/lib/java/dex/art/core-libart-hostdex.jar',
		'/usr/lib/java/dex/art/hamcrest-hostdex.jar',
		'/usr/lib/java/dex/art/junit-runner-hostdex.jar',
		'/usr/lib/java/dex/art/okhttp-hostdex.jar',
		'/usr/lib/java/dex/art/wolfssljni-hostdex.jar',
		'/usr/lib/java/dex/android_translation_layer/api-impl.jar',
	]
	return '-Xbootclasspath:' + paths.map(root + it).join(':')
}

fn check_case(root string, capacity int) {
	want := expected(root)
	mut storage := []u8{len: capacity + 2, init: sentinel}
	result := ws_boot_classpath(root.str, unsafe { &char(&storage[1]) }, usize(capacity))
	assert result == (capacity > want.len), 'exact-fit result capacity=' + capacity.str()
	assert storage[0] == sentinel && storage[capacity + 1] == sentinel, 'buffer guards'
	if capacity == 0 {
		assert storage.all(it == sentinel), 'zero capacity must not write'
		return
	}
	written := if capacity - 1 < want.len { capacity - 1 } else { want.len }
	assert storage[1..written + 1] == want[..written].bytes(), 'exact ordered bytes'
	assert storage[written + 1] == 0, 'bounded NUL termination'
	assert storage[written + 2..].all(it == sentinel), 'no writes past terminator'
	if result {
		actual := storage[1..want.len + 1].bytestr()
		assert actual.all_before(':') == '-Xbootclasspath'
		assert actual.all_after(':').split(':').len == 11, 'exact eleven boot entries'
		assert actual == want
	}
}

fn main() {
	$if prod { panic('live assertions required') }
	mut cases := 0
	for root in ['/opt/vinix-android-aarch64', '/sandbox/%s', '/' + 'a'.repeat(4094)] {
		want := expected(root)
		for capacity in [0, 1, 2, want.len - 1, want.len, want.len + 1, want.len + 2, 65536] {
			check_case(root, capacity)
			cases++
		}
	}
	mut untouched := []u8{len: 65538, init: sentinel}
	assert !ws_boot_classpath(unsafe { nil }, unsafe { &char(&untouched[1]) }, 65536)
	assert untouched.all(it == sentinel), 'null root must not write'
	assert !ws_boot_classpath(c'/opt/vinix-android-aarch64', unsafe { nil }, 65536)
	assert !ws_boot_classpath(unsafe { nil }, unsafe { nil }, 0)
	assert untouched.all(it == sentinel)
	println('FRAMEWORK-BOOT-HELPER-PASS cases=' + (cases + 3).str() + ' exact11 ordered real-root null zero-capacity exact-fit truncation sentinel long4095root64KiB')
}
