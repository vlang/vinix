// SPDX-License-Identifier: GPL-2.0-or-later
// Independent public ABI declarations; run unchanged against the installed
// Mac AudioToolbox and the ARM64 iOS Mach-O runner.
typedef unsigned U32;
typedef int Status;
typedef void *Converter;
typedef struct {
    double rate;
    U32 id, flags, packet_bytes, packet_frames, frame_bytes, channels, bits, reserved;
} Format;
typedef struct { U32 channels, bytes; void *data; } Buffer;
typedef struct { U32 count; Buffer buffers[2]; } Buffers;
typedef Status (*Input)(Converter, U32 *, Buffers *, void *, void *);
extern Status AudioConverterNew(const Format *, const Format *, Converter *);
extern Status AudioConverterDispose(Converter), AudioConverterReset(Converter);
extern Status AudioConverterConvertComplexBuffer(Converter, U32, const Buffers *, Buffers *);
extern Status AudioConverterFillComplexBuffer(Converter, Input, void *, U32 *, Buffers *, void *);
extern int puts(const char *), printf(const char *, ...);
#define CHECK(x) do { if (!(x)) { printf("IOS-AUDIO-CONVERTER FAIL line %d: %s\n", __LINE__, #x); return 1; } } while (0)

static const short samples[] = {-32768,16384, -16384,8192, 0,0, 16384,-8192, 32767,-16384, 8192,-32768};
typedef struct { unsigned position, calls; int error; } Source;
static Status supply(Converter converter, U32 *count, Buffers *data, void *descriptions, void *user) {
    (void)converter; (void)descriptions;
    Source *source = user;
    ++source->calls;
    if (source->error && source->position == 2) { *count = 0; source->error = 0; return -12345; }
    U32 remaining = 6 - source->position;
    if (*count > remaining) *count = remaining;
    if (*count > 2) *count = 2;
    data->count = 1;
    data->buffers[0] = (Buffer){2, *count * 4, (void *)(samples + source->position * 2)};
    source->position += *count;
    return 0;
}

int main(int argc, char **argv) {
    (void)argv;
    Format integer = {48000,0x6c70636d,12,4,1,4,2,16,0};
    Format planar = {48000,0x6c70636d,41,4,1,4,2,32,0};
    Format wide = {48000,0x6c70636d,9,16,1,16,2,64,0};
    Converter converter = 0;
    if (argc > 1) {
        Format unsupported = planar;
        unsupported.rate = 44100;
        CHECK(AudioConverterNew(&integer, &unsupported, &converter) == 0x666d743f && !converter);
        unsupported = integer; unsupported.id = 0x61616320;
        CHECK(AudioConverterNew(&unsupported, &planar, &converter) == 0x666d743f && !converter);
        unsupported = integer; unsupported.channels = 99;
        CHECK(AudioConverterNew(&unsupported, &planar, &converter) == 0x666d743f && !converter);
        CHECK(AudioConverterDispose((Converter)123) != 0); // safe invalid handle, no dereference
        puts("IOS-AUDIO-CONVERTER: unsupported codecs/rates and invalid handles rejected");
        return 0;
    }
    CHECK(AudioConverterNew(&integer, &planar, &converter) == 0 && converter);
    float left[8], right[8];
    for (unsigned i = 0; i < 8; ++i) left[i] = right[i] = 42;
    Buffers input = {1, {{2,sizeof(samples),(void *)samples}}};
    Buffers output = {2, {{1,24,left},{1,24,right}}};
    CHECK(AudioConverterConvertComplexBuffer(converter, 6, &input, &output) == 0);
    CHECK(output.buffers[0].bytes == 24 && output.buffers[1].bytes == 24);
    for (unsigned i = 0; i < 6; ++i) {
        CHECK(left[i] == samples[2*i] / 32768.0f && right[i] == samples[2*i+1] / 32768.0f);
    }
    CHECK(left[6] == 42 && right[6] == 42);
    CHECK(AudioConverterReset(converter) == 0);
    Source source = {0,0,1};
    U32 packets = 6;
    output.buffers[0].bytes = output.buffers[1].bytes = 24;
    CHECK(AudioConverterFillComplexBuffer(converter, supply, &source, &packets, &output, 0) == -12345);
    CHECK(packets == 2 && output.buffers[0].bytes == 8 && output.buffers[1].bytes == 8);
    packets = 4;
    output.buffers[0] = (Buffer){1,16,left+2}; output.buffers[1] = (Buffer){1,16,right+2};
    CHECK(AudioConverterFillComplexBuffer(converter, supply, &source, &packets, &output, 0) == 0 && packets == 4);
    for (unsigned i = 0; i < 6; ++i) {
        CHECK(left[i] == samples[2*i] / 32768.0f && right[i] == samples[2*i+1] / 32768.0f);
    }
    packets = 2; output.buffers[0] = (Buffer){1,8,left+6}; output.buffers[1] = (Buffer){1,8,right+6};
    CHECK(AudioConverterFillComplexBuffer(converter, supply, &source, &packets, &output, 0) == 0 && packets == 0);
    CHECK(output.buffers[0].bytes == 0 && output.buffers[1].bytes == 0 && left[6] == 42);
    CHECK(AudioConverterReset(converter) == 0);
    source = (Source){0,0,0}; packets = 6;
    output.buffers[0] = (Buffer){1,24,left}; output.buffers[1] = (Buffer){1,24,right};
    CHECK(AudioConverterFillComplexBuffer(converter, supply, &source, &packets, &output, 0) == 0 && packets == 6 && source.calls >= 3);
    CHECK(AudioConverterDispose(converter) == 0);

    // Round-trip through Float64 interleaved, then Float32 planar -> Int16.
    CHECK(AudioConverterNew(&integer, &wide, &converter) == 0);
    double doubles[12];
    output = (Buffers){1, {{2,sizeof(doubles),doubles}}};
    CHECK(AudioConverterConvertComplexBuffer(converter,6,&input,&output) == 0);
    for (unsigned i = 0; i < 12; ++i) CHECK(doubles[i] == samples[i] / 32768.0);
    CHECK(AudioConverterDispose(converter) == 0);
    CHECK(AudioConverterNew(&planar,&integer,&converter) == 0);
    short recovered[12];
    input = (Buffers){2, {{1,24,left},{1,24,right}}};
    output = (Buffers){1, {{2,sizeof(recovered),recovered}}};
    CHECK(AudioConverterConvertComplexBuffer(converter,6,&input,&output) == 0);
    for (unsigned i = 0; i < 12; ++i) CHECK(recovered[i] == samples[i]);
    CHECK(AudioConverterDispose(converter) == 0);
    Format mono_wide = {48000,0x6c70636d,9,8,1,8,1,64,0};
    Format mono_short = {48000,0x6c70636d,12,2,1,2,1,16,0};
    double ties[] = {0.5/32768,1.5/32768,2.5/32768,-0.5/32768,-1.5/32768,-2.5/32768,2,-2};
    const short rounded[] = {1,2,3,-1,-2,-3,32767,-32768};
    short quantized[8];
    input = (Buffers){1, {{1,sizeof(ties),ties}}};
    output = (Buffers){1, {{1,sizeof(quantized),quantized}}};
    CHECK(AudioConverterNew(&mono_wide,&mono_short,&converter) == 0);
    CHECK(AudioConverterConvertComplexBuffer(converter,8,&input,&output) == 0);
    for (unsigned i = 0; i < 8; ++i) CHECK(quantized[i] == rounded[i]);
    CHECK(AudioConverterDispose(converter) == 0);
    for (unsigned i = 0; i < 200; ++i) {
        CHECK(AudioConverterNew(&integer,&planar,&converter) == 0);
        CHECK(AudioConverterDispose(converter) == 0);
    }
    puts("IOS-AUDIO-CONVERTER: real PCM samples, planar/interleaved layouts, callback errors/resume, EOF/reset and ownership");
    return 0;
}
