// SPDX-License-Identifier: Apache-2.0
// V replacement for AOSP build/tools/diff_package_overlays.py.
// Original algorithm: Copyright (C) 2012 The Android Open Source Project.
module artgenerators

import os

struct OverlayConfig {
mut:
	names []string
	values map[string]string
}

fn load_overlays(path string) !OverlayConfig {
	mut config := OverlayConfig{}
	lines := os.read_file(path)!.split_into_lines()
	for raw in lines {
		line := raw.trim_space()
		if line == '' || line.starts_with('#') { continue }
		fields := line.fields()
		name := fields[0]
		if name !in config.values { config.names << name }
		config.values[name] = fields[1..].join(' ')
	}
	return config
}

// Preserve the previous configuration of packages outside a partial build.
// Only CURRENT_OVERLAYS is appended to, matching the original implementation.
pub fn package_overlays(packages string, current string, previous string) ![]string {
	all_packages := os.read_file(packages)!.fields()
	new := load_overlays(current)!
	old := load_overlays(previous)!
	mut changed := []string{}
	mut carry := []string{}
	for name in new.names {
		if name !in old.values || new.values[name] != old.values[name] { changed << name }
	}
	for name in old.names {
		if name !in new.values {
			if name in all_packages { changed << name }
			else { carry << name + ' ' + old.values[name] + '\n' }
		}
	}
	if carry.len > 0 {
		mut file := os.open_append(current)!
		defer { file.close() }
		text := carry.join('')
		if file.write_string(text)! != text.len { return error('short overlay carry-forward write') }
	}
	return changed
}
