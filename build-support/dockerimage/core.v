// SPDX-License-Identifier: GPL-2.0-only
module dockerimage

import os
import tarcore

pub const applets = ['[', 'ash', 'awk', 'basename', 'cat', 'chmod', 'chown', 'cp', 'cut', 'date',
	'df', 'dirname', 'du', 'echo', 'env', 'false', 'find', 'grep', 'head', 'hostname', 'id', 'kill',
	'ln', 'ls', 'mkdir', 'mount', 'mv', 'printf', 'ps', 'pwd', 'readlink', 'rm', 'sed', 'sh', 'sleep',
	'sort', 'stat', 'sync', 'tail', 'tee', 'test', 'touch', 'tr', 'true', 'umount', 'uname', 'uniq',
	'wc', 'whoami', 'xargs']

pub const directories = ['bin', 'dev', 'etc', 'proc', 'root', 'sys', 'tmp', 'usr', 'usr/bin', 'var']
pub const epoch = i64(1735689600)

pub fn build(busybox_path string, output string) !u64 {
	busybox := os.read_bytes(busybox_path)!
	os.mkdir_all(os.dir(output))!
	mut archive := tarcore.create(output)!
	defer { archive.close() }
	for directory in directories {
		archive.add(tarcore.Member{
			name:  directory
			kind:  `5`
			mode:  if directory == 'tmp' { 0o1777 } else { 0o755 }
			mtime: epoch
		}, []u8{})!
	}
	archive.add(tarcore.Member{ name: 'bin/busybox', mode: 0o755, size: busybox.len, mtime: epoch }, busybox)!
	for applet in applets {
		archive.add(tarcore.Member{ name: 'bin/${applet}', kind: `2`, linkname: 'busybox', mode: 0o777, mtime: epoch }, []u8{})!
	}
	files := {
		'etc/passwd':     'root:x:0:0:root:/root:/bin/sh\nnobody:x:65534:65534:nobody:/:/bin/false\n'
		'etc/group':      'root:x:0:\nnogroup:x:65534:\n'
		'etc/os-release': 'NAME="Vinix busybox"\nID=vinix-busybox\n'
	}
	for name, content in files {
		archive.add(tarcore.Member{ name: name, mode: 0o644, size: content.len, mtime: epoch }, content.bytes())!
	}
	return archive.finish()!
}

pub fn run(args []string) int {
	mut values := map[string]string{}
	mut index := 0
	for index < args.len {
		arg := args[index]
		if arg in ['-h', '--help'] {
			println('Usage: make-docker-image --busybox PATH --output PATH [--tag TAG]')
			println('Write a deterministic busybox root filesystem tar for docker import.')
			return 0
		}
		name := arg.all_before('=')
		if name !in ['--busybox', '--output', '--tag'] {
			eprintln('unknown argument: ${arg}')
			return 2
		}
		if arg.contains('=') {
			values[name] = arg.all_after('=')
		} else {
			index++
			if index == args.len {
				eprintln('${name} requires a value')
				return 2
			}
			values[name] = args[index]
		}
		index++
	}
	if '--busybox' !in values || '--output' !in values {
		eprintln('Usage: make-docker-image --busybox PATH --output PATH [--tag TAG]')
		return 2
	}
	size := build(values['--busybox'], values['--output']) or {
		eprintln(err)
		return 1
	}
	println('rootfs tar: ${values['--output']} (${size} bytes)')
	return 0
}
