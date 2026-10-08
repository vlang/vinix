// SPDX-License-Identifier: GPL-2.0-or-later
module packagestore

import androidhost as ah

struct Count {
mut:
	value int
}

struct Upload {
mut:
	path string
}

fn validate(path string, maximum string) ! {
	count := validate_archive(path, maximum) or {
		if kind(err, 'tar_error') || kind(err, 'os_error') {
			failed('OverlayError', 'invalid tar archive: ' + err.msg(), err)!
		}
		return err
	}
	if count == 0 { failed('OverlayError', 'empty archive', none)! }
}

fn validate_archive(path string, maximum string) !int {
	archive := invoke('tarfile.open', [o(path), v(ah.Value('r:'))], {})!
	entered := enter(archive)!
	mut count := Count{}
	archive_members(entered, maximum, mut count) or {
		failure := err
		if retire(archive, failure)! { return count.value }
		return failure
	}
	retire(archive, none)!
	return count.value
}

fn validate_name(name string, message string) ! {
	posix := call('PurePosixPath', o(name))!
	parts := attribute(posix, 'parts')!
	if !truth(name)! || truth(method(name, 'startswith', [v(ah.Value('/'))], {})!)! || truth(call('operator.contains', o(parts), v(ah.Value('..')))!)! {
		failed('OverlayError', message, none)!
	}
}

fn archive_members(archive string, maximum string, mut count Count) ! {
	mut total := literal(ah.Value(0))!
	members := iterator(archive)!
	for {
		row := next(members)!
		if row.done { break }
		member := row.value
		count.value++
		if count.value > 300_000 { failed('OverlayError', 'too many archive members', none)! }
		name := method(attribute(member, 'name')!, 'removeprefix', [v(ah.Value('./'))], {})!
		validate_name(name, 'unsafe archive path')!
		if !truth(method(member, 'isfile', [], {})!)! && !truth(method(member, 'isdir', [], {})!)! && !truth(method(member, 'issym', [], {})!)! && !truth(method(member, 'islnk', [], {})!)! {
			failed('OverlayError', 'unsupported archive member', none)!
		}
		if truth(method(member, 'islnk', [], {})!)! {
			target := method(attribute(member, 'linkname')!, 'removeprefix', [v(ah.Value('./'))], {})!
			validate_name(target, 'unsafe hard-link target')!
		}
		total = call('operator.add', o(total), o(attribute(member, 'size')!))!
		if compare('gt', total, maximum)! {
			failed('OverlayError', 'expanded overlay is too large', none)!
		}
	}
}

fn server_field(receiver string, name string) !string {
	return attribute(attribute(receiver, 'server')!, name)!
}

fn receiver_call(receiver string, name string, args []ah.Value) ! {
	method(receiver, name, args, {})!
}

fn header(receiver string, name string, value string) ! {
	receiver_call(receiver, 'send_header', [v(ah.Value(name)), o(value)])!
}

fn text_header(receiver string, name string, value string) ! {
	receiver_call(receiver, 'send_header', [v(ah.Value(name)), v(ah.Value(value))])!
}

fn status(receiver string, code int) ! {
	receiver_call(receiver, 'send_response', [v(ah.Value(code))])!
}

fn send_error(receiver string, code int, message ?string) ! {
	mut args := [v(ah.Value(code))]
	if value := message { args << v(ah.Value(value)) }
	receiver_call(receiver, 'send_error', args)!
}

fn headers_done(receiver string) ! { receiver_call(receiver, 'end_headers', [])! }

fn length_text(value string) !string {
	return call('builtins.str', o(call('builtins.len', o(value))!))!
}

fn get(receiver string) ! {
	pathname := attribute(receiver, 'path')!
	if compare('eq', pathname, literal(ah.Value('/clipboard'))!)! && truth(server_field(receiver, 'clipboard')!)! {
		clipboard := call('read_clipboard') or {
			if kind(err, 'clipboard') {
				activate(err)!
				send_error(receiver, 503, err.msg())!
				return
			}
			return err
		}
		status(receiver, 200)!
		text_header(receiver, 'Content-Type', 'text/plain; charset=utf-8')!
		header(receiver, 'Content-Length', length_text(clipboard)!)!
		text_header(receiver, 'Cache-Control', 'no-store')!
		headers_done(receiver)!
		method(attribute(receiver, 'wfile')!, 'write', [o(clipboard)], {})!
		return
	}
	if compare('eq', pathname, literal(ah.Value('/health'))!)! {
		status(receiver, 204)!
		headers_done(receiver)!
		return
	}
	parts := method(method(pathname, 'lstrip', [v(ah.Value('/'))], {})!, 'partition', [v(ah.Value('/'))], {})!
	app := call('operator.getitem', o(parts), v(ah.Value(0)))!
	name := call('operator.getitem', o(parts), v(ah.Value(2)))!
	live := call('LIVE_APPS')!
	if truth(call('operator.contains', o(live), o(app))!)! && (compare('eq', name, literal(ah.Value('version'))!)! || compare('eq', name, literal(ah.Value('binary'))!)!)! && !compare('is_', server_field(receiver, 'source_root')!, null()!)! {
		method(receiver, 'send_app_build', [o(app), o(name)], {})!
		return
	}
	if compare('eq', pathname, literal(ah.Value('/vinix-source.tar'))!)! && !compare('is_', server_field(receiver, 'source_root')!, null()!)! {
		method(receiver, 'send_source_snapshot', [], {})!
		return
	}
	send_error(receiver, 404, none)!
}

fn send_app(receiver string, app string, name string) ! {
	path := call('operator.truediv', o(server_field(receiver, 'source_root')!), o(call('operator.getitem', o(call('LIVE_APPS')!), o(app))!))!
	filename := if compare('eq', name, literal(ah.Value('version'))!)! {
		literal(ah.Value('version'))!
	} else {
		app
	}
	selected := call('operator.truediv', o(path), o(filename))!
	app_stream(receiver, selected) or {
		if kind(err, 'missing') {
			activate(err)!
			send_error(receiver, 404, none)!
			return
		}
		return err
	}
}

fn app_stream(receiver string, path string) ! {
	manager := method(path, 'open', [v(ah.Value('rb'))], {})!
	entered := enter(manager)!
	app_body(receiver, path, entered) or {
		failure := err
		if retire(manager, failure)! { return }
		return failure
	}
	retire(manager, none)!
}

fn app_body(receiver string, path string, source string) ! {
	size := attribute(method(path, 'stat', [], {})!, 'st_size')!
	status(receiver, 200)!
	text_header(receiver, 'Content-Type', 'application/octet-stream')!
	header(receiver, 'Content-Length', call('builtins.str', o(size))!)!
	text_header(receiver, 'Cache-Control', 'no-store')!
	headers_done(receiver)!
	call('shutil.copyfileobj', o(source), o(attribute(receiver, 'wfile')!))!
}

fn send_snapshot(receiver string) ! {
	snapshot := call('build_source_snapshot', o(server_field(receiver, 'source_root')!), o(server_field(receiver, 'source_extras')!), o(server_field(receiver, 'ui2_source')!)) or {
		if kind(err, 'source') {
			activate(err)!
			send_error(receiver, 503, err.msg())!
			return
		}
		return err
	}
	own(snapshot, 'close')!
	snapshot_body(receiver, snapshot) or {
		failure := err
		close(snapshot, failure)!
		return failure
	}
	close(snapshot, none)!
}

fn snapshot_body(receiver string, snapshot string) ! {
	status(receiver, 200)!
	text_header(receiver, 'Content-Type', 'application/x-tar')!
	size := method(snapshot, 'seek', [v(ah.Value(0)), o(call('os.SEEK_END')!)], {})!
	header(receiver, 'Content-Length', call('builtins.str', o(size))!)!
	text_header(receiver, 'Cache-Control', 'no-store')!
	headers_done(receiver)!
	method(snapshot, 'seek', [v(ah.Value(0))], {})!
	for {
		chunk := method(snapshot, 'read', [v(ah.Value(1024 * 1024))], {})!
		if !truth(chunk)! { break }
		method(attribute(receiver, 'wfile')!, 'write', [o(chunk)], {})!
	}
}

fn save(receiver string) ! {
	if !compare('eq', attribute(receiver, 'path')!, literal(ah.Value('/packages'))!)! {
		send_error(receiver, 404, none)!
		return
	}
	mut length := call('builtins.int', o(method(attribute(receiver, 'headers')!, 'get', [
		v(ah.Value('Content-Length')),
		v(ah.Value('')),
	], {})!)) or { if kind(err, 'value_error') { literal(ah.Value(-1))! } else { return err } }
	maximum := server_field(receiver, 'maximum_overlay')!
	if compare('le', length, literal(ah.Value(0))!)! || compare('gt', length, maximum)! {
		send_error(receiver, 413, 'invalid overlay size')!
		return
	}
	destination := server_field(receiver, 'destination')!
	parent := attribute(destination, 'parent')!
	method(parent, 'mkdir', [], {
		'parents':  v(ah.Value(true))
		'exist_ok': v(ah.Value(true))
	})!
	mut temporary := Upload{ path: null()! }
	save_body(receiver, destination, parent, length, maximum, mut temporary) or {
		if kind(err, 'os_error') || kind(err, 'overlay') {
			activate(err)!
			if !compare('is_', temporary.path, null()!)! {
				method(temporary.path, 'unlink', [], {
					'missing_ok': v(ah.Value(true))
				})!
			}
			send_error(receiver, 400, err.msg())!
			return
		}
		return err
	}
	log('qemu-package-store: saved ' + text(length)! + ' bytes to ' + text(destination)!)!
	status(receiver, 204)!
	headers_done(receiver)!
}

fn save_body(receiver string, destination string, parent string, length string, maximum string, mut temporary Upload) ! {
	manager := invoke('tempfile.NamedTemporaryFile', [], {
		'prefix': v(ah.Value('.' + text(attribute(destination, 'name')!)! + '.'))
		'dir':    o(parent)
		'delete': v(ah.Value(false))
	})!
	output := enter(manager)!
	mut retired := false
	upload_context(receiver, output, length, mut temporary) or {
		failure := err
		retired = true
		if !retire(manager, failure)! { return failure }
	}
	if !retired { retire(manager, none)! }
	call('validate_overlay', o(temporary.path), o(maximum))!
	call('os.replace', o(temporary.path), o(destination))!
	temporary.path = null()!
	directory := call('os.open', o(parent), o(call('os.O_RDONLY')!))!
	own_function(directory, 'os.close')!
	call('os.fsync', o(directory)) or {
		failure := err
		close(directory, failure)!
		return failure
	}
	close(directory, none)!
}

fn upload_context(receiver string, output string, length string, mut temporary Upload) ! {
	temporary.path = call('Path', o(attribute(output, 'name')!))!
	upload_body(receiver, output, length)!
}

fn upload_body(receiver string, output string, length string) ! {
	mut remaining := length
	for truth(remaining)! {
		amount := call('builtins.min', o(remaining), v(ah.Value(1024 * 1024)))!
		chunk := method(attribute(receiver, 'rfile')!, 'read', [o(amount)], {})!
		if !truth(chunk)! { failed('OverlayError', 'short request body', none)! }
		method(output, 'write', [o(chunk)], {})!
		remaining = call('operator.sub', o(remaining), o(call('builtins.len', o(chunk))!))!
	}
	method(output, 'flush', [], {})!
	call('os.fsync', o(method(output, 'fileno', [], {})!))!
}
