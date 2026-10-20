module desktopimage

fn test_tar_normalization() ! {
	assert tar_normalization('tar (GNU tar) 1.35\n')! == ['--owner=root:0', '--group=root:0']
	assert tar_normalization('bsdtar 3.5.3 - libarchive 3.5.3\n')! == ['--uid', '0', '--gid', '0',
		'--uname', 'root', '--gname', 'root']
	tar_normalization('unknown tar') or {
		assert err.msg().contains('unsupported tar version')
		return
	}
	assert false, 'unknown tar must be rejected'
}
