/* SPDX-License-Identifier: MIT
 * C ABI adapter to Iris's PS2 hardware and software GS. Compiled as C++20.
 */
#include "bridge.h"
#include <algorithm>
#include <cerrno>
#include <cstdio>
#include <cstring>
#include <exception>
#include <memory>
#include <stdexcept>
#include <string>
#include <vector>
#include <sys/stat.h>
#include <unistd.h>
#include "ps2.h"
#include "ee/ee_def.hpp"
#include "elf.h"
#include "gs/renderer/software.hpp"
#include "vbridge/native-abi.h"
extern "C" void vinix_ps2_ioman_destroy(struct iop_state *);

namespace {
constexpr unsigned CARD_BYTES = 0x4000 * (512 + 16);
constexpr unsigned MAX_FRAME_BLOCKS = 1000000;
struct core_exit : std::exception {
    const char *what() const noexcept override { return "The PS2 core encountered unsupported hardware or an instruction"; }
};

struct machine {
    ps2_state *ps2 = nullptr;
    software_state *software = nullptr;
    ds_state *pad = nullptr;
    mcd_state *card = nullptr;
    std::string working_card;
    unsigned vblanks = 0;
    ~machine() {
        // GS callbacks point at software until the hardware is destroyed.
        if (ps2) {
            vinix_ps2_ioman_destroy(ps2->iop);
            ps2_destroy(ps2);
        }
        delete software;
        if (!working_card.empty()) unlink(working_card.c_str());
    }
};

struct frontend {
    std::unique_ptr<machine> running;
    vinix_ps2_video_cb video;
    vinix_ps2_audio_cb audio;
    std::string game, bios, card;
    std::string error;
    std::vector<uint32_t> pixels;
};

void blank(void *userdata) { ++static_cast<machine *>(userdata)->vblanks; }
void tty(void *, char) { /* The BIOS's terminal output is optional. */ }

void primitive(ps2_gs *gs, void *userdata, void (*render)(ps2_gs *, void *)) {
    // The retained single-thread software rasterizer expects integer screen
    // coordinates. The GS supplies XYZ and XYOFFSET in 12.4 fixed point.
    // Convert at its boundary, as Iris's threaded rasterizer does, preserving
    // the original hardware state and texture coordinates after the call.
    struct restore {
        ps2_gs *gs;
        gs_context *context;
        int x[4], y[4];
        unsigned ox, oy;
        explicit restore(ps2_gs *g) : gs(g), context(g->ctx), ox(g->ctx->ofx), oy(g->ctx->ofy) {
            for (unsigned i = 0; i < 4; ++i) {
                x[i] = gs->vq[i].x; y[i] = gs->vq[i].y;
                gs->vq[i].x = (x[i] - int(ox)) >> 4;
                gs->vq[i].y = (y[i] - int(oy)) >> 4;
            }
            context->ofx = context->ofy = 0;
        }
        ~restore() {
            for (unsigned i = 0; i < 4; ++i) { gs->vq[i].x = x[i]; gs->vq[i].y = y[i]; }
            context->ofx = ox; context->ofy = oy;
        }
    } coordinates(gs);
    render(gs, userdata);
}
void point(ps2_gs *gs, void *userdata) { primitive(gs, userdata, software_render_point); }
void line(ps2_gs *gs, void *userdata) { primitive(gs, userdata, software_render_line); }
void triangle(ps2_gs *gs, void *userdata) { primitive(gs, userdata, software_render_triangle); }
void sprite(ps2_gs *gs, void *userdata) { primitive(gs, userdata, software_render_sprite); }

bool file_size(FILE *file, size_t &size) { return vinix_ps2_file_size(file, &size) != 0; }

std::vector<unsigned char> read_file(const char *path, size_t maximum) {
    FILE *file = fopen(path, "rb");
    if (!file) throw std::runtime_error(std::string("Cannot open file: ") + path);
    size_t size;
    if (!file_size(file, size) || size > maximum) {
        fclose(file);
        throw std::runtime_error("File is too large or unreadable");
    }
    std::vector<unsigned char> bytes(size);
    bool ok = !size || fread(bytes.data(), 1, size, file) == size;
    fclose(file);
    if (!ok) throw std::runtime_error("Cannot read complete file");
    return bytes;
}

void check_elf(const std::vector<unsigned char> &bytes, Elf32_Ehdr &header) {
    vinix_ps2_check_elf(bytes.data(), bytes.size(), &header);
}

void load_baremetal(machine &m, const std::vector<unsigned char> &bytes, const Elf32_Ehdr &header) {
    vinix_ps2_load_baremetal(m.ps2, bytes.data(), &header);
}

void tick(machine &m) { vinix_ps2_tick(m.ps2); }

void boot_bios(machine &m, const std::string &path) {
    vinix_ps2_boot_bios(m.ps2, path.c_str(), path.size());
}

void attach_card(machine &m, const std::string &path) {
    if (path.empty()) return;
    std::vector<unsigned char> bytes;
    struct stat st;
    if (!stat(path.c_str(), &st)) bytes = read_file(path.c_str(), CARD_BYTES);
    else if (errno == ENOENT) bytes.assign(CARD_BYTES, 0xff);
    else throw std::runtime_error("Cannot inspect memory card path");
    if (bytes.size() != CARD_BYTES) throw std::runtime_error("Memory card must be an 8 MiB PS2 card with ECC");
    m.working_card = path + ".working-XXXXXX";
    std::vector<char> temporary(m.working_card.begin(), m.working_card.end());
    temporary.push_back(0);
    int descriptor = mkstemp(temporary.data());
    if (descriptor < 0) throw std::runtime_error("Cannot create memory card working file");
    m.working_card = temporary.data();
    FILE *file = fdopen(descriptor, "wb");
    if (!file) { close(descriptor); throw std::runtime_error("Cannot open memory card working file"); }
    bool ok = fwrite(bytes.data(), 1, bytes.size(), file) == bytes.size();
    if (fclose(file)) ok = false;
    if (!ok) throw std::runtime_error("Cannot initialize memory card working file");
    m.card = mcd_sio2_attach(m.ps2->sio2, 2, m.working_card.c_str());
    if (!m.card) throw std::runtime_error("Cannot attach PS2 memory card");
}

bool save_card(frontend &f) {
    if (!f.running || !f.running->card) return true;
    auto *card = f.running->card;
    std::string name = f.card + ".save-XXXXXX";
    std::vector<char> temporary(name.begin(), name.end());
    temporary.push_back(0);
    int descriptor = mkstemp(temporary.data());
    if (descriptor < 0) { f.error = "Cannot create memory card save file"; return false; }
    FILE *file = fdopen(descriptor, "wb");
    if (!file) { close(descriptor); unlink(temporary.data()); f.error = "Cannot open memory card save file"; return false; }
    bool ok = fwrite(card->buf, 1, card->buf_size, file) == card->buf_size;
    if (fflush(file)) ok = false;
    // Vinix and host musl support fsync; persist the file before replacement.
    if (fsync(descriptor)) ok = false;
    if (fclose(file)) ok = false;
    if (ok && rename(temporary.data(), f.card.c_str())) ok = false;
    unlink(temporary.data());
    if (!ok) f.error = "Cannot save PS2 memory card";
    return ok;
}

void display(frontend &f) {
    auto *gs = f.running->ps2->gs;
    uint64_t display = (gs->pmode & 1) ? gs->display1 : gs->display2;
    uint64_t fb = (gs->pmode & 1) ? gs->dispfb1 : gs->dispfb2;
    unsigned width = unsigned((display >> 32) & 0xfff) / (unsigned((display >> 23) & 15) + 1) + 1;
    unsigned height = unsigned((display >> 44) & 0x7ff) / (unsigned((display >> 27) & 3) + 1) + 1;
    if ((gs->smode2 & 3) == 3) height /= 2;
    if (!(gs->pmode & 3) || width < 2 || !height || width > 1024 || height > 1024) return;
    unsigned stride = unsigned((fb >> 9) & 63) * 64;
    unsigned base = unsigned(fb & 511) << 11;
    unsigned format = unsigned((fb >> 15) & 31);
    unsigned start_x = unsigned((fb >> 32) & 0x7ff), start_y = unsigned((fb >> 43) & 0x7ff);
    if (!stride || width > stride) return;
    f.pixels.resize(size_t(width) * height);
    for (unsigned y = 0; y < height; ++y) {
        for (unsigned x = 0; x < width; ++x) {
            unsigned offset = start_x + x + (start_y + y) * stride;
            uint32_t color;
            if (format == GS_PSMCT16 || format == GS_PSMCT16S) {
                unsigned index = base * 2 + offset;
                uint16_t pixel = reinterpret_cast<uint16_t *>(gs->vram)[index & 0x1fffff];
                color = ((pixel & 31) << 3) | (((pixel >> 5) & 31) << 11) | (((pixel >> 10) & 31) << 19);
            } else if (format == GS_PSMCT32 || format == GS_PSMCT24) {
                color = gs->vram[(base + offset) & 0xfffff];
            } else return;
            // Iris's GS RAM uses ABGR; the compositor's framebuffer is XRGB.
            f.pixels[size_t(y) * width + x] = ((color & 255) << 16) | (color & 0xff00) | ((color >> 16) & 255);
        }
    }
    if (f.video) f.video(f.pixels.data(), width, height, size_t(width) * 4);
}

} // namespace

extern "C" [[noreturn]] void vinix_ps2_core_exit(int) { throw core_exit(); }
extern "C" [[noreturn]] void vinix_ps2_core_assert(const char *expression, const char *, int, const char *) {
    throw std::runtime_error(std::string("The PS2 core encountered unsupported hardware: ") + expression);
}

extern "C" void ps2_spu2_init(ps2_spu2 *spu2, ps2_iop_dma *dma, ps2_iop_intc *intc, sched_state *sched) {
    // Equivalent Iris hardware initialization, without its global adma.wav
    // capture. With simultaneous candidate/old machines, old destruction
    // otherwise closes the candidate's FILE and later teardown uses it again.
    memset(spu2, 0, sizeof(*spu2));
    spu2->dma = dma;
    spu2->intc = intc;
    spu2->sched = sched;
    spu2->c[0].stat = spu2->c[1].stat = 0x80;
    spu2->c[0].endx = spu2->c[1].endx = 0x00ffffff;
}

extern "C" void ps2_spu2_destroy(ps2_spu2 *spu2) { free(spu2); }

extern "C" void *vinix_ps2_create(vinix_ps2_video_cb video, vinix_ps2_audio_cb audio) {
    try {
        auto *f = new frontend;
        f->video = video;
        f->audio = audio;
        return f;
    } catch (...) { return nullptr; }
}

extern "C" int vinix_ps2_load(void *core, const char *game, const char *bios, const char *card) {
    if (!core) return 0;
    auto &f = *static_cast<frontend *>(core);
    try {
        if (!game || !*game) throw std::runtime_error("Choose a PS2 ELF or ISO/BIN game");
        FILE *file = fopen(game, "rb");
        if (!file) throw std::runtime_error("Cannot open PS2 game");
        unsigned char magic[8] = {};
        size_t size = fread(magic, 1, sizeof magic, file);
        fclose(file);
        bool elf = size >= 4 && !memcmp(magic, "\x7f" "ELF", 4);
        bool baremetal = elf && size >= 8 && magic[7] == 0x56;
        std::vector<unsigned char> bytes;
        Elf32_Ehdr header = {};
        std::string name = game;
        bool elf_extension = name.size() >= 4 && name.substr(name.size() - 4) == ".elf";
        if (elf || elf_extension) { bytes = read_file(game, 64 * 1024 * 1024); check_elf(bytes, header); elf = true; }
        std::vector<unsigned char> firmware;
        if (!baremetal) {
            if (!bios || !*bios) throw std::runtime_error("A dumped PS2 BIOS is required for this game");
            try { firmware = read_file(bios, 4 * 1024 * 1024); }
            catch (const std::exception &) { throw std::runtime_error("Cannot open PS2 BIOS dump (a 4 MiB ROM is required)"); }
            if (firmware.size() != 4 * 1024 * 1024) throw std::runtime_error("PS2 BIOS must be a 4 MiB ROM dump");
        }
        auto candidate = std::make_unique<machine>();
        candidate->ps2 = ps2_create();
        if (!candidate->ps2) throw std::bad_alloc();
        ps2_init(candidate->ps2);
        ps2_init_kputchar(candidate->ps2, tty, nullptr, tty, nullptr);
        ps2_set_timescale(candidate->ps2, 8); // Same default as Iris's frontend.
        candidate->software = new software_state{};
        software_init(candidate->software, candidate->ps2->gs, nullptr, nullptr);
        auto &backend = candidate->ps2->gs->backend;
        backend.render_point = point;
        backend.render_line = line;
        backend.render_triangle = triangle;
        backend.render_sprite = sprite;
        backend.transfer_start = software_transfer_start;
        backend.transfer_write = software_transfer_write;
        backend.transfer_read = software_transfer_read;
        backend.udata = candidate->software;
        candidate->pad = ds_sio2_attach(candidate->ps2->sio2, 0);
        attach_card(*candidate, card ? card : "");
        if (candidate->card && f.running && f.running->card && card && f.card == card)
            memcpy(candidate->card->buf, f.running->card->buf, candidate->card->buf_size);
        std::string boot;
        if (!elf) {
            if (ps2_cdvd_open(candidate->ps2->cdvd, game, 0)) throw std::runtime_error("Unsupported or unreadable PS2 disc (use ISO or BIN)");
            const char *path = disc_get_boot_path(candidate->ps2->cdvd->disc);
            if (!path || !*path) throw std::runtime_error("PS2 disc has no BOOT2 entry in SYSTEM.CNF");
            boot = path;
        }
        if (baremetal) load_baremetal(*candidate, bytes, header);
        else {
            memcpy(candidate->ps2->bios->buf, firmware.data(), firmware.size());
            ee_bus_init_fastmem(candidate->ps2->ee_bus);
            iop_bus_init_fastmem(candidate->ps2->iop_bus);
            if (elf) boot = std::string("host:  ") + game;
            boot_bios(*candidate, boot);
        }
        ps2_gs_init_callback(candidate->ps2->gs, GS_EVENT_VBLANK, blank, candidate.get());
        // A failed replacement keeps the old machine and its memory card live.
        if (!save_card(f)) throw std::runtime_error(f.error);
        f.running.swap(candidate);
        f.game = game;
        f.bios = bios ? bios : "";
        f.card = card ? card : "";
        f.error.clear();
        return 1;
    } catch (const std::exception &error) { f.error = error.what(); return 0; }
}

extern "C" int vinix_ps2_frame(void *core, uint32_t buttons) {
    if (!core) return 0;
    auto &f = *static_cast<frontend *>(core);
    if (!f.running) { f.error = "No PS2 game loaded"; return 0; }
    try {
        const uint16_t mapping[16] = {DS_BT_CROSS, DS_BT_SQUARE, DS_BT_SELECT, DS_BT_START,
            DS_BT_UP, DS_BT_DOWN, DS_BT_LEFT, DS_BT_RIGHT, DS_BT_CIRCLE, DS_BT_TRIANGLE,
            DS_BT_L1, DS_BT_R1, DS_BT_L2, DS_BT_R2, DS_BT_L3, DS_BT_R3};
        uint16_t pressed = 0;
        for (unsigned i = 0; i < 16; ++i) if (buttons & (1u << i)) pressed |= mapping[i];
        ds_button_release(f.running->pad, 0xffff);
        ds_button_press(f.running->pad, pressed);
        unsigned old = f.running->vblanks;
        unsigned blocks = 0;
        while (f.running->vblanks == old && blocks++ < MAX_FRAME_BLOCKS) tick(*f.running);
        if (f.running->vblanks == old) throw std::runtime_error("PS2 did not produce VBlank within the frame cycle limit");
        display(f);
        if (f.audio) {
            int16_t samples[800 * 2];
            for (unsigned i = 0; i < 800; ++i) {
                spu2_sample sample = ps2_spu2_get_sample(f.running->ps2->spu2);
                samples[i * 2] = sample.s16[0]; samples[i * 2 + 1] = sample.s16[1];
            }
            f.audio(samples, 800);
        }
        f.error.clear();
        return 1;
    } catch (const std::exception &error) { f.error = error.what(); return 0; }
}

extern "C" int vinix_ps2_reset(void *core) {
    if (!core) return 0;
    auto &f = *static_cast<frontend *>(core);
    if (!f.running) { f.error = "No PS2 game loaded"; return 0; }
    if (!save_card(f)) return 0;
    // Copy paths: load replaces their storage only after the candidate boots.
    std::string game = f.game, bios = f.bios, card = f.card;
    return vinix_ps2_load(core, game.c_str(), bios.c_str(), card.c_str());
}

extern "C" int vinix_ps2_save(void *core) {
    return core && save_card(*static_cast<frontend *>(core));
}

extern "C" const char *vinix_ps2_error(void *core) {
    return core ? static_cast<frontend *>(core)->error.c_str() : "Cannot allocate PS2 frontend";
}

extern "C" void vinix_ps2_destroy(void *core) {
    if (!core) return;
    save_card(*static_cast<frontend *>(core));
    delete static_cast<frontend *>(core);
}
