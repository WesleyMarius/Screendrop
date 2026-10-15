#include <metal_stdlib>
using namespace metal;

struct StudioSkinSmoothingParameters {
    // Where the output's pixel (0, 0) sits in the source texture.
    int2 offset;
    // Pixels between taps; the filter reaches three taps each way.
    float step;
    // How different a neighbour may be, in gamma-ish units, before it
    // stops counting: wider smooths stronger blemishes away.
    float rangeSigma;
    float amount;
};

// Skin smoothing: an edge-preserving (bilateral) blur where the skin mask
// is, blended back over the original by the mask and `amount`. Eyes,
// brows and lips are cut out of the mask, and the range weight keeps any
// remaining hard edge - a hairline, a beard - from bleeding.
kernel void studioSkinSmoothing(texture2d<float, access::read> source [[texture(0)]],
                                texture2d<float, access::read> mask [[texture(1)]],
                                texture2d<float, access::write> output [[texture(2)]],
                                constant StudioSkinSmoothingParameters &parameters [[buffer(0)]],
                                uint2 pixel [[thread_position_in_grid]]) {
    if (pixel.x >= output.get_width() || pixel.y >= output.get_height()) return;
    int2 size = int2(source.get_width(), source.get_height());
    int2 center = clamp(int2(pixel) + parameters.offset, int2(0), size - 1);
    float4 original = source.read(uint2(center));
    float weight = mask.read(uint2(min(pixel, uint2(mask.get_width() - 1, mask.get_height() - 1)))).r
        * parameters.amount;
    if (weight < 0.004f) {
        output.write(original, pixel);
        return;
    }

    // Compare in a perceptual-ish space so shadows and highlights smooth
    // alike; the working space is linear.
    float3 reference = sqrt(max(original.rgb, 0.0f));
    float inverseRange = 1.0f / (2.0f * parameters.rangeSigma * parameters.rangeSigma);
    float3 total = 0;
    float totalWeight = 0;
    for (int y = -3; y <= 3; ++y) {
        for (int x = -3; x <= 3; ++x) {
            float2 offset = float2(x, y) * parameters.step;
            int2 tap = clamp(center + int2(round(offset)), int2(0), size - 1);
            float3 color = source.read(uint2(tap)).rgb;
            float3 difference = sqrt(max(color, 0.0f)) - reference;
            // Spatial sigma of 1.5 taps.
            float spatial = exp(-float(x * x + y * y) / 4.5f);
            float range = exp(-dot(difference, difference) * inverseRange);
            float w = spatial * range;
            total += color * w;
            totalWeight += w;
        }
    }
    float3 smoothed = total / max(totalWeight, 1e-5f);
    output.write(float4(mix(original.rgb, smoothed, weight), original.a), pixel);
}
