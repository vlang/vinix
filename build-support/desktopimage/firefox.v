module desktopimage

import os

// All symlinks are interpreted inside the guest root, including absolute links.
// os.real_path would silently accept a dependency supplied by the build host.
fn guest_path(root string, path string) !string {
	mut pending := path.split('/')
	mut parts := []string{}
	mut links := 0
	for pending.len > 0 {
		part := pending[0]
		pending.delete(0)
		if part in ['', '.'] {
			continue
		}
		if part == '..' {
			if parts.len > 0 { parts.pop() }
			continue
		}
		candidate := root + '/' + [...parts, part].join('/')
		if os.is_link(candidate) {
			links++
			if links > 40 { return error('symlink loop: ${path}') }
			target := os.readlink(candidate)!
			if target.starts_with('/') { parts.clear() }
			mut expanded := target.split('/')
			expanded << pending
			pending = expanded.clone()
		} else {
			parts << part
		}
	}
	return root + '/' + parts.join('/')
}

fn required(root string, path string, executable bool) !string {
	resolved := guest_path(root, path)!
	if !os.is_file(resolved) || os.file_size(resolved) == 0 {
		return error('missing or empty ${path}')
	}
	if executable && !os.is_executable(resolved) {
		return error('not executable: ${path}')
	}
	return resolved
}

pub fn find_readelf() !string {
	configured := os.getenv('VINIX_DESKTOP_READELF')
	if configured != '' {
		return os.find_abs_path_of_executable(configured)
	}
	for name in ['llvm-readelf', 'readelf', '/opt/homebrew/opt/llvm/bin/llvm-readelf',
		'/usr/local/opt/llvm/bin/llvm-readelf'] {
		found := os.find_abs_path_of_executable(name) or { continue }
		return found
	}
	return error('install llvm-readelf/readelf or set VINIX_DESKTOP_READELF')
}

fn amd64_elf(path string) ! {
	mut file := os.open(path)!
	defer { file.close() }
	header := file.read_bytes(20)
	if header.len != 20 || header[..6] != [u8(0x7f), `E`, `L`, `F`, 2, 1]
		|| header[16] !in [u8(2), 3] || header[17..20] != [u8(0), 62, 0] {
		return error('not an amd64 ELF executable/shared object: ${path}')
	}
}

struct Dynamic {
	needed      []string
	paths       []string
	interpreter string
}

fn bracket(line string) !string {
	start := line.index('[') or { return error('malformed readelf line: ${line}') }
	end := line.last_index(']') or { return error('malformed readelf line: ${line}') }
	if end <= start + 1 { return error('empty readelf value: ${line}') }
	return line[start + 1..end]
}

fn parse_dynamic(output string) !Dynamic {
	mut needed := []string{}
	mut paths := []string{}
	mut interpreter := ''
	for line in output.split_into_lines() {
		if line.contains('(NEEDED)') { needed << bracket(line)! }
		if line.contains('(RPATH)') || line.contains('(RUNPATH)') {
			paths << bracket(line)!.split(':')
		}
		if line.contains('[Requesting program interpreter: ') {
			interpreter = bracket(line)!.all_after('Requesting program interpreter: ')
		}
	}
	return Dynamic{needed, paths, interpreter}
}

fn dynamic(reader string, path string) !Dynamic {
	amd64_elf(path)!
	mut process := os.new_process(reader)
	mut environment := os.environ()
	environment['LC_ALL'] = 'C'
	process.set_environment(environment)
	process.set_args(['--program-headers', '--dynamic', '--wide', path])
	process.set_redirect_stdio()
	process.run()
	output := process.stdout_slurp()
	diagnostics := process.stderr_slurp()
	process.wait()
	code := process.code
	process.close()
	if code != 0 || diagnostics.trim_space() != '' {
		return error('readelf rejected ${path}: ${diagnostics}')
	}
	return parse_dynamic(output)
}

fn library(root string, name string, origin string, paths []string) !string {
	if name.contains('/') {
		if !name.starts_with('/') { return error('relative dependency: ${name}') }
		return required(root, name, false)
	}
	// The hosted launcher's LD_LIBRARY_PATH, declared ELF paths (including
	// Firefox's $ORIGIN), then musl's default paths. Never search the host.
	mut directories := ['/usr/lib', '/usr/lib/xorg/modules']
	for path in paths {
		expanded := path.replace('\${ORIGIN}', origin).replace('$ORIGIN', origin)
		if !expanded.starts_with('/') || expanded.contains('$') {
			return error('unsupported library search path: ${path}')
		}
		directories << expanded
	}
	directories << ['/lib', '/usr/local/lib']
	for directory in directories {
		candidate := guest_path(root, directory + '/' + name)!
		if os.is_file(candidate) && os.file_size(candidate) > 0 { return candidate }
	}
	return error('missing dependency ${name} (from ${origin})')
}

fn closure(root string, reader string, seeds []string) ! {
	mut pending := seeds.clone()
	mut seen := map[string]bool{}
	for pending.len > 0 {
		path := pending.pop()
		if path in seen {
			continue
		}
		seen[path] = true
		info := dynamic(reader, path)!
		if info.interpreter != '' {
			pending << required(root, info.interpreter, true)!
		}
		origin := os.dir(path).trim_string_left(root)
		for name in info.needed {
			pending << library(root, name, origin, info.paths)!
		}
	}
}

// This is a packaging gate, not evidence that Firefox boots or renders on Vinix.
pub fn validate(root_path string, reader string) ! {
	root := os.real_path(root_path).trim_right('/')
	if root == '' || !os.is_dir(root) { return error('invalid staging root') }
	mut app := ''
	mut browser := ''
	for name in ['firefox-esr', 'firefox'] {
		candidate := guest_path(root, '/usr/lib/${name}/${name}')!
		if os.is_file(candidate) && os.is_executable(candidate) {
			app = '/usr/lib/${name}'
			browser = name
			break
		}
	}
	if app == '' { return error('missing executable Firefox application binary') }
	mut seeds := []string{}
	for path in ['${app}/${browser}', '${app}/libxul.so', '/usr/bin/Xorg', '/usr/bin/Xvfb',
		'/usr/bin/vinix-wine-host', '/usr/bin/vinix-xinput', '/usr/bin/xset', '/usr/bin/xkbcomp',
		'/usr/lib/libgtk-3.so.0', '/usr/lib/libavcodec.so.60', '/usr/lib/xorg/modules/dri/swrast_dri.so',
		'/usr/lib/xorg/modules/drivers/fbdev_drv.so'] {
		seeds << required(root, path, !path.ends_with('.so') && !path.contains('.so.'))!
	}
	// The hosted browser prefers this server when it is executable.
	glx := guest_path(root, '/usr/bin/Xvfb-glx')!
	if os.is_executable(glx) {
		seeds << required(root, '/usr/bin/Xvfb-glx', true)!
	}
	// Firefox dlopens companion libraries; DT_NEEDED on the small executable
	// alone does not cover Gecko, GTK glue or the media decoder libraries.
	for path in os.walk_ext(guest_path(root, app)!, '.so') {
		seeds << required(root, path.trim_string_left(root), false)!
	}
	for path in ['/usr/bin/${browser}', '/usr/bin/run-firefox', '/usr/bin/startx'] {
		resolved := required(root, path, true)!
		mut file := os.open(resolved)!
		header := file.read_bytes(256).bytestr()
		file.close()
		if header.starts_with('#!') {
			interpreter := header.all_before('\n')[2..].trim_space().all_before(' ')
			seeds << required(root, interpreter, true)!
		} else {
			seeds << resolved
		}
	}
	for path in ['${app}/application.ini', '${app}/omni.ja', '${app}/defaults/pref/vinix.js',
		'${app}/distribution/policies.json', '/etc/X11/xorg.conf', '/usr/share/X11/xkb/rules/evdev',
		'/usr/share/X11/xkb/keycodes/evdev', '/usr/share/X11/xkb/symbols/us',
		'/usr/share/X11/xkb/types/complete', '/usr/share/X11/xkb/compat/complete',
		'/etc/ssl/certs/ca-certificates.crt', '/usr/share/vinix/firefox-smoke.html'] {
		required(root, path, false)!
	}
	fonts := os.walk_ext(guest_path(root, '/usr/share/fonts')!, '.ttf')
	if fonts.len == 0 { return error('missing TrueType fonts') }
	required(root, fonts[0].trim_string_left(root), false)!
	closure(root, reader, seeds)!
}
