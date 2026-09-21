/* SPDX-FileCopyrightText: 2026 Alexander Medvednikov
 * SPDX-License-Identifier: GPL-2.0-or-later */

#include "GHOST_SystemVinix.hh"

#include "GHOST_ContextEGL.hh"
#include "GHOST_DisplayManager.hh"
#include "GHOST_Event.hh"
#include "GHOST_EventButton.hh"
#include "GHOST_EventCursor.hh"
#include "GHOST_EventKey.hh"
#include "GHOST_EventWheel.hh"
#include "GHOST_TimerManager.hh"
#include "GHOST_VinixProtocol.hh"
#include "GHOST_WindowManager.hh"
#include "GHOST_WindowVinix.hh"

#include <algorithm>
#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <poll.h>
#include <stdexcept>
#include <time.h>
#include <unistd.h>

namespace {

uint32_t environment_dimension(const char *name)
{
  const char *text = std::getenv(name);
  if (!text || !text[0]) {
    throw std::runtime_error(std::string(name) + " is required by the Vinix GHOST backend");
  }
  char *end = nullptr;
  const unsigned long value = std::strtoul(text, &end, 10);
  if (!end || *end != '\0' || value == 0 || value > 8192) {
    throw std::runtime_error(std::string(name) + " is not a valid surface dimension");
  }
  return uint32_t(value);
}

class GHOST_DisplayManagerVinix : public GHOST_DisplayManager {
 public:
  GHOST_DisplayManagerVinix(uint32_t width, uint32_t height) : width_(width), height_(height) {}

  GHOST_TSuccess getNumDisplays(uint8_t &count) const override
  {
    count = 1;
    return GHOST_kSuccess;
  }

  GHOST_TSuccess getNumDisplaySettings(uint8_t display, int32_t &count) const override
  {
    if (display != 0) {
      return GHOST_kFailure;
    }
    count = 1;
    return GHOST_kSuccess;
  }

  GHOST_TSuccess getDisplaySetting(uint8_t display,
                                   int32_t index,
                                   GHOST_DisplaySetting &setting) const override
  {
    if (display != 0 || index != 0) {
      return GHOST_kFailure;
    }
    setting.xPixels = width_;
    setting.yPixels = height_;
    setting.bpp = 32;
    setting.frequency = 60;
    return GHOST_kSuccess;
  }

  GHOST_TSuccess getCurrentDisplaySetting(uint8_t display,
                                          GHOST_DisplaySetting &setting) const override
  {
    return getDisplaySetting(display, 0, setting);
  }

  GHOST_TSuccess setCurrentDisplaySetting(uint8_t display,
                                          const GHOST_DisplaySetting & /*setting*/) override
  {
    return display == 0 ? GHOST_kSuccess : GHOST_kFailure;
  }

 private:
  uint32_t width_;
  uint32_t height_;
};

GHOST_TKey ascii_key(unsigned char character, bool &shift)
{
  shift = false;
  if (character >= 'a' && character <= 'z') {
    return GHOST_TKey(int(GHOST_kKeyA) + character - 'a');
  }
  if (character >= 'A' && character <= 'Z') {
    shift = true;
    return GHOST_TKey(int(GHOST_kKeyA) + character - 'A');
  }
  if (character >= '0' && character <= '9') {
    return GHOST_TKey(int(GHOST_kKey0) + character - '0');
  }
  switch (character) {
    case ' ':
      return GHOST_kKeySpace;
    case '\t':
      return GHOST_kKeyTab;
    case '\r':
    case '\n':
      return GHOST_kKeyEnter;
    case 8:
    case 127:
      return GHOST_kKeyBackSpace;
    case '\'':
      return GHOST_kKeyQuote;
    case ',':
      return GHOST_kKeyComma;
    case '-':
      return GHOST_kKeyMinus;
    case '.':
      return GHOST_kKeyPeriod;
    case '/':
      return GHOST_kKeySlash;
    case ';':
      return GHOST_kKeySemicolon;
    case '=':
      return GHOST_kKeyEqual;
    case '[':
      return GHOST_kKeyLeftBracket;
    case ']':
      return GHOST_kKeyRightBracket;
    case '\\':
      return GHOST_kKeyBackslash;
    case '`':
      return GHOST_kKeyAccentGrave;
    default:
      break;
  }

  static const char shifted[] = "!@#$%^&*()_+{}|:\"<>?~";
  static const char unshifted[] = "1234567890-=[]\\;',./`";
  const char *match = std::strchr(shifted, int(character));
  if (match) {
    shift = true;
    bool ignored_shift = false;
    return ascii_key(static_cast<unsigned char>(unshifted[match - shifted]), ignored_shift);
  }
  return GHOST_kKeyUnknown;
}

}  // namespace

GHOST_SystemVinix::GHOST_SystemVinix()
    : GHOST_System(),
      m_width(environment_dimension("VINIX_SURFACE_WIDTH")),
      m_height(environment_dimension("VINIX_SURFACE_HEIGHT")),
      m_cursor_x(0),
      m_cursor_y(0),
      m_left_button(false),
      m_middle_button(false),
      m_right_button(false),
      m_input_closed(false),
      m_close_sent(false),
      m_window_count(0)
{
  const char *surface_path = std::getenv("VINIX_SURFACE_PATH");
  if (!surface_path || surface_path[0] != '/') {
    throw std::runtime_error("VINIX_SURFACE_PATH must be an absolute path");
  }
  m_surface_path = surface_path;
  const int flags = fcntl(STDIN_FILENO, F_GETFL, 0);
  if (flags < 0 || fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK) != 0) {
    throw std::runtime_error("Vinix GHOST could not make its input pipe non-blocking");
  }
}

GHOST_TSuccess GHOST_SystemVinix::init()
{
  if (GHOST_System::init() != GHOST_kSuccess) {
    return GHOST_kFailure;
  }
  m_displayManager = new GHOST_DisplayManagerVinix(m_width, m_height);
  return m_displayManager ? GHOST_kSuccess : GHOST_kFailure;
}

GHOST_IWindow *GHOST_SystemVinix::createWindow(const char *title,
                                               int32_t /*left*/,
                                               int32_t /*top*/,
                                               uint32_t /*width*/,
                                               uint32_t /*height*/,
                                               GHOST_TWindowState state,
                                               GHOST_GPUSettings gpu_settings,
                                               bool exclusive,
                                               bool /*is_dialog*/,
                                               const GHOST_IWindow * /*parent_window*/)
{
  const std::string path = m_window_count == 0 ?
                               m_surface_path :
                               m_surface_path + "." + std::to_string(m_window_count);
  GHOST_WindowVinix *window = new GHOST_WindowVinix(this,
                                                    title,
                                                    m_width,
                                                    m_height,
                                                    state,
                                                    gpu_settings.context_type,
                                                    (gpu_settings.flags & GHOST_gpuStereoVisual) !=
                                                        0,
                                                    exclusive,
                                                    path);
  if (!window->getValid()) {
    delete window;
    return nullptr;
  }
  ++m_window_count;
  m_windowManager->addWindow(window);
  pushEvent(new GHOST_Event(getMilliSeconds(), GHOST_kEventWindowSize, window));
  pushEvent(new GHOST_Event(getMilliSeconds(), GHOST_kEventWindowActivate, window));
  window->invalidate();
  return window;
}

uint64_t GHOST_SystemVinix::getMilliSeconds() const
{
  struct timespec stamp = {};
  if (clock_gettime(CLOCK_MONOTONIC, &stamp) != 0) {
    return 0;
  }
  return uint64_t(stamp.tv_sec) * 1000 + uint64_t(stamp.tv_nsec) / 1000000;
}

uint8_t GHOST_SystemVinix::getNumDisplays() const
{
  return 1;
}

void GHOST_SystemVinix::getAllDisplayDimensions(uint32_t &width, uint32_t &height) const
{
  width = m_width;
  height = m_height;
}

void GHOST_SystemVinix::getMainDisplayDimensions(uint32_t &width, uint32_t &height) const
{
  getAllDisplayDimensions(width, height);
}

GHOST_TSuccess GHOST_SystemVinix::getCursorPosition(int32_t &x, int32_t &y) const
{
  x = m_cursor_x;
  y = m_cursor_y;
  return GHOST_kSuccess;
}

GHOST_TSuccess GHOST_SystemVinix::setCursorPosition(int32_t /*x*/, int32_t /*y*/)
{
  return GHOST_kFailure;
}

GHOST_TSuccess GHOST_SystemVinix::getModifierKeys(GHOST_ModifierKeys &keys) const
{
  keys.clear();
  return GHOST_kSuccess;
}

GHOST_TSuccess GHOST_SystemVinix::getButtons(GHOST_Buttons &buttons) const
{
  buttons.clear();
  buttons.set(GHOST_kButtonMaskLeft, m_left_button);
  buttons.set(GHOST_kButtonMaskMiddle, m_middle_button);
  buttons.set(GHOST_kButtonMaskRight, m_right_button);
  return GHOST_kSuccess;
}

GHOST_TCapabilityFlag GHOST_SystemVinix::getCapabilities() const
{
  return GHOST_TCapabilityFlag(GHOST_CAPABILITY_FLAG_ALL &
                               ~(GHOST_kCapabilityCursorWarp | GHOST_kCapabilityWindowPosition |
                                 GHOST_kCapabilityPrimaryClipboard |
                                 GHOST_kCapabilityClipboardImages |
                                 GHOST_kCapabilityDesktopSample | GHOST_kCapabilityInputIME));
}

bool GHOST_SystemVinix::setConsoleWindowState(GHOST_TConsoleWindowState /*action*/)
{
  return false;
}

char *GHOST_SystemVinix::getClipboard(bool /*selection*/) const
{
  return nullptr;
}

void GHOST_SystemVinix::putClipboard(const char * /*buffer*/, bool /*selection*/) const {}

GHOST_IContext *GHOST_SystemVinix::createOffscreenContext(GHOST_GPUSettings gpu_settings)
{
  if (gpu_settings.context_type != GHOST_kDrawingContextTypeOpenGL) {
    return nullptr;
  }
#ifdef WITH_OPENGL_BACKEND
  for (int minor = 6; minor >= 3; --minor) {
    GHOST_Context *context = new GHOST_ContextEGL(this,
                                                  false,
                                                  EGLNativeWindowType(0),
                                                  EGLNativeDisplayType(EGL_DEFAULT_DISPLAY),
                                                  EGL_CONTEXT_OPENGL_CORE_PROFILE_BIT,
                                                  4,
                                                  minor,
                                                  GHOST_OPENGL_EGL_CONTEXT_FLAGS,
                                                  GHOST_OPENGL_EGL_RESET_NOTIFICATION_STRATEGY,
                                                  EGL_OPENGL_API);
    if (context->initializeDrawingContext()) {
      return context;
    }
    delete context;
  }
#endif
  return nullptr;
}

GHOST_TSuccess GHOST_SystemVinix::disposeContext(GHOST_IContext *context)
{
  delete context;
  return GHOST_kSuccess;
}

void GHOST_SystemVinix::addDirtyWindow(GHOST_WindowVinix *window)
{
  m_dirty_windows.push_back(window);
}

void GHOST_SystemVinix::emitKey(GHOST_TKey key, const char *utf8, bool shift, bool control)
{
  GHOST_IWindow *window = m_windowManager->getActiveWindow();
  if (!window || key == GHOST_kKeyUnknown) {
    return;
  }
  const uint64_t now = getMilliSeconds();
  if (control) {
    pushEvent(new GHOST_EventKey(now, GHOST_kEventKeyDown, window, GHOST_kKeyLeftControl, false));
  }
  if (shift) {
    pushEvent(new GHOST_EventKey(now, GHOST_kEventKeyDown, window, GHOST_kKeyLeftShift, false));
  }
  pushEvent(new GHOST_EventKey(now, GHOST_kEventKeyDown, window, key, false, utf8));
  pushEvent(new GHOST_EventKey(now, GHOST_kEventKeyUp, window, key, false));
  if (shift) {
    pushEvent(new GHOST_EventKey(now, GHOST_kEventKeyUp, window, GHOST_kKeyLeftShift, false));
  }
  if (control) {
    pushEvent(new GHOST_EventKey(now, GHOST_kEventKeyUp, window, GHOST_kKeyLeftControl, false));
  }
}

void GHOST_SystemVinix::emitSpecialKey(GHOST_TKey key)
{
  emitKey(key);
}

void GHOST_SystemVinix::emitText(const uint8_t *data, size_t size)
{
  for (size_t i = 0; i < size;) {
    if (data[i] == 0x1b) {
      if (i + 2 < size && data[i + 1] == '[') {
        GHOST_TKey key = GHOST_kKeyUnknown;
        size_t consumed = 3;
        switch (data[i + 2]) {
          case 'A':
            key = GHOST_kKeyUpArrow;
            break;
          case 'B':
            key = GHOST_kKeyDownArrow;
            break;
          case 'C':
            key = GHOST_kKeyRightArrow;
            break;
          case 'D':
            key = GHOST_kKeyLeftArrow;
            break;
          case 'H':
            key = GHOST_kKeyHome;
            break;
          case 'F':
            key = GHOST_kKeyEnd;
            break;
          case '2':
            if (i + 3 < size && data[i + 3] == '~') {
              key = GHOST_kKeyInsert;
              consumed = 4;
            }
            break;
          case '3':
            if (i + 3 < size && data[i + 3] == '~') {
              key = GHOST_kKeyDelete;
              consumed = 4;
            }
            break;
          case '5':
            if (i + 3 < size && data[i + 3] == '~') {
              key = GHOST_kKeyUpPage;
              consumed = 4;
            }
            break;
          case '6':
            if (i + 3 < size && data[i + 3] == '~') {
              key = GHOST_kKeyDownPage;
              consumed = 4;
            }
            break;
          default:
            break;
        }
        if (key != GHOST_kKeyUnknown) {
          emitSpecialKey(key);
          i += consumed;
          continue;
        }
      }
      if (i + 2 < size && data[i + 1] == 'O' && data[i + 2] >= 'P' && data[i + 2] <= 'S') {
        emitSpecialKey(GHOST_TKey(int(GHOST_kKeyF1) + data[i + 2] - 'P'));
        i += 3;
        continue;
      }
      emitSpecialKey(GHOST_kKeyEsc);
      ++i;
      continue;
    }

    if (data[i] >= 1 && data[i] <= 26) {
      emitKey(GHOST_TKey(int(GHOST_kKeyA) + data[i] - 1), nullptr, false, true);
      ++i;
      continue;
    }

    size_t utf8_size = 1;
    if ((data[i] & 0xe0) == 0xc0)
      utf8_size = 2;
    else if ((data[i] & 0xf0) == 0xe0)
      utf8_size = 3;
    else if ((data[i] & 0xf8) == 0xf0)
      utf8_size = 4;
    utf8_size = std::min(utf8_size, size - i);
    char utf8[6] = {};
    std::memcpy(utf8, data + i, utf8_size);
    bool shift = false;
    const GHOST_TKey key = utf8_size == 1 ? ascii_key(data[i], shift) : GHOST_kKeyUnknown;
    if (key == GHOST_kKeyUnknown && utf8_size > 1) {
      GHOST_IWindow *window = m_windowManager->getActiveWindow();
      if (window) {
        const uint64_t now = getMilliSeconds();
        pushEvent(new GHOST_EventKey(now, GHOST_kEventKeyDown, window, key, false, utf8));
        pushEvent(new GHOST_EventKey(now, GHOST_kEventKeyUp, window, key, false));
      }
    }
    else {
      emitKey(key, utf8, shift, false);
    }
    i += utf8_size;
  }
}

void GHOST_SystemVinix::processInputRecord(
    uint32_t kind, int32_t x, int32_t y, int32_t value, const uint8_t *data, size_t size)
{
  GHOST_IWindow *window = m_windowManager->getActiveWindow();
  if (!window) {
    return;
  }
  const VinixInputEventKind event_kind = VinixInputEventKind(kind);
  if (event_kind == VinixInputEventKind::Keys) {
    emitText(data, size);
    return;
  }

  m_cursor_x = std::clamp(x, 0, int32_t(m_width - 1));
  m_cursor_y = std::clamp(y, 0, int32_t(m_height - 1));
  const uint64_t now = getMilliSeconds();
  pushEvent(new GHOST_EventCursor(
      now, GHOST_kEventCursorMove, window, m_cursor_x, m_cursor_y, GHOST_TABLET_DATA_NONE));
  if (event_kind == VinixInputEventKind::Wheel) {
    if (value != 0) {
      pushEvent(new GHOST_EventWheel(now, window, value));
    }
    return;
  }
  if (event_kind == VinixInputEventKind::ButtonDown || event_kind == VinixInputEventKind::ButtonUp)
  {
    const bool down = event_kind == VinixInputEventKind::ButtonDown;
    GHOST_TButton button = GHOST_kButtonMaskNone;
    switch (VinixPointerButton(value)) {
      case VinixPointerButton::Left:
        button = GHOST_kButtonMaskLeft;
        m_left_button = down;
        break;
      case VinixPointerButton::Middle:
        button = GHOST_kButtonMaskMiddle;
        m_middle_button = down;
        break;
      case VinixPointerButton::Right:
        button = GHOST_kButtonMaskRight;
        m_right_button = down;
        break;
      default:
        return;
    }
    pushEvent(new GHOST_EventButton(now,
                                    down ? GHOST_kEventButtonDown : GHOST_kEventButtonUp,
                                    window,
                                    button,
                                    GHOST_TABLET_DATA_NONE));
  }
}

bool GHOST_SystemVinix::processInputRecords()
{
  bool processed = false;
  while (m_input_buffer.size() >= sizeof(VinixInputEvent)) {
    VinixInputEvent event = {};
    std::memcpy(&event, m_input_buffer.data(), sizeof(event));
    if (event.magic != VINIX_INPUT_EVENT_MAGIC ||
        event.kind < uint32_t(VinixInputEventKind::Motion) ||
        event.kind > uint32_t(VinixInputEventKind::Wheel) ||
        event.length > VINIX_INPUT_MAX_PAYLOAD ||
        (event.kind != uint32_t(VinixInputEventKind::Keys) && event.length != 0))
    {
      m_input_buffer.clear();
      return processed;
    }
    const size_t record_size = sizeof(event) + event.length;
    if (m_input_buffer.size() < record_size) {
      break;
    }
    processInputRecord(event.kind,
                       event.x,
                       event.y,
                       event.value,
                       m_input_buffer.data() + sizeof(event),
                       event.length);
    m_input_buffer.erase(m_input_buffer.begin(), m_input_buffer.begin() + record_size);
    processed = true;
  }
  return processed;
}

bool GHOST_SystemVinix::readInput()
{
  bool received_any = false;
  uint8_t chunk[4096];
  while (!m_input_closed) {
    const ssize_t received = read(STDIN_FILENO, chunk, sizeof(chunk));
    if (received > 0) {
      m_input_buffer.insert(m_input_buffer.end(), chunk, chunk + received);
      received_any = true;
      if (m_input_buffer.size() > 1024 * 1024) {
        m_input_buffer.clear();
      }
      continue;
    }
    if (received == 0) {
      m_input_closed = true;
      break;
    }
    if (errno == EINTR) {
      continue;
    }
    if (errno != EAGAIN && errno != EWOULDBLOCK) {
      m_input_closed = true;
    }
    break;
  }
  return processInputRecords() || received_any;
}

bool GHOST_SystemVinix::processEvents(bool wait_for_event)
{
  bool processed = false;
  do {
    if (wait_for_event && m_dirty_windows.empty() && !m_input_closed) {
      int timeout = -1;
      const uint64_t next = getTimerManager()->nextFireTime();
      if (next != GHOST_kFireTimeNever) {
        const uint64_t now = getMilliSeconds();
        timeout = next <= now ? 0 : int(std::min<uint64_t>(next - now, INT32_MAX));
      }
      struct pollfd descriptor = {STDIN_FILENO, POLLIN | POLLHUP, 0};
      while (poll(&descriptor, 1, timeout) < 0 && errno == EINTR) {
      }
    }

    processed = readInput() || processed;
    if (getTimerManager()->fireTimers(getMilliSeconds())) {
      processed = true;
    }
    for (GHOST_WindowVinix *window : m_dirty_windows) {
      window->validate();
      pushEvent(new GHOST_Event(getMilliSeconds(), GHOST_kEventWindowUpdate, window));
      processed = true;
    }
    m_dirty_windows.clear();

    if (m_input_closed && !m_close_sent) {
      GHOST_IWindow *window = m_windowManager->getActiveWindow();
      pushEvent(new GHOST_Event(getMilliSeconds(), GHOST_kEventQuitRequest, window));
      m_close_sent = true;
      processed = true;
    }
  } while (wait_for_event && !processed && !m_input_closed);
  return processed;
}
