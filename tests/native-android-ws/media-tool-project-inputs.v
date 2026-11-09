// SPDX-License-Identifier: GPL-2.0-or-later
// List the actual generated projects, explicit sources and linked archives.
module main

import os

const file_limit = 20000
const listing_limit = 4 * 1024 * 1024

struct WalkBudget {
mut:
	entries int
}

fn canonical(path string) ! {
	if !os.is_abs_path(path) || path.len > 4096 || path.contains_any('\x00\r\n')
		|| os.real_path(path) != path { return error('canonical absolute path required: ' + path) }
}

fn regular(path string) ! {
	canonical(path)!
	if os.lstat(path)!.get_filetype() != .regular { return error('regular file required: ' + path) }
}

fn add(path string, mut files map[string]bool) ! {
	regular(path)!
	files[path] = true
	if files.len > file_limit { return error('bounded input count required') }
}

fn walk(directory string, depth int, mut files map[string]bool, mut budget WalkBudget) ! {
	canonical(directory)!
	if depth > 32 || os.lstat(directory)!.get_filetype() != .directory {
		return error('bounded regular directory tree required: ' + directory)
	}
	for name in os.ls(directory)!.sorted() {
		budget.entries++
		if budget.entries > file_limit { return error('bounded project tree required') }
		path := directory + '/' + name
		kind := os.lstat(path)!.get_filetype()
		if kind == .directory { walk(path, depth + 1, mut files, mut budget)! }
		else if kind == .regular { add(path, mut files)! }
		else { return error('project links and special files forbidden: ' + path) }
	}
}

fn linked_archives(project string, mut files map[string]bool) ! {
	path := project + '/build_command.txt'
	regular(path)!
	if os.file_size(path) > 65536 { return error('bounded emitted command required') }
	text := os.read_file(path)!.trim_space()
	if text.contains_any("'\"`\n\r;$|&<>") { return error('unexpected emitted command syntax') }
	tokens := text.fields()
	if tokens.len < 10 || tokens.len > 2048 || tokens[0] != 'cc' {
		return error('expected emitted host C compiler command')
	}
	for token in tokens[1..] {
		if token.ends_with('.a') { add(token, mut files)! }
	}
}

fn listing(files map[string]bool) !string {
	if files.len == 0 { return error('nonempty input list required') }
	text := files.keys().sorted().join('\n') + '\n'
	if text.len > listing_limit { return error('bounded input listing required') }
	return text
}

fn fresh_write(path string, text string) ! {
	mut file := os.open_file(path, 'wx', 0o600)!
	defer { file.close() }
	file.write_string(text)!
}

fn run(tools string, repo string, profile string) ! {
	if profile !in ['global-settings-string', 'default-network-active'] { return error('literal media input profile required') }
	for root in [tools, repo] {
		canonical(root)!
		if os.lstat(root)!.get_filetype() != .directory { return error('existing directory required: ' + root) }
	}
	outputs := ['project-files.txt', 'extra-inputs.txt', 'link-inputs.txt']
	for name in outputs {
		if os.exists(tools + '/' + name) || os.is_link(tools + '/' + name) {
			return error('fresh input lists required: ' + name)
		}
	}
	mut projects := map[string]bool{}
	mut archives := map[string]bool{}
	mut budget := WalkBudget{}
	for name in ['stager-project', 'batches-project', 'ancestry-project', 'discovery-project'] {
		project := tools + '/' + name
		walk(project, 0, mut projects, mut budget)!
		linked_archives(project, mut archives)!
	}
	mut extra := map[string]bool{}
	relatives := match profile {
		'global-settings-string' {
			['maps-global-settings-string-stage.v', 'maps-global-settings-string-ancestry.v',
				'mapsaccountstage/batches.v', 'mapsaccountstage/batches_test.v', 'media-stage-inputs.v',
				'global-settings-string-native-readback.v']
		}
		else {
			['maps-default-network-active-stage.v', 'maps-default-network-active-ancestry.v',
				'mapsaccountstage/batches.v', 'mapsaccountstage/batches_test.v', 'media-stage-inputs.v',
				'default-network-active-native-readback.v']
		}
	}
	for relative in relatives {
		for root in [repo, tools + '/sources'] {
			add(root + '/tests/native-android-ws/' + relative, mut extra)!
		}
	}
	for path in [repo + '/tests/native-android-ws/media-tool-input-capture.v',
		os.abs_path(@FILE), os.executable()] { add(path, mut extra)! }
	// Validate all inputs and all three payloads before creating any output.
	project_text := listing(projects)!
	extra_text := listing(extra)!
	archive_text := listing(archives)!
	fresh_write(tools + '/project-files.txt', project_text)!
	fresh_write(tools + '/extra-inputs.txt', extra_text)!
	fresh_write(tools + '/link-inputs.txt', archive_text)!
	println('MEDIA-TOOL-PROJECT-INPUTS PASS profile=' + profile + ' project=' + projects.len.str()
		+ ' extra=' + extra.len.str() + ' archives=' + archives.len.str())
}

fn main() {
	if os.args.len != 4 {
		eprintln('usage: media-tool-project-inputs TOOLS_ROOT REPO_ROOT global-settings-string|default-network-active')
		exit(2)
	}
	run(os.args[1], os.args[2], os.args[3]) or { eprintln(err); exit(1) }
}
