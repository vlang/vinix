// SPDX-License-Identifier: GPL-2.0-or-later
module dylibclosure

import os

pub type Checked = fn ([]string) !string

pub struct Closure {
pub:
	// Hash these regular files with the caller's ordinary input inventory.
	paths []string
	// Includes intermediate symlinks, ordered resolution attempts, load commands,
	// and explicitly excluded OS shared-cache dependencies.
	metadata map[string]string
}

const otool = '/usr/bin/otool'
const developer_otool = '/Library/Developer/CommandLineTools/usr/bin/otool'
const system_version = '/System/Library/CoreServices/SystemVersion.plist'

struct Image {
	dependencies []string
	rpaths       []string
	id           string
	dylinker     string
}

struct Located {
	path    string
	present bool
}

struct State {
mut:
	paths        map[string]bool
	metadata     map[string]string
	visited      map[string]bool
	images       int
	entries      int
	architecture string
}

// Apple supplies these through the OS's dyld shared cache; many have no
// ordinary filesystem entry. Bind their install names and the OS version,
// rather than claiming to have hashed shared-cache contents.
fn system_path(path string) bool {
	return (path.starts_with('/usr/lib/') || path.starts_with('/System/Library/'))
		&& !path.split('/').any(it == '..' || it == '.')
}

fn field(line string, prefix string, suffix string) !string {
	if !line.starts_with(prefix) { return error('unexpected otool field: ' + line) }
	end := line.last_index(suffix) or { return error('malformed otool field: ' + line) }
	value := line[prefix.len..end]
	if value == '' || value.contains('\n') || value.contains('\x00') {
		return error('empty/invalid otool field')
	}
	return value
}

// Cross-check -L against actual load commands, excluding LC_ID_DYLIB (which
// -L prints as its first entry for a dylib). Refuse unfamiliar/universal output
// rather than silently omitting a slice or a dependency.
fn parse_image(path string, listed string, commands string) !Image {
	if listed.len > 4 * 1024 * 1024 || commands.len > 4 * 1024 * 1024 {
		return error('otool output limit')
	}
	lines := listed.trim_space().split_into_lines()
	if lines.len == 0 || lines[0] != path + ':' {
		return error('unsupported otool image header: ' + path)
	}
	mut names := []string{}
	for line in lines[1..] {
		if line.trim_space() == '' { continue }
		if !line.starts_with('\t') { return error('unsupported otool dependency line') }
		names << field(line.trim_space(), '', ' (compatibility version ')!
	}
	mut dependencies := []string{}
	mut rpaths := []string{}
	mut id := ''
	mut dylinker := ''
	mut command := ''
	mut found_header := false
	for raw in commands.split_into_lines() {
		line := raw.trim_space()
		if line == path + ':' {
			if found_header { return error('multiple otool image headers') }
			found_header = true
			continue
		}
		if line.starts_with('Load command ') { command = ''; continue }
		if line.starts_with('cmd ') { command = line[4..]; continue }
		if command == 'LC_RPATH' && line.starts_with('path ') {
			rpaths << field(line, 'path ', ' (offset ')!
		} else if line.starts_with('name ') {
			if command in ['LC_LOAD_DYLIB', 'LC_LOAD_WEAK_DYLIB', 'LC_REEXPORT_DYLIB',
				'LC_LOAD_UPWARD_DYLIB', 'LC_LAZY_LOAD_DYLIB'] {
				dependencies << field(line, 'name ', ' (offset ')!
			} else if command == 'LC_ID_DYLIB' {
				if id != '' { return error('multiple dylib IDs') }
				id = field(line, 'name ', ' (offset ')!
			} else if command == 'LC_LOAD_DYLINKER' {
				if dylinker != '' { return error('multiple dynamic loaders') }
				dylinker = field(line, 'name ', ' (offset ')!
			} else { return error('unsupported named load command: ' + command) }
		}
	}
	if !found_header || dependencies.len > 256 || rpaths.len > 256 {
		return error('otool image/command limit')
	}
	mut expected := []string{}
	if id != '' { expected << id }
	expected << dependencies
	if names != expected { return error('otool -L/-l dependency mismatch: ' + path) }
	return Image{dependencies: dependencies, rpaths: rpaths, id: id, dylinker: dylinker}
}

// Resolve components in filesystem order. Cleaning "link/.." lexically would
// lose the link's meaning and its provenance. Record every intermediate link,
// including Homebrew's opt links, before following its target.
fn (mut state State) locate(path string, links []string) !Located {
	if !path.starts_with('/') || path.len > 16384 || links.len >= 40 {
		return error('invalid/deep dylib path: ' + path)
	}
	mut current := '/'
	for part in path.split('/') {
		if part == '' || part == '.' { continue }
		if part == '..' { current = os.dir(current); continue }
		candidate := if current == '/' { '/' + part } else { current + '/' + part }
		state.entries++
		if state.entries > 100000 { return error('dylib path entry limit') }
		if !os.exists(candidate) && !os.is_link(candidate) {
			state.metadata['absent:' + candidate] = 'absent'
			return Located{path: candidate, present: false}
		}
		info := os.lstat(candidate)!
		kind := info.mode & 0o170000
		state.metadata['mode:' + candidate] = (info.mode & 0o177777).str()
		if kind == 0o120000 {
			if candidate in links { return error('cyclic dylib symlink: ' + candidate) }
			target := os.readlink(candidate)!
			state.metadata['link:' + candidate] = target
			mut next := links.clone()
			next << candidate
			joined := if target.starts_with('/') { target } else { current + '/' + target }
			resolved := state.locate(joined, next)!
			if !resolved.present { return error('dangling dylib symlink: ' + candidate) }
			state.metadata['resolved:' + candidate] = resolved.path
			current = resolved.path
		} else if kind in [0o040000, 0o100000] {
			current = candidate
		} else { return error('unsupported dylib path type: ' + candidate) }
	}
	return Located{path: current, present: true}
}

fn anchored(path string, loader string, executable string) !string {
	if path == '@loader_path' { return os.dir(loader) }
	if path.starts_with('@loader_path/') { return os.dir(loader) + path[12..] }
	if path == '@executable_path' { return os.dir(executable) }
	if path.starts_with('@executable_path/') { return os.dir(executable) + path[16..] }
	if path.starts_with('/') { return path }
	return error('unsupported relative dylib/rpath: ' + path)
}

fn (mut state State) resolve(name string, loader string, executable string, rpaths []string,
	context string) !string {
	if name.starts_with('@rpath/') {
		for index, runpath in rpaths {
			candidate := runpath + '/' + name[7..]
			if system_path(candidate) {
				// Shared-cache existence cannot be tested using os.exists().
				return error('system @rpath candidate requires shared-cache resolution: ' + candidate)
			}
			located := state.locate(candidate, [])!
			state.metadata['candidate:' + context + ':' + index.str()] = candidate + '\n'
				+ if located.present { located.path } else { 'absent' }
			if located.present { return candidate }
		}
		return error('unresolved @rpath dependency: ' + name + ' from ' + loader)
	}
	return anchored(name, loader, executable)
}

fn (mut state State) visit(literal string, executable string, inherited []string, depth int,
	checked Checked) ! {
	if depth > 64 { return error('dylib dependency depth limit') }
	located := state.locate(literal, [])!
	if !located.present { return error('missing dylib image: ' + literal) }
	image := located.path
	if os.lstat(image)!.mode & 0o170000 != 0o100000 {
		return error('dylib image is not a regular file: ' + image)
	}
	state.paths[image] = true
	context := executable + '|' + image
	// dyld reuses an image already loaded in this executable's dependency graph.
	if context in state.visited { return }
	state.visited[context] = true
	state.images++
	if state.images > 512 { return error('dylib image count limit') }
	listed := checked([otool, '-arch', state.architecture, '-L', image])!
	commands := checked([otool, '-arch', state.architecture, '-l', image])!
	state.metadata['otool-L:' + context] = listed
	state.metadata['otool-l:' + context] = commands
	parsed := parse_image(image, listed, commands)!
	mut rpaths := []string{}
	for path in parsed.rpaths {
		expanded := anchored(path, image, executable)!
		if expanded !in rpaths { rpaths << expanded }
	}
	for path in inherited { if path !in rpaths { rpaths << path } }
	state.metadata['rpaths:' + context] = rpaths.join('\n')
	if parsed.dylinker != '' {
		if !system_path(parsed.dylinker) { return error('non-system dynamic loader') }
		state.metadata['system-loader:' + context] = parsed.dylinker
	}
	for index, dependency in parsed.dependencies {
		edge := context + ':' + index.str()
		if system_path(dependency) {
			state.metadata['system-dependency:' + edge] = dependency
			continue
		}
		resolved := state.resolve(dependency, image, executable, rpaths, edge)!
		if system_path(resolved) {
			state.metadata['system-dependency:' + edge] = resolved
			continue
		}
		state.metadata['dependency:' + edge] = dependency + '\n' + resolved
		state.visit(resolved, executable, rpaths, depth + 1, checked)!
	}
}

// No subprocess is launched here except through the caller's bounded callback.
// Environment-based DYLD overrides must already have been removed by the caller.
pub fn closure(roots []string, checked Checked) !Closure {
	if roots.len == 0 || roots.len > 128 { return error('dylib closure root count limit') }
	architecture := os.uname().machine
	if architecture !in ['arm64', 'x86_64'] { return error('unsupported dylib host architecture') }
	mut state := State{architecture: architecture}
	for tool in [otool, developer_otool, system_version] {
		located := state.locate(tool, [])!
		if !located.present { return error('missing dylib inventory tool/provenance: ' + tool) }
		state.paths[located.path] = true
	}
	state.metadata['host-architecture'] = architecture
	state.metadata['otool-dispatch'] = 'DEVELOPER_DIR=/Library/Developer/CommandLineTools; '
		+ otool + ' selects ' + developer_otool
	state.metadata['system-provenance'] = 'OS dyld shared-cache dependencies excluded from file hashing; install names and '
		+ system_version + ' identify the OS provenance boundary'
	for root in roots {
		located := state.locate(root, [])!
		if !located.present { return error('missing dylib closure root: ' + root) }
		state.visit(root, located.path, [], 0, checked)!
	}
	mut paths := state.paths.keys()
	paths.sort()
	return Closure{paths: paths, metadata: state.metadata}
}
