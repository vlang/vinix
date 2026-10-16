// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

const stored_root_entry_keys = ['source', 'path']
const stored_root_recipe_keys = ['format', 'manifest', 'entries']

fn (mut r StoredReader) root_entry() !RootEntry {
	r.expect(`{`)!
	mut entry := RootEntry{}
	mut accepted := false
	defer { if !accepted { unsafe { entry.source.free(); entry.path.free() } } }
	mut seen := u32(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(stored_root_entry_keys, seen)!
		seen |= u32(1) << field
		match field {
			0 { entry = RootEntry{ ...entry, source: r.quoted(1024)! } }
			1 { entry = RootEntry{ ...entry, path: r.quoted(1024)! } }
			else {}
		}
	}
	if seen != 3 { return error('missing required prepared-root selector field') }
	accepted = true
	return entry
}

fn (mut r StoredReader) root_entries() ![]RootEntry {
	r.expect(`[` )!
	mut entries := []RootEntry{cap: 16}
	unsafe { entries.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { unsafe {
		for entry in entries { entry.source.free(); entry.path.free() }
		entries.free()
	} } }
	mut first := true
	for r.next(first, `]`)! {
		first = false
		if entries.len == 1024 { return error('prepared-root selector count exceeds its bound') }
		entry := r.root_entry()!
		pointer := unsafe { &entry }
		unsafe { entries.push_many(pointer, 1) }
	}
	accepted = true
	return entries
}

fn (mut r StoredReader) root_recipe() !RootRecipe {
	r.expect(`{`)!
	mut recipe := RootRecipe{}
	mut accepted := false
	defer { if !accepted { close_decoded_root_recipe(recipe) } }
	mut seen := u32(0)
	mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(stored_root_recipe_keys, seen)!
		seen |= u32(1) << field
		match field {
			0 { recipe = RootRecipe{ ...recipe, format: int(r.unsigned(u64(max_i32))!) } }
			// Prepared-root manifests are templates; omissions retain SDK defaults.
			1 { recipe = RootRecipe{ ...recipe, manifest: r.package_fields(false)! } }
			2 { recipe = RootRecipe{ ...recipe, entries: r.root_entries()! } }
			else {}
		}
	}
	if seen & 6 != 6 { return error('missing required prepared-root recipe field') }
	accepted = true
	return recipe
}
