module nativeidentity

import os

fn test_explicit_application_credential_configuration() {
	config := parse('10000', '19999', '/srv/app/data', '/srv/app/home')!
	assert config.enabled && config.uid == 10000 && config.gid == 19999
	for pair in [['', '10000'], ['10000', ''], ['0', '10000'], ['9999', '10000'], ['20000', '10000'],
		['10000', '20000'], ['+10000', '10000'], ['010000', '10000'], ['1000a', '10000']] {
		mut rejected := false
		parse(pair[0], pair[1], '/data', '/home') or { rejected = true }
		assert rejected, pair.str()
	}
	for paths in [['', '/home'], ['data', '/home'], ['/data', 'home']] {
		mut rejected := false
		parse('10000', '10000', paths[0], paths[1]) or { rejected = true }
		assert rejected
	}
}

fn test_absent_options_preserve_the_launching_identity() {
	uid := os.getenv_opt('VINIX_ANDROID_UID')
	gid := os.getenv_opt('VINIX_ANDROID_GID')
	defer {
		if value := uid { os.setenv('VINIX_ANDROID_UID', value, true) }
		if value := gid { os.setenv('VINIX_ANDROID_GID', value, true) }
	}
	os.unsetenv('VINIX_ANDROID_UID')
	os.unsetenv('VINIX_ANDROID_GID')
	config := from_environment()!
	assert !config.enabled
	config.activate('', '', '')!
	os.setenv('VINIX_ANDROID_UID', '', true)
	mut rejected := false
	from_environment() or { rejected = true }
	assert rejected
	os.unsetenv('VINIX_ANDROID_UID')
}
