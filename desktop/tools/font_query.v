// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.
module main

import encoding.hex
import fixturehost
import fonthost
import hosttest
import json2
import os

fn failure(err IError) map[string]json2.Any {
	if err is fonthost.BindingError { return err.value }
	if err is fonthost.FontError { return {'kind': json2.Any(err.kind), 'message': json2.Any(err.message)} }
	if err is fixturehost.FileError {
		return {'kind': json2.Any('OSError'), 'errno': json2.Any(err.number), 'filename': json2.Any(err.filename.bytes().hex()), 'message': json2.Any(err.message)}
	}
	if err is hosttest.ModuleDecodeError {
		return {'kind': json2.Any('UnicodeDecodeError'), 'data': json2.Any(hex.encode(err.data)), 'start': json2.Any(err.start), 'end': json2.Any(err.end), 'reason': json2.Any(err.reason)}
	}
	return {'kind': json2.Any('RuntimeError'), 'message': json2.Any(err.msg())}
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--install-controller' {
		fixturehost.install(os.args[2]) or { eprintln(err); exit(1) }; return
	}
	mut engine := fonthost.Engine{}
	for {
		line := os.get_raw_line()
		if line == '' { break }
		row := hosttest.decode_json(line) or { println(json2.encode({'error': json2.Any(failure(err))}, escape_unicode: true)); continue }
		query := row.as_map()
		value := if (query['operation'] or { json2.Null{} }).str() == 'description' { json2.Any(fonthost.description()) } else if (query['operation'] or { json2.Null{} }).str() == 'constants' {
			fonthost.constants() or { println(json2.encode({'error': json2.Any(failure(err))}, escape_unicode: true)); continue }
		} else {
			engine.dispatch(query) or { println(json2.encode({'error': json2.Any(failure(err))}, escape_unicode: true)); continue }
		}
		println(json2.encode({'value': value}, escape_unicode: true))
	}
}
