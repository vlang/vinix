module debiancore

import androidhost as ah
import runtimebuild as rb

fn file_sha256(path ah.Value) !ah.Value {
	digest := rb.call('acquire', 'hashlib', 'sha256', [], {})!
	input := rb.method('enter', path, 'open', [rb.ordinary(ah.Value('rb'))], {})!
	mut failed := false
	mut cause := IError(none)
	hash_body(input, digest) or {
		failed = true
		cause = err
	}
	suppressed := exit(input, failed, cause)!
	if failed && !suppressed { return cause }
	return rb.method('acquire', digest, 'hexdigest', [], {})!
}

fn hash_body(input ah.Value, digest ah.Value) ! {
	empty := bytes_hex('')!
	for {
		chunk := rb.method('acquire', input, 'read', [rb.ordinary(ah.Value(1 << 20))], {})!
		if rb.eq(chunk, empty)! { break }
		rb.method('invoke', digest, 'update', [rb.object(chunk)], {})!
	}
}

fn sha(path ah.Value) !ah.Value {
	if native('file_sha256')! { return file_sha256(path)! }
	return rb.api('file_sha256', [rb.object(path)], {}, true)!
}

fn download(mirror ah.Value, package ah.Value, cache ah.Value) !ah.Value {
	filename := rb.attribute(package, 'filename', true)!
	path := rb.api('Path', [rb.object(filename)], {}, true)!
	target := join(cache, rb.attribute(path, 'name', true)!)!
	if test(target, 'is_file')! {
		hash := rb.attribute(package, 'sha256', true)!
		if !rb.bool_object(hash)! || rb.eq(sha(target)!, rb.attribute(package, 'sha256', true)!)! {
			return target
		}
	}
	url := rb.format_object(rb.method('acquire', mirror, 'rstrip', [rb.ordinary(ah.Value('/'))], {})!)! + '/' + rb.format_object(rb.attribute(package, 'filename', true)!)!
	emit('  downloading ' + rb.format_object(rb.attribute(package, 'architecture', true)!)! + '/' + rb.format_object(rb.attribute(target, 'name', true)!)!, true)!
	partial := rb.method('acquire', target, 'with_name', [rb.ordinary(ah.Value(rb.format_object(rb.attribute(target, 'name', true)!)! + '.partial'))], {})!
	mut arguments := ['curl', '--fail', '--location', '--retry', '3', '--retry-all-errors',
		'--connect-timeout', '15', '--speed-limit', '1024', '--speed-time', '30', '--continue-at',
		'-', '--silent', '--show-error', '--output',
		rb.call('invoke', 'builtins', 'str', [rb.object(partial)], {})!.text(), url]
	rb.call('invoke', 'subprocess', 'run', [rb.ordinary(rb.strings(arguments))], {
		'check': ah.Value(true)
	})!
	if rb.bool_object(rb.attribute(package, 'sha256', true)!)! && !rb.eq(sha(partial)!, rb.attribute(package, 'sha256', true)!)! {
		rb.method('invoke', partial, 'unlink', [], {})!
		return failure('checksum mismatch downloading ' + url)
	}
	rb.method('invoke', partial, 'replace', [rb.object(target)], {})!
	return target
}
