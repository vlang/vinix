/* SPDX-License-Identifier: GPL-2.0-only */
/* Independent typed driver model; compares observable forwarding/output and
 * temporary ownership rather than copying the production algorithms. */
#define _POSIX_C_SOURCE 200809L
#define VINIX_AGX_TRACE_TEST
#include "../../tools/agx-re/agx_trace.c"
#include <assert.h>
#include <errno.h>
#include <stdatomic.h>
#define CHECK(x) do { if (!(x)) { fprintf(stderr,"AGX trace fixture line %d: %s\n",__LINE__,#x); abort(); } } while (0)
static size_t owned, allocations, releases;
static int allocation_fail, read_fail, partial, driver_calls;
static uint32_t actual_connection, actual_selector, actual_wake, actual_references, actual_inputs;
static const void *actual_input;
static void *actual_output;
static size_t actual_input_bytes;
void *vagt_test_malloc(size_t size) {
    if (allocation_fail) return NULL;
    void *p = malloc(size); if (p) { ++owned; ++allocations; } return p;
}
void vagt_test_free(void *p) { if (p) { CHECK(owned > 0); --owned; ++releases; } free(p); }
int vagt_read(const void *source, size_t bytes, void *destination, uint64_t *copied) {
    if (read_fail) { *copied = 0; return 22; }
    size_t n = partial && bytes > 1 ? bytes - 1 : bytes;
    memcpy(destination, source, n); *copied = n; return 0;
}
static void driver(void) {
    /* Encoded hooks forward only after releasing the trace mutex. */
    CHECK(pthread_mutex_trylock(&trace_lock) == 0); pthread_mutex_unlock(&trace_lock); ++driver_calls;
}
void IOGPUMetalCommandBufferStorageBeginKernelCommands(void *storage, const void *start) { CHECK(storage && start); driver(); }
void IOGPUMetalCommandBufferStorageEndKernelCommands(void *storage, const void *end) { CHECK(storage); (void)end; driver(); }
void IOGPUMetalCommandBufferStorageBeginSegment(void *storage, const void *start) { CHECK(storage && start); driver(); }
void IOGPUMetalCommandBufferStorageEndSegment(void *storage) { CHECK(storage); driver(); }
void IOGPUMetalCommandBufferStorageGrowKernelCommandBuffer(void *storage, size_t bytes) {
    CHECK(storage && bytes == 1234); driver();
    const void *cursor = (char *)storage + 16, *limit = (char *)storage + 32;
    memcpy((char *)storage + 0x30, &cursor, sizeof(cursor)); memcpy((char *)storage + 0x38, &limit, sizeof(limit));
}
kern_return_t IOServiceOpen(io_service_t service, task_port_t owner, uint32_t kind, io_connect_t *connection) {
    CHECK(owner == 23 && kind == 3); driver(); if (connection) *connection = service; return service == 66 ? -7 : 0;
}
kern_return_t IORegistryEntryGetName(io_service_t service, char *name) { strcpy(name, service == 7 || service == 66 || service >= 200 ? "AGXAccelerator" : "HID"); return 0; }
kern_return_t IOObjectGetClass(io_service_t service, char *name) { strcpy(name, service == 8 ? "GPUUserClient" : "UserClient"); return 0; }
kern_return_t IOConnectCallStructMethod(mach_port_t connection, uint32_t selector, const void *input, size_t input_bytes, void *output, size_t *output_bytes) {
    driver(); actual_connection=connection; actual_selector=selector; actual_input=input; actual_input_bytes=input_bytes; actual_output=output;
    if (output_bytes) { CHECK(*output_bytes >= 4); *output_bytes = 4; if (output) memcpy(output,"\x01\x02\x03\x04",4); }
    return 17;
}
kern_return_t IOConnectCallAsyncScalarMethod(mach_port_t connection, uint32_t selector, mach_port_t wake, uint64_t *reference, uint32_t references,
        const uint64_t *input, uint32_t inputs, uint64_t *output, uint32_t *outputs) {
    driver(); actual_connection=connection; actual_selector=selector; actual_wake=wake; actual_references=references; actual_inputs=inputs;
    actual_input=input; actual_output=output; CHECK(reference && reference[0] == 0x8877665544332211ULL);
    if (outputs) { CHECK(*outputs >= 1); *outputs=1; if (output) output[0]=0x1122334455667788ULL; } return -5;
}
static void *marker_thread(void *argument) {
    (void)argument; for (int i=0;i<100;i++) agx_trace_resource_hook_status(1); return NULL;
}
int main(int argc, char **argv) {
    CHECK(argc == 3 || argc == 4); CHECK(setenv("AGX_TRACE_FILE",argv[1],1)==0); CHECK(setenv("AGX_TRACE_RESOURCES","1",1)==0);
    CHECK(setenv("AGX_TRACE_BYTES",argc == 4 ? argv[3] : "8",1)==0);
    if (!strcmp(argv[2],"all")) CHECK(setenv("AGX_TRACE_ALL","1",1)==0); else CHECK(unsetenv("AGX_TRACE_ALL")==0);
    uint32_t connection;
    CHECK(agx_IOServiceOpen(7,23,3,&connection)==0 && connection==7);
    CHECK(agx_IOServiceOpen(8,23,3,&connection)==0 && connection==8);
    CHECK(agx_IOServiceOpen(99,23,3,&connection)==0 && connection==99);
    CHECK(agx_IOServiceOpen(66,23,3,&connection)==-7 && connection==66);
    CHECK(agx_IOServiceOpen(99,23,3,NULL)==0);
    for (uint32_t service=200;service<266;service++) CHECK(agx_IOServiceOpen(service,23,3,&connection)==0);
    agx_trace_resource_hook_status(0); agx_trace_marker("phase-one");
    unsigned char resource[16]; for (size_t i=0;i<sizeof(resource);i++) resource[i]=(unsigned char)i;
    uint64_t gpu=0x100000;
    agx_trace_record_resource(resource,gpu,resource,sizeof(resource));
    agx_trace_record_resource(resource,gpu,resource,sizeof(resource));
    unsigned char segment[24]={0}; memcpy(segment+4,&gpu,sizeof(gpu)); memcpy(segment+12,&gpu,sizeof(gpu));
    unsigned char storage[64]={0}; const void *end=segment+sizeof(segment); memcpy(storage+0x30,&end,sizeof(end));
    agx_IOGPUMetalCommandBufferStorageBeginKernelCommands(storage,segment);
    agx_IOGPUMetalCommandBufferStorageEndKernelCommands(storage,end); CHECK(owned==0);
    agx_IOGPUMetalCommandBufferStorageBeginSegment(storage,segment); agx_IOGPUMetalCommandBufferStorageEndSegment(storage); CHECK(owned==0);
    agx_IOGPUMetalCommandBufferStorageGrowKernelCommandBuffer(storage,1234);
    unsigned char input[8]={0,1,2,3,4,5,6,7}, output[8]={0}; size_t output_bytes=8;
    CHECK(agx_IOConnectCallStructMethod(7,0x100,input,8,output,&output_bytes)==17 && output_bytes==4);
    CHECK(actual_connection==7 && actual_selector==0x100 && actual_input==input && actual_input_bytes==8 && actual_output==output);
    output_bytes=8; CHECK(agx_IOConnectCallStructMethod(99,0x101,input,8,output,&output_bytes)==17);
    output_bytes=8; CHECK(agx_IOConnectCallStructMethod(66,0x101,input,8,output,&output_bytes)==17);
    CHECK(agx_IOConnectCallStructMethod(8,0x113,NULL,0,NULL,NULL)==17);
    output_bytes=8; CHECK(agx_IOConnectCallStructMethod(265,0x101,input,8,output,&output_bytes)==17);
    if (argc == 4 && strcmp(argv[3],"0")) {
        unsigned char large[70000]={0}; output_bytes=8;
        CHECK(agx_IOConnectCallStructMethod(7,0x105,large,sizeof(large),output,&output_bytes)==17);
    }
    uint64_t reference=0x8877665544332211ULL, in=0xaabbccddeeff0011ULL,out=0; uint32_t outputs=2;
    CHECK(agx_IOConnectCallAsyncScalarMethod(7,0x112,19,&reference,1,&in,1,&out,&outputs)==-5 && outputs==1 && out==0x1122334455667788ULL);
    CHECK(actual_wake==19 && actual_references==1 && actual_inputs==1 && actual_input==&in && actual_output==&out);
    CHECK(agx_IOConnectCallAsyncScalarMethod(99,0x101,19,&reference,1,NULL,0,NULL,NULL)==-5);
    read_fail=1; output_bytes=8; CHECK(agx_IOConnectCallStructMethod(7,0x10a,input,8,output,&output_bytes)==17); CHECK(owned==0); read_fail=0;
    partial=1; output_bytes=8; CHECK(agx_IOConnectCallStructMethod(7,0x10b,input,8,output,&output_bytes)==17); CHECK(owned==0); partial=0;
    allocation_fail=1; output_bytes=8; CHECK(agx_IOConnectCallStructMethod(7,0x10c,input,8,output,&output_bytes)==17); CHECK(owned==0); allocation_fail=0;
    unsigned char storages[70][64]={{0}};
    for(int i=0;i<70;i++) { agx_IOGPUMetalCommandBufferStorageBeginKernelCommands(storages[i],segment); agx_IOGPUMetalCommandBufferStorageEndKernelCommands(storages[i],end); CHECK(owned==0); }
    for(int i=0;i<1026;i++) agx_trace_record_resource((void *)(uintptr_t)(i+1),0x200000+(uint64_t)i*64,resource,sizeof(resource));
    uint64_t ignored=0x200000+1025ULL*64; memcpy(segment+4,&ignored,8); memcpy(segment+12,&ignored,8);
    agx_IOGPUMetalCommandBufferStorageBeginKernelCommands(storage,segment); agx_IOGPUMetalCommandBufferStorageEndKernelCommands(storage,end); CHECK(owned==0);
    pthread_t threads[4]; for(int i=0;i<4;i++) CHECK(pthread_create(&threads[i],NULL,marker_thread,NULL)==0);
    for(int i=0;i<4;i++) CHECK(pthread_join(threads[i],NULL)==0);
    agx_trace_marker(NULL);
    CHECK(owned==0 && allocations==releases && driver_calls>=160); printf("AGX TRACE HOST PASS allocations=%zu releases=%zu\n",allocations,releases); return 0;
}
