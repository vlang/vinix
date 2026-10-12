// SPDX-License-Identifier: GPL-2.0-or-later
module runtimehost

import androidhost as ah
import androidrun
import cachecli
import gamehost
import hosttest
import os

pub fn prepare_debian(tools gamehost.Tools, output string) ! {
	work := hosttest.module_resolve(output)!
	cache := gamehost.path(work, 'downloads')
	gamehost.mkdir(cache)!
	compressed := gamehost.path(cache, 'Packages.xz')
	index := gamehost.path(cache, 'Packages')
	if !os.exists(compressed) {
		partial := gamehost.path(cache, 'Packages.part')
		tools.run(['curl', '-fL', '--retry', '3', '-o', partial,
			'https://deb.debian.org/debian/dists/trixie/main/binary-arm64/Packages.xz'])!
		if C.rename(partial.str, compressed.str) != 0 { return os.error_posix() }
	}
	if !os.exists(index) {
		os.write_file(index, tools.output(['xz', '--decompress', '--stdout', compressed])!)!
	}
	packages := parse_packages(os.read_file(index)!)!
	mut by_name := map[string]Package{}
	for package in packages { by_name[package.name] = package }
	meta := by_name['linux-image-cloud-arm64'] or { return error('linux-image-cloud-arm64 missing') }
	mut dependency := ''
	for group in meta.dependencies {
		for name in group {
			if name.starts_with('linux-image-') {
				dependency = name
				break
			}
		}
		if dependency != '' { break }
	}
	if dependency == '' { return error('kernel dependency missing') }
	selected := by_name[dependency] or { return error('kernel package missing: ' + dependency) }
	kernel_root := gamehost.path(work, 'root')
	gamehost.mkdir(kernel_root)!
	archive := download_package(tools, 'https://deb.debian.org/debian', selected, cache)!
	extract_deb(archive, kernel_root)!
	tools.run([gamehost.path(tools.root, 'build-support/debian-root'), '--index', index, '--mirror',
		'https://deb.debian.org/debian', '--cache', cache, '--root', gamehost.path(work, 'userland'),
		'--manifest', gamehost.path(work, 'packages.tsv'), 'base-files', 'busybox-static'])!
	kernel_name := selected.name.replace_once('linux-image-', 'vmlinuz-')
	kernel := gamehost.path(kernel_root, 'boot/' + kernel_name)
	if !os.is_file(kernel) { return error('Debian package did not contain ' + kernel_name) }
	record := ah.Value({
		'package': ah.Value(selected.name)
		'version': ah.Value(selected.version)
		'sha256':  ah.Value(selected.sha256)
		'image':   ah.Value(kernel)
	})
	os.write_file(gamehost.path(work, 'kernel.json'), androidrun.dump_json(record, 2) + '\n')!
	println('Debian kernel: ${kernel}\nDebian root: ${gamehost.path(work, 'userland')}')
}

pub fn prepare_debian_cli(root string, argv []string) !int {
	args := cachecli.arguments(argv, ['--output'], [], [], 0, 0, 'Fetch Debian ARM64 cloud kernel and minimal userspace.\nUsage: prepare-debian [--output DIR]') or { return error_with_code(err.msg(), 2) }
	prepare_debian(gamehost.Tools{ root: root }, args.value('--output', gamehost.path(root, 'build-aarch64-dhewm3/debian')))!
	return 0
}
