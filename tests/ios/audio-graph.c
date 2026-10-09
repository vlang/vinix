// SPDX-License-Identifier: GPL-2.0-or-later
// Same public-ABI fixture for installed AudioToolbox and native iOS Mach-O.
typedef unsigned U32;
typedef unsigned long long U64;
typedef int Status, Node;
typedef void *Graph, *Unit, *Component;
typedef struct { double rate; U32 id, flags, packet_bytes, packet_frames, frame_bytes, channels, bits, reserved; } Format;
typedef struct { U32 kind, subtype, manufacturer, flags, mask; } Description;
typedef struct { U32 channels, bytes; void *data; } Buffer;
typedef struct { U32 count; Buffer buffers[2]; } Buffers;
typedef struct { double sample; U64 host; double scalar; U64 word; char smpte[24]; U32 flags, reserved; } Timestamp;
typedef Status (*Render)(void *, U32 *, const Timestamp *, U32, U32, Buffers *);
typedef struct { Render proc; void *user; } Callback;
typedef struct { Unit unit; U32 output, input; } Connection;
extern Component AudioComponentFindNext(Component, const Description *);
extern Status AudioComponentGetDescription(Component, Description *);
extern Status AudioComponentInstanceNew(Component, Unit *), AudioComponentInstanceDispose(Unit);
extern Status NewAUGraph(Graph *), DisposeAUGraph(Graph), AUGraphOpen(Graph);
extern Status AUGraphAddNode(Graph, const Description *, Node *), AUGraphNodeInfo(Graph, Node, Description *, Unit *);
extern Status AUGraphConnectNodeInput(Graph, Node, U32, Node, U32);
extern Status AUGraphSetNodeInputCallback(Graph, Node, U32, const Callback *);
extern Status AUGraphInitialize(Graph), AUGraphUninitialize(Graph), AUGraphStart(Graph), AUGraphStop(Graph), AUGraphIsRunning(Graph,unsigned char *);
extern Status AudioUnitInitialize(Unit), AudioUnitUninitialize(Unit), AudioOutputUnitStart(Unit), AudioOutputUnitStop(Unit);
extern Status AudioUnitSetProperty(Unit,U32,U32,U32,const void *,U32), AudioUnitGetProperty(Unit,U32,U32,U32,void *,U32 *);
extern Status AudioUnitSetParameter(Unit,U32,U32,U32,float,U32), AudioUnitGetParameter(Unit,U32,U32,U32,float *);
extern Status AudioUnitRender(Unit,U32 *,const Timestamp *,U32,U32,Buffers *);
extern int pthread_create(unsigned long *,const void *,void *(*)(void *),void *);
extern int pthread_join(unsigned long,void **);
extern int printf(const char *, ...), puts(const char *);
#define CHECK(x) do { if (!(x)) { printf("IOS-AUDIO-GRAPH FAIL line %d: %s\n",__LINE__,#x); return 1; } } while (0)

typedef struct { unsigned calls, expected_bus, channels; int error, silent, bad, queried; Unit thread_unit; } Source;
static void *query_format(void *user) {
    Source *source = user;
    Format format = {0}; U32 size = sizeof(format);
    if (AudioUnitGetProperty(source->thread_unit,8,2,0,&format,&size) || format.channels != source->channels) source->bad = 1;
    return 0;
}
static Status render(void *user, U32 *flags, const Timestamp *time, U32 bus, U32 frames, Buffers *buffers) {
    Source *source = user;
    ++source->calls;
    if (source->thread_unit && !source->queried) {
        source->queried = 1;
        unsigned long thread;
        if (pthread_create(&thread,0,query_format,source) || pthread_join(thread,0)) source->bad = 1;
    }
    if (bus != source->expected_bus || !time || buffers->count != source->channels) source->bad = 1;
    if (source->error) { source->error = 0; return -12345; }
    if (source->silent) *flags |= 16;
    for (unsigned channel=0;channel<source->channels;++channel) {
        Buffer *buffer = buffers->buffers + channel;
        if (!buffer->data || buffer->bytes < frames*4 || buffer->channels != 1) { source->bad = 1; return -50; }
        float *samples = buffer->data;
        for (unsigned frame=0;frame<frames;++frame) samples[frame] = bus ? 0.125f : channel ? -0.25f : 0.25f;
        buffer->bytes = frames*4;
    }
    return 0;
}

int main(int argc, char **argv) {
    (void)argv;
    Description output_desc = {0x61756f75,0x67656e72,0x6170706c,0,0};
    Description mixer_desc = {0x61756d78,0x6d636d78,0x6170706c,0,0};
    Format floating = {48000,0x6c70636d,41,4,1,4,1,32,0};
    Format integer = {48000,0x6c70636d,12,2,1,2,1,16,0};
    Component component = AudioComponentFindNext(0,&output_desc);
    CHECK(component);
    Description actual = {0};
    CHECK(AudioComponentGetDescription(component,&actual) == 0 && actual.kind == output_desc.kind && actual.subtype == output_desc.subtype);
    CHECK(!AudioComponentFindNext(component,&output_desc));
    Graph graph = 0;
    CHECK(NewAUGraph(&graph) == 0 && graph);
    Node output_node = 0, mixer_node = 0;
    CHECK(AUGraphAddNode(graph,&output_desc,&output_node) == 0);
    CHECK(AUGraphAddNode(graph,&mixer_desc,&mixer_node) == 0 && mixer_node != output_node);
    CHECK(AUGraphConnectNodeInput(graph,mixer_node,0,output_node,0) == 0);
    CHECK(AUGraphOpen(graph) == 0 && AUGraphOpen(graph) == 0);
    Unit output = 0, mixer = 0;
    CHECK(AUGraphNodeInfo(graph,output_node,&actual,&output) == 0 && output);
    CHECK(AUGraphNodeInfo(graph,mixer_node,0,&mixer) == 0 && mixer);
    CHECK(AUGraphNodeInfo(graph,999,&actual,0) == -50);
    U32 count = 2, maximum = 128;
    CHECK(AudioUnitSetProperty(mixer,11,1,0,&count,4) == 0);
    CHECK(AudioUnitSetProperty(mixer,8,2,0,&floating,sizeof(floating)) == 0);
    for (unsigned bus=0;bus<2;++bus) CHECK(AudioUnitSetProperty(mixer,8,1,bus,&floating,sizeof(floating)) == 0);
    CHECK(AudioUnitSetProperty(output,8,1,0,&floating,sizeof(floating)) == 0);
    CHECK(AudioUnitSetProperty(output,8,2,0,&integer,sizeof(integer)) == 0);
    CHECK(AudioUnitSetProperty(mixer,14,0,0,&maximum,4) == 0);
    CHECK(AudioUnitSetProperty(output,14,0,0,&maximum,4) == 0);
    U32 size = sizeof(actual); Format read_format = {0}; size = sizeof(read_format);
    CHECK(AudioUnitGetProperty(output,8,2,0,&read_format,&size) == 0 && size == sizeof(read_format));
    CHECK(read_format.rate == 48000 && read_format.id == integer.id && read_format.bits == 16 && read_format.frame_bytes == 2);
    Source sources[2] = {{.expected_bus=0,.channels=1,.thread_unit=mixer},{.expected_bus=1,.channels=1}};
    for (unsigned bus=0;bus<2;++bus) {
        Callback callback = {render,sources+bus};
        CHECK(AUGraphSetNodeInputCallback(graph,mixer_node,bus,&callback) == 0);
    }
    float initial = 9;
    CHECK(AudioUnitGetParameter(mixer,0,1,0,&initial) == 0 && initial == 0);
    CHECK(AudioUnitGetParameter(mixer,0,2,0,&initial) == 0 && initial == 0);
    CHECK(AudioUnitSetParameter(mixer,0,1,0,1.0f,0) == 0);
    CHECK(AudioUnitSetParameter(mixer,0,1,1,0.5f,0) == 0);
    CHECK(AudioUnitSetParameter(mixer,0,2,0,0.5f,0) == 0);
    float gain = 0;
    CHECK(AudioUnitGetParameter(mixer,0,1,1,&gain) == 0 && gain == 0.5f);
    Timestamp time = {0}; time.flags = 1;
    short samples[258]; for(unsigned i=0;i<258;++i) samples[i] = 1234;
    Buffers buffers = {1,{{1,256,samples}}}; U32 flags = 0;
    CHECK(AudioUnitRender(output,&flags,&time,0,8,&buffers) == -10867);
    CHECK(AUGraphInitialize(graph) == 0);
    CHECK(AUGraphStart(graph) == 0);
    unsigned char running = 0;
    CHECK(AUGraphIsRunning(graph,&running) == 0 && running);
    CHECK(AudioUnitRender(output,&flags,&time,0,8,&buffers) == 0);
    CHECK(!(flags & 16) && buffers.buffers[0].bytes == 16);
    for (unsigned i=0;i<8;++i) CHECK(samples[i] == 5120);
    CHECK(samples[8] == 1234 && sources[0].calls && sources[1].calls && !sources[0].bad && !sources[1].bad);
    CHECK(AUGraphStop(graph) == 0 && AUGraphIsRunning(graph,&running) == 0 && !running);
    CHECK(AUGraphUninitialize(graph) == 0);
    // Disable one bus, then propagate silence from the remaining callback.
    CHECK(AudioUnitSetParameter(mixer,1,1,1,0,0) == 0);
    CHECK(AUGraphInitialize(graph) == 0);
    time.sample += 128; buffers.buffers[0].bytes = 512; flags = 0;
    CHECK(AudioUnitRender(output,&flags,&time,0,8,&buffers) == 0);
    for (unsigned i=0;i<8;++i) CHECK(samples[i] == 4096);
    sources[0].silent = 1; time.sample += 128; buffers.buffers[0].bytes = 512; flags = 0;
    CHECK(AudioUnitRender(output,&flags,&time,0,8,&buffers) == 0);
    CHECK(flags & 16);
    for(unsigned i=0;i<8;++i) CHECK(samples[i] == 0);
    sources[0].silent = 0; sources[0].error = 1; time.sample += 128; buffers.buffers[0].bytes = 512; flags = 0;
    CHECK(AudioUnitRender(output,&flags,&time,0,8,&buffers) == 0 && samples[0] == 0);
    time.sample += 128; buffers.buffers[0].bytes = 512; flags = 0;
    CHECK(AudioUnitRender(output,&flags,&time,0,8,&buffers) == 0 && samples[0] == 4096);
    CHECK(DisposeAUGraph(graph) == 0);
    // Direct unit ownership and stable unit-owned output buffers.
    Unit direct = 0;
    floating.channels = 2;
    sources[0].channels = 2;
    CHECK(AudioComponentInstanceNew(component,&direct) == 0 && direct);
    sources[0].thread_unit = direct; sources[0].queried = 0;
    CHECK(AudioUnitSetProperty(direct,8,1,0,&floating,sizeof(floating)) == 0);
    CHECK(AudioUnitSetProperty(direct,8,2,0,&floating,sizeof(floating)) == 0);
    Callback callback = {render,sources};
    CHECK(AudioUnitSetProperty(direct,23,1,0,&callback,sizeof(callback)) == 0);
    CHECK(AudioUnitInitialize(direct) == 0 && AudioOutputUnitStart(direct) == 0);
    buffers = (Buffers){2,{{1,0,0},{1,0,0}}}; flags = 0; time.sample += 128;
    CHECK(AudioUnitRender(direct,&flags,&time,0,8,&buffers) == 0);
    CHECK(buffers.buffers[0].data && buffers.buffers[1].data && buffers.buffers[0].bytes == 32);
    CHECK(((float *)buffers.buffers[0].data)[0] == 0.25f && ((float *)buffers.buffers[1].data)[0] == -0.25f);
    CHECK(sources[0].queried && !sources[0].bad);
    sources[0].error = 1; flags = 0; time.sample += 128;
    CHECK(AudioUnitRender(direct,&flags,&time,0,8,&buffers) == -12345);
    CHECK(AudioOutputUnitStop(direct) == 0 && AudioUnitUninitialize(direct) == 0);
    CHECK(AudioComponentInstanceDispose(direct) == 0);
    if (argc > 1) {
        Description remote = {0x61756f75,0x72696f63,0x6170706c,0,0};
        CHECK(!AudioComponentFindNext(0,&remote));
        remote.subtype = 0x7670696f;
        CHECK(!AudioComponentFindNext(0,&remote));
        CHECK(NewAUGraph(&graph) == 0);
        CHECK(AUGraphAddNode(graph,&remote,&output_node) == -3000);
        CHECK(DisposeAUGraph(graph) == 0);
        puts("IOS-AUDIO-GRAPH: hardware output and voice capture are unavailable");
    }
    puts("IOS-AUDIO-GRAPH: native callbacks, mixer gains, PCM conversion, errors/silence, offline start/stop and buffer ownership");
    return 0;
}
