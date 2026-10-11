// SPDX-License-Identifier: GPL-2.0-or-later
module perfrunner

import crypto.sha256
import hosttest
import os
import perfconsole
import perfreport
import sourcecommand
import strconv

pub struct Build {
pub:
	name   string
	binary string
}

pub struct Plan {
pub:
	root         string
	here         string
	libc         string
	builds       []Build
	scenarios    []string
	rounds       int
	settle       int
	seconds      int
	mem          int
	timeout      i64
	desktop_args string
	initramfs    string
	assets       []string
	json_path    ?string
	shots        ?string
}

fn path(value string) string { return if value == '' { '.' } else { value } }

pub fn parse(argv []string, root string, here string, libc string) !Plan {
	mut options := {
		'scenarios':    'idle,apps,pointer,drag'
		'rounds':       '2'
		'settle':       '15'
		'seconds':      '45'
		'desktop-args': ''
		'mem':          '12288'
		'initramfs':    root + '/build-support/init-aarch64/initramfs-desktop.tar'
		'timeout':      '0'
	}
	names := ['scenarios', 'rounds', 'settle', 'seconds', 'desktop-args', 'mem', 'initramfs',
		'dictionary-data', 'json', 'shots', 'timeout']
	mut builds := []string{}
	mut index := 0
	mut positional := false
	for index < argv.len {
		argument := argv[index]
		if !positional && argument == '--' {
			positional = true
			index++
			continue
		}
		if !positional && argument.starts_with('--') {
			prefix := argument[2..].all_before('=')
			mut matches := names.filter(it.starts_with(prefix))
			if prefix in names { matches = [prefix] }
			if matches.len != 1 { return error('unknown or ambiguous option ' + argument) }
			name := matches[0]
			value := if argument.contains('=') {
				argument.all_after('=')
			} else {
				index++
				if index >= argv.len || argv[index].starts_with('--') {
					return error('missing value for --' + name)
				}
				argv[index]
			}
			options[name] = value
		} else if !positional && argument.starts_with('-') {
			return error('unrecognized argument ' + argument)
		} else {
			builds << argument
		}
		index++
	}
	selected := options['scenarios'].split(',').filter(it != '')
	mut seen := map[string]bool{}
	for name in selected { seen[name] = true }
	if selected.len == 0 || seen.len != selected.len {
		return error('choose at least one scenario without duplicates')
	}
	rounds := strconv.atoi(options['rounds'])!
	seconds := strconv.atoi(options['seconds'])!
	settle := strconv.atoi(options['settle'])!
	requested := strconv.parse_int(options['timeout'], 10, 64)!
	if rounds < 1 || seconds < 1 || settle < 0 || requested < 0 {
		return error('rounds and seconds must be positive; settle and timeout must be nonnegative')
	}
	allowed := if libc == '' {
		perfreport.scenarios
	} else {
		['idle', 'apps', 'pointer', 'drag', 'wakeups', 'churn', 'cache', 'ops']
	}
	for name in selected {
		if name !in allowed {
			return error('unknown scenario ' + name + '; choose from ' + allowed.join(', '))
		}
	}
	if builds.len == 0 { return error('at least one NAME=BINARY is required') }
	mut plan_builds := []Build{}
	mut labels := map[string]bool{}
	for item in builds {
		name := item.all_before('=')
		binary := if item.contains('=') { item.all_after('=') } else { '' }
		if name == '' || binary == '' || !name.bytes().all((it.is_alnum() && it < 128) || it in [
			`_`,
			`-`,
		]) {
			return error('expected NAME=BINARY, got ' + item)
		}
		if !os.is_file(binary) { return error('no such binary: ' + binary) }
		plan_builds << Build{name, binary}
		labels[name] = true
	}
	if labels.len != plan_builds.len { return error('build labels must be unique') }
	if 'workflows' in selected && 'dictionary-data' !in options {
		return error('workflows requires --dictionary-data=DIR with prepared local data and license')
	}
	mut assets := []string{}
	if 'dictionary-data' in options {
		assets = dictionary_assets(path(options['dictionary-data']))!
	}
	mut budget := i64(0)
	for scenario in selected {
		budget += if libc != '' || scenario !in ['ops', 'churn'] {
			i64(settle) + seconds + 60
		} else if scenario == 'ops' {
			1500
		} else {
			240
		}
	}
	timeout := if requested != 0 { requested } else { 900 + budget * plan_builds.len * rounds }
	if timeout <= 0 { return error('measurement timeout exceeds supported bounds') }
	return Plan{ root: root, here: here, libc: libc, builds: plan_builds, scenarios: selected, rounds: rounds, settle: settle, seconds: seconds, mem: strconv.atoi(options['mem'])!, timeout: timeout, desktop_args: options['desktop-args'], initramfs: path(options['initramfs']), assets: assets, json_path: if 'json' in options {
		?string(path(options['json']))
	} else {
		none
	}, shots: if 'shots' in options { ?string(path(options['shots'])) } else { none } }
}

pub fn dictionary_assets(directory string) ![]string {
	data := directory + '/dictionary.vnd'
	license := directory + '/LICENSE.WordNet'
	if !os.is_file(data) || !os.is_file(license) {
		return error('dictionary data requires regular dictionary.vnd and LICENSE.WordNet files')
	}
	size := os.file_size(data)
	license_size := os.file_size(license)
	if size < 24 || size > 64 * 1024 * 1024 || license_size == 0 || license_size > 16384 {
		return error('dictionary data or license exceeds supported size bounds')
	}
	mut file := os.open(data)!
	defer { file.close() }
	mut header := []u8{len: 24}
	mut read := 0
	for read < 24 {
		mut part := unsafe { header[read..] }
		count := file.read(mut part)!
		if count == 0 { break }
		read += count
	}
	if read != 24 || header[..8].bytestr() != 'VNXDICT1' {
		return error('dictionary.vnd has an invalid VNXDICT1 header')
	}
	mut words := []u64{}
	for at := 8; at < 24; at += 4 {
		words << u64(header[at]) | u64(header[at + 1]) << 8 | u64(header[at + 2]) << 16 | u64(header[at + 3]) << 24
	}
	count, keys, definitions, reserved := words[0], words[1], words[2], words[3]
	if count < 1 || count > 200000 || keys < count || keys > count * 128 || definitions < count || definitions > count * 65536 || reserved != 0 || size != 24 + count * 16 + keys + definitions {
		return error('dictionary.vnd has invalid header bounds or length')
	}
	return [data, license]
}

pub fn measure_command(root string, source string, output string, libc string, env map[string]string) ![]string {
	mut llvm := env['LLVM_BIN'] or { '/opt/homebrew/opt/llvm/bin' }
	if !os.exists(llvm + '/clang') {
		located := os.find_abs_path_of_executable('clang') or { 'clang' }
		llvm = os.dir(located)
	}
	sysroot := env['VINIX_AARCH64_SYSROOT'] or { root + '/build-aarch64-userland/staging' }
	directory := sysroot + '/usr/lib/gcc/aarch64-alpine-linux-musl'
	mut versions := os.ls(directory)!
	versions.sort()
	if versions.len == 0 { return error('GCC install directory missing') }
	gcc := directory + '/' + versions.last()
	lib := sysroot + '/usr/lib'
	mut command := [llvm + '/clang', '--target=aarch64-linux-musl', '-static', '-nostdinc', '-nostdlib',
		'-isystem', gcc + '/include', '-isystem', sysroot + '/usr/include', '-O2', '-Wall',
		lib + '/crt1.o', lib + '/crti.o', gcc + '/crtbeginT.o', source]
	if libc != '' { command << '-L' + libc + '/usr/lib' }
	command << ['-L' + lib, '-L' + gcc, '-lc', '-lgcc', gcc + '/crtend.o', lib + '/crtn.o',
		'-fuse-ld=lld', '-B' + llvm, '-o', output]
	return command
}

pub fn command(argv []string) ! {
	result := sourcecommand.capture(argv, os.environ(), -1, 0x7fffffff, perfconsole.cancelled)!
	if result.stdout != '' { print(result.stdout) }
	if result.stderr != '' { eprint(result.stderr) }
	if result.status != 0 {
		return error('guest command failed with status ${result.status}: ' + argv.join(' '))
	}
}

pub struct Launch {
pub:
	command []string
	env     map[string]string
	socket  string
}

pub fn prepare(plan Plan, runtime string, execute fn ([]string) !) !Launch {
	overlay := runtime + '/overlay/opt/vinix-perf'
	os.mkdir_all(overlay)!
	if plan.assets.len > 0 {
		directory := runtime + '/overlay/usr/share/vinix/dictionary'
		os.mkdir_all(directory)!
		for asset in plan.assets {
			hosttest.module_copy_file(asset, directory + '/' + os.file_name(asset))!
		}
	}
	if plan.libc != '' {
		for relative in ['lib/ld-musl-aarch64.so.1', 'usr/share/vinix/musl-build.json',
			'usr/share/licenses/musl/COPYRIGHT'] {
			target := runtime + '/overlay/' + relative
			os.mkdir_all(os.dir(target))!
			hosttest.module_copy_file(plan.libc + '/' + relative, target)!
		}
	}
	for build in plan.builds {
		hosttest.module_copy_file(build.binary, overlay + '/vinix-desktop-' + build.name)!
	}
	perfconsole.checkpoint()!
	execute(measure_command(plan.root, plan.here + '/measure.c', overlay + '/measure', plan.libc, os.environ())!)!
	labels := plan.builds.map(it.name)
	os.write_file(overlay + '/config', "VARIANTS='" + labels.join(' ') + "'\nSCENARIOS='" + plan.scenarios.join(' ') + "'\nROUNDS=${plan.rounds}\nSETTLE=${plan.settle}\nMEASURE=${plan.seconds}\nDESKTOP_ARGS='" + plan.desktop_args + "'\n")!
	initramfs := hosttest.module_resolve(plan.initramfs)!
	filename := os.file_name(initramfs)
	stem := if filename.last_index('.') or { -1 } > 0 {
		filename.all_before_last('.')
	} else {
		filename
	}
	tag := sha256.sum(initramfs.bytes()).hex()[..12]
	iso := plan.root + '/build/desktop-perf/' + stem + '-' + tag + '.iso'
	if plan.libc == '' {
		execute([plan.root + '/tools/prune-build-artifacts', '--root', plan.root, '--automatic',
			'--keep', initramfs, '--keep', iso])!
	}
	execute([plan.root + '/tools/build-qemu-module-iso', initramfs, iso])!
	mut env := os.environ()
	socket := os.dir(runtime) + '/qmp.sock'
	updates := {
		'VINIX_INITRAMFS':            initramfs
		'VINIX_INITRAMFS_COMPRESSED': '0'
		'VINIX_QEMU_MODULE_ISO':      iso
		'VINIX_QEMU_BASE_ARCHIVE':    ''
		'VINIX_QEMU_MODULE_MANIFEST': ''
		'VINIX_QEMU_EXTRA_MODULES':   ''
		'VINIX_QEMU_ROOT_DISK':       '0'
		'VINIX_BOOT_DISK':            runtime + '/boot.img'
		'VINIX_EFIVARS':              runtime + '/efivars.fd'
		'VINIX_QEMU_PACKAGE_STORE':   runtime + '/packages.tar'
		'VINIX_QEMU_PACKAGE_PERSIST': '0'
		'VINIX_QEMU_PERSIST_DISK':    runtime + '/root.ext2'
		'VINIX_QEMU_PERSIST_SIZE_MB': '256'
		'VINIX_KEEP_TEMP_BOOT_DISK':  '1'
		'VINIX_QEMU_OVERLAY':         runtime + '/overlay'
		'VINIX_QEMU_RESOLUTION':      '2048x1536x32'
		'VINIX_OVMF_CODE':            plan.root + '/boot-image/edk2-aarch64-code-2048x1536.fd'
		'VINIX_QEMU_EXTRA':           ((env['VINIX_QEMU_EXTRA'] or { '' }) + ' -qmp unix:' + socket + ',server,nowait').trim_space()
		'VINIX_QEMU_HOST_SOURCE':     '0'
		'VINIX_QEMU_AUDIO':           'off'
	}
	for key, value in updates { env[key] = value }
	env.delete('VINIX_QEMU_PERSIST')
	return Launch{[plan.root + '/scripts/run-aarch64.sh', '--no-build', '--serial',
		'--mem=${plan.mem}', '--guest-init=' + plan.here + '/perf-init.sh'], env, socket}
}

pub fn run(plan Plan) !int {
	work := sourcecommand.temporary('vinix-desktop-perf')!
	return run_prepared(plan, work, command)!
}

// The fixture boundary substitutes the three build commands, while retaining
// the production plan, staging, runtime cleanup and native guest supervisor.
pub fn run_prepared(plan Plan, work string, execute fn ([]string) !) !int {
	runtime := work + '/vm'
	os.mkdir(runtime)!
	defer { os.rmdir_all(runtime) or { eprintln(err) } }
	launch := prepare(plan, runtime, execute)!
	println('==> Measuring ' + plan.builds.map(it.name).join(', ') + ' over ' + plan.scenarios.join(', ') + ' x${plan.rounds} (up to ${plan.timeout}s)')
	return drive(plan, launch, work, 10, true)!
}

pub fn cli(args []string, root string, here string, libc string) int {
	if args.any(it in ['--help', '-h']) {
		println('run NAME=BINARY... [--scenarios idle,apps,pointer,drag] [--rounds N] [--settle N] [--seconds N] [--desktop-args TEXT] [--mem N] [--initramfs PATH] [--dictionary-data DIR] [--json PATH] [--shots DIR] [--timeout N]')
		return 0
	}
	plan := parse(args, root, here, libc) or {
		eprintln(err)
		return 2
	}
	guard := perfconsole.own_commands()
	defer { guard.close() }
	status := run(plan) or {
		eprintln(err)
		return if perfconsole.cancelled() { perfconsole.interrupt_status() } else { 1 }
	}
	return if perfconsole.cancelled() { perfconsole.interrupt_status() } else { status }
}
