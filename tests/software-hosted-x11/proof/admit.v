// SPDX-License-Identifier: GPL-2.0-or-later
module proof

import crypto.sha256
import json2
import os

pub fn digest(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut hash := sha256.new()
	defer { unsafe { hash.free() } }
	mut bytes := []u8{len: 1024 * 1024}
	defer { unsafe { bytes.free() } }
	for {
		count := file.read(mut bytes) or { if err is os.Eof { break } else { return err } }
		if count == 0 { break }
		hash.write(bytes[..count])!
	}
	sum := hash.sum([]u8{})
	defer { unsafe { sum.free() } }
	return sum.hex()
}

pub fn inventory(directory string, prefix string, mut paths map[string]string) ! {
	entries := os.ls(directory)!
	defer { unsafe { entries.free() } }
	for name in entries {
		// The anchored historical builder used os.walk_ext, which excludes
		// hidden entries. Fresh compilation trees below include them instead.
		if name.starts_with('.') { continue }
		path := directory + '/' + name
		if os.is_dir(path) && !os.is_link(path) {
			inventory(path, prefix + name + '/', mut paths)!
		} else if os.is_file(path) {
			paths[prefix + name] = path
		}
	}
}

fn read_map(path string) !map[string]string {
	text := os.read_file(path)!
	defer { unsafe { text.free() } }
	return json2.decode[map[string]string](text)
}

fn verify(path string, expected string, name string) ! {
	actual := digest(path)!
	defer { unsafe { actual.free() } }
	if actual != expected { return error('assembled input digest differs: ' + name) }
}

fn archived_build_path(desktop string, name string, original string) !string {
	if !original.starts_with('/') || original.contains('\x00') { return error('invalid original desktop input path') }
	if !name.starts_with('source/') { return original }
	relative := name['source/'.len..]
	if relative == '' || relative.contains('\x00') || relative.contains('\\') {
		return error('invalid archived desktop source path')
	}
	for component in relative.split('/') {
		if component == '' || component == '.' || component == '..' { return error('invalid archived desktop source path') }
	}
	return desktop + '/source/' + relative
}

// Unlike the historical stage selector, the new desktop builder includes
// hidden regular files and skips all directory aliases and .git entries.
fn desktop_inventory(directory string, prefix string, mut paths map[string]string) ! {
	for name in os.ls(directory)! {
		if name == '.git' { continue }
		path := directory + '/' + name
		if os.is_link(path) {
			if os.is_file(path) { paths[prefix + name] = path }
		} else if os.is_dir(path) {
			desktop_inventory(path, prefix + name + '/', mut paths)!
		} else if os.is_file(path) { paths[prefix + name] = path }
	}
}

// The desktop is rebuilt with the Software pointer prerequisite; the initial
// stage remains the independently qualified a54cd7cf7 snapshot. Each deliberate
// replacement requires a reviewed fixture snapshot with new receipt anchors.
pub fn assembled(desktop string, stage string, arch string, compiler string) !map[string]string {
	if arch !in ['aarch64', 'x86_64'] { return error('unsupported assembled architecture') }
	desktop_hash := if arch == 'aarch64' {
		'8b403e0fb9e8eee60396155f86ceb457257ca91a02c1210b8f27a79d8ce3c10c'
	} else { '96f856167a9dbc0c49942885c63b4ee17b996b50e0e0528bf04f61751dadef47' }
	stage_hash := if arch == 'aarch64' {
		'687011a8471aa12689300e7932ca3f7bc18359817a7c37ae90ac2c5d010ba40e'
	} else { 'a967f7bbd29690cc74e63193545199d1dd7676274de29d2dad91f03c0fdd0762' }
	verify(desktop + '/desktop-build.json', desktop_hash, 'desktop receipt')!
	verify(stage + '/stage-build.json', stage_hash, 'stage receipt')!
	desktop_inputs := read_map(desktop + '/desktop-build.json')!
	stage_inputs := read_map(stage + '/stage-build.json')!
	mut result := {'assembled/desktop/desktop-build.json': desktop + '/desktop-build.json',
		'assembled/stage/stage-build.json': stage + '/stage-build.json'}
	metadata := if arch == 'aarch64' { {
		'build-inputs.json': '78a1b2f7292af2546e2cc7087a1f3c6e965e864493e64140ef2f67c3977036e4'
		'build-input-paths.json': '1430a900677b7bd43c47d5b7489ef29440e9538d2de9d746d8fa32cf312964c6'
		'build-argv.json': '51141ebafc24d5c22e92dbe515b618047cafda6ee91d1babbb558de587444aaa'
	} } else { {
		'build-inputs.json': '8bb9818c2ba904d81f591a3166cf8463213e3f743d1503e5923eb5fbad3347e8'
		'build-input-paths.json': '0d78ac2137c0004d2749d3c35b31d491cfba8cc7ea8b2229daf2c3f86d74365d'
		'build-argv.json': 'b45c71755fe98770166e2a314eac7a78c25edd1383fd07d315278c159b9698bb'
	} }
	for name, hash in metadata {
		verify(desktop + '/' + name, hash, 'desktop/' + name)!
		result['assembled/desktop/' + name] = desktop + '/' + name
	}
	build_inputs := read_map(desktop + '/build-inputs.json')!
	build_paths := read_map(desktop + '/build-input-paths.json')!
	if build_inputs.len < 100 || build_inputs.len != build_paths.len { return error('desktop build input inventory incomplete') }
	for name, hash in build_inputs {
		original := build_paths[name] or { return error('desktop build input path absent: ' + name) }
		// The anchored receipt pins the original compilation path and bytes.
		// Source bytes are also retained in the exact frozen inventory; later
		// edits in that old checkout do not change this compositor snapshot.
		path := archived_build_path(desktop, name, original)!
		verify(path, hash, 'desktop build input/' + name)!
		result['assembled/desktop/build-input/' + name] = path
	}
	mut expected_sources := map[string]string{}
	for name, hash in desktop_inputs {
		if name == 'repository-head' {
			if hash != '2018514db9fc4a258cd86fb26baad724a9e1083a' { return error('unexpected desktop source commit') }
			continue
		}
		path := if name == 'compiler' { compiler }
			else if name.starts_with('app/') || name == 'vinix-desktop' { desktop + '/' + name }
			else { desktop + '/source/' + name }
		verify(path, hash, 'desktop/' + name)!
		result['assembled/desktop/' + name] = path
		if name != 'compiler' && !name.starts_with('app/') && name != 'vinix-desktop' {
			expected_sources[name] = path
		}
	}
	mut actual_sources := map[string]string{}
	desktop_inventory(desktop + '/source', '', mut actual_sources)!
	if actual_sources != expected_sources { return error('assembled desktop source inventory differs') }
	for name, hash in stage_inputs {
		if name == 'repository-head' {
			if hash != 'a54cd7cf7b32d2aebd3df32e236522f3d614a4f0' { return error('unexpected assembled source commit') }
			continue
		}
		path := if name == 'compiler' { compiler }
			else if name == 'driver' { stage + '/cross-shim' }
			else if name.starts_with('usr/') { stage + '/root/' + name }
			else { stage + '/' + name }
		verify(path, hash, 'stage/' + name)!
		result['assembled/stage/' + name] = path
	}
	stage_sources := read_map(stage + '/source.json')!
	mut expected_stage := map[string]string{}
	for name, hash in stage_sources {
		path := stage + '/source/' + name
		verify(path, hash, 'stage/source/' + name)!
		expected_stage[name] = path
		result['assembled/stage/source/' + name] = path
	}
	mut actual_stage := map[string]string{}
	inventory(stage + '/source', '', mut actual_stage)!
	// The anchored driver selected git-tracked source paths before V generated
	// these two translations. They are retained in the separate complete current
	// archive tree, rather than added to the historical compilation-input claim.
	for generated in ['tools/accounts/stage.c', 'tools/packages/stage.c'] {
		actual_stage.delete(generated)
	}
	if actual_stage != expected_stage { return error('assembled stage source inventory differs') }
	return result
}

pub fn hashes(paths map[string]string) !map[string]string {
	mut result := map[string]string{}
	for name, path in paths { result[name] = digest(path)! }
	return result
}

pub fn unchanged(before map[string]string, paths map[string]string) ! {
	if before.len != paths.len { return error('build input inventory differs') }
	for name, path in paths {
		expected := before[name] or { return error('missing build input: ' + name) }
		actual := digest(path)!
		defer { unsafe { actual.free() } }
		if actual != expected { return error('build input changed: ' + name) }
	}
}

pub fn source() string { return $embed_file('admit.v').to_string() }

// Record names, types and literal link targets. Regular files also carry their
// byte digest; links to files pin both the link and its resolved byte input.
pub fn tree(root string, selected_sources bool) !map[string]string {
	mut result := map[string]string{}
	walk(root, '', selected_sources, mut result)!
	return result
}

fn walk(root string, prefix string, selected bool, mut result map[string]string) ! {
	for name in os.ls(root + '/' + prefix)! {
		if name == '.git' { continue }
		relative := prefix + name
		path := root + '/' + relative
		if os.is_link(path) {
			if !selected || name.ends_with('.v') || name.ends_with('.h') || name.ends_with('.sh') {
				result[relative] = 'link:' + os.readlink(path)! + if os.is_file(path) { '\nsha256:' + digest(path)! } else { '' }
			}
		} else if os.is_dir(path) {
			if !selected { result[relative] = 'directory' }
			walk(root, relative + '/', selected, mut result)!
		} else if os.is_file(path) && (!selected || name.ends_with('.v') || name.ends_with('.h') || name.ends_with('.sh')) {
			result[relative] = digest(path)!
		} else if !selected { return error('unsupported inventory file type: ' + path) }
	}
}

pub fn tree_unchanged(root string, selected bool, expected map[string]string) ! {
	if tree(root, selected)! != expected { return error('complete input tree changed: ' + root) }
}

pub fn copied(root string, expected map[string]string, exact bool) ! {
	actual := tree(root, false)!
	if exact && actual != expected { return error('frozen copy inventory differs: ' + root) }
	for name, hash in expected {
		if actual[name] or { '' } != hash { return error('frozen copy input differs: ' + root + '/' + name) }
	}
}

pub fn copied_sources(root string, expected map[string]string) ! {
	if tree(root, true)! != expected { return error('frozen source inventory differs: ' + root) }
}
