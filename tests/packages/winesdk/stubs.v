// SPDX-License-Identifier: GPL-2.0-or-later
// Conservative library-declaration projection for the retained TAPI v4 profile.
module winesdk

import os
import tests.packages.winelink
import tests.packages.winesource

pub const sdk = '/Library/Developer/CommandLineTools/SDKs/MacOSX27.2.sdk'

pub struct Document {
pub:
	name string
	reexports []string
}

pub struct Stub {
pub:
	resolved string
	sha256 string
	documents []Document
}

pub struct Graph {
pub:
	format int = 1
	sdk string = sdk
	stubs map[string]Stub
	edges map[string][]string
}

fn library(name string) bool {
	if !name.starts_with('/usr/lib/') || !name.ends_with('.dylib') || name.len > 4096 { return false }
	for byte in name.bytes() { if !byte.is_alnum() && byte !in [u8(`/`), `.`, `_`, `-`, `+`] { return false } }
	return !name[1..].split('/').any(it in ['', '.', '..'])
}

fn flow(lines []string, start int, prefix string, quoted bool) !([]string, int) {
	mut index := start
	mut value := lines[index].all_after(prefix).trim_space()
	if !value.starts_with('[') { return error('SDK declaration requires a flow list') }
	for !value.contains(']') {
		index++
		if index >= lines.len || !lines[index].starts_with(' ') { return error('SDK declaration list is incomplete') }
		value += ' ' + lines[index].trim_space()
	}
	if !value.ends_with(']') || value.count('[') != 1 || value.count(']') != 1 { return error('SDK declaration list differs') }
	mut result := []string{}
	for item in value[1..value.len - 1].split(',') {
		mut token := item.trim_space()
		if quoted {
			if token.len < 2 || !token.starts_with("'") || !token.ends_with("'") { return error('SDK library declaration must be quoted') }
			token = token[1..token.len - 1]
			if !library(token) { return error('SDK library declaration path differs') }
		} else {
			if token == '' || !token.bytes().all(it.is_alnum() || it in [u8(`.`), `_`, `-`]) { return error('SDK target declaration differs') }
		}
		if token in result || result.len >= 1024 { return error('SDK declaration duplicates or exceeds bound') }
		result << token
	}
	return result, index
}

// Symbols and symbol reexports are opaque here. Only top-level library
// declarations are projected; this is not a general YAML or TAPI validator.
pub fn documents(text string) ![]Document {
	if text.len == 0 || text.len > 4 * 1024 * 1024 || text.bytes().any(it < 32 && it != `\n`)
		|| !text.ends_with('...\n') { return error('SDK stub framing differs') }
	lines := text.split_into_lines()
	mut result := []Document{}
	mut index := 0
	for index < lines.len && lines[index] != '...' {
		if lines[index] != '--- !tapi-tbd' || result.len >= 256 { return error('SDK stub document marker differs') }
		index++
		mut fields := map[string]bool{}
		mut name := ''
		mut refs := []string{}
		for index < lines.len && lines[index] !in ['--- !tapi-tbd', '...'] {
			line := lines[index]
			if line == '' { return error('SDK stub empty line differs') }
			if line.starts_with(' ') {
				if line.trim_space().starts_with('libraries:') || line.trim_space().starts_with('reexported-libraries:') {
					return error('SDK library declaration outside supported block')
				}
				index++; continue
			}
			key := line.all_before(':')
			if !line.contains(':') || key !in ['tbd-version', 'targets', 'install-name', 'current-version', 'compatibility-version',
				'parent-umbrella', 'exports', 'reexports', 'reexported-libraries'] || key in fields {
				return error('SDK stub field differs or duplicates')
			}
			fields[key] = true
			match key {
				'tbd-version' { if line.all_after(':').trim_space() != '4' { return error('SDK stub version differs') } }
				'targets' { _, next := flow(lines, index, 'targets:', false)!; index = next }
				'install-name' {
					value := line.all_after(':').trim_space()
					if value.len < 2 || !value.starts_with("'") || !value.ends_with("'") || !library(value[1..value.len - 1]) {
						return error('SDK stub install name differs')
					}
					name = value[1..value.len - 1]
				}
				'reexported-libraries' {
					if line != 'reexported-libraries:' { return error('SDK reexport block differs') }
					index++
					mut groups := 0
					for index < lines.len && lines[index].starts_with('  - targets:') {
						_, next := flow(lines, index, 'targets:', false)!
						index = next + 1
						if index >= lines.len || !lines[index].starts_with('    libraries:') { return error('SDK reexport libraries absent') }
						libraries, last := flow(lines, index, 'libraries:', true)!
						for ref in libraries { if ref !in refs { refs << ref } }
						index = last + 1; groups++
					}
					if groups == 0 { return error('SDK reexport targets absent') }
					continue
				}
				else {}
			}
			index++
		}
		if name == '' || 'targets' !in fields || 'tbd-version' !in fields || result.any(it.name == name) {
			return error('SDK stub identity absent or duplicated')
		}
		refs.sort()
		result << Document{name: name, reexports: refs}
	}
	if index != lines.len - 1 || result.len == 0 { return error('SDK stub end differs') }
	return result
}

pub fn graph(archive winelink.Archive, bytes []u8) !Graph {
	mut stubs := map[string]Stub{}
	mut edges := map[string][]string{}
	prefix := 'link-inputs/' + sdk[1..] + '/usr/lib/'
	for path, member in archive.members {
		if path.ends_with('.tbd') && !path.starts_with(prefix) { return error('SDK stub member namespace differs') }
		if !path.starts_with(prefix) || !path.ends_with('.tbd') { continue }
		name := '/' + path['link-inputs/'.len..]
		resolved := os.real_path(name)
		if !resolved.starts_with(sdk + '/usr/lib/') || os.lstat(resolved)!.get_filetype() != .regular
			|| winesource.file_digest(resolved)! != member.sha256 { return error('SDK source target or bytes differ') }
		docs := documents(bytes[member.offset..member.offset + member.size].bytestr())!
		stubs[name] = Stub{resolved: resolved, sha256: member.sha256, documents: docs}
		for doc in docs {
			if doc.name in edges && edges[doc.name] != doc.reexports { return error('SDK projected reexports conflict') }
			edges[doc.name] = doc.reexports
		}
	}
	for name in ['libm.tbd', 'libpthread.tbd', 'libSystem.tbd'] {
		path := sdk + '/usr/lib/' + name
		if path !in stubs || stubs[path].resolved != sdk + '/usr/lib/libSystem.B.tbd'
			|| stubs[path].documents[0].name != '/usr/lib/libSystem.B.dylib' { return error('SDK direct alias identity differs') }
	}
	for _, refs in edges {
		for ref in refs {
			path := sdk + ref[..ref.len - '.dylib'.len] + '.tbd'
			if path !in stubs || stubs[path].documents[0].name != ref { return error('SDK declared reexport stub absent or mismatched') }
		}
	}
	return Graph{stubs: stubs, edges: edges}
}

pub fn verify_sources(graph Graph) ! {
	for path, stub in graph.stubs {
		if os.real_path(path) != stub.resolved || os.lstat(stub.resolved)!.get_filetype() != .regular
			|| winesource.file_digest(stub.resolved)! != stub.sha256 { return error('SDK source target or bytes differ') }
	}
}
