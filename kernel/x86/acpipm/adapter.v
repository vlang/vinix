// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// The charger (ACPI0003): _PSR says whether it is supplying power, and
// firmware sends Notify 0x80 when it is plugged in or pulled.
module acpipm

import devcore
import psupply
import uacpi

struct Adapter {
mut:
	node   uacpi.Node
	supply &psupply.Supply = unsafe { nil }
}

const max_adapters = 2

__global (
	acpipm_adapter_table [max_adapters]Adapter
)

fn adapter_read(context voidptr, mut reading psupply.Reading) bool {
	adapter := unsafe { &Adapter(context) }
	online := uacpi.evaluate_integer(adapter.node, '_PSR') or { return false }
	reading.present = true
	reading.online = online != 0
	return true
}

fn adapter_notify(context voidptr, _node voidptr, _value u64) uacpi.UACPIStatus {
	adapter := unsafe { &Adapter(context) }
	if adapter.supply != unsafe { nil } {
		mut supply := adapter.supply
		psupply.changed(mut supply)
	}
	return .ok
}

fn adapter_found(context voidptr, node uacpi.Node) {
	if acpipm_adapters >= max_adapters {
		return
	}
	mut adapter := unsafe { &acpipm_adapter_table[acpipm_adapters] }
	adapter.node = node
	mut name := [16]u8{}
	mut length := uacpi.node_name(node, &name[0], 12)
	if length == 0 {
		name[0] = `A`
		name[1] = `C`
		length = 2
	}
	adapter.supply = psupply.register(psupply.Supply{
		name:    unsafe { tos(&name[0], length) }
		kind:    .mains
		read:    adapter_read
		context: voidptr(adapter)
	}) or { return }
	acpipm_adapters++
	uacpi.on_notify(node, adapter_notify, voidptr(adapter))
	mut driver := unsafe { &devcore.Driver(context) }
	add_device(node, 'ACPI0003', mut driver)
}
