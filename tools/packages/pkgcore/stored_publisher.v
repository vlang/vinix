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
	return r.root_recipe_fields(false)
}

fn (mut r StoredReader) root_recipe_fields(complete bool) !RootRecipe {
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
			// Pinned catalogs require every declaration; source recipes allow defaults.
			1 { recipe = RootRecipe{ ...recipe, manifest: r.package_fields(complete)! } }
			2 { recipe = RootRecipe{ ...recipe, entries: r.root_entries()! } }
			else {}
		}
	}
	if seen & 6 != 6 || (complete && seen != 7) { return error('missing required prepared-root recipe field') }
	accepted = true
	return recipe
}

const stored_catalog_keys = ['format', 'architectures', 'packages']
const stored_catalog_import_keys = ['source', 'recipe']

fn (mut r StoredReader) catalog_import() !CatalogImport {
	r.expect(`{`)!
	mut item := CatalogImport{ source: '', recipe: RootRecipe{} }
	mut accepted := false
	defer { if !accepted { unsafe { item.source.free() }; close_decoded_root_recipe(item.recipe) } }
	mut seen := u32(0); mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(stored_catalog_import_keys, seen)!; seen |= u32(1) << field
		match field {
			0 { item = CatalogImport{ ...item, source: r.quoted(1024)! } }
			1 { item = CatalogImport{ ...item, recipe: r.root_recipe_fields(true)! } }
			else {}
		}
	}
	if seen != 3 { return error('missing required catalog import field') }
	accepted = true
	return item
}

fn (mut r StoredReader) catalog_imports() ![]CatalogImport {
	r.expect(`[` )!
	mut items := []CatalogImport{cap: 16}
	unsafe { items.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { unsafe {
		for item in items { item.source.free(); close_decoded_root_recipe(item.recipe) }
		items.free()
	} } }
	mut first := true
	for r.next(first, `]`)! {
		first = false
		if items.len == 4096 { return error('catalog import count exceeds its bound') }
		item := r.catalog_import()!
		pointer := unsafe { &item }
		unsafe { items.push_many(pointer, 1) }
	}
	accepted = true
	return items
}

// Own only decoding and schema admission. Catalog normalization, architecture
// coverage and dependency closures remain in catalog_recipe.
fn decode_catalog_recipe(text string) !CatalogRecipe {
	if text.len > max_metadata { return error('catalog recipe exceeds metadata limit') }
	document_keys_schema(text, catalog_key, catalog_required_fields, catalog_value_type)!
	mut r := &StoredReader{ text: text }
	defer { unsafe { free(r) } }
	r.expect(`{`)!
	mut value := CatalogRecipe{ format: 1, architectures: [], packages: [] }
	mut accepted := false
	defer { if !accepted { close_decoded_catalog(value) } }
	mut seen := u32(0); mut first := true
	for r.next(first, `}`)! {
		first = false
		field := r.member(stored_catalog_keys, seen)!; seen |= u32(1) << field
		match field {
			0 { value = CatalogRecipe{ ...value, format: int(r.unsigned(u64(max_i32))!) } }
			1 { value = CatalogRecipe{ ...value, architectures: r.strings(16, 2)! } }
			2 { value = CatalogRecipe{ ...value, packages: r.catalog_imports()! } }
			else {}
		}
	}
	r.spaces()
	if r.position != text.len { return error('trailing catalog recipe data') }
	if seen != 7 { return error('missing required catalog recipe field') }
	accepted = true
	return value
}
