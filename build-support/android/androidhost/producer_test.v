module androidhost

import os

fn test_native_producer_digest_tracks_account_authority_sources() {
	root := path_join(os.temp_dir(), 'vinix-android-producer-${os.getpid()}')
	assert !os.exists(root)
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or { panic(err) } }
	support := root + '/build-support/android'
	for directory in ['atlframework', 'nativews', 'wsloader', 'nativeapk', 'nativeidentity', 'nativecache', 'nativeaccountauth'] {
		os.mkdir_all(support + '/' + directory)!
	}
	for name in ['nativews/bindings.txt', 'native-entry.v', 'native-run.v'] {
		os.write_file(support + '/' + name, 'unchanged')!
	}
	path := support + '/nativeaccountauth/registry.v'
	os.write_file(path, 'first authority implementation')!
	before := native_producer_digest(support, []string{}, ['build-support/android/atlframework'])!
	os.write_file(path, 'changed authority implementation')!
	after := native_producer_digest(support, []string{}, ['build-support/android/atlframework'])!
	assert before != after
	os.write_file(support + '/nativeaccountauth/registry_test.v', 'host tests do not enter the producer')!
	assert after == native_producer_digest(support, []string{}, ['build-support/android/atlframework'])!
}
