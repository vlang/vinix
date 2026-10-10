// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module dma

import devcore

// Find and switch on the machine's IOMMUs: Intel's, described by the ACPI DMAR
// table, and AMD's, described by IVRS. A PC has one kind or neither.
//
// Translation is only switched on when the command line asks for it with
// vinix.iommu=1. A unit that is on blocks every device behind it whose driver
// has not asked for its memory through this module, and it takes over the
// machine's firmware-owned DMA as well; neither has been tried on a physical
// PC yet, and a boot that hangs with no disk is a poor way to find out.
// Called after ACPI is up and PCI has been enumerated, before any driver
// that does DMA is registered.
pub fn initialise() {
	if !devcore.boot_flag('vinix.iommu=', false) {
		return
	}
	vtd_initialise()
	amdvi_initialise()
	if dma_iommu_count == 0 {
		print('dma: vinix.iommu=1, but this machine describes no IOMMU\n')
	}
}
