// SPDX-License-Identifier: GPL-2.0-or-later
module cachekey

import crypto.sha256
import os
import strconv

pub fn ignored_source(path string, policy string) !bool {
	name := path.all_after_last('/')
	directory := path_is_directory(path)!
	if policy == 'office' {
		return directory || name.ends_with('_test.v')
			|| !['.c', '.h', '.m', '.v'].any(name.ends_with(it))
	}
	if policy == 'vlib' && directory && parent_path(path).all_after_last('/') == 'vlib'
		&& name in ['v', 'v3'] {
		return true
	}
	if directory { return name in ['.git', '__pycache__', 'testdata', 'tests'] }
	return name.ends_with('_test.v')
		|| !['.c', '.cc', '.cpp', '.h', '.m', '.S', '.v', '.vsh'].any(name.ends_with(it))
}

fn path_is_directory(path string) !bool {
	return path_kind(path, u32(C.S_IFDIR))
}

fn path_exists(path string) !bool {
	return path_kind(path, 0)
}

fn path_kind(path string, expected u32) !bool {
	if path.contains('\x00') { return false }
	mut state := C.vinix_cache_stat{}
	if C.vinix_cache_stat_path(&char(path.str), &state) != 0 {
		if C.errno in [C.ENOENT, C.ENOTDIR, C.EBADF, C.ELOOP] { return false }
		return file_error(path)
	}
	return expected == 0 || state.st_mode & u32(C.S_IFMT) == expected
}

// Desktop build inputs follow link targets and ignore directory generation.
// These differ deliberately from the payload-only content-key policy.
fn build_hash_path(mut digest sha256.Digest, path string, label string, metadata bool,
	policy string, mut active map[string]bool) ! {
	add_field(mut digest, label)
	if path.contains('\x00') { return error('embedded null byte') }
	mut state := C.vinix_cache_stat{}
	if C.vinix_cache_lstat(&char(path.str), &state) != 0 {
		if C.errno == C.ENOENT {
			add_field(mut digest, 'missing')
			return
		}
		return file_error(path)
	}
	add_field(mut digest, '0o' + strconv.format_uint(u64(state.st_mode & 0o7777), 8))
	kind := state.st_mode & u32(C.S_IFMT)
	if metadata && kind != u32(C.S_IFDIR) { generation(mut digest, state) }
	if kind == u32(C.S_IFLNK) {
		add_field(mut digest, 'symlink')
		add_field(mut digest, os.readlink(path) or { return file_error(path) })
		resolved := resolve_path(path)!
		if resolved != path && path_exists(resolved)! {
			build_hash_path(mut digest, resolved, label + '/target', metadata, policy, mut active)!
		}
	} else if kind == u32(C.S_IFREG) {
		add_field(mut digest, 'file')
		add_field(mut digest, state.st_size.str())
		if !metadata { file_contents(mut digest, path)! }
	} else if kind == u32(C.S_IFDIR) {
		add_field(mut digest, 'directory')
		identity := state.st_dev.str() + ':' + state.st_ino.str()
		if identity in active {
			add_field(mut digest, 'symlink-cycle')
			return
		}
		active[identity] = true
		defer { active.delete(identity) }
		mut names := os.ls(path) or { return file_error(path) }
		names.sort()
		for name in names {
			child := join_path(path, name)
			if policy != '' && ignored_source(child, policy)! { continue }
			build_hash_path(mut digest, child, label + '/' + name, metadata, policy, mut active)!
		}
	} else {
		add_field(mut digest, 'special')
		add_field(mut digest, kind.str())
	}
}

pub struct BuildInput {
pub:
	path     string
	label    string
	metadata bool
	policy   string
}

pub fn build_tree_key(namespace string, fields []string, inputs []BuildInput) !string {
	mut digest := sha256.new()
	add_field(mut digest, namespace)
	for value in fields { add_field(mut digest, value) }
	mut active := map[string]bool{}
	for input in inputs {
		build_hash_path(mut digest, input.path, input.label, input.metadata, input.policy, mut active)!
	}
	return digest.sum([]u8{}).hex()
}

fn native_inputs(mut digest sha256.Digest, root string, mut active map[string]bool) ! {
	for item in ['build-support/cachekey', 'build-support/cache_query.v',
		'build-support/_cache_native.py'] {
		build_hash_path(mut digest, join_path(root, item), 'native-helper/' + item, false, '', mut active)!
	}
}

pub fn staging_key(root string, values []string, sources []string, metadata []string, vlib []string) !string {
	mut digest := sha256.new()
	add_field(mut digest, 'vinix-staging-cache-v2')
	mut active := map[string]bool{}
	build_hash_path(mut digest, join_path(root, 'build-support/staging-cache.py'), 'staging-helper', false, '', mut active)!
	build_hash_path(mut digest, join_path(root, 'desktop/tools/build_cache.py'), 'hash-helper', false, '', mut active)!
	native_inputs(mut digest, root, mut active)!
	for value in values { add_field(mut digest, value) }
	for index, path in sources {
		build_hash_path(mut digest, path, 'source-' + index.str(), false, '', mut active)!
	}
	for index, path in metadata {
		build_hash_path(mut digest, path, 'metadata-' + index.str(), true, '', mut active)!
	}
	for index, path in vlib {
		build_hash_path(mut digest, path, 'vlib-' + index.str(), true, 'vlib', mut active)!
	}
	return digest.sum([]u8{}).hex()
}

pub fn staging_complete(staging string, required []string, executable_paths []string, any_paths []string) !bool {
	if !path_is_directory(staging)! { return false }
	for path in required { if !path_exists(join_absolute(staging, path))! { return false } }
	for path in executable_paths {
		joined := join_absolute(staging, path)
		if !path_is_file(joined)! || C.access(&char(joined.str), C.X_OK) != 0 { return false }
	}
	if any_paths.len == 0 { return true }
	for path in any_paths {
		joined := join_absolute(staging, path)
		if path_is_file(joined)! && C.access(&char(joined.str), C.X_OK) == 0 { return true }
	}
	return false
}

fn join_absolute(base string, name string) string {
	return if name.starts_with('/') { name } else { join_path(base, name) }
}

pub fn resolved_tool(path string) !string {
	if !path.starts_with('/') && !path.contains('/') {
		found := which(path, os.environ())!
		if found != '' { return resolve_path(found) }
	}
	return resolve_path(path)
}

pub struct OfficeInputs {
pub:
	repo          string
	builder       string
	office        string
	ui2           string
	v             string
	vroot         string
	arch          string
	target        string
	clang         string
	strip         string
	clang_headers string
	sysroot       string
	gcclib        string
	cc_shim       string
	llvm          string
}

fn office_app(name string) !string {
	return match name {
		'calc' { 'cmd/excel' }
		'writer' { 'cmd/word' }
		else { return error('Unknown VOffice application: ' + name) }
	}
}

pub fn office_source_files(source string) ![]string {
	mut result := []string{}
	mut names := os.ls(source) or { return file_error(source) }
	names.sort()
	for name in names {
		path := join_path(source, name)
		if path_is_file(path)! && !ignored_source(path, 'office')! { result << path }
	}
	return result
}

pub fn office_modules(office string, app string) ![]string {
	mut pending := [join_path(office, office_app(app)!)]
	mut visited := map[string]bool{}
	mut modules := map[string]bool{}
	for pending.len > 0 {
		source := pending.pop()
		identity := resolve_path(source)!
		if identity in visited { continue }
		visited[identity] = true
		for path in office_source_files(source)! {
			if !path.ends_with('.v') { continue }
			for name in office_imports(source_text(path)!) {
				if name in modules { continue }
				directory := join_path(office, name)
				if path_is_directory(directory)! {
					modules[name] = true
					pending << directory
				}
			}
		}
	}
	mut result := modules.keys()
	result.sort()
	return result
}

pub fn office_shared(input OfficeInputs) !string {
	mut digest := sha256.new()
	add_field(mut digest, 'vinix-voffice-cache-v2')
	compiler := resolved_tool(input.v)!
	for value in ['arch', input.arch, 'target', input.target] { add_field(mut digest, value) }
	mut active := map[string]bool{}
	for item in [BuildInput{input.builder, 'builder', false, ''},
		BuildInput{join_path(parent_path(input.builder), 'build_cache.py'), 'cache-helper', false, ''},
		BuildInput{join_path(input.repo, 'desktop/tools/stage_ui2.py'), 'stager', false, ''},
		BuildInput{join_path(input.repo, 'desktop/tools/ui2_vinix_backend.v'), 'backend', false, ''},
		BuildInput{join_path(input.ui2, 'v.mod'), 'ui2-manifest', false, ''},
		BuildInput{join_path(input.office, 'v.mod'), 'office-manifest', false, ''},
		BuildInput{join_path(input.office, 'VERSION'), 'office-version', false, ''},
		BuildInput{compiler, 'v-compiler', false, ''}] {
		build_hash_path(mut digest, item.path, item.label, item.metadata, item.policy, mut active)!
	}
	native_inputs(mut digest, input.repo, mut active)!
	build_hash_path(mut digest, join_path(input.vroot, 'vlib'), 'vlib', true, 'vlib', mut active)!
	build_hash_path(mut digest, join_path(input.vroot, 'thirdparty/mbedtls'), 'mbedtls', true, 'v', mut active)!
	for name in module_subdirs(input.ui2)! {
		if name == 'appkit' { continue }
		build_hash_path(mut digest, join_absolute(input.ui2, name), 'ui2/' + name, false, 'v', mut active)!
	}
	build_hash_path(mut digest, join_path(input.ui2, 'assets'), 'ui2/assets', false, '', mut active)!
	for item in [BuildInput{resolved_tool(input.clang)!, 'clang', true, ''},
		BuildInput{resolved_tool(input.strip)!, 'strip', true, ''},
		BuildInput{input.clang_headers, 'clang-resource-headers', true, ''},
		BuildInput{join_path(input.sysroot, 'usr/include'), 'sysroot-headers', true, ''},
		BuildInput{join_path(input.gcclib, 'include'), 'gcc-headers', true, ''},
		BuildInput{join_path(input.sysroot, 'usr/lib/crt1.o'), 'crt1', true, ''},
		BuildInput{join_path(input.sysroot, 'usr/lib/crti.o'), 'crti', true, ''},
		BuildInput{join_path(input.sysroot, 'usr/lib/crtn.o'), 'crtn', true, ''},
		BuildInput{join_path(input.sysroot, 'usr/lib/libc.a'), 'libc', true, ''},
		BuildInput{join_path(input.sysroot, 'usr/lib/libm.a'), 'libm', true, ''},
		BuildInput{join_path(input.gcclib, 'crtbeginT.o'), 'crtbegin', true, ''},
		BuildInput{join_path(input.gcclib, 'crtend.o'), 'crtend', true, ''},
		BuildInput{join_path(input.gcclib, 'libgcc.a'), 'libgcc', true, ''},
		BuildInput{join_path(input.gcclib, 'libgcc_eh.a'), 'libgcc-eh', true, ''}] {
		build_hash_path(mut digest, item.path, item.label, true, '', mut active)!
	}
	if input.cc_shim != '' {
		build_hash_path(mut digest, input.cc_shim, 'cc-shim', false, '', mut active)!
	}
	if input.llvm != '' {
		build_hash_path(mut digest, join_path(input.llvm, 'ld.lld'), 'ld.lld', true, '', mut active)!
	}
	return digest.sum([]u8{}).hex()
}

pub fn office_key(office string, shared string, app string) !string {
	mut digest := sha256.new()
	add_field(mut digest, 'vinix-voffice-app-v2')
	add_field(mut digest, shared)
	mut active := map[string]bool{}
	app_path := office_app(app)!
	build_hash_path(mut digest, join_path(office, app_path), 'office/' + app_path, false, 'office', mut active)!
	for name in office_modules(office, app)! {
		build_hash_path(mut digest, join_path(office, name), 'office/' + name, false, 'office', mut active)!
	}
	return digest.sum([]u8{}).hex()
}
