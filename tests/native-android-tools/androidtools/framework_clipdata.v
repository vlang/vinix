// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Keep the items and description used by Intent URI grants. Factories must
// retain their payload, including a nullable Intent, rather than a text proxy.
fn framework_clipdata(smali string) ! {
 clip := 'Landroid/content/ClipData;'
 item := 'Landroid/content/ClipData$Item;'
 desc := 'Landroid/content/ClipDescription;'
 path := smali + '/android/content/ClipData.smali'
 mut text := os.read_file(path)!
 text += '\n.field private vinixDescription:' + desc + '\n.field private vinixItems:Ljava/util/ArrayList;\n'
 text = framework_replace_method(text, '<init>(' + desc + item + ')V', signature_method(
  'public constructor <init>(' + desc + item + ')V',
  'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\n' +
  'invoke-static {p2}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;\n' +
  'iput-object p1, p0, ' + clip + '->vinixDescription:' + desc + '\n' +
  'new-instance v0, Ljava/util/ArrayList;\ninvoke-direct {v0}, Ljava/util/ArrayList;-><init>()V\n' +
  'invoke-virtual {v0, p2}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z\n' +
  'iput-object v0, p0, ' + clip + '->vinixItems:Ljava/util/ArrayList;\n' +
  // ClipboardManager in the upstream framework reads this legacy text field.
  'invoke-virtual {p2}, ' + item + '->getText()Ljava/lang/CharSequence;\nmove-result-object v0\n' +
  'if-nez v0, :string\ninvoke-virtual {p2}, ' + item + '->getUri()Landroid/net/Uri;\nmove-result-object v0\n' +
  'if-eqz v0, :done\n:string\ninvoke-virtual {v0}, Ljava/lang/Object;->toString()Ljava/lang/String;\n' +
  'move-result-object v0\niput-object v0, p0, ' + clip + '->text:Ljava/lang/String;\n:done\nreturn-void'))!
 text = framework_replace_method(text, '<init>(' + clip + ')V', signature_method(
  'public constructor <init>(' + clip + ')V',
  'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\n' +
  'iget-object v0, p1, ' + clip + '->vinixDescription:' + desc + '\niput-object v0, p0, ' + clip + '->vinixDescription:' + desc + '\n' +
  'iget-object v0, p1, ' + clip + '->vinixItems:Ljava/util/ArrayList;\nnew-instance v1, Ljava/util/ArrayList;\n' +
  'invoke-direct {v1, v0}, Ljava/util/ArrayList;-><init>(Ljava/util/Collection;)V\n' +
  'iput-object v1, p0, ' + clip + '->vinixItems:Ljava/util/ArrayList;\n' +
  'iget-object v0, p1, ' + clip + '->text:Ljava/lang/String;\niput-object v0, p0, ' + clip + '->text:Ljava/lang/String;\nreturn-void'))!
 for index, name in ['newPlainText', 'newIntent', 'newRawUri'] {
  payload := ['Ljava/lang/CharSequence;', 'Landroid/content/Intent;', 'Landroid/net/Uri;'][index]
  mime := ['text/plain', 'text/vnd.android.intent', 'text/uri-list'][index]
  method := name + '(Ljava/lang/CharSequence;' + payload + ')' + clip
  text = framework_replace_method(text, method, signature_method('public static ' + method,
   'const/4 v0, 1\nnew-array v0, v0, [Ljava/lang/String;\nconst/4 v1, 0\n' +
   'const-string v2, "' + mime + '"\naput-object v2, v0, v1\n' +
   'new-instance v1, ' + desc + '\ninvoke-direct {v1, p0, v0}, ' + desc + '-><init>(Ljava/lang/CharSequence;[Ljava/lang/String;)V\n' +
   'new-instance v2, ' + item + '\ninvoke-direct {v2, p1}, ' + item + '-><init>(' + payload + ')V\n' +
   'new-instance v0, ' + clip + '\ninvoke-direct {v0, v1, v2}, ' + clip + '-><init>(' + desc + item + ')V\nreturn-object v0'))!
 }
 text = framework_replace_method(text, 'getDescription()' + desc, signature_method('public getDescription()' + desc,
  'iget-object v0, p0, ' + clip + '->vinixDescription:' + desc + '\nreturn-object v0'))!
 text = framework_replace_method(text, 'getItemCount()I', signature_method('public getItemCount()I',
  'iget-object v0, p0, ' + clip + '->vinixItems:Ljava/util/ArrayList;\n' +
  'invoke-virtual {v0}, Ljava/util/ArrayList;->size()I\nmove-result v0\nreturn v0'))!
 text = framework_replace_method(text, 'getItemAt(I)' + item, signature_method('public getItemAt(I)' + item,
  'iget-object v0, p0, ' + clip + '->vinixItems:Ljava/util/ArrayList;\n' +
  'invoke-virtual {v0, p1}, Ljava/util/ArrayList;->get(I)Ljava/lang/Object;\nmove-result-object v0\ncheck-cast v0, ' + item + '\nreturn-object v0'))!
 text = framework_replace_method(text, 'addItem(' + item + ')V', signature_method('public addItem(' + item + ')V',
  'invoke-static {p1}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;\n' +
  'iget-object v0, p0, ' + clip + '->vinixItems:Ljava/util/ArrayList;\n' +
  'invoke-virtual {v0, p1}, Ljava/util/ArrayList;->add(Ljava/lang/Object;)Z\nreturn-void'))!
 os.write_file(path, text)!

 item_path := smali + '/android/content/ClipData$Item.smali'
 mut items := os.read_file(item_path)!
 for index, field in ['Text', 'Intent', 'Uri'] {
  payload := ['Ljava/lang/CharSequence;', 'Landroid/content/Intent;', 'Landroid/net/Uri;'][index]
  member := 'vinix' + field + ':' + payload
  items += '\n.field private ' + member + '\n'
  items = framework_replace_method(items, '<init>(' + payload + ')V', signature_method('public constructor <init>(' + payload + ')V',
   'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, ' + item + '->' + member + '\nreturn-void'))!
  items = framework_replace_method(items, 'get' + field + '()' + payload, signature_method('public get' + field + '()' + payload,
   'iget-object v0, p0, ' + item + '->' + member + '\nreturn-object v0'))!
 }
 os.write_file(item_path, items)!

 desc_path := smali + '/android/content/ClipDescription.smali'
 mut description := os.read_file(desc_path)!
 description += '\n.field private vinixLabel:Ljava/lang/CharSequence;\n.field private vinixMimeTypes:Ljava/util/ArrayList;\n'
 description = framework_replace_method(description, '<init>(Ljava/lang/CharSequence;[Ljava/lang/String;)V', signature_method(
  'public constructor <init>(Ljava/lang/CharSequence;[Ljava/lang/String;)V',
  'invoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, ' + desc + '->vinixLabel:Ljava/lang/CharSequence;\n' +
  'invoke-static {p2}, Ljava/util/Arrays;->asList([Ljava/lang/Object;)Ljava/util/List;\nmove-result-object v0\n' +
  'new-instance v1, Ljava/util/ArrayList;\ninvoke-direct {v1, v0}, Ljava/util/ArrayList;-><init>(Ljava/util/Collection;)V\n' +
  'iput-object v1, p0, ' + desc + '->vinixMimeTypes:Ljava/util/ArrayList;\nreturn-void'))!
 description = framework_replace_method(description, 'getLabel()Ljava/lang/CharSequence;', signature_method('public getLabel()Ljava/lang/CharSequence;',
  'iget-object v0, p0, ' + desc + '->vinixLabel:Ljava/lang/CharSequence;\nreturn-object v0'))!
 description = framework_replace_method(description, 'getMimeTypeCount()I', signature_method('public getMimeTypeCount()I',
  'iget-object v0, p0, ' + desc + '->vinixMimeTypes:Ljava/util/ArrayList;\n' +
  'invoke-virtual {v0}, Ljava/util/ArrayList;->size()I\nmove-result v0\nreturn v0'))!
 description = framework_replace_method(description, 'getMimeType(I)Ljava/lang/String;', signature_method('public getMimeType(I)Ljava/lang/String;',
  'iget-object v0, p0, ' + desc + '->vinixMimeTypes:Ljava/util/ArrayList;\n' +
  'invoke-virtual {v0, p1}, Ljava/util/ArrayList;->get(I)Ljava/lang/Object;\nmove-result-object v0\ncheck-cast v0, Ljava/lang/String;\nreturn-object v0'))!
 os.write_file(desc_path, description)!
}
