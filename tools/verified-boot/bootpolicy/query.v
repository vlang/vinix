// SPDX-License-Identifier: GPL-2.0-or-later
module bootpolicy

import json2
import encoding.hex

fn text(row map[string]json2.Any, name string) !string {
	value := row[name] or { return error('missing query field ' + name) }
	if value is string { return value }
	return error('TypeError: expected string')
}

pub fn query(request string) !string {
	row := json2.decode[map[string]json2.Any](request, strict: true)!
	operation := text(row, 'operation')!
	return match operation {
		'digest' { json2.encode(digest(text(row, 'path')!)!) }
		'check_cmdline' {
			json2.encode(check_cmdline(text(row, 'value')!, text(row, 'verity_token')!)!)
		}
		'pe_info' {
			pe := pe_info(hex.decode(text(row, 'data')!)!, text(row, 'arch')!)!
			'[${pe.field},${pe.signature_size}]'
		}
		'check_kernel' {
			check_kernel(text(row, 'path')!, text(row, 'arch')!)!
			'null'
		}
		'config_text' {
			values := row['module_hashes'] or { return error('missing query field module_hashes') }
			if values !is []json2.Any { return error('TypeError: expected module list') }
			mut hashes := []string{}
			for hash in values as []json2.Any {
				if hash !is string { return error('TypeError: expected module hash') }
				hashes << hash as string
			}
			json2.encode(config_text(text(row, 'kernel_hash')!, hashes, text(row, 'cmdline')!,
				text(row, 'dtb_hash')!, text(row, 'verity_token')!)!)
		}
		'regular_file' { json2.encode(regular_file(text(row, 'path')!)!) }
		else { return error('unknown verified-boot operation ' + operation) }
	}
}

pub fn error_json(err IError) string {
	if err is FileError {
		return '{"error":' + json2.encode(err.msg()) + ',"kind":"OSError","errno":' + err.code().str() + ',"filename":' + json2.encode(err.filename) + '}'
	}
	if err.msg().starts_with('KeyError: ') {
		return json2.encode(map[string]string{
			'error': err.msg()[10..]
			'kind':  'KeyError'
		})
	}
	if err.msg().starts_with('TypeError: ') {
		return json2.encode(map[string]string{
			'error': err.msg()[11..]
			'kind':  'TypeError'
		})
	}
	return json2.encode(map[string]string{
		'error': err.msg()
		'kind':  if err is InvalidBundle { 'InvalidBundle' } else { 'OSError' }
	})
}
