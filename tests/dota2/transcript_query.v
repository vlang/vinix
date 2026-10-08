// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hosttest
import transcriptcore
import encoding.hex
import json2
import os

fn field(row map[string]json2.Any, key string) !json2.Any {
	return row[key] or { return error('Missing ' + key) }
}

fn request(row map[string]json2.Any) !string {
	op := field(row, 'operation')!.str()
	text := hex.decode(field(row, 'transcript_hex')!.str())!.bytestr()
	match op {
		'capture' {
			return json2.encode({
				'value': json2.Any(transcriptcore.decode_capture(text)!.hex())
			})
		}
		'wake' {
			return '{"value":' + json2.encode(transcriptcore.wake_verdict(text, field(row, 'reaped')!.bool())) + '}'
		}
		'environment' {
			return '{"value":' + json2.encode(transcriptcore.environment_verdict(text, field(row, 'harness_zero')!.bool())) + '}'
		}
		else { return error('Unknown transcript operation: ' + op) }
	}
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--install-query' {
		hosttest.module_copy_file(os.executable(), os.args[2]) or {
			eprintln(err)
			exit(1)
		}
		os.chmod(os.args[2], 0o700) or {
			eprintln(err)
			exit(1)
		}
		return
	}
	for {
		line := os.get_raw_line()
		if line == '' { break }
		row := hosttest.decode_json(line) or {
			println(json2.encode({
				'error': json2.Any(err.msg())
			}))
			continue
		}.as_map()
		result := request(row) or {
			mut failure := {
				'error': json2.Any(err.msg())
				'kind':  json2.Any('ValueError')
			}
			if err is transcriptcore.DecodeError { failure['kind'] = err.kind }
			println(json2.encode(failure))
			continue
		}
		println(result)
	}
}
