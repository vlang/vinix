// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

// Fixed publisher profiles enumerate files, including required notices and
// source archives. Validate the imported inventory before checking its objects:
// a preflight file can have become a directory, empty file or oversized notice.
fn profile_file_inventory(recipe RootRecipe, p Package, notices []string) ! {
	if p.files.len != recipe.entries.len {
		return error('catalog profile imported an unexpected payload inventory: ${p.id}/${p.architecture}')
	}
	for entry in recipe.entries {
		mut position := -1
		for i, file in p.files {
			if file.path == entry.path { position = i; break }
		}
		if position < 0 {
			return error('catalog profile imported an unexpected payload path: ${p.id}/${p.architecture}/${entry.path}')
		}
		file := p.files[position]
		if entry.path in notices && (file.bytes == 0 || file.bytes > u64(1024 * 1024)) {
			return error('catalog profile imported an invalid redistribution/build notice: ${p.id}/${p.architecture}/${file.path}')
		}
	}
}
