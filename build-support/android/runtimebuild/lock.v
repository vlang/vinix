module runtimebuild

import androidhost as ah
import boothost

fn unpack_count(values []ah.Value, size int) ! {
	if values.len < size {
		return boothost.PolicyError{'ValueError', 'not enough values to unpack (expected ${size}, got ${values.len})'}
	}
	if values.len > size {
		return boothost.PolicyError{'ValueError', 'too many values to unpack (expected ${size})'}
	}
}

fn index_contents(source ah.Value, archive ah.Value, index ah.Value) ! {
	member := method('acquire', source, 'extractfile', [ordinary(ah.Value('APKINDEX'))], {})!
	if is_none(member)! { return fail('APKINDEX missing from ' + str(archive)!) }
	payload := method('acquire', member, 'read', [], {})!
	method('invoke', index, 'write_bytes', [object(payload)], {})!
}

fn (e Engine) make_lock(downloads ah.Value, mirror ah.Value) !ah.Value {
	mut indexes := []ah.Value{}
	mirror_text := format_object(mirror)!
	architecture := e.c('ARCHITECTURE').text()
	for item in e.c('REPOSITORIES').items() {
		repository := item.text()
		archive := join(downloads, repository + '_APKINDEX.tar.gz')!
		unlink(archive, true)!
		digest := api('download', [
			ordinary(ah.Value(mirror_text + '/' + repository + '/' + architecture + '/APKINDEX.tar.gz')),
			object(archive),
		], {}, true)!
		index := join(downloads, repository + '_APKINDEX')!
		source := call('enter', 'tarfile', 'open', [object(archive)], {})!
		mut failed := false
		mut cause := IError(none)
		index_contents(source, archive, index) or {
			failed = true
			cause = err
		}
		suppressed := exit_context(source, failed, cause)!
		if failed && !suppressed { return cause }
		indexes << dictionary([ordinary(ah.Value('repository')), ordinary(ah.Value('sha256'))], [
			ordinary(item),
			object(digest),
		])!
	}
	mut command := [ordinary(ah.Value('python3')),
		ordinary(ah.Value(str(e.root_path('build-support/alpine-resolve.py')!)!))]
	for item in e.c('REPOSITORIES').items() {
		command << ordinary(ah.Value('--index'))
		command << ordinary(item)
		command << ordinary(ah.Value(str(join(downloads, item.text() + '_APKINDEX')!)!))
	}
	for item in e.c('ROOT_PACKAGES').items() { command << ordinary(item) }
	output := call('acquire', 'subprocess', 'check_output', [object(make_sequence(command)!)], {
		'text': ah.Value(true)
	})!
	lines := method('acquire', output, 'splitlines', [], {})!
	iter := iter_object(lines)!
	mut records := []ah.Value{}
	for {
		line := next(iter)!
		if line == null() { break }
		fields := method('invoke', line, 'split', [ordinary(ah.Value('\t'))], {})!.items()
		unpack_count(fields, 2)!
		repository := fields[0].text()
		filename := fields[1].text()
		// Preserve the original unconditional four-character suffix removal.
		filename_object := callback('retain', {
			'value': ordinary(ah.Value(filename))
		})!
		suffix := call('acquire', 'builtins', 'slice', [ordinary(null()), ordinary(ah.Value(-4))], {})!
		stem := method('acquire', filename_object, '__getitem__', [object(suffix)], {})!
		parts := method('invoke', stem, 'rsplit', [ordinary(ah.Value('-')), ordinary(ah.Value(2))], {})!.items().map(it.text())
		unpack_count(parts.map(ah.Value(it)), 3)!
		records << dictionary(['repository', 'filename', 'name', 'version'].map(ordinary(ah.Value(it))),
			[ordinary(ah.Value(repository)), ordinary(ah.Value(filename)),
				ordinary(ah.Value(parts[0])), ordinary(ah.Value(parts[1] + '-' + parts[2]))])!
	}
	fetched := pool_map('fetch_lock', make_sequence(records.map(object(it)))!, {
		'downloads': object(downloads)
		'mirror':    object(mirror)
	})!
	return dictionary(['format', 'architecture', 'mirror', 'root_packages', 'indexes', 'packages'].map(ordinary(ah.Value(it))),
		[ordinary(ah.Value(1)), ordinary(e.c('ARCHITECTURE')), object(mirror),
			ordinary(e.c('ROOT_PACKAGES')), object(make_sequence(indexes.map(object(it)))!),
			object(fetched)])!
}

fn (e Engine) fetch_lock(record ah.Value, downloads ah.Value, mirror ah.Value) !ah.Value {
	filename := get(record, 'filename')!
	url := format_object(mirror)! + '/' + format_object(get(record, 'repository')!)! + '/' + e.c('ARCHITECTURE').text() + '/' + str(filename)!
	digest := api('download', [ordinary(ah.Value(url)), object(join_object(downloads, filename)!)], {}, true)!
	put(record, 'sha256', object(digest))!
	return record
}

fn fetch_package(record ah.Value, downloads ah.Value, package_lock ah.Value) !ah.Value {
	filename := get(record, 'filename')!
	archive := join_object(downloads, filename)!
	url := format_object(get(package_lock, 'mirror')!)! + '/' + format_object(get(record, 'repository')!)! + '/' + format_object(get(package_lock, 'architecture')!)! + '/' + format_object(filename)!
	api('download', [ordinary(ah.Value(url)), object(archive), object(get(record, 'sha256')!)], {}, false)!
	return archive
}
