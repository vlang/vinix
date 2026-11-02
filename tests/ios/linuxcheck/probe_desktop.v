// SPDX-License-Identifier: GPL-2.0-or-later
// A guarded GNU application gets the existing diagnostic VAPP v10 peer.
// This observes window protocol traffic; it provides no compositor or input device.
module linuxcheck

import json2
import os
import probedesktop

struct ProbeDesktopTask {
	invocation []string
	config     probedesktop.Config
}

fn probe_desktop_setup(_ string) ! {}

fn probe_desktop_config(runtime ProbeRuntime) !probedesktop.Config {
	startup := if runtime.desktop_startup_ms == 0 {
		runtime.deadline_seconds * 1000
	} else {
		runtime.desktop_startup_ms
	}
	if startup < 1 || startup > runtime.deadline_seconds * 1000 || startup > 1800000
		|| runtime.desktop_reply_ms !in 1 .. 60001 || runtime.desktop_session_ms !in 0 .. 60001 {
		return error('invalid probe desktop startup, reply or session limit')
	}
	return probedesktop.Config{
		startup_ms: startup
		reply_ms:   runtime.desktop_reply_ms
		session_ms: runtime.desktop_session_ms
	}
}

fn probe_desktop_validate(task ProbeDesktopTask) ! {
	if task.invocation.len == 0 || task.invocation.any(it == '' || it.contains('\x00'))
		|| !os.is_abs_path(task.invocation[0]) {
		return error('desktop task requires an explicit executable invocation')
	}
	if task.config.width !in 1 .. 8193 || task.config.height !in 1 .. 8193
		|| task.config.startup_ms !in 1 .. 1800001 || task.config.reply_ms !in 1 .. 60001
		|| task.config.session_ms !in 0 .. 60001 {
		return error('invalid desktop task limits')
	}
}

// Called by the maintained driver before its ordinary mode parsing. The outer
// guarded_command owns this wrapper and all descendants in one process group.
// No guest cgroup setup is applied to the GNU process; limits here are time,
// output and protocol bounds, not the historical Vinix memory budget.
pub fn maybe_probe_desktop_child() !bool {
	if os.args.len < 2 || os.args[1] != '--linux-probe-desktop' { return false }
	if os.args.len != 3 { return error('usage: --linux-probe-desktop TASK.json') }
	path := os.abs_path(os.args[2])
	if os.lstat(path)!.get_filetype() != .regular || os.file_size(path) > 1048576 {
		return error('desktop task must be a regular JSON file of at most 1 MiB')
	}
	task := json2.decode[ProbeDesktopTask](os.read_file(path)!)!
	probe_desktop_validate(task)!
	output := os.dir(path) + '/desktop-observation.json'
	if os.exists(output) || os.is_link(output) { return error('desktop observation must be fresh') }
	observation := probedesktop.run(task.invocation[0], task.invocation[1..],
		probe_desktop_setup, '', task.config)!
	os.write_file(output, json2.encode(observation, prettify: true))!
	return true
}

fn probe_desktop_exit(status int) !int {
	if status < 0 || status > 65535 { return error('invalid desktop application wait status') }
	if status & 127 == 0 { return (status >> 8) & 255 }
	if status & 127 > 64 || status >> 8 != 0 {
		return error('desktop application was not reaped to termination')
	}
	return 128 + (status & 127)
}

fn probe_desktop_observation(path string) !probedesktop.Observation {
	if os.lstat(path)!.get_filetype() != .regular || os.file_size(path) > 1048576 {
		return error('desktop wrapper did not produce a regular bounded observation')
	}
	text := os.read_file(path)!
	fields := json2.decode[map[string]json2.Any](text)!
	for name in ['handshake', 'builds', 'polls', 'nodes', 'images', 'closed', 'forced', 'wait_status',
		'stop'] {
		if name !in fields { return error('desktop observation omitted ${name}') }
	}
	observation := json2.decode[probedesktop.Observation](text)!
	probe_desktop_exit(observation.wait_status)!
	if observation.stop == '' || observation.builds < 0 || observation.polls < 0
		|| observation.nodes < 0 || observation.images < 0 || observation.images > observation.nodes
		|| (!observation.handshake && (observation.builds != 0 || observation.polls != 0))
		|| (observation.closed && (!observation.handshake || observation.builds < 1)) {
		return error('inconsistent desktop observation')
	}
	return observation
}

fn probe_desktop_application(out string, input ProbeInput, runtime ProbeRuntime,
	command []string, env map[string]string, mut result ProbeResult) !string {
	config := probe_desktop_config(runtime)!
	task := ProbeDesktopTask{ invocation: command, config: config }
	probe_desktop_validate(task)!
	path := out + '/desktop-task.json'
	os.write_file(path, json2.encode(task, prettify: true))!
	result.desktop_enabled = true
	wrapper_code, output := guarded_command(out, 'application-wrapper',
		[runtime.desktop_driver, '--linux-probe-desktop', path], input.bundle, env,
		runtime.deadline_seconds)!
	result.wrapper_exit = wrapper_code
	if wrapper_code != 0 {
		return error('desktop wrapper failed; actual application status is unavailable')
	}
	observation_path := out + '/desktop-observation.json'
	observation := probe_desktop_observation(observation_path)!
	result.application_exit = probe_desktop_exit(observation.wait_status)!
	result.desktop_handshake = observation.handshake
	result.desktop_forced = observation.forced
	os.write_file(out + '/application.status.txt', '${result.application_exit}\n')!
	return output
}
