// SPDX-License-Identifier: GPL-2.0-or-later
// Independent N64 guest regression; real VAPP subprocesses and shared pixels.
@[translated; has_globals]
module guestfixture

#include <n64-guest-native-abi.h>

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
fn C.__atomic_load_n(&u32, i32) u32
fn C.__atomic_store_n(&u32, u32, i32)

const window_width = 800
const window_height = 680
const width = 640
const height = 480
const pixels = width * height
const surface_bytes = 48 + pixels * 8
const surface_prefix_length = 14
const log_path = unsafe { &char(c'/tmp/n64-emulator.log') }

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
	controlled   [pixels]u32
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
		C.printf(c'N64 FAIL: %s (poll frame %u)\n', reason, frame_count)
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

fn changed_court(left &u32, right &u32) u32 {
	unsafe {
		mut result := u32(0)
		// BEST persists across reset; deterministic gameplay excludes that HUD.
		for index := u32(width * 64); index < pixels; index++ { result += u32(left[index] != right[index]) }
		return result
	}
}

fn inspect_frame(frame &u32, homebrew bool) {
	unsafe {
		mut lit := u32(0)
		mut distinct := u32(0)
		mut rdp_background := u32(0)
		mut colors := [4096]u8{}
		for index := u32(0); index < pixels; index++ {
			color := frame[index]
			lit += u32((color & 0xffffff) != 0)
			red := (color >> 16) & 255
			green := (color >> 8) & 255
			blue := color & 255
			rdp_background += u32(red >= 4 && red <= 16 && green >= 8 && green <= 24 && blue >= 24 && blue <= 40)
			colors[((color >> 12) & 0xf00) | ((color >> 8) & 0xf0) | ((color >> 4) & 0xf)] = 1
		}
		for index := usize(0); index < sizeof(colors); index++ { distinct += colors[index] }
		C.printf(c'N64-PIXELS: lit=%u colors=%u rdp-background=%u\n', lit, distinct, rdp_background)
		if lit < pixels / 32 || distinct < 4 { fail(c'Nintendo 64 did not draw a detailed game frame') }
		if homebrew && rdp_background < pixels / 3 { fail(c'the real RDP did not clear the homebrew framebuffer') }
	}
}

fn export_frame(frame &u32) {
	unsafe {
		// Assertions inspect the full 640x480 surface; the serial artifact is quarter size.
		digits := &char(c'0123456789abcdef')
		mut row := [width / 4 * 6 + 2]char{}
		C.printf(c'N64-FRAME: %u %u\n', u32(width / 4), u32(height / 4))
		for y := u32(0); y < height; y += 4 {
			C.fputs(c'N64-ROW: ', C.stdout)
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
			C.setenv(c'VINIX_N64_DATA', c'/opt/n64/data', 1)
			if game != nil { C.execl(c'/usr/bin/vinix-n64', c'vinix-n64', c'--mute', game, &char(nil)) }
			else { C.execl(c'/usr/bin/vinix-n64', c'vinix-n64', c'--mute', &char(nil)) }
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
	// Original N64 code copies its program through PI, initializes VI and reads SRAM.
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
			C.printf(c'N64-STATUS: %s\n', &status_text[0])
			fail(c'Open game did not explain rejected content')
		}
	}
}

fn test_rejected_content() {
	unsafe {
		mut invalid := [u8(0x80), 0x37, 0x12, 0x40, 0, 0, 0]!
		mut fd := C.open(c'/opt/n64/truncated.z64', C.O_CREAT | C.O_TRUNC | C.O_WRONLY, i32(0o600))
		if fd < 0 || C.write(fd, &invalid[0], sizeof(invalid)) != isize(sizeof(invalid)) { fail(c'truncated ROM fixture') }
		C.close(fd)
		fd = C.open(c'/opt/n64/bad-header.z64', C.O_CREAT | C.O_TRUNC | C.O_WRONLY, i32(0o600))
		if fd < 0 || C.ftruncate(fd, 0x100000) != 0 { fail(c'invalid ROM header fixture') }
		C.close(fd)
		action(c'pause')
		snapshot(&first[0])
		rejected_open(c'/opt/n64/truncated.z64', c'ROM')
		rejected_open(c'/opt/n64/bad-header.z64', c'header')
		ticks(4)
		snapshot(&last[0])
		if changed(&first[0], &last[0]) != 0 { fail(c'failed Open ROM lost the paused game') }
		action(c'pause')
		ticks(8)
		snapshot(&last[0])
		if changed(&first[0], &last[0]) < 16 { fail(c'failed Open ROM could not resume the previous game') }
		snapshot(&first[0])
		rejected_open(c'/opt/n64/missing.z64', c'path')
		ticks(8)
		snapshot(&last[0])
		if changed(&first[0], &last[0]) < 16 { fail(c'missing ROM request stopped the previous running game') }
		C.puts(c'N64 PASS: rejected content preserves the running game and pause state')
	}
}

fn read_sram(fd i32, values &u32) bool {
	unsafe {
		mut raw := [16]u8{}
		if C.pread(fd, &raw[0], sizeof(raw), 133120) != isize(sizeof(raw)) { return false }
		// The packed save retains the emulator's little-endian host word order.
		for i := u32(0); i < 4; i++ {
			values[i] = u32(raw[i * 4]) | u32(raw[i * 4 + 1]) << 8 | u32(raw[i * 4 + 2]) << 16 | u32(raw[i * 4 + 3]) << 24
		}
		return true
	}
}

fn write_sram(fd i32, values &u32) bool {
	unsafe {
		mut raw := [16]u8{}
		for i := u32(0); i < 4; i++ {
			for j := u32(0); j < 4; j++ { raw[i * 4 + j] = u8(values[i] >> (j * 8)) }
		}
		return C.pwrite(fd, &raw[0], sizeof(raw), 133120) == isize(sizeof(raw)) && C.fsync(fd) == 0
	}
}

fn test_sram() {
	unsafe {
		game := &char(c'/usr/share/games/n64/paddle.z64')
		mut hash := u32(2166136261)
		for index := u32(0); game[index] != 0; index++ { hash = (hash ^ u32(u8(game[index]))) * u32(16777619) }
		mut path := [256]char{}
		C.snprintf(&path[0], sizeof(path), c'/opt/n64/data/saves/paddle.z64-%08x.sav', hash)
		mut info := C.stat{}
		if C.stat(&path[0], &info) != 0 || info.st_size != 296960 { fail(c'N64 save file geometry') }
		// Change BEST and require a fresh process to load it and increment games.
		mut record := [4]u32{}
		mut fd := C.open(&path[0], C.O_RDWR)
		if fd < 0 || !read_sram(fd, &record[0]) || record[0] != 0x4e504144 || record[2] == 0 ||
			record[3] != (record[0] ^ record[1] ^ record[2]) { fail(c'game did not write its cartridge SRAM through PI') }
		games := record[2]
		record[1] = 42
		record[3] = record[0] ^ record[1] ^ record[2]
		if !write_sram(fd, &record[0]) { fail(c'cartridge SRAM fixture write') }
		C.close(fd)
		start(nil)
		begin_paddle()
		snapshot(&last[0])
		inspect_frame(&last[0], true)
		stop()
		fd = C.open(&path[0], C.O_RDONLY)
		if fd < 0 || !read_sram(fd, &record[0]) || record[0] != 0x4e504144 || record[1] != 42 || record[2] != games + 1 ||
			record[3] != (record[0] ^ record[1] ^ record[2]) { fail(c'fresh N64 process did not load and update its PI SRAM save') }
		C.close(fd)
		C.puts(c'N64 PASS: cartridge SRAM survives a fresh emulator process')
	}
}

fn test_rom_formats() {
	unsafe {
		paths := [&char(c'/opt/n64/paddle.v64'), &char(c'/opt/n64/paddle.n64')]!
		for i := usize(0); i < sizeof(paths) / sizeof(paths[0]); i++ {
			start(paths[i])
			begin_paddle()
			snapshot(&first[0])
			inspect_frame(&first[0], true)
			ticks(8)
			snapshot(&last[0])
			if changed(&first[0], &last[0]) < 16 { fail(c'converted ROM did not run and animate') }
			stop()
		}
		C.puts(c'N64 PASS: byte-swapped and word-swapped ROM formats boot real code')
	}
}

fn test_instruction_limit() {
	unsafe {
		// Structurally valid stalled boot code must reply and permit another game.
		start(c'/opt/n64/budget.z64')
		ticks(1)
		command(1, c'')
		status_text[0] = 0
		if parse(0, 0) != byte_count || C.strstr(&status_text[0], c'instruction limit') == nil {
			C.printf(c'N64-STATUS: %s\n', &status_text[0])
			fail(c'stalled boot code did not report its instruction limit')
		}
		ticks(2)
		action(c'open')
		command(3, c'/usr/share/games/n64/paddle.z64')
		command(3, c'\n')
		begin_paddle()
		snapshot(&first[0])
		inspect_frame(&first[0], true)
		ticks(8)
		snapshot(&last[0])
		if changed(&first[0], &last[0]) < 16 { fail(c'emulator did not recover after its instruction limit') }
		stop()
		C.puts(c'N64 PASS: stalled boot code hits its instruction limit and recovers')
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
		inspect_frame(&first[0], true)
		export_frame(&first[0])
		ticks(8)
		snapshot(&last[0])
		animated := changed(&first[0], &last[0])
		C.printf(c'N64-GAMEPLAY: animated=%u\n', animated)
		if animated < 16 { fail(c'running Nintendo 64 game did not animate') }
		C.puts(c'N64 PASS: native emulator boots Nintendo 64 code and publishes real frames')

		// Equal ages distinguish actual controller effects from animation alone.
		action(c'reset')
		begin_paddle()
		ticks(20)
		snapshot(&neutral[0])
		action(c'reset')
		begin_paddle()
		pointer(1, 352, 613)
		action(c'n64.right')
		ticks(12)
		pointer(2, 352, 613)
		ticks(8)
		snapshot(&last[0])
		moved := changed(&neutral[0], &last[0])
		C.printf(c'N64-CONTROLLER: equal-age input changed=%u\n', moved)
		if moved < 16 { fail(c'controller did not change the emulated game') }
		C.puts(c'N64 PASS: controller input changes the emulated game')
		export_frame(&last[0])
		C.memcpy(&controlled[0], &last[0], sizeof(controlled))

		action(c'reset')
		begin_paddle()
		action(c'stick_right')
		ticks(20)
		snapshot(&last[0])
		analog := changed_court(&neutral[0], &last[0])
		C.printf(c'N64-ANALOG: equal-age input changed=%u\n', analog)
		if analog < 16 { fail(c'analog stick did not change the emulated game') }
		C.puts(c'N64 PASS: analog stick reaches the emulated controller')

		action(c'reset')
		begin_paddle()
		command(3, c'\x1b[C\x1b[C')
		ticks(20)
		snapshot(&last[0])
		if changed_court(&controlled[0], &last[0]) != 0 { fail(c'batched arrow keys did not match the real D-pad') }
		action(c'reset')
		begin_paddle()
		command(3, c'dd')
		ticks(20)
		snapshot(&last[0])
		if changed_court(&controlled[0], &last[0]) != 0 { fail(c'batched WASD keys did not match the analog stick') }
		C.puts(c'N64 PASS: batched arrow and WASD input stays running and moves the game')

		toolbar(c'n64.pause', 184, 575)
		snapshot(&first[0])
		action(c'open')
		command(3, c'\x1b')
		ticks(4)
		snapshot(&last[0])
		if changed(&first[0], &last[0]) != 0 { fail(c'emulation drew while paused') }
		toolbar(c'n64.pause', 184, 575)
		ticks(8)
		snapshot(&last[0])
		if changed(&first[0], &last[0]) < 16 { fail(c'emulation did not resume') }
		C.puts(c'N64 PASS: pause freezes emulation and resume produces new frames')

		action(c'reset')
		begin_paddle()
		ticks(20)
		snapshot(&last[0])
		if changed_court(&neutral[0], &last[0]) != 0 { fail(c'reset did not reproduce the game\'s initial state') }
		test_rejected_content()
		stop()
		C.puts(c'N64 PASS: reset restarts the game and close releases the native surface')
		test_sram()
		test_rom_formats()
		test_instruction_limit()

		game := C.fopen(c'/opt/n64/game-path', c'r')
		if game != nil {
			mut path := [4096]char{}
			if C.fgets(&path[0], i32(sizeof(path)), game) == nil { fail(c'supplied game path') }
			C.fclose(game)
			path[C.strcspn(&path[0], c'\r\n')] = 0
			start(&path[0])
			ticks(180)
			press(c'start')
			press(c'a')
			ticks(60)
			snapshot(&last[0])
			inspect_frame(&last[0], false)
			export_frame(&last[0])
			stop()
			C.puts(c'N64 PASS: supplied game rendered and shut down cleanly')
		}
		C.puts(c'VINIX N64 GUEST: PASS')
		for { C.pause() }
		return 0
	}
}
