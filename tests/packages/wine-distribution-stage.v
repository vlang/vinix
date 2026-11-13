// SPDX-License-Identifier: GPL-2.0-or-later
// Reconstruct a fresh local distribution input tree; never restore originals.
module main

import hwhost
import json2
import os
import tests.packages.wineoverlay
import winepatch

fn tool(argv []string, log string) ! {
	os.write_file(log + '.argv.json', json2.encode(argv))!
	hwhost.run_tool(argv, map[string]string{}, log, 120)!
}
fn links(path string, root string) ! {
	for name in os.ls(path)! {
		entry := path + '/' + name
		info := os.lstat(entry)!
		if info.get_filetype() == .symbolic_link {
			target := os.readlink(entry)!
			local := os.abs_path(if target.starts_with('/') { root + target } else { os.dir(entry) + '/' + target })
			if local != root && !local.starts_with(root + '/') { return error('distribution link escapes fresh root') }
			if target.starts_with('/') {
				os.rm(entry)!
				os.symlink(os.path_rel(os.dir(entry), local)!, entry)!
			}
		} else if info.get_filetype() == .directory { links(entry, root)! }
	}
}
fn run() ! {
	if os.args.len != 7 { return error('usage: STAGE FRESH_OUTPUT PACKAGE_LIST DOWNLOADS HISTORICAL_INPUT_JSON HISTORICAL_ROOT FONT_CONFIG') }
	work := os.abs_path(os.args[1]); downloads := os.real_path(os.args[3])
	if os.exists(work) || os.is_link(work) { return error('fresh distribution output required') }
	os.mkdir_all(work + '/logs')!
	root := work + '/stage/usr/libexec/vinix-x86_64/root'
	os.mkdir_all(root)!
	mut inputs := map[string]string{}
	for path in [os.executable(), @FILE, os.args[2], os.args[4], os.args[6], '/usr/bin/tar'] { inputs[path] = wineoverlay.digest(path)! }
	patch_sources := os.real_path(os.dir(@FILE) + '/../../build-support/x86-translation/winepatch')
	for path in os.walk_ext(patch_sources, '.v') { inputs[path] = wineoverlay.digest(path)! }
	mut index := 0
	for line in os.read_lines(os.args[2])! {
		fields := line.split('\t')
		if fields.len != 2 || fields[0] !in ['main', 'community'] || fields[1] == '' || !fields[1].ends_with('.apk') { return error('invalid distribution package list') }
		for byte in fields[1] { if !(byte >= `a` && byte <= `z`) && !(byte >= `A` && byte <= `Z`) && !(byte >= `0` && byte <= `9`) && byte !in [`-`, `_`, `.`, `+`] { return error('invalid APK name') } }
		archive := downloads + '/x86_64_' + fields[1]
		if archive in inputs { return error('duplicate distribution archive') }
		inputs[archive] = wineoverlay.digest(archive)!
		log := work + '/logs/' + index.str()
		tool(['/usr/bin/tar', '-tf', archive], log + '-names.log')!
		for name in os.read_lines(log + '-names.log')! {
			if name.starts_with('/') || name.contains('\x00') || '..' in name.split('/') { return error('unsafe distribution archive name') }
		}
		tool(['/usr/bin/tar', '-xf', archive, '-C', root, '--exclude', '.SIGN*', '--exclude', '.PKGINFO', '--exclude', '.pre-*', '--exclude', '.post-*', '--exclude', '.trigger'], log + '-extract.log')!
		index++
	}
	links(root, root)!
	for kind, file in {
		'wine-x86_64-qemu': 'x86_64-unix/ntdll.so'
		'wine-x86_64-context': 'x86_64-windows/ntdll.dll'
		'msxml-unicode': 'x86_64-windows/msxml3.dll'
		'wine-service-timeout': 'x86_64-windows/services.exe'
	} {
		message := winepatch.patch_file(kind, root + '/usr/lib/wine/' + file)!
		os.write_file(work + '/logs/' + kind + '.log', message)!
	}
	os.cp(os.args[6], root + '/etc/fonts/conf.d/35-vinix-wine.conf')!
	historical := json2.decode[map[string]string](os.read_file(os.args[4])!)!
	prefix := os.args[5].trim_right('/') + '/'
	mut failures := map[string]string{}
	mut checked := 0
	for path, expected in historical {
		if !path.starts_with(prefix) { continue }
		selected := root + '/' + path[prefix.len..]
		resolved := os.real_path(selected)
		if !resolved.starts_with(root + '/') || !os.is_file(selected) { failures[selected] = 'missing or outside fresh root'; continue }
		actual := wineoverlay.digest(selected)!
		if actual != expected { failures[selected] = actual }
		checked++
	}
	for path, expected in inputs { if wineoverlay.digest(path)! != expected { return error('distribution reconstruction input changed') } }
	os.write_file(work + '/inputs.json', json2.encode(inputs))!
	os.write_file(work + '/comparison.json', json2.encode({'checked': checked.str(), 'differences': failures.len.str(), 'scope': 'fresh selected-file byte comparison; historical originals remain required'}))!
	os.write_file(work + '/differences.json', json2.encode(failures))!
	if checked == 0 || failures.len != 0 { return error('fresh distribution differs from retained inputs; see differences.json') }
	println('WINE DISTRIBUTION STAGE PASS complete selected-file byte coverage')
}
fn main() { run() or { eprintln(err); exit(1) } }
