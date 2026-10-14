// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

fn inventory_refused(recipe RootRecipe, files []Payload, notices []string, diagnostic string) {
	mut denied := false
	profile_file_inventory(recipe, Package{ ...recipe.manifest, files: files }, notices) or { denied = err.msg().contains(diagnostic) }
	assert denied, recipe.manifest.id + ': ' + diagnostic
}

fn test_fixed_profile_inventories_require_every_declared_file_without_extra_or_substituted_paths() {
	for architecture in ['aarch64', 'x86_64'] {
		for profile in ['native', 'sqlite', 'ffmpeg'] {
			recipes := match profile {
				'native' { native_profile_templates(architecture, '1.0.0') }
				'sqlite' { sqlite_profile_templates(architecture, '3.53.4', '1.0.0') }
				else { ffmpeg_templates(architecture, '1.0.0') }
			}
			notices := match profile { 'native' { native_notices } 'sqlite' { sqlite_notices } else { ffmpeg_notices } }
			for recipe in recipes {
				files := recipe.entries.map(Payload{ path: it.path, bytes: 1, sha256: '01'.repeat(32) })
				profile_file_inventory(recipe, Package{ ...recipe.manifest, files: files }, notices)!
				inventory_refused(recipe, files[1..], notices, 'unexpected payload inventory')
				mut extra := files.clone()
				extra << Payload{ path: 'unexpected', bytes: 1, sha256: '01'.repeat(32) }
				inventory_refused(recipe, extra, notices, 'unexpected payload inventory')
				mut duplicate := files.clone()
				duplicate[0] = files[1]
				inventory_refused(recipe, duplicate, notices, 'unexpected payload path')
				// A one-file directory substitution keeps the file count unchanged.
				for i, original in files {
					mut renamed := files.clone()
					renamed[i] = Payload{ ...original, path: original.path + '/child' }
					inventory_refused(recipe, renamed, notices, 'unexpected payload path')
					if original.path !in notices { continue }
					for size in [u64(0), u64(1024 * 1024 + 1)] {
						mut invalid := files.clone()
						invalid[i] = Payload{ ...original, bytes: size }
						inventory_refused(recipe, invalid, notices, 'invalid redistribution/build notice')
					}
					mut maximum := files.clone()
					maximum[i] = Payload{ ...original, bytes: 1024 * 1024 }
					profile_file_inventory(recipe, Package{ ...recipe.manifest, files: maximum }, notices)!
				}
			}
		}
	}
}
