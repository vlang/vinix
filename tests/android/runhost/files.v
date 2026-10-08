module runhost

import androidhost as ah
import crypto.sha256
import encoding.hex
import json2

fn runner_digest(value string) !string {
	row := {
		'operation': ah.Value('runner_digest')
		'path_hex':  ah.Value(value.bytes().hex())
	}
	return (json2.decode[ah.Value](ah.query(ah.encode(ah.Value(row)))!)!).text()
}

fn digest(value string) !string {
	data := hex.decode(callback('read_bytes', {
		'path': ah.Value(value)
	})!.text())!
	return sha256.sum(data).hex()
}

fn streaming_digest(value string) !string {
	owner := callback('open_read', {
		'path': ah.Value(value)
	})!
	mut hash := sha256.new()
	mut failed := false
	mut cause := IError(none)
	for {
		encoded := callback('read_handle', {
			'id':    owner
			'limit': ah.Value(1024 * 1024)
		}) or {
			failed = true
			cause = err
			break
		}
		data := hex.decode(encoded.text()) or {
			failed = true
			cause = err
			break
		}
		if data.len == 0 { break }
		hash.write(data) or {
			failed = true
			cause = err
			break
		}
	}
	suppressed := retire('exit_handle', owner, failed, cause)!
	if failed && !suppressed { return cause }
	return hash.sum([]u8{}).hex()
}

fn copy_layer_tree(source string, destination string) ! {
	mkdir(destination, true, true)!
	for entry in list('iterdir', source, []ah.Value{})! {
		name := path('name', entry, []ah.Value{}, map[string]ah.Value{})!.text()
		target := join([destination, name])!
		if test('is_symlink', entry)! {
			if test('exists', target)! || test('is_symlink', target)! { unlink(target)! }
			linkname := callback('readlink', {
				'arguments': strings([entry])
			})!
			path('symlink_to', target, [linkname], map[string]ah.Value{})!
		} else if test('is_dir', entry)! {
			copy_layer_tree(entry, target)!
		} else {
			stat := callback('stat', {
				'path':   ah.Value(entry)
				'fields': strings(['st_dev', 'st_ino', 'st_nlink'])
			})!.object()
			key := ah.Value([ah.field(stat, 'st_dev'), ah.field(stat, 'st_ino')])
			if test('exists', target)! || test('is_symlink', target)! { unlink(target)! }
			multiple := (ah.integer(ah.field(stat, 'st_nlink')) or { u64(0) }) > 1
			if multiple && truth(callback('inode_contains', {
				'key': key
			})!) {
				callback('inode_link', {
					'key':  key
					'path': ah.Value(target)
				})!
			} else {
				copy(entry, target)!
				if multiple {
					callback('inode_set', {
						'key':  key
						'path': ah.Value(target)
					})!
				}
			}
		}
	}
}

fn supply_host_libraries(repo string, root string, base_libraries []string) ! {
	search := [join([root, 'lib'])!, join([root, 'usr/lib'])!,
		join([root, 'usr/lib/xorg/legacy-glx'])!]
	sources := [join([repo, 'build-aarch64-userland/staging/lib'])!,
		join([repo, 'build-aarch64-userland/staging/usr/lib'])!,
		join([repo, 'build-aarch64-x11/sysroot/lib'])!,
		join([repo, 'build-aarch64-x11/sysroot/usr/lib'])!]
	mut pending := []string{}
	for directory in [join([root, 'usr/bin'])!, join([root, 'usr/lib'])!,
		join([root, 'opt/android-test'])!] {
		if test('exists', directory)! {
			for item in list('rglob', directory, [ah.Value('*')])! {
				if test('is_file', item)! { pending << item }
			}
		}
	}
	mut visited := map[string]bool{}
	for pending.len != 0 {
		value := pending.pop()
		if value in visited { continue }
		visited[value] = true
		needed := callback('function', {
			'name':      ah.Value('needed_libraries')
			'arguments': ah.Value([ah.Value([ah.Value('path'), ah.Value(value)])])
		})!.items().map(it.text())
		for name in needed {
			if name in base_libraries { continue }
			mut found := ''
			for directory in search {
				candidate := join([directory, name])!
				if test('is_file', candidate)! {
					found = candidate
					break
				}
			}
			if found != '' {
				pending << found
				continue
			}
			mut source := ''
			for directory in sources {
				candidate := join([directory, name])!
				if test('is_file', candidate)! {
					source = candidate
					break
				}
			}
			if source == '' { continue }
			target := join([root, 'usr/lib', name])!
			mkdir(path('parent', target, []ah.Value{}, map[string]ah.Value{})!.text(), true, true)!
			copy(source, target)!
			pending << target
		}
	}
}

struct ArchivePath {
	path     string
	relative string
	length   u64
}

fn archive_body(root string, owner ah.Value) ! {
	mut identities := map[string]string{}
	mut paths := []ArchivePath{}
	for item in list('rglob', root, [ah.Value('*')])! {
		relative := path('relative_to', item, [ah.Value(root)], map[string]ah.Value{})!.text()
		length := ah.integer(callback('length', {
			'data': ah.Value(relative)
		})!) or { u64(0) }
		paths << ArchivePath{item, relative, length}
	}
	paths.sort_with_compare(fn (left &ArchivePath, right &ArchivePath) int {
		if left.length < right.length { return -1 }
		if left.length > right.length { return 1 }
		if left.path < right.path { return -1 }
		if left.path > right.path { return 1 }
		return 0
	})
	for item in paths {
		name := './' + item.relative
		info := callback('tar_info', {
			'id':   owner
			'path': ah.Value(item.path)
			'name': ah.Value(name)
		})!.object()
		mut row := {
			'id':   owner
			'info': ah.field(info, 'id')
		}
		if truth(ah.field(info, 'regular')) {
			mut identity := ''
			if (ah.integer(ah.field(info, 'size')) or { u64(0) }) >= 4096
				&& (ah.integer(callback('length', {
					'data': ah.Value(name)
				})!) or { u64(101) }) <= 100 {
				identity = ah.encode(ah.field(info, 'size')) + '\x00' + ah.encode(ah.field(info, 'mode')) + '\x00' + streaming_digest(item.path)!
			}
			if identity != '' && identity in identities {
				row['fields'] = ah.Value({
					'type':     ah.Value('1')
					'linkname': ah.Value(identities[identity])
					'size':     ah.Value(0)
				})
			} else {
				row['path'] = ah.Value(item.path)
				callback('tar_add', row)!
				if identity != '' { identities[identity] = name }
				continue
			}
		}
		callback('tar_add', row)!
	}
}

fn archive_root(root string, destination string) ! {
	owner := callback('tar_open', {
		'path':    ah.Value(destination)
		'mode':    ah.Value('w')
		'options': ah.Value({
			'format': ah.Value(0)
		})
	})!
	mut failed := false
	mut cause := IError(none)
	archive_body(root, owner) or {
		failed = true
		cause = err
	}
	suppressed := retire('tar_exit', owner, failed, cause)!
	if failed && !suppressed { return cause }
}

// The existing planner represents non-finite JSON floats with null plus the
// separately captured Python type. Preserve that established representation.
fn planner_value(value ah.Value) ah.Value {
	return match value {
		ah.Number {
			if value.text in ['nan', 'inf', '-inf'] { null() } else { value }
		}
		[]ah.Value { ah.Value(value.map(planner_value(it))) }
		map[string]ah.Value {
			mut row := map[string]ah.Value{}
			for key, item in value { row[key] = planner_value(item) }
			ah.Value(row)
		}
		else { value }
	}
}

fn split_prepare(source string, destination string) !ah.Value {
	cases := callback('json_loads', {
		'data': path('read_text', join([source, 'test-cases.json'])!, []ah.Value{}, map[string]ah.Value{})!
	})!.object()['cases'] or {
		return ah.MissingKey{'cases'}
	}
	kind := callback('type_name', {
		'value': cases
	})!.text()
	mut types := []string{}
	if cases is []ah.Value {
		for item in cases {
			types << callback('type_name', {
				'value': item
			})!.text()
		}
	}
	plan := ah.split_probe_plan(planner_value(cases), kind, types)!.object()
	mkdir(destination, false, false)!
	mut checksums := map[string]ah.Value{}
	for filename in ah.field(plan, 'files').items().map(it.text()) {
		target := join([destination, filename])!
		copy(join([source, filename])!, target)!
		checksums[filename] = ah.Value(runner_digest(target)!)
	}
	for launch in ah.field(plan, 'launches').items() {
		row := launch.object()
		target := join([destination, text(row, 'name')])!
		write(target, text(row, 'script'))!
		chmod(target, 0o755)!
		name := path('name', target, []ah.Value{}, map[string]ah.Value{})!.text()
		write(path('with_name', target, [ah.Value(name + '.expected')], map[string]ah.Value{})!.text(), text(row, 'expected'))!
		write(path('with_name', target, [ah.Value(name + '.error')], map[string]ah.Value{})!.text(), text(row, 'error'))!
	}
	return ah.Value(checksums)
}

fn copy_layer(source string, destination string, reset bool) ! {
	if reset { callback('inode_reset', map[string]ah.Value{})! }
	copy_layer_tree(source, destination)!
}
