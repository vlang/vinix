/* SPDX-License-Identifier: GPL-2.0-or-later */
#pragma once

#include <cstdint>

constexpr uint32_t VINIX_SURFACE_MAGIC = 0x31534656; /* VSF1. */
constexpr uint32_t VINIX_SURFACE_VERSION = 1;
constexpr uint32_t VINIX_SURFACE_FORMAT_XRGB8888 = 1;
constexpr uint32_t VINIX_SURFACE_NO_READER = UINT32_MAX;
constexpr uint32_t VINIX_INPUT_EVENT_MAGIC = 0x31494e56; /* VNI1. */
constexpr uint32_t VINIX_INPUT_MAX_PAYLOAD = 4096;

enum class VinixInputEventKind : uint32_t {
  Motion = 1,
  ButtonDown = 2,
  ButtonUp = 3,
  Keys = 4,
  Wheel = 5,
};

enum class VinixPointerButton : int32_t {
  Left = 1,
  Middle = 2,
  Right = 3,
};

struct VinixSurfaceHeader {
  uint32_t magic;
  uint32_t version;
  uint32_t header_size;
  uint32_t width;
  uint32_t height;
  uint32_t stride;
  uint32_t format;
  uint32_t active_buffer;
  uint32_t reader_buffer;
  uint32_t sequence;
  uint32_t buffer_size;
  uint32_t reserved;
};

struct VinixInputEvent {
  uint32_t magic;
  uint32_t kind;
  int32_t x;
  int32_t y;
  int32_t value;
  uint32_t length;
};

static_assert(sizeof(VinixSurfaceHeader) == 48, "Vinix surface header ABI changed");
static_assert(sizeof(VinixInputEvent) == 24, "Vinix input event ABI changed");
