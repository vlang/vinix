// SPDX-License-Identifier: GPL-2.0-or-later
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <vulkan/vulkan.h>
#define VK(call)                                                               \
  do {                                                                         \
    VkResult r = (call);                                                       \
    if (r != VK_SUCCESS) {                                                     \
      fprintf(stderr, "VENUS FAIL %s = %d\n", #call, r);                       \
      return 1;                                                                \
    }                                                                          \
  } while (0)
static int gpu_fill(void) {
  VkInstance instance;
  VkApplicationInfo app = {.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
                           .pApplicationName = "Vinix Venus smoke",
                           .apiVersion = VK_API_VERSION_1_1};
  VkInstanceCreateInfo ci = {.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
                             .pApplicationInfo = &app};
  VK(vkCreateInstance(&ci, 0, &instance));
  uint32_t n = 1;
  VkPhysicalDevice physical;
  VK(vkEnumeratePhysicalDevices(instance, &n, &physical));
  if (!n)
    return 2;
  VkPhysicalDeviceProperties properties;
  vkGetPhysicalDeviceProperties(physical, &properties);
  printf("VENUS GPU: %s\n", properties.deviceName);
  fflush(stdout);
  uint32_t count = 0;
  vkGetPhysicalDeviceQueueFamilyProperties(physical, &count, 0);
  VkQueueFamilyProperties *families = calloc(count, sizeof(*families));
  vkGetPhysicalDeviceQueueFamilyProperties(physical, &count, families);
  uint32_t q = 0;
  while (q < count && !(families[q].queueFlags & VK_QUEUE_GRAPHICS_BIT))
    q++;
  free(families);
  if (q == count)
    return 3;
  float priority = 1;
  VkDeviceQueueCreateInfo qc = {.sType =
                                    VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
                                .queueFamilyIndex = q,
                                .queueCount = 1,
                                .pQueuePriorities = &priority};
  VkDeviceCreateInfo dc = {.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
                           .queueCreateInfoCount = 1,
                           .pQueueCreateInfos = &qc};
  VkDevice device;
  VK(vkCreateDevice(physical, &dc, 0, &device));
  VkQueue queue;
  vkGetDeviceQueue(device, q, 0, &queue);
  VkBufferCreateInfo bc = {.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
                           .size = 65536,
                           .usage = VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                           .sharingMode = VK_SHARING_MODE_EXCLUSIVE};
  VkBuffer buffer;
  VK(vkCreateBuffer(device, &bc, 0, &buffer));
  VkMemoryRequirements req;
  vkGetBufferMemoryRequirements(device, buffer, &req);
  VkPhysicalDeviceMemoryProperties mp;
  vkGetPhysicalDeviceMemoryProperties(physical, &mp);
  uint32_t m = 0;
  while (m < mp.memoryTypeCount && (!(req.memoryTypeBits & (1u << m)) ||
                                    (mp.memoryTypes[m].propertyFlags &
                                     (VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
                                      VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)) !=
                                        (VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT |
                                         VK_MEMORY_PROPERTY_HOST_COHERENT_BIT)))
    m++;
  if (m == mp.memoryTypeCount)
    return 4;
  VkMemoryAllocateInfo ma = {.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
                             .allocationSize = req.size,
                             .memoryTypeIndex = m};
  VkDeviceMemory memory;
  VK(vkAllocateMemory(device, &ma, 0, &memory));
  VK(vkBindBufferMemory(device, buffer, memory, 0));
  VkCommandPoolCreateInfo pc = {.sType =
                                    VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
                                .queueFamilyIndex = q};
  VkCommandPool pool;
  VK(vkCreateCommandPool(device, &pc, 0, &pool));
  VkCommandBufferAllocateInfo ca = {
      .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
      .commandPool = pool,
      .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY,
      .commandBufferCount = 1};
  VkCommandBuffer command;
  VK(vkAllocateCommandBuffers(device, &ca, &command));
  VkCommandBufferBeginInfo begin = {
      .sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
  VK(vkBeginCommandBuffer(command, &begin));
  vkCmdFillBuffer(command, buffer, 0, VK_WHOLE_SIZE, 0x52a17e3d);
  VK(vkEndCommandBuffer(command));
  VkFenceCreateInfo fc = {.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
  VkFence fence;
  VK(vkCreateFence(device, &fc, 0, &fence));
  VkSubmitInfo submit = {.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
                         .commandBufferCount = 1,
                         .pCommandBuffers = &command};
  VK(vkQueueSubmit(queue, 1, &submit, fence));
  VK(vkWaitForFences(device, 1, &fence, VK_TRUE, 5000000000ull));
  vkDestroyFence(device, fence, 0);
  VK(vkQueueWaitIdle(queue));
  uint32_t *ptr;
  VK(vkMapMemory(device, memory, 0, VK_WHOLE_SIZE, 0, (void **)&ptr));
  for (unsigned i = 0; i < 65536 / 4; i++)
    if (ptr[i] != 0x52a17e3d) {
      printf("VENUS FAIL pixel %u = %x\n", i, ptr[i]);
      return 5;
    }
  vkUnmapMemory(device, memory);
  vkDestroyCommandPool(device, pool, 0);
  vkDestroyBuffer(device, buffer, 0);
  vkFreeMemory(device, memory, 0);
  vkDestroyDevice(device, 0);
  vkDestroyInstance(instance, 0);
  return 0;
}
#include "measure.h"

static void slab_snapshot(const char *phase) {
  FILE *f = fopen("/proc/slabinfo", "r");
  if (!f)
    return;
  char line[512];
  while (fgets(line, sizeof(line), f)) {
    if (strncmp(line, "size-", 5) == 0)
      printf("VENUS-SLAB %s %s", phase, line);
  }
  fclose(f);
  fflush(stdout);
}
int main(void) {
  // Warm renderer/driver caches before measuring repeated instance, blob,
  // mapping, GPU-fence and context creation/destruction.
  for (unsigned i = 0; i < 4; i++)
    if (gpu_fill())
      return 1;
  // Allow deferred filesystem/resource reclamation to finish on both sides
  // of the measurement, rather than counting its grace period as a leak.
  usleep(500000);
  start_tracking();
  slab_snapshot("before");
  for (unsigned i = 0; i < 32; i++)
    if (gpu_fill())
      return 1;
  usleep(500000);
  slab_snapshot("after");
  dump_sites("venus-fill");
  puts("VINIX_VENUS_GPU_FILL_PASS");
  return 0;
}
