// SPDX-License-Identifier: GPL-2.0-only
// Observe driver-encoded memory read-only, then forward the original typed ABI.
// Records are borrowed identities; temporary Mach snapshots explicitly free.
@[translated]
module tracecore
#include "agx_trace_v.h"
fn C.getenv(&char) &char
fn C.fopen(&char, &char) voidptr
fn C.strtoul(&char, voidptr, i32) u64
fn C.fprintf(voidptr, &char, ...) i32
fn C.fflush(voidptr) i32
fn C.snprintf(&char, usize, &char, ...) i32
fn C.strstr(&char, &char) &char
fn C.malloc(usize) voidptr
fn C.free(voidptr)
fn C.memcpy(voidptr, voidptr, usize) voidptr
fn C.vagt_lock()
fn C.vagt_unlock()
fn C.vagt_read(voidptr, usize, voidptr, &u64) i32
fn C.IOGPUMetalCommandBufferStorageBeginKernelCommands(voidptr, voidptr)
fn C.IOGPUMetalCommandBufferStorageEndKernelCommands(voidptr, voidptr)
fn C.IOGPUMetalCommandBufferStorageBeginSegment(voidptr, voidptr)
fn C.IOGPUMetalCommandBufferStorageEndSegment(voidptr)
fn C.IOGPUMetalCommandBufferStorageGrowKernelCommandBuffer(voidptr, usize)
fn C.IOServiceOpen(u32, u32, u32, &u32) i32
fn C.IORegistryEntryGetName(u32, &char) i32
fn C.IOObjectGetClass(u32, &char) i32
fn C.IOConnectCallStructMethod(u32, u32, voidptr, usize, voidptr, &usize) i32
fn C.IOConnectCallAsyncScalarMethod(u32, u32, u32, &u64, u32, voidptr, u32, &u64, &u32) i32
@[c_extern] __global C.stderr voidptr
struct StorageTrace { mut: storage voidptr kernel_start voidptr segment_start voidptr }
struct ResourceTrace { mut: object voidptr gpu_address u64 cpu_address voidptr bytes usize }
__global (
 vagt_stream voidptr
 vagt_connections [64]u32
 vagt_connection_count usize
 vagt_all bool
 vagt_resources bool
 vagt_bytes usize
 vagt_phase [64]char
 vagt_storages [64]StorageTrace
 vagt_records [1024]ResourceTrace
 vagt_record_count usize
)
fn nonnull(pointer voidptr) bool { unsafe { return pointer != nil } }
fn trace_begin() {
 unsafe {
  C.vagt_lock()
  if !nonnull(vagt_stream) {
   path := C.getenv(c'AGX_TRACE_FILE')
   vagt_stream = if nonnull(path) && path[0] != 0 { C.fopen(path, c'w') } else { C.stderr }
   if !nonnull(vagt_stream) { vagt_stream = C.stderr }
   vagt_all = nonnull(C.getenv(c'AGX_TRACE_ALL')); vagt_resources = nonnull(C.getenv(c'AGX_TRACE_RESOURCES'))
   bytes := C.getenv(c'AGX_TRACE_BYTES')
   if nonnull(bytes) { vagt_bytes = usize(C.strtoul(bytes, nil, 0)); if vagt_bytes > 65536 { vagt_bytes = 65536 } }
   C.fprintf(vagt_stream, c'{"event":"trace_start","schema":2}\n'); C.fflush(vagt_stream)
  }
 }
}
fn trace_end() { C.fflush(vagt_stream); C.vagt_unlock() }
fn phase_field() { unsafe { if vagt_phase[0] != 0 { C.fprintf(vagt_stream, c',"phase":"%s"', &vagt_phase[0]) } } }
fn trace_hex(name &char, data voidptr, size usize) {
 unsafe {
  if vagt_bytes == 0 || !nonnull(data) || size == 0 { return }
  count := if size < vagt_bytes { size } else { vagt_bytes }
  bytes := &u8(C.malloc(count)); if !nonnull(bytes) { return }
  mut copied := u64(0); status := C.vagt_read(data, count, bytes, &copied)
  if status != 0 || copied == 0 { C.free(bytes); C.fprintf(vagt_stream, c',"%s_read_status":%d', name, status); return }
  C.fprintf(vagt_stream, c',"%s_prefix":"', name)
  for index := u64(0); index < copied; index++ { C.fprintf(vagt_stream, c'%02x', u32(bytes[index])) }
  C.fprintf(vagt_stream, c'"'); C.free(bytes)
 }
}
fn gpu_name(name &char) bool {
 return nonnull(name) && (nonnull(C.strstr(name, c'AGX')) || nonnull(C.strstr(name, c'GPU')) || nonnull(C.strstr(name, c'gpu')))
}
fn remember_connection(connection u32) {
 unsafe { if connection == 0 || vagt_connection_count == 64 { return }; vagt_connections[vagt_connection_count] = connection; vagt_connection_count++ }
}
fn should_trace(connection u32) bool {
 unsafe { if vagt_all { return true }; for i := usize(0); i < vagt_connection_count; i++ { if vagt_connections[i] == connection { return true } }; return false }
}
fn storage_for(storage voidptr) &StorageTrace {
 unsafe {
  mut empty := &StorageTrace(nil)
  for i := 0; i < 64; i++ { if vagt_storages[i].storage == storage { return &vagt_storages[i] }; if !nonnull(vagt_storages[i].storage) && !nonnull(empty) { empty = &vagt_storages[i] } }
  if nonnull(empty) { empty.storage = storage }; return empty
 }
}
fn read_pointer(address voidptr, value &voidptr) bool {
 unsafe { mut copied := u64(0); *value = nil; status := C.vagt_read(address, sizeof(voidptr), value, &copied); return status == 0 && copied == sizeof(voidptr) }
}
fn distance(start voidptr, end voidptr) usize {
 first := usize(start); last := usize(end)
 return if first == 0 || last < first || last - first > 16 * 1024 * 1024 { usize(0) } else { last - first }
}
@[export: 'vagt_resource_hook_status']
pub fn resource_hook_status(installed i32) { trace_begin(); C.fprintf(vagt_stream, c'{"event":"resource_hook","installed":%s}\n', if installed != 0 { &char(c'true') } else { &char(c'false') }); trace_end() }
@[export: 'vagt_record_resource']
pub fn record_resource(object voidptr, gpu_address u64, cpu_address voidptr, bytes usize) {
 unsafe {
  trace_begin()
  if vagt_resources && nonnull(object) && gpu_address != 0 && bytes != 0 {
   mut i := usize(0)
   for ; i < vagt_record_count; i++ {
    r := &vagt_records[i]
    if r.object == object || (r.gpu_address == gpu_address && r.cpu_address == cpu_address && r.bytes == bytes) { break }
   }
   if i == vagt_record_count && vagt_record_count < 1024 { vagt_record_count++ }
   if i < vagt_record_count { vagt_records[i] = ResourceTrace{object: object, gpu_address: gpu_address, cpu_address: cpu_address, bytes: bytes} }
   C.fprintf(vagt_stream, c'{"event":"resource","object":"%p","gpu_address":"0x%zx","cpu_address":"%p","bytes":%zu', object, usize(gpu_address), cpu_address, bytes)
   phase_field(); C.fprintf(vagt_stream, c'}\n')
  }
  trace_end()
 }
}
fn segment_resources(segment voidptr, segment_bytes usize) {
 unsafe {
  if !vagt_resources || vagt_bytes == 0 || !nonnull(segment) || segment_bytes < sizeof(u64) { return }
  copy := &u8(C.malloc(segment_bytes)); if !nonnull(copy) { return }
  mut copied := u64(0); status := C.vagt_read(segment, segment_bytes, copy, &copied)
  if status != 0 || copied != segment_bytes { C.free(copy); return }
  mut emitted := [1024]bool{}
  for offset := usize(0); offset + sizeof(u64) <= segment_bytes; offset += 4 {
   mut address := u64(0); C.memcpy(&address, copy + offset, sizeof(address))
   for i := usize(0); i < vagt_record_count; i++ {
    r := &vagt_records[i]
    if emitted[i] || !nonnull(r.cpu_address) || address < r.gpu_address || address - r.gpu_address >= r.bytes { continue }
    resource_offset := usize(address - r.gpu_address)
    C.fprintf(vagt_stream, c'{"event":"resource_snapshot","source_offset":%zu,"gpu_address":"0x%zx","resource_gpu_address":"0x%zx","resource_offset":%zu,"resource_bytes":%zu', offset, usize(address), usize(r.gpu_address), resource_offset, r.bytes)
    phase_field(); trace_hex(c'data', r.cpu_address, r.bytes); C.fprintf(vagt_stream, c'}\n'); emitted[i] = true
   }
  }
  C.free(copy)
 }
}
@[export: 'vagt_marker']
pub fn marker(phase &char) {
 unsafe { trace_begin(); C.snprintf(&vagt_phase[0], sizeof(vagt_phase), c'%s', if nonnull(phase) { phase } else { &char(c'') }); C.fprintf(vagt_stream, c'{"event":"marker","phase":"%s"}\n', &vagt_phase[0]); trace_end() }
}
@[export: 'vagt_begin_kernel']
pub fn begin_kernel(storage voidptr, start voidptr) {
 unsafe { trace_begin(); entry := storage_for(storage); if nonnull(entry) { entry.kernel_start = start }; C.fprintf(vagt_stream, c'{"event":"kernel_commands_begin","storage":"%p","start":"%p"', storage, start); phase_field(); C.fprintf(vagt_stream, c'}\n'); trace_end(); C.IOGPUMetalCommandBufferStorageBeginKernelCommands(storage, start) }
}
@[export: 'vagt_end_kernel']
pub fn end_kernel(storage voidptr, end voidptr) {
 unsafe { trace_begin(); entry := storage_for(storage); start := if nonnull(entry) { entry.kernel_start } else { voidptr(nil) }; bytes := distance(start, end); C.fprintf(vagt_stream, c'{"event":"kernel_commands","storage":"%p","start":"%p","end":"%p","bytes":%zu', storage, start, end, bytes); phase_field(); trace_hex(c'data', start, bytes); C.fprintf(vagt_stream, c'}\n'); segment_resources(start, bytes); if nonnull(entry) { entry.kernel_start = nil }; trace_end(); C.IOGPUMetalCommandBufferStorageEndKernelCommands(storage, end) }
}
@[export: 'vagt_begin_segment']
pub fn begin_segment(storage voidptr, start voidptr) {
 unsafe { trace_begin(); entry := storage_for(storage); if nonnull(entry) { entry.segment_start = start }; C.fprintf(vagt_stream, c'{"event":"segment_begin","storage":"%p","start":"%p"', storage, start); phase_field(); C.fprintf(vagt_stream, c'}\n'); trace_end(); C.IOGPUMetalCommandBufferStorageBeginSegment(storage, start) }
}
@[export: 'vagt_end_segment']
pub fn end_segment(storage voidptr) {
 unsafe { mut end := voidptr(nil); read_pointer(&u8(storage) + 0x30, &end); trace_begin(); entry := storage_for(storage); start := if nonnull(entry) { entry.segment_start } else { voidptr(nil) }; bytes := distance(start, end); C.fprintf(vagt_stream, c'{"event":"segment","storage":"%p","start":"%p","end":"%p","bytes":%zu', storage, start, end, bytes); phase_field(); trace_hex(c'data', start, bytes); C.fprintf(vagt_stream, c'}\n'); segment_resources(start, bytes); if nonnull(entry) { entry.segment_start = nil }; trace_end(); C.IOGPUMetalCommandBufferStorageEndSegment(storage) }
}
@[export: 'vagt_grow']
pub fn grow(storage voidptr, bytes usize) {
 unsafe { C.IOGPUMetalCommandBufferStorageGrowKernelCommandBuffer(storage, bytes); mut cursor := voidptr(nil); mut limit := voidptr(nil); read_pointer(&u8(storage) + 0x30, &cursor); read_pointer(&u8(storage) + 0x38, &limit); trace_begin(); C.fprintf(vagt_stream, c'{"event":"command_buffer_grow","storage":"%p","requested_bytes":%zu,"cursor":"%p","limit":"%p"', storage, bytes, cursor, limit); phase_field(); C.fprintf(vagt_stream, c'}\n'); trace_end() }
}
fn method_name(selector u32) &char {
 unsafe {
  return match selector {
   0x100 { c'getDeviceConfig' } 0x101 { c'getDeviceInfo' } 0x102 { c'getDriverInfo' } 0x103 { c'getVerbosityInfo' }
   0x104 { c'getFrameDumpInfo' } 0x105 { c'performanceCounterSamplerControl' } 0x106 { c'getSettingsFromKMD' }
   0x107 { c'setDeviceNotificationPort' } 0x109 { c'consistentPerfStateControl' } 0x10a { c'getDeviceUserVARange' }
   0x10b { c'createDeadlineProfile' } 0x10c { c'destroyDeadlineProfile' } 0x10d { c'performanceStateControl' }
   0x10f { c'getDeviceUMAPoolSizes' } 0x110 { c'invalidateICache' } 0x112 { c'getSPTMEventCounters' }
   else { &char(nil) }
  }
 }
}
fn method_field(selector u32) { name := method_name(selector); if nonnull(name) { C.fprintf(vagt_stream, c',"method":"%s"', name) } }
@[export: 'vagt_service_open']
pub fn service_open(service u32, owner u32, kind u32, connection &u32) i32 {
 unsafe {
  status := C.IOServiceOpen(service, owner, kind, connection)
  mut name := [128]char{}; mut class_name := [128]char{}
  C.IORegistryEntryGetName(service, &name[0]); C.IOObjectGetClass(service, &class_name[0])
  if status == 0 && nonnull(connection) && (gpu_name(&name[0]) || gpu_name(&class_name[0])) { remember_connection(*connection) }
  trace_begin(); C.fprintf(vagt_stream, c'{"event":"service_open","service":"%s","class":"%s","type":%u,"connection":%u,"status":%d}\n', &name[0], &class_name[0], kind, if nonnull(connection) { *connection } else { u32(0) }, status); trace_end(); return status
 }
}
@[export: 'vagt_struct_method']
pub fn struct_method(connection u32, selector u32, input voidptr, input_bytes usize, output voidptr, output_bytes &usize) i32 {
 unsafe {
  requested := if nonnull(output_bytes) { *output_bytes } else { usize(0) }
  status := C.IOConnectCallStructMethod(connection, selector, input, input_bytes, output, output_bytes)
  trace_begin()
  if should_trace(connection) {
   C.fprintf(vagt_stream, c'{"event":"method","api":"struct","connection":%u,"selector":%u,"input_bytes":%zu,"requested_output_bytes":%zu,"output_bytes":%zu,"status":%d', connection, selector, input_bytes, requested, if nonnull(output_bytes) { *output_bytes } else { usize(0) }, status)
   method_field(selector); trace_hex(c'input', input, input_bytes); trace_hex(c'output', output, if nonnull(output_bytes) { *output_bytes } else { usize(0) }); C.fprintf(vagt_stream, c'}\n')
  }
  trace_end(); return status
 }
}
@[export: 'vagt_async_method']
pub fn async_method(connection u32, selector u32, wake u32, reference &u64, references u32, input voidptr, inputs u32, output &u64, outputs &u32) i32 {
 unsafe {
  requested := if nonnull(outputs) { *outputs } else { u32(0) }
  status := C.IOConnectCallAsyncScalarMethod(connection, selector, wake, reference, references, input, inputs, output, outputs)
  trace_begin()
  if should_trace(connection) {
   C.fprintf(vagt_stream, c'{"event":"method","api":"async_scalar","connection":%u,"selector":%u,"references":%u,"input_scalars":%u,"requested_output_scalars":%u,"output_scalars":%u,"status":%d', connection, selector, references, inputs, requested, if nonnull(outputs) { *outputs } else { u32(0) }, status)
   method_field(selector); trace_hex(c'input', input, usize(inputs) * sizeof(u64)); trace_hex(c'output', output, if nonnull(outputs) { usize(*outputs) * sizeof(u64) } else { usize(0) }); C.fprintf(vagt_stream, c'}\n')
  }
  trace_end(); return status
 }
}
