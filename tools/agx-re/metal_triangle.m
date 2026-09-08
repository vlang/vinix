#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#include <dlfcn.h>
#include <stdbool.h>
#include <string.h>

typedef void (*trace_marker_fn)(const char *phase);

static void trace_marker(const char *phase) {
    trace_marker_fn marker = (trace_marker_fn)dlsym(RTLD_DEFAULT, "agx_trace_marker");
    if (marker)
        marker(phase);
}

static int submit(id<MTLCommandQueue> queue, id<MTLTexture> texture,
                  id<MTLTexture> depth_texture,
                  id<MTLRenderPipelineState> pipeline,
                  id<MTLDepthStencilState> depth_state, bool draw,
                  const char *phase) {
    id<MTLCommandBuffer> commands = [queue commandBuffer];

    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    if (depth_texture) {
        pass.depthAttachment.texture = depth_texture;
        pass.depthAttachment.loadAction = MTLLoadActionClear;
        pass.depthAttachment.storeAction = MTLStoreActionStore;
        pass.depthAttachment.clearDepth = 1.0;
    }

    trace_marker(phase);
    id<MTLRenderCommandEncoder> encoder = [commands renderCommandEncoderWithDescriptor:pass];
    if (draw) {
        [encoder setRenderPipelineState:pipeline];
        if (depth_state)
            [encoder setDepthStencilState:depth_state];
        [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    }
    [encoder endEncoding];
    [commands commit];
    [commands waitUntilCompleted];
    if (commands.status != MTLCommandBufferStatusCompleted) {
        fprintf(stderr, "metal_triangle: GPU submission failed: %s\n",
                commands.error.localizedDescription.UTF8String);
        return 1;
    }

    uint8_t pixels[64 * 64 * 4] = {0};
    [texture getBytes:pixels
          bytesPerRow:64 * 4
           fromRegion:MTLRegionMake2D(0, 0, 64, 64)
          mipmapLevel:0];
    unsigned long checksum = 0;
    for (size_t index = 0; index < sizeof(pixels); ++index)
        checksum += pixels[index];
    const unsigned long clear_checksum = 64ul * 64ul * 255ul;
    if (draw && checksum == clear_checksum) {
        fprintf(stderr, "metal_triangle: output contains only the opaque black clear color\n");
        return 1;
    }
    if (!draw && checksum != clear_checksum) {
        fprintf(stderr, "metal_triangle: clear produced unexpected checksum %lu\n", checksum);
        return 1;
    }
    printf("metal_triangle: %s rendered on %s (checksum %lu)\n", phase,
           queue.device.name.UTF8String, checksum);
    return 0;
}

static int run_triangle(const char *mode) {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
        fprintf(stderr, "metal_triangle: no Metal device\n");
        return 1;
    }

    bool depth = strcmp(mode, "depth-pair") == 0;
    NSError *error = nil;
    id<MTLRenderPipelineState> pipeline = nil;
    if (strcmp(mode, "clear") != 0) {
        NSString *source =
            @"#include <metal_stdlib>\n"
             "using namespace metal;\n"
             "struct VOut { float4 position [[position]]; float3 color; };\n"
             "vertex VOut triangle_vertex(uint id [[vertex_id]]) {\n"
             "  const float2 p[3] = {float2(0.0, 0.8), float2(-0.8, -0.8), float2(0.8, -0.8)};\n"
             "  const float3 c[3] = {float3(1,0,0), float3(0,1,0), float3(0,0,1)};\n"
             "  return {float4(p[id], 0, 1), c[id]};\n"
             "}\n"
             "fragment float4 triangle_fragment(VOut in [[stage_in]]) { return float4(in.color, 1); }\n";

        id<MTLLibrary> library = [device newLibraryWithSource:source options:nil error:&error];
        if (!library) {
            fprintf(stderr, "metal_triangle: shader compile failed: %s\n",
                    error.localizedDescription.UTF8String);
            return 1;
        }

        MTLRenderPipelineDescriptor *pipeline_desc = [MTLRenderPipelineDescriptor new];
        pipeline_desc.vertexFunction = [library newFunctionWithName:@"triangle_vertex"];
        pipeline_desc.fragmentFunction = [library newFunctionWithName:@"triangle_fragment"];
        pipeline_desc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        if (depth)
            pipeline_desc.depthAttachmentPixelFormat = MTLPixelFormatDepth32Float;
        pipeline = [device newRenderPipelineStateWithDescriptor:pipeline_desc error:&error];
        if (!pipeline) {
            fprintf(stderr, "metal_triangle: pipeline creation failed: %s\n",
                    error.localizedDescription.UTF8String);
            return 1;
        }
    }

    MTLTextureDescriptor *texture_desc =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                          width:64
                                                         height:64
                                                      mipmapped:NO];
    texture_desc.storageMode = MTLStorageModeShared;
    texture_desc.usage = MTLTextureUsageRenderTarget;
    id<MTLTexture> texture = [device newTextureWithDescriptor:texture_desc];
    id<MTLTexture> depth_texture = nil;
    id<MTLDepthStencilState> depth_state = nil;
    if (depth) {
        MTLTextureDescriptor *depth_desc =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatDepth32Float
                                                               width:64
                                                              height:64
                                                           mipmapped:NO];
        depth_desc.storageMode = MTLStorageModePrivate;
        depth_desc.usage = MTLTextureUsageRenderTarget;
        depth_texture = [device newTextureWithDescriptor:depth_desc];

        MTLDepthStencilDescriptor *state_desc = [MTLDepthStencilDescriptor new];
        state_desc.depthCompareFunction = MTLCompareFunctionLess;
        state_desc.depthWriteEnabled = YES;
        depth_state = [device newDepthStencilStateWithDescriptor:state_desc];
        if (!depth_texture || !depth_state) {
            fprintf(stderr, "metal_triangle: depth resource creation failed\n");
            return 1;
        }
    }
    id<MTLCommandQueue> queue = [device newCommandQueue];
    if (strcmp(mode, "pair") == 0) {
        if (submit(queue, texture, nil, pipeline, nil, false, "clear"))
            return 1;
        return submit(queue, texture, nil, pipeline, nil, true, "triangle");
    }
    if (depth) {
        if (submit(queue, texture, depth_texture, pipeline, depth_state, false,
                   "depth-clear"))
            return 1;
        return submit(queue, texture, depth_texture, pipeline, depth_state, true,
                      "depth-triangle");
    }
    return submit(queue, texture, nil, pipeline, nil,
                  strcmp(mode, "clear") != 0, mode);
}

int main(int argc, const char **argv) {
    @autoreleasepool {
        const char *mode = argc == 1 ? "triangle" : argv[1];
        if (argc > 2 ||
            (strcmp(mode, "clear") != 0 && strcmp(mode, "triangle") != 0 &&
             strcmp(mode, "pair") != 0 && strcmp(mode, "depth-pair") != 0)) {
            fprintf(stderr,
                    "usage: metal_triangle [clear|triangle|pair|depth-pair]\n");
            return 2;
        }
        return run_triangle(mode);
    }
}
