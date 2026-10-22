// SPDX-License-Identifier: GPL-2.0-or-later
module main

import crypto.sha256
import json2
import os

const installed_id = 'vinix-software-maintenance-installed-1'
const observation_path = '/root/software-maintenance-retained.json'
const counter_path = '/home/alex/.local/share/vinix-apps/org.vinix.counter/counter.txt'

struct InstalledFile {
	path string
	bytes u64
	sha256 string
	uid u32
	gid u32
	mode u32
}

struct InstalledObservation {
	current string
	files []InstalledFile
}

fn require_uninstalled() ! {
	base := '/var/lib/vinix-packages'
	for name in ['state.json', 'current'] {
		if os.exists(base + '/' + name) || os.is_link(base + '/' + name) {
			return error('graphical acquisition requires no installed package state: ' + name)
		}
	}
	if os.is_dir(base + '/generations') && os.ls(base + '/generations')!.len != 0 {
		return error('graphical acquisition requires no existing package generations')
	}
	if (os.read_file('/var/log/vinix/auth.log') or { '' }).contains('run packages-change') {
		return error('graphical acquisition requires no previous package approval audit')
	}
}

fn observed_file(path string) !InstalledFile {
	bytes := os.read_bytes(path)!
	defer { unsafe { bytes.free() } }
	info := os.stat(path)!
	return InstalledFile{path: path, bytes: u64(bytes.len), sha256: sha256.sum(bytes).hex(),
		uid: info.uid, gid: info.gid, mode: info.mode & 0o7777}
}

fn installed_root() !bool {
	root := os.stat('/')!
	if root.dev == 0 || !os.read_file('/proc/mounts')!.split_into_lines().any(it.fields().len >= 3 &&
		it.fields()[0] == '/dev/root' && it.fields()[1] == '/' && it.fields()[2] == 'ext2') {
		return error('graphical installed check requires the installer-selected disk root')
	}
	if os.read_file('/.vinix-image-id')!.trim_space() != installed_id {
		return error('unexpected installed image identity')
	}
	proof := json2.decode[map[string]string](os.read_file('/usr/share/software-maintenance-installed.json')!)!
	for path, digest in proof {
		info := os.lstat(path)!
		if info.dev != root.dev || info.mode & 0o170000 != 0o100000 || info.uid != 0 || info.mode & 0o022 != 0 ||
			(observed_file(path)!).sha256 != digest {
			return error('installed root input identity/mode/digest differs: ' + path)
		}
	}
	fresh := !os.exists(observation_path)
	if fresh {
		if os.exists('/root/software-maintenance-disk-canary') { return error('partial installed fixture') }
		os.write_file('/root/software-maintenance-disk-canary', 'Created on the installed system disk\n')!
	} else {
		previous := json2.decode[InstalledObservation](os.read_file(observation_path)!)!
		if os.readlink('/var/lib/vinix-packages/current')! != previous.current {
			return error('installed package generation changed across cold boot')
		}
		for file in previous.files {
			if observed_file(file.path)! != file || (os.stat(file.path)!).dev != root.dev {
				return error('cold boot changed retained contents, ownership or mode: ' + file.path)
			}
		}
		println('SOFTWARE MAINTENANCE INSTALLED BOOT 2 exact tools accounts trust state private-data retained PASS')
	}
	println('SOFTWARE MAINTENANCE INSTALLED disk-root declaration modes digests PASS')
	return fresh
}

fn retain_installed() ! {
	mut files := []InstalledFile{}
	for path in ['/etc/passwd', '/etc/group', '/etc/shadow', '/etc/vinix-packages/config.json',
		'/var/lib/vinix-packages/current/state.json', '/var/lib/vinix-packages/catalog.json',
		'/var/lib/vinix-packages/trust-history.json', counter_path,
		'/root/software-maintenance-disk-canary', '/var/log/vinix/auth.log',
		media + '/index.json', media + '/index.sig'] {
		files << observed_file(path)!
	}
	os.write_file(observation_path, json2.encode(InstalledObservation{
		current: os.readlink('/var/lib/vinix-packages/current')!, files: files}) + '\n')!
}

