// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module platformfixture

fn test_validation() {
	unsafe {
		mut p := plan()
		p.sid = 2
		reject(&p)
		p = plan()
		p.pool_physical = 0
		reject(&p)
		p = plan()
		p.tables_physical = p.pool_physical + 0x4000
		reject(&p)
		p = plan()
		p.tables_physical = u64(1) << 36
		reject(&p)
		p = plan()
		p.pool_cpu++
		reject(&p)
		p = plan()
		p.config_size = 4096
		reject(&p)
		p = plan()
		p.window_bus = 0xfffff000
		reject(&p)
		p = plan()
		p.seed_len = 0
		reject(&p)
		p = plan()
		p.calibration_len = 0
		reject(&p)
		p = plan()
		p.antenna[0] = 0
		reject(&p)
	}
}

fn test_dart_tables() {
	unsafe {
		reset()
		host().p = plan()
		mut tables := voidptr(0)
		C.assert(C.posix_memalign(&tables, 16384, 32768) == 0)
		host().p.tables_cpu = usize(tables)
		reg_set(host().p.dart, u32(14) << 24)
		C.assert(C.vinix_m1_core_dart_prepare() == 0)
		root := &u64(tables)
		leaf := root + 2048
		for i := u32(0); i < 2048; i++ {
			C.assert(root[i] == if i == 8 { host().p.tables_physical + 16384 + 1 } else { u64(0) })
		}
		for i := u32(0); i < 2048; i++ {
			C.assert(leaf[i] == if i < u32(C.BW_POOL_MIN) / 16384 {
				(host().p.pool_physical + u64(i) * 16384) | 3
			} else {
				u64(0)
			})
		}
		C.assert(reg_get(host().p.dart + 0x210) == (u32(host().p.tables_physical >> 12) | 0x80000000))
		C.assert(reg_get(host().p.dart + 0x104) == 0x80 && reg_get(host().p.dart + 0xfc) == 2)
		C.assert(reg_get(host().p.port + 0x828) == 0x80010100)
		C.assert(sync_calls == 1)
		C.free(tables)
	}
}

fn test_stream_conflict() {
	unsafe {
		reset()
		host().p = plan()
		reg_set(host().p.dart, u32(14) << 24)
		reg_set(host().p.port + 0x828, 0x80010101)
		C.assert(C.vinix_m1_core_dart_prepare() == i32(C.BW_ENOTSUP))
		C.assert(register_writes == 0 && sync_calls == 0)
	}
}

fn test_dart_locked() {
	unsafe {
		reset()
		host().p = plan()
		reg_set(host().p.dart, u32(14) << 24)
		reg_set(host().p.dart + 0x60, 0x8000)
		C.assert(C.vinix_m1_core_dart_prepare() == i32(C.BW_ENOTSUP) && register_writes == 0)
	}
}

fn test_bar_probe() {
	unsafe {
		reset()
		host().endpoint = 0x200000
		probe_bar = host().endpoint + 0x10
		probe_size = 0x4000
		reg_set(probe_bar, 0x80000004)
		reg_set(probe_bar + 4, 0)
		mut size := u64(0)
		C.assert(C.vinix_m1_core_bar_size(0x10, &size) == 0 && size == 0x4000)
		C.assert(reg_get(probe_bar) == 0x80000004 && reg_get(probe_bar + 4) == 0)
	}
}

fn test_stop_revokes() {
	unsafe {
		reset()
		host().p = plan()
		host().endpoint = 0x200000
		host().endpoint_valid = 1
		host().prepared = 1
		reg_set(host().endpoint + 4, 0x406)
		reg_set(host().p.dart + 0x104, 0x80)
		C.vinix_m1_core_stop_dma(nil)
		C.assert(reg_get(host().endpoint + 4) == 0x402)
		C.assert(reg_get(host().p.dart + 0x104) == 0)
		C.assert(reg_get(host().p.dart + 0x34) == 2)
	}
}

fn test_public_stop_after_flush_failure() {
	unsafe {
		reset()
		mut p := plan()
		mut tables := voidptr(0)
		C.assert(C.posix_memalign(&tables, 16384, 32768) == 0)
		p.tables_cpu = usize(tables)
		reg_set(p.phy, 12)
		reg_set(p.port + 0x804, 1)
		reg_set(p.port + 0x208, 1)
		reg_set(p.config + 8, 0x06040000)
		reg_set(p.config + 0x100000, 0x442514e4)
		probe_bar = p.config + 0x100010
		probe_size = 0x4000
		probe_bar2 = p.config + 0x100018
		probe_size2 = 0x400000
		reg_set(probe_bar, 4)
		reg_set(probe_bar2, 4)
		reg_set(p.dart, u32(14) << 24)
		timeout_register = p.dart + 0x20
		C.assert(C.brcm_m1_prepare(&p) == i32(C.BW_ETIME) && host().prepared != 0 && usize(host().dev.ops.stop_dma) == 0)
		C.assert(host().dev.state == i32(C.BW_FAULT) && host().dev.error == i32(C.BW_ETIME))
		C.brcm_m1_stop()
		C.assert(reg_get(p.dart + 0x104) == 0)
		C.brcm_m1_stop()
		C.assert(reg_get(p.dart + 0x104) == 0)
		C.free(tables)
	}
}

fn test_config_bounds() {
	unsafe {
		reset()
		host().bar0_len = 0
		C.assert(C.vinix_m1_core_bus_read(nil, u32(C.BW_REGS), 0, 4) == 0xffffffff && register_reads == 0)
		C.vinix_m1_core_bus_write(nil, u32(C.BW_REGS), 0, 4, 1)
		C.assert(register_writes == 0)
		host().bar0_len = 0x3000
		C.assert(C.vinix_m1_core_bus_read(nil, u32(C.BW_REGS), 0x3000, 4) == 0xffffffff && register_reads == 0)
		C.assert(C.vinix_m1_core_bus_read(nil, u32(C.BW_REGS), 1, 4) == 0xffffffff && register_reads == 0)
	}
}

@[export:'wifi_platform_main']
pub fn fixture_main() i32 {
	test_validation()
	$if wifi_fixture_guest ? {
		C.puts(c'PASS test_validation')
	}
	test_dart_tables()
	$if wifi_fixture_guest ? {
		C.puts(c'PASS test_dart_tables')
	}
	test_stream_conflict()
	$if wifi_fixture_guest ? {
		C.puts(c'PASS test_stream_conflict')
	}
	test_dart_locked()
	$if wifi_fixture_guest ? {
		C.puts(c'PASS test_dart_locked')
	}
	test_bar_probe()
	$if wifi_fixture_guest ? {
		C.puts(c'PASS test_bar_probe')
	}
	test_stop_revokes()
	$if wifi_fixture_guest ? {
		C.puts(c'PASS test_stop_revokes')
	}
	test_public_stop_after_flush_failure()
	$if wifi_fixture_guest ? {
		C.puts(c'PASS test_public_stop_after_flush_failure')
	}
	test_config_bounds()
	$if wifi_fixture_guest ? {
		C.puts(c'PASS test_config_bounds')
	}
	C.puts(c'8 platform policy groups passed (simulated MMIO, not hardware)')
	return 0
}
