module nativeaccountauth

import os

fn record(name string, uid string, gid string, path string, hash string) string {
	return [name, uid, gid, path, hash, 'b'.repeat(64), '-'].join('\t') + '\n'
}

fn test_exact_service_and_action_allowlist() {
	selector := 'com.example.auth.Outer$Service@com.example.AUTH'
	text := fixture_registry().replace('\t-\n', '\t' + selector + '\n')
	registry := parse_registry(text)!
	assert registry.entries[0].services == [Service{'com.example.auth.Outer$Service', 'com.example.AUTH'}]
	for value in ['', 'com.example.Service', 'com.example.Service@', '@com.example.AUTH',
		'com.example.Service@com.example.AUTH@extra', 'com.example.Service@bad action',
		'com.example.Service@com.example.$AUTH', selector + ',' + selector, selector + ',',
		(selector + ',').repeat(16) + selector] {
		mut rejected := false
		parse_registry(fixture_registry().replace('\t-\n', '\t' + value + '\n')) or { rejected = true }
		assert rejected
	}
}

fn fixture_registry() string {
	return registry_header + '\n' +
		record('com.example.maps', '10000', '10000', '/srv/android/maps.apk', 'a'.repeat(64)) +
		record('com.example.auth', '10001', '10001', '/srv/android/auth.apk', 'c'.repeat(64))
}

fn test_registry_entries_and_strict_ambiguity_rejection() {
	text := fixture_registry()
	registry := parse_registry(text)!
	assert registry.entries.len == 2
	assert registry.entries[0].package_name == 'com.example.maps'
	assert registry.entries[1].uid == 10001
	first := text.split_into_lines()[1] + '\n'
	for bad in [
		'', registry_header + '\n', text.trim_right('\n'), text.replace('\n', '\r\n'),
		text.replace(registry_header, 'vinix-android-account-authority-v2'), text + '\n',
		text.replace('com.example.maps', 'single'), text.replace('com.example.maps', 'com..maps'),
		text.replace('com.example.maps', 'com.1maps'), text.replace('com.example.maps', 'com.maps!'),
		text.replace('\t10000\t', '\t00000\t'), text.replace('\t10000\t', '\t20000\t'),
		text.replace('\t10000\t', '\t010000\t'), text.replace('\t10000\t', '\t+10000\t'),
		text.replace('/srv/android/maps.apk', 'maps.apk'), text.replace('/srv/android/maps.apk', '/srv//maps.apk'),
		text.replace('/srv/android/maps.apk', '/srv/../maps.apk'), text.replace('/srv/android/maps.apk', '/srv/./maps.apk'),
		text.replace('/srv/android/maps.apk', '/srv/android/maps.apk/'), text.replace('/srv/android/maps.apk', '/srv/android/ma\x00ps.apk'),
		text.replace('a'.repeat(64), 'A'.repeat(64)), text.replace('a'.repeat(64), 'a'.repeat(63)),
		text.replace('b'.repeat(64), 'z'.repeat(64)), text.replace('\t' + 'b'.repeat(64), ''),
		text + first, text.replace('com.example.auth', 'com.example.maps'),
		text.replace('\t10001\t10001\t', '\t10000\t10001\t'),
		text.replace('\t10001\t10001\t', '\t10001\t10000\t'),
		text.replace('/srv/android/auth.apk', '/srv/android/maps.apk'),
		text.replace('c'.repeat(64), 'a'.repeat(64)),
		registry_header + '\n' + first.repeat(65), 'x'.repeat(max_registry_bytes + 1),
	] {
		mut rejected := false
		parse_registry(bad) or { rejected = true }
		assert rejected
	}
}

fn test_authority_comes_from_peer_and_rejects_forged_claims() {
	registry := parse_registry(fixture_registry())!
	peer := Peer{pid: 77, uid: 10000, gid: 10000}
	caller := registry.authenticate_peer(peer, Claims{})!
	assert caller.package_name == 'com.example.maps'
	assert caller.uid == 10000 && caller.gid == 10000 && caller.pid == 77
	assert caller.apk_sha256 == 'a'.repeat(64)
	assert caller.certificate_sha256 == 'b'.repeat(64)
	assert registry.authenticate_peer(peer, Claims{'com.example.maps', 10000, 77})! == caller
	for claims in [Claims{package_name: 'com.example.auth'}, Claims{uid: 10001}, Claims{uid: 0},
		Claims{pid: 88}, Claims{pid: 0}, Claims{uid: -2}, Claims{pid: -2}] {
		mut rejected := false
		registry.authenticate_peer(peer, claims) or { rejected = true }
		assert rejected
	}
	for wrong in [Peer{0, 10000, 10000}, Peer{77, 10000, 10001}, Peer{77, 10002, 10002},
		Peer{77, 0, 0}] {
		mut rejected := false
		registry.authenticate_peer(wrong, Claims{package_name: 'com.example.maps'}) or { rejected = true }
		assert rejected
	}
	mut rejected := false
	registry.authenticate(-1, Claims{package_name: 'com.example.maps', uid: 10000, pid: 77}) or { rejected = true }
	assert rejected
}

fn test_protected_metadata_rejects_writable_inputs_and_aliases() {
	assert protected_metadata(u32(C.S_IFREG) | 0o444, 0, 1, 4, false, 4)
	assert protected_metadata(u32(C.S_IFDIR) | 0o755, 0, 2, 0, true, 0)
	for mode in [u32(0o644), 0o464, 0o446, 0o666] {
		assert !protected_metadata(u32(C.S_IFREG) | mode, 0, 1, 4, false, 4)
	}
	assert !protected_metadata(u32(C.S_IFREG) | 0o444, 10000, 1, 4, false, 4)
	assert !protected_metadata(u32(C.S_IFREG) | 0o444, 0, 2, 4, false, 4)
	assert !protected_metadata(u32(C.S_IFREG) | 0o444, 0, 1, 5, false, 4)
	assert !protected_metadata(u32(C.S_IFLNK) | 0o444, 0, 1, 4, false, 4)
	assert !protected_metadata(u32(C.S_IFIFO) | 0o444, 0, 1, 4, false, 4)
	assert !protected_metadata(u32(C.S_IFDIR) | 0o777, 0, 2, 0, true, 0)
	assert !protected_metadata(u32(C.S_IFDIR) | 0o775, 0, 2, 0, true, 0)
	assert !protected_metadata(u32(C.S_IFDIR) | 0o755, 10000, 2, 0, true, 0)
}

fn test_configured_registry_never_downgrades_to_an_unchecked_launch() {
	old := os.getenv_opt('VINIX_ANDROID_ACCOUNT_REGISTRY')
	defer {
		if value := old { os.setenv('VINIX_ANDROID_ACCOUNT_REGISTRY', value, true) }
		else { os.unsetenv('VINIX_ANDROID_ACCOUNT_REGISTRY') }
	}
	os.unsetenv('VINIX_ANDROID_ACCOUNT_REGISTRY')
	verify_environment_launch('/missing.apk', 0, 0, false)!
	for value in ['', 'relative', '/definitely-missing-account-authority'] {
		os.setenv('VINIX_ANDROID_ACCOUNT_REGISTRY', value, true)
		for selected in [false, true] {
			mut rejected := false
			verify_environment_launch('/missing.apk', 10000, 10000, selected) or { rejected = true }
			assert rejected
		}
	}
}

fn test_launch_package_and_ids_cannot_be_changed() {
	registry := parse_registry(fixture_registry())!
	for args in [['/srv/android/maps.apk', '10001', '10001'],
		['/srv/android/auth.apk', '10000', '10000'], ['/other.apk', '10000', '10000']] {
		mut rejected := false
		registry.verify_launch(args[0], args[1].u32(), args[2].u32()) or { rejected = true }
		assert rejected
	}
}
