// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// An HD Audio controller across a sleep.
//
// Nearly every PC has one, and a driver that could not take it through a
// loss of power kept all of them from a suspend to RAM. What the controller
// and the codecs on its link hold is all set by this driver, so nothing is
// read out of them to be put back: going down, the streams are stopped, the
// interrupt and the command rings switched off and the controller put into
// reset, which takes the link and the codecs down with it; coming back, the
// controller is taken out of reset and told again, from what the driver
// keeps, where its rings and each stream's buffers are, and the codecs are
// powered and their output paths programmed as the last program to set a
// format left them. That is the same after a suspend to idle and after a
// suspend to RAM, so resume does not ask which it was.
//
// Sound that was queued when the machine went down is dropped: the link's
// position starts again from nothing, and what a stream had left to play no
// longer lines up with it. A stream that was playing starts empty, and a
// program blocked on a full buffer finds room.
module hda

import devcore
import event
import katomic

// How long the controller may take to go into reset and to come out of it.
// The specification wants it within 100 microseconds; this allows for a slow
// one and still ends.
const reset_timeout_ns = 100 * devcore.millisecond
// What the controller needs in reset before it is taken out again.
const reset_hold_ns = 200 * devcore.microsecond
// What codecs need after the link is up before they take a command: 521
// microseconds by the specification, a millisecond here as at boot.
const codec_settle_ms = u64(1)

fn controller_in_reset(context voidptr) bool {
	mut volatile regs := unsafe { &HDARegisters(context) }
	return regs.gctl & gctl_crst == 0
}

fn controller_out_of_reset(context voidptr) bool {
	mut volatile regs := unsafe { &HDARegisters(context) }
	return regs.gctl & gctl_crst != 0
}

fn stream_in_reset(context voidptr) bool {
	mut volatile regs := unsafe { &HDAStreamRegisters(context) }
	return regs.ctl0 & sdctl0_srst != 0
}

fn stream_out_of_reset(context voidptr) bool {
	mut volatile regs := unsafe { &HDAStreamRegisters(context) }
	return regs.ctl0 & sdctl0_srst == 0
}

// The code the ring size registers take for a ring of `entries`.
fn ring_size_code(entries u16) u8 {
	return if entries == 256 {
		u8(0b10)
	} else if entries == 16 {
		u8(0b1)
	} else {
		u8(0)
	}
}

// A stream stopped for a sleep: whether it was playing, and the format its
// register held, which the controller forgets.
fn (mut s HDAStream) put_down() {
	s.was_playing = s.is_playing()
	s.kept_format = s.regs.fmt
	s.play(false)
}

// Tell the controller about the stream again. One that was playing starts
// from an empty buffer.
fn (mut s HDAStream) bring_up() {
	// A stream is reset before its registers are written: whatever state the
	// controller came back with is not one this driver put it in.
	s.regs.ctl0 = s.regs.ctl0 | sdctl0_srst
	devcore.spin_until(stream_in_reset, voidptr(s.regs), reset_timeout_ns)
	s.regs.ctl0 = s.regs.ctl0 & ~sdctl0_srst
	devcore.spin_until(stream_out_of_reset, voidptr(s.regs), reset_timeout_ns)
	s.initialize_output()
	s.regs.fmt = s.kept_format
	if s.was_playing {
		s.was_playing = false
		s.cur_user_pos = 0
		katomic.store(mut &s.remaining_data, u32(0))
		event.trigger(mut s.event, true)
	}
}

// Power a codec's audio function groups again, and put its output paths
// back as the last format set left them.
fn (mut c HDACodec) bring_up() {
	groups := c.get_parameter(0, param_node_count)
	count := u8(groups & 0xff)
	first := u8((groups >> 16) & 0xff)
	for nid := first; nid < first + count; nid++ {
		if u8(c.get_parameter(nid, param_func_group_type) & 0xff) != func_group_type_audio {
			continue
		}
		c.set_power_state(nid, power_state_d0)
	}
	stream := &c.controller.out_streams[0]
	if stream.configured {
		c.setup_all_output_paths(stream.kept_rate, stream.kept_bits, stream.kept_channels)
	}
}

fn controller_suspend(mut dev devcore.Device) bool {
	mut c := unsafe { &HDAController(dev.driver_data) }
	if c == unsafe { nil } || c.regs == unsafe { nil } {
		return true
	}
	for i in 0 .. c.in_stream_count {
		c.in_streams[i].put_down()
	}
	for i in 0 .. c.out_stream_count {
		c.out_streams[i].put_down()
	}
	c.regs.intctl = 0
	c.regs.corbctl = c.regs.corbctl & ~u8(corbctl_run)
	c.regs.rirbctl = c.regs.rirbctl & ~u8(corbctl_run)
	// Into reset: the link goes quiet and the codecs with it.
	c.regs.gctl = c.regs.gctl & ~u32(gctl_crst)
	devcore.spin_until(controller_in_reset, voidptr(c.regs), reset_timeout_ns)
	return true
}

fn controller_resume(mut dev devcore.Device) bool {
	mut c := unsafe { &HDAController(dev.driver_data) }
	if c == unsafe { nil } || c.regs == unsafe { nil } {
		return true
	}
	// Memory decoding and bus mastering, which a loss of power clears and
	// the device core's restore of configuration space may not have set.
	dev.pci.update_command(0, 0x6)

	c.regs.gctl = c.regs.gctl & ~u32(gctl_crst)
	if !devcore.spin_until(controller_in_reset, voidptr(c.regs), reset_timeout_ns) {
		return false
	}
	devcore.stall(reset_hold_ns)
	c.regs.gctl = c.regs.gctl | u32(gctl_crst)
	if !devcore.spin_until(controller_out_of_reset, voidptr(c.regs), reset_timeout_ns) {
		return false
	}

	// The rings, where they were and as long as they were.
	mut corb_size := c.regs.corbsize
	corb_size &= ~(corbsize_size_mask << corbsize_size_shift)
	corb_size |= ring_size_code(c.corb_size) << corbsize_size_shift
	c.regs.corbsize = corb_size
	mut rirb_size := c.regs.rirbsize
	rirb_size &= ~(corbsize_size_mask << corbsize_size_shift)
	rirb_size |= ring_size_code(c.rirb_size) << corbsize_size_shift
	c.regs.rirbsize = rirb_size
	corb_phys := u64(c.corb) - higher_half
	rirb_phys := u64(c.rirb) - higher_half
	positions_phys := u64(c.dma_pos) - higher_half
	c.regs.corblbase = u32(corb_phys)
	c.regs.corbubase = u32(corb_phys >> 32)
	c.regs.rirblbase = u32(rirb_phys)
	c.regs.rirbubase = u32(rirb_phys >> 32)
	c.regs.dplbase = u32(positions_phys)
	c.regs.dpubase = u32(positions_phys >> 32)
	c.regs.dplbase = c.regs.dplbase | u32(dplbase_dpbe)
	c.regs.corbctl = c.regs.corbctl | u8(corbctl_run)
	c.regs.rirbctl = c.regs.rirbctl | u8(corbctl_run)
	c.regs.rintcnt = c.regs.rintcnt | 0xff

	for i in 0 .. c.in_stream_count {
		c.in_streams[i].bring_up()
	}
	for i in 0 .. c.out_stream_count {
		c.out_streams[i].bring_up()
	}

	streams := (u32(1) << (c.in_stream_count + c.out_stream_count)) - 1
	c.regs.intctl = c.regs.intctl | intctl_gie | intctl_cie | streams

	devcore.sleep_ms(codec_settle_ms)
	for mut codec in c.codecs {
		codec.bring_up()
	}
	return true
}

// Before power off or a restart: no stream running, no interrupt, and the
// controller in reset, as firmware expects to find it.
fn controller_shutdown(mut dev devcore.Device) {
	controller_suspend(mut dev)
}
