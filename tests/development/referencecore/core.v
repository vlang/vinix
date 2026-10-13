// SPDX-License-Identifier: GPL-2.0-or-later
module referencecore

import json2
import os
import tools.development.devcore

pub const catalog = ['make', 'cmake', 'ninja', 'sqlite', 'node', 'go']

pub struct Settings {
pub:
	root string
	profiles []string
	tools map[string]devcore.Pin
}

pub fn required_tools(profiles []string) []string {
	mut names := []string{}
	for profile in profiles {
		selected := match profile {
			'make' { ['make', 'cc', 'sh'] }
			'cmake' { ['cmake', 'ninja', 'cc', 'sh'] }
			'ninja' { ['ninja', 'cc', 'sh'] }
			'sqlite' { ['sqlite3'] }
			'node' { ['node'] }
			'go' { ['go'] }
			else { []string{} }
		}
		for name in selected { if name !in names { names << name } }
	}
	return names
}

pub fn options(root string, selection string, arch string) !Settings {
	if root == '' && selection == '' { return Settings{} }
	if root == '' || selection == '' || arch !in ['aarch64', 'x86_64'] {
		return error('reference qualification requires an SDK, explicit profiles and a supported architecture')
	}
	profiles := selection.split(',')
	if profiles.len == 0 || profiles.any(it !in catalog) {
		return error('reference profiles must select make,cmake,ninja,sqlite,node,go')
	}
	mut seen := map[string]bool{}
	for name in profiles {
		if seen[name] { return error('duplicate reference profile: ' + name) }
		seen[name] = true
	}
	if os.is_link(root) || !os.is_dir(root) { return error('reference SDK must be an ordinary directory') }
	base := os.real_path(root)
	mut tools := map[string]devcore.Pin{}
	for name in required_tools(profiles) {
		path := base + '/bin/' + name
		resolved := os.real_path(path)
		if !resolved.starts_with(base + '/') || !os.is_file(path) || !os.is_executable(path)
			|| os.stat(path)!.mode & 0o6000 != 0 {
			return error('reference tool must be executable, without set-ID bits, and inside the SDK: ' + name)
		}
		elf(path, arch)!
		tools[name] = devcore.Pin{path, devcore.file_hash(path)!}
	}
	if os.lstat(base + '/lib/libc.so')!.get_filetype() != .regular {
		return error('reference musl runtime must be an ordinary file inside the SDK')
	}
	elf(base + '/lib/libc.so', arch)!
	return Settings{base, profiles, tools}
}

pub fn version_arguments(name string) []string {
	return if name == 'go' { ['version'] } else { ['--version'] }
}

fn elf(path string, arch string) ! {
	mut file := os.open(path)!
	defer { file.close() }
	mut header := []u8{len: 20}
	count := file.read(mut header)!
	if count != 20 || header[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
		|| (u16(header[18]) | (u16(header[19]) << 8)) != if arch == 'aarch64' { u16(183) } else { u16(62) } {
		return error('reference tool/runtime has the wrong ELF architecture: ' + path)
	}
}

pub fn artifacts(profiles []string) []string {
	mut paths := ['qualification/report.json']
	for name in profiles {
		base := 'qualification/' + name + '/'
		match name {
			'sqlite' { paths << base + 'project.db' }
			'node' { paths << [base + 'project.js', base + 'project.data'] }
			'cmake' { paths << [base + 'build/project', base + 'project.data'] }
			else { paths << [base + 'project', base + 'project.data'] }
		}
	}
	return paths
}

pub struct Command {
pub:
	argv []string
	executable_sha256 string
	exit_code int
	log string
}

struct Verdict {
	profile string
	status string
	commands []Command
}

struct Report {
	schema int
	kernel string
	architecture string
	runner_sha256 string
	uid int
	context string
	requested []string
	command_timeout_seconds int
	complete bool
	all_selected_passed bool
	results []Verdict
}

// Independent receipt contracts for the public reference workflows. A passing
// marker or a version command cannot substitute for the planned project.
fn commands(profile string, work string) [][]string {
	bin := '/opt/reference/bin/'
	match profile {
		'make' { return [[bin + 'make', 'CC=' + bin + 'cc'], [work + '/project']] }
		'ninja' { return [[bin + 'ninja'], [work + '/project']] }
		'cmake' { return [[bin + 'cmake', '-S', '.', '-B', 'build', '-G', 'Ninja', '-DCMAKE_C_COMPILER=' + bin + 'cc'],
			[bin + 'cmake', '--build', 'build'], [work + '/build/project']] }
		'node' { return [[bin + 'node', 'project.js']] }
		'go' { return [[bin + 'go', 'build', '-trimpath', '-buildvcs=false', '-o', 'project', 'main.go'],
			[work + '/project']] }
		'sqlite' { return [[bin + 'sqlite3', 'project.db',
			'CREATE TABLE answer(n INTEGER); BEGIN; INSERT INTO answer VALUES(42); COMMIT; BEGIN; INSERT INTO answer VALUES(7); ROLLBACK;'],
			[bin + 'sqlite3', 'project.db', 'PRAGMA integrity_check; SELECT n FROM answer;']] }
		else { return [][]string{} }
	}
}

pub fn verify_report(text string, arch string, profiles []string, qualifier_sha string,
	tool_pins map[string]devcore.Pin, work string, outputs map[string]string) ! {
	report := json2.decode[Report](text, strict: true)!
	if report.schema != 1 || report.kernel != 'Vinix' || report.architecture != arch
		|| report.uid != 1000 || report.context != 'vinix-native' || report.command_timeout_seconds != 600
		|| report.runner_sha256 != qualifier_sha || !report.complete || !report.all_selected_passed
		|| report.requested != profiles || report.results.len != profiles.len {
		return error('reference qualification identity or verdict failed validation')
	}
	for i, result in report.results {
		profile := profiles[i]
		project := work + '/qualification/' + profile
		expected := commands(profile, project)
		if result.profile != profile || result.status != 'passed' || result.commands.len != expected.len {
			return error('reference profile workflow is incomplete')
		}
		for index, actual in result.commands {
			argv := expected[index]
			mut hash := ''
			if argv[0].starts_with('/opt/reference/bin/') {
				pin := tool_pins[os.base(argv[0])] or { return error('reference command tool is not pinned') }
				hash = pin.sha256
			} else {
				hash = outputs[argv[0].all_after(work + '/')] or { return error('executed reference artifact is missing') }
			}
			if actual.argv != argv || actual.exit_code != 0 || actual.executable_sha256 != hash
				|| hash.len != 64 || actual.log != project + '/command-' + index.str() + '.log' {
				return error('reference executed argv, executable pin, status or log changed')
			}
		}
	}
}
