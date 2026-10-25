// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Locale metadata uses Paint's existing ordered locale list. This does not add
// locale-sensitive shaping or glyph fallback to the native text renderer.
pub fn framework_locale_span(smali string) ! {
 owner := 'Landroid/text/style/LocaleSpan;'
 list := 'Landroid/os/LocaleList;'
 locale := 'Ljava/util/Locale;'
 file := smali + '/android/text/style/LocaleSpan.smali'
 if os.exists(file) { return error('LocaleSpan already exists') }
 mut text := '.class public ${owner}\n.super Landroid/text/style/MetricAffectingSpan;\n.implements Landroid/text/ParcelableSpan;\n.implements Landroid/os/Parcelable;\n.field private final vinixLocales:${list}\n'
 for signature, body in {
  'constructor <init>(${locale})V': 'invoke-direct {p0}, Landroid/text/style/MetricAffectingSpan;-><init>()V\nif-eqz p1, :empty\nconst/4 v0, 1\nnew-array v0, v0, [${locale}\nconst/4 v1, 0\naput-object p1, v0, v1\nnew-instance v1, ${list}\ninvoke-direct {v1, v0}, ${list}-><init>([${locale})V\ngoto :store\n:empty\ninvoke-static {}, ${list}->getEmptyLocaleList()${list}\nmove-result-object v1\n:store\niput-object v1, p0, ${owner}->vinixLocales:${list}\nreturn-void'
  'constructor <init>(${list})V': 'invoke-direct {p0}, Landroid/text/style/MetricAffectingSpan;-><init>()V\nif-nez p1, :store\nnew-instance v0, Ljava/lang/NullPointerException;\nconst-string v1, "locales cannot be null"\ninvoke-direct {v0, v1}, Ljava/lang/NullPointerException;-><init>(Ljava/lang/String;)V\nthrow v0\n:store\niput-object p1, p0, ${owner}->vinixLocales:${list}\nreturn-void'
  'constructor <init>(Landroid/os/Parcel;)V': 'invoke-direct {p0}, Landroid/text/style/MetricAffectingSpan;-><init>()V\ninvoke-virtual {p1}, Landroid/os/Parcel;->readString()Ljava/lang/String;\nmove-result-object v0\ninvoke-static {v0}, ${list}->forLanguageTags(Ljava/lang/String;)${list}\nmove-result-object v0\niput-object v0, p0, ${owner}->vinixLocales:${list}\nreturn-void'
  'getLocale()${locale}': 'iget-object v0, p0, ${owner}->vinixLocales:${list}\nconst/4 v1, 0\ninvoke-virtual {v0, v1}, ${list}->get(I)${locale}\nmove-result-object v0\nreturn-object v0'
  'getLocales()${list}': 'iget-object v0, p0, ${owner}->vinixLocales:${list}\nreturn-object v0'
  'getSpanTypeId()I': 'invoke-virtual {p0}, ${owner}->getSpanTypeIdInternal()I\nmove-result v0\nreturn v0'
  'getSpanTypeIdInternal()I': 'const/16 v0, 23\nreturn v0'
  'describeContents()I': 'const/4 v0, 0\nreturn v0'
  'writeToParcel(Landroid/os/Parcel;I)V': 'invoke-virtual {p0, p1, p2}, ${owner}->writeToParcelInternal(Landroid/os/Parcel;I)V\nreturn-void'
  // LocaleList's legacy Parcel format is one language-tag string. Its existing
  // CREATOR is a stub here, so encode that format without altering LocaleList.
  'writeToParcelInternal(Landroid/os/Parcel;I)V': 'iget-object v0, p0, ${owner}->vinixLocales:${list}\ninvoke-virtual {v0}, ${list}->toLanguageTags()Ljava/lang/String;\nmove-result-object v0\ninvoke-virtual {p1, v0}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V\nreturn-void'
 } {
  text += '.method public ${signature}\n.locals 2\n${body}\n.end method\n'
 }
 for name in ['updateDrawState', 'updateMeasureState'] {
  text += '.method public ${name}(Landroid/text/TextPaint;)V\n.locals 1\niget-object v0, p0, ${owner}->vinixLocales:${list}\ninvoke-virtual {p1, v0}, Landroid/graphics/Paint;->setTextLocales(${list})V\nreturn-void\n.end method\n'
 }
 os.write_file(file, text)!
}
