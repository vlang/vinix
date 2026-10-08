// SPDX-License-Identifier: GPL-2.0-or-later
module main

import cachekey
import json2
import encoding.hex
import os

fn bytes_field(row map[string]json2.Any, name string) !string {
	return hex.decode((row[name] or { return error('Missing ' + name) }).str())!.bytestr()
}

fn bytes_list(row map[string]json2.Any, name string) ![]string {
	mut result := []string{}
	for item in (row[name] or { return error('Missing ' + name) }).as_array() {
		result << hex.decode(item.str())!.bytestr()
	}
	return result
}

fn environment(row map[string]json2.Any) !map[string]string {
	mut result := map[string]string{}
	for item in (row['env'] or { return error('Missing env') }).as_array() {
		pair := item.as_array()
		if pair.len != 2 { return error('Invalid environment entry') }
		result[hex.decode(pair[0].str())!.bytestr()] = hex.decode(pair[1].str())!.bytestr()
	}
	return result
}

fn request(line string) !string {
	row := json2.decode[map[string]json2.Any](line, strict: true)!
	operation := (row['operation'] or { return error('Missing operation') }).str()
	return match operation {
		'content' {
			json2.encode(cachekey.content_key(bytes_list(row, 'paths')!, (row['metadata'] or { return error('Missing metadata') }).bool())!)
		}
		'tree' {
			json2.encode(cachekey.tree_key(bytes_list(row, 'paths')!, (row['metadata'] or { return error('Missing metadata') }).bool(), bytes_field(row, 'namespace')!)!)
		}
		'root' { json2.encode(cachekey.root_generation(bytes_field(row, 'path')!)!) }
		'resolve' { json2.encode(cachekey.resolve_path(bytes_field(row, 'path')!)!.bytes().hex()) }
		'env_path' {
			json2.encode(cachekey.env_path(environment(row)!, bytes_field(row, 'name')!, bytes_field(row, 'fallback')!)!.bytes().hex())
		}
		'tool_path' {
			json2.encode(cachekey.tool_path(environment(row)!, bytes_field(row, 'name')!, bytes_field(row, 'fallback')!)!.bytes().hex())
		}
		'desktop_prepare' {
			cachekey.desktop_encode(cachekey.desktop_prepare(bytes_field(row, 'root')!, bytes_field(row, 'v')!, environment(row)!, bytes_field(row, 'python')!)!)
		}
		'desktop_complete' {
			input := cachekey.desktop_decode(json2.encode(row['prepared'] or { return error('Missing prepared inputs') }))!
			json2.encode(cachekey.desktop_complete(input, environment(row)!, bytes_field(row, 'platform')!, bytes_field(row, 'python_version')!, bytes_field(row, 'pillow_version')!, bytes_field(row, 'musl_path')!, bytes_field(row, 'musl_version')!)!)
		}
		else { return error('Unknown cache query: ' + operation) }
	}
}

fn main() {
	if os.args.len == 3 && os.args[1] == '--install-query' {
		os.cp(os.executable(), os.args[2]) or {
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
		result := request(line) or {
			if err is cachekey.FileError {
				println(json2.encode({
					'error':        json2.Any(err.msg())
					'errno':        json2.Any(err.number)
					'filename_hex': json2.Any(err.filename.bytes().hex())
				}))
			} else if err is cachekey.PathLoopError {
				println(json2.encode({
					'error':        json2.Any(err.msg())
					'kind':         json2.Any('PathLoopError')
					'filename_hex': json2.Any(err.filename.bytes().hex())
				}))
			} else {
				println(json2.encode({
					'error': json2.Any(err.msg())
				}))
			}
			continue
		}
		println(result)
	}
}
