module runtimebuild

import androidhost as ah

fn digest_blocks(hash ah.Value, owner ah.Value) ! {
	for {
		block := method('acquire', owner, 'read', [ordinary(ah.Value(1024 * 1024))], {})!
		if bool_object(call('acquire', 'operator', 'eq', [object(block), bytes('')], {})!)! {
			break
		}
		method('invoke', hash, 'update', [object(block)], {})!
	}
}

fn digest(path ah.Value) !string {
	hash := call('acquire', 'hashlib', 'sha256', [], {})!
	owner := method('enter', path, 'open', [ordinary(ah.Value('rb'))], {})!
	mut failed := false
	mut cause := IError(none)
	digest_blocks(hash, owner) or {
		failed = true
		cause = err
	}
	suppressed := exit_context(owner, failed, cause)!
	if failed && !suppressed { return cause }
	return method('invoke', hash, 'hexdigest', [], {})!.text()
}

fn expected_is_none(expected ah.Value) !bool {
	return truth(callback('is_none', {
		'id': expected
	})!)
}

fn expected_matches(actual ah.Value, expected ah.Value) !bool {
	matched := call('acquire', 'operator', 'eq', [object(actual), object(expected)], {})!
	return truth(call('invoke', 'builtins', 'bool', [object(matched)], {})!)
}

fn expected_differs(actual ah.Value, expected ah.Value) !bool {
	matched := call('acquire', 'operator', 'ne', [object(actual), object(expected)], {})!
	return bool_object(matched)!
}

fn download(url ah.Value, target ah.Value, expected ah.Value) !ah.Value {
	if test(target, 'exists')! {
		actual := api('sha256', [object(target)], {}, true)!
		if expected_is_none(expected)! || expected_matches(actual, expected)! { return actual }
		return fail('cached download checksum mismatch: ' + format_object(target)!)
	}
	callback('print', {
		'data':    ah.Value('  downloading ' + format_object(attribute(target, 'name', true)!)!)
		'options': ah.Value({
			'flush': ah.Value(true)
		})
	})!
	suffix := call('acquire', 'operator', 'add', [
		object(attribute(target, 'suffix', true)!),
		ordinary(ah.Value('.part')),
	], {})!
	temporary := method('acquire', target, 'with_suffix', [object(suffix)], {})!
	mut failed := false
	mut cause := IError(none)
	mut actual := null()
	actual = download_body(url, target, temporary, expected) or {
		failed = true
		cause = err
		null()
	}
	unlink(temporary, true)!
	if failed { return cause }
	return actual
}

fn download_body(url ah.Value, target ah.Value, temporary ah.Value, expected ah.Value) !ah.Value {
	mut arguments := ['curl', '--fail', '--location', '--silent', '--show-error', '--retry', '3',
		'--output', str(temporary)!].map(ordinary(ah.Value(it)))
	arguments << object(url)
	command := callback('sequence', {
		'arguments': ah.Value(arguments)
	})!
	call('invoke', 'subprocess', 'run', [object(command)], {
		'check': ah.Value(true)
	})!
	actual := api('sha256', [object(temporary)], {}, true)!
	if !expected_is_none(expected)! && expected_differs(actual, expected)! {
		return fail('download checksum mismatch: ' + format_object(url)!)
	}
	method('invoke', temporary, 'replace', [object(target)], {})!
	return actual
}

fn (e Engine) calculator(downloads ah.Value) !ah.Value {
	metadata := e.c('CALCULATOR').object()
	apk := join(downloads, text(metadata, 'filename'))!
	if test(apk, 'exists')! {
		if api('sha256', [object(apk)], {}, false)!.text() != text(metadata, 'sha256') {
			return fail('calculator APK checksum mismatch: ' + str(apk)!)
		}
		return apk
	}
	archive := join(downloads, 'arity-calculator-source-archive.zip')!
	api('download', [ordinary(ah.field(metadata, 'url')), object(archive),
		ordinary(ah.field(metadata, 'archive_sha256'))], {}, false)!
	owner := call('enter', 'zipfile', 'ZipFile', [object(archive)], {})!
	mut payload := null()
	mut failed := false
	mut cause := IError(none)
	mut seen := false
	payload = method('acquire', owner, 'read', [ordinary(ah.field(metadata, 'archive_member'))], {}) or {
		failed = true
		cause = err
		null()
	}
	seen = !failed
	suppressed := exit_context(owner, failed, cause)!
	if failed && !suppressed { return cause }
	if !seen { unbound('payload')! }
	hash := call('acquire', 'hashlib', 'sha256', [object(payload)], {})!
	if method('invoke', hash, 'hexdigest', [], {})!.text() != text(metadata, 'sha256') {
		return fail('calculator APK checksum mismatch in official source archive')
	}
	method('invoke', apk, 'write_bytes', [object(payload)], {})!
	return apk
}

fn (e Engine) relocate(runtime ah.Value) ! {
	directory := join(runtime, 'etc/fonts')!
	sequence := method('acquire', directory, 'rglob', [ordinary(ah.Value('*.conf'))], {})!
	iterator := call('acquire', 'builtins', 'iter', [object(sequence)], {})!
	for {
		config := next(iterator)!
		if config == null() { break }
		if test(config, 'is_symlink')! { continue }
		mut contents := method('acquire', config, 'read_text', [], {})!
		for name in ['/usr/share/fonts', '/usr/local/share/fonts', '/etc/fonts'] {
			contents = method('acquire', contents, 'replace', [
				ordinary(ah.Value(name)),
				ordinary(ah.Value(e.c('PREFIX').text() + name)),
			], {})!
		}
		method('invoke', config, 'write_text', [object(contents)], {})!
	}
}

fn materialize(runtime ah.Value) ! {
	for name in ['lib', 'usr/lib'] {
		directory := join(runtime, name)!
		sequence := method('acquire', directory, 'rglob', [ordinary(ah.Value('*'))], {})!
		sorted := call('acquire', 'builtins', 'sorted', [object(sequence)], {})!
		iterator := call('acquire', 'builtins', 'iter', [object(sorted)], {})!
		for {
			link := next(iterator)!
			if link == null() { break }
			if !test(link, 'is_symlink')! { continue }
			filename := attribute(link, 'name', false)!.text()
			if !filename.contains('.so') && !filename.starts_with('ld-musl-') { continue }
			source := method('acquire', link, 'resolve', [], {
				'strict': ah.Value(true)
			})!
			if !truth(method('invoke', source, 'is_relative_to', [object(runtime)], {})!) {
				return fail('runtime library symlink escapes prefix: ' + str(link)!)
			}
			unlink(link, false)!
			call('invoke', 'os', 'link', [object(source), object(link)], {})!
		}
	}
}
