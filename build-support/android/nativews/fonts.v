// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

struct WsFont {
mut:
 references i32 = 1
 info voidptr
 asset voidptr
 data voidptr
 borrowed bool
}

// One retained cache reference per installed static face (three families,
// four styles). Java typefaces, Paint and TextView own additional references.
__global ws_system_fonts [12]&WsFont
__global ws_font_mutex C.pthread_mutex_t

type WsCharRelease = fn (voidptr, voidptr, &u16, i32)

// The public APIs use UTF-16 offsets, with a count for char[] and an exclusive
// end for String. Decode pairs only within that range, including embedded NUL.
// Advances match this backend's Canvas rasterizer; complex shaping is absent.
fn ws_measure_text(e voidptr, paint voidptr, text voidptr, start i32, limit i32, array bool) f32 {
 unsafe {
  if text == nil { throw(e, c'java/lang/IllegalArgumentException', c'text cannot be null'); return 0 }
  length := WsLength(slot(e, if array { 171 } else { 164 }))(e, text)
  count := if array { i64(limit) } else { i64(limit) - i64(start) }
  if start < 0 || count < 0 || i64(start) + count > i64(length) {
   kind := if array { &char(c'java/lang/ArrayIndexOutOfBoundsException') } else { &char(c'java/lang/IndexOutOfBoundsException') }
   throw(e, kind, c'invalid text range'); return 0
  }
  if count == 0 { return 0 }
  chars := WsChars(slot(e, if array { 185 } else { 165 }))(e, text, nil)
  if chars == nil { return 0 }
  defer {
   if array { WsCharRelease(slot(e, 193))(e, text, chars, 2) }
   else { WsCharsRelease(slot(e, 166))(e, text, chars) }
  }
  native := &WsPaint(get_long(e, paint, c'android/graphics/Paint', c'paint'))
  if pending(e) { return 0 }
  info := ws_font_info(native.font)
  if info == nil { return 0 }
  scale := C.stbtt_ScaleForPixelHeight(info, native.size)
  mut width := f32(0)
  mut pos := i64(start)
  end := pos + count
  for pos < end {
   mut code := i32(chars[pos])
   pos++
   if code >= 0xd800 && code <= 0xdbff && pos < end && chars[pos] >= 0xdc00 && chars[pos] <= 0xdfff {
    code = 0x10000 + ((code - 0xd800) << 10) + i32(chars[pos]) - 0xdc00
    pos++
   } else if code >= 0xd800 && code <= 0xdfff { code = 0xfffd }
   mut advance := i32(0)
   mut bearing := i32(0)
   C.stbtt_GetCodepointHMetrics(info, code, &advance, &bearing)
   width += f32(advance) * scale
  }
  return C.ceilf(width)
 }
}

// Return raw advances per UTF-16 code unit. Paired low surrogates have zero
// advance; the font and decoder match measureText and Canvas's rasterizer.
fn ws_text_widths(e voidptr, paint voidptr, text voidptr, start i32, limit i32, widths voidptr, array bool) i32 {
 unsafe {
  if text == nil { throw(e, c'java/lang/IllegalArgumentException', c'text cannot be null'); return 0 }
  length := WsLength(slot(e, if array { 171 } else { 164 }))(e, text)
  count := if array { i64(limit) } else { i64(limit) - i64(start) }
  if start < 0 || count < 0 || i64(start) + count > i64(length) {
   kind := if array { &char(c'java/lang/ArrayIndexOutOfBoundsException') } else { &char(c'java/lang/IndexOutOfBoundsException') }
   throw(e, kind, c'invalid text range'); return 0
  }
  if widths == nil { throw(e, c'java/lang/NullPointerException', c'widths cannot be null'); return 0 }
  if count > i64(WsLength(slot(e, 171))(e, widths)) {
   throw(e, c'java/lang/ArrayIndexOutOfBoundsException', c'widths array too short'); return 0
  }
  if count == 0 { return 0 }
  native := &WsPaint(get_long(e, paint, c'android/graphics/Paint', c'paint'))
  if pending(e) { return 0 }
  info := ws_font_info(native.font)
  if info == nil { return 0 }
  chars := WsChars(slot(e, if array { 185 } else { 165 }))(e, text, nil)
  if chars == nil { return 0 }
  defer {
   if array { WsCharRelease(slot(e, 193))(e, text, chars, 2) }
   else { WsCharsRelease(slot(e, 166))(e, text, chars) }
  }
  // Stage all advances before touching Java output, including on OOM.
  data := &f32(C.calloc(usize(count), sizeof(f32)))
  if data == nil { throw(e, c'java/lang/OutOfMemoryError', c'text widths allocation'); return 0 }
  defer { C.free(data) }
  scale := C.stbtt_ScaleForPixelHeight(info, native.size)
  mut pos := i64(start)
  end := pos + count
  for pos < end {
   index := pos - i64(start)
   mut code := i32(chars[pos])
   pos++
   if code >= 0xd800 && code <= 0xdbff && pos < end && chars[pos] >= 0xdc00 && chars[pos] <= 0xdfff {
    code = 0x10000 + ((code - 0xd800) << 10) + i32(chars[pos]) - 0xdc00
    pos++
   } else if code >= 0xd800 && code <= 0xdfff { code = 0xfffd }
   mut advance := i32(0)
   mut bearing := i32(0)
   C.stbtt_GetCodepointHMetrics(info, code, &advance, &bearing)
   data[index] = f32(advance) * scale
  }
  WsFloatRegion(slot(e, 213))(e, widths, 0, i32(count), data)
  return if pending(e) { 0 } else { i32(count) }
 }
}

fn ws_font_ref(font &WsFont) {
 if font != unsafe { nil } { C.__atomic_add_fetch(&font.references, 1, 5) }
}

fn ws_font_unref(font &WsFont) {
 unsafe {
  if font == nil || C.__atomic_sub_fetch(&font.references, 1, 5) != 0 { return }
  if font.asset != nil { C.Asset_delete(font.asset) }
  if !font.borrowed { C.free(font.info) }
  C.free(font.data)
  C.free(font)
 }
}

fn ws_font_info(font &WsFont) voidptr {
 return if font == unsafe { nil } { ws_font } else { font.info }
}

fn ws_typeface_font(e voidptr, face voidptr) &WsFont {
 unsafe {
  if face == nil || pending(e) { return nil }
  m := method(e, c'android/graphics/Typeface', c'vinixResolve', c'()J')
  if m == nil { return nil }
  return &WsFont(WsLongCall(slot(e, 54))(e, face, m, nil))
 }
}

fn ws_system_font(e voidptr, family i32, style i32) &WsFont {
 unsafe {
  C.pthread_mutex_lock(&ws_font_mutex)
  defer { C.pthread_mutex_unlock(&ws_font_mutex) }
  index := family * 4 + style
  if ws_system_fonts[index] != nil { return ws_system_fonts[index] }
  mut info := ws_font
  mut data := voidptr(nil)
  if index != 0 {
   name := if family == 1 { &char(c'DejaVuSerif') } else if family == 2 { &char(c'DejaVuSansMono') } else { &char(c'DejaVuSans') }
   suffix := if style == 1 { &char(c'-Bold') } else if style == 2 { if family == 1 { &char(c'-Italic') } else { &char(c'-Oblique') } } else if style == 3 { if family == 1 { &char(c'-BoldItalic') } else { &char(c'-BoldOblique') } } else { &char(c'') }
   path := &char(C.alloca(8192))
   C.snprintf(path, 8192, c'%s/usr/share/fonts/dejavu/%s%s.ttf', ws.root, name, suffix)
   fd := C.open(path, 0)
   if fd < 0 { throw(e, c'java/lang/RuntimeException', c'installed system font missing'); return nil }
   defer { C.close(fd) }
   length := C.lseek(fd, 0, 2)
   C.lseek(fd, 0, 0)
   if length < 12 || length > 64 * 1024 * 1024 { throw(e, c'java/lang/RuntimeException', c'invalid system font'); return nil }
   data = C.malloc(usize(length))
   info = C.calloc(1, sizeof(C.stbtt_fontinfo))
   if data == nil || info == nil {
    C.free(data); C.free(info)
    throw(e, c'java/lang/OutOfMemoryError', c'system font allocation'); return nil
   }
   mut used := i64(0)
   for used < length {
    count := C.read(fd, voidptr(usize(data) + usize(used)), usize(length - used))
    if count <= 0 { break }
    used += count
   }
   if used != length || C.stbtt_InitFont(info, data, 0) == 0 {
    C.free(data); C.free(info)
    throw(e, c'java/lang/RuntimeException', c'system font could not be read'); return nil
   }
  }
  font := &WsFont(C.malloc(sizeof(WsFont)))
  if font == nil {
   if index != 0 { C.free(data); C.free(info) }
   throw(e, c'java/lang/OutOfMemoryError', c'system font allocation'); return nil
  }
  *font = WsFont{info: info, data: data, borrowed: index == 0}
  ws_system_fonts[index] = font
  return font
 }
}

// Called through a synchronized Java method so resolution installs exactly one
// owned reference. A derived resource face retains its original asset-backed
// font; system families select the nearest installed regular/bold/italic face.
fn ws_typeface_resolve(e voidptr, face voidptr) i64 {
 unsafe {
  pointer := get_long(e, face, c'android/graphics/Typeface', c'native_instance')
  if pointer != 0 || pending(e) { return pointer }
  source := get_object(e, face, c'android/graphics/Typeface', c'vinixSource', c'Landroid/graphics/Typeface;')
  mut font := &WsFont(nil)
  if source != nil {
   base := ws_typeface_font(e, source)
   if pending(e) { return 0 }
   if base != nil && base.asset != nil { font = base }
  }
  if font == nil {
   name := get_object(e, face, c'android/graphics/Typeface', c'vinixFamily', c'Ljava/lang/String;')
   mut family := i32(0)
   if name != nil {
    chars := ws_utf(e, name)
    if C.strcmp(chars, c'serif') == 0 { family = 1 }
    if C.strcmp(chars, c'monospace') == 0 { family = 2 }
    ws_release(e, name, chars)
   }
   weight := get_int(e, face, c'android/graphics/Typeface', c'vinixWeight')
   italic := get_int(e, face, c'android/graphics/Typeface', c'vinixSlant')
   style := (if weight >= 550 { i32(1) } else { i32(0) }) + italic * 2
   font = ws_system_font(e, family, style)
  }
  if pending(e) || font == nil { return 0 }
  ws_font_ref(font)
  ws_put_long(e, face, c'android/graphics/Typeface', c'native_instance', i64(font))
  return i64(font)
 }
}

fn ws_font_u16(data &u8, at i64) i32 {
 unsafe { return (i32(data[at]) << 8) | i32(data[at + 1]) }
}

// Read static-face style metadata with bounds independent of stb's parser.
// OS/2 usWeightClass and fsSelection describe the actual resource font, rather
// than assuming every loaded face is regular. Missing tables keep defaults.
fn ws_font_style(e voidptr, face voidptr, data &u8, length i64) {
 unsafe {
  if length < 12 { return }
  count := ws_font_u16(data, 4)
  if i64(count) > (length - 12) / 16 { return }
  for i := i32(0); i < count; i++ {
   at := i64(12) + i64(i) * 16
   if data[at] != 0x4f || data[at + 1] != 0x53 || data[at + 2] != 0x2f || data[at + 3] != 0x32 { continue }
   offset := (u32(data[at + 8]) << 24) | (u32(data[at + 9]) << 16) | (u32(data[at + 10]) << 8) | u32(data[at + 11])
   size := (u32(data[at + 12]) << 24) | (u32(data[at + 13]) << 16) | (u32(data[at + 14]) << 8) | u32(data[at + 15])
   if size < 64 || i64(offset) > length || i64(size) > length - i64(offset) { return }
   weight := ws_font_u16(data, i64(offset) + 4)
   if weight >= 1 && weight <= 1000 { put_int(e, face, c'android/graphics/Typeface', c'vinixWeight', weight) }
   put_int(e, face, c'android/graphics/Typeface', c'vinixSlant', ws_font_u16(data, i64(offset) + 62) & 1)
   return
  }
 }
}

fn ws_font_load(e voidptr, assets voidptr, path voidptr) voidptr {
 unsafe {
  asset := voidptr(ws_open_asset(e, assets, path, 3))
  if asset == nil { return nil }
  info := C.calloc(1, sizeof(C.stbtt_fontinfo))
  if info == nil { C.Asset_delete(asset); throw(e, c'java/lang/OutOfMemoryError', c'font allocation'); return nil }
  if C.Asset_getLength(asset) < 12 || C.stbtt_InitFont(info, C.Asset_getBuffer(asset, true), 0) == 0 {
   C.free(info)
   C.Asset_delete(asset)
   return nil
  }
  font := &WsFont(C.malloc(sizeof(WsFont)))
  if font == nil { C.free(info); C.Asset_delete(asset); throw(e, c'java/lang/OutOfMemoryError', c'font allocation'); return nil }
  *font = WsFont{info: info, asset: asset}
  face := new_object(e, c'android/graphics/Typeface', c'()V', nil)
  if pending(e) || face == nil { ws_font_unref(font); return nil }
  ws_put_long(e, face, c'android/graphics/Typeface', c'native_instance', i64(font))
  ws_font_style(e, face, C.Asset_getBuffer(asset, true), i64(C.Asset_getLength(asset)))
  return face
 }
}

fn ws_resource_font(e voidptr, resources voidptr, id i32, depth i32) voidptr {
 unsafe {
  if depth > 8 { throw(e, c'android/content/res/Resources$NotFoundException', c'cyclic font family'); return nil }
  value := new_object(e, c'android/util/TypedValue', c'()V', nil)
  mut args := &Value(C.alloca(3 * sizeof(Value)))
  args[0] = Value{i: id}
  args[1] = Value{l: value}
  args[2] = Value{i: 1}
  call(e, resources, c'android/content/res/Resources', c'getValue', c'(ILandroid/util/TypedValue;Z)V', args)
  if pending(e) { return nil }
  path_value := get_object(e, value, c'android/util/TypedValue', c'string', c'Ljava/lang/CharSequence;')
  if path_value == nil { throw(e, c'android/content/res/Resources$NotFoundException', c'font is not a file'); return nil }
  path := obj(e, path_value, c'java/lang/Object', c'toString', c'()Ljava/lang/String;', nil)
  chars := ws_utf(e, path)
  xml := C.strlen(chars) >= 4 && C.strcmp(&chars[C.strlen(chars) - 4], c'.xml') == 0
  ws_release(e, path, chars)
  if xml {
   args[0] = Value{i: id}
   parser := obj(e, resources, c'android/content/res/Resources', c'getXml', c'(I)Landroid/content/res/XmlResourceParser;', args)
   if pending(e) { return nil }
   defer {
    exception := ExceptionGet(slot(e, 15))(e)
    if exception != nil { ExceptionClear(slot(e, 17))(e) }
    call(e, parser, c'android/content/res/XmlResourceParser', c'close', c'()V', nil)
    if exception != nil { ExceptionThrow(slot(e, 13))(e, exception) }
   }
   for !pending(e) {
    event := integer(e, parser, c'org/xmlpull/v1/XmlPullParser', c'next', c'()I', nil)
    if event == 1 { break }
    if event != 2 { continue }
    count := integer(e, parser, c'org/xmlpull/v1/XmlPullParser', c'getAttributeCount', c'()I', nil)
    for i := i32(0); i < count; i++ {
     args[0] = Value{i: i}
     args[1] = Value{i: 0}
     name := obj(e, parser, c'org/xmlpull/v1/XmlPullParser', c'getAttributeName', c'(I)Ljava/lang/String;', args)
     attr := ws_utf(e, name)
     is_font := C.strcmp(attr, c'font') == 0
     fallback := C.strcmp(attr, c'fontProviderSystemFontFamily') == 0
     ws_release(e, name, attr)
     if is_font {
      ref := integer(e, parser, c'android/util/AttributeSet', c'getAttributeResourceValue', c'(II)I', args)
      if ref != 0 { return ws_resource_font(e, resources, ref, depth + 1) }
      file := obj(e, parser, c'org/xmlpull/v1/XmlPullParser', c'getAttributeValue', c'(I)Ljava/lang/String;', args)
      assets := obj(e, resources, c'android/content/res/Resources', c'getAssets', c'()Landroid/content/res/AssetManager;', nil)
      result := ws_font_load(e, assets, file)
      if result != nil { return result }
     } else if fallback {
      family := obj(e, parser, c'org/xmlpull/v1/XmlPullParser', c'getAttributeValue', c'(I)Ljava/lang/String;', args)
      args[0] = Value{l: family}
      args[1] = Value{i: 0}
      // Unknown system families use the backend's real default font. There is
      // no remote font provider; no network font download is claimed.
      return static_obj(e, c'android/graphics/Typeface', c'create', c'(Ljava/lang/String;I)Landroid/graphics/Typeface;', args)
     }
    }
   }
  } else {
   assets := obj(e, resources, c'android/content/res/Resources', c'getAssets', c'()Landroid/content/res/AssetManager;', nil)
   result := ws_font_load(e, assets, path)
   if result != nil { return result }
  }
  if !pending(e) { throw(e, c'android/content/res/Resources$NotFoundException', c'font resource could not be loaded') }
  return nil
 }
}

fn ws_paint_typeface(e voidptr, paint voidptr, face voidptr) voidptr {
 old := get_object(e, paint, c'android/graphics/Paint', c'vinixTypeface', c'Landroid/graphics/Typeface;')
 font := ws_typeface_font(e, face)
 if pending(e) { return old }
 ws_font_ref(font)
 unsafe {
  native := &WsPaint(get_long(e, paint, c'android/graphics/Paint', c'paint'))
  ws_font_unref(native.font)
  native.font = font
 }
 put_object(e, paint, c'android/graphics/Paint', c'vinixTypeface', c'Landroid/graphics/Typeface;', face)
 return old
}

fn ws_view_typeface(e voidptr, view voidptr, face voidptr) {
 font := ws_typeface_font(e, face)
 if pending(e) { return }
 ws_font_ref(font)
 native := ws_view(e, view)
 ws_font_unref(native.font)
 native.font = font
 put_object(e, view, c'android/widget/TextView', c'vinixTypeface', c'Landroid/graphics/Typeface;', face)
 ws_mark()
}
