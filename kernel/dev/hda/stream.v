module hda

import devcore
import memory
import dev.oss
import event.eventstruct
import event
import katomic

struct HDABufferDescriptor {
pub mut:
	address u64
	length  u32
	ioc     u32
}

const max_buffer_descriptors = page_size / sizeof(HDABufferDescriptor)
const total_buffer_size = max_buffer_descriptors * page_size
const chunk_size = page_size

struct HDAStream {
pub mut:
	volatile regs           &HDAStreamRegisters
	volatile dma_pos        &u32
	controller     &HDAController
	bdl            &HDABufferDescriptor
	event          eventstruct.Event
	bdl_phys       u64
	cur_user_pos   u32
	remaining_data u32
	// Where the controller was at the last interrupt: what it has played
	// since is zeroed and taken off remaining_data.
	hw_pos u32
	cur_volume     u32
	channels       u8
	is_output      bool
	// For a sleep (power.v): the last format a program set, which the codecs
	// are told again afterwards, and what the stream was doing when the
	// machine went down.
	configured    bool
	kept_rate     u32
	kept_bits     u8
	kept_channels u8
	kept_format   u16
	was_playing   bool
}

fn (mut s HDAStream) initialize_output() {
	s.regs.bdpl = u32(s.bdl_phys)
	s.regs.bdpu = u32(s.bdl_phys >> 32)

	if s.is_output {
		mut ctl2 := s.regs.ctl2
		ctl2 &= ~(sdctl2_strm_mask << sdctl2_strm_shift)
		ctl2 |= 1 << sdctl2_strm_shift
		s.regs.ctl2 = ctl2

		mut ctl0 := s.regs.ctl0
		ctl0 |= sdctl0_ioce
		s.regs.ctl0 = ctl0

		// cyclic buffer length
		s.regs.cbl = u32(max_buffer_descriptors * 0x1000)

		// 256 entries
		mut lvi := s.regs.lvi
		lvi &= ~(sdlvi_lvi_mask << sdlvi_lvi_shift)
		lvi |= 0xFF << sdlvi_lvi_shift
		s.regs.lvi = lvi
	}
}

pub fn (mut s HDAStream) initialize(index u8, is_output bool) {
	bdl_phys := u64(memory.pmm_alloc(1))
	s.bdl = unsafe { &HDABufferDescriptor(bdl_phys + higher_half) }
	s.bdl_phys = bdl_phys
	s.is_output = is_output

	s.dma_pos = unsafe {
		if is_output {
			&s.controller.dma_pos[(s.controller.in_stream_count * 2 + index * 2)]
		} else {
			&s.controller.dma_pos[2 * index]
		}
	}

	for i in 0 .. max_buffer_descriptors {
		unsafe {
			s.bdl[i].address = u64(memory.pmm_alloc(1))
			s.bdl[i].length = u32(page_size)
			// Every page interrupts, the first as well: accounting follows the
			// controller's position, and a long gap between interrupts only
			// delays the silence that replaces what was played.
			s.bdl[i].ioc = 1
			C.memset(voidptr(s.bdl[i].address + higher_half), 0, page_size)
		}
	}

	s.initialize_output()
}

fn (s HDAStream) hda_get_format() PCMFormat {
	return PCMFormat{
		value: s.regs.fmt
	}
}

fn (mut s HDAStream) hda_set_format(fmt PCMFormat) {
	s.regs.fmt = fmt.value
}

fn (mut s HDAStream) setup_params(fmt u32, rate u32, channels u8) {
	mut bits := u8(0)

	match fmt {
		oss.afmt_u8 {
			bits = 8
		}
		oss.afmt_s16_le {
			bits = 16
		}
		oss.afmt_s8 {
			bits = 8
		}
		oss.afmt_u16_le {
			bits = 16
		}
		oss.afmt_s32_le {
			bits = 32
		}
		else {
			return
		}
	}

	mut hda_fmt := s.hda_get_format()
	hda_fmt.set_sample_rate(rate)
	hda_fmt.set_bits_per_sample(bits)
	hda_fmt.set_num_channels(channels)
	s.hda_set_format(hda_fmt)
	s.configured = true
	s.kept_rate = rate
	s.kept_bits = bits
	s.kept_channels = channels

	for mut codec in s.controller.codecs {
		codec.setup_all_output_paths(rate, bits, channels)
	}
}

fn (s HDAStream) volume() int {
	return int(s.cur_volume)
}

fn (mut s HDAStream) writable() u64 {
	return u64(total_buffer_size) - u64(katomic.load(&s.remaining_data))
}

fn (mut s HDAStream) change_volume(percentage int) {
	s.cur_volume = u32(percentage)

	for mut codec in s.controller.codecs {
		for path in codec.non_overlapping_output_paths {
			for widget in path.widgets {
				if widget.widget_type == widget_type_audio_out {
					max_val := widget.out_amp_caps & 0x7F

					mut one_percentage := max_val / 100
					if one_percentage == 0 {
						one_percentage = 1
					}
					mut value := one_percentage * u32(percentage)
					if value > max_val {
						value = max_val
					}

					// set output amp, set left amp, set right amp and gain
					amp_data := u16(1 << 15 | 1 << 13 | 1 << 12 | value)
					codec.set_amp_gain_mute(widget.nid, amp_data)
				}
			}
		}
	}
}

fn (mut s HDAStream) play(play bool) {
	mut ctl0 := s.regs.ctl0
	if (ctl0 & sdctl0_run) == 0 && play {
		ctl0 |= sdctl0_run
		s.regs.ctl0 = ctl0
	} else if (ctl0 & sdctl0_run) != 0 && !play {
		ctl0 &= ~sdctl0_run
		s.regs.ctl0 = ctl0
	}
}

fn (mut s HDAStream) reset() {
	assert (s.regs.ctl0 & sdctl0_run) == 0, 'stream must be stopped prior to resetting'

	// By the clock: this is reached from a program closing the device, and a
	// controller that has stopped answering must not keep it for ever.
	s.regs.ctl0 |= sdctl0_srst
	devcore.spin_until(stream_in_reset, voidptr(s.regs), reset_timeout_ns)

	s.regs.ctl0 &= ~sdctl0_srst
	devcore.spin_until(stream_out_of_reset, voidptr(s.regs), reset_timeout_ns)

	s.initialize_output()
	s.forget_ring()
}

// An empty, silent ring at its start, as after a reset of the stream:
// nothing queued, and nothing left from before to be played.
fn (mut s HDAStream) forget_ring() {
	s.cur_user_pos = 0
	s.hw_pos = 0
	katomic.store(mut &s.remaining_data, u32(0))
	s.clear_ring(0, u32(total_buffer_size))
}

fn (s HDAStream) is_playing() bool {
	return s.regs.ctl0 & sdctl0_run != 0
}

fn (mut s HDAStream) sync_write(buf voidptr, _loc u64, count u64) ?i64 {
	mut first_write := false
	// A stream that ran dry has kept going over silence, past where the last
	// write ended. Queue new sound from the page after the controller's
	// position, counting the silence before it, or it would wait a whole
	// turn of the ring.
	if s.regs.ctl0 & sdctl0_run != 0 && katomic.load(&s.remaining_data) == 0 {
		pos := s.position()
		next := (pos / u32(page_size) + 1) * u32(page_size)
		if katomic.cas(mut s.remaining_data, 0, next - pos) {
			s.cur_user_pos = next % u32(total_buffer_size)
		}
	}

	mut i := u64(0)
	for {
		if i == count {
			break
		}

		s_remaining := katomic.load(&s.remaining_data)

		if s.regs.ctl0 & sdctl0_run != 0 && s_remaining == total_buffer_size {
			event.await_one(mut s.event, true) or {}
		}

		to_copy := if i + (total_buffer_size - s_remaining) > count {
			count - i
		} else {
			total_buffer_size - s_remaining
		}

		mut progress := u64(0)
		for {
			if progress == to_copy {
				break
			}

			desc_index := s.cur_user_pos / page_size
			desc_offset := s.cur_user_pos % page_size

			remaining := to_copy - progress
			small_chunk_size := if remaining < (page_size - desc_offset) {
				remaining
			} else {
				page_size - desc_offset
			}

			unsafe {
				desc := &s.bdl[desc_index]
				ptr := voidptr(desc.address + desc_offset + higher_half)
				C.memcpy(ptr, voidptr(uint(buf) + i + progress), small_chunk_size)
			}
			s.cur_user_pos += u32(small_chunk_size)
			if s.cur_user_pos == u32(total_buffer_size) {
				s.cur_user_pos = 0
			}

			progress += small_chunk_size
		}

		for {
			old := katomic.load(&s.remaining_data)
			if katomic.cas(mut s.remaining_data, old, old + u32(to_copy)) {
				break
			}
		}

		if s.regs.ctl0 & sdctl0_run == 0 && s.remaining_data >= chunk_size * 2 {
			s.play(true)
			first_write = true
		}

		i += to_copy
	}

	if first_write {
		for {
			s_remaining := katomic.load(&s.remaining_data)
			if s_remaining <= chunk_size * 2 {
				break
			}
			event.await_one(mut s.event, true) or {}
		}
	}

	return count
}

fn (mut s HDAStream) wait_until_empty() {
	for {
		s_remaining := katomic.load(&s.remaining_data)
		if s_remaining == 0 {
			break
		}
		// A write starts the stream only once two pages are queued. Less than
		// that, waited for here, would never be played and never interrupt.
		if s.regs.ctl0 & sdctl0_run == 0 {
			s.play(true)
		} else if s_remaining <= u32(total_buffer_size - chunk_size) {
			mut progress := u64(0)
			for {
				if progress == chunk_size {
					break
				}

				desc_index := s.cur_user_pos / page_size
				desc_offset := s.cur_user_pos % page_size

				remaining := chunk_size - progress
				small_chunk_size := if remaining < (page_size - desc_offset) {
					remaining
				} else {
					page_size - desc_offset
				}

				unsafe {
					desc := &s.bdl[desc_index]
					ptr := voidptr(desc.address + desc_offset + higher_half)
					C.memset(ptr, 0, small_chunk_size)
				}
				s.cur_user_pos += u32(small_chunk_size)
				if s.cur_user_pos == u32(total_buffer_size) {
					s.cur_user_pos = 0
				}

				progress += small_chunk_size
			}
		}

		event.await_one(mut s.event, true) or {}
	}
}

fn (s &HDAStream) position() u32 {
	return katomic.load(&s.regs.lpib) % u32(total_buffer_size)
}

// Zero `length` bytes of the ring from `at`, wrapping at its end.
fn (mut s HDAStream) clear_ring(at u32, length u32) {
	mut pos := at
	mut left := length
	for left > 0 {
		offset := pos % u32(page_size)
		piece := if left < u32(page_size) - offset { left } else { u32(page_size) - offset }
		unsafe {
			desc := &s.bdl[pos / u32(page_size)]
			C.memset(voidptr(desc.address + offset + higher_half), 0, piece)
		}
		pos = (pos + piece) % u32(total_buffer_size)
		left -= piece
	}
}

// Take what the controller played since the last interrupt off what is
// queued, however many pages that was, and zero it. A stream that runs dry
// keeps going over the ring, and must then play silence, not the ring's
// old contents.
fn (mut s HDAStream) handle_irq() {
	pos := s.position()
	played := (pos + u32(total_buffer_size) - s.hw_pos) % u32(total_buffer_size)
	s.clear_ring(s.hw_pos, played)
	s.hw_pos = pos
	for {
		old := katomic.load(&s.remaining_data)
		new_value := if old <= played { u32(0) } else { old - played }
		if katomic.cas(mut s.remaining_data, old, new_value) {
			break
		}
	}
	event.trigger(mut s.event, true)
}
