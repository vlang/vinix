// SPDX-License-Identifier: GPL-2.0-or-later
module utilitysource

import encoding.utf8
import os

pub const tests = ['preview_app', 'console_app', 'system_information', 'utilities',
	'archive_app', 'disk_utility', 'backup_app', 'notes_app', 'reminders_app',
	'grapher_app', 'calculator_features', 'color_meter', 'clock_utility', 'native_close',
	'start_menu_paging', 'taskbar_pinning', 'quick_launch', 'dictionary', 'editor_workflow',
	'editor_selection', 'calendar_ics', 'calendar_search', 'disk_usage_features',
	'files_trash', 'i18n', 'text_copy_client', 'terminal_selection']

pub fn materialize(directory string) ! {
	for name in os.ls(directory)! {
		path := directory + '/' + name
		if os.is_link(path) && os.is_file(path) {
			data := os.read_bytes(path)!
			os.rm(path)!
			os.write_file_array(path, data)!
		}
	}
}

fn lines(text string) []string {
	mut result := []string{}
	mut start := 0
	mut position := 0
	for value in text.runes() {
		length := value.str().len
		if value in [rune(10), 11, 12, 28, 29, 30, 133, 0x2028, 0x2029] {
			result << text[start..position]
			start = position + length
		}
		position += length
	}
	if start < text.len { result << text[start..] }
	return result
}

pub fn merge(root string, destination string, names []string) ! {
	mut imports := []string{}
	mut bodies := []string{}
	for name in names {
		text := os.read_file(root + '/desktop/tools/tests/' + name + '_test.v')!
		if !utf8.validate_str(text) { return error('invalid UTF-8 utility source') }
		mut body := []string{}
		for line in lines(text.replace('\r\n', '\n').replace('\r', '\n')) {
			if line.starts_with('module ') { continue }
			if line.starts_with('import ') {
				if line !in imports { imports << line }
			} else { body << line }
		}
		bodies << body.join('\n')
	}
	imports.sort()
	os.write_file(destination, 'module main\n' + imports.join('\n') + '\n\n' + bodies.join('\n\n'))!
}
