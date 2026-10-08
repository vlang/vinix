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
		'build_tree' {
			mut inputs := []cachekey.BuildInput{}
			for value in (row['inputs'] or { return error('Missing inputs') }).as_array() {
				item := value.as_map()
				inputs << cachekey.BuildInput{bytes_field(item, 'path')!, bytes_field(item, 'label')!, item['metadata'].bool(), item['policy'].str()}
			}
			json2.encode(cachekey.build_tree_key(bytes_field(row, 'namespace')!, bytes_list(row, 'fields')!, inputs)!)
		}
		'ignored_source' {
			json2.encode(cachekey.ignored_source(bytes_field(row, 'path')!, row['policy'].str())!)
		}
		'module_subdirs' { json2.encode(cachekey.module_subdirs(bytes_field(row, 'path')!)!) }
		'subdirs_text' { json2.encode(cachekey.subdirs_text(bytes_field(row, 'text')!)) }
		'office_imports' { json2.encode(cachekey.office_imports(bytes_field(row, 'text')!)) }
		'resolved_tool' {
			json2.encode(cachekey.resolved_tool(bytes_field(row, 'path')!)!.bytes().hex())
		}
		'office_source_files' {
			json2.encode(cachekey.office_source_files(bytes_field(row, 'path')!)!.map(it.bytes().hex()))
		}
		'office_modules' {
			json2.encode(cachekey.office_modules(bytes_field(row, 'office')!, bytes_field(row, 'app')!)!)
		}
		'office_key' {
			json2.encode(cachekey.office_key(bytes_field(row, 'office')!, bytes_field(row, 'shared')!, bytes_field(row, 'app')!)!)
		}
		'office_shared' {
			input := cachekey.OfficeInputs{
				repo:          bytes_field(row, 'repo')!
				builder:       bytes_field(row, 'builder')!
				office:        bytes_field(row, 'office')!
				ui2:           bytes_field(row, 'ui2')!
				v:             bytes_field(row, 'v')!
				vroot:         bytes_field(row, 'vroot')!
				arch:          bytes_field(row, 'arch')!
				target:        bytes_field(row, 'target')!
				clang:         bytes_field(row, 'clang')!
				strip:         bytes_field(row, 'strip')!
				clang_headers: bytes_field(row, 'clang_headers')!
				sysroot:       bytes_field(row, 'sysroot')!
				gcclib:        bytes_field(row, 'gcclib')!
				cc_shim:       bytes_field(row, 'cc_shim')!
				llvm:          bytes_field(row, 'llvm')!
			}
			json2.encode(cachekey.office_shared(input)!)
		}
		'staging_key' {
			json2.encode(cachekey.staging_key(bytes_field(row, 'root')!, bytes_list(row, 'values')!, bytes_list(row, 'sources')!, bytes_list(row, 'metadata')!, bytes_list(row, 'vlib')!)!)
		}
		'staging_complete' {
			json2.encode(cachekey.staging_complete(bytes_field(row, 'staging')!, bytes_list(row, 'required')!, bytes_list(row, 'executable')!, bytes_list(row, 'any')!)!)
		}
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
			if err is cachekey.TextDecodeError {
				println(json2.encode({
					'error': json2.Any(err.reason)
					'kind':  json2.Any('UnicodeDecodeError')
					'data':  json2.Any(err.data.hex())
					'start': json2.Any(err.start)
					'end':   json2.Any(err.end)
				}))
			} else if err is cachekey.FileError {
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
