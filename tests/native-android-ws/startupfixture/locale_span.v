// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

pub fn install_locale_span_probe(dir string) ! {
 c := 'Lorg/vinix/bootstrap/LocaleSpanProbe;'
 span := 'Landroid/text/style/LocaleSpan;'
 list := 'Landroid/os/LocaleList;'
 paint := 'Landroid/graphics/Paint;'
 mut text := '.class public ${c}\n.super Ljava/lang/Object;\n'
 text += method('private static fail()V', '
new-instance v0, Ljava/lang/AssertionError;
const-string v1, "LocaleSpan metadata, paint, range or parcel contract"
invoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V
throw v0')
 text += method('private static equal(Ljava/lang/Object;Ljava/lang/Object;)V', '
invoke-virtual {p0, p1}, Ljava/lang/Object;->equals(Ljava/lang/Object;)Z
move-result v0
if-nez v0, :done
invoke-static {}, ${c}->fail()V
:done
return-void')
 text += method('private static tags(${span}Ljava/lang/String;)V', '
invoke-virtual {p0}, ${span}->getLocales()${list}
move-result-object v0
invoke-virtual {v0}, ${list}->toLanguageTags()Ljava/lang/String;
move-result-object v0
invoke-static {v0, p1}, ${c}->equal(Ljava/lang/Object;Ljava/lang/Object;)V
return-void')
 text += method('private static paintTags(Landroid/text/TextPaint;Ljava/lang/String;)V', '
invoke-virtual {p0}, ${paint}->getTextLocales()${list}
move-result-object v0
invoke-virtual {v0}, ${list}->toLanguageTags()Ljava/lang/String;
move-result-object v0
invoke-static {v0, p1}, ${c}->equal(Ljava/lang/Object;Ljava/lang/Object;)V
invoke-virtual {p0}, ${paint}->getTextSize()F
move-result v0
const/high16 v1, 0x41d80000
cmpl-float v0, v0, v1
if-nez v0, :bad
iget v0, p0, Landroid/text/TextPaint;->density:F
const/high16 v1, 0x40200000
cmpl-float v0, v0, v1
if-nez v0, :bad
invoke-virtual {p0}, ${paint}->getColor()I
move-result v0
const v1, 0xff123456
if-ne v0, v1, :bad
return-void
:bad
invoke-static {}, ${c}->fail()V
return-void')
 text += method('private static metadata(${span})V', '
instance-of v0, p0, Landroid/text/style/MetricAffectingSpan;
if-eqz v0, :bad
instance-of v0, p0, Landroid/text/ParcelableSpan;
if-eqz v0, :bad
instance-of v0, p0, Landroid/os/Parcelable;
if-eqz v0, :bad
invoke-virtual {p0}, ${span}->getSpanTypeId()I
move-result v0
const/16 v1, 23
if-ne v0, v1, :bad
invoke-virtual {p0}, ${span}->getSpanTypeIdInternal()I
move-result v0
if-ne v0, v1, :bad
invoke-virtual {p0}, ${span}->describeContents()I
move-result v0
if-nez v0, :bad
return-void
:bad
invoke-static {}, ${c}->fail()V
return-void')
 mut parcel := ''
 for writer in ['writeToParcel', 'writeToParcelInternal'] {
  parcel += '
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v0
const/4 v1, 0
invoke-virtual {p0, v0, v1}, ${span}->${writer}(Landroid/os/Parcel;I)V
invoke-virtual {v0}, Landroid/os/Parcel;->dataPosition()I
move-result v4
invoke-virtual {v0, v1}, Landroid/os/Parcel;->setDataPosition(I)V
# Read the wire independently of the span constructor.
invoke-virtual {v0}, Landroid/os/Parcel;->readString()Ljava/lang/String;
move-result-object v2
invoke-static {v2, p1}, ${c}->equal(Ljava/lang/Object;Ljava/lang/Object;)V
invoke-virtual {v0}, Landroid/os/Parcel;->dataPosition()I
move-result v2
if-ne v2, v4, :bad
invoke-virtual {v0, v1}, Landroid/os/Parcel;->setDataPosition(I)V
new-instance v3, ${span}
invoke-direct {v3, v0}, ${span}-><init>(Landroid/os/Parcel;)V
invoke-static {v3, p1}, ${c}->tags(${span}Ljava/lang/String;)V
invoke-static {v3}, ${c}->metadata(${span})V
invoke-virtual {v0}, Landroid/os/Parcel;->dataPosition()I
move-result v2
if-ne v2, v4, :bad
invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V
'
 }
 parcel += '
# Construct from an independently written language-tag string.
invoke-static {}, Landroid/os/Parcel;->obtain()Landroid/os/Parcel;
move-result-object v0
invoke-virtual {v0, p1}, Landroid/os/Parcel;->writeString(Ljava/lang/String;)V
const/4 v1, 0
invoke-virtual {v0, v1}, Landroid/os/Parcel;->setDataPosition(I)V
new-instance v2, ${span}
invoke-direct {v2, v0}, ${span}-><init>(Landroid/os/Parcel;)V
invoke-static {v2, p1}, ${c}->tags(${span}Ljava/lang/String;)V
invoke-virtual {v0}, Landroid/os/Parcel;->recycle()V
return-void
:bad
invoke-static {}, ${c}->fail()V
return-void'
 text += method('private static parcel(${span}Ljava/lang/String;)V', parcel)
 text += method('private static edges(Landroid/text/TextPaint;)V', '
# A nullable Locale produces an empty list and a null first locale.
const/4 v1, 0
new-instance v0, ${span}
invoke-direct {v0, v1}, ${span}-><init>(Ljava/util/Locale;)V
invoke-virtual {v0}, ${span}->getLocale()Ljava/util/Locale;
move-result-object v2
if-nez v2, :bad
const-string v2, ""
invoke-static {v0, v2}, ${c}->tags(${span}Ljava/lang/String;)V
invoke-static {v0, v2}, ${c}->parcel(${span}Ljava/lang/String;)V
invoke-static {}, ${list}->getEmptyLocaleList()${list}
move-result-object v2
new-instance v3, ${span}
invoke-direct {v3, v2}, ${span}-><init>(${list})V
invoke-virtual {v3}, ${span}->getLocales()${list}
move-result-object v4
if-ne v2, v4, :bad
invoke-virtual {v3}, ${span}->getLocale()Ljava/util/Locale;
move-result-object v4
if-nez v4, :bad
:null_start
new-instance v2, ${span}
invoke-direct {v2, v1}, ${span}-><init>(${list})V
:null_end
goto :bad
.catch Ljava/lang/NullPointerException; {:null_start .. :null_end} :null_caught
:null_caught
move-exception v2
:draw_start
invoke-virtual {v0, p0}, ${span}->updateDrawState(Landroid/text/TextPaint;)V
:draw_end
goto :bad
.catch Ljava/lang/IllegalArgumentException; {:draw_start .. :draw_end} :draw_caught
:draw_caught
move-exception v2
:measure_start
invoke-virtual {v3, p0}, ${span}->updateMeasureState(Landroid/text/TextPaint;)V
:measure_end
goto :bad
.catch Ljava/lang/IllegalArgumentException; {:measure_start .. :measure_end} :measure_caught
:measure_caught
move-exception v2
const-string v2, "sr-Cyrl-RS,fr-FR"
invoke-static {p0, v2}, ${c}->paintTags(Landroid/text/TextPaint;Ljava/lang/String;)V
return-void
:bad
invoke-static {}, ${c}->fail()V
return-void')
 text += method('public static check()V', '
# Match Maps batc.z: resolve LocaleSpan and construct with a language-tag Locale.
new-instance v0, ${span}
const-string v1, "fr-FR"
invoke-static {v1}, Ljava/util/Locale;->forLanguageTag(Ljava/lang/String;)Ljava/util/Locale;
move-result-object v2
invoke-direct {v0, v2}, ${span}-><init>(Ljava/util/Locale;)V
invoke-static {v0}, ${c}->metadata(${span})V
invoke-static {v0, v1}, ${c}->tags(${span}Ljava/lang/String;)V
invoke-virtual {v0}, ${span}->getLocale()Ljava/util/Locale;
move-result-object v3
invoke-static {v3, v2}, ${c}->equal(Ljava/lang/Object;Ljava/lang/Object;)V
invoke-static {v0, v1}, ${c}->parcel(${span}Ljava/lang/String;)V
new-instance v1, Landroid/text/SpannableString;
const-string v2, "Jardin d’Acclimatation"
invoke-direct {v1, v2}, Landroid/text/SpannableString;-><init>(Ljava/lang/CharSequence;)V
invoke-virtual {v2}, Ljava/lang/String;->length()I
move-result v3
const/4 v4, 0
const/16 v5, 0x11
invoke-virtual {v1, v0, v4, v3, v5}, Landroid/text/SpannableString;->setSpan(Ljava/lang/Object;III)V
invoke-virtual {v1, v0}, Landroid/text/SpannableString;->getSpanStart(Ljava/lang/Object;)I
move-result v2
if-nez v2, :bad
invoke-virtual {v1, v0}, Landroid/text/SpannableString;->getSpanEnd(Ljava/lang/Object;)I
move-result v2
if-ne v2, v3, :bad
invoke-virtual {v1, v0}, Landroid/text/SpannableString;->getSpanFlags(Ljava/lang/Object;)I
move-result v2
if-ne v2, v5, :bad
const-class v2, ${span}
invoke-virtual {v1, v4, v3, v2}, Landroid/text/SpannableString;->getSpans(IILjava/lang/Class;)[Ljava/lang/Object;
move-result-object v2
array-length v3, v2
const/4 v5, 1
if-ne v3, v5, :bad
aget-object v2, v2, v4
if-ne v2, v0, :bad
const-string v1, "sr-Cyrl-RS,fr-FR"
invoke-static {v1}, ${list}->forLanguageTags(Ljava/lang/String;)${list}
move-result-object v2
new-instance v3, ${span}
invoke-direct {v3, v2}, ${span}-><init>(${list})V
invoke-virtual {v3}, ${span}->getLocales()${list}
move-result-object v4
if-ne v4, v2, :bad
invoke-virtual {v3}, ${span}->getLocale()Ljava/util/Locale;
move-result-object v4
const-string v5, "sr-Cyrl-RS"
invoke-static {v5}, Ljava/util/Locale;->forLanguageTag(Ljava/lang/String;)Ljava/util/Locale;
move-result-object v5
invoke-static {v4, v5}, ${c}->equal(Ljava/lang/Object;Ljava/lang/Object;)V
invoke-static {v3, v1}, ${c}->tags(${span}Ljava/lang/String;)V
sget-object v8, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v9, "LOCALE-SPAN-STAGE-PASS locale ordered-list span-range"
invoke-virtual {v8, v9}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
new-instance v4, Landroid/text/TextPaint;
invoke-direct {v4}, Landroid/text/TextPaint;-><init>()V
const/high16 v5, 0x41d80000
invoke-virtual {v4, v5}, ${paint}->setTextSize(F)V
const/high16 v5, 0x40200000
iput v5, v4, Landroid/text/TextPaint;->density:F
const v5, 0xff123456
invoke-virtual {v4, v5}, ${paint}->setColor(I)V
invoke-virtual {v0, v4}, Landroid/text/style/MetricAffectingSpan;->updateDrawState(Landroid/text/TextPaint;)V
const-string v5, "fr-FR"
invoke-static {v4, v5}, ${c}->paintTags(Landroid/text/TextPaint;Ljava/lang/String;)V
invoke-virtual {v3, v4}, Landroid/text/style/MetricAffectingSpan;->updateMeasureState(Landroid/text/TextPaint;)V
invoke-static {v4, v1}, ${c}->paintTags(Landroid/text/TextPaint;Ljava/lang/String;)V
invoke-virtual {v3, v4}, ${span}->updateDrawState(Landroid/text/TextPaint;)V
invoke-static {v4, v1}, ${c}->paintTags(Landroid/text/TextPaint;Ljava/lang/String;)V
const-string v9, "LOCALE-SPAN-STAGE-PASS draw measure paint-state"
invoke-virtual {v8, v9}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
invoke-static {v3, v1}, ${c}->parcel(${span}Ljava/lang/String;)V
invoke-static {v4}, ${c}->edges(Landroid/text/TextPaint;)V
const-string v9, "LOCALE-SPAN-STAGE-PASS parcel wire roundtrip empty null"
invoke-virtual {v8, v9}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
const-string v9, "LOCALE-SPAN-PASS"
invoke-virtual {v8, v9}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
:bad
invoke-static {}, ${c}->fail()V
return-void')
 os.write_file(dir + '/LocaleSpanProbe.smali', text)!
}
