/* SPDX-License-Identifier: GPL-2.0-only */
/* Link the unchanged Linux 6.6.157 i915_config.c. This is timeout policy;
 * fence callbacks, submission, timers and reservation ownership are separate. */
#include <i915_config.h>
#include <assert.h>
#include <linux/jiffies.h>
#include <i915_utils.h>

_Static_assert(HZ == 1000, "Vinix timeout fixture requires the native tick rate");
_Static_assert(CONFIG_DRM_I915_FENCE_TIMEOUT == 10000,
               "Use the pinned DRM_I915_FENCE_TIMEOUT Kconfig default");

static unsigned int host_i915_config_devices, host_i915_config_contexts;
static const struct drm_i915_private *host_i915_config_device(void)
{
    host_i915_config_devices++;
    return NULL;
}
static u64 host_i915_config_context(u64 value)
{
    host_i915_config_contexts++;
    return value;
}

static void i915_config_tests(void)
{
    /* Context zero deliberately has no supplementary foreign-fence timeout.
     * Every nonzero 64-bit context receives 10000 ticks plus the extra tick
     * supplied by the genuine msecs_to_jiffies_timeout inline. */
    const u64 contexts[] = {0, 1, 2, 0xffffffffULL, 1ULL << 32, 1ULL << 63, U64_MAX};
    const unsigned long ticks[] = {0, 10001, 10001, 10001, 10001, 10001, 10001};
    host_i915_config_devices = host_i915_config_contexts = 0;
    for (unsigned int i = 0; i < ARRAY_SIZE(contexts); i++) {
        assert(i915_fence_context_timeout(host_i915_config_device(),
                    host_i915_config_context(contexts[i])) == ticks[i]);
        assert(host_i915_config_devices == i + 1 && host_i915_config_contexts == i + 1);
    }
    /* The original public inline selects U64_MAX, rather than the zero
     * context exception. Its opaque device argument is not dereferenced. */
    assert(i915_fence_timeout(host_i915_config_device()) == 10001);
    assert(host_i915_config_devices == ARRAY_SIZE(contexts) + 1);

    const unsigned int milliseconds[] = {0, 1, 999, 1000, 10000, INT_MAX, UINT_MAX};
    const unsigned long rounded[] = {1, 2, 1000, 1001, 10001,
                                     2147483648UL, MAX_JIFFY_OFFSET};
    for (unsigned int i = 0; i < ARRAY_SIZE(milliseconds); i++) {
        volatile unsigned int runtime_value = milliseconds[i];
        assert(msecs_to_jiffies_timeout(runtime_value) == rounded[i]);
    }
    assert(msecs_to_jiffies_timeout(0) == 1);
    assert(msecs_to_jiffies_timeout(10000) == 10001);
    assert(msecs_to_jiffies_timeout(UINT_MAX) == MAX_JIFFY_OFFSET);
}
