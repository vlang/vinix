// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import tools.packages.appsdk

pub struct Launch {
pub:
	program   string
	arguments []string
	directory string
}

fn validate_launch_document(path string) ! {
	if !path.starts_with('/') || !printable(path, 4096) {
		return error('document must be an existing absolute regular file')
	}
	// Follow document aliases as before, but inspect the target type. os.is_file
	// only excludes directories and would also admit devices, FIFOs and sockets.
	info := os.stat(path) or {
		return error('document must be an existing absolute regular file: ${path}')
	}
	if info.get_filetype() != .regular {
		return error('document must be an existing absolute regular file: ${path}')
	}
}

fn application_closure(state State, id string) []Installed {
	mut pending := [id]
	mut seen := map[string]bool{}
	mut result := []Installed{}
	for pending.len > 0 {
		name := pending.pop()
		if name in seen { continue }
		seen[name] = true
		for installed in state.packages {
			if installed.package.id != name { continue }
			result << installed
			for dependency in installed.package.dependencies { pending << dependency.id }
		}
	}
	return result
}

pub fn launch_plan(config Config, directory string, state State, id string, data string, uid int, gid int, documents []string) !Launch {
	return application_launch_plan(config, directory, state, id, data, uid, gid, LaunchInput{ documents: documents })
}

pub fn terminal_launch_plan(config Config, directory string, state State, id string, data string, uid int, gid int, documents []string) !Launch {
	return application_launch_plan(config, directory, state, id, data, uid, gid, LaunchInput{ documents: documents, terminal: true })
}

pub fn command_launch_plan(config Config, directory string, state State, id string, data string, uid int, gid int, input CommandLaunch, terminal bool) !Launch {
	validate_command(input)!
	return application_launch_plan(config, directory, state, id, data, uid, gid, LaunchInput{
		documents: input.documents, arguments: input.arguments, terminal: terminal, command: true, data_cwd: input.data_cwd })
}

fn application_launch_plan(config Config, directory string, state State, id string, data string, uid int, gid int, input LaunchInput) !Launch {
	if !identifier(id) || uid <= 0 || gid <= 0 || !data.starts_with('/') || data.contains('\x00') {
		return error('launch requires a non-root identity and an absolute application data directory')
	}
	validate_state(state, config.architecture)!
	selected := state.packages.filter(it.package.id == id)
	if selected.len != 1 || selected[0].package.kind in ['data', 'runtime'] {
		return error('application is not installed: ${id}')
	}
	installed := selected[0]
	p := installed.package
	if input.window && (p.window_protocol !in [1, 2] || p.kind != 'native' || 'display' !in p.permissions) {
		return error('${id}: the installed application does not support a native window protocol')
	}
	check_policy(p, config.policy)!
	if !config.repositories.any(it.id == installed.repository && it.public_key == installed.public_key) {
		return error('${id}: publisher key has been revoked')
	}
	generation := directory + '/generations/' + state.generation.str()
	app := generation + '/apps/' + id
	runtime := if p.runtime == '' { app } else { generation + '/apps/' + p.runtime }
	mut args := ['--uid', uid.str(), '--gid', gid.str()]
	// Advisory locks coordinate writes to already unveiled app data. They grant
	// no additional paths or inherited descriptors; SQLite requires F_SETLK.
	mut promises := ['stdio', 'rpath', 'wpath', 'cpath', 'flock', 'exec', 'prot_exec']
	if input.terminal { promises << 'tty' }
	if 'network' in p.permissions { promises << ['inet', 'dns'] }
	if 'process' in p.permissions { promises << 'proc' }
	if 'display' in p.permissions && !input.window { promises << 'unix' }
	args << ['--promises', promises.join(' '), '--unveil', app, 'rx', '--unveil', data, 'rwc']
	if runtime != app { args << ['--unveil', runtime, 'rx'] }
	mut libraries := [app + '/lib', app + '/usr/lib', runtime + '/lib', runtime + '/usr/lib']
	for dependency in application_closure(state, id) {
		check_policy(dependency.package, config.policy)!
		if !config.repositories.any(it.id == dependency.repository && it.public_key == dependency.public_key) {
			return error('${dependency.package.id}: dependency publisher key has been revoked')
		}
		if dependency.package.id in [id, p.runtime] { continue }
		path := generation + '/apps/' + dependency.package.id
		args << ['--unveil', path, 'rx']
		libraries << path + '/lib'
		libraries << path + '/usr/lib'
	}
	args << ['--env', 'HOME=' + data, '--env', 'TMPDIR=' + data + '/tmp', '--env',
		'PATH=' + runtime + '/bin', '--env', 'LD_LIBRARY_PATH=' + libraries.join(':'), '--env',
		'WINEPREFIX=' + data + '/wine', '--env', 'LANG=C.UTF-8']
	runtime_version := if p.runtime == '' { p.version } else { state.packages.filter(it.package.id == p.runtime)[0].package.version }
	context := appsdk.Context{ id: p.id, version: p.version, architecture: config.architecture, kind: p.kind,
		generation: state.generation, repository: installed.repository, public_key: installed.public_key, sequence: installed.sequence,
		app_directory: app, data_directory: data, runtime_id: p.runtime, runtime_version: runtime_version,
		runtime_directory: runtime, permissions: p.permissions }
	mut environment := context.environment()!
	defer { appsdk.free_values(mut environment) }
	for value in environment { args << '--env'; args << value.clone() }
	if input.terminal { args << ['--env', 'TERM=linux'] }
	if input.window { args << ['--env', if p.window_protocol == 1 { 'VINIX_WINDOW_PROTOCOL=1' } else { 'VINIX_WINDOW_PROTOCOL=2' }] }
	if 'display' in p.permissions && !input.window {
		args << ['--unveil', '/tmp/.X11-unix', 'rw', '--env', 'DISPLAY=' + os.getenv('DISPLAY')]
	}
	if 'audio' in p.permissions { args << ['--unveil', '/dev/snd', 'rw'] }
	for document in input.documents {
		validate_launch_document(document)!
		if 'files' !in p.permissions { return error('${id}: file permission is not declared') }
		args << ['--unveil', document, 'rw']
	}
	args << ['--', runtime + '/' + p.entrypoint]
	for argument in p.arguments {
		args << argument.replace('@APP@', app).replace('@DATA@', data).replace('@RUNTIME@', runtime)
	}
	args << input.arguments
	if !input.command { args << input.documents }
	return Launch{ program: '/usr/bin/vinix-sandbox', arguments: args, directory: if input.command && input.data_cwd { data } else { app } }
}

pub fn run_application(config Config, directory string, id string, documents []string) !int {
	if int(C.geteuid()) == 0 {
		// The ordinary child re-reads policy, verifies the current generation and
		// owns its lease. Root never creates or chmods files in a user's home.
		return run_in_session(config, id, documents)
	}
	// A reader locks the activation pointer until its generation lease is held.
	fd := C.open((directory + '/lock').str, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW)
	if fd < 0 || C.flock(fd, C.LOCK_SH) != 0 {
		if fd >= 0 { C.close(fd) }
		return error('cannot read package state lock')
	}
	state, lease := generation_lease(directory, config.architecture, id) or {
		C.close(fd)
		return err
	}
	C.close(fd)
	defer { C.close(lease) }
	return run_leased_application(config, directory, state, id, documents)
}

// The caller holds the package reader lock until this lease has been acquired.
fn generation_lease(directory string, architecture string, id string) !(State, int) {
	state := read_state(directory, architecture)!
	if state.generation == 0 || !state.packages.any(it.package.id == id) {
		return error('application is not installed: ${id}')
	}
	lease_path := directory + '/generations/' + state.generation.str() + '/lease'
	lease := C.open(lease_path.str, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW)
	if lease < 0 || C.flock(lease, C.LOCK_SH) != 0 {
		if lease >= 0 { C.close(lease) }
		return error('cannot hold application generation lease')
	}
	return state, lease
}

fn run_leased_application(config Config, directory string, state State, id string, documents []string) !int {
	return run_leased_mode(config, directory, state, id, LaunchInput{ documents: documents })
}

fn run_leased_mode(config Config, directory string, state State, id string, input LaunchInput) !int {
	uid := int(C.geteuid())
	gid := int(C.getegid())
	if uid == 0 || gid == 0 { return error('run applications from an ordinary user session') }
	home := os.home_dir()
	if home == '' || !home.starts_with('/') { return error('user home directory is unavailable') }
	data := home.trim_right('/') + '/.local/share/vinix-apps/' + id
	launch := application_launch_plan(config, directory, state, id, data, uid, gid, input)!
	for installed in application_closure(state, id) {
		check_policy(installed.package, config.policy)!
		if !config.repositories.any(it.id == installed.repository && it.public_key == installed.public_key) {
			return error('runtime publisher key has been revoked')
		}
		for file in installed.package.files {
			path := directory + '/generations/' + state.generation.str() + '/apps/' + installed.package.id + '/' + file.path
			if !verified_file(path, file) {
				return error('installed application payload changed: ${path}')
			}
		}
	}
	os.mkdir_all(data + '/tmp')!
	os.chmod(data, 0o700)!
	mut process := os.new_process(launch.program)
	process.set_args(launch.arguments)
	process.set_work_folder(launch.directory)
	process.wait()
	code := process.code
	process.close()
	return code
}
