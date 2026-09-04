#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <objc/runtime.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static void json_string(const char *value) {
    putchar('"');
    if (value) {
        for (const unsigned char *cursor = (const unsigned char *)value; *cursor; ++cursor) {
            switch (*cursor) {
            case '"':
                fputs("\\\"", stdout);
                break;
            case '\\':
                fputs("\\\\", stdout);
                break;
            case '\n':
                fputs("\\n", stdout);
                break;
            case '\r':
                fputs("\\r", stdout);
                break;
            case '\t':
                fputs("\\t", stdout);
                break;
            default:
                if (*cursor < 0x20)
                    printf("\\u%04x", *cursor);
                else
                    putchar(*cursor);
            }
        }
    }
    putchar('"');
}

static void dump_object(const char *kind, id object) {
    const unsigned char *bytes = (const unsigned char *)(__bridge const void *)object;
    printf("{\"event\":\"object\",\"kind\":");
    json_string(kind);
    printf(",\"class\":");
    json_string(object_getClassName(object));
    printf("}\n");

    for (Class cls = object_getClass(object); cls; cls = class_getSuperclass(cls)) {
        printf("{\"event\":\"class\",\"kind\":");
        json_string(kind);
        printf(",\"class\":");
        json_string(class_getName(cls));
        printf(",\"instance_bytes\":%zu}\n", class_getInstanceSize(cls));

        unsigned int ivar_count = 0;
        Ivar *ivars = class_copyIvarList(cls, &ivar_count);
        for (unsigned int index = 0; index < ivar_count; ++index) {
            ptrdiff_t offset = ivar_getOffset(ivars[index]);
            const char *type = ivar_getTypeEncoding(ivars[index]);
            uint64_t raw = 0;
            size_t available = class_getInstanceSize(object_getClass(object));
            if (offset >= 0 && (size_t)offset + sizeof(raw) <= available)
                memcpy(&raw, bytes + offset, sizeof(raw));
            printf("{\"event\":\"ivar\",\"kind\":");
            json_string(kind);
            printf(",\"class\":");
            json_string(class_getName(cls));
            printf(",\"name\":");
            json_string(ivar_getName(ivars[index]));
            printf(",\"type\":");
            json_string(type);
            printf(",\"offset\":%td,\"raw\":\"0x%016llx\"}\n", offset,
                   (unsigned long long)raw);
        }
        free(ivars);

        unsigned int method_count = 0;
        Method *methods = class_copyMethodList(cls, &method_count);
        for (unsigned int index = 0; index < method_count; ++index) {
            printf("{\"event\":\"method\",\"kind\":");
            json_string(kind);
            printf(",\"class\":");
            json_string(class_getName(cls));
            printf(",\"name\":");
            json_string(sel_getName(method_getName(methods[index])));
            printf(",\"type\":");
            json_string(method_getTypeEncoding(methods[index]));
            printf("}\n");
        }
        free(methods);
    }
}

int main(void) {
    @autoreleasepool {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        if (!device) {
            fprintf(stderr, "objc_layout: no Metal device\n");
            return 1;
        }

        id<MTLCommandQueue> queue = [device newCommandQueue];
        id<MTLCommandBuffer> commands = [queue commandBuffer];
        MTLTextureDescriptor *desc =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                              width:64
                                                             height:64
                                                          mipmapped:NO];
        desc.storageMode = MTLStorageModeShared;
        desc.usage = MTLTextureUsageRenderTarget;
        id<MTLTexture> texture = [device newTextureWithDescriptor:desc];

        MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
        pass.colorAttachments[0].texture = texture;
        pass.colorAttachments[0].loadAction = MTLLoadActionClear;
        pass.colorAttachments[0].storeAction = MTLStoreActionStore;
        id<MTLRenderCommandEncoder> encoder = [commands renderCommandEncoderWithDescriptor:pass];

        dump_object("device", device);
        dump_object("queue", queue);
        dump_object("command_buffer", commands);
        dump_object("texture", texture);
        dump_object("render_encoder", encoder);
        [encoder endEncoding];
        return 0;
    }
}
