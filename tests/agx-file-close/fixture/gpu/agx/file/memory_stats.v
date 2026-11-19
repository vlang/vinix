// SPDX-License-Identifier: GPL-2.0-or-later
module file

import drm
import drm.gem
import drm.ioctl
import gpu.agx.gpu

// The fdinfo totals count what a client created, as Asahi's do: not what it
// imported, and all of it resident, since Vinix allocates backing at creation.
fn check_memory_stats() {
	gpu.set_running(true)
	creator_key := u64(0x5100)
	importer_key := u64(0x5200)
	mut creator := &GpuFile{ client_serial: 41 }
	mut importer := &GpuFile{ client_serial: 42 }
	file_map[creator_key] = creator
	file_map[importer_key] = importer
	device := drm.DrmDevice{}
	// A description that has made no request yet has nothing to report.
	empty := memory_stats_handle(&device, voidptr(u64(0x5300))) or { panic('stats without a file') }
	assert empty.private == 0 && empty.shared == 0 && empty.resident == 0
	assert empty.supported == drm.memory_stats_resident

	mut first := ioctl.DrmAsahiGemCreate{ size: 0x10000 }
	assert creator.ioctl_gem_create(&first) == 0
	mut second := ioctl.DrmAsahiGemCreate{ size: 0x4001 }
	assert creator.ioctl_gem_create(&second) == 0
	mut stats := memory_stats_handle(&device, voidptr(creator_key)) or { panic('creator stats') }
	assert stats.private == 0x18000 && stats.resident == 0x18000 && stats.shared == 0
	assert stats.supported == drm.memory_stats_resident

	// An imported object counts for its creator only.
	shared := creator.objects.table.find(first.handle) or { panic('created object') }
	assert shared.creator == 41
	imported_handle := importer.objects.import_object(shared) or { panic('import') }
	stats = memory_stats_handle(&device, voidptr(importer_key)) or { panic('importer stats') }
	assert stats.private == 0 && stats.resident == 0
	mut own := ioctl.DrmAsahiGemCreate{ size: 0x4000 }
	assert importer.ioctl_gem_create(&own) == 0
	stats = memory_stats_handle(&device, voidptr(importer_key)) or { panic('importer stats') }
	assert stats.private == 0x4000 && stats.resident == 0x4000
	stats = memory_stats_handle(&device, voidptr(creator_key)) or { panic('creator stats') }
	assert stats.private == 0x18000

	// Once the creator closes its handle the object leaves its total, even
	// while the importer keeps it. Asahi would still count it for the creator.
	closed := creator.objects.table.remove(first.handle) or { panic('close') }
	gem.unref(closed)
	stats = memory_stats_handle(&device, voidptr(creator_key)) or { panic('creator stats') }
	assert stats.private == 0x8000 && stats.resident == 0x8000
	stats = memory_stats_handle(&device, voidptr(importer_key)) or { panic('importer stats') }
	assert stats.private == 0x4000

	for handle in [second.handle] {
		object := creator.objects.table.remove(handle) or { panic('created') }
		gem.unref(object)
	}
	for handle in [imported_handle, own.handle] {
		object := importer.objects.table.remove(handle) or { panic('imported') }
		gem.unref(object)
	}
	creator.objects.table.release_all()
	importer.objects.table.release_all()
	file_map.delete(creator_key)
	file_map.delete(importer_key)
	assert gem.live() == 0 && !creator.lock.is_held() && !importer.lock.is_held()
	println('AGX fdinfo memory: created objects counted resident, imports left to their creator, closed handles dropped')
}
