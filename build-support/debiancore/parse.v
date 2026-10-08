module debiancore

import alpinecore
import androidhost as ah
import runtimebuild as rb

fn dependency_key(specification ah.Value) !ah.Value {
	stripped := rb.method('acquire', specification, 'strip', [], {})!
	split := rb.call('acquire', 're', 'split', [rb.ordinary(ah.Value(r'[\s(\[<>=]')),
		rb.object(stripped)], {
		'maxsplit': ah.Value(1)
	})!
	name := at(split, 0)!
	return at(rb.method('acquire', name, 'split', [rb.ordinary(ah.Value(':')),
		rb.ordinary(ah.Value(1))], {})!, 0)!
}

fn parse_relations(field ah.Value) !ah.Value {
	mut result := []ah.Value{}
	groups := rb.iter_object(rb.method('acquire', field, 'split', [rb.ordinary(ah.Value(','))], {})!)!
	for {
		group := rb.next(groups)!
		if group == rb.null() { break }
		mut alternatives := []ah.Value{}
		iter := rb.iter_object(rb.method('acquire', group, 'split', [rb.ordinary(ah.Value('|'))], {})!)!
		for {
			alternative := rb.next(iter)!
			if alternative == rb.null() { break }
			if rb.bool_object(key(alternative)!)! { alternatives << rb.object(key(alternative)!) }
		}
		if alternatives.len != 0 { result << rb.object(tuple(alternatives)!) }
	}
	return tuple(result)!
}

fn strip(text string) string {
	mut first := 0
	mut last := 0
	mut index := 0
	mut started := false
	for index < text.len {
		width := alpinecore.space_width(text, index)
		if width == 0 {
			if !started {
				first = index
				started = true
			}
			last = index + 1
		}
		index += if width != 0 { width } else { 1 }
	}
	return if started { text[first..last] } else { '' }
}

fn parse_index(path ah.Value) !ah.Value {
	contents := rb.method('acquire', path, 'read_text', [], {
		'encoding': ah.Value('utf-8')
		'errors':   ah.Value('replace')
	})!
	blocks := rb.method('invoke', contents, 'split', [rb.ordinary(ah.Value('\n\n'))], {})!.items()
	packages := rb.call('acquire', 'builtins', 'list', [], {})!
	for block in blocks {
		mut fields := map[string]string{}
		mut previous := ''
		for line in alpinecore.lines(block.text()) {
			if line.len != 0 && alpinecore.space_width(line, 0) != 0 {
				if previous != '' { fields[previous] += ' ' + strip(line) }
				continue
			}
			colon := line.index(':') or { continue }
			previous = line[..colon]
			fields[previous] = strip(line[colon + 1..])
		}
		if 'Package' !in fields || 'Filename' !in fields { continue }
		size := rb.call('acquire', 'builtins', 'int', [rb.ordinary(ah.Value(fields['Size'] or { '0' }))], {})!
		before := relations(retain(ah.Value(fields['Pre-Depends']))!)!
		after := relations(retain(ah.Value(fields['Depends']))!)!
		dependencies := rb.call('acquire', 'operator', 'add', [rb.object(before), rb.object(after)], {})!
		mut provides := []ah.Value{}
		for provision in fields['Provides'].split(',') {
			object := retain(ah.Value(provision))!
			if rb.bool_object(key(object)!)! { provides << rb.object(key(object)!) }
		}
		package := rb.callback('function', {
			'name':            ah.Value('Package')
			'object':          ah.Value(true)
			'options':         ah.Value({
				'name':         ah.Value(fields['Package'])
				'version':      ah.Value(fields['Version'])
				'architecture': ah.Value(fields['Architecture'])
				'filename':     ah.Value(fields['Filename'])
				'sha256':       ah.Value(fields['SHA256'])
			})
			'keyword_objects': ah.Value({
				'size':         size
				'dependencies': dependencies
				'provides':     tuple(provides)!
			})
		})!
		append(packages, package)!
	}
	return packages
}
