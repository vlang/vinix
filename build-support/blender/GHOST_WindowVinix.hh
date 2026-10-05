/* SPDX-FileCopyrightText: 2026 Alexander Medvednikov
 * SPDX-License-Identifier: GPL-2.0-or-later */

#pragma once

#include "GHOST_VinixProtocol.hh"
#include "GHOST_Window.hh"

#include <cstdint>
#include <string>
#include <vector>

class GHOST_SystemVinix;

class GHOST_WindowVinix : public GHOST_Window {
 public:
  GHOST_WindowVinix(GHOST_SystemVinix *system,
                    const char *title,
                    uint32_t width,
                    uint32_t height,
                    GHOST_TWindowState state,
                    GHOST_TDrawingContextType type,
                    bool stereo_visual,
                    bool exclusive,
                    const std::string &surface_path);
  ~GHOST_WindowVinix() override;

  bool getValid() const override;
  void setTitle(const char *title) override;
  std::string getTitle() const override;
  void getWindowBounds(GHOST_Rect &bounds) const override;
  void getClientBounds(GHOST_Rect &bounds) const override;
  GHOST_TSuccess setClientWidth(uint32_t width) override;
  GHOST_TSuccess setClientHeight(uint32_t height) override;
  GHOST_TSuccess setClientSize(uint32_t width, uint32_t height) override;
  void screenToClient(int32_t in_x, int32_t in_y, int32_t &out_x, int32_t &out_y) const override;
  void clientToScreen(int32_t in_x, int32_t in_y, int32_t &out_x, int32_t &out_y) const override;
  GHOST_TSuccess setState(GHOST_TWindowState state) override;
  GHOST_TWindowState getState() const override;
  GHOST_TSuccess setOrder(GHOST_TWindowOrder order) override;
  GHOST_TSuccess invalidate() override;
  GHOST_TSuccess swapBuffers() override;
  GHOST_TSuccess beginFullScreen() const override;
  GHOST_TSuccess endFullScreen() const override;

  void validate();

 protected:
  GHOST_Context *newDrawingContext(GHOST_TDrawingContextType type) override;
  GHOST_TSuccess setWindowCursorGrab(GHOST_TGrabCursorMode mode) override;
  GHOST_TSuccess setWindowCursorShape(GHOST_TStandardCursor shape) override;
  GHOST_TSuccess hasCursorShape(GHOST_TStandardCursor shape) override;
  GHOST_TSuccess setWindowCustomCursorShape(uint8_t *bitmap,
                                            uint8_t *mask,
                                            int size_x,
                                            int size_y,
                                            int hot_x,
                                            int hot_y,
                                            bool can_invert_color) override;
  GHOST_TSuccess setWindowCursorVisibility(bool visible) override;

 private:
  bool createSurface();
  bool publishFramebuffer();

  GHOST_SystemVinix *m_system;
  std::string m_title;
  std::string m_surface_path;
  uint32_t m_width;
  uint32_t m_height;
  GHOST_TWindowState m_state;
  bool m_valid_surface;
  bool m_invalid_window;
  void *m_surface_mapping;
  size_t m_surface_mapping_size;
  VinixSurfaceHeader *m_surface_header;
  uint8_t *m_surface_buffers;
  std::vector<uint8_t> m_readback;
};
