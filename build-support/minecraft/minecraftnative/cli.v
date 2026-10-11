// SPDX-License-Identifier: GPL-2.0-or-later
module minecraftnative

import os
import strconv

struct ArgumentError {
	message string
}

fn (e ArgumentError) msg() string { return e.message }

fn (e ArgumentError) code() int { return 2 }

struct Options {
	values map[string]string
	help   bool
}

fn (o Options) has(name string) bool { return name in o.values }

fn (o Options) value(name string, fallback string) string { return o.values[name] or { fallback } }

fn (o Options) integer(name string, fallback int) !int {
	if !o.has(name) { return fallback }
	return strconv.atoi(o.values[name]) or { return ArgumentError{'invalid integer for ' + name} }
}

fn parse(args []string) !Options {
	mut values := map[string]string{}
	names := ['--version', '--max-java', '--staging', '--game-root', '--jobs', '--no-assets',
		'--manifest', '--maven', '--assets', '--help']
	mut index := 0
	for index < args.len {
		arg := args[index]
		name := arg.all_before('=')
		matches := names.filter(it == name || (name.starts_with('--') && it.starts_with(name)))
		if arg == '-h' || matches == ['--help'] {
			if arg.contains('=') { return ArgumentError{'--help does not take a value'} }
			return Options{ help: true }
		}
		if matches.len != 1 { return ArgumentError{'unknown or ambiguous option: ' + arg} }
		key := matches[0]
		if key == '--no-assets' {
			if arg.contains('=') { return ArgumentError{'--no-assets does not take a value'} }
			values[key] = 'true'
		} else if arg.contains('=') {
			values[key] = arg.all_after('=')
		} else {
			index++
			if index >= args.len || args[index].starts_with('--') {
				return ArgumentError{'missing value for ' + key}
			}
			values[key] = args[index]
		}
		index++
	}
	if '--staging' !in values { return ArgumentError{'--staging is required'} }
	return Options{ values: values }
}

fn stage(args []string) ! {
	options := parse(args)!
	if options.help {
		println('Usage: fetch-minecraft --staging DIRECTORY [--version release|snapshot|ID] [--max-java N] [--game-root /usr/share/minecraft] [--jobs 16] [--no-assets] [--manifest URL] [--maven URL] [--assets URL]')
		return
	}
	jobs := options.integer('--jobs', 16)!
	if jobs <= 0 || jobs > 64 {
		return ArgumentError{ message: 'jobs must be between 1 and 64' }
	}
	game_root := options.value('--game-root', '/usr/share/minecraft')
	if !game_root.starts_with('/') {
		return ArgumentError{ message: 'game-root must be absolute' }
	}
	safe_relative(game_root.trim_left('/'))!
	source := Source{ manifest: options.value('--manifest', manifest_url), maven: options.value('--maven', maven_url), assets: options.value('--assets', assets_url) }
	maximum := if options.has('--max-java') {
		?int(options.integer('--max-java', 0)!)
	} else {
		?int(none)
	}
	version_id, version := source.resolve_version(options.value('--version', 'release'), maximum)!
	safe_relative(version_id)!
	println('  Minecraft ' + version_id + ' (' + text(field(version, 'type')!)! + '), Java ' + java_major(version).str())
	root := os.join_path(options.value('--staging', ''), game_root.trim_left('/'))
	ensure_directory(root)!
	client := field(field(version, 'downloads')!, 'client')!
	client_path := 'versions/' + version_id + '/' + version_id + '.jar'
	println('  client jar')
	source.download_to(text(field(client, 'url')!)!, os.join_path(root, client_path), text(field(client, 'sha1')!)!)!
	mojang, natives := source.select_libraries(version)!
	for i, entries in [mojang, natives] {
		source.download_all(entries, os.join_path(root, 'libraries'), if i == 0 {
			'libraries'
		} else {
			'LWJGL natives-linux-arm64'
		}, jobs)!
	}
	index := source.download_assets(version, root, jobs, options.has('--no-assets'))!
	mut classpath := []string{}
	for entries in [mojang, natives] {
		for entry in entries { classpath << 'libraries/' + entry.path }
	}
	classpath << client_path
	write_launch_env(os.join_path(root, 'launch.env'), version_id, version, classpath, index, game_root)!
	mut total := u64(0)
	for path in os.walk_ext(root, '') { if os.is_file(path) { total += os.file_size(path) } }
	mut rounded := total / (1 << 20)
	remainder := total % (1 << 20)
	if remainder > (1 << 19) || (remainder == (1 << 19) && rounded % 2 != 0) { rounded++ }
	println('  staged ' + rounded.str() + ' MiB under ' + game_root)
}

pub fn cli(args []string) int {
	guard := own_commands()
	defer { guard.close() }
	stage(args) or {
		eprintln(err)
		return if interrupt_status() != 0 {
			interrupt_status()
		} else if err is ArgumentError {
			2
		} else {
			1
		}
	}
	return 0
}
