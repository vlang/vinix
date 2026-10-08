module boothost

import androidhost as ah
import crypto.sha256
import encoding.hex
import json2

struct Prepared {
	jars     string
	manifest map[string]ah.Value
}

fn mkdir(name string, parents bool, exist_ok bool) ! {
	path('mkdir', name, [], {
		'parents':  ah.Value(parents)
		'exist_ok': ah.Value(exist_ok)
	})!
}

fn (e Engine) prepare(build_dir string, java string) !Prepared {
	mkdir(build_dir, true, true)!
	downloads := join(build_dir, 'downloads')!
	mkdir(downloads, false, true)!
	mut archives := []string{}
	for record in e.c('INPUTS').items() { archives << e.download(record.object(), downloads)! }
	key_hash := text(e.cache_identity()!, 'key')
	cache := join(build_dir, 'bootclasspath-runtime-manifest.json')!
	jars := join(build_dir, 'jars')!
	if path('is_file', cache, [], {})! as bool {
		previous := e.cached(jars, cache) or {
			if err is BindingError {
				if text(err.value, 'kind') !in ['RuntimeError', 'ValueError', 'JSONDecodeError',
					'OSError', 'FileNotFoundError', 'PermissionError', 'IsADirectoryError',
					'NotADirectoryError'] {
					return err
				}
			} else if err !is PolicyError {
				return err
			}
			map[string]ah.Value{}
		}
		if text(previous, 'input_key') == key_hash { return Prepared{jars, previous} }
	}
	work := join(build_dir, 'work')!
	if path('exists', work, [], {})! as bool {
		callback('rmtree', {
			'path': ah.Value(work)
		})!
	}
	mkdir(work, false, false)!
	raw := join(work, 'core-all_classes.jar')!
	e.extract_member(archives[1], e.c('JAVA_CLASS_JAR').text(), raw)!
	version := strip_python(callback('capture', {
		'arguments': strings([java, '-cp', archives[2], 'com.android.tools.r8.D8', '--version'])
	})!.text())
	next_jars := join(build_dir, 'jars.next')!
	if path('exists', next_jars, [], {})! as bool {
		callback('rmtree', {
			'path': ah.Value(next_jars)
		})!
	}
	destination := join(next_jars, e.c('BOOT_DIRECTORY').text())!
	mkdir(destination, true, false)!
	mut files := []ah.Value{}
	for value in e.c('BOOT_JARS').items() {
		name := value.text()
		original := join(work, name)!
		e.extract_member(archives[0], e.c('BOOT_DIRECTORY').text() + '/' + name, original)!
		before := e.jar_info(original)!
		inputs := join(work, name + '.classes.jar')!
		e.class_subset(raw, before.classes, inputs)!
		directory := join(work, name + '.dex')!
		mkdir(directory, false, false)!
		mut compiler_argv := [java, '-cp', archives[2], 'com.android.tools.r8.D8']
		compiler_argv << e.c('COMPILER_ARGUMENTS').items().map(it.text())
		compiler_argv << ['--lib', raw, '--output', directory, inputs]
		callback('run', {
			'arguments': strings(compiler_argv)
		})!
		output := join(destination, name)!
		e.package_jar(original, directory, output)!
		generated := e.jar_info(output)!
		if generated.callsites != 0 || before.classes.any(it !in generated.classes) {
			return fail('desugared bootclasspath lost classes or retained bootstrap calls: ' + name)
		}
		files << ah.Value({
			'path':                       ah.Value(e.c('BOOT_DIRECTORY').text() + '/' + name)
			'sha256':                     ah.Value(digest(output)!)
			'size':                       callback('stat', {
				'path': ah.Value(output)
			})!
			'original_sha256':            ah.Value(digest(original)!)
			'classes_before':             ah.Value(before.classes.len)
			'classes_after':              ah.Value(generated.classes.len)
			'bootstrap_callsites_before': ah.Value(before.callsites)
			'bootstrap_callsites_after':  ah.Value(generated.callsites)
		})
	}
	manifest := {
		'format':             ah.Value(1)
		'input_key':          ah.Value(key_hash)
		'compiler':           ah.Value(version)
		'compiler_arguments': e.c('COMPILER_ARGUMENTS')
		'inputs':             e.c('INPUTS')
		'files':              ah.Value(files)
	}
	e.validate_provenance(next_jars, ah.Value(manifest), ah.Value(json2.null))!
	if path('exists', jars, [], {})! as bool {
		callback('rmtree', {
			'path': ah.Value(jars)
		})!
	}
	path('replace', next_jars, [ah.Value(jars)], {})!
	next_cache := path('with_suffix', cache, [ah.Value('.json.next')], {})!.text()
	serialized := callback('json_dumps', {
		'data':    ah.Value(manifest)
		'options': ah.Value({
			'indent': ah.Value(2)
		})
	})!.text() + '\n'
	callback('write_text', {
		'path': ah.Value(next_cache)
		'data': ah.Value(serialized)
	})!
	path('replace', next_cache, [ah.Value(cache)], {})!
	return Prepared{jars, manifest}
}

fn (e Engine) cached(jars string, cache string) !map[string]ah.Value {
	previous := callback('json_loads', {
		'data': callback('read_text', {
			'path': ah.Value(cache)
		})!
	})!
	e.validate_provenance(jars, previous, ah.Value(json2.null))!
	return previous.object()
}

fn (e Engine) stage(build_dir string, overlay string, java string) !map[string]ah.Value {
	manifest_name := callback('art_import', {
		'path': ah.Value(join(e.support, 'art-runtime.py')!)
	})!.text()
	mut manifest := callback('art_read', {
		'path': ah.Value(overlay)
	})!.object()
	result := e.prepare(build_dir, java)!
	provenance := result.manifest
	replaced := ah.field(provenance, 'files').items().map(text(it.object(), 'path'))
	mut records := ah.field(manifest, 'files').items().filter(text(it.object(), 'path') !in replaced)
	for value in ah.field(provenance, 'files').items() {
		record := value.object()
		target := callback('art_inside', {
			'path': ah.Value(overlay)
			'name': key(record, 'path')!
		})!.text()
		parent := path('parent', target, [], {})!.text()
		mkdir(parent, true, true)!
		temporary := callback('temporary_copy', {
			'path':   ah.Value(parent)
			'prefix': ah.Value('.vinix-art-java-')
			'source': ah.Value(join(result.jars, text(record, 'path'))!)
		})!.text()
		e.stage_file(temporary, target, record)!
		records << ah.Value({
			'path':   key(record, 'path')!
			'sha256': key(record, 'sha256')!
			'size':   key(record, 'size')!
		})
	}
	records.sort_with_compare(fn (a &ah.Value, b &ah.Value) int {
		an := text(a.object(), 'path')
		bn := text(b.object(), 'path')
		return if an < bn {
			-1
		} else if an > bn {
			1
		} else {
			0
		}
	})
	manifest['files'] = ah.Value(records)
	manifest['bootclasspath'] = ah.Value(provenance)
	target := join(overlay, manifest_name)!
	temporary := path('with_suffix', target, [ah.Value('.json.next')], {})!.text()
	serialized := callback('json_dumps', {
		'data':    ah.Value(manifest)
		'options': ah.Value({
			'indent': ah.Value(2)
		})
	})!.text() + '\n'
	callback('write_text', {
		'path': ah.Value(temporary)
		'data': ah.Value(serialized)
	})!
	path('replace', temporary, [ah.Value(target)], {})!
	return callback('art_read', {
		'path': ah.Value(overlay)
	})!.object()
}

fn (e Engine) stage_file(temporary string, target string, record map[string]ah.Value) ! {
	e.stage_copy(temporary, target, record) or {
		path('unlink', temporary, [], {
			'missing_ok': ah.Value(true)
		})!
		return err
	}
	path('unlink', temporary, [], {
		'missing_ok': ah.Value(true)
	})!
}

fn (e Engine) stage_copy(temporary string, target string, record map[string]ah.Value) ! {
	if digest(temporary)! != key(record, 'sha256')!.text() {
		return fail('bootclasspath cache changed during staging: ' + text(record, 'path'))
	}
	path('chmod', temporary, [ah.Value(0o644)], {})!
	callback('replace', {
		'path':        ah.Value(temporary)
		'destination': ah.Value(target)
	})!
}

fn (e Engine) build_probe(build_dir string, output string, java string, javac string) ! {
	e.prepare(build_dir, java)!
	directory := join(build_dir, 'probe')!
	if path('exists', directory, [], {})! as bool {
		callback('rmtree', {
			'path': ah.Value(directory)
		})!
	}
	classes := join(directory, 'classes')!
	dex := join(directory, 'dex')!
	mkdir(classes, true, false)!
	mkdir(dex, false, false)!
	raw := join(directory, 'core-all_classes.jar')!
	downloads := join(build_dir, 'downloads')!
	e.extract_member(join(downloads, text(e.c('INPUTS').items()[1].object(), 'filename'))!, e.c('JAVA_CLASS_JAR').text(), raw)!
	support_parent := path('parent', e.support, [], {})!.text()
	root := path('parent', support_parent, [], {})!.text()
	source := join(root, 'tests/android/ArtBootProbe.java')!
	callback('run', {
		'arguments': strings([javac, '--release', '8', '-d', classes, source])
	})!
	inputs := join(directory, 'classes.jar')!
	e.archive_files(classes, inputs, '*.class', true)!
	compiler := join(downloads, text(e.c('INPUTS').items()[2].object(), 'filename'))!
	callback('run', {
		'arguments': strings([java, '-cp', compiler, 'com.android.tools.r8.D8', '--release', '--min-api',
			'26', '--lib', raw, '--output', dex, inputs])
	})!
	mkdir(path('parent', output, [], {})!.text(), true, true)!
	e.archive_files(dex, output, '*.dex', false)!
	e.jar_info(output)!
}

fn (e Engine) archive_files(directory string, output string, pattern string, recursive bool) ! {
	id := zip_open(output, 'w', 0)!
	e.archive_contents(id, directory, pattern, recursive) or {
		close(id)!
		return err
	}
	close(id)!
}

fn (e Engine) archive_contents(id ah.Value, directory string, pattern string, recursive bool) ! {
	mut files := callback(if recursive { 'rglob' } else { 'glob' }, {
		'path':    ah.Value(directory)
		'pattern': ah.Value(pattern)
	})!.items().map(it.text())
	files.sort_with_compare(fn (a &string, b &string) int { return path_order(*a, *b) })
	for file in files {
		name := if recursive {
			path('relative_to', file, [ah.Value(directory)], {})!.text()
		} else {
			path('name', file, [], {})!.text()
		}
		callback('zip_file', {
			'id':   id
			'path': ah.Value(file)
			'name': ah.Value(name)
		})!
	}
}

fn path_order(a string, b string) int {
	left := a.split('/')
	right := b.split('/')
	for index in 0 .. if left.len < right.len { left.len } else { right.len } {
		if left[index] < right[index] { return -1 }
		if left[index] > right[index] { return 1 }
	}
	return if left.len < right.len {
		-1
	} else if left.len > right.len {
		1
	} else {
		0
	}
}

fn (e Engine) cache_identity() !map[string]ah.Value {
	encoded := callback('json_dumps', {
		'data':    e.c('INPUTS')
		'options': ah.Value({
			'sort_keys': ah.Value(true)
		})
	})!.text()
	mut input := encoded.bytes()
	mut records := []ah.Value{}
	mut sources := ['art-bootclasspath.py', '_boot_native.py', '_native.py', 'boot-query.v']
	for module_name in ['boothost', 'androidhost', 'fixturehost', 'hosttest'] {
		mut helpers := []string{}
		for pattern in ['*.v', '*.h'] {
			helpers << callback('glob', {
				'path':    ah.Value(join(e.support, module_name)!)
				'pattern': ah.Value(pattern)
			})!.items().map(it.text()).filter(!it.ends_with('_test.v'))
		}
		helpers.sort()
		for helper in helpers {
			sources << module_name + '/' + path('name', helper, [], {})!.text()
		}
	}
	for name in sources {
		filename := if name == 'art-bootclasspath.py' { e.source } else { join(e.support, name)! }
		data := hex.decode(callback('read_bytes', {
			'path': ah.Value(filename)
		})!.text())!
		input << u8(0)
		input << name.bytes()
		input << u8(0)
		input << data.len.str().bytes()
		input << u8(0)
		input << data
		records << ah.Value({
			'path':   ah.Value(name)
			'size':   ah.Value(data.len)
			'sha256': ah.Value(sha256.sum(data).hex())
		})
	}
	return {
		'key':     ah.Value(sha256.sum(input).hex())
		'sources': ah.Value(records)
	}
}

fn strip_python(value string) string {
	mut left := 0
	mut right := 0
	mut cursor := 0
	mut leading := true
	for cursor < value.len {
		point, length := rune_at(value, cursor)
		cursor += length
		if leading && python_space(point) {
			left = cursor
			continue
		}
		leading = false
		if !python_space(point) { right = cursor }
	}
	return value[left..if right < left { left } else { right }]
}

fn rune_at(value string, position int) (rune, int) {
	first := value[position]
	length := if first < 0x80 {
		1
	} else if first < 0xe0 {
		2
	} else if first < 0xf0 {
		3
	} else {
		4
	}
	mut point := u32(first & if length == 1 {
		u8(0x7f)
	} else if length == 2 {
		u8(0x1f)
	} else if length == 3 {
		u8(0x0f)
	} else {
		u8(0x07)
	})
	for index in 1 .. length { point = point << 6 | u32(value[position + index] & 0x3f) }
	return rune(point), length
}

fn python_space(point rune) bool {
	return (point >= 9 && point <= 13) || (point >= 0x1c && point <= 0x20) || point in [
		rune(0x85),
		0xa0,
		0x1680,
		0x2028,
		0x2029,
		0x202f,
		0x205f,
		0x3000,
	] || (point >= 0x2000 && point <= 0x200a)
}
