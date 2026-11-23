// SPDX-License-Identifier: GPL-2.0-or-later
module main

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

fn route() ! {
	for directory in ['/run', '/home', '/root', '/tmp', '/var/log'] { os.mkdir_all(directory)! }
	os.chmod('/tmp', 0o1777)!
	os.chmod('/root', 0o700)!
	os.setenv('PATH', '/usr/sbin:/usr/bin:/sbin:/bin', true)
	os.setenv('HOME', '/root', true)
	os.setenv('VINIX_SYSTEM_SESSION', '1', true)
	require_uninstalled()!
	checked(['/usr/sbin/vinix-account', 'init'], '')!
	checked(['/usr/sbin/vinix-account', 'add', 'alex', 'Alex', 'admin'], 'test-only password\n')!
	os.write_file(choice, 'skip\n')!
	os.chmod(choice, 0o600)!
	os.chown(choice, 1000, 1000)!
	lock_text := os.read_file(declaration)!
	mut document := pkgprotocol.decode_deployment_document(lock_text)!
	defer { document.close() }
	architecture := $if arm64 { 'aarch64' } $else { 'x86_64' }
	if document.format != 2 || document.architecture != architecture || editor !in document.packages
		|| runtime in document.packages || !document.locked.any(it.id == runtime) {
		return error('release declaration must select Neovim with its locked runtime dependency')
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
