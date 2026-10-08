module debiancore

import androidhost as ah
import runtimebuild as rb

struct Member {
	done    bool
	name    ah.Value
	payload ah.Value
	offset  ah.Value
}

fn ar_next(data ah.Value, offset ah.Value, initial bool) !Member {
	if initial && !rb.bool_object(rb.method('acquire', data, 'startswith', [rb.object(bytes_hex('213c617263683e0a')!)], {})!)! {
		return failure('not an ar archive')
	}
	start := add(offset, retain(ah.Value(60))!)!
	length := rb.call('acquire', 'builtins', 'len', [rb.object(data)], {})!
	if !rb.bool_object(rb.call('acquire', 'operator', 'le', [rb.object(start), rb.object(length)], {})!)! {
		return Member{ done: true }
	}
	header := slice_objects(data, offset, start)!
	name := rb.method('acquire', rb.method('acquire', rb.method('acquire', slice(header, 0, 16)!, 'decode', [rb.ordinary(ah.Value('ascii'))], {})!, 'strip', [], {})!, 'rstrip', [rb.ordinary(ah.Value('/'))], {})!
	raw := rb.method('acquire', rb.method('acquire', slice(header, 48, 58)!, 'decode', [rb.ordinary(ah.Value('ascii'))], {})!, 'strip', [], {})!
	size := rb.call('acquire', 'builtins', 'int', [rb.object(raw)], {})!
	end := add(start, size)!
	odd := rb.call('acquire', 'operator', 'and_', [rb.object(size), rb.ordinary(ah.Value(1))], {})!
	return Member{false, name, slice_objects(data, start, end)!, add(end, odd)!}
}

fn copy_output(stream ah.Value, destination ah.Value) ! {
	output := rb.method('enter', destination, 'open', [rb.ordinary(ah.Value('wb'))], {})!
	mut failed := false
	mut cause := IError(none)
	copy_chunks(stream, output) or {
		failed = true
		cause = err
	}
	suppressed := exit(output, failed, cause)!
	if failed && !suppressed { return cause }
}

fn copy_chunks(stream ah.Value, output ah.Value) ! {
	for {
		chunk := rb.method('acquire', stream, 'read', [rb.ordinary(ah.Value(1 << 20))], {})!
		if !rb.bool_object(chunk)! { break }
		rb.method('invoke', output, 'write', [rb.object(chunk)], {})!
	}
}

fn mode(value ah.Value) !ah.Value {
	return rb.call('acquire', 'operator', 'and_', [rb.object(value), rb.ordinary(ah.Value(0o7777))], {})!
}

fn extract_body(archive ah.Value, deb ah.Value, root ah.Value) ! {
	iter := rb.iter_object(rb.method('acquire', archive, 'getmembers', [], {})!)!
	for {
		member := rb.next(iter)!
		if member == rb.null() { break }
		relative := rb.call('acquire', 'os.path', 'normpath', [rb.object(rb.attribute(member, 'name', true)!)], {})!
		if rb.bool_object(rb.method('acquire', relative, 'startswith', [rb.ordinary(ah.Value('..'))], {})!)! || rb.bool_object(rb.call('acquire', 'os.path', 'isabs', [rb.object(relative)], {})!)! {
			return failure(rb.format_object(rb.attribute(deb, 'name', true)!)! + ': refusing to unpack ' + rb.format_object(rb.attribute(member, 'name', true)!)!)
		}
		destination := join(root, relative)!
		if test(member, 'isdir')! {
			rb.method('invoke', destination, 'mkdir', [], {
				'parents':  ah.Value(true)
				'exist_ok': ah.Value(true)
			})!
			continue
		}
		rb.method('invoke', rb.attribute(destination, 'parent', true)!, 'mkdir', [], {
			'parents':  ah.Value(true)
			'exist_ok': ah.Value(true)
		})!
		if test(destination, 'is_symlink')! || test(destination, 'exists')! {
			rb.method('invoke', destination, 'unlink', [], {})!
		}
		if test(member, 'issym')! {
			rb.method('invoke', destination, 'symlink_to', [rb.object(rb.attribute(member, 'linkname', true)!)], {})!
		} else if test(member, 'islnk')! {
			source := join(root, rb.call('acquire', 'os.path', 'normpath', [rb.object(rb.attribute(member, 'linkname', true)!)], {})!)!
			rb.method('invoke', destination, 'write_bytes', [rb.object(rb.method('acquire', source, 'read_bytes', [], {})!)], {})!
			rb.method('invoke', destination, 'chmod', [rb.object(mode(rb.attribute(rb.method('acquire', source, 'stat', [], {})!, 'st_mode', true)!)!)], {})!
		} else if test(member, 'isfile')! {
			stream := rb.method('acquire', archive, 'extractfile', [rb.object(member)], {})!
			if is_none(stream)! {
				rb.callback('raise', {
					'kind': ah.Value('AssertionError')
				})!
			}
			copy_output(stream, destination)!
			rb.method('invoke', destination, 'chmod', [rb.object(mode(rb.attribute(member, 'mode', true)!)!)], {})!
		}
	}
}

fn extract_payload(payload ah.Value, deb ah.Value, root ah.Value) ! {
	buffer := rb.call('acquire', 'io', 'BytesIO', [rb.object(payload)], {})!
	archive := rb.callback('enter', {
		'module':          ah.Value('tarfile')
		'name':            ah.Value('open')
		'options':         ah.Value({
			'mode': ah.Value('r:*')
		})
		'keyword_objects': ah.Value({
			'fileobj': buffer
		})
	})!
	mut failed := false
	mut cause := IError(none)
	extract_body(archive, deb, root) or {
		failed = true
		cause = err
	}
	suppressed := exit(archive, failed, cause)!
	if failed && !suppressed { return cause }
}

fn extract_deb(deb ah.Value, root ah.Value) !ah.Value {
	data := rb.method('acquire', deb, 'read_bytes', [], {})!
	if native('ar_members')! {
		mut offset := retain(ah.Value(8))!
		mut initial := true
		for {
			member := ar_next(data, offset, initial)!
			initial = false
			if member.done { break }
			offset = member.offset
			if rb.bool_object(rb.method('acquire', member.name, 'startswith', [rb.ordinary(ah.Value('data.tar'))], {})!)! {
				extract_payload(member.payload, deb, root)!
				return rb.null()
			}
		}
	} else {
		iter := rb.iter_object(rb.api('ar_members', [rb.object(data)], {}, true)!)!
		for {
			pair := rb.next(iter)!
			if pair == rb.null() { break }
			values := rb.callback('unpack_pair', {
				'id': pair
			})!.items()
			if rb.bool_object(rb.method('acquire', values[0], 'startswith', [rb.ordinary(ah.Value('data.tar'))], {})!)! {
				extract_payload(values[1], deb, root)!
				return rb.null()
			}
		}
	}
	return failure(rb.format_object(rb.attribute(deb, 'name', true)!)! + ': no data archive')
}
