// SPDX-License-Identifier: GPL-2.0-or-later
module muslstage

import androidhost as ah

struct Publication {
	args         string
	stage        string
	retain       string
	loader       string
	version      string
	source_sha   string
	source_url   string
	cc           string
	ar           string
	ranlib       string
	patch_inputs string
	cflags       string
	ldflags      string
	optimization string
	manifest     string
	key          string
	cache        string
}

fn publish(c Publication) !string {
	manager := method(join(c.cache, 'build.lock')!, 'open', [v(ah.Value('w'))], {})!
	lock_file := enter(manager)!
	publish_locked(c, lock_file) or {
		cause := err
		if !retire(manager, cause)! { return cause }
		return report_published(c)!
	}
	retire(manager, none)!
	return report_published(c)!
}

fn report_published(c Publication) !string {
	version := text(c.version)!
	arch := text(attribute(c.args, 'arch')!)!
	retain := text(c.retain)!
	short_key := item(c.key, o(call('builtins.slice', v(none_value()), v(ah.Value(12)), v(none_value()))!))!
	call('print', v(ah.Value('    staged Vinix musl ' + version + ' (' + arch + ', retention=' + retain + ', ' + text(short_key)! + ')')))!
	return literal(ah.Value(0))!
}

fn publish_locked(c Publication, lock_file string) ! {
	call('fcntl.flock', o(lock_file), o(constant('fcntl.LOCK_EX')!))!
	build := div(div(c.cache, attribute(c.args, 'arch')!)!, c.key)!
	published := join(build, 'build.json')!
	if !truth(method(published, 'is_file', [], {})!)! { rebuild(c, build, published)! }
	objects := join(build, 'objects')!
	loads := constant('json.loads')!
	cached_manifest := load_published(loads, published) or {
		cause := err
		release(loads)!
		return cause
	}
	input_items := iterator(method(c.manifest, 'items', [], {})!)!
	for {
		input := next(input_items)!
		if input.done { break }
		values := pair(input.value)!
		if compare('ne', method(cached_manifest, 'get', [o(values[0])], {})!, values[1])! {
			fail('cached musl build inputs do not match: ' + text(values[0])!)!
		}
	}
	for fields in [['libc.so', 'libc_so_sha256'], ['libc.a', 'libc_a_sha256']] {
		library := join(join(objects, 'lib')!, fields[0])!
		if compare('ne', call('sha256', o(library))!, method(cached_manifest, 'get', [v(ah.Value(fields[1]))], {})!)! {
			fail('cached musl library checksum mismatch: ' + text(library)!)!
		}
	}
	check_output := constant('subprocess.check_output')!
	readelf := locate_readelf(check_output, c.cc) or {
		cause := err
		release(check_output)!
		return cause
	}
	// Set subtraction and sorted diagnostics retain the original callback semantics.
	missing := call('operator.sub', o(exports(readelf, c.loader)!), o(exports(readelf, join(objects, 'lib/libc.so')!)!))!
	if truth(missing)! {
		fail('rebuilt libc would remove existing exports: ' + text(method(literal(ah.Value(', '))!, 'join', [o(call('sorted', o(missing))!)], {})!)!)!
	}
	set_factory := constant('set')!
	required := required_exports(set_factory, c.args) or {
		cause := err
		release(set_factory)!
		return cause
	}
	required_missing := call('operator.sub', o(required), o(exports(readelf, join(objects, 'lib/libc.so')!)!))!
	if truth(required_missing)! {
		fail('rebuilt libc lacks required runtime exports: ' + text(method(literal(ah.Value(', '))!, 'join', [o(call('sorted', o(required_missing))!)], {})!)!)!
	}
	apply(constant('install')!, [o(join(objects, 'lib/libc.so')!),
		o(join(c.stage, 'lib/ld-musl-' + text(attribute(c.args, 'arch')!)! + '.so.1')!),
		v(ah.Value(0o755))])!
	apply(constant('replace_link')!, [
		o(join(c.stage, 'lib/libc.musl-' + text(attribute(c.args, 'arch')!)! + '.so.1')!),
		v(ah.Value('ld-musl-' + text(attribute(c.args, 'arch')!)! + '.so.1')),
	])!
	if truth(method(join(c.stage, 'usr/include/stdlib.h')!, 'is_file', [], {})!)! {
		apply(constant('install')!, [o(join(objects, 'lib/libc.a')!),
			o(join(c.stage, 'usr/lib/libc.a')!), v(ah.Value(0o644))])!
		apply(constant('install')!, [
			o(join(build, 'musl-' + text(c.version)! + '/include/malloc.h')!),
			o(join(c.stage, 'usr/include/malloc.h')!),
			v(ah.Value(0o644)),
		])!
		apply(constant('replace_link')!, [o(join(c.stage, 'usr/lib/libc.so')!),
			v(ah.Value('../../lib/ld-musl-' + text(attribute(c.args, 'arch')!)! + '.so.1'))])!
	}
	apply(constant('install')!, [o(published), o(join(c.stage, 'usr/share/vinix/musl-build.json')!),
		v(ah.Value(0o644))])!
	apply(constant('install')!, [
		o(join(build, 'musl-' + text(c.version)! + '/COPYRIGHT')!),
		o(join(c.stage, 'usr/share/licenses/musl/COPYRIGHT')!),
		v(ah.Value(0o644)),
	])!
}

fn load_published(factory string, published string) !string {
	return evaluated(factory, [o(method(published, 'read_text', [], {})!)], {})!
}

fn locate_readelf(factory string, cc string) !string {
	value := evaluated(factory, [o(add(cc, words(['-print-prog-name=readelf'])!)!)], {
		'text': v(ah.Value(true))
	})!
	return method(value, 'strip', [], {})!
}

fn required_exports(factory string, args string) !string {
	return evaluated(factory, [o(attribute(args, 'require_export')!)], {})!
}

fn rebuild(c Publication, build string, published string) ! {
	source_archive := join(c.cache, 'musl-' + text(c.version)! + '.tar.gz')!
	if !truth(method(source_archive, 'is_file', [], {})!)! { download(c, source_archive)! }
	if compare('ne', call('sha256', o(source_archive))!, c.source_sha)! {
		fail('musl release checksum mismatch')!
	}
	if truth(method(build, 'exists', [], {})!)! { call('shutil.rmtree', o(build))! }
	method(build, 'mkdir', [], {
		'parents': v(ah.Value(true))
	})!
	source := join(build, 'musl-' + text(c.version)!)!
	extract_source(c, source_archive, build)!
	manager := method(join(build, 'build.log')!, 'open', [v(ah.Value('w'))], {})!
	log := enter(manager)!
	build_logged(c, build, source, published, log) or {
		cause := err
		if !retire(manager, cause)! { return cause }
		return
	}
	retire(manager, none)!
}

fn download(c Publication, source_archive string) ! {
	values := pair(invoke('tempfile.mkstemp', [], {
		'prefix': v(ah.Value('.musl-download.'))
		'dir':    o(c.cache)
	})!)!
	call('os.close', o(values[0]))!
	download_body(c, values[1], source_archive) or {
		cause := err
		cleanup_temporary(values[1], cause)!
		return cause
	}
	cleanup_temporary(values[1], none)!
}

fn download_body(c Publication, temporary string, source_archive string) ! {
	manager := invoke('urllib.request.urlopen', [o(c.source_url)], {
		'timeout': v(ah.Value(60))
	})!
	response := enter(manager)!
	copy_download(response, temporary) or {
		cause := err
		if !retire(manager, cause)! { return cause }
		finish_download(c, temporary, source_archive)!
		return
	}
	retire(manager, none)!
	finish_download(c, temporary, source_archive)!
}

fn copy_download(response string, temporary string) ! {
	manager := call('open', o(temporary), v(ah.Value('wb')))!
	output := enter(manager)!
	call('shutil.copyfileobj', o(response), o(output)) or {
		cause := err
		if !retire(manager, cause)! { return cause }
		return
	}
	retire(manager, none)!
}

fn finish_download(c Publication, temporary string, source_archive string) ! {
	factory := constant('sha256')!
	digest := download_digest(factory, temporary) or {
		cause := err
		release(factory)!
		return cause
	}
	if compare('ne', digest, c.source_sha)! {
		fail('musl release checksum mismatch')!
	}
	call('os.replace', o(temporary), o(source_archive))!
}

fn download_digest(factory string, temporary string) !string {
	return evaluated(factory, [o(call('Path', o(temporary))!)], {})!
}

fn extract_source(c Publication, source_archive string, build string) ! {
	manager := call('tarfile.open', o(source_archive))!
	archive := enter(manager)!
	extract_body(c, archive, build) or {
		cause := err
		if !retire(manager, cause)! { return cause }
		return
	}
	retire(manager, none)!
}

fn extract_body(c Publication, archive string, build string) ! {
	values := method(archive, 'getmembers', [], {})!
	entries := iterator(values) or {
		cause := err
		release(values)!
		return cause
	}
	release(values)!
	mut cursor := ArchiveCursor{}
	validate_entries(c, entries, mut cursor) or {
		cause := err
		release_error([entries], cause)!
		return cause
	}
	release(entries)!
	method(archive, 'extractall', [o(build)], {})!
}

struct ArchiveCursor {
mut:
	previous string
	parts    string
}

fn validate_entries(c Publication, entries string, mut cursor ArchiveCursor) ! {
	for {
		entry := next(entries)!
		if entry.done { break }
		if cursor.previous != '' { release(cursor.previous)! }
		cursor.previous = entry.value
		factory := constant('Path')!
		path := archive_path(factory, entry.value) or {
			cause := err
			release(factory)!
			return cause
		}
		parts := attribute(path, 'parts') or {
			cause := err
			release(path)!
			return cause
		}
		release(path)!
		if cursor.parts != '' { release(cursor.parts)! }
		cursor.parts = parts
		if !truth(parts)! || compare('ne', item(parts, v(ah.Value(0)))!, literal(ah.Value('musl-' + text(c.version)!))!)! || truth(call('operator.contains', o(parts), v(ah.Value('..')))!)! || truth(method(entry.value, 'issym', [], {})!)! || truth(method(entry.value, 'islnk', [], {})!)! {
			fail('unsafe musl archive entry: ' + text(attribute(entry.value, 'name')!)!)!
		}
	}
}

fn archive_path(factory string, entry string) !string {
	return evaluated(factory, [o(attribute(entry, 'name')!)], {})!
}

fn build_logged(c Publication, build string, source string, published string, log string) ! {
	snapshots := join(build, 'patches')!
	method(snapshots, 'mkdir', [], {})!
	patches := iterator(c.patch_inputs)!
	for {
		input := next(patches)!
		if input.done { break }
		values := pair(input.value)!
		patch := div(snapshots, values[0])!
		method(patch, 'write_bytes', [o(values[1])], {})!
		factory := constant('subprocess.run')!
		run_patch(factory, patch, source, log) or {
			cause := err
			release(factory)!
			return cause
		}
	}
	if compare('eq', c.version, literal(ah.Value('1.2.6'))!)! {
		for name in ['memcpy.s', 'memmove.s'] {
			method(join(join(source, 'src/string/x86_64')!, name)!, 'unlink', [], {})!
		}
	}
	objects := join(build, 'objects')!
	method(objects, 'mkdir', [], {})!
	dict_factory := constant('dict')!
	env := build_environment(dict_factory, c) or {
		cause := err
		release(dict_factory)!
		return cause
	}
	configure := collection('list', [call('str', o(join(source, 'configure')!))!,
		literal(ah.Value('--target=' + text(attribute(c.args, 'arch')!)! + '-linux-musl'))!,
		literal(ah.Value('--prefix=/usr'))!, literal(ah.Value('--syslibdir=/lib'))!,
		literal(ah.Value('--disable-wrapper'))!,
		literal(ah.Value('--enable-optimize=' + text(c.optimization)!))!])!
	options := {
		'cwd':    o(objects)
		'env':    o(env)
		'check':  v(ah.Value(true))
		'stdout': o(log)
		'stderr': o(log)
	}
	invoke('subprocess.run', [o(configure)], options)!
	make_factory := constant('subprocess.run')!
	run_make(make_factory, c.args, options) or {
		cause := err
		release(make_factory)!
		return cause
	}
	set_item(c.manifest, v(ah.Value('configure_argv')), o(configure))!
	set_item(c.manifest, v(ah.Value('libc_so_sha256')), o(call('sha256', o(join(objects, 'lib/libc.so')!))!))!
	set_item(c.manifest, v(ah.Value('libc_a_sha256')), o(call('sha256', o(join(objects, 'lib/libc.a')!))!))!
	writer := attribute(published, 'write_text')!
	publish_manifest(writer, c.manifest) or {
		cause := err
		release(writer)!
		return cause
	}
}

fn run_patch(factory string, patch string, source string, log string) ! {
	argv := collection('list', [literal(ah.Value('patch'))!, literal(ah.Value('--batch'))!,
			literal(ah.Value('-p1'))!, literal(ah.Value('-i'))!, call('str', o(patch))!])!
		evaluated(factory, [o(argv)], {
			'cwd':    o(source)
			'check':  v(ah.Value(true))
			'stdout': o(log)
			'stderr': o(log)
		})!
}

fn build_environment(factory string, c Publication) !string {
	return evaluated(factory, [o(attribute(constant('os')!, 'environ')!)], {
		'CC':      o(call('shlex.join', o(c.cc))!)
		'AR':      o(c.ar)
		'RANLIB':  o(c.ranlib)
		'CFLAGS':  o(c.cflags)
		'LDFLAGS': o(c.ldflags)
	})!
}

fn run_make(factory string, args string, options map[string]ah.Value) ! {
	evaluated(factory, [o(words(['make', '-j' + text(attribute(args, 'jobs')!)!])!)], options)!
}

fn publish_manifest(factory string, manifest string) ! {
	evaluated(factory, [o(add(invoke('json.dumps', [o(manifest)], {
		'indent': v(ah.Value(2))
	})!, literal(ah.Value('\n'))!)!)], {})!
}

fn exports(readelf string, path string) !string {
	start := callback('checkpoint', {})!
	factory := constant('subprocess.check_output')!
	table := export_table(factory, readelf, path) or {
		cause := err
		release(factory)!
		return cause
	}
	lines := method(table, 'splitlines', [], {})!
	sequence := iterator(lines) or {
		cause := err
		release(lines)!
		return cause
	}
	release(lines)!
	result := collection('set', [])!
	mut cursor := ExportCursor{ checkpoint: callback('checkpoint', {})! }
	export_lines(sequence, result, mut cursor) or {
		cause := err
		release_error([sequence], cause)!
		return cause
	}
	release(sequence)!
	if cursor.line != '' { release(cursor.line)! }
	forget_since(start, [result])!
	return result
}

fn export_table(factory string, readelf string, path string) !string {
	argv := collection('list', [readelf, literal(ah.Value('--dyn-syms'))!,
		literal(ah.Value('--wide'))!, call('str', o(path))!])!
	result := evaluated(factory, [o(argv)], {
		'text': v(ah.Value(true))
	}) or {
		cause := err
		release(argv)!
		return cause
	}
	release(argv)!
	return result
}

fn export_lines(sequence string, result string, mut cursor ExportCursor) ! {
	for {
		phase := callback('checkpoint', {})!
		line := next(sequence)!
		if line.done { return }
		if cursor.line != '' { release(cursor.line)! }
		cursor.line = line.value
		parts := method(line.value, 'split', [], {})!
		forget_since(cursor.checkpoint, [sequence, result, line.value, parts])!
		cursor.checkpoint = phase
		if compare('ge', call('len', o(parts))!, literal(ah.Value(8))!)! && truth(call('operator.contains', o(collection('tuple', [
			literal(ah.Value('GLOBAL'))!,
			literal(ah.Value('WEAK'))!,
		])!), o(item(parts, v(ah.Value(4)))!))!)! && compare('ne', item(parts, v(ah.Value(6)))!, literal(ah.Value('UND'))!)! {
			name := item(method(item(parts, v(ah.Value(7)))!, 'split', [v(ah.Value('@'))], {})!, v(ah.Value(0)))!
			method(result, 'add', [o(name)], {})!
		}
	}
}

struct ExportCursor {
mut:
	checkpoint ah.Value
	line       string
}
