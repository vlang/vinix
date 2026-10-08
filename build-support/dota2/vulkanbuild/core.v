// SPDX-License-Identifier: GPL-2.0-or-later
module vulkanbuild

import json2
import os
import qemubuild

fn join(a string, b string) string { return qemubuild.join(a, b) }

fn parent(value string) string { return value.trim_right('/').all_before_last('/') }

pub fn clone_tree(source string, destination string, platform string) ! {
	qemubuild.mkdir(parent(destination), true, true)!
	if platform == 'darwin' {
		command('run', ['/bin/cp', '-cRp', source, destination], {
			'check': json2.Any(true)
		})!
	} else {
		qemubuild.clone_tree(source, destination)!
	}
}

pub fn package_files(root string) !json2.Any {
	mut files := []json2.Any{}
	for filename in qemubuild.paths(root)! {
		relative := filename[root.trim_right('/').len + 1..]
		mut value := json2.Any(json2.Null{})
		if qemubuild.is_link(filename)! {
			value = json2.Any({
				'target': json2.Any({
					'filesystem_text': json2.Any(os.readlink(filename)!.bytes().hex())
				})
			})
		} else if qemubuild.is_file(filename)! {
			value = json2.Any({
				'sha256': json2.Any(digest(filename)!)
				'mode':   json2.Any(os.stat(filename)!.mode & 0o7777)
			})
		}
		if value !is json2.Null {
			files << json2.Any([json2.Any(relative.bytes().hex()), value])
		}
	}
	return json2.Any({
		'filesystem_map': json2.Any(files)
	})
}

pub fn stage_glibc_package(resolver json2.Any, pin map[string]json2.Any, cache string, root string) ! {
	libraries := global('GLIBC_LIBRARIES')!.as_array().map(it.str())
	empty := json2.Any({
		'tuple': json2.Any([]json2.Any{})
	})
	value := method(resolver, 'Package', [pin['package']!, pin['version']!, pin['architecture']!,
		pin['filename']!, pin['sha256']!, pin['size']!, empty, empty])!
	archive := path(method(resolver, 'download', [pin['mirror']!, value, paths(cache)])!)!
	same_size := request({
		'kind':      json2.Any('equal')
		'arguments': json2.Any([json2.Any(os.stat(archive)!.size), pin['size']!])
	})!.bool()
	if !same_size || digest(archive)! != pin['sha256']!.str() {
		return fail('checksum or size mismatch for pinned libc6: ' + archive)
	}
	owner := request({
		'kind':     json2.Any('temporary')
		'keywords': json2.Any({
			'prefix': json2.Any('dota2-libc6-')
			'dir':    paths(cache)
		})
	})!.as_map()
	stage_glibc_entered(resolver, pin, archive, owner['entered']!, root, libraries) or {
		failure := err
		suppressed := request({
			'kind':      json2.Any('retire')
			'arguments': json2.Any([owner['owner']!])
			'context':   json2.Any(failure_record(failure))
		})!.bool()
		if suppressed { return }
		return failure
	}
	request({
		'kind':      json2.Any('retire')
		'arguments': json2.Any([owner['owner']!])
	})!
}

fn stage_glibc_entered(resolver json2.Any, pin map[string]json2.Any, archive string, entered json2.Any, root string, libraries []string) ! {
	payload := path(request({
		'kind':      json2.Any('call')
		'target':    global('Path')!
		'arguments': json2.Any([entered])
	})!)!
	stage_glibc_payload(resolver, pin, archive, payload, root, libraries)!
}

fn stage_glibc_payload(resolver json2.Any, pin map[string]json2.Any, archive string, payload string, root string, libraries []string) ! {
	method(resolver, 'extract_deb', [paths(archive), paths(payload)])!
	canonical := join(payload, 'usr/lib/x86_64-linux-gnu')
	for name in libraries {
		filename := join(canonical, name)
		if !qemubuild.is_file(filename)! || qemubuild.is_link(filename)! {
			return fail('pinned libc6 must contain the complete usrmerged amd64 family')
		}
	}
	files := public('package_files', [paths(payload)])!
	method(resolver, 'extract_deb', [paths(archive), paths(root)])!
	mut aliases := map[string]json2.Any{}
	mut names := os.ls(canonical) or { return qemubuild.FileError{err.code(), canonical} }
	names.sort()
	for name in names {
		filename := join(canonical, name)
		if !qemubuild.is_file(filename)! || qemubuild.is_link(filename)! { continue }
		legacy := join(root, 'lib/x86_64-linux-gnu/' + name)
		if !qemubuild.exists(legacy)! && !qemubuild.is_link(legacy)! { continue }
		qemubuild.unlink(legacy)!
		target := '../../usr/lib/x86_64-linux-gnu/' + name
		request({
			'kind':      json2.Any('symlink')
			'arguments': json2.Any([json2.Any(target), paths(legacy)])
		})!
		aliases[legacy[root.trim_right('/').len + 1..]] = json2.Any(target)
	}
	loader := join(root, 'lib64/ld-linux-x86-64.so.2')
	qemubuild.mkdir(parent(loader), true, true)!
	if qemubuild.exists(loader)! || qemubuild.is_link(loader)! { qemubuild.unlink(loader)! }
	target := '../usr/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2'
	request({
		'kind':      json2.Any('symlink')
		'arguments': json2.Any([json2.Any(target), paths(loader)])
	})!
	aliases[loader[root.trim_right('/').len + 1..]] = json2.Any(target)
	write_json(join(root, constant('GLIBC_MARKER')!), json2.Any({
		'package':      json2.Any(pin)
		'alias_policy': global('GLIBC_ALIAS_POLICY')!
		'files':        files
		'aliases':      json2.Any(aliases)
	}), true)!
}

pub fn stage_lavapipe(selected []json2.Any, root string, work string, expected map[string]json2.Any) ! {
	mut mesa := map[string]json2.Any{}
	for item in selected {
		if text(package(item), 'name') == 'mesa-vulkan-drivers' {
			mesa = package(item)
			break
		}
	}
	if mesa.len == 0 { return StageError{'StopIteration', ''} }
	if text(mesa, 'version') != text(expected, 'debian_version') {
		return fail("Debian's mesa-vulkan-drivers is " + text(mesa, 'version') + '; the Lavapipe patch is pinned to ' + text(expected, 'debian_version'))
	}
	library := path(public('build_lavapipe', [paths(root), paths(work)])!)!
	destination := join(root, constant('LAVAPIPE_LIBRARY')!)
	request({
		'kind':      json2.Any('copy2')
		'arguments': json2.Any([paths(library), paths(destination)])
	})!
	os.chmod(destination, 0o644) or { return qemubuild.FileError{err.code(), destination} }
	write_json(join(root, constant('LAVAPIPE_MARKER')!), json2.Any({
		'inputs': json2.Any(expected)
		'sha256': json2.Any(digest(destination)!)
	}), true)!
}

pub fn stage_venus(root string, work string, guest_root string, expected map[string]json2.Any) ! {
	built := public('build_venus', [paths(root), paths(work)])!.as_array()
	library := path(built[0])!
	manifest := path(built[1])!
	destination := join(root, constant('VENUS_LIBRARY')!)
	request({
		'kind':      json2.Any('copy2')
		'arguments': json2.Any([paths(library), paths(destination)])
	})!
	os.chmod(destination, 0o644) or { return qemubuild.FileError{err.code(), destination} }
	mut data := decode_json(qemubuild.read_text(manifest)!)!.as_map()
	mut icd := data['ICD']!.as_map()
	icd['library_path'] = json2.Any(guest_root.trim_right('/') + '/' + constant('VENUS_LIBRARY')!)
	data['ICD'] = json2.Any(icd)
	write_json(join(root, constant('VENUS_ICD')!), json2.Any(data), false)!
	write_json(join(root, constant('VENUS_MARKER')!), json2.Any({
		'inputs': json2.Any(expected)
		'sha256': json2.Any(digest(destination)!)
	}), true)!
}
