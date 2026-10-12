// SPDX-License-Identifier: GPL-2.0-or-later
module runtimehost

import alpinecore
import boothost
import cachecli
import gamehost
import os
import strconv

pub struct Package {
pub:
	name         string
	version      string
	architecture string
	filename     string
	sha256       string
	size         i64
	dependencies [][]string
	provides     []string
}

pub fn dependency_key(specification string) string {
	value := boothost.unicode_strip(specification)
	mut end := value.len
	for index := 0; index < value.len; index++ {
		if alpinecore.space_width(value, index) > 0 || value[index] in [u8(`(`), `[`, `<`, `>`,
			`=`] {
			end = index
			break
		}
	}
	return value[..end].all_before(':')
}

pub fn parse_relations(value string) [][]string {
	mut result := [][]string{}
	for group in value.split(',') {
		mut alternatives := []string{}
		for alternative in group.split('|') {
			name := dependency_key(alternative)
			if name != '' { alternatives << name }
		}
		if alternatives.len > 0 { result << alternatives }
	}
	return result
}

pub fn parse_packages(data string) ![]Package {
	normalized := replace_utf8(data.bytes()).replace('\r\n', '\n').replace('\r', '\n')
	mut packages := []Package{}
	for block in normalized.split('\n\n') {
		mut fields := map[string]string{}
		mut previous := ''
		for line in alpinecore.lines(block) {
			if line.len > 0 && alpinecore.space_width(line, 0) > 0 {
				if previous != '' { fields[previous] += ' ' + boothost.unicode_strip(line) }
				continue
			}
			colon := line.index(':') or { continue }
			previous = line[..colon]
			fields[previous] = boothost.unicode_strip(line[colon + 1..])
		}
		if 'Package' !in fields || 'Filename' !in fields { continue }
		mut provides := []string{}
		for item in fields['Provides'].split(',') {
			name := dependency_key(item)
			if name != '' { provides << name }
		}
		packages << Package{
			name:         fields['Package']
			version:      fields['Version']
			architecture: fields['Architecture']
			filename:     fields['Filename']
			sha256:       fields['SHA256']
			size:         strconv.parse_int(fields['Size'] or { '0' }, 10, 64)!
			dependencies: [...parse_relations(fields['Pre-Depends']),
				...parse_relations(fields['Depends'])]
			provides:     provides
		}
	}
	return packages
}

pub fn resolve(packages []Package, roots []string, ignored []string) ![]Package {
	mut by_name := map[string]int{}
	mut providers := map[string][]int{}
	for index, package in packages {
		if package.name !in by_name { by_name[package.name] = index }
		for name in package.provides { providers[name] << index }
	}
	mut selected := map[string]Package{}
	mut queue := roots.map([it])
	mut cursor := 0
	for cursor < queue.len {
		alternatives := queue[cursor]
		cursor++
		mut satisfied := false
		for name in alternatives {
			if name in selected || name in ignored {
				satisfied = true
				break
			}
		}
		if satisfied { continue }
		mut choice := -1
		for name in alternatives {
			if name in by_name {
				choice = by_name[name]
				break
			}
		}
		if choice == -1 {
			for name in alternatives {
				if name in providers {
					choice = providers[name][0]
					break
				}
			}
		}
		if choice == -1 {
			return error('unresolved Debian dependency: ' + alternatives.join(' | '))
		}
		package := packages[choice]
		if package.name in selected { continue }
		selected[package.name] = package
		queue << package.dependencies
	}
	mut names := selected.keys()
	names.sort()
	return names.map(selected[it])
}

pub fn download_package(tools gamehost.Tools, mirror string, package Package, cache string) !string {
	target := gamehost.path(cache, package.filename.all_after_last('/'))
	if os.is_file(target) && (package.sha256 == '' || gamehost.digest(target)! == package.sha256) {
		return target
	}
	url := mirror.trim_right('/') + '/' + package.filename
	eprintln('  downloading ${package.architecture}/${target.all_after_last('/')}')
	partial := target + '.partial'
	tools.run(['curl', '--fail', '--location', '--retry', '3', '--retry-all-errors', '--connect-timeout',
		'15', '--speed-limit', '1024', '--speed-time', '30', '--continue-at', '-', '--silent',
		'--show-error', '--output', partial, url])!
	if package.sha256 != '' && gamehost.digest(partial)! != package.sha256 {
		os.rm(partial)!
		return error('checksum mismatch downloading ' + url)
	}
	if C.rename(partial.str, target.str) != 0 { return os.error_posix() }
	return target
}

struct PackageDownload {
	path    string
	failure string
}

fn package_worker(tools gamehost.Tools, mirror string, cache string, packages []Package) []PackageDownload {
	mut results := []PackageDownload{}
	for package in packages {
		destination := download_package(tools, mirror, package, cache) or {
			results << PackageDownload{ failure: err.msg() }
			continue
		}
		results << PackageDownload{ path: destination }
	}
	return results
}

pub fn download_packages(tools gamehost.Tools, mirror string, cache string, packages []Package) ![]string {
	mut jobs := []thread []PackageDownload{}
	for slot in 0 .. 6 {
		mut assigned := []Package{}
		for i := slot; i < packages.len; i += 6 { assigned << packages[i] }
		jobs << spawn package_worker(tools, mirror, cache, assigned)
	}
	mut ordered := []PackageDownload{len: packages.len}
	for slot, job in jobs {
		for index, result in job.wait() { ordered[slot + index * 6] = result }
	}
	mut paths := []string{}
	for result in ordered {
		if result.failure != '' { return error(result.failure) }
		paths << result.path
	}
	return paths
}

pub fn debian_cli(root string, argv []string) !int {
	args := cachecli.arguments(argv, ['--mirror', '--cache', '--root', '--manifest'], [
		'--index',
		'--ignore',
	], ['--resolve-only'], 1, -1, 'Stage a verified Debian package closure without dpkg.\nUsage: debian-root --index Packages --mirror URL --cache DIR --root DIR [--ignore PACKAGE --manifest FILE --resolve-only] PACKAGES...') or { return error_with_code(err.msg(), 2) }
	if '--index' !in args.options { return error_with_code('missing required --index', 2) }
	mirror := args.required('--mirror') or { return error_with_code(err.msg(), 2) }
	cache := args.required('--cache') or { return error_with_code(err.msg(), 2) }
	destination := args.required('--root') or { return error_with_code(err.msg(), 2) }
	mut packages := []Package{}
	for index in args.options['--index'] { packages << parse_packages(os.read_file(index)!)! }
	selected := resolve(packages, args.positional, args.options['--ignore'])!
	lines := selected.map('${it.name}\t${it.version}\t${it.architecture}\t${it.filename}').join('\n')
	if '--resolve-only' in args.options {
		println(lines)
		return 0
	}
	if manifest := args.options['--manifest'] { os.write_file(manifest[0], lines + '\n')! }
	gamehost.mkdir(cache)!
	gamehost.mkdir(destination)!
	mut bytes := i64(0)
	for package in selected { bytes += package.size }
	eprintln('  ${selected.len} packages, ${f64(bytes) / (1 << 20):.0f} MiB of archives')
	for archive in download_packages(gamehost.Tools{ root: root }, mirror, cache, selected)! {
		extract_deb(archive, destination)!
	}
	return 0
}
