// SPDX-License-Identifier: GPL-2.0-or-later
module winehostimages

import os
import json2
import tests.packages.winesource

const clang = '/opt/homebrew/opt/llvm/bin/clang'
const linker = '/opt/homebrew/bin/ld.lld'

pub struct Image {
pub:
	path string
	uuid string
	sha256 string
}

pub struct Baseline {
pub:
	format int = 1
	recorded_directory string
	images []Image
}

pub fn managed(tool string) bool { return tool in [clang, linker] }

fn system(path string) bool {
	return path.starts_with('/usr/lib/') || path.starts_with('/System/Library/')
}

fn environment(directory string) map[string]string {
	return {'PATH': '/usr/bin:/bin', 'HOME': directory + '/host-home', 'TMPDIR': directory + '/host-tmp',
		'LANG': 'C', 'LC_ALL': 'C', 'TZ': 'UTC', 'SOURCE_DATE_EPOCH': '0', 'DYLD_PRINT_LIBRARIES': '1'}
}

fn safe_path(path string) bool {
	if !os.is_abs_path(path) || path.len > 4096 || path.contains('\r') || path.contains('\n') || path.contains('\x00') { return false }
	for part in path.split('/')[1..] { if part in ['', '.', '..'] { return false } }
	return true
}

// dyld may print images from multiple child PIDs. Preserve one identity per
// path and reject disagreement; OS namespaces are metadata-only, never bytes.
pub fn trace(text string) ![]Image {
	if text.len > 8 * 1024 * 1024 || text.contains('\r') || text.contains('\x00') {
		return error('invalid host image trace control byte or size')
	}
	mut found := map[string]string{}
	mut names := map[string]bool{}
	for line in text.split_into_lines() {
		if !line.starts_with('dyld[') { return error('invalid host image trace line') }
		end := line.index(']: ') or { return error('invalid host image trace PID') }
		pid := line[5..end]
		if pid == '' || pid.bytes().any(it < `0` || it > `9`) { return error('invalid host image trace PID') }
		payload := line[end + 3..]
		delay_prefix := 'move loaded to delayed: '
		if payload.starts_with(delay_prefix) {
			if pid + '/' + payload[delay_prefix.len..] !in names { return error('host delayed image notice has no prior observation') }
			continue
		}
		if !payload.starts_with('<') { return error('unsupported host image trace diagnostic') }
		start := end + 4
		if line.len < start + 38 || line[start + 36..start + 38] != '> ' { return error('invalid host image UUID record') }
		uuid := line[start..start + 36]
		for index, byte in uuid.bytes() {
			if index in [8, 13, 18, 23] { if byte != `-` { return error('invalid host image UUID') } }
			else if !byte.is_hex_digit() { return error('invalid host image UUID') }
		}
		path := line[start + 38..]
		if !safe_path(path) || found.len >= 4096 { return error('invalid host image path or count') }
		if path in found && found[path] != uuid { return error('host image UUID changed within command') }
		found[path] = uuid
		names[pid + '/' + os.file_name(path)] = true
	}
	if found.len == 0 { return error('host image trace is empty') }
	mut paths := found.keys(); paths.sort()
	return paths.map(Image{path: it, uuid: found[it]})
}

fn record(path string) !string {
	st := os.lstat(path)!
	if st.get_filetype() != .regular || st.size < 1 || st.size > 8 * 1024 * 1024 {
		return error('host image evidence must be a bounded ordinary file')
	}
	return os.read_file(path)
}

fn capture(observed []Image) ![]Image {
	mut result := []Image{}
	for image in observed {
		if system(image.path) { result << image; continue }
		if os.real_path(image.path) != image.path || os.lstat(image.path)!.get_filetype() != .regular {
			return error('host image must be a canonical ordinary file')
		}
		result << Image{path: image.path, uuid: image.uuid, sha256: winesource.file_digest(image.path)!}
	}
	return result
}

fn raw(command []string, cwd string, log string, env map[string]string) ![]Image {
	os.write_file(log + '.argv.json', json2.encode(command) + '\n')!
	os.write_file(log + '.environment.json', json2.encode(env) + '\n')!
	mut child := os.new_process(command[0])
	defer { child.close() }
	child.set_args(command[1..]); child.set_work_folder(cwd); child.set_environment(env)
	child.set_redirect_stdio_merged(); child.run()
	C.close(child.stdio_fd[0]); child.stdio_fd[0] = -1
	text := child.stdout_slurp(); child.wait()
	if text.contains('\r') || text.contains('\x00') {
		os.write_file(log + '.failed-raw.log', text)!
		return error('invalid host command output control byte')
	}
	mut dyld := []string{}
	mut body := []string{}
	for line in text.split_into_lines() {
		if line.starts_with('dyld[') { dyld << line } else { body << line }
	}
	os.write_file(log, body.join('\n') + if body.len > 0 { '\n' } else { '' })!
	trace_text := dyld.join('\n') + '\n'
	os.write_file(log + '.dyld.log', trace_text)!
	if child.code != 0 { return error('host image command failed: ' + log) }
	images := capture(trace(trace_text)!)!
	if !images.any(it.path == os.real_path(command[0])) { return error('host image executable observation missing') }
	os.write_file(log + '.images.json', json2.encode(images) + '\n')!
	return images
}

fn merge(first []Image, second []Image) ![]Image {
	mut by_path := map[string]Image{}
	for image in [...first, ...second] {
		if image.path in by_path && by_path[image.path] != image { return error('host probe image identities differ') }
		by_path[image.path] = image
	}
	mut paths := by_path.keys(); paths.sort()
	return paths.map(by_path[it])
}

fn compatible(actual []Image, expected []Image) ! {
	mut known := map[string]Image{}
	for image in expected { known[image.path] = image }
	for image in actual {
		if system(image.path) {
			if image.sha256 != '' { return error('OS host images must remain explicitly unadmitted') }
			if image.path in known && known[image.path].uuid != image.uuid { return error('OS host image UUID differs') }
		} else if image.path !in known || image != known[image.path] {
			return error('host image absent or changed from before-command probes')
		}
	}
}

pub fn invoke(command []string, cwd string, log string) !string {
	if command.len == 0 || !managed(command[0]) { return error('unsupported host image tool') }
	directory := os.dir(log)
	for name in ['host-home', 'host-tmp'] {
		os.mkdir_all(directory + '/' + name)!
		if os.real_path(directory + '/' + name) != directory + '/' + name { return error('host tool environment directory is not canonical') }
	}
	env := environment(directory)
	baseline_path := directory + '/host-images-before.json'
	if !os.exists(baseline_path) && !os.is_link(baseline_path) {
		first := raw([clang, '--version'], directory, directory + '/host-clang-version.log', env)!
		second := raw([linker, '--version'], directory, directory + '/host-linker-version.log', env)!
		os.write_file(baseline_path, json2.encode(Baseline{recorded_directory: directory, images: merge(first, second)!}) + '\n')!
	}
	baseline := json2.decode[Baseline](record(baseline_path)!)!
	if baseline.format != 1 || baseline.recorded_directory != directory { return error('host image before-command namespace differs') }
	actual := raw(command, cwd, log, env)!
	compatible(actual, baseline.images)!
	return os.read_file(log)
}

fn admit_record(log string, env map[string]string, tool string) ![]Image {
	images := json2.decode[[]Image](record(log + '.images.json')!)!
	observed := trace(record(log + '.dyld.log')!)!
	if images.len != observed.len { return error('host image observations differ') }
	for index, image in images {
		if image.path != observed[index].path || image.uuid != observed[index].uuid
			|| (system(image.path) && image.sha256 != '') { return error('host image observations differ') }
	}
	if !images.any(it.path == os.real_path(tool)) { return error('host image executable observation missing') }
	if json2.decode[map[string]string](record(log + '.environment.json')!)! != env { return error('host tool environment differs') }
	args := json2.decode[[]string](record(log + '.argv.json')!)!
	if args.len == 0 || args[0] != tool { return error('host image command tool differs') }
	return images
}

fn admit_names(directory string, recorded string, names []string) ! {
	baseline := json2.decode[Baseline](record(directory + '/host-images-before.json')!)!
	if baseline.format != 1 || !os.is_abs_path(recorded) || baseline.recorded_directory != recorded {
		return error('host image before-command namespace differs')
	}
	env := environment(recorded)
	first := admit_record(directory + '/host-clang-version.log', env, clang)!
	second := admit_record(directory + '/host-linker-version.log', env, linker)!
	for pair in [['host-clang-version.log', clang], ['host-linker-version.log', linker]] {
		if json2.decode[[]string](record(directory + '/' + pair[0] + '.argv.json')!)! != [pair[1], '--version'] {
			return error('host image probe argv differs')
		}
	}
	if merge(first, second)! != baseline.images { return error('host image before-command receipts differ') }
	for name in names {
		tool := if name in ['link-version.log', 'link-replay.log'] { linker } else { clang }
		compatible(admit_record(directory + '/' + name, env, tool)!, baseline.images)!
	}
	for image in baseline.images {
		if system(image.path) { continue }
		if os.real_path(image.path) != image.path || os.lstat(image.path)!.get_filetype() != .regular
			|| winesource.file_digest(image.path)! != image.sha256 { return error('host image bytes or target changed') }
	}
}

pub fn admit_link(directory string, recorded string) ! {
	admit_names(directory, recorded, ['c-discover.log', 'cc.log', 'link-version.log', 'link-replay.log'])!
}

// Host Mach-O builds admit observed C children without claiming ELF replay.
pub fn admit_c(directory string, recorded string) ! {
	admit_names(directory, recorded, ['clang-resource.log', 'c-discover.log', 'cc.log'])!
}

pub fn c_artifacts() []string {
	mut result := ['host-images-before.json']
	for name in ['host-clang-version.log', 'host-linker-version.log'] { result << [name, name + '.argv.json'] }
	for name in ['host-clang-version.log', 'host-linker-version.log', 'clang-resource.log', 'c-discover.log', 'cc.log'] {
		for suffix in ['.environment.json', '.dyld.log', '.images.json'] { result << name + suffix }
	}
	return result
}

pub fn admit_build(directory string, recorded string) ! {
	admit_names(directory, recorded, ['clang-resource.log', 'c-discover.log', 'cc.log', 'link-version.log', 'link-replay.log'])!
}

pub fn artifacts() []string {
	mut result := ['host-images-before.json']
	for name in ['host-clang-version.log', 'host-linker-version.log'] {
		result << [name, name + '.argv.json']
	}
	for name in ['host-clang-version.log', 'host-linker-version.log', 'clang-resource.log', 'c-discover.log', 'cc.log', 'link-version.log', 'link-replay.log'] {
		for suffix in ['.environment.json', '.dyld.log', '.images.json'] { result << name + suffix }
	}
	return result
}

pub fn inputs(directory string) !map[string]string {
	baseline := json2.decode[Baseline](record(directory + '/host-images-before.json')!)!
	mut result := map[string]string{}
	for image in baseline.images { if !system(image.path) { result[image.path] = image.sha256 } }
	return result
}

// V's source-generation phase has a separate, selected executable and private
// module/home/tmp namespaces. No caller flags, module search or fallback enter.
fn v_environment(directory string, tool string) map[string]string {
	mut env := environment(directory)
	env['HOME'] = directory + '/v-host-home'
	env['TMPDIR'] = directory + '/v-host-tmp'
	env['VMODULES'] = directory + '/v-host-modules'
	env['VEXE'] = tool
	env['V_MACOS_V3_CALLER_VEXE'] = tool
	env['V_MACOS_V3_CALLER_VEXE_PRESENT'] = '1'
	env['V_MACOS_V3_CALLER_VCHILD_PRESENT'] = '0'
	env['V_MACOS_V3_NO_FALLBACK'] = '1'
	return env
}

fn v_tool(tool string) ! {
	if !safe_path(tool) || os.real_path(tool) != tool || os.lstat(tool)!.get_filetype() != .regular {
		return error('V host compiler must be a canonical ordinary file')
	}
}

pub fn invoke_v(command []string, cwd string, log string) !string {
	if command.len == 0 { return error('missing V host compiler') }
	tool := command[0]
	v_tool(tool)!
	directory := os.dir(log)
	for name in ['v-host-home', 'v-host-tmp', 'v-host-modules'] {
		path := directory + '/' + name
		os.mkdir_all(path)!
		if os.real_path(path) != path || os.lstat(path)!.get_filetype() != .directory {
			return error('V host environment directory is not canonical')
		}
		os.chmod(path, 0o700)!
	}
	env := v_environment(directory, tool)
	baseline_path := directory + '/v-host-images-before.json'
	if !os.exists(baseline_path) && !os.is_link(baseline_path) {
		images := raw([tool, '-version'], directory, directory + '/host-v-version.log', env)!
		os.write_file(baseline_path, json2.encode(Baseline{recorded_directory: directory, images: images}) + '\n')!
	}
	baseline := json2.decode[Baseline](record(baseline_path)!)!
	if baseline.format != 1 || baseline.recorded_directory != directory { return error('V host before-command namespace differs') }
	compatible(raw(command, cwd, log, env)!, baseline.images)!
	return os.read_file(log)
}

pub fn admit_v(directory string, recorded string, tool string, inputs map[string]string) ! {
	v_tool(tool)!
	if tool !in inputs || winesource.file_digest(tool)! != inputs[tool] { return error('V host compiler input absent or changed') }
	baseline := json2.decode[Baseline](record(directory + '/v-host-images-before.json')!)!
	if baseline.format != 1 || !os.is_abs_path(recorded) || baseline.recorded_directory != recorded {
		return error('V host before-command namespace differs')
	}
	env := v_environment(recorded, tool)
	probe := directory + '/host-v-version.log'
	if json2.decode[[]string](record(probe + '.argv.json')!)! != [tool, '-version'] { return error('V host probe argv differs') }
	if admit_record(probe, env, tool)! != baseline.images { return error('V host before-command receipts differ') }
	for name in ['discover.log', 'v.log'] {
		compatible(admit_record(directory + '/' + name, env, tool)!, baseline.images)!
	}
	for image in baseline.images {
		if system(image.path) { continue }
		if os.real_path(image.path) != image.path || os.lstat(image.path)!.get_filetype() != .regular
			|| winesource.file_digest(image.path)! != image.sha256 { return error('V host image bytes or target changed') }
	}
}

pub fn v_artifacts() []string {
	mut result := ['v-host-images-before.json', 'host-v-version.log', 'host-v-version.log.argv.json']
	for name in ['host-v-version.log', 'discover.log', 'v.log'] {
		for suffix in ['.environment.json', '.dyld.log', '.images.json'] { result << name + suffix }
	}
	return result
}

pub fn v_inputs(directory string) !map[string]string {
	baseline := json2.decode[Baseline](record(directory + '/v-host-images-before.json')!)!
	mut result := map[string]string{}
	for image in baseline.images { if !system(image.path) { result[image.path] = image.sha256 } }
	return result
}
