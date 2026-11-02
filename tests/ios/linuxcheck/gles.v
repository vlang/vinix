// SPDX-License-Identifier: GPL-2.0-or-later
module linuxcheck

import os
import json2

struct GlesProfile {
	enabled   bool
	root      string
	include   string
	libraries string
	driver    string
	vendor    string
}

struct GlesInput {
	path     string
	resolved string
	sha256   string
}

fn gles_profile(mode string) !GlesProfile {
	if mode !in ['gles', 'cxx-gles', 'build-run-ios-gles', 'build-run-ios-cxx-gles', 'probe-no-ads'] { return GlesProfile{} }
	value := os.getenv('VINIX_IOS_LINUX_GLES_ROOT')
	if value == '' {
		return error('GLES modes require VINIX_IOS_LINUX_GLES_ROOT with ARM64 GNU Mesa headers, libraries and swrast driver')
	}
	return gles_profile_at(value)
}

fn gles_profile_at(path string) !GlesProfile {
	root := os.real_path(path)
	if root.contains(':') || root.contains(',') {
		return error('Linux GLES root cannot contain loader/QEMU path delimiters (: or ,)')
	}
	profile := GlesProfile{
		enabled:   true
		root:      root
		include:   os.join_path(root, 'usr/include')
		libraries: os.join_path(root, 'usr/lib/aarch64-linux-gnu')
		driver:    os.join_path(root, 'usr/lib/aarch64-linux-gnu/dri/swrast_dri.so')
		vendor:    os.join_path(root, 'usr/lib/aarch64-linux-gnu/libEGL_mesa.so.0')
	}
	for header in ['EGL/egl.h', 'EGL/eglext.h', 'GLES2/gl2.h', 'GLES3/gl3.h', 'KHR/khrplatform.h'] {
		if !os.is_file(profile.include + '/' + header) {
			return error('missing Linux GLES header: ' + profile.include + '/' + header)
		}
		gles_resolved_input(profile, profile.include + '/' + header)!
	}
	for name in ['libEGL.so', 'libEGL.so.1', 'libGLESv2.so', 'libGLESv2.so.2', 'libEGL_mesa.so.0',
		'libz.so.1', 'dri/swrast_dri.so'] {
		require_arm64_elf(gles_resolved_input(profile, profile.libraries + '/' + name)!)!
	}
	return profile
}

// Select only the validated EGL/GLES ELF files as direct linker inputs.
// A broad SDK -L also selects unrelated glibc development scripts whose
// absolute paths can refer outside the compiler sysroot.
fn gles_link_flags(profile GlesProfile) ![]string {
	if !profile.enabled { return []string{} }
	mut flags := ['-Wl,-rpath-link,' + profile.libraries]
	for name in ['libEGL.so', 'libGLESv2.so'] {
		resolved := gles_resolved_input(profile, profile.libraries + '/' + name)!
		require_arm64_elf(resolved)!
		flags << resolved
	}
	return flags
}

fn gles_resolved_input(profile GlesProfile, path string) !string {
	resolved := os.real_path(path)
	if profile.root != '/' && !resolved.starts_with(profile.root + '/') {
		return error('Linux GLES input escapes selected SDK: ' + path)
	}
	if os.lstat(resolved)!.get_filetype() != .regular {
		return error('Linux GLES input is not a regular file: ' + path)
	}
	return resolved
}

fn gles_input(profile GlesProfile, path string) !GlesInput {
	resolved := gles_resolved_input(profile, path)!
	return GlesInput{ path: path, resolved: resolved, sha256: digest(resolved)!.sha256 }
}

fn gles_headers(profile GlesProfile, path string, mut items []GlesInput) ! {
	names := directory_names(path)!
	for name in names {
		child := path + '/' + name
		kind := os.lstat(child)!.get_filetype()
		if kind == .directory {
			gles_headers(profile, child, mut items)!
		} else if kind == .regular || kind == .symbolic_link {
			items << gles_input(profile, child)!
		} else {
			return error('Linux GLES headers contain a special file: ' + child)
		}
	}
}

// Record the headers, selected DRI driver and every shared library in the
// private GNU library directory, including the path of each resolved alias.
// The original SDK is retained separately; the before/after comparison refuses
// qualification if its inputs change during a capture.
fn gles_inputs(profile GlesProfile) ![]GlesInput {
	mut items := []GlesInput{}
	if !profile.enabled { return items }
	for name in ['EGL', 'GLES2', 'GLES3', 'KHR'] {
		gles_headers(profile, profile.include + '/' + name, mut items)!
	}
	for name in directory_names(profile.libraries)! {
		if name.ends_with('.so') || name.contains('.so.') {
			path := profile.libraries + '/' + name
			resolved := gles_resolved_input(profile, path)!
			// Development sysroots can also contain textual linker scripts.
			// Required EGL/GLES libraries were checked as ELF above; record
			// additional scripts without treating them as executable inputs.
			mut file := os.open(resolved)!
			header := file.read_bytes(4)
			file.close()
			if header == [u8(0x7f), `E`, `L`, `F`] { require_arm64_elf(path)! }
			items << gles_input(profile, path)!
		}
	}
	items << gles_input(profile, profile.driver)!
	items.sort(a.path < b.path)
	return items
}

fn gles_environment(profile GlesProfile, out string, prefix string, mut env map[string]string) ! {
	if prefix.contains(':') || prefix.contains(',') {
		return error('Linux GLES loader prefix cannot contain loader/QEMU path delimiters (: or ,)')
	}
	// Driver overrides, fake version/extension claims, shader replacements and
	// disabled rasterization/error checking cannot turn a fixture into a pass.
	for key in env.keys() {
		if key.starts_with('MESA_') || key.starts_with('GALLIUM_') || key.starts_with('LIBGL_')
			|| key.starts_with('EGL_') || key.starts_with('__EGL_') || key.starts_with('SOFTPIPE_')
			|| key.starts_with('LP_') || key.starts_with('GALLIVM_') || key in [
			'DRI_PRIME',
			'DRIRC_CONFIGDIR',
		] {
			env.delete(key)
		}
	}
	// GLVND must load the selected Mesa provider, not a host architecture's
	// default vendor JSON. json2 escapes arbitrary external SDK path names.
	json := '{"file_format_version":"1.0.0","ICD":{"library_path":' + json2.encode(profile.vendor) + '}}\n'
	os.write_file(out + '/mesa-vendor.json', json)!
	env['__EGL_VENDOR_LIBRARY_FILENAMES'] = out + '/mesa-vendor.json'
	env['LIBGL_DRIVERS_PATH'] = os.dir(profile.driver)
	env['LIBGL_ALWAYS_SOFTWARE'] = 'true'
	env['GALLIUM_DRIVER'] = 'softpipe'
	env['MESA_SHADER_CACHE_DISABLE'] = 'true'
	env['EGL_PLATFORM'] = 'surfaceless'
	env['LD_LIBRARY_PATH'] = profile.libraries + if prefix == '' {
		''
	} else {
		':' + prefix + '/lib'
	}
}
