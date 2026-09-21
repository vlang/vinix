import ctypes


class Pattern(ctypes.Structure):
    pass


Pattern._fields_ = [
    ("prefix", ctypes.c_void_p),
    ("mask", ctypes.c_char_p),
    ("relevance", ctypes.c_int),
]


class Format(ctypes.Structure):
    pass


Format._fields_ = [
    ("name", ctypes.c_char_p),
    ("signature", ctypes.POINTER(Pattern)),
    ("domain", ctypes.c_char_p),
    ("description", ctypes.c_char_p),
    ("mime_types", ctypes.c_void_p),
    ("extensions", ctypes.c_void_p),
    ("flags", ctypes.c_uint32),
    ("disabled", ctypes.c_int),
    ("license", ctypes.c_char_p),
]


class GSList(ctypes.Structure):
    pass


ListPointer = ctypes.POINTER(GSList)
GSList._fields_ = [("data", ctypes.c_void_p), ("next", ListPointer)]

libc = ctypes.CDLL(None)
libc.fopen.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
libc.fopen.restype = ctypes.c_void_p
libc.fread.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_size_t, ctypes.c_void_p]
libc.fread.restype = ctypes.c_size_t
stream = libc.fopen(b"/usr/share/icons/hicolor/16x16/apps/firefox-esr.png", b"rb")
buffer = ctypes.create_string_buffer(128)
count = libc.fread(buffer, 1, 128, stream)
print("fread", count, repr(buffer.raw[:16]), flush=True)

gio = ctypes.CDLL("libgio-2.0.so.0")
gio.g_content_type_guess.argtypes = [
    ctypes.c_char_p,
    ctypes.c_void_p,
    ctypes.c_size_t,
    ctypes.POINTER(ctypes.c_int),
]
gio.g_content_type_guess.restype = ctypes.c_char_p
for filename in (None, b"firefox-esr.png"):
    uncertain = ctypes.c_int()
    content_type = gio.g_content_type_guess(
        filename, buffer, count, ctypes.byref(uncertain)
    )
    print(
        "content type",
        filename,
        content_type,
        "uncertain",
        uncertain.value,
        flush=True,
    )

library = ctypes.CDLL("libgdk_pixbuf-2.0.so.0")
library.gdk_pixbuf_get_formats.restype = ListPointer
item = library.gdk_pixbuf_get_formats()
while item:
    image_format = ctypes.cast(item.contents.data, ctypes.POINTER(Format)).contents
    if image_format.name == b"png":
        print("format", image_format.name, "disabled", image_format.disabled, flush=True)
        for index in range(5):
            pattern = image_format.signature[index]
            if not pattern.prefix:
                print("end", index, flush=True)
                break
            print(
                index,
                repr(ctypes.string_at(pattern.prefix)),
                repr(pattern.mask),
                pattern.relevance,
                flush=True,
            )
    item = item.contents.next
