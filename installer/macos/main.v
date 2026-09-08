module main

import json2
import os
import strconv
import ui2

const installer_width = 680
const installer_height = 556
const default_space_gb = 32
const minimum_space_gb = 16
const decimal_gb = i64(1_000_000_000)
const compiled_source_root = $d('vinix_source_root', '')

struct DiskList {
	whole_disks              []string @[json: 'WholeDisks']
	all_disks_and_partitions []DiskPartition @[json: 'AllDisksAndPartitions']
}

struct DiskPartition {
	device_identifier string @[json: 'DeviceIdentifier']
	size              i64 @[json: 'Size']
	partitions        []PartitionInfo @[json: 'Partitions']
}

struct PartitionInfo {
	content string @[json: 'Content']
}

struct DiskInfo {
	device_identifier string @[json: 'DeviceIdentifier']
	media_name        string @[json: 'MediaName']
	registry_name     string @[json: 'IORegistryEntryName']
	bus_protocol      string @[json: 'BusProtocol']
	device_tree_path  string @[json: 'DeviceTreePath']
	virtual_physical  string @[json: 'VirtualOrPhysical']
	size              i64 @[json: 'Size']
	internal          bool @[json: 'Internal']
	writable          bool @[json: 'Writable']
	whole_disk        bool @[json: 'WholeDisk']
}

struct InstallDisk {
	id        string
	name      string
	bus       string
	size      i64
	internal  bool
	is_system bool
}

fn (disk InstallDisk) display_name() string {
	location := if disk.is_system { 'internal, startup disk' } else { 'external; will be erased' }
	return '${disk.id} — ${disk.name} — ${format_gb(disk.size)} (${location})'
}

fn (disk InstallDisk) detail() string {
	if disk.is_system {
		return 'macOS stays in place. Its APFS container is safely shrunk by the upstream installer.'
	}
	return 'All partitions and data on ${disk.id} will be erased. Space after the Vinix allocation stays free.'
}

@[heap]
struct InstallerState {
mut:
	disks        []InstallDisk
	selected     int
	space_text   string = default_space_gb.str()
	acknowledged bool
	supported    bool
	payload_dir  string
	status       string
	status_error bool
}

const installer_state = &InstallerState{}

fn shell_output(command string) !string {
	mut process := os.new_process('/bin/sh')
	process.set_args(['-c', command])
	process.set_redirect_stdio_merged()
	process.run()
	output := process.stdout_slurp()
	process.wait()
	if process.code != 0 {
		return error(output.trim_space())
	}
	return output
}

fn valid_disk_id(id string) bool {
	if !id.starts_with('disk') || id.len <= 4 {
		return false
	}
	for character in id[4..] {
		if character < `0` || character > `9` {
			return false
		}
	}
	return true
}

fn is_system_disk(entry DiskPartition) bool {
	return entry.partitions.any(it.content == 'Apple_APFS_ISC')
}

fn decode_disk_listing(list_json string, info_json map[string]string) ![]InstallDisk {
	listing := json2.decode[DiskList](list_json)!
	mut system_disk := ''
	for entry in listing.all_disks_and_partitions {
		if is_system_disk(entry) {
			system_disk = entry.device_identifier
			break
		}
	}
	if system_disk.len == 0 {
		return error('could not identify the Apple Silicon startup disk')
	}

	mut disks := []InstallDisk{}
	for id in listing.whole_disks {
		if !valid_disk_id(id) {
			continue
		}
		raw := info_json[id] or { continue }
		info := json2.decode[DiskInfo](raw) or { continue }
		if !info.whole_disk || !info.writable || info.size <= 0 {
			continue
		}
		is_startup := id == system_disk
		// Match the external-disk policy in the upstream Asahi installer. In
		// particular, do not offer disk images, Thunderbolt targets, SD cards,
		// or USB devices attached through a topology m1n1 cannot boot.
		external_bootable := !info.internal && info.virtual_physical != 'Virtual'
			&& info.bus_protocol == 'USB' && info.device_tree_path.contains('usb-drd')
		if !is_startup && !external_bootable {
			continue
		}
		name := if info.media_name.len > 0 {
			info.media_name
		} else if info.registry_name.len > 0 {
			info.registry_name
		} else {
			'Physical disk'
		}
		disks << InstallDisk{
			id: id
			name: name
			bus: info.bus_protocol
			size: info.size
			internal: info.internal
			is_system: is_startup
		}
	}
	disks.sort_with_compare(fn (a &InstallDisk, b &InstallDisk) int {
		if a.is_system != b.is_system {
			return if a.is_system { -1 } else { 1 }
		}
		return a.id.compare(b.id)
	})
	if disks.len == 0 || !disks[0].is_system {
		return error('the startup disk is not writable')
	}
	return disks
}

fn discover_disks() ![]InstallDisk {
	list_json := shell_output('/usr/sbin/diskutil list -plist physical | /usr/bin/plutil -convert json -o - -- -')!
	listing := json2.decode[DiskList](list_json)!
	mut info := map[string]string{}
	for id in listing.whole_disks {
		if !valid_disk_id(id) {
			continue
		}
		info[id] = shell_output('/usr/sbin/diskutil info -plist ${id} | /usr/bin/plutil -convert json -o - -- -')!
	}
	return decode_disk_listing(list_json, info)
}

fn format_gb(bytes i64) string {
	return '${f64(bytes) / f64(decimal_gb):.1f} GB'
}

fn allocation_gb(value string, disk InstallDisk) !int {
	trimmed := value.trim_space()
	if trimmed.len == 0 || trimmed.bytes().any(it < `0` || it > `9`) {
		return error('Enter the allocation as a whole number of GB.')
	}
	amount := strconv.atoi(trimmed) or { return error('Enter the allocation as a whole number of GB.') }
	if amount < minimum_space_gb {
		return error('Vinix needs at least ${minimum_space_gb} GB.')
	}
	disk_gb := int(disk.size / decimal_gb)
	maximum := if disk.is_system { disk_gb - 40 } else { disk_gb }
	if amount > maximum {
		if disk.is_system {
			return error('Leave at least 40 GB on the startup disk for macOS and updates.')
		}
		return error('The allocation is larger than ${disk.id}.')
	}
	return amount
}

fn support_file(name string) string {
	executable_dir := os.dir(os.executable())
	if os.base(executable_dir) == 'MacOS' {
		candidate := os.join_path(os.dir(executable_dir), 'Resources', name)
		if os.is_file(candidate) {
			return candidate
		}
	}
	return os.join_path(os.dir(@FILE), name)
}

fn payload_files_exist(path string) bool {
	flat_files := ['BOOTAA64.EFI', 'limine.conf', 'vinix', 'initramfs.tar']
	if flat_files.all(os.is_file(os.join_path(path, it))) {
		return true
	}
	repo_files := [
		'boot-image/limine-bin/BOOTAA64.EFI',
		'build-support/limine.conf',
		'kernel/bin/vinix',
		'build-support/init-aarch64/initramfs-desktop.tar',
	]
	return repo_files.all(os.is_file(os.join_path(path, it)))
}

fn locate_payload() string {
	executable_dir := os.dir(os.executable())
	if os.base(executable_dir) == 'MacOS' {
		bundled := os.join_path(os.dir(executable_dir), 'Resources', 'payload')
		if payload_files_exist(bundled) {
			return bundled
		}
	}
	configured := os.getenv_opt('VINIX_INSTALLER_PAYLOAD') or { '' }
	if configured.len > 0 && payload_files_exist(configured) {
		return os.real_path(configured)
	}
	if compiled_source_root.len > 0 && payload_files_exist(compiled_source_root) {
		return compiled_source_root
	}
	repository := os.real_path(os.join_path(os.dir(@FILE), '..', '..'))
	if payload_files_exist(repository) {
		return repository
	}
	return ''
}

fn machine_support_error() string {
	$if !macos {
		return 'The installer app runs only on macOS.'
	}
	architecture := shell_output('/usr/bin/uname -m') or { return 'Could not identify this Mac.' }
	if architecture.trim_space() != 'arm64' {
		return 'Vinix requires an Apple Silicon Mac running natively, not Rosetta.'
	}
	brand := shell_output('/usr/sbin/sysctl -n machdep.cpu.brand_string') or {
		return 'Could not identify the Apple Silicon processor.'
	}
	if brand.trim_space() != 'Apple M1' {
		return 'This Vinix image currently supports the original Apple M1 only (found ${brand.trim_space()}).'
	}
	return ''
}

fn current_disk(state &InstallerState) ?InstallDisk {
	if state.selected < 0 || state.selected >= state.disks.len {
		return none
	}
	return state.disks[state.selected]
}

fn acknowledgement_text(disk InstallDisk) string {
	if disk.is_system {
		return 'I have a current backup of this Mac.'
	}
	return 'I understand that ${disk.id} will be completely erased.'
}

fn install_ready(state &InstallerState) bool {
	if !state.supported || state.payload_dir.len == 0 || !state.acknowledged {
		return false
	}
	disk := current_disk(state) or { return false }
	allocation_gb(state.space_text, disk) or { return false }
	return true
}

fn enabled_element(element ui2.Element, enabled bool) ui2.Element {
	return ui2.Element{
		...element
		enabled: enabled
	}
}

fn build_screen() ui2.Element {
	state := unsafe { installer_state }
	frame := ui2.bounds()
	width := if frame.width > 0 { frame.width } else { f64(installer_width) }
	mut children := []ui2.Element{}
	children << ui2.view('card', ui2.rect(24, 20, width - 48, 510), ui2.BoxStyle{
		bg: 0xffffff
		radius: 12
	}, [
		ui2.label('title', 'Install Vinix on Apple M1', ui2.rect(24, 22, width - 96, 34), ui2.TextStyle{
			color: 0x111827
			size: 24
			bold: true
		}),
		ui2.label('subtitle', 'Set up m1n1, U-Boot, Limine, and the Vinix desktop beside macOS.', ui2.rect(24, 60, width - 96, 22), ui2.TextStyle{
			color: 0x64748b
			size: 13
		}),
		ui2.view('rule', ui2.rect(24, 96, width - 96, 1), ui2.BoxStyle{ bg: 0xe2e8f0 }, []),
		ui2.label('disk_label', 'Disk', ui2.rect(24, 118, width - 96, 20), ui2.TextStyle{
			color: 0x334155
			size: 13
			bold: true
		}),
	])

	mut options := []string{}
	for disk in state.disks {
		options << disk.display_name()
	}
	selected_text := if disk := current_disk(state) {
		disk.display_name()
	} else {
		'No compatible disk found'
	}
	children << enabled_element(ui2.dropdown('disk', selected_text, options, ui2.rect(48, 160, width - 96, 38), ui2.BoxStyle{ bg: 0xf8fafc, radius: 7 }, ui2.TextStyle{
		color: 0x0f172a
		size: 13
	}), options.len > 0)

	detail := if disk := current_disk(state) {
		disk.detail()
	} else {
		'Connect a compatible disk and refresh.'
	}
	detail_color := if disk := current_disk(state) {
		if disk.is_system { u32(0x64748b) } else { u32(0xb45309) }
	} else {
		u32(0x64748b)
	}
	children << ui2.label('disk_detail', detail, ui2.rect(48, 206, width - 96, 34), ui2.TextStyle{
		color: detail_color
		size: 12
		lines: 2
	})
	children << ui2.label('space_label', 'Space for Vinix', ui2.rect(48, 258, 220, 20), ui2.TextStyle{
		color: 0x334155
		size: 13
		bold: true
	})
	children << ui2.text_field_with_change('space', '32', state.space_text, ui2.rect(48, 284, 132, 38), ui2.BoxStyle{ bg: 0xf8fafc, radius: 7 }, ui2.TextStyle{
		color: 0x0f172a
		size: 14
	}, ui2.keyboard_decimal)
	children << ui2.label('space_unit', 'GB', ui2.rect(190, 293, 36, 20), ui2.TextStyle{
		color: 0x475569
		size: 13
	})
	children << ui2.label('space_help', 'Minimum ${minimum_space_gb} GB. The Asahi safety checks preserve room needed by macOS.', ui2.rect(240, 287, width - 288, 34), ui2.TextStyle{
		color: 0x64748b
		size: 12
		lines: 2
	})

	if disk := current_disk(state) {
		children << ui2.checkbox('acknowledge', acknowledgement_text(disk), state.acknowledged, ui2.rect(48, 344, width - 96, 28), ui2.TextStyle{
			color: 0x334155
			size: 13
		})
	}
	status_color := if state.status_error { u32(0xb91c1c) } else { u32(0x166534) }
	children << ui2.label('status', state.status, ui2.rect(48, 386, width - 96, 46), ui2.TextStyle{
		color: status_color
		size: 12
		lines: 2
	})
	children << ui2.with_native_style(ui2.button('refresh', 'Refresh disks', ui2.rect(48, 454, 116, 34), ui2.BoxStyle{}, ui2.TextStyle{}))
	install_button := ui2.with_native_style(ui2.button('install', 'Install Vinix…', ui2.rect(width - 180, 454, 132, 34), ui2.BoxStyle{}, ui2.TextStyle{}))
	children << enabled_element(install_button, install_ready(state))
	return ui2.screen(0xf1f5f9, children)
}

fn shell_quote(value string) string {
	return "'" + value.replace("'", '\'"\'"\'') + "'"
}

fn launch_installer(support string, disk InstallDisk, space int, payload string) ! {
	command_path := os.join_path(os.temp_dir(), 'vinix-installer-${os.getpid()}.command')
	command := '#!/bin/sh\nexec ${shell_quote(support)} --confirmed --disk ${shell_quote(disk.id)} --space-gb ${space} --payload ${shell_quote(payload)}\n'
	os.write_file(command_path, command)!
	os.chmod(command_path, 0o700)!
	mut process := os.new_process('/usr/bin/open')
	process.set_args(['-a', 'Terminal', command_path])
	process.run()
	process.wait()
	if process.code != 0 {
		return error('Terminal could not be opened (exit ${process.code}).')
	}
}

fn refresh_disks(mut state InstallerState) {
	state.disks = discover_disks() or {
		state.status = 'Disk discovery failed: ${err}'
		state.status_error = true
		state.selected = -1
		return
	}
	state.selected = 0
	state.acknowledged = false
	state.status = 'Ready. Installation continues in Terminal for administrator authentication and progress.'
	state.status_error = false
}

fn begin_install(mut state InstallerState) {
	disk := current_disk(state) or {
		state.status = 'Select a compatible disk.'
		state.status_error = true
		return
	}
	space := allocation_gb(state.space_text, disk) or {
		state.status = err.msg()
		state.status_error = true
		return
	}
	warning := if disk.is_system {
		'Vinix will shrink the macOS APFS container on ${disk.id} and allocate ${space} GB. Back up first. The upstream installer will stop if its APFS safety checks do not pass.'
	} else {
		'ALL DATA on ${disk.id} (${disk.name}) will be erased. Vinix will use ${space} GB and leave the rest unallocated.'
	}
	if !ui2.confirm('Install Vinix?', warning) {
		return
	}
	support := support_file('install-vinix.sh')
	if !os.is_file(support) {
		state.status = 'Installer support file is missing: ${support}'
		state.status_error = true
		return
	}
	launch_installer(support, disk, space, state.payload_dir) or {
		state.status = err.msg()
		state.status_error = true
		return
	}
	state.status = 'Installer opened in Terminal. Keep this Mac connected to power and follow the authentication prompt.'
	state.status_error = false
}

fn handle_event(event string) {
	mut state := unsafe { installer_state }
	match event {
		'disk' {
			selected := ui2.text('disk')
			for index, disk in state.disks {
				if disk.display_name() == selected {
					state.selected = index
					state.acknowledged = false
					break
				}
			}
		}
		'space' {
			state.space_text = ui2.text('space')
			if disk := current_disk(state) {
				allocation_gb(state.space_text, disk) or {
					state.status = err.msg()
					state.status_error = true
					ui2.refresh()
					return
				}
				state.status = 'Ready. The exact APFS resize is verified again before any disk changes.'
				state.status_error = false
			}
		}
		'acknowledge' {
			state.acknowledged = !state.acknowledged
		}
		'refresh' { refresh_disks(mut state) }
		'install' { begin_install(mut state) }
		else {}
	}
	ui2.refresh()
}

fn main() {
	mut state := unsafe { installer_state }
	state.payload_dir = locate_payload()
	support_error := machine_support_error()
	if support_error.len > 0 {
		state.supported = false
		state.status = support_error
		state.status_error = true
	} else {
		state.supported = true
		refresh_disks(mut state)
	}
	if state.payload_dir.len == 0 {
		state.status = 'Vinix boot payload is missing. Build the desktop image, then rebuild this app.'
		state.status_error = true
	}
	ui2.run_window('Vinix Installer', installer_width, installer_height, build_screen, handle_event)
}
