// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2

fn catalog_required_fields(parent string, keys []string) ! {
	fields := match parent {
		'' { ['format', 'architectures', 'packages'] }
		'packages' { ['source', 'recipe'] }
		'recipe' { ['format', 'manifest', 'entries'] }
		'entries' { ['source', 'path'] }
		else { []string{} }
	}
	defer { unsafe { fields.free() } }
	for key in fields {
		if key !in keys { return error('missing required catalog field: ' + key) }
	}
	if parent in ['manifest', 'dependencies', 'files']! {
		index_required_fields(if parent == 'manifest' { 'packages' } else { parent }, keys)!
	}
}

fn catalog_value_type(parent string, key string, token u8) bool {
	if parent == '' {
		if key == 'format' { return token >= `0` && token <= `9` }
		return token == `[`
	}
	if parent == 'packages' { return token == if key == 'recipe' { u8(`{`) } else { u8(`"`) } }
	if parent == 'recipe' {
		return match key {
			'format' { token >= `0` && token <= `9` }
			'manifest' { token == `{` }
			else { token == `[` }
		}
	}
	if parent == 'entries' { return token == `"` }
	return index_value_type(if parent == 'manifest' { 'packages' } else { parent }, key, token)
}

fn root_recipe_field(parent string, key string) bool {
	return catalog_key(if parent == '' { 'recipe' } else { parent }, key)
}

fn root_recipe_value_type(parent string, key string, token u8) bool {
	return catalog_value_type(if parent == '' { 'recipe' } else { parent }, key, token)
}

fn root_recipe_required_fields(parent string, keys []string) ! {
	// Prepared-root templates preserve the documented default format and
	// manifest omissions. Selectors and their source/path fields are explicit.
	fields := match parent {
		'' { ['manifest', 'entries'] }
		'entries' { ['source', 'path'] }
		else { []string{} }
	}
	defer { unsafe { fields.free() } }
	for key in fields {
		if key !in keys { return error('missing required prepared-root field: ' + key) }
	}
}

fn decode_root_recipe(text string) !RootRecipe {
	if text.len > max_metadata { return error('prepared-root recipe exceeds metadata limit') }
	recipe := json2.decode[RootRecipe](text, strict: true)!
	mut accepted := false
	defer { if !accepted { close_decoded_root_recipe(recipe) } }
	document_keys_schema(text, root_recipe_field, root_recipe_required_fields, root_recipe_value_type)!
	validate_root_recipe(recipe)!
	accepted = true
	return recipe
}

fn close_decoded_root_recipe(recipe RootRecipe) {
	close_decoded_package(recipe.manifest)
	unsafe {
		for entry in recipe.entries { entry.source.free(); entry.path.free() }
		(&array(&recipe.entries)).free()
	}
}

fn close_decoded_catalog(recipe CatalogRecipe) {
	unsafe {
		for architecture in recipe.architectures { architecture.free() }
		(&array(&recipe.architectures)).free()
		for item in recipe.packages {
			item.source.free()
			close_decoded_root_recipe(item.recipe)
		}
		(&array(&recipe.packages)).free()
	}
}
