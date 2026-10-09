// SPDX-License-Identifier: GPL-2.0-or-later
module muslstage

import androidhost as ah

fn sha256(path string) !string {
	factory := callback('resolve', {
		'name': ah.Value('hashlib.sha256')
	})!.text()
	data := method(path, 'read_bytes', [], {}) or {
		cause := err
		release_error([factory], cause)!
		return cause
	}
	digest := callback('function', {
		'target': ah.Value(factory)
		'call':   ah.Value(true)
		'args':   ah.Value([o(data)])
	}) or {
		cause := err
		release_error([data, factory], cause)!
		return cause
	}
	release(data, factory)!
	result := method(digest.text(), 'hexdigest', [], {}) or {
		cause := err
		release_error([digest.text()], cause)!
		return cause
	}
	release(digest.text())!
	return result
}

fn pair(id string) ![]string {
	return callback('unpack_pair', {
		'owner': ah.Value(id)
	})!.items().map(it.text())
}

fn cleanup_temporary(temporary string, cause ?IError) ! {
	if error := cause {
		callback('active_error', {
			'error': detail(error)
		})!
	}
	invoke_unlink(temporary)!
	callback('active_error', {
		'error': none_value()
	})!
}

fn invoke_unlink(temporary string) ! {
	method(call('Path', o(temporary))!, 'unlink', [], {
		'missing_ok': v(ah.Value(true))
	})!
}

fn install(source string, target string, mode string) ! {
	method(attribute(target, 'parent')!, 'mkdir', [], {
		'parents':  v(ah.Value(true))
		'exist_ok': v(ah.Value(true))
	})!
	if truth(method(target, 'is_file', [], {})!)! && !truth(method(target, 'is_symlink', [], {})!)! && compare('eq', call('sha256', o(target))!, call('sha256', o(source))!)! {
		bits := call('operator.and_', o(attribute(method(target, 'stat', [], {})!, 'st_mode')!), v(ah.Value(0o777)))!
		if compare('eq', bits, mode)! { return }
	}
	prefix := add(add(literal(ah.Value('.'))!, attribute(target, 'name')!)!, literal(ah.Value('.'))!)!
	values := pair(invoke('tempfile.mkstemp', [], {
		'prefix': o(prefix)
		'dir':    o(attribute(target, 'parent')!)
	})!)!
	install_body(values[0], values[1], source, target, mode) or {
		cause := err
		cleanup_temporary(values[1], cause)!
		return cause
	}
	cleanup_temporary(values[1], none)!
}

fn install_body(fd string, temporary string, source string, target string, mode string) ! {
	manager := call('os.fdopen', o(fd), v(ah.Value('wb')))!
	output := enter(manager)!
	write_bytes(output, source) or {
		cause := err
		if !retire(manager, cause)! { return cause }
		finish_install(temporary, target, mode)!
		return
	}
	retire(manager, none)!
	finish_install(temporary, target, mode)!
}

fn write_bytes(output string, source string) ! {
	data := method(source, 'read_bytes', [], {})!
	method(output, 'write', [o(data)], {}) or {
		cause := err
		release_error([data], cause)!
		return cause
	}
	release(data)!
}

fn finish_install(temporary string, target string, mode string) ! {
	call('os.chmod', o(temporary), o(mode))!
	call('os.replace', o(temporary), o(target))!
}

fn replace_link(target string, destination string) ! {
	method(attribute(target, 'parent')!, 'mkdir', [], {
		'parents':  v(ah.Value(true))
		'exist_ok': v(ah.Value(true))
	})!
	if truth(method(target, 'is_symlink', [], {})!)! && compare('eq', call('os.readlink', o(target))!, destination)! {
		return
	}
	prefix := add(add(literal(ah.Value('.'))!, attribute(target, 'name')!)!, literal(ah.Value('.'))!)!
	values := pair(invoke('tempfile.mkstemp', [], {
		'prefix': o(prefix)
		'dir':    o(attribute(target, 'parent')!)
	})!)!
	call('os.close', o(values[0]))!
	call('os.unlink', o(values[1]))!
	replace_link_body(target, destination, values[1]) or {
		cause := err
		cleanup_temporary(values[1], cause)!
		return cause
	}
	cleanup_temporary(values[1], none)!
}

fn replace_link_body(target string, destination string, temporary string) ! {
	call('os.symlink', o(destination), o(temporary))!
	call('os.replace', o(temporary), o(target))!
}
