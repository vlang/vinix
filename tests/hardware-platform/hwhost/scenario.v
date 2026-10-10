// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The scenario table: what each hardware test boots, what it must print, and
// what the host does to the machine while it runs.
//
// A scenario is data. Its guest half is the function of the same name in
// ../guest (scenario_<name>), and the two halves meet only through the lines
// the guest prints on the serial port. Nothing here knows what a scenario
// checks inside the guest, so a new one is a record below and a function
// there, with no change to the controller.
module hwhost

pub const architectures = ['aarch64', 'x86_64']

// What no scenario may print. The first two are the kernel's own words for
// dying; the third is the guest saying a check did not hold.
pub const always_forbidden = ['KERNEL PANIC', 'FATAL EXCEPTION', 'HWTEST FAIL']

// How the machine is expected to end.
pub enum Ending {
	// QEMU exits by itself because the guest powered the machine off.
	poweroff
	// QEMU exits by itself because the guest reset the machine: it runs
	// with -no-reboot, which turns a reset into an exit that says so.
	restart
	// The guest stays up: the controller stops QEMU once every marker is seen.
	running
}

// A file the controller writes in the state directory before the boot.
pub struct StateFile {
pub:
	path string // relative to the state directory; directories are made
	text string
}

// A raw disk the controller creates in the state directory before the boot.
pub struct Disk {
pub:
	name     string // file name inside the state directory
	size_mib int
	// Written at offset 0. The kernel installs the system onto a disk that is
	// blank, so a test disk that must be left alone starts with something.
	header string
}

// Bytes the guest is expected to have left on a disk, checked on the host
// after the machine is gone: byte i of the run is seed + 7 * i (mod 256), the
// pattern the guest writes with pattern_bytes().
pub struct DiskPattern {
pub:
	disk   string
	offset u64
	length int
	seed   u8
}

// One thing the host does to the machine. Actions run in the order listed,
// and each waits for its own marker on a line printed after the previous
// action's, so a guest can ask for the same thing twice.
pub struct Action {
pub:
	after    string // the serial marker that triggers it
	delay_ms int    // how long after the marker the command is sent
	qmp      string // the command, as QMP JSON text; may contain {state}
	// With a value, the machine must end the way the scenario expects within
	// this many seconds of the command, rather than by the scenario timeout.
	end_within int
}

pub struct Scenario {
pub:
	name   string
	about  string
	arches []string
	// A reason the scenario cannot pass yet. Such a scenario runs only when it
	// is named, so the default run stays a statement about what works.
	pending string
	// A flag the kernel must have been built with (-d <define>) for the
	// scenario to mean anything: a self-test compiled into the kernel. Such a
	// scenario also runs only when it is named, against a kernel built for it.
	define  string
	cmdline string // extra kernel command line
	// Extra QEMU arguments, for every architecture and for one. `{state}`
	// stands for the scenario's state directory.
	qemu         []string
	qemu_aarch64 []string
	qemu_x86_64  []string
	disks        []Disk
	// ACPI tables to give the machine, by the names acpi_table() knows. Each is
	// written to {state}/<name>.aml; the scenario's own QEMU arguments load it.
	tables       []string
	// Small files to put in the state directory before the boot, such as what
	// QEMU's TFTP server is to serve.
	files        []StateFile
	required     []string // every one must appear on some serial line
	forbidden    []string // besides always_forbidden
	actions      []Action
	ending       Ending
	patterns     []DiskPattern
}

// What QEMU's TFTP server serves the guest's network probe; see guest/network.v.
const tftp_probe = StateFile{
	path: 'tftp/hwtest-probe'
	text: 'hwtest-okay'
}

const iommu_disk = Disk{
	name:     'disk.raw'
	size_mib: 32
	header:   'vinix hardware test disk: not blank'
}

pub const scenarios = [
	Scenario{
		name:         'devices'
		about:        'PCI devices in sysfs; unbind, bind, reset and remove an e1000'
		arches:       ['aarch64', 'x86_64']
		qemu_aarch64: ['-device', 'e1000,netdev=hwn0', '-netdev', 'user,id=hwn0']
		qemu_x86_64:  ['-nic', 'user,model=e1000']
		required:     ['HWTEST START devices', 'HWTEST PASS devices']
		ending:       .poweroff
	},
	Scenario{
		name:     'ahci'
		about:    'SATA disk I/O before and after a controller reset'
		arches:   ['x86_64']
		qemu:     ['-drive', 'if=ide,format=raw,file={state}/disk.raw']
		disks:    [
			Disk{
				name:     'disk.raw'
				size_mib: 32
				header:   'vinix hardware test disk: not blank'
			},
		]
		required: ['HWTEST START ahci', 'HWTEST PASS ahci']
		ending:   .poweroff
		patterns: [
			DiskPattern{
				disk:   'disk.raw'
				offset: 1 << 20
				length: 65536
				seed:   0x11
			},
			DiskPattern{
				disk:   'disk.raw'
				offset: 2 << 20
				length: 65536
				seed:   0x55
			},
		]
	},
	Scenario{
		name:     'qmp-powerdown'
		about:    'the power button powers the machine off'
		arches:   ['aarch64', 'x86_64']
		required: ['HWTEST START qmp-powerdown', 'HWTEST STEP waiting for power button']
		actions:  [
			Action{
				after:      'HWTEST STEP waiting for power button'
				qmp:        '{"execute":"system_powerdown"}'
				end_within: 30
			},
		]
		ending:   .poweroff
	},
	Scenario{
		name:     'power-button-init'
		about:    'the power button asks an init that handles the request'
		arches:   ['aarch64', 'x86_64']
		required: ['HWTEST START power-button-init', 'HWTEST PASS power-button-init']
		actions:  [
			Action{
				after: 'HWTEST STEP waiting for power button'
				qmp:   '{"execute":"system_powerdown"}'
			},
		]
		ending:   .poweroff
	},
	Scenario{
		name:     'iommu-intel'
		about:    'network card and disk controller isolated behind Intel VT-d'
		arches:   ['x86_64']
		cmdline:  'vinix.iommu=1'
		qemu:     ['-device', 'intel-iommu', '-nic', 'user,model=e1000,tftp={state}/tftp', '-drive',
			'if=ide,format=raw,file={state}/disk.raw']
		disks:    [iommu_disk]
		files:    [tftp_probe]
		required: ['HWTEST START iommu-intel', 'HWTEST PASS iommu-intel']
		ending:   .poweroff
	},
	Scenario{
		name:     'iommu-amd'
		about:    'network card and disk controller isolated behind AMD-Vi'
		arches:   ['x86_64']
		cmdline:  'vinix.iommu=1'
		// QEMU's AMD unit translates nothing unless it is told to.
		qemu:     ['-device', 'amd-iommu,dma-remap=on', '-nic', 'user,model=e1000,tftp={state}/tftp',
			'-drive', 'if=ide,format=raw,file={state}/disk.raw']
		disks:    [iommu_disk]
		files:    [tftp_probe]
		required: ['HWTEST START iommu-amd', 'HWTEST PASS iommu-amd']
		ending:   .poweroff
	},
	Scenario{
		name:     'iommu-off'
		about:    'an IOMMU the command line did not ask for is left off'
		arches:   ['x86_64']
		qemu:     ['-device', 'intel-iommu', '-nic', 'user,model=e1000,tftp={state}/tftp', '-drive',
			'if=ide,format=raw,file={state}/disk.raw']
		disks:    [iommu_disk]
		files:    [tftp_probe]
		required: ['HWTEST START iommu-off', 'HWTEST PASS iommu-off']
		ending:   .poweroff
	},
	Scenario{
		name:     'iommu-intel-selftest'
		about:    'the kernel makes a card reach past its domain behind Intel VT-d'
		arches:   ['x86_64']
		define:   'vtd_selftest'
		cmdline:  'vinix.iommu=1'
		qemu:     ['-device', 'intel-iommu', '-nic', 'user,model=e1000']
		required: ['HWTEST START iommu-intel-selftest', 'HWTEST PASS iommu-intel-selftest']
		ending:   .poweroff
	},
	Scenario{
		name:     'iommu-amd-selftest'
		about:    'the kernel makes a card reach past its domain behind AMD-Vi'
		arches:   ['x86_64']
		define:   'amdvi_selftest'
		cmdline:  'vinix.iommu=1'
		qemu:     ['-device', 'amd-iommu,dma-remap=on', '-nic', 'user,model=e1000']
		required: ['HWTEST START iommu-amd-selftest', 'HWTEST PASS iommu-amd-selftest']
		ending:   .poweroff
	},
	Scenario{
		name:     'cpu-power'
		about:    'idle states counted and switchable, wake-ups kept, no frequency control claimed'
		arches:   ['aarch64', 'x86_64']
		required: ['HWTEST START cpu-power', 'HWTEST PASS cpu-power']
		ending:   .poweroff
	},
	Scenario{
		name:     'cpu-power-simulated'
		about:    'governors and profiles reach every CPU through a made-up frequency driver'
		arches:   ['aarch64', 'x86_64']
		cmdline:  'vinix.cpufreq=simulate'
		required: ['HWTEST START cpu-power-simulated', 'HWTEST PASS cpu-power-simulated']
		ending:   .poweroff
	},
	Scenario{
		name:     'thermal'
		about:    'no sensors invented; a missing register fails cleanly instead of faulting'
		arches:   ['aarch64', 'x86_64']
		required: ['HWTEST START thermal', 'HWTEST PASS thermal']
		ending:   .poweroff
	},
	Scenario{
		name:     'thermal-selftest'
		about:    'the limit follows a made-up temperature; critical turns the machine off'
		arches:   ['aarch64', 'x86_64']
		define:   'thermal_selftest'
		required: ['HWTEST START thermal-selftest', 'HWTEST PASS thermal-selftest',
			'HWTEST STEP going critical']
		ending:   .poweroff
	},
	Scenario{
		name:     'firmware'
		about:    'the firmware loader: reads, updates/, refused names, no retained memory'
		arches:   ['aarch64', 'x86_64']
		required: ['HWTEST START firmware', 'HWTEST PASS firmware']
		ending:   .poweroff
	},
	Scenario{
		name:     'acpi-power'
		about:    'ACPI battery, charger and lid: readings, time left, lid sleep, low and critical'
		arches:   ['x86_64']
		tables:   ['power-bench']
		qemu:     ['-acpitable', 'file={state}/power-bench.aml']
		required: ['HWTEST START acpi-power', 'HWTEST PASS acpi-power']
		ending:   .poweroff
	},
	Scenario{
		name:         'restart'
		about:        'reboot(2) resets the machine, devices stopped first'
		arches:       ['aarch64', 'x86_64']
		qemu_aarch64: ['-device', 'e1000,netdev=hwn0', '-netdev', 'user,id=hwn0']
		qemu_x86_64:  ['-nic', 'user,model=e1000']
		required:     ['HWTEST START restart', 'HWTEST PASS restart']
		ending:       .restart
	},
	Scenario{
		name:         'suspend'
		about:        'suspend to idle: rehearsal, alarm, key and power button wakeups'
		arches:       ['aarch64', 'x86_64']
		qemu_aarch64: ['-device', 'e1000,netdev=hwn0', '-netdev', 'user,id=hwn0']
		qemu_x86_64:  ['-nic', 'user,model=e1000']
		required:     ['HWTEST START suspend', 'HWTEST PASS suspend']
		// A modifier, so that nothing is echoed into the guest's own lines.
		actions:      [
			Action{
				after:    'HWTEST STEP asleep for a key'
				delay_ms: 1500
				qmp:      '{"execute":"send-key","arguments":{"keys":[{"type":"qcode","data":"shift"}]}}'
			},
			Action{
				after:    'HWTEST STEP asleep for the power button'
				delay_ms: 1500
				qmp:      '{"execute":"system_powerdown"}'
			},
			Action{
				after:    'HWTEST STEP asleep, keys ignored'
				delay_ms: 1000
				qmp:      '{"execute":"send-key","arguments":{"keys":[{"type":"qcode","data":"shift"}]}}'
			},
		]
		ending:       .poweroff
	},
]

// The scenarios one invocation deals with: those it boots, and those it names
// in the summary as left out.
pub struct Selection {
pub:
	run     []Scenario
	skipped []Scenario
}

pub fn find_scenario(all []Scenario, name string) ?Scenario {
	for scenario in all {
		if scenario.name == name {
			return scenario
		}
	}
	return none
}

// With no names, everything that applies to the architecture runs except what
// is pending. A name is a request: it runs even when pending, and it is an
// error rather than a silent skip when it cannot run on this architecture.
pub fn select_scenarios(all []Scenario, arch string, names []string) !Selection {
	if arch !in architectures {
		return error('unknown architecture ${arch} (expected ${architectures.join(' or ')})')
	}
	mut chosen := []Scenario{}
	mut skipped := []Scenario{}
	if names.len == 0 {
		for scenario in all {
			if arch !in scenario.arches {
				continue
			}
			if scenario.left_out() != '' {
				skipped << scenario
			} else {
				chosen << scenario
			}
		}
		return Selection{
			run:     chosen
			skipped: skipped
		}
	}
	for name in names {
		scenario := find_scenario(all, name) or {
			return error('unknown scenario ${name} (known: ${all.map(it.name).join(', ')})')
		}
		if arch !in scenario.arches {
			return error('scenario ${name} does not run on ${arch} (only on ${scenario.arches.join(', ')})')
		}
		if !chosen.any(it.name == name) {
			chosen << scenario
		}
	}
	return Selection{
		run: chosen
	}
}

// The extra QEMU arguments of a scenario on one architecture, before
// substitution.
pub fn (s &Scenario) qemu_arguments(arch string) []string {
	mut extra := s.qemu.clone()
	if arch == 'aarch64' {
		extra << s.qemu_aarch64
	} else {
		extra << s.qemu_x86_64
	}
	return extra
}

pub fn (s &Scenario) forbidden_markers() []string {
	mut markers := always_forbidden.clone()
	markers << s.forbidden
	return markers
}

// What a table must satisfy for the controller to run it. Checked before
// anything is booted, so a mistake in a new record is reported as one.
pub fn validate_scenarios(all []Scenario) ! {
	mut names := map[string]bool{}
	for scenario in all {
		if scenario.name == '' {
			return error('a scenario has no name')
		}
		if scenario.name in names {
			return error('scenario ${scenario.name} is listed twice')
		}
		names[scenario.name] = true
		for letter in scenario.name {
			if !(letter.is_letter() || letter.is_digit() || letter == `-`) {
				return error('scenario ${scenario.name}: a name is letters, digits and dashes')
			}
		}
		if scenario.arches.len == 0 {
			return error('scenario ${scenario.name} runs on no architecture')
		}
		for arch in scenario.arches {
			if arch !in architectures {
				return error('scenario ${scenario.name}: unknown architecture ${arch}')
			}
		}
		if 'HWTEST START ${scenario.name}' !in scenario.required {
			return error('scenario ${scenario.name} must require its HWTEST START line')
		}
		for marker in scenario.required {
			for forbidden in scenario.forbidden_markers() {
				if marker.contains(forbidden) {
					return error('scenario ${scenario.name} requires "${marker}", which contains the forbidden "${forbidden}"')
				}
			}
		}
		for action in scenario.actions {
			if action.after == '' || action.qmp == '' {
				return error('scenario ${scenario.name}: an action needs a marker and a command')
			}
			qmp_frame(action.qmp) or {
				return error('scenario ${scenario.name}: ${err.msg()}')
			}
		}
		for pattern in scenario.patterns {
			if !scenario.disks.any(it.name == pattern.disk) {
				return error('scenario ${scenario.name}: pattern on ${pattern.disk}, which is not one of its disks')
			}
		}
	}
}

// Replaces `{state}` in a QEMU argument or a QMP command. Anything else in
// braces that looks like a placeholder is a mistake in the scenario table,
// and is reported instead of being handed to QEMU as a file name.
pub fn substitute(text string, state string) !string {
	replaced := text.replace('{state}', state)
	mut i := 0
	for i < replaced.len {
		if replaced[i] != `{` {
			i++
			continue
		}
		mut end := i + 1
		for end < replaced.len && (replaced[end].is_letter() || replaced[end] == `_`) {
			end++
		}
		if end > i + 1 && end < replaced.len && replaced[end] == `}` {
			return error('unknown placeholder ${replaced[i..end + 1]} in "${text}"')
		}
		i++
	}
	return replaced
}

pub fn substitute_all(arguments []string, state string) ![]string {
	mut out := []string{cap: arguments.len}
	for argument in arguments {
		out << substitute(argument, state)!
	}
	return out
}

// A state directory ends up inside QEMU options, where a comma separates
// fields, and inside QMP JSON. Rather than quote it three ways, refuse the
// few characters that would need it.
pub fn check_state_path(path string) ! {
	for c in path {
		if c in [`,`, `"`, `\\`, `{`, `}`] || c < 0x20 {
			return error('the state directory path may not contain , " \\ { } or control characters: ${path}')
		}
	}
}

// Why a default run leaves the scenario out, or '' when it does not.
pub fn (s Scenario) left_out() string {
	if s.pending != '' {
		return 'pending: ${s.pending}'
	}
	if s.define != '' {
		return 'needs a kernel built with -d ${s.define}'
	}
	return ''
}
