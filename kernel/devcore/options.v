// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module devcore

import limine

// The value the kernel command line gives `name`, which ends in its `=`:
// boot_option('vinix.iommu=') is "1" for "vinix.iommu=1". A view into the
// command line, good for the life of the machine; none when the option is not
// there. The last one wins, as it does for every other vinix. option.
pub fn boot_option(name string) ?string {
	kernel_file := limine.kernel_file()
	if kernel_file == unsafe { nil } || kernel_file.cmdline == unsafe { nil } {
		return none
	}
	text := unsafe { &u8(kernel_file.cmdline) }
	mut found := false
	mut value := ''
	mut index := 0
	for unsafe { text[index] } != 0 {
		for unsafe { text[index] } == ` ` {
			index++
		}
		start := index
		for unsafe { text[index] } != 0 && unsafe { text[index] } != ` ` {
			index++
		}
		if index - start < name.len {
			continue
		}
		mut matched := true
		for i in 0 .. name.len {
			if unsafe { text[start + i] } != name[i] {
				matched = false
				break
			}
		}
		if matched {
			found = true
			value = unsafe { tos(&text[start + name.len], index - start - name.len) }
		}
	}
	if !found {
		return none
	}
	return value
}

// Whether the command line switches `name` on: its value is 1, on or yes.
// `default` when it does not say.
pub fn boot_flag(name string, default bool) bool {
	value := boot_option(name) or { return default }
	if value == '1' || value == 'on' || value == 'yes' {
		return true
	}
	if value == '0' || value == 'off' || value == 'no' {
		return false
	}
	return default
}
