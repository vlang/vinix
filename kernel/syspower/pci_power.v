// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What the device core did about PCI power states in the sleeps so far
// (devcore/pci_power.v), as /sys says it:
//
//	/sys/power/pci_d3    "on" or "off" (vinix.pci_d3=off), then
//	                     last:      functions the last sleep put into D3hot
//	                     total:     and all sleeps together
//	                     refused:   functions that would not go
//	                     not back:  functions that did not return to D0
//	                     rewritten: registers the last wake found changed
//	                                and wrote back
module syspower

import devcore
import fs
import lib

fn show_pci_d3(_ voidptr, mut text lib.Text) {
	last, total, refused, stuck, rewritten := devcore.pci_sleep_report()
	text.add(if devcore.pci_d3_wanted() { 'on\n' } else { 'off\n' })
	text.add('last: ')
	number_line(mut text, last)
	text.add('total: ')
	number_line(mut text, total)
	text.add('refused: ')
	number_line(mut text, refused)
	text.add('not back: ')
	number_line(mut text, stuck)
	text.add('rewritten: ')
	number_line(mut text, rewritten)
}

fn publish_pci_power() {
	fs.sysfs_attribute('power/pci_d3', 0o444, show_pci_d3, unsafe { nil }, unsafe { nil })
}
