#!/usr/bin/env python3
"""Return success when a viewable X11 window contains the requested title."""

import ctypes
import sys


Display = ctypes.c_void_p
Window = ctypes.c_ulong


class XWindowAttributes(ctypes.Structure):
    _fields_ = [
        ("x", ctypes.c_int),
        ("y", ctypes.c_int),
        ("width", ctypes.c_int),
        ("height", ctypes.c_int),
        ("border_width", ctypes.c_int),
        ("depth", ctypes.c_int),
        ("visual", ctypes.c_void_p),
        ("root", Window),
        ("window_class", ctypes.c_int),
        ("bit_gravity", ctypes.c_int),
        ("win_gravity", ctypes.c_int),
        ("backing_store", ctypes.c_int),
        ("backing_planes", ctypes.c_ulong),
        ("backing_pixel", ctypes.c_ulong),
        ("save_under", ctypes.c_int),
        ("colormap", ctypes.c_ulong),
        ("map_installed", ctypes.c_int),
        ("map_state", ctypes.c_int),
        ("all_event_masks", ctypes.c_long),
        ("your_event_mask", ctypes.c_long),
        ("do_not_propagate_mask", ctypes.c_long),
        ("override_redirect", ctypes.c_int),
        ("screen", ctypes.c_void_p),
    ]


def configure_xlib(xlib):
    xlib.XOpenDisplay.argtypes = [ctypes.c_char_p]
    xlib.XOpenDisplay.restype = Display
    xlib.XDefaultRootWindow.argtypes = [Display]
    xlib.XDefaultRootWindow.restype = Window
    xlib.XQueryTree.argtypes = [
        Display,
        Window,
        ctypes.POINTER(Window),
        ctypes.POINTER(Window),
        ctypes.POINTER(ctypes.POINTER(Window)),
        ctypes.POINTER(ctypes.c_uint),
    ]
    xlib.XQueryTree.restype = ctypes.c_int
    xlib.XGetWindowAttributes.argtypes = [
        Display,
        Window,
        ctypes.POINTER(XWindowAttributes),
    ]
    xlib.XGetWindowAttributes.restype = ctypes.c_int
    xlib.XFetchName.argtypes = [Display, Window, ctypes.POINTER(ctypes.c_void_p)]
    xlib.XFetchName.restype = ctypes.c_int
    xlib.XFree.argtypes = [ctypes.c_void_p]
    xlib.XFree.restype = ctypes.c_int
    xlib.XInternAtom.argtypes = [Display, ctypes.c_char_p, ctypes.c_int]
    xlib.XInternAtom.restype = ctypes.c_ulong
    xlib.XGetWindowProperty.argtypes = [
        Display,
        Window,
        ctypes.c_ulong,
        ctypes.c_long,
        ctypes.c_long,
        ctypes.c_int,
        ctypes.c_ulong,
        ctypes.POINTER(ctypes.c_ulong),
        ctypes.POINTER(ctypes.c_int),
        ctypes.POINTER(ctypes.c_ulong),
        ctypes.POINTER(ctypes.c_ulong),
        ctypes.POINTER(ctypes.c_void_p),
    ]
    xlib.XGetWindowProperty.restype = ctypes.c_int
    xlib.XCloseDisplay.argtypes = [Display]
    xlib.XCloseDisplay.restype = ctypes.c_int


def net_wm_name(xlib, display, window):
    """The UTF-8 title. Chromium sets only this one, not the legacy WM_NAME."""
    name_atom = xlib.XInternAtom(display, b"_NET_WM_NAME", True)
    utf8_atom = xlib.XInternAtom(display, b"UTF8_STRING", True)
    if not name_atom or not utf8_atom:
        return ""
    actual_type = ctypes.c_ulong()
    actual_format = ctypes.c_int()
    items = ctypes.c_ulong()
    remaining = ctypes.c_ulong()
    data = ctypes.c_void_p()
    status = xlib.XGetWindowProperty(
        display, window, name_atom, 0, 1024, False, utf8_atom,
        ctypes.byref(actual_type), ctypes.byref(actual_format),
        ctypes.byref(items), ctypes.byref(remaining), ctypes.byref(data),
    )
    if status != 0 or not data.value:
        return ""
    try:
        return ctypes.string_at(data.value, items.value).decode("utf-8", "replace")
    finally:
        xlib.XFree(data)


def window_title(xlib, display, window):
    title = ctypes.c_void_p()
    if xlib.XFetchName(display, window, ctypes.byref(title)) and title.value:
        try:
            return ctypes.string_at(title.value).decode("utf-8", "replace")
        finally:
            xlib.XFree(title)
    return net_wm_name(xlib, display, window)


def find_window(xlib, display, window, expected, depth=0):
    if depth > 8:
        return None

    root = Window()
    parent = Window()
    children = ctypes.POINTER(Window)()
    count = ctypes.c_uint()
    if not xlib.XQueryTree(
        display,
        window,
        ctypes.byref(root),
        ctypes.byref(parent),
        ctypes.byref(children),
        ctypes.byref(count),
    ):
        return None

    try:
        for index in range(count.value):
            child = children[index]
            attributes = XWindowAttributes()
            if xlib.XGetWindowAttributes(display, child, ctypes.byref(attributes)):
                title = window_title(xlib, display, child)
                if attributes.map_state == 2 and expected in title:
                    return title
            match = find_window(xlib, display, child, expected, depth + 1)
            if match:
                return match
    finally:
        if children:
            xlib.XFree(children)
    return None


def main():
    if len(sys.argv) != 3:
        print(f"usage: {sys.argv[0]} DISPLAY TITLE", file=sys.stderr)
        return 2

    xlib = ctypes.CDLL("libX11.so.6")
    configure_xlib(xlib)
    display = xlib.XOpenDisplay(sys.argv[1].encode("ascii"))
    if not display:
        return 1
    try:
        title = find_window(
            xlib,
            display,
            xlib.XDefaultRootWindow(display),
            sys.argv[2],
        )
        if not title:
            return 1
        print(f"WINDOW={title}")
        return 0
    finally:
        xlib.XCloseDisplay(display)


if __name__ == "__main__":
    raise SystemExit(main())
