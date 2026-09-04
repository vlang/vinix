#ifndef VINIX_AGX_TRACE_H
#define VINIX_AGX_TRACE_H

#include <stddef.h>
#include <stdint.h>

void agx_trace_record_resource(const void *object, uint64_t gpu_address,
                               const void *cpu_address, size_t bytes);
void agx_trace_resource_hook_status(int installed);

#endif
