module nativecache

import os

fn test_prepare_selected_art_cache() {
	cache := os.getenv_opt('XDG_CACHE_HOME')
	home := os.getenv_opt('HOME')
	root := os.join_path(os.temp_dir(), 'vinix-art-cache-${os.getpid()}')
	os.mkdir(root)!
	defer {
		os.rmdir_all(root) or {}
		if value := cache { os.setenv('XDG_CACHE_HOME', value, true) }
		else { os.unsetenv('XDG_CACHE_HOME') }
		if value := home { os.setenv('HOME', value, true) }
		else { os.unsetenv('HOME') }
	}
	os.setenv('HOME', root + '/home', true)
	os.setenv('XDG_CACHE_HOME', root + '/cache', true)
	assert directory()! == root + '/cache/art/arm64'
	prepare()!
	assert os.is_dir(root + '/cache/art/arm64')
	assert !os.exists(root + '/home')
	os.write_file(root + '/cache/art/arm64/retained.oat', 'retained')!
	prepare()!
	assert os.read_file(root + '/cache/art/arm64/retained.oat')! == 'retained'

	os.unsetenv('XDG_CACHE_HOME')
	assert directory()! == root + '/home/.cache/art/arm64'
	prepare()!
	assert os.is_dir(root + '/home/.cache/art/arm64')

	// A legal Unix backslash must name the same directory in ART and launcher.
	os.setenv('XDG_CACHE_HOME', root + '/back\\slash', true)
	prepare()!
	assert os.is_dir(root + '/back\\slash/art/arm64')
	assert !os.exists(root + '/back/slash')

	// Existing cache directory links remain usable under the launching UID.
	os.symlink(root + '/cache', root + '/linked-cache')!
	os.setenv('XDG_CACHE_HOME', root + '/linked-cache', true)
	prepare()!
	assert os.read_file(root + '/linked-cache/art/arm64/retained.oat')! == 'retained'

	// An existing file must fail before ART receives an invalid oat location.
	os.write_file(root + '/file', 'keep')!
	os.setenv('XDG_CACHE_HOME', root + '/file', true)
	mut rejected := false
	prepare() or { rejected = err.msg().contains('not a directory') }
	assert rejected
	assert os.read_file(root + '/file')! == 'keep'

	// Empty-but-present XDG must not silently select HOME instead of ART's /art.
	for value in ['', 'relative-cache'] {
		os.setenv('XDG_CACHE_HOME', value, true)
		rejected = false
		prepare() or { rejected = err.msg().contains('absolute XDG_CACHE_HOME') }
		assert rejected
	}
	os.unsetenv('XDG_CACHE_HOME')
	os.setenv('HOME', '', true)
	rejected = false
	prepare() or { rejected = err.msg().contains('absolute HOME') }
	assert rejected
	os.unsetenv('HOME')
	rejected = false
	prepare() or { rejected = err.msg().contains('requires XDG_CACHE_HOME or HOME') }
	assert rejected
}

fn test_prepare_rejects_unwritable_cache() {
	cache := os.getenv_opt('XDG_CACHE_HOME')
	root := os.join_path(os.temp_dir(), 'vinix-art-cache-permissions-${os.getpid()}')
	os.mkdir_all(root + '/art/arm64')!
	defer {
		os.chmod(root + '/art/arm64', 0o700) or {}
		os.rmdir_all(root) or {}
		if value := cache { os.setenv('XDG_CACHE_HOME', value, true) }
		else { os.unsetenv('XDG_CACHE_HOME') }
	}
	os.chmod(root + '/art/arm64', 0o500)!
	os.setenv('XDG_CACHE_HOME', root, true)
	// Unix root intentionally bypasses mode permission checks.
	if os.is_writable(root + '/art/arm64') { return }
	mut rejected := false
	prepare() or { rejected = err.msg().contains('not readable, writable and searchable') }
	assert rejected
}
