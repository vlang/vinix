/* Lavapipe descriptor-set binding check for Dota 2's Vulkan renderer.
 *
 * With VK_EXT_graphics_pipeline_library enabled, vkCmdBindDescriptorSets may
 * pass VK_NULL_HANDLE sets, and an independent-set pipeline layout may omit a
 * set layout. Dota's local map binds such sets for compute; Debian's Mesa
 * 22.3.6 Lavapipe then reads set->layout from the null set.
 *
 * Every mode binds a storage buffer in sets 0 and 2 around set 1, then a
 * compute shader stores a marker through set 2, binding 0. Shaders reserve
 * slots for every set layout before their own set, so only set 2's buffer
 * may change; a misplaced binding leaves it zero or writes another buffer.
 *
 * Link to the staged x86-64 glibc and Vulkan loader directly, like
 * tests/dota2/env-test.c: clang's freestanding headers and Mesa's Vulkan
 * headers only, with manual libc prototypes.
 */
#include <stdarg.h>
#include <vulkan/vulkan.h>

extern int strcmp(const char *, const char *);
extern int vsnprintf(char *, unsigned long, const char *, va_list);
extern long write(int, const void *, unsigned long);
extern void exit(int);
extern unsigned int alarm(unsigned int);

__asm__(".text\n.global _start\n_start:\n"
        "xor %ebp,%ebp\nmov %rdx,%r9\npop %rsi\nmov %rsp,%rdx\n"
        "and $-16,%rsp\npush %rax\npush %rsp\nxor %r8d,%r8d\nxor %ecx,%ecx\n"
        "lea main(%rip),%rdi\ncall *__libc_start_main@GOTPCREL(%rip)\nhlt\n");

enum { marker = 0x56494e58, sets = 3, watchdog_seconds = 150 };

/* SPIR-V 1.0 for:
 *   layout(local_size_x = 1) in;
 *   layout(set = 2, binding = 0) buffer Out { uint value; } result;
 *   void main() { result.value = 0x56494e58u; }
 */
static const uint32_t shader[] = {
    0x07230203, 0x00010000, 0, 14, 0,
    0x00020011, 1,                                  /* OpCapability Shader */
    0x0003000e, 0, 1,                               /* OpMemoryModel Logical GLSL450 */
    0x0005000f, 5, 1, 0x6e69616d, 0,                /* OpEntryPoint GLCompute %1 "main" */
    0x00060010, 1, 17, 1, 1, 1,                     /* OpExecutionMode %1 LocalSize 1 1 1 */
    0x00030047, 5, 3,                               /* OpDecorate %5 BufferBlock */
    0x00050048, 5, 0, 35, 0,                        /* OpMemberDecorate %5 0 Offset 0 */
    0x00040047, 11, 34, 2,                          /* OpDecorate %11 DescriptorSet 2 */
    0x00040047, 11, 33, 0,                          /* OpDecorate %11 Binding 0 */
    0x00020013, 2,                                  /* %2 = OpTypeVoid */
    0x00030021, 3, 2,                               /* %3 = OpTypeFunction %2 */
    0x00040015, 4, 32, 0,                           /* %4 = OpTypeInt 32 0 */
    0x0003001e, 5, 4,                               /* %5 = OpTypeStruct %4 */
    0x00040020, 6, 2, 5,                            /* %6 = OpTypePointer Uniform %5 */
    0x00040020, 7, 2, 4,                            /* %7 = OpTypePointer Uniform %4 */
    0x00040015, 8, 32, 1,                           /* %8 = OpTypeInt 32 1 */
    0x0004002b, 8, 9, 0,                            /* %9 = OpConstant %8 0 */
    0x0004002b, 4, 10, marker,                      /* %10 = OpConstant %4 marker */
    0x0004003b, 6, 11, 2,                           /* %11 = OpVariable %6 Uniform */
    0x00050036, 2, 1, 0, 3,                         /* %1 = OpFunction %2 None %3 */
    0x000200f8, 12,                                 /* %12 = OpLabel */
    0x00050041, 7, 13, 11, 9,                       /* %13 = OpAccessChain %7 %11 %9 */
    0x0003003e, 13, 10,                             /* OpStore %13 %10 */
    0x000100fd,                                     /* OpReturn */
    0x00010038,                                     /* OpFunctionEnd */
};

static void report(const char *format, ...)
{
    /* Unbuffered: a crashing driver must not discard earlier progress. */
    char line[256];
    va_list arguments;
    va_start(arguments, format);
    int length = vsnprintf(line, sizeof line, format, arguments);
    va_end(arguments);
    if (length > 0) write(1, line, length < (int)sizeof line ? (unsigned long)length : sizeof line - 1);
}

static void checked(VkResult result, const char *operation)
{
    if (result == VK_SUCCESS) return;
    report("VINIX-DOTA2-LVP-FAIL: %s result=%d\n", operation, result);
    exit(2);
}
#define CHECK(call) checked(call, #call)

static int has_extension(VkPhysicalDevice physical, const char *name)
{
    static VkExtensionProperties properties[512];
    uint32_t count = 512;
    CHECK(vkEnumerateDeviceExtensionProperties(physical, 0, &count, properties));
    for (uint32_t i = 0; i < count; i++)
        if (!strcmp(properties[i].extensionName, name)) return 1;
    return 0;
}

int main(int argc, char **argv)
{
    alarm(watchdog_seconds);
    const char *mode = argc == 2 ? argv[1] : "";
    int null_set = !strcmp(mode, "null-set");
    int absent_layout = !strcmp(mode, "absent-layout");
    int absent_first_set = !strcmp(mode, "absent-first-set");
    if (!null_set && !absent_layout && !absent_first_set && strcmp(mode, "bound")) {
        report("VINIX-DOTA2-LVP-FAIL: unknown mode\n");
        return 2;
    }
    report("VINIX-DOTA2-LVP-START: %s\n", mode);

    VkApplicationInfo application = {.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO,
        .pApplicationName = "Vinix Lavapipe descriptor sets", .apiVersion = VK_API_VERSION_1_3};
    VkInstanceCreateInfo instance_info = {.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
        .pApplicationInfo = &application};
    VkInstance instance;
    CHECK(vkCreateInstance(&instance_info, 0, &instance));
    VkPhysicalDevice physical;
    uint32_t physical_count = 1;
    VkResult enumerated = vkEnumeratePhysicalDevices(instance, &physical_count, &physical);
    if ((enumerated != VK_SUCCESS && enumerated != VK_INCOMPLETE) || !physical_count) {
        report("VINIX-DOTA2-LVP-FAIL: no Vulkan device\n");
        return 2;
    }
    VkPhysicalDeviceProperties properties;
    vkGetPhysicalDeviceProperties(physical, &properties);
    report("VINIX-DOTA2-LVP-DEVICE: %s\n", properties.deviceName);
    VkPhysicalDeviceGraphicsPipelineLibraryFeaturesEXT library_feature = {
        .sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_GRAPHICS_PIPELINE_LIBRARY_FEATURES_EXT};
    VkPhysicalDeviceFeatures2 features = {.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2,
        .pNext = &library_feature};
    vkGetPhysicalDeviceFeatures2(physical, &features);
    /* The feature is what makes null sets and set layouts valid API usage. */
    if (properties.deviceType != VK_PHYSICAL_DEVICE_TYPE_CPU || !library_feature.graphicsPipelineLibrary ||
        !has_extension(physical, VK_EXT_GRAPHICS_PIPELINE_LIBRARY_EXTENSION_NAME) ||
        !has_extension(physical, VK_KHR_PIPELINE_LIBRARY_EXTENSION_NAME)) {
        report("VINIX-DOTA2-LVP-FAIL: graphics pipeline libraries unavailable\n");
        return 2;
    }

    VkQueueFamilyProperties families[16];
    uint32_t family_count = 16, family = 0;
    vkGetPhysicalDeviceQueueFamilyProperties(physical, &family_count, families);
    while (family < family_count && !(families[family].queueFlags & VK_QUEUE_COMPUTE_BIT)) family++;
    if (family == family_count) {
        report("VINIX-DOTA2-LVP-FAIL: no compute queue\n");
        return 2;
    }
    float priority = 1;
    VkDeviceQueueCreateInfo queue_info = {.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO,
        .queueFamilyIndex = family, .queueCount = 1, .pQueuePriorities = &priority};
    const char *extensions[] = {VK_EXT_GRAPHICS_PIPELINE_LIBRARY_EXTENSION_NAME,
                                VK_KHR_PIPELINE_LIBRARY_EXTENSION_NAME};
    VkDeviceCreateInfo device_info = {.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO,
        .pNext = &library_feature, .queueCreateInfoCount = 1, .pQueueCreateInfos = &queue_info,
        .enabledExtensionCount = 2, .ppEnabledExtensionNames = extensions};
    VkDevice device;
    CHECK(vkCreateDevice(physical, &device_info, 0, &device));
    VkQueue queue;
    vkGetDeviceQueue(device, family, 0, &queue);

    /* Three storage buffers in one host-visible allocation. */
    VkDeviceSize stride = properties.limits.minStorageBufferOffsetAlignment;
    if (stride < 256) stride = 256;
    VkBuffer buffers[sets];
    VkBufferCreateInfo buffer_info = {.sType = VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO,
        .size = 16, .usage = VK_BUFFER_USAGE_STORAGE_BUFFER_BIT,
        .sharingMode = VK_SHARING_MODE_EXCLUSIVE};
    for (int i = 0; i < sets; i++) CHECK(vkCreateBuffer(device, &buffer_info, 0, &buffers[i]));
    VkMemoryRequirements requirements;
    vkGetBufferMemoryRequirements(device, buffers[0], &requirements);
    if (stride % requirements.alignment) stride += requirements.alignment - stride % requirements.alignment;
    VkPhysicalDeviceMemoryProperties memory_properties;
    vkGetPhysicalDeviceMemoryProperties(physical, &memory_properties);
    const VkMemoryPropertyFlags host = VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT | VK_MEMORY_PROPERTY_HOST_COHERENT_BIT;
    uint32_t type = 0;
    while (type < memory_properties.memoryTypeCount &&
           (!(requirements.memoryTypeBits & (1u << type)) ||
            (memory_properties.memoryTypes[type].propertyFlags & host) != host)) type++;
    if (type == memory_properties.memoryTypeCount) {
        report("VINIX-DOTA2-LVP-FAIL: no host-visible memory\n");
        return 2;
    }
    VkMemoryAllocateInfo allocate_memory = {.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO,
        .allocationSize = stride * sets, .memoryTypeIndex = type};
    VkDeviceMemory memory;
    CHECK(vkAllocateMemory(device, &allocate_memory, 0, &memory));
    unsigned char *mapped;
    CHECK(vkMapMemory(device, memory, 0, VK_WHOLE_SIZE, 0, (void **)&mapped));
    for (VkDeviceSize i = 0; i < stride * sets; i++) mapped[i] = 0;
    for (int i = 0; i < sets; i++) CHECK(vkBindBufferMemory(device, buffers[i], memory, stride * i));

    VkDescriptorSetLayoutBinding binding = {.binding = 0,
        .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .descriptorCount = 1,
        .stageFlags = VK_SHADER_STAGE_COMPUTE_BIT};
    VkDescriptorSetLayoutCreateInfo set_info = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
        .bindingCount = 1, .pBindings = &binding};
    VkDescriptorSetLayout storage;
    CHECK(vkCreateDescriptorSetLayout(device, &set_info, 0, &storage));
    int omit = absent_layout || absent_first_set;
    VkDescriptorSetLayout set_layouts[sets] = {storage, omit ? VK_NULL_HANDLE : storage, storage};
    VkPipelineLayoutCreateInfo layout_info = {.sType = VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO,
        .flags = VK_PIPELINE_LAYOUT_CREATE_INDEPENDENT_SETS_BIT_EXT,
        .setLayoutCount = sets, .pSetLayouts = set_layouts};
    VkPipelineLayout layout;
    CHECK(vkCreatePipelineLayout(device, &layout_info, 0, &layout));

    VkShaderModuleCreateInfo module_info = {.sType = VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO,
        .codeSize = sizeof shader, .pCode = shader};
    VkShaderModule module;
    CHECK(vkCreateShaderModule(device, &module_info, 0, &module));
    VkComputePipelineCreateInfo pipeline_info = {.sType = VK_STRUCTURE_TYPE_COMPUTE_PIPELINE_CREATE_INFO,
        .stage = {.sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO,
                  .stage = VK_SHADER_STAGE_COMPUTE_BIT, .module = module, .pName = "main"},
        .layout = layout};
    VkPipeline pipeline;
    CHECK(vkCreateComputePipelines(device, VK_NULL_HANDLE, 1, &pipeline_info, 0, &pipeline));

    VkDescriptorPoolSize pool_size = {VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, sets};
    VkDescriptorPoolCreateInfo pool_info = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO,
        .maxSets = sets, .poolSizeCount = 1, .pPoolSizes = &pool_size};
    VkDescriptorPool pool;
    CHECK(vkCreateDescriptorPool(device, &pool_info, 0, &pool));
    VkDescriptorSetLayout allocate_layouts[sets] = {storage, storage, storage};
    VkDescriptorSetAllocateInfo allocate_sets = {.sType = VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO,
        .descriptorPool = pool, .descriptorSetCount = sets, .pSetLayouts = allocate_layouts};
    VkDescriptorSet descriptor_sets[sets];
    CHECK(vkAllocateDescriptorSets(device, &allocate_sets, descriptor_sets));
    VkDescriptorBufferInfo buffer_descriptors[sets];
    VkWriteDescriptorSet writes[sets];
    for (int i = 0; i < sets; i++) {
        buffer_descriptors[i] = (VkDescriptorBufferInfo){buffers[i], 0, VK_WHOLE_SIZE};
        writes[i] = (VkWriteDescriptorSet){.sType = VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET,
            .dstSet = descriptor_sets[i], .descriptorCount = 1,
            .descriptorType = VK_DESCRIPTOR_TYPE_STORAGE_BUFFER, .pBufferInfo = &buffer_descriptors[i]};
    }
    vkUpdateDescriptorSets(device, sets, writes, 0, 0);

    VkCommandPoolCreateInfo command_pool_info = {.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO,
        .queueFamilyIndex = family};
    VkCommandPool command_pool;
    CHECK(vkCreateCommandPool(device, &command_pool_info, 0, &command_pool));
    VkCommandBufferAllocateInfo command_info = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO,
        .commandPool = command_pool, .level = VK_COMMAND_BUFFER_LEVEL_PRIMARY, .commandBufferCount = 1};
    VkCommandBuffer command;
    CHECK(vkAllocateCommandBuffers(device, &command_info, &command));
    VkCommandBufferBeginInfo begin = {.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    CHECK(vkBeginCommandBuffer(command, &begin));
    vkCmdBindPipeline(command, VK_PIPELINE_BIND_POINT_COMPUTE, pipeline);
    VkDescriptorSet bound[sets] = {descriptor_sets[0],
        null_set || absent_layout ? VK_NULL_HANDLE : descriptor_sets[1], descriptor_sets[2]};
    if (absent_first_set) {
        /* A later call starting past the omitted layout. */
        vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, 1, bound, 0, 0);
        vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 2, 1, bound + 2, 0, 0);
    } else {
        vkCmdBindDescriptorSets(command, VK_PIPELINE_BIND_POINT_COMPUTE, layout, 0, sets, bound, 0, 0);
    }
    vkCmdDispatch(command, 1, 1, 1);
    CHECK(vkEndCommandBuffer(command));
    VkFenceCreateInfo fence_info = {.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
    VkFence fence;
    CHECK(vkCreateFence(device, &fence_info, 0, &fence));
    VkSubmitInfo submit = {.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO,
        .commandBufferCount = 1, .pCommandBuffers = &command};
    report("VINIX-DOTA2-LVP-SUBMIT: %s\n", mode);
    CHECK(vkQueueSubmit(queue, 1, &submit, fence));
    CHECK(vkWaitForFences(device, 1, &fence, VK_TRUE, 60000000000ull));

    uint32_t values[sets];
    for (int i = 0; i < sets; i++) values[i] = *(volatile uint32_t *)(mapped + stride * i);
    report("VINIX-DOTA2-LVP-RESULT: mode=%s set0=%08x set1=%08x set2=%08x\n",
           mode, values[0], values[1], values[2]);
    vkUnmapMemory(device, memory);
    vkDestroyFence(device, fence, 0);
    vkDestroyCommandPool(device, command_pool, 0);
    vkDestroyDescriptorPool(device, pool, 0);
    vkDestroyPipeline(device, pipeline, 0);
    vkDestroyShaderModule(device, module, 0);
    vkDestroyPipelineLayout(device, layout, 0);
    vkDestroyDescriptorSetLayout(device, storage, 0);
    for (int i = 0; i < sets; i++) vkDestroyBuffer(device, buffers[i], 0);
    vkFreeMemory(device, memory, 0);
    vkDestroyDevice(device, 0);
    vkDestroyInstance(instance, 0);
    alarm(0);
    if (values[0] || values[1] || values[2] != marker) {
        report("VINIX-DOTA2-LVP-FAIL: %s stored through the wrong descriptor slot\n", mode);
        return 1;
    }
    report("VINIX-DOTA2-LVP-PASS: %s\n", mode);
    return 0;
}
