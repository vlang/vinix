module dhewmcore

import androidhost as ah
import boothost
import runtimebuild as rb

fn o(value ah.Value) ah.Value { return rb.object(value) }

fn v(value string) ah.Value { return rb.ordinary(ah.Value(value)) }

fn global(name string) !ah.Value {
	return rb.callback('borrow_global', {
		'name': ah.Value(name)
	})!
}

fn text(value ah.Value) !string { return rb.format_object(value)! }

fn py_str(value ah.Value) !string {
	return rb.call('invoke', 'builtins', 'str', [o(value)], {})!.text()
}

fn literal(value string) !ah.Value {
	return rb.callback('retain', {
		'value': v(value)
	})!
}

fn join(base ah.Value, name string) !ah.Value {
	return rb.method('acquire', base, '__truediv__', [v(name)], {})!
}

fn test(value ah.Value, method string) !bool {
	return rb.bool_object(rb.method('acquire', value, method, [], {})!)!
}

fn method(value ah.Value, name string, arguments []ah.Value) !ah.Value {
	return rb.method('acquire', value, name, arguments, {})!
}

fn run(argv []string, quiet bool) ! {
	mut row := {
		'module':    ah.Value('subprocess')
		'name':      ah.Value('run')
		'arguments': ah.Value([rb.ordinary(rb.strings(argv))])
		'options':   ah.Value({
			'check': ah.Value(true)
		})
	}
	if quiet {
		row['options'] = ah.Value(map[string]ah.Value{})
		row['keyword_objects'] = ah.Value({
			'stderr': rb.attribute(global('subprocess')!, 'DEVNULL', true)!
			'check':  rb.callback('retain', {
				'value': rb.ordinary(ah.Value(true))
			})!
		})
	}
	rb.callback('invoke', row)!
}

fn output(argv []string) !ah.Value {
	return rb.call('acquire', 'subprocess', 'check_output', [rb.ordinary(rb.strings(argv))], {
		'text': ah.Value(true)
	})!
}

fn mkdir(path ah.Value) ! {
	rb.method('invoke', path, 'mkdir', [], {
		'parents':  ah.Value(true)
		'exist_ok': ah.Value(true)
	})!
}

fn copy(source ah.Value, destination ah.Value) ! {
	rb.call('invoke', 'shutil', 'copy2', [o(source), o(destination)], {})!
}

fn remove(path ah.Value) ! { rb.call('invoke', 'shutil', 'rmtree', [o(path)], {})! }

fn exit(owner ah.Value, failed bool, cause IError) !bool {
	return rb.callback('exit', {
		'id':    owner
		'error': if failed { ah.Value(boothost.failure(cause)) } else { rb.null() }
	})! == ah.Value(true)
}

fn pinned_download(url ah.Value, path ah.Value) ! {
	if rb.callback('function_is', {
		'name':      ah.Value('download')
		'reference': ah.Value('_native_download')
	})! == ah.Value(true) {
		download(url, path)!
	} else {
		rb.api('download', [o(url), o(path)], {}, false)!
	}
}

fn failure(message string) IError { return boothost.PolicyError{'SystemExit', message} }

fn unpack_pair(value ah.Value) ![]ah.Value {
	return rb.callback('unpack_pair', {
		'id': value
	})!.items()
}
