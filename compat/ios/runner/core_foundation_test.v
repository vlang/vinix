// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn test_cf_owned_collections_release_members_and_raw_collections_leave_pointers_alone() {
	objc_start()
	defer { objc_stop() }
	cf_allocator_default()
	array_callbacks := cf_callbacks_constant('_kCFTypeArrayCallBacks')
	key_callbacks := cf_callbacks_constant('_kCFTypeDictionaryKeyCallBacks')
	value_callbacks := cf_callbacks_constant('_kCFTypeDictionaryValueCallBacks')
	baseline := ios_runtime.live
	pool := objc_pool_push()
	for _ in 0 .. 200 {
		key := cf_string_create(0, c'a distinct owned CF key', 0x08000100)
		value := cf_string_bytes(0, u64(c'A\x00Z'), 3, 0x08000100, false)
		assert string_text(value).len == 3
		values := [key, value]!
		array := cf_array_create(0, u64(&values[0]), 2, array_callbacks)
		dictionary := cf_dictionary_mutable(0, 0, key_callbacks, value_callbacks)
		cf_dictionary_set(dictionary, key, value)
		cf_dictionary_set(dictionary, key, value)
		objc_release(key)
		objc_release(value)
		objc_release(array)
		objc_release(dictionary)
		raw := [u64(1), 2, 0]!
		objc_release(cf_array_create(0, u64(&raw[0]), 3, 0))
		raw_dictionary := cf_dictionary_mutable(0, 0, 0, 0)
		cf_dictionary_set(raw_dictionary, 1, 2)
		cf_dictionary_set(raw_dictionary, 1, 3)
		assert cf_dictionary_value(raw_dictionary, 1) == 3
		objc_release(raw_dictionary)
		data := cf_data_mutable(0, 0)
		cf_data_set_length(data, 4096)
		cf_data_set_length(data, 0)
		cf_data_set_length(data, 8192)
		objc_release(data)
		assert ios_runtime.live == baseline
	}
	objc_pool_pop(pool)
	assert ios_runtime.live == baseline
}
