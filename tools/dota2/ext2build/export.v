// SPDX-License-Identifier: GPL-2.0-or-later
module ext2build

import androidhost as ah

fn identity(info string) !string {
	mut values := []string{}
	for name in ['st_dev', 'st_ino', 'st_size', 'st_mtime_ns', 'st_ctime_ns'] {
		values << attribute(info, name)!
	}
	return collection('list', values)!
}

fn same_source(info string, recorded string) !string {
	slice := call('builtins.slice', v(ah.Value(1)), o(null()!))!
	return call('operator.eq', o(item(api('identity', o(info))!, o(slice))!), o(item(recorded, o(slice))!))!
}

fn export_initialize(self string, state string) ! {
	manifest := call('json.loads', o(method(join(state, 'manifest.json')!, 'read_text', [], {})!))!
	if compare('ne', item(manifest, v(ah.Value('version')))!, literal(ah.Value(1))!)! {
		failed('ValueError', v(ah.Value('Unsupported export manifest')))!
	}
	set_attr(self, 'size', o(item(manifest, v(ah.Value('size')))!))!
	files := item(manifest, v(ah.Value('files')))!
	regions := item(manifest, v(ah.Value('regions')))!
	set_attr(self, 'files', o(files))!
	set_attr(self, 'regions', o(regions))!
	starts := call('builtins.list')!
	iter := iterator(regions)!
	for {
		row := next(iter)!
		if row.done { break }
		append(starts, o(item(row.value, v(ah.Value(0)))!))!
	}
	set_attr(self, 'starts', o(starts))!
	set_attr(self, 'metadata', o(call('os.open', o(join(state, 'metadata.ext2')!), o(call('os.O_RDONLY')!))!))!
	set_attr(self, 'open_files', o(call('OrderedDict')!))!
	set_attr(self, 'lock', o(call('threading.Lock')!))!
}

fn export_close(self string) ! {
	manager := attribute(self, 'lock')!
	enter(manager)!
	close_files(self) or {
		failure := err
		if !retire(manager, failure)! { return failure }
		return
	}
	retire(manager, none)!
}

fn close_files(self string) ! {
	iter := iterator(method(attribute(self, 'open_files')!, 'values', [], {})!)!
	for {
		row := next(iter)!
		if row.done { break }
		call('os.close', o(row.value))!
	}
	method(attribute(self, 'open_files')!, 'clear', [], {})!
	call('os.close', o(attribute(self, 'metadata')!))!
}

fn read_source(self string, index string, offset string, count string) !string {
	manager := attribute(self, 'lock')!
	enter(manager)!
	result := source_locked(self, index, offset, count) or {
		failure := err
		if !retire(manager, failure)! { return failure }
		return null()!
	}
	retire(manager, none)!
	return result
}

fn source_locked(self string, index string, offset string, count string) !string {
	entry := item(attribute(self, 'files')!, o(index))!
	mut descriptor := method(attribute(self, 'open_files')!, 'pop', [o(index), o(null()!)], {})!
	if compare('is_', descriptor, null()!)! {
		flags := call('operator.or_', o(call('os.O_RDONLY')!), o(call('builtins.getattr', o(callback('resolve', {
			'name': ah.Value('os')
		})!.text()), v(ah.Value('O_NOFOLLOW')), v(ah.Value(0)))!))!
		descriptor = call('os.open', o(item(entry, v(ah.Value('path')))!), o(flags))!
	}
	set_item(attribute(self, 'open_files')!, o(index), o(descriptor))!
	for compare('gt', call('builtins.len', o(attribute(self, 'open_files')!))!, literal(ah.Value(64))!)! {
		old := method(attribute(self, 'open_files')!, 'popitem', [], {
			'last': v(ah.Value(false))
		})!
		call('os.close', o(unpack2(old)![1]))!
	}
	if !truth(api('same_source', o(call('os.fstat', o(descriptor))!), o(item(entry, v(ah.Value('identity')))!))!)! {
		failed('OSError', o(call('errno.EIO')!), v(ah.Value('Source changed; rebuild the export: ' + formatted(item(entry, v(ah.Value('path')))!)!)))!
	}
	file_size := item(item(entry, v(ah.Value('identity')))!, v(ah.Value(2)))!
	wanted := call('builtins.max', v(ah.Value(0)), o(call('builtins.min', o(count), o(call('operator.sub', o(file_size), o(offset))!))!))!
	result := call('os.pread', o(descriptor), o(wanted), o(offset))!
	if compare('ne', call('builtins.len', o(result))!, wanted)! || !truth(api('same_source', o(call('os.fstat', o(descriptor))!), o(item(entry, v(ah.Value('identity')))!))!)! {
		failed('OSError', o(call('errno.EIO')!), v(ah.Value('Source changed while reading: ' + formatted(item(entry, v(ah.Value('path')))!)!)))!
	}
	return call('operator.add', o(result), o(call('builtins.bytes', o(call('operator.sub', o(count), o(wanted))!))!))!
}

fn formatted(id string) !string {
	return datum('builtins.format', [o(id), v(ah.Value(''))])!.text()
}

fn disk_read(self string, offset string, count string) !string {
	zero := literal(ah.Value(0))!
	if compare('lt', offset, zero)! || compare('lt', count, zero)! || compare('gt', count, call('MAX_REQUEST')!)! || compare('gt', call('operator.add', o(offset), o(count))!, attribute(self, 'size')!)! {
		failed('OSError', o(call('errno.EINVAL')!), v(ah.Value('Invalid disk read range')))!
	}
	output := call('builtins.list')!
	end := call('operator.add', o(offset), o(count))!
	mut position := offset
	for compare('lt', position, end)! {
		index := call('operator.sub', o(call('bisect.bisect_right', o(attribute(self, 'starts')!), o(position))!), v(ah.Value(1)))!
		mut contained := compare('ge', index, zero)!
		if contained {
			start := item(item(attribute(self, 'regions')!, o(index))!, v(ah.Value(0)))!
			length := item(item(attribute(self, 'regions')!, o(index))!, v(ah.Value(1)))!
			contained = compare('lt', position, call('operator.add', o(start), o(length))!)!
		}
		mut length := ''
		if contained {
			parts := unpack(item(attribute(self, 'regions')!, o(index))!, 4)!
			start, region_length, source, source_offset := parts[0], parts[1], parts[2], parts[3]
			length = call('builtins.min', o(call('operator.sub', o(end), o(position))!), o(call('operator.sub', o(call('operator.add', o(start), o(region_length))!), o(position))!))!
			file_offset := call('operator.sub', o(call('operator.add', o(source_offset), o(position))!), o(start))!
			append(output, o(api_method(self, 'read_source', [o(source), o(file_offset), o(length)])!))!
		} else {
			next_index := call('operator.add', o(index), v(ah.Value(1)))!
			boundary := if compare('lt', next_index, call('builtins.len', o(attribute(self, 'starts')!))!)! {
				item(attribute(self, 'starts')!, o(next_index))!
			} else {
				attribute(self, 'size')!
			}
			length = call('builtins.min', o(call('operator.sub', o(end), o(position))!), o(call('operator.sub', o(boundary), o(position))!))!
			data := call('os.pread', o(attribute(self, 'metadata')!), o(length), o(position))!
			if compare('ne', call('builtins.len', o(data))!, length)! {
				failed('OSError', o(call('errno.EIO')!), v(ah.Value('Short metadata read')))!
			}
			append(output, o(data))!
		}
		position = call('operator.add', o(position), o(length))!
	}
	return method(call('builtins.bytes')!, 'join', [o(output)], {})!
}
