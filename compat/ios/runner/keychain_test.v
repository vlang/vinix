// SPDX-License-Identifier: GPL-2.0-or-later
module main

import macho
import os
import encoding.hex

fn C.mkdtemp(&char) &char
fn C.link(&char, &char) int

fn keychain_test_directory(prefix string) string {
	template := os.join_path(os.temp_dir(), prefix + 'XXXXXX')
	assert C.mkdtemp(unsafe { &char(template.str) }) != unsafe { nil }
	return template
}

fn keychain_test_environment(root string) string {
	previous := os.getenv('VINIX_IOS_KEYCHAIN')
	os.setenv('VINIX_IOS_KEYCHAIN', root, true)
	return previous
}

fn test_native_keychain_queries_and_persistence() {
	path := os.getenv('VINIX_IOS_KEYCHAIN_FIXTURE')
	if path == '' { return }
	root := keychain_test_directory('vinix-ios-keychain-')
	defer { os.rmdir_all(root) or { panic(err) } }
	previous := keychain_test_environment(root)
	defer { os.setenv('VINIX_IOS_KEYCHAIN', previous, true) }
	data := os.read_bytes(path)!
	defer { unsafe { data.free() } }
	image := macho.parse(data)!
	defer { module_image_free(image) }
	for _ in 0 .. 2 {
		assert execute(image, [path])! == 0
		assert ios_runtime.live == 0
		for mode in ['write', 'read', 'delete'] {
			assert execute(image, [path, mode])! == 0
			assert ios_runtime.live == 0
		}
	}
}

fn keychain_test_constant(name string) u64 {
 if address := security_constant(name) { return read64(address) }
 return framework_object(name)
}

fn keychain_test_query(account string, add bool) u64 {
	query := objc_autorelease(objc_allocate(ios_runtime.names['NSMutableDictionary']))
	dictionary_put(query, keychain_test_constant('_kSecClass'), keychain_test_constant('_kSecClassGenericPassword'))
	dictionary_put(query, keychain_test_constant('_kSecAttrService'), make_string(c'vinix-unit'))
	if account != '' { dictionary_put(query, keychain_test_constant('_kSecAttrAccount'), make_string(unsafe { &char(account.str) })) }
	if add {
		dictionary_put(query, keychain_test_constant('_kSecAttrAccessible'), keychain_test_constant('_kSecAttrAccessibleAfterFirstUnlock'))
		bytes := cf_data_create(0, u64(c'vinix-private-secret'), 20)
		dictionary_put(query, keychain_test_constant('_kSecValueData'), bytes)
		objc_release(bytes)
	}
	return query
}

fn test_keychain_integrity_policy_and_atomic_updates() {
	root := keychain_test_directory('vinix-ios-keychain-unit-')
	defer { os.rmdir_all(root) or { panic(err) } }
	store := os.join_path(root, 'store')
	previous := keychain_test_environment(store)
	defer { os.setenv('VINIX_IOS_KEYCHAIN', previous, true) }
	objc_start()
	ios_runtime.bundle = os.join_path(root, 'fixture')
	os.mkdir(ios_runtime.bundle)!
	pool := objc_pool_push()
	defer { objc_pool_pop(pool); objc_stop(); assert ios_runtime.live == 0 }
	mut result := u64(0x1234)
	assert sec_item_add(0, &result) == -50 && result == 0
	query := keychain_test_query('one', true)
	assert sec_item_add(query, &result) == 0 && result == 0
	second := keychain_test_query('two', true)
	assert sec_item_add(second, unsafe { nil }) == 0
	broad := keychain_test_query('', false)
	changes := objc_autorelease(objc_allocate(ios_runtime.names['NSMutableDictionary']))
	dictionary_put(changes, keychain_test_constant('_kSecAttrAccount'), make_string(c'collision'))
	assert sec_item_update(broad, changes) == -25299
	// Even if a later record collides, neither earlier staged update is saved.
	for account in ['one', 'two'] {
		q := keychain_test_query(account, false)
		assert sec_item_copy(q, unsafe { nil }) == 0
	}
	updated := objc_autorelease(objc_allocate(ios_runtime.names['NSMutableDictionary']))
	bytes := cf_data_create(0, u64(c'new'), 3)
	dictionary_put(updated, keychain_test_constant('_kSecValueData'), bytes)
	objc_release(bytes)
	assert sec_item_update(broad, updated) == 0
	all := keychain_test_query('', false)
	dictionary_put(all, keychain_test_constant('_kSecMatchLimit'), keychain_test_constant('_kSecMatchLimitAll'))
	dictionary_put(all, keychain_test_constant('_kSecReturnData'), keychain_test_constant('_kCFBooleanTrue'))
	assert sec_item_copy(all, &result) == 0
	assert cf_array_count(result) == 2
	for i in 0 .. 2 {
		item := cf_array_value(result, i)
		assert data_length(item) == 3
		assert C.memcmp(voidptr(data_pointer(item)), c'new', 3) == 0
	}
	objc_release(result)
	assert sec_item_copy(all, unsafe { nil }) == 0
	// Encrypted file contains neither attributes nor password plaintext.
	item_path := os.join_path(store, 'fixture', 'items')
	key_path := os.join_path(store, 'fixture', 'key')
	original := os.read_bytes(item_path)!
	defer { unsafe { original.free() } }
	assert original.len > 72
	assert !original.bytestr().contains('vinix-unit')
	assert !original.bytestr().contains('vinix-private-secret')
	// Flip header, IV, ciphertext and tag; each failure preserves the corrupt
	// bytes and rejects a subsequent attempted mutation rather than resetting.
	for offset in [0, 8, 24, original.len - 1] {
		mut altered := original.clone()
		altered[offset] ^= 1
		os.write_file_array(item_path, altered)!
		result = 0x1234
		assert sec_item_copy(broad, &result) == -26275 && result == 0
		assert sec_item_delete(broad) == -26275
		check := os.read_bytes(item_path)!
		assert check == altered
		unsafe { altered.free(); check.free() }
	}
	os.write_file_array(item_path, original)!
	// A wrong key cannot authenticate a valid store; repair only in this fixture.
	mut private_key := os.read_bytes(key_path)!
	private_key[40] ^= 1
	os.write_file_array(key_path, private_key)!
	assert sec_item_copy(broad, &result) == -26275
	private_key[40] ^= 1
	os.write_file_array(key_path, private_key)!
	C.ios_secure_zero(private_key.data, usize(private_key.len))
	unsafe { private_key.free() }
	os.chmod(key_path, 0o644)!
	assert sec_item_copy(broad, &result) == -25291
	os.chmod(key_path, 0o600)!
	os.rename(key_path, key_path + '.saved')!
	assert sec_item_copy(broad, &result) == -25291
	assert !os.exists(key_path)
	os.symlink(key_path + '.saved', key_path)!
	assert sec_item_copy(broad, &result) == -25291
	os.rm(key_path)!
	os.rename(key_path + '.saved', key_path)!
	linked := key_path + '.link'
	assert C.link(unsafe { &char(key_path.str) }, unsafe { &char(linked.str) }) == 0
	assert sec_item_copy(broad, &result) == -25291
	os.rm(linked)!
	os.chmod(os.dir(key_path), 0o755)!
	assert sec_item_copy(broad, &result) == -25291
	os.chmod(os.dir(key_path), 0o700)!
	os.rename(item_path, item_path + '.saved')!
	os.symlink(item_path + '.saved', item_path)!
	assert sec_item_copy(broad, &result) == -26275
	os.rm(item_path)!
	os.rename(item_path + '.saved', item_path)!
	// Unsupported security policies fail before touching existing records.
	unsupported := keychain_test_query('three', true)
	dictionary_put(unsupported, keychain_test_constant('_kSecAttrSynchronizable'), keychain_test_constant('_kCFBooleanTrue'))
	assert sec_item_add(unsupported, &result) == -4 && result == 0
	group := keychain_test_query('three', true)
	dictionary_put(group, keychain_test_constant('_kSecAttrAccessGroup'), make_string(c'other.app'))
	assert sec_item_add(group, &result) == -34018 && result == 0
	policy := keychain_test_query('three', true)
	dictionary_put(policy, keychain_test_constant('_kSecUseDataProtectionKeychain'), keychain_test_constant('_kCFBooleanTrue'))
	assert sec_item_add(policy, &result) == -4
	invalid := keychain_test_query('three', true)
	dictionary_put(invalid, keychain_test_constant('_kSecValueData'), make_string(c'not data'))
	assert sec_item_add(invalid, &result) == -50
	missing_policy := keychain_test_query('three', true)
	dictionary_put(missing_policy, keychain_test_constant('_kSecAttrAccessible'), 0)
	assert sec_item_add(missing_policy, &result) == -4
	assert sec_item_delete(broad) == 0
	assert sec_item_copy(broad, &result) == -25300 && result == 0
	// The same service/account in a different application directory is distinct.
	assert sec_item_add(query, unsafe { nil }) == 0
	ios_runtime.bundle = os.join_path(root, 'other')
	os.mkdir(ios_runtime.bundle)!
	assert sec_item_copy(broad, &result) == -25300
	assert sec_item_add(query, unsafe { nil }) == 0
	// Info.plist identity, rather than the directory basename, selects the app.
	info_path := os.join_path(ios_runtime.bundle, 'Info.plist')
	os.write_file(info_path, '<plist><dict><key>CFBundleIdentifier</key><string>com.vinix.keychain</string></dict></plist>')!
	assert sec_item_copy(broad, &result) == -25300
	assert sec_item_add(query, unsafe { nil }) == 0
	assert sec_item_copy(broad, &result) == 0 && result == 0
	os.write_file(info_path, '<plist><dict><key>CFBundleIdentifier</key><string>../fixture</string></dict></plist>')!
	assert sec_item_copy(broad, &result) == -25291
}

fn test_keychain_independent_encrypted_envelope() {
	root := keychain_test_directory('vinix-ios-keychain-vector-')
	defer { os.rmdir_all(root) or { panic(err) } }
	previous := keychain_test_environment(root)
	defer { os.setenv('VINIX_IOS_KEYCHAIN', previous, true) }
	objc_start()
	ios_runtime.bundle = os.join_path(root, 'fixture')
	pool := objc_pool_push()
	defer { objc_pool_pop(pool); objc_stop(); assert ios_runtime.live == 0 }
	query := keychain_test_query('golden', true)
	assert sec_item_add(query, unsafe { nil }) == 0
	// Public synthetic test key 00..3f; ciphertext generated with installed
	// OpenSSL AES-256-CBC and authenticated by Python hashlib/HMAC, not our writer.
	mut key := []u8{len: 64}
	for i in 0 .. key.len { key[i] = u8(i) }
	defer { unsafe { key.free() } }
	mut envelope := hex.decode('564e584b43483031101112131415161718191a1b1c1d1e1f40ea334d8179154cb0a3fe8431f68147cd34cce9859307cb5bb8655036bc31c57ebadf57768835ce5ac35edfd3bc52a122df5b44e3814b3a963fcf6ad5554dcd92bf725f8b43a04f8407c4a4543110e941810e167541448e93db1ce26a6dfdb4a50a4e8e63d7e7e27a610f6d3e1f8ac3389ea7de0eaf9b6049bc195eb7c1026ad5d5b6656988abc9907d1d51e03d07991e19abdc75f69fee4422d08f9699e151cb38e396c1c978fbff17547e81e354621f955c72256a16cfd24720ccfaa7d05e4b183c72e95c616223c81b6a78adaf4659f3947db4b10ddb211d5414f7379d9e1e968de25c6a1c4248bad3906810b485a9ef0f181de194f7685a0d4dbbc5961c3403ec97c57a92e6e8fe86c1a4bf1bb6a59305a5307dd726a6bfd641e7e6270f8030d9fec70d69ea4498715467b4b690')!
	defer { unsafe { envelope.free() } }
	item_path := os.join_path(root, 'fixture', 'items')
	os.write_file_array(os.join_path(root, 'fixture', 'key'), key)!
	os.write_file_array(item_path, envelope)!
	lookup := keychain_test_query('golden', false)
	dictionary_put(lookup, keychain_test_constant('_kSecReturnData'), keychain_test_constant('_kCFBooleanTrue'))
	mut result := u64(0)
	assert sec_item_copy(lookup, &result) == 0
	expected := [u8(0), 1, 2, 255]!
	assert data_length(result) == 4 && C.memcmp(voidptr(data_pointer(result)), unsafe { &expected[0] }, 4) == 0
	objc_release(result)
	// A valid tag with invalid PKCS#7 must still fail before parsing plaintext.
	envelope[envelope.len - 32 - 17] ^= 1
	cc_hmac(2, unsafe { &key[32] }, 32, envelope.data, u64(envelope.len - 32), unsafe { &envelope[envelope.len - 32] })
	os.write_file_array(item_path, envelope)!
	assert sec_item_copy(lookup, &result) == -26275 && result == 0
}
