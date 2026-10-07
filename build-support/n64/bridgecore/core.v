// SPDX-License-Identifier: MIT
// One owner of the unchanged libretro core; explicit native allocations only.
@[translated; has_globals]
module bridgecore

#include <native-abi.h>

@[typedef] struct C.FILE {}
@[typedef] struct C.n64_const_void {}
@[typedef] struct C.n64_const_sample {}
@[typedef] struct C.n64_const_char {}
@[typedef] struct C.n64_frame_escape {}
@[typedef] struct C.n64_native_va {}
struct C.stat { st_mode u32 st_size i64 }
struct C.r4300_core {}
struct C.device { mut: r4300 C.r4300_core }
struct C.retro_log_callback { mut: @log fn (i32, &char, ...) }
struct C.retro_variable { mut: key &C.n64_const_char value &C.n64_const_char }
struct C.retro_system_timing { sample_rate f64 }
struct C.retro_system_av_info { timing C.retro_system_timing }
struct C.retro_game_info { path &char data voidptr size usize meta &char }

@[c_extern] __global C.errno i32
@[c_extern] __global C.frame_break i32
@[c_extern] __global C.g_rsp_force_halt i32
@[c_extern] __global C.g_real_stop i32
@[c_extern] __global C.g_dev C.device

fn C.snprintf(&char, usize, &char, ...) i32
fn C.vsnprintf(&char, usize, &char, C.n64_native_va) i32
fn C.strcmp(&char, &char) i32
fn C.strlen(&char) usize
fn C.strdup(&char) &char
fn C.calloc(usize, usize) voidptr
fn C.malloc(usize) voidptr
fn C.free(voidptr)
fn C.memcmp(voidptr, voidptr, usize) i32
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.fopen(&char, &char) &C.FILE
fn C.fclose(&C.FILE) i32
fn C.fileno(&C.FILE) i32
fn C.fstat(i32, &C.stat) i32
fn C.S_ISREG(u32) bool
fn C.fread(voidptr, usize, usize, &C.FILE) usize
fn C.mkstemp(&char) i32
fn C.write(i32, voidptr, usize) isize
fn C.fsync(i32) i32
fn C.close(i32) i32
fn C.rename(&char, &char) i32
fn C.unlink(&char) i32
fn C.setjmp(C.n64_frame_escape) i32
fn C.longjmp(C.n64_frame_escape, i32)
fn C.r4300_stop(&C.r4300_core) &i32
fn C.CoreShutdown() i32
fn C.retro_set_environment(fn (u32, voidptr) bool)
fn C.retro_set_video_refresh(fn (&C.n64_const_void, u32, u32, usize))
fn C.retro_set_audio_sample(fn (i16, i16))
fn C.retro_set_audio_sample_batch(fn (&C.n64_const_sample, usize) usize)
fn C.retro_set_input_poll(fn ())
fn C.retro_set_input_state(fn (u32, u32, u32, u32) i16)
fn C.retro_unload_game()
fn C.retro_deinit()
fn C.retro_init()
fn C.retro_load_game(&C.retro_game_info) bool
fn C.retro_get_memory_size(u32) usize
fn C.retro_get_memory_data(u32) voidptr
fn C.retro_set_controller_port_device(u32, u32)
fn C.retro_run()
fn C.vinix_n64_log_message(i32, &char, ...)

struct Core {
mut:
	video fn (&C.n64_const_void, u32, u32, usize)
	audio fn (&C.n64_const_sample, usize, u32)
	error [256]char
	game &char
	save &char
	buttons u32
	audio_rate u32
	initialized bool
	loaded bool
	failed bool
	in_frame bool
	frame_escape C.n64_frame_escape
}

__global active &Core
@[export: 'vinix_n64_cpu_budget'] __global cpu_budget u64
@[export: 'vinix_n64_rsp_budget'] __global rsp_budget u64
@[export: 'vinix_n64_pi_started'] __global pi_started i32
@[export: 'vinix_n64_setup_done'] __global setup_done i32

fn fail(core &Core, message &char) i32 {
	unsafe { if core != nil { C.snprintf(&core.error[0], sizeof(core.error), c'%s', message) } }
	return 0
}

@[export: 'vinix_n64_budget_exhausted']
pub fn budget_exhausted() {
	unsafe {
		if active != nil { active.failed = true; fail(active, c'Emulation exceeded the instruction limit for one frame') }
		C.frame_break = 1
		C.g_rsp_force_halt = 1
		*C.r4300_stop(&C.g_dev.r4300) = 1
		// Synchronous interpreters/renderer retain no stack-owned resources.
		if active != nil && active.in_frame { C.longjmp(active.frame_escape, 1) }
	}
}

// Assembly captures complete native variadic registers; libc borrows the
// cursor synchronously, including floating-point and overflow-stack values.
@[export: 'vinix_n64_log_entry']
pub fn log_entry(level i32, format &char, native_va voidptr) {
	unsafe {
		if active == nil || level < C.RETRO_LOG_ERROR || active.failed { return }
		C.vsnprintf(&active.error[0], sizeof(active.error), format, *(&C.n64_native_va(native_va)))
	}
}

fn option(key &C.n64_const_char) &C.n64_const_char {
	unsafe {
		keys := [&char(c'parallel-n64-cpucore'), c'parallel-n64-gfxplugin', c'parallel-n64-rspplugin',
			c'parallel-n64-angrylion-multithread', c'parallel-n64-angrylion-vioverlay',
			c'parallel-n64-angrylion-overscan', c'parallel-n64-upscaling', c'parallel-n64-64dd-hardware',
			c'parallel-n64-alt-map', c'parallel-n64-OverrideSaveType', c'parallel-n64-pak1',
			c'parallel-n64-pak2', c'parallel-n64-pak3', c'parallel-n64-pak4',
			c'parallel-n64-astick-deadzone', c'parallel-n64-astick-sensitivity']!
		values := [&char(c'pure_interpreter'), c'angrylion', c'cxd4', c'off', c'filtered', c'disabled',
			c'1', c'disabled', c'enabled', c'IGNORE', c'memory', c'none', c'none', c'none', c'0', c'100']!
		for i := usize(0); i < sizeof(keys) / sizeof(keys[0]); i++ {
			if C.strcmp(&char(key), keys[i]) == 0 { return &C.n64_const_char(values[i]) }
		}
		return nil
	}
}

fn environment(command u32, data voidptr) bool {
	unsafe {
		match command {
			u32(C.RETRO_ENVIRONMENT_GET_LOG_INTERFACE) { (&C.retro_log_callback(data)).@log = C.vinix_n64_log_message; return true }
			u32(C.RETRO_ENVIRONMENT_GET_VARIABLE) {
				variable := &C.retro_variable(data)
				variable.value = option(variable.key)
				return variable.value != nil
			}
			u32(C.RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE) { *(&bool(data)) = false; return true }
			u32(C.RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY), u32(C.RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY) { *(&&char(data)) = &char(c'/tmp'); return true }
			u32(C.RETRO_ENVIRONMENT_GET_LANGUAGE) { *(&u32(data)) = C.RETRO_LANGUAGE_ENGLISH; return true }
			u32(C.RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION) { *(&u32(data)) = 0; return true }
			u32(C.RETRO_ENVIRONMENT_GET_INPUT_BITMASKS) { return false }
			u32(C.RETRO_ENVIRONMENT_GET_AUDIO_VIDEO_ENABLE) { *(&i32(data)) = 3; return true }
			u32(C.RETRO_ENVIRONMENT_SET_PIXEL_FORMAT) { return *(&i32(data)) == C.RETRO_PIXEL_FORMAT_XRGB8888 }
			u32(C.RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO) {
				rate := (&C.retro_system_av_info(data)).timing.sample_rate
				if active != nil && rate >= 1000 && rate <= 192000 { active.audio_rate = u32(rate + 0.5) }
				return true
			}
			u32(C.RETRO_ENVIRONMENT_SET_GEOMETRY), u32(C.RETRO_ENVIRONMENT_SET_VARIABLES),
			u32(C.RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS), u32(C.RETRO_ENVIRONMENT_SET_CONTROLLER_INFO),
			u32(C.RETRO_ENVIRONMENT_SET_SUBSYSTEM_INFO), u32(C.RETRO_ENVIRONMENT_SET_SERIALIZATION_QUIRKS) { return true }
			else { return false }
		}
	}
}

fn video_frame(pixels &C.n64_const_void, width u32, height u32, pitch usize) {
	unsafe {
		if active == nil || active.video == nil || pixels == nil || usize(pixels) == usize(C.RETRO_HW_FRAME_BUFFER_VALID) { return }
		if width > 640 || height > 576 || pitch < usize(width) * 4 {
			active.failed = true
			fail(active, c'Emulator produced an unsupported video frame')
			return
		}
		active.video(pixels, width, height, pitch)
	}
}

fn audio_batch(samples &C.n64_const_sample, frames usize) usize {
	unsafe { if active != nil && active.audio != nil && samples != nil { active.audio(samples, frames, active.audio_rate) } }
	return frames
}

fn audio_sample(left i16, right i16) {
	unsafe { mut samples := [left, right]!; audio_batch(&C.n64_const_sample(&samples[0]), 1) }
}
fn poll_input() {}

fn input_state(port u32, device u32, index u32, id u32) i16 {
	unsafe {
		if active == nil || port != 0 { return 0 }
		if device == C.RETRO_DEVICE_ANALOG && index == C.RETRO_DEVICE_INDEX_ANALOG_LEFT {
			negative := if id == C.RETRO_DEVICE_ID_ANALOG_X { u32(16) } else { u32(14) }
			positive := if id == C.RETRO_DEVICE_ID_ANALOG_X { u32(17) } else { u32(15) }
			return i16(((active.buttons >> positive) & 1) * 32767 - ((active.buttons >> negative) & 1) * 32767)
		}
		if device != C.RETRO_DEVICE_JOYPAD || index != 0 { return 0 }
		bits := [i32(0), 1, 12, 3, 4, 5, 6, 7, 9, 8, 10, 11, 2, 13, -1, -1]!
		return if id < 16 && bits[id] >= 0 { i16((active.buttons >> bits[id]) & 1) } else { i16(0) }
	}
}

fn close_content(core &Core) {
	unsafe {
		if core.loaded { C.retro_unload_game() }
		if core.initialized { C.retro_deinit(); C.CoreShutdown() }
		core.loaded = false
		core.initialized = false
		core.buttons = 0
		cpu_budget = 0
		rsp_budget = 0
		pi_started = 0
		setup_done = 0
		C.g_real_stop = 0
	}
}

@[export: 'vinix_n64_create']
pub fn create(video fn (&C.n64_const_void, u32, u32, usize), audio fn (&C.n64_const_sample, usize, u32)) voidptr {
	unsafe {
		if active != nil { return nil }
		core := &Core(C.calloc(1, sizeof(Core)))
		if core == nil { return nil }
		core.video = video
		core.audio = audio
		core.audio_rate = 32040
		active = core
		C.retro_set_environment(environment)
		C.retro_set_video_refresh(video_frame)
		C.retro_set_audio_sample(audio_sample)
		C.retro_set_audio_sample_batch(audio_batch)
		C.retro_set_input_poll(poll_input)
		C.retro_set_input_state(input_state)
		return core
	}
}

fn read_rom(core &Core, path &char, size &usize) &u8 {
	unsafe {
		stream := C.fopen(path, c'rb')
		if stream == nil { fail(core, c'Cannot open N64 cartridge'); return nil }
		mut info := C.stat{}
		if C.fstat(C.fileno(stream), &info) != 0 || !C.S_ISREG(info.st_mode) || info.st_size < 0x1004 ||
			info.st_size > 64 * 1024 * 1024 || info.st_size % 4 != 0 {
			C.fclose(stream); fail(core, c'Cartridge must be a complete 4 KiB–64 MiB N64 ROM'); return nil
		}
		*size = usize(info.st_size)
		rom := &u8(C.malloc(*size))
		if rom == nil { C.fclose(stream); fail(core, c'Not enough memory to load cartridge'); return nil }
		read := C.fread(rom, 1, *size, stream) == *size
		C.fclose(stream)
		if !read { C.free(rom); fail(core, c'Cannot read N64 cartridge'); return nil }
		if C.memcmp(rom, c'\x37\x80\x40\x12', 4) == 0 {
			for i := usize(0); i < *size; i += 2 { byte := rom[i]; rom[i] = rom[i + 1]; rom[i + 1] = byte }
		} else if C.memcmp(rom, c'\x40\x12\x37\x80', 4) == 0 {
			for i := usize(0); i < *size; i += 4 {
				a := rom[i]; b := rom[i + 1]
				rom[i] = rom[i + 3]; rom[i + 1] = rom[i + 2]; rom[i + 2] = b; rom[i + 3] = a
			}
		}
		entry := u32(rom[8]) << 24 | u32(rom[9]) << 16 | u32(rom[10]) << 8 | u32(rom[11])
		if C.memcmp(rom, c'\x80\x37\x12\x40', 4) != 0 || (entry & 3) != 0 ||
			!((entry >= 0x80000000 && entry < 0x80800000) || (entry >= 0xa0000000 && entry < 0xa0800000)) {
			C.free(rom); fail(core, c'Invalid N64 cartridge header or entry address'); return nil
		}
		return rom
	}
}

@[export: 'vinix_n64_save']
pub fn save(handle voidptr) i32 {
	unsafe {
		core := &Core(handle)
		if core == nil || usize(core) != usize(active) { return 0 }
		if !core.loaded || core.save == nil || *core.save == 0 { return 1 }
		size := C.retro_get_memory_size(C.RETRO_MEMORY_SAVE_RAM)
		bytes := C.retro_get_memory_data(C.RETRO_MEMORY_SAVE_RAM)
		if bytes == nil || size == 0 || size > 512 * 1024 { return fail(core, c'Invalid cartridge save memory') }
		length := C.strlen(core.save)
		temporary := &char(C.malloc(length + 16))
		if temporary == nil { return fail(core, c'Not enough memory to save cartridge') }
		C.snprintf(temporary, length + 16, c'%s.tmp.XXXXXX', core.save)
		fd := C.mkstemp(temporary)
		mut ok := fd >= 0
		for offset := usize(0); ok && offset < size; {
			count := C.write(fd, &u8(bytes) + offset, size - offset)
			if count < 0 && C.errno == C.EINTR { continue }
			if count <= 0 { ok = false } else { offset += usize(count) }
		}
		if ok && C.fsync(fd) != 0 { ok = false }
		if fd >= 0 && C.close(fd) != 0 { ok = false }
		if ok && C.rename(temporary, core.save) != 0 { ok = false }
		if !ok { C.unlink(temporary) }
		C.free(temporary)
		return if ok { 1 } else { fail(core, c'Cannot write cartridge save') }
	}
}

@[export: 'vinix_n64_load']
pub fn load(handle voidptr, game_path &C.n64_const_char, save_path &C.n64_const_char) i32 {
	unsafe {
		core := &Core(handle)
		game := &char(game_path)
		if core == nil || usize(core) != usize(active) || game == nil || *game == 0 { return 0 }
		mut size := usize(0)
		rom := read_rom(core, game, &size)
		if rom == nil { return 0 }
		new_game := C.strdup(game)
		new_save := C.strdup(if save_path != nil { &char(save_path) } else { &char(c'') })
		mut save_bytes := &u8(nil)
		save_size := usize(0x800 + 4 * 0x8000 + 0x8000 + 0x20000)
		if new_game == nil || new_save == nil {
			C.free(rom); C.free(new_game); C.free(new_save); return fail(core, c'Not enough memory to load cartridge')
		}
		if *new_save != 0 {
			stream := C.fopen(new_save, c'rb')
			if stream != nil {
				mut info := C.stat{}
				save_bytes = &u8(C.malloc(save_size))
				ok := save_bytes != nil && C.fstat(C.fileno(stream), &info) == 0 && C.S_ISREG(info.st_mode) &&
					info.st_size == i64(save_size) && C.fread(save_bytes, 1, save_size, stream) == save_size
				C.fclose(stream)
				if !ok { C.free(rom); C.free(new_game); C.free(new_save); C.free(save_bytes); return fail(core, c'Invalid or unreadable cartridge save') }
			} else if C.errno != C.ENOENT {
				C.free(rom); C.free(new_game); C.free(new_save); return fail(core, c'Cannot open cartridge save')
			}
		}
		if save(core) == 0 { C.free(rom); C.free(new_game); C.free(new_save); C.free(save_bytes); return 0 }
		if core.loaded && core.save != nil && C.strcmp(core.save, new_save) == 0 {
			if save_bytes == nil { save_bytes = &u8(C.malloc(save_size)) }
			if save_bytes == nil { C.free(rom); C.free(new_game); C.free(new_save); return fail(core, c'Not enough memory to retain cartridge save') }
			C.memcpy(save_bytes, C.retro_get_memory_data(C.RETRO_MEMORY_SAVE_RAM), save_size)
		}
		close_content(core)
		C.free(core.game); C.free(core.save)
		core.game = new_game; core.save = new_save
		core.error[0] = 0
		core.failed = false
		core.audio_rate = 32040
		C.retro_init()
		core.initialized = true
		mut content := C.retro_game_info{path: core.game, data: rom, size: size, meta: nil}
		is_loaded := C.retro_load_game(&content)
		C.free(rom)
		core.loaded = is_loaded
		if !is_loaded { C.free(save_bytes); close_content(core); return fail(core, c'N64 emulator could not initialize the cartridge') }
		if save_bytes != nil { C.memcpy(C.retro_get_memory_data(C.RETRO_MEMORY_SAVE_RAM), save_bytes, save_size) }
		C.free(save_bytes)
		C.retro_set_controller_port_device(0, C.RETRO_DEVICE_JOYPAD)
		for port := u32(1); port < 4; port++ { C.retro_set_controller_port_device(port, C.RETRO_DEVICE_NONE) }
		return 1
	}
}

@[export: 'vinix_n64_frame']
pub fn frame(handle voidptr, buttons u32) i32 {
	unsafe {
		core := &Core(handle)
		if core == nil || usize(core) != usize(active) || !core.loaded || core.failed { return 0 }
		core.buttons = buttons
		cpu_budget = 16000000
		rsp_budget = 16000000
		core.in_frame = true
		if C.setjmp(core.frame_escape) == 0 { C.retro_run() }
		core.in_frame = false
		cpu_budget = 0
		rsp_budget = 0
		return i32(!core.failed)
	}
}

@[export: 'vinix_n64_reset']
pub fn reset(handle voidptr) i32 {
	unsafe {
		core := &Core(handle)
		if core == nil || usize(core) != usize(active) || !core.loaded { return 0 }
		return load(core, &C.n64_const_char(core.game), &C.n64_const_char(core.save))
	}
}

@[export: 'vinix_n64_error']
pub fn error_text(handle voidptr) &C.n64_const_char {
	unsafe {
		core := &Core(handle)
		return if core != nil && usize(core) == usize(active) { &C.n64_const_char(&core.error[0]) } else { &C.n64_const_char(c'N64 emulator is unavailable') }
	}
}

@[export: 'vinix_n64_loaded']
pub fn loaded(handle voidptr) i32 {
	unsafe { core := &Core(handle); return i32(core != nil && usize(core) == usize(active) && core.loaded) }
}

@[export: 'vinix_n64_destroy']
pub fn destroy(handle voidptr) {
	unsafe {
		core := &Core(handle)
		if core == nil || usize(core) != usize(active) { return }
		save(core)
		close_content(core)
		C.free(core.game); C.free(core.save)
		active = nil
		C.free(core)
	}
}
