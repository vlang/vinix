// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import json2
import os

pub const sqlite_application_id = 'org.sqlite.cli'
pub const sqlite_runtime_id = 'org.vinix.sqlite-runtime'

pub struct SqliteProfileInfo {
pub:
	format int = 1
	profile string = 'sqlite-cli'
	directory string
	catalog string
	catalog_sha256 string
	sqlite_version string
	runtime_version string
	architectures []string
}

fn sqlite_profile_templates(architecture string, sqlite_version string, runtime_version string) []RootRecipe {
	return [
		RootRecipe{
			manifest: Package{ id: sqlite_application_id, version: sqlite_version, architecture: architecture,
				name: 'SQLite', description: 'Interactive SQLite command line. Run from Terminal; the default database is retained in this application\'s personal data directory.',
				homepage: 'https://www.sqlite.org/', license: 'SQLite-Public-Domain', kind: 'linux',
				runtime: sqlite_runtime_id, entrypoint: 'bin/vinix-linux-runner',
				arguments: ['@RUNTIME@/lib/ld-musl-' + architecture + '.so.1', '@APP@/bin/sqlite3', '@DATA@/database.sqlite3'],
				dependencies: [Dependency{ id: sqlite_runtime_id, minimum: '1.0.0', before: '2.0.0' }] }
			entries: [RootEntry{ source: 'bin/sqlite3', path: 'bin/sqlite3' },
				RootEntry{ source: 'licenses/sqlite-COPYRIGHT', path: 'licenses/sqlite-COPYRIGHT' }]
		},
		RootRecipe{
			manifest: Package{ id: sqlite_runtime_id, version: runtime_version, architecture: architecture,
				name: 'SQLite isolated runtime', description: 'Explicit musl loader, SQLite library and static SDK runner for the SQLite CLI profile.',
				homepage: 'https://www.sqlite.org/', license: 'GPL-2.0-or-later AND MIT AND SQLite-Public-Domain', kind: 'runtime' }
			entries: [RootEntry{ source: 'bin/vinix-linux-runner', path: 'bin/vinix-linux-runner' },
				RootEntry{ source: 'lib/libc.so', path: 'lib/libc.so' },
				RootEntry{ source: 'lib/libc.so', path: 'lib/ld-musl-' + architecture + '.so.1' },
				RootEntry{ source: 'lib/libsqlite3.so.0', path: 'lib/libsqlite3.so.0' },
				RootEntry{ source: 'licenses/sqlite-COPYRIGHT', path: 'licenses/sqlite-COPYRIGHT' },
				RootEntry{ source: 'licenses/musl-COPYRIGHT', path: 'licenses/musl-COPYRIGHT' },
				RootEntry{ source: 'licenses/vinix-COPYING', path: 'licenses/vinix-COPYING' }]
		},
	]
}

pub fn sqlite_catalog(sqlite_version string, runtime_version string, source_roots string, destination string) !SqliteProfileInfo {
	version_parts(sqlite_version)!
	version_parts(runtime_version)!
	if compare_versions(runtime_version, '1.0.0') < 0 || compare_versions(runtime_version, '2.0.0') >= 0 {
		return error('SQLite profile runtime must be in the supported 1.x compatibility range')
	}
	target := export_target(destination, 'SQLite profile')!
	root := C.open(source_roots.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
	if root < 0 { return error('SQLite profile roots must be an ordinary directory') }
	defer { C.close(root) }
	mut roots := map[string]int{}
	defer { for _, fd in roots { C.close(fd) } }
	mut needed := u64(4 * 1024 * 1024)
	mut scratch := u64(0)
	for architecture in ['aarch64', 'x86_64'] {
		fd := C.openat(root, architecture.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
		if fd < 0 { return error('SQLite profile requires both ordinary architecture roots: ${architecture}') }
		roots[architecture] = fd
		mut root_bytes := u64(0)
		for path, kind in {'bin/sqlite3': 'pie', 'bin/vinix-linux-runner': 'static',
			'lib/libc.so': 'shared', 'lib/libsqlite3.so.0': 'shared'} {
			profile_elf(fd, path, architecture, kind, true)!
			node := import_node(fd, path)!
			C.close(node.fd)
			root_bytes = mirror_cost(root_bytes, node.bytes)!
		}
		for path in ['licenses/sqlite-COPYRIGHT', 'licenses/musl-COPYRIGHT', 'licenses/vinix-COPYING'] {
			node := import_node(fd, path)!
			C.close(node.fd)
			if node.mode & 0o170000 != 0o100000 || node.bytes == 0 || node.bytes > u64(1024 * 1024) {
				return error('SQLite profile requires a nonempty redistribution notice of at most 1 MiB: ${path}')
			}
			root_bytes = mirror_cost(root_bytes, node.bytes)!
		}
		needed = mirror_cost(needed, root_bytes)!
		if root_bytes > scratch { scratch = root_bytes }
	}
	parent := os.dir(target)
	scratch = mirror_cost(scratch, scratch)!
	disk_check(free_bytes(parent)!, mirror_cost(needed, scratch)!, 64 * 1024 * 1024)!
	disk_check(free_bytes(os.temp_dir())!, scratch, 64 * 1024 * 1024)!
	stage := export_stage(parent, '.vinix-sqlite-profile')!
	defer { os.rmdir_all(stage) or {} }
	mut packages := []CatalogImport{}
	for architecture in ['aarch64', 'x86_64'] {
		for recipe in sqlite_profile_templates(architecture, sqlite_version, runtime_version) {
			p := pack_root_descriptor(recipe, roots[architecture], stage + '/inventory', false)!
			// Validate the materialized bytes too: a source may have changed after
			// preflight. Object modes are storage modes; the manifest carries exec.
			objects := C.open((stage + '/inventory/objects').str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
			if objects < 0 { return error('cannot inspect SQLite profile inventory') }
			for file in p.files {
				kind := if file.path == 'bin/sqlite3' { 'pie' } else if file.path == 'bin/vinix-linux-runner' { 'static' }
					else if file.path.starts_with('lib/') { 'shared' } else { '' }
				if kind == '' { continue }
				if !file.executable { C.close(objects); return error('SQLite profile payload is not executable: ${file.path}') }
				profile_elf(objects, file.sha256, architecture, kind, false) or {
					C.close(objects)
					return error('SQLite profile imported ${p.id}/${file.path}: ${err}')
				}
			}
			C.close(objects)
			packages << CatalogImport{ source: architecture, recipe: RootRecipe{ ...recipe, manifest: p } }
		}
	}
	text := json2.encode(CatalogRecipe{ format: 1, architectures: ['aarch64', 'x86_64'], packages: packages })
	canonical := json2.encode(catalog_recipe(text)!) + '\n'
	if canonical.len > max_metadata { return error('SQLite catalog lock exceeds metadata limit') }
	// Only the reviewed lock is published. Temporary payload copies are removed;
	// pack-catalog rechecks these exact pins when constructing the workspace.
	os.mkdir(stage + '/lock')!
	os.chmod(stage + '/lock', 0o700)!
	atomic_write(stage + '/lock/catalog.json', canonical)!
	publish_new_directory(stage + '/lock', target, 'SQLite profile')!
	sync_directory(parent) or { return error('SQLite profile published at ${target}, but its directory flush failed: ${err}') }
	return SqliteProfileInfo{ directory: target, catalog: target + '/catalog.json',
		catalog_sha256: index_digest(canonical), sqlite_version: sqlite_version, runtime_version: runtime_version,
		architectures: ['aarch64', 'x86_64'] }
}
