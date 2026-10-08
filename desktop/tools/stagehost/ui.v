// SPDX-License-Identifier: GPL-2.0-only
module stagehost

import json2

const subdirs_pattern = '\\bsubdirs\\s*:\\s*\\[([^]]*)\\]'
const entries_pattern = '[\'"]([^\'"]+)[\'"]'

pub fn staged_source(name string, source string) !json2.Any {
	if name in ['file_dialog_linux.v', 'message_box_linux.v'] {
		return json2.Any(read(source, '')!.replace('os.execute(command)', "os.exec(['/bin/sh', '-c', command])").bytes().hex())
	}
	if name != 'vml_embed.v' { return json2.Null{} }
	mut text := read(source, '')!
	text = text.replace('(mut app VmlApp[T])', '(mut vml_app VmlApp[T])').replace('(app &VmlApp[T])', '(vml_app &VmlApp[T])')
	for member in ['control_text', 'control_value', 'events', 'model', 'template', 'text_of', 'value_of'] {
		text = text.replace('app.' + member, 'vml_app.' + member)
	}
	return json2.Any(text.bytes().hex())
}

pub fn symlink_entries(source string, destination string) ! {
	mkdir(destination, true)!
	mut files := names(source)!
	files.sort()
	for name in files {
		if name.ends_with('_tmp.v') { continue }
		upstream := path('abspath', [join([source, name])!])!
		staged := staged_source(name, upstream)!
		target := join([destination, name])!
		if staged is json2.Null {
			primitive('symlink', [upstream, target])!
		} else {
			write(target, decode(staged.str())!, '')!
		}
	}
}

pub fn module_subdirs(text string) ![]string {
	rows := regex(subdirs_pattern, text, 16)!
	if rows.len == 0 { return []string{} }
	body := decode(rows[0].as_map()['groups']!.as_array()[0].str())!
	return regex(entries_pattern, body, 0)!.map(decode(it.as_map()['groups']!.as_array()[0].str())!)
}

pub fn filter_manifest_subdirs(text string) !string {
	rows := regex(subdirs_pattern, text, 16)!
	if rows.len == 0 { return text }
	kept := module_subdirs(text)!.filter(it != 'appkit')
	span := rows[0].as_map()['spans']!.as_array()[0].as_array()
	return text[..span[0].int()] + kept.map("'" + it + "'").join(', ') + text[span[1].int()..]
}

pub fn ui_main(arguments []string) ! {
	if arguments.len != 3 {
		return failure('stage_ui2.py <output-ui2-dir> <source-ui2-dir> <bridge.v>')
	}
	output, source, bridge := path('abspath', [arguments[0]])!, path('abspath', [arguments[1]])!, path('abspath', [arguments[2]])!
	manifest := join([source, 'v.mod'])!
	if !test('isfile', manifest)! { return failure(source + ': ui2 v.mod not found') }
	manifest_text := read(manifest, '')!
	if test('isdir', output)! { primitive('rmtree', [output])! }
	mkdir(output, false)!
	// open(w) happens before the transformation in the original expression.
	target := join([output, 'v.mod'])!
	write_after_open(target, 'filter_manifest', [manifest_text])!
	assets := join([source, 'assets'])!
	if test('exists', assets)! { primitive('symlink', [assets, join([output, 'assets'])!])! }
	for subdir in module_subdirs(manifest_text)! {
		if subdir == 'appkit' { continue }
		upstream, staged := join([source, subdir])!, join([output, subdir])!
		if subdir == 'ui' {
			symlink_entries(upstream, staged)!
			bridge_name := if bridge.ends_with('.c.v') {
				'vinix_headless_backend.c.v'
			} else {
				'vinix_headless_backend.v'
			}
			primitive('copy', [bridge, join([staged, bridge_name])!])!
		} else {
			primitive('symlink', [upstream, staged])!
		}
	}
}
