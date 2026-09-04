#import <Foundation/Foundation.h>
#import <Metal/Metal.h>

static int run_triangle(void) {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    if (!device) {
        fprintf(stderr, "metal_triangle: no Metal device\n");
        return 1;
    }

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

    NSError *error = nil;
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
    id<MTLRenderPipelineState> pipeline = [device newRenderPipelineStateWithDescriptor:pipeline_desc
                                                                                error:&error];
    if (!pipeline) {
        fprintf(stderr, "metal_triangle: pipeline creation failed: %s\n",
                error.localizedDescription.UTF8String);
        return 1;
    }

    MTLTextureDescriptor *texture_desc =
        [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                          width:64
                                                         height:64
                                                      mipmapped:NO];
    texture_desc.storageMode = MTLStorageModeShared;
    texture_desc.usage = MTLTextureUsageRenderTarget;
    id<MTLTexture> texture = [device newTextureWithDescriptor:texture_desc];
    id<MTLCommandQueue> queue = [device newCommandQueue];
    id<MTLCommandBuffer> commands = [queue commandBuffer];

    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);

    id<MTLRenderCommandEncoder> encoder = [commands renderCommandEncoderWithDescriptor:pass];
    [encoder setRenderPipelineState:pipeline];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
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
    if (checksum == 64ul * 64ul * 255ul) {
        fprintf(stderr, "metal_triangle: output contains only the opaque black clear color\n");
        return 1;
    }
    printf("metal_triangle: rendered on %s (checksum %lu)\n", device.name.UTF8String, checksum);
    return 0;
}

int main(void) {
    @autoreleasepool {
        return run_triangle();
    }
}
