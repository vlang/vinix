#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define DYLD_INTERPOSE(replacement, replacee)                                      \
    __attribute__((used)) static struct {                                           \
        const void *replacement;                                                    \
        const void *replacee;                                                       \
    } _interpose_##replacee __attribute__((section("__DATA,__interpose"))) = {      \
        (const void *)(uintptr_t)&replacement, (const void *)(uintptr_t)&replacee};

static pthread_mutex_t trace_lock = PTHREAD_MUTEX_INITIALIZER;
static FILE *trace_stream;
static io_connect_t gpu_connections[64];
static size_t gpu_connection_count;
static bool trace_all;
static size_t trace_bytes;

static void trace_begin(void) {
    pthread_mutex_lock(&trace_lock);
    if (!trace_stream) {
        const char *path = getenv("AGX_TRACE_FILE");
        trace_stream = path && path[0] ? fopen(path, "w") : stderr;
        if (!trace_stream)
            trace_stream = stderr;
        trace_all = getenv("AGX_TRACE_ALL") != NULL;
        const char *bytes = getenv("AGX_TRACE_BYTES");
        if (bytes) {
            trace_bytes = strtoul(bytes, NULL, 0);
            if (trace_bytes > 4096)
                trace_bytes = 4096;
        }
        fprintf(trace_stream, "{\"event\":\"trace_start\",\"schema\":1}\n");
        fflush(trace_stream);
    }
}

static void trace_hex(const char *name, const void *data, size_t size) {
    if (!trace_bytes || !data || !size)
        return;
    const unsigned char *bytes = data;
    size_t count = size < trace_bytes ? size : trace_bytes;
    fprintf(trace_stream, ",\"%s_prefix\":\"", name);
    for (size_t index = 0; index < count; ++index)
        fprintf(trace_stream, "%02x", bytes[index]);
    fprintf(trace_stream, "\"");
}

static void trace_end(void) {
    fflush(trace_stream);
    pthread_mutex_unlock(&trace_lock);
}

static bool gpu_name(const char *name) {
    return name && (strstr(name, "AGX") || strstr(name, "GPU") || strstr(name, "gpu"));
}

static void remember_gpu_connection(io_connect_t connection) {
    if (!connection || gpu_connection_count == sizeof(gpu_connections) / sizeof(gpu_connections[0]))
        return;
    gpu_connections[gpu_connection_count++] = connection;
}

static bool should_trace(io_connect_t connection) {
    if (trace_all)
        return true;
    for (size_t index = 0; index < gpu_connection_count; ++index) {
        if (gpu_connections[index] == connection)
            return true;
    }
    return false;
}

// Names recovered from AGXDeviceUserClient::getTargetAndMethodForIndex in the
// locally installed AGXG17X kernel collection. Selectors below 0x100 belong to
// the IOGPU superclass and intentionally remain unnamed here.
static const char *agx_method_name(uint32_t selector) {
    switch (selector) {
    case 0x100:
        return "getDeviceConfig";
    case 0x101:
        return "getDeviceInfo";
    case 0x102:
        return "getDriverInfo";
    case 0x103:
        return "getVerbosityInfo";
    case 0x104:
        return "getFrameDumpInfo";
    case 0x105:
        return "performanceCounterSamplerControl";
    case 0x106:
        return "getSettingsFromKMD";
    case 0x107:
        return "setDeviceNotificationPort";
    case 0x109:
        return "consistentPerfStateControl";
    case 0x10a:
        return "getDeviceUserVARange";
    case 0x10b:
        return "createDeadlineProfile";
    case 0x10c:
        return "destroyDeadlineProfile";
    case 0x10d:
        return "performanceStateControl";
    case 0x10f:
        return "getDeviceUMAPoolSizes";
    case 0x110:
        return "invalidateICache";
    case 0x112:
        return "getSPTMEventCounters";
    default:
        return NULL;
    }
}

static void trace_method_name(uint32_t selector) {
    const char *name = agx_method_name(selector);
    if (name)
        fprintf(trace_stream, ",\"method\":\"%s\"", name);
}

static kern_return_t agx_IOServiceOpen(io_service_t service, task_port_t owning_task,
                                       uint32_t type, io_connect_t *connection) {
    kern_return_t status = IOServiceOpen(service, owning_task, type, connection);

    io_name_t name = {0};
    io_name_t class_name = {0};
    IORegistryEntryGetName(service, name);
    IOObjectGetClass(service, class_name);
    if (status == KERN_SUCCESS && connection && (gpu_name(name) || gpu_name(class_name)))
        remember_gpu_connection(*connection);

    trace_begin();
    fprintf(trace_stream,
            "{\"event\":\"service_open\",\"service\":\"%s\",\"class\":\"%s\","
            "\"type\":%u,\"connection\":%u,\"status\":%d}\n",
            name, class_name, type, connection ? *connection : 0, status);
    trace_end();
    return status;
}
DYLD_INTERPOSE(agx_IOServiceOpen, IOServiceOpen)

static kern_return_t agx_IOConnectCallStructMethod(mach_port_t connection, uint32_t selector,
                                                    const void *input, size_t input_size,
                                                    void *output, size_t *output_size) {
    size_t requested_output = output_size ? *output_size : 0;
    kern_return_t status =
        IOConnectCallStructMethod(connection, selector, input, input_size, output, output_size);
    trace_begin();
    if (should_trace(connection)) {
        fprintf(trace_stream,
                "{\"event\":\"method\",\"api\":\"struct\",\"connection\":%u,"
                "\"selector\":%u,\"input_bytes\":%zu,\"requested_output_bytes\":%zu,"
                "\"output_bytes\":%zu,\"status\":%d",
                connection, selector, input_size, requested_output, output_size ? *output_size : 0,
                status);
        trace_method_name(selector);
        trace_hex("input", input, input_size);
        trace_hex("output", output, output_size ? *output_size : 0);
        fprintf(trace_stream, "}\n");
    }
    trace_end();
    return status;
}
DYLD_INTERPOSE(agx_IOConnectCallStructMethod, IOConnectCallStructMethod)

static kern_return_t agx_IOConnectCallAsyncScalarMethod(
    mach_port_t connection, uint32_t selector, mach_port_t wake_port, uint64_t *reference,
    uint32_t reference_count, const uint64_t *input, uint32_t input_count, uint64_t *output,
    uint32_t *output_count) {
    uint32_t requested_output = output_count ? *output_count : 0;
    kern_return_t status = IOConnectCallAsyncScalarMethod(
        connection, selector, wake_port, reference, reference_count, input, input_count, output,
        output_count);
    trace_begin();
    if (should_trace(connection)) {
        fprintf(trace_stream,
                "{\"event\":\"method\",\"api\":\"async_scalar\",\"connection\":%u,"
                "\"selector\":%u,\"references\":%u,\"input_scalars\":%u,"
                "\"requested_output_scalars\":%u,\"output_scalars\":%u,\"status\":%d",
                connection, selector, reference_count, input_count, requested_output,
                output_count ? *output_count : 0, status);
        trace_method_name(selector);
        trace_hex("input", input, (size_t)input_count * sizeof(*input));
        trace_hex("output", output,
                  output_count ? (size_t)*output_count * sizeof(*output) : 0);
        fprintf(trace_stream, "}\n");
    }
    trace_end();
    return status;
}
DYLD_INTERPOSE(agx_IOConnectCallAsyncScalarMethod, IOConnectCallAsyncScalarMethod)
