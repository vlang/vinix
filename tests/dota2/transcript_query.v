// SPDX-License-Identifier: GPL-2.0-or-later
module main

import hosttest
import transcriptcore
import buildcore
import encoding.hex
import json2
import os

fn field(row map[string]json2.Any, key string) !json2.Any {
	return row[key] or { return error('Missing ' + key) }
}

fn path_field(row map[string]json2.Any, key string) !string {
	if key + '_hex' in row { return hex.decode(field(row, key + '_hex')!.str())!.bytestr() }
	return field(row, key)!.str()
}

fn request(row map[string]json2.Any) !string {
	op := field(row, 'operation')!.str()
	text := hex.decode(field(row, 'transcript_hex')!.str())!.bytestr()
	match op {
		'glibc-valid' {
			return '{"value":' + buildcore.glibc_valid(path_field(row, 'root')!, buildcore.decode_value(field(row, 'marker')!)!, buildcore.decode_value(field(row, 'pin')!)!, field(row, 'alias_policy')!.str(), field(row, 'libraries')!.as_array().map(it.str())).str() + '}'
		}
		'driver-valid' {
			return '{"value":' + buildcore.driver_valid(path_field(row, 'root')!, buildcore.decode_value(field(row, 'marker')!)!, buildcore.decode_value(field(row, 'expected')!)!, field(row, 'library')!.str(), field(row, 'icd')!.str()).str() + '}'
		}
		'mesa-pin' {
			buildcore.validate_mesa(buildcore.decode_value(field(row, 'data')!)!, path_field(row, 'path')!)!
			return '{"value":null}'
		}
		'glibc-pin' {
			buildcore.validate_glibc(buildcore.decode_value(field(row, 'data')!)!, path_field(row, 'path')!)!
			return '{"value":null}'
		}
		'shared-elf' { return '{"value":' + buildcore.shared_elf(text.bytes()).str() + '}' }
		'static-translator' {
			return '{"value":' + buildcore.static_translator(text.bytes(), field(row, 'dynamic')!.str()).str() + '}'
		}
		'needed' { return '{"value":' + json2.encode(buildcore.needed(text)) + '}' }
		'verify-dynamic' {
			buildcore.verify_dynamic(text, path_field(row, 'base')!)!
			return '{"value":null}'
		}
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
			if err is buildcore.PolicyError {
				failure['kind'] = err.kind
				failure.delete('error')
				failure['error_hex'] = err.msg().bytes().hex()
			}
			println(json2.encode(failure))
			continue
		}
		println(result)
	}
}
