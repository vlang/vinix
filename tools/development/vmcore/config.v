// SPDX-License-Identifier: GPL-2.0-or-later
module vmcore

import devcore
import json2
import os
import os.filelock

pub struct Config {
pub:
	schema        int = 1
	architecture  string
	accelerator   string = 'tcg'
	memory_mib    int    = 2048
	cpus          int    = 2
	qemu          devcore.Pin
	qemu_img      devcore.Pin
	disk          devcore.Pin
	firmware_code devcore.Pin
	firmware_vars devcore.Pin
	// TCG's executable mappings require an explicitly authorized JIT policy
	// in the installed system. The manager never grants or changes that policy.
	jit              bool
	network          bool
	ssh_port         int
	shared_directory string
	guest_agent      bool
	start_paused     bool
}

pub fn validate(config Config) ! {
	validate_settings(config)!
	for pin in [config.qemu, config.qemu_img, config.disk, config.firmware_code, config.firmware_vars] {
		devcore.verify(pin)!
		option_path(pin.path)!
	}
	if !os.is_executable(config.qemu.path) || !os.is_executable(config.qemu_img.path) {
		return error('QEMU and qemu-img must be executable')
	}
}

fn validate_settings(config Config) ! {
	if config.schema != 1 || config.architecture !in ['x86_64', 'aarch64']
		|| config.accelerator !in ['tcg', 'kvm', 'hvf'] || config.memory_mib < 64
		|| config.memory_mib > 65536 || config.cpus < 1 || config.cpus > 64
		|| config.ssh_port < 0 || config.ssh_port > 65535 || config.ssh_port != 0 && !config.network
		|| config.jit && config.accelerator != 'tcg' {
		return error('invalid VM configuration')
	}
	if config.shared_directory != '' {
		option_path(config.shared_directory)!
		if !os.is_dir(config.shared_directory) { return error('shared directory is missing') }
	}
}

fn option_path(path string) ! {
	if !path.starts_with('/') || path.contains(',') || path.contains('\x00') || path.contains('\n') {
		return error('QEMU paths must be absolute and contain no comma, newline or NUL')
	}
}

fn state_path(path string) !string {
	devcore.private_directory(path)!
	state := os.real_path(path)
	option_path(state)!
	// Unix-domain sockets have small architecture-dependent path limits.
	if state.len > 80 { return error('VM state path is too long for Unix sockets') }
	return state
}

pub fn load(path string) !(string, Config) {
	state := state_path(path)!
	config := json2.decode[Config](os.read_file(state + '/config.json')!, strict: true)!
	validate_settings(config)!
	return state, config
}

fn lease(state string) !filelock.FileLock {
	mut guard := filelock.new_file(state + '/run.lock', mode: .exclusive)
	if !guard.try_acquire() { return error('VM is running or another operation holds its lock') }
	return guard
}

pub fn initialise(config_text string, destination string) ! {
	config := json2.decode[Config](config_text, strict: true)!
	validate(config)!
	devcore.fresh_directory(destination)!
	state := state_path(destination)!
	os.write_file(state + '/run.lock', '')!
	mut guard := lease(state)!
	defer { guard.release() }
	// Each VM owns its disk and firmware variables. No writable state is
	// shared with another VM or with the user's original image.
	os.cp(config.firmware_code.path, state + '/code.fd')!
	os.cp(config.firmware_vars.path, state + '/vars.fd')!
	status := devcore.run([config.qemu_img.path, 'convert', '-f', 'raw', '-O', 'qcow2',
		config.disk.path, state + '/disk.qcow2'], state, devcore.environment(0), 3600,
		state + '/import.log')!
	if status != 0 { return error('disk import failed; see import.log') }
	for pin in [config.disk, config.firmware_code, config.firmware_vars] { devcore.verify(pin)! }
	os.write_file(state + '/config.json', json2.encode(config, prettify: true) + '\n')!
	os.mkdir(state + '/snapshots', mode: 0o700)!
}

pub fn arguments(config Config, state string) ![]string {
	option_path(state)!
	mut result := [config.qemu.path, '-name', 'vinix-managed', '-accel', config.accelerator, '-machine',
		if config.architecture == 'aarch64' { 'virt,gic-version=3' } else { 'q35,smm=off' }, '-cpu',
		if config.accelerator == 'tcg' { 'max' } else { 'host' }, '-m', config.memory_mib.str(),
		'-smp', config.cpus.str(), '-display', 'none', '-monitor', 'none', '-qmp',
		'unix:${state}/qmp.sock,server=on,wait=off', '-serial', 'file:${state}/serial.log', '-no-reboot',
		'-drive', 'if=pflash,format=raw,unit=0,readonly=on,file=${state}/code.fd', '-drive',
		'if=pflash,format=raw,unit=1,file=${state}/vars.fd', '-drive',
		'if=none,id=disk,format=qcow2,file=${state}/disk.qcow2', '-device',
		if config.architecture == 'aarch64' {
			'virtio-blk-device,drive=disk'
		} else {
			'virtio-blk-pci,drive=disk'
		}]
	if config.architecture == 'aarch64' { result << ['-device', 'ramfb'] }
	if config.start_paused { result << '-S' }
	if config.network {
		forward := if config.ssh_port == 0 {
			''
		} else {
			',hostfwd=tcp:127.0.0.1:${config.ssh_port}-:22'
		}
		result << ['-netdev', 'user,id=net' + forward, '-device',
			if config.architecture == 'aarch64' {
				'virtio-net-device,netdev=net'
			} else {
				'e1000,netdev=net'
			}]
	} else {
		result << ['-nic', 'none']
	}
	if config.shared_directory != '' {
		option_path(config.shared_directory)!
		result << ['-fsdev',
			'local,id=share,path=${config.shared_directory},security_model=none,readonly=on', '-device',
			if config.architecture == 'aarch64' {
				'virtio-9p-device,fsdev=share,mount_tag=vinix-share'
			} else {
				'virtio-9p-pci,fsdev=share,mount_tag=vinix-share'
			}]
	}
	if config.guest_agent {
		result << ['-chardev', 'socket,id=agent,path=${state}/agent.sock,server=on,wait=off', '-device',
			if config.architecture == 'aarch64' {
				'virtio-serial-device'
			} else {
				'virtio-serial-pci'
			}, '-device', 'virtserialport,chardev=agent,name=org.qemu.guest_agent.0']
	}
	return result
}
