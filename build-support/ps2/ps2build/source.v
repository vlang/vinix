// SPDX-License-Identifier: MIT
module ps2build

import androidhost as ah

fn sha256(path string) !string {
	digest := call('hashlib.sha256')!
	manager := method(path, 'open', [v(ah.Value('rb'))], {})!
	stream := enter(manager)!
	hash_stream(digest, stream) or {
		if !retire(manager, err)! { return err }
		return method(digest, 'hexdigest', [], {})!
	}
	retire(manager, none)!
	return method(digest, 'hexdigest', [], {})!
}

fn hash_stream(digest string, stream string) ! {
	for {
		chunk := method(stream, 'read', [v(ah.Value(1024 * 1024))], {})!
		if !truth(chunk)! { break }
		method(digest, 'update', [o(chunk)], {})!
	}
}

fn fetch(path string) ! {
	url := global('SOURCE_URL')!
	digest := global('SOURCE_SHA256')!
	if !exists(path)! {
		request := invoke('urllib.request.Request', [o(url)], {
			'headers': o(request_headers('User-Agent', 'Vinix-PS2-build')!)
		})!
		// The request headers are fixed data; their dictionary lives in the importing owner table.
		manager := invoke('tempfile.NamedTemporaryFile', [], {
			'dir':    o(attribute(path, 'parent')!)
			'delete': v(ah.Value(false))
		})!
		stream := enter(manager)!
		fetch_stream(path, request, digest, stream) or {
			if !retire(manager, err)! { return err }
			verify_cached(path, digest)!
			return
		}
		retire(manager, none)!
	}
	verify_cached(path, digest)!
}

fn request_headers(key string, value string) !string {
	id := call('builtins.dict')!
	set(id, key, lit(value)!)!
	return id
}

fn fetch_stream(path string, request string, digest string, stream string) ! {
	temporary := call('Path', o(attribute(stream, 'name')!))!
	own(temporary, 'unlink', {
		'missing_ok': v(ah.Value(true))
	}, '')!
	fetch_to(path, request, digest, stream, temporary) or {
		failure := err
		close(temporary, failure)!
		return failure
	}
	close(temporary, none)!
}

fn fetch_to(path string, request string, digest string, stream string, temporary string) ! {
	manager := invoke('urllib.request.urlopen', [o(request)], {
		'timeout': v(ah.Value(120))
	})!
	response := enter(manager)!
	fetch_response(response, stream) or {
		if !retire(manager, err)! { return err }
		verify_download(path, digest, stream, temporary)!
		return
	}
	retire(manager, none)!
	verify_download(path, digest, stream, temporary)!
}

fn fetch_response(response string, stream string) ! {
	mut count := literal(ah.Value(0))!
	for {
		chunk := method(response, 'read', [v(ah.Value(1024 * 1024))], {})!
		if !truth(chunk)! { break }
		count = call('operator.iadd', o(count), o(length(chunk)!))!
		if compare('gt', count, literal(ah.Value(8 * 1024 * 1024))!)! {
			failed('ValueError', 'source download exceeds size limit', none)!
		}
		method(stream, 'write', [o(chunk)], {})!
	}
}

fn verify_download(path string, digest string, stream string, temporary string) ! {
	method(stream, 'flush', [], {})!
	if compare('ne', public('sha256', [temporary], {})!, digest)! {
		failed('ValueError', 'Iris source checksum mismatch', none)!
	}
	method(temporary, 'replace', [o(path)], {})!
}

fn verify_cached(path string, digest string) ! {
	size := attribute(method(path, 'stat', [], {})!, 'st_size')!
	if compare('gt', size, literal(ah.Value(8 * 1024 * 1024))!)! || compare('ne', public('sha256', [path], {})!, digest)! {
		failed('ValueError', 'cached source checksum mismatch: ' + text(path)!, none)!
	}
}

fn unpack(archive string, destination string) ! {
	manager := call('tarfile.open', o(archive), v(ah.Value('r:gz')))!
	stream := enter(manager)!
	unpack_members(stream, destination) or {
		if !retire(manager, err)! { return err }
		return
	}
	retire(manager, none)!
}

fn unpack_members(stream string, destination string) ! {
	members := iterator(stream)!
	for {
		member := next(members)!
		if member.done { break }
		name := attribute(member.value, 'name')!
		path := call('PurePosixPath', o(name))!
		if truth(method(path, 'is_absolute', [], {})!)! || truth(call('operator.contains', o(attribute(path, 'parts')!), v(ah.Value('..')))!)! || truth(call('operator.contains', o(name), v(ah.Value('\\')))!)! {
			failed('ValueError', 'unsafe archive path: ' + text(name)!, none)!
		}
		if truth(method(member.value, 'isdir', [], {})!)! { continue }
		if !truth(method(member.value, 'isfile', [], {})!)! || compare('lt', length(attribute(path, 'parts')!)!, literal(ah.Value(2))!)! || compare('gt', attribute(member.value, 'size')!, literal(ah.Value(16 * 1024 * 1024))!)! {
			failed('ValueError', 'unsupported archive member: ' + text(name)!, none)!
		}
		parts := slice(attribute(path, 'parts')!, literal(ah.Value(1))!, null()!)!
		mut path_args := []ah.Value{}
		iter := iterator(parts)!
		for {
			item := next(iter)!
			if item.done { break }
			path_args << o(item.value)
		}
		target := method(destination, 'joinpath', path_args, {})!
		mkdir(attribute(target, 'parent')!, true)!
		manager := method(stream, 'extractfile', [o(member.value)], {})!
		data := enter(manager)!
		write_member(target, data) or {
			if !retire(manager, err)! { return err }
			set_member_mode(member.value, target)!
			continue
		}
		retire(manager, none)!
		set_member_mode(member.value, target)!
	}
}

fn write_member(target string, data string) ! {
	method(target, 'write_bytes', [o(method(data, 'read', [], {})!)], {})!
}

fn set_member_mode(member string, target string) ! {
	executable := truth(call('operator.and_', o(attribute(member, 'mode')!), v(ah.Value(0o111)))!)!
	method(target, 'chmod', [v(ah.Value(if executable { 0o755 } else { 0o644 }))], {})!
}
