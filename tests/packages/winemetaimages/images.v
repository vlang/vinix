// SPDX-License-Identifier: GPL-2.0-or-later
// Exact metadata-only aliases of previously admitted ordinary images.
module winemetaimages

import os
import tests.packages.winehostimages
import tests.packages.winereadclosure

const linker = '/opt/homebrew/bin/ld64.lld'

pub struct Aliases {
pub mut:
	links map[string]string
	images map[string]string
}

pub fn capture(pins map[string]string, baseline winehostimages.Baseline) !Aliases {
	canonical := os.real_path(linker)
	if !baseline.images.any(it.path == canonical && it.sha256 != '' && pins[it.path] == it.sha256) {
		return error('metadata linker image pin absent')
	}
	mut result := Aliases{}
	mut selected := {linker: os.real_path(linker)}
	for image in baseline.images {
		if winereadclosure.system(image.path) { continue }
		if image.sha256 == '' || pins[image.path] != image.sha256 { return error('metadata image pin absent') }
		if !image.path.starts_with('/opt/homebrew/Cellar/') { return error('unsupported metadata image namespace') }
		parts := image.path.all_after('/opt/homebrew/Cellar/').split('/')
		if parts.len < 4 { return error('unsupported metadata image profile') }
		names := os.ls(os.dir(image.path))!
		if names.len > 4096 { return error('metadata image alias directory outside bound') }
		for name in names {
			local := os.dir(image.path) + '/' + name
			if os.real_path(local) != image.path { continue }
			selected[local] = image.path
			alias := '/opt/homebrew/opt/' + parts[0] + '/' + parts[2..parts.len - 1].join('/') + '/' + name
			if os.real_path(alias) == image.path { selected[alias] = image.path }
			if selected.len > 128 { return error('metadata image aliases outside bound') }
		}
	}
	mut pending := selected.keys(); pending.sort()
	mut depth := map[string]int{}
	mut cursor := 0
	for cursor < pending.len {
		path := pending[cursor]; cursor++
		expected := selected[path]
		if expected !in pins || os.real_path(path) != expected || os.lstat(expected)!.get_filetype() != .regular {
			return error('metadata image alias target differs')
		}
		result.images[path] = expected
		parts := path[1..].split('/')
		mut prefix := ''
		for index, part in parts {
			prefix += '/' + part
			if os.lstat(prefix)!.get_filetype() != .symbolic_link { continue }
			target := os.readlink(prefix)!
			result.links[prefix] = target
			mut expanded := os.norm_path(if os.is_abs_path(target) { target } else { os.dir(prefix) + '/' + target })
			if index + 1 < parts.len { expanded += '/' + parts[index + 1..].join('/') }
			if depth[path] >= 16 || result.links.len > 128 { return error('metadata alias expansion outside bound') }
			if expanded !in selected {
				selected[expanded] = expected; pending << expanded; depth[expanded] = depth[path] + 1
				if pending.len > 128 { return error('metadata image aliases outside bound') }
			} else if selected[expanded] != expected { return error('metadata alias targets disagree') }
		}
	}
	return result
}

pub fn paths(aliases Aliases, capabilities map[string]string) []string {
	mut selected := map[string]bool{}
	for path in [...aliases.links.keys(), ...aliases.images.keys()] {
		if path !in capabilities { selected[path] = true }
	}
	mut result := selected.keys(); result.sort()
	return result
}

