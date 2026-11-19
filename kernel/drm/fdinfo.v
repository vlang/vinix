// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module drm

// The DRM lines of /proc/<pid>/fdinfo/<fd>, as Linux's drm_show_fdinfo() and
// drm_print_memory_stats() print them; see the kernel's
// Documentation/gpu/drm-usage-stats.rst. Monitoring tools read these.

import file
import klock
import lib
import resource

// What a client's memory is, in bytes. A driver fills in what it can tell;
// `supported` says which of the optional keys to print.
pub struct MemoryStats {
pub:
	shared    u64 // shared with other clients; part of the total
	private   u64 // private to this client; part of the total
	resident  u64
	purgeable u64
	active    u64
	supported u32 // memory_stats_* bits
}

// Linux's DRM_GEM_OBJECT_RESIDENT, _PURGEABLE and _ACTIVE.
pub const memory_stats_resident = u32(1)
pub const memory_stats_purgeable = u32(2)
pub const memory_stats_active = u32(4)

// Linux numbers every DRM file from one counter when it is opened. Vinix has no
// per-open DRM state, so a description gets its number the first time fdinfo
// shows it, and keeps it until it is closed.
__global (
	drm_client_lock    klock.Lock
	drm_client_ids     = map[u64]u64{}
	drm_last_client_id = u64(0)
)

fn drm_client_id(handle voidptr) u64 {
	key := u64(handle)
	drm_client_lock.acquire()
	defer { drm_client_lock.release() }
	if id := drm_client_ids[key] { return id }
	drm_last_client_id++
	drm_client_ids[key] = drm_last_client_id
	return drm_last_client_id
}

// Called when the description is released, before its address can be reused.
fn forget_drm_client(handle voidptr) {
	key := u64(handle)
	drm_client_lock.acquire()
	drm_client_ids.delete(key)
	drm_client_lock.release()
}

// Append the DRM lines for an open description of a DRM node. The caller keeps
// the description referenced, which keeps the driver's file state alive.
pub fn add_fdinfo(handle voidptr, mut text lib.Text) {
	if handle == unsafe { nil } { return }
	description := unsafe { &file.Handle(handle) }
	// An O_PATH descriptor is not a DRM file; Linux gives it no DRM lines.
	if description.flags & resource.o_path != 0 { return }
	mut res := description.resource
	if res == unsafe { nil } { return }
	if mut res is DrmNode {
		dev := res.dev
		if dev == unsafe { nil } || dev.driver == unsafe { nil } || !dev.is_registered() { return }
		add_client_lines(mut text, dev.driver.name, drm_client_id(handle))
		if dev.driver.memory_stats == unsafe { nil } { return }
		stats := dev.driver.memory_stats(dev, handle) or { return }
		add_memory_stats(mut text, stats, 'system')
	}
}

// drm_show_fdinfo(): the driver and the client. A platform device has no
// drm-pdev line, and Vinix has no client names.
fn add_client_lines(mut text lib.Text, driver string, client u64) {
	text.add('drm-driver:\t')
	text.add(driver)
	text.add('\ndrm-client-id:\t')
	text.add_unsigned(client)
	text.add_byte(`\n`)
}

fn add_memory_stats(mut text lib.Text, stats MemoryStats, region string) {
	add_fdinfo_size(mut text, 'total', region, stats.private + stats.shared)
	add_fdinfo_size(mut text, 'shared', region, stats.shared)
	if stats.supported & memory_stats_active != 0 {
		add_fdinfo_size(mut text, 'active', region, stats.active)
	}
	if stats.supported & memory_stats_resident != 0 {
		add_fdinfo_size(mut text, 'resident', region, stats.resident)
	}
	if stats.supported & memory_stats_purgeable != 0 {
		add_fdinfo_size(mut text, 'purgeable', region, stats.purgeable)
	}
}

// drm_fdinfo_print_size(): KiB or MiB only while the size divides evenly.
fn add_fdinfo_size(mut text lib.Text, stat string, region string, size u64) {
	mut value := size
	mut unit := 0
	for unit < 2 && value != 0 && value % 1024 == 0 {
		value /= 1024
		unit++
	}
	text.add('drm-')
	text.add(stat)
	text.add_byte(`-`)
	text.add(region)
	text.add(':\t')
	text.add_unsigned(value)
	if unit == 1 {
		text.add(' KiB')
	} else if unit == 2 {
		text.add(' MiB')
	}
	text.add_byte(`\n`)
}
