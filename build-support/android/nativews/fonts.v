// SPDX-License-Identifier: GPL-2.0-or-later
@[translated]
module atlframework

struct WsFont {
mut:
 references i32 = 1
 info voidptr
 asset voidptr
}

fn ws_font_ref(font &WsFont) {
 if font != unsafe { nil } { C.__atomic_add_fetch(&font.references, 1, 5) }
}

fn ws_font_unref(font &WsFont) {
 unsafe {
  if font == nil || C.__atomic_sub_fetch(&font.references, 1, 5) != 0 { return }
  C.Asset_delete(font.asset)
  C.free(font.info)
  C.free(font)
 }
}

fn ws_font_info(font &WsFont) voidptr {
 return if font == unsafe { nil } { ws_font } else { font.info }
}

fn ws_typeface_font(e voidptr, face voidptr) &WsFont {
 unsafe { return if face == nil { &WsFont(nil) } else { &WsFont(get_long(e, face, c'android/graphics/Typeface', c'native_instance')) } }
}

fn ws_font_load(e voidptr, assets voidptr, path voidptr) voidptr {
 unsafe {
  asset := voidptr(ws_open_asset(e, assets, path, 3))
  if asset == nil { return nil }
  info := C.calloc(1, sizeof(C.stbtt_fontinfo))
  if C.Asset_getLength(asset) < 12 || C.stbtt_InitFont(info, C.Asset_getBuffer(asset, true), 0) == 0 {
   C.free(info)
   C.Asset_delete(asset)
   return nil
  }
  font := &WsFont(C.malloc(sizeof(WsFont)))
  *font = WsFont{info: info, asset: asset}
  face := new_object(e, c'android/graphics/Typeface', c'()V', nil)
  if pending(e) || face == nil { ws_font_unref(font); return nil }
  ws_put_long(e, face, c'android/graphics/Typeface', c'native_instance', i64(font))
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
 ws_font_ref(font)
 native := ws_view(e, view)
 ws_font_unref(native.font)
 native.font = font
 put_object(e, view, c'android/widget/TextView', c'vinixTypeface', c'Landroid/graphics/Typeface;', face)
 ws_mark()
}
