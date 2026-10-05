// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module ans

import devicetree
import aarch64.pmgr
import memory

struct Domain {
	phandle u32
	region  devicetree.DTReg
	offset  u32
}

struct Plan {
mut:
	nvme    devicetree.DTReg
	asc     devicetree.DTReg
	mailbox devicetree.DTReg
	sart    devicetree.DTReg
	reset   Domain
	power   []Domain
	// DMA addresses the bus passes through untranslated end here.
	dma_limit u64
}

fn compatible(node &devicetree.DTNode, value string) bool {
	list := devicetree.get_string_list(node, 'compatible') or { return false }
	defer { unsafe { list.free() } }
	for item in list {
		if item == value { return true }
	}
	return false
}

fn enabled(node &devicetree.DTNode) bool {
	mut n := node
	for _ in 0 .. 64 {
		if n == unsafe { nil } { return true }
		status := devicetree.get_string_prop(n, 'status') or { 'okay' }
		if status != 'okay' && status != 'ok' { return false }
		n = n.parent
	}
	return false
}

fn find_ans(node &devicetree.DTNode, depth int) ?&devicetree.DTNode {
	if depth > 64 || !enabled(node) { return none }
	if compatible(node, 'apple,t8103-nvme-ans2') { return node }
	for child in node.children {
		found := find_ans(child, depth + 1) or { continue }
		return found
	}
	return none
}

fn valid_region(r devicetree.DTReg, minimum u64) bool {
	return r.base != 0 && r.base & 7 == 0 && r.size >= minimum
		&& r.size <= 0x1000000 && r.base <= ~u64(0) - r.size
}

fn single_region(node &devicetree.DTNode, minimum u64) ?devicetree.DTReg {
	regs := devicetree.get_translated_reg_ranges(node) or { return none }
	defer { unsafe { regs.free() } }
	if regs.len != 1 || !valid_region(regs[0], minimum) { return none }
	return regs[0]
}

fn overlap(a devicetree.DTReg, b devicetree.DTReg) bool {
	return a.base < b.base + b.size && b.base < a.base + a.size
}

fn domain(handle u32) ?Domain {
	node := devicetree.find_phandle(handle) or { return none }
	if !enabled(node) || !compatible(node, 'apple,pmgr-pwrstate')
		|| devicetree.get_u32(node, '#power-domain-cells') or { u32(1) } != 0 {
		return none
	}
	parent := node.parent
	if parent == unsafe { nil } || !compatible(parent, 'apple,t8103-pmgr')
		|| devicetree.get_u32(parent, '#address-cells') or { u32(0) } != 1
		|| devicetree.get_u32(parent, '#size-cells') or { u32(0) } != 1 {
		return none
	}
	region := single_region(parent, 4) or { return none }
	reg := devicetree.get_u32_array(node, 'reg') or { return none }
	defer { unsafe { reg.free() } }
	if reg.len != 2 || reg[0] & 3 != 0 || reg[1] < 4
		|| u64(reg[0]) > region.size - 4 || u64(reg[1]) > region.size - u64(reg[0]) {
		return none
	}
	return Domain{phandle: handle, region: region, offset: reg[0]}
}

// A PMGR provider's reg is an offset, not a physical address. Resolve parents
// first; a cycle hits the depth bound instead of being accepted as visited.
fn plan_power(node &devicetree.DTNode, depth int, mut plan Plan) bool {
	if depth > 16 || plan.power.len > 64 { return false }
	_ := devicetree.get_property(node, 'power-domains') or { return true }
	handles := devicetree.get_u32_array(node, 'power-domains') or { return false }
	defer { unsafe { handles.free() } }
	if handles.len > 8 { return false }
	for handle in handles {
		mut seen := false
		for d in plan.power {
			if d.phandle == handle { seen = true; break }
		}
		if seen { continue }
		d := domain(handle) or { return false }
		provider := devicetree.find_phandle(handle) or { return false }
		if !plan_power(provider, depth + 1, mut plan) || plan.power.len >= 64 { return false }
		plan.power << d
	}
	return true
}

fn read_cells(values []u32, at int, count int) u64 {
	mut value := u64(0)
	for i in 0 .. count {
		value = (value << 32) | u64(values[at + i])
	}
	return value
}

// The end of the identity window from address 0 that a node's dma-ranges
// gives, or none when any entry translates. Asahi's trees give the soc bus
// <0 0 0 0 0xffffffff 0xffffc000> so that DARTs can reach memory above 4 GiB:
// one identity window over nearly the whole address space, which moves no
// address and only bounds them.
fn identity_window(node &devicetree.DTNode) ?u64 {
	child_cells := int(devicetree.get_u32(node, '#address-cells') or { u32(2) })
	size_cells := int(devicetree.get_u32(node, '#size-cells') or { u32(1) })
	mut parent_cells := 2
	if node.parent != unsafe { nil } {
		parent_cells = int(devicetree.get_u32(node.parent, '#address-cells') or { u32(2) })
	}
	if child_cells < 1 || child_cells > 2 || parent_cells < 1 || parent_cells > 2
		|| size_cells < 1 || size_cells > 2 {
		return none
	}
	values := devicetree.get_u32_array(node, 'dma-ranges') or { return none }
	defer { unsafe { values.free() } }
	entry := child_cells + parent_cells + size_cells
	if values.len == 0 || values.len % entry != 0 {
		return none
	}
	mut limit := u64(0)
	for i := 0; i < values.len; i += entry {
		child := read_cells(values, i, child_cells)
		parent := read_cells(values, i + child_cells, parent_cells)
		size := read_cells(values, i + child_cells + parent_cells, size_cells)
		if child != parent || size == 0 {
			return none
		}
		if child == 0 {
			limit = size
		}
	}
	if limit == 0 {
		return none
	}
	return limit
}

// This transport uses physical DMA addresses, not translated IOVAs. The M1
// binding uses SART/NVMMU; an IOMMU or a bus that translates DMA is not
// supported. Returns where untranslated DMA addresses end.
fn dma_limit(node &devicetree.DTNode) ?u64 {
	mut limit := ~u64(0)
	mut current := node
	for _ in 0 .. 64 {
		if current == unsafe { nil } { return limit }
		if ranges := devicetree.get_property(current, 'dma-ranges') {
			if ranges.len != 0 {
				window := identity_window(current) or { return none }
				if window < limit { limit = window }
			}
		}
		if iommu := devicetree.get_property(current, 'iommus') {
			_ = iommu
			return none
		}
		current = current.parent
	}
	return none
}

// Which discovery check failed: "invalid or unsupported device-tree
// resources" alone left the first M1 boot with nothing to go on.
fn refuse(reason string) bool {
	C.kprintf(c'ans: device tree: %.*s\n', i32(reason.len), reason.str)
	return false
}

fn discover(node &devicetree.DTNode, mut plan Plan) bool {
	plan.dma_limit = dma_limit(node) or {
		return refuse('the bus translates DMA addresses (dma-ranges or an IOMMU)')
	}
	regs := devicetree.get_translated_reg_ranges(node) or { return refuse('no registers') }
	defer { unsafe { regs.free() } }
	names := devicetree.get_string_list(node, 'reg-names') or { return refuse('no reg-names') }
	defer { unsafe { names.free() } }
	if regs.len != 2 || names.len != 2 || names[0] != 'nvme' || names[1] != 'ans'
		|| !valid_region(regs[0], 0x28124) || !valid_region(regs[1], 0x48) {
		return refuse('registers are not the nvme and ans apertures expected')
	}
	plan.nvme = regs[0]
	plan.asc = regs[1]
	mboxes := devicetree.get_u32_array(node, 'mboxes') or { return refuse('no mboxes') }
	defer { unsafe { mboxes.free() } }
	if mboxes.len != 1 { return refuse('not exactly one mailbox') }
	mbox := devicetree.find_phandle(mboxes[0]) or { return refuse('mailbox node missing') }
	if !enabled(mbox) || !compatible(mbox, 'apple,asc-mailbox-v4')
		|| devicetree.get_u32(mbox, '#mbox-cells') or { u32(1) } != 0 {
		return refuse('mailbox is not an enabled apple,asc-mailbox-v4')
	}
	plan.mailbox = single_region(mbox, 0x840) or { return refuse('mailbox registers unusable') }
	sart_handle := devicetree.get_u32(node, 'apple,sart') or { return refuse('no apple,sart') }
	sart := devicetree.find_phandle(sart_handle) or { return refuse('SART node missing') }
	if !enabled(sart) || !compatible(sart, 'apple,t8103-sart') {
		return refuse('SART is not an enabled apple,t8103-sart')
	}
	plan.sart = single_region(sart, 0x80) or { return refuse('SART registers unusable') }
	pd := devicetree.get_u32_array(node, 'power-domains') or { return refuse('no power-domains') }
	defer { unsafe { pd.free() } }
	pd_names := devicetree.get_string_list(node, 'power-domain-names') or {
		return refuse('no power-domain-names')
	}
	defer { unsafe { pd_names.free() } }
	resets := devicetree.get_u32_array(node, 'resets') or { return refuse('no resets') }
	defer { unsafe { resets.free() } }
	if pd.len != 2 || pd_names.len != 2 || pd_names[0] != 'ans'
		|| pd_names[1] != 'apcie0' || resets.len != 1 || resets[0] != pd[0] {
		return refuse('power domains are not ans and apcie0 with the ans domain as reset')
	}
	reset := devicetree.find_phandle(resets[0]) or { return refuse('reset node missing') }
	if devicetree.get_u32(reset, '#reset-cells') or { u32(1) } != 0 {
		return refuse('reset takes arguments')
	}
	plan.reset = domain(resets[0]) or { return refuse('reset is not a t8103 PMGR power state') }
	// These apertures belong to distinct devices. Refuse aliasing resources.
	if overlap(plan.nvme, plan.asc) || overlap(plan.nvme, plan.mailbox)
		|| overlap(plan.nvme, plan.sart) || overlap(plan.asc, plan.mailbox)
		|| overlap(plan.asc, plan.sart) || overlap(plan.mailbox, plan.sart) {
		return refuse('device apertures overlap')
	}
	if !plan_power(node, 0, mut plan) || !plan_power(mbox, 0, mut plan)
		|| !plan_power(sart, 0, mut plan) {
		return refuse('a power domain or one it depends on is unusable')
	}
	for d in plan.power {
		if overlap(d.region, plan.nvme) || overlap(d.region, plan.asc)
			|| overlap(d.region, plan.mailbox) || overlap(d.region, plan.sart) {
			return refuse('a PMGR region overlaps a device aperture')
		}
	}
	return true
}

fn initialise_hardware() bool {
	root := devicetree.find_node('/') or { return false }
	if !compatible(root, 'apple,t8103') {
		println('ans: unsupported SoC (only base M1/t8103 is enabled)')
		return false
	}
	node := find_ans(root, 0) or {
		println('ans: no enabled M1 ANS2 node')
		return false
	}
	mut plan := Plan{}
	defer { unsafe { plan.power.free() } }
	if !discover(node, mut plan) {
		println('ans: invalid or unsupported device-tree resources; not probing')
		return false
	}
	// Map everything before any power/reset/controller register writes.
	nvme := memory.map_mmio(plan.nvme.base, plan.nvme.size)
	asc := memory.map_mmio(plan.asc.base, plan.asc.size)
	mailbox := memory.map_mmio(plan.mailbox.base, plan.mailbox.size)
	sart := memory.map_mmio(plan.sart.base, plan.sart.size)
	reset := memory.map_mmio(plan.reset.region.base, plan.reset.region.size)
	if nvme == 0 || asc == 0 || mailbox == 0 || sart == 0 || reset == 0 { return false }
	// One bounded, fallible allocation. DMA is 16 KiB aligned.
	bytes := u64(0x460000)
	physical := u64(memory.pmm_alloc_aligned_fallible(bytes / memory.page_size,
		u64(0x4000) / memory.page_size))
	if physical == 0 { println('ans: DMA allocation failed'); return false }
	if physical + bytes > plan.dma_limit {
		memory.pmm_free(voidptr(physical), bytes / memory.page_size)
		println('ans: DMA arena lies beyond the bus DMA window; not probing')
		return false
	}
	// Never free this arena after hardware has been started, even on error.
	// Its queues, TCBs and firmware system buffers may still be DMA targets.
	for d in plan.power {
		if !pmgr.enable_region(d.region.base, d.region.size, d.offset) {
			memory.pmm_free(voidptr(physical), bytes / memory.page_size)
			println('ans: power-domain enable failed')
			return false
		}
	}
	result := C.vinix_ans_init(nvme, asc, mailbox, sart, reset + plan.reset.offset,
		voidptr(physical + memory.get_hhdm_offset()), physical, bytes)
	if result != 0 {
		report('initialization failed (DMA pinned)', result)
		return false
	}
	return true
}
