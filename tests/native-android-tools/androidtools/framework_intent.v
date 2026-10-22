// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Filter-only copies are used as service binding keys. Keep mutable category
// sets independent and omit extras, flags and selectors from these copies.
// Semantics: Android 11 Intent.java, cloneFilter and COPY_MODE_FILTER.
fn framework_intent(smali string) ! {
 path := smali + '/android/content/Intent.smali'
 owner := 'Landroid/content/Intent;'
 mut text := os.read_file(path)!
 text += '\n.field private vinixCategories:Ljava/util/HashSet;\n.field private vinixIdentifier:Ljava/lang/String;\n.field private vinixClipData:Landroid/content/ClipData;\n'
 fields := ['action:Ljava/lang/String;', 'data:Landroid/net/Uri;', 'type:Ljava/lang/String;',
  'packageName:Ljava/lang/String;', 'component:Landroid/content/ComponentName;', 'vinixIdentifier:Ljava/lang/String;']
 mut copy := ''
 for field in fields {
  copy += 'iget-object v0, p1, ' + owner + '->' + field + '\niput-object v0, p0, ' + owner + '->' + field + '\n'
 }
 copy += 'iget-object v0, p1, ' + owner + '->vinixCategories:Ljava/util/HashSet;\nif-eqz v0, :categories_done\n' +
  'new-instance v1, Ljava/util/HashSet;\ninvoke-direct {v1, v0}, Ljava/util/HashSet;-><init>(Ljava/util/Collection;)V\n' +
  'iput-object v1, p0, ' + owner + '->vinixCategories:Ljava/util/HashSet;\n:categories_done\n'
 text += '\n.method private constructor <init>(Landroid/content/Intent;Z)V\n.locals 2\n' +
  'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\n' + copy +
  'if-nez p2, :done\niget v0, p1, ' + owner + '->flags:I\niput v0, p0, ' + owner + '->flags:I\n' +
  'iget-object v0, p1, ' + owner + '->extras:Landroid/os/Bundle;\nif-eqz v0, :extras_done\n' +
  'new-instance v1, Landroid/os/Bundle;\ninvoke-direct {v1, v0}, Landroid/os/Bundle;-><init>(Landroid/os/Bundle;)V\n' +
  'iput-object v1, p0, ' + owner + '->extras:Landroid/os/Bundle;\n:extras_done\n' +
  'iget-object v0, p1, ' + owner + '->vinixClipData:Landroid/content/ClipData;\nif-eqz v0, :clip_done\n' +
  'new-instance v1, Landroid/content/ClipData;\ninvoke-direct {v1, v0}, Landroid/content/ClipData;-><init>(Landroid/content/ClipData;)V\n' +
  'iput-object v1, p0, ' + owner + '->vinixClipData:Landroid/content/ClipData;\n:clip_done\n' +
  'iget-object v0, p1, ' + owner + '->selector:Landroid/content/Intent;\nif-eqz v0, :done\n' +
  'new-instance v1, ' + owner + '\ninvoke-direct {v1, v0}, ' + owner + '-><init>(Landroid/content/Intent;)V\n' +
  'iput-object v1, p0, ' + owner + '->selector:Landroid/content/Intent;\n:done\nreturn-void\n.end method\n'
 text = framework_replace_method(text, '<init>(Landroid/content/Intent;)V',
  '.method public constructor <init>(Landroid/content/Intent;)V\n.locals 1\nconst/4 v0, 0\n' +
  'invoke-direct {p0, p1, v0}, ' + owner + '-><init>(Landroid/content/Intent;Z)V\nreturn-void\n.end method')!
 for mode in ['cloneFilter', 'clone'] {
  signature := mode + '()' + if mode == 'clone' { 'Ljava/lang/Object;' } else { owner }
  text = framework_replace_method(text, signature, '.method public ' + signature + '\n.locals 2\n' +
   'new-instance v0, ' + owner + '\nconst/4 v1, ' + (if mode == 'cloneFilter' { '1' } else { '0' }) + '\n' +
   'invoke-direct {v0, p0, v1}, ' + owner + '-><init>(Landroid/content/Intent;Z)V\nreturn-object v0\n.end method')!
 }
 text = framework_replace_method(text, 'getClipData()Landroid/content/ClipData;', signature_method('public getClipData()Landroid/content/ClipData;',
  'iget-object v0, p0, ' + owner + '->vinixClipData:Landroid/content/ClipData;\nreturn-object v0'))!
 text = framework_replace_method(text, 'setClipData(Landroid/content/ClipData;)V', signature_method('public setClipData(Landroid/content/ClipData;)V',
  'iput-object p1, p0, ' + owner + '->vinixClipData:Landroid/content/ClipData;\nreturn-void'))!
 text = framework_replace_method(text, 'addCategory(Ljava/lang/String;)Landroid/content/Intent;',
  '.method public addCategory(Ljava/lang/String;)Landroid/content/Intent;\n.locals 1\n' +
  'iget-object v0, p0, ' + owner + '->vinixCategories:Ljava/util/HashSet;\nif-nez v0, :ready\n' +
  'new-instance v0, Ljava/util/HashSet;\ninvoke-direct {v0}, Ljava/util/HashSet;-><init>()V\n' +
  'iput-object v0, p0, ' + owner + '->vinixCategories:Ljava/util/HashSet;\n:ready\n' +
  'invoke-virtual {v0, p1}, Ljava/util/HashSet;->add(Ljava/lang/Object;)Z\nreturn-object p0\n.end method')!
 text = framework_replace_method(text, 'getCategories()Ljava/util/Set;',
  '.method public getCategories()Ljava/util/Set;\n.locals 1\niget-object v0, p0, ' + owner + '->vinixCategories:Ljava/util/HashSet;\nreturn-object v0\n.end method')!
 text = framework_replace_method(text, 'hasCategory(Ljava/lang/String;)Z',
  '.method public hasCategory(Ljava/lang/String;)Z\n.locals 1\niget-object v0, p0, ' + owner + '->vinixCategories:Ljava/util/HashSet;\n' +
  'if-eqz v0, :absent\ninvoke-virtual {v0, p1}, Ljava/util/HashSet;->contains(Ljava/lang/Object;)Z\nmove-result v0\nreturn v0\n:absent\nconst/4 v0, 0\nreturn v0\n.end method')!
 text = framework_replace_method(text, 'removeCategory(Ljava/lang/String;)V',
  '.method public removeCategory(Ljava/lang/String;)V\n.locals 1\niget-object v0, p0, ' + owner + '->vinixCategories:Ljava/util/HashSet;\n' +
  'if-eqz v0, :done\ninvoke-virtual {v0, p1}, Ljava/util/HashSet;->remove(Ljava/lang/Object;)Z\n' +
  'invoke-virtual {v0}, Ljava/util/HashSet;->isEmpty()Z\nmove-result v0\nif-eqz v0, :done\nconst/4 v0, 0\n' +
  'iput-object v0, p0, ' + owner + '->vinixCategories:Ljava/util/HashSet;\n:done\nreturn-void\n.end method')!
 text = framework_replace_method(text, 'getIdentifier()Ljava/lang/String;',
  '.method public getIdentifier()Ljava/lang/String;\n.locals 1\niget-object v0, p0, ' + owner + '->vinixIdentifier:Ljava/lang/String;\nreturn-object v0\n.end method')!
 text = framework_replace_method(text, 'setIdentifier(Ljava/lang/String;)Landroid/content/Intent;',
  '.method public setIdentifier(Ljava/lang/String;)Landroid/content/Intent;\n.locals 0\niput-object p1, p0, ' + owner + '->vinixIdentifier:Ljava/lang/String;\nreturn-object p0\n.end method')!
 text += '\n.method private vinixPackageEquivalent()Z\n.locals 2\n' +
  'iget-object v0, p0, ' + owner + '->component:Landroid/content/ComponentName;\nif-eqz v0, :no\n' +
  'iget-object v1, p0, ' + owner + '->packageName:Ljava/lang/String;\nif-eqz v1, :yes\n' +
  'invoke-virtual {v0}, Landroid/content/ComponentName;->getPackageName()Ljava/lang/String;\nmove-result-object v0\n' +
  'invoke-virtual {v1, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v0\nreturn v0\n' +
  ':yes\nconst/4 v0, 1\nreturn v0\n:no\nconst/4 v0, 0\nreturn v0\n.end method\n'
 mut equals := 'if-eqz p1, :different\n'
 mut hash := 'const/4 v0, 0\n'
 mut matching_fields := fields.clone()
 matching_fields << 'vinixCategories:Ljava/util/HashSet;'
 for index, field in matching_fields {
  if field.starts_with('packageName:') {
   equals += 'invoke-direct {p0}, ' + owner + '->vinixPackageEquivalent()Z\nmove-result v0\nif-eqz v0, :compare_package\n' +
    'invoke-direct {p1}, ' + owner + '->vinixPackageEquivalent()Z\nmove-result v0\nif-nez v0, :package_done\n:compare_package\n'
  }
  equals += 'iget-object v0, p0, ' + owner + '->' + field + '\niget-object v1, p1, ' + owner + '->' + field + '\n' +
   'invoke-static {v0, v1}, Ljava/util/Objects;->equals(Ljava/lang/Object;Ljava/lang/Object;)Z\nmove-result v0\nif-eqz v0, :different\n'
  if field.starts_with('packageName:') { equals += ':package_done\n' }
  hash += 'iget-object v1, p0, ' + owner + '->' + field + '\nif-eqz v1, :next_' + index.str() + '\n' +
   'invoke-virtual {v1}, Ljava/lang/Object;->hashCode()I\nmove-result v1\nadd-int/2addr v0, v1\n:next_' + index.str() + '\n'
 }
 text = framework_replace_method(text, 'filterEquals(Landroid/content/Intent;)Z',
  '.method public filterEquals(Landroid/content/Intent;)Z\n.locals 2\n' + equals +
  'const/4 v0, 1\nreturn v0\n:different\nconst/4 v0, 0\nreturn v0\n.end method')!
 text = framework_replace_method(text, 'filterHashCode()I', '.method public filterHashCode()I\n.locals 2\n' + hash + 'return v0\n.end method')!
 // A filter copy has a null extras field. Existing upstream typed getters
 // dereference it directly, while writers need to allocate it on first use.
 for block in text.split('.method ')[1..] {
  signature := block.all_before('\n').all_after_last(' ')
  access := '    iget-object v0, p0, ' + owner + '->extras:Landroid/os/Bundle;'
  if !block.contains(access) || signature == 'getExtras()Landroid/os/Bundle;' { continue }
  mut guard := ''
  if signature.starts_with('put') {
   guard = '\n    if-nez v0, :vinix_extras_ready\n    new-instance v0, Landroid/os/Bundle;\n' +
    '    invoke-direct {v0}, Landroid/os/Bundle;-><init>()V\n    iput-object v0, p0, ' + owner + '->extras:Landroid/os/Bundle;\n    :vinix_extras_ready\n'
  } else if signature.starts_with('get') || signature.starts_with('hasExtra') || signature.starts_with('removeExtra') {
   result := signature.all_after(')')
   mut empty := 'const/4 v0, 0\nreturn-object v0'
   if result == 'V' { empty = 'return-void' }
   else if !result.starts_with('L') && !result.starts_with('[') {
    empty = if signature.contains(';J)') { 'return-wide p2' }
     else if signature.contains(';') && !signature.contains(';)') { 'return p2' }
     else { 'const/4 v0, 0\nreturn v0' }
   }
   guard = '\n    if-nez v0, :vinix_extras_ready\n' + empty + '\n    :vinix_extras_ready\n'
  }
  if guard != '' {
   method := '.method ' + block.all_before('.end method') + '.end method'
   text = text.replace(method, method.replace(access, access + guard))
  }
 }
 os.write_file(path, text)!
 comparison := 'Landroid/content/Intent$FilterComparison;'
 os.write_file(smali + '/android/content/Intent$FilterComparison.smali',
  '.class public final ' + comparison + '\n.super Ljava/lang/Object;\n' +
  '.field private final intent:Landroid/content/Intent;\n.field private final hash:I\n' +
  '.method public constructor <init>(Landroid/content/Intent;)V\n.locals 1\n' +
  'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, ' + comparison + '->intent:Landroid/content/Intent;\n' +
  'invoke-virtual {p1}, Landroid/content/Intent;->filterHashCode()I\nmove-result v0\niput v0, p0, ' + comparison + '->hash:I\nreturn-void\n.end method\n' +
  '.method public getIntent()Landroid/content/Intent;\n.locals 1\niget-object v0, p0, ' + comparison + '->intent:Landroid/content/Intent;\nreturn-object v0\n.end method\n' +
  '.method public hashCode()I\n.locals 1\niget v0, p0, ' + comparison + '->hash:I\nreturn v0\n.end method\n' +
  '.method public equals(Ljava/lang/Object;)Z\n.locals 2\ninstance-of v0, p1, ' + comparison + '\nif-eqz v0, :different\ncheck-cast p1, ' + comparison + '\n' +
  'iget-object v0, p0, ' + comparison + '->intent:Landroid/content/Intent;\niget-object v1, p1, ' + comparison + '->intent:Landroid/content/Intent;\n' +
  'invoke-virtual {v0, v1}, Landroid/content/Intent;->filterEquals(Landroid/content/Intent;)Z\nmove-result v0\nreturn v0\n:different\nconst/4 v0, 0\nreturn v0\n.end method\n')!
}
