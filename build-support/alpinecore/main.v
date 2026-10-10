// SPDX-License-Identifier: GPL-2.0-or-later
module alpinecore

pub struct Package {
pub:
	name         string
	version      string
	dependencies []string
	provides     []string
	repository   string
}

pub struct Index {
pub:
	repository string
	path       string
}

// Repository order wins, real names take precedence over virtual provisions,
// and conflicts and the shell's built-in provisions are ignored.
pub fn resolve(packages []Package, requests []string) ![]Package {
	mut by_name := map[string]int{}
	mut providers := map[string]int{}
	for index, package in packages {
		if package.name !in by_name { by_name[package.name] = index }
		if package.name !in providers { providers[package.name] = index }
		for provision in package.provides {
			key := dependency_key(provision)
			if key !in providers { providers[key] = index }
		}
	}
	mut queue := requests.clone()
	mut selected := map[string]bool{}
	mut result := []Package{}
	mut next := 0
	for next < queue.len {
		requested := dependency_key(queue[next])
		next++
		if requested == '' || requested.starts_with('!') || requested in ['/bin/sh', 'cmd:sh',
			'cmd:busybox'] {
			continue
		}
		index := by_name[requested] or {
			providers[requested] or { return error('unresolved Alpine dependency: ${requested}') }
		}
		package := packages[index]
		if package.name in selected { continue }
		selected[package.name] = true
		result << package
		queue << package.dependencies
	}
	result.sort(a.name < b.name)
	return result
}

pub fn manifest(indexes []Index, requests []string) !string {
	mut packages := []Package{}
	for index in indexes { packages << parse_index(index.path, index.repository)! }
	selected := resolve(packages, requests)!
	mut result := ''
	for package in selected {
		result += '${package.repository}\t${package.name}-${package.version}.apk\n'
	}
	return result
}

fn usage() {
	println('Usage: alpine-resolve --index REPOSITORY APKINDEX [--index REPOSITORY APKINDEX ...] PACKAGE ...')
	println('Resolve an Alpine runtime dependency closure from unpacked APKINDEX files.')
}

pub fn run(args []string) int {
	mut indexes := []Index{}
	mut requests := []string{}
	mut position := 0
	mut positional := false
	for position < args.len {
		arg := args[position]
		position++
		if !positional && arg == '--' {
			positional = true
			continue
		}
		if !positional && arg in ['-h', '--help'] {
			usage()
			return 0
		}
		if !positional && (arg == '--index' || arg.starts_with('--index=')) {
			count := if arg == '--index' { 2 } else { 1 }
			if args.len - position < count {
				eprintln('--index requires REPOSITORY and APKINDEX')
				return 2
			}
			values := args[position..position + count]
			if values.any(it.starts_with('-')) {
				eprintln('--index requires REPOSITORY and APKINDEX')
				return 2
			}
			indexes << Index{
				repository: if count == 2 { values[0] } else { arg.all_after('=') }
				path:       values.last()
			}
			position += count
			continue
		}
		if !positional && arg.starts_with('-') {
			eprintln('unknown argument: ${arg}')
			return 2
		}
		requests << arg
	}
	if indexes.len == 0 || requests.len == 0 {
		eprintln('alpine-resolve requires at least one --index and one package')
		return 2
	}
	output := manifest(indexes, requests) or {
		eprintln(err)
		return 1
	}
	print(output)
	return 0
}
