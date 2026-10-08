module debiancore

import androidhost as ah
import runtimebuild as rb

fn workflow(args ah.Value) !ah.Value {
	packages := rb.call('acquire', 'builtins', 'list', [], {})!
	indexes := rb.iter_object(rb.attribute(args, 'index', true)!)!
	for {
		path := rb.next(indexes)!
		if path == rb.null() { break }
		parsed := if native('parse_index')! {
			parse_index(path)!
		} else {
			rb.api('parse_index', [rb.object(path)], {}, true)!
		}
		rb.method('invoke', packages, 'extend', [rb.object(parsed)], {})!
	}
	roots := rb.attribute(args, 'packages', true)!
	ignored := rb.call('acquire', 'builtins', 'set', [rb.object(rb.attribute(args, 'ignore', true)!)], {})!
	selected := if native('resolve')! {
		resolve(packages, roots, ignored)!
	} else {
		rb.api('resolve', [rb.object(packages), rb.object(roots), rb.object(ignored)], {}, true)!
	}
	lines := rb.call('acquire', 'builtins', 'list', [], {})!
	iter := rb.iter_object(selected)!
	for {
		package := rb.next(iter)!
		if package == rb.null() { break }
		text := rb.format_object(rb.attribute(package, 'name', true)!)! + '\t' + rb.format_object(rb.attribute(package, 'version', true)!)! + '\t' + rb.format_object(rb.attribute(package, 'architecture', true)!)! + '\t' + rb.format_object(rb.attribute(package, 'filename', true)!)!
		append(lines, retain(ah.Value(text))!)!
	}
	joined := rb.method('acquire', retain(ah.Value('\n'))!, 'join', [rb.object(lines)], {})!
	if rb.bool_object(rb.attribute(args, 'resolve_only', true)!)! {
		emit(rb.format_object(joined)!, false)!
		return ah.Value(0)
	}
	manifest := rb.attribute(args, 'manifest', true)!
	if !is_none(manifest)! {
		text := rb.call('acquire', 'operator', 'add', [rb.object(joined), rb.ordinary(ah.Value('\n'))], {})!
		rb.method('invoke', manifest, 'write_text', [rb.object(text)], {
			'encoding': ah.Value('utf-8')
		})!
	}
	cache := rb.attribute(args, 'cache', true)!
	rb.method('invoke', cache, 'mkdir', [], {
		'parents':  ah.Value(true)
		'exist_ok': ah.Value(true)
	})!
	root := rb.attribute(args, 'root', true)!
	rb.method('invoke', root, 'mkdir', [], {
		'parents':  ah.Value(true)
		'exist_ok': ah.Value(true)
	})!
	mut total := retain(ah.Value(0))!
	sizes := rb.iter_object(selected)!
	for {
		package := rb.next(sizes)!
		if package == rb.null() { break }
		total = rb.call('acquire', 'operator', 'add', [rb.object(total),
			rb.object(rb.attribute(package, 'size', true)!)], {})!
	}
	mib := rb.call('acquire', 'operator', 'truediv', [rb.object(total), rb.ordinary(ah.Value(1 << 20))], {})!
	formatted := rb.call('invoke', 'builtins', 'format', [rb.object(mib), rb.ordinary(ah.Value('.0f'))], {})!.text()
	count := rb.call('invoke', 'builtins', 'len', [rb.object(selected)], {})!
	emit('  ' + ah.encode(count) + ' packages, ' + formatted + ' MiB of archives', true)!
	archives := rb.callback('pool_function', {
		'factory': ah.Value('ThreadPoolExecutor')
		'name':    ah.Value('download')
		'before':  ah.Value([ah.Value([ah.Value('attribute'), ah.Value([args, ah.Value('mirror')])])])
		'after':   ah.Value([ah.Value([ah.Value('attribute'), ah.Value([args, ah.Value('cache')])])])
		'workers': ah.Value(6)
		'id':      selected
	})!
	// Iterating zip retains its shortest-input termination and caller overrides.
	zipped := rb.iter_object(rb.call('acquire', 'builtins', 'zip', [
		rb.object(selected),
		rb.object(archives),
	], {})!)!
	for {
		pair := rb.next(zipped)!
		if pair == rb.null() { break }
		objects := rb.callback('unpack_pair', {
			'id': pair
		})!.items()
		if native('extract_deb')! {
			extract_deb(objects[1], rb.attribute(args, 'root', true)!)!
		} else {
			rb.api('extract_deb', [rb.object(objects[1]), rb.object(rb.attribute(args, 'root', true)!)], {}, false)!
		}
	}
	return ah.Value(0)
}

pub fn dispatch(row map[string]ah.Value) !ah.Value {
	operation := ah.field(row, 'operation').text()
	match operation {
		'dependency_key' { return rb.result_object(dependency_key(rb.borrow('specification')!)!) }
		'parse_relations' { return rb.result_object(parse_relations(rb.borrow('field')!)!) }
		'parse_index' { return rb.result_object(parse_index(rb.borrow('path')!)!) }
		'resolve' {
			return rb.result_object(resolve(rb.borrow('packages')!, rb.borrow('roots')!, rb.borrow('ignored')!)!)
		}
		'download' {
			return rb.result_object(download(rb.borrow('mirror')!, rb.borrow('package')!, rb.borrow('cache')!)!)
		}
		'file_sha256' { return rb.result_object(file_sha256(rb.borrow('path')!)!) }
		'extract_deb' { return extract_deb(rb.borrow('deb')!, rb.borrow('root')!) }
		'main' { return workflow(rb.borrow('arguments')!) }
		'ar_next' {
			offset := rb.borrow('offset')!
			member := ar_next(rb.borrow('data')!, offset, rb.bool_object(rb.borrow('initial')!)!)!
			if member.done { return rb.null() }
			return rb.result_object(rb.make_sequence([rb.object(member.name),
				rb.object(member.payload), rb.object(member.offset)])!)
		}
		else { return error('Unknown Debian package operation') }
	}
}
