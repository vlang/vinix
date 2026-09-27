// SPDX-License-Identifier: GPL-2.0-or-later
// Files preferences and tags. Kept in the user's home so separate Files
// windows see the same choices after they are reopened.
module main

import encoding.hex

const files_settings_filename = '.vinix-files-settings'
const files_settings_limit = 1024 * 1024
const files_tag_limit = 32

struct FilesTag {
mut:
	id       int
	name     string
	color    u32
	favorite bool
	sidebar  bool = true
}

struct FilesSettings {
mut:
	show_hidden  bool
	tint_folders bool = true
	tags         []FilesTag
	assignments  map[string][]int
	next_tag_id  int = 10
}

fn default_files_settings() FilesSettings {
	return FilesSettings{
		tags:        [
			FilesTag{ id: 0, name: 'Red', color: 0xff595e, favorite: true },
			FilesTag{ id: 1, name: 'Orange', color: 0xffa044, favorite: true },
			FilesTag{ id: 2, name: 'Yellow', color: 0xffd84a, favorite: true },
			FilesTag{ id: 3, name: 'Green', color: 0x59cc74, favorite: true },
			FilesTag{ id: 4, name: 'Blue', color: 0x4896f2, favorite: true },
			FilesTag{ id: 5, name: 'Purple', color: 0xc864dc, favorite: true },
			FilesTag{ id: 6, name: 'Gray', color: 0xa0a1a6, favorite: true },
			FilesTag{ id: 7, name: 'Work', color: 0x4896f2 },
			FilesTag{ id: 8, name: 'Home', color: 0x59cc74 },
			FilesTag{ id: 9, name: 'Important', color: 0xff595e },
		]
		assignments: map[string][]int{}
	}
}

fn files_settings_path(home string) string {
	return '${home}/${files_settings_filename}'
}

fn files_settings_bool(value string) bool {
	return value == '1'
}

fn load_files_settings(home string) FilesSettings {
	mut settings := default_files_settings()
	path := files_settings_path(home)
	defer { unsafe { path.free() } }
	info := desktop_stat(path) or { return settings }
	if info.is_dir || info.size == 0 || info.size > files_settings_limit {
		return settings
	}
	mut buffer := []u8{len: int(info.size)}
	defer { unsafe { buffer.free() } }
	got := desktop_read_file(path, buffer.data, info.size)
	if got <= 0 {
		return settings
	}
	contents := buffer[..int(got)].bytestr()
	defer { unsafe { contents.free() } }
	mut loaded_tags := []FilesTag{}
	mut loaded_items := map[string][]int{}
	mut version_ok := false
	for line in contents.split_into_lines() {
		parts := line.split('\t')
		if parts.len == 2 && parts[0] == 'version' && parts[1] == '1' {
			version_ok = true
		} else if parts.len == 2 && parts[0] == 'hidden' {
			settings.show_hidden = files_settings_bool(parts[1])
		} else if parts.len == 2 && parts[0] == 'tint' {
			settings.tint_folders = files_settings_bool(parts[1])
		} else if parts.len == 6 && parts[0] == 'tag' && loaded_tags.len < files_tag_limit {
			name_bytes := hex.decode(parts[2]) or { continue }
			name := name_bytes.bytestr()
			if name.len == 0 || name.len > 64 {
				continue
			}
			id := parts[1].int()
			if id < 0 || id > 100000 {
				continue
			}
			loaded_tags << FilesTag{
				id:       id
				name:     name
				color:    u32(parts[3].int())
				favorite: files_settings_bool(parts[4])
				sidebar:  files_settings_bool(parts[5])
			}
			if id >= settings.next_tag_id {
				settings.next_tag_id = id + 1
			}
		} else if parts.len == 3 && parts[0] == 'item' {
			path_bytes := hex.decode(parts[1]) or { continue }
			item_path := path_bytes.bytestr()
			id := parts[2].int()
			if item_path.starts_with('/') && id >= 0 {
				mut assigned := loaded_items[item_path] or { []int{} }
				if !assigned.contains(id) {
					assigned << id
					loaded_items[item_path] = assigned
				}
			}
		}
	}
	if version_ok {
		settings.tags = loaded_tags
		settings.assignments = loaded_items
	}
	return settings
}

fn (s &FilesSettings) save(home string) bool {
	mut data := 'version\t1\nhidden\t${int(s.show_hidden)}\ntint\t${int(s.tint_folders)}\n'
	for tag in s.tags {
		encoded := hex.encode(tag.name.bytes())
		data += 'tag\t${tag.id}\t${encoded}\t${tag.color}\t${int(tag.favorite)}\t${int(tag.sidebar)}\n'
	}
	for path, ids in s.assignments {
		encoded := hex.encode(path.bytes())
		for id in ids {
			data += 'item\t${encoded}\t${id}\n'
		}
	}
	path := files_settings_path(home)
	defer { unsafe { path.free() } }
	return desktop_write_file(path, data.str, u64(data.len))
}

fn (s &FilesSettings) tag_index(id int) int {
	for index, tag in s.tags {
		if tag.id == id {
			return index
		}
	}
	return -1
}

fn (s &FilesSettings) first_color(path string) u32 {
	ids := s.assignments[path] or { return 0 }
	for id in ids {
		index := s.tag_index(id)
		if index >= 0 {
			return s.tags[index].color
		}
	}
	return 0
}

fn (s &FilesSettings) tagged_paths(id int) []string {
	mut paths := []string{}
	for path, ids in s.assignments {
		if ids.contains(id) && desktop_lstat(path) != none {
			paths << path.clone()
		}
	}
	paths.sort()
	return paths
}

fn (mut s FilesSettings) toggle_tag(path string, id int) {
	if s.tag_index(id) < 0 {
		return
	}
	mut ids := s.assignments[path] or { []int{} }
	index := ids.index(id)
	if index >= 0 {
		ids.delete(index)
	} else {
		ids << id
	}
	if ids.len == 0 {
		s.assignments.delete(path)
	} else {
		s.assignments[path] = ids
	}
}

fn (mut s FilesSettings) remove_tag(index int) {
	if index < 0 || index >= s.tags.len {
		return
	}
	id := s.tags[index].id
	s.tags.delete(index)
	for path, old_ids in s.assignments {
		mut ids := old_ids.clone()
		at := ids.index(id)
		if at >= 0 {
			ids.delete(at)
			if ids.len == 0 {
				s.assignments.delete(path)
			} else {
				s.assignments[path] = ids
			}
		}
	}
}

fn files_tag_path_inside(path string, directory string) bool {
	return path == directory || path.starts_with('${directory}/')
}

fn (mut s FilesSettings) remove_path(path string) {
	for candidate, _ in s.assignments {
		if files_tag_path_inside(candidate, path) {
			s.assignments.delete(candidate)
		}
	}
}

fn (mut s FilesSettings) rebase_path(old_path string, new_path string) {
	mut replacements := map[string][]int{}
	for candidate, ids in s.assignments {
		if files_tag_path_inside(candidate, old_path) {
			suffix := candidate[old_path.len..]
			replacements[new_path + suffix] = ids.clone()
			s.assignments.delete(candidate)
		}
	}
	for candidate, ids in replacements {
		s.assignments[candidate] = ids
	}
}

fn (mut s FilesSettings) copy_path(old_path string, new_path string) {
	mut additions := map[string][]int{}
	for candidate, ids in s.assignments {
		if files_tag_path_inside(candidate, old_path) {
			suffix := candidate[old_path.len..]
			additions[new_path + suffix] = ids.clone()
		}
	}
	for candidate, ids in additions {
		s.assignments[candidate] = ids
	}
}
