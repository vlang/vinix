module alpinecore

import androidhost as ah
import boothost
import runtimebuild as rb

fn key(specification ah.Value) !ah.Value {
	native := rb.callback('function_is', {
		'name':      ah.Value('dependency_key')
		'reference': ah.Value('_native_dependency_key')
	})! == ah.Value(true)
	if native { return dependency_key(specification)! }
	return rb.api('dependency_key', [rb.object(specification)], {}, true)!
}

fn contains(container ah.Value, value ah.Value) !bool {
	return rb.bool_object(rb.call('acquire', 'operator', 'contains', [
		rb.object(container),
		rb.object(value),
	], {})!)!
}

fn defaults(dictionary ah.Value, name ah.Value, value ah.Value) ! {
	rb.method('invoke', dictionary, 'setdefault', [rb.object(name), rb.object(value)], {})!
}

fn resolve_main(args ah.Value) !ah.Value {
	packages := rb.call('acquire', 'builtins', 'list', [], {})!
	indexes := rb.iter_object(rb.attribute(args, 'index', true)!)!
	for {
		row := rb.next(indexes)!
		if row == rb.null() { break }
		pair := rb.callback('unpack_pair', {
			'id': row
		})!.items()
		repository := pair[0]
		path := rb.api('Path', [rb.object(pair[1])], {}, true)!
		parsed := rb.api('parse_index', [rb.object(path), rb.object(repository)], {}, true)!
		rb.method('invoke', packages, 'extend', [rb.object(parsed)], {})!
	}
	by_name := rb.call('acquire', 'builtins', 'dict', [], {})!
	providers := rb.call('acquire', 'builtins', 'dict', [], {})!
	iter := rb.iter_object(packages)!
	for {
		package := rb.next(iter)!
		if package == rb.null() { break }
		defaults(by_name, rb.attribute(package, 'name', true)!, package)!
		defaults(providers, rb.attribute(package, 'name', true)!, package)!
		provisions := rb.iter_object(rb.attribute(package, 'provides', true)!)!
		for {
			provision := rb.next(provisions)!
			if provision == rb.null() { break }
			defaults(providers, key(provision)!, package)!
		}
	}
	ignored := rb.call('acquire', 'builtins', 'set', [rb.ordinary(rb.strings(['/bin/sh', 'cmd:sh',
		'cmd:busybox']))], {})!
	queue := rb.call('acquire', 'collections', 'deque', [rb.object(rb.attribute(args, 'packages', true)!)], {})!
	selected := rb.call('acquire', 'builtins', 'dict', [], {})!
	for rb.bool_object(queue)! {
		requested := key(rb.method('acquire', queue, 'popleft', [], {})!)!
		if !rb.bool_object(requested)! || rb.bool_object(rb.method('acquire', requested, 'startswith', [rb.ordinary(ah.Value('!'))], {})!)! || contains(ignored, requested)! {
			continue
		}
		mut package := rb.method('acquire', by_name, 'get', [rb.object(requested)], {})!
		if !rb.bool_object(package)! {
			package = rb.method('acquire', providers, 'get', [rb.object(requested)], {})!
		}
		if rb.call('invoke', 'operator', 'is_', [rb.object(package), rb.ordinary(rb.null())], {})! == ah.Value(true) {
			return boothost.PolicyError{'SystemExit', 'unresolved Alpine dependency: ' + rb.format_object(requested)!}
		}
		if contains(selected, rb.attribute(package, 'name', true)!)! { continue }
		rb.method('invoke', selected, '__setitem__', [
			rb.object(rb.attribute(package, 'name', true)!),
			rb.object(package),
		], {})!
		rb.method('invoke', queue, 'extend', [rb.object(rb.attribute(package, 'dependencies', true)!)], {})!
	}
	values := rb.method('acquire', selected, 'values', [], {})!
	// Attribute lookup is selected by V; the binding is the generic sorter.
	sorted := rb.callback('sort_attribute', {
		'id':   values
		'name': ah.Value('name')
	})!
	ordered := rb.iter_object(sorted)!
	for {
		package := rb.next(ordered)!
		if package == rb.null() { break }
		text := rb.format_object(rb.attribute(package, 'repository', true)!)! + '\t' + rb.format_object(rb.attribute(package, 'name', true)!)! + '-' + rb.format_object(rb.attribute(package, 'version', true)!)! + '.apk'
		rb.callback('print', {
			'data': ah.Value(text)
		})!
	}
	return ah.Value(0)
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	return match ah.field(row, 'operation').text() {
		'parse_index' { parse_index(rb.borrow('path')!)! }
		'dependency_key' { rb.result_object(dependency_key(rb.borrow('specification')!)!) }
		'main' { resolve_main(rb.borrow('args')!)! }
		else { return error('Unknown Alpine resolver operation') }
	}
}
