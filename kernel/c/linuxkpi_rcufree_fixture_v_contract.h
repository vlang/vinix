/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_RCUFREE_FIXTURE_V_CONTRACT_H
#define VINIX_LINUXKPI_RCUFREE_FIXTURE_V_CONTRACT_H
#include "linuxkpi_rcu_fixture_v_contract.h"
#include "linuxkpi_rcufree_fixture_v_primitives.h"
#include <linux/slab.h>
void kvfree(const void *);
/* Layout metadata only. Runtime construction, validation and ownership are V. */
struct vkrf_zero { struct rcu_head head; uint64_t magic; };
struct vkrf_middle { uint64_t magic; uint64_t padding; struct rcu_head head; };
struct vkrf_boundary { uint64_t magic; uint8_t padding[4080]; struct rcu_head head; };
_Static_assert(offsetof(struct vkrf_zero, head) == 0 &&
               offsetof(struct vkrf_middle, head) == 16 &&
               offsetof(struct vkrf_boundary, head) == 4088 &&
               sizeof(struct vkrf_boundary) == 4104,
               "deferred-free fixture covers zero, interior and last aligned offset");
/* Symbol adapters retain the unchanged original variadic/member macros. */
#define vkrf_kfree_zero(p) kfree_rcu((p), head)
#define vkrf_kvfree_middle(p) kvfree_rcu((p), head)
#define vkrf_kvfree_boundary(p) kvfree_rcu((p), head)
#endif
