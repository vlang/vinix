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
mut:
	// The log of the boot that is running.
	path   string
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

fn qemu_command(host Host, scenario Scenario, media []string, state string, boot int) ![]string {
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
	// Each boot of a machine that is booted more than once has a serial log
	// of its own: QEMU empties the file it is given.
	command << ['-display', 'none', '-monitor', 'none', '-serial',
		'file:' + os.join_path(state, serial_log_name(boot)), '-no-reboot', '-qmp',
		'unix:' + os.join_path(state, 'qmp.sock') + ',server=on,wait=off']
	command << substitute_all(scenario.boot_arguments(host.arch, boot), state)!
	return command
}

// What is followed across every boot of one scenario: the markers and the
// actions take up in a later boot where the one before left them, and the
// events of the machines that have ended are kept.
struct Session {
mut:
	markers MarkerWatch
	actions ActionCursor
	events  EventLog
}

// The events of the boots that have ended and of the one that is running.
fn (session &Session) events_with(running &EventLog) EventLog {
	// Copies of its own: adding counts in place.
	mut all := EventLog{
		names:  session.events.names.clone()
		counts: session.events.counts.clone()
	}
	all.add(running)
	return all
}

// Why a boot that is not the last did not end the way one must: by the
// guest switching the machine off. '' when it did.
pub fn intermediate_end_problem(boot int, shutdown_reason string, exit_code int, outcome string) string {
	how := if shutdown_reason != '' { shutdown_reason } else { outcome }
	if exit_code != 0 {
		return 'QEMU failed in boot ${boot + 1}: ${outcome}'
	}
	if shutdown_reason != 'guest-shutdown' {
		return 'boot ${boot + 1} ended by ${how}, not by the guest switching the machine off'
	}
	return ''
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
	mut media := boot_media(host, run.kernel, initramfs, scenario.cmdline, state)!
	mut media_cmdline := scenario.cmdline
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
	mut session := Session{
		markers: new_marker_watch(scenario.required, scenario.forbidden_markers())
		actions: new_action_cursor(scenario.actions)
	}
	qemu_log := os.join_path(state, 'qemu.log')
	os.write_file(qemu_log, '')!
	started := now_ms()
	deadline := started + i64(run.timeout) * 1000
	for boot in 0 .. scenario.boots() {
		last := boot == scenario.boots() - 1
		if boot > 0 {
			// The machine is off: QEMU has let go of the disks.
			for damage in scenario.reboots[boot - 1].damage {
				apply_damage(damage, state)!
			}
			os.rm(socket) or {}
			m.serial.text.lines << boot_separator(boot)
		}
		// A boot with a command line of its own, or the first after one,
		// needs the boot medium made for it.
		if scenario.boot_cmdline(boot) != media_cmdline {
			media_cmdline = scenario.boot_cmdline(boot)
			media = boot_media(host, run.kernel, initramfs, media_cmdline, state)!
		}
		command := qemu_command(host, scenario, media, state, boot)!
		mut log := os.open_append(qemu_log)!
		log.writeln(command.join(' '))!
		log.close()
		m.serial.path = os.join_path(state, serial_log_name(boot))
		m.serial.offset = 0
		m.child = start_child(command, map[string]string{}, qemu_log)!
		m.started = true
		m.qmp = qmp_connect(socket, os.join_path(state, 'qmp.log'), mut m.child, started) or {
			if err is Interrupted {
				return err
			}
			// A QEMU that would not start has said why, and nowhere else:
			// its log has the commands, and its complaint after the last.
			said := os.read_lines(qemu_log) or { []string{} }
			complaint := if said.len > boot + 1 { '\n  ' + said[boot + 1..].join('\n  ') } else { '' }
			return error(err.msg() + complaint)
		}
		m.watch(scenario, state, deadline, run.timeout, mut session, boot, last)!
		// QEMU has exited or the scenario leaves the machine up; either way
		// what the guest synced is in the disk files only once QEMU has let
		// go of them.
		m.child.stop()
		m.qmp.drain()
		session.events.add(&m.qmp.events)
		m.qmp.close()
		m.qmp = unsafe { nil }
		m.started = false
	}
	for disk in scenario.disks {
		check_disk_header(disk, state)!
		check_disk_untouched(disk, state)!
	}
	for pattern in scenario.patterns {
		check_pattern(pattern, state)!
	}
	for bytes in scenario.disk_bytes {
		check_disk_bytes(bytes, state)!
	}
	for screen in scenario.screens {
		check_screen(screen, state)!
	}
	for sound in scenario.sounds {
		check_sound(sound, state)!
	}
	for writing in scenario.writings {
		check_writing(writing, state)!
	}
}

// Follows one boot until the machine ends, or until nothing more is expected
// of a machine that stays up. `last` says it is the scenario's final boot,
// which is the one the scenario's ending is asked of; any other must end
// with the guest switching the machine off.
fn (mut m Machine) watch(scenario Scenario, state string, deadline i64, timeout int, mut session Session, boot int, last bool) ! {
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
			session.markers.line(line)
			session.actions.line(line, now)
			if line.contains('HWTEST INFO') {
				m.notes << line.all_after('HWTEST INFO').trim_space()
			}
		}
		m.qmp.drain()
		if ended {
			break
		}
		if session.markers.failed() {
			if failed_at == 0 {
				failed_at = now
			}
			if now - failed_at >= failure_grace_ms {
				break
			}
		} else {
			events := session.events_with(&m.qmp.events)
			if action := session.actions.take_ready(now, &events) {
				command := substitute(action.qmp, state)!
				answer := m.qmp.execute(command)!
				fault := answer_fault(action, answer.text)
				if fault != '' {
					return error(fault)
				}
				if action.end_within > 0 {
					end_deadline = now_ms() + i64(action.end_within) * 1000
					end_reason = '${action.end_within} s after ${command}'
				}
			}
			if last && scenario.ending == .running && session.markers.complete()
				&& session.actions.done() {
				return
			}
		}
		if end_deadline != 0 && now >= end_deadline {
			return error('the machine was still running ${end_reason}')
		}
		if now >= deadline {
			where := if scenario.boots() > 1 { ' (in boot ${boot + 1} of ${scenario.boots()})' } else { '' }
			event := session.actions.waiting_for_event()
			if event != '' {
				return error('timed out after ${timeout} s${where}: QEMU never reported the event ${event}')
			}
			missing := session.markers.missing()
			if missing.len > 0 {
				return error('timed out after ${timeout} s${where} without ${quoted(missing)}')
			}
			waiting := session.actions.waiting_for()
			if waiting != '' {
				return error('timed out after ${timeout} s${where} waiting for "${waiting}"')
			}
			return error('timed out after ${timeout} s${where}: the machine did not power off')
		}
		time.sleep(poll_interval)
	}
	if session.markers.failed() {
		return error('forbidden "${session.markers.forbidden_marker}" in the line: ${session.markers.forbidden_line}')
	}
	// From here on the machine has ended by itself.
	how := if m.qmp.shutdown_reason != '' { m.qmp.shutdown_reason } else { m.child.outcome() }
	if !last {
		problem := intermediate_end_problem(boot, m.qmp.shutdown_reason, m.child.exit_code(),
			m.child.outcome())
		if problem != '' {
			return error(problem)
		}
		return
	}
	missing := session.markers.missing()
	if missing.len > 0 {
		return error('the machine ended (${how}) without ${quoted(missing)}')
	}
	if !session.actions.done() {
		return error('the machine ended (${how}) before an action could run; its marker was "${session.actions.waiting_for()}"')
	}
	unseen := session.events_with(&m.qmp.events).missing(scenario.events)
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
	} else if reason == '' {
		for disk in scenario.disks {
			if disk.bulky {
				os.rm(os.join_path(run.state, disk.name)) or {}
			}
		}
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
