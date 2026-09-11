/* SPDX-FileCopyrightText: 2026 Alexander Medvednikov
 * SPDX-License-Identifier: GPL-2.0-or-later */

#include "GHOST_WindowVinix.hh"

#include "GHOST_ContextEGL.hh"
#include "GHOST_Rect.hh"
#include "GHOST_SystemVinix.hh"

#include <epoxy/gl.h>

#include <algorithm>
#include <cerrno>
#include <cstring>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

GHOST_WindowVinix::GHOST_WindowVinix(GHOST_SystemVinix *system,
                                     const char *title,
                                     uint32_t width,
                                     uint32_t height,
                                     GHOST_TWindowState state,
                                     GHOST_TDrawingContextType type,
                                     bool stereo_visual,
                                     bool exclusive,
                                     const std::string &surface_path)
    : GHOST_Window(width, height, state, stereo_visual, exclusive),
      m_system(system),
      m_title(title ? title : "Blender"),
      m_surface_path(surface_path),
      m_width(width),
      m_height(height),
      m_state(state),
      m_valid_surface(false),
      m_invalid_window(false),
      m_surface_mapping(MAP_FAILED),
      m_surface_mapping_size(0),
      m_surface_header(nullptr),
      m_surface_buffers(nullptr)
{
  m_valid_surface = createSurface();
  if (m_valid_surface && setDrawingContextType(type) != GHOST_kSuccess) {
    m_valid_surface = false;
  }
}

GHOST_WindowVinix::~GHOST_WindowVinix()
{
  releaseNativeHandles();
  if (m_surface_mapping != MAP_FAILED) {
    munmap(m_surface_mapping, m_surface_mapping_size);
  }
  if (!m_surface_path.empty()) {
    unlink(m_surface_path.c_str());
  }
}

bool GHOST_WindowVinix::createSurface()
{
  if (m_width == 0 || m_height == 0 || m_width > 8192 || m_height > 8192 ||
      m_width > UINT32_MAX / 4)
  {
    return false;
  }
  const uint32_t stride = m_width * 4;
  const uint64_t buffer_size = uint64_t(stride) * m_height;
  const uint64_t mapping_size = sizeof(VinixSurfaceHeader) + buffer_size * 2;
  if (buffer_size > UINT32_MAX || mapping_size > SIZE_MAX) {
    return false;
  }

  const int fd = open(m_surface_path.c_str(), O_RDWR | O_CREAT | O_TRUNC, 0600);
  if (fd < 0) {
    return false;
  }
  if (ftruncate(fd, off_t(mapping_size)) != 0) {
    close(fd);
    return false;
  }
  m_surface_mapping = mmap(
      nullptr, size_t(mapping_size), PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
  close(fd);
  if (m_surface_mapping == MAP_FAILED) {
    return false;
  }

  m_surface_mapping_size = size_t(mapping_size);
  std::memset(m_surface_mapping, 0, m_surface_mapping_size);
  m_surface_header = static_cast<VinixSurfaceHeader *>(m_surface_mapping);
  m_surface_buffers = reinterpret_cast<uint8_t *>(m_surface_header + 1);
  m_surface_header->magic = VINIX_SURFACE_MAGIC;
  m_surface_header->version = VINIX_SURFACE_VERSION;
  m_surface_header->header_size = uint32_t(sizeof(VinixSurfaceHeader));
  m_surface_header->width = m_width;
  m_surface_header->height = m_height;
  m_surface_header->stride = stride;
  m_surface_header->format = VINIX_SURFACE_FORMAT_XRGB8888;
  m_surface_header->active_buffer = 0;
  m_surface_header->reader_buffer = VINIX_SURFACE_NO_READER;
  m_surface_header->sequence = 0;
  m_surface_header->buffer_size = uint32_t(buffer_size);
  __atomic_thread_fence(__ATOMIC_RELEASE);
  return true;
}

GHOST_Context *GHOST_WindowVinix::newDrawingContext(GHOST_TDrawingContextType type)
{
  if (type != GHOST_kDrawingContextTypeOpenGL) {
    return nullptr;
  }
#ifdef WITH_OPENGL_BACKEND
  for (int minor = 6; minor >= 3; --minor) {
    GHOST_Context *context = new GHOST_ContextEGL(m_system,
                                                  m_wantStereoVisual,
                                                  EGLNativeWindowType(0),
                                                  EGLNativeDisplayType(EGL_DEFAULT_DISPLAY),
                                                  EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT,
                                                  4,
                                                  minor,
                                                  GHOST_OPENGL_EGL_CONTEXT_FLAGS,
                                                  GHOST_OPENGL_EGL_RESET_NOTIFICATION_STRATEGY,
                                                  EGL_OPENGL_API,
                                                  EGLint(m_width),
                                                  EGLint(m_height));
    if (context->initializeDrawingContext()) {
      return context;
    }
    delete context;
  }
#endif
  return nullptr;
}

bool GHOST_WindowVinix::publishFramebuffer()
{
  if (!m_valid_surface || activateDrawingContext() != GHOST_kSuccess) {
    return false;
  }
  const uint32_t active = __atomic_load_n(&m_surface_header->active_buffer, __ATOMIC_ACQUIRE);
  const uint32_t target = active ^ 1U;
  if (__atomic_load_n(&m_surface_header->reader_buffer, __ATOMIC_ACQUIRE) == target) {
    return true; /* The compositor is still presenting this buffer; drop one
                    frame. */
  }

  const size_t row_size = size_t(m_width) * 4;
  m_readback.resize(row_size * m_height);
  glPixelStorei(GL_PACK_ALIGNMENT, 4);
  glFinish();
  glReadPixels(
      0, 0, GLsizei(m_width), GLsizei(m_height), GL_BGRA, GL_UNSIGNED_BYTE, m_readback.data());
  if (glGetError() != GL_NO_ERROR) {
    return false;
  }

  uint8_t *destination = m_surface_buffers + size_t(target) * m_surface_header->buffer_size;
  for (uint32_t y = 0; y < m_height; ++y) {
    const uint8_t *source = m_readback.data() + size_t(m_height - 1 - y) * row_size;
    std::memcpy(destination + size_t(y) * m_surface_header->stride, source, row_size);
  }
  __atomic_add_fetch(&m_surface_header->sequence, 1U, __ATOMIC_RELAXED);
  __atomic_store_n(&m_surface_header->active_buffer, target, __ATOMIC_RELEASE);
  return true;
}

GHOST_TSuccess GHOST_WindowVinix::swapBuffers()
{
  const bool published = publishFramebuffer();
  const GHOST_TSuccess swapped = GHOST_Window::swapBuffers();
  return published && swapped == GHOST_kSuccess ? GHOST_kSuccess : GHOST_kFailure;
}

bool GHOST_WindowVinix::getValid() const
{
  return m_valid_surface && GHOST_Window::getValid();
}

void GHOST_WindowVinix::setTitle(const char *title)
{
  m_title = title ? title : "";
}

std::string GHOST_WindowVinix::getTitle() const
{
  return m_title;
}

void GHOST_WindowVinix::getWindowBounds(GHOST_Rect &bounds) const
{
  getClientBounds(bounds);
}

void GHOST_WindowVinix::getClientBounds(GHOST_Rect &bounds) const
{
  bounds.m_l = 0;
  bounds.m_t = 0;
  bounds.m_r = m_width;
  bounds.m_b = m_height;
}

GHOST_TSuccess GHOST_WindowVinix::setClientWidth(uint32_t width)
{
  return width == m_width ? GHOST_kSuccess : GHOST_kFailure;
}

GHOST_TSuccess GHOST_WindowVinix::setClientHeight(uint32_t height)
{
  return height == m_height ? GHOST_kSuccess : GHOST_kFailure;
}

GHOST_TSuccess GHOST_WindowVinix::setClientSize(uint32_t width, uint32_t height)
{
  return width == m_width && height == m_height ? GHOST_kSuccess : GHOST_kFailure;
}

void GHOST_WindowVinix::screenToClient(int32_t in_x,
                                       int32_t in_y,
                                       int32_t &out_x,
                                       int32_t &out_y) const
{
  out_x = in_x;
  out_y = in_y;
}

void GHOST_WindowVinix::clientToScreen(int32_t in_x,
                                       int32_t in_y,
                                       int32_t &out_x,
                                       int32_t &out_y) const
{
  out_x = in_x;
  out_y = in_y;
}

GHOST_TSuccess GHOST_WindowVinix::setState(GHOST_TWindowState state)
{
  m_state = state;
  return GHOST_kSuccess;
}

GHOST_TWindowState GHOST_WindowVinix::getState() const
{
  return m_state;
}

GHOST_TSuccess GHOST_WindowVinix::setOrder(GHOST_TWindowOrder /*order*/)
{
  return GHOST_kSuccess;
}

GHOST_TSuccess GHOST_WindowVinix::invalidate()
{
  if (!m_invalid_window) {
    m_invalid_window = true;
    m_system->addDirtyWindow(this);
  }
  return GHOST_kSuccess;
}

void GHOST_WindowVinix::validate()
{
  m_invalid_window = false;
}

GHOST_TSuccess GHOST_WindowVinix::setWindowCursorGrab(GHOST_TGrabCursorMode /*mode*/)
{
  return GHOST_kSuccess;
}

GHOST_TSuccess GHOST_WindowVinix::setWindowCursorShape(GHOST_TStandardCursor /*shape*/)
{
  return GHOST_kSuccess;
}

GHOST_TSuccess GHOST_WindowVinix::hasCursorShape(GHOST_TStandardCursor /*shape*/)
{
  return GHOST_kSuccess;
}

GHOST_TSuccess GHOST_WindowVinix::setWindowCustomCursorShape(uint8_t * /*bitmap*/,
                                                             uint8_t * /*mask*/,
                                                             int /*size_x*/,
                                                             int /*size_y*/,
                                                             int /*hot_x*/,
                                                             int /*hot_y*/,
                                                             bool /*can_invert_color*/)
{
  return GHOST_kSuccess;
}

GHOST_TSuccess GHOST_WindowVinix::setWindowCursorVisibility(bool /*visible*/)
{
  return GHOST_kSuccess;
}

GHOST_TSuccess GHOST_WindowVinix::beginFullScreen() const
{
  return GHOST_kSuccess;
}

GHOST_TSuccess GHOST_WindowVinix::endFullScreen() const
{
  return GHOST_kSuccess;
}
