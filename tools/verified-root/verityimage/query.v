// SPDX-License-Identifier: GPL-2.0-or-later
module verityimage

import json2
import strconv
import encoding.hex

// Preserve input integer tokens before the generic decoder can round to f64.
struct Number {
mut:
	raw string
}

fn (mut n Number) from_json_number(raw string) ! { n.raw = raw }

type Value = []Value | bool | Number | map[string]Value | string | json2.Null

fn text(value Value) !string {
	if value is string { return value }
	return error('TypeError: expected string')
}

fn block_count(value Value) !u64 {
	if value is Number {
		if value.raw.len > 0 && value.raw.bytes().all(it >= `0` && it <= `9`) {
			return strconv.parse_uint(value.raw, 10, 64) or { return invalid('data block count must be a positive, bounded integer') }
		}
	}
	return invalid('data block count must be a positive, bounded integer')
}

fn digest_text(value Value) !string {
	if value !is string {
		return invalid('root hash must be exactly 64 lowercase hexadecimal digits')
	}
	root_hash(value as string)!
	return value as string
}

fn device_text(value Value) !string {
	if value !is string { return invalid('device must be an exact /dev block-device path') }
	return device_name(value as string)!
}

fn item(row map[string]Value, name string) !Value {
	return row[name] or { return error('KeyError: ' + name) }
}

pub fn query(request string) !string {
	row := json2.decode[map[string]Value](request, strict: true)!
	operation := text(item(row, 'operation')!)!
	match operation {
		'layout' {
			levels := layout(block_count(item(row, 'data_blocks')!)!)!
			return json2.encode(levels.map([it.offset, it.count]))
		}
		'total_blocks' { return total_blocks(block_count(item(row, 'data_blocks')!)!)!.str() }
		'root_hash' {
			value := item(row, 'value')!
			if value !is string {
				return invalid('root hash must be exactly 64 lowercase hexadecimal digits')
			}
			return json2.encode(root_hash(text(value)!)!.hex())
		}
		'device_name' {
			value := item(row, 'value')!
			if value !is string { return invalid('device must be an exact /dev block-device path') }
			return json2.encode(device_name(text(value)!)!)
		}
		'command_line' {
			blocks := block_count(item(row, 'data_blocks')!)!
			layout(blocks)!
			digest := digest_text(item(row, 'digest')!)!
			return json2.encode(command_line(device_text(item(row, 'device')!)!, blocks, digest)!)
		}
		'parse_command_line' {
			value := item(row, 'token')!
			if value !is string { return error('TypeError: expected string or bytes-like object') }
			policy := parse_command_line(value as string)!
			return '[' + json2.encode(policy.device) + ',' + policy.data_blocks.str() + ',' + json2.encode(policy.digest) + ']'
		}
		'regular' { return json2.encode(regular(text(item(row, 'path')!)!)!) }
		'hash_block' {
			return json2.encode(hash_block(hex.decode(text(item(row, 'data')!)!)!).hex())
		}
		'verify' {
			digest := digest_text(item(row, 'digest')!)!
			blocks := block_count(item(row, 'data_blocks')!)!
			verify(text(item(row, 'path')!)!, blocks, digest)!
			return 'null'
		}
		'build' {
			padding := item(row, 'pad')!
			if padding !is bool { return error('TypeError: pad must be boolean') }
			return json2.encode(build(text(item(row, 'source')!)!, text(item(row, 'output')!)!, padding as bool)!)
		}
		else { return error('unknown verified-root operation ' + operation) }
	}
}

pub fn error_json(err IError) string {
	if err.msg().starts_with('TypeError: ') {
		return json2.encode(map[string]string{'error': err.msg()[11..], 'kind': 'TypeError'})
	}
	if err is FileError {
		return '{"error":' + json2.encode(err.msg()) + ',"kind":"OSError","errno":' + err.code().str() + ',"filename":' + json2.encode(err.filename) + ',"filename2":' + json2.encode(err.filename2) + '}'
	}
	return json2.encode(map[string]string{
		'error': err.msg()
		'kind':  if err is InvalidImage { 'InvalidImage' } else { 'OSError' }
	})
}
