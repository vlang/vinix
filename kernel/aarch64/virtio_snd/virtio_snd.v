@[has_globals]
module virtio_snd

// Playback through a VirtIO sound device (QEMU's `virtio-sound-device`),
// published as the OSS /dev/dsp that SDL and other ports already speak.
//
// Only the control and transmit queues are used. Each transmit message is one
// period of PCM: a header descriptor naming the stream, the samples, and a
// status the device writes back. QEMU hands a message back only once its
// audio backend has consumed it, so the used ring advances in real time and a
// writer that runs out of free periods is paced by the host's sound card.

import aarch64.cpu
import dev.oss
import errno
import event
import katomic
import memory
import proc
import time
import time.sys
import userland
import usercopy

const reg_magic = u64(0x000)
const reg_version = u64(0x004)
const reg_device_id = u64(0x008)
const reg_guest_features = u64(0x020)
const reg_guest_page_size = u64(0x028)
const reg_queue_sel = u64(0x030)
const reg_queue_num_max = u64(0x034)
const reg_queue_num = u64(0x038)
const reg_queue_align = u64(0x03c)
const reg_queue_pfn = u64(0x040)
const reg_queue_notify = u64(0x050)
const reg_interrupt_status = u64(0x060)
const reg_interrupt_ack = u64(0x064)
const reg_status = u64(0x070)
const reg_config = u64(0x100)

const virtio_magic = u32(0x74726976)
const virtio_id_sound = u32(25)
const status_acknowledge = u32(1)
const status_driver = u32(2)
const status_driver_ok = u32(4)
const status_failed = u32(128)
const desc_next = u16(1)
const desc_write = u16(2)

const mmio_base = u64(0x0a000000)
const mmio_slot_size = u64(0x200)
const mmio_slot_count = u64(32)
const page_bytes = u64(4096)
const queue_align = u64(4096)

const control_queue_index = u16(0)
const transmit_queue_index = u16(2)

const r_pcm_info = u32(0x0100)
const r_pcm_set_params = u32(0x0101)
const r_pcm_prepare = u32(0x0102)
const r_pcm_release = u32(0x0103)
const r_pcm_start = u32(0x0104)
const r_pcm_stop = u32(0x0105)
const s_ok = u32(0x8000)

const direction_output = u8(0)
const pcm_info_size = u64(32)

const fmt_s8 = u8(3)
const fmt_u8 = u8(4)
const fmt_s16 = u8(5)
const fmt_u16 = u8(6)
const fmt_s32 = u8(17)

// Request and response share one page. A PCM_INFO answer is the largest
// response and is capped to what fits after the offset.
const response_offset = u64(2048)
const max_info_streams = u32(63)

// Periods in flight. A period is about 10 ms, so this bounds how far ahead of
// the speaker a writer can get to about 80-90 ms: enough to ride out a busy
// guest, short enough that a game's sounds still land on its frames.
const max_periods = 8
const period_target_hz = u32(100)
const descriptors_per_period = u16(3)

const poll_ns = i64(1000000)
const max_wait_ns = i64(10000000)
// How long QEMU can still be holding audio after the last period came back.
const tail_ns = i64(50000000)
const control_timeout_ns = u64(1000000000)
// QEMU's backends consume in real time, even the silent ones, so this long
// without a period coming back means the device is not playing at all.
const stall_timeout_ns = u64(2000000000)

struct Queue {
mut:
	size      u16
	desc      u64
	avail     u64
	used      u64
	avail_idx u16
	last_used u16
}

pub struct SoundCard {}

pub struct SoundStream {
mut:
	id           u32
	formats      u64
	rates        u64
	channels_min u8
	channels_max u8
	prepared     bool
	started      bool
	format       u8
	frame_bytes  u32
	period_bytes u32
	// How long a writer waiting for a free period sleeps between looks.
	wait_ns   i64 = poll_ns
	level     int
	periods   int
	busy      [max_periods]bool
	in_flight int
	// The period being filled by writes, or -1. It is queued once it is full.
	filling  int = -1
	fill_len u32
	// A sleeping lock: a write waits for the device with it held.
	mutex u64
}

__global (
	snd_base      = u64(0)
	snd_hhdm      = u64(0)
	snd_control   Queue
	snd_tx        Queue
	snd_ctl_phys  = u64(0)
	snd_meta_phys = u64(0)
	snd_data_phys = u64(0)
	snd_card      SoundCard
	snd_stream    SoundStream
)

fn mmio_r32(address u64) u32 {
	value := unsafe { *&u32(address) }
	cpu.dmb_ish()
	return value
}

fn mmio_w32(address u64, value u32) {
	cpu.dmb_ish()
	unsafe { *&u32(address) = value }
}

fn align_up(value u64, alignment u64) u64 {
	return (value + alignment - 1) & ~(alignment - 1)
}

fn wr32(address u64, value u32) {
	unsafe { *&u32(address) = value }
}

fn rd32(address u64) u32 {
	return unsafe { *&u32(address) }
}

fn set_desc(table u64, index u16, address u64, length u32, flags u16, next u16) {
	d := table + u64(index) * 16
	unsafe {
		*&u64(d) = address
		*&u32(d + 8) = length
		*&u16(d + 12) = flags
		*&u16(d + 14) = next
	}
}

fn setup_queue(index u16, wanted u16) ?Queue {
	mmio_w32(snd_base + reg_queue_sel, index)
	maximum := mmio_r32(snd_base + reg_queue_num_max)
	if maximum == 0 {
		return none
	}
	size := if maximum < wanted { u16(maximum) } else { wanted }
	mmio_w32(snd_base + reg_queue_num, size)
	mmio_w32(snd_base + reg_queue_align, u32(queue_align))

	avail_offset := u64(size) * 16
	used_offset := align_up(avail_offset + 4 + 2 * u64(size) + 2, queue_align)
	pages := (used_offset + 4 + 8 * u64(size) + 2 + page_bytes - 1) / page_bytes
	phys := u64(memory.pmm_alloc(pages))
	if phys == 0 {
		return none
	}
	virt := phys + snd_hhdm
	unsafe { C.memset(voidptr(virt), 0, pages * page_bytes) }
	cpu.dmb_ish()
	mmio_w32(snd_base + reg_queue_pfn, u32(phys / page_bytes))
	return Queue{
		size:  size
		desc:  virt
		avail: virt + avail_offset
		used:  virt + used_offset
	}
}

fn push(mut q Queue, head u16, queue u16) {
	unsafe { *&u16(q.avail + 4 + u64(q.avail_idx % q.size) * 2) = head }
	q.avail_idx++
	cpu.dmb_ish()
	unsafe { *&u16(q.avail + 2) = q.avail_idx }
	mmio_w32(snd_base + reg_queue_notify, queue)
}

fn ack_interrupt() {
	isr := mmio_r32(snd_base + reg_interrupt_status)
	if isr != 0 {
		mmio_w32(snd_base + reg_interrupt_ack, isr)
	}
}

fn request_page() u64 {
	return snd_ctl_phys + snd_hhdm
}

// control sends the request already written at the start of the control page
// and returns the status code of the response written after it.
fn control(request_len u32, response_len u32) u32 {
	page := request_page()
	wr32(page + response_offset, 0)
	set_desc(snd_control.desc, 0, snd_ctl_phys, request_len, desc_next, 1)
	set_desc(snd_control.desc, 1, snd_ctl_phys + response_offset, response_len, desc_write, 0)
	push(mut snd_control, 0, control_queue_index)

	// QEMU answers during the notify itself; the wait is only a backstop.
	start := time.monotonic_ns()
	for {
		cpu.dmb_ish()
		used := unsafe { *&u16(snd_control.used + 2) }
		if used != snd_control.last_used {
			snd_control.last_used = used
			break
		}
		if time.monotonic_ns() - start > control_timeout_ns {
			print('virtio-snd: control request timed out\n')
			return 0
		}
		sys.nsleep(poll_ns)
	}
	ack_interrupt()
	cpu.dmb_ish()
	return rd32(page + response_offset)
}

fn stream_request(code u32, stream_id u32) u32 {
	page := request_page()
	wr32(page, code)
	wr32(page + 4, stream_id)
	return control(8, 4)
}

fn rate_hz(index int) u32 {
	return match index {
		0 { u32(5512) }
		1 { 8000 }
		2 { 11025 }
		3 { 16000 }
		4 { 22050 }
		5 { 32000 }
		6 { 44100 }
		7 { 48000 }
		8 { 64000 }
		9 { 88200 }
		10 { 96000 }
		11 { 176400 }
		12 { 192000 }
		13 { 384000 }
		else { 0 }
	}
}

const rate_count = 14

const no_format = u8(0xff)

fn virtio_format(fmt u32) u8 {
	return match fmt {
		oss.afmt_u8 { fmt_u8 }
		oss.afmt_s8 { fmt_s8 }
		oss.afmt_s16_le { fmt_s16 }
		oss.afmt_u16_le { fmt_u16 }
		oss.afmt_s32_le { fmt_s32 }
		else { no_format }
	}
}

fn supports(format u8) bool {
	return format != no_format && snd_stream.formats & (u64(1) << format) != 0
}

fn sample_bytes(format u8) u32 {
	return match format {
		fmt_u8, fmt_s8 { u32(1) }
		fmt_s16, fmt_u16 { 2 }
		fmt_s32 { 4 }
		else { 0 }
	}
}

// ---- oss.OssAudioDevice ----

fn (c SoundCard) get_output_stream() &oss.OssAudioStream {
	return &snd_stream
}

fn (c SoundCard) name() string {
	return 'virtio'
}

fn (c SoundCard) formats() u32 {
	mut mask := u32(0)
	if supports(fmt_u8) {
		mask |= oss.afmt_u8
	}
	if supports(fmt_s8) {
		mask |= oss.afmt_s8
	}
	if supports(fmt_s16) {
		mask |= oss.afmt_s16_le
	}
	if supports(fmt_u16) {
		mask |= oss.afmt_u16_le
	}
	if supports(fmt_s32) {
		mask |= oss.afmt_s32_le
	}
	return mask
}

fn (c SoundCard) refine_fmt(fmt u32) u32 {
	if supports(virtio_format(fmt)) {
		return fmt
	}
	if supports(fmt_s16) {
		return oss.afmt_s16_le
	}
	return oss.afmt_u8
}

// refine_rate picks the supported rate nearest the one asked for; a program
// that does not get its exact rate resamples to the one it is told.
fn (c SoundCard) refine_rate(rate u32) u32 {
	mut best := u32(0)
	for i in 0 .. rate_count {
		if snd_stream.rates & (u64(1) << i) == 0 {
			continue
		}
		candidate := rate_hz(i)
		if best == 0 || distance(candidate, rate) < distance(best, rate)
			|| (distance(candidate, rate) == distance(best, rate) && candidate > best) {
			best = candidate
		}
	}
	return if best == 0 { u32(48000) } else { best }
}

fn distance(a u32, b u32) u32 {
	return if a > b { a - b } else { b - a }
}

fn (c SoundCard) refine_channels(channels u8) u8 {
	if channels < snd_stream.channels_min {
		return snd_stream.channels_min
	}
	if channels > snd_stream.channels_max {
		return snd_stream.channels_max
	}
	return channels
}

// ---- oss.OssAudioStream ----

enum Nap {
	// The time passed, or the thread was woken for a signal it blocks.
	slept
	// A signal with a handler is waiting to be delivered.
	signalled
	// A signal that ends or stops the process is waiting.
	fatal
}

// nap sleeps for `ns`, and says whether a signal is waiting to be delivered.
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

// Any signal sent to a thread ends its wait, even one it blocks, and SDL's
// audio thread blocks nearly all of them, so a wakeup alone means nothing.
// Signals that are ignored never become pending, which leaves a pending one
// at its default action as one that kills or stops the process.
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

fn (mut s SoundStream) lock() {
	for !katomic.cas(mut s.mutex, u64(0), u64(1)) {
		sys.nsleep(poll_ns)
	}
}

fn (mut s SoundStream) unlock() {
	katomic.store(mut s.mutex, u64(0))
}

fn data_virt(period int) u64 {
	return snd_data_phys + snd_hhdm + u64(period) * page_bytes
}

fn (mut s SoundStream) setup_params(fmt u32, rate u32, channels u8) {
	s.lock()
	defer {
		s.unlock()
	}
	s.release_locked()

	format := virtio_format(fmt)
	bytes := sample_bytes(format)
	mut rate_index := -1
	for i in 0 .. rate_count {
		if rate_hz(i) == rate {
			rate_index = i
		}
	}
	if bytes == 0 || rate_index < 0 || channels == 0 {
		print('virtio-snd: unsupported parameters: format ${fmt:x}, ${rate} Hz, ${channels} channels\n')
		return
	}

	// Whole frames per period, a power of two near 10 ms, never past the
	// page each period is given.
	frame_bytes := bytes * u32(channels)
	mut frames := u32(1)
	for frames * period_target_hz < rate {
		frames <<= 1
	}
	for frames > 1 && u64(frames * frame_bytes) > page_bytes {
		frames >>= 1
	}
	period_bytes := frames * frame_bytes
	// Look for a returned period about twice per period.
	mut wait_ns := i64(u64(frames) * 1000000000 / u64(rate) / 2)
	if wait_ns < poll_ns {
		wait_ns = poll_ns
	} else if wait_ns > max_wait_ns {
		wait_ns = max_wait_ns
	}

	page := request_page()
	wr32(page, r_pcm_set_params)
	wr32(page + 4, s.id)
	wr32(page + 8, period_bytes * u32(s.periods))
	wr32(page + 12, period_bytes)
	wr32(page + 16, 0)
	unsafe {
		*&u8(page + 20) = channels
		*&u8(page + 21) = format
		*&u8(page + 22) = u8(rate_index)
		*&u8(page + 23) = 0
	}
	code := control(24, 4)
	if code != s_ok {
		print('virtio-snd: SET_PARAMS failed (${code:x})\n')
		return
	}
	prepare := stream_request(r_pcm_prepare, s.id)
	if prepare != s_ok {
		print('virtio-snd: PREPARE failed (${prepare:x})\n')
		return
	}
	s.format = format
	s.frame_bytes = frame_bytes
	s.period_bytes = period_bytes
	s.wait_ns = wait_ns
	s.prepared = true
}

fn (mut s SoundStream) change_volume(percentage int) {
	s.level = if percentage < 0 {
		0
	} else if percentage > 100 {
		100
	} else {
		percentage
	}
}

fn (s SoundStream) volume() int {
	return s.level
}

fn (mut s SoundStream) play(play bool) {
	s.lock()
	defer {
		s.unlock()
	}
	if play {
		s.start_locked()
	} else if s.started {
		stream_request(r_pcm_stop, s.id)
		s.started = false
	}
}

fn (mut s SoundStream) reset() {
	s.lock()
	defer {
		s.unlock()
	}
	s.release_locked()
}

fn (s SoundStream) is_playing() bool {
	return s.prepared
}

fn (mut s SoundStream) writable() u64 {
	s.lock()
	defer {
		s.unlock()
	}
	if !s.prepared {
		// The first write configures the stream and always has room.
		return page_bytes
	}
	s.reap()
	mut idle := s.periods - s.in_flight
	mut room := u64(0)
	if s.filling >= 0 {
		idle--
		room = u64(s.period_bytes - s.fill_len)
	}
	return room + u64(idle) * u64(s.period_bytes)
}

fn (mut s SoundStream) sync_write(buf voidptr, _loc u64, count u64) ?i64 {
	s.lock()
	defer {
		s.unlock()
	}
	if !s.prepared {
		errno.set(errno.eio)
		return none
	}

	mut done := u64(0)
	for done < count {
		if s.filling < 0 {
			period := s.wait_for_period(count - done)
			if period < 0 {
				if done > 0 {
					return i64(done)
				}
				errno.set(if period == interrupted { errno.eintr } else { errno.eio })
				return none
			}
			s.filling = period
			s.fill_len = 0
		}

		mut n := u64(s.period_bytes - s.fill_len)
		if n > count - done {
			n = count - done
		}
		destination := voidptr(data_virt(s.filling) + u64(s.fill_len))
		if !usercopy.copy_from_user(destination, u64(buf) + done, n) {
			if done > 0 {
				return i64(done)
			}
			errno.set(errno.efault)
			return none
		}
		s.fill_len += u32(n)
		done += n

		if s.fill_len == s.period_bytes {
			s.submit()
		}
	}
	return i64(done)
}

fn (mut s SoundStream) wait_until_empty() {
	s.lock()
	defer {
		s.unlock()
	}
	if !s.prepared {
		return
	}
	if s.filling >= 0 {
		s.fill_len -= s.fill_len % s.frame_bytes
		if s.fill_len > 0 {
			s.submit()
		} else {
			s.filling = -1
		}
	}
	mut last_progress := time.monotonic_ns()
	for {
		before := s.in_flight
		s.reap()
		if s.in_flight == 0 {
			// The device hands a period back once it is in QEMU's own
			// mixing buffer, not once it has been heard. Stopping now would
			// cut off that last stretch, and play it at the start of the
			// next stream instead.
			nap(tail_ns)
			return
		}
		now := time.monotonic_ns()
		if s.in_flight != before {
			last_progress = now
		} else if now - last_progress > stall_timeout_ns {
			print('virtio-snd: device stopped consuming audio\n')
			return
		}
		if nap(s.wait_ns) != .slept {
			return
		}
	}
}

// ---- stream internals, called with the lock held ----

fn (mut s SoundStream) start_locked() {
	if s.prepared && !s.started {
		code := stream_request(r_pcm_start, s.id)
		if code != s_ok {
			print('virtio-snd: START failed (${code:x})\n')
			return
		}
		s.started = true
	}
}

fn (mut s SoundStream) release_locked() {
	if s.started {
		stream_request(r_pcm_stop, s.id)
		s.started = false
	}
	if s.prepared {
		// The device completes every period still queued before it answers.
		stream_request(r_pcm_release, s.id)
		s.prepared = false
	}
	s.reap()
	for i in 0 .. max_periods {
		s.busy[i] = false
	}
	s.in_flight = 0
	s.filling = -1
	s.fill_len = 0
}

fn (mut s SoundStream) reap() {
	cpu.dmb_ish()
	used := unsafe { *&u16(snd_tx.used + 2) }
	for snd_tx.last_used != used {
		entry := snd_tx.used + 4 + u64(snd_tx.last_used % snd_tx.size) * 8
		head := rd32(entry)
		period := int(head / u32(descriptors_per_period))
		if period < s.periods && s.busy[period] {
			s.busy[period] = false
			s.in_flight--
		}
		snd_tx.last_used++
	}
	ack_interrupt()
}

const stalled = -1
const interrupted = -2

// wait_for_period returns a free period to fill, waiting for the device to
// hand one back if every period is queued. It returns `stalled` if the device
// never does and `interrupted` if a signal has to be delivered first.
//
// Linux restarts a sound write that a handled signal interrupts, and SDL
// counts on that: it takes a failed write to mean the card is gone for good.
// Vinix cannot restart a system call, so a write with no more left than the
// device holds, which is every write SDL makes, finishes first and the
// handler runs right after it. A signal that kills the process does not wait.
fn (mut s SoundStream) wait_for_period(remaining u64) int {
	can_finish := remaining <= u64(s.periods) * u64(s.period_bytes)
	mut last_progress := time.monotonic_ns()
	for time.monotonic_ns() - last_progress <= stall_timeout_ns {
		before := s.in_flight
		s.reap()
		for i in 0 .. s.periods {
			if !s.busy[i] && i != s.filling {
				return i
			}
		}
		if s.in_flight != before {
			last_progress = time.monotonic_ns()
		}
		match nap(s.wait_ns) {
			.slept {}
			.signalled {
				if !can_finish {
					return interrupted
				}
			}
			.fatal {
				return interrupted
			}
		}
	}
	print('virtio-snd: device stopped consuming audio\n')
	return stalled
}

fn (mut s SoundStream) scale(address u64, length u32) {
	if s.level >= 100 {
		return
	}
	level := i64(s.level)
	match s.format {
		fmt_s16 {
			for off := u64(0); off + 2 <= u64(length); off += 2 {
				p := unsafe { &i16(address + off) }
				unsafe {
					*p = i16(i64(*p) * level / 100)
				}
			}
		}
		fmt_u16 {
			for off := u64(0); off + 2 <= u64(length); off += 2 {
				p := unsafe { &u16(address + off) }
				unsafe {
					*p = u16((i64(*p) - 32768) * level / 100 + 32768)
				}
			}
		}
		fmt_s32 {
			for off := u64(0); off + 4 <= u64(length); off += 4 {
				p := unsafe { &i32(address + off) }
				unsafe {
					*p = i32(i64(*p) * level / 100)
				}
			}
		}
		fmt_s8 {
			for off := u64(0); off < u64(length); off++ {
				p := unsafe { &i8(address + off) }
				unsafe {
					*p = i8(i64(*p) * level / 100)
				}
			}
		}
		fmt_u8 {
			for off := u64(0); off < u64(length); off++ {
				p := unsafe { &u8(address + off) }
				unsafe {
					*p = u8((i64(*p) - 128) * level / 100 + 128)
				}
			}
		}
		else {}
	}
}

fn (mut s SoundStream) submit() {
	period := s.filling
	s.scale(data_virt(period), s.fill_len)
	head := u16(period) * descriptors_per_period
	set_desc(snd_tx.desc, head + 1, snd_data_phys + u64(period) * page_bytes, s.fill_len,
		desc_next, head + 2)
	cpu.dmb_ish()
	push(mut snd_tx, head, transmit_queue_index)
	s.busy[period] = true
	s.in_flight++
	s.filling = -1
	s.fill_len = 0
	s.start_locked()
}

// ---- discovery ----

fn find_output_stream(streams u32) bool {
	count := if streams > max_info_streams { max_info_streams } else { streams }
	page := request_page()
	wr32(page, r_pcm_info)
	wr32(page + 4, 0)
	wr32(page + 8, count)
	wr32(page + 12, u32(pcm_info_size))
	code := control(16, u32(4 + u64(count) * pcm_info_size))
	if code != s_ok {
		print('virtio-snd: PCM_INFO failed (${code:x})\n')
		return false
	}
	for i := u32(0); i < count; i++ {
		info := page + response_offset + 4 + u64(i) * pcm_info_size
		direction := unsafe { *&u8(info + 24) }
		if direction != direction_output {
			continue
		}
		snd_stream.id = i
		snd_stream.formats = unsafe { *&u64(info + 8) }
		snd_stream.rates = unsafe { *&u64(info + 16) }
		snd_stream.channels_min = unsafe { *&u8(info + 25) }
		snd_stream.channels_max = unsafe { *&u8(info + 26) }
		if snd_stream.channels_min == 0 {
			snd_stream.channels_min = 1
		}
		if snd_stream.channels_max < snd_stream.channels_min {
			snd_stream.channels_max = snd_stream.channels_min
		}
		return true
	}
	print('virtio-snd: no output stream\n')
	return false
}

fn fail(message string) {
	print('virtio-snd: ${message}\n')
	mmio_w32(snd_base + reg_status, status_failed)
}

pub fn initialise(hhdm u64) {
	snd_hhdm = hhdm
	for i := u64(0); i < mmio_slot_count; i++ {
		base := hhdm + mmio_base + i * mmio_slot_size
		if mmio_r32(base + reg_magic) != virtio_magic {
			continue
		}
		if mmio_r32(base + reg_device_id) != virtio_id_sound {
			continue
		}
		snd_base = base
		break
	}
	if snd_base == 0 {
		return
	}
	if mmio_r32(snd_base + reg_version) != 1 {
		print('virtio-snd: only the legacy MMIO transport is supported\n')
		snd_base = 0
		return
	}

	mmio_w32(snd_base + reg_status, 0)
	mmio_w32(snd_base + reg_status, status_acknowledge)
	mmio_w32(snd_base + reg_status, status_acknowledge | status_driver)
	mmio_w32(snd_base + reg_guest_features, 0)
	mmio_w32(snd_base + reg_guest_page_size, u32(page_bytes))

	snd_control = setup_queue(control_queue_index, 16) or {
		fail('control queue unavailable')
		return
	}
	snd_tx = setup_queue(transmit_queue_index, 32) or {
		fail('transmit queue unavailable')
		return
	}
	periods := int(snd_tx.size / descriptors_per_period)
	snd_stream.periods = if periods > max_periods { max_periods } else { periods }
	if snd_stream.periods < 2 {
		fail('transmit queue too small')
		return
	}

	snd_ctl_phys = u64(memory.pmm_alloc(1))
	snd_meta_phys = u64(memory.pmm_alloc(1))
	snd_data_phys = u64(memory.pmm_alloc(u64(max_periods)))
	if snd_ctl_phys == 0 || snd_meta_phys == 0 || snd_data_phys == 0 {
		fail('out of memory')
		return
	}

	mmio_w32(snd_base + reg_status, status_acknowledge | status_driver | status_driver_ok)

	streams := mmio_r32(snd_base + reg_config + 4)
	if streams == 0 || !find_output_stream(streams) {
		fail('no playback stream')
		return
	}

	// Each period's chain never changes shape: the stream header, the
	// samples, and the status the device writes back. Only the sample
	// length is filled in when a period is queued.
	meta := snd_meta_phys + snd_hhdm
	for p := 0; p < snd_stream.periods; p++ {
		head := u16(p) * descriptors_per_period
		header := snd_meta_phys + u64(p) * 16
		wr32(meta + u64(p) * 16, snd_stream.id)
		set_desc(snd_tx.desc, head, header, 4, desc_next, head + 1)
		set_desc(snd_tx.desc, head + 1, snd_data_phys + u64(p) * page_bytes, 0, desc_next,
			head + 2)
		set_desc(snd_tx.desc, head + 2, header + 8, 8, desc_write, 0)
	}

	snd_stream.level = 100
	snd_stream.filling = -1
	print('virtio-snd: stream ${snd_stream.id}, ${snd_stream.channels_min}-${snd_stream.channels_max} channels, formats ${snd_stream.formats:x}, rates ${snd_stream.rates:x}, ${snd_stream.periods} periods\n')

	oss.create_device(&snd_card)
}
