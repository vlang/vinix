module debiancore

import androidhost as ah
import boothost
import runtimebuild as rb

fn retain(value ah.Value) !ah.Value {
	return rb.callback('retain', {
		'value': rb.ordinary(value)
	})!
}

fn test(id ah.Value, name string) !bool {
	return rb.bool_object(rb.method('acquire', id, name, [], {})!)!
}

fn contains(container ah.Value, value ah.Value) !bool {
	return rb.bool_object(rb.call('acquire', 'operator', 'contains', [
		rb.object(container),
		rb.object(value),
	], {})!)!
}

fn join(base ah.Value, name ah.Value) !ah.Value {
	return rb.method('acquire', base, '__truediv__', [rb.object(name)], {})!
}

fn at(id ah.Value, index int) !ah.Value {
	return rb.method('acquire', id, '__getitem__', [rb.ordinary(ah.Value(index))], {})!
}

fn is_none(id ah.Value) !bool {
	return rb.callback('is_none', {
		'id': id
	})! == ah.Value(true)
}

fn native(name string) !bool {
	return rb.callback('function_is', {
		'name':      ah.Value(name)
		'reference': ah.Value('_native_' + name)
	})! == ah.Value(true)
}

fn tuple(values []ah.Value) !ah.Value {
	return rb.call('acquire', 'builtins', 'tuple', [rb.object(rb.make_sequence(values)!)], {})!
}

fn append(sequence ah.Value, value ah.Value) ! {
	rb.method('invoke', sequence, 'append', [rb.object(value)], {})!
}

fn failure(message string) IError { return boothost.PolicyError{'SystemExit', message} }

fn exit(owner ah.Value, failed bool, cause IError) !bool {
	return rb.callback('exit', {
		'id':    owner
		'error': if failed { ah.Value(boothost.failure(cause)) } else { rb.null() }
	})! == ah.Value(true)
}

fn emit(text string, stderr bool) ! {
	mut row := {
		'data': ah.Value(text)
	}
	if stderr {
		row['keyword_objects'] = ah.Value({
			'file': rb.attribute(rb.callback('borrow_global', {
				'name': ah.Value('sys')
			})!, 'stderr', true)!
		})
	}
	rb.callback('print', row)!
}

fn bytes_hex(text string) !ah.Value {
	return rb.method('acquire', rb.call('acquire', 'builtins', 'bytes', [], {})!, 'fromhex', [rb.ordinary(ah.Value(text))], {})!
}

fn slice_objects(id ah.Value, begin ah.Value, end ah.Value) !ah.Value {
	selection := rb.call('acquire', 'builtins', 'slice', [rb.object(begin), rb.object(end)], {})!
	return rb.method('acquire', id, '__getitem__', [rb.object(selection)], {})!
}

fn slice(id ah.Value, begin int, end int) !ah.Value {
	return slice_objects(id, retain(ah.Value(begin))!, retain(ah.Value(end))!)!
}

fn add(left ah.Value, right ah.Value) !ah.Value {
	return rb.call('acquire', 'operator', 'add', [rb.object(left), rb.object(right)], {})!
}

fn key(specification ah.Value) !ah.Value {
	if native('dependency_key')! { return dependency_key(specification)! }
	return rb.api('dependency_key', [rb.object(specification)], {}, true)!
}

fn relations(field ah.Value) !ah.Value {
	if native('parse_relations')! { return parse_relations(field)! }
	return rb.api('parse_relations', [rb.object(field)], {}, true)!
}
