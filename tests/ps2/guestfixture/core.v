// SPDX-License-Identifier: GPL-2.0-or-later
// Independent PS2 guest regression; real VAPP subprocesses and shared pixels.
@[translated; has_globals]
module guestfixture

#include <ps2-guest-native-abi.h>

@[typedef]
struct C.FILE {}
struct C.pollfd {
mut:
	fd      i32
	events  i16
	revents i16
}
struct C.stat {
mut:
	st_size i64
}

@[c_extern] __global C.errno i32
@[c_extern] __global C.stdout &C.FILE
fn C.printf(&char, ...) i32
fn C.puts(&char) i32
fn C.fopen(&char, &char) &C.FILE
fn C.fgets(&char, i32, &C.FILE) &char
fn C.fputs(&char, &C.FILE) i32
fn C.fclose(&C.FILE) i32
fn C.fflush(&C.FILE) i32
fn C.setvbuf(&C.FILE, &char, i32, usize) i32
fn C.poll(&C.pollfd, usize, i32) i32
fn C.signal(i32, fn (i32)) fn (i32)
fn C.pause() i32
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.memset(voidptr, i32, usize) voidptr
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.strlen(&char) usize
fn C.strstr(&char, &char) &char
fn C.strcspn(&char, &char) usize
fn C.read(i32, voidptr, usize) isize
fn C.write(i32, voidptr, usize) isize
fn C.open(&char, i32, ...) i32
fn C.close(i32) i32
fn C.dup2(i32, i32) i32
fn C.pipe(&i32) i32
fn C.fork() i32
fn C._exit(i32)
fn C.execl(&char, &char, ...&char) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.setenv(&char, &char, i32) i32
fn C.fstat(i32, &C.stat) i32
fn C.stat(&char, &C.stat) i32
fn C.ftruncate(i32, i64) i32
fn C.mmap(voidptr, usize, i32, i32, i32, i64) voidptr
fn C.munmap(voidptr, usize) i32
fn C.waitpid(i32, &i32, i32) i32
fn C.WIFEXITED(i32) bool
fn C.WEXITSTATUS(i32) i32
fn C.usleep(u32) i32
fn C.access(&char, i32) i32
fn C.pread(i32, voidptr, usize, i64) isize
fn C.pwrite(i32, voidptr, usize, i64) isize
fn C.fsync(i32) i32
fn C.rename(&char, &char) i32
fn C.__atomic_load_n(&u32, i32) u32
fn C.__atomic_store_n(&u32, u32, i32)

const window_width = 800
const window_height = 680
const width = 640
const height = 480
const pixels = width * height
const surface_bytes = 48 + pixels * 8
const surface_prefix_length = 14
const log_path = unsafe { &char(c'/tmp/ps2-emulator.log') }

__global (
	request_fd   i32 = -1
	response_fd  i32 = -1
	state        [116]u8
	bytes        [65536]u8
	byte_count   usize
	surface_path [512]char
	status_text  [1024]char
	surface      &u32
	first        [pixels]u32
	last         [pixels]u32
	neutral      [pixels]u32
	child        i32
	frame_count  u32
)

fn print_log() {
	unsafe {
		log := C.fopen(log_path, c'r')
		if log == nil { return }
		mut line := [512]char{}
		for C.fgets(&line[0], i32(sizeof(line)), log) != nil { C.fputs(&line[0], C.stdout) }
		C.fclose(log)
	}
}

fn fail(reason &char) {
	unsafe {
		print_log()
		C.printf(c'PS2 FAIL: %s (poll frame %u)\n', reason, frame_count)
		C.fflush(C.stdout)
		for { C.pause() }
	}
}

fn number(pointer voidptr) u32 {
	unsafe {
		mut value := u32(0)
		C.memcpy(&value, pointer, sizeof(value))
		return value
	}
}

fn transfer(fd i32, pointer voidptr, length usize, writing bool) {
	unsafe {
		mut offset := usize(0)
		for offset < length {
			if !writing {
				mut waiting := C.pollfd{fd: fd, events: i16(C.POLLIN)}
				mut ready := i32(0)
				for {
					ready = C.poll(&waiting, 1, 30000)
					if !(ready < 0 && C.errno == C.EINTR) { break }
				}
				if ready <= 0 { fail(c'application reply timeout') }
			}
			address := &char(pointer) + offset
			count := if writing { C.write(fd, address, length - offset) }
				else { C.read(fd, address, length - offset) }
			if count < 0 && C.errno == C.EINTR { continue }
			if count <= 0 { fail(c'application pipe closed') }
			offset += usize(count)
		}
	}
}

fn reply() {
	unsafe {
		mut header := [128]u8{}
		transfer(response_fd, &header[0], sizeof(header), false)
		if number(&header[0]) != 0x56415050 || header[4] != 10 || header[5] != 0 { fail(c'VAPP reply header') }
		C.memcpy(&state[0], &header[8], sizeof(state))
		byte_count = usize(number(&header[124]))
		if byte_count > sizeof(bytes) { fail(c'VAPP reply size') }
		transfer(response_fd, &bytes[0], byte_count, false)
	}
}

fn command_data(kind u32, payload voidptr, length u32) {
	unsafe {
		mut header := [136]u8{}
		mut magic := u32(0x56415050)
		mut request_width := u32(window_width)
		mut request_height := u32(window_height)
		C.memcpy(&header[0], &magic, 4)
		header[4] = 10
		header[5] = u8(kind)
		C.memcpy(&header[8], &request_width, 4)
		C.memcpy(&header[12], &request_height, 4)
		C.memcpy(&header[16], &state[0], sizeof(state))
		C.memcpy(&header[132], &length, 4)
		transfer(request_fd, &header[0], sizeof(header), true)
		transfer(request_fd, payload, length, true)
		reply()
		if kind == 4 { frame_count++ }
	}
}

fn command(kind u32, payload &char) { unsafe { command_data(kind, payload, u32(C.strlen(payload))) } }
fn ticks(count u32) { for index := u32(0); index < count; index++ { command(4, c'') } }
fn action(name &char) { command(2, name) }
fn press(name &char) { action(name); ticks(12) }

fn pointer(phase u32, x i32, y i32) {
	unsafe {
		mut payload := [i32(phase), 1, 0, x, y, window_width, window_height]!
		command_data(5, &payload[0], u32(sizeof(payload)))
	}
}

fn toolbar(name &char, x i32, y i32) {
	// The desktop sends both raw pointer events and the button's action.
	pointer(1, x, y)
	action(name)
	pointer(2, x, y)
}

fn parse(start_offset usize, depth u32) usize {
	unsafe {
		mut offset := start_offset
		if depth > 32 || offset + 274 > byte_count { fail(c'view element size') }
		kind := bytes[offset]
		offset += 274
		for index := u32(0); index < 12; index++ {
			if offset + 4 > byte_count { fail(c'view string boundary') }
			length := usize(number(&bytes[offset]))
			offset += 4
			if length > byte_count - offset { fail(c'view string size') }
			if kind == 2 && index == 3 {
				if length >= sizeof(status_text) { fail(c'status label size') }
				C.memcpy(&status_text[0], &bytes[offset], length)
				status_text[length] = 0
			}
			prefix := &char(c'vinix-surface:')
			// sizeof the original NUL-terminated prefix minus its terminator.
			if index == 4 && length > surface_prefix_length && C.memcmp(&bytes[offset], prefix, surface_prefix_length) == 0 {
				path_length := length - surface_prefix_length
				if path_length >= sizeof(surface_path) { fail(c'surface path size') }
				C.memcpy(&surface_path[0], &bytes[offset + surface_prefix_length], path_length)
				surface_path[path_length] = 0
			}
			offset += length
		}
		if offset + 8 > byte_count || number(&bytes[offset]) != 0 { fail(c'view menu boundary') }
		children := number(&bytes[offset + 4])
		offset += 8
		if children > 64 { fail(c'view child count') }
		for index := u32(0); index < children; index++ { offset = parse(offset, depth + 1) }
		return offset
	}
}

fn snapshot(destination &u32) {
	unsafe {
		active := C.__atomic_load_n(surface + 7, C.__ATOMIC_ACQUIRE)
		if active > 1 { fail(c'surface active buffer') }
		C.__atomic_store_n(surface + 8, active, C.__ATOMIC_RELEASE)
		C.memcpy(destination, surface + 12 + active * pixels, pixels * 4)
		C.__atomic_store_n(surface + 8, ~u32(0), C.__ATOMIC_RELEASE)
	}
}

fn changed(left &u32, right &u32) u32 {
	unsafe {
		mut result := u32(0)
		for index := u32(0); index < pixels; index++ { result += u32(left[index] != right[index]) }
		return result
	}
}

fn inspect_frame(frame &u32) {
	unsafe {
		mut lit := u32(0)
		mut distinct := u32(0)
		mut colors := [4096]u8{}
		for index := u32(0); index < pixels; index++ {
			color := frame[index]
			lit += u32((color & 0xffffff) != 0)
			colors[((color >> 12) & 0xf00) | ((color >> 8) & 0xf0) | ((color >> 4) & 0xf)] = 1
		}
		for index := usize(0); index < sizeof(colors); index++ { distinct += colors[index] }
		C.printf(c'PS2-PIXELS: lit=%u colors=%u\n', lit, distinct)
		if lit < pixels / 32 || distinct < 4 { fail(c'PlayStation did not draw a detailed game frame') }
	}
}

fn export_frame(frame &u32) {
	unsafe {
		// Assertions inspect the full 640x480 surface; the serial artifact is quarter size.
		digits := &char(c'0123456789abcdef')
		mut row := [width / 4 * 6 + 2]char{}
		C.printf(c'PS2-FRAME: %u %u\n', u32(width / 4), u32(height / 4))
		for y := u32(0); y < height; y += 4 {
			C.fputs(c'PS2-ROW: ', C.stdout)
			for x := u32(0); x < width; x += 4 {
				color := frame[y * width + x]
				for index := u32(0); index < 6; index++ {
					row[x / 4 * 6 + index] = digits[(color >> (20 - index * 4)) & 15]
				}
			}
			row[sizeof(row) - 2] = `\n`
			row[sizeof(row) - 1] = 0
			C.fputs(&row[0], C.stdout)
		}
	}
}

fn start(game &char) {
	unsafe {
		mut requests := [2]i32{}
		mut responses := [2]i32{}
		if C.pipe(&requests[0]) != 0 || C.pipe(&responses[0]) != 0 { fail(c'pipes') }
		child = C.fork()
		if child < 0 { fail(c'fork') }
		if child == 0 {
			C.close(requests[1])
			C.close(responses[0])
			log := C.open(log_path, C.O_CREAT | C.O_TRUNC | C.O_RDWR, i32(0o600))
			if log < 0 || C.dup2(log, 1) < 0 || C.dup2(log, 2) < 0 { C._exit(126) }
			C.close(log)
			mut input := [32]char{}
			mut output := [32]char{}
			C.snprintf(&input[0], sizeof(input), c'%d', requests[0])
			C.snprintf(&output[0], sizeof(output), c'%d', responses[1])
			C.setenv(c'VINIX_REQUEST_FD', &input[0], 1)
			C.setenv(c'VINIX_RESPONSE_FD', &output[0], 1)
			C.setenv(c'VINIX_PS2_DATA', c'/opt/ps2/data', 1)
			if game != nil { C.execl(c'/usr/bin/vinix-ps2', c'vinix-ps2', c'--mute', game, &char(nil)) }
			else { C.execl(c'/usr/bin/vinix-ps2', c'vinix-ps2', c'--mute', &char(nil)) }
			C._exit(127)
		}
		C.close(requests[0])
		C.close(responses[1])
		request_fd = requests[1]
		response_fd = responses[0]
		frame_count = 0
		C.memset(&state[0], 0, sizeof(state))
		reply()
		command(1, c'')
		surface_path[0] = 0
		if parse(0, 0) != byte_count || surface_path[0] == 0 { fail(c'shared surface view missing') }
		fd := C.open(&surface_path[0], C.O_RDWR)
		mut info := C.stat{}
		if fd < 0 || C.fstat(fd, &info) != 0 || info.st_size != surface_bytes { fail(c'surface file size') }
		surface = &u32(C.mmap(nil, surface_bytes, C.PROT_READ | C.PROT_WRITE, C.MAP_SHARED, fd, 0))
		C.close(fd)
		if usize(surface) == usize(C.MAP_FAILED) || surface[0] != 0x31534656 || surface[1] != 1 || surface[2] != 48 ||
			surface[3] != width || surface[4] != height || surface[5] != width * 4 || surface[6] != 1 { fail(c'VSF1 header') }
	}
}

fn stop() {
	unsafe {
		command(6, c'')
		C.close(request_fd)
		C.close(response_fd)
		mut status := i32(0)
		mut reaped := false
		for attempt := u32(0); attempt < 500; attempt++ {
			result := C.waitpid(child, &status, C.WNOHANG)
			if result == child { reaped = true; break }
			if result < 0 && C.errno != C.EINTR { fail(c'application waitpid') }
			C.usleep(10000)
		}
		if !reaped || !C.WIFEXITED(status) || C.WEXITSTATUS(status) != 0 { fail(c'application clean shutdown') }
		if C.munmap(surface, surface_bytes) != 0 { fail(c'surface munmap') }
		if C.access(&surface_path[0], C.F_OK) == 0 { fail(c'surface file leaked') }
		print_log()
	}
}

fn begin_paddle() {
	// PS2 code boots both processors, initializes GS and reads its memory card.
	ticks(2)
	press(c'start')
}

fn rejected_open(path &char, message &char) {
	unsafe {
		action(c'open')
		command(3, path)
		command(3, c'\n')
		command(1, c'')
		status_text[0] = 0
		if parse(0, 0) != byte_count || C.strstr(&status_text[0], message) == nil {
			C.printf(c'PS2-STATUS: %s\n', &status_text[0])
			fail(c'Open game did not explain rejected content')
		}
	}
}

fn test_rejected_content() {
	unsafe {
		// A magic-only ELF must never reach the emulated loader.
		mut invalid := [u8(0x7f), `E`, `L`, `F`, 1, 1, 1]!
		mut fd := C.open(c'/opt/ps2/truncated.elf', C.O_CREAT | C.O_TRUNC | C.O_WRONLY, i32(0o600))
		if fd < 0 || C.write(fd, &invalid[0], sizeof(invalid)) != isize(sizeof(invalid)) { fail(c'malformed ELF fixture') }
		C.close(fd)
		// Reject a complete LOAD segment crossing the machine's 32 MiB RAM boundary.
		mut oversized := [84]u8{}
		mut magic := [u8(0x7f), `E`, `L`, `F`, 1, 1, 1, 0x56]!
		C.memcpy(&oversized[0], &magic[0], sizeof(magic))
		mut elf_type := u16(2)
		mut machine := u16(8)
		mut header_size := u16(52)
		mut entry_size := u16(32)
		mut entries := u16(1)
		mut version := u32(1)
		mut entry := u32(0x00100000)
		mut headers := u32(52)
		C.memcpy(&oversized[16], &elf_type, 2)
		C.memcpy(&oversized[18], &machine, 2)
		C.memcpy(&oversized[20], &version, 4)
		C.memcpy(&oversized[24], &entry, 4)
		C.memcpy(&oversized[28], &headers, 4)
		C.memcpy(&oversized[40], &header_size, 2)
		C.memcpy(&oversized[42], &entry_size, 2)
		C.memcpy(&oversized[44], &entries, 2)
		mut segment := [u32(1), u32(sizeof(oversized)), u32(0x01fff000), u32(0x01fff000), u32(0), u32(8192), u32(5), u32(16)]!
		C.memcpy(&oversized[52], &segment[0], sizeof(segment))
		fd = C.open(c'/opt/ps2/outside-ram.elf', C.O_CREAT | C.O_TRUNC | C.O_WRONLY, i32(0o600))
		if fd < 0 || C.write(fd, &oversized[0], sizeof(oversized)) != isize(sizeof(oversized)) { fail(c'out-of-range ELF fixture') }
		C.close(fd)
		action(c'pause')
		snapshot(&first[0])
		rejected_open(c'/opt/ps2/truncated.elf', c'ELF')
		rejected_open(c'/opt/ps2/outside-ram.elf', c'RAM')
		ticks(4)
		snapshot(&last[0])
		if changed(&first[0], &last[0]) != 0 { fail(c'failed Open game lost the paused game') }
		action(c'pause')
		ticks(8)
		snapshot(&last[0])
		if changed(&first[0], &last[0]) < 16 { fail(c'failed Open game could not resume the previous game') }

		// Hide even an optional supplied BIOS only inside this disposable VM.
		had_bios := C.rename(c'/opt/ps2/data/bios/ps2.bin', c'/opt/ps2/data/bios/ps2.bin.saved') == 0
		fd = C.open(c'/opt/ps2/firmware-required.iso', C.O_CREAT | C.O_TRUNC | C.O_WRONLY, i32(0o600))
		if fd < 0 || C.ftruncate(fd, 32768) != 0 { fail(c'disc fixture') }
		C.close(fd)
		snapshot(&first[0])
		rejected_open(c'/opt/ps2/firmware-required.iso', c'BIOS')
		ticks(8)
		snapshot(&last[0])
		if changed(&first[0], &last[0]) < 16 { fail(c'missing BIOS request stopped the previous running game') }
		if had_bios && C.rename(c'/opt/ps2/data/bios/ps2.bin.saved', c'/opt/ps2/data/bios/ps2.bin') != 0 { fail(c'BIOS fixture restore') }
		C.puts(c'PS2 PASS: rejected content preserves the running game and pause state')
	}
}

fn test_card() {
	unsafe {
		game := &char(c'/usr/share/games/ps2/paddle.elf')
		mut hash := u32(2166136261)
		for index := u32(0); game[index] != 0; index++ { hash = (hash ^ u32(u8(game[index]))) * u32(16777619) }
		mut path := [256]char{}
		C.snprintf(&path[0], sizeof(path), c'/opt/ps2/data/saves/paddle.elf-%08x.ps2', hash)
		mut info := C.stat{}
		if C.stat(&path[0], &info) != 0 || info.st_size != 16384 * 528 { fail(c'PS2 memory card geometry') }
		// The IOP wrote through SIO2. Preserve BEST and increment games on reload.
		mut record := [4]u32{}
		mut fd := C.open(&path[0], C.O_RDWR)
		if fd < 0 || C.pread(fd, &record[0], sizeof(record), 16 * 528) != isize(sizeof(record)) ||
			record[0] != 0x44415056 || record[2] == 0 || record[3] != (record[0] ^ record[1] ^ record[2]) { fail(c'game did not write its memory card through SIO2') }
		games := record[2]
		record[1] = 42
		record[3] = record[0] ^ record[1] ^ record[2]
		if C.pwrite(fd, &record[0], sizeof(record), 16 * 528) != isize(sizeof(record)) || C.fsync(fd) != 0 { fail(c'memory card fixture write') }
		C.close(fd)
		start(nil)
		begin_paddle()
		snapshot(&last[0])
		inspect_frame(&last[0])
		stop()
		fd = C.open(&path[0], C.O_RDONLY)
		if fd < 0 || C.pread(fd, &record[0], sizeof(record), 16 * 528) != isize(sizeof(record)) ||
			record[0] != 0x44415056 || record[1] != 42 || record[2] != games + 1 ||
			record[3] != (record[0] ^ record[1] ^ record[2]) { fail(c'fresh PS2 process did not load and update its SIO2 save') }
		C.close(fd)
		C.puts(c'PS2 PASS: memory card survives a fresh emulator process')
	}
}

@[export: 'main']
pub fn run() i32 {
	unsafe {
		C.setvbuf(C.stdout, nil, C._IONBF, 0)
		C.signal(C.SIGPIPE, C.SIG_IGN)
		start(nil)
		begin_paddle()
		snapshot(&first[0])
		inspect_frame(&first[0])
		export_frame(&first[0])
		ticks(8)
		snapshot(&last[0])
		animated := changed(&first[0], &last[0])
		C.printf(c'PS2-GAMEPLAY: animated=%u\n', animated)
		if animated < 16 { fail(c'running PlayStation game did not animate') }
		C.puts(c'PS2 PASS: native emulator boots PlayStation code and publishes real frames')

		// Equal emulated ages distinguish actual controller effects from animation.
		action(c'reset')
		begin_paddle()
		ticks(20)
		snapshot(&neutral[0])
		action(c'reset')
		begin_paddle()
		pointer(1, 348, 613)
		action(c'ps2.right')
		ticks(12)
		pointer(2, 348, 613)
		ticks(8)
		snapshot(&last[0])
		moved := changed(&neutral[0], &last[0])
		C.printf(c'PS2-CONTROLLER: equal-age input changed=%u\n', moved)
		if moved < 16 { fail(c'controller did not change the emulated game') }
		C.puts(c'PS2 PASS: controller input changes the emulated game')
		export_frame(&last[0])

		toolbar(c'ps2.pause', 184, 575)
		snapshot(&first[0])
		action(c'open')
		command(3, c'\x1b')
		ticks(4)
		snapshot(&last[0])
		if changed(&first[0], &last[0]) != 0 { fail(c'emulation drew while paused') }
		toolbar(c'ps2.pause', 184, 575)
		ticks(8)
		snapshot(&last[0])
		if changed(&first[0], &last[0]) < 16 { fail(c'emulation did not resume') }
		C.puts(c'PS2 PASS: pause freezes emulation and resume produces new frames')

		action(c'reset')
		begin_paddle()
		ticks(20)
		snapshot(&last[0])
		if changed(&neutral[0], &last[0]) != 0 { fail(c'reset did not reproduce the game\'s initial state') }
		test_rejected_content()
		stop()
		C.puts(c'PS2 PASS: reset restarts the game and close releases the native surface')
		test_card()

		game := C.fopen(c'/opt/ps2/game-path', c'r')
		if game != nil {
			mut path := [4096]char{}
			if C.fgets(&path[0], i32(sizeof(path)), game) == nil { fail(c'supplied game path') }
			C.fclose(game)
			path[C.strcspn(&path[0], c'\r\n')] = 0
			start(&path[0])
			ticks(180)
			press(c'start')
			press(c'cross')
			ticks(60)
			snapshot(&last[0])
			inspect_frame(&last[0])
			export_frame(&last[0])
			stop()
			C.puts(c'PS2 PASS: supplied game rendered and shut down cleanly')
		}
		C.puts(c'VINIX PS2 GUEST: PASS')
		for { C.pause() }
	}
	return 0
}
