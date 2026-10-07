/* SPDX-License-Identifier: MIT */
#define _POSIX_C_SOURCE 200809L
#include "bridge.h"
#include "budget.h"
#include <libretro.h>
#include <m64p_frontend.h>
#include <m64p_types.h>
#include "device/device.h"
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <setjmp.h>
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

/* libretro and its device models have process-global state: exactly one owner. */
struct n64_core {
    vinix_n64_video_cb video;
    vinix_n64_audio_cb audio;
    char error[256];
    char *game;
    char *save;
    uint32_t buttons;
    unsigned audio_rate;
    bool initialized, loaded, failed;
    bool in_frame;
    jmp_buf frame_escape;
};
static struct n64_core *active;
uint64_t vinix_n64_cpu_budget, vinix_n64_rsp_budget;
int vinix_n64_pi_started, vinix_n64_setup_done;
extern int frame_break;
extern int g_rsp_force_halt;
extern int g_real_stop;
extern struct device g_dev;

static int fail(struct n64_core *core, const char *message)
{
    if (core) snprintf(core->error, sizeof(core->error), "%s", message);
    return 0;
}

void vinix_n64_budget_exhausted(void)
{
    if (active) {
        active->failed = true;
        fail(active, "Emulation exceeded the instruction limit for one frame");
    }
    frame_break = 1;
    g_rsp_force_halt = 1;
    *r4300_stop(&g_dev.r4300) = 1;
    /* The C interpreters and synchronous C renderer hold no stack-owned
     * resources. Escape a stalled machine even when guest exception handling
     * prevents upstream's normal frame-yield flags from unwinding the loop. */
    if (active && active->in_frame) longjmp(active->frame_escape, 1);
}

static void log_message(enum retro_log_level level, const char *format, ...)
{
    if (!active || level < RETRO_LOG_ERROR || active->failed) return;
    va_list arguments;
    va_start(arguments, format);
    vsnprintf(active->error, sizeof(active->error), format, arguments);
    va_end(arguments);
}

static const char *option(const char *key)
{
    static const struct { const char *key, *value; } values[] = {
        {"parallel-n64-cpucore", "pure_interpreter"},
        {"parallel-n64-gfxplugin", "angrylion"},
        {"parallel-n64-rspplugin", "cxd4"},
        {"parallel-n64-angrylion-multithread", "off"},
        {"parallel-n64-angrylion-vioverlay", "filtered"},
        {"parallel-n64-angrylion-overscan", "disabled"},
        {"parallel-n64-upscaling", "1"},
        {"parallel-n64-64dd-hardware", "disabled"},
        {"parallel-n64-alt-map", "enabled"},
        {"parallel-n64-OverrideSaveType", "IGNORE"},
        {"parallel-n64-pak1", "memory"},
        {"parallel-n64-pak2", "none"},
        {"parallel-n64-pak3", "none"},
        {"parallel-n64-pak4", "none"},
        {"parallel-n64-astick-deadzone", "0"},
        {"parallel-n64-astick-sensitivity", "100"},
    };
    for (size_t i = 0; i < sizeof(values) / sizeof(values[0]); ++i)
        if (!strcmp(key, values[i].key)) return values[i].value;
    return NULL;
}

static bool environment(unsigned command, void *data)
{
    switch (command) {
    case RETRO_ENVIRONMENT_GET_LOG_INTERFACE:
        ((struct retro_log_callback *)data)->log = log_message; return true;
    case RETRO_ENVIRONMENT_GET_VARIABLE: {
        struct retro_variable *variable = data;
        variable->value = option(variable->key); return variable->value != NULL;
    }
    case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE: *(bool *)data = false; return true;
    case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY:
    case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY: *(const char **)data = "/tmp"; return true;
    case RETRO_ENVIRONMENT_GET_LANGUAGE: *(unsigned *)data = RETRO_LANGUAGE_ENGLISH; return true;
    case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION: *(unsigned *)data = 0; return true;
    case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS: return false;
    case RETRO_ENVIRONMENT_GET_AUDIO_VIDEO_ENABLE: *(int *)data = 3; return true;
    case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT:
        return *(enum retro_pixel_format *)data == RETRO_PIXEL_FORMAT_XRGB8888;
    case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO: {
        double rate = ((const struct retro_system_av_info *)data)->timing.sample_rate;
        if (active && rate >= 1000 && rate <= 192000) active->audio_rate = (unsigned)(rate + 0.5);
        return true;
    }
    case RETRO_ENVIRONMENT_SET_GEOMETRY:
    case RETRO_ENVIRONMENT_SET_VARIABLES:
    case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS:
    case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO:
    case RETRO_ENVIRONMENT_SET_SUBSYSTEM_INFO:
    case RETRO_ENVIRONMENT_SET_SERIALIZATION_QUIRKS: return true;
    default: return false;
    }
}

static void video_frame(const void *pixels, unsigned width, unsigned height, size_t pitch)
{
    if (!active || !active->video || !pixels || pixels == RETRO_HW_FRAME_BUFFER_VALID) return;
    if (width > 640 || height > 576 || pitch < (size_t)width * 4) {
        active->failed = true;
        fail(active, "Emulator produced an unsupported video frame");
        return;
    }
    active->video(pixels, width, height, pitch);
}
static size_t audio_batch(const int16_t *samples, size_t frames)
{
    if (active && active->audio && samples)
        active->audio(samples, frames, active->audio_rate);
    return frames;
}
static void audio_sample(int16_t left, int16_t right)
{
    int16_t samples[2] = {left, right};
    audio_batch(samples, 1);
}
static void poll_input(void) {}
static int16_t input_state(unsigned port, unsigned device, unsigned index, unsigned id)
{
    if (!active || port != 0) return 0;
    if (device == RETRO_DEVICE_ANALOG && index == RETRO_DEVICE_INDEX_ANALOG_LEFT) {
        unsigned negative = id == RETRO_DEVICE_ID_ANALOG_X ? 16 : 14;
        unsigned positive = id == RETRO_DEVICE_ID_ANALOG_X ? 17 : 15;
        return ((active->buttons >> positive) & 1) * 32767
             - ((active->buttons >> negative) & 1) * 32767;
    }
    if (device != RETRO_DEVICE_JOYPAD || index != 0) return 0;
    /* Independent C-buttons map: N64 A/B occupy libretro B/Y. */
    static const int bits[16] = {0, 1, 12, 3, 4, 5, 6, 7, 9, 8, 10, 11, 2, 13, -1, -1};
    return id < 16 && bits[id] >= 0 ? (active->buttons >> bits[id]) & 1 : 0;
}

static void close_content(struct n64_core *core)
{
    if (core->loaded) retro_unload_game();
    if (core->initialized) {
        retro_deinit();
        CoreShutdown();
    }
    core->loaded = core->initialized = false;
    core->buttons = 0;
    vinix_n64_cpu_budget = vinix_n64_rsp_budget = 0;
    vinix_n64_pi_started = vinix_n64_setup_done = 0;
    g_real_stop = 0;
}

void *vinix_n64_create(vinix_n64_video_cb video, vinix_n64_audio_cb audio)
{
    if (active) return NULL;
    struct n64_core *core = calloc(1, sizeof(*core));
    if (!core) return NULL;
    core->video = video;
    core->audio = audio;
    core->audio_rate = 32040;
    active = core;
    retro_set_environment(environment);
    retro_set_video_refresh(video_frame);
    retro_set_audio_sample(audio_sample);
    retro_set_audio_sample_batch(audio_batch);
    retro_set_input_poll(poll_input);
    retro_set_input_state(input_state);
    return core;
}

/* Validate and normalize all three cartridge byte orders before replacing a game. */
static unsigned char *read_rom(struct n64_core *core, const char *path, size_t *size)
{
    FILE *stream = fopen(path, "rb");
    if (!stream) { fail(core, "Cannot open N64 cartridge"); return NULL; }
    struct stat info;
    if (fstat(fileno(stream), &info) || !S_ISREG(info.st_mode)
        || info.st_size < 0x1004 || info.st_size > 64 * 1024 * 1024 || info.st_size % 4) {
        fclose(stream); fail(core, "Cartridge must be a complete 4 KiB–64 MiB N64 ROM"); return NULL;
    }
    *size = (size_t)info.st_size;
    unsigned char *rom = malloc(*size);
    if (!rom) { fclose(stream); fail(core, "Not enough memory to load cartridge"); return NULL; }
    bool read = fread(rom, 1, *size, stream) == *size;
    fclose(stream);
    if (!read) { free(rom); fail(core, "Cannot read N64 cartridge"); return NULL; }
    if (!memcmp(rom, "\x37\x80\x40\x12", 4)) {
        for (size_t i = 0; i < *size; i += 2) {
            unsigned char byte = rom[i]; rom[i] = rom[i + 1]; rom[i + 1] = byte;
        }
    } else if (!memcmp(rom, "\x40\x12\x37\x80", 4)) {
        for (size_t i = 0; i < *size; i += 4) {
            unsigned char a = rom[i], b = rom[i + 1];
            rom[i] = rom[i + 3]; rom[i + 1] = rom[i + 2]; rom[i + 2] = b; rom[i + 3] = a;
        }
    }
    uint32_t entry = (uint32_t)rom[8] << 24 | (uint32_t)rom[9] << 16 | (uint32_t)rom[10] << 8 | rom[11];
    if (memcmp(rom, "\x80\x37\x12\x40", 4) || (entry & 3)
        || !((entry >= 0x80000000 && entry < 0x80800000)
             || (entry >= 0xa0000000 && entry < 0xa0800000))) {
        free(rom); fail(core, "Invalid N64 cartridge header or entry address"); return NULL;
    }
    return rom;
}

int vinix_n64_save(void *handle)
{
    struct n64_core *core = handle;
    if (!core || core != active) return 0;
    if (!core->loaded || !core->save || !*core->save) return 1;
    size_t size = retro_get_memory_size(RETRO_MEMORY_SAVE_RAM);
    const void *bytes = retro_get_memory_data(RETRO_MEMORY_SAVE_RAM);
    if (!bytes || !size || size > 512 * 1024) return fail(core, "Invalid cartridge save memory");
    size_t length = strlen(core->save);
    char *temporary = malloc(length + 16);
    if (!temporary) return fail(core, "Not enough memory to save cartridge");
    snprintf(temporary, length + 16, "%s.tmp.XXXXXX", core->save);
    int fd = mkstemp(temporary);
    bool ok = fd >= 0;
    for (size_t offset = 0; ok && offset < size;) {
        ssize_t count = write(fd, (const unsigned char *)bytes + offset, size - offset);
        if (count < 0 && errno == EINTR) continue;
        if (count <= 0) ok = false;
        else offset += (size_t)count;
    }
    if (ok && fsync(fd)) ok = false;
    if (fd >= 0 && close(fd)) ok = false;
    if (ok && rename(temporary, core->save)) ok = false;
    if (!ok) unlink(temporary);
    free(temporary);
    return ok ? 1 : fail(core, "Cannot write cartridge save");
}

int vinix_n64_load(void *handle, const char *game, const char *save)
{
    struct n64_core *core = handle;
    if (!core || core != active || !game || !*game) return 0;
    size_t size;
    unsigned char *rom = read_rom(core, game, &size);
    if (!rom) return 0;
    char *new_game = strdup(game), *new_save = strdup(save ? save : "");
    unsigned char *save_bytes = NULL;
    /* Cartridge-only libretro layout: EEPROM, four controller paks, SRAM, Flash. */
    const size_t save_size = 0x800 + 4 * 0x8000 + 0x8000 + 0x20000;
    if (!new_game || !new_save) {
        free(rom); free(new_game); free(new_save); return fail(core, "Not enough memory to load cartridge");
    }
    if (*new_save) {
        FILE *stream = fopen(new_save, "rb");
        if (stream) {
            struct stat info;
            save_bytes = malloc(save_size);
            bool ok = save_bytes && !fstat(fileno(stream), &info) && S_ISREG(info.st_mode)
                && info.st_size == (off_t)save_size && fread(save_bytes, 1, save_size, stream) == save_size;
            fclose(stream);
            if (!ok) {
                free(rom); free(new_game); free(new_save); free(save_bytes);
                return fail(core, "Invalid or unreadable cartridge save");
            }
        } else if (errno != ENOENT) {
            free(rom); free(new_game); free(new_save); return fail(core, "Cannot open cartridge save");
        }
    }
    if (!vinix_n64_save(core)) {
        free(rom); free(new_game); free(new_save); free(save_bytes); return 0;
    }
    if (core->loaded && core->save && !strcmp(core->save, new_save)) {
        /* Reset and reopening the same save retain the latest live memory. */
        if (!save_bytes) save_bytes = malloc(save_size);
        if (!save_bytes) {
            free(rom); free(new_game); free(new_save);
            return fail(core, "Not enough memory to retain cartridge save");
        }
        memcpy(save_bytes, retro_get_memory_data(RETRO_MEMORY_SAVE_RAM), save_size);
    }
    close_content(core);
    free(core->game); free(core->save);
    core->game = new_game; core->save = new_save;
    core->error[0] = 0;
    core->failed = false;
    core->audio_rate = 32040;
    retro_init();
    core->initialized = true;
    struct retro_game_info content = {core->game, rom, size, NULL};
    bool loaded = retro_load_game(&content);
    free(rom);
    core->loaded = loaded;
    if (!loaded) {
        free(save_bytes); close_content(core);
        return fail(core, "N64 emulator could not initialize the cartridge");
    }
    if (save_bytes) memcpy(retro_get_memory_data(RETRO_MEMORY_SAVE_RAM), save_bytes, save_size);
    free(save_bytes);
    retro_set_controller_port_device(0, RETRO_DEVICE_JOYPAD);
    for (unsigned port = 1; port < 4; ++port) retro_set_controller_port_device(port, RETRO_DEVICE_NONE);
    return 1;
}

int vinix_n64_frame(void *handle, uint32_t buttons)
{
    struct n64_core *core = handle;
    if (!core || core != active || !core->loaded || core->failed) return 0;
    core->buttons = buttons;
    vinix_n64_cpu_budget = 16000000;
    vinix_n64_rsp_budget = 16000000;
    core->in_frame = true;
    if (!setjmp(core->frame_escape)) retro_run();
    core->in_frame = false;
    vinix_n64_cpu_budget = vinix_n64_rsp_budget = 0;
    return !core->failed;
}

int vinix_n64_reset(void *handle)
{
    struct n64_core *core = handle;
    if (!core || core != active || !core->loaded) return 0;
    /* Recreate a power-on machine between frames, retaining cartridge saves. */
    return vinix_n64_load(core, core->game, core->save);
}

const char *vinix_n64_error(void *handle)
{
    struct n64_core *core = handle;
    return core && core == active ? core->error : "N64 emulator is unavailable";
}

int vinix_n64_loaded(void *handle)
{
    struct n64_core *core = handle;
    return core && core == active && core->loaded;
}

void vinix_n64_destroy(void *handle)
{
    struct n64_core *core = handle;
    if (!core || core != active) return;
    vinix_n64_save(core);
    close_content(core);
    free(core->game); free(core->save);
    active = NULL;
    free(core);
}
