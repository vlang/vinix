/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_SCHED_MM_FIXTURE_CONTRACT_H
#define VINIX_SCHED_MM_FIXTURE_CONTRACT_H
#include <stdint.h>
typedef uint64_t u64;
#include "linuxkpi_common_v_contract.h"
#define u64 vkh_linux_u64
#include <linux/kobject.h>
#undef u64

_Static_assert(CONFIG_BASE_FULL == 1 && CONFIG_BASE_SMALL == 0,
               "native profile requires BASE_FULL=1 and BASE_SMALL=0");
#if defined(CONFIG_SYSFS) || defined(CONFIG_KERNFS) || defined(CONFIG_DEBUG_KOBJECT_RELEASE) || \
    defined(CONFIG_MEMCG) || defined(CONFIG_MEMBARRIER) || defined(CONFIG_PREEMPT_RT) || \
    defined(CONFIG_LOCKDEP) || defined(CONFIG_DEBUG_LOCK_ALLOC)
#error "unsupported scheduler/MM or published kobject configuration"
#endif

#define SMM_TYPE(expression, type) \
    _Static_assert(__builtin_types_compatible_p(__typeof__(expression), type), "original ABI: " #expression)
SMM_TYPE(&in_vfork, bool (*)(struct task_struct *));
SMM_TYPE(&current_gfp_context, gfp_t (*)(gfp_t));
SMM_TYPE(&memalloc_noio_save, unsigned int (*)(void));
SMM_TYPE(&memalloc_noio_restore, void (*)(unsigned int));
SMM_TYPE(&memalloc_nofs_save, unsigned int (*)(void));
SMM_TYPE(&memalloc_nofs_restore, void (*)(unsigned int));
SMM_TYPE(&memalloc_noreclaim_save, unsigned int (*)(void));
SMM_TYPE(&memalloc_noreclaim_restore, void (*)(unsigned int));
SMM_TYPE(&memalloc_pin_save, unsigned int (*)(void));
SMM_TYPE(&memalloc_pin_restore, void (*)(unsigned int));
SMM_TYPE(&kobject_init, void (*)(struct kobject *, const struct kobj_type *));
SMM_TYPE(&kobject_get, struct kobject *(*)(struct kobject *));
SMM_TYPE(&kobject_get_unless_zero, struct kobject *(*)(struct kobject *));
SMM_TYPE(&kobject_put, void (*)(struct kobject *));
SMM_TYPE(&kobject_set_name, int (*)(struct kobject *, const char *, ...));
SMM_TYPE(&kobject_set_name_vargs, int (*)(struct kobject *, const char *, va_list));
SMM_TYPE(((struct kobj_type *)0)->release, void (*)(struct kobject *));
SMM_TYPE(((struct kobj_type *)0)->sysfs_ops, const struct sysfs_ops *);
SMM_TYPE(((struct kobj_type *)0)->default_groups, const struct attribute_group **);
SMM_TYPE(((struct kobj_type *)0)->child_ns_type, const struct kobj_ns_type_operations *(*)(const struct kobject *));
SMM_TYPE(((struct kobj_type *)0)->namespace, const void *(*)(const struct kobject *));
SMM_TYPE(((struct kobj_type *)0)->get_ownership, void (*)(const struct kobject *, kuid_t *, kgid_t *));
SMM_TYPE(&mm_update_next_owner, void (*)(struct mm_struct *));
SMM_TYPE(&set_active_memcg, struct mem_cgroup *(*)(struct mem_cgroup *));
SMM_TYPE(&membarrier_exec_mmap, void (*)(struct mm_struct *));
SMM_TYPE(&fs_reclaim_acquire, void (*)(gfp_t));
#undef SMM_TYPE

/* Original records/offsets only; no duplicated layout or executable algorithm. */
static const unsigned long vinix_sched_mm_original_layout[] __attribute__((used)) = {
    sizeof(struct kobject), _Alignof(struct kobject), sizeof(struct kobj_type),
    _Alignof(struct kobj_type), sizeof(struct kset), _Alignof(struct kset),
    offsetof(struct kobject, name), offsetof(struct kobject, entry),
    offsetof(struct kobject, parent), offsetof(struct kobject, kset),
    offsetof(struct kobject, ktype), offsetof(struct kobject, sd),
    offsetof(struct kobject, kref), offsetof(struct kset, kobj)
};
#endif
