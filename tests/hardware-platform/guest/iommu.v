// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// iommu-intel, iommu-amd and iommu-off: devices doing their work from behind
// an IOMMU, each held to its own memory.
//
// With the unit switched on (vinix.iommu=1) every device the kernel drives
// must still work, which for the network card and the disk controller means
// every address they were given was mapped for them, and their `dma` file
// must say they are isolated: a domain of their own with only their rings,
// tables and buffers in it. Unbinding and binding the card twenty times must
// leave it working and isolated, and at the end the unit must have recorded
// no fault -- a device reaching for memory it was not given is exactly what a
// fault is.
//
// iommu-off is the same machine without the option: nothing is switched on,
// and everything works as it does with no unit at all.
//
// That a device is *stopped* from reaching other memory is shown by the
// kernel's own self-tests, which make a card try; they need a kernel built
// for them and are described in docs/hardware-platform.md.
module main

import os

fn dma_line(device string) string {
	text := read_text('${device}/dma') or { return 'unreadable' }
	return text.split_into_lines()[0] or { '' }
}

// The sysfs device bound to `driver`, or ''.
fn bound_device(driver string) string {
	names := list_dir('/sys/bus/pci/drivers/${driver}') or { return '' }
	for name in names {
		if name.starts_with('0000:') {
			return '/sys/bus/pci/devices/${name}'
		}
	}
	return ''
}

// `unit` is the name the kernel gives the machine's first unit, dmar0 or
// ivhd0, or '' when none is to be on. `quiet` is the file that counts what it
// caught and the text that file has when it caught nothing.
fn check_iommu(mut t Test, unit string, quiet_file string, quiet_text string) {
	card := bound_device('e1000')
	controller := bound_device('ahci')
	t.check(card != '', 'no e1000 is bound')
	t.check(controller != '', 'no AHCI controller is bound')
	if card == '' || controller == '' {
		return
	}
	expected := if unit == '' { 'domain: direct' } else { 'domain: ${unit} isolated' }
	if unit == '' {
		units := list_dir('/sys/class/iommu') or { []string{} }
		t.check(units.len == 0, 'units are listed without vinix.iommu=1: ${units}')
	} else {
		state := read_text('/sys/class/iommu/${unit}/${if unit.starts_with('dmar') { 'state' } else { 'unit' }}') or {
			''
		}
		t.check(state.contains('on'), '${unit} is not on: "${state.replace('\n', ' | ')}"')
	}
	t.check(dma_line(card) == expected, 'the card says "${dma_line(card)}", not "${expected}"')
	t.check(dma_line(controller) == expected, 'the disk controller says "${dma_line(controller)}", not "${expected}"')

	t.check(network_works(20), 'the network does not work')
	write_pattern('/dev/sd0', 1 << 20, 0x21, 65536) or { t.check(false, 'disk: ${err.msg()}') }

	name := os.base(card)
	for i in 0 .. 20 {
		write_text('/sys/bus/pci/drivers/e1000/unbind', name) or {
			t.check(false, 'unbind ${i + 1}: ${err.msg()}')
			break
		}
		write_text('/sys/bus/pci/drivers/e1000/bind', name) or {
			t.check(false, 'bind ${i + 1}: ${err.msg()}')
			break
		}
	}
	t.check(dma_line(card) == expected, 'after twenty rebinds the card says "${dma_line(card)}"')
	t.check(network_works(20), 'the network does not work after twenty rebinds')
	write_pattern('/dev/sd0', 2 << 20, 0x65, 65536) or { t.check(false, 'disk: ${err.msg()}') }

	if unit != '' {
		caught := read_text('/sys/class/iommu/${unit}/${quiet_file}') or { 'unreadable' }
		t.check(caught.contains(quiet_text), '${unit} recorded a fault: "${caught.replace('\n', ' | ')}"')
		t.info('${unit}: card and disk controller isolated; network and disk work; ${quiet_file} says ${quiet_text}')
	}
}

fn scenario_iommu_intel(mut t Test) {
	check_iommu(mut t, 'dmar0', 'faults', 'count: 0')
}

fn scenario_iommu_amd(mut t Test) {
	check_iommu(mut t, 'ivhd0', 'events', 'total: 0')
}

fn scenario_iommu_off(mut t Test) {
	check_iommu(mut t, '', '', '')
}
