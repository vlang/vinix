// SPDX-License-Identifier: GPL-2.0-or-later
// Vendor glibc libraries stay private and never replace the Alpine desktop.
module main

import os

struct FirstRunDebianPackage {
	name         string
	filename     string
	sha256       string
	dependencies [][]string
	provides     []string
}

fn first_run_debian_relations(text string) [][]string {
	mut groups := [][]string{}
	for group in text.split(',') {
		mut names := []string{}
		for alternative in group.split('|') {
			name := alternative.trim_space().all_before(' ').all_before('(').all_before(':')
			if name != '' { names << name }
		}
		if names.len > 0 { groups << names }
	}
	return groups
}

fn first_run_debian_packages(text string) []FirstRunDebianPackage {
	mut packages := []FirstRunDebianPackage{}
	for block in text.split('\n\n') {
		mut fields := map[string]string{}
		mut previous := ''
		for line in block.split_into_lines() {
			if line.starts_with(' ') || line.starts_with('\t') {
				fields[previous] += ' ' + line.trim_space()
				continue
			}
			colon := line.index(':') or { continue }
			previous = line[..colon]
			fields[previous] = line[colon + 1..].trim_space()
		}
		filename := fields['Filename']
		if fields['Package'] == '' || filename == '' || filename.starts_with('/')
			|| filename.split('/').contains('..') {
			continue
		}
		mut provides := []string{}
		for group in first_run_debian_relations(fields['Provides']) { provides << group }
		packages << FirstRunDebianPackage{
			name:         fields['Package']
			filename:     filename
			sha256:       fields['SHA256']
			dependencies: [...first_run_debian_relations(fields['Pre-Depends']),
				...first_run_debian_relations(fields['Depends'])]
			provides:     provides
		}
	}
	return packages
}

fn first_run_debian_resolve(packages []FirstRunDebianPackage, roots []string) ![]FirstRunDebianPackage {
	mut by_name := map[string]int{}
	mut providers := map[string]int{}
	for i, package in packages {
		by_name[package.name] = i
		for name in package.provides { if name !in providers { providers[name] = i } }
	}
	mut selected := map[string]bool{}
	mut result := []FirstRunDebianPackage{}
	mut queue := roots.map([it])
	for cursor := 0; cursor < queue.len; cursor++ {
		alternatives := queue[cursor]
		if alternatives.any(it in selected) { continue }
		mut choice := -1
		for name in alternatives {
			if name in by_name {
				choice = by_name[name]
				break
			}
		}
		if choice < 0 {
			for name in alternatives {
				if name in providers {
					choice = providers[name]
					break
				}
			}
		}
		if choice < 0 {
			return error('missing Linux runtime dependency: ' + alternatives.join(' | '))
		}
		package := packages[choice]
		if package.name in selected { continue }
		selected[package.name] = true
		result << package
		queue << package.dependencies
	}
	return result
}

fn first_run_debian_triplet(arch string) string {
	return match arch {
		'aarch64' { 'aarch64-linux-gnu' }
		'i386' { 'i386-linux-gnu' }
		else { 'x86_64-linux-gnu' }
	}
}

fn first_run_linux_loader(arch string) string {
	return match arch {
		'aarch64' { 'ld-linux-aarch64.so.1' }
		'i386' { 'ld-linux.so.2' }
		else { 'ld-linux-x86-64.so.2' }
	}
}

fn first_run_linux_runtime_packages() []string {
	return ['libc6', 'libstdc++6', 'libasound2t64', 'libgtk-3-0t64', 'libnss3', 'libxss1', 'libxtst6',
		'libxshmfence1', 'libgbm1', 'libsecret-1-0', 'libcurl4t64', 'libvulkan1', 'mesa-vulkan-drivers',
		'libgl1', 'libegl1', 'libatomic1', 'libnotify4']
}

fn first_run_materialize_libraries(root string, directory string) ! {
	for name in os.ls(directory)! {
		path := directory + '/' + name
		if os.is_link(path) {
			if !name.contains('.so') { continue }
			mut target := path
			for _ in 0 .. 32 {
				if !os.is_link(target) { break }
				link := os.readlink(target)!
				target = os.norm_path(if link.starts_with('/') {
					root + link
				} else {
					os.dir(target) + '/' + link
				})
				if !target.starts_with(root + '/') {
					return error('Linux library link leaves its private runtime')
				}
			}
			if os.is_file(target) && !os.is_link(target) {
				os.cp(target, path + '.setup')!
				os.rm(path)!
				os.mv(path + '.setup', path)!
			}
		} else if os.is_dir(path) {
			first_run_materialize_libraries(root, path)!
		}
	}
}

fn first_run_install_linux_runtime(arch string, work string) ! {
	if arch !in ['aarch64', 'x86_64', 'i386'] {
		return error('unsupported Linux runtime architecture')
	}
	$if arm64 {
		if arch in ['x86_64', 'i386'] {
			translator := if arch == 'i386' { 'qemu-i386' } else { 'qemu-x86_64' }
			if !os.is_executable('/usr/bin/' + translator) {
				first_run_tool(['pkg', 'install', translator])!
			}
		}
	}
	destination := '/opt/vinix-linux/' + arch
	loader := '/usr/lib/' + first_run_debian_triplet(arch) + '/' + first_run_linux_loader(arch)
	if os.is_file(destination + '/.setup-v1') && os.is_executable(destination + loader) { return }
	println('Installing the private ${arch} Linux runtime')
	debian_arch := match arch {
		'aarch64' { 'arm64' }
		'x86_64' { 'amd64' }
		else { 'i386' }
	}
	index := work + '/Packages-${arch}.xz'
	first_run_download('https://deb.debian.org/debian/dists/trixie/main/binary-${debian_arch}/Packages.xz', index)!
	text := first_run_tool(['/usr/bin/bsdtar', '-xOf', index, '--format=raw']) or {
		// xz is part of the small on-demand extraction toolset.
		first_run_tool(['pkg', 'install', 'xz'])!
		first_run_tool(['/usr/bin/xz', '-dc', index])!
	}
	packages := first_run_debian_packages(text)
	// Include the ordinary Electron/GTK/CEF libraries and Vulkan's software
	// renderer. Debian owns dependency resolution within this private tree.
	selected := first_run_debian_resolve(packages, first_run_linux_runtime_packages())!
	stage := work + '/linux-' + arch
	os.mkdir_all(stage)!
	for package in selected {
		archive := work + '/' + os.file_name(package.filename)
		first_run_download('https://deb.debian.org/debian/' + package.filename, archive)!
		first_run_verify_hash(archive, package.sha256)!
		first_run_unpack(archive, stage, true)!
		os.rm(archive)!
	}
	first_run_materialize_libraries(stage, stage)!
	first_run_elf_arch(stage + loader, arch)!
	os.chmod(stage + loader, 0o755)!
	os.write_file(stage + '/.setup-v1', 'Debian trixie ${debian_arch}\n')!
	os.mkdir_all('/opt/vinix-linux')!
	if os.exists(destination) {
		return error('incomplete Linux runtime exists at ${destination}; move it aside and retry')
	}
	os.mv(stage, destination)!
}
