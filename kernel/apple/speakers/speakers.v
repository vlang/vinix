// SPDX-License-Identifier: GPL-2.0-only
// Copyright (c) 2026 Alexander Medvednikov
@[has_globals]
module speakers

// The built-in speakers of the base M1 MacBook Air (J313), published as the
// OSS /dev/dsp that SDL and the other ports already speak.
//
// Everything is found in the device tree the Asahi boot chain passes on: the
// "Speakers" link of the apple,j313-macaudio sound node names the MCA ports
// and the two TAS5770L amplifiers, and those lead to the clocks, DMA
// channels, I2C buses, pins and power domains. Nothing is guessed: a device
// tree without all of it leaves the speakers off. The register work and the
// speaker protection model are in c/apple_speakers.c.
import aarch64.kio
import aarch64.pmgr
import apple.dart
import dev.oss
import devicetree
import errno
import event
import katomic
import memory
import proc
import time
import time.sys
import userland
import usercopy

#include "apple_speakers.h"

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
	coil_mc        [2]i32
	magnet_mc      [2]i32
	model_gain_mdb i32
	applied_att    i32
	verified       i32
	fault          i32
	underruns      u64
	sense_chunks   u64
	dma_errors     u64
}

fn C.vinix_apple_speakers_init(cfg &C.vinix_apple_speakers_config) int
fn C.vinix_apple_speakers_configure(rate u32) int
fn C.vinix_apple_speakers_start_clocks() u32
fn C.vinix_apple_speakers_start_stream() int
fn C.vinix_apple_speakers_stop()
fn C.vinix_apple_speakers_wants_start() int
fn C.vinix_apple_speakers_service() u32
fn C.vinix_apple_speakers_reserve(length &u32) &u8
fn C.vinix_apple_speakers_commit(bytes u32)
fn C.vinix_apple_speakers_room() u32
fn C.vinix_apple_speakers_drain()
fn C.vinix_apple_speakers_drained() int
fn C.vinix_apple_speakers_set_volume(percent u32)
fn C.vinix_apple_speakers_running() int
fn C.vinix_apple_speakers_active() int
fn C.vinix_apple_speakers_faulted() int
fn C.vinix_apple_speakers_fail()
fn C.vinix_apple_speakers_get_status(out &C.vinix_apple_speakers_status)
fn C.vinix_apple_speakers_take_event(out &i32) int

// macaudio's frontends: playback on the secondary (BCLK = 256 fs, room for
// the sense slots), sense capture on the third.
const tx_cluster = u32(1)
const sense_cluster = u32(2)
const tx_dma_name = 'tx1a'
const sense_dma_name = 'rx2b'
const cluster_stride = u64(0x4000)
const nco_stride = u64(0x4000)
const tx_ring_bytes = u64(16384)
const sense_ring_bytes = u64(32768)
const dma_alignment = u64(16384)
const tx_iova = u64(0x100000)
const sense_iova = u64(0x110000)
const ring_room_unconfigured = u64(16384)

const speaker_poll_ns = i64(1000000)
const running_period_ns = i64(2000000)
const idle_period_ns = i64(20000000)
// How long ADMAC's FIFO and the amplifiers still hold sound once the last
// period has been reported done.
const drain_tail_ns = i64(20000000)
const drain_stall_ns = u64(2000000000)

const ev_amp = 1
const ev_verified = 2
const ev_stale = 3
const ev_dead = 4
const ev_gain = 5
const ev_fault_temp = 6
const ev_fault_power = 7
const ev_fault_i2c = 8
const ev_dma_error = 9
const ev_serdes = 10

const service_running = u32(1)
const service_progress = u32(2)
const service_drained = u32(4)
const service_fault = u32(8)
const service_idle = u32(16)

struct Domain {
	handle u32
	region devicetree.DTReg
	offset u32
}

struct PinMux {
	region   devicetree.DTReg
	pin      u32
	function u32
}

struct Plan {
mut:
	mca_clusters  devicetree.DTReg
	mca_switch    devicetree.DTReg
	cluster_count u32
	port_mask     u32
	admac         devicetree.DTReg
	admac_count   u32
	tx_dma        u32
	sense_dma     u32
	nco           devicetree.DTReg
	nco_count     u32
	nco_ref_hz    u32
	tx_nco        u32
	sense_nco     u32
	dart          devicetree.DTReg
	dart_stream   u32
	i2c           [2]devicetree.DTReg
	i2c_ref_hz    u32
	address       [2]u8
	imon          [2]u8
	vmon          [2]u8
	gpio          devicetree.DTReg
	gpio_pin      u32
	pins          []PinMux
	power         []Domain
	cluster_power [2]Domain
	reset         Domain
}

pub struct SpeakerCard {}

pub struct SpeakerStream {
mut:
	rate  u32 = 48000
	level int = 100
	// A sleeping lock around the C driver: writers and the service thread.
	mutex u64
}

__global (
	speaker_card    SpeakerCard
	speaker_stream  SpeakerStream
	speaker_plan    Plan
	speaker_present = false
)

// ---- device tree ----

fn compatible(node &devicetree.DTNode, name string) bool {
	values := devicetree.get_string_list(node, 'compatible') or { return false }
	defer { unsafe { values.free() } }
	for value in values {
		if value == name {
			return true
		}
	}
	return false
}

fn enabled(node &devicetree.DTNode) bool {
	mut current := node
	for _ in 0 .. 64 {
		if current == unsafe { nil } {
			return true
		}
		status := devicetree.get_string_prop(current, 'status') or { 'okay' }
		if status != 'okay' && status != 'ok' {
			return false
		}
		current = current.parent
	}
	return false
}

fn has_property(node &devicetree.DTNode, name string) bool {
	_ := devicetree.get_property(node, name) or { return false }
	return true
}

fn find_enabled(node &devicetree.DTNode, name string, depth int) ?&devicetree.DTNode {
	if depth > 64 || !enabled(node) {
		return none
	}
	if compatible(node, name) {
		return node
	}
	for child in node.children {
		found := find_enabled(child, name, depth + 1) or { continue }
		return found
	}
	return none
}

fn child_named(node &devicetree.DTNode, name string) ?&devicetree.DTNode {
	for child in node.children {
		if child.name == name {
			return child
		}
	}
	return none
}

fn sane_region(r devicetree.DTReg, minimum u64) bool {
	return r.base != 0 && r.base & 3 == 0 && r.size >= minimum && r.size <= 0x1000000
		&& r.base <= ~u64(0) - r.size
}

fn only_region(node &devicetree.DTNode, minimum u64) ?devicetree.DTReg {
	regions := devicetree.get_translated_reg_ranges(node) or { return none }
	defer { unsafe { regions.free() } }
	if regions.len != 1 || !sane_region(regions[0], minimum) {
		return none
	}
	return regions[0]
}

fn fixed_clock_hz(handle u32) ?u32 {
	clock := devicetree.find_phandle(handle) or { return none }
	if !enabled(clock) || !compatible(clock, 'fixed-clock')
		|| devicetree.get_u32(clock, '#clock-cells') or { u32(1) } != 0 {
		return none
	}
	hz := devicetree.get_u32(clock, 'clock-frequency') or { return none }
	if hz == 0 {
		return none
	}
	return hz
}

// A PMGR power-state node: its register sits at `reg` within the enclosing
// PMGR syscon. Only the t8103 layout is accepted.
fn pwrstate(handle u32) ?Domain {
	domain := devicetree.find_phandle(handle) or { return none }
	if !enabled(domain) || !compatible(domain, 'apple,pmgr-pwrstate') {
		return none
	}
	parent := domain.parent
	if parent == unsafe { nil } || !compatible(parent, 'apple,t8103-pmgr')
		|| devicetree.get_u32(parent, '#address-cells') or { u32(0) } != 1
		|| devicetree.get_u32(parent, '#size-cells') or { u32(0) } != 1 {
		return none
	}
	region := only_region(parent, 4) or { return none }
	reg := devicetree.get_u32_array(domain, 'reg') or { return none }
	defer { unsafe { reg.free() } }
	if reg.len != 2 || reg[0] & 3 != 0 || reg[1] < 4 || u64(reg[0]) > region.size - 4 {
		return none
	}
	return Domain{
		handle: handle
		region: region
		offset: reg[0]
	}
}

fn planned(plan &Plan, handle u32) bool {
	for d in plan.power {
		if d.handle == handle {
			return true
		}
	}
	return false
}

// A domain after everything it depends on, each once.
fn plan_domain(handle u32, depth int, mut plan Plan) bool {
	if depth > 16 || plan.power.len >= 64 {
		return false
	}
	if planned(plan, handle) {
		return true
	}
	node := devicetree.find_phandle(handle) or { return false }
	if !plan_power(node, depth + 1, mut plan) {
		return false
	}
	d := pwrstate(handle) or { return false }
	if !planned(plan, handle) {
		plan.power << d
	}
	return true
}

fn plan_power(node &devicetree.DTNode, depth int, mut plan Plan) bool {
	if !has_property(node, 'power-domains') {
		return true
	}
	handles := devicetree.get_u32_array(node, 'power-domains') or { return false }
	defer { unsafe { handles.free() } }
	if handles.len > 8 {
		return false
	}
	for handle in handles {
		if !plan_domain(handle, depth, mut plan) {
			return false
		}
	}
	return true
}

fn gpio_region(provider &devicetree.DTNode, pin u32) ?devicetree.DTReg {
	if !enabled(provider) || !compatible(provider, 'apple,t8103-pinctrl')
		|| !has_property(provider, 'gpio-controller')
		|| devicetree.get_u32(provider, '#gpio-cells') or { u32(0) } != 2 {
		return none
	}
	region := only_region(provider, 4) or { return none }
	ranges := devicetree.get_u32_array(provider, 'gpio-ranges') or { return none }
	defer { unsafe { ranges.free() } }
	if ranges.len != 4 || ranges[1] != 0 || ranges[2] != 0 || pin >= ranges[3]
		|| u64(ranges[3]) > region.size / 4 {
		return none
	}
	range_provider := devicetree.find_phandle(ranges[0]) or { return none }
	if range_provider != provider {
		return none
	}
	return region
}

fn plan_pins(bus &devicetree.DTNode, mut plan Plan) bool {
	groups := devicetree.get_u32_array(bus, 'pinctrl-0') or { return false }
	defer { unsafe { groups.free() } }
	if groups.len == 0 || groups.len > 4 {
		return false
	}
	for handle in groups {
		group := devicetree.find_phandle(handle) or { return false }
		provider := group.parent
		if provider == unsafe { nil } || !enabled(group) || !plan_power(provider, 0, mut plan) {
			return false
		}
		pins := devicetree.get_u32_array(group, 'pinmux') or { return false }
		defer { unsafe { pins.free() } }
		if pins.len == 0 || pins.len > 8 {
			return false
		}
		for encoded in pins {
			// APPLE_PINMUX(pin, function) = pin | (function << 16).
			pin := encoded & 0xffff
			function := encoded >> 16
			region := gpio_region(provider, pin) or { return false }
			if function > 3 || plan.pins.len >= 16 {
				return false
			}
			plan.pins << PinMux{
				region:   region
				pin:      pin
				function: function
			}
		}
	}
	return true
}

fn dma_channel(mca &devicetree.DTNode, name string, admac_handle u32) ?u32 {
	names := devicetree.get_string_list(mca, 'dma-names') or { return none }
	defer { unsafe { names.free() } }
	cells := devicetree.get_u32_array(mca, 'dmas') or { return none }
	defer { unsafe { cells.free() } }
	if cells.len != names.len * 2 {
		return none
	}
	for index, value in names {
		if value == name && cells[index * 2] == admac_handle {
			return cells[index * 2 + 1]
		}
	}
	return none
}

fn plan_amp(node &devicetree.DTNode, index int, mut plan Plan) string {
	if !enabled(node) || !compatible(node, 'ti,tas2770')
		|| devicetree.get_u32(node, '#sound-dai-cells') or { u32(1) } != 0 {
		return 'speaker ${index} is not an enabled TAS2770-family amplifier'
	}
	reg := devicetree.get_u32_array(node, 'reg') or { return 'speaker ${index} has no address' }
	defer { unsafe { reg.free() } }
	imon := devicetree.get_u32(node, 'ti,imon-slot-no') or { u32(0xff) }
	vmon := devicetree.get_u32(node, 'ti,vmon-slot-no') or { u32(0xff) }
	if reg.len != 1 || reg[0] > 0x7f || imon > 0x3f || vmon > 0x3f {
		return 'speaker ${index} has no usable address or sense slots'
	}
	gpio := devicetree.get_u32_array(node, 'shutdown-gpios') or {
		return 'speaker ${index} has no shutdown GPIO'
	}
	defer { unsafe { gpio.free() } }
	if gpio.len != 3 || gpio[2] != 0 {
		return 'speaker ${index} shutdown GPIO is not active-high'
	}
	provider := devicetree.find_phandle(gpio[0]) or { return 'speaker GPIO provider missing' }
	region := gpio_region(provider, gpio[1]) or { return 'speaker GPIO is not an Apple pin' }
	if index == 0 {
		plan.gpio = region
		plan.gpio_pin = gpio[1]
		if !plan_power(provider, 0, mut plan) {
			return 'GPIO power domains unusable'
		}
	} else if region.base != plan.gpio.base || gpio[1] != plan.gpio_pin {
		// The two amplifiers share one shutdown line on the J313.
		return 'the amplifiers do not share one shutdown line'
	}
	bus := node.parent
	if bus == unsafe { nil } || !enabled(bus) || !compatible(bus, 'apple,t8103-i2c')
		|| devicetree.get_u32(bus, '#address-cells') or { u32(0) } != 1
		|| devicetree.get_u32(bus, '#size-cells') or { u32(1) } != 0 {
		return 'speaker ${index} is not on an enabled t8103 I2C bus'
	}
	plan.i2c[index] = only_region(bus, 0x30) or { return 'I2C bus ${index} registers unusable' }
	clocks := devicetree.get_u32_array(bus, 'clocks') or { return 'I2C bus has no clock' }
	defer { unsafe { clocks.free() } }
	if clocks.len != 1 {
		return 'I2C bus clock unsupported'
	}
	hz := fixed_clock_hz(clocks[0]) or { return 'I2C bus clock unsupported' }
	if index == 1 && hz != plan.i2c_ref_hz {
		return 'I2C bus clocks differ'
	}
	plan.i2c_ref_hz = hz
	if !plan_power(bus, 0, mut plan) {
		return 'I2C power domains unusable'
	}
	if (index == 0 || plan.i2c[1].base != plan.i2c[0].base) && !plan_pins(bus, mut plan) {
		return 'I2C pins unusable'
	}
	plan.address[index] = u8(reg[0])
	plan.imon[index] = u8(imon)
	plan.vmon[index] = u8(vmon)
	return ''
}

fn discover(root &devicetree.DTNode, mut plan Plan) string {
	sound := find_enabled(root, 'apple,j313-macaudio', 0) or {
		return 'no enabled apple,j313-macaudio sound node'
	}
	mut link := &devicetree.DTNode(unsafe { nil })
	for child in sound.children {
		name := devicetree.get_string_prop(child, 'link-name') or { continue }
		if name == 'Speakers' || name == 'Speaker' {
			link = child
		}
	}
	if link == unsafe { nil } {
		return 'the sound node has no Speakers link'
	}
	cpu := child_named(link, 'cpu') or { return 'Speakers link has no cpu' }
	codec := child_named(link, 'codec') or { return 'Speakers link has no codec' }
	cpu_dai := devicetree.get_u32_array(cpu, 'sound-dai') or { return 'no cpu sound-dai' }
	defer { unsafe { cpu_dai.free() } }
	codec_dai := devicetree.get_u32_array(codec, 'sound-dai') or { return 'no codec sound-dai' }
	defer { unsafe { codec_dai.free() } }
	if cpu_dai.len != 4 || cpu_dai[0] != cpu_dai[2] || cpu_dai[1] == cpu_dai[3]
		|| cpu_dai[1] > 5 || cpu_dai[3] > 5 || codec_dai.len != 2 {
		return 'Speakers link is not two MCA ports and two amplifiers'
	}
	plan.port_mask = (u32(1) << cpu_dai[1]) | (u32(1) << cpu_dai[3])

	mca := devicetree.find_phandle(cpu_dai[0]) or { return 'MCA missing' }
	if !enabled(mca) || !compatible(mca, 'apple,t8103-mca')
		|| devicetree.get_u32(mca, '#sound-dai-cells') or { u32(0) } != 1 {
		return 'MCA is not an enabled t8103 MCA'
	}
	regions := devicetree.get_translated_reg_ranges(mca) or { return 'MCA has no registers' }
	defer { unsafe { regions.free() } }
	if regions.len != 2 || !sane_region(regions[0], cluster_stride)
		|| regions[0].size % cluster_stride != 0 || !sane_region(regions[1], 0x8000) {
		return 'MCA registers unusable'
	}
	plan.mca_clusters = regions[0]
	plan.mca_switch = regions[1]
	plan.cluster_count = u32(regions[0].size / cluster_stride)
	if plan.cluster_count < 3 || plan.cluster_count > 6
		|| regions[1].size < u64(plan.cluster_count) * 0x8000
		|| plan.port_mask >> plan.cluster_count != 0
		|| plan.port_mask & (u32(1) << sense_cluster) != 0 {
		return 'MCA cluster layout unsupported'
	}

	clocks := devicetree.get_u32_array(mca, 'clocks') or { return 'MCA has no clocks' }
	defer { unsafe { clocks.free() } }
	if clocks.len != int(plan.cluster_count) * 2 || clocks[tx_cluster * 2] != clocks[sense_cluster * 2] {
		return 'MCA clocks unsupported'
	}
	plan.tx_nco = clocks[tx_cluster * 2 + 1]
	plan.sense_nco = clocks[sense_cluster * 2 + 1]
	nco := devicetree.find_phandle(clocks[tx_cluster * 2]) or { return 'NCO missing' }
	if !enabled(nco) || !compatible(nco, 'apple,t8103-nco')
		|| devicetree.get_u32(nco, '#clock-cells') or { u32(0) } != 1 {
		return 'NCO is not an enabled t8103 NCO'
	}
	plan.nco = only_region(nco, nco_stride) or { return 'NCO registers unusable' }
	plan.nco_count = u32((plan.nco.size + nco_stride - 0x14) / nco_stride)
	if plan.tx_nco >= plan.nco_count || plan.sense_nco >= plan.nco_count {
		return 'NCO channel out of range'
	}
	nco_parent := devicetree.get_u32_array(nco, 'clocks') or { return 'NCO has no reference' }
	defer { unsafe { nco_parent.free() } }
	if nco_parent.len != 1 {
		return 'NCO reference unsupported'
	}
	plan.nco_ref_hz = fixed_clock_hz(nco_parent[0]) or { return 'NCO reference unsupported' }

	dmas := devicetree.get_u32_array(mca, 'dmas') or { return 'MCA has no DMA' }
	defer { unsafe { dmas.free() } }
	if dmas.len < 2 {
		return 'MCA has no DMA'
	}
	admac_handle := dmas[0]
	plan.tx_dma = dma_channel(mca, tx_dma_name, admac_handle) or { return 'no ${tx_dma_name} DMA' }
	plan.sense_dma = dma_channel(mca, sense_dma_name, admac_handle) or {
		return 'no ${sense_dma_name} DMA'
	}
	admac := devicetree.find_phandle(admac_handle) or { return 'ADMAC missing' }
	if !enabled(admac) || !compatible(admac, 'apple,t8103-admac')
		|| devicetree.get_u32(admac, '#dma-cells') or { u32(0) } != 1 {
		return 'ADMAC is not an enabled t8103 ADMAC'
	}
	plan.admac = only_region(admac, 0x20000) or { return 'ADMAC registers unusable' }
	plan.admac_count = devicetree.get_u32(admac, 'dma-channels') or { u32(0) }
	if plan.admac_count == 0 || plan.admac_count > 64 || plan.tx_dma >= plan.admac_count
		|| plan.sense_dma >= plan.admac_count || plan.tx_dma & 1 != 0 || plan.sense_dma & 1 != 1 {
		return 'ADMAC channels unusable'
	}
	iommu := devicetree.get_u32_array(admac, 'iommus') or { return 'ADMAC has no IOMMU' }
	defer { unsafe { iommu.free() } }
	if iommu.len != 2 || iommu[1] > 15 {
		return 'ADMAC IOMMU unsupported'
	}
	dart_node := devicetree.find_phandle(iommu[0]) or { return 'SIO DART missing' }
	if !enabled(dart_node) || !compatible(dart_node, 'apple,t8103-dart')
		|| devicetree.get_u32(dart_node, '#iommu-cells') or { u32(0) } != 1 {
		return 'SIO DART is not an enabled t8103 DART'
	}
	plan.dart = only_region(dart_node, 0x4000) or { return 'SIO DART registers unusable' }
	plan.dart_stream = iommu[1]

	// Power: everything but the clusters now; those only once they are
	// clocked, when a stream starts.
	domains := devicetree.get_u32_array(mca, 'power-domains') or { return 'MCA has no power' }
	defer { unsafe { domains.free() } }
	if domains.len != int(plan.cluster_count) + 1 {
		return 'MCA power domains unsupported'
	}
	if !plan_domain(domains[0], 0, mut plan) || !plan_power(admac, 0, mut plan)
		|| !plan_power(dart_node, 0, mut plan) {
		return 'audio power domains unusable'
	}
	for i, cluster in [tx_cluster, sense_cluster] {
		handle := domains[cluster + 1]
		node := devicetree.find_phandle(handle) or { return 'cluster power domain missing' }
		if !has_property(node, 'apple,externally-clocked') || !plan_power(node, 0, mut plan) {
			return 'cluster power domain unsupported'
		}
		plan.cluster_power[i] = pwrstate(handle) or { return 'cluster power domain unusable' }
	}
	mca_reset := devicetree.get_u32_array(mca, 'resets') or { return 'MCA has no reset' }
	defer { unsafe { mca_reset.free() } }
	admac_reset := devicetree.get_u32_array(admac, 'resets') or { return 'ADMAC has no reset' }
	defer { unsafe { admac_reset.free() } }
	if mca_reset.len != 1 || admac_reset.len != 1 || mca_reset[0] != admac_reset[0]
		|| !planned(plan, mca_reset[0]) {
		return 'audio reset unsupported'
	}
	plan.reset = pwrstate(mca_reset[0]) or { return 'audio reset unusable' }

	for index in 0 .. 2 {
		amp := devicetree.find_phandle(codec_dai[index]) or { return 'amplifier ${index} missing' }
		reason := plan_amp(amp, index, mut plan)
		if reason != '' {
			return reason
		}
	}
	return ''
}

// ---- bring-up ----

pub fn initialise() {
	$if no_apple_speakers ? {
		println('apple-speakers: disabled at build time')
	} $else {
		initialise_hardware()
	}
}

fn initialise_hardware() {
	root := devicetree.find_node('/') or { return }
	if !compatible(root, 'apple,j313') || !compatible(root, 'apple,t8103') {
		// The protection parameters are the J313's; nothing else is safe.
		return
	}
	mut plan := Plan{}
	reason := discover(root, mut plan)
	if reason != '' {
		println('apple-speakers: ${reason}; speakers off')
		unsafe {
			plan.pins.free()
			plan.power.free()
		}
		return
	}
	speaker_plan = plan

	for d in plan.power {
		if !pmgr.enable_region(d.region.base, d.region.size, d.offset) {
			println('apple-speakers: power domain 0x${d.offset:x} did not come up; speakers off')
			return
		}
	}
	if !pmgr.reset_region(plan.reset.region.base, plan.reset.region.size, plan.reset.offset) {
		println('apple-speakers: audio block reset failed; speakers off')
		return
	}
	for pin in plan.pins {
		base := memory.map_mmio(pin.region.base, pin.region.size)
		reg := unsafe { &u32(base + u64(pin.pin) * 4) }
		value := kio.mmin32(reg)
		// Select the peripheral and enable the input, as Linux's pinmux does.
		kio.mmout32(reg, (value & ~u32((3 << 5) | (1 << 9))) | (pin.function << 5) | (u32(1) << 9))
	}

	tx_phys, sense_phys := allocate_rings() or {
		println('apple-speakers: no memory for the DMA rings; speakers off')
		return
	}
	mut iommu := dart.new_dart(plan.dart.base, u8(plan.dart_stream))
	if !iommu.init_preserving() || !iommu.map(tx_iova, tx_phys, tx_ring_bytes)
		|| !iommu.map(sense_iova, sense_phys, sense_ring_bytes) {
		println('apple-speakers: SIO DART stream ${plan.dart_stream} unusable; speakers off')
		return
	}

	hhdm := memory.get_hhdm_offset()
	mut cfg := C.vinix_apple_speakers_config{}
	cfg.mca_clusters = memory.map_mmio(plan.mca_clusters.base, plan.mca_clusters.size)
	cfg.mca_cluster_count = plan.cluster_count
	cfg.mca_switch = memory.map_mmio(plan.mca_switch.base, plan.mca_switch.size)
	cfg.admac = memory.map_mmio(plan.admac.base, plan.admac.size)
	cfg.admac_channels = plan.admac_count
	cfg.nco = memory.map_mmio(plan.nco.base, plan.nco.size)
	cfg.nco_channels = plan.nco_count
	cfg.nco_ref_hz = plan.nco_ref_hz
	cfg.tx_cluster = tx_cluster
	cfg.sense_cluster = sense_cluster
	cfg.tx_nco = plan.tx_nco
	cfg.sense_nco = plan.sense_nco
	cfg.tx_dma = plan.tx_dma
	cfg.sense_dma = plan.sense_dma
	cfg.port_mask = plan.port_mask
	for i in 0 .. 2 {
		cfg.i2c[i] = memory.map_mmio(plan.i2c[i].base, plan.i2c[i].size)
		cfg.amp_address[i] = plan.address[i]
		cfg.imon_slot[i] = plan.imon[i]
		cfg.vmon_slot[i] = plan.vmon[i]
	}
	cfg.i2c_ref_hz = plan.i2c_ref_hz
	cfg.shutdown_gpio = memory.map_mmio(plan.gpio.base, plan.gpio.size) + u64(plan.gpio_pin) * 4
	cfg.tx_buffer = tx_phys + hhdm
	cfg.tx_iova = tx_iova
	cfg.tx_bytes = u32(tx_ring_bytes)
	cfg.sense_buffer = sense_phys + hhdm
	cfg.sense_iova = sense_iova
	cfg.sense_bytes = u32(sense_ring_bytes)
	ok := C.vinix_apple_speakers_init(&cfg) != 0
	print_events()
	if !ok {
		println('apple-speakers: amplifier or DMA setup failed; speakers off')
		return
	}
	speaker_present = true
	// Globals start zeroed, whatever the struct's defaults say.
	speaker_stream.rate = 48000
	speaker_stream.level = 100
	println('apple-speakers: MacBook Air J313 speakers on MCA ports 0x${plan.port_mask:x}, amplifiers 0x${plan.address[0]:x} and 0x${plan.address[1]:x}; output held at -20 dB until the sense data checks out')
	oss.create_device(&speaker_card)
	spawn service_thread()
}

fn allocate_rings() ?(u64, u64) {
	align := dma_alignment / memory.page_size
	tx := u64(memory.pmm_alloc_aligned_fallible(tx_ring_bytes / memory.page_size,
		if align == 0 { 1 } else { align }))
	sense := u64(memory.pmm_alloc_aligned_fallible(sense_ring_bytes / memory.page_size,
		if align == 0 { 1 } else { align }))
	if tx == 0 || sense == 0 {
		return none
	}
	return tx, sense
}

// ---- driver messages ----

fn take_event(mut e [3]i32) bool {
	mut s := &speaker_stream
	s.lock()
	taken := C.vinix_apple_speakers_take_event(&e[0]) != 0
	s.unlock()
	return taken
}

fn print_events() {
	mut e := [3]i32{}
	for take_event(mut e) {
		code := int(e[0])
		side := if e[1] == 0 { 'left' } else { 'right' }
		if code == ev_amp {
			println('apple-speakers: ${side} amplifier ready (revision 0x${e[2]:x})')
		} else if code == ev_verified {
			println('apple-speakers: sense data tracks the output; protection model in control')
		} else if code == ev_stale {
			println('apple-speakers: no sense data for ${e[1]} ms; output held at -20 dB')
		} else if code == ev_dead {
			println('apple-speakers: ${side} speaker measured no voltage while playing; output held at -20 dB')
		} else if code == ev_gain {
			if e[1] == 0 {
				println('apple-speakers: speakers cool; full volume available')
			} else {
				tenths := -e[1] / 100
				println('apple-speakers: speakers warm; limited to -${tenths / 10}.${tenths % 10} dB')
			}
		} else if code == ev_fault_temp {
			println('apple-speakers: ${side} speaker model reached ${e[2] / 1000} C; amplifiers shut down until reboot')
		} else if code == ev_fault_power {
			println('apple-speakers: ${side} speaker sense implies ${e[2]} mW; amplifiers shut down until reboot')
		} else if code == ev_fault_i2c {
			println('apple-speakers: ${side} amplifier I2C error ${e[2]}')
		} else if code == ev_dma_error {
			println('apple-speakers: ADMAC channel ${e[1]} ring error')
		} else if code == ev_serdes {
			println('apple-speakers: MCA cluster ${e[1]} serializer did not leave reset')
		}
	}
}

// ---- the service thread ----

fn (mut s SpeakerStream) lock() {
	for !katomic.cas(mut s.mutex, u64(0), u64(1)) {
		sys.nsleep(speaker_poll_ns)
	}
}

fn (mut s SpeakerStream) unlock() {
	katomic.store(mut s.mutex, u64(0))
}

// A stream that will not start once will not start the next time either:
// shut the amplifiers down rather than retry behind every write.
fn start_locked() {
	mask := C.vinix_apple_speakers_start_clocks()
	if mask == 0 {
		if C.vinix_apple_speakers_faulted() == 0 {
			println('apple-speakers: clocks did not start; speakers off')
		}
		C.vinix_apple_speakers_fail()
		return
	}
	for i, cluster in [tx_cluster, sense_cluster] {
		if mask & (u32(1) << cluster) == 0 {
			continue
		}
		d := speaker_plan.cluster_power[i]
		if !pmgr.enable_region_externally_clocked(d.region.base, d.region.size, d.offset) {
			println('apple-speakers: MCA cluster ${cluster} did not power up; speakers off')
			C.vinix_apple_speakers_stop()
			C.vinix_apple_speakers_fail()
			return
		}
	}
	if C.vinix_apple_speakers_start_stream() == 0 {
		C.vinix_apple_speakers_stop()
		C.vinix_apple_speakers_fail()
	}
}

fn service_thread() {
	mut faulted := false
	for {
		mut s := &speaker_stream
		s.lock()
		if C.vinix_apple_speakers_wants_start() != 0 {
			start_locked()
		}
		flags := C.vinix_apple_speakers_service()
		if flags & service_idle != 0 {
			// Seconds of nothing but silence: let the amplifiers rest. The
			// next write starts a new stream.
			C.vinix_apple_speakers_stop()
		}
		s.unlock()
		print_events()
		if flags & service_fault != 0 && !faulted {
			faulted = true
			mut st := C.vinix_apple_speakers_status{}
			C.vinix_apple_speakers_get_status(&st)
			println('apple-speakers: stopped; modelled coil ${st.coil_mc[0] / 1000}/${st.coil_mc[1] / 1000} C')
		}
		sys.nsleep(if flags & service_running != 0 { running_period_ns } else { idle_period_ns })
	}
}

// ---- oss.OssAudioDevice ----

fn (c SpeakerCard) get_output_stream() &oss.OssAudioStream {
	return &speaker_stream
}

fn (c SpeakerCard) name() string {
	return 'apple-j313'
}

fn (c SpeakerCard) formats() u32 {
	return oss.afmt_s16_le
}

fn (c SpeakerCard) refine_fmt(fmt u32) u32 {
	return oss.afmt_s16_le
}

fn (c SpeakerCard) refine_rate(rate u32) u32 {
	return if rate <= 46050 { u32(44100) } else { u32(48000) }
}

fn (c SpeakerCard) refine_channels(channels u8) u8 {
	return 2
}

// ---- oss.OssAudioStream ----

enum Nap {
	slept
	signalled
	fatal
}

fn nap(ns i64) Nap {
	mut timer := time.new_timer(time.TimeSpec{
		tv_sec:  ns / 1000000000
		tv_nsec: ns % 1000000000
	})
	defer {
		timer.disarm()
		unsafe { free(timer) }
	}
	mut events := [&timer.event]
	defer {
		unsafe { events.free() }
	}
	event.await(mut events, true) or { return pending_signal() }
	return .slept
}

// As in virtio_snd: a wakeup alone means nothing, since SDL's audio thread
// blocks nearly every signal; only a deliverable one counts.
fn pending_signal() Nap {
	t := proc.current_thread()
	pending := katomic.load(&t.pending_signals) & ~t.masked_signals
	if pending == 0 {
		return .slept
	}
	for signal := 1; signal <= 64; signal++ {
		if pending & (u64(1) << (signal - 1)) != 0
			&& t.sigactions[signal].sa_sigaction == userland.sig_dfl {
			return .fatal
		}
	}
	return .signalled
}

fn (mut s SpeakerStream) setup_params(fmt u32, rate u32, channels u8) {
	s.lock()
	defer {
		s.unlock()
	}
	if C.vinix_apple_speakers_active() != 0 {
		C.vinix_apple_speakers_stop()
	}
	s.rate = speaker_card.refine_rate(rate)
	if C.vinix_apple_speakers_configure(s.rate) == 0 && C.vinix_apple_speakers_faulted() == 0 {
		println('apple-speakers: cannot play ${rate} Hz')
	}
}

fn (mut s SpeakerStream) change_volume(percentage int) {
	s.level = if percentage < 0 {
		0
	} else if percentage > 100 {
		100
	} else {
		percentage
	}
	s.lock()
	C.vinix_apple_speakers_set_volume(u32(s.level))
	s.unlock()
}

fn (s SpeakerStream) volume() int {
	return s.level
}

fn (mut s SpeakerStream) play(play bool) {
	if play {
		return // a stream starts by itself once there is something to play
	}
	s.lock()
	C.vinix_apple_speakers_stop()
	s.unlock()
}

fn (mut s SpeakerStream) reset() {
	s.lock()
	C.vinix_apple_speakers_stop()
	s.unlock()
}

fn (s SpeakerStream) is_playing() bool {
	return C.vinix_apple_speakers_active() != 0
}

fn (mut s SpeakerStream) writable() u64 {
	s.lock()
	defer {
		s.unlock()
	}
	if C.vinix_apple_speakers_active() == 0 {
		// The first write configures the stream and always has room.
		return ring_room_unconfigured
	}
	return u64(C.vinix_apple_speakers_room())
}

fn (mut s SpeakerStream) sync_write(buf voidptr, _loc u64, count u64) ?i64 {
	// Linux restarts a sound write that a handled signal interrupts; Vinix
	// cannot, and SDL takes a failed write for a lost card. So, as in
	// virtio_snd, a write no longer than the ring finishes first.
	can_finish := count <= tx_ring_bytes
	mut done := u64(0)
	mut last_progress := time.monotonic_ns()
	for done < count {
		s.lock()
		if C.vinix_apple_speakers_faulted() != 0 {
			s.unlock()
			if done > 0 {
				return i64(done)
			}
			errno.set(errno.eio)
			return none
		}
		if C.vinix_apple_speakers_active() == 0 {
			// Stopped under the writer (silence or a drain): start over.
			C.vinix_apple_speakers_configure(s.rate)
		}
		mut length := u32(0)
		region := C.vinix_apple_speakers_reserve(&length)
		s.unlock()
		if length == 0 {
			if time.monotonic_ns() - last_progress > drain_stall_ns {
				print('apple-speakers: playback stopped moving\n')
				s.lock()
				C.vinix_apple_speakers_commit(0)
				s.unlock()
				if done > 0 {
					return i64(done)
				}
				errno.set(errno.eio)
				return none
			}
			s.lock()
			C.vinix_apple_speakers_commit(0)
			s.unlock()
			match nap(running_period_ns) {
				.slept {}
				.signalled {
					if !can_finish {
						if done > 0 {
							return i64(done)
						}
						errno.set(errno.eintr)
						return none
					}
				}
				.fatal {
					if done > 0 {
						return i64(done)
					}
					errno.set(errno.eintr)
					return none
				}
			}
			continue
		}
		mut n := u64(length)
		if n > count - done {
			n = count - done
		}
		copied := usercopy.copy_from_user(voidptr(region), u64(buf) + done, n)
		s.lock()
		C.vinix_apple_speakers_commit(if copied { u32(n) } else { u32(0) })
		s.unlock()
		if !copied {
			if done > 0 {
				return i64(done)
			}
			errno.set(errno.efault)
			return none
		}
		done += n
		last_progress = time.monotonic_ns()
	}
	return i64(done)
}

fn (mut s SpeakerStream) wait_until_empty() {
	s.lock()
	if C.vinix_apple_speakers_active() == 0 {
		s.unlock()
		return
	}
	C.vinix_apple_speakers_drain()
	s.unlock()
	start := time.monotonic_ns()
	for {
		s.lock()
		done := C.vinix_apple_speakers_drained() != 0 || C.vinix_apple_speakers_faulted() != 0
		s.unlock()
		if done {
			break
		}
		if time.monotonic_ns() - start > drain_stall_ns {
			print('apple-speakers: drain did not finish\n')
			break
		}
		if nap(running_period_ns) == .fatal {
			break
		}
	}
	nap(drain_tail_ns)
	s.lock()
	C.vinix_apple_speakers_stop()
	s.unlock()
}
