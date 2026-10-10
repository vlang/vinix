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
	// Patterns the host writes before the boot, for a guest to read: data on
	// the disk that the guest's kernel cannot have in a cache.
	prefill []DiskPattern
	// The machine must leave every byte of it as the controller made it.
	// Checked once the machine has ended, however many times it booted.
	untouched bool
	// Its file is removed once the scenario has passed even where the state
	// directory is being kept: what it holds is hundreds of megabytes of a
	// machine's memory, of use only for looking into a failure.
	bulky bool
}

// Bytes the controller overwrites in a disk's file between two boots, the
// machine being off: `length` bytes at `offset`, each set to `fill`.
pub struct DiskDamage {
pub:
	disk   string
	offset u64
	length int
	fill   u8
}

// Bytes a disk's file must hold at `offset` once the machine has ended:
// `text`, or `zeros` bytes of zero.
pub struct DiskBytes {
pub:
	disk   string
	offset u64
	text   string
	zeros  int
}

// One more boot of the same machine. A scenario with any is run boot after
// boot on one state directory: the same boot image, the same disks with
// whatever the boot before left on them. Every boot but the last must end
// with the guest switching the machine off, which QEMU reports; the last
// ends the way the scenario says. The x86-64 machine has no firmware
// variables to carry over: QEMU's firmware is given none to keep.
pub struct Reboot {
pub:
	// Extra QEMU arguments for this boot alone, after the scenario's own: a
	// second -m replaces the first.
	qemu []string
	// What the controller does to the disks before it.
	damage []DiskDamage
	// With own_cmdline, this boot alone has `cmdline` as its extra kernel
	// command line instead of the scenario's, and the boot medium is made
	// again for it: the same kernel and the same guest, started another way.
	own_cmdline bool
	cmdline     string
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
	// With an event, the command is held back until QEMU has reported that
	// event `event_count` times since it started, and `event_delay_ms` more
	// have passed: a machine can only be woken once QEMU says it is
	// suspended, however long the guest took to get there.
	event          string
	event_count    int
	event_delay_ms int
	// What QEMU's answer to the command must contain, and what it must not:
	// how the host reads something out of the machine rather than doing
	// something to it. Compared with the answer as it was received.
	answer_has   string
	answer_lacks string
}

// A file QEMU writes in the state directory while the machine runs, and what
// it must hold, to the byte, once the machine has ended: what firmware wrote
// to a port that QEMU records, say.
pub struct Writing {
pub:
	file string
	text string
}

// What is wrong with QEMU's `answer` to `action`, or nothing.
pub fn answer_fault(action Action, answer string) string {
	if action.answer_has != '' && !answer.contains(action.answer_has) {
		return 'after "${action.after}", QEMU\'s answer to ${action.qmp} does not hold "${action.answer_has}"'
	}
	if action.answer_lacks != '' && answer.contains(action.answer_lacks) {
		return 'after "${action.after}", QEMU\'s answer to ${action.qmp} holds "${action.answer_lacks}"'
	}
	return ''
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
	// A way the kernel must have been built that is not a -d flag, as the
	// make argument that does it: `PROD=false` for a driver only a debug
	// kernel starts. Such a scenario, too, runs only when it is named.
	build   string
	cmdline string // extra kernel command line
	// How many seconds the machine may run, when that is more than a run
	// allows every scenario.
	timeout int
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
	// QMP events QEMU must have sent by the time the machine ends; one named
	// twice must have arrived twice. This is how the host knows that the
	// machine, and not only the guest's own account of it, changed.
	events       []string
	ending       Ending
	patterns     []DiskPattern
	// Pictures of the screen that actions take (`screendump` into {state}),
	// and whether each must be dark or show something; see screen.v.
	screens      []Screen
	// Recordings of what the machine played (`-audiodev wav` into {state}),
	// and the heights each must hold; see sound.v.
	sounds       []Sound
	// Files the machine wrote through QEMU (into {state}), and what each must
	// hold.
	writings     []Writing
	// The boots after the first; see Reboot. The markers, the actions and
	// the events are those of all the boots together, in order.
	reboots      []Reboot
	// What the disks must hold at the end, besides their patterns.
	disk_bytes   []DiskBytes
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

// A machine with an empty PCI Express port, no network card, and the network
// a card put into the port will be on.
const hotplug_machine = ['-nic', 'none', '-device', 'pcie-root-port,id=hwport0,chassis=1,bus=pcie.0',
	'-netdev', 'user,id=hwhot0,tftp={state}/tftp']

// The same machine with an Intel IOMMU.
const hotplug_machine_isolated = ['-device', 'intel-iommu', '-nic', 'none', '-device',
	'pcie-root-port,id=hwport0,chassis=1,bus=pcie.0', '-netdev', 'user,id=hwhot0,tftp={state}/tftp']

// pci-d3: an Intel 82574L, the one card in these machines that QEMU gives a
// power management capability and whose power state QEMU acts on: put into
// D3hot it is taken off the bus (its registers are no longer in the machine's
// memory map). What the host asks QEMU for is the memory map as it is laid
// out at that moment, in which the card's registers are named when they can
// be reached and are not there when they cannot.
//
// QEMU's card forgets nothing on the way back to D0, which most real ones
// do. pci-d3-selftest is the same machine with a kernel that clears the
// card's address and command registers while it is down, so that writing
// them back is what makes the card work again.
const d3_card = ['-netdev', 'user,id=hwn0,tftp={state}/tftp', '-device', 'e1000e,netdev=hwn0,id=hwcard0']
const d3_look = '{"execute":"human-monitor-command","arguments":{"command-line":"info mtree -f"}}'
const d3_card_memory = 'e1000e-mmio'
// How long after the guest says it is going down the host looks: the guest
// stays down for twice this (guest/pci_d3.v), so the look lands in the
// middle of the sleep with three seconds to spare on either side.
const d3_look_after_ms = 3000

const d3_actions = [
	Action{
		after:      'HWTEST STEP the card is awake'
		delay_ms:   100
		qmp:        d3_look
		answer_has: d3_card_memory
	},
	Action{
		after:        'HWTEST STEP a rehearsal, the card asleep'
		delay_ms:     d3_look_after_ms
		qmp:          d3_look
		answer_lacks: d3_card_memory
	},
	Action{
		after:      'HWTEST STEP awake after the rehearsal'
		delay_ms:   100
		qmp:        d3_look
		answer_has: d3_card_memory
	},
	Action{
		after:        'HWTEST STEP a suspend to idle, the card asleep'
		delay_ms:     d3_look_after_ms
		qmp:          d3_look
		answer_lacks: d3_card_memory
	},
	Action{
		after:      'HWTEST STEP awake after the suspend to idle'
		delay_ms:   100
		qmp:        d3_look
		answer_has: d3_card_memory
	},
]

// suspend-deep-wake: the byte of the event enable register that holds events
// 0x10 to 0x17, as QEMU's PC has it (the block is at 0x620, eight bytes of
// status and then eight of enable), read through the monitor. The lid's
// event is its first bit and the sleep button's its second.
const wake_look = '{"execute":"human-monitor-command","arguments":{"command-line":"i/1xb 0x62a"}}'
const wake_both = '= 0x03'
const wake_button_only = '= 0x02'
const wake_none = '= 0x00'

const hotplug_add = '{"execute":"device_add","arguments":{"driver":"e1000","bus":"hwport0","id":"hwcard0","netdev":"hwhot0"}}'
const hotplug_remove = '{"execute":"device_del","arguments":{"id":"hwcard0"}}'

// The card goes in when the guest waits for it, and is asked back when the
// guest says it is in use; then both again.
const hotplug_actions = [
	Action{
		after: 'HWTEST STEP waiting for the card'
		qmp:   hotplug_add
	},
	Action{
		after: 'HWTEST STEP card in use'
		qmp:   hotplug_remove
	},
	Action{
		after: 'HWTEST STEP waiting for the card again'
		qmp:   hotplug_add
	},
	Action{
		after: 'HWTEST STEP card in use again'
		qmp:   hotplug_remove
	},
]

// The command that has QEMU write a picture of the screen, `<name>.ppm`, into
// the state directory.
fn screen_picture(name string) string {
	return '{"execute":"screendump","arguments":{"filename":"{state}/${name}.ppm"}}'
}

// The machine of the embedded controller self-test: the tables that describe
// the controller, and room for three more processors. Their only part here
// is that adding one makes QEMU's chipset raise general purpose event 2 --
// the event the tables give the controller.
fn ec_selftest_qemu(table string, early bool) []string {
	mut extra := ['-acpitable', 'file={state}/' + table + '.aml']
	if early {
		extra << ['-acpitable', 'file={state}/ec-ecdt.aml']
	}
	extra << ['-smp', '2,maxcpus=5']
	return extra
}

fn ec_raise(core int) string {
	return '{"execute":"device_add","arguments":{"driver":"max-x86_64-cpu","id":"hwcpu${core}","socket-id":0,"core-id":${core},"thread-id":0}}'
}

// Each time the guest has put an event into the simulated controller and
// says so, the host has the chipset raise the controller's event.
const ec_selftest_actions = [
	Action{
		after: 'HWTEST STEP controller event 1'
		qmp:   ec_raise(2)
	},
	Action{
		after: 'HWTEST STEP controller event 2'
		qmp:   ec_raise(3)
	},
	Action{
		after: 'HWTEST STEP controller event 3'
		qmp:   ec_raise(4)
	},
]

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
		name:     'acpi-thermal'
		about:    'an ACPI thermal zone and fans: speeds follow a scripted heat, critical powers off'
		arches:   ['x86_64']
		tables:   ['thermal-bench']
		qemu:     ['-acpitable', 'file={state}/thermal-bench.aml']
		required: ['HWTEST START acpi-thermal', 'HWTEST PASS acpi-thermal', 'HWTEST STEP going critical']
		ending:   .poweroff
	},
	Scenario{
		name:     'acpi-ec-absent'
		about:    'an embedded controller nothing answers for is given up on, and the machine goes on'
		arches:   ['x86_64']
		tables:   ['ec-absent']
		qemu:     ['-acpitable', 'file={state}/ec-absent.aml']
		required: ['HWTEST START acpi-ec-absent', 'HWTEST PASS acpi-ec-absent']
		ending:   .poweroff
	},
	Scenario{
		name:     'acpi-ec-off'
		about:    'vinix.ec=off leaves an embedded controller alone'
		arches:   ['x86_64']
		cmdline:  'vinix.ec=off'
		tables:   ['ec-absent']
		qemu:     ['-acpitable', 'file={state}/ec-absent.aml']
		required: ['HWTEST START acpi-ec-off', 'HWTEST PASS acpi-ec-off']
		ending:   .poweroff
	},
	Scenario{
		name:     'acpi-ec-selftest'
		about:    'a simulated embedded controller: fields, events, sleep, and giving up'
		arches:   ['x86_64']
		define:   'acpiec_selftest'
		timeout:  240
		tables:   ['ec-bench', 'ec-ecdt']
		qemu:     ec_selftest_qemu('ec-bench', true)
		required: ['HWTEST START acpi-ec-selftest', 'HWTEST PASS acpi-ec-selftest']
		actions:  ec_selftest_actions
		ending:   .poweroff
	},
	Scenario{
		name:     'acpi-ec-selftest-dsdt'
		about:    'the same with no ECDT, and the controller cleared of events at start and on resume'
		arches:   ['x86_64']
		define:   'acpiec_selftest'
		cmdline:  'vinix.ec=clear,dsdt-gpe'
		timeout:  240
		tables:   ['ec-bench-dsdt']
		qemu:     ec_selftest_qemu('ec-bench-dsdt', false)
		required: ['HWTEST START acpi-ec-selftest-dsdt', 'HWTEST PASS acpi-ec-selftest-dsdt']
		actions:  ec_selftest_actions
		ending:   .poweroff
	},
	Scenario{
		name:     'apple-smc-selftest'
		about:    'a simulated Apple SMC: battery, charger, sensors, a fan, the charge limit, a sleep, and giving up'
		arches:   ['aarch64']
		define:   'applesmc_selftest'
		timeout:  240
		required: ['HWTEST START apple-smc-selftest', 'HWTEST PASS apple-smc-selftest',
			'apple-smc: self-test kernel: the SMC is simulated', 'apple-smc: battery service stopped']
		ending:   .poweroff
	},
	Scenario{
		name:     'apple-smc-selftest-bare'
		about:    'the same SMC with no fan and no charge limit: neither has files'
		arches:   ['aarch64']
		define:   'applesmc_selftest'
		cmdline:  'vinix.apple_smc_sim=bare'
		required: ['HWTEST START apple-smc-selftest-bare', 'HWTEST PASS apple-smc-selftest-bare']
		ending:   .poweroff
	},
	Scenario{
		name:     'apple-smc-selftest-options'
		about:    'vinix.apple_smc=nosensors,nolimit: the battery and charger alone'
		arches:   ['aarch64']
		define:   'applesmc_selftest'
		cmdline:  'vinix.apple_smc=nosensors,nolimit'
		required: ['HWTEST START apple-smc-selftest-options', 'HWTEST PASS apple-smc-selftest-options']
		ending:   .poweroff
	},
	Scenario{
		name:     'apple-smc-selftest-legacy'
		about:    'vinix.apple_smc=legacy: /dev/battery and /dev/battery-power and nothing else'
		arches:   ['aarch64']
		define:   'applesmc_selftest'
		cmdline:  'vinix.apple_smc=legacy'
		required: ['HWTEST START apple-smc-selftest-legacy', 'HWTEST PASS apple-smc-selftest-legacy',
			'left out by vinix.apple_smc=legacy']
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
	Scenario{
		name:     'pci-d3'
		about:    'a network card put into D3 for every kind of sleep and brought back; the host watches it leave the bus'
		arches:   ['aarch64', 'x86_64']
		qemu:     d3_card
		files:    [tftp_probe]
		required: ['HWTEST START pci-d3', 'HWTEST PASS pci-d3']
		actions:  d3_actions
		ending:   .poweroff
	},
	Scenario{
		name:     'pci-d3-selftest'
		about:    'the same, with a card made to forget its configuration in D3 as real ones do; a kernel built with -d pci_d3_selftest'
		arches:   ['aarch64', 'x86_64']
		define:   'pci_d3_selftest'
		qemu:     d3_card
		files:    [tftp_probe]
		required: ['HWTEST START pci-d3-selftest', 'HWTEST PASS pci-d3-selftest']
		actions:  d3_actions
		ending:   .poweroff
	},
	Scenario{
		name:     'pci-d3-off'
		about:    'vinix.pci_d3=off: the same card stays in D0, and on the bus, through a sleep'
		arches:   ['aarch64', 'x86_64']
		cmdline:  'vinix.pci_d3=off'
		qemu:     d3_card
		files:    [tftp_probe]
		required: ['HWTEST START pci-d3-off', 'HWTEST PASS pci-d3-off']
		actions:  [
			Action{
				after:      'HWTEST STEP a rehearsal, the card left awake'
				delay_ms:   d3_look_after_ms
				qmp:        d3_look
				answer_has: d3_card_memory
			},
		]
		ending:   .poweroff
	},
	Scenario{
		name:     'screen-sleep'
		about:    'the screen is dark while the machine sleeps, and as it was afterwards'
		arches:   ['aarch64', 'x86_64']
		required: ['HWTEST START screen-sleep', 'HWTEST PASS screen-sleep']
		actions:  [
			Action{
				after: 'HWTEST STEP screen before the sleep'
				qmp:   screen_picture('before')
			},
			Action{
				after:    'HWTEST STEP asleep for the screen'
				delay_ms: 1500
				qmp:      screen_picture('asleep')
			},
			Action{
				after: 'HWTEST STEP screen after the sleep'
				qmp:   screen_picture('after')
			},
			Action{
				after:    'HWTEST STEP rehearsing for the screen'
				delay_ms: 1500
				qmp:      screen_picture('rehearsing')
			},
			Action{
				after: 'HWTEST STEP screen after the rehearsal'
				qmp:   screen_picture('rehearsed')
			},
		]
		screens:  [
			Screen{
				file: 'before.ppm'
			},
			Screen{
				file: 'asleep.ppm'
				dark: true
			},
			Screen{
				file: 'after.ppm'
			},
			Screen{
				file: 'rehearsing.ppm'
				dark: true
			},
			Screen{
				file: 'rehearsed.ppm'
			},
		]
		ending:   .poweroff
	},
	Scenario{
		name:        'pci-hotplug'
		about:       'a network card put into a port the kernel watches, and taken out, twice'
		arches:      ['aarch64', 'x86_64']
		qemu:        hotplug_machine
		// QEMU's PC keeps its ports to itself unless told otherwise; see
		// pci-hotplug-acpi for that.
		qemu_x86_64: ['-global', 'ICH9-LPC.acpi-pci-hotplug-with-bridge-support=off']
		files:       [tftp_probe]
		required:    ['HWTEST START pci-hotplug', 'HWTEST PASS pci-hotplug']
		actions:     hotplug_actions
		events:      ['DEVICE_DELETED', 'DEVICE_DELETED']
		ending:      .poweroff
	},
	Scenario{
		name:     'pci-hotplug-acpi'
		about:    'the same card announced and asked back by firmware through ACPI'
		arches:   ['x86_64']
		qemu:     hotplug_machine
		files:    [tftp_probe]
		required: ['HWTEST START pci-hotplug-acpi', 'HWTEST PASS pci-hotplug-acpi']
		actions:  hotplug_actions
		events:   ['DEVICE_DELETED', 'DEVICE_DELETED']
		ending:   .poweroff
	},
	Scenario{
		name:     'pci-hotplug-iommu'
		about:    'a card that arrives behind an IOMMU that is on gets a domain of its own'
		arches:   ['x86_64']
		cmdline:  'vinix.iommu=1'
		qemu:     hotplug_machine_isolated
		files:    [tftp_probe]
		required: ['HWTEST START pci-hotplug-iommu', 'HWTEST PASS pci-hotplug-iommu']
		actions:  hotplug_actions
		events:   ['DEVICE_DELETED', 'DEVICE_DELETED']
		ending:   .poweroff
	},
	Scenario{
		name:     'suspend-deep'
		about:    'suspend to RAM (ACPI S3): three ways to wake, every CPU, memory, disk, network, clocks, screen'
		arches:   ['x86_64']
		qemu:     ['-smp', '4', '-nic', 'user,model=e1000,tftp={state}/tftp', '-drive',
			'if=ide,format=raw,file={state}/disk.raw']
		disks:    [deep_disk]
		files:    [tftp_probe]
		required: ['HWTEST START suspend-deep', 'HWTEST PASS suspend-deep']
		actions:  deep_actions
		ending:   .poweroff
		patterns: deep_patterns
		events:   deep_events
		screens:  deep_screens
		timeout:  240
	},
	Scenario{
		name:     'suspend-deep-iommu'
		about:    'the same behind Intel VT-d: the unit is brought back before any device may use the bus'
		arches:   ['x86_64']
		cmdline:  'vinix.iommu=1'
		qemu:     ['-smp', '4', '-device', 'intel-iommu', '-nic', 'user,model=e1000,tftp={state}/tftp',
			'-drive', 'if=ide,format=raw,file={state}/disk.raw']
		disks:    [deep_disk]
		files:    [tftp_probe]
		required: ['HWTEST START suspend-deep-iommu', 'HWTEST PASS suspend-deep-iommu']
		actions:  deep_actions
		ending:   .poweroff
		patterns: deep_patterns
		events:   deep_events
		screens:  deep_screens
		timeout:  240
	},
	Scenario{
		name:     'suspend-deep-iommu-amd'
		about:    'the same behind AMD-Vi'
		arches:   ['x86_64']
		cmdline:  'vinix.iommu=1'
		qemu:     ['-smp', '4', '-device', 'amd-iommu,dma-remap=on', '-nic', 'user,model=e1000,tftp={state}/tftp',
			'-drive', 'if=ide,format=raw,file={state}/disk.raw']
		disks:    [deep_disk]
		files:    [tftp_probe]
		required: ['HWTEST START suspend-deep-iommu-amd', 'HWTEST PASS suspend-deep-iommu-amd']
		actions:  deep_actions
		ending:   .poweroff
		patterns: deep_patterns
		events:   deep_events
		screens:  deep_screens
		timeout:  240
	},
	Scenario{
		name:     'suspend-deep-xapic'
		about:    'the same on processors without x2APIC: the local APICs are driven through memory'
		arches:   ['x86_64']
		qemu:     ['-cpu', 'max,-x2apic', '-smp', '4', '-nic', 'user,model=e1000,tftp={state}/tftp',
			'-drive', 'if=ide,format=raw,file={state}/disk.raw']
		disks:    [deep_disk]
		files:    [tftp_probe]
		required: ['HWTEST START suspend-deep-xapic', 'HWTEST PASS suspend-deep-xapic']
		actions:  deep_actions
		ending:   .poweroff
		patterns: deep_patterns
		events:   deep_events
		screens:  deep_screens
		timeout:  240
	},
	Scenario{
		name:     'suspend-deep-bridge'
		about:    'the same with the card behind a PCI Express port whose hot-plug slot the kernel watches'
		arches:   ['x86_64']
		qemu:     ['-smp', '4', '-global', 'ICH9-LPC.acpi-pci-hotplug-with-bridge-support=off', '-nic',
			'none', '-device', 'pcie-root-port,id=hwport0,chassis=1,bus=pcie.0', '-netdev',
			'user,id=hwhot0,tftp={state}/tftp', '-device', 'e1000,bus=hwport0,netdev=hwhot0', '-drive',
			'if=ide,format=raw,file={state}/disk.raw']
		disks:    [deep_disk]
		files:    [tftp_probe]
		required: ['HWTEST START suspend-deep-bridge', 'HWTEST PASS suspend-deep-bridge']
		actions:  deep_actions
		ending:   .poweroff
		patterns: deep_patterns
		events:   deep_events
		screens:  deep_screens
		timeout:  240
	},
	Scenario{
		name:        'suspend-deep-arrival'
		about:       'a card put into a watched slot while the machine is suspended to RAM is found when it wakes'
		arches:      ['x86_64']
		qemu:        hotplug_machine
		qemu_x86_64: ['-smp', '2', '-global', 'ICH9-LPC.acpi-pci-hotplug-with-bridge-support=off']
		files:       [tftp_probe]
		required:    ['HWTEST START suspend-deep-arrival', 'HWTEST PASS suspend-deep-arrival']
		actions:     deep_arrival_actions
		ending:      .poweroff
		events:      ['SUSPEND', 'WAKEUP', 'SUSPEND', 'WAKEUP', 'DEVICE_DELETED']
		screens:     [Screen{
			file: 'woken.ppm'
		}]
		timeout:     180
	},
	Scenario{
		name:     'suspend-deep-departure'
		about:    'a card taken while the machine is suspended to RAM is removed when it wakes, and one put in is found'
		arches:   ['x86_64']
		qemu:     ['-smp', '2', '-nic', 'none', '-device', 'pcie-root-port,id=hwport0,chassis=1,bus=pcie.0',
			'-netdev', 'user,id=hwhot0,tftp={state}/tftp', '-device', 'e1000,bus=hwport0,netdev=hwhot0,id=hwcard0']
		files:    [tftp_probe]
		required: ['HWTEST START suspend-deep-departure', 'HWTEST PASS suspend-deep-departure']
		actions:  deep_departure_actions
		ending:   .poweroff
		events:   ['SUSPEND', 'WAKEUP', 'SUSPEND', 'WAKEUP', 'SUSPEND', 'WAKEUP', 'DEVICE_DELETED']
		screens:  [Screen{
			file: 'woken.ppm'
		}]
		timeout:  180
	},
	Scenario{
		name:     'suspend-deep-ec'
		about:    'the embedded controller driver through a suspend to RAM: exchanges, and the chipset\'s event heard again'
		arches:   ['x86_64']
		define:   'acpiec_selftest'
		tables:   ['ec-bench', 'ec-ecdt']
		qemu:     ec_selftest_qemu('ec-bench', true)
		required: ['HWTEST START suspend-deep-ec', 'HWTEST PASS suspend-deep-ec']
		actions:  [
			Action{
				after: 'HWTEST STEP controller event before the sleep'
				qmp:   ec_raise(2)
			},
			Action{
				after: 'HWTEST STEP controller event after the sleep'
				qmp:   ec_raise(3)
			},
			Action{
				after: 'HWTEST STEP controller event after the second sleep'
				qmp:   ec_raise(4)
			},
		]
		events:   ['SUSPEND', 'WAKEUP', 'SUSPEND', 'WAKEUP']
		ending:   .poweroff
	},
	Scenario{
		name:     'suspend-deep-undrawable'
		about:    'a display the kernel cannot bring back: suspend to RAM is not offered'
		arches:   ['x86_64']
		qemu:     ['-vga', 'virtio']
		required: ['HWTEST START suspend-deep-undrawable', 'HWTEST PASS suspend-deep-undrawable']
		ending:   .poweroff
	},
	Scenario{
		name:     'suspend-deep-forced'
		about:    'the same display with vinix.deep_sleep=force: offered, and the machine comes back'
		arches:   ['x86_64']
		cmdline:  'vinix.deep_sleep=force'
		qemu:     ['-vga', 'virtio']
		required: ['HWTEST START suspend-deep-forced', 'HWTEST PASS suspend-deep-forced']
		ending:   .poweroff
		events:   deep_once
	},
	Scenario{
		name:     'suspend-deep-headless'
		about:    'no display at all: suspend to RAM is offered, and the machine comes back'
		arches:   ['x86_64']
		qemu:     ['-vga', 'none']
		required: ['HWTEST START suspend-deep-headless', 'HWTEST PASS suspend-deep-headless']
		ending:   .poweroff
		events:   deep_once
	},
	Scenario{
		name:     'suspend-deep-wake'
		about:    'a lid and a sleep button armed to end a suspend to RAM: their events left on, firmware told'
		arches:   ['x86_64']
		tables:   ['wake-bench']
		qemu:     ['-acpitable', 'file={state}/wake-bench.aml', '-chardev', 'file,id=hwsaid,path={state}/firmware-said.txt',
			'-device', 'isa-debugcon,iobase=0x505,chardev=hwsaid']
		required: ['HWTEST START suspend-deep-wake', 'HWTEST PASS suspend-deep-wake']
		actions:  [
			Action{
				after:        'HWTEST STEP awake, nothing armed'
				delay_ms:     100
				qmp:          wake_look
				answer_lacks: wake_both
			},
			Action{
				after:          'HWTEST STEP deep sleep, lid and sleep button armed'
				event:          'SUSPEND'
				event_count:    1
				event_delay_ms: 500
				qmp:            wake_look
				answer_has:     wake_both
			},
			Action{
				after:          'HWTEST STEP deep sleep, the lid not allowed'
				event:          'SUSPEND'
				event_count:    2
				event_delay_ms: 500
				qmp:            wake_look
				answer_has:     wake_button_only
			},
		]
		ending:   .poweroff
		events:   ['SUSPEND', 'WAKEUP', 'SUSPEND', 'WAKEUP']
		// The lid told to wake the machine, the sleep button told with the
		// sleep state and the device state; both told not to; then the same
		// for the button alone. Never the power button's `!`.
		writings: [
			Writing{
				file: 'firmware-said.txt'
				text: 'LS33lsS33s'
			},
		]
	},
	Scenario{
		name:     'suspend-deep-wake-off'
		about:    'vinix.acpi_wake=off: the same lid and button are left alone, and no event is left on for the sleep'
		arches:   ['x86_64']
		cmdline:  'vinix.acpi_wake=off'
		tables:   ['wake-bench']
		qemu:     ['-acpitable', 'file={state}/wake-bench.aml', '-chardev', 'file,id=hwsaid,path={state}/firmware-said.txt',
			'-device', 'isa-debugcon,iobase=0x505,chardev=hwsaid']
		required: ['HWTEST START suspend-deep-wake-off', 'HWTEST PASS suspend-deep-wake-off']
		actions:  [
			Action{
				after:          'HWTEST STEP deep sleep, nothing armed'
				event:          'SUSPEND'
				event_count:    1
				event_delay_ms: 500
				qmp:            wake_look
				answer_has:     wake_none
			},
		]
		ending:   .poweroff
		events:   deep_once
		writings: [
			Writing{
				file: 'firmware-said.txt'
				text: ''
			},
		]
	},
	Scenario{
		name:     'drivers-sleep'
		about:    'HD Audio and an IDE disk through a rehearsal, a suspend to idle and a suspend to RAM'
		arches:   ['x86_64']
		qemu:     ['-audiodev', 'wav,id=hwsnd,path={state}/sound.wav,out.frequency=48000', '-device',
			'intel-hda', '-device', 'hda-output,audiodev=hwsnd,mixer=off', '-device', 'piix3-ide,id=hwide',
			'-drive', 'if=none,id=hwidedisk,format=raw,file={state}/ide.raw', '-device',
			'ide-hd,drive=hwidedisk,bus=hwide.0']
		disks:    [
			Disk{
				name:     'ide.raw'
				size_mib: 16
				header:   'vinix hardware test disk: not blank'
			},
		]
		required: ['HWTEST START drivers-sleep', 'HWTEST PASS drivers-sleep']
		ending:   .poweroff
		events:   deep_once
		patterns: [
			DiskPattern{
				disk:   'ide.raw'
				offset: 1 << 20
				length: 65536
				seed:   0x21
			},
			DiskPattern{
				disk:   'ide.raw'
				offset: 2 << 20
				length: 65536
				seed:   0x42
			},
			DiskPattern{
				disk:   'ide.raw'
				offset: 3 << 20
				length: 65536
				seed:   0x63
			},
			DiskPattern{
				disk:   'ide.raw'
				offset: 4 << 20
				length: 65536
				seed:   0x7c
			},
		]
		// A second and a half of tone at each height is 72000 frames; a
		// third of that is asked for, which a card that played nothing
		// after a sleep does not come near.
		sounds:   [
			Sound{
				file:   'sound.wav'
				levels: [6000, 12000, 18000, 24000]
				frames: 24000
			},
		]
		timeout:  120
	},
	Scenario{
		name:     'nvme-sleep'
		about:    'an NVMe disk through a rehearsal, a suspend to idle and a suspend to RAM'
		arches:   ['x86_64']
		build:    'PROD=false'
		qemu:     ['-drive', 'if=none,id=hwnvme,format=raw,file={state}/nvme.raw', '-device',
			'nvme,drive=hwnvme,serial=hwtest0001']
		disks:    [
			Disk{
				name:     'nvme.raw'
				size_mib: 16
				header:   'vinix hardware test disk: not blank'
			},
		]
		required: ['HWTEST START nvme-sleep', 'HWTEST PASS nvme-sleep']
		ending:   .poweroff
		events:   deep_once
		patterns: [
			DiskPattern{
				disk:   'nvme.raw'
				offset: 1 << 20
				length: 65536
				seed:   0x21
			},
			DiskPattern{
				disk:   'nvme.raw'
				offset: 2 << 20
				length: 65536
				seed:   0x42
			},
			DiskPattern{
				disk:   'nvme.raw'
				offset: 3 << 20
				length: 65536
				seed:   0x63
			},
			DiskPattern{
				disk:   'nvme.raw'
				offset: 4 << 20
				length: 65536
				seed:   0x7c
			},
		]
		timeout:  120
	},
	Scenario{
		name:       'hibernate'
		about:      'suspend to disk, twice: the machine is switched off and the same process carries on in the next boot'
		arches:     ['x86_64']
		cmdline:    'vinix.hibernate=sd1'
		qemu:       hibernate_machine
		disks:      [hibernate_data_disk, hibernate_image_disk]
		files:      [tftp_probe]
		required:   ['HWTEST START hibernate', 'HWTEST PASS hibernate']
		actions:    hibernate_actions
		reboots:    [Reboot{}, Reboot{}]
		ending:     .poweroff
		patterns:   hibernate_patterns
		disk_bytes: hibernate_no_image
		screens:    [Screen{
			file: 'after.ppm'
		}]
		timeout:    300
	},
	Scenario{
		name:       'hibernate-xapic'
		about:      'the same on processors without x2APIC or 57-bit addresses: page tables four levels deep'
		arches:     ['x86_64']
		cmdline:    'vinix.hibernate=sd1'
		qemu:       ['-cpu', 'max,-x2apic,-la57', '-smp', '4', '-nic', 'user,model=e1000,tftp={state}/tftp',
			'-drive', 'if=ide,format=raw,file={state}/disk.raw', '-drive',
			'if=ide,format=raw,file={state}/image.raw']
		disks:      [hibernate_data_disk, hibernate_image_disk]
		files:      [tftp_probe]
		required:   ['HWTEST START hibernate-xapic', 'HWTEST PASS hibernate-xapic']
		actions:    hibernate_actions
		reboots:    [Reboot{}, Reboot{}]
		ending:     .poweroff
		patterns:   hibernate_patterns
		disk_bytes: hibernate_no_image
		screens:    [Screen{
			file: 'after.ppm'
		}]
		timeout:    300
	},
	Scenario{
		name:       'hibernate-iommu'
		about:      'the same behind Intel VT-d, which the kernel that loads the image has switched on too'
		arches:     ['x86_64']
		cmdline:    'vinix.iommu=1 vinix.hibernate=sd1'
		qemu:       hibernate_machine_isolated
		disks:      [hibernate_data_disk, hibernate_image_disk]
		files:      [tftp_probe]
		required:   ['HWTEST START hibernate-iommu', 'HWTEST PASS hibernate-iommu']
		actions:    hibernate_actions
		reboots:    [Reboot{}, Reboot{}]
		ending:     .poweroff
		patterns:   hibernate_patterns
		disk_bytes: hibernate_no_image
		screens:    [Screen{
			file: 'after.ppm'
		}]
		timeout:    300
	},
	Scenario{
		name:       'hibernate-iommu-amd'
		about:      'the same behind AMD-Vi'
		arches:     ['x86_64']
		cmdline:    'vinix.iommu=1 vinix.hibernate=sd1'
		qemu:       ['-smp', '4', '-device', 'amd-iommu,dma-remap=on', '-nic',
			'user,model=e1000,tftp={state}/tftp', '-drive', 'if=ide,format=raw,file={state}/disk.raw',
			'-drive', 'if=ide,format=raw,file={state}/image.raw']
		disks:      [hibernate_data_disk, hibernate_image_disk]
		files:      [tftp_probe]
		required:   ['HWTEST START hibernate-iommu-amd', 'HWTEST PASS hibernate-iommu-amd']
		actions:    hibernate_actions
		reboots:    [Reboot{}, Reboot{}]
		ending:     .poweroff
		patterns:   hibernate_patterns
		disk_bytes: hibernate_no_image
		screens:    [Screen{
			file: 'after.ppm'
		}]
		timeout:    300
	},
	Scenario{
		name:       'hibernate-cycles'
		about:      'five suspends to disk one after another, and what the last four leave allocated in the kernel'
		arches:     ['x86_64']
		cmdline:    'vinix.hibernate=sd1'
		qemu:       hibernate_machine
		disks:      [hibernate_data_disk, hibernate_image_disk]
		files:      [tftp_probe]
		required:   ['HWTEST START hibernate-cycles', 'HWTEST PASS hibernate-cycles']
		reboots:    [Reboot{}, Reboot{}, Reboot{}, Reboot{}, Reboot{}]
		ending:     .poweroff
		disk_bytes: hibernate_no_image
		timeout:    300
	},
	Scenario{
		name:       'hibernate-damaged-header'
		about:      'an image whose header was damaged while the machine was off is not gone back into'
		arches:     ['x86_64']
		cmdline:    'vinix.hibernate=sd1'
		qemu:       hibernate_machine
		disks:      [hibernate_data_disk, hibernate_image_disk]
		files:      [tftp_probe]
		required:   ['HWTEST START hibernate-damaged-header', 'HWTEST PASS hibernate-damaged-header']
		// Eight bytes of the header, past its signature: what it says no
		// longer matches its checksum.
		reboots:    [
			Reboot{
				damage: [
					DiskDamage{
						disk:   'image.raw'
						offset: 72
						length: 8
						fill:   0xa5
					},
				]
			},
		]
		ending:     .poweroff
		patterns:   hibernate_refusal_patterns
		disk_bytes: hibernate_no_image
		timeout:    180
	},
	Scenario{
		name:       'hibernate-damaged-pages'
		about:      'nor one with a page damaged, which is only found once all of it has been read'
		arches:     ['x86_64']
		cmdline:    'vinix.hibernate=sd1'
		qemu:       hibernate_machine
		disks:      [hibernate_data_disk, hibernate_image_disk]
		files:      [tftp_probe]
		required:   ['HWTEST START hibernate-damaged-pages', 'HWTEST PASS hibernate-damaged-pages']
		// Sixteen megabytes in, among the pages of any image of this machine.
		reboots:    [
			Reboot{
				damage: [
					DiskDamage{
						disk:   'image.raw'
						offset: (16 << 20) + 100
						length: 24
						fill:   0x5a
					},
				]
			},
		]
		ending:     .poweroff
		patterns:   hibernate_refusal_patterns
		disk_bytes: hibernate_no_image
		timeout:    180
	},
	Scenario{
		name:       'hibernate-memory'
		about:      'nor by a machine with another amount of memory than the image was taken on'
		arches:     ['x86_64']
		cmdline:    'vinix.hibernate=sd1'
		qemu:       hibernate_machine
		disks:      [hibernate_data_disk, hibernate_image_disk]
		files:      [tftp_probe]
		required:   ['HWTEST START hibernate-memory', 'HWTEST PASS hibernate-memory']
		reboots:    [
			Reboot{
				qemu: ['-m', '768']
			},
		]
		ending:     .poweroff
		patterns:   hibernate_refusal_patterns
		disk_bytes: hibernate_no_image
		timeout:    180
	},
	Scenario{
		name:       'hibernate-disks'
		about:      'nor by a machine with a disk more than the image was taken with'
		arches:     ['x86_64']
		cmdline:    'vinix.hibernate=sd1'
		qemu:       hibernate_machine
		disks:      [hibernate_data_disk, hibernate_image_disk,
			Disk{
				name:     'extra.raw'
				size_mib: 16
				header:   'vinix hardware test disk: not blank'
			}]
		files:      [tftp_probe]
		required:   ['HWTEST START hibernate-disks', 'HWTEST PASS hibernate-disks']
		// Last, so that the two the image knew keep their places and names.
		reboots:    [
			Reboot{
				qemu: ['-drive', 'if=ide,format=raw,file={state}/extra.raw']
			},
		]
		ending:     .poweroff
		patterns:   hibernate_refusal_patterns
		disk_bytes: hibernate_no_image
		timeout:    180
	},
	Scenario{
		name:       'hibernate-root'
		about:      'suspend to disk with the system on a disk: resumed, used again, and found whole by a third start'
		arches:     ['x86_64']
		cmdline:    'vinix.hibernate=sd1'
		qemu:       hibernate_root_machine
		disks:      [hibernate_data_disk, hibernate_image_disk, hibernate_system_disk]
		files:      [tftp_probe]
		required:   ['HWTEST START hibernate-root', 'HWTEST STEP read back from the disk',
			'HWTEST PASS hibernate-root']
		reboots:    [Reboot{}, Reboot{}]
		ending:     .poweroff
		disk_bytes: hibernate_no_image
		timeout:    420
	},
	Scenario{
		name:       'hibernate-waiting'
		about:      'a start without the option, between the suspend to disk and the resume, leaves the image and the system\'s disk alone'
		arches:     ['x86_64']
		cmdline:    'vinix.hibernate=sd1'
		qemu:       hibernate_root_machine
		disks:      [hibernate_data_disk, hibernate_image_disk, hibernate_system_disk]
		files:      [tftp_probe]
		required:   ['HWTEST START hibernate-waiting', 'HWTEST STEP back in the image',
			'HWTEST PASS hibernate-waiting']
		// The second start is told of no device for an image.
		reboots:    [Reboot{
			own_cmdline: true
		}, Reboot{}]
		ending:     .poweroff
		disk_bytes: hibernate_no_image
		timeout:    420
	},
	Scenario{
		name:     'hibernate-foreign'
		about:    'a named device that holds something else is not written to, and there is no disk state'
		arches:   ['x86_64']
		cmdline:  'vinix.hibernate=sd1'
		qemu:     hibernate_machine
		disks:    [
			Disk{
				...hibernate_data_disk
				untouched: true
			},
			Disk{
				name:      'image.raw'
				size_mib:  64
				header:    'somebody else\'s data, named by mistake'
				untouched: true
			},
		]
		files:    [tftp_probe]
		required: ['HWTEST START hibernate-foreign', 'HWTEST PASS hibernate-foreign']
		ending:   .poweroff
	},
	Scenario{
		name:     'hibernate-unnamed'
		about:    'with no device named for an image there is no disk state, and nothing is written to any disk'
		arches:   ['x86_64']
		qemu:     hibernate_machine
		disks:    [
			Disk{
				...hibernate_data_disk
				untouched: true
			},
			Disk{
				...hibernate_image_disk
				untouched: true
			},
		]
		files:    [tftp_probe]
		required: ['HWTEST START hibernate-unnamed', 'HWTEST PASS hibernate-unnamed']
		ending:   .poweroff
	},
]

// The machine the suspend-to-disk scenarios boot: four processors, a network
// card, and two SATA disks -- sd0 for the tests to read and write, and sd1,
// blank when the machine is first started, for the image.
const hibernate_machine = ['-smp', '4', '-nic', 'user,model=e1000,tftp={state}/tftp', '-drive',
	'if=ide,format=raw,file={state}/disk.raw', '-drive', 'if=ide,format=raw,file={state}/image.raw']

const hibernate_machine_isolated = ['-smp', '4', '-device', 'intel-iommu', '-nic',
	'user,model=e1000,tftp={state}/tftp', '-drive', 'if=ide,format=raw,file={state}/disk.raw',
	'-drive', 'if=ide,format=raw,file={state}/image.raw']

// The same with a third disk, sd2: blank, and of the least size the kernel
// installs a system onto, which it does at the machine's first start.
const hibernate_root_machine = ['-smp', '4', '-nic', 'user,model=e1000,tftp={state}/tftp', '-drive',
	'if=ide,format=raw,file={state}/disk.raw', '-drive', 'if=ide,format=raw,file={state}/image.raw',
	'-drive', 'if=ide,format=raw,file={state}/system.raw']

const hibernate_system_disk = Disk{
	name:     'system.raw'
	size_mib: 4096
	bulky:    true
}

const hibernate_data_disk = Disk{
	name:     'disk.raw'
	size_mib: 32
	header:   'vinix hardware test disk: not blank'
}

// Room for an image of everything a machine with a gigabyte of memory can
// have in use and still take a copy of. The file is a hole until written.
const hibernate_image_disk = Disk{
	name:     'image.raw'
	size_mib: 640
	bulky:    true
}

const hibernate_actions = [
	Action{
		after:    'HWTEST STEP screen after the cycles'
		delay_ms: 200
		qmp:      screen_picture('after')
	},
	Action{
		after: 'HWTEST STEP waiting for power button'
		qmp:   '{"execute":"system_powerdown"}'
	},
]

// What guest/hibernate.v writes around each of its two cycles.
const hibernate_patterns = [
	DiskPattern{
		disk:   'disk.raw'
		offset: 1 << 20
		length: 65536
		seed:   0x51
	},
	DiskPattern{
		disk:   'disk.raw'
		offset: 2 << 20
		length: 65536
		seed:   0x52
	},
	DiskPattern{
		disk:   'disk.raw'
		offset: 3 << 20
		length: 65536
		seed:   0x53
	},
	DiskPattern{
		disk:   'disk.raw'
		offset: 4 << 20
		length: 65536
		seed:   0x54
	},
]

// And around an image that is refused: one before the machine is put away,
// one by the machine that started afresh.
const hibernate_refusal_patterns = [
	DiskPattern{
		disk:   'disk.raw'
		offset: 1 << 20
		length: 65536
		seed:   0x61
	},
	DiskPattern{
		disk:   'disk.raw'
		offset: 2 << 20
		length: 65536
		seed:   0x62
	},
]

// What the image device must hold when the machine has ended: the header of
// a device that is this system's, describing no pages. An image that was
// gone back into, and one that was refused, are both gone.
const hibernate_no_image = [
	DiskBytes{
		disk: 'image.raw'
		text: 'VINIXHIB'
	},
	DiskBytes{
		disk:   'image.raw'
		offset: 24
		zeros:  8
	},
]

// One sleep that QEMU must have seen begin and end.
const deep_once = ['SUSPEND', 'WAKEUP']

// What the suspend-to-RAM scenarios share. guest/suspend_deep.v reads the
// parts of the disk filled here, each once, and writes the patterns looked
// for afterwards.
const deep_disk = Disk{
	name:     'disk.raw'
	size_mib: 32
	header:   'vinix hardware test disk: not blank'
	prefill:  [
		DiskPattern{
			offset: 17 << 20
			length: 65536
			seed:   0x41
		},
		DiskPattern{
			offset: 18 << 20
			length: 65536
			seed:   0x42
		},
		DiskPattern{
			offset: 19 << 20
			length: 65536
			seed:   0x43
		},
		DiskPattern{
			offset: 20 << 20
			length: 65536
			seed:   0x44
		},
	]
}

const deep_patterns = [
	DiskPattern{
		disk:   'disk.raw'
		offset: 1 << 20
		length: 65536
		seed:   0x31
	},
	DiskPattern{
		disk:   'disk.raw'
		offset: 3 << 20
		length: 65536
		seed:   0x71
	},
	DiskPattern{
		disk:   'disk.raw'
		offset: 4 << 20
		length: 65536
		seed:   0x72
	},
	DiskPattern{
		disk:   'disk.raw'
		offset: 5 << 20
		length: 65536
		seed:   0x73
	},
	DiskPattern{
		disk:   'disk.raw'
		offset: 6 << 20
		length: 65536
		seed:   0x74
	},
]

// What the host does to a machine going through the suspend-to-RAM scenarios,
// in the order the guest asks for it. The machine is woken by the host only
// once QEMU has said it is suspended: `system_wakeup` is refused for a
// machine that is running. The sleep between the two woken from here is
// ended by the clock's alarm, inside the machine, and so are the five that
// follow them.
const deep_type_a = '{"execute":"send-key","arguments":{"keys":[{"type":"qcode","data":"a"},{"type":"qcode","data":"ret"}]}}'
const deep_press_shift = '{"execute":"send-key","arguments":{"keys":[{"type":"qcode","data":"shift"}]}}'
const deep_move_mouse = '{"execute":"input-send-event","arguments":{"events":[{"type":"rel","data":{"axis":"x","value":40}},{"type":"rel","data":{"axis":"y","value":25}}]}}'

const deep_actions = [
	Action{
		after:    'HWTEST STEP type on the keyboard'
		delay_ms: 300
		qmp:      deep_type_a
	},
	Action{
		after:    'HWTEST STEP move the pointer'
		delay_ms: 300
		qmp:      deep_move_mouse
	},
	Action{
		after:    'HWTEST STEP screen drawn'
		delay_ms: 200
		qmp:      '{"execute":"screendump","arguments":{"filename":"{state}/screen-before.ppm"}}'
	},
	// While the machine is down in a rehearsal, which this must end as a
	// sleep that failed.
	Action{
		after:    'HWTEST STEP rehearsal for a key'
		delay_ms: 1000
		qmp:      deep_press_shift
	},
	Action{
		after:          'HWTEST STEP deep sleep, a picture'
		event:          'SUSPEND'
		event_count:    1
		event_delay_ms: 500
		qmp:            '{"execute":"screendump","arguments":{"filename":"{state}/screen-asleep.ppm"}}'
	},
	Action{
		after:          'HWTEST STEP deep sleep for a wakeup'
		event:          'SUSPEND'
		event_count:    1
		event_delay_ms: 2000
		qmp:            '{"execute":"system_wakeup"}'
	},
	Action{
		after:    'HWTEST STEP awake after the wakeup'
		delay_ms: 100
		qmp:      '{"execute":"screendump","arguments":{"filename":"{state}/screen-woken.ppm"}}'
	},
	Action{
		after:          'HWTEST STEP deep sleep for a key'
		event:          'SUSPEND'
		event_count:    3
		event_delay_ms: 2000
		qmp:            deep_press_shift
	},
	Action{
		after:    'HWTEST STEP type on the keyboard'
		delay_ms: 300
		qmp:      deep_type_a
	},
	Action{
		after:    'HWTEST STEP move the pointer'
		delay_ms: 300
		qmp:      deep_move_mouse
	},
	Action{
		after:    'HWTEST STEP screen after the sleeps'
		delay_ms: 200
		qmp:      '{"execute":"screendump","arguments":{"filename":"{state}/screen-after.ppm"}}'
	},
	Action{
		after: 'HWTEST STEP waiting for power button'
		qmp:   '{"execute":"system_powerdown"}'
	},
]

// A card that comes or goes while QEMU has the machine suspended. The guest
// prints both lines before it goes down; the card is dealt with half a second
// into the sleep and the machine woken two seconds after that.
const deep_wakeup = '{"execute":"system_wakeup"}'

const deep_arrival_actions = [
	Action{
		after:          'HWTEST STEP a card while asleep'
		event:          'SUSPEND'
		event_count:    1
		event_delay_ms: 500
		qmp:            hotplug_add
	},
	Action{
		after:          'HWTEST STEP a wakeup with the card in'
		event:          'SUSPEND'
		event_count:    1
		event_delay_ms: 2500
		qmp:            deep_wakeup
	},
	Action{
		after:    'HWTEST STEP screen after the sleeps'
		delay_ms: 200
		qmp:      screen_picture('woken')
	},
	Action{
		after: 'HWTEST STEP card in use after the sleeps'
		qmp:   hotplug_remove
	},
]

const deep_departure_actions = [
	Action{
		after:          'HWTEST STEP the card goes while asleep'
		event:          'SUSPEND'
		event_count:    1
		event_delay_ms: 500
		qmp:            hotplug_remove
	},
	Action{
		after:          'HWTEST STEP a wakeup without the card'
		event:          'SUSPEND'
		event_count:    1
		event_delay_ms: 2500
		qmp:            deep_wakeup
	},
	Action{
		after:          'HWTEST STEP a card while asleep'
		event:          'SUSPEND'
		event_count:    2
		event_delay_ms: 500
		qmp:            hotplug_add
	},
	Action{
		after:          'HWTEST STEP a wakeup with the card in'
		event:          'SUSPEND'
		event_count:    2
		event_delay_ms: 2500
		qmp:            deep_wakeup
	},
	Action{
		after:    'HWTEST STEP screen after the sleeps'
		delay_ms: 200
		qmp:      screen_picture('woken')
	},
]

// Eight sleeps, each of which QEMU must have seen begin and end.
const deep_events = ['SUSPEND', 'SUSPEND', 'SUSPEND', 'SUSPEND', 'SUSPEND', 'SUSPEND', 'SUSPEND',
	'SUSPEND', 'WAKEUP', 'WAKEUP', 'WAKEUP', 'WAKEUP', 'WAKEUP', 'WAKEUP', 'WAKEUP', 'WAKEUP']

// What the guest drew before the first sleep must be what the display
// adapter shows straight after the first wake and after the last, in the
// same mode; and while the machine is down the screen must be dark.
const deep_screens = [
	Screen{
		file:    'screen-before.ppm'
		pattern: 256
	},
	Screen{
		file: 'screen-asleep.ppm'
		dark: true
	},
	Screen{
		file:    'screen-woken.ppm'
		like:    'screen-before.ppm'
		pattern: 256
	},
	Screen{
		file:    'screen-after.ppm'
		like:    'screen-before.ppm'
		pattern: 256
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

// How many times the machine is booted.
pub fn (s &Scenario) boots() int {
	return 1 + s.reboots.len
}

// The same for boot `boot`, the first being 0: a later boot's own arguments
// come last, where they override.
pub fn (s &Scenario) boot_arguments(arch string, boot int) []string {
	mut extra := s.qemu_arguments(arch)
	if boot > 0 && boot <= s.reboots.len {
		extra << s.reboots[boot - 1].qemu
	}
	return extra
}

// The extra kernel command line of boot `boot`.
pub fn (s &Scenario) boot_cmdline(boot int) string {
	if boot > 0 && boot <= s.reboots.len && s.reboots[boot - 1].own_cmdline {
		return s.reboots[boot - 1].cmdline
	}
	return s.cmdline
}

// The serial log of boot `boot`: serial.log, then serial-2.log and so on,
// since QEMU empties the file it is given.
pub fn serial_log_name(boot int) string {
	return if boot == 0 { 'serial.log' } else { 'serial-${boot + 1}.log' }
}

// The line put between two boots' serial output where they are shown as one.
pub fn boot_separator(boot int) string {
	return '──── boot ${boot + 1} ────'
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
			if (action.event == '') != (action.event_count == 0) || action.event_count < 0 {
				return error('scenario ${scenario.name}: an action that waits for an event names it and says how many')
			}
		}
		for writing in scenario.writings {
			if !scenario.qemu_arguments('x86_64').any(it.contains('{state}/${writing.file}'))
				&& !scenario.qemu_arguments('aarch64').any(it.contains('{state}/${writing.file}')) {
				return error('scenario ${scenario.name}: nothing writes ${writing.file}')
			}
		}
		for sound in scenario.sounds {
			// A recording QEMU is not told to make would fail every run.
			if sound.levels.len == 0 || sound.frames <= 0 {
				return error('scenario ${scenario.name}: the recording ${sound.file} is asked for nothing')
			}
			if !scenario.qemu_arguments('x86_64').any(it.contains('{state}/${sound.file}'))
				&& !scenario.qemu_arguments('aarch64').any(it.contains('{state}/${sound.file}')) {
				return error('scenario ${scenario.name}: nothing records ${sound.file}')
			}
		}
		if scenario.reboots.len > 0 && scenario.ending == .running {
			return error('scenario ${scenario.name}: a machine booted more than once has to end by itself')
		}
		mut damages := []DiskDamage{}
		for reboot in scenario.reboots {
			damages << reboot.damage
		}
		for damage in damages {
			if damage.length <= 0 || !scenario.disks.any(it.name == damage.disk) {
				return error('scenario ${scenario.name}: damage is done to a disk the scenario has, and to some of it')
			}
		}
		for bytes in scenario.disk_bytes {
			if !scenario.disks.any(it.name == bytes.disk) || (bytes.text == '') == (bytes.zeros == 0) {
				return error('scenario ${scenario.name}: bytes are expected on a disk the scenario has, as text or as zeros')
			}
		}
		for screen in scenario.screens {
			if screen.pattern < 0 || (screen.dark && screen.pattern != 0) {
				return error('scenario ${scenario.name}: the picture ${screen.file} cannot be dark and show a pattern')
			}
			if screen.like != '' && !scenario.screens.any(it.file == screen.like) {
				return error('scenario ${scenario.name}: the picture ${screen.file} is compared with ${screen.like}, which is not one of its pictures')
			}
		}
		for screen in scenario.screens {
			// A picture nobody takes would fail every run for a reason that
			// has nothing to do with the kernel.
			if !scenario.actions.any(it.qmp.contains('"screendump"')
				&& it.qmp.contains('{state}/${screen.file}"')) {
				return error('scenario ${scenario.name}: no action takes the picture ${screen.file}')
			}
		}
		for event in scenario.events {
			// SHUTDOWN is judged by how the scenario is to end, not listed.
			if event == '' || event == 'SHUTDOWN' || event != event.to_upper() {
				return error('scenario ${scenario.name}: "${event}" is not an event a scenario can require')
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
	if s.build != '' {
		return 'needs a kernel built with ${s.build}'
	}
	return ''
}
