module runnercore

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

fn literal(value string) !ah.Value {
	return rb.callback('retain', {
		'value': v(value)
	})!
}

fn text(value ah.Value) !string { return rb.format_object(value)! }

fn py_str(value ah.Value) !ah.Value {
	return rb.api('_call_name', [v('str'), o(value)], {}, true)!
}

fn join(base ah.Value, name string) !ah.Value {
	return rb.call('acquire', 'operator', 'truediv', [o(base), v(name)], {})!
}

fn method(value ah.Value, name string, arguments []ah.Value) !ah.Value {
	return rb.method('acquire', value, name, arguments, {})!
}

fn test(value ah.Value, name string) !bool { return rb.bool_object(method(value, name, [])!)! }

fn attr(value ah.Value, name string) !ah.Value { return rb.attribute(value, name, true)! }

fn flag(value ah.Value, name string) !bool { return rb.bool_object(attr(value, name)!)! }

fn mkdir(path ah.Value, parents bool) ! {
	rb.method('invoke', path, 'mkdir', [], if parents {
		{
			'parents':  ah.Value(true)
			'exist_ok': ah.Value(true)
		}
	} else {
		{
			'exist_ok': ah.Value(true)
		}
	})!
}

fn copy(source ah.Value, dest ah.Value) ! {
	rb.call('invoke', 'shutil', 'copy2', [o(source), o(dest)], {})!
}

fn append(list ah.Value, value ah.Value) ! { rb.method('invoke', list, 'append', [o(value)], {})! }

fn failure(message string) IError { return boothost.PolicyError{'SystemExit', message} }

fn exit(owner ah.Value, failed bool, cause IError) !bool {
	return rb.callback('exit', {
		'id':    owner
		'error': if failed { ah.Value(boothost.failure(cause)) } else { rb.null() }
	})! == ah.Value(true)
}

fn make_path(value ah.Value) !ah.Value { return rb.api('Path', [o(value)], {}, true)! }

fn native_copy(source ah.Value, dest ah.Value) ! {
	if rb.callback('function_is', {
		'name':      ah.Value('copy_layer')
		'reference': ah.Value('_native_copy_layer')
	})! == ah.Value(true) {
		copy_layer(source, dest)!
	} else {
		rb.api('copy_layer', [o(source), o(dest)], {}, false)!
	}
}
