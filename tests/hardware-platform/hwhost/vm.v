// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// One scenario, from nothing to a verdict: build what boots, start QEMU,
// follow the serial port, do what the scenario's actions ask, and judge how
// the machine ended.
//
// The verdict is made of things the machine did, not of how long things
// took. Every required line must have been printed and no forbidden one; a
// machine that is to power off must have done so itself, which QEMU reports
// as a SHUTDOWN event caused by the guest -- a triple fault also makes QEMU
// exit, and must not pass for a power-off.
module hwhost

import os
import time

// The lines of a failing run that are printed with the verdict.
pub const tail_lines = 40

const poll_interval = 50 * time.millisecond

// After a forbidden line the machine is left running this long: what follows
// a panic's first line is the part worth reading.
const failure_grace_ms = 2000

// macOS allows 104 bytes for a unix socket's path and Linux 108, with the
// terminator.
const socket_path_limit = 100

pub struct Run {
pub:
	kernel  string
	guest   string // the guest binary, already built
	state   string // this scenario's state directory
	timeout int    // seconds the machine may run
	keep    bool   // leave the images in the state directory
}

pub struct Outcome {
pub:
	scenario    string
	passed      bool
	interrupted bool
	seconds     f64
	reason      string   // why it failed
	notes       []string // what the guest reported with HWTEST INFO
	tail        []string // the last serial lines
	state       string
}

// Reads what has been added to the serial log since the last look.
struct SerialReader {
	path string
mut:
	offset u64
	text   SerialLines
}

fn (mut r SerialReader) read() []string {
	size := os.file_size(r.path)
	if size <= r.offset {
		return []string{}
	}
	mut file := os.open(r.path) or { return []string{} }
	defer {
		file.close()
	}
	mut buffer := []u8{len: int(size - r.offset)}
	count := file.read_from(r.offset, mut buffer) or { 0 }
	if count <= 0 {
		return []string{}
	}
	r.offset += u64(count)
	return r.text.feed(buffer[..count])
}

struct Machine {
mut:
	child   Child
	started bool // there is a QEMU to stop
	qmp     &QmpClient = unsafe { nil }
	serial  SerialReader
	notes   []string
}

// Stops QEMU and closes its socket. Safe at any point of a run, and the one
// thing that happens after every run however it went.
fn (mut m Machine) stop() {
	if m.started {
		m.child.stop()
	}
	if !isnil(m.qmp) {
		// QEMU says why it is going before it goes; that belongs in the log.
		m.qmp.drain()
		m.qmp.close()
		m.qmp = unsafe { nil }
	}
}

fn qemu_command(host Host, scenario Scenario, media []string, state string) ![]string {
	mut command := [host.qemu]
	if host.arch == 'aarch64' {
		command << ['-machine', 'virt,gic-version=3']
		command << host.accelerator()
		command << ['-m', '1024', '-smp', '4']
		// The devices scripts/run-aarch64.sh gives the machine: an entropy
		// source, input, and ramfb for the firmware's framebuffer. The
		// tests boot what that script boots, less the desktop.
		command << ['-object', 'rng-random,filename=/dev/urandom,id=vinix-rng', '-device',
			'virtio-rng-device,rng=vinix-rng']
		command << media
		command << ['-device', 'virtio-keyboard-device', '-device', 'virtio-tablet-device', '-device',
			'ramfb']
	} else {
		// The machine the repository's amd64 scripts boot
		// (scripts/run-desktop-amd64.sh), so a result here is about the
		// same one.
		command << ['-machine', 'q35,smm=off']
		command << host.accelerator()
		command << ['-m', '1024', '-smp', '2']
		command << media
	}
	// -no-reboot turns a reset into an exit: a guest that crashes into its
	// reset vector ends the run instead of booting again until the timeout.
	command << ['-display', 'none', '-monitor', 'none', '-serial',
		'file:' + os.join_path(state, 'serial.log'), '-no-reboot', '-qmp',
		'unix:' + os.join_path(state, 'qmp.sock') + ',server=on,wait=off']
	command << substitute_all(scenario.qemu_arguments(host.arch), state)!
	return command
}

// Builds, boots and watches. An error is the reason the scenario failed.
fn (mut m Machine) run(host Host, scenario Scenario, run Run) ! {
	state := run.state
	check_state_path(state)!
	socket := os.join_path(state, 'qmp.sock')
	if socket.len > socket_path_limit {
		return error('${socket} is too long for a unix socket; use a shorter --state-dir')
	}
	os.mkdir_all(state)!
	initramfs := build_initramfs(run.guest, scenario.name, state)!
	media := boot_media(host, run.kernel, initramfs, scenario.cmdline, state)!
	for disk in scenario.disks {
		create_disk(disk, state)!
	}
	for file in scenario.files {
		path := os.join_path(state, file.path)
		os.mkdir_all(os.dir(path))!
		os.write_file(path, file.text)!
	}
	for table in scenario.tables {
		os.write_file_array(os.join_path(state, table + '.aml'), acpi_table(table)!)!
	}
	command := qemu_command(host, scenario, media, state)!
	qemu_log := os.join_path(state, 'qemu.log')
	os.write_file(qemu_log, command.join(' ') + '\n')!
	m.serial = SerialReader{
		path: os.join_path(state, 'serial.log')
	}
	m.child = start_child(command, map[string]string{}, qemu_log)!
	m.started = true
	started := now_ms()
	m.qmp = qmp_connect(socket, os.join_path(state, 'qmp.log'), mut m.child, started) or {
		if err is Interrupted {
			return err
		}
		// A QEMU that would not start has said why, and nowhere else: the
		// first line of its log is the command, the rest is its complaint.
		said := os.read_lines(qemu_log) or { []string{} }
		complaint := if said.len > 1 { '\n  ' + said[1..].join('\n  ') } else { '' }
		return error(err.msg() + complaint)
	}
	m.watch(scenario, state, started + i64(run.timeout) * 1000, run.timeout)!
	// QEMU has exited or the scenario leaves the machine up; either way what
	// the guest synced is in the disk files only once QEMU has let go of
	// them.
	m.child.stop()
	for disk in scenario.disks {
		check_disk_header(disk, state)!
	}
	for pattern in scenario.patterns {
		check_pattern(pattern, state)!
	}
	for screen in scenario.screens {
		check_screen(screen, state)!
	}
	for sound in scenario.sounds {
		check_sound(sound, state)!
	}
}

fn (mut m Machine) watch(scenario Scenario, state string, deadline i64, timeout int) ! {
	mut markers := new_marker_watch(scenario.required, scenario.forbidden_markers())
	mut actions := new_action_cursor(scenario.actions)
	mut end_deadline := i64(0) // set by an action with end_within
	mut end_reason := ''
	mut failed_at := i64(0)
	mut ended := false
	for {
		if interrupted() {
			return Interrupted{}
		}
		// Look at the process first and the log second: what the machine
		// wrote last is then in the log by the time it is read.
		ended = m.child.poll()
		mut fresh := m.serial.read()
		if ended {
			fresh << m.serial.text.finish()
		}
		now := now_ms()
		for line in fresh {
			markers.line(line)
			actions.line(line, now)
			if line.contains('HWTEST INFO') {
				m.notes << line.all_after('HWTEST INFO').trim_space()
			}
		}
		m.qmp.drain()
		if ended {
			break
		}
		if markers.failed() {
			if failed_at == 0 {
				failed_at = now
			}
			if now - failed_at >= failure_grace_ms {
				break
			}
		} else {
			if action := actions.take_ready(now, &m.qmp.events) {
				command := substitute(action.qmp, state)!
				m.qmp.execute(command)!
				if action.end_within > 0 {
					end_deadline = now_ms() + i64(action.end_within) * 1000
					end_reason = '${action.end_within} s after ${command}'
				}
			}
			if scenario.ending == .running && markers.complete() && actions.done() {
				return
			}
		}
		if end_deadline != 0 && now >= end_deadline {
			return error('the machine was still running ${end_reason}')
		}
		if now >= deadline {
			event := actions.waiting_for_event()
			if event != '' {
				return error('timed out after ${timeout} s: QEMU never reported the event ${event}')
			}
			missing := markers.missing()
			if missing.len > 0 {
				return error('timed out after ${timeout} s without ${quoted(missing)}')
			}
			waiting := actions.waiting_for()
			if waiting != '' {
				return error('timed out after ${timeout} s waiting for "${waiting}"')
			}
			return error('timed out after ${timeout} s: the machine did not power off')
		}
		time.sleep(poll_interval)
	}
	if markers.failed() {
		return error('forbidden "${markers.forbidden_marker}" in the line: ${markers.forbidden_line}')
	}
	// From here on the machine has ended by itself.
	how := if m.qmp.shutdown_reason != '' { m.qmp.shutdown_reason } else { m.child.outcome() }
	missing := markers.missing()
	if missing.len > 0 {
		return error('the machine ended (${how}) without ${quoted(missing)}')
	}
	if !actions.done() {
		return error('the machine ended (${how}) before an action could run; its marker was "${actions.waiting_for()}"')
	}
	unseen := m.qmp.events.missing(scenario.events)
	if unseen.len > 0 {
		return error('the machine ended (${how}) without QEMU reporting ${quoted(unseen)} as often as expected')
	}
	if scenario.ending == .running {
		return error('the machine ended (${how}); it was expected to stay up')
	}
	if m.child.exit_code() != 0 {
		return error('QEMU failed: ${m.child.outcome()}')
	}
	if scenario.ending == .restart {
		if m.qmp.shutdown_reason != 'guest-reset' {
			return error('the machine ended by ${how}, not by the guest restarting it')
		}
		return
	}
	if m.qmp.shutdown_reason != 'guest-shutdown' {
		return error('the machine ended by ${how}, not by the guest powering it off')
	}
}

fn quoted(markers []string) string {
	return markers.map('"${it}"').join(', ')
}

pub fn run_scenario(host Host, scenario Scenario, run Run) Outcome {
	started := now_ms()
	mut machine := Machine{}
	mut reason := ''
	mut was_interrupted := false
	machine.run(host, scenario, run) or {
		was_interrupted = err is Interrupted
		reason = err.msg()
	}
	machine.stop()
	if !run.keep {
		remove_images(scenario, run.state)
	}
	return Outcome{
		scenario:    scenario.name
		passed:      reason == ''
		interrupted: was_interrupted
		seconds:     f64(now_ms() - started) / 1000.0
		reason:      reason
		notes:       machine.notes
		tail:        machine.serial.text.tail(tail_lines)
		state:       run.state
	}
}
