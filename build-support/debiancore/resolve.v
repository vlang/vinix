module debiancore

import androidhost as ah
import runtimebuild as rb

fn resolve(packages ah.Value, roots ah.Value, ignored ah.Value) !ah.Value {
	by_name := rb.call('acquire', 'builtins', 'dict', [], {})!
	providers := rb.call('acquire', 'builtins', 'dict', [], {})!
	source := rb.iter_object(packages)!
	for {
		package := rb.next(source)!
		if package == rb.null() { break }
		rb.method('invoke', by_name, 'setdefault', [
			rb.object(rb.attribute(package, 'name', true)!),
			rb.object(package),
		], {})!
		provisions := rb.iter_object(rb.attribute(package, 'provides', true)!)!
		for {
			provision := rb.next(provisions)!
			if provision == rb.null() { break }
			list := rb.call('acquire', 'builtins', 'list', [], {})!
			owners := rb.method('acquire', providers, 'setdefault', [
				rb.object(provision),
				rb.object(list),
			], {})!
			append(owners, package)!
		}
	}
	selected := rb.call('acquire', 'builtins', 'dict', [], {})!
	queue := rb.call('acquire', 'collections', 'deque', [], {})!
	root_iter := rb.iter_object(roots)!
	for {
		root := rb.next(root_iter)!
		if root == rb.null() { break }
		append(queue, tuple([rb.object(root)])!)!
	}
	for rb.bool_object(queue)! {
		alternatives := rb.method('acquire', queue, 'popleft', [], {})!
		mut satisfied := false
		names := rb.iter_object(alternatives)!
		for {
			name := rb.next(names)!
			if name == rb.null() { break }
			if contains(selected, name)! || contains(ignored, name)! {
				satisfied = true
				break
			}
		}
		if satisfied { continue }
		mut package := retain(rb.null())!
		direct := rb.iter_object(alternatives)!
		for {
			name := rb.next(direct)!
			if name == rb.null() { break }
			if contains(by_name, name)! {
				package = rb.method('acquire', by_name, '__getitem__', [rb.object(name)], {})!
				break
			}
		}
		if is_none(package)! {
			virtual := rb.iter_object(alternatives)!
			for {
				name := rb.next(virtual)!
				if name == rb.null() { break }
				if contains(providers, name)! {
					package = at(rb.method('acquire', providers, '__getitem__', [rb.object(name)], {})!, 0)!
					break
				}
			}
		}
		if is_none(package)! {
			joined := rb.method('invoke', retain(ah.Value(' | '))!, 'join', [rb.object(alternatives)], {})!.text()
			return failure('unresolved Debian dependency: ' + joined)
		}
		name := rb.attribute(package, 'name', true)!
		if contains(selected, name)! { continue }
		rb.method('invoke', selected, '__setitem__', [rb.object(name), rb.object(package)], {})!
		rb.method('invoke', queue, 'extend', [rb.object(rb.attribute(package, 'dependencies', true)!)], {})!
	}
	return rb.callback('sort_attribute', {
		'id':   rb.method('acquire', selected, 'values', [], {})!
		'name': ah.Value('name')
	})!
}
