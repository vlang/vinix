#import <objc/message.h>
#import <objc/runtime.h>
#include <stdint.h>

#include "agx_trace.h"

static IMP original_init_with_resource;
static IMP original_init_with_device;
static IMP original_init_with_remote_resource;

static void record_resource(id result) {
    if (!result)
        return;

    uint64_t gpu_address = ((uint64_t(*)(id, SEL))objc_msgSend)(result, @selector(gpuAddress));
    uint64_t bytes = ((uint64_t(*)(id, SEL))objc_msgSend)(result, @selector(resourceSize));
    void *cpu_address = ((void *(*)(id, SEL))objc_msgSend)(result, @selector(virtualAddress));
    agx_trace_record_resource((__bridge const void *)result, gpu_address, cpu_address,
                              (size_t)bytes);
}

static id traced_init_with_resource(id self, SEL selector, void *resource_ref) {
    id result = ((id(*)(id, SEL, void *))original_init_with_resource)(self, selector, resource_ref);
    record_resource(result);
    return result;
}

static id traced_init_with_device(id self, SEL selector, id device, uint64_t options, void *args,
                                  uint32_t args_size) {
    id result = ((id(*)(id, SEL, id, uint64_t, void *, uint32_t))original_init_with_device)(
        self, selector, device, options, args, args_size);
    record_resource(result);
    return result;
}

static id traced_init_with_remote_resource(id self, SEL selector, id device, id remote_resource,
                                           uint64_t options, void *args, uint32_t args_size) {
    id result =
        ((id(*)(id, SEL, id, id, uint64_t, void *, uint32_t))original_init_with_remote_resource)(
            self, selector, device, remote_resource, options, args, args_size);
    record_resource(result);
    return result;
}

static IMP install(Class cls, const char *name, IMP replacement) {
    Method method = cls ? class_getInstanceMethod(cls, sel_registerName(name)) : NULL;
    return method ? method_setImplementation(method, replacement) : NULL;
}

__attribute__((constructor)) static void install_resource_trace(void) {
    Class cls = objc_getClass("IOGPUMetalResource");
    original_init_with_resource =
        install(cls, "initWithResource:", (IMP)traced_init_with_resource);
    original_init_with_device = install(cls, "initWithDevice:options:args:argsSize:",
                                        (IMP)traced_init_with_device);
    original_init_with_remote_resource =
        install(cls, "initWithDevice:remoteStorageResource:options:args:argsSize:",
                (IMP)traced_init_with_remote_resource);
    agx_trace_resource_hook_status(original_init_with_resource && original_init_with_device &&
                                   original_init_with_remote_resource);
}
