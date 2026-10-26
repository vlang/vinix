// SPDX-License-Identifier: GPL-2.0-or-later
module browserlaunch

import os

const test_pin = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'

fn complete_manifest() string {
	mut lines := [manifest_header, 'exclusive-principal\t10042\t10043\t/var/lib/vinix/apps/10042',
		'root\t/opt/vinix/browser', 'loader\tlib/ld.so', 'engine\tbin/engine', 'xvfb\tbin/Xvfb',
		'libraries\tlib:lib64', 'xkb\tshare/xkb', 'fonts\tshare/fonts', 'fontconfig\tetc/fonts.conf']
	for path in ['lib/ld.so', 'bin/engine', 'bin/Xvfb', 'etc/fonts.conf', injected_bundle] {
		lines << 'file\t${test_pin}\t${path}'
	}
	for path in external_dependencies() {
		lines << 'external\t${test_pin}\t${path}'
	}
	return lines.join('\n') + '\n'
}

fn rejects_manifest(text string) bool {
	parse_manifest(text) or { return true }
	return false
}

fn test_manifest_admits_only_complete_pinned_configuration() {
	mut config := parse_manifest(complete_manifest()) or { panic(err) }
	assert config.enabled && config.manifest_fd == -1 && config.root_fd == -1
	assert config.uid == 10042 && config.gid == 10043
	assert config.data == '/var/lib/vinix/apps/10042'
	assert config.root == '/opt/vinix/browser' && config.loader == 'lib/ld.so'
	assert config.engine == 'bin/engine' && config.xvfb == 'bin/Xvfb'
	assert config.libraries == ['lib', 'lib64']
	assert config.xkb == 'share/xkb' && config.fonts == 'share/fonts'
	assert config.fontconfig == 'etc/fonts.conf'
	assert config.files.len == 5 && config.externals.len == external_helpers.len + external_data.len
	assert config.files['bin/engine'] == test_pin
	for path in external_dependencies() {
		assert config.externals[path] == test_pin
	}
	config.close()
	config.close()
}

fn test_manifest_rejects_each_missing_or_duplicate_admission_entry() {
	text := complete_manifest()
	lines := text.trim_space().split('\n')
	for line in lines[1..] {
		assert rejects_manifest(text.replace(line + '\n', '')), 'missing entry: ' + line
		assert rejects_manifest(text + line + '\n'), 'duplicate entry: ' + line
	}
}

fn test_manifest_rejects_malformed_framing_keys_pins_and_principals() {
	text := complete_manifest()
	for invalid in ['', manifest_header + '\n', text[..text.len - 1], text + '\n',
		text.replace('\n', '\r\n'), text + '\x00\n',
		text.replace(manifest_header, manifest_header + '-new'), text.replace('root\t', 'unknown\t'),
		text.replace('root\t', ' root\t'),
		text.replace('root\t/opt/vinix/browser', 'root\t/opt/vinix/browser\textra'),
		text.replace('loader\tlib/ld.so', 'loader\tlib/unpinned.so'),
		text.replace(test_pin, test_pin.to_upper()), text.replace(test_pin, test_pin[..63]),
		text.replace(test_pin, 'g' + test_pin[1..]),
		text.replace('file\t' + test_pin + '\tbin/engine', 'file\t' + test_pin + '\tbin/../engine'),
		text.replace('file\t' + test_pin + '\tbin/engine', 'file\t' + test_pin + '\t/bin/engine'),
		text.replace('/usr/bin/bwrap', '/usr/bin/curl'),
		text.replace('external\t' + test_pin + '\t/usr/bin/bwrap', 'external\t' + test_pin + '\tusr/bin/bwrap'),
		text.replace('libraries\tlib:lib64', 'libraries\tlib::lib64'),
		text.replace('libraries\tlib:lib64', 'libraries\t' + ['lib'].repeat(9).join(':')),
		text.replace('10042\t10043', '9999\t10043'), text.replace('10042\t10043', '20000\t10043'),
		text.replace('10042\t10043', '+0042\t10043'), text.replace('10042\t10043', '10042\t00043'),
		text.replace('10042\t10043', '10042\t20000'),
		text.replace('/var/lib/vinix/apps/10042', '/var/lib/vinix/apps/../10042'),
		text.replace('/var/lib/vinix/apps/10042', 'var/lib/vinix/apps/10042'),
		text.replace('10042\t10043\t/var/lib/vinix/apps/10042', '10042\t10043')] {
		assert invalid != text && rejects_manifest(invalid), invalid
	}
	assert rejects_manifest('x'.repeat(manifest_limit + 1) + '\n')
	too_many := manifest_header + '\n' + 'x\ty\n'.repeat(20033)
	parse_manifest(too_many) or {
		assert err.msg().contains('entry count')
		return
	}
	assert false, 'manifest entry count limit was not enforced'
}

fn test_paths_and_hashes_reject_ambiguous_or_noncanonical_inputs() {
	for path in ['bin/engine', 'lib/ld.so', 'share/fonts'] {
		assert clean_path(path, false) && !clean_path(path, true)
		assert clean_path('/' + path, true) && !clean_path('/' + path, false)
	}
	for path in ['', '.', '..', 'a/.', 'a/..', './a', '../a', 'a/../b', 'a//b', 'a/', 'a\\b', 'a:b',
		'a\x00b', 'a\tb', 'a\nb', 'a\rb', 'a\x1fb', 'a\x7fb', 'a'.repeat(4097)] {
		assert !clean_path(path, false), path
		assert !clean_path('/' + path, true), path
	}
	assert !clean_path('/', true) && !clean_path('//root', true)
	assert hash_valid(test_pin)
	for hash in ['', test_pin[..63], test_pin + '0', test_pin.to_upper(), 'z'.repeat(64),
		'0'.repeat(63) + '\n'] {
		assert !hash_valid(hash)
	}
}

fn metadata(mode u32, uid u32, links u64, size i64) C.stat {
	$if macos {
		return C.stat{ st_mode: u16(mode), st_uid: uid, st_nlink: u16(links), st_size: size }
	} $else {
		return C.stat{ st_mode: mode, st_uid: uid, st_nlink: links, st_size: u64(size) }
	}
}

fn test_root_metadata_enforces_readonly_regular_files_without_link_or_mode_bypasses() {
	for mode in [u32(0o100400), 0o100444, 0o100555] {
		assert protected_metadata(metadata(mode, 0, 1, 12), false)
	}
	for mode in [u32(0o100644), 0o100464, 0o100446, 0o104444, 0o102444, 0o101444, 0o120444, 0o040555,
		0o010444, 0o020444, 0o060444, 0o140444] {
		assert !protected_metadata(metadata(mode, 0, 1, 12), false), mode.str()
	}
	assert !protected_metadata(metadata(0o100444, 10042, 1, 12), false)
	assert !protected_metadata(metadata(0o100444, 0, 0, 12), false)
	assert !protected_metadata(metadata(0o100444, 0, 2, 12), false)
	assert protected_metadata(metadata(0o100444, 0, 1, i64(file_limit)), false)
	assert !protected_metadata(metadata(0o100444, 0, 1, i64(file_limit + 1)), false)
	assert !protected_metadata(metadata(0o100444, 0, 1, -1), false)
	for mode in [u32(0o040755), 0o040700, 0o040555] {
		assert protected_metadata(metadata(mode, 0, 2, 0), true)
	}
	for mode in [u32(0o040775), 0o040757, 0o100555, 0o120755] {
		assert !protected_metadata(metadata(mode, 0, 2, 0), true)
	}
	assert !protected_metadata(metadata(0o040755, 10042, 2, 0), true)
}

fn test_snapshot_inode_identity_requires_both_device_and_inode() {
	first := C.stat{ st_dev: 7, st_ino: 42 }
	assert same_inode(first, C.stat{ st_dev: 7, st_ino: 42 })
	assert !same_inode(first, C.stat{ st_dev: 8, st_ino: 42 })
	assert !same_inode(first, C.stat{ st_dev: 7, st_ino: 43 })
}

fn count_test_fds() int {
	mut count := 0
	for fd in 0 .. 4096 {
		if C.fcntl(i32(fd), C.F_GETFD) >= 0 { count++ }
	}
	return count
}

fn test_protected_open_failures_close_all_temporary_descriptors() {
	initial := count_test_fds()
	for _ in 0 .. 32 {
		for path in ['/dev/null', '/tmp/vinix-browser-config-missing', '/dev/../dev/null'] {
			mut rejected := false
			fd := open_protected(path, false) or {
				rejected = true
				i32(-1)
			}
			if fd >= 0 { C.close(fd) }
			assert rejected, path
		}
	}
	assert count_test_fds() == initial
}

fn test_close_releases_owned_fds_once_without_closing_reused_descriptors() {
	first := unsafe { C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC) }
	second := unsafe { C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC) }
	assert first >= 0 && second >= 0 && first != second
	mut config := Config{ manifest_fd: first, root_fd: second }
	config.close()
	assert config.manifest_fd == -1 && config.root_fd == -1
	assert C.fcntl(first, C.F_GETFD) < 0 && C.fcntl(second, C.F_GETFD) < 0
	reused := unsafe { C.open(c'/dev/null', C.O_RDONLY | C.O_CLOEXEC) }
	assert reused >= 0
	defer { C.close(reused) }
	config.close()
	assert C.fcntl(reused, C.F_GETFD) >= 0
}

fn test_manifest_reader_bounds_and_caller_owned_fd_failures() {
	path := os.join_path(os.temp_dir(), 'vinix-browser-config-' + os.getpid().str())
	assert !os.exists(path)
	defer { os.rm(path) or {} }
	os.write_file(path, complete_manifest()) or { panic(err) }
	fd := unsafe { C.open(&char(path.str), C.O_RDONLY | C.O_CLOEXEC) }
	assert fd >= 0
	defer { C.close(fd) }
	assert manifest_text(fd) or { panic(err) } == complete_manifest()
	mut rejected := false
	digest_fd(fd, 4) or {
		rejected = true
		''
	}
	assert rejected && C.fcntl(fd, C.F_GETFD) >= 0
	os.write_file(path, 'x'.repeat(manifest_limit + 1)) or { panic(err) }
	rejected = false
	manifest_text(fd) or {
		rejected = true
		''
	}
	assert rejected && C.fcntl(fd, C.F_GETFD) >= 0
}

fn test_environment_opt_in_cannot_reuse_a_forged_channel_or_bypass_identity() {
	keys := ['VINIX_ANDROID_BROWSER_MANIFEST', 'VINIX_ANDROID_BROWSER_MANIFEST_SHA256',
		'VINIX_ANDROID_WEBVIEW_FD', 'WEBKIT_DISABLE_SANDBOX_THIS_IS_DANGEROUS']
	saved := os.environ()
	defer {
		for key in keys {
			if key in saved { os.setenv(key, saved[key], true) } else { os.unsetenv(key) }
		}
	}
	for key in keys { os.unsetenv(key) }
	os.setenv('VINIX_ANDROID_WEBVIEW_FD', '7', true)
	mut disabled := from_environment(10042, 10043, '/var/lib/vinix/apps/10042', true, true) or { panic(err) }
	assert !disabled.enabled && disabled.manifest_fd == -1 && disabled.root_fd == -1
	assert 'VINIX_ANDROID_WEBVIEW_FD' !in os.environ()
	disabled.close()
	for enabled in [[false, true]!, [true, false]!, [false, false]!, [true, true]!] {
		for missing in 0 .. 2 {
			os.unsetenv('VINIX_ANDROID_BROWSER_MANIFEST')
			os.unsetenv('VINIX_ANDROID_BROWSER_MANIFEST_SHA256')
			if missing == 0 {
				os.setenv('VINIX_ANDROID_BROWSER_MANIFEST', '/opt/vinix/manifest', true)
			} else {
				os.setenv('VINIX_ANDROID_BROWSER_MANIFEST_SHA256', test_pin, true)
			}
			os.setenv('VINIX_ANDROID_WEBVIEW_FD', '7', true)
			mut rejected := false
			from_environment(10042, 10043, '/var/lib/vinix/apps/10042', enabled[0], enabled[1]) or {
				rejected = true
				Config{}
			}
			assert rejected && 'VINIX_ANDROID_WEBVIEW_FD' !in os.environ()
		}
	}
	os.setenv('VINIX_ANDROID_BROWSER_MANIFEST', '/opt/vinix/manifest', true)
	os.setenv('VINIX_ANDROID_BROWSER_MANIFEST_SHA256', test_pin, true)
	for enabled in [[false, true]!, [true, false]!, [false, false]!] {
		mut rejected := false
		from_environment(10042, 10043, '/var/lib/vinix/apps/10042', enabled[0], enabled[1]) or {
			rejected = true
			Config{}
		}
		assert rejected
	}
}
