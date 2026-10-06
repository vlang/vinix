// SPDX-License-Identifier: GPL-2.0-only
// Original independent assertions and double-precision oracle, in V.
@[has_globals; translated]
module model

__global (
	reference_chunk   [2048]i16
	temperature_chunk [2048]i16
)

fn test_fixed_point_math() {
	unsafe {
		for x := u64(1); x < (u64(1) << 62); x = x * 3 + 7 {
			want := C.log2(f64(x))
			got := f64(C.vinix_spk_core_log2_q16(x)) / 65536.0
			C.assert(C.fabs(got - want) < 1e-4)
		}
		for mdb := i32(-110000); mdb <= 20000; mdb += 137 {
			want := C.pow(10.0, f64(mdb) / 10000.0)
			got := f64(C.vinix_spk_core_db_to_power_q32(mdb)) / 4294967296.0
			C.assert(C.fabs(got - want) <= want * 2e-4 + 1e-9)
		}
		mut reference := Reference{}
		reference_init(&reference)
		C.assert(C.abs(C.vinix_spk_core_min_gain_mdb() - i32(C.lrint(reference.min_gain * 1000))) <= 3)
		C.assert(C.vinix_spk_core_min_gain_mdb() < -11700 && C.vinix_spk_core_min_gain_mdb() > -11900)
		tests++
	}
}

fn test_nco() {
	unsafe {
		mut forward := [2048]u16{}
		mut inverse := [2048]u16{}
		mut state := u32(C.LFSR_INIT)
		rates := [u32(12288000), u32(11289600)]!
		for i := i32(C.LFSR_SIZE) - 1; i > 0; i-- {
			state = C.vinix_spk_core_lfsr_step(state)
			forward[i] = u16(state)
			inverse[state] = u16(i)
		}
		forward[0] = 0
		inverse[0] = 0
		for divisor := u32(8); divisor < 4 * (2 + u32(C.LFSR_SIZE)); divisor++ {
			want := (u32(forward[divisor / 4 - 2]) << 2) | (divisor % 4)
			C.assert(C.vinix_spk_core_nco_div_register(divisor) == want)
		}
		boot()
		for r := u32(0); r < 2; r++ {
			base := fake_nco + u32(C.NCO_STRIDE)
			C.assert(C.vinix_spk_core_nco_set_rate(&sut, 1, rates[r]) == 0)
			register := reg_get(base + u32(C.NCO_DIV))
			inc1 := reg_get(base + u32(C.NCO_INC1))
			inc2 := reg_get(base + u32(C.NCO_INC2))
			divisor := (u32(inverse[(register >> 2) & 0x7ff]) + 2) * 4 + (register & 3)
			incbase := inc1 - inc2
			got := 900000000.0 * 2 * f64(incbase) / (f64(divisor) * f64(incbase) + f64(inc1))
			C.assert(C.fabs(got - f64(rates[r])) < 1.0)
			C.assert(reg_get(base + u32(C.NCO_ACCINIT)) == u32(1) << 31)
		}
		tests++
	}
}

fn test_amplifier_setup() {
	unsafe {
		boot()
		for i := i32(0); i < 2; i++ {
			r := &amps[i].regs[0]
			C.assert(amps[i].resets == 1)
			C.assert((r[u32(C.TAS_PLAY_CFG0)] & 0x1f) == u32(C.AMP_LEVEL))
			C.assert(r[u32(C.TAS_PLAY_CFG2)] == i32(C.ATT_MUTE))
			C.assert((r[u32(C.TAS_PWR_CTRL)] & 0x0f) == u32(C.PWR_SHUTDOWN))
			C.assert(r[u32(C.TAS_TDM1)] == 0x03)
			C.assert((r[u32(C.TAS_TDM2)] & 0x3f) == 0x12)
			C.assert(r[u32(C.TAS_TDM3)] == (if i != 0 { u8(0x11) } else { u8(0) }))
			C.assert(r[0x0e] == 0x13)
			C.assert(r[u32(C.TAS_TDM5)] == (if i != 0 { u8(0x46) } else { u8(0x42) }))
			C.assert(r[u32(C.TAS_TDM6)] == (if i != 0 { u8(0x44) } else { u8(0x40) }))
		}
		C.assert((reg_get(fake_gpio) & (u32(C.GPIO_MODE_MASK) | u32(C.GPIO_DATA))) == (u32(C.GPIO_MODE_OUT) | u32(C.GPIO_DATA)))
		C.assert(buses[0].ctl == (u32(C.CTL_MTR) | u32(C.CTL_MRR) | u32(C.CTL_UJM) | u32(C.CTL_EN) | 15))
		C.assert(buses[1].ctl == buses[0].ctl)
		C.assert(reg_get(fake_admac + chan_base(tx_ch) + u32(C.CHAN_CARVEOUT)) == u32(C.SRAM_BLOCK) << 16)
		C.assert((reg_get(fake_admac + chan_base(tx_ch) + u32(C.CHAN_BUS_WIDTH)) & 0xff) == 0x11)
		C.assert((reg_get(fake_admac + chan_base(sense_ch) + u32(C.CHAN_BUS_WIDTH)) & 0xff) == 0x21)
		C.assert(count_events(i32(C.SPK_EV_AMP)) == 2)
		C.memset(&sut, 0, sizeof(sut))
		amps[1].address = 0x35
		sut.io = bind_io()
		mut cfg := machine_config()
		C.assert(C.vinix_spk_core_c_init(&sut, &cfg) == 0)
		C.assert((reg_get(fake_gpio) & u32(C.GPIO_DATA)) == 0)
		tests++
	}
}

fn test_stream_registers() {
	unsafe {
		tx := fake_mca + u32(C.MCA_STRIDE)
		sense := fake_mca + 2 * u32(C.MCA_STRIDE)
		boot()
		C.assert(C.vinix_spk_core_configure(&sut, 48000) == 1)
		feed(3 * u32(C.TX_PERIOD_BYTES))
		C.assert(C.vinix_spk_core_wants_start(&sut) != 0)
		C.assert(C.vinix_spk_core_start_clocks(&sut) == 1)
		C.assert(domain_on[1] != 0 && domain_on[2] == 0)
		C.assert(C.vinix_spk_core_start_stream(&sut) == 1)
		C.assert(domain_on[1] != 0 && domain_on[2] != 0)
		C.assert((reg_get(tx + u32(C.MCA_TXA) + u32(C.TX_CONF)) & 0x7ffff) == (7 | u32(C.CONF_WIDTH_32) | (u32(2) << 16) | u32(C.CONF_UNK1) | u32(C.CONF_UNK2) | u32(C.CONF_UNK3)))
		C.assert(reg_get(tx + u32(C.MCA_TXA) + u32(C.TX_BITSTART)) == 1)
		C.assert(reg_get(tx + u32(C.MCA_TXA) + u32(C.TX_SLOTMASK) + 4) == ~u32(3))
		C.assert(reg_get(tx + u32(C.MCA_TXA) + u32(C.TX_SLOTMASK) + 0xc) == ~u32(0xff))
		C.assert(reg_get(tx + u32(C.MCA_TXA) + u32(C.SERDES_STATUS)) == u32(C.SERDES_EN))
		C.assert(reg_get(fake_switch + 0x8000) == 0x205050)
		C.assert(reg_get(tx + u32(C.MCA_SYNCGEN_HI)) == 127 && reg_get(tx + u32(C.MCA_SYNCGEN_LO)) == 127)
		C.assert(reg_get(tx + u32(C.MCA_SYNCGEN_SEL)) == 2)
		C.assert((reg_get(tx + u32(C.MCA_SYNCGEN_STATUS)) & u32(C.MCA_SYNCGEN_EN)) != 0)
		C.assert((reg_get(tx + u32(C.MCA_STATUS)) & u32(C.MCA_MCLK_EN)) != 0)
		C.assert(reg_get(tx + u32(C.MCA_MCLK_CONF)) == 0x100)
		for port_index := u32(0); port_index < 2; port_index++ {
			port := fake_mca + port_index * u32(C.MCA_STRIDE)
			C.assert(reg_get(port + u32(C.MCA_PORT_DATA_SEL)) == 4)
			C.assert(reg_get(port + u32(C.MCA_PORT_CLOCK_SEL)) == 0x200)
			C.assert(reg_get(port + u32(C.MCA_PORT_ENABLES)) == 0xe)
		}
		C.assert((reg_get(sense + u32(C.MCA_RXB) + u32(C.RX_CONF)) & 0x7ffff) == (15 | u32(C.CONF_WIDTH_16) | (u32(3) << 16) | u32(C.CONF_UNK1) | u32(C.CONF_UNK2) | u32(C.CONF_NO_FEEDBACK)))
		C.assert(reg_get(sense + u32(C.MCA_RXB) + u32(C.RX_PORT)) == 3)
		C.assert(reg_get(sense + u32(C.MCA_RXB) + u32(C.RX_SLOTMASK) + 4) == ~u32(0xf))
		C.assert(reg_get(sense + u32(C.MCA_SYNCGEN_SEL)) == 7)
		C.assert(reg_get(sense + u32(C.MCA_RXB) + u32(C.SERDES_STATUS)) == u32(C.SERDES_EN))
		C.assert(reg_get(fake_switch + 0x10000 + 0x4000) == 0x405050)
		C.assert((reg_get(fake_nco + u32(C.NCO_STRIDE) + u32(C.NCO_CTRL)) & u32(C.NCO_ENABLE)) != 0)
		C.assert(chans[tx_ch].running != 0 && chans[sense_ch].running != 0)
		C.assert(chans[tx_ch].count >= 3 && chans[sense_ch].count == 4)
		C.assert(reg_get(fake_admac + chan_base(tx_ch) + chan_intmask(u32(C.ADMAC_IRQ_INDEX))) == 0)
		C.assert(reg_get(fake_admac + chan_base(sense_ch) + chan_intmask(u32(C.ADMAC_IRQ_INDEX))) == 0)
		C.assert(amps[0].regs[u32(C.TAS_PWR_CTRL)] == u32(C.PWR_ACTIVE) && amps[1].regs[u32(C.TAS_PWR_CTRL)] == u32(C.PWR_ACTIVE))
		C.assert(amps[0].regs[u32(C.TAS_PLAY_CFG2)] == i32(C.ATT_SAFE))
		C.assert(amps[0].regs[u32(C.TAS_TDM0)] == 0x06)
		C.vinix_spk_core_stop(&sut)
		C.assert(domain_on[1] == 0 && domain_on[2] == 0 && sut.powered == 0)
		C.assert(chans[tx_ch].running == 0 && chans[sense_ch].running == 0)
		C.assert((amps[0].regs[u32(C.TAS_PWR_CTRL)] & 3) == u32(C.PWR_SHUTDOWN))
		C.assert(amps[1].regs[u32(C.TAS_PLAY_CFG2)] == i32(C.ATT_MUTE))
		C.assert((reg_get(tx + u32(C.MCA_STATUS)) & u32(C.MCA_MCLK_EN)) == 0)
		C.assert((reg_get(fake_nco + u32(C.NCO_STRIDE) + u32(C.NCO_CTRL)) & u32(C.NCO_ENABLE)) == 0)
		C.assert(reg_get(fake_mca + u32(C.MCA_PORT_ENABLES)) == 0)
		C.assert(sut.state == i32(C.ST_IDLE))
		C.assert(C.vinix_spk_core_configure(&sut, 44100) == 1)
		feed(3 * u32(C.TX_PERIOD_BYTES))
		C.vinix_spk_core_start_clocks(&sut)
		C.vinix_spk_core_start_stream(&sut)
		C.assert(amps[1].regs[u32(C.TAS_TDM0)] == 0x26)
		C.assert(C.vinix_spk_core_configure(&sut, 32000) == 0)
		tests++
	}
}

fn test_playback_is_exact() {
	unsafe {
		boot()
		C.assert(C.vinix_spk_core_configure(&sut, 48000) == 1)
		tone_phase = 0.5
		tone_level = 0.25
		mut flags := pump(1000000, 1)
		C.assert((flags & u32(C.VINIX_SPK_SERVICE_PROGRESS)) != 0)
		C.assert((flags & u32(C.VINIX_SPK_SERVICE_FAULT)) == 0)
		C.assert(sut.underruns == 0)
		C.assert(chans[tx_ch].starved == 0)
		total := sut.written
		C.vinix_spk_core_drain(&sut)
		flags = pump(200000, 0)
		C.assert((flags & u32(C.VINIX_SPK_SERVICE_DRAINED)) != 0)
		C.assert(C.vinix_spk_core_drained(&sut) != 0)
		C.assert(sut.played >= total)
		expected := &i16(C.malloc(usize(total / 2) * sizeof(i16)))
		tone_phase = 0.5
		for i := usize(0); i < total / 4; i++ {
			value := i16(C.lrint(C.sin(tone_phase) * tone_level * 32767))
			tone_phase += 2 * f64(C.M_PI) * tone_hz / 48000
			expected[2 * i] = value
			expected[2 * i + 1] = value
		}
		mut first := usize(0)
		for first < played_count && played[first] == 0 {
			first++
			continue
		}
		first &= ~usize(1)
		C.assert(played_count - first >= total / 2)
		C.assert(C.memcmp(played + first, expected, usize(total)) == 0)
		C.free(expected)
		tests++
	}
}

fn test_verification_releases_hold() {
	unsafe {
		boot()
		C.vinix_spk_core_configure(&sut, 48000)
		tone_level = 0.3
		pump(40000, 1)
		C.assert(sut.state == i32(C.ST_RUNNING))
		C.assert(amps[0].regs[u32(C.TAS_PLAY_CFG2)] == i32(C.ATT_SAFE))
		start := now
		for sut.verified == 0 && now - start < 1000000 { pump(2000, 1) }
		C.assert(sut.verified != 0)
		C.assert(now - start < 300000)
		C.assert(count_events(i32(C.SPK_EV_VERIFIED)) == 1)
		C.assert(amps[0].regs[u32(C.TAS_PLAY_CFG2)] > 30)
		pump(400000, 1)
		C.assert(amps[0].regs[u32(C.TAS_PLAY_CFG2)] == 0 && amps[1].regs[u32(C.TAS_PLAY_CFG2)] == 0)
		C.assert(sut.live[0] != 0 && sut.live[1] != 0)
		tests++
	}
}

fn test_dead_sense_keeps_hold() {
	unsafe {
		boot()
		sense_mode = mode_dead
		C.vinix_spk_core_configure(&sut, 48000)
		tone_level = 0.5
		pump(2000000, 1)
		C.assert(sut.verified == 0)
		C.assert(amps[0].regs[u32(C.TAS_PLAY_CFG2)] >= i32(C.ATT_SAFE))
		C.assert(amps[1].regs[u32(C.TAS_PLAY_CFG2)] >= i32(C.ATT_SAFE))
		C.assert(count_events(i32(C.SPK_EV_DEAD)) >= 1)
		C.assert(sut.state == i32(C.ST_RUNNING))
		tests++
	}
}

fn test_silence_does_not_verify() {
	unsafe {
		boot()
		C.vinix_spk_core_configure(&sut, 48000)
		tone_level = 0.0
		pump(1000000, 1)
		C.assert(sut.verified == 0)
		C.assert(amps[0].regs[u32(C.TAS_PLAY_CFG2)] == i32(C.ATT_SAFE))
		tests++
	}
}

fn test_stale_sense_restores_hold() {
	unsafe {
		boot()
		C.vinix_spk_core_configure(&sut, 48000)
		tone_level = 0.3
		pump(800000, 1)
		C.assert(sut.verified != 0 && amps[0].regs[u32(C.TAS_PLAY_CFG2)] == 0)
		sense_mode = mode_stalled
		start := now
		for amps[0].regs[u32(C.TAS_PLAY_CFG2)] < i32(C.ATT_SAFE) && now - start < 1000000 {
			pump(2000, 1)
		}
		C.assert(amps[0].regs[u32(C.TAS_PLAY_CFG2)] >= i32(C.ATT_SAFE))
		C.assert(now - start >= 250000 && now - start < 300000)
		C.assert(count_events(i32(C.SPK_EV_STALE)) == 1)
		sense_mode = mode_normal
		pump(800000, 1)
		C.assert(sut.verified != 0 && amps[0].regs[u32(C.TAS_PLAY_CFG2)] == 0)
		tests++
	}
}

fn test_negative_power_faults() {
	unsafe {
		boot()
		sense_mode = mode_inverted
		C.vinix_spk_core_configure(&sut, 48000)
		tone_level = 0.5
		pump(200000, 1)
		C.assert(sut.state == i32(C.ST_FAULT))
		C.assert(count_events(i32(C.SPK_EV_FAULT_POWER)) >= 1)
		C.assert((reg_get(fake_gpio) & u32(C.GPIO_DATA)) == 0)
		C.assert((amps[0].regs[u32(C.TAS_PWR_CTRL)] & 3) == u32(C.PWR_SHUTDOWN))
		C.assert(chans[tx_ch].running == 0)
		mut count := u32(0)
		C.assert(C.vinix_spk_core_reserve(&sut, &count) == nil && count == 0)
		C.vinix_spk_core_commit(&sut, 0)
		C.assert(C.vinix_spk_core_configure(&sut, 48000) == 0)
		C.assert(C.vinix_spk_core_service(&sut) == u32(C.VINIX_SPK_SERVICE_FAULT))
		tests++
	}
}

fn test_thermal_limiting() {
	unsafe {
		mut status := C.vinix_apple_speakers_status{}
		boot()
		C.vinix_spk_core_configure(&sut, 48000)
		tone_level = 1.0
		tone_hz = 200
		pump(20000000, 1)
		C.vinix_spk_core_get_status(&sut, &status)
		C.assert(status.model_gain_mdb < -1000)
		limited_attenuation := i32(amps[0].regs[u32(C.TAS_PLAY_CFG2)])
		C.assert(limited_attenuation >= (-status.model_gain_mdb + 499) / 500)
		C.assert(status.coil_mc[0] > 100000 && status.coil_mc[0] < 135000)
		C.assert(sut.state == i32(C.ST_RUNNING))
		C.assert(count_events(i32(C.SPK_EV_GAIN)) >= 1)
		pump(60000000, 1)
		C.vinix_spk_core_get_status(&sut, &status)
		C.assert(status.coil_mc[0] < 125000 && status.coil_mc[1] < 125000)
		C.assert(sut.state == i32(C.ST_RUNNING))
		tone_hz = 1000
		tests++
	}
}

fn test_model_matches_reference() {
	unsafe {
		mut references := [2]Reference{}
		mut seed := u64(12345)
		boot()
		sut.rate = 48000
		C.vinix_spk_core_model_rate(&sut)
		reference_init(&references[0])
		reference_init(&references[1])
		mut limited := i32(0)
		for k := u32(0); k < 48000 * 90 / u32(C.PERIOD_FRAMES); k++ {
			burst := if (k / 400) % 2 != 0 { 0.9 } else { 0.15 }
			for frame := u32(0); frame < u32(C.PERIOD_FRAMES); frame++ {
				for i := u32(0); i < 2; i++ {
					seed = seed * u64(6364136223846793005) + u64(1442695040888963407)
					mut voltage := C.sin(f64(k * u32(C.PERIOD_FRAMES) + frame) * 0.05 * f64(i + 1)) * burst * 14.0 * 0.25
					voltage += (f64(seed >> 40) / f64(1 << 24) - 0.5) * 0.2
					current := voltage / 4.9 * (1.0 + 0.1 * f64(i))
					reference_chunk[frame * 4 + i * 2] = quantize(current, 3.75)
					reference_chunk[frame * 4 + i * 2 + 1] = quantize(voltage, 14.0)
				}
			}
			for i := u32(0); i < 2; i++ {
				mut value := i32(0)
				code := C.vinix_spk_core_model_run(&sut, i, &reference_chunk[0], u32(C.PERIOD_FRAMES), &value)
				C.assert(code == 0)
				reference_run(&references[i], &reference_chunk[0], u32(C.PERIOD_FRAMES), i32(i) * 2 + 1, i32(i) * 2, 48000)
				C.assert(C.fabs(q32_to_c(sut.model[i].coil) - references[i].coil) < 0.005)
				C.assert(C.fabs(q32_to_c(sut.model[i].magnet) - references[i].magnet) < 0.005)
				C.assert(C.abs(sut.model[i].gain_mdb - i32(C.lrint(references[i].gain * 1000))) <= 20)
				limited |= if sut.model[i].gain_mdb < -1000 { 1 } else { 0 }
			}
		}
		C.assert(limited != 0)
		gaps := [f64(0.01), f64(0.5), f64(3), f64(30), f64(600), f64(36000)]!
		for k := u32(0); k < 6; k++ {
			C.vinix_spk_core_model_cool(&sut, u64(gaps[k] * 48000))
			for i := u32(0); i < 2; i++ {
				reference_skip(&references[i], f64(u64(gaps[k] * 48000)) / 48000)
				if C.getenv(c'SPK_DEBUG') != nil {
					C.fprintf(C.stderr, c'gap %g spk %u coil %.6f ref %.6f magnet %.6f ref %.6f\n', gaps[k], i, q32_to_c(sut.model[i].coil), references[i].coil, q32_to_c(sut.model[i].magnet), references[i].magnet)
				}
				C.assert(C.fabs(q32_to_c(sut.model[i].coil) - references[i].coil) < 0.005)
				C.assert(C.fabs(q32_to_c(sut.model[i].magnet) - references[i].magnet) < 0.005)
			}
		}
		C.assert(C.fabs(q32_to_c(sut.model[0].coil) - 50.0) < 0.01)
		tests++
	}
}

fn test_overtemperature_faults() {
	unsafe {
		boot()
		C.vinix_spk_core_configure(&sut, 48000)
		tone_level = 0.3
		pump(100000, 1)
		for frame := u32(0); frame < u32(C.PERIOD_FRAMES); frame++ {
			temperature_chunk[frame * 4] = 32767
			temperature_chunk[frame * 4 + 1] = 32767
			temperature_chunk[frame * 4 + 2] = 0
			temperature_chunk[frame * 4 + 3] = 0
		}
		mut code := i32(0)
		for k := u32(0); k < 10000 && code == 0; k++ {
			mut value := i32(0)
			code = C.vinix_spk_core_model_run(&sut, 0, &temperature_chunk[0], u32(C.PERIOD_FRAMES), &value)
			if code != 0 { C.assert(value > 135000) }
		}
		C.assert(code == i32(C.SPK_EV_FAULT_TEMP))
		tests++
	}
}

fn test_underrun_and_idle() {
	unsafe {
		boot()
		C.vinix_spk_core_configure(&sut, 48000)
		tone_level = 0.25
		pump(300000, 1)
		before := played_count
		mut flags := pump(500000, 0)
		C.assert(sut.underruns > 0)
		C.assert(chans[tx_ch].starved == 0)
		for i := before + 4 * u32(C.TX_PERIOD_BYTES); i < played_count; i++ {
			C.assert(played[i] == 0)
		}
		C.assert((flags & u32(C.VINIX_SPK_SERVICE_IDLE)) == 0)
		flags = pump(3000000, 0)
		C.assert((flags & u32(C.VINIX_SPK_SERVICE_IDLE)) != 0)
		tests++
	}
}

fn test_software_volume() {
	unsafe {
		boot()
		C.vinix_spk_core_configure(&sut, 48000)
		sut.volume = 50
		mut count := u32(0)
		p := &i16(C.vinix_spk_core_reserve(&sut, &count))
		C.assert(count >= 8)
		p[0] = 1000
		p[1] = -2000
		p[2] = 32767
		p[3] = -32768
		C.vinix_spk_core_commit(&sut, 8)
		C.assert(p[0] == 500 && p[1] == -1000 && p[2] == 16383 && p[3] == -16384)
		tests++
	}
}

fn test_lost_attenuation_faults() {
	unsafe {
		boot()
		C.vinix_spk_core_configure(&sut, 48000)
		tone_level = 0.3
		pump(800000, 1)
		C.assert(sut.verified != 0 && amps[0].regs[u32(C.TAS_PLAY_CFG2)] == 0)
		amps[1].fail_writes = 1
		sense_mode = mode_stalled
		pump(400000, 1)
		C.assert(sut.state == i32(C.ST_FAULT))
		C.assert((reg_get(fake_gpio) & u32(C.GPIO_DATA)) == 0)
		C.assert(count_events(i32(C.SPK_EV_FAULT_I2C)) >= 1)
		tests++
	}
}

fn test_abandoned_start_stops_clocks() {
	unsafe {
		tx := fake_mca + u32(C.MCA_STRIDE)
		boot()
		C.vinix_spk_core_configure(&sut, 48000)
		feed(3 * u32(C.TX_PERIOD_BYTES))
		C.assert(C.vinix_spk_core_start_clocks(&sut) != 0)
		C.assert((reg_get(fake_nco + u32(C.NCO_STRIDE) + u32(C.NCO_CTRL)) & u32(C.NCO_ENABLE)) != 0)
		C.vinix_spk_core_stop(&sut)
		C.assert((reg_get(fake_nco + u32(C.NCO_STRIDE) + u32(C.NCO_CTRL)) & u32(C.NCO_ENABLE)) == 0)
		C.assert(reg_get(fake_mca + u32(C.MCA_PORT_ENABLES)) == 0)
		C.assert((reg_get(tx + u32(C.MCA_STATUS)) & u32(C.MCA_MCLK_EN)) == 0)
		C.vinix_spk_core_configure(&sut, 48000)
		feed(3 * u32(C.TX_PERIOD_BYTES))
		C.assert(C.vinix_spk_core_start_clocks(&sut) != 0)
		C.vinix_spk_core_fault_shutdown(&sut)
		C.assert(sut.state == i32(C.ST_FAULT) && sut.clocks_on == 0)
		C.assert(domain_on[1] == 0 && domain_on[2] == 0)
		C.assert((reg_get(fake_nco + u32(C.NCO_STRIDE) + u32(C.NCO_CTRL)) & u32(C.NCO_ENABLE)) == 0)
		C.assert((reg_get(fake_gpio) & u32(C.GPIO_DATA)) == 0)
		tests++
	}
}

fn test_streams_cycle_cluster_power() {
	unsafe {
		boot()
		tone_level = 0.1
		for pass := i32(0); pass < 3; pass++ {
			before := played_count
			C.vinix_spk_core_configure(&sut, 48000)
			pump(200000, 1)
			C.assert(sut.state == i32(C.ST_RUNNING) && domain_on[1] != 0 && domain_on[2] != 0)
			C.vinix_spk_core_drain(&sut)
			for C.vinix_spk_core_drained(&sut) == 0 { pump(2000, 0) }
			C.vinix_spk_core_stop(&sut)
			C.assert(sut.state == i32(C.ST_IDLE) && domain_on[1] == 0 && domain_on[2] == 0)
			C.assert(!tx_clock_runs() && sut.clocks_on == 0)
			C.assert(played_count > before + 2 * 48000 / 10)
			advance(2000000)
		}
		C.assert(count_events(i32(C.SPK_EV_POWER)) == 0)
		clear_events()
		tests++
	}
}

fn test_cluster_power_failures() {
	unsafe {
		mut event := C.speaker_event{}
		boot()
		clear_events()
		C.vinix_spk_core_configure(&sut, 48000)
		feed(3 * u32(C.TX_PERIOD_BYTES))
		fail_power_on = 1
		C.assert(C.vinix_spk_core_start_clocks(&sut) == 0)
		C.assert(C.vinix_spk_core_take_event(&sut, &event) != 0 && event.code == i32(C.SPK_EV_POWER) && event.a == 1 && event.b == 1)
		C.vinix_spk_core_fault_shutdown(&sut)
		C.assert(!tx_clock_runs() && domain_on[1] == 0 && domain_on[2] == 0)
		C.assert(reg_get(fake_mca + u32(C.MCA_PORT_ENABLES)) == 0)
		boot()
		clear_events()
		C.vinix_spk_core_configure(&sut, 48000)
		feed(3 * u32(C.TX_PERIOD_BYTES))
		C.assert(C.vinix_spk_core_start_clocks(&sut) == 1)
		fail_power_on = 1
		C.assert(C.vinix_spk_core_start_stream(&sut) == 0)
		C.assert(C.vinix_spk_core_take_event(&sut, &event) != 0 && event.code == i32(C.SPK_EV_POWER) && event.a == 2 && event.b == 1)
		C.vinix_spk_core_stop(&sut)
		C.assert(!tx_clock_runs() && domain_on[1] == 0 && domain_on[2] == 0)
		boot()
		clear_events()
		C.vinix_spk_core_configure(&sut, 48000)
		pump(100000, 1)
		clear_events()
		fail_power_off = 1
		C.vinix_spk_core_stop(&sut)
		C.assert(count_events(i32(C.SPK_EV_POWER)) == 2 && sut.powered == 0 && !tx_clock_runs())
		clear_events()
		fail_power_off = 0
		C.vinix_spk_core_configure(&sut, 48000)
		pump(100000, 1)
		C.assert(sut.state == i32(C.ST_RUNNING) && domain_on[1] != 0 && domain_on[2] != 0)
		tests++
	}
}

fn test_idle_cooling_between_streams() {
	unsafe {
		boot()
		C.vinix_spk_core_configure(&sut, 48000)
		tone_level = 0.3
		pump(500000, 1)
		C.vinix_spk_core_stop(&sut)
		before := sut.model[0].coil
		advance(60000000)
		C.vinix_spk_core_configure(&sut, 48000)
		feed(3 * u32(C.TX_PERIOD_BYTES))
		C.vinix_spk_core_start_clocks(&sut)
		C.assert(sut.model[0].coil < before - q32(5))
		clear_events()
		tests++
	}
}

@[export: 'speaker_fixture_main']
pub fn fixture_main() i32 {
	unsafe {
		test_fixed_point_math()
		$if speakers_guest ? {
			C.printf(c'apple-speakers: fixed_point_math ok\n')
		}
		test_nco()
		$if speakers_guest ? {
			C.printf(c'apple-speakers: nco ok\n')
		}
		test_amplifier_setup()
		$if speakers_guest ? {
			C.printf(c'apple-speakers: amplifier_setup ok\n')
		}
		test_stream_registers()
		$if speakers_guest ? {
			C.printf(c'apple-speakers: stream_registers ok\n')
		}
		test_playback_is_exact()
		$if speakers_guest ? {
			C.printf(c'apple-speakers: playback_is_exact ok\n')
		}
		test_verification_releases_hold()
		$if speakers_guest ? {
			C.printf(c'apple-speakers: verification_releases_hold ok\n')
		}
		test_dead_sense_keeps_hold()
		$if speakers_guest ? {
			C.printf(c'apple-speakers: dead_sense_keeps_hold ok\n')
		}
		test_silence_does_not_verify()
		$if speakers_guest ? {
			C.printf(c'apple-speakers: silence_does_not_verify ok\n')
		}
		test_stale_sense_restores_hold()
		$if speakers_guest ? {
			C.printf(c'apple-speakers: stale_sense_restores_hold ok\n')
		}
		test_negative_power_faults()
		$if speakers_guest ? {
			C.printf(c'apple-speakers: negative_power_faults ok\n')
		}
		test_thermal_limiting()
		$if speakers_guest ? {
			C.printf(c'apple-speakers: thermal_limiting ok\n')
		}
		test_model_matches_reference()
		$if speakers_guest ? {
			C.printf(c'apple-speakers: model_matches_reference ok\n')
		}
		test_overtemperature_faults()
		$if speakers_guest ? {
			C.printf(c'apple-speakers: overtemperature_faults ok\n')
		}
		test_underrun_and_idle()
		$if speakers_guest ? {
			C.printf(c'apple-speakers: underrun_and_idle ok\n')
		}
		test_software_volume()
		$if speakers_guest ? {
			C.printf(c'apple-speakers: software_volume ok\n')
		}
		test_lost_attenuation_faults()
		$if speakers_guest ? {
			C.printf(c'apple-speakers: lost_attenuation_faults ok\n')
		}
		test_idle_cooling_between_streams()
		$if speakers_guest ? {
			C.printf(c'apple-speakers: idle_cooling_between_streams ok\n')
		}
		test_abandoned_start_stops_clocks()
		$if speakers_guest ? {
			C.printf(c'apple-speakers: abandoned_start_stops_clocks ok\n')
		}
		test_streams_cycle_cluster_power()
		$if speakers_guest ? {
			C.printf(c'apple-speakers: streams_cycle_cluster_power ok\n')
		}
		test_cluster_power_failures()
		$if speakers_guest ? {
			C.printf(c'apple-speakers: cluster_power_failures ok\n')
		}
		C.free(played)
		C.printf(c'apple-speakers: %u tests passed\n', tests)
		return 0
	}
}
