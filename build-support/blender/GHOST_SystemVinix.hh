/* SPDX-FileCopyrightText: 2026 Alexander Medvednikov
 * SPDX-License-Identifier: GPL-2.0-or-later */

#pragma once

#include "GHOST_System.hh"

#include <cstdint>
#include <string>
#include <vector>

class GHOST_WindowVinix;

class GHOST_SystemVinix : public GHOST_System {
 public:
  GHOST_SystemVinix();
  ~GHOST_SystemVinix() override = default;

  bool processEvents(bool wait_for_event) override;
  bool setConsoleWindowState(GHOST_TConsoleWindowState action) override;
  GHOST_TSuccess getModifierKeys(GHOST_ModifierKeys &keys) const override;
  GHOST_TSuccess getButtons(GHOST_Buttons &buttons) const override;
  GHOST_TCapabilityFlag getCapabilities() const override;
  char *getClipboard(bool selection) const override;
  void putClipboard(const char *buffer, bool selection) const override;
  uint64_t getMilliSeconds() const override;
  uint8_t getNumDisplays() const override;
  GHOST_TSuccess getCursorPosition(int32_t &x, int32_t &y) const override;
  GHOST_TSuccess setCursorPosition(int32_t x, int32_t y) override;
  void getAllDisplayDimensions(uint32_t &width, uint32_t &height) const override;
  void getMainDisplayDimensions(uint32_t &width, uint32_t &height) const override;
  GHOST_IContext *createOffscreenContext(GHOST_GPUSettings gpu_settings) override;
  GHOST_TSuccess disposeContext(GHOST_IContext *context) override;

  void addDirtyWindow(GHOST_WindowVinix *window);

 private:
  GHOST_TSuccess init() override;
  GHOST_IWindow *createWindow(const char *title,
                              int32_t left,
                              int32_t top,
                              uint32_t width,
                              uint32_t height,
                              GHOST_TWindowState state,
                              GHOST_GPUSettings gpu_settings,
                              bool exclusive = false,
                              bool is_dialog = false,
                              const GHOST_IWindow *parent_window = nullptr) override;

  bool readInput();
  bool processInputRecords();
  void processInputRecord(
      uint32_t kind, int32_t x, int32_t y, int32_t value, const uint8_t *data, size_t size);
  void emitText(const uint8_t *data, size_t size);
  void emitKey(GHOST_TKey key,
               const char *utf8 = nullptr,
               bool shift = false,
               bool control = false);
  void emitSpecialKey(GHOST_TKey key);

  std::string m_surface_path;
  uint32_t m_width;
  uint32_t m_height;
  int32_t m_cursor_x;
  int32_t m_cursor_y;
  bool m_left_button;
  bool m_middle_button;
  bool m_right_button;
  bool m_input_closed;
  bool m_close_sent;
  unsigned int m_window_count;
  std::vector<uint8_t> m_input_buffer;
  std::vector<GHOST_WindowVinix *> m_dirty_windows;
};
