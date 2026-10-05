@[translated]
module spkcore

#include "apple_speakers.h"
#include "apple_platform_io.h"

// 128-bit integers (C `__int128`)
pub struct SpkWide128 {
pub mut:
	lo u64
	hi u64
}

@[export: 'vinix_spk_core_wide_unsigned']
pub fn wide_unsigned(v u64) SpkWide128 {
	unsafe {
		return SpkWide128{
			lo: v
		}
	}
}

@[export: 'vinix_spk_core_wide_signed']
pub fn wide_signed(v i64) SpkWide128 {
	unsafe {
		return SpkWide128{
			lo: u64(v)
			hi: if v < 0 { u64(-1) } else { 0 }
		}
	}
}

@[export: 'vinix_spk_core_wide_add']
pub fn wide_add(a SpkWide128, b SpkWide128) SpkWide128 {
	unsafe {
		lo := a.lo + b.lo
		return SpkWide128{
			lo: lo
			hi: a.hi + b.hi + (if lo < a.lo { u64(1) } else { u64(0) })
		}
	}
}

@[export: 'vinix_spk_core_wide_mul_words']
pub fn wide_mul_words(x u64, y u64) SpkWide128 {
	unsafe {
		x0 := x & 0xffffffff
		x1 := x >> 32
		y0 := y & 0xffffffff
		y1 := y >> 32
		w0 := x0 * y0
		t := x1 * y0 + (w0 >> 32)
		w1 := (t & 0xffffffff) + x0 * y1
		return SpkWide128{
			lo: x * y
			hi: x1 * y1 + (t >> 32) + (w1 >> 32)
		}
	}
}

@[export: 'vinix_spk_core_wide_multiply']
pub fn wide_multiply(a SpkWide128, b SpkWide128) SpkWide128 {
	unsafe {
		p := wide_mul_words(a.lo, b.lo)
		return SpkWide128{
			lo: p.lo
			hi: p.hi + a.lo * b.hi + a.hi * b.lo
		}
	}
}

@[export: 'vinix_spk_core_wide_shift_left']
pub fn wide_shift_left(a SpkWide128, n int) SpkWide128 {
	unsafe {
		s := n & 127
		if s == 0 {
			return a
		}
		if s >= 64 {
			return SpkWide128{
				hi: a.lo << (s - 64)
			}
		}
		return SpkWide128{
			lo: a.lo << s
			hi: (a.hi << s) | (a.lo >> (64 - s))
		}
	}
}

@[export: 'vinix_spk_core_wide_shift_right']
pub fn wide_shift_right(a SpkWide128, n int) SpkWide128 {
	unsafe {
		s := n & 127
		if s == 0 {
			return a
		}
		if s >= 64 {
			return SpkWide128{
				lo: a.hi >> (s - 64)
			}
		}
		return SpkWide128{
			lo: (a.lo >> s) | (a.hi << (64 - s))
			hi: a.hi >> s
		}
	}
}

// Arithmetic shift of a signed value.
@[export: 'vinix_spk_core_wide_arithmetic_right']
pub fn wide_arithmetic_right(a SpkWide128, n int) SpkWide128 {
	unsafe {
		s := n & 127
		if s == 0 {
			return a
		}
		sign_bits := if i64(a.hi) < 0 { u64(-1) } else { u64(0) }
		if s >= 64 {
			return SpkWide128{
				lo: u64(i64(a.hi) >> (s - 64))
				hi: sign_bits
			}
		}
		return SpkWide128{
			lo: (a.lo >> s) | (a.hi << (64 - s))
			hi: u64(i64(a.hi) >> s)
		}
	}
}

// SPDX-License-Identifier: GPL-2.0-only

// The base M1 MacBook Air (J313) speaker path: two TAS5770L amplifiers fed
// *by the MCA I2S block through ADMAC, with a speaker protection model driven
// *by the amplifiers' own voltage and current sense data.
// * *Every address is a mapped kernel virtual address, except the two IOVAs,
// *which are what ADMAC sees through the SIO DART. The V platform layer
// *validates the device tree, powers the blocks and maps them before calling
// *vinix_apple_speakers_init(). All functions are serialized by that layer.

// Switches the power domain of MCA cluster `cluster` on or off; 1 on
// *success. The cluster domains are externally clocked and change state only
// *while their clock runs, so the driver calls this itself at the one point in
// *the start and stop sequences where that holds.

pub type Vinix_apple_speakers_power_fn = fn (u32, i32) i32

pub struct C.vinix_apple_speakers_config {
pub mut:
	mca_clusters u64
	// MCA reg[0]: one 0x4000 window per cluster
	mca_cluster_count u32
	mca_switch        u64
	// MCA reg[1]: DMA adapters
	admac          u64
	admac_channels u32
	nco            u64
	nco_channels   u32
	nco_ref_hz     u32
	tx_cluster     u32
	// frontend that serializes playback
	sense_cluster u32
	// frontend that captures V/I sense
	tx_nco u32
	// clock channels feeding those clusters
	sense_nco u32
	tx_dma    u32
	// ADMAC channels: even = TX, odd = RX
	sense_dma u32
	port_mask u32
	// I2S ports wired to the amplifiers
	i2c [2]u64
	// left, right amplifier buses
	i2c_ref_hz    u32
	amp_address   [2]u8
	imon_slot     [2]u8
	vmon_slot     [2]u8
	shutdown_gpio u64
	// pin register of the shared SDZ line
	tx_buffer u64
	// CPU address, 16 KiB aligned
	tx_iova       u64
	tx_bytes      u32
	sense_buffer  u64
	sense_iova    u64
	sense_bytes   u32
	cluster_power Vinix_apple_speakers_power_fn
}

// keep calling service

// playback advanced; wake writers

// everything written has played

// spk_controller shut down for safety

// only silence for a while: stop

pub struct C.vinix_apple_speakers_status {
pub mut:
	coil_mc [2]i32
	// modelled temperatures, milli-degrees C
	magnet_mc      [2]i32
	model_gain_mdb i32
	// reduction the model asks for
	applied_att i32
	// amplifier attenuation, 0.5 dB steps
	verified     i32
	fault        i32
	underruns    u64
	sense_chunks u64
	dma_errors   u64
}

// 1 on success. Resets and configures both amplifiers, leaves them shut down
// *and muted, and sets up the DMA channels. Nothing plays until start.

// Prepare for a stream at `rate` Hz, S16_LE stereo. 0 if unsupported.

// Stream start, in two halves, each 1 on success: the clocks and the
// *playback cluster, then the amplifiers, DMA and sense capture. The caller
// *stops the stream if either fails.

// Whether the service loop wants the stream started: enough is queued, or a
// *drain was requested.

// One pass of the playback, sense and protection loop.

// Writer interface. reserve returns a contiguous writable span of the ring
// *(0 bytes when full); commit publishes what was copied into it, applying
// *the software volume.

// configured or running

// A stream that cannot start is a fault too: shut down, stay down.

// For sysrq 't', read without the caller's lock, which a hang may hold:
// *state, powered clusters, clocks_on, written, queued, played, draining,
// *drain_target, reserved, underruns, sense_chunks, dma_errors.

// Pops the oldest driver event into {code, a, b}; 0 when there is none.
// *Codes: 1 amp found (amp, revision), 2 sense verified, 3 sense stale (ms),
// *4 sense dead (speaker), 5 model gain (mdB), 6 over temperature (speaker,
// *milli-degrees), 7 negative power (speaker, mW), 8 I2C error (amp, error),
// *9 DMA error (channel, ring), 10 serializer reset stuck (cluster),
// *11 cluster power domain did not switch (cluster, on).

// SPDX-License-Identifier: GPL-2.0-only
// * *Built-in spk_controller of the base M1 MacBook Air (J313).
// * *Playback runs from a ring buffer through ADMAC into an MCA frontend, out of
// *two I2S ports to a pair of TI TAS5770L amplifiers (TAS2770 family), which
// *are configured over the P.A. Semi I2C controllers. The amplifiers send the
// *voltage across and current through each voice coil back on the same bus;
// *a second MCA frontend captures that, and a thermal model of each speaker
// *turns it into a gain limit. This is the job Asahi Linux splits between the
// *kernel and speakersafetyd; here it all lives in the driver, so the model
// *runs whenever the spk_controller can make sound.
// * *Register sequences follow Asahi Linux: sound/soc/apple/mca.c,
// *drivers/dma/apple-admac.c, drivers/clk/clk-apple-nco.c (Martin PoviÅ¡er),
// *sound/soc/codecs/tas2770.c, drivers/i2c/busses/i2c-pasemi-core.c,
// *sound/soc/apple/macaudio.c. The protection model and the J313 parameters
// *come from speakersafetyd (conf/apple/j313.conf), The Asahi Linux
// *Contributors, MIT.
// * *Safety policy, stricter than running without the daemon on Linux:
// * - The amplifier gain is fixed at the value macOS uses on this machine.
// * - Until the sense data has been seen to track the output, and whenever it
// *   stops arriving for 250 ms, the output is held 20 dB down.
// * - Gaps in the sense data never count as cooling time while playing.
// * - A modelled temperature past the limit plus headroom, or sense data
// *   that implies negative power, shuts both amplifiers down until reboot.
// * *The kernel is built with general registers only: everything is fixed
// *point. Temperatures and power are Q32 (units of 2^-32 degrees and watts).
//

// ---- geometry ----

// S16_LE stereo

// I left, V left, I right, V right

// ADMAC descriptor ring depth

// below this many queued, pad with silence

// start a short write that never fills two periods

// ---- P.A. Semi I2C ----

// ---- TAS2770 / TAS5770L ----

// AMP_LEVEL[4:0]: 11 dBV + 0.5 dB/step

// DVC: 0.5 dB of attenuation per step

// PWR_CTRL bit 2 powers VSENSE down and bit 3 ISENSE; both stay clear.

// macOS runs the J313 amplifiers at level 10, 16 dBV (macaudio_j313_cfg).

// -20 dB, Asahi's general safe level

// -100.5 dB, the bottom of the range

// releasing attenuation: 0.5 dB per 5 ms

// ---- NCO ----

// ---- MCA ----

// BCLK = 256 fs: 8 slots of 32 bits

// the same frame as 16 slots of 16 bits

// ---- ADMAC ----

// the one output wired on t8103

// ---- Apple GPIO ----

// ---- the protection model (speakersafetyd, conf/apple/j313.conf) ----

pub struct Speaker_params {
pub mut:
	tr_coil_m i32
	// thermal resistance, milli-degrees per watt
	tr_magnet_m i32
	tau_coil_ms i32
	// time constants
	tau_magnet_ms i32
	t_limit_m     i32
	// milli-degrees
	t_headroom_m   i32
	z_nominal_mohm i32
	is_scale_m     i32
	// sense full scale: milliamps, millivolts
	vs_scale_m i32
	is_chan    u8
	vs_chan    u8
}

__global j313_speakers = [Speaker_params{
	tr_coil_m:      29000
	tr_magnet_m:    36000
	tau_coil_ms:    2400
	tau_magnet_ms:  80000
	t_limit_m:      120000
	t_headroom_m:   15000
	z_nominal_mohm: 4900
	is_scale_m:     3750
	vs_scale_m:     14000
	is_chan:        u8(0)
	vs_chan:        u8(1)
}, Speaker_params{
	tr_coil_m:      29000
	tr_magnet_m:    36000
	tau_coil_ms:    2400
	tau_magnet_ms:  80000
	t_limit_m:      120000
	t_headroom_m:   15000
	z_nominal_mohm: 4900
	is_scale_m:     3750
	vs_scale_m:     14000
	is_chan:        u8(2)
	vs_chan:        u8(3)
}]!

pub struct Speaker_model {
pub mut:
	coil i64
	// Q32 degrees
	magnet      i64
	coil_hyst   i64
	magnet_hyst i64
	gain_mdb    i32
}

// ---- events for the V layer to print ----

// empty enum
pub const spk_ev_none = 0
pub const spk_ev_amp = 1
// a = amp, b = revision
pub const spk_ev_verified = 2
// sense data tracks the output: limit lifted
pub const spk_ev_stale = 3
// a = ms since the last sense data
pub const spk_ev_dead = 4
// a = speaker: output but no measured voltage
pub const spk_ev_gain = 5
// a = model gain mdB
pub const spk_ev_fault_temp = 6
// a = speaker, b = milli-degrees
pub const spk_ev_fault_power = 7
// a = speaker, b = milliwatts
pub const spk_ev_fault_i2c = 8
// a = amp, b = error
pub const spk_ev_dma_error = 9
// a = channel
pub const spk_ev_serdes = 10
// a = cluster: reset bit stuck
pub const spk_ev_power = 11

// a = cluster, b = on: domain did not switch

pub struct Speaker_event {
pub mut:
	code i32
	a    i32
	b    i32
}

// ---- driver state ----

pub struct Spk_io {
pub mut:
	read32     fn (voidptr, u64) u32
	write32    fn (voidptr, u64, u32)
	now_us     fn (voidptr) u64
	delay_us   fn (voidptr, u32)
	clean      fn (voidptr, u64, u32)
	invalidate fn (voidptr, u64, u32)
	power      fn (voidptr, u32, i32) i32
	cookie     voidptr
}

// empty enum
pub const st_off = 0
pub const st_idle = 1
pub const st_prepared = 2
pub const st_running = 3
pub const st_fault = 4

pub struct Speakers {
pub mut:
	io        Spk_io
	cfg       C.vinix_apple_speakers_config
	state     i32
	clocks_on i32
	// start_clocks ran; hardware_stop undoes it
	powered u32
	// MCA clusters whose power domains are on
	rate    u32
	i2c_div u32
	i2c_rev [2]u32
	amp_rev [2]u32
	// playback ring, byte positions since the stream was configured
	tx_ring   u32
	written   u64
	queued    u64
	played    u64
	reserved  u32
	scaled_to u64
	// volume applied up to here
	measured_to u64
	// output energy accounted up to here
	draining         i32
	drain_target     u64
	volume           u32
	first_write_us   u64
	silence_since_us u64
	period_energy    [32][2]u64
	period_tag       [32]u64
	// sense ring, in periods
	sense_periods u32
	sense_queued  u64
	sense_done    u64
	sense_origin  u64
	// playback frame at which sense capture began

	// protection
	model        [2]Speaker_model
	min_gain_mdb i32
	alpha_coil   i64
	// Q48, per sample
	alpha_magnet i64
	power_factor i64
	// sense product to Q32 watts, times 10^6
	expect_q32 u64
	// output power to sense-LSB power, 0 dB
	last_model_us   u64
	last_sense_us   u64
	window_expected [8][2]u64
	window_measured [8][2]u64
	live            [2]i32
	dead            [2]i32
	verified        i32
	stale_reported  i32
	applied_att     i32
	reported_gain   i32
	last_ramp_us    u64
	i2c_failures    u32
	underruns       u64
	sense_chunks    u64
	dma_errors      u64
	events          [16]Speaker_event
	event_head      u32
	event_count     u32
}

// ---- small helpers ----

@[export: 'vinix_spk_core_rd']
pub fn rd(s &Speakers, address u64) u32 {
	unsafe {
		return s.io.read32(voidptr(s.io.cookie), address)
	}
}

@[export: 'vinix_spk_core_wr']
pub fn wr(s &Speakers, address u64, value u32) {
	unsafe {
		s.io.write32(voidptr(s.io.cookie), address, value)
	}
}

@[export: 'vinix_spk_core_modify']
pub fn modify(s &Speakers, address u64, mask u32, value u32) {
	unsafe {
		wr(s, address, (rd(s, address) & ~mask) | (value & mask))
	}
}

@[export: 'vinix_spk_core_now_us']
pub fn now_us(s &Speakers) u64 {
	unsafe {
		return s.io.now_us(voidptr(s.io.cookie))
	}
}

@[export: 'vinix_spk_core_delay_us']
pub fn delay_us(s &Speakers, us u32) {
	unsafe {
		s.io.delay_us(voidptr(s.io.cookie), us)
	}
}

@[export: 'vinix_spk_core_post']
pub fn post(s &Speakers, code i32, a i32, b i32) {
	unsafe {
		slot := u32(0)
		if s.event_count == 16 {
			// Keep the newest: drop the oldest.

			s.event_head = (s.event_head + u32(1)) % 16
			s.event_count--
		}
		slot = (s.event_head + s.event_count) % 16
		s.events[slot].code = code
		s.events[slot].a = a
		s.events[slot].b = b
		s.event_count++
	}
}

@[export: 'vinix_spk_core_take_event']
pub fn take_event(s &Speakers, out &Speaker_event) i32 {
	unsafe {
		if !s.event_count {
			return 0
		}
		*out = s.events[s.event_head]
		s.event_head = (s.event_head + u32(1)) % 16
		s.event_count--
		return 1
	}
}

@[export: 'vinix_spk_core_mul_q48']
pub fn mul_q48(a i64, b i64) i64 {
	unsafe {
		p := wide_multiply(wide_signed(i64(a)), wide_signed(i64(b)))
		return i64((wide_arithmetic_right((wide_add(p, (wide_shift_left(wide_signed(i64(1)), int(47))))), int(48))).lo)
	}
}

@[export: 'vinix_spk_core_mul_q32u']
pub fn mul_q32u(a u64, b u64) u64 {
	unsafe {
		p := wide_multiply(wide_unsigned(u64(a)), wide_unsigned(u64(b)))
		return u64((wide_shift_right((wide_add(p, wide_unsigned(u64((u32(1) << 31))))), int(32))).lo)
	}
}

// ---- fixed-point logarithms ----

pub const pow2_frac_q32 = [u64(u64(6074001000)), u64(u64(5107605667)), u64(u64(4683695048)),
	u64(u64(4485121744)), u64(u64(4389014833)), u64(u64(4341736423)), u64(u64(4318288544)),
	u64(u64(4306612134)), u64(u64(4300785774)), u64(u64(4297875550)), u64(u64(4296421177)),
	u64(u64(4295694175)), u64(u64(4295330720)), u64(u64(4295149004)), u64(u64(4295058149)),
	u64(u64(4295012722))]!

// log2(x) in Q16, x > 0.

@[export: 'vinix_spk_core_log2_q16']
pub fn log2_q16(x u64) i64 {
	unsafe {
		n := i64(63)
		y := u64(0)
		result := i64(0)
		bit := i32(0)
		for !(x & (u64(1) << 63)) {
			x <<= 1
			n--
		}
		// x now holds the mantissa in Q63 of [1, 2). Keep 32 bits of it.

		y = x >> 31
		// Q32

		result = n << 16
		for bit = 15; bit >= 0; bit-- {
			y = u64((wide_shift_right((wide_multiply(wide_unsigned(u64(y)), wide_unsigned(u64(y)))), int(32))).lo)
			if y >= (u64(2) << 32) {
				y >>= 1
				result |= i64(1) << bit
			}
		}
		return result
	}
}

// 10^(mdb/10000) in Q32: power ratio of a level in milli-decibels.

@[export: 'vinix_spk_core_db_to_power_q32']
pub fn db_to_power_q32(mdb i32) u64 {
	unsafe {
		// 10^(x/10) = 2^(x *log2(10) / 10); exponent in Q16.

		e := (i64(mdb) * i64(3321928) * i64(65536)) / 10000000000
		whole := e >> 16
		// floor, also for negative e

		frac := u32((e & i64(65535)))
		value := u64(u64(1) << 32)
		bit := i32(0)
		for bit = 0; bit < 16; bit++ {
			if frac & (32768 >> bit) {
				value = mul_q32u(value, pow2_frac_q32[bit])
			}
		}
		if whole >= i64(0) {
			if whole > i64(30) {
				return ~0
			}
			return value << whole
		}
		if whole < i64(-63) {
			return u64(0)
		}
		return value >> -whole
	}
}

// ---- I2C ----

@[export: 'vinix_spk_core_i2c_base']
pub fn i2c_base(s &Speakers, amp i32) u64 {
	unsafe {
		return s.cfg.i2c[amp]
	}
}

@[export: 'vinix_spk_core_i2c_reset']
pub fn i2c_reset(s &Speakers, amp i32) {
	unsafe {
		value := (1 << 9) | (1 << 10) | (1 << 8) | (s.i2c_div & u32(255))
		if s.i2c_rev[amp] >= u32(6) {
			value |= (1 << 11)
		}
		wr(s, i2c_base(s, amp) + u64(28), value)
	}
}

@[export: 'vinix_spk_core_i2c_clear']
pub fn i2c_clear(s &Speakers, amp i32) i32 {
	unsafe {
		base := i2c_base(s, amp)
		start := now_us(s)
		status := u32(0)
		for {
			status = rd(s, base + u64(20))
			if !(status & ((1 << 28) | (1 << 24))) {
				break
			}
			if now_us(s) - start > u64(100000) {
				return -1
			}
			delay_us(s, u32(50))
		}
		if (status & ((1 << 19) | (1 << 25) | (1 << 23) | (1 << 6) | (1 << 21) | (1 << 22))) || !(status & (1 << 16)) {
			i2c_reset(s, amp)
		}
		wr(s, base + u64(20), status)
		return 0
	}
}

@[export: 'vinix_spk_core_i2c_wait']
pub fn i2c_wait(s &Speakers, amp i32) i32 {
	unsafe {
		base := i2c_base(s, amp)
		start := now_us(s)
		status := u32(0)
		for {
			status = rd(s, base + u64(20))
			if status & (1 << 27) {
				break
			}
			if now_us(s) - start > u64(100000) {
				return -2
			}
			delay_us(s, u32(10))
		}
		if status & (1 << 6) {
			return -3
		}
		if status & (1 << 23) {
			return -4
		}
		if status & (1 << 28) {
			return -5
		}
		if status & (1 << 22) {
			return -6
		}
		if status & (1 << 21) {
			return -7
		}
		wr(s, base + u64(20), (1 << 27))
		return 0
	}
}

@[export: 'vinix_spk_core_i2c_write']
pub fn i2c_write(s &Speakers, amp i32, reg u8, value u8) i32 {
	unsafe {
		base := i2c_base(s, amp)
		address := u32(s.cfg.amp_address[amp])
		error_ := i2c_clear(s, amp)
		if error_ {
			return error_
		}
		wr(s, base + u64(0), (1 << 8) | (address << 1))
		wr(s, base + u64(0), u32(reg))
		wr(s, base + u64(0), u32(value) | (1 << 9))
		error_ = i2c_wait(s, amp)
		if error_ {
			i2c_reset(s, amp)
		}
		return error_
	}
}

// Register address write without a stop, then a repeated-start read of one
// *byte: the two-message transfer regmap-i2c issues.

@[export: 'vinix_spk_core_i2c_read']
pub fn i2c_read(s &Speakers, amp i32, reg u8, value &u8) i32 {
	unsafe {
		base := i2c_base(s, amp)
		address := u32(s.cfg.amp_address[amp])
		data := u32(0)
		error_ := i2c_clear(s, amp)
		if error_ {
			return error_
		}
		wr(s, base + u64(0), (1 << 8) | (address << 1))
		wr(s, base + u64(0), u32(reg))
		wr(s, base + u64(0), (1 << 8) | (address << 1) | u32(1))
		wr(s, base + u64(0), u32(1) | (1 << 10) | (1 << 9))
		error_ = i2c_wait(s, amp)
		if error_ {
			i2c_reset(s, amp)
			return error_
		}
		data = rd(s, base + u64(4))
		if data & (1 << 8) {
			i2c_reset(s, amp)
			return -8
		}
		*value = u8(data)
		return 0
	}
}

@[export: 'vinix_spk_core_tas_update']
pub fn tas_update(s &Speakers, amp i32, reg u8, mask u8, value u8) i32 {
	unsafe {
		current := u8(0)
		error_ := i2c_read(s, amp, reg, &current)
		if error_ {
			return error_
		}
		return i2c_write(s, amp, reg, u8(((i32(current) & ~i32(mask)) | (i32(value) & i32(mask)))))
	}
}

@[export: 'vinix_spk_core_tas_expect']
pub fn tas_expect(s &Speakers, amp i32, reg u8, mask u8, value u8) i32 {
	unsafe {
		current := u8(0)
		error_ := i2c_read(s, amp, reg, &current)
		if error_ {
			return error_
		}
		return if (i32(current) & i32(mask)) == (i32(value) & i32(mask)) { 0 } else { -9 }
	}
}

@[export: 'vinix_spk_core_tas_power']
pub fn tas_power(s &Speakers, amp i32, mode u8) i32 {
	unsafe {
		return tas_update(s, amp, u8(2), u8(3 | 12), mode)
	}
}

@[export: 'vinix_spk_core_tas_init']
pub fn tas_init(s &Speakers, amp i32) i32 {
	unsafe {
		slot := u8(amp)
		// left plays slot 0, right slot 1

		rev := u8(0)
		error_ := i32(0)
		error_ = i2c_write(s, amp, u8(0), u8(0))
		if error_ {
			return error_
		}
		error_ = i2c_write(s, amp, u8(1), u8(1))
		if error_ {
			return error_
		}
		delay_us(s, u32(2000))
		error_ = i2c_write(s, amp, u8(0), u8(0))
		if error_ {
			return error_
		}
		error_ = i2c_read(s, amp, u8(125), &rev)
		if error_ {
			return error_
		}
		s.amp_rev[amp] = u32(rev)
		// Sense can only be powered through shutdown: power it with the
		//     *amplifier off, and leave it there until a stream starts.

		error_ = tas_power(s, amp, u8(2))
		if error_ {
			return error_
		}
		error_ = i2c_write(s, amp, u8(5), u8(201))
		if error_ {
			return error_
		}
		// I2S with both clocks inverted: data on the falling edge, one bit of
		//     *offset, frame sync starting a frame on its rising edge.

		error_ = tas_update(s, amp, u8(11), u8(63), u8(3))
		if error_ {
			return error_
		}
		// ASI1 plays the left slot; 16-bit words in 32-bit slots.

		error_ = tas_update(s, amp, u8(12), u8(63), u8(18))
		if error_ {
			return error_
		}
		error_ = i2c_write(s, amp, u8(13), u8((i32(slot) << 4 | i32(slot))))
		if error_ {
			return error_
		}
		// TDM4, the bus keeper for unused sense slots, stays at its reset value.
		//     *The J313 device tree asks for "zero", but macaudio applies idle modes
		//     *only to backends with several amplifiers, and each J313 backend has
		//     *one: the default is what sense capture has always run with.

		error_ = tas_update(s, amp, u8(15), u8(127), u8((64 | i32(s.cfg.vmon_slot[amp]))))
		if error_ {
			return error_
		}
		error_ = tas_update(s, amp, u8(16), u8(127), u8((64 | i32(s.cfg.imon_slot[amp]))))
		if error_ {
			return error_
		}
		error_ = tas_update(s, amp, u8(3), u8(31), u8(10))
		if error_ {
			return error_
		}
		// The model's power limit depends on the gain: read it back.

		error_ = tas_expect(s, amp, u8(3), u8(31), u8(10))
		if error_ {
			return error_
		}
		error_ = tas_expect(s, amp, u8(5), u8(255), u8(201))
		if error_ {
			return error_
		}
		return tas_expect(s, amp, u8(2), u8(15), u8(2))
	}
}

@[export: 'vinix_spk_core_tas_set_rate']
pub fn tas_set_rate(s &Speakers, amp i32) i32 {
	unsafe {
		// FPOL clear; 44.1 kHz family in bit 5; the 44.1/48 kHz ramp rate.

		value := u8((6 | (if s.rate == u32(44100) { 32 } else { 0 })))
		return tas_update(s, amp, u8(10), u8(47), value)
	}
}

// ---- GPIO ----

@[export: 'vinix_spk_core_sdz_set']
pub fn sdz_set(s &Speakers, enabled i32) {
	unsafe {
		modify(s, s.cfg.shutdown_gpio, (3 << 5) | (7 << 1) | (1 << 0), (1 << 1) | (if enabled {
			(1 << 0)
		} else {
			u32(0)
		}))
	}
}

// ---- NCO ----

@[export: 'vinix_spk_core_lfsr_step']
pub fn lfsr_step(state u32) u32 {
	unsafe {
		return if state & u32(1) { (state >> 1) ^ (2561 >> 1) } else { state >> 1 }
	}
}

// The coarse divisor is counted in a Galois LFSR: the register takes the
// *LFSR state that many steps before the end of its period.

@[export: 'vinix_spk_core_nco_div_register']
pub fn nco_div_register(div u32) u32 {
	unsafe {
		index := div / u32(4) - 2
		state := u32(0)
		i := u32(0)
		if index {
			state = 2047
			for i = u32(0); i < 2048 - index; i++ {
				state = lfsr_step(state)
			}
		}
		return (state << 2) | (div % u32(4))
	}
}

@[export: 'vinix_spk_core_nco_set_rate']
pub fn nco_set_rate(s &Speakers, channel u32, rate u32) i32 {
	unsafe {
		base := s.cfg.nco + u64(channel) * u64(16384)
		twice := 2 * u64(s.cfg.nco_ref_hz)
		div := u32(0)
		inc1 := u32(0)
		inc2 := u32(0)
		ctrl := u32(0)

		if !rate {
			return -1
		}
		div = u32((twice / u64(rate)))
		if div / u32(4) < 2 || div / u32(4) >= 2 + 2048 {
			return -1
		}
		inc1 = u32((twice - u64(div) * u64(rate)))
		inc2 = inc1 - rate
		ctrl = rd(s, base + u64(0))
		wr(s, base + u64(0), ctrl & ~(u32(1) << 31))
		wr(s, base + u64(4), nco_div_register(div))
		wr(s, base + u64(8), inc1)
		wr(s, base + u64(12), inc2)
		wr(s, base + u64(16), u32(1) << 31)
		if ctrl & (u32(1) << 31) {
			wr(s, base + u64(0), ctrl | (u32(1) << 31))
		}
		return 0
	}
}

@[export: 'vinix_spk_core_nco_enable']
pub fn nco_enable(s &Speakers, channel u32, enable i32) {
	unsafe {
		base := s.cfg.nco + u64(channel) * u64(16384)
		modify(s, base + u64(0), (u32(1) << 31), if enable { (u32(1) << 31) } else { u32(0) })
	}
}

// ---- MCA ----

@[export: 'vinix_spk_core_cluster']
pub fn cluster(s &Speakers, n u32) u64 {
	unsafe {
		return s.cfg.mca_clusters + u64(n) * u64(16384)
	}
}

// The cluster power domains are externally clocked: they change state only
// *while their clock runs. So a domain goes on after its clock starts and off
// *before it stops, as mca_fe_enable_clocks and mca_fe_disable_clocks order
// *it. Nothing in a cluster but its port block is touched while it is off.

@[export: 'vinix_spk_core_cluster_on']
pub fn cluster_on(s &Speakers, n u32) i32 {
	unsafe {
		if !s.io.power(voidptr(s.io.cookie), n, 1) {
			post(s, i32(spk_ev_power), i32(n), 1)
			return 0
		}
		s.powered |= 1 << n
		return 1
	}
}

@[export: 'vinix_spk_core_cluster_off']
pub fn cluster_off(s &Speakers, n u32) {
	unsafe {
		if !(s.powered & (1 << n)) {
			return
		}
		s.powered &= ~(1 << n)
		if !s.io.power(voidptr(s.io.cookie), n, 0) {
			post(s, i32(spk_ev_power), i32(n), 0)
		}
	}
}

// I2S, CPU provides the clocks, both inverted (macaudio's DAI format).

@[export: 'vinix_spk_core_mca_set_format']
pub fn mca_set_format(s &Speakers, n u32) {
	unsafe {
		c := cluster(s, n)
		modify(s, c + u64(768) + u64(4), 1024, u32(0))
		modify(s, c + u64(1024) + u64(8), 1024, u32(0))
		wr(s, c + u64(768) + u64(8), u32(1))
		wr(s, c + u64(1024) + u64(12), u32(1))
	}
}

@[export: 'vinix_spk_core_adapter_value']
pub fn adapter_value(channels u32) u32 {
	unsafe {
		pad := u32(32 - 16)
		return (channels << 20) | (2 << 5) | (2 << 13) | pad | (pad << 8)
	}
}

@[export: 'vinix_spk_core_mca_configure_tx']
pub fn mca_configure_tx(s &Speakers) {
	unsafe {
		t := s.cfg.tx_cluster
		c := cluster(s, t)
		serdes := c + u64(768)
		modify(s, serdes + u64(4), (31 << 4) | 15 | (7 << 16) | (1 << 12) | (1 << 13) | (1 << 14), (8 - u32(1)) | 256 | ((t + u32(1)) << 16) | (1 << 12) | (1 << 13) | (1 << 14))
		wr(s, serdes + u64(12), u32(4294967295))
		wr(s, serdes + u64(12) + u64(4), ~3)
		// two channels of eight slots

		wr(s, serdes + u64(12) + u64(8), u32(4294967295))
		wr(s, serdes + u64(12) + u64(12), ~255)
		wr(s, s.cfg.mca_switch + u64((32768 * t)), adapter_value(u32(2)))
		wr(s, c + u64(264), 256 / u32(2) - u32(1))
		wr(s, c + u64(268), (256 + u32(1)) / u32(2) - u32(1))
		wr(s, c + u64(4), 1 << 8)
	}
}

@[export: 'vinix_spk_core_mca_configure_sense']
pub fn mca_configure_sense(s &Speakers) {
	unsafe {
		n := s.cfg.sense_cluster
		c := cluster(s, n)
		serdes := c + u64(1024)
		modify(s, serdes + u64(8), (31 << 4) | 15 | (7 << 16) | (1 << 12) | (1 << 13) | (1 << 14) | (1 << 15), (16 - u32(1)) | 64 | ((n + u32(1)) << 16) | (1 << 12) | (1 << 13) | (1 << 15))
		wr(s, serdes + u64(16), u32(4294967295))
		wr(s, serdes + u64(16) + u64(4), ~15)
		// four channels of sixteen

		wr(s, serdes + u64(4), s.cfg.port_mask)
		wr(s, s.cfg.mca_switch + u64((32768 * n + 16384)), adapter_value(4))
		wr(s, c + u64(264), 256 / u32(2) - u32(1))
		wr(s, c + u64(268), (256 + u32(1)) / u32(2) - u32(1))
		wr(s, c + u64(4), 1 << 8)
	}
}

@[export: 'vinix_spk_core_mca_ports']
pub fn mca_ports(s &Speakers, on i32) {
	unsafe {
		p := u32(0)
		for p = u32(0); p < s.cfg.mca_cluster_count; p++ {
			c := u64(0)
			if !(s.cfg.port_mask & (1 << p)) {
				continue
			}
			c = cluster(s, p)
			if on {
				wr(s, c + u64(1544), 1 << (s.cfg.tx_cluster * u32(2)))
				modify(s, c + u64(1536), (1 << 3), (1 << 3))
				wr(s, c + u64(1540), (s.cfg.tx_cluster + u32(1)) << 8)
				modify(s, c + u64(1536), (3 << 1), (3 << 1))
			} else {
				modify(s, c + u64(1536), (1 << 3), u32(0))
				wr(s, c + u64(1544), u32(0))
				modify(s, c + u64(1536), (3 << 1), u32(0))
				wr(s, c + u64(1540), u32(0))
			}
		}
	}
}

@[export: 'vinix_spk_core_lowest_port']
pub fn lowest_port(mask u32) u32 {
	unsafe {
		p := u32(0)
		for !(mask & 1) {
			mask >>= 1
			p++
		}
		return p
	}
}

// Reset the serializer with its sync input parked, as mca_fe_early_trigger
// *does before ADMAC starts.

@[export: 'vinix_spk_core_serdes_reset']
pub fn serdes_reset(s &Speakers, n u32, unit u32, conf u32) {
	unsafe {
		serdes := cluster(s, n) + u64(unit)
		modify(s, serdes + u64(conf), (7 << 16), u32(0))
		modify(s, serdes + u64(conf), (7 << 16), 7 << 16)
		modify(s, serdes + u64(0), (1 << 0) | (1 << 1), (1 << 1))
		delay_us(s, u32(50))
		if rd(s, serdes + u64(0)) & (1 << 1) {
			post(s, i32(spk_ev_serdes), i32(n), 0)
		}
		modify(s, serdes + u64(conf), (7 << 16), u32(0))
		modify(s, serdes + u64(conf), (7 << 16), (n + u32(1)) << 16)
		delay_us(s, u32(100))
	}
}

@[export: 'vinix_spk_core_serdes_enable']
pub fn serdes_enable(s &Speakers, n u32, unit u32, enable i32) {
	unsafe {
		serdes := cluster(s, n) + u64(unit)
		if enable {
			modify(s, serdes + u64(0), (1 << 0) | (1 << 1), (1 << 0))
		} else {
			modify(s, serdes + u64(0), (1 << 0), u32(0))
		}
	}
}

// ---- ADMAC ----

@[export: 'vinix_spk_core_chan']
pub fn channel_base(s &Speakers, ch u32) u64 {
	unsafe {
		return s.cfg.admac + u64((32768 + ch * 512))
	}
}

@[export: 'vinix_spk_core_admac_setup']
pub fn admac_setup(s &Speakers, ch u32, frame u32) i32 {
	unsafe {
		sram := rd(s, s.cfg.admac + u64((if ch & u32(1) { 152 } else { 148 })))
		width := u32(0)
		if sram < 2048 {
			return -1
		}
		// This driver owns the whole controller: the first block of each SRAM.

		wr(s, channel_base(s, ch) + u64(80), 2048 << 16)
		width = rd(s, channel_base(s, ch) + u64(64)) & ~255
		wr(s, channel_base(s, ch) + u64(64), width | 1 | frame)
		wr(s, channel_base(s, ch) + u64(84), ((48 * u32(2)) << 16) | (24 * u32(2)))
		return 0
	}
}

@[export: 'vinix_spk_core_admac_reset_rings']
pub fn admac_reset_rings(s &Speakers, ch u32) {
	unsafe {
		wr(s, channel_base(s, ch) + u64(0), (1 << 0))
		wr(s, channel_base(s, ch) + u64(0), u32(0))
	}
}

@[export: 'vinix_spk_core_admac_descriptor']
pub fn admac_descriptor(s &Speakers, ch u32, iova u64, length u32) {
	unsafe {
		port := s.cfg.admac + u64((65536 + (ch / 2) * 4 + (ch & 1) * 16384))
		wr(s, port, u32(iova))
		wr(s, port, u32((iova >> 32)))
		wr(s, port, length)
		wr(s, port, (1 << 16))
	}
}

@[export: 'vinix_spk_core_admac_run']
pub fn admac_run(s &Speakers, ch u32, run i32) {
	unsafe {
		bit := 1 << (ch / u32(2))
		if run {
			// Asahi's apple-admac driver unmasks this output only because its
			//         *IRQ handler drains the report ring and acknowledges every level
			//         *interrupt.  Vinix deliberately polls the rings from the speaker
			//         *service thread, so an unmasked descriptor-done interrupt would
			//         *remain asserted between polls and trap a CPU in an IRQ storm as
			//         *soon as the first period completed.

			wr(s, channel_base(s, ch) + u64((16 + 1 * 4)), (1 << 0) | (1 << 6))
			wr(s, channel_base(s, ch) + u64((32 + 1 * 4)), u32(0))
			wr(s, s.cfg.admac + u64((if ch & u32(1) { 8 } else { 0 })), bit)
		} else {
			wr(s, s.cfg.admac + u64((if ch & u32(1) { 12 } else { 4 })), bit)
			admac_reset_rings(s, ch)
			wr(s, channel_base(s, ch) + u64((32 + 1 * 4)), u32(0))
		}
	}
}

// Completed descriptors since the last call.

@[export: 'vinix_spk_core_admac_reap']
pub fn admac_reap(s &Speakers, ch u32) u32 {
	unsafe {
		c := channel_base(s, ch)
		port := s.cfg.admac + u64((65792 + (ch / 2) * 4 + (ch & 1) * 16384))
		n := u32(0)
		if rd(s, c + u64(112)) & (1 << 10) {
			wr(s, c + u64(112), (1 << 10))
			s.dma_errors++
			post(s, i32(spk_ev_dma_error), i32(ch), 0)
		}
		if rd(s, c + u64(116)) & (1 << 10) {
			wr(s, c + u64(116), (1 << 10))
			s.dma_errors++
			post(s, i32(spk_ev_dma_error), i32(ch), 1)
		}
		for n < 4 && !(rd(s, c + u64(116)) & (1 << 8)) {
			rd(s, port)
			rd(s, port)
			rd(s, port)
			rd(s, port)
			n++
		}
		if n {
			wr(s, c + u64((16 + 1 * 4)), (1 << 0))
		}
		return n
	}
}

// ---- protection model ----

@[export: 'vinix_spk_core_model_rate']
pub fn model_rate(s &Speakers) {
	unsafe {
		p := &j313_speakers[0] + 0
		// alpha = step / (tau + step) = 1 / (tau *rate + 1), in Q48.

		s.alpha_coil = i64(((u64(1000) << 48) / (u64(p.tau_coil_ms) * u64(s.rate) + u64(1000))))
		s.alpha_magnet = i64(((u64(1000) << 48) / (u64(p.tau_magnet_ms) * u64(s.rate) + u64(1000))))
	}
}

@[export: 'vinix_spk_core_model_reset']
pub fn model_reset(s &Speakers) {
	unsafe {
		i := u32(0)
		for i = u32(0); i < 2; i++ {
			p := &j313_speakers[0] + i
			m := &s.model[0] + i
			// speakersafetyd's cold boot: warm, but not warm enough to limit.
			//         *Whatever played before this kernel is unknown.

			coil := ((i64((p.t_limit_m - 20000)) << 32) / i64(1000)) - (i64(1) << 32)
			m.coil = coil
			m.magnet = ((i64(50000) << 32) / i64(1000)) + (coil - ((i64(50000) << 32) / i64(1000))) * i64(p.tr_magnet_m) / i64((p.tr_magnet_m + p.tr_coil_m))
			m.coil_hyst = i64(0)
			m.magnet_hyst = i64(0)
			m.gain_mdb = 0
		}
	}
}

// The model with no power: c' = (1-ac) c + ac m, m' = (1-am) m, relative to
// *ambient. Raise that step to `samples` by squaring and apply it once.

@[export: 'vinix_spk_core_model_cool']
pub fn model_cool(s &Speakers, samples u64) {
	unsafe {
		one := u64(u64(1) << 62)
		ac := u64(s.alpha_coil) << 14
		// Q48 -> Q62

		am := u64(s.alpha_magnet) << 14
		a := one - ac
		b := ac
		d := one - am

		// step matrix

		ra := one
		rb := u64(0)
		rd_ := one

		// result: identity

		i := u32(0)
		if !samples {
			return
		}
		for samples {
			if samples & u64(1) {
				// result = result *step

				na := u64((wide_shift_right((wide_multiply(wide_unsigned(u64(ra)), wide_unsigned(u64(a)))), int(62))).lo)
				nb := u64((wide_shift_right((wide_add((wide_multiply(wide_unsigned(u64(ra)), wide_unsigned(u64(b)))), (wide_multiply(wide_unsigned(u64(rb)), wide_unsigned(u64(d)))))), int(62))).lo)
				nd := u64((wide_shift_right((wide_multiply(wide_unsigned(u64(rd_)), wide_unsigned(u64(d)))), int(62))).lo)
				ra = na
				rb = nb
				rd_ = nd
			}
			na := u64((wide_shift_right((wide_multiply(wide_unsigned(u64(a)), wide_unsigned(u64(a)))), int(62))).lo)
			nb := u64((wide_shift_right((wide_add((wide_multiply(wide_unsigned(u64(a)), wide_unsigned(u64(b)))), (wide_multiply(wide_unsigned(u64(b)), wide_unsigned(u64(d)))))), int(62))).lo)
			nd := u64((wide_shift_right((wide_multiply(wide_unsigned(u64(d)), wide_unsigned(u64(d)))), int(62))).lo)
			a = na
			b = nb
			d = nd
			samples >>= 1
		}
		for i = u32(0); i < 2; i++ {
			m := &s.model[0] + i
			c := m.coil - ((i64(50000) << 32) / i64(1000))
			g := m.magnet - ((i64(50000) << 32) / i64(1000))
			nc := i64((wide_arithmetic_right((wide_add(wide_multiply(wide_signed(i64(c)), wide_signed(i64(i64(ra)))), wide_multiply(wide_signed(i64(g)), wide_signed(i64(i64(rb)))))), int(62))).lo)
			ng := i64((wide_arithmetic_right((wide_multiply(wide_signed(i64(g)), wide_signed(i64(i64(rd_))))), int(62))).lo)
			m.coil = ((i64(50000) << 32) / i64(1000)) + nc
			m.magnet = ((i64(50000) << 32) / i64(1000)) + ng
		}
	}
}

@[export: 'vinix_spk_core_model_idle']
pub fn model_idle(s &Speakers) {
	unsafe {
		now := now_us(s)
		elapsed := now - s.last_model_us
		// Only time with the amplifiers shut down counts as cooling.

		model_cool(s, elapsed * u64(s.rate) / u64(1000000))
		s.last_model_us = now
	}
}

@[export: 'vinix_spk_core_min_gain_mdb']
pub fn min_gain_mdb() i32 {
	unsafe {
		p := &j313_speakers[0] + 0
		// max power / peak power, speakersafetyd's min_gain:
		//     *  ((t_limit - t_ambient) / (tr_magnet + tr_coil)) /
		//     *  (10^(amp_gain/10) / z *2)

		num := u64((p.t_limit_m - 50000)) * u64(p.z_nominal_mohm)
		den := u64((p.tr_magnet_m + p.tr_coil_m)) * u64(2) * u64(1000)
		diff := log2_q16(num) - log2_q16(den)
		mdb := diff * i64(30103) / i64((65536 * 10)) - i64((11000 + 500 * i32(10)))
		return if mdb > i64(0) { 0 } else { i32(mdb) }
	}
}

// Run the model over one chunk of sense data. 0, or a fault event code.

@[export: 'vinix_spk_core_model_run']
pub fn model_run(s &Speakers, n u32, frames &i16, count u32, fault_value &i32) i32 {
	unsafe {
		p := &j313_speakers[0] + n
		m := &s.model[0] + n
		ambient := ((i64(50000) << 32) / i64(1000))
		ceiling := ((i64((p.t_limit_m + p.t_headroom_m)) << 32) / i64(1000))
		sum := i64(0)
		average := i64(0)
		temp := i64(0)
		excess := i64(0)

		f := u32(0)
		for f = u32(0); f < count; f++ {
			v := i32(frames[f * 4 + u32(p.vs_chan)])
			i := i32(frames[f * 4 + u32(p.is_chan)])
			power := i64(v) * i64(i) * s.power_factor / i64(1000000)
			coil_target := m.magnet + power * i64(p.tr_coil_m) / i64(1000)
			magnet_target := ambient + power * i64(p.tr_magnet_m) / i64(1000)
			m.coil += mul_q48(coil_target - m.coil, s.alpha_coil)
			m.magnet += mul_q48(magnet_target - m.magnet, s.alpha_magnet)
			if m.coil > ceiling || m.magnet > ceiling {
				hot := if m.coil > m.magnet { m.coil } else { m.magnet }
				*fault_value = i32(((hot * i64(1000)) >> 32))
				return spk_ev_fault_temp
			}
			sum += power
		}
		average = if count { sum / i64(count) } else { i64(0) }
		// Only rounding should make the average negative.

		if average < -((i64(1) << 32) / i64(100)) {
			*fault_value = i32(((average * i64(1000)) >> 32))
			return spk_ev_fault_power
		}
		if m.coil_hyst < m.coil {
			m.coil_hyst = m.coil
		}
		if m.coil_hyst > m.coil + ((i64(5000) << 32) / i64(1000)) {
			m.coil_hyst = m.coil + ((i64(5000) << 32) / i64(1000))
		}
		if m.magnet_hyst < m.magnet {
			m.magnet_hyst = m.magnet
		}
		if m.magnet_hyst > m.magnet + ((i64(5000) << 32) / i64(1000)) {
			m.magnet_hyst = m.magnet + ((i64(5000) << 32) / i64(1000))
		}
		temp = if m.coil_hyst > m.magnet_hyst { m.coil_hyst } else { m.magnet_hyst }
		excess = temp - ((i64((p.t_limit_m - 20000)) << 32) / i64(1000))
		if excess <= i64(0) {
			m.gain_mdb = 0
		} else {
			gain := i64(s.min_gain_mdb) * excess / ((i64(20000) << 32) / i64(1000))
			m.gain_mdb = if gain > i64(-10) {
				0
			} else {
				(if gain < i64(-100000) { -100000 } else { i32(gain) })
			}
		}
		return 0
	}
}

@[export: 'vinix_spk_core_model_gain']
pub fn model_gain(s &Speakers) i32 {
	unsafe {
		gain := i32(0)
		i := u32(0)
		for i = u32(0); i < 2; i++ {
			if s.model[i].gain_mdb < gain {
				gain = s.model[i].gain_mdb
			}
		}
		return gain
	}
}

// ---- amplifier state ----

@[export: 'vinix_spk_core_set_attenuation']
pub fn set_attenuation(s &Speakers, att i32) i32 {
	unsafe {
		i := u32(0)
		failed := i32(0)
		if att < 0 {
			att = 0
		}
		if att > 201 {
			att = 201
		}
		for i = u32(0); i < 2; i++ {
			error_ := i2c_write(s, i32(i), u8(5), u8(att))
			if error_ {
				failed = 1
				post(s, i32(spk_ev_fault_i2c), i32(i), error_)
			}
		}
		if failed {
			// A write that should have made it quieter must not be lost.

			s.i2c_failures++
			if s.i2c_failures >= u32(3) || att > s.applied_att {
				fault_shutdown(s)
			}
			return -1
		}
		s.i2c_failures = u32(0)
		s.applied_att = att
		return 0
	}
}

@[export: 'vinix_spk_core_apply_policy']
pub fn apply_policy(s &Speakers, now u64) {
	unsafe {
		fresh := i32(now - s.last_sense_us <= u64(250000))
		any_live := i32(0)
		any_dead := i32(0)

		gain := model_gain(s)
		model_att := i32(0)
		target := i32(0)

		i := u32(0)
		for i = u32(0); i < 2; i++ {
			any_live |= s.live[i]
			any_dead |= s.dead[i]
		}
		if !fresh && !s.stale_reported {
			s.stale_reported = 1
			post(s, i32(spk_ev_stale), i32(((now - s.last_sense_us) / u64(1000))), 0)
		}
		if fresh && any_live && !any_dead {
			if !s.verified {
				post(s, i32(spk_ev_verified), 0, 0)
			}
			s.verified = 1
		} else {
			s.verified = 0
		}
		if gain != s.reported_gain {
			// Report entering, leaving and whole-decibel steps of limiting.

			if gain == 0 || s.reported_gain == 0 || gain / 1000 != s.reported_gain / 1000 {
				post(s, i32(spk_ev_gain), gain, 0)
			}
			s.reported_gain = gain
		}
		model_att = (-gain + 499) / 500
		target = if s.verified { model_att } else { (if model_att > 40 { model_att } else { 40 }) }
		if target > s.applied_att {
			set_attenuation(s, target)
			s.last_ramp_us = now
		} else if target < s.applied_att && now - s.last_ramp_us >= u64(5000) {
			set_attenuation(s, s.applied_att - 1)
			s.last_ramp_us = now
		}
	}
}

// ---- playback ring ----

@[export: 'vinix_spk_core_tx_at']
pub fn tx_at(s &Speakers, position u64) &u8 {
	unsafe {
		return &u8(usize((s.cfg.tx_buffer + position % u64(s.tx_ring))))
	}
}

@[export: 'vinix_spk_core_tx_submit']
pub fn tx_submit(s &Speakers) {
	unsafe {
		offset := u32((s.queued % u64(s.tx_ring)))
		s.io.clean(voidptr(s.io.cookie), s.cfg.tx_buffer + u64(offset), (512 * 4))
		admac_descriptor(s, s.cfg.tx_dma, s.cfg.tx_iova + u64(offset), (512 * 4))
		s.queued += u64((512 * 4))
	}
}

@[export: 'vinix_spk_core_energy_slot']
pub fn energy_slot(s &Speakers, period u64) &u64 {
	unsafe {
		slot := u32((period % u64(32)))
		if s.period_tag[slot] != period + u64(1) {
			s.period_tag[slot] = period + u64(1)
			s.period_energy[slot][0] = u64(0)
			s.period_energy[slot][1] = u64(0)
		}
		return &s.period_energy[slot][0]
	}
}

// Scale and account for whole samples and frames up to `written`.

@[export: 'vinix_spk_core_tx_account']
pub fn tx_account(s &Speakers) {
	unsafe {
		end := s.written & ~1
		for s.scaled_to < end {
			sample := &i16(voidptr(tx_at(s, s.scaled_to)))
			if s.volume < u32(100) {
				*sample = i16((i32(*sample) * i32(s.volume) / 100))
			}
			s.scaled_to += u64(2)
		}
		end = s.written & ~u64((4 - u32(1)))
		for s.measured_to < end {
			frame := &i16(voidptr(tx_at(s, s.measured_to)))
			energy := energy_slot(s, s.measured_to / u64((512 * 4)))
			energy[0] += u64((i32(frame[0]) * i32(frame[0])))
			energy[1] += u64((i32(frame[1]) * i32(frame[1])))
			s.measured_to += u64(4)
		}
	}
}

// Complete the period being written with silence.

@[export: 'vinix_spk_core_tx_pad']
pub fn tx_pad(s &Speakers) {
	unsafe {
		end := (s.written / u64((512 * 4)) + u64(1)) * u64((512 * 4))
		if s.written % u64((512 * 4)) == u64(0) && s.written > s.queued {
			return
		}
		if s.written == s.queued {
			end = s.queued + u64((512 * 4))
		}
		for s.written < end {
			{
				c2v_target := tx_at(s, s.written)
				*c2v_target = u8(0)
			}
			s.written++
		}
		s.scaled_to = s.written
		tx_account(s)
	}
}

@[export: 'vinix_spk_core_tx_service']
pub fn tx_service(s &Speakers, now u64) u32 {
	unsafe {
		flags := u32(0)
		done := admac_reap(s, s.cfg.tx_dma)
		if done {
			s.played += u64(done) * u64((512 * 4))
			if s.played > s.queued {
				s.played = s.queued
			}
			flags |= 2
		}
		for s.queued - s.played < u64(4) * u64((512 * 4)) {
			if s.written - s.queued >= u64((512 * 4)) {
				tx_submit(s)
				s.silence_since_us = u64(0)
				continue
			}
			if s.queued - s.played < u64(2) * u64((512 * 4)) && !s.reserved {
				empty := i32(s.written == s.queued)
				if !s.draining {
					s.underruns++
				}
				tx_pad(s)
				tx_submit(s)
				if empty && !s.silence_since_us {
					s.silence_since_us = if now { now } else { u64(1) }
				} else if !empty {
					s.silence_since_us = u64(0)
				}
				continue
			}
			break
		}
		if s.draining && s.played >= s.drain_target {
			flags |= 4
		}
		return flags
	}
}

// ---- sense ring ----

@[export: 'vinix_spk_core_sense_iova']
pub fn sense_iova(s &Speakers, period u64) u64 {
	unsafe {
		return s.cfg.sense_iova + (period % u64(s.sense_periods)) * u64((512 * (4 * 2)))
	}
}

@[export: 'vinix_spk_core_sense_submit']
pub fn sense_submit(s &Speakers) {
	unsafe {
		admac_descriptor(s, s.cfg.sense_dma, sense_iova(s, s.sense_queued), (512 * (4 * 2)))
		s.sense_queued++
	}
}

// Output energy that should have been measured during sense chunk `k`,
// *per speaker, in sense-voltage LSB squared.

@[export: 'vinix_spk_core_expected_energy']
pub fn expected_energy(s &Speakers, k u64, out &u64) {
	unsafe {
		start := s.sense_origin + k * u64(512)
		first := start / u64(512)
		w_second := start % u64(512)
		w_first := u64(512) - w_second
		scale := mul_q32u(s.expect_q32, db_to_power_q32(-500 * s.applied_att))
		i := u32(0)
		for i = u32(0); i < 2; i++ {
			e := u64(0)
			slot := u32((first % u64(32)))
			if s.period_tag[slot] == first + u64(1) {
				e += s.period_energy[slot][i] / u64(512) * w_first
			}
			slot = u32(((first + u64(1)) % u64(32)))
			if w_second && s.period_tag[slot] == first + u64(2) {
				e += s.period_energy[slot][i] / u64(512) * w_second
			}
			out[i] = mul_q32u(e, scale)
		}
	}
}

// Liveness: output that should have produced a measurable voltage must have.
// *Judged over a window of chunks so the two streams need not align exactly.

@[export: 'vinix_spk_core_check_liveness']
pub fn check_liveness(s &Speakers, k u64, frames &i16) {
	unsafe {
		window_frames := u64(8) * u64(512)
		// 50 mV and 100 mV RMS, in sense LSB (14 V full scale) squared.

		judge := 13690 * window_frames
		condemn := 54760 * window_frames
		expected := [2]u64{}
		slot := u32((k % u64(8)))
		i := u32(0)
		f := u32(0)
		c := u32(0)

		expected_energy(s, k, &expected[0])
		for i = u32(0); i < 2; i++ {
			p := &j313_speakers[0] + i
			measured := u64(0)
			total_expected := u64(0)
			total_measured := u64(0)

			for f = u32(0); f < 512; f++ {
				v := i32(frames[f * 4 + u32(p.vs_chan)])
				measured += u64((v * v))
			}
			s.window_expected[slot][i] = expected[i]
			s.window_measured[slot][i] = measured
			if k + u64(1) < u64(8) {
				continue
			}
			for c = u32(0); c < 8; c++ {
				total_expected += s.window_expected[c][i]
				total_measured += s.window_measured[c][i]
			}
			if total_expected >= judge && total_measured * u64(100) >= total_expected * u64(9) {
				s.live[i] = 1
				// at least 30% of the expected RMS

				s.dead[i] = 0
			} else if total_expected >= condemn && total_measured * u64(100) < total_expected {
				if !s.dead[i] {
					post(s, i32(spk_ev_dead), i32(i), 0)
				}
				s.dead[i] = 1
				// under 10% of it
			}
		}
	}
}

@[export: 'vinix_spk_core_sense_service']
pub fn sense_service(s &Speakers, now u64) {
	unsafe {
		done := admac_reap(s, s.cfg.sense_dma)
		for done-- {
			k := s.sense_done
			address := s.cfg.sense_buffer + (k % u64(s.sense_periods)) * u64((512 * (4 * 2)))
			frames := &i16(usize(address))
			i := u32(0)
			s.io.invalidate(voidptr(s.io.cookie), address, (512 * (4 * 2)))
			for i = u32(0); i < 2; i++ {
				value := i32(0)
				code := model_run(s, i, frames, 512, &value)
				if code {
					post(s, code, i32(i), value)
					fault_shutdown(s)
					return
				}
			}
			check_liveness(s, k, frames)
			s.sense_done++
			s.sense_chunks++
			s.last_sense_us = now
			s.stale_reported = 0
			sense_submit(s)
		}
	}
}

// ---- stream control ----

@[export: 'vinix_spk_core_reset_positions']
pub fn reset_positions(s &Speakers) {
	unsafe {
		i := u32(0)
		s.played = u64(0)
		s.queued = s.played
		s.written = s.queued
		s.measured_to = u64(0)
		s.scaled_to = s.measured_to
		s.reserved = u32(0)
		s.draining = 0
		s.drain_target = u64(0)
		s.first_write_us = u64(0)
		s.silence_since_us = u64(0)
		for i = u32(0); i < 32; i++ {
			s.period_tag[i] = u64(0)
		}
	}
}

@[export: 'vinix_spk_core_hardware_stop']
pub fn hardware_stop(s &Speakers) {
	unsafe {
		i := u32(0)
		tx := cluster(s, s.cfg.tx_cluster)
		for i = u32(0); i < 2; i++ {
			tas_power(s, i32(i), u8(1))
		}
		delay_us(s, u32(1000))
		for i = u32(0); i < 2; i++ {
			tas_power(s, i32(i), u8(2))
		}
		// Sense is clocked through the speaker port: power it down while that
		//     *still runs.

		if s.powered & (1 << s.cfg.sense_cluster) {
			serdes_enable(s, s.cfg.sense_cluster, u32(1024), 0)
			modify(s, cluster(s, s.cfg.sense_cluster) + u64(256), (1 << 0), u32(0))
		}
		admac_run(s, s.cfg.sense_dma, 0)
		cluster_off(s, s.cfg.sense_cluster)
		if s.powered & (1 << s.cfg.tx_cluster) {
			serdes_enable(s, s.cfg.tx_cluster, u32(768), 0)
			modify(s, tx + u64(256), (1 << 0), u32(0))
			modify(s, tx + u64(0), (1 << 0), u32(0))
		}
		admac_run(s, s.cfg.tx_dma, 0)
		cluster_off(s, s.cfg.tx_cluster)
		nco_enable(s, s.cfg.tx_nco, 0)
		mca_ports(s, 0)
		s.clocks_on = 0
	}
}

@[export: 'vinix_spk_core_fault_shutdown']
pub fn fault_shutdown(s &Speakers) {
	unsafe {
		was_running := i32(s.state == st_running || s.clocks_on)
		// The shutdown line first: it needs no I2C to work.

		sdz_set(s, 0)
		s.state = st_fault
		if was_running {
			hardware_stop(s)
		}
	}
}

@[export: 'vinix_spk_core_configure']
pub fn configure(s &Speakers, rate u32) i32 {
	unsafe {
		if s.state == st_off || s.state == st_fault || s.state == st_running {
			return 0
		}
		if rate != u32(44100) && rate != u32(48000) {
			return 0
		}
		s.rate = rate
		model_rate(s)
		reset_positions(s)
		s.state = st_prepared
		return 1
	}
}

@[export: 'vinix_spk_core_wants_start']
pub fn wants_start(s &Speakers) i32 {
	unsafe {
		if s.state != st_prepared || s.written == u64(0) {
			return 0
		}
		return i32(s.written - s.queued >= u64(2) * u64((512 * 4)) || s.draining || now_us(s) - s.first_write_us >= u64(20000))
	}
}

@[export: 'vinix_spk_core_start_clocks']
pub fn start_clocks(s &Speakers) i32 {
	unsafe {
		i := u32(0)
		if s.state != st_prepared {
			return 0
		}
		model_idle(s)
		for i = u32(0); i < 2; i++ {
			error_ := tas_set_rate(s, i32(i))
			if !error_ {
				error_ = i2c_write(s, i32(i), u8(5), u8(40))
			}
			if error_ {
				post(s, i32(spk_ev_fault_i2c), i32(i), error_)
				fault_shutdown(s)
				return 0
			}
		}
		s.applied_att = 40
		if nco_set_rate(s, s.cfg.tx_nco, 256 * s.rate) || nco_set_rate(s, s.cfg.sense_nco, 256 * s.rate) {
			return 0
		}
		mca_ports(s, 1)
		nco_enable(s, s.cfg.tx_nco, 1)
		s.clocks_on = 1
		if !cluster_on(s, s.cfg.tx_cluster) {
			return 0
		}
		mca_set_format(s, s.cfg.tx_cluster)
		mca_configure_tx(s)
		return 1
	}
}

@[export: 'vinix_spk_core_start_stream']
pub fn start_stream(s &Speakers) i32 {
	unsafe {
		tx := cluster(s, s.cfg.tx_cluster)
		sense := cluster(s, s.cfg.sense_cluster)
		i := u32(0)
		residue := u32(0)

		position := u64(0)
		if s.state != st_prepared {
			return 0
		}
		wr(s, tx + u64(260), s.cfg.tx_cluster + u32(1))
		modify(s, tx + u64(256), (1 << 0), (1 << 0))
		modify(s, tx + u64(0), (1 << 0), (1 << 0))
		delay_us(s, u32(1000))
		for i = u32(0); i < 2; i++ {
			error_ := tas_power(s, i32(i), u8(0))
			if error_ {
				post(s, i32(spk_ev_fault_i2c), i32(i), error_)
				s.state = st_running
				fault_shutdown(s)
				return 0
			}
		}
		// Playback: the first period, the channel, then the rest of the ring.

		serdes_reset(s, s.cfg.tx_cluster, u32(768), u32(4))
		admac_reset_rings(s, s.cfg.tx_dma)
		tx_pad(s)
		tx_submit(s)
		admac_run(s, s.cfg.tx_dma, 1)
		for s.queued - s.played < u64(4) * u64((512 * 4)) && s.written - s.queued >= u64((512 * 4)) && !(rd(s, channel_base(s, s.cfg.tx_dma) + u64(112)) & (1 << 9)) {
			tx_submit(s)
		}
		serdes_enable(s, s.cfg.tx_cluster, u32(768), 1)
		// Sense: a clock consumer framed by the first speaker port, which runs
		//     *now.

		if !cluster_on(s, s.cfg.sense_cluster) {
			return 0
		}
		mca_set_format(s, s.cfg.sense_cluster)
		mca_configure_sense(s)
		wr(s, sense + u64(260), lowest_port(s.cfg.port_mask) + u32(6) + u32(1))
		modify(s, sense + u64(256), (1 << 0), (1 << 0))
		serdes_reset(s, s.cfg.sense_cluster, u32(1024), u32(8))
		admac_reset_rings(s, s.cfg.sense_dma)
		s.sense_done = u64(0)
		s.sense_queued = s.sense_done
		sense_submit(s)
		admac_run(s, s.cfg.sense_dma, 1)
		for s.sense_queued < u64(4) {
			sense_submit(s)
		}
		// Where playback is now, so each sense chunk can be matched with the
		//     *output it measured.

		s.played += u64(admac_reap(s, s.cfg.tx_dma)) * u64((512 * 4))
		residue = rd(s, channel_base(s, s.cfg.tx_dma) + u64(100))
		position = s.played + u64((if residue <= (512 * 4) { (512 * 4) - residue } else { u32(0) }))
		serdes_enable(s, s.cfg.sense_cluster, u32(1024), 1)
		s.sense_origin = position / u64(4)
		for i = u32(0); i < 2; i++ {
			s.live[i] = 0
			s.dead[i] = 0
		}
		for i = u32(0); i < 8; i++ {
			s.window_expected[i][1] = u64(0)
			s.window_expected[i][0] = s.window_expected[i][1]
			s.window_measured[i][1] = u64(0)
			s.window_measured[i][0] = s.window_measured[i][1]
		}
		s.verified = 0
		s.stale_reported = 0
		s.last_sense_us = now_us(s)
		s.last_ramp_us = s.last_sense_us
		s.state = st_running
		return 1
	}
}

@[export: 'vinix_spk_core_stop']
pub fn stop(s &Speakers) {
	unsafe {
		if s.state == st_running || (s.state == st_prepared && s.clocks_on) {
			i := u32(0)
			hardware_stop(s)
			// The amplifiers are shut down; the next start sets the level.

			for i = u32(0); i < 2; i++ {
				i2c_write(s, i32(i), u8(5), u8(201))
			}
			s.applied_att = 201
			s.last_model_us = now_us(s)
		}
		if s.state == st_running || s.state == st_prepared {
			s.state = st_idle
		}
		reset_positions(s)
	}
}

@[export: 'vinix_spk_core_service']
pub fn service(s &Speakers) u32 {
	unsafe {
		now := u64(0)
		flags := u32(0)
		if s.state == st_fault {
			return 8
		}
		if s.state != st_running {
			return u32(0)
		}
		now = now_us(s)
		flags = tx_service(s, now) | 1
		sense_service(s, now)
		if s.state == st_fault {
			return 8 | 2
		}
		apply_policy(s, now)
		if s.state == st_fault {
			return 8 | 2
		}
		if s.silence_since_us && !s.draining && !s.reserved && now - s.silence_since_us >= u64(3000000) {
			flags |= 16
		}
		return flags
	}
}

@[export: 'vinix_spk_core_room']
pub fn room(s &Speakers) u32 {
	unsafe {
		used := u64(0)
		if s.state != st_prepared && s.state != st_running {
			return u32(0)
		}
		used = s.written - s.played
		return if used >= u64(s.tx_ring) { u32(0) } else { u32((u64(s.tx_ring) - used)) }
	}
}

@[export: 'vinix_spk_core_reserve']
pub fn reserve(s &Speakers, length &u32) &u8 {
	unsafe {
		available := room(s)
		contiguous := s.tx_ring - u32((s.written % u64(s.tx_ring)))
		if s.draining {
			available = u32(0)
		}
		if available > contiguous {
			available = contiguous
		}
		*length = available
		s.reserved = available
		return if available { tx_at(s, s.written) } else { &u8(nil) }
	}
}

@[export: 'vinix_spk_core_commit']
pub fn commit(s &Speakers, bytes u32) {
	unsafe {
		if bytes > s.reserved {
			bytes = s.reserved
		}
		s.reserved = u32(0)
		if !bytes {
			return
		}
		if !s.written {
			s.first_write_us = now_us(s)
		}
		s.written += u64(bytes)
		tx_account(s)
	}
}

@[export: 'vinix_spk_core_drain']
pub fn drain(s &Speakers) {
	unsafe {
		if s.state != st_prepared && s.state != st_running {
			return
		}
		if s.written % u64((512 * 4)) {
			tx_pad(s)
		}
		s.draining = 1
		s.drain_target = s.written
	}
}

@[export: 'vinix_spk_core_drained']
pub fn drained(s &Speakers) i32 {
	unsafe {
		if s.state == st_running {
			return i32(s.draining && s.played >= s.drain_target)
		}
		return i32(s.state != st_prepared || s.written == u64(0))
	}
}

@[c:'init']
@[export: 'vinix_spk_core_c_init']
pub fn c_init(s &Speakers, cfg &C.vinix_apple_speakers_config) i32 {
	unsafe {
		p := &j313_speakers[0] + 0
		i := u32(0)
		s.cfg = *cfg
		s.state = st_off
		mut __c2v_condition_0 := false
		mut __c2v_condition_1 := false
		__c2v_condition_1 = cfg.tx_cluster >= cfg.mca_cluster_count
		__c2v_condition_0 = __c2v_condition_1
		if !__c2v_condition_0 {
			mut __c2v_condition_2 := false
			__c2v_condition_2 = cfg.sense_cluster >= cfg.mca_cluster_count
			__c2v_condition_0 = __c2v_condition_2
		}
		if !__c2v_condition_0 {
			mut __c2v_condition_3 := false
			__c2v_condition_3 = cfg.tx_cluster == cfg.sense_cluster
			__c2v_condition_0 = __c2v_condition_3
		}
		if !__c2v_condition_0 {
			mut __c2v_condition_4 := false
			__c2v_condition_4 = !cfg.port_mask
			__c2v_condition_0 = __c2v_condition_4
		}
		if !__c2v_condition_0 {
			mut __c2v_condition_5 := false
			__c2v_condition_5 = cfg.port_mask >> cfg.mca_cluster_count
			__c2v_condition_0 = __c2v_condition_5
		}
		if !__c2v_condition_0 {
			mut __c2v_condition_6 := false
			__c2v_condition_6 = (cfg.port_mask & (1 << cfg.sense_cluster))
			__c2v_condition_0 = __c2v_condition_6
		}
		if !__c2v_condition_0 {
			mut __c2v_condition_7 := false
			__c2v_condition_7 = cfg.tx_nco >= cfg.nco_channels
			__c2v_condition_0 = __c2v_condition_7
		}
		if !__c2v_condition_0 {
			mut __c2v_condition_8 := false
			__c2v_condition_8 = cfg.sense_nco >= cfg.nco_channels
			__c2v_condition_0 = __c2v_condition_8
		}
		if !__c2v_condition_0 {
			mut __c2v_condition_9 := false
			__c2v_condition_9 = (cfg.tx_dma & u32(1))
			__c2v_condition_0 = __c2v_condition_9
		}
		if !__c2v_condition_0 {
			mut __c2v_condition_10 := false
			__c2v_condition_10 = !(cfg.sense_dma & u32(1))
			__c2v_condition_0 = __c2v_condition_10
		}
		if !__c2v_condition_0 {
			mut __c2v_condition_11 := false
			__c2v_condition_11 = cfg.tx_dma >= cfg.admac_channels
			__c2v_condition_0 = __c2v_condition_11
		}
		if !__c2v_condition_0 {
			mut __c2v_condition_12 := false
			__c2v_condition_12 = cfg.sense_dma >= cfg.admac_channels
			__c2v_condition_0 = __c2v_condition_12
		}
		if !__c2v_condition_0 {
			mut __c2v_condition_13 := false
			__c2v_condition_13 = !cfg.nco_ref_hz
			__c2v_condition_0 = __c2v_condition_13
		}
		if !__c2v_condition_0 {
			mut __c2v_condition_14 := false
			__c2v_condition_14 = !cfg.i2c_ref_hz
			__c2v_condition_0 = __c2v_condition_14
		}
		if !__c2v_condition_0 {
			mut __c2v_condition_15 := false
			__c2v_condition_15 = (cfg.tx_buffer | cfg.tx_iova | cfg.sense_buffer | cfg.sense_iova) & u64(16383)
			__c2v_condition_0 = __c2v_condition_15
		}
		if !__c2v_condition_0 {
			mut __c2v_condition_16 := false
			__c2v_condition_16 = cfg.tx_bytes < u32(8) * (512 * 4)
			__c2v_condition_0 = __c2v_condition_16
		}
		if !__c2v_condition_0 {
			mut __c2v_condition_17 := false
			__c2v_condition_17 = cfg.sense_bytes < u32(8) * (512 * (4 * 2))
			__c2v_condition_0 = __c2v_condition_17
		}
		if __c2v_condition_0 {
			return 0
		}
		for i = u32(0); i < 2; i++ {
			if !cfg.i2c[i] || i32(cfg.amp_address[i]) > 127 || i32(cfg.imon_slot[i]) > 63 || i32(cfg.vmon_slot[i]) > 63 {
				return 0
			}
		}
		s.tx_ring = cfg.tx_bytes / (512 * 4) * (512 * 4)
		s.sense_periods = cfg.sense_bytes / (512 * (4 * 2))
		s.volume = u32(100)
		s.min_gain_mdb = min_gain_mdb()
		// sense product (LSB^2) to Q32 watts, times 10^6: is *vs *4

		s.power_factor = i64(p.is_scale_m) * i64(p.vs_scale_m) * i64(4)
		// Output at full scale reaches at least 10^(gain/20) volts; in sense
		//     *LSB: (that / vs_scale)^2.

		s.expect_q32 = db_to_power_q32((11000 + 500 * i32(10))) * 1000000 / (u64(p.vs_scale_m) * u64(p.vs_scale_m))
		s.i2c_div = (cfg.i2c_ref_hz + u32(16) * 100000 - u32(1)) / (u32(16) * 100000)
		if s.i2c_div < u32(4) || s.i2c_div > u32(255) {
			return 0
		}
		s.io.clean(voidptr(s.io.cookie), cfg.tx_buffer, cfg.tx_bytes)
		s.io.clean(voidptr(s.io.cookie), cfg.sense_buffer, cfg.sense_bytes)
		for i = u32(0); i < 2; i++ {
			s.i2c_rev[i] = rd(s, cfg.i2c[i] + u64(40))
			wr(s, cfg.i2c[i] + u64(24), u32(0))
			i2c_reset(s, i32(i))
		}
		// Both amplifiers share one shutdown line: cycle it, then reset each.

		sdz_set(s, 0)
		delay_us(s, u32(5000))
		sdz_set(s, 1)
		delay_us(s, u32(2000))
		for i = u32(0); i < 2; i++ {
			error_ := tas_init(s, i32(i))
			if error_ {
				post(s, i32(spk_ev_fault_i2c), i32(i), error_)
				sdz_set(s, 0)
				return 0
			}
			post(s, i32(spk_ev_amp), i32(i), i32(s.amp_rev[i]))
		}
		if admac_setup(s, cfg.tx_dma, 16) || admac_setup(s, cfg.sense_dma, 32) {
			sdz_set(s, 0)
			return 0
		}
		s.rate = u32(48000)
		model_rate(s)
		model_reset(s)
		s.last_model_us = now_us(s)
		s.applied_att = 201
		s.state = st_idle
		return 1
	}
}

@[export: 'vinix_spk_core_get_status']
pub fn get_status(s &Speakers, out &C.vinix_apple_speakers_status) {
	unsafe {
		i := u32(0)
		for i = u32(0); i < 2; i++ {
			out.coil_mc[i] = i32(((s.model[i].coil * i64(1000)) >> 32))
			out.magnet_mc[i] = i32(((s.model[i].magnet * i64(1000)) >> 32))
		}
		out.model_gain_mdb = model_gain(s)
		out.applied_att = s.applied_att
		out.verified = s.verified
		out.fault = s.state == st_fault
		out.underruns = s.underruns
		out.sense_chunks = s.sense_chunks
		out.dma_errors = s.dma_errors
	}
}

// Width-exact MMIO, as for the other Apple drivers.

fn C.vinix_mmio_read32(arg voidptr) u32
fn C.vinix_mmio_read64(arg voidptr) u64

fn C.vinix_mmio_write32(arg voidptr, arg_2 u32)

__global spk_controller Speakers

__global spk_counter_frequency u64

__global spk_cache_line u64

@[export: 'vinix_spk_core_kernel_read32']
pub fn kernel_read32(cookie voidptr, address u64) u32 {
	unsafe {
		v := u32(0)

		v = C.vinix_mmio_read32(voidptr(usize(address)))
		asm volatile aarch64 {
		dmb ish
		; ; ; memory
	}
		return v
	}
}

@[export: 'vinix_spk_core_kernel_write32']
pub fn kernel_write32(cookie voidptr, address u64, value u32) {
	unsafe {
		asm volatile aarch64 {
		dmb ish
		; ; ; memory
	}
		C.vinix_mmio_write32(voidptr(usize(address)), value)
	}
}

@[export: 'vinix_spk_core_kernel_now_us']
pub fn kernel_now_us(cookie voidptr) u64 {
	unsafe {
		mut count := u64(0)
		asm volatile aarch64 { mrs count, cntvct_el0 ; =r (count) }
		return (count / spk_counter_frequency) * u64(1000000) + (count % spk_counter_frequency) * u64(1000000) / spk_counter_frequency
	}
}

@[export: 'vinix_spk_core_kernel_delay_us']
pub fn kernel_delay_us(cookie voidptr, us u32) {
	unsafe {
		start := kernel_now_us(voidptr(cookie))
		for kernel_now_us(voidptr(cookie)) - start < u64(us) {
			asm volatile aarch64 {
		yield
		; ; ; memory
	}
		}
	}
}

// ADMAC does not snoop the CPU caches: push playback out to memory before
// *it is queued, and drop stale lines before reading what it captured.

@[export: 'vinix_spk_core_kernel_clean']
pub fn kernel_clean(cookie voidptr, address u64, length u32) {
	unsafe {
		a := address & ~(spk_cache_line - u64(1))

		asm volatile aarch64 {
		dsb sy
		; ; ; memory
	}
		for ; a < address + u64(length); a += spk_cache_line {
			asm volatile aarch64 { dc civac, a ; ; r (a) ; memory }
		}
		asm volatile aarch64 {
		dsb sy
		; ; ; memory
	}
	}
}

@[export: 'vinix_spk_core_kernel_invalidate']
pub fn kernel_invalidate(cookie voidptr, address u64, length u32) {
	unsafe {
		a := address & ~(spk_cache_line - u64(1))

		asm volatile aarch64 {
		dsb sy
		; ; ; memory
	}
		for ; a < address + u64(length); a += spk_cache_line {
			asm volatile aarch64 { dc ivac, a ; ; r (a) ; memory }
		}
		asm volatile aarch64 {
		dsb sy
		; ; ; memory
	}
	}
}

@[export: 'vinix_spk_core_kernel_power']
pub fn kernel_power(cookie voidptr, cluster_2 u32, on i32) i32 {
	unsafe {
		return spk_controller.cfg.cluster_power(cluster_2, on)
	}
}

@[export: 'vinix_apple_speakers_init']
pub fn vinix_apple_speakers_init(cfg &C.vinix_apple_speakers_config) i32 {
	unsafe {
		mut ctr := u64(0)
		if (usize(cfg) == 0) || (usize(cfg.cluster_power) == 0) || spk_controller.state != st_off {
			return 0
		}
		mut frequency := u64(0)
		asm volatile aarch64 { mrs frequency, cntfrq_el0 ; =r (frequency) }
		asm volatile aarch64 { mrs ctr, ctr_el0 ; =r (ctr) }
		spk_counter_frequency = frequency
		spk_cache_line = u64(4) << ((ctr >> 16) & u64(15))
		if !spk_counter_frequency {
			return 0
		}
		spk_controller.io = Spk_io{
			read32:     kernel_read32
			write32:    kernel_write32
			now_us:     kernel_now_us
			delay_us:   kernel_delay_us
			clean:      kernel_clean
			invalidate: kernel_invalidate
			power:      kernel_power
			cookie:     0
		}

		return c_init(&spk_controller, cfg)
	}
}

@[export: 'vinix_apple_speakers_configure']
pub fn vinix_apple_speakers_configure(rate u32) i32 {
	unsafe {
		return configure(&spk_controller, rate)
	}
}

@[export: 'vinix_apple_speakers_start_clocks']
pub fn vinix_apple_speakers_start_clocks() i32 {
	unsafe {
		return start_clocks(&spk_controller)
	}
}

@[export: 'vinix_apple_speakers_start_stream']
pub fn vinix_apple_speakers_start_stream() i32 {
	unsafe {
		return start_stream(&spk_controller)
	}
}

@[export: 'vinix_apple_speakers_stop']
pub fn vinix_apple_speakers_stop() {
	unsafe {
		stop(&spk_controller)
	}
}

@[export: 'vinix_apple_speakers_wants_start']
pub fn vinix_apple_speakers_wants_start() i32 {
	unsafe {
		return wants_start(&spk_controller)
	}
}

@[export: 'vinix_apple_speakers_service']
pub fn vinix_apple_speakers_service() u32 {
	unsafe {
		return service(&spk_controller)
	}
}

@[export: 'vinix_apple_speakers_reserve']
pub fn vinix_apple_speakers_reserve(length &u32) &u8 {
	unsafe {
		return reserve(&spk_controller, length)
	}
}

@[export: 'vinix_apple_speakers_commit']
pub fn vinix_apple_speakers_commit(bytes u32) {
	unsafe {
		commit(&spk_controller, bytes)
	}
}

@[export: 'vinix_apple_speakers_room']
pub fn vinix_apple_speakers_room() u32 {
	unsafe {
		return room(&spk_controller)
	}
}

@[export: 'vinix_apple_speakers_drain']
pub fn vinix_apple_speakers_drain() {
	unsafe {
		drain(&spk_controller)
	}
}

@[export: 'vinix_apple_speakers_drained']
pub fn vinix_apple_speakers_drained() i32 {
	unsafe {
		return drained(&spk_controller)
	}
}

@[export: 'vinix_apple_speakers_running']
pub fn vinix_apple_speakers_running() i32 {
	unsafe {
		return i32(spk_controller.state == st_running)
	}
}

@[export: 'vinix_apple_speakers_active']
pub fn vinix_apple_speakers_active() i32 {
	unsafe {
		return i32(spk_controller.state == st_prepared || spk_controller.state == st_running)
	}
}

@[export: 'vinix_apple_speakers_faulted']
pub fn vinix_apple_speakers_faulted() i32 {
	unsafe {
		return i32(spk_controller.state == st_fault)
	}
}

@[export: 'vinix_apple_speakers_fail']
pub fn vinix_apple_speakers_fail() {
	unsafe {
		fault_shutdown(&spk_controller)
	}
}

@[export: 'vinix_apple_speakers_set_volume']
pub fn vinix_apple_speakers_set_volume(percent u32) {
	unsafe {
		spk_controller.volume = if percent > u32(100) { u32(100) } else { percent }
	}
}

@[export: 'vinix_apple_speakers_get_status']
pub fn vinix_apple_speakers_get_status(out &C.vinix_apple_speakers_status) {
	unsafe {
		get_status(&spk_controller, out)
	}
}

@[export: 'vinix_apple_speakers_debug']
pub fn vinix_apple_speakers_debug(out &u64) {
	unsafe {
		s := &spk_controller
		out[0] = u64(C.vinix_mmio_read32(&s.state))
		out[1] = u64(C.vinix_mmio_read32(&s.powered))
		out[2] = u64(C.vinix_mmio_read32(&s.clocks_on))
		out[3] = C.vinix_mmio_read64(&s.written)
		out[4] = C.vinix_mmio_read64(&s.queued)
		out[5] = C.vinix_mmio_read64(&s.played)
		out[6] = u64(C.vinix_mmio_read32(&s.draining))
		out[7] = C.vinix_mmio_read64(&s.drain_target)
		out[8] = u64(C.vinix_mmio_read32(&s.reserved))
		out[9] = C.vinix_mmio_read64(&s.underruns)
		out[10] = C.vinix_mmio_read64(&s.sense_chunks)
		out[11] = C.vinix_mmio_read64(&s.dma_errors)
	}
}

@[export: 'vinix_apple_speakers_take_event']
pub fn vinix_apple_speakers_take_event(out &i32) i32 {
	unsafe {
		e := Speaker_event{}
		if !take_event(&spk_controller, &e) {
			return 0
		}
		out[0] = e.code
		out[1] = e.a
		out[2] = e.b
		return 1
	}
}

// __AARCH64__

// __AARCH64__ || VINIX_APPLE_SPEAKERS_TEST

