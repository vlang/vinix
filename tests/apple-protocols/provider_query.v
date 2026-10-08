// SPDX-License-Identifier: GPL-2.0-only
module main

import applehost
import encoding.hex
import fixturehost
import hosttest
import json2
import os

fn field(row map[string]json2.Any, name string) !string {
	return hex.decode(row[name]!.str())!.bytestr()
}

fn run(row map[string]json2.Any) !json2.Any {
	return applehost.copy_provider(field(row, 'root')!, field(row, 'destination')!, row['family']!.str(), row['ans']!.bool(), row['hardware']!.bool())!
}

fn failure(err IError) map[string]json2.Any {
	if err is applehost.ProviderError {
		return {
			'kind':    json2.Any(err.kind)
			'message': json2.Any(err.message)
		}
	}
	if err is fixturehost.FileError {
		return {
			'kind':     json2.Any('OSError')
			'errno':    json2.Any(err.number)
			'filename': json2.Any(err.filename.bytes().hex())
		}
	}
	if err is hosttest.ModuleDecodeError {
		return {
			'kind':   json2.Any('UnicodeDecodeError')
			'data':   json2.Any(err.data.hex())
			'start':  json2.Any(err.start)
			'end':    json2.Any(err.end)
			'reason': json2.Any(err.reason)
		}
	}
	return {
		'kind':    json2.Any('ValueError')
		'message': json2.Any(err.msg())
	}
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--install-controller' {
		fixturehost.install(os.args[2]) or { eprintln(err); exit(1) }
		return
	}
	if os.args.len == 4 && os.args[1] == '--query' {
		row := hosttest.decode_json(os.args[3]) or { panic(err) }.as_map()
		value := run(row) or {
			fixturehost.write(os.args[2], json2.encode(failure(err))) or { panic(err) }
			return
		}
		fixturehost.write(os.args[2], json2.encode({'value': value})) or { panic(err) }
		return
	}
	row := hosttest.decode_json(os.args[1]) or { panic(err) }.as_map()
	value := run(row) or {
		println(json2.encode(failure(err)))
		return
	}
	println(json2.encode({
		'value': value
	}))
}
