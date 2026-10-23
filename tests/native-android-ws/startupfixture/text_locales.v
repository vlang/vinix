// SPDX-License-Identifier: GPL-2.0-or-later
module startupfixture

import os

fn install_text_locales_probe(dir string) ! {
 probe := 'Lorg/vinix/bootstrap/TextLocalesProbe;'
 view := 'Lorg/vinix/bootstrap/LocaleView;'
 paint := 'Landroid/graphics/Paint;'
 list := 'Landroid/os/LocaleList;'
 locale := 'Ljava/util/Locale;'
 bad := '\n:bad\nnew-instance v0, Ljava/lang/AssertionError;\nconst-string v1, "text locale state, copy/reset or view propagation"\ninvoke-direct {v0, v1}, Ljava/lang/AssertionError;-><init>(Ljava/lang/Object;)V\nthrow v0'
 mut subclass := '.class public ${view}\n.super Landroid/widget/TextView;\n.field public layouts:I\n.field public invalidates:I\n'
 subclass += method('public constructor <init>(Landroid/content/Context;)V', 'invoke-direct {p0, p1}, Landroid/widget/TextView;-><init>(Landroid/content/Context;)V\nreturn-void')
 for name, counter in {'requestLayout': 'layouts', 'invalidate': 'invalidates'} {
  subclass += method('public ${name}()V', 'iget v0, p0, ${view}->${counter}:I\nadd-int/lit8 v0, v0, 1\niput v0, p0, ${view}->${counter}:I\ninvoke-super {p0}, Landroid/widget/TextView;->${name}()V\nreturn-void')
 }
 os.write_file(dir + '/LocaleView.smali', subclass)!
 mut text := '.class public ${probe}\n.super Ljava/lang/Object;\n'
 text += method('private static equal(${list}${list})V', 'invoke-virtual {p0, p1}, ${list}->equals(Ljava/lang/Object;)Z\nmove-result v0\nif-eqz v0, :bad\nreturn-void' + bad)
 text += method('public static check(Landroid/content/Context;)V', '
# Snapshot the default when each Paint is constructed; reset uses the current one.
invoke-static {}, ${list}->getDefault()${list}
move-result-object v9
invoke-static {}, ${list}->getAdjustedDefault()${list}
move-result-object v8
new-instance v0, ${paint}
invoke-direct {v0}, ${paint}-><init>()V
invoke-virtual {v0}, ${paint}->getTextLocales()${list}
move-result-object v1
invoke-static {v1, v8}, ${probe}->equal(${list}${list})V
const-string v1, "ja-JP,en-US"
invoke-static {v1}, ${list}->forLanguageTags(Ljava/lang/String;)${list}
move-result-object v7
invoke-static {v7}, ${list}->setDefault(${list})V
invoke-virtual {v0}, ${paint}->getTextLocales()${list}
move-result-object v1
invoke-static {v1, v8}, ${probe}->equal(${list}${list})V
invoke-virtual {v0}, ${paint}->reset()V
invoke-virtual {v0}, ${paint}->getTextLocales()${list}
move-result-object v1
invoke-static {v1, v7}, ${probe}->equal(${list}${list})V
# Copy constructor, set and self-set preserve the ordered immutable list.
new-instance v1, ${paint}
invoke-direct {v1, v0}, ${paint}-><init>(${paint})V
new-instance v2, ${paint}
invoke-direct {v2}, ${paint}-><init>()V
invoke-virtual {v2, v0}, ${paint}->set(${paint})V
invoke-virtual {v2, v2}, ${paint}->set(${paint})V
sget-object v3, Ljava/util/Locale;->FRENCH:${locale}
invoke-virtual {v0, v3}, ${paint}->setTextLocale(${locale})V
invoke-virtual {v0}, ${paint}->getTextLocale()${locale}
move-result-object v4
invoke-virtual {v3, v4}, ${locale}->equals(Ljava/lang/Object;)Z
move-result v4
if-eqz v4, :bad
invoke-virtual {v0}, ${paint}->getTextLocales()${list}
move-result-object v4
invoke-virtual {v4}, ${list}->size()I
move-result v4
const/4 v5, 1
if-ne v4, v5, :bad
invoke-virtual {v1}, ${paint}->getTextLocales()${list}
move-result-object v4
invoke-static {v4, v7}, ${probe}->equal(${list}${list})V
invoke-virtual {v2}, ${paint}->getTextLocales()${list}
move-result-object v4
invoke-static {v4, v7}, ${probe}->equal(${list}${list})V
new-instance v6, ${view}
invoke-direct {v6, p0}, ${view}-><init>(Landroid/content/Context;)V
const/4 v4, 0
iput v4, v6, ${view}->layouts:I
iput v4, v6, ${view}->invalidates:I
invoke-virtual {v6, v7}, Landroid/widget/TextView;->setTextLocales(${list})V
invoke-virtual {v6}, Landroid/widget/TextView;->getTextLocales()${list}
move-result-object v4
invoke-static {v4, v7}, ${probe}->equal(${list}${list})V
iget v4, v6, ${view}->layouts:I
if-lez v4, :bad
iget v4, v6, ${view}->invalidates:I
if-lez v4, :bad
invoke-virtual {v6, v3}, Landroid/widget/TextView;->setTextLocale(${locale})V
invoke-virtual {v6}, Landroid/widget/TextView;->getTextLocale()${locale}
move-result-object v4
invoke-virtual {v3, v4}, ${locale}->equals(Ljava/lang/Object;)Z
move-result v4
if-eqz v4, :bad
invoke-virtual {v6}, Landroid/widget/TextView;->getPaint()Landroid/text/TextPaint;
move-result-object v4
invoke-virtual {v4, v7}, ${paint}->setTextLocales(${list})V
invoke-virtual {v6}, Landroid/widget/TextView;->getTextLocales()${list}
move-result-object v4
invoke-static {v4, v7}, ${probe}->equal(${list}${list})V
invoke-static {v0, v6}, ${probe}->errors(${paint}Landroid/widget/TextView;)V
invoke-static {v9}, ${list}->setDefault(${list})V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "BOOTSTRAP-TEXT-LOCALES-PASS defaults ordered-list primary copy set self reset textview paint layout invalidate invalid"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void' + bad)
 mut errors := ''
 for i, call in [
  'const/4 v1, 0\ninvoke-virtual {p0, v1}, ${paint}->setTextLocale(${locale})V',
  'const/4 v1, 0\ninvoke-virtual {p0, v1}, ${paint}->setTextLocales(${list})V',
  'invoke-static {}, ${list}->getEmptyLocaleList()${list}\nmove-result-object v1\ninvoke-virtual {p0, v1}, ${paint}->setTextLocales(${list})V',
  'const/4 v1, 0\ninvoke-virtual {p1, v1}, Landroid/widget/TextView;->setTextLocale(${locale})V',
  'const/4 v1, 0\ninvoke-virtual {p1, v1}, Landroid/widget/TextView;->setTextLocales(${list})V',
  'invoke-static {}, ${list}->getEmptyLocaleList()${list}\nmove-result-object v1\ninvoke-virtual {p1, v1}, Landroid/widget/TextView;->setTextLocales(${list})V',
 ] {
  errors += '\n:case${i}\n${call}\n:end${i}\ngoto :bad\n.catch Ljava/lang/IllegalArgumentException; {:case${i} .. :end${i}} :caught${i}\n:caught${i}\nmove-exception v0\n'
 }
 text += method('private static errors(${paint}Landroid/widget/TextView;)V', errors + '\nreturn-void' + bad)
 os.write_file(dir + '/TextLocalesProbe.smali', text)!
}
