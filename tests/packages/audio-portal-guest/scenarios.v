// SPDX-License-Identifier: GPL-2.0-or-later
module main

import authclient
import authproto
import json2
import os
import tools.packages.pkgcore

fn launch(package string, mode string, run string, frequency int) !int {
	return child_start(['/usr/sbin/vinix-session', 'run', '--seat', 'alex', '/sbin/init', 'login',
		package, mode, run, frequency.str()], '', '')
}

fn ready(run string) !Ready {
	value := json2.decode[Ready](wait_file(data + '/' + run + '.ready')!)!
	require(value.pid > 1 && value.worker > 1 && value.pid != value.worker
		&& value.socket.starts_with('/run/user/1000/vinix-audio-') && value.socket.ends_with('.sock')
		&& value.device > 0 && value.inode > 0 && value.generation > 0 && value.manifest.len == 64, 'invalid observed audio endpoint')!
	require(os.exists('/proc/${value.pid}') && os.exists('/proc/${value.worker}') && os.exists(value.socket), 'observed audio actors are absent')!
	return value
}

fn finish(pid int, run string, package string) ! {
	require(wait(pid)! == 0, 'ordinary package session failed: ${run}')!
	path := '/home/alex/.local/share/vinix-apps/' + package + '/' + run + '.done'
	require(text(path) == 'PASS\n', 'payload completion missing: ${run}')!
	for _ in 0 .. 100 {
		entries := os.ls('/run/user/1000') or { []string{} }
		if !entries.any(it.starts_with('vinix-audio-')) { return }
		C.usleep(100_000)
	}
	return error('audio endpoint survived session completion: ${run}')
}

fn gone(value Ready) ! {
	for _ in 0 .. 200 {
		// A killed launcher can orphan its worker to PID1 (this fixture).
		mut status := i32(0)
		C.waitpid(value.worker, &status, C.WNOHANG)
		if !os.exists('/proc/${value.worker}') && !os.exists(value.socket) { return }
		C.usleep(100_000)
	}
	return error('audio worker or exact endpoint survived cleanup: ${value.worker} ${value.socket}')
}

fn setup() ! {
	command(['/usr/sbin/vinix-account', 'init'], '')!
	command(['/usr/sbin/vinix-account', 'add', 'alex', 'Alex Example', 'admin'], 'alex has a password\n')!
	command(['/usr/sbin/vinix-account', 'add', 'sam', 'Sam Example'], 'sam has another\n')!
	child_start(['/usr/sbin/vinix-authd'], '', '')!
	mut live := false
	for _ in 0 .. 100 {
		mut reply := authclient.ask_root(authclient.default_socket, authproto.op_info) or {
			C.usleep(100_000)
			continue
		}
		live = reply.code == authproto.status_ok
		reply.close()
		if live { break }
		C.usleep(100_000)
	}
	require(live, 'real account service unavailable')!
	require(os.exists('/dev/dsp'), 'selected kernel/hardware has no /dev/dsp')!
	command(['/usr/bin/vinix-package', 'update'], '')!
	command(['/usr/bin/vinix-package', 'install', 'tone', 'noaudio'], '')!
	println('AUDIO SETUP signed tone and noaudio installed PASS')
}

fn basic() ! {
	qualify_forgery()!
	noaudio := launch('noaudio', 'refuse', 'missing', 0)!
	finish(noaudio, 'missing', 'noaudio')!
	println('AUDIO CONTROL absent-permission refused PASS')
	config_text := text('/etc/vinix-packages/config.json')
	config := json2.decode[pkgcore.Config](config_text)!
	os.write_file('/etc/vinix-packages/config.json', json2.encode(pkgcore.Config{ ...config, policy: pkgcore.Policy{ ...config.policy, permissions: [
		'files',
		'process',
		'network',
		'display',
	] } }))!
	blocked := launch('tone', 'tone', 'policy', 440)!
	require(wait(blocked)! != 0 && !os.exists(data + '/policy.done'), 'organization audio policy did not refuse launch')!
	os.write_file('/etc/vinix-packages/config.json', config_text)!
	println('AUDIO CONTROL organization-policy refused PASS')
	forged := launch('tone', 'forged', 'forged', 0)!
	finish(forged, 'forged', 'tone')!
	println('AUDIO CONTROL forged-endpoint refused PASS')
	for mode in ['service', 'changed'] {
		pid := launch('tone', mode, mode, 0)!
		value := ready(mode)!
		if mode == 'service' {
			require(C.kill(value.worker, C.SIGKILL) == 0, 'cannot stop observed worker')!
		} else {
			os.rm(value.socket)!
			os.write_file(value.socket, 'foreign replacement\n')!
		}
		os.write_file(data + '/' + mode + '.go', 'go\n')!
		require(wait(pid)! == 0 && text(data + '/' + mode + '.done') == 'PASS\n', '${mode} control failed')!
		if mode == 'changed' {
			require(text(value.socket) == 'foreign replacement\n', 'portal removed a replacement endpoint')!
			os.rm(value.socket)!
		}
		gone(value)!
		println('AUDIO CONTROL ${mode} refused and cleanup PASS')
	}
	C.usleep(1_500_000)
	pid := launch('tone', 'sequence', 'sequence', 0)!
	finish(pid, 'sequence', 'tone')!
	C.usleep(1_500_000)
	println('AUDIO PCM exact sequence 440 660 880 PASS')
}

fn lifecycle() ! {
	for index, target in ['client', 'launcher'] {
		run := if index == 0 { 'client' } else { 'launcher' }
		pid := launch('tone', 'hold', run, if index == 0 { 440 } else { 880 })!
		value := ready(run)!
		outer := wait_file('/home/alex/Documents/' + run + '.outer')!.trim_space().int()
		require(outer > 1 && outer != value.pid && outer != value.worker, 'outer CLI identity not observed')!
		require(C.kill(if target == 'client' { value.pid } else { outer }, C.SIGKILL) == 0, 'cannot kill observed ${target}')!
		gone(value)!
		if target == 'launcher' {
			require(os.exists('/proc/${value.pid}'), 'held client exited before launcher-death cleanup was observed')!
			require(C.kill(value.pid, C.SIGKILL) == 0, 'cannot clean held client')!
		}
		require(wait(pid)! != 0, 'killed ${target} reported successful session')!
		C.usleep(1_500_000)
		next := if index == 0 { 'afterclient' } else { 'afterlauncher' }
		fresh := launch('tone', 'tone', next, if index == 0 { 660 } else { 440 })!
		finish(fresh, next, 'tone')!
		C.usleep(1_500_000)
		println('AUDIO LIFECYCLE ${target}-death cleanup and relaunch PASS')
	}
}
