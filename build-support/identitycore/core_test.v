// SPDX-License-Identifier: GPL-2.0-or-later
module identitycore

import os

fn test_identity_replaces_package_links_without_modifying_their_targets() {
	work := os.join_path(os.temp_dir(), 'vinix-identity-stage-${os.getpid()}')
	os.mkdir_all(work + '/root/bin')!
	os.mkdir_all(work + '/root/usr/bin')!
	os.mkdir_all(work + '/root/usr/lib')!
	os.mkdir_all(work + '/root/etc')!
	defer { os.rmdir_all(work) or {} }
	source := os.dir(os.dir(@FILE)) + '/uname'
	os.write_file(work + '/root/bin/busybox', 'unchanged BusyBox')!
	os.write_file(work + '/external', 'external host file')!
	os.write_file(work + '/root/etc/alpine-release', '3.21.7\n')!
	os.symlink('/bin/busybox', work + '/root/bin/uname')!
	os.symlink('/bin/busybox', work + '/root/usr/bin/uname')!
	os.symlink(work + '/external', work + '/root/usr/lib/os-release')!
	os.symlink('../usr/lib/os-release', work + '/root/etc/os-release')!
	stage(work + '/root', source)!
	assert os.read_file(work + '/root/bin/busybox')! == 'unchanged BusyBox'
	assert os.read_file(work + '/external')! == 'external host file'
	assert os.read_file(work + '/root/etc/alpine-release')! == '3.21.7\n'
	assert os.read_file(work + '/root/bin/uname')! == os.read_file(source)!
	assert os.readlink(work + '/root/usr/bin/uname')! == '../../bin/uname'
	assert os.stat(work + '/root/bin/uname')!.mode & 0o777 == 0o755
	for name in ['etc/os-release', 'usr/lib/os-release'] {
		assert os.read_file(work + '/root/' + name)! == os_release
		assert !os.is_link(work + '/root/' + name)
	}
	assert os.read_file(work + '/root/etc/lsb-release')! == lsb_release
	assert os.read_file(work + '/root/etc/issue')! == issue
	assert os.read_file(work + '/root/etc/motd')! == motd
	// An Alpine package overlay can replace the metadata on later rebuilds.
	os.write_file(work + '/root/etc/os-release', 'NAME="Alpine Linux"\n')!
	stage(work + '/root', source)!
	assert os.read_file(work + '/root/etc/os-release')! == os_release
}

fn test_identity_rejects_host_root_missing_roots_and_linked_directories() {
	source := os.dir(os.dir(@FILE)) + '/uname'
	for path in ['', '/', '/path/that/does/not/exist/vinix-identity'] {
		stage(path, source) or { continue }
		assert false
	}
	work := os.join_path(os.temp_dir(), 'vinix-identity-guard-${os.getpid()}')
	os.mkdir_all(work + '/root')!
	os.mkdir_all(work + '/outside')!
	defer { os.rmdir_all(work) or {} }
	os.symlink(work + '/outside', work + '/root/etc')!
	stage(work + '/root', source) or {
		assert os.ls(work + '/outside')!.len == 0
		return
	}
	assert false
}
