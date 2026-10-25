// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import os
import tools.packages.appsdk
import tools.packages.x11auth

pub struct Launch {
pub:
	program   string
	arguments []string
	directory string
}

// Plans returned by the launch planners own all fields independently of their
// inputs. Retire after the process has finished using the argument vector.
pub fn (mut launch Launch) close() {
	mut owned_arguments := unsafe { launch.arguments }
	appsdk.free_values(mut owned_arguments)
	unsafe { launch.program.free(); launch.directory.free() }
	launch = Launch{}
}

// Transfer one owned string (or a literal) without V's implicit append clone.
fn launch_take(mut values []string, value string) {
	unsafe { values.push_many(&value, 1) }
}

fn launch_unveil(mut args []string, path string, permissions string) {
	args << '--unveil'
	args << path.clone()
	args << permissions.clone()
}

// value is transferred to the argument vector, including on later refusal.
fn launch_environment(mut args []string, value string) {
	args << '--env'
	launch_take(mut args, value)
}

fn launch_x11(mut args []string, uid int, root string, system_owner u32) ! {
	display := os.getenv('DISPLAY')
	authority := os.getenv('XAUTHORITY')
	defer { unsafe { display.free(); authority.free() } }
	if uid != int(C.geteuid()) || !x11auth.admit(root.str, authority.str, display.str, u32(uid), system_owner) {
		return error('graphical launch requires an authenticated private display owned by this account')
	}
	// Xlib's local socket and authority are the only X11 filesystem grants.
	// Do not unveil the global socket directory or inherit an ambient authority.
	number := unsafe { tos(display.str + 1, display.len - 1) }
	socket := root + 'tmp/.X11-unix/X' + number
	defer { unsafe { socket.free() } }
	launch_unveil(mut args, socket, 'rw')
	launch_unveil(mut args, authority, 'r')
	launch_environment(mut args, 'DISPLAY=' + display)
	launch_environment(mut args, 'XAUTHORITY=' + authority)
}

fn validate_launch_document(path string) ! {
	if !path.starts_with('/') || !printable(path, 4096) {
		return error('document must be an existing absolute regular file')
	}
	// Follow document aliases as before, but inspect the target type. os.is_file
	// only excludes directories and would also admit devices, FIFOs and sockets.
	// Keep the native stat scratch on the stack under the manual-free compiler.
	mut info := C.stat{}
	if C.fstatat(C.AT_FDCWD, path.str, unsafe { &info }, 0) != 0 || info.st_mode & 0o170000 != 0o100000 {
		return error('document must be an existing absolute regular file: ${path}')
	}
}

fn application_closure(state State, id string) []Installed {
	mut pending := [id]
	mut seen := map[string]bool{}
	mut result := []Installed{}
	unsafe { pending.flags |= .noslices; result.flags |= .noslices }
	// Pending names and result manifests borrow state; only seen owns key copies.
	defer { unsafe { (&array(&pending)).free(); seen.free() } }
	for pending.len > 0 {
		name := pending.pop()
		if name in seen { continue }
		seen[name] = true
		for installed in state.packages {
			if installed.package.id != name { continue }
			unsafe { result.push_many(&installed, 1) }
			for dependency in installed.package.dependencies {
				unsafe { pending.push_many(&dependency.id, 1) }
			}
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
	mut selected := -1
	for index, item in state.packages { if item.package.id == id { selected = index; break } }
	if selected < 0 || state.packages[selected].package.kind in ['data', 'runtime'] {
		return error('application is not installed: ${id}')
	}
	installed := state.packages[selected]
	p := installed.package
	if input.window && (p.window_protocol !in [1, 2] || p.kind != 'native' || 'display' !in p.permissions) {
		return error('${id}: the installed application does not support a native window protocol')
	}
	check_policy(p, config.policy)!
	if !config.repositories.any(it.id == installed.repository && it.public_key == installed.public_key) {
		return error('${id}: publisher key has been revoked')
	}
	closure := application_closure(state, id)
	defer { unsafe { (&array(&closure)).free() } }
	require_publisher_keys(closure)!
	number := state.generation.str()
	generation := directory + '/generations/' + number
	app := generation + '/apps/' + id
	runtime := if p.runtime == '' { app.clone() } else { generation + '/apps/' + p.runtime }
	defer { unsafe { number.free(); generation.free(); app.free(); runtime.free() } }
	mut args := ['--uid', uid.str(), '--gid', gid.str()]
	unsafe { args.flags |= .noslices }
	mut accepted := false
	defer { if !accepted { appsdk.free_values(mut args) } }
	// Advisory locks coordinate writes to already unveiled app data. They grant
	// no additional paths or inherited descriptors; SQLite requires F_SETLK.
	mut promises := []string{cap: 12}
	for value in ['stdio', 'rpath', 'wpath', 'cpath', 'flock', 'exec', 'prot_exec']! { promises << value.clone() }
	defer { appsdk.free_values(mut promises) }
	if input.terminal { promises << 'tty' }
	if 'network' in p.permissions { promises << 'inet'; promises << 'dns' }
	if 'process' in p.permissions { promises << 'proc' }
	// Child processes use socketpair and local RPC as well as fork/exec. This
	// grants no extra paths; pathname sockets remain subject to unveil.
	if 'process' in p.permissions || 'audio' in p.permissions || ('display' in p.permissions && !input.window) { promises << 'unix' }
	args << '--promises'; args << promises.join(' ')
	launch_unveil(mut args, app, 'rx')
	launch_unveil(mut args, data, 'rwc')
	if runtime != app { launch_unveil(mut args, runtime, 'rx') }
	mut libraries := [app + '/lib', app + '/usr/lib', runtime + '/lib', runtime + '/usr/lib']
	unsafe { libraries.flags |= .noslices }
	defer { appsdk.free_values(mut libraries) }
	for dependency in closure {
		check_policy(dependency.package, config.policy)!
		if !config.repositories.any(it.id == dependency.repository && it.public_key == dependency.public_key) {
			return error('${dependency.package.id}: dependency publisher key has been revoked')
		}
		if dependency.package.id in [id, p.runtime] { continue }
		path := generation + '/apps/' + dependency.package.id
		defer { unsafe { path.free() } }
		launch_unveil(mut args, path, 'rx')
		libraries << path + '/lib'
		libraries << path + '/usr/lib'
	}
	library_path := libraries.join(':')
	defer { unsafe { library_path.free() } }
	launch_environment(mut args, 'HOME=' + data)
	launch_environment(mut args, 'TMPDIR=' + data + '/tmp')
	launch_environment(mut args, 'PATH=' + runtime + '/bin')
	launch_environment(mut args, 'LD_LIBRARY_PATH=' + library_path)
	launch_environment(mut args, 'WINEPREFIX=' + data + '/wine')
	launch_environment(mut args, 'LANG=C.UTF-8')
	if p.kind == 'apple' {
		// Foundation and the compatibility keychain have their own container
		// overrides. Derive them from admitted private data, never ambient env
		// or the immutable application bundle. Existing unveil grants suffice.
		launch_environment(mut args, 'VINIX_IOS_DOCUMENTS=' + data + '/Documents')
		launch_environment(mut args, 'VINIX_IOS_KEYCHAIN=' + data + '/Keychains')
	}
	mut runtime_version := p.version
	for item in state.packages { if item.package.id == p.runtime { runtime_version = item.package.version; break } }
	context := appsdk.Context{ id: p.id, version: p.version, architecture: config.architecture, kind: p.kind,
		generation: state.generation, repository: installed.repository, public_key: installed.public_key, sequence: installed.sequence,
		app_directory: app, data_directory: data, runtime_id: p.runtime, runtime_version: runtime_version,
		runtime_directory: runtime, permissions: p.permissions }
	mut environment := context.environment()!
	defer { appsdk.free_values(mut environment) }
	for value in environment { launch_environment(mut args, value.clone()) }
	if input.terminal { launch_environment(mut args, 'TERM=linux') }
	if input.window { launch_environment(mut args, if p.window_protocol == 1 { 'VINIX_WINDOW_PROTOCOL=1' } else { 'VINIX_WINDOW_PROTOCOL=2' }) }
	if 'display' in p.permissions && !input.window {
		launch_x11(mut args, uid, '/', 0)!
	}
	if 'audio' in p.permissions { launch_audio(mut args, id, uid, state.generation, p)! }
	for document in input.documents {
		validate_launch_document(document)!
		if 'files' !in p.permissions { return error('${id}: file permission is not declared') }
		launch_unveil(mut args, document, 'rw')
	}
	args << '--'; args << runtime + '/' + p.entrypoint
	for argument in p.arguments {
		app_argument := argument.replace('@APP@', app)
		data_argument := app_argument.replace('@DATA@', data)
		defer { unsafe { app_argument.free(); data_argument.free() } }
		args << data_argument.replace('@RUNTIME@', runtime)
	}
	for argument in input.arguments { args << argument.clone() }
	if !input.command { for document in input.documents { args << document.clone() } }
	accepted = true
	return Launch{ program: '/usr/bin/vinix-sandbox', arguments: args, directory: if input.command && input.data_cwd { data.clone() } else { app.clone() } }
}

pub fn run_application(config Config, directory string, id string, documents []string) !int {
	if int(C.geteuid()) == 0 {
		// The ordinary child re-reads policy, verifies the current generation and
		// owns its lease. Root never creates or chmods files in a user's home.
		return run_in_session(config, id, documents)
	}
	// A reader locks the activation pointer until its generation lease is held.
	guard := acquire_reader(directory)!
	state, lease := generation_lease(directory, config.architecture, id) or {
		guard.release()
		return err
	}
	guard.release()
	defer { C.close(lease); close_decoded_state(state) }
	return run_leased_application(config, directory, state, id, documents)
}

// The caller holds the package reader lock until this lease has been acquired.
fn generation_lease(directory string, architecture string, id string) !(State, int) {
	state := read_state(directory, architecture)!
	mut admitted := false
	defer { if !admitted && state.generation != 0 { close_decoded_state(state) } }
	if state.generation == 0 || !state.packages.any(it.package.id == id) {
		return error('application is not installed: ${id}')
	}
	number := state.generation.str()
	lease_path := directory + '/generations/' + number + '/lease'
	defer { unsafe { lease_path.free(); number.free() } }
	lease := C.open(lease_path.str, C.O_RDONLY | C.O_CLOEXEC | C.O_NOFOLLOW | C.O_NONBLOCK)
	if lease < 0 { return error('cannot open application generation lease; repair package state before retrying') }
	check_coordination_file(lease, lease_path, 'application generation lease') or { C.close(lease); return err }
	if C.flock(lease, C.LOCK_SH | C.LOCK_NB) != 0 {
		C.close(lease)
		return error('cannot hold application generation lease; another holder may be collecting it, retry after it finishes')
	}
	check_coordination_file(lease, lease_path, 'application generation lease') or { C.close(lease); return err }
	admitted = true
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
	defer { unsafe { home.free() } }
	if home == '' || !home.starts_with('/') { return error('user home directory is unavailable') }
	home_prefix := home.trim_right('/')
	data := home_prefix + '/.local/share/vinix-apps/' + id
	defer { unsafe { data.free(); home_prefix.free() } }
	mut launch := application_launch_plan(config, directory, state, id, data, uid, gid, input)!
	defer { launch.close() }
	verify_launch_payloads(config, directory, state, id)!
	prepare_launch_data(home, id, u32(uid))!
	return run_launch_process(launch)
}

// Shared by actual execution and the pre-isolation audio admission. Holding
// the caller's generation lease keeps this exact verified closure available.
fn verify_launch_payloads(config Config, directory string, state State, id string) ! {
	closure := application_closure(state, id)
	defer { unsafe { (&array(&closure)).free() } }
	require_publisher_keys(closure)!
	number := state.generation.str()
	generation := directory + '/generations/' + number
	defer { unsafe { number.free(); generation.free() } }
	for installed in closure {
		check_policy(installed.package, config.policy)!
		if !config.repositories.any(it.id == installed.repository && it.public_key == installed.public_key) {
			return error('runtime publisher key has been revoked')
		}
		verify_installed_namespace(directory, state.generation, installed.package)!
		for file in installed.package.files {
			path := generation + '/apps/' + installed.package.id + '/' + file.path
			defer { unsafe { path.free() } }
			if !verified_installed_file(path, file) {
				return error('installed application payload changed: ${path}')
			}
		}
		registration_valid := verified_registration(generation, installed.package)
		if !registration_valid {
			return error('${installed.package.id}: installed application registration verification failed; use Repair installed or vinix-package repair')
		}
	}
}
