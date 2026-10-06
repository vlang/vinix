// SPDX-License-Identifier: GPL-2.0-only
// Independent TAS/I2C/ADMAC machine and double-precision thermal oracle.
@[has_globals; translated]
module model

#include "fixture-native-abi.h"

type Read32 = fn (voidptr, u64) u32
type Write32 = fn (voidptr, u64, u32)
type Now = fn (voidptr) u64
type Delay = fn (voidptr, u32)
type Cache = fn (voidptr, u64, u32)
type Power = fn (voidptr, u32, i32) i32

struct C.spk_io {
mut:
	read32     Read32
	write32    Write32
	now_us     Now
	delay_us   Delay
	clean      Cache
	invalidate Cache
	power      Power
	cookie     voidptr
}

struct C.speaker_model {
mut:
	coil        i64
	magnet      i64
	coil_hyst   i64
	magnet_hyst i64
	gain_mdb    i32
}

struct C.speaker_event {
mut:
	code i32
	a    i32
	b    i32
}

struct C.speakers {
mut:
	io          C.spk_io
	state       i32
	clocks_on   i32
	powered     u32
	rate        u32
	written     u64
	played      u64
	volume      u32
	model       [2]C.speaker_model
	live        [2]i32
	verified    i32
	underruns   u64
	events      [16]C.speaker_event
	event_head  u32
	event_count u32
}

struct C.vinix_apple_speakers_config {
mut:
	mca_clusters      u64
	mca_cluster_count u32
	mca_switch        u64
	admac             u64
	admac_channels    u32
	nco               u64
	nco_channels      u32
	nco_ref_hz        u32
	tx_cluster        u32
	sense_cluster     u32
	tx_nco            u32
	sense_nco         u32
	tx_dma            u32
	sense_dma         u32
	port_mask         u32
	i2c               [2]u64
	i2c_ref_hz        u32
	amp_address       [2]u8
	imon_slot         [2]u8
	vmon_slot         [2]u8
	shutdown_gpio     u64
	tx_buffer         u64
	tx_iova           u64
	tx_bytes          u32
	sense_buffer      u64
	sense_iova        u64
	sense_bytes       u32
}

struct C.vinix_apple_speakers_status {
mut:
	model_gain_mdb i32
	coil_mc        [2]i32
}

@[typedef]
struct C.FILE {}

@[c_extern]
__global C.stderr &C.FILE

fn C.assert(bool)
fn C.malloc(usize) voidptr
fn C.realloc(voidptr, usize) voidptr
fn C.aligned_alloc(usize, usize) voidptr
fn C.free(voidptr)
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memmove(voidptr, voidptr, usize) voidptr
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.getenv(&char) &char
fn C.printf(&char, ...) i32
fn C.fprintf(&C.FILE, &char, ...) i32
fn C.pow(f64, f64) f64
fn C.exp(f64) f64
fn C.fmin(f64, f64) f64
fn C.fmax(f64, f64) f64
fn C.log10(f64) f64
fn C.log2(f64) f64
fn C.fabs(f64) f64
fn C.lrint(f64) i64
fn C.sin(f64) f64
fn C.abs(i32) i32
fn C.fflush(voidptr) i32
fn C.pause() i32
fn C.speaker_fixture_io_read(voidptr, u64) u32
fn C.speaker_fixture_io_write(voidptr, u64, u32)
fn C.speaker_fixture_io_now(voidptr) u64
fn C.speaker_fixture_io_delay(voidptr, u32)
fn C.speaker_fixture_io_cache(voidptr, u64, u32)
fn C.speaker_fixture_io_power(voidptr, u32, i32) i32
fn C.vinix_spk_core_log2_q16(u64) i64
fn C.vinix_spk_core_db_to_power_q32(i32) u64
fn C.vinix_spk_core_min_gain_mdb() i32
fn C.vinix_spk_core_lfsr_step(u32) u32
fn C.vinix_spk_core_nco_div_register(u32) u32
fn C.vinix_spk_core_nco_set_rate(&C.speakers, u32, u32) i32
fn C.vinix_spk_core_c_init(&C.speakers, &C.vinix_apple_speakers_config) i32
fn C.vinix_spk_core_configure(&C.speakers, u32) i32
fn C.vinix_spk_core_reserve(&C.speakers, &u32) &u8
fn C.vinix_spk_core_commit(&C.speakers, u32)
fn C.vinix_spk_core_wants_start(&C.speakers) i32
fn C.vinix_spk_core_start_clocks(&C.speakers) i32
fn C.vinix_spk_core_start_stream(&C.speakers) i32
fn C.vinix_spk_core_service(&C.speakers) u32
fn C.vinix_spk_core_take_event(&C.speakers, &C.speaker_event) i32
fn C.vinix_spk_core_drain(&C.speakers)
fn C.vinix_spk_core_drained(&C.speakers) i32
fn C.vinix_spk_core_stop(&C.speakers)
fn C.vinix_spk_core_get_status(&C.speakers, &C.vinix_apple_speakers_status)
fn C.vinix_spk_core_model_rate(&C.speakers)
fn C.vinix_spk_core_model_run(&C.speakers, u32, &i16, u32, &i32) i32
fn C.vinix_spk_core_model_cool(&C.speakers, u64)
fn C.vinix_spk_core_fault_shutdown(&C.speakers)

const fake_mca = u64(0x10000000)
const fake_switch = u64(0x11000000)
const fake_admac = u64(0x12000000)
const fake_nco = u64(0x13000000)
const fake_i2c0 = u64(0x14000000)
const fake_i2c1 = u64(0x14100000)
const fake_gpio = u64(0x15000000 + 181 * 4)
const tx_ch = u32(4)
const sense_ch = u32(11)
const mode_normal = i32(0)
const mode_dead = i32(1)
const mode_inverted = i32(2)
const mode_stalled = i32(3)

fn chan_base(channel u32) u32 { return 0x8000 + channel * 0x200 }

fn chan_intmask(index u32) u32 { return 0x20 + index * 4 }

fn desc_write(channel u32) u32 { return 0x10000 + (channel / 2) * 4 + (channel & 1) * 0x4000 }

fn report_read(channel u32) u32 { return 0x10100 + (channel / 2) * 4 + (channel & 1) * 0x4000 }

fn q32(value i64) i64 { return value << 32 }

struct FakeAmp {
mut:
	regs          [128]u8
	address       u8
	resets        i32
	fail_writes   i32
	writes_to_dvc i32
}

struct FakeBus {
mut:
	amp          &FakeAmp
	smsta        u32
	rx           [16]u32
	rx_count     i32
	selected     i32
	reading      i32
	have_pointer i32
	pointer      u8
	nack         i32
	ctl          u32
}

struct FakeDesc {
mut:
	address u64
	length  u32
}

struct FakeChan {
mut:
	ring         [4]FakeDesc
	count        i32
	words        [4]u32
	nwords       i32
	reports      i32
	report_words i32
	running      i32
	progress     u32
	starved      u64
}

@[c_extern]
__global (
	C.ADMAC_IRQ_INDEX            u32
	C.ADMAC_RX_SRAM_SIZE         u32
	C.ADMAC_RX_START             u32
	C.ADMAC_RX_STOP              u32
	C.ADMAC_TX_SRAM_SIZE         u32
	C.ADMAC_TX_START             u32
	C.ADMAC_TX_STOP              u32
	C.AMP_LEVEL                  u32
	C.ATT_MUTE                   i32
	C.ATT_SAFE                   i32
	C.CHAN_BUS_WIDTH             u32
	C.CHAN_CARVEOUT              u32
	C.CHAN_CTL                   u32
	C.CHAN_DESC_RING             u32
	C.CHAN_REPORT_RING           u32
	C.CHAN_RESIDUE               u32
	C.CHAN_RST_RINGS             u32
	C.CONF_NO_FEEDBACK           u32
	C.CONF_UNK1                  u32
	C.CONF_UNK2                  u32
	C.CONF_UNK3                  u32
	C.CONF_WIDTH_16              u32
	C.CONF_WIDTH_32              u32
	C.CTL_EN                     u32
	C.CTL_MRR                    u32
	C.CTL_MTR                    u32
	C.CTL_UJM                    u32
	C.DESC_NOTIFY                u32
	C.GPIO_DATA                  u32
	C.GPIO_MODE_MASK             u32
	C.GPIO_MODE_OUT              u32
	C.I2C_CTL                    u32
	C.I2C_MRXFIFO                u32
	C.I2C_MTXFIFO                u32
	C.I2C_REV                    u32
	C.I2C_SMSTA                  u32
	C.LFSR_INIT                  u32
	C.LFSR_SIZE                  u32
	C.MAX_EVENTS                 u32
	C.MCA_MCLK_CONF              u32
	C.MCA_MCLK_EN                u32
	C.MCA_PORT_CLOCK_SEL         u32
	C.MCA_PORT_DATA_SEL          u32
	C.MCA_PORT_ENABLES           u32
	C.MCA_RXB                    u32
	C.MCA_STATUS                 u32
	C.MCA_STRIDE                 u32
	C.MCA_SYNCGEN_EN             u32
	C.MCA_SYNCGEN_HI             u32
	C.MCA_SYNCGEN_LO             u32
	C.MCA_SYNCGEN_SEL            u32
	C.MCA_SYNCGEN_STATUS         u32
	C.MCA_TXA                    u32
	C.MRX_EMPTY                  u32
	C.MTX_READ                   u32
	C.MTX_START                  u32
	C.MTX_STOP                   u32
	C.M_PI                       f64
	C.NCO_ACCINIT                u32
	C.NCO_CTRL                   u32
	C.NCO_DIV                    u32
	C.NCO_ENABLE                 u32
	C.NCO_INC1                   u32
	C.NCO_INC2                   u32
	C.NCO_STRIDE                 u32
	C.PERIOD_FRAMES              u32
	C.PORT_CLOCKS                u32
	C.PWR_ACTIVE                 u32
	C.PWR_SHUTDOWN               u32
	C.RING_EMPTY                 u32
	C.RING_FULL                  u32
	C.RX_CONF                    u32
	C.RX_PORT                    u32
	C.RX_SLOTMASK                u32
	C.SERDES_EN                  u32
	C.SERDES_RST                 u32
	C.SERDES_STATUS              u32
	C.SM_MTE                     u32
	C.SM_MTN                     u32
	C.SM_XEN                     u32
	C.SPK_EV_AMP                 i32
	C.SPK_EV_DEAD                i32
	C.SPK_EV_FAULT_I2C           i32
	C.SPK_EV_FAULT_POWER         i32
	C.SPK_EV_FAULT_TEMP          i32
	C.SPK_EV_GAIN                i32
	C.SPK_EV_POWER               i32
	C.SPK_EV_STALE               i32
	C.SPK_EV_VERIFIED            i32
	C.SRAM_BLOCK                 u32
	C.ST_FAULT                   i32
	C.ST_IDLE                    i32
	C.ST_RUNNING                 i32
	C.TAS_PLAY_CFG0              u32
	C.TAS_PLAY_CFG2              u32
	C.TAS_PWR_CTRL               u32
	C.TAS_REV                    u32
	C.TAS_SW_RST                 u32
	C.TAS_TDM0                   u32
	C.TAS_TDM1                   u32
	C.TAS_TDM2                   u32
	C.TAS_TDM3                   u32
	C.TAS_TDM5                   u32
	C.TAS_TDM6                   u32
	C.TX_BITSTART                u32
	C.TX_CONF                    u32
	C.TX_PERIOD_BYTES            u32
	C.TX_SLOTMASK                u32
	C.VINIX_SPK_SERVICE_DRAINED  u32
	C.VINIX_SPK_SERVICE_FAULT    u32
	C.VINIX_SPK_SERVICE_IDLE     u32
	C.VINIX_SPK_SERVICE_PROGRESS u32
)

__global (
	tests           = u32(0)
	reg_key         [4096]u64
	reg_val         [4096]u32
	amps            [2]FakeAmp
	buses           [2]FakeBus
	chans           [24]FakeChan
	now             = u64(0)
	frac_frames     = u64(0)
	sense_mode      = i32(0)
	played          &i16
	played_count    = usize(0)
	played_capacity = usize(0)
	peak_voltage    = f64(8.92)
	sut             C.speakers
	domain_on       [6]i32
	fail_power_on   = i32(0)
	fail_power_off  = i32(0)
	tx_memory       &u8
	sense_memory    &u8
	tone_phase      = f64(0)
	tone_level      = f64(0.5)
	tone_hz         = f64(1000)
)

fn reg_slot(address u64) &u32 {
	unsafe {
		mut slot := u32((address * u64(0x9e3779b97f4a7c15)) >> 52) % 4096
		for reg_key[slot] != 0 && reg_key[slot] != address { slot = (slot + 1) % 4096 }
		reg_key[slot] = address
		return &reg_val[slot]
	}
}

fn reg_get(address u64) u32 {
	unsafe { return *reg_slot(address)
	 }
}

fn reg_set(address u64, value u32) {
	unsafe { *reg_slot(address) = value }
}

fn amp_defaults(amp &FakeAmp) {
	unsafe {
		C.memset(&amp.regs[0], 0, sizeof(amp.regs))
		amp.regs[u32(C.TAS_PWR_CTRL)] = 0x0e
		amp.regs[u32(C.TAS_PLAY_CFG0)] = 0x10
		amp.regs[u32(C.TAS_PLAY_CFG2)] = 0
		amp.regs[u32(C.TAS_TDM0)] = 0x09
		amp.regs[u32(C.TAS_TDM1)] = 0x02
		amp.regs[u32(C.TAS_TDM2)] = 0x0a
		amp.regs[u32(C.TAS_TDM3)] = 0x10
		amp.regs[0x0e] = 0x13
		amp.regs[u32(C.TAS_TDM5)] = 0x02
		amp.regs[u32(C.TAS_TDM6)] = 0
		amp.regs[u32(C.TAS_REV)] = 0x21
	}
}

fn bus_write(bus &FakeBus, offset u64, value u32) {
	unsafe {
		if offset == u32(C.I2C_SMSTA) {
			bus.smsta &= ~value
			return
		}
		if offset == u32(C.I2C_CTL) {
			bus.ctl = value
			if (value & u32(C.CTL_MRR)) != 0 { bus.rx_count = 0 }
			return
		}
		if offset != u32(C.I2C_MTXFIFO) { return }
		if (value & u32(C.MTX_START)) != 0 {
			address := u8((value >> 1) & 0x7f)
			bus.selected = if address == bus.amp.address { 1 } else { 0 }
			bus.reading = i32(value & 1)
			if bus.selected == 0 { bus.nack = 1 }
			if bus.reading == 0 { bus.have_pointer = 0 }
			return
		}
		if (value & u32(C.MTX_READ)) != 0 {
			count := value & 0xff
			for i := u32(0); i < count && bus.selected != 0; i++ {
				bus.rx[bus.rx_count] = bus.amp.regs[(u32(bus.pointer) + i) & 0x7f]
				bus.rx_count++
			}
		} else if bus.selected != 0 {
			byte := u8(value)
			if bus.have_pointer == 0 {
				bus.pointer = byte
				bus.have_pointer = 1
			} else if bus.amp.fail_writes != 0 {
				bus.nack = 1
			} else {
				bus.amp.regs[bus.pointer & 0x7f] = byte
				if bus.pointer == u32(C.TAS_SW_RST) && (byte & 1) != 0 {
					amp_defaults(bus.amp)
					bus.amp.resets++
				}
				if bus.pointer == u32(C.TAS_PLAY_CFG2) { bus.amp.writes_to_dvc++ }
				bus.pointer++
			}
		}
		if (value & u32(C.MTX_STOP)) != 0 {
			bus.smsta |= u32(C.SM_XEN) | (if bus.nack != 0 { u32(C.SM_MTN) } else { u32(0) })
			bus.nack = 0
			bus.selected = 0
		}
	}
}

fn bus_read(bus &FakeBus, offset u64) u32 {
	unsafe {
		if offset == u32(C.I2C_SMSTA) { return bus.smsta | u32(C.SM_MTE) }
		if offset == u32(C.I2C_REV) { return 7 }
		if offset == u32(C.I2C_MRXFIFO) {
			if bus.rx_count == 0 { return u32(C.MRX_EMPTY) }
			value := bus.rx[0]
			C.memmove(&bus.rx[0], &bus.rx[1], usize(bus.rx_count - 1) * sizeof(bus.rx[0]))
			bus.rx_count--
			return value
		}
		return 0
	}
}

fn admac_write(offset u64, value u32) {
	unsafe {
		if offset == u32(C.ADMAC_TX_START) || offset == u32(C.ADMAC_RX_START) || offset == u32(C.ADMAC_TX_STOP) || offset == u32(C.ADMAC_RX_STOP) {
			for i := u32(0); i < 12; i++ {
				if (value & (u32(1) << i)) == 0 { continue }
				index := i * 2 + (if offset == u32(C.ADMAC_RX_START) || offset == u32(C.ADMAC_RX_STOP) {
					u32(1)
				} else {
					u32(0)
				})
				chans[index].running = if offset == u32(C.ADMAC_TX_START) || offset == u32(C.ADMAC_RX_START) {
					1
				} else {
					0
				}
			}
			return
		}
		if offset >= 0x10000 && offset < 0x10100 + 0x4000 + 0x100 {
			for i := u32(0); i < 24; i++ {
				if offset == desc_write(i) {
					channel := &chans[i]
					channel.words[channel.nwords] = value
					channel.nwords++
					if channel.nwords == 4 {
						C.assert(channel.count < 4)
						C.assert(channel.words[3] == u32(C.DESC_NOTIFY))
						channel.ring[channel.count].address = u64(channel.words[0]) | (u64(channel.words[1]) << 32)
						channel.ring[channel.count].length = channel.words[2]
						channel.count++
						channel.nwords = 0
					}
					return
				}
			}
		}
		for i := u32(0); i < 24; i++ {
			if offset == chan_base(i) + u32(C.CHAN_CTL) && (value & u32(C.CHAN_RST_RINGS)) != 0 {
				chans[i].count = 0
				chans[i].reports = 0
				chans[i].nwords = 0
				chans[i].report_words = 0
				chans[i].progress = 0
				return
			}
		}
		reg_set(fake_admac + offset, value)
	}
}

fn admac_read(offset u64) u32 {
	unsafe {
		if offset == u32(C.ADMAC_TX_SRAM_SIZE) || offset == u32(C.ADMAC_RX_SRAM_SIZE) {
			return 0x4000
		}
		for i := u32(0); i < 24; i++ {
			channel := &chans[i]
			if offset == chan_base(i) + u32(C.CHAN_DESC_RING) {
				return (if channel.count == 4 { u32(C.RING_FULL) } else { u32(0) }) | (if channel.count == 0 {
					u32(C.RING_EMPTY)
				} else {
					u32(0)
				})
			}
			if offset == chan_base(i) + u32(C.CHAN_REPORT_RING) {
				return if channel.reports != 0 { u32(0) } else { u32(C.RING_EMPTY) }
			}
			if offset == chan_base(i) + u32(C.CHAN_RESIDUE) {
				return if channel.count != 0 {
					channel.ring[0].length - channel.progress
				} else {
					u32(0)
				}
			}
			if offset == report_read(i) {
				C.assert(channel.reports > 0)
				channel.report_words++
				if channel.report_words == 4 {
					channel.report_words = 0
					channel.reports--
				}
				return 0
			}
		}
		return reg_get(fake_admac + offset)
	}
}

fn amp_voltage(index i32, sample i16) f64 {
	unsafe {
		amp := &amps[index]
		if (amp.regs[u32(C.TAS_PWR_CTRL)] & 3) != u32(C.PWR_ACTIVE) || (reg_get(fake_gpio) & u32(C.GPIO_DATA)) == 0 {
			return 0
		}
		level := C.pow(10.0, (11.0 + 0.5 * f64(amp.regs[u32(C.TAS_PLAY_CFG0)] & 0x1f) - 16.0) / 20.0)
		attenuation := C.pow(10.0, -0.5 * f64(amp.regs[u32(C.TAS_PLAY_CFG2)]) / 20.0)
		return f64(sample) / 32768.0 * peak_voltage * level * attenuation
	}
}

fn quantize(value f64, full_scale f64) i16 {
	unsafe {
		mut lsb := value / full_scale * 32768.0
		if lsb > 32767 { lsb = 32767 }
		if lsb < -32768 { lsb = -32768 }
		return i16(C.lrint(lsb))
	}
}

fn hw_frames(frames u64) {
	unsafe {
		tx := &chans[tx_ch]
		rx := &chans[sense_ch]
		mut remaining := frames
		for remaining != 0 {
			remaining--
			mut out := [i16(0), i16(0)]!
			mut volts := [2]f64{}
			if tx.running != 0 {
				if tx.count != 0 {
					p := &i16(usize(tx.ring[0].address + tx.progress))
					out[0] = p[0]
					out[1] = p[1]
					tx.progress += 4
					if tx.progress == tx.ring[0].length {
						C.memmove(&tx.ring[0], &tx.ring[1], 3 * sizeof(tx.ring[0]))
						tx.count--
						tx.progress = 0
						tx.reports++
						C.assert(tx.reports <= 4)
					}
				} else {
					tx.starved++
				}
				if played_count + 2 > played_capacity {
					played_capacity = if played_capacity != 0 {
						played_capacity * 2
					} else {
						usize(1) << 16
					}
					played = &i16(C.realloc(played, played_capacity * sizeof(i16)))
				}
				played[played_count] = out[0]
				played_count++
				played[played_count] = out[1]
				played_count++
			}
			for i := i32(0); i < 2; i++ { volts[i] = amp_voltage(i, out[i]) }
			if rx.running != 0 && rx.count != 0 && sense_mode != mode_stalled {
				p := &i16(usize(rx.ring[0].address + rx.progress))
				for i := i32(0); i < 2; i++ {
					voltage := if sense_mode == mode_dead { f64(0) } else { volts[i] }
					mut current := voltage / 4.9
					if sense_mode == mode_inverted { current = -current }
					p[i * 2] = quantize(current, 3.75)
					p[i * 2 + 1] = quantize(voltage, 14.0)
				}
				rx.progress += 8
				if rx.progress == rx.ring[0].length {
					C.memmove(&rx.ring[0], &rx.ring[1], 3 * sizeof(rx.ring[0]))
					rx.count--
					rx.progress = 0
					rx.reports++
					C.assert(rx.reports <= 4)
				}
			}
		}
	}
}

fn advance(us u64) {
	unsafe {
		rate := if sut.rate != 0 { u64(sut.rate) } else { u64(48000) }
		total := us * rate + frac_frames
		now += us
		frac_frames = total % 1000000
		hw_frames(total / 1000000)
	}
}

fn tx_clock_runs() bool {
	return (reg_get(fake_nco + u32(C.NCO_STRIDE) + u32(C.NCO_CTRL)) & u32(C.NCO_ENABLE)) != 0
}

fn sense_clock_runs() bool {
	return tx_clock_runs() && (reg_get(fake_mca + u32(C.MCA_PORT_ENABLES)) & u32(C.PORT_CLOCKS)) != 0
}

@[export: 'speaker_fixture_io_power']
pub fn io_power(cookie voidptr, cluster u32, on i32) i32 {
	unsafe {
		C.assert(cluster == 1 || cluster == 2)
		C.assert(if cluster == 1 { tx_clock_runs() } else { sense_clock_runs() })
		if (if on != 0 { fail_power_on } else { fail_power_off }) != 0 { return 0 }
		domain_on[cluster] = on
		return 1
	}
}

fn check_cluster_access(address u64) {
	unsafe {
		cluster := u32((address - fake_mca) / u32(C.MCA_STRIDE))
		offset := u32((address - fake_mca) % u32(C.MCA_STRIDE))
		if offset >= u32(C.MCA_PORT_ENABLES) && offset <= u32(C.MCA_PORT_DATA_SEL) { return }
		C.assert(cluster < 6 && domain_on[cluster] != 0)
	}
}

@[export: 'speaker_fixture_io_read']
pub fn io_read(cookie voidptr, address u64) u32 {
	unsafe {
		if address >= fake_i2c0 && address < fake_i2c0 + 0x4000 {
			return bus_read(&buses[0], address - fake_i2c0)
		}
		if address >= fake_i2c1 && address < fake_i2c1 + 0x4000 {
			return bus_read(&buses[1], address - fake_i2c1)
		}
		if address >= fake_admac && address < fake_admac + 0x34000 {
			return admac_read(address - fake_admac)
		}
		if address >= fake_mca && address < fake_mca + 0x18000 {
			offset := u32((address - fake_mca) % u32(C.MCA_STRIDE))
			check_cluster_access(address)
			value := reg_get(address)
			if offset == u32(C.MCA_TXA) + u32(C.SERDES_STATUS) || offset == u32(C.MCA_RXB) + u32(C.SERDES_STATUS) {
				reg_set(address, value & ~u32(C.SERDES_RST))
				return value & ~u32(C.SERDES_RST)
			}
			return value
		}
		return reg_get(address)
	}
}

@[export: 'speaker_fixture_io_write']
pub fn io_write(cookie voidptr, address u64, value u32) {
	unsafe {
		if address >= fake_i2c0 && address < fake_i2c0 + 0x4000 {
			bus_write(&buses[0], address - fake_i2c0, value)
			return
		}
		if address >= fake_i2c1 && address < fake_i2c1 + 0x4000 {
			bus_write(&buses[1], address - fake_i2c1, value)
			return
		}
		if address >= fake_admac && address < fake_admac + 0x34000 {
			admac_write(address - fake_admac, value)
			return
		}
		if address >= fake_mca && address < fake_mca + 0x18000 { check_cluster_access(address) }
		reg_set(address, value)
	}
}

@[export: 'speaker_fixture_io_now']
pub fn io_now(cookie voidptr) u64 { return now }

@[export: 'speaker_fixture_io_delay']
pub fn io_delay(cookie voidptr, us u32) { advance(us) }

@[export: 'speaker_fixture_io_cache']
pub fn io_cache(cookie voidptr, address u64, length u32) {}

fn machine_config() C.vinix_apple_speakers_config {
	unsafe {
		mut cfg := C.vinix_apple_speakers_config{}
		C.memset(&cfg, 0, sizeof(cfg))
		cfg.mca_clusters = fake_mca
		cfg.mca_cluster_count = 6
		cfg.mca_switch = fake_switch
		cfg.admac = fake_admac
		cfg.admac_channels = 24
		cfg.nco = fake_nco
		cfg.nco_channels = 5
		cfg.nco_ref_hz = 900000000
		cfg.tx_cluster = 1
		cfg.sense_cluster = 2
		cfg.tx_nco = 1
		cfg.sense_nco = 2
		cfg.tx_dma = tx_ch
		cfg.sense_dma = sense_ch
		cfg.port_mask = 3
		cfg.i2c[0] = fake_i2c0
		cfg.i2c[1] = fake_i2c1
		cfg.i2c_ref_hz = 24000000
		cfg.amp_address[0] = 0x31
		cfg.amp_address[1] = 0x34
		cfg.imon_slot[0] = 0
		cfg.vmon_slot[0] = 2
		cfg.imon_slot[1] = 4
		cfg.vmon_slot[1] = 6
		cfg.shutdown_gpio = fake_gpio
		cfg.tx_buffer = u64(usize(tx_memory))
		cfg.tx_iova = cfg.tx_buffer
		cfg.tx_bytes = 16384
		cfg.sense_buffer = u64(usize(sense_memory))
		cfg.sense_iova = cfg.sense_buffer
		cfg.sense_bytes = 32768
		return cfg
	}
}

fn bind_io() C.spk_io {
	return C.spk_io{ read32: C.speaker_fixture_io_read, write32: C.speaker_fixture_io_write, now_us: C.speaker_fixture_io_now, delay_us: C.speaker_fixture_io_delay, clean: C.speaker_fixture_io_cache, invalidate: C.speaker_fixture_io_cache, power: C.speaker_fixture_io_power, cookie: voidptr(0) }
}

fn boot() {
	unsafe {
		C.memset(&reg_key[0], 0, sizeof(reg_key))
		C.memset(&reg_val[0], 0, sizeof(reg_val))
		C.memset(&chans[0], 0, sizeof(chans))
		C.memset(&buses[0], 0, sizeof(buses))
		C.memset(&sut, 0, sizeof(sut))
		C.memset(&domain_on[0], 0, sizeof(domain_on))
		fail_power_on = 0
		fail_power_off = 0
		amp_defaults(&amps[0])
		amp_defaults(&amps[1])
		amps[0].address = 0x31
		amps[1].address = 0x34
		amps[0].resets = 0
		amps[1].resets = 0
		amps[0].fail_writes = 0
		amps[1].fail_writes = 0
		amps[0].writes_to_dvc = 0
		amps[1].writes_to_dvc = 0
		buses[0].amp = &amps[0]
		buses[1].amp = &amps[1]
		if tx_memory == nil {
			tx_memory = &u8(C.aligned_alloc(16384, 16384))
			sense_memory = &u8(C.aligned_alloc(16384, 32768))
		}
		C.memset(tx_memory, 0x55, 16384)
		C.memset(sense_memory, 0x55, 32768)
		now = 1000000
		frac_frames = 0
		played_count = 0
		sense_mode = mode_normal
		sut.io = bind_io()
		mut cfg := machine_config()
		C.assert(C.vinix_spk_core_c_init(&sut, &cfg) == 1)
	}
}

fn feed(max_bytes u32) u32 {
	unsafe {
		mut total := u32(0)
		for {
			mut count := u32(0)
			p := C.vinix_spk_core_reserve(&sut, &count)
			if count == 0 || total >= max_bytes {
				C.vinix_spk_core_commit(&sut, 0)
				return total
			}
			if count > max_bytes - total { count = max_bytes - total }
			count &= ~u32(3)
			if count == 0 {
				C.vinix_spk_core_commit(&sut, 0)
				return total
			}
			for i := u32(0); i < count; i += 4 {
				mut sample := i16(C.lrint(C.sin(tone_phase) * tone_level * 32767))
				tone_phase += 2 * f64(C.M_PI) * tone_hz / f64(sut.rate)
				C.memcpy(p + i, &sample, 2)
				C.memcpy(p + i + 2, &sample, 2)
			}
			C.vinix_spk_core_commit(&sut, count)
			total += count
		}
		return 0
	}
}

fn pump(us u64, keep_feeding i32) u32 {
	unsafe {
		mut flags := u32(0)
		end := now + us
		for now < end {
			if keep_feeding != 0 { feed(~u32(0)) }
			if C.vinix_spk_core_wants_start(&sut) != 0 {
				C.assert(C.vinix_spk_core_start_clocks(&sut) == 1)
				C.assert(C.vinix_spk_core_start_stream(&sut) == 1)
			}
			flags |= C.vinix_spk_core_service(&sut)
			advance(2000)
		}
		return flags
	}
}

fn count_events(code i32) i32 {
	unsafe {
		mut count := i32(0)
		for i := u32(0); i < sut.event_count; i++ {
			if sut.events[(sut.event_head + i) % u32(C.MAX_EVENTS)].code == code { count++ }
		}
		return count
	}
}

fn clear_events() {
	unsafe {
		mut event := C.speaker_event{}
		for C.vinix_spk_core_take_event(&sut, &event) != 0 { continue }
	}
}

struct Reference {
mut:
	coil        f64
	magnet      f64
	coil_hyst   f64
	magnet_hyst f64
	gain        f64
	min_gain    f64
}

fn reference_init(reference &Reference) {
	unsafe {
		max_power := (120.0 - 50.0) / (36.0 + 29.0)
		peak_power := C.pow(10.0, 16.0 / 10.0) / 4.9 * 2.0
		reference.coil = 120.0 - 20.0 - 1.0
		reference.magnet = 50.0 + (reference.coil - 50.0) * (36.0 / (36.0 + 29.0))
		reference.coil_hyst = 0
		reference.magnet_hyst = 0
		reference.gain = 0
		reference.min_gain = C.fmin(10.0 * C.log10(max_power / peak_power), 0.0)
	}
}

fn reference_run(reference &Reference, buffer &i16, frames u32, voltage_slot i32, current_slot i32, rate f64) {
	unsafe {
		step := 1.0 / rate
		alpha_coil := step / (2.4 + step)
		alpha_magnet := step / (80.0 + step)
		for frame := u32(0); frame < frames; frame++ {
			voltage := f64(buffer[frame * 4 + voltage_slot]) / 32768.0 * 14.0
			current := f64(buffer[frame * 4 + current_slot]) / 32768.0 * 3.75
			power := voltage * current
			coil_target := reference.magnet + power * 29.0
			magnet_target := 50.0 + power * 36.0
			reference.coil = coil_target * alpha_coil + reference.coil * (1 - alpha_coil)
			reference.magnet = magnet_target * alpha_magnet + reference.magnet * (1 - alpha_magnet)
		}
		reference.coil_hyst = C.fmin(C.fmax(reference.coil_hyst, reference.coil), reference.coil + 5.0)
		reference.magnet_hyst = C.fmin(C.fmax(reference.magnet_hyst, reference.magnet), reference.magnet + 5.0)
		temperature := C.fmax(reference.coil_hyst, reference.magnet_hyst)
		reduction := (temperature - (120.0 - 20.0)) / 20.0
		reference.gain = reference.min_gain * C.fmax(reduction, 0.0)
		if reference.gain > -0.01 { reference.gain = 0 }
	}
}

fn reference_skip(reference &Reference, time f64) {
	unsafe {
		coil := reference.coil - 50.0
		magnet := reference.magnet - 50.0
		eta := 1.0 / (1.0 - 2.4 / 80.0)
		a := C.exp(-time / 2.4) * (coil - eta * magnet)
		b := C.exp(-time / 80.0) * magnet
		reference.coil = 50.0 + a + b * eta
		reference.magnet = 50.0 + b
	}
}

fn q32_to_c(value i64) f64 { return f64(value) / 4294967296.0 }
