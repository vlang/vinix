// SPDX-License-Identifier: GPL-2.0-or-later
module copycore

import encoding.utf8
import hosttest
import os

fn join(parent string, child string) string {
	return if parent == '' || child.starts_with('/') {
		child
	} else {
		parent.trim_right('/') + '/' + child
	}
}

fn parents(path string) ! {
	if path == '' || os.is_dir(path) { return }
	if path.contains('/') { parents(path.all_before_last('/'))! }
	os.mkdir(path) or {
		if !os.is_dir(path) { return err }
	}
}

fn space(character rune) bool {
	return utf8.is_space(character) || character in [`\x1c`, `\x1d`, `\x1e`, `\x1f`]
}

fn imports(text string) []string {
	mut result := []string{}
	characters := text.replace('\r\n', '\n').replace('\r', '\n').runes()
	mut cursor := 0
	for cursor < characters.len {
		mut start := cursor
		for start < characters.len && space(characters[start]) {
			start++
		}
		cursor = start
		if start + 6 >= characters.len || characters[start..start + 6].string() != 'import'
			|| !space(characters[start + 6]) {
			for cursor < characters.len && characters[cursor] != `\n` { cursor++ }
			cursor++
			continue
		}
		start += 6
		for start < characters.len && space(characters[start]) {
			start++
		}
		if start >= characters.len || !(characters[start] == `_`
			|| (characters[start] >= `A` && characters[start] <= `Z`)
			|| (characters[start] >= `a` && characters[start] <= `z`)) {
			for cursor < characters.len && characters[cursor] != `\n` { cursor++ }
			cursor++
			continue
		}
		mut end := start + 1
		for end < characters.len {
			character := characters[end]
			if !(character in [`_`, `.`] || (character >= `A` && character <= `Z`)
				|| (character >= `a` && character <= `z`) || (character >= `0` && character <= `9`)) {
				break
			}
			end++
		}
		result << characters[start..end].string()
		cursor = end
		for cursor < characters.len && characters[cursor] != `\n` { cursor++ }
		cursor++
	}
	return result
}

fn copy(kernel string, destination string, relative string, mut copied map[string]bool, mut pending []string) ! {
	if relative in copied {
		return
	}
	target := join(destination, relative)
	parents(target.all_before_last('/'))!
	source := join(kernel, relative)
	if os.is_dir(source) {
		return error('Not a source file: ${source}')
	}
	// This producer follows file symlinks and preserves modes and timestamps,
	// matching the old shutil.copy2 inputs to V's allocation-warning scan.
	hosttest.module_copy_tree(source, target)!
	copied[relative] = true
	pending << relative
}

pub fn copy_sources(kernel string, files string, destination string) ![]string {
	mut copied := map[string]bool{}
	mut pending := []string{}
	for relative in hosttest.module_read_text(files)!.split_into_lines() {
		copy(kernel, destination, relative, mut copied, mut pending)!
	}
	for pending.len > 0 {
		relative := pending.pop()
		for name in imports(hosttest.module_read_text(join(destination, relative))!) {
			module_path := name.split('.').filter(it != '').join('/')
			original := join(kernel, module_path)
			if !os.is_dir(original) {
				continue
			}
			already := os.ls(join(destination, module_path)) or { []string{} }
			if already.any(it.ends_with('.v')) {
				continue // Keep the makefile's filtering for an existing module.
			}
			mut names := os.ls(original)!
			names = names.filter(it.ends_with('.v'))
			names.sort()
			for source in names {
				copy(kernel, destination, module_path + '/' + source, mut copied, mut pending)!
			}
		}
	}
	hosttest.module_copy_tree(join(kernel, 'v.mod'), join(destination, 'v.mod'))!
	mut result := copied.keys()
	result.sort()
	return result
}
