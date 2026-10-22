// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn rect_parcel_method(signature string, body string) string {
 return '.method public ' + signature + '\n.locals 2\n' + body + '\n.end method\n'
}

fn framework_rect_parcels(smali string) ! {
 for name in ['Rect', 'RectF'] {
  class := 'Landroid/graphics/${name};'
  creator := 'Landroid/graphics/Vinix${name}Creator;'
  path := smali + '/android/graphics/${name}.smali'
  mut text := os.read_file(path)!
  text = text.replace('.super Ljava/lang/Object;', '.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable;')
  text += '\n.field public static final CREATOR:Landroid/os/Parcelable\$Creator;\n'
  initialize := 'new-instance v0, ${creator}\ninvoke-direct {v0}, ${creator}-><init>()V\nsput-object v0, ${class}->CREATOR:Landroid/os/Parcelable\$Creator;\n'
  if text.contains(' <clinit>()V\n') {
   start := text.index(' <clinit>()V\n') or { return error('missing rectangle initializer') }
   end := start + (text[start..].index('.end method') or { return error('unterminated rectangle initializer') })
   text = text[..start] + text[start..end].replace('return-void', initialize + 'return-void') + text[end..]
  } else {
   text += '.method static constructor <clinit>()V\n.locals 1\n' + initialize + 'return-void\n.end method\n'
  }
  kind := if name == 'Rect' { 'I' } else { 'F' }
  primitive := if name == 'Rect' { 'Int' } else { 'Float' }
  mut write := ''
  mut read := ''
  for field in ['left', 'top', 'right', 'bottom'] {
   write += 'iget v0, p0, ${class}->${field}:${kind}\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->write${primitive}(${kind})V\n'
   read += 'invoke-virtual {p1}, Landroid/os/Parcel;->read${primitive}()${kind}\nmove-result v0\niput v0, p0, ${class}->${field}:${kind}\n'
  }
  text = framework_replace_method(text, 'describeContents()I', rect_parcel_method('describeContents()I', 'const/4 v0, 0\nreturn v0'))!
  text = framework_replace_method(text, 'writeToParcel(Landroid/os/Parcel;I)V', rect_parcel_method('writeToParcel(Landroid/os/Parcel;I)V', write + 'return-void'))!
  text = framework_replace_method(text, 'readFromParcel(Landroid/os/Parcel;)V', rect_parcel_method('readFromParcel(Landroid/os/Parcel;)V', read + 'return-void'))!
  os.write_file(path, text)!
  os.write_file(smali + '/android/graphics/Vinix${name}Creator.smali', '.class public final ${creator}\n.super Ljava/lang/Object;\n.implements Landroid/os/Parcelable\$Creator;\n' +
   rect_parcel_method('constructor <init>()V', 'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\nreturn-void') +
   rect_parcel_method('createFromParcel(Landroid/os/Parcel;)${class}', 'new-instance v0, ${class}\ninvoke-direct {v0}, ${class}-><init>()V\ninvoke-virtual {v0, p1}, ${class}->readFromParcel(Landroid/os/Parcel;)V\nreturn-object v0') +
   rect_parcel_method('bridge synthetic createFromParcel(Landroid/os/Parcel;)Ljava/lang/Object;', 'invoke-virtual {p0, p1}, ${creator}->createFromParcel(Landroid/os/Parcel;)${class}\nmove-result-object v0\nreturn-object v0') +
   rect_parcel_method('newArray(I)[${class}', 'new-array v0, p1, [${class}\nreturn-object v0') +
   rect_parcel_method('bridge synthetic newArray(I)[Ljava/lang/Object;', 'invoke-virtual {p0, p1}, ${creator}->newArray(I)[${class}\nmove-result-object v0\nreturn-object v0'))!
 }
}
