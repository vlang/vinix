/* SPDX-License-Identifier: GPL-2.0-or-later */
#ifndef VINIX_LINUXKPI_SMP_MASKS_V_PRIMITIVES_H
#define VINIX_LINUXKPI_SMP_MASKS_V_PRIMITIVES_H
#include <stdbool.h>
#include <stdint.h>

/* The original-layout contract independently checks these native ABI limits. */
#define VKM_CPU_LIMIT 256U
#define VKM_MASK_WORDS 4U

/* Synchronous borrowed views of permanent original storage. Only the sole
 * boot publisher writes them, before any compatibility consumer can run.
 * Kinds: 0 possible, 1 online, 2 present, 3 active, 4 dying; others return NULL.
 * The online view points to the genuine atomic_t.counter field. */
void *vkm_mask_storage(uint32_t kind);
void *vkm_cpu_ids_storage(void);
void *vkm_online_storage(void);

/* One boot publication, with no reset, concurrent constructor or hotplug.
 * Invalid count is rejected before the already-ready check or any write.
 * Internal checked queries acquire readiness. Original Linux inline readers
 * do not: native integration must finish publication before exposing users. */
int32_t vkm_cpu_masks_bootstrap(uint32_t count);
bool vkm_cpu_masks_ready(void);
bool vkm_mask_has(uint32_t kind, uint32_t cpu);
uint32_t vkm_mask_weight(uint32_t kind);
bool vkm_mask_of_has(uint32_t selected, uint32_t cpu);
bool vkm_all_has(uint32_t cpu);
uint32_t vkm_online_count(void);
uint32_t vkm_cpu_ids(void);

/* Compiler atomics, not maintained C implementations. */
#define vkms_load32(pointer, order) __atomic_load_n((pointer), (order))
#define vkms_store32(pointer, value, order) \
	__atomic_store_n((pointer), (value), (order))
#endif
