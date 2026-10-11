// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// hwcheck: what this machine has, what drives it, and whether the parts of
// power management that can be tried without risk work -- as a report to
// attach to a hardware qualification checklist.
//
// It reads only what the kernel publishes in /sys, /proc and /dev, so it says
// what the running kernel found rather than what it was built to support.
// With --rehearse-sleep it also suspends and resumes every device once
// without sleeping (pm_test = devices), which is how a machine's drivers are
// checked before the machine is trusted to sleep. It never writes to a disk
// and never sleeps for real.
//
//	hwcheck                     the report, as Markdown, on standard output
//	hwcheck --rehearse-sleep    the same, then the sleep rehearsal
//
// Run as the first process of a machine -- a test image -- it writes to the
// console and turns the machine off when it is done.
module main

import os

#include <unistd.h>
#include <sys/reboot.h>

fn C.sync()
fn C.reboot(command int) int
fn C.usleep(microseconds u32) int

const sys = '/sys'

struct Report {
mut:
	lines    []string
	problems int
}

fn (mut r Report) add(line string) {
	r.lines << line
}

fn (mut r Report) problem(text string) {
	r.problems++
	r.lines << '- **problem:** ${text}'
}

fn word(path string) string {
	return (os.read_file(path) or { '' }).trim_space()
}

fn one_line(path string) string {
	return word(path).replace('\n', '; ')
}

fn listing(path string) []string {
	mut names := os.ls(path) or { []string{} }
	names.sort()
	return names
}

// The name of the driver a device's `driver` link leads to, or '-'.
fn driver_of(device string) string {
	target := os.readlink(device + '/driver') or { return '-' }
	return os.base(target)
}

fn machine(mut r Report) {
	r.add('# Hardware report')
	r.add('')
	r.add('| | |')
	r.add('| --- | --- |')
	r.add('| kernel | ${one_line('/proc/version')} |')
	release := word('/etc/vinix-release')
	if release != '' {
		r.add('| release | ${release} |')
	}
	mut model := ''
	mut cpus := 0
	for line in (os.read_file('/proc/cpuinfo') or { '' }).split_into_lines() {
		if line.starts_with('processor') {
			cpus++
		}
		if model == '' && (line.starts_with('model name') || line.starts_with('Hardware')
			|| line.starts_with('CPU part')) {
			model = line.all_after(':').trim_space()
		}
	}
	r.add('| processor | ${model} (${cpus} CPUs online) |')
	for line in (os.read_file('/proc/meminfo') or { '' }).split_into_lines() {
		if line.starts_with('MemTotal') {
			r.add('| memory | ${line.all_after(':').trim_space()} |')
		}
	}
	compatible := word('/proc/device-tree/compatible').replace('\0', ' ')
	if compatible != '' {
		r.add('| device tree | ${compatible} |')
	}
	r.add('')
}

fn devices(mut r Report) {
	r.add('## Devices and drivers')
	r.add('')
	r.add('| bus | device | what it is | driver | state | DMA |')
	r.add('| --- | --- | --- | --- | --- | --- |')
	mut bound := 0
	mut total := 0
	for bus in listing(sys + '/bus') {
		for name in listing('${sys}/bus/${bus}/devices') {
			device := '${sys}/bus/${bus}/devices/${name}'
			state := word(device + '/state')
			dma := (os.read_file(device + '/dma') or { '' }).split_into_lines()[0] or { '' }
			r.add('| ${bus} | ${name} | ${word(device + '/modalias')} | ${driver_of(device)} | ${state} | ${dma.all_after('domain: ')} |')
			total++
			if state == 'bound' {
				bound++
			}
			if state == 'failed' {
				r.problem('${bus} device ${name} is failed: ${one_line(device + '/health')}')
			}
		}
	}
	r.add('')
	r.add('${bound} of ${total} devices have a driver.')
	units := listing(sys + '/class/iommu')
	if units.len == 0 {
		r.add('No IOMMU is switched on (see `vinix.iommu=1`).')
	} else {
		r.add('IOMMU units on: ${units.join(', ')}.')
	}
	slots := listing(sys + '/bus/pci/slots')
	if slots.len == 0 {
		r.add('No PCI hot-plug slot is watched by the kernel.')
	}
	for name in slots {
		slot := '${sys}/bus/pci/slots/${name}'
		r.add('PCI hot-plug slot ${name}: ${word(slot + '/state')}, leads to ${word(slot + '/address')}.')
	}
	r.add('')
	r.add('Device nodes: ${listing('/dev').filter(it != 'pts' && it != 'shm').join(' ')}')
	r.add('')
}

fn power(mut r Report) {
	r.add('## Power')
	r.add('')
	r.add('| | |')
	r.add('| --- | --- |')
	r.add('| sleep states | ${word(sys + '/power/state')} |')
	r.add('| `mem` means | ${word(sys + '/power/mem_sleep')} |')
	// Why a suspend to RAM is or is not offered, in the kernel's own words;
	// empty on a kernel or an architecture that has none.
	deep := (os.read_file(sys + '/power/deep_sleep') or { '' }).split_into_lines()
	if deep.len > 0 {
		r.add('| suspend to RAM | ${deep[0]} |')
	}
	r.add('| lid | ${word(sys + '/power/lid/state')}, on closing: ${word(sys + '/power/lid/action')} |')
	mut wake := []string{}
	for name in listing(sys + '/class/wakeup') {
		source := '${sys}/class/wakeup/${name}'
		if word(source + '/enabled') == 'enabled' {
			wake << word(source + '/name')
		}
	}
	r.add('| may wake the machine | ${wake.join(', ')} |')
	r.add('| screen across a sleep | dark ${word(sys + '/power/suspend_stats/screen_dark')} times, left lit ${word(sys +
		'/power/suspend_stats/screen_lit')} |')
	// Panels whose backlight the kernel can set: without one a dark screen is a
	// black picture on a lit panel.
	panels := listing(sys + '/class/backlight')
	if panels.len == 0 {
		r.add('| backlight | none the kernel can set |')
	}
	for name in panels {
		panel := '${sys}/class/backlight/${name}'
		r.add('| backlight ${name} | level ${word(panel + '/brightness')} of ${word(panel + '/max_brightness')}, the panel says ${word(panel +
			'/actual_brightness')}; set by ${word(panel + '/type')}; ${one_line(panel + '/stats')} |')
	}
	r.add('| sleeps so far | ${word(sys + '/power/suspend_stats/success')} succeeded, ${word(sys +
		'/power/suspend_stats/fail')} failed |')
	cpu0 := sys + '/devices/system/cpu/cpu0'
	mut states := []string{}
	for name in listing(cpu0 + '/cpuidle') {
		states << word('${cpu0}/cpuidle/${name}/name')
	}
	r.add('| idle driver | ${word(sys + '/devices/system/cpu/cpuidle/current_driver')}: ${states.join(', ')} |')
	r.add('| frequency driver | ${word(cpu0 + '/cpufreq/scaling_driver')}, governor ${word(cpu0 +
		'/cpufreq/scaling_governor')}, ${word(cpu0 + '/cpufreq/scaling_min_freq')}-${word(cpu0 +
		'/cpufreq/scaling_max_freq')} kHz, profile ${word(sys + '/devices/system/cpu/cpufreq/profile')} |')
	r.add('| thermal limit | ${word(sys + '/class/thermal/thermal_limit')}% |')
	r.add('')
	supplies := listing(sys + '/class/power_supply').filter(it != 'policy')
	if supplies.len == 0 {
		r.add('No battery or charger is known to the kernel.')
	} else {
		r.add('| supply | type | state |')
		r.add('| --- | --- | --- |')
		for name in supplies {
			supply := '${sys}/class/power_supply/${name}'
			if word(supply + '/type') == 'Mains' {
				r.add('| ${name} | Mains | ${if word(supply + '/online') == '1' { 'online' } else { 'offline' }} |')
				continue
			}
			to_empty := word(supply + '/time_to_empty_now').int()
			// Only a battery whose driver can say where charging stops has the file.
			limit := word(supply + '/charge_control_end_threshold')
			charged_to := if limit == '' { '' } else { ', charged to ${limit}%' }
			r.add('| ${name} | Battery | ${word(supply + '/capacity')}% ${word(supply + '/status')}, level ${word(supply +
				'/capacity_level')}, ${to_empty / 60} min to empty, ${word(supply + '/cycle_count')} cycles${charged_to}, ${word(supply +
				'/technology')} ${word(supply + '/manufacturer')} ${word(supply + '/model_name')} |')
			// A battery that is there with no state and a full charge of nothing
			// is one its driver cannot read: Apple's SMC stopped answering.
			full := word(supply + '/charge_full') + word(supply + '/energy_full')
			if word(supply + '/present') == '1' && word(supply + '/status') == 'Unknown' && full == '0' {
				r.problem('battery ${name} is there and cannot be read')
			}
		}
	}
	r.add('')
	zones := listing(sys + '/class/thermal').filter(it.starts_with('thermal_zone'))
	if zones.len == 0 {
		r.add('No temperature sensor is known to the kernel.')
	} else {
		r.add('| zone | type | temperature | mode |')
		r.add('| --- | --- | --- | --- |')
		for name in zones {
			zone := '${sys}/class/thermal/${name}'
			millidegrees := word(zone + '/temp').int()
			r.add('| ${name} | ${word(zone + '/type')} | ${millidegrees / 1000}.${(millidegrees % 1000) / 100} C | ${word(zone +
				'/mode')} |')
			if word(zone + '/mode') == 'disabled' {
				r.problem('thermal zone ${name} is disabled: its sensor stopped answering')
			}
		}
	}
	r.add('')
	// Every temperature and fan speed a zone carries, with the name its
	// driver gives it: a zone's own temperature is temp1.
	mut sensors := []string{}
	for name in listing(sys + '/class/hwmon') {
		chip := '${sys}/class/hwmon/${name}'
		for file in listing(chip) {
			if !file.ends_with('_input') {
				continue
			}
			channel := file.all_before('_input')
			label := word('${chip}/${channel}_label')
			called := if label == '' { channel } else { label }
			reading := word('${chip}/${file}')
			if reading == '' {
				sensors << '| ${name} ${word(chip + '/name')} | ${called} | no reading |'
			} else if channel.starts_with('temp') {
				millidegrees := reading.int()
				sensors << '| ${name} ${word(chip + '/name')} | ${called} | ${millidegrees / 1000}.${(millidegrees % 1000) / 100} C |'
			} else if channel.starts_with('fan') {
				sensors << '| ${name} ${word(chip + '/name')} | ${called} | ${reading} rpm |'
			}
		}
	}
	if sensors.len > 0 {
		r.add('| chip | sensor | reading |')
		r.add('| --- | --- | --- |')
		for line in sensors {
			r.add(line)
		}
		r.add('')
	}
	// Apple's SMC: what its driver found, and whether it is still answering.
	smc := sys + '/devices/platform/apple-smc/smc/status'
	if os.exists(smc) {
		status := os.read_file(smc) or { '' }
		r.add('Apple SMC: ${status.trim_space().replace('\n', ', ')}.')
		for line in status.split_into_lines() {
			if line.starts_with('transport ') && line != 'transport ok' {
				r.problem('the Apple SMC stopped answering: ${line.all_after('transport ')}')
			}
			if line.starts_with('keys_odd_sized ') && line != 'keys_odd_sized 0' {
				r.problem('the Apple SMC has keys of a size its driver does not take: ${line}')
			}
		}
		r.add('')
	}
	// The fans firmware describes: how each is driven and what it was last
	// told.
	fans := (os.read_file(sys + '/class/thermal/acpi_fans') or { '' }).split_into_lines()
	if fans.len == 0 {
		r.add('No fan is driven by the kernel.')
	} else {
		r.add('Fans: ${fans.join('; ')}.')
		for fan in fans {
			if fan.contains(' failures ') {
				r.problem('firmware refused a fan command: ${fan}')
			}
		}
	}
	r.add('')
}

// The number on the line of /sys/power/pci_d3 that starts with `name`.
fn d3_figure(name string) int {
	for line in (os.read_file(sys + '/power/pci_d3') or { '' }).split_into_lines() {
		if line.starts_with(name + ':') {
			return line.all_after(':').trim_space().int()
		}
	}
	return 0
}

// Which PCI functions the last sleep switched nearly off, and whether each
// came back. Nothing is said on a kernel that has no such report.
fn d3_report(mut r Report) {
	if !os.exists(sys + '/power/pci_d3') {
		return
	}
	mut down := []string{}
	for name in listing(sys + '/bus/pci/devices') {
		device := '${sys}/bus/pci/devices/${name}'
		if word(device + '/power/d3_count').int() > 0 {
			down << name
		}
		state := word(device + '/power_state')
		if state != '' && state != 'D0' {
			r.problem('pci device ${name} is in ${state} with the machine awake')
		}
	}
	r.add('PCI power states are ${word(sys + '/power/pci_d3').all_before('\n')}: the last sleep put ${d3_figure('last')} functions into D3hot (${down.join(', ')}) and wrote back ${d3_figure('rewritten')} of their registers.')
	if d3_figure('refused') > 0 {
		r.problem('${d3_figure('refused')} PCI functions would not go into D3hot')
	}
	if d3_figure('not back') > 0 {
		r.problem('${d3_figure('not back')} PCI functions did not come back from D3hot')
	}
}

// Suspends and resumes every device without sleeping.
fn rehearse(mut r Report) {
	r.add('## Sleep rehearsal')
	r.add('')
	before := word(sys + '/power/suspend_stats/success').int()
	os.write_file(sys + '/power/pm_test', 'devices') or {
		r.problem('pm_test cannot be written: ${err} (root is needed)')
		return
	}
	os.write_file(sys + '/power/state', 'freeze') or {
		r.problem('the rehearsal was refused: ${err}; step ${word(sys + '/power/suspend_stats/last_failed_step')}, device ${word(sys +
			'/power/suspend_stats/last_failed_dev')}')
	}
	os.write_file(sys + '/power/pm_test', 'none') or {}
	if word(sys + '/power/suspend_stats/success').int() == before + 1 {
		r.add('Every device suspended in ${word(sys + '/power/suspend_stats/last_suspend_ms')} ms and resumed in ${word(sys +
			'/power/suspend_stats/last_resume_ms')} ms. The CPU protection registers were compared ${word(sys +
			'/power/suspend_stats/security_checks')} times and found changed ${word(sys +
			'/power/suspend_stats/security_changes')} times.')
	}
	d3_report(mut r)
	for bus in listing(sys + '/bus') {
		for name in listing('${sys}/bus/${bus}/devices') {
			if word('${sys}/bus/${bus}/devices/${name}/state') == 'failed' {
				r.problem('${bus} device ${name} did not come back from the rehearsal')
			}
		}
	}
	r.add('')
}

fn main() {
	mut r := Report{}
	machine(mut r)
	devices(mut r)
	power(mut r)
	// As the first process of a test image there are no arguments to ask with.
	if '--rehearse-sleep' in os.args || os.getpid() == 1 {
		rehearse(mut r)
	}
	r.add(if r.problems == 0 { 'No problems found.' } else { '${r.problems} problem(s) found.' })
	text := r.lines.join('\n') + '\n'
	if os.getpid() != 1 {
		print(text)
		exit(if r.problems == 0 { 0 } else { 1 })
	}
	// The first process of a test image: there is no terminal, only the
	// console, and nothing to return to.
	console := $if arm64 { '/dev/console' } $else { '/dev/com1' }
	os.write_file(console, text) or { print(text) }
	C.sync()
	C.reboot(0x4321fedc)
	for {
		C.usleep(1000000)
	}
}
