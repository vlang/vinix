// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
//
// hibernate and its relatives: suspend to disk, across more than one boot
// of the machine.
//
// `echo disk > /sys/power/state` writes an image of memory to the device the
// kernel command line names (vinix.hibernate=sd1) and switches the machine
// off. The controller starts the machine again on the same disks. A kernel
// that finds the image, and finds the machine to be the one it was taken on,
// goes back into it: the write to `state` then returns, in this same process,
// in a machine that has been off.
//
// `hibernate` does that twice in a row, and checks before and after each
// that what a process has is still what it had: its memory, a thread that
// counts, a file in tmpfs, a descriptor with an offset, bytes left in a
// pipe, a child waiting -- and that the machine is whole: every processor,
// the clocks, the disk, the network.
//
// The others are about an image that must not be gone back into. There the
// machine starts afresh, and this program with it, so it leaves itself a
// note on the data disk before it hibernates and reads it when it starts:
//
//	hibernate-damaged-header  the controller damages the image's header
//	hibernate-damaged-pages   and, here, a page of the image itself
//	hibernate-memory          the machine is given less memory
//	hibernate-unnamed         no device is named: there is no `disk`
//
// The machine has two SATA disks: sd0, a data disk the tests read and write,
// and sd1, the image's.
module main

import os
import sync.stdatomic

const hib_state = '/sys/power/state'
const hib_report = '/sys/power/hibernate'
const hib_data_disk = '/dev/sd0'
const hib_image_disk = '/dev/sd1'
const hib_memory_bytes = 64 << 20
// Where on the data disk this program leaves word for itself.
const hib_note_offset = i64(8) << 20
const hib_note_bytes = 512
const hib_pattern_bytes = 65536
const hib_file = '/tmp/hibernate-file'
const hib_file_bytes = 16384
const hib_file_read = 5000
const hib_pipe_text = 'left in the pipe'

fn C.lseek(fd i32, offset i64, whence i32) i64
fn C.waitpid(pid i32, status &i32, options i32) i32
fn C._exit(code i32)

// One line of /sys/power/hibernate: the text after "name: ", or ''.
fn hib_line(name string) string {
	text := read_text(hib_report) or { return '' }
	for line in text.split_into_lines() {
		if line.starts_with(name + ': ') {
			return line.all_after(': ')
		}
	}
	return ''
}

fn hib_number(name string) i64 {
	return hib_line(name).i64()
}

// The first line: "available", or "unavailable: " and why.
fn hib_offer() string {
	text := read_text(hib_report) or { return '' }
	return text.all_before('\n')
}

// The note this program left itself on the data disk, or ''.
fn hib_note() string {
	fd := C.open(&char(hib_data_disk.str), C.O_RDONLY)
	if fd < 0 {
		return ''
	}
	defer {
		C.close(fd)
	}
	mut bytes := []u8{len: hib_note_bytes}
	if C.pread(fd, bytes.data, usize(hib_note_bytes), hib_note_offset) != hib_note_bytes {
		return ''
	}
	mut length := 0
	for length < hib_note_bytes && bytes[length] != 0 {
		length++
	}
	return bytes[..length].bytestr()
}

fn hib_leave_note(text string) ! {
	mut bytes := []u8{len: hib_note_bytes}
	for i in 0 .. text.len {
		bytes[i] = text[i]
	}
	fd := C.open(&char(hib_data_disk.str), C.O_RDWR)
	if fd < 0 {
		return errno_error(hib_data_disk)
	}
	defer {
		C.close(fd)
	}
	if C.pwrite(fd, bytes.data, usize(hib_note_bytes), hib_note_offset) != hib_note_bytes {
		return errno_error(hib_data_disk)
	}
	if C.fsync(fd) != 0 {
		return errno_error(hib_data_disk)
	}
}

// What the image device's first block says: its signature as text, and how
// many pages it says it holds. '' when the device cannot be read.
fn hib_image_header() (string, u64) {
	fd := C.open(&char(hib_image_disk.str), C.O_RDONLY)
	if fd < 0 {
		return '', 0
	}
	defer {
		C.close(fd)
	}
	mut block := []u8{len: 4096}
	if C.pread(fd, block.data, usize(4096), 0) != 4096 {
		return '', 0
	}
	mut pages := u64(0)
	for i in 0 .. 8 {
		pages |= u64(block[24 + i]) << (8 * i)
	}
	return block[..8].bytestr(), pages
}

// The device holds a header of this system's that describes no image.
fn hib_check_no_image(mut t Test, when string) {
	signature, pages := hib_image_header()
	t.check(signature == 'VINIXHIB' && pages == 0, '${when}: the image device says "${signature}" with ${pages} pages; it was to hold no image')
}

fn hib_file_byte(index int) u8 {
	return u8(index * 13 + 5)
}

struct HibRun {
mut:
	cpus   int
	memory []u64
	// A file open for reading, with some of it read.
	fd i32
	// A pipe with bytes written and not read.
	pipe_read i32
	// A child blocked reading a pipe this process holds the other end of.
	child     int
	child_end i32
	resumes   int
}

// Everything a process is to find again, put in place.
fn (mut run HibRun) set_up(mut t Test) bool {
	run.cpus = cpu_count()
	t.check(run.cpus == 4, 'the machine has ${run.cpus} CPUs, not the 4 the scenario asks QEMU for')
	if run.cpus > deep_max_cpus {
		run.cpus = deep_max_cpus
	}
	for cpu in 0 .. run.cpus {
		spawn count_on_cpu(cpu)
	}
	spawn count_freely()
	run.memory = []u64{len: hib_memory_bytes / 8}
	fill_memory(mut run.memory)

	mut content := []u8{len: hib_file_bytes}
	for i in 0 .. hib_file_bytes {
		content[i] = hib_file_byte(i)
	}
	os.write_file_array(hib_file, content) or {
		t.check(false, 'writing ${hib_file}: ${err.msg()}')
		return false
	}
	run.fd = C.open(&char(hib_file.str), C.O_RDONLY)
	mut read := []u8{len: hib_file_read}
	if !t.check(run.fd >= 0 && C.read(run.fd, read.data, usize(hib_file_read)) == hib_file_read, 'opening and reading ${hib_file}') {
		return false
	}

	mut ends := [2]i32{}
	C.pipe(voidptr(&ends[0]))
	run.pipe_read = ends[0]
	t.check(C.write(ends[1], hib_pipe_text.str, usize(hib_pipe_text.len)) == hib_pipe_text.len, 'writing into the pipe')

	mut to_child := [2]i32{}
	C.pipe(voidptr(&to_child[0]))
	run.child = os.fork()
	if run.child == 0 {
		// Waits for one byte and says which it was with its exit status.
		mut b := [1]u8{}
		if C.read(to_child[0], &b[0], 1) == 1 {
			C._exit(40 + i32(b[0]))
		}
		C._exit(1)
	}
	run.child_end = to_child[1]
	return t.check(run.child > 0, 'fork failed')
}

// What a process had is still what it has.
fn (mut run HibRun) check_process(mut t Test, when string) {
	damage := memory_damage(run.memory)
	t.check(damage < 0, '${when}: ${hib_memory_bytes >> 20} MiB of memory differs from what was written, first at word ${damage}')
	counted := stdatomic.load_u64(&deep_free_count)
	sleep_ms(200)
	t.check(stdatomic.load_u64(&deep_free_count) > counted, '${when}: the counting thread stands still')

	content := os.read_bytes(hib_file) or { []u8{} }
	mut file_ok := content.len == hib_file_bytes
	for i in 0 .. content.len {
		if content[i] != hib_file_byte(i) {
			file_ok = false
			break
		}
	}
	t.check(file_ok, '${when}: ${hib_file} is not what was written (${content.len} bytes)')
	// The descriptor is where it was left, and reads on from there.
	offset := C.lseek(run.fd, 0, 1)
	t.check(offset == hib_file_read, '${when}: the open file is at offset ${offset}, not ${hib_file_read}')
	mut next := [16]u8{}
	t.check(C.pread(run.fd, &next[0], 16, hib_file_read) == 16 && next[0] == hib_file_byte(hib_file_read)
		&& next[15] == hib_file_byte(hib_file_read + 15), '${when}: the open file does not read on from where it was')
}

// And what was waiting is still waiting: the bytes in the pipe, the child.
fn (mut run HibRun) check_waiting(mut t Test, when string) {
	mut found := []u8{len: 64}
	count := C.read(run.pipe_read, found.data, usize(64))
	t.check(count == hib_pipe_text.len && found[..hib_pipe_text.len].bytestr() == hib_pipe_text, '${when}: the pipe held ${count} bytes, not the ${hib_pipe_text.len} left in it')
	mut status := i32(0)
	t.check(C.waitpid(i32(run.child), &status, 1) == 0, '${when}: the child that was waiting has gone')
	b := [u8(2)]!
	C.write(run.child_end, &b[0], 1)
	t.check(C.waitpid(i32(run.child), &status, 0) == run.child && (status >> 8) & 0xff == 42 && status & 0x7f == 0, '${when}: the child ended with status ${status}, not by exiting with 42')
}

fn (mut run HibRun) check_machine(mut t Test, when string, seed u8, offset i64) {
	check_every_cpu(mut t, run.cpus, when)
	// What was on the disk before is there, and the disk takes more.
	read_pattern(hib_data_disk, offset - (1 << 20), seed - 1, hib_pattern_bytes) or {
		t.check(false, '${when}: the pattern written before: ${err.msg()}')
	}
	write_pattern(hib_data_disk, offset, seed, hib_pattern_bytes) or {
		t.check(false, '${when}: a new pattern on the disk: ${err.msg()}')
	}
	t.check(network_works(20), '${when}: the network does not work')
}

// One suspend to disk and the way back from it, as the process that asked
// sees it.
fn (mut run HibRun) cycle(mut t Test, number int) bool {
	what := 'cycle ${number}'
	// Megabytes 1 and 2 of the disk for the first cycle, 3 and 4 for the
	// second: one written before, one after. hwhost looks for all four.
	seed := u8(0x50 + 2 * number)
	offset := i64(2 * number) << 20
	// Written before, read after, from a disk the kernel has just reset.
	write_pattern(hib_data_disk, offset - (1 << 20), seed - 1, hib_pattern_bytes) or {
		t.check(false, '${what}: a pattern on the disk before: ${err.msg()}')
	}
	hib_leave_note('hibernate cycle ${number}') or { t.check(false, '${what}: leaving a note: ${err.msg()}') }
	run.check_process(mut t, '${what}, before')
	if t.failures != 0 {
		return false
	}
	frozen_from := stdatomic.load_u64(&deep_free_count)
	mono_before := monotonic_ms()
	real_before := realtime_ms()
	t.step('hibernating ${number}')
	write_text(hib_state, 'disk') or {
		t.check(false, '${what}: writing disk to state: ${err.msg()} (${deep_stat('last_failed_step')}: ${deep_stat('last_failed_reason')})')
		return false
	}
	mono := monotonic_ms() - mono_before
	real := realtime_ms() - real_before
	frozen := stdatomic.load_u64(&deep_free_count) - frozen_from
	run.resumes++

	// This process is running, so it is the same process; and the machine
	// is another one than it was: the kernel has been put back by a boot.
	t.check(hib_number('resumes') == run.resumes, '${what}: the kernel counts ${hib_number('resumes')} resumes from disk, not ${run.resumes}')
	t.check(hib_number('loader uptime ms') > 0, '${what}: no kernel says it loaded this one')
	t.check(hib_number('writes before the image was looked for') == 0, '${what}: the boot that loaded the image had written to a disk first')
	t.check(deep_stat('last_depth') == 'disk' && deep_stat('last_wake') == 'resume-from-disk', '${what}: recorded as ${deep_stat('last_depth')}, woken by ${deep_stat('last_wake')}')
	t.check(deep_stat('success') == run.resumes.str() && deep_stat('fail') == '0' && deep_stat('disk') == run.resumes.str(), '${what}: success ${deep_stat('success')}, fail ${deep_stat('fail')}, disk ${deep_stat('disk')} after ${run.resumes} suspends to disk')
	t.check(deep_stat('security_changes') == '0', '${what}: CPU protections changed across the sleep')
	t.check(deep_stat('security_cpus') == run.cpus.str(), '${what}: the protections of ${deep_stat('security_cpus')} CPUs were compared, not of ${run.cpus}')
	t.check(deep_report('processors lost') == 0, '${what}: ${deep_report('processors lost')} processors did not come back')
	t.check(deep_report('pci functions not restored') == 0, '${what}: ${deep_report('pci functions not restored')} PCI functions were not restored')
	pages := hib_number('image pages')
	t.check(pages > 0 && hib_number('pages read in place') + hib_number('pages moved into place') == pages, '${what}: ${pages} pages in the image, ${hib_number('pages read in place')} read in place and ${hib_number('pages moved into place')} moved')

	// The monotonic clock carries on from where it stopped; the time the
	// machine was off is added to the wall clock, in whole seconds.
	moved_on := real - mono
	t.check(mono >= 0 && mono < 30000, '${what}: the monotonic clock moved ${mono} ms')
	t.check(moved_on >= 900 && moved_on < 300000, '${what}: the wall clock moved ${real} ms and the monotonic clock ${mono} ms: the time off was not added to the wall clock')
	t.check((moved_on + 100) % 1000 < 200, '${what}: the wall clock was moved on ${moved_on} ms more than the monotonic clock, which is not a whole number of seconds')
	asleep := deep_stat('last_sleep_ms').i64()
	t.check(asleep >= moved_on - 100 && asleep <= real + 100, '${what}: last_sleep_ms is ${asleep}, with ${moved_on} ms away and ${real} ms on the wall clock')
	rate := free_rate()
	t.check(frozen < u64(rate) * u64(asleep) / 300 / 4, '${what}: userspace ran while the machine was down: ${frozen} counts in ${asleep} ms, ${rate} per 300 ms awake')

	run.check_process(mut t, '${what}, after')
	run.check_machine(mut t, '${what}, after', seed, offset)
	// The image was gone back into once, and is no longer there to go back
	// into.
	hib_check_no_image(mut t, what)
	t.check(read_word(hib_state).contains('disk') && hib_offer() == 'available', '${what}: disk is not offered again: "${read_word(hib_state)}", "${hib_offer()}"')
	t.info('${what}: image of ${pages} pages, ${hib_number('image bytes') >> 20} MiB; copied in ${hib_number('copy ms')} ms, written in ${hib_number('write ms')} ms; loaded in ${hib_number('load ms')} ms by a kernel ${hib_number('loader uptime ms')} ms old (${hib_number('pages read in place')} pages in place, ${hib_number('pages moved into place')} moved); off for ${moved_on} ms; down in ${deep_stat('last_suspend_ms')} ms, back in ${deep_stat('last_resume_ms')} ms')
	return t.failures == 0
}

// Whether `disk` is on offer, with the device as it should be.
fn hib_offered(mut t Test) bool {
	state := read_word(hib_state)
	if !t.check(state == 'freeze mem disk' && hib_offer() == 'available', 'disk is not offered: state "${state}", hibernate "${hib_offer()}"') {
		return false
	}
	t.check(read_word('/sys/power/disk') == '[shutdown]', '/sys/power/disk reads "${read_word('/sys/power/disk')}"')
	if _ := write_text('/sys/power/disk', 'platform') {
		t.check(false, 'a way of switching off that is not there was accepted')
	}
	t.check(hib_line('device') == 'sd1', 'the image device is "${hib_line('device')}"')
	// An image is a copy of memory: nobody but root reads the device.
	if attributes := os.stat(hib_image_disk) {
		t.check(attributes.mode & 0o777 == 0o600, '${hib_image_disk} has mode 0${attributes.mode & 0o777:o}, not 0600')
	} else {
		t.check(false, '${hib_image_disk} cannot be looked at')
	}
	return true
}

fn hibernate_twice(mut t Test, unit string) {
	// Started afresh where a kernel was to be gone back into.
	note := hib_note()
	if !t.check(note == '', 'the machine started afresh after "${note}" instead of going back into its image: ${hib_line('boot')}') {
		return
	}
	if !hib_offered(mut t) {
		return
	}
	t.check(hib_line('boot') == 'no image', 'the first boot found "${hib_line('boot')}" on a blank device')
	if unit != '' {
		t.check(deep_report('iommu units') == 1 && deep_report('iommu units translating') == 1, 'before any sleep ${deep_report('iommu units')} units are on and ${deep_report('iommu units translating')} translating')
	}
	t.check(network_works(20), 'the network does not work before any sleep')
	os.signal_opt(.usr2, on_power_off_request) or {
		t.check(false, 'could not install a SIGUSR2 handler: ${err}')
		return
	}
	mut run := HibRun{}
	if !run.set_up(mut t) {
		return
	}
	check_every_cpu(mut t, run.cpus, 'before any sleep')
	if !run.cycle(mut t, 1) {
		return
	}
	// And again: a kernel that has been put back can be put away.
	if !run.cycle(mut t, 2) {
		return
	}
	run.check_waiting(mut t, 'after two cycles')
	if unit != '' {
		t.check(deep_report('iommu units') == 1 && deep_report('iommu units translating') == 1, 'after two cycles ${deep_report('iommu units')} units are on and ${deep_report('iommu units translating')} translating')
		card := bound_device('e1000')
		dma := read_text(card + '/dma') or { '' }
		t.check(card != '' && dma.contains('isolated'), 'the card is not confined after two cycles: "${dma.replace('\n', ' ')}"')
	}
	hib_leave_note('') or { t.check(false, 'clearing the note: ${err.msg()}') }
	t.step('screen after the cycles')
	sleep_ms(1000)
	// ACPI's events were switched on again from the kernel's own record of
	// them: a press of the power button reaches init as it would have before.
	t.step('waiting for power button')
	asked := wait_until(30000, fn () bool {
		return power_button_asked
	})
	t.check(asked, 'after two cycles a power button press did not reach init within 30 s')
}

fn scenario_hibernate(mut t Test) {
	hibernate_twice(mut t, '')
}

// The same on processors without x2APIC and without 57-bit addresses: the
// local APICs driven through memory, and page tables four levels deep, which
// is what the page table an image is entered through has to match.
fn scenario_hibernate_xapic(mut t Test) {
	mode := read_text('/sys/power/deep_sleep') or { '' }
	t.check(mode.contains('apic mode: xapic\n'), 'the local APICs are not in xapic mode: "${mode.replace('\n', ' | ')}"')
	hibernate_twice(mut t, '')
}

fn scenario_hibernate_iommu(mut t Test) {
	hibernate_twice(mut t, 'dmar0')
}

fn scenario_hibernate_iommu_amd(mut t Test) {
	hibernate_twice(mut t, 'ivhd0')
}

// How many suspends to disk hibernate-cycles measures, after one it does not.
const hib_measured_cycles = 4

// One suspend to disk with nothing else: no file read, nothing allocated in
// this program, whose own heap growing costs the kernel objects too.
fn hib_bare_cycle() bool {
	fd := C.open(c'/sys/power/state', C.O_WRONLY)
	if fd < 0 {
		return false
	}
	written := C.write(fd, c'disk', 4)
	C.close(fd)
	return written == 4
}

// hibernate-cycles: what a suspend to disk leaves allocated in the kernel
// that took it. Every cycle makes tables of the pages it saves and takes a
// page for each; the kernel inside the image gives them all back when it
// wakes. One cycle is run first and not measured -- what is made once is
// made in it -- then four are, with nothing between them.
fn scenario_hibernate_cycles(mut t Test) {
	note := hib_note()
	if !t.check(note == '', 'the machine started afresh after "${note}" instead of going back into its image: ${hib_line('boot')}') {
		return
	}
	if !hib_offered(mut t) {
		return
	}
	hib_leave_note('hibernate-cycles') or { t.check(false, 'leaving a note: ${err.msg()}') }
	if !t.check(hib_bare_cycle(), 'the first suspend to disk failed: ${deep_stat('last_failed_reason')}') {
		return
	}
	sleep_ms(grace_ms)
	free_before := meminfo_kb('MemFree') or { 0 }
	before := heap_usage() or {
		t.check(false, err.msg())
		return
	}
	mut refused := 0
	for _ in 0 .. hib_measured_cycles {
		if !hib_bare_cycle() {
			refused++
		}
	}
	sleep_ms(grace_ms)
	after := heap_usage() or {
		t.check(false, err.msg())
		return
	}
	free_after := meminfo_kb('MemFree') or { 0 }
	cycles := hib_measured_cycles + 1
	t.check(refused == 0, '${refused} of ${hib_measured_cycles} suspends to disk failed: ${deep_stat('last_failed_reason')}')
	t.check(hib_number('resumes') == cycles && deep_stat('disk') == cycles.str() && deep_stat('fail') == '0', '${hib_number('resumes')} resumes and ${deep_stat('disk')} suspends to disk are counted after ${cycles}, with ${deep_stat('fail')} failures')
	t.check(deep_stat('security_changes') == '0', 'CPU protections changed across a sleep')
	t.check(deep_report('processors lost') == 0 && deep_report('pci functions not restored') == 0, '${deep_report('processors lost')} processors lost and ${deep_report('pci functions not restored')} PCI functions not restored')
	t.check(after.objects - before.objects <= heap_noise_objects && after.large_pages <= before.large_pages, '${hib_measured_cycles} suspends to disk left ${after.objects - before.objects} more live kernel heap objects and ${after.large_pages - before.large_pages} more large pages')
	// The pages a snapshot is copied into are a quarter of this machine's
	// memory; one cycle's not given back would show here four times over.
	t.check(free_before - free_after < 16384, '${hib_measured_cycles} suspends to disk left ${free_before - free_after} kB less memory free')
	hib_check_no_image(mut t, 'after ${cycles} cycles')
	t.check(network_works(20), 'the network does not work after ${cycles} cycles')
	t.info('${hib_measured_cycles} more cycles: live heap objects ${before.objects} -> ${after.objects}, large pages ${before.large_pages} -> ${after.large_pages}, MemFree ${free_before} -> ${free_after} kB; last image ${hib_number('image pages')} pages')
	hib_leave_note('') or { t.check(false, 'clearing the note: ${err.msg()}') }
}

// An image that must not be gone back into. In the first boot the machine
// is put away; the controller then makes the image, or the machine, other
// than it was, and in the second boot this program starts from the top and
// finds its note. `why` is what the kernel must give as its reason.
fn hibernate_refused(mut t Test, why string) {
	note := hib_note()
	if note == '' {
		if !hib_offered(mut t) {
			return
		}
		write_pattern(hib_data_disk, 1 << 20, 0x61, hib_pattern_bytes) or {
			t.check(false, 'a pattern on the disk: ${err.msg()}')
		}
		hib_leave_note('put away') or { t.check(false, 'leaving a note: ${err.msg()}') }
		if t.failures != 0 {
			return
		}
		t.step('hibernating')
		write_text(hib_state, 'disk') or {
			t.check(false, 'writing disk to state: ${err.msg()} (${deep_stat('last_failed_reason')})')
			return
		}
		t.check(false, 'the machine went back into an image it was to refuse')
		return
	}
	// Started afresh, as it must.
	t.check(note == 'put away', 'the note on the disk reads "${note}"')
	verdict := hib_line('boot')
	t.check(verdict.starts_with('image not resumed: ') && verdict.contains(why), 'the boot says "${verdict}"; it was to refuse the image because "${why}"')
	t.check(hib_number('resumes') == 0 && deep_stat('success') == '0', 'a resume or a sleep is counted in a machine that started afresh')
	// The image is gone for good, and the device can take another.
	hib_check_no_image(mut t, 'after the refusal')
	t.check(read_word(hib_state).contains('disk') && hib_offer() == 'available', 'disk is not offered after the refusal: "${read_word(hib_state)}", "${hib_offer()}"')
	// And the machine works: the disk has what was written before, takes
	// more, and the network answers.
	read_pattern(hib_data_disk, 1 << 20, 0x61, hib_pattern_bytes) or {
		t.check(false, 'the pattern written before the machine was put away: ${err.msg()}')
	}
	write_pattern(hib_data_disk, 2 << 20, 0x62, hib_pattern_bytes) or {
		t.check(false, 'a new pattern on the disk: ${err.msg()}')
	}
	t.check(network_works(20), 'the network does not work')
	t.info('started afresh: ${verdict}')
}

fn scenario_hibernate_damaged_header(mut t Test) {
	hibernate_refused(mut t, 'its header does not match its checksum')
}

fn scenario_hibernate_damaged_pages(mut t Test) {
	hibernate_refused(mut t, 'its pages do not match its checksum')
}

fn scenario_hibernate_memory(mut t Test) {
	hibernate_refused(mut t, 'memory')
}

// A disk more in the second boot than the image was taken with.
fn scenario_hibernate_disks(mut t Test) {
	hibernate_refused(mut t, 'the disks have changed')
}

// No device named: nothing is offered, and nothing is written anywhere. The
// controller compares both disks with what it made, byte for byte, so this
// writes to neither.
fn scenario_hibernate_unnamed(mut t Test) {
	state := read_word(hib_state)
	t.check(state == 'freeze mem', 'state offers "${state}" with no device named')
	t.check(hib_offer().starts_with('unavailable: ') && hib_offer().contains('no device was named'), 'hibernate says "${hib_offer()}"')
	t.check(hib_line('device') == 'none', 'the image device is "${hib_line('device')}"')
	mut refused := false
	write_text(hib_state, 'disk') or { refused = true }
	t.check(refused, 'writing disk to state worked with no device named')
	t.check(deep_stat('success') == '0' && deep_stat('fail') == '0', 'a sleep was counted: success ${deep_stat('success')}, fail ${deep_stat('fail')}')
	t.check(hib_number('images written') == 0, '${hib_number('images written')} images were written')
	// The other sleeps are untouched by any of this.
	write_text('/sys/class/rtc/rtc0/wakealarm', '+2') or { t.check(false, 'wakealarm: ${err.msg()}') }
	write_text(hib_state, 'freeze') or { t.check(false, 'freeze: ${err.msg()}') }
	t.check(deep_stat('success') == '1' && deep_stat('last_depth') == 's2idle', 'a suspend to idle afterwards: success ${deep_stat('success')}, depth ${deep_stat('last_depth')}')
	t.info('state: ${state}; hibernate: ${hib_offer()}; disk writes since boot: ${hib_number('disk writes since boot')}')
}

// A device is named, and it holds something that is not an image and is not
// nothing: somebody's data. It is not the kernel's to write to. `disk` is
// not offered, the reason is given, and the controller finds the device as
// it made it.
fn scenario_hibernate_foreign(mut t Test) {
	state := read_word(hib_state)
	t.check(state == 'freeze mem', 'state offers "${state}" with the named device holding something else')
	t.check(hib_offer().starts_with('unavailable: ') && hib_offer().contains('holds something else'), 'hibernate says "${hib_offer()}"')
	t.check(hib_line('device') == 'sd1' && hib_line('boot') == 'no image', 'the device is "${hib_line('device')}" and the boot found "${hib_line('boot')}"')
	mut refused := false
	write_text(hib_state, 'disk') or { refused = true }
	t.check(refused, 'writing disk to state worked with the named device holding something else')
	t.check(deep_stat('success') == '0' && hib_number('images written') == 0, 'a sleep or an image is counted: success ${deep_stat('success')}, images ${hib_number('images written')}')
	t.check(hib_number('disk writes since boot') == 0, '${hib_number('disk writes since boot')} writes went to a disk')
	// Named or not, nobody but root reads it.
	if attributes := os.stat(hib_image_disk) {
		t.check(attributes.mode & 0o777 == 0o600, '${hib_image_disk} has mode 0${attributes.mode & 0o777:o}, not 0600')
	} else {
		t.check(false, '${hib_image_disk} cannot be looked at')
	}
	t.info('state: ${state}; hibernate: ${hib_offer()}')
}

// ── A system that lives on a disk ───────────────────────────────────────────
//
// The scenarios above run from memory: the machine's root is the initial
// filesystem unpacked into RAM, and no filesystem on a disk is mounted when
// the image is taken. That is not what a suspend to disk is for. In the two
// below the machine has a third disk, blank and large enough for the kernel
// to install the system onto at its first start (vinix.disk=auto, which the
// boot medium always asks for), so that the root is an ext2 volume on sd2
// and the image holds that filesystem's state.

const hib_proof_a = '/hibernate-proof-a'
const hib_proof_b = '/hibernate-proof-b'
const hib_proof_bytes = 1 << 20

// Write a megabyte of a pattern to a file on the root, and have it reach the
// disk.
fn hib_write_proof(path string, seed u8) ! {
	os.write_file_array(path, pattern_bytes(seed, hib_proof_bytes))!
	fd := C.open(&char(path.str), C.O_RDONLY)
	if fd < 0 {
		return errno_error(path)
	}
	defer {
		C.close(fd)
	}
	if C.fsync(fd) != 0 {
		return errno_error(path)
	}
	C.sync()
}

// What is wrong with such a file, or ''.
fn hib_proof_problem(path string, seed u8) string {
	found := os.read_bytes(path) or { return '${path} cannot be read: ${err.msg()}' }
	if found.len != hib_proof_bytes {
		return '${path} is ${found.len} bytes long, not ${hib_proof_bytes}'
	}
	expected := pattern_bytes(seed, hib_proof_bytes)
	for i in 0 .. hib_proof_bytes {
		if found[i] != expected[i] {
			return '${path}: byte ${i} is 0x${found[i].hex()}, not 0x${expected[i].hex()}'
		}
	}
	return ''
}

// The machine was put back from its image, as the process that asked sees it.
fn hib_check_back(mut t Test) {
	t.check(hib_number('resumes') == 1 && deep_stat('last_wake') == 'resume-from-disk' && deep_stat('disk') == '1', 'the kernel counts ${hib_number('resumes')} resumes; last_wake is ${deep_stat('last_wake')}')
	t.check(hib_number('writes before the image was looked for') == 0, 'the boot that loaded the image had written to a disk first')
	t.check(deep_stat('security_changes') == '0' && deep_report('processors lost') == 0 && deep_report('pci functions not restored') == 0, 'the machine did not come back whole: ${deep_stat('security_changes')} protection changes, ${deep_report('processors lost')} processors lost, ${deep_report('pci functions not restored')} PCI functions not restored')
	hib_check_no_image(mut t, 'after the resume')
}

// hibernate-root: the system is on a disk when the image is taken, the same
// kernel goes on using that disk after it has been put back, and a third
// kernel, started afresh from the disk, finds on it what both of them wrote.
fn scenario_hibernate_root(mut t Test) {
	note := hib_note()
	if note == '' {
		if !hib_offered(mut t) {
			return
		}
		hib_write_proof(hib_proof_a, 0x71) or {
			t.check(false, 'a file on the root: ${err.msg()}')
			return
		}
		hib_leave_note('root: put away') or { t.check(false, 'leaving a note: ${err.msg()}') }
		if t.failures != 0 {
			return
		}
		t.step('hibernating')
		write_text(hib_state, 'disk') or {
			t.check(false, 'writing disk to state: ${err.msg()} (${deep_stat('last_failed_reason')})')
			return
		}
		// The same process, a boot later.
		hib_check_back(mut t)
		problem := hib_proof_problem(hib_proof_a, 0x71)
		t.check(problem == '', 'after the resume: ${problem}')
		// The filesystem the image held is used again: by the kernel whose
		// memory it is in, on a disk nothing has touched in between.
		hib_write_proof(hib_proof_b, 0x72) or { t.check(false, 'a second file on the root: ${err.msg()}') }
		t.check(network_works(20), 'the network does not work after the resume')
		hib_leave_note('root: back') or { t.check(false, 'leaving a note: ${err.msg()}') }
		t.info('resumed with the root on a disk: image of ${hib_number('image pages')} pages, loaded in ${hib_number('load ms')} ms')
		return
	}
	if !t.check(note == 'root: back', 'the machine started afresh after "${note}" instead of going back into its image: ${hib_line('boot')}') {
		return
	}
	// Started afresh from the disk, by a kernel that has seen none of it.
	t.step('read back from the disk')
	t.check(hib_line('boot') == 'no image' && hib_line('waiting') == 'none', 'the third boot found "${hib_line('boot')}", waiting "${hib_line('waiting')}"')
	first := hib_proof_problem(hib_proof_a, 0x71)
	second := hib_proof_problem(hib_proof_b, 0x72)
	t.check(first == '', 'what was written before the image was taken: ${first}')
	t.check(second == '', 'what was written after the resume: ${second}')
	hib_write_proof('/hibernate-proof-c', 0x73) or { t.check(false, 'a third file on the root: ${err.msg()}') }
	hib_leave_note('') or { t.check(false, 'clearing the note: ${err.msg()}') }
	t.info('started afresh from the disk: both files as written')
}

// hibernate-waiting: between the suspend to disk and the resume the machine
// is started once without the option that names the image's device. That
// kernel is not told of any image; it must find it all the same, leave it
// exactly as it is, and keep its hands off the system's disk, whose state
// the image holds: it runs from memory. The next start, with the option
// again, goes back into the image and finds the disk as the image knew it.
fn scenario_hibernate_waiting(mut t Test) {
	note := hib_note()
	if note == '' {
		if !hib_offered(mut t) {
			return
		}
		hib_write_proof(hib_proof_a, 0x75) or {
			t.check(false, 'a file on the root: ${err.msg()}')
			return
		}
		hib_leave_note('waiting: put away') or { t.check(false, 'leaving a note: ${err.msg()}') }
		if t.failures != 0 {
			return
		}
		t.step('hibernating')
		write_text(hib_state, 'disk') or {
			t.check(false, 'writing disk to state: ${err.msg()} (${deep_stat('last_failed_reason')})')
			return
		}
		// The same process, two boots later.
		t.step('back in the image')
		hib_check_back(mut t)
		problem := hib_proof_problem(hib_proof_a, 0x75)
		t.check(problem == '', 'after the resume: ${problem}')
		hib_write_proof(hib_proof_b, 0x76) or { t.check(false, 'a second file on the root: ${err.msg()}') }
		second := hib_proof_problem(hib_proof_b, 0x76)
		t.check(second == '', 'after the resume: ${second}')
		t.check(network_works(20), 'the network does not work after the resume')
		hib_leave_note('') or { t.check(false, 'clearing the note: ${err.msg()}') }
		t.info('resumed after a boot that left the image and the disks alone')
		return
	}
	if !t.check(note == 'waiting: put away', 'the note on the disk reads "${note}"') {
		return
	}
	if !t.check(hib_line('device') == 'none', 'the machine started afresh, with the device named, instead of going back into its image: ${hib_line('boot')}') {
		return
	}
	// The boot in between. Nothing here writes to a disk: not even the note.
	state := read_word(hib_state)
	t.check(state == 'freeze mem', 'state offers "${state}" with no device named')
	t.check(hib_line('waiting') == 'sd1', 'the kernel says an image is waiting on "${hib_line('waiting')}"; one is, on sd1')
	t.check(!os.exists(hib_proof_a), 'the file on the system\'s disk is there: the disk was mounted by a kernel that had not gone back into the image')
	t.check(hib_number('disk writes since boot') == 0, '${hib_number('disk writes since boot')} writes went to a disk')
	signature, pages := hib_image_header()
	t.check(signature == 'VINIXHIB' && pages > 0, 'the image device says "${signature}" with ${pages} pages: the image was to be left as it was')
	t.info('started without the option: an image of ${pages} pages found waiting on ${hib_line('waiting')}; running from memory, ${hib_number('disk writes since boot')} writes to disks')
}
