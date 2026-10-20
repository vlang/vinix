module desktopimage

import os
import time

fn put(mut data []u8, at int, value u64, count int) {
	for i in 0 .. count {
		data[at + i] = u8(value >> (i * 8))
	}
}

// Small ELF64 dynamic fixtures consumed by the real readelf. No guest code runs.
fn elf_fixture(needed string, interpreter string) []u8 {
	mut data := []u8{len: 1024}
	for i, byte in [u8(0x7f), `E`, `L`, `F`, 2, 1, 1] {
		data[i] = byte
	}
	put(mut data, 16, 3, 2)
	put(mut data, 18, 62, 2)
	put(mut data, 20, 1, 4)
	put(mut data, 32, 64, 8)
	put(mut data, 52, 64, 2)
	put(mut data, 54, 56, 2)
	put(mut data, 56, if interpreter == '' { u64(2) } else { 3 }, 2)
	put(mut data, 64, 1, 4) // PT_LOAD covers dynamic strings
	put(mut data, 68, 5, 4)
	put(mut data, 80, 0x400000, 8)
	put(mut data, 96, u64(data.len), 8)
	put(mut data, 104, u64(data.len), 8)
	put(mut data, 112, 4096, 8)
	put(mut data, 120, 2, 4) // PT_DYNAMIC
	put(mut data, 128, 256, 8)
	put(mut data, 136, 0x400100, 8)
	put(mut data, 152, 64, 8)
	put(mut data, 160, 64, 8)
	put(mut data, 256, 5, 8) // DT_STRTAB
	put(mut data, 264, 0x400200, 8)
	put(mut data, 272, 10, 8) // DT_STRSZ
	put(mut data, 280, u64(needed.len + 2), 8)
	if needed != '' {
		put(mut data, 288, 1, 8) // DT_NEEDED
		put(mut data, 296, 1, 8)
		for i, byte in needed.bytes() {
			data[513 + i] = byte
		}
	}
	if interpreter != '' {
		put(mut data, 176, 3, 4) // PT_INTERP
		put(mut data, 184, 768, 8)
		put(mut data, 208, u64(interpreter.len + 1), 8)
		for i, byte in interpreter.bytes() {
			data[768 + i] = byte
		}
	}
	return data
}

fn write_fixture(root string, path string, data []u8) ! {
	os.mkdir_all(os.dir(root + path))!
	os.write_file_array(root + path, data)!
	os.chmod(root + path, 0o755)!
}

fn complete_root(root string) ! {
	app := '/usr/lib/firefox-esr'
	for path in ['${app}/firefox-esr', '${app}/libxul.so', '/usr/bin/Xorg', '/usr/bin/Xvfb',
		'/usr/bin/Xvfb-glx', '/usr/bin/vinix-wine-host', '/usr/bin/vinix-xinput', '/usr/bin/xset',
		'/usr/bin/xkbcomp', '/usr/lib/libgtk-3.so.0', '/usr/lib/libavcodec.so.60',
		'/usr/lib/xorg/modules/dri/swrast_dri.so', '/usr/lib/xorg/modules/drivers/fbdev_drv.so',
		'/bin/sh', '/lib/ld-musl-x86_64.so.1'] {
		write_fixture(root, path, elf_fixture('', ''))!
	}
	write_fixture(root, app + '/firefox-esr', elf_fixture('libgtk-3.so.0',
		'/lib/ld-musl-x86_64.so.1'))!
	for path in ['/usr/bin/firefox-esr', '/usr/bin/run-firefox', '/usr/bin/startx'] {
		write_fixture(root, path, '#!/bin/sh\nexit 0\n'.bytes())!
	}
	for path in ['${app}/application.ini', '${app}/omni.ja', '${app}/defaults/pref/vinix.js',
		'${app}/distribution/policies.json', '/etc/X11/xorg.conf', '/usr/share/X11/xkb/rules/evdev',
		'/usr/share/X11/xkb/keycodes/evdev', '/usr/share/X11/xkb/symbols/us',
		'/usr/share/X11/xkb/types/complete', '/usr/share/X11/xkb/compat/complete',
		'/etc/ssl/certs/ca-certificates.crt', '/usr/share/vinix/firefox-smoke.html',
		'/usr/share/fonts/dejavu/test.ttf'] {
		write_fixture(root, path, 'fixture data'.bytes())!
	}
}

fn expect_invalid(root string, reader string, message string) {
	validate(root, reader) or {
		assert err.msg().contains(message), err.msg()
		return
	}
	assert false, 'invalid image passed: ${message}'
}

fn test_final_image_and_broken_runtime() ! {
	reader := find_readelf()!
	root := os.join_path(os.temp_dir(), 'vinix-firefox-${os.getpid()}-${time.now().unix_micro()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	complete_root(root)!
	validate(root, reader)!
	for path in ['/usr/lib/firefox-esr/firefox-esr', '/usr/lib/firefox-esr/libxul.so', '/usr/bin/Xvfb',
		'/usr/bin/vinix-wine-host', '/usr/bin/run-firefox', '/usr/bin/xkbcomp',
		'/usr/share/X11/xkb/rules/evdev', '/usr/share/X11/xkb/symbols/us', '/lib/ld-musl-x86_64.so.1',
		'/etc/ssl/certs/ca-certificates.crt'] {
		os.mv(root + path, root + path + '.saved')!
		expect_invalid(root, reader, if path.ends_with('/firefox-esr') {
			'missing executable Firefox'
		} else {
			'missing or empty'
		})
		os.mv(root + path + '.saved', root + path)!
	}
	write_fixture(root, '/usr/bin/Xvfb-glx', 'broken preferred X server'.bytes())!
	expect_invalid(root, reader, 'not an amd64 ELF')
	write_fixture(root, '/usr/bin/Xvfb-glx', elf_fixture('libglxmissing.so', ''))!
	expect_invalid(root, reader, 'missing dependency libglxmissing.so')
	os.rm(root + '/usr/bin/Xvfb-glx')!
	validate(root, reader)! // The host falls back to Xvfb when GLX is absent.
	// A nonempty directory with GTK/media markers is not a browser.
	write_fixture(root, '/usr/lib/firefox-esr/firefox-esr', 'not ELF'.bytes())!
	expect_invalid(root, reader, 'not an amd64 ELF')
	write_fixture(root, '/usr/lib/firefox-esr/firefox-esr', elf_fixture('', '')[..20])!
	expect_invalid(root, reader, 'readelf rejected')
	complete_root(root)!
	os.chmod(root + '/usr/lib/firefox-esr/firefox-esr', 0o644)!
	expect_invalid(root, reader, 'missing executable Firefox')
	complete_root(root)!
	mut wrong_arch := elf_fixture('', '')
	put(mut wrong_arch, 18, 183, 2)
	write_fixture(root, '/usr/lib/firefox-esr/libxul.so', wrong_arch)!
	expect_invalid(root, reader, 'not an amd64 ELF')
	// Missing transitive dependency of a dlopened Firefox companion library.
	write_fixture(root, '/usr/lib/firefox-esr/libxul.so', elf_fixture('libmissing.so', ''))!
	expect_invalid(root, reader, 'missing dependency libmissing.so')
	// Presence is insufficient: dependencies must themselves be valid ELF.
	write_fixture(root, '/usr/lib/libmissing.so', 'broken dependency'.bytes())!
	expect_invalid(root, reader, 'not an amd64 ELF')
	write_fixture(root, '/usr/lib/libmissing.so', elf_fixture('', ''))!
	validate(root, reader)!
	// Absolute guest symlinks must work without depending on host /lib.
	os.rm(root + '/usr/lib/libmissing.so')!
	write_fixture(root, '/lib/libmissing.so', elf_fixture('', ''))!
	os.symlink('/lib/libmissing.so', root + '/usr/lib/libmissing.so')!
	validate(root, reader)!
	os.rm(root + '/lib/libmissing.so')!
	expect_invalid(root, reader, 'missing dependency libmissing.so')
}

fn test_dynamic_paths_and_guest_symlink_loops() ! {
	info :=
		parse_dynamic(' 0x1 (NEEDED) Shared library: [libgtk-3.so.0]\n 0x1d (RUNPATH) Library runpath: [$ORIGIN:/usr/lib]\n [Requesting program interpreter: /lib/ld-musl-x86_64.so.1]')!
	assert info.needed == ['libgtk-3.so.0']
	assert info.paths == ['$ORIGIN', '/usr/lib']
	assert info.interpreter == '/lib/ld-musl-x86_64.so.1'
	root := os.join_path(os.temp_dir(), 'vinix-firefox-links-${os.getpid()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	write_fixture(root, '/usr/lib/firefox-esr/private.so', elf_fixture('', ''))!
	assert library(root, 'private.so', '/usr/lib/firefox-esr', ['$ORIGIN'])! == root +
		'/usr/lib/firefox-esr/private.so'
	unresolved := library(root, 'private.so', '/usr/lib/firefox-esr', []) or {
		assert err.msg().contains('missing dependency private.so')
		''
	}
	assert unresolved == ''
	// An absolute link to a real host file is not a dependency in the image.
	os.write_file(root + '-host.so', 'host-only data')!
	defer { os.rm(root + '-host.so') or {} }
	os.symlink(root + '-host.so', root + '/host.so')!
	host_only := required(root, '/host.so', false) or {
		assert err.msg().contains('missing or empty')
		''
	}
	assert host_only == ''
	os.symlink('/loop', root + '/loop')!
	guest_path(root, '/loop') or {
		assert err.msg().contains('symlink loop')
		return
	}
	assert false
}

fn test_bundle_from_full_and_compact_images() ! {
	root := os.join_path(os.temp_dir(),
		'vinix-x11-bundle-${os.getpid()}-${time.now().unix_micro()}')
	os.mkdir_all(root)!
	defer { os.rmdir_all(root) or {} }
	repo := os.real_path(os.join_path(os.dir(@FILE), '../..'))
	source := os.read_file(repo + '/scripts/build-desktop-amd64.sh')!
	start := source.index('if [ -n "$X11_BUNDLE" ]; then') or { panic('bundle block missing') }
	end := source.index('\nINITRAMFS=') or { panic('bundle end missing') }
	// Execute the actual packaging block, with tiny staged files rather than
	// compiling the desktop, fetching packages, building a kernel or booting.
	for full in ['0', '1'] {
		work := root + '/' + full
		base := work + '/base'
		staging := work + '/staging'
		layer := work + '/layer'
		for name in ['Xvfb', 'vinix-wine-host', 'vinix-xinput'] {
			write_fixture(layer, '/usr/bin/' + name, 'X11 fixture'.bytes())!
			if full == '1' { write_fixture(staging, '/usr/bin/' + name, 'merged X11'.bytes())! }
		}
		write_fixture(base, '/usr/lib/base.so', 'base'.bytes())!
		write_fixture(staging, '/usr/lib/base.so', 'base'.bytes())!
		write_fixture(layer, '/usr/lib/base.so', 'layer copy'.bytes())!
		os.mkdir_all(work + '/build')!
		mut environment := os.environ()
		environment['SCRIPT_DIR'] = repo
		environment['BUILD_DIR'] = work + '/build'
		environment['SYSROOT'] = base
		environment['STAGING'] = staging
		environment['X11_STAGING'] = layer
		environment['WITH_X11'] = full
		environment['X11_BUNDLE'] = work + '/x11.tar.gz'
		mut process := os.new_process('bash')
		process.set_args(['-e', '-u', '-o', 'pipefail', '-c', source[start..end]])
		process.set_environment(environment)
		process.set_redirect_stdio()
		process.run()
		output := process.stdout_slurp()
		diagnostics := process.stderr_slurp()
		process.wait()
		assert process.code == 0, output + diagnostics
		process.close()
		assert os.file_size(work + '/x11.tar.gz') > 0
		assert os.file_size(work + '/x11.tar.gz.sha256') > 0
		for name in ['Xvfb', 'vinix-wine-host', 'vinix-xinput', 'startx'] {
			assert os.is_executable(work + '/build/x11-bundle-root/usr/bin/' + name)
		}
		assert !os.exists(work + '/build/x11-bundle-root/usr/lib/base.so')
	}
}
