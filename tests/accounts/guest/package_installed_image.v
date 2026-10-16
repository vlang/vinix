// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

struct PackageInstalledFile { role string bytes u64 sha256 string }
struct PackageInstalledImage { format int image string files []PackageInstalledFile }

const package_installed_observation = '/root/package-installed-observation.json'
const package_installed_tools = ['/sbin/init', '/usr/bin/vinix-package', '/usr/bin/vinix-sandbox',
	'/usr/sbin/vinix-account', '/usr/sbin/vinix-authd', '/usr/sbin/vinix-session',
	'/usr/share/package-fixtures/software-image', '/usr/share/vinix/actions/packages-change',
	'/usr/share/vinix/actions/packages-launch']

fn package_installed_root() !bool {
	mut root := C.stat{}
	if C.stat(c'/', unsafe { &root }) != 0 || root.st_dev == 0 {
		return error('installed system root has no filesystem identity')
	}
	mut disk_root := false
	for line in os.read_file('/proc/mounts')!.split_into_lines() {
		fields := line.fields()
		if fields.len >= 3 && fields[0] == '/dev/root' && fields[1] == '/' && fields[2] == 'ext2' { disk_root = true }
	}
	if !disk_root { return error('Software installed-system check requires the installer-selected disk root') }
	proof := json2.decode[PackageInstalledImage](os.read_file('/usr/share/package-fixtures/installed-image.json')!)!
	assert proof.format == 1 && proof.image == 'vinix-packages-installed-sdk-1'
	assert os.read_file('/.vinix-image-id')!.trim_space() == proof.image
	assert proof.files.len == package_installed_tools.len
	mut seen := []string{}
	for file in proof.files {
		assert file.role in package_installed_tools && file.role !in seen
		seen << file.role
		mut info := C.stat{}
		if C.lstat(file.role.str, unsafe { &info }) != 0 || info.st_dev != root.st_dev
			|| info.st_mode & 0o170000 != 0o100000 || info.st_uid != 0 || info.st_mode & 0o022 != 0 {
			return error('installed tool must be an ordinary root-owned file on the system disk: ' + file.role)
		}
		bytes := os.read_bytes(file.role)!
		defer { unsafe { bytes.free() } }
		if u64(bytes.len) != file.bytes || sha256.sum(bytes).hex() != file.sha256 {
			return error('installed tool differs from its production-staged input: ' + file.role)
		}
	}
	fresh := !os.exists(package_installed_observation)
	canary := '/usr/share/package-fixtures/installed-only.txt'
	if fresh {
		assert !os.exists(canary)
		os.write_file(canary, 'Created only on the installed system disk')!
	} else { assert os.read_file(canary)! == 'Created only on the installed system disk' }
	return fresh
}
