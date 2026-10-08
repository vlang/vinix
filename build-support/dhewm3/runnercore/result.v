module runnercore

import androidhost as ah
import runtimebuild as rb

fn builtin(name string, arguments []ah.Value) !ah.Value {
	mut parameters := [v(name)]
	for parameter in arguments { parameters << parameter }
	return rb.api('_call_name', parameters, {}, true)!
}

fn getitem(value ah.Value, key ah.Value) !ah.Value {
	return rb.call('acquire', 'operator', 'getitem', [o(value), key], {})!
}

fn raw(value string) !ah.Value {
	return rb.callback('retain', {
		'value': ah.Value([ah.Value('bytes'), ah.Value(value.bytes().hex())])
	})!
}

fn has(value ah.Value, marker string) !bool {
	return rb.bool_object(rb.call('acquire', 'operator', 'contains', [o(value), o(raw(marker)!)], {})!)!
}

fn artifact_result(args ah.Value, work ah.Value, transcript ah.Value, os_name ah.Value) !ah.Value {
	normalized := method(builtin('bytes', [o(transcript)])!, 'replace', [
		o(raw('\r')!),
		o(raw('')!),
	])!
	files := rb.call('acquire', 'builtins', 'list', [], {})!
	shot := rb.call('acquire', 'builtins', 'tuple', [o(rb.make_sequence([
		o(raw('SHOT')!),
		v(text(os_name)! + '.xwd'),
	])!)], {})!
	append(files, shot)!
	if flag(args, 'record')! {
		pair := rb.call('acquire', 'builtins', 'tuple', [o(rb.make_sequence([
			o(raw('DEMO')!),
			v('vinix-demo.demo'),
		])!)], {})!
		rb.method('invoke', files, 'insert', [rb.ordinary(ah.Value(0)), o(pair)], {})!
	}
	iter := rb.iter_object(files)!
	for {
		pair := rb.next(iter)!
		if pair == rb.null() { break }
		marker := getitem(pair, rb.ordinary(ah.Value(0)))!
		filename := getitem(pair, rb.ordinary(ah.Value(1)))!
		begin := rb.call('acquire', 'operator', 'add', [o(raw('DHEWM3-')!), o(marker)], {})!
		begin_line := rb.call('acquire', 'operator', 'add', [o(begin), o(raw('-BEGIN\n')!)], {})!
		data := getitem(method(normalized, 'split', [o(begin_line), rb.ordinary(ah.Value(1))])!, rb.ordinary(ah.Value(1)))!
		end := rb.call('acquire', 'operator', 'add', [o(begin), o(raw('-END')!)], {})!
		payload := getitem(method(data, 'split', [o(end), rb.ordinary(ah.Value(1))])!, rb.ordinary(ah.Value(0)))!
		lines := rb.call('acquire', 'builtins', 'list', [], {})!
		split := rb.iter_object(method(payload, 'splitlines', [])!)!
		for {
			line := rb.next(split)!
			if line == rb.null() { break }
			matched := rb.call('acquire', 're', 'fullmatch', [
				o(raw('[A-Za-z0-9+/]+={0,2}')!),
				o(line),
			], {})!
			if rb.bool_object(matched)! { append(lines, line)! }
		}
		encoded := method(raw('')!, 'join', [o(lines)])!
		decoded := rb.call('acquire', 'base64', 'b64decode', [o(encoded)], {
			'validate': ah.Value(true)
		})!
		target := rb.call('acquire', 'operator', 'truediv', [o(work), o(filename)], {})!
		rb.method('invoke', target, 'write_bytes', [o(decoded)], {})!
	}
	if rb.bool_object(rb.call('acquire', 'shutil', 'which', [v('ffmpeg')], {})!)! {
		png := join(work, text(os_name)! + '.png')!
		argv := rb.make_sequence([v('ffmpeg'), v('-hide_banner'), v('-loglevel'), v('error'), v('-y'),
			v('-i'), o(py_str(join(work, text(os_name)! + '.xwd')!)!), v('-frames:v'), v('1'),
			o(py_str(png)!)])!
		rb.call('invoke', 'subprocess', 'run', [o(argv)], {
			'check': ah.Value(true)
		})!
		append(files, rb.call('acquire', 'builtins', 'tuple', [o(rb.make_sequence([
			o(raw('PNG')!),
			o(attr(png, 'name')!),
		])!)], {})!)!
	}
	artifacts := rb.call('acquire', 'builtins', 'list', [], {})!
	paths := rb.iter_object(files)!
	for {
		pair := rb.next(paths)!
		if pair == rb.null() { break }
		values := rb.callback('unpack_pair', {
			'id': pair
		})!.items()
		append(artifacts, builtin('str', [o(rb.call('acquire', 'operator', 'truediv', [
			o(work),
			o(values[1]),
		], {})!)])!)!
	}
	return rb.dictionary([v('os'), v('artifacts')], [o(os_name), o(artifacts)])!
}

fn benchmark_result(args ah.Value, transcript ah.Value, os_name ah.Value) !ah.Value {
	rows := rb.call('acquire', 'builtins', 'list', [], {})!
	matches := rb.iter_object(method(global('FPS')!, 'finditer', [o(transcript)])!)!
	for {
		found := rb.next(matches)!
		if found == rb.null() { break }
		row := rb.dictionary([v('frames'), v('seconds'), v('fps')], [
			o(builtin('int', [o(getitem(found, rb.ordinary(ah.Value(1)))!)])!),
			o(builtin('float', [o(getitem(found, rb.ordinary(ah.Value(2)))!)])!),
			o(builtin('float', [o(getitem(found, rb.ordinary(ah.Value(3)))!)])!),
		])!
		append(rows, row)!
	}
	elapsed := rb.call('acquire', 'builtins', 'list', [], {})!
	counters := rb.iter_object(rb.call('acquire', 're', 'finditer', [
		o(raw(r'DHEWM3-ELAPSED ns=(\d+) status=0')!),
		o(transcript),
	], {})!)!
	for {
		found := rb.next(counters)!
		if found == rb.null() { break }
		ns := builtin('int', [o(getitem(found, rb.ordinary(ah.Value(1)))!)])!
		append(elapsed, rb.call('acquire', 'operator', 'truediv', [o(ns),
			rb.ordinary(ah.Value(1000000000))], {})!)!
	}
	if rb.bool_object(rb.call('acquire', 'operator', 'ne', [
		o(builtin('len', [o(elapsed)])!),
		o(builtin('len', [o(rows)])!),
	], {})!)! {
		return failure('Missing independent counter measurements')
	}
	zipped := rb.iter_object(builtin('zip', [o(rows), o(elapsed)])!)!
	for {
		pair := rb.next(zipped)!
		if pair == rb.null() { break }
		values := rb.callback('unpack_pair', {
			'id': pair
		})!.items()
		rb.method('invoke', values[0], '__setitem__', [v('process_seconds'), o(values[1])], {})!
	}
	row_count := builtin('len', [o(rows)])!
	expected := rb.call('acquire', 'operator', 'add', [o(attr(args, 'rounds')!),
		rb.ordinary(ah.Value(1))], {})!
	mut invalid := rb.bool_object(rb.call('acquire', 'operator', 'ne', [o(row_count), o(expected)], {})!)!
	if !invalid {
		frames := rb.call('acquire', 'builtins', 'set', [], {})!
		records := rb.iter_object(rows)!
		for {
			row := rb.next(records)!
			if row == rb.null() { break }
			rb.method('invoke', frames, 'add', [o(getitem(row, v('frames'))!)], {})!
		}
		invalid = rb.bool_object(rb.call('acquire', 'operator', 'ne', [
			o(builtin('len', [o(frames)])!),
			rb.ordinary(ah.Value(1)),
		], {})!)!
	}
	if invalid { return failure('Incomplete or inconsistent timedemos: ' + text(rows)!) }
	warmup := getitem(rows, rb.ordinary(ah.Value(0)))!
	slicing := rb.call('acquire', 'builtins', 'slice', [rb.ordinary(ah.Value(1)),
		rb.ordinary(rb.null())], {})!
	runs := getitem(rows, o(slicing))!
	// The generator holds the independent original slice and reads fps lazily.
	median_rows := getitem(rows, o(slicing))!
	generator := rb.api('_iter_items', [o(median_rows), v('fps')], {}, true)!
	median := rb.call('acquire', 'statistics', 'median', [o(generator)], {})!
	return rb.dictionary([v('os'), v('warmup'), v('runs'), v('median_fps')], [
		o(os_name),
		o(warmup),
		o(runs),
		o(median),
	])!
}

fn result(args ah.Value, work ah.Value, transcript ah.Value, os_name ah.Value) !ah.Value {
	if !has(transcript, 'DHEWM3-DONE')! {
		return failure(text(os_name)! + ' did not finish; inspect ' + text(work)! + '/' + text(os_name)! + '.log')
	}
	if flag(args, 'clock_only')! {
		return rb.dictionary([v('os'), v('clock_probe')], [o(os_name), v('passed')])!
	}
	if flag(args, 'record')! || flag(args, 'screenshot')! {
		return artifact_result(args, work, transcript, os_name)!
	}
	return benchmark_result(args, transcript, os_name)!
}
