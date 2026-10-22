module nvimcompat

fn test_libuv_no_io_uring_changes_only_the_expected_branch() {
	source := '// prefix\n' + libuv_original + '\n#elif OTHER\n// untouched epoll implementation\n'
	patched := libuv_linux(source) or { panic(err) }
	assert patched == '// prefix\n' + libuv_replacement + '\n#elif OTHER\n// untouched epoll implementation\n'
	assert patched.count(libuv_define) == 1
	if _ := libuv_linux(patched) { assert false, 'a repeated patch was admitted' }
}

fn test_libuv_no_io_uring_refuses_source_drift_and_ambiguity() {
	for source in ['', libuv_original.replace('uint32_t', 'unsigned'),
		libuv_original + '\n' + libuv_original, '// ' + libuv_define + '\n' + libuv_original] {
		if _ := libuv_linux(source) { assert false, 'an unexpected source was patched' }
	}
}
