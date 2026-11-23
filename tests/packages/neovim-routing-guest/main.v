// SPDX-License-Identifier: GPL-2.0-or-later
module main

import json2
import os
import time
import tools.packages.pkgprotocol

#include <fcntl.h>
fn C.dup2(int, int) int

const declaration = '/usr/share/vinix-packages/applications.json'
const legacy_log = '/home/alex/legacy-installer.log'
const choice = '/home/alex/.vinix-first-run-release'
const editor = 'org.neovim.editor'
const runtime = 'org.vinix.neovim-runtime'
const approval_input = '/etc/neovim-routing-approval'
const approval_success = 'uid=1000 run packages-change as alex: exit 0'
const mixed_catalog_input = '/etc/neovim-routing-mixed-catalog'
const sqlite = 'org.sqlite.cli'
const ffmpeg = 'org.ffmpeg.cli'
const ffprobe = 'org.ffmpeg.probe'
const hello = 'org.vinix.package-hello'
const app_data = '/home/alex/.local/share/vinix-apps/'
const mixed_database = app_data + sqlite + '/database.sqlite3'
const mixed_media_name = 'mixed release; \$literal.wav'
const mixed_media = app_data + ffmpeg + '/' + mixed_media_name

struct VerifiedGeneration {
	generation u64
	requested []string
}

fn run_command(args []string, input string) !(int, string) {
	mut child := os.new_process(args[0])
	defer { child.close() }
	child.set_args(args[1..])
	child.set_redirect_stdio_merged()
	child.run()
	if input != '' { child.stdin_write(input) }
	C.close(child.stdio_fd[0])
	child.stdio_fd[0] = -1
	output := child.stdout_slurp()
	child.wait()
	return child.code, output
}

fn checked(args []string, input string) !string {
	code, output := run_command(args, input)!
	if code != 0 { return error(args.join(' ') + ' failed: ' + output) }
	return output
}

fn setup_command() !(int, string) {
	return run_command(['/usr/sbin/vinix-session', 'run', '--isolated', 'alex',
		'/usr/bin/vinix-desktop', '--install-setup-app', 'neovim'], '')
}

fn record_legacy_install() ! {
	if os.getuid() != 1000 || os.geteuid() != 1000 || os.args[1..] != ['install', 'neovim'] {
		return error('unexpected legacy install call')
	}
	mut output := os.open_append(legacy_log)!
	defer { output.close() }
	output.writeln('install neovim')!
}

fn await_path(path string, mut child os.Process) ! {
	deadline := time.sys_mono_now() + 120 * time.second
	for !os.exists(path) {
		if !child.is_alive() || time.sys_mono_now() >= deadline {
			return error('service did not publish ' + path)
		}
		time.sleep(100 * time.millisecond)
	}
}

fn require_uninstalled() ! {
	base := '/var/lib/vinix-packages'
	for name in ['state.json', 'current'] {
		if os.exists(base + '/' + name) || os.is_link(base + '/' + name) {
			return error('review activated a package generation')
		}
	}
	if os.is_dir(base + '/generations') && os.ls(base + '/generations')!.len != 0 {
		return error('review created a package generation')
	}
	if (os.read_file('/var/log/vinix/auth.log') or { '' }).contains('run packages-change') {
		return error('review requested package change approval')
	}
}

fn software_clients() !int {
	mut count := 0
	for pid in os.ls('/proc')! {
		if pid.int() <= 0 { continue }
		args := (os.read_file('/proc/' + pid + '/cmdline') or { continue }).split('\x00')
		if args.len < 2 || os.file_name(args[0]) != 'vinix-software'
			|| '--vinix-app=vinix-software' !in args {
			continue
		}
		status := os.read_file('/proc/' + pid + '/status')!
		uids := status.split_into_lines().filter(it.starts_with('Uid:'))
		if uids.len != 1 || uids[0].all_after(':').fields() != ['1000', '1000', '1000', '1000'] {
			return error('Software review client did not run under the ordinary account')
		}
		count++
	}
	return count
}

fn verify_proposal(document pkgprotocol.DeploymentDocument) ! {
	reply := checked(['/usr/bin/vinix-package', '--offline', 'deployment-review', declaration], '')!
	mut proposal := pkgprotocol.decode_review(reply)!
	defer { proposal.close() }
	if proposal.operation != 'deploy' || proposal.architecture != document.architecture
		|| proposal.generation != 0 || proposal.requested != document.packages {
		return error('read-only proposal differs from the signed release roots')
	}
	if proposal.rows.len != document.locked.len { return error('read-only proposal lost a locked dependency') }
	for pin in document.locked {
		matches := proposal.rows.filter(it.id == pin.id)
		if matches.len != 1 { return error('missing or duplicate proposal row for ' + pin.id) }
		row := matches[0]
		if row.version != pin.version || row.architecture != pin.architecture || row.repository != pin.repository
			|| row.public_key != pin.public_key || row.requested != (pin.id in document.packages) || row.action != 'install' {
			return error('proposal row differs from its exact lock for ' + pin.id)
		}
	}
	println('HWTEST INFO SIGNED PROPOSAL ' + reply.trim_space())
}

fn approval_step(name string, pause time.Duration) {
	println('HWTEST INFO approval ' + name)
	time.sleep(pause)
}

fn read_after_catalog_refresh(args []string) !string {
	// Software's follow-up catalog refresh can overlap the installed-state checks.
	deadline := time.sys_mono_now() + 30 * time.second
	for {
		code, output := run_command(args, '')!
		if code == 0 { return output }
		if !output.contains('another package transaction is running; review again when it finishes')
			|| time.sys_mono_now() >= deadline {
			return error(args.join(' ') + ' failed: ' + output)
		}
		time.sleep(200 * time.millisecond)
	}
	return error('package read did not complete')
}

fn verify_approved_install(document pkgprotocol.DeploymentDocument, password string) ! {
	// The host delivers input through QEMU at each step. The guest only observes
	// package state, authentication and the real installed entrypoint.
	approval_step('pointer', 300 * time.millisecond)
	approval_step('press', 300 * time.millisecond)
	approval_step('release', 2 * time.second)
	require_uninstalled()!
	approval_step('prompt', 400 * time.millisecond)
	for index in 0 .. password.len {
		approval_step('key ${index}.', 250 * time.millisecond)
	}
	require_uninstalled()!
	approval_step('masked without activation PASS', 400 * time.millisecond)
	approval_step('submit', 300 * time.millisecond)
	// Leave time to capture Software's visible result on both success and failure.
	defer { approval_step('response', 4 * time.second) }

	log_path := '/var/log/vinix/auth.log'
	// TCG needs extra time to verify and publish the full VJFS generation.
	timeout := if os.is_file(installed_proof) { 600 * time.second } else { 90 * time.second }
	deadline := time.sys_mono_now() + timeout
	for {
		log := os.read_file(log_path) or { '' }
		if log.contains(password) { return error('administrator audit exposed the fixture password') }
		if log.contains(approval_success) {
			if log.split_into_lines().filter(it.contains('run packages-change')).len != 1 {
				return error('expected exactly one approved package change')
			}
			// The auth service records dispatch before the package worker has
			// finished. Wait for the real activation before auditing.
			if os.is_link('/var/lib/vinix-packages/current') { break }
		}
		if time.sys_mono_now() >= deadline {
			println('HWTEST INFO package change dispatched ${log.contains(approval_success)}')
			if budget := os.read_file('/proc/kernel-resources') {
				println('HWTEST INFO package install kernel reservations\n' + budget)
			}
			if memory := os.read_file('/proc/meminfo') { println('HWTEST INFO package install memory\n' + memory) }
			return error('approved package change did not activate a generation')
		}
		time.sleep(200 * time.millisecond)
	}
	audit_text := read_after_catalog_refresh(['/usr/bin/vinix-package', '--offline', '--json',
		'deployment-audit', declaration])!
	mut audit := pkgprotocol.decode_deployment_audit(audit_text)!
	defer { audit.close() }
	if !audit.matches || audit.generation != 1 || audit.architecture != document.architecture
		|| audit.rows.len != document.locked.len || audit.rows.any(it.status != 'match') {
		return error('approved generation differs from the reviewed release lock')
	}
	state_text := read_after_catalog_refresh(['/usr/bin/vinix-package', '--offline', '--json', 'verify'])!
	state := json2.decode[VerifiedGeneration](state_text)!
	if state.generation != audit.generation || state.requested != document.packages {
		return error('verified generation did not retain the approved application roots')
	}
	println('HWTEST INFO INSTALLED AUDIT ' + audit_text.trim_space())
	result := checked(['/usr/bin/vinix-package', '--offline', 'run-args', editor, '--data-cwd', '--',
		'--headless', '-u', 'NONE', '-i', 'NONE', '-n',
		'-c', "lua assert(vim.uv.getuid()==1000); print('NEOVIM_SOFTWARE_INSTALL_OK')", '-c', 'qa!'], '')!
	if !result.contains('NEOVIM_SOFTWARE_INSTALL_OK') {
		return error('approved install did not run the real editor as the ordinary user')
	}
}

fn verify_mixed_catalog() ! {
	package := '/usr/bin/vinix-package'
	document := '/tmp/mixed-release-document.txt'
	text := 'Mixed release native SDK document'
	os.write_file(document, text + '\n')!
	os.chmod(document, 0o644)!
	native := checked([package, '--offline', 'run', hello, document], '')!
	if !native.contains('Application: ' + hello) || !native.contains(text) {
		return error('native SDK launcher did not read its granted document')
	}

	sqlite_args := [package, '--offline', 'run', sqlite]
	created := checked(sqlite_args, '.bail on\nPRAGMA journal_mode=WAL; CREATE TABLE saved(value); INSERT INTO saved VALUES(42);\n')!
	reopened := checked(sqlite_args, '.bail on\nSELECT sum(value) FROM saved; PRAGMA integrity_check;\n')!
	if created.trim_space() != 'wal' || reopened.trim_space() != '42\nok'
		|| (os.stat(mixed_database)!).uid != 1000 {
		return error('SQLite did not reopen a valid ordinary-owned private database')
	}

	checked([package, '--offline', 'run-args', ffmpeg, '--data-cwd', '--', '-v', 'error',
		'-f', 'lavfi', '-i', 'sine=frequency=440:duration=0.1', '-c:a', 'pcm_s16le', mixed_media_name], '')!
	if os.file_size(mixed_media) == 0 || (os.stat(mixed_media)!).uid != 1000 {
		return error('FFmpeg did not create ordinary-owned private media')
	}
	without_grant, _ := probe_mixed_media(false)!
	if without_grant == 0 {
		return error('FFprobe opened private audio without a file grant')
	}
	verify_mixed_media()!
	println('HWTEST PASS approved mixed catalog ran native SDK, SQLite, FFmpeg and FFprobe')
}

fn probe_mixed_media(grant bool) !(int, string) {
	files := if grant { ['--file', mixed_media] } else { []string{} }
	return run_command(['/usr/bin/vinix-package', '--offline', 'run-args', ffprobe, ...files,
		'--', '-v', 'error', '-select_streams', 'a:0', '-show_entries',
		'stream=codec_name,sample_rate,channels', '-of', 'csv=p=0', mixed_media], '')
}

fn verify_mixed_media() ! {
	code, output := probe_mixed_media(true)!
	if code != 0 || output.trim_space() != 'pcm_s16le,44100,1' {
		return error('FFprobe did not identify the granted audio: ' + output)
	}
}

fn route() ! {
	for directory in ['/run', '/home', '/root', '/tmp', '/var/log'] { os.mkdir_all(directory)! }
	os.chmod('/tmp', 0o1777)!
	os.chmod('/root', 0o700)!
	os.setenv('PATH', '/usr/sbin:/usr/bin:/sbin:/bin', true)
	os.setenv('HOME', '/root', true)
	os.setenv('VINIX_SYSTEM_SESSION', '1', true)
	installed := os.is_file(installed_proof)
	if installed && resume_installed()! { return }
	require_uninstalled()!
	approve := os.exists(approval_input)
	password := if approve { os.read_file(approval_input)! } else { 'test-only password' }
	checked(['/usr/sbin/vinix-account', 'init'], '')!
	checked(['/usr/sbin/vinix-account', 'add', 'alex', 'Alex', 'admin'], password + '\n')!
	os.write_file(choice, 'skip\n')!
	os.chmod(choice, 0o600)!
	os.chown(choice, 1000, 1000)!
	lock_text := os.read_file(declaration)!
	mut document := pkgprotocol.decode_deployment_document(lock_text)!
	defer { document.close() }
	mixed_catalog := os.is_file(mixed_catalog_input)
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	if document.format != 2 || document.architecture != architecture || editor !in document.packages
		|| runtime in document.packages || !document.locked.any(it.id == runtime) {
		return error('release declaration must select Neovim with its locked runtime dependency')
	}
	if mixed_catalog && (!approve || document.packages != [ffmpeg, ffprobe, editor, sqlite,
		'org.vinix.counter', 'org.vinix.memo', hello]) {
		return error('mixed release declaration must select the seven application roots for approval')
	}

	os.rename(declaration, declaration + '.saved')!
	code, output := setup_command()!
	if code != 0 || os.read_file(legacy_log)! != 'install neovim\n' {
		return error('absent declaration did not invoke the legacy installer: ' + output)
	}
	os.rename(declaration + '.saved', declaration)!
	println('HWTEST INFO absent declaration called legacy installer as uid 1000 PASS')
	checked(['/usr/bin/vinix-package', '--offline', 'update'], '')!

	mut auth := os.new_process('/usr/sbin/vinix-authd')
	defer { auth.close() }
	auth.set_args(['--foreground'])
	auth.run()
	await_path('/run/vinix/auth.sock', mut auth)!
	mut desktop := os.new_process('/usr/sbin/vinix-session')
	defer { desktop.close() }
	desktop.set_args(['run', '--seat', 'alex', '/usr/bin/vinix-desktop'])
	desktop.run()
	ready := '/run/user/1000/vinix-desktop-ready'
	await_path(ready, mut desktop)!
	if (os.lstat(ready)!).uid != 1000 { return error('desktop ready marker is not owned by alex') }
	time.sleep(time.second)
	println('HWTEST INFO ordinary desktop before Neovim setup')
	time.sleep(3 * time.second)

	os.write_file(declaration, '{}')!
	invalid, diagnostic := setup_command()!
	os.write_file(declaration, lock_text)!
	if invalid == 0 || !diagnostic.contains('unsupported deployment format')
		|| os.read_file(legacy_log)! != 'install neovim\n' || software_clients()! != 0 {
		return error('invalid declaration did not refuse the setup command without fallback')
	}
	println('HWTEST INFO invalid declaration refused without fallback PASS')
	time.sleep(3 * time.second)

	status, result := setup_command()!
	if status != 0 || os.read_file(legacy_log)! != 'install neovim\n' {
		return error('signed setup command failed to request review without fallback: ' + result)
	}
	verify_proposal(document)!
	println('HWTEST INFO exact setup command requested signed Neovim review PASS')
	time.sleep(8 * time.second)
	if software_clients()! != 1 { return error('expected one ordinary Software review client') }
	if os.read_file(declaration)! != lock_text || os.read_file(choice)! != 'skip\n'
		|| os.read_file(legacy_log)! != 'install neovim\n' {
		return error('review changed release inputs or invoked the legacy installer')
	}
	require_uninstalled()!
	println('HWTEST PASS Neovim graphical routing without activation or approval')
	if approve {
		verify_approved_install(document, password)!
		if mixed_catalog { verify_mixed_catalog()! }
		if os.read_file(declaration)! != lock_text || os.read_file(choice)! != 'skip\n'
			|| os.read_file(legacy_log)! != 'install neovim\n' {
			return error('approved install changed release inputs or called the legacy installer')
		}
		println('HWTEST PASS approved Software generation verified and Neovim launched as uid 1000')
		if installed {
			checkpoint_installed('approved')!
			println('HWTEST PASS mixed release approved on installed disk')
			poweroff_installed()!
		}
	}
}

fn main() {
	if os.file_name(os.args[0]) == 'pkg' {
		record_legacy_install() or { eprintln(err); exit(1) }
		return
	}
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	fd := C.open(console.str, C.O_WRONLY)
	if fd >= 0 { C.dup2(fd, 1); C.dup2(fd, 2); if fd > 2 { C.close(fd) } }
	route() or { eprintln('HWTEST FAIL Neovim graphical routing: ' + err.msg()) }
	for { time.sleep(time.second) }
}
