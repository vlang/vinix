// SPDX-License-Identifier: GPL-2.0-or-later
module cachekey

import crypto.sha256
import os

pub struct DesktopTool {
pub:
	name string
	path string
}

pub struct DesktopInputs {
pub:
	sources  []string
	in_place []string
	layers   []string
	tools    []DesktopTool
}

pub fn desktop_prepare(root_path string, compiler_path string, env map[string]string, python_path string) !DesktopInputs {
	root := resolve_path(root_path)!
	compiler := resolve_path(compiler_path)!
	userland := env_path(env, 'VINIX_AARCH64_USERLAND_BUILD_DIR', join_path(root, 'build-aarch64-userland'))!
	sysroot := env_path(env, 'VINIX_AARCH64_SYSROOT', userland + '/staging')!
	archive := env_path(env, 'VINIX_AARCH64_DEVTOOLS_ARCHIVE', userland + '/alpine-devtools.tar')!
	mut layers := [join_path(root, 'build-support/init-aarch64/initramfs.tar'), archive, sysroot]
	mut selected := map[string]string{}
	for item in desktop_layer_defaults {
		value := env_path(env, item.variable, join_path(root, item.path))!
		selected[item.variable] = value
	}
	// Keep resolution order before the source-list and tool selections. X11 is
	// resolved among these defaults even though its recursive generation is kept
	// separate from the large layers' root-only generations.
	for name in desktop_layer_order { layers << selected[name] }
	x11 := selected['VINIX_X11_STAGING']
	doom := selected['VINIX_DOOM_STAGING']
	gpu := env_path(env, 'VINIX_GPU_SYSROOT', join_path(root, 'build-aarch64-x11/sysroot'))!
	sibling := join_path(parent_path(root), 'ui2')
	ui_default := if path_is_file(sibling + '/v.mod')! {
		sibling
	} else {
		join_path(root, 'third_party/ui2')
	}
	ui := env_path(env, 'VINIX_UI2_SOURCE', ui_default)!
	mut sources := []string{}
	for item in desktop_source_paths {
		sources << (if item.starts_with('ui2:') {
			join_path(ui, item[4..])
		} else {
			join_path(root, item)
		})
	}
	// Native helper changes must invalidate an existing image just as edits to
	// the former Python producers did. This is an explicit cache format upgrade.
	for item in ['build-support/cachekey', 'build-support/cache_query.v',
		'build-support/_cache_native.py'] {
		sources << join_path(root, item)
	}
	wifi := env['VINIX_WIFI_BUNDLE'] or { '' }
	if wifi != '' {
		if wifi.contains('\x00') { return error('embedded null byte') }
		sources << resolve_path(expand_user(wifi)!)!
	}
	llvm_input := env['LLVM_BIN'] or { '/opt/homebrew/opt/llvm/bin' }
	mut llvm := expand_user(llvm_input)!
	if !path_is_file(join_path(llvm, 'clang'))! {
		found := which('clang', env)!
		if found != '' { llvm = parent_path(resolve_path(found)!) }
	}
	tools := [DesktopTool{'v', compiler},
		DesktopTool{'llvm-clang', resolve_path(join_path(llvm, 'clang'))!},
		DesktopTool{'llvm-strip', resolve_path(join_path(llvm, 'llvm-strip'))!},
		DesktopTool{'ld-lld', tool_path(env, 'LD_LLD', 'ld.lld')!},
		DesktopTool{'host-clang', tool_path(env, 'CLANG', 'clang')!},
		DesktopTool{'ld64-lld', tool_path(env, 'LD64_LLD', 'ld64.lld')!},
		DesktopTool{'python', resolve_path(python_path)!}]
	return DesktopInputs{sources, [x11, gpu, doom], layers, tools}
}

fn add_text(mut digest sha256.Digest, name string, value string) {
	add_field(mut digest, name)
	add_field(mut digest, value)
}

pub fn desktop_complete(input DesktopInputs, env map[string]string, platform string, python_version string, pillow_version string, musl_path string, musl_version string) !string {
	mut digest := sha256.new()
	add_field(mut digest, 'vinix-desktop-run-build-key-v2')
	add_text(mut digest, 'platform', platform)
	add_text(mut digest, 'python-version', python_version)
	add_text(mut digest, 'pillow-version', pillow_version)
	for item in [DesktopEnv{'optimized-musl', 'VINIX_OPTIMIZED_MUSL', '1'},
		DesktopEnv{'musl-retain', 'VINIX_MUSL_RETAIN', '1'},
		DesktopEnv{'musl-compiler', 'VINIX_MUSL_CC_AARCH64', 'aarch64-linux-musl-gcc'}] {
		add_text(mut digest, item.label, env[item.variable] or { item.fallback })
	}
	add_text(mut digest, 'musl-compiler-version', musl_version)
	add_text(mut digest, 'with-asahi', env['VINIX_WITH_ASAHI_GPU'] or { '0' })
	add_text(mut digest, 'macho-linker', env['VINIX_MACHO_LINKER'] or { 'auto' })
	add_text(mut digest, 'sources', tree_key(input.sources, false, 'vinix-desktop-build-content-v1')!)
	add_text(mut digest, 'inplace-layer-generation', tree_key(input.in_place, true, 'vinix-desktop-build-metadata-v1')!)
	for path in input.layers { add_text(mut digest, 'layer:' + path, root_generation(path)!) }
	mut tools := input.tools.clone()
	if musl_path != '' { tools << DesktopTool{'musl-cc', musl_path} }
	for tool in tools {
		add_text(mut digest, 'tool:' + tool.name + ':' + if tool.path != '' {
			tool.path
		} else {
			'missing'
		},
			if tool.path != '' { root_generation(tool.path)! } else { 'missing' })
	}
	return digest.sum([]u8{}).hex()
}

struct DesktopEnv {
	label    string
	variable string
	fallback string
}

struct DesktopLayer {
	variable string
	path     string
}
