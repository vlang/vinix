// SPDX-License-Identifier: GPL-2.0-only
module stagehost

import json2

pub fn native_v3_source(text string) !string {
	prefix := '// Copyright (c) '
	suffix := '. All rights reserved.'
	if !text.starts_with(prefix) { return text }
	first_end := text.index('\n') or { return text }
	first := text[..first_end]
	if first.len <= prefix.len + suffix.len || !first.ends_with(suffix) { return text }
	following := '\n// Use of this source code is governed by a GPL v2 license\n' +
		'// that can be found in the LICENSE file.\n\n'
	if !text[first_end..].starts_with(following + '// SPDX-License-Identifier:') { return text }
	return text[first_end + following.len..]
}

pub fn v_string(text string) string {
	return "'" + text.replace('\\', '\\\\').replace("'", "\\'").replace('$', '\\$').replace('\t', '\\t').replace('\r', '\\r') + "'"
}

pub fn strip_main(text string, origin string) !string {
	matches := regex(main_pattern, text, 8)!
	if matches.len == 0 {
		return failure(origin + ': no `fn main()` to remove; is this a ui2 example?')
	}
	if matches.len > 1 { return failure(origin + ': more than one `fn main()`') }
	first := matches[0].as_map()
	trailing := text[first['end']!.int()..]
	if trailing.contains('\nfn ') || trailing.contains('\npub fn ') {
		return failure(origin + ': `fn main()` is not the last function; cannot cut to end')
	}
	header := '// Staged from ' + origin + ' by desktop/tools/stage_app.py.\n' +
		"// The example's `fn main()` is removed — it opens a platform window\n" +
		'// and blocks, which is the job the desktop is doing instead. The rest\n' +
		"// is the example's own source, unmodified.\n"
	mut body := decode(primitive('strip', [text[..first['start']!.int()]])!.str())! + '\n'
	declarations := regex(embedded_view_pattern, body, 8)!
	for declaration in declarations.reverse() {
		row := declaration.as_map()
		name := decode(row['groups']!.as_array()[0].str())!
		// Identifier characters cannot contain regex syntax. Word boundaries retain
		// the original caller's Unicode table through the stdlib regex primitive.
		if regex('\\b' + name + '\\b', body, 0)!.len == 1 {
			body = body[..row['start']!.int()] + body[row['end']!.int()..]
		}
	}
	if !body.contains('ui2.') { body = body.replace_once('\nimport ui2\n', '\nimport ui2 as _\n') }
	return header + body
}

pub fn stage_desktop(staging string, desktop string) ! {
	mut files := names(desktop)!
	files.sort()
	for name in files {
		source := join([desktop, name])!
		if !test('isfile', source)! { continue }
		if !name.ends_with('.v') && !name.ends_with('.h') && !name.ends_with('.vml') { continue }
		destination := join([staging, name])!
		remove_existing(destination)!
		if name.ends_with('.v') {
			text := read(source, '')!
			compatible := native_v3_source(text)!
			if compatible != text {
				write(destination, compatible, '')!
				continue
			}
		}
		primitive('symlink', [path('abspath', [source])!, destination])!
	}
}

pub fn stage_translations(staging string, desktop string) ! {
	directory := join([desktop, 'translations'])!
	mut files := names(directory)!.filter(it.ends_with('.tr'))
	files.sort()
	if files.len == 0 { return failure(directory + ': no .tr translation files') }
	mut out := [
		'// Generated from desktop/translations/*.tr by desktop/tools/stage_app.py.',
		'// Edit the .tr files, not this.',
		'module main',
		'',
		'const desktop_translation_files = {',
	]
	for name in files {
		text := read(join([directory, name])!, 'utf-8')!
		if text.contains('\r') { return failure(name + ': use LF line endings') }
		out << '\t' + v_string(name) + ': ['
		for line in text.trim_right('\n').split('\n') { out << '\t\t' + v_string(line) + ',' }
		out << "\t].join('\\n') + '\\n'"
	}
	out << ['}', '']
	write(join([staging, 'translations_data.v'])!, out.join('\n'), 'utf-8')!
}

pub fn stage_icon_data(staging string, desktop string) ! {
	directory := join([desktop, 'assets'])!
	mut files := names(directory) or {
		if err is BindingError && (err.value['os_error'] or { json2.Any(false) }).bool() {
			return failure(directory + ': cannot read icon artwork: ' + err.msg())
		}
		return err
	}
	files = files.filter(it.ends_with('.qoi'))
	files.sort()
	if files.len == 0 { return failure(directory + ': no .qoi icon artwork') }
	mut out := icon_lines_0.clone()
	mut icons := [][2]string{}
	for name in files {
		stem := name[..name.len - 4]
		if !full('[A-Za-z_][A-Za-z_0-9]*', stem)! {
			return failure(name + ': icon filename is not a C identifier')
		}
		source := join([directory, name])!
		data := read_bytes(source) or {
			if err is BindingError && (err.value['os_error'] or { json2.Any(false) }).bool() {
				return failure(source + ': cannot read icon artwork: ' + err.msg())
			}
			return err
		}
		if data.len == 0 { return failure(source + ': empty icon artwork') }
		symbol := 'vinix_app_icon_' + stem
		icons << [stem, symbol]!
		out << 'static const unsigned char ' + symbol + '[] = {'
		for offset := 0; offset < data.len; offset += 16 {
			mut bytes := []string{}
			for value in data[offset..if offset + 16 > data.len { data.len } else { offset + 16 }] {
				bytes << '0x' + value.hex()
			}
			out << '    ' + bytes.join(', ') + ','
		}
		out << icon_lines_1
	}
	out << icon_lines_2
	for icon in icons {
		stem, symbol := icon[0], icon[1]
		out << ['    if (strcmp(name, "' + stem + '") == 0) {',
			'        if (size != NULL) *size = sizeof(' + symbol + ');',
			'        return (void *)' + symbol + ';', '    }']
	}
	out << icon_lines_3
	destination := join([staging, 'app_icon_data.h'])!
	remove_existing(destination)!
	write(destination, out.join('\n'), 'ascii')!
}

pub fn stage_example(staging string, example string) ! {
	name := path('basename', [path('normpath', [example])!])!
	main_path := join([example, 'main.v'])!
	if !test('isfile', main_path)! { return failure(example + ': no main.v') }
	text := read(main_path, '')!
	origin := join(['third_party/ui2/examples', name, 'main.v'])!
	// Original open(w) truncates before strip_main can reject an example.
	destination := join([staging, 'app_' + name + '.v'])!
	write_after_open(destination, 'strip_main', [text, origin])!
	mut files := names(example)!
	files.sort()
	for asset in files {
		if asset.ends_with('.v') { continue }
		source := join([example, asset])!
		if test('isfile', source)! { primitive('copy', [source, join([staging, asset])!])! }
	}
}

pub fn app_main(arguments []string) ! {
	if arguments.len < 3 {
		return failure('stage_app.py <staging-dir> <desktop-dir> <example-dir>...')
	}
	staging, desktop := arguments[0], arguments[1]
	if test('isdir', staging)! { primitive('rmtree', [staging])! }
	mkdir(staging, false)!
	stage_desktop(staging, desktop)!
	stage_translations(staging, desktop)!
	stage_icon_data(staging, desktop)!
	for example in arguments[2..] { stage_example(staging, example)! }
	primitive('print', ['    staged ' + (arguments.len - 2).str() + ' example(s) into ' + staging])!
}
