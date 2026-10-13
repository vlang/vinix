// SPDX-License-Identifier: GPL-2.0-or-later
module hostfixture

import encoding.base64
import os
import plist
import strings

fn escape(text string) string {
	return text.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')
}

fn xml(value plist.Value, depth int) !string {
	if depth > 64 { return error('plist nesting exceeds limit') }
	indent := '\t'.repeat(depth)
	match value.kind {
		.string { return indent + '<string>' + escape(value.text) + '</string>\n' }
		.integer { return indent + '<integer>' + value.integer.str() + '</integer>\n' }
		.real { return indent + '<real>' + value.real.str() + '</real>\n' }
		.boolean { return indent + if value.boolean { '<true/>\n' } else { '<false/>\n' } }
		.data { return indent + '<data>' + base64.encode(value.data) + '</data>\n' }
		.array {
			mut output := strings.new_builder(128)
			output.write_string(indent + '<array>\n')
			for item in value.values { output.write_string(xml(item, depth + 1)!) }
			output.write_string(indent + '</array>\n')
			return output.str()
		}
		.dictionary {
			mut output := strings.new_builder(256)
			output.write_string(indent + '<dict>\n')
			mut keys := value.fields.keys()
			keys.sort()
			for key in keys {
				output.write_string(indent + '\t<key>' + escape(key) + '</key>\n')
				output.write_string(xml(value.fields[key] or { return error('missing plist field') }, depth + 1)!)
			}
			output.write_string(indent + '</dict>\n')
			return output.str()
		}
	}
}

fn copy_tree(source string, destination string, depth int) ! {
	if depth > 64 { return error('resource directory nesting exceeds limit') }
	state := os.stat(source)!
	if state.get_filetype() == .directory {
		os.mkdir_all(destination)!
		for name in os.ls(source)! { copy_tree(source + '/' + name, destination + '/' + name, depth + 1)! }
	} else if state.get_filetype() == .regular {
		os.cp(source, destination)!
	} else { return error('unsupported resource: ' + source) }
	os.chmod(destination, int(state.mode & 0o7777))!
	os.utime(destination, state.atime, state.mtime)!
}

pub fn game_bundle(source string, bundle string) ! {
	info := plist.parse(os.read_bytes(source + '/NumberTileGame-Info.plist')!)!
	if info.kind != .dictionary { return error('upstream Info.plist is not a dictionary') }
	mut fields := info.fields.clone()
	for key in ['CFBundleDisplayName', 'CFBundleExecutable', 'CFBundleName'] {
		fields[key] = plist.Value{kind:.string, text:'NumberTileGame'}
	}
	fields['CFBundleIdentifier'] = plist.Value{kind:.string, text:'f3nghuang.NumberTileGame'}
	fields['UIRequiredDeviceCapabilities'] = plist.Value{kind:.array, values:[plist.Value{kind:.string, text:'arm64'}]}
	text := '<?xml version="1.0" encoding="UTF-8"?>\n<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n<plist version="1.0">\n' +
		xml(plist.Value{kind:.dictionary, fields:fields}, 0)! + '</plist>\n'
	os.write_file(bundle + '/Info.plist', text)!
	copy_tree(source + '/Base.lproj', bundle + '/Base.lproj', 0)!
}
