// SPDX-License-Identifier: GPL-2.0-or-later
module androidrun

import androidhost as ah
import androidtools
import boothost
import encoding.hex
import hosttest
import json2
import os
import sourcecommand
import cachecli

#include <unistd.h>

fn C.link(&char, &char) int

fn glob_parts(directory string, pieces []string, index int) ![]string {
	if index == pieces.len {
		return if os.exists(directory) || os.is_link(directory) { [directory] } else { []string{} }
	}
	if !os.is_dir(directory) { return []string{} }
	mut result := []string{}
	for name in os.ls(directory)! {
		if name.match_glob(pieces[index]) {
			result << glob_parts(join([directory, name]), pieces, index + 1)!
		}
	}
	return result
}

fn type_name(value ah.Value) string {
	return match value {
		string { 'str' }
		bool { 'bool' }
		json2.Null { 'NoneType' }
		[]ah.Value { 'list' }
		map[string]ah.Value { 'dict' }
		ah.Number {
			if value.text.contains_any('.eE') || value.text in ['nan', 'inf', '-inf'] {
				'float'
			} else {
				'int'
			}
		}
		else { 'int' }
	}
}

fn replace_utf8(bytes []u8) string {
	// Decode malformed serial diagnostics without discarding valid text.
	mut result := []u8{}
	mut index := 0
	for index < bytes.len {
		first := bytes[index]
		width := if first < 0x80 {
			1
		} else if first >= 0xc2 && first <= 0xdf {
			2
		} else if first >= 0xe0 && first <= 0xef {
			3
		} else if first >= 0xf0 && first <= 0xf4 {
			4
		} else {
			0
		}
		mut consumed := 1
		if width > 0 {
			for position in 1 .. width {
				if index + position >= bytes.len { break }
				value := bytes[index + position]
				if value < 0x80 || value > 0xbf || (position == 1 && ((first == 0xe0 && value < 0xa0) || (first == 0xed && value > 0x9f) || (first == 0xf0 && value < 0x90) || (first == 0xf4 && value > 0x8f))) {
					break
				}
				consumed++
			}
		}
		if width > 0 && consumed == width {
			result << bytes[index..index + width]
			index += width
		} else {
			result << '\ufffd'.bytes()
			index += consumed
		}
	}
	return result.bytestr()
}

fn (mut context Context) primitive(operation string, row map[string]ah.Value) !ah.Value {
	return match operation {
		'path' { context.path(row)! }
		'join' { ah.Value(join(ah.field(row, 'parts').items().map(it.text()))) }
		'attribute' { context.args[text(row, 'name')] or { null() } }
		'args_set' {
			context.args[text(row, 'name')] = ah.field(row, 'value')
			null()
		}
		'args_append' {
			name := text(row, 'name')
			mut values := ah.field(context.args, name).items().clone()
			values << ah.field(row, 'value')
			context.args[name] = ah.Value(values)
			null()
		}
		'args_item' {
			name := text(row, 'name')
			mut values := ah.field(context.args, name).object().clone()
			values[text(row, 'key')] = ah.field(row, 'value')
			context.args[name] = ah.Value(values)
			null()
		}
		'str_attribute' {
			value := ah.field(context.args, text(row, 'name'))
			ah.Value(ordinary(if 'index' in row {
				value.items()[int(number(ah.field(row, 'index'))!)]
			} else {
				value
			}))
		}
		'attribute_bytes' { ah.Value(os.read_bytes(text(context.args, text(row, 'name')))!.hex()) }
		'parser_error' { return androidtools.InputError{ message: text(row, 'message') } }
		'print' {
			message := ordinary(ah.field(row, 'data'))
			if truth(ah.field(row, 'stderr')) {
				eprintln(message)
				flush_stderr()
			} else {
				println(message)
				flush_stdout()
			}
			null()
		}
		'environ' {
			mut environment := map[string]ah.Value{}
			for key, value in os.environ() { environment[key] = ah.Value(value) }
			ah.Value(environment)
		}
		'platform' { ah.Value(if os.user_os() == 'macos' { 'Darwin' } else { 'Linux' }) }
		'strip' { ah.Value(boothost.unicode_strip(text(row, 'data'))) }
		'import' { return error('native Android runner has no interpreter import primitive') }
		'length' { ah.Value(text(row, 'data').runes().len) }
		'read_bytes' { ah.Value(os.read_bytes(text(row, 'path'))!.hex()) }
		'json_loads' { load_json(text(row, 'data'))! }
		'json_dumps' {
			ah.Value(dump_json(ah.field(row, 'data'), if 'indent' in ah.field(row, 'options').object() {
				int(number(ah.field(ah.field(row, 'options').object(), 'indent'))!)
			} else {
				-1
			}))
		}
		'bytes_decode' {
			bytes := hex.decode(text(row, 'data'))!
			if text(ah.field(row, 'options').object(), 'errors') == 'replace' {
				ah.Value(replace_utf8(bytes))
			} else {
				hosttest.module_decode_utf8(bytes.bytestr())!
				ah.Value(bytes.bytestr())
			}
		}
		'bytes_int' {
			digits := hex.decode(text(row, 'data'))!.bytestr().trim_left('0')
			ah.Value(ah.Number{if digits == '' { '0' } else { digits }})
		}
		'type_name' { ah.Value(type_name(ah.field(row, 'value'))) }
		'which' { ah.Value(os.find_abs_path_of_executable(text(row, 'name')) or { '' }) }
		'run' {
			argv := ah.field(row, 'arguments').items().map(it.text())
			if argv.len == 0 || argv[0].all_after_last('/') in ['python', 'python3'] {
				return error('native runner requires a V command entrypoint')
			}
			if context.command_hook != unsafe { nil } {
				context.command_hook(argv, context.command_context)!
				return null()
			}
			result := sourcecommand.run_preferred(argv, os.environ(), cachecli.cancelled, '')!
			if result.status != 0 { return ah.command_failure(argv, result.status, false, '') }
			null()
		}
		'copy2' {
			args := ah.field(row, 'arguments').items().map(it.text())
			destination := if os.is_dir(args[1]) {
				join([args[1], args[0].all_after_last('/')])
			} else {
				args[1]
			}
			hosttest.module_copy_file_preserving_stat(args[0], destination)!
			ah.Value(destination)
		}
		'rmtree' {
			hosttest.remove_work_dir(ah.field(row, 'arguments').items()[0].text())!
			null()
		}
		'readlink' { ah.Value(os.readlink(ah.field(row, 'arguments').items()[0].text())!) }
		'link' {
			args := ah.field(row, 'arguments').items().map(it.text())
			if C.link(args[0].str, args[1].str) != 0 { return os.error_posix() }
			null()
		}
		'inode_reset' {
			context.inodes.clear()
			null()
		}
		'inode_set' {
			context.inodes[ah.encode(ah.field(row, 'key'))] = text(row, 'path')
			null()
		}
		'inode_contains' { ah.Value(ah.encode(ah.field(row, 'key')) in context.inodes) }
		'inode_link' {
			source := context.inodes[ah.encode(ah.field(row, 'key'))] or { return error('missing source inode') }
			if C.link(source.str, text(row, 'path').str) != 0 { return os.error_posix() }
			null()
		}
		'open_read' {
			file := os.open(text(row, 'path'))!
			id := context.next_file
			context.next_file++
			context.files[id] = file
			ah.Value(id)
		}
		'read_handle' {
			id := int(number(ah.field(row, 'id'))!)
			mut file := context.files[id] or { return error('retired native file handle') }
			limit := int(number(ah.field(row, 'limit'))!)
			mut bytes := []u8{len: limit}
			count := file.read(mut bytes) or { if err is os.Eof { 0 } else { return err } }
			ah.Value(bytes[..count].hex())
		}
		'exit_handle' {
			id := int(number(ah.field(row, 'id'))!)
			mut file := context.files[id] or { return error('retired native file handle') }
			context.files.delete(id)
			file.close()
			ah.Value(false)
		}
		'iterdir', 'glob', 'rglob' {
			directory := text(row, 'path')
			if operation == 'iterdir' {
				ah.Value(paths(directory, false)!.map(ah.Value(it)))
			} else {
				pattern := ah.field(row, 'arguments').items()[0].text()
				mut matches := []string{}
				if operation == 'glob' {
					matches = glob_parts(directory, pattern.split('/'), 0)!
				} else {
					for path in paths(directory, true)! {
						if path.all_after_last('/').match_glob(pattern) { matches << path }
					}
				}
				ah.Value(matches.map(ah.Value(it)))
			}
		}
		'stat' {
			state := os.stat(text(row, 'path'))!
			mut fields := map[string]ah.Value{}
			for name in ah.field(row, 'fields').items().map(it.text()) {
				fields[name] = match name {
					'st_size' { ah.Value(state.size) }
					'st_dev' { ah.Value(state.dev) }
					'st_ino' { ah.Value(state.inode) }
					'st_nlink' { ah.Value(state.nlink) }
					else { return error('unsupported stat field') }
				}
			}
			ah.Value(fields)
		}
		'api' {
			value := if text(row, 'name') == 'prepare' {
				if context.prepare_hook != unsafe { nil } {
					context.prepare_hook(mut context)!
				} else {
					context.call('prepare', context.args)!
				}
			} else if text(row, 'name') == 'run' {
				pairs := ah.field(row, 'arguments').items()
				ah.Value(context.run_session(if pairs.len > 0 {
					pairs[0].items()[1]
				} else {
					null()
				})!)
			} else {
				return error('unknown native runner API')
			}
			ah.Value({
				'value': value
				'args':  ah.Value(context.args)
			})
		}
		'function' {
			name := text(row, 'name')
			args := ah.field(row, 'arguments').items()
			if name == 'needed_libraries' {
				request := ah.Value({
					'operation': ah.Value(name)
					'path_hex':  ah.Value(args[0].items()[1].text().bytes().hex())
				})
				json2.decode[ah.Value](ah.query(ah.encode(request))!, strict: true)!
			} else {
				return error('unsupported native runner function: ' + name)
			}
		}
		'roblox_validate' { context.validate_roblox(text(row, 'staging'), text(row, 'runtime'))! }
		'tar_open', 'tar_next', 'tar_extract', 'tar_info', 'tar_add', 'tar_exit' {
			context.tar_primitive(operation, row)!
		}
		else { return error('unsupported native Android runner primitive: ' + operation) }
	}
}
