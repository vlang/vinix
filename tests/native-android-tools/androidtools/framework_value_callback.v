// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools
import os

pub fn framework_value_callback_source(original string) !string {
 lines := original.split_into_lines().map(it.all_before('#').trim_space()).filter(it != '' && !it.starts_with('.source '))
 headers := lines.filter(it.starts_with('.method '))
 if lines.filter(it.starts_with('.super ')) != ['.super Ljava/lang/Object;']
  || lines.any(it.starts_with('.field ') || it.starts_with('.implements ')) {
  return error('unexpected ValueCallback hierarchy or fields')
 }
 classes := lines.filter(it.starts_with('.class '))
 if classes == ['.class public Landroid/webkit/ValueCallback;'] {
  if lines != ['.class public Landroid/webkit/ValueCallback;', '.super Ljava/lang/Object;',
   '.method public constructor <init>()V', '.registers 1',
   'invoke-direct {p0}, Ljava/lang/Object;-><init>()V', 'return-void', '.end method'] {
   return error('canonical empty ValueCallback class required')
  }
 } else if classes == ['.class public interface abstract Landroid/webkit/ValueCallback;'] {
  // Also accept the correct interface supplied by the ATL source patch.
  if headers != ['.method public abstract onReceiveValue(Ljava/lang/Object;)V']
   || lines.filter(it == '.end method').len != 1
   || lines.any(it.starts_with('.locals ') || it.starts_with('.registers ')
    || it.starts_with('invoke-') || it.starts_with('return')) {
   return error('canonical ValueCallback interface required')
  }
 } else { return error('unexpected ValueCallback declaration') }
 return r'
.class public interface abstract Landroid/webkit/ValueCallback;
.super Ljava/lang/Object;
.annotation system Ldalvik/annotation/Signature;
value = {"<T:Ljava/lang/Object;>", "Ljava/lang/Object;"}
.end annotation
.method public abstract onReceiveValue(Ljava/lang/Object;)V
.annotation system Ldalvik/annotation/Signature;
value = {"(TT;)V"}
.end annotation
.end method
'
}

pub fn framework_value_callback(smali string) ! {
 path := smali + '/android/webkit/ValueCallback.smali'
 os.write_file(path, framework_value_callback_source(os.read_file(path)!)!)!
}
