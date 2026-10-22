// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os

pub const neovim_application_id = 'org.neovim.editor'
pub const neovim_runtime_id = 'org.vinix.neovim-runtime'
pub const neovim_profile_version = '0.12.5'

const neovim_archives = {
	'neovim': '314bb8d8695cc2c1c9b69e6c93df8c75108ca66588dfffb81c42369d2f85c90a'
	'libuv': '478baf2599bfbc882c355288c9cb6f92e0e7dda435fa04031fa5b607cf3f414c'
	'lua': '2640fc56a795f29d28ef15e13c34a47e223960b0240e8cb0a82d9b0738695333'
	'luv': 'e8b8774b31d24be4fcf2b021b90599ecccc8e476c61efcc59c3c10cab813a885'
	'lpeg': '4b155d67d2246c1ffa7ad7bc466c1ea899bbc40fef0257cc9c03cecbaed4352a'
	'lua-compat': 'f5dc30e7b1fda856ee4d392be457642c1f0c259264a9b9bfbcb680302ce88fc2'
	'utf8proc': 'abfed50b6d4da51345713661370290f4f4747263ee73dc90356299dfc7990c78'
	'tree-sitter': 'ece24c3c5e2a76384075e830c7139b59fce8fb01e4ef8436fab08bbe10444c89'
}
const neovim_notices = ['licenses/neovim-LICENSE.txt', 'licenses/libuv-LICENSE',
	'licenses/lua-COPYRIGHT', 'licenses/luv-LICENSE.txt', 'licenses/lpeg-LICENSE',
	'licenses/lua-compat-LICENSE', 'licenses/utf8proc-LICENSE.md', 'licenses/tree-sitter-LICENSE',
	'licenses/musl-COPYRIGHT', 'licenses/vinix-COPYING', 'licenses/v-COPYRIGHT',
	'licenses/gcc-14.2.0-COPYING.RUNTIME', 'licenses/gcc-14.2.0-COPYING3',
	'sources/build.json', 'sources/neovim-build.v', 'sources/neovim-runner.v',
	'sources/nvimcompat-libuv.v', 'sources/libuv-patches.json']
const neovim_runtime_required = ['doc/help.txt', 'doc/tags', 'filetype.lua', 'lua/vim/_init_packages.lua', 'syntax/vim.vim']
const neovim_pinned_notices = {
	'licenses/gcc-14.2.0-COPYING.RUNTIME': '9d6b43ce4d8de0c878bf16b54d8e7a10d9bd42b75178153e3af6a815bdc90f74'
	'licenses/gcc-14.2.0-COPYING3': '8ceb4b9ee5adedde47b31e975c1d90c73ad27b6b165a1dcd80c7c545eb65b903'
}

pub struct NeovimProfileInfo {
pub:
	format int = 1
	profile string = 'neovim-cli'
	directory string
	catalog string
	catalog_sha256 string
	neovim_version string = neovim_profile_version
	runtime_version string
	architectures []string
}

pub fn (mut info NeovimProfileInfo) close() {
	unsafe {
		info.directory.free(); info.catalog.free(); info.catalog_sha256.free(); info.runtime_version.free()
		for architecture in info.architectures { architecture.free() }
		(&array(&info.architectures)).free()
	}
	info = NeovimProfileInfo{}
}

struct NeovimProfilePlan {
	templates []RootRecipe
mut:
	packages []CatalogImport
}

fn neovim_templates(arch string, version string) []RootRecipe {
	mut entries := []RootEntry{}
	for path in ['bin/vinix-neovim-runner', 'share/nvim/runtime']! {
		entries << RootEntry{source: path.clone(), path: path.clone()}
	}
	for path in neovim_notices { entries << RootEntry{source: path.clone(), path: path.clone()} }
	mut names := neovim_archives.keys(); names.sort()
	defer { unsafe { (&array(&names)).free() } }
	for name in names {
		path := 'sources/' + name + '.tar.gz'
		entries << RootEntry{source: path, path: path.clone()}
	}
	return [RootRecipe{
		manifest: Package{id: neovim_application_id, version: neovim_profile_version, architecture: arch,
			name: 'Neovim', description: 'Terminal text editor with Lua, Vimscript syntax and the complete upstream runtime. Uses Lua 5.1 without JIT; external tools and grammar parsers are not bundled.',
			homepage: 'https://neovim.io/', license: 'Apache-2.0 AND Vim AND MIT AND Unicode-DFS-2016 AND (GPL-3.0-or-later WITH GCC-exception-3.1)', kind: 'linux',
			runtime: neovim_runtime_id, entrypoint: 'bin/vinix-neovim-runner', permissions: ['files', 'process'],
			arguments: ['@RUNTIME@/share/nvim/runtime'.clone(), '@APP@/bin/nvim'.clone()],
			dependencies: [Dependency{id: neovim_runtime_id, minimum: '1.0.0', before: '2.0.0'}]}
		entries: [RootEntry{source: 'bin/nvim'.clone(), path: 'bin/nvim'.clone()},
			RootEntry{source: neovim_notices[0].clone(), path: neovim_notices[0].clone()}]
	}, RootRecipe{
		manifest: Package{id: neovim_runtime_id, version: version, architecture: arch,
			name: 'Neovim isolated runtime', description: 'Static launch adapter, Neovim runtime data and pinned source/redistribution notices.',
			homepage: 'https://neovim.io/', license: 'GPL-2.0-or-later AND Apache-2.0 AND Vim AND MIT AND Unicode-DFS-2016 AND (GPL-3.0-or-later WITH GCC-exception-3.1)', kind: 'runtime'}
		entries: entries
	}]
}

fn (mut plan NeovimProfilePlan) close() {
	for item in plan.packages { close_decoded_package(item.recipe.manifest) }
	unsafe {
		(&array(&plan.packages)).free()
		for recipe in plan.templates {
			for entry in recipe.entries { entry.source.free(); entry.path.free() }
			for argument in recipe.manifest.arguments { argument.free() }
			(&array(&recipe.entries)).free(); (&array(&recipe.manifest.arguments)).free()
			(&array(&recipe.manifest.dependencies)).free(); (&array(&recipe.manifest.permissions)).free()
		}
		(&array(&plan.templates)).free()
	}
	plan = NeovimProfilePlan{}
}

// Reuse the captured prepared-root namespace and importer bounds for the data
// tree. Symlink aliases cannot escape the guest root; cycles hit the depth cap.
struct NeovimTreeBudget {
mut:
	count int
}

fn neovim_tree_cost(root int, path string, depth int, mut budget NeovimTreeBudget) !u64 {
	if depth > max_pack_depth || budget.count >= max_pack_entries { return error('Neovim runtime exceeds import limits') }
	budget.count++
	node := import_node(root, path)!
	defer { C.close(node.fd) }
	if node.mode & 0o170000 == 0o100000 { return mirror_cost(0, node.bytes) }
	if node.mode & 0o170000 != 0o040000 { return error('Neovim runtime contains a special file') }
	names := import_names_limit(node.fd, max_files)!
	defer { unsafe { names.free() } }
	mut bytes := u64(4096)
	for name in names {
		child := path + '/' + name
		defer { unsafe { child.free() } }
		bytes = mirror_cost(bytes, neovim_tree_cost(root, child, depth + 1, mut budget)!)!
	}
	return bytes
}

fn neovim_kind(path string) string {
	return if path.starts_with('bin/') { 'static' } else { '' }
}

fn neovim_static_elf(root int, path string, architecture string, require_executable bool) ! {
	profile_elf(root, path, architecture, 'static', require_executable)!
	mut info := profile_dynamic(root, ProfileElfImage{space: 'app', path: path,
		object: path, kind: 'static'})!
	info.close()
}

pub fn neovim_catalog(version string, source_roots string, destination string) !NeovimProfileInfo {
	return neovim_catalog_with(version, source_roots, destination, CatalogOptions{})
}

fn neovim_catalog_with(version string, source_roots string, destination string, options CatalogOptions) !NeovimProfileInfo {
	validated_version(version)!
	if compare_versions(version, '1.0.0') < 0 || compare_versions(version, '2.0.0') >= 0 { return error('Neovim profile runtime must be in the supported 1.x compatibility range') }
	root := capture_prepared_root(source_roots, 'Neovim profile')!
	defer { C.close(root) }
	target := export_target(destination, 'Neovim profile')!
	defer { unsafe { target.free() } }
	mut roots := map[string]int{}
	defer { for _, fd in roots { C.close(fd) }; unsafe { roots.free() } }
	mut plan := NeovimProfilePlan{templates: []RootRecipe{cap: 4}, packages: []CatalogImport{cap: 4}}
	defer { plan.close() }
	mut needed := u64(4 * 1024 * 1024); mut scratch := u64(0)
	for arch in ['aarch64', 'x86_64']! {
		fd := C.openat(root, arch.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
		if fd < 0 { return error('Neovim profile requires both ordinary architecture roots') }
		roots[arch] = fd
		recipes := neovim_templates(arch, version)
		defer { unsafe { (&array(&recipes)).free() } }
		mut bytes := u64(0); mut budget := NeovimTreeBudget{}
		for recipe in recipes {
			// Transfer owned template fields before any preflight can fail.
			unsafe { plan.templates.push_many(&recipe, 1) }
		}
		for recipe in recipes { for entry in recipe.entries {
			kind := neovim_kind(entry.path)
			if kind != '' { neovim_static_elf(fd, entry.source, arch, true)! }
			bytes = mirror_cost(bytes, neovim_tree_cost(fd, entry.source, 0, mut budget)!)!
		} }
		needed = mirror_cost(needed, bytes)!
		if bytes > scratch { scratch = bytes }
	}
	parent := os.dir(target); temporary := import_temporary_directory()
	defer { unsafe { parent.free(); temporary.free() } }
	scratch = mirror_cost(scratch, scratch)!
	disk_check(options.available_space(parent)!, mirror_cost(needed, scratch)!, 64 * 1024 * 1024)!
	disk_check(options.available_space(temporary)!, scratch, 64 * 1024 * 1024)!
	mut exporting := create_profile_stage(parent, '.vinix-neovim-profile', 'Neovim profile')!
	defer { exporting.close() }
	canonical := write_neovim_profile(target, roots, options, mut exporting, mut plan) or { return exporting.failure(err) }
	defer { unsafe { canonical.free() } }
	exporting.finish(target)!
	return NeovimProfileInfo{directory: target.clone(), catalog: target + '/catalog.json', catalog_sha256: index_digest(canonical),
		runtime_version: version.clone(), architectures: ['aarch64'.clone(), 'x86_64'.clone()]}
}

fn neovim_inventory(recipe RootRecipe, p Package) ! {
	for entry in recipe.entries {
		if entry.path == 'share/nvim/runtime' { continue }
		if !p.files.any(it.path == entry.path) { return error('Neovim profile lost a required payload: ' + entry.path) }
	}
	for file in p.files {
		if file.path.starts_with('share/nvim/runtime/') {
			if file.executable { return error('Neovim runtime data must not be executable') }
			continue
		}
		if !recipe.entries.any(it.path == file.path) { return error('Neovim profile imported an unexpected payload') }
		if file.path in neovim_notices && (file.bytes == 0 || file.bytes > u64(1024 * 1024) || file.executable) { return error('Neovim profile requires nonempty ordinary redistribution/build notices of at most 1 MiB') }
	}
	if p.kind == 'runtime' {
		for tail in neovim_runtime_required {
			path := 'share/nvim/runtime/' + tail
			defer { unsafe { path.free() } }
			if !p.files.any(it.path == path && it.bytes > 0) { return error('Neovim profile requires complete runtime data: ' + path) }
		}
	}
}

fn write_neovim_profile(target string, roots map[string]int, options CatalogOptions, mut exporting ProfileStage, mut plan NeovimProfilePlan) !string {
	inventory := exporting.stage.path + '/inventory'; object_path := inventory + '/objects'
	defer { unsafe { inventory.free(); object_path.free() } }
	exporting.checkpoint('created', options)!
	for recipe in plan.templates {
		mut p := pack_root_descriptor(recipe, roots[recipe.manifest.architecture], inventory, false)!
		mut transferred := false
		defer { if !transferred { p.close() } }
		neovim_inventory(recipe, p)!
		for name, digest in neovim_archives {
			if p.kind != 'runtime' { break }
			path := 'sources/' + name + '.tar.gz'
			defer { unsafe { path.free() } }
			if !p.files.any(it.path == path && it.sha256 == digest && !it.executable) { return error('Neovim profile source archive differs from the reviewed pin: ' + name) }
		}
		for path, digest in neovim_pinned_notices {
			if p.kind != 'runtime' { break }
			if !p.files.any(it.path == path && it.sha256 == digest && !it.executable) { return error('Neovim profile runtime notice differs from the reviewed pin: ' + path) }
		}
		plan.packages << CatalogImport{source: recipe.manifest.architecture, recipe: RootRecipe{...recipe, manifest: p}}
		transferred = true
		exporting.checkpoint('packed', options)!
	}
	objects := C.open(object_path.str, C.O_RDONLY | C.O_DIRECTORY | C.O_CLOEXEC | C.O_NOFOLLOW)
	if objects < 0 { return error('cannot inspect Neovim profile inventory') }
	defer { C.close(objects) }
	// The editor and adapter are static: reject an interpreter and any dynamic
	// metadata rather than admitting an unnecessary ambient dependency search.
	for item in plan.packages {
		p := item.recipe.manifest
		for file in p.files {
			if !file.executable { continue }
			neovim_static_elf(objects, file.sha256, p.architecture, false)!
		}
	}
	architectures := ['aarch64', 'x86_64']
	defer { unsafe { (&array(&architectures)).free() } }
	text := publisher_json(CatalogRecipe{format: 1, architectures: architectures, packages: plan.packages})
	defer { unsafe { text.free() } }
	decoded := catalog_recipe(text)!
	defer { close_decoded_catalog(decoded) }
	canonical := publisher_json(decoded)
	mut published := false
	defer { if !published { unsafe { canonical.free() } } }
	if canonical.len > max_metadata { return error('Neovim catalog lock exceeds metadata limit') }
	exporting.publish(canonical, target, options)!
	published = true
	return canonical
}
