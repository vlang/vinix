// SPDX-License-Identifier: GPL-2.0-or-later
/*
 * Fault injection for the fake-G17 Mesa VM test.  This interposes only the
 * unstable Asahi GEM_BIND and SUBMIT ioctls in the test process.  It lets the
 * integration test mutate Mesa's real BO/VA state without adding test hooks to
 * the kernel or exposing fake-backend internals through the UAPI.
 */
#define _GNU_SOURCE

#include <dlfcn.h>
#include <errno.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>

#define DRM_IOCTL_TYPE 'd'
#define DRM_GEM_CLOSE_NR 0x09
#define DRM_ASAHI_GEM_CREATE_NR 0x43
#define DRM_ASAHI_GEM_BIND_NR 0x45
#define DRM_ASAHI_QUEUE_DESTROY_NR 0x47
#define DRM_ASAHI_SUBMIT_NR 0x48
#define DRM_IOCTL_NR(request) ((unsigned int)(request) & 0xffu)
#define DRM_IOCTL_REQUEST_TYPE(request) (((unsigned int)(request) >> 8) & 0xffu)

#define ASAHI_BIND_OP_BIND 0
#define ASAHI_BIND_OP_UNBIND 1
#define ASAHI_BIND_OP_UNBIND_ALL 2
#define ASAHI_BIND_READ (1u << 0)
#define ASAHI_BIND_WRITE (1u << 1)

#define ASAHI_CMD_RENDER 0
#define MAX_TRACKED_BINDINGS 1024
#define MAX_SUBMISSION_COMMANDS 64

/* musl follows the historical int request ABI; Darwin and glibc expose an
 * unsigned long prototype.  Match the platform declaration for interposing. */
#if defined(__linux__) && !defined(__GLIBC__)
typedef int ioctl_request_t;
#else
typedef unsigned long ioctl_request_t;
#endif

struct drm_asahi_gem_bind {
    uint64_t extensions;
    uint32_t op;
    uint32_t flags;
    uint32_t handle;
    uint32_t vm_id;
    uint64_t offset;
    uint64_t range;
    uint64_t addr;
};

struct drm_gem_close {
    uint32_t handle;
    uint32_t pad;
};

struct drm_asahi_gem_create {
    uint64_t extensions;
    uint64_t size;
    uint32_t flags;
    uint32_t vm_id;
    uint32_t handle;
    uint32_t pad;
};

struct drm_asahi_queue_destroy {
    uint64_t extensions;
    uint32_t queue_id;
    uint32_t pad;
};

struct drm_asahi_command {
    uint64_t extensions;
    uint32_t cmd_type;
    uint32_t flags;
    uint64_t cmd_buffer;
    uint64_t cmd_buffer_size;
    uint64_t result_offset;
    uint64_t result_size;
    uint32_t barriers[2];
};

struct drm_asahi_submit {
    uint64_t extensions;
    uint64_t in_syncs;
    uint64_t out_syncs;
    uint64_t commands;
    uint32_t flags;
    uint32_t queue_id;
    uint32_t result_handle;
    uint32_t in_sync_count;
    uint32_t out_sync_count;
    uint32_t command_count;
};

/* Prefix through the evidence-backed depth metadata store address. */
struct drm_asahi_cmd_render_prefix {
    uint64_t extensions;
    uint64_t flags;
    uint64_t encoder_ptr;
    uint64_t vertex_usc_base;
    uint64_t fragment_usc_base;
    uint64_t vertex_attachments;
    uint64_t fragment_attachments;
    uint32_t vertex_attachment_count;
    uint32_t fragment_attachment_count;
    uint32_t vertex_helper_program;
    uint32_t fragment_helper_program;
    uint32_t vertex_helper_cfg;
    uint32_t fragment_helper_cfg;
    uint64_t vertex_helper_arg;
    uint64_t fragment_helper_arg;
    uint64_t depth_buffer_load;
    uint64_t depth_buffer_load_stride;
    uint64_t depth_buffer_store;
    uint64_t depth_buffer_store_stride;
    uint64_t depth_buffer_partial;
    uint64_t depth_buffer_partial_stride;
    uint64_t depth_meta_buffer_load;
    uint64_t depth_meta_buffer_load_stride;
    uint64_t depth_meta_buffer_store;
};

struct tracked_binding {
    int fd;
    struct drm_asahi_gem_bind request;
};

_Static_assert(sizeof(struct drm_asahi_gem_bind) == 48,
               "Asahi GEM_BIND ABI mismatch");
_Static_assert(sizeof(struct drm_gem_close) == 8,
               "DRM GEM_CLOSE ABI mismatch");
_Static_assert(sizeof(struct drm_asahi_gem_create) == 32,
               "Asahi GEM_CREATE ABI mismatch");
_Static_assert(sizeof(struct drm_asahi_queue_destroy) == 16,
               "Asahi QUEUE_DESTROY ABI mismatch");
_Static_assert(sizeof(struct drm_asahi_command) == 56,
               "Asahi command ABI mismatch");
_Static_assert(sizeof(struct drm_asahi_submit) == 56,
               "Asahi submit ABI mismatch");
_Static_assert(sizeof(struct drm_asahi_cmd_render_prefix) == 168,
               "Asahi render ABI mismatch");

static int (*next_ioctl)(int, ioctl_request_t, ...);
static struct tracked_binding bindings[MAX_TRACKED_BINDINGS];
static size_t binding_count;
static ioctl_request_t gem_bind_request;
static int fault_done;
static int lifetime_fd = -1;
static uint32_t lifetime_closed_handle;
static struct drm_asahi_gem_bind lifetime_replacement;
static int lifetime_reuse_pending;

#define DRM_IOCTL_GEM_CLOSE_REQUEST                                         \
    ((ioctl_request_t)_IOW(DRM_IOCTL_TYPE, DRM_GEM_CLOSE_NR,                \
                           struct drm_gem_close))
#define DRM_IOCTL_ASAHI_GEM_CREATE_REQUEST                                  \
    ((ioctl_request_t)_IOWR(DRM_IOCTL_TYPE, DRM_ASAHI_GEM_CREATE_NR,        \
                            struct drm_asahi_gem_create))
#define DRM_IOCTL_ASAHI_GEM_BIND_REQUEST                                    \
    ((ioctl_request_t)_IOW(DRM_IOCTL_TYPE, DRM_ASAHI_GEM_BIND_NR,           \
                           struct drm_asahi_gem_bind))
#define DRM_IOCTL_ASAHI_QUEUE_DESTROY_REQUEST                               \
    ((ioctl_request_t)_IOW(DRM_IOCTL_TYPE, DRM_ASAHI_QUEUE_DESTROY_NR,      \
                           struct drm_asahi_queue_destroy))

static const char *fault_mode(void)
{
    const char *mode = getenv("VINIX_AGX_FAULT");
    return mode ? mode : "";
}

static int call_next(int fd, ioctl_request_t request, void *argument)
{
    if (!next_ioctl)
        next_ioctl = (int (*)(int, ioctl_request_t, ...))dlsym(RTLD_NEXT,
                                                               "ioctl");
    if (!next_ioctl) {
        errno = ENOSYS;
        return -1;
    }
    return next_ioctl(fd, request, argument);
}

static void remember_binding(int fd, const struct drm_asahi_gem_bind *request)
{
    if (binding_count >= MAX_TRACKED_BINDINGS)
        return;
    bindings[binding_count].fd = fd;
    bindings[binding_count].request = *request;
    binding_count++;
}

static void forget_range(int fd, uint32_t vm_id, uint64_t address,
                         uint64_t range)
{
    for (size_t index = binding_count; index-- > 0;) {
        const struct tracked_binding *binding = &bindings[index];
        if (binding->fd == fd && binding->request.vm_id == vm_id &&
            binding->request.addr == address &&
            binding->request.range == range) {
            bindings[index] = bindings[--binding_count];
            return;
        }
    }
}

static void forget_handle(int fd, uint32_t vm_id, uint32_t handle)
{
    for (size_t index = binding_count; index-- > 0;) {
        const struct tracked_binding *binding = &bindings[index];
        if (binding->fd == fd && binding->request.vm_id == vm_id &&
            binding->request.handle == handle)
            bindings[index] = bindings[--binding_count];
    }
}

static struct tracked_binding *find_binding(int fd, uint64_t address)
{
    for (size_t index = binding_count; index-- > 0;) {
        struct tracked_binding *binding = &bindings[index];
        uint64_t start = binding->request.addr;
        if (binding->fd == fd && address >= start &&
            address - start < binding->request.range)
            return binding;
    }
    return NULL;
}

static struct drm_asahi_gem_bind unbind_request(
    const struct drm_asahi_gem_bind *binding)
{
    struct drm_asahi_gem_bind request = {
        .op = ASAHI_BIND_OP_UNBIND,
        .vm_id = binding->vm_id,
        .range = binding->range,
        .addr = binding->addr,
    };
    return request;
}

static void inject_after_bind(int fd,
                              const struct drm_asahi_gem_bind *binding)
{
    const char *mode = fault_mode();
    if (fault_done)
        return;

    if (strcmp(mode, "overlap") == 0) {
        errno = 0;
        int result = call_next(fd, gem_bind_request, (void *)binding);
        int error = errno;
        if (result == -1 && error == EBUSY)
            fprintf(stderr,
                    "vinix-agx-fault: overlapping Mesa binding rejected\n");
        else
            fprintf(stderr,
                    "vinix-agx-fault: overlap check failed result=%d errno=%d\n",
                    result, error);
        fault_done = 1;
    } else if (strcmp(mode, "rebind") == 0) {
        struct drm_asahi_gem_bind unbind = unbind_request(binding);
        int unbind_result = call_next(fd, gem_bind_request, &unbind);
        int bind_result = unbind_result == 0
                              ? call_next(fd, gem_bind_request, (void *)binding)
                              : -1;
        if (unbind_result == 0 && bind_result == 0)
            fprintf(stderr,
                    "vinix-agx-fault: Mesa binding unbound and reused\n");
        else
            fprintf(stderr,
                    "vinix-agx-fault: binding reuse failed unbind=%d bind=%d\n",
                    unbind_result, bind_result);
        fault_done = 1;
    }
}

static uint64_t depth_metadata_store(const struct drm_asahi_submit *submit)
{
    if (!submit || !submit->commands ||
        submit->command_count > MAX_SUBMISSION_COMMANDS)
        return 0;

    const struct drm_asahi_command *commands =
        (const struct drm_asahi_command *)(uintptr_t)submit->commands;
    for (uint32_t index = 0; index < submit->command_count; index++) {
        const struct drm_asahi_command *command = &commands[index];
        if (command->cmd_type != ASAHI_CMD_RENDER || !command->cmd_buffer ||
            command->cmd_buffer_size <
                sizeof(struct drm_asahi_cmd_render_prefix))
            continue;
        const struct drm_asahi_cmd_render_prefix *render =
            (const struct drm_asahi_cmd_render_prefix *)(uintptr_t)
                command->cmd_buffer;
        if (render->depth_meta_buffer_store)
            return render->depth_meta_buffer_store;
    }
    return 0;
}

static void lifetime_failure(const char *operation, int result, int error)
{
    fprintf(stderr,
            "vinix-agx-fault: lifetime check failed at %s result=%d errno=%d\n",
            operation, result, error);
    fault_done = 1;
    fflush(stderr);
    _Exit(87);
}

static void require_busy(const char *operation, int result, int error)
{
    if (result != -1 || error != EBUSY)
        lifetime_failure(operation, result, error);
}

static void inject_lifetime_after_submit(
    int fd, const struct drm_asahi_submit *submit,
    const struct drm_asahi_gem_bind *original)
{
    struct drm_gem_close close_request = {.handle = original->handle};
    errno = 0;
    int result = call_next(fd, DRM_IOCTL_GEM_CLOSE_REQUEST, &close_request);
    if (result != 0)
        lifetime_failure("GEM_CLOSE", result, errno);
    fprintf(stderr,
            "vinix-agx-fault: referenced GEM handle closed while job pending\n");

    struct drm_asahi_gem_create create = {.size = original->range};
    errno = 0;
    result = call_next(fd, DRM_IOCTL_ASAHI_GEM_CREATE_REQUEST, &create);
    if (result != 0 || create.handle == 0)
        lifetime_failure("replacement GEM_CREATE", result, errno);

    struct drm_asahi_gem_bind replacement = {
        .op = ASAHI_BIND_OP_BIND,
        .flags = ASAHI_BIND_READ | ASAHI_BIND_WRITE,
        .handle = create.handle,
        .vm_id = original->vm_id,
        .range = original->range,
        .addr = original->addr,
    };
    errno = 0;
    result = call_next(fd, DRM_IOCTL_ASAHI_GEM_BIND_REQUEST, &replacement);
    require_busy("early GPU VA reuse", result, errno);
    fprintf(stderr,
            "vinix-agx-fault: GPU VA reuse blocked while job pending\n");

    struct drm_asahi_gem_bind unbind = unbind_request(original);
    errno = 0;
    result = call_next(fd, DRM_IOCTL_ASAHI_GEM_BIND_REQUEST, &unbind);
    require_busy("in-flight GEM unbind", result, errno);
    fprintf(stderr, "vinix-agx-fault: in-flight unbind rejected\n");

    struct drm_asahi_queue_destroy destroy = {.queue_id = submit->queue_id};
    errno = 0;
    result = call_next(fd, DRM_IOCTL_ASAHI_QUEUE_DESTROY_REQUEST, &destroy);
    require_busy("in-flight queue destroy", result, errno);
    fprintf(stderr,
            "vinix-agx-fault: in-flight queue destroy rejected\n");

    /* Return to Mesa so its genuine fence wait drives the cooperative kernel
     * scheduler.  The first ioctl after that wait is our retirement point. */
    lifetime_fd = fd;
    lifetime_closed_handle = original->handle;
    lifetime_replacement = replacement;
    lifetime_reuse_pending = 1;
}

static void try_retired_reuse(int fd)
{
    if (!lifetime_reuse_pending || fd != lifetime_fd)
        return;
    errno = 0;
    int result = call_next(fd, DRM_IOCTL_ASAHI_GEM_BIND_REQUEST,
                           &lifetime_replacement);
    if (result == 0) {
        fprintf(stderr,
                "vinix-agx-fault: GPU VA reused after retirement\n");
        lifetime_reuse_pending = 0;
        fault_done = 1;
    } else if (errno != EBUSY) {
        lifetime_failure("retired GPU VA reuse", result, errno);
    }
}

static int inject_submit_fault(int fd, ioctl_request_t request,
                               struct drm_asahi_submit *submit)
{
    const char *mode = fault_mode();
    int lifetime = strcmp(mode, "lifetime") == 0;
    if (fault_done || (!lifetime && strcmp(mode, "unbind") != 0 &&
                       strcmp(mode, "readonly") != 0))
        return call_next(fd, request, submit);

    uint64_t address = depth_metadata_store(submit);
    if (!address)
        return call_next(fd, request, submit);
    struct tracked_binding *tracked = find_binding(fd, address);
    if (!tracked) {
        fprintf(stderr,
                "vinix-agx-fault: referenced depth metadata binding not found\n");
        fault_done = 1;
        return call_next(fd, request, submit);
    }

    struct drm_asahi_gem_bind original = tracked->request;
    if (lifetime) {
        errno = 0;
        int result = call_next(fd, request, submit);
        int submit_errno = errno;
        if (result != 0)
            lifetime_failure("valid Mesa submit", result, submit_errno);
        inject_lifetime_after_submit(fd, submit, &original);
        errno = submit_errno;
        return result;
    }

    struct drm_asahi_gem_bind unbind = unbind_request(&original);
    if (call_next(fd, gem_bind_request, &unbind) != 0) {
        fprintf(stderr,
                "vinix-agx-fault: referenced metadata unbind failed errno=%d\n",
                errno);
        fault_done = 1;
        return call_next(fd, request, submit);
    }

    if (strcmp(mode, "readonly") == 0) {
        struct drm_asahi_gem_bind readonly = original;
        readonly.flags = (original.flags & ~ASAHI_BIND_WRITE) |
                         ASAHI_BIND_READ;
        if (call_next(fd, gem_bind_request, &readonly) != 0) {
            fprintf(stderr,
                    "vinix-agx-fault: read-only metadata rebind failed errno=%d\n",
                    errno);
            call_next(fd, gem_bind_request, &original);
            fault_done = 1;
            return call_next(fd, request, submit);
        }
        fprintf(stderr,
                "vinix-agx-fault: referenced depth metadata made read-only\n");
    } else {
        fprintf(stderr,
                "vinix-agx-fault: referenced depth metadata unbound\n");
    }

    errno = 0;
    int result = call_next(fd, request, submit);
    int submit_errno = errno;
    int rejected = result == -1 && submit_errno == EINVAL;
    if (rejected)
        fprintf(stderr,
                "vinix-agx-fault: invalid Mesa resource submission rejected\n");
    else
        fprintf(stderr,
                "vinix-agx-fault: invalid submission accepted result=%d errno=%d\n",
                result, submit_errno);

    /* Mesa waits on its expected fence after a rejected submit. Exit here so
     * the VM test is bounded and let fd teardown clean the deliberately
     * damaged mapping state.  A distinct status keeps unexpected acceptance
     * distinguishable even though the transcript is the primary assertion. */
    fault_done = 1;
    fflush(stderr);
    _Exit(rejected ? 86 : 87);
}

int ioctl(int fd, ioctl_request_t request, ...)
{
    va_list arguments;
    va_start(arguments, request);
    void *argument = va_arg(arguments, void *);
    va_end(arguments);

    if (DRM_IOCTL_REQUEST_TYPE(request) != DRM_IOCTL_TYPE)
        return call_next(fd, request, argument);

    if (DRM_IOCTL_NR(request) == DRM_GEM_CLOSE_NR && fault_done &&
        fd == lifetime_fd && argument &&
        ((struct drm_gem_close *)argument)->handle == lifetime_closed_handle)
        return 0;

    if (DRM_IOCTL_NR(request) == DRM_ASAHI_GEM_BIND_NR) {
        struct drm_asahi_gem_bind *binding = argument;
        gem_bind_request = request;
        int result = call_next(fd, request, binding);
        if (result != 0 || !binding)
            return result;
        if (binding->op == ASAHI_BIND_OP_BIND) {
            remember_binding(fd, binding);
            inject_after_bind(fd, binding);
        } else if (binding->op == ASAHI_BIND_OP_UNBIND) {
            forget_range(fd, binding->vm_id, binding->addr, binding->range);
        } else if (binding->op == ASAHI_BIND_OP_UNBIND_ALL) {
            forget_handle(fd, binding->vm_id, binding->handle);
        }
        return result;
    }

    if (DRM_IOCTL_NR(request) == DRM_ASAHI_SUBMIT_NR)
        return inject_submit_fault(fd, request, argument);

    int result = call_next(fd, request, argument);
    int saved_errno = errno;
    try_retired_reuse(fd);
    errno = saved_errno;
    return result;
}
