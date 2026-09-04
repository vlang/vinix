#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <pthread.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "agx_trace.h"

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
static bool trace_resources;
static size_t trace_bytes;
static char trace_phase[64];

struct storage_trace {
    const void *storage;
    const void *kernel_start;
    const void *segment_start;
};

static struct storage_trace storage_traces[64];

struct resource_trace {
    const void *object;
    uint64_t gpu_address;
    const void *cpu_address;
    size_t bytes;
};

static struct resource_trace resource_traces[1024];
static size_t resource_trace_count;

// These are private IOGPU entry points. Their calling convention and the
// storage cursor at offsets 0x30/0x38 were recovered from the local arm64e
// AGXMetalG17X binary. Keep these hooks read-only: they observe byte ranges
// which Apple's driver has already encoded and then invoke the real function.
extern void IOGPUMetalCommandBufferStorageBeginKernelCommands(void *storage,
                                                               const void *start);
extern void IOGPUMetalCommandBufferStorageEndKernelCommands(void *storage,
                                                             const void *end);
extern void IOGPUMetalCommandBufferStorageBeginSegment(void *storage, const void *start);
extern void IOGPUMetalCommandBufferStorageEndSegment(void *storage);
extern void IOGPUMetalCommandBufferStorageGrowKernelCommandBuffer(void *storage,
                                                                  size_t bytes);

static void trace_begin(void) {
    pthread_mutex_lock(&trace_lock);
    if (!trace_stream) {
        const char *path = getenv("AGX_TRACE_FILE");
        trace_stream = path && path[0] ? fopen(path, "w") : stderr;
        if (!trace_stream)
            trace_stream = stderr;
        trace_all = getenv("AGX_TRACE_ALL") != NULL;
        trace_resources = getenv("AGX_TRACE_RESOURCES") != NULL;
        const char *bytes = getenv("AGX_TRACE_BYTES");
        if (bytes) {
            trace_bytes = strtoul(bytes, NULL, 0);
            if (trace_bytes > 65536)
                trace_bytes = 65536;
        }
        fprintf(trace_stream, "{\"event\":\"trace_start\",\"schema\":2}\n");
        fflush(trace_stream);
    }
}

static void trace_phase_field(void) {
    if (trace_phase[0])
        fprintf(trace_stream, ",\"phase\":\"%s\"", trace_phase);
}

static void trace_hex(const char *name, const void *data, size_t size) {
    if (!trace_bytes || !data || !size)
        return;
    size_t count = size < trace_bytes ? size : trace_bytes;
    unsigned char *bytes = malloc(count);
    if (!bytes)
        return;
    mach_vm_size_t copied = 0;
    kern_return_t status = mach_vm_read_overwrite(
        mach_task_self(), (mach_vm_address_t)(uintptr_t)data, (mach_vm_size_t)count,
        (mach_vm_address_t)(uintptr_t)bytes, &copied);
    if (status != KERN_SUCCESS || copied == 0) {
        free(bytes);
        fprintf(trace_stream, ",\"%s_read_status\":%d", name, status);
        return;
    }
    fprintf(trace_stream, ",\"%s_prefix\":\"", name);
    for (size_t index = 0; index < copied; ++index)
        fprintf(trace_stream, "%02x", bytes[index]);
    fprintf(trace_stream, "\"");
    free(bytes);
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

static struct storage_trace *storage_trace_for(const void *storage) {
    struct storage_trace *free_entry = NULL;
    for (size_t index = 0; index < sizeof(storage_traces) / sizeof(storage_traces[0]); ++index) {
        if (storage_traces[index].storage == storage)
            return &storage_traces[index];
        if (!storage_traces[index].storage && !free_entry)
            free_entry = &storage_traces[index];
    }
    if (free_entry)
        free_entry->storage = storage;
    return free_entry;
}

static bool read_pointer(const void *address, const void **value) {
    mach_vm_size_t copied = 0;
    *value = NULL;
    kern_return_t status = mach_vm_read_overwrite(
        mach_task_self(), (mach_vm_address_t)(uintptr_t)address, sizeof(*value),
        (mach_vm_address_t)(uintptr_t)value, &copied);
    return status == KERN_SUCCESS && copied == sizeof(*value);
}

static size_t byte_distance(const void *start, const void *end) {
    uintptr_t first = (uintptr_t)start;
    uintptr_t last = (uintptr_t)end;
    if (!first || last < first || last - first > 16 * 1024 * 1024)
        return 0;
    return last - first;
}

void agx_trace_resource_hook_status(int installed) {
    trace_begin();
    fprintf(trace_stream, "{\"event\":\"resource_hook\",\"installed\":%s}\n",
            installed ? "true" : "false");
    trace_end();
}

void agx_trace_record_resource(const void *object, uint64_t gpu_address,
                               const void *cpu_address, size_t bytes) {
    trace_begin();
    if (trace_resources && object && gpu_address && bytes) {
        size_t index = 0;
        for (; index < resource_trace_count; ++index) {
            if (resource_traces[index].object == object ||
                (resource_traces[index].gpu_address == gpu_address &&
                 resource_traces[index].cpu_address == cpu_address &&
                 resource_traces[index].bytes == bytes))
                break;
        }
        if (index == resource_trace_count && resource_trace_count <
                                                 sizeof(resource_traces) /
                                                     sizeof(resource_traces[0]))
            ++resource_trace_count;
        if (index < resource_trace_count) {
            resource_traces[index] = (struct resource_trace){
                .object = object,
                .gpu_address = gpu_address,
                .cpu_address = cpu_address,
                .bytes = bytes,
            };
        }
        fprintf(trace_stream,
                "{\"event\":\"resource\",\"object\":\"%p\","
                "\"gpu_address\":\"0x%llx\",\"cpu_address\":\"%p\","
                "\"bytes\":%zu",
                object, (unsigned long long)gpu_address, cpu_address, bytes);
        trace_phase_field();
        fprintf(trace_stream, "}\n");
    }
    trace_end();
}

// Find GPU virtual addresses embedded in a completed segment and snapshot
// their CPU-visible backing allocations. This follows only allocations which
// the IOGPUMetalResource hook observed; it never tries to map an arbitrary GPU
// address or touch device MMIO.
static void trace_segment_resources(const void *segment, size_t segment_bytes) {
    if (!trace_resources || !trace_bytes || !segment || segment_bytes < sizeof(uint64_t))
        return;
    unsigned char *copy = malloc(segment_bytes);
    if (!copy)
        return;
    mach_vm_size_t copied = 0;
    kern_return_t status = mach_vm_read_overwrite(
        mach_task_self(), (mach_vm_address_t)(uintptr_t)segment,
        (mach_vm_size_t)segment_bytes, (mach_vm_address_t)(uintptr_t)copy, &copied);
    if (status != KERN_SUCCESS || copied != segment_bytes) {
        free(copy);
        return;
    }

    bool emitted[1024] = {0};
    for (size_t offset = 0; offset + sizeof(uint64_t) <= segment_bytes; offset += 4) {
        uint64_t address = 0;
        memcpy(&address, copy + offset, sizeof(address));
        for (size_t index = 0; index < resource_trace_count; ++index) {
            const struct resource_trace *resource = &resource_traces[index];
            if (emitted[index] || !resource->cpu_address || address < resource->gpu_address ||
                address - resource->gpu_address >= resource->bytes)
                continue;
            size_t resource_offset = (size_t)(address - resource->gpu_address);
            fprintf(trace_stream,
                    "{\"event\":\"resource_snapshot\",\"source_offset\":%zu,"
                    "\"gpu_address\":\"0x%llx\",\"resource_gpu_address\":"
                    "\"0x%llx\",\"resource_offset\":%zu,\"resource_bytes\":%zu",
                    offset, (unsigned long long)address,
                    (unsigned long long)resource->gpu_address, resource_offset,
                    resource->bytes);
            trace_phase_field();
            trace_hex("data", resource->cpu_address, resource->bytes);
            fprintf(trace_stream, "}\n");
            emitted[index] = true;
        }
    }
    free(copy);
}

__attribute__((visibility("default"))) void agx_trace_marker(const char *phase) {
    trace_begin();
    if (!phase)
        phase = "";
    snprintf(trace_phase, sizeof(trace_phase), "%s", phase);
    fprintf(trace_stream, "{\"event\":\"marker\",\"phase\":\"%s\"}\n", trace_phase);
    trace_end();
}

static void agx_IOGPUMetalCommandBufferStorageBeginKernelCommands(void *storage,
                                                                  const void *start) {
    trace_begin();
    struct storage_trace *entry = storage_trace_for(storage);
    if (entry)
        entry->kernel_start = start;
    fprintf(trace_stream,
            "{\"event\":\"kernel_commands_begin\",\"storage\":\"%p\","
            "\"start\":\"%p\"",
            storage, start);
    trace_phase_field();
    fprintf(trace_stream, "}\n");
    trace_end();
    IOGPUMetalCommandBufferStorageBeginKernelCommands(storage, start);
}
DYLD_INTERPOSE(agx_IOGPUMetalCommandBufferStorageBeginKernelCommands,
               IOGPUMetalCommandBufferStorageBeginKernelCommands)

static void agx_IOGPUMetalCommandBufferStorageEndKernelCommands(void *storage,
                                                                const void *end) {
    trace_begin();
    struct storage_trace *entry = storage_trace_for(storage);
    const void *start = entry ? entry->kernel_start : NULL;
    size_t bytes = byte_distance(start, end);
    fprintf(trace_stream,
            "{\"event\":\"kernel_commands\",\"storage\":\"%p\","
            "\"start\":\"%p\",\"end\":\"%p\",\"bytes\":%zu",
            storage, start, end, bytes);
    trace_phase_field();
    trace_hex("data", start, bytes);
    fprintf(trace_stream, "}\n");
    trace_segment_resources(start, bytes);
    if (entry)
        entry->kernel_start = NULL;
    trace_end();
    IOGPUMetalCommandBufferStorageEndKernelCommands(storage, end);
}
DYLD_INTERPOSE(agx_IOGPUMetalCommandBufferStorageEndKernelCommands,
               IOGPUMetalCommandBufferStorageEndKernelCommands)

static void agx_IOGPUMetalCommandBufferStorageBeginSegment(void *storage, const void *start) {
    trace_begin();
    struct storage_trace *entry = storage_trace_for(storage);
    if (entry)
        entry->segment_start = start;
    fprintf(trace_stream,
            "{\"event\":\"segment_begin\",\"storage\":\"%p\","
            "\"start\":\"%p\"",
            storage, start);
    trace_phase_field();
    fprintf(trace_stream, "}\n");
    trace_end();
    IOGPUMetalCommandBufferStorageBeginSegment(storage, start);
}
DYLD_INTERPOSE(agx_IOGPUMetalCommandBufferStorageBeginSegment,
               IOGPUMetalCommandBufferStorageBeginSegment)

static void agx_IOGPUMetalCommandBufferStorageEndSegment(void *storage) {
    const void *end = NULL;
    read_pointer((const unsigned char *)storage + 0x30, &end);
    trace_begin();
    struct storage_trace *entry = storage_trace_for(storage);
    const void *start = entry ? entry->segment_start : NULL;
    size_t bytes = byte_distance(start, end);
    fprintf(trace_stream,
            "{\"event\":\"segment\",\"storage\":\"%p\","
            "\"start\":\"%p\",\"end\":\"%p\",\"bytes\":%zu",
            storage, start, end, bytes);
    trace_phase_field();
    trace_hex("data", start, bytes);
    fprintf(trace_stream, "}\n");
    trace_segment_resources(start, bytes);
    if (entry)
        entry->segment_start = NULL;
    trace_end();
    IOGPUMetalCommandBufferStorageEndSegment(storage);
}
DYLD_INTERPOSE(agx_IOGPUMetalCommandBufferStorageEndSegment,
               IOGPUMetalCommandBufferStorageEndSegment)

static void agx_IOGPUMetalCommandBufferStorageGrowKernelCommandBuffer(void *storage,
                                                                      size_t bytes) {
    IOGPUMetalCommandBufferStorageGrowKernelCommandBuffer(storage, bytes);
    const void *cursor = NULL;
    const void *limit = NULL;
    read_pointer((const unsigned char *)storage + 0x30, &cursor);
    read_pointer((const unsigned char *)storage + 0x38, &limit);
    trace_begin();
    fprintf(trace_stream,
            "{\"event\":\"command_buffer_grow\",\"storage\":\"%p\","
            "\"requested_bytes\":%zu,\"cursor\":\"%p\",\"limit\":\"%p\"",
            storage, bytes, cursor, limit);
    trace_phase_field();
    fprintf(trace_stream, "}\n");
    trace_end();
}
DYLD_INTERPOSE(agx_IOGPUMetalCommandBufferStorageGrowKernelCommandBuffer,
               IOGPUMetalCommandBufferStorageGrowKernelCommandBuffer)

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
