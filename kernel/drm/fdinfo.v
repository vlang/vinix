// SPDX-License-Identifier: GPL-2.0-or-later
@[has_globals]
module drm

// The DRM lines of /proc/<pid>/fdinfo/<fd>, as Linux's drm_show_fdinfo() and
// drm_print_memory_stats() print them; see the kernel's
// Documentation/gpu/drm-usage-stats.rst. Monitoring tools read these.

import file
import drm.ioctl
import katomic
import lib
import resource
import usercopy

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

fn ioctl_set_client_name(handle voidptr, data voidptr) int {
	if handle == unsafe { nil } || data == unsafe { nil } { return -22 }
	request := unsafe { &ioctl.DrmSetClientName(data) }
	if request.name_len > file.drm_client_name_max_len { return -22 }
	mut name := [file.drm_client_name_max_len]u8{}
	if request.name_len != 0 {
		if request.name == 0 || request.name_len - 1 > ~request.name
			|| !usercopy.copy_from_user(unsafe { &name[0] }, request.name, request.name_len) {
			return -14
		}
		for i in 0 .. int(request.name_len) {
			if name[i] < 0x21 || name[i] > 0x7e { return -22 }
		}
	}
	mut description := unsafe { &file.Handle(handle) }
	description.l.acquire()
	description.drm_client_name = name
	description.drm_client_name_len = u8(request.name_len)
	description.l.release()
	return 0
}

// Append the lines for a DRM node or PRIME export. The caller keeps the
// description referenced, which keeps the driver's file state alive.
pub fn add_fdinfo(handle voidptr, mut text lib.Text) {
	if handle == unsafe { nil } { return }
	mut description := unsafe { &file.Handle(handle) }
	// An O_PATH descriptor is not a DRM file; Linux gives it no DRM lines.
	if description.flags & resource.o_path != 0 { return }
	mut res := description.resource
	if res == unsafe { nil } { return }
	if mut res is GemPrimeResource {
		// Exclude the temporary reference held by the procfs reader.
		refs := katomic.load(&description.refcount) - 1
		add_dma_buf_lines(mut text, u64(res.stat.size), refs)
		if res.obj != unsafe { nil } {
			mut obj := unsafe { res.obj }
			obj.lock.acquire()
			name := obj.prime_name
			length := int(obj.prime_name_len)
			obj.lock.release()
			if length != 0 {
				text.add('name:\t')
				text.add(unsafe { tos(&name[0], length - 1) })
				text.add_byte(`\n`)
			}
		}
		return
	}
	if mut res is DrmNode {
		dev := res.dev
		if dev == unsafe { nil } || dev.driver == unsafe { nil } || !dev.is_registered() { return }
		add_client_lines(mut text, dev.driver.name, description.drm_client_id)
		add_client_name(mut description, mut text)
		if dev.driver.memory_stats == unsafe { nil } { return }
		stats := dev.driver.memory_stats(dev, handle) or { return }
		add_memory_stats(mut text, stats, 'system')
	}
}

fn add_client_name(mut description file.Handle, mut text lib.Text) {
	description.l.acquire()
	length := int(description.drm_client_name_len)
	name := description.drm_client_name
	description.l.release()
	if length == 0 { return }
	text.add('drm-client-name:\t')
	text.add(unsafe { tos(&name[0], length) })
	text.add_byte(`\n`)
}

// drm_show_fdinfo(): the driver and the client. A platform device has no
// drm-pdev line.
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

fn add_dma_buf_lines(mut text lib.Text, size u64, refs int) {
	text.add('size:\t')
	text.add_unsigned(size)
	text.add('\ncount:\t')
	text.add_decimal(i64(refs))
	text.add('\nexp_name:\tdrm\n')
}
