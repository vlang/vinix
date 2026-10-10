// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// What an IOMMU driver gives the DMA layer.
//
// An IOMMU sits between a set of devices and memory and translates every
// address they put on the bus through page tables the kernel writes. A driver
// for one -- Intel's VT-d, AMD's AMD-Vi, Apple's DART -- registers a unit here
// with the six operations below, and the DMA layer does the rest: it asks
// which unit a device is behind, has page tables made for the device when its
// driver first asks for memory, and keeps them in step with the buffers the
// driver holds.
//
//	covers    whether this unit translates for the device
//	attach    make the device a domain of its own, empty; returns a cookie
//	detach    take it away: the device reaches nothing again
//	map       let the domain reach `bytes` at `phys`, at address `iova`
//	unmap     the reverse, not returning until the device cannot use it
//	map_all   let the domain reach all of RAM, for allow_all()
//
// A unit that is switched on blocks every device behind it that has no
// domain. That is the point of it, and it is why a unit is only switched on
// once the drivers of the devices behind it ask for their memory through
// this module.
@[has_globals]
module dma

import devcore

pub struct Iommu {
pub mut:
	name    string
	covers  fn (iommu &Iommu, dev &devcore.Device) bool               = unsafe { nil }
	attach  fn (iommu &Iommu, mut dev devcore.Device) voidptr         = unsafe { nil }
	detach  fn (cookie voidptr)                                       = unsafe { nil }
	map     fn (cookie voidptr, iova u64, phys u64, bytes u64) bool   = unsafe { nil }
	unmap   fn (cookie voidptr, iova u64, bytes u64)                  = unsafe { nil }
	map_all fn (cookie voidptr) bool                                  = unsafe { nil }
	// The unit's own state.
	data voidptr
}

const max_iommus = 8

__global (
	dma_iommus      [max_iommus]Iommu
	dma_iommu_count int
)

// Add a unit. The record is copied; the pointer returned is good for the life
// of the machine.
pub fn register_iommu(unit Iommu) ?&Iommu {
	dma_lock.acquire()
	defer {
		dma_lock.release()
	}
	if dma_iommu_count >= max_iommus {
		return none
	}
	mut slot := unsafe { &dma_iommus[dma_iommu_count] }
	unsafe {
		*slot = unit
	}
	dma_iommu_count++
	return slot
}

pub fn iommu_count() int {
	return dma_iommu_count
}

// The unit in front of `dev`, or nil. Units are registered at boot, before
// the first driver asks for memory, and never go.
fn iommu_for(dev &devcore.Device) &Iommu {
	for i in 0 .. dma_iommu_count {
		unit := unsafe { &dma_iommus[i] }
		if unit.covers != unsafe { nil } && unit.covers(unit, dev) {
			return unit
		}
	}
	return unsafe { nil }
}
