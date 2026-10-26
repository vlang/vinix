// SPDX-License-Identifier: GPL-2.0-or-later
module main

fn test_runpath_exceptions_are_bound_to_exact_bytes_names_and_paths() {
	checksum := '5a228127ca3ffa0c88bcae0aa5f7ab10e15b383dfb46822c573013105628bbaa'
	assert allowed_runpath('any', '', '')
	assert allowed_runpath('usr/lib/libsqlite3.so.0', checksum, '/usr/lib')
	assert allowed_runpath('usr/lib/libsqlite3.so.3.53.4', checksum, '/usr/lib')
	assert !allowed_runpath('usr/lib/other.so', checksum, '/usr/lib')
	assert !allowed_runpath('usr/lib/libsqlite3.so.0', '0'.repeat(64), '/usr/lib')
	assert !allowed_runpath('usr/lib/libsqlite3.so.0', checksum, '/usr/lib:/tmp')
	for name in ['usr/lib/libLLVM-23.so', 'usr/lib/libLLVM.so.23.1'] {
		assert allowed_runpath(name, '9ae7d1082a730f4214dfe67be55eadd64f2a907afb17a140a3299c8ae7c17a78', '/usr/lib/llvm23')
		assert !allowed_runpath(name, checksum, '/usr/lib/llvm23')
	}
	for name in ['usr/lib/libproxy.so.1', 'usr/lib/libproxy.so.0.5.12'] {
		assert allowed_runpath(name, '3a1304f3d8575a64f2b0059f56e77bda3a2ee95bfe69bac5d8047264f25b3666', '/usr/lib/libproxy')
		assert !allowed_runpath(name, checksum, '/usr/lib/libproxy')
	}
	assert allowed_runpath('usr/lib/libproxy/libpxbackend-1.0.so', '5b8028197a47c1e72654bdf65201294a11c94c2517b4c5ca0f8194e97751d825', '/usr/lib/libproxy')
	assert !allowed_runpath('usr/lib/libproxy/libpxbackend-1.0.so', checksum, '/usr/lib/libproxy')
}

fn test_deployment_manifests_bind_each_maps_identity_to_its_private_data() {
	for uid in [10012, 10013] {
		text := manifest(uid, {
			'bin/webview-engine': 'a'.repeat(64)
		}, {
			'/usr/bin/bwrap': 'b'.repeat(64)
		})
		assert text.starts_with('vinix-android-browser-launch-v1\nexclusive-principal\t${uid}\t${uid}\t/var/lib/vinix/apps/${uid}/data\n')
		assert text.contains('root\t/opt/vinix-google-browser\n')
		assert text.contains('libraries\tusr/lib:lib:usr/lib/libproxy\n')
		assert text.ends_with('external\t' + 'b'.repeat(64) + '\t/usr/bin/bwrap\n')
	}
}

fn test_engine_inventory_paths_reject_escape_and_ambiguous_separators() {
	for name in ['build.json', 'sources/engine.v'] {
		assert relative(name)
	}
	for name in ['', '/build.json', '../build.json', 'a/../build.json', 'a//b', 'a\\b', 'a:b',
		'a\nb'] {
		assert !relative(name)
	}
}
