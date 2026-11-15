// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools
import os

pub fn framework_contact_labels_source(original string, kind string) !string {
 if kind !in ['Email', 'Phone'] { return error('unsupported contact label kind') }
 owner := 'Landroid/provider/ContactsContract$CommonDataKinds$' + kind + ';'
 for declaration in ['.class public final ' + owner, '.super Ljava/lang/Object;',
  '.field public static final CONTENT_URI:Landroid/net/Uri;', '.method public constructor <init>()V'] {
  if original.count(declaration + '\n') != 1 { return error('canonical contact label input required') }
 }
 for member in ['getTypeLabel(', 'getTypeLabelResource(', 'TYPE_CUSTOM:I', 'TYPE_HOME:I'] {
  if original.contains(member) { return error('contact label API already exists') }
 }
 names := if kind == 'Email' { ['Home', 'Work', 'Other', 'Mobile'] } else {
  ['Home', 'Mobile', 'Work', 'FaxWork', 'FaxHome', 'Pager', 'Other', 'Callback',
   'Car', 'CompanyMain', 'Isdn', 'Main', 'OtherFax', 'Radio', 'Telex', 'TtyTdd',
   'WorkMobile', 'WorkPager', 'Assistant', 'Mms']
 }
 constants := if kind == 'Email' { ['HOME', 'WORK', 'OTHER', 'MOBILE'] } else {
  ['HOME', 'MOBILE', 'WORK', 'FAX_WORK', 'FAX_HOME', 'PAGER', 'OTHER', 'CALLBACK',
   'CAR', 'COMPANY_MAIN', 'ISDN', 'MAIN', 'OTHER_FAX', 'RADIO', 'TELEX', 'TTY_TDD',
   'WORK_MOBILE', 'WORK_PAGER', 'ASSISTANT', 'MMS']
 }
 prefix := kind.to_lower() + 'Type'
 mut extra := '\n.field public static final TYPE_CUSTOM:I = 0\n'
 for i, name in constants { extra += '.field public static final TYPE_' + name + ':I = ' + (i+1).str() + '\n' }
 extra += '\n.method public static final getTypeLabelResource(I)I\n.locals 4\n'
 extra += 'packed-switch p0, :types\nconst-string v0, "' + prefix + 'Custom"\ngoto :lookup\n'
 for i, name in names {
  extra += ':type_' + (i+1).str() + '\nconst-string v0, "' + prefix + name + '"\ngoto :lookup\n'
 }
 // Resolve private framework IDs from the bundled resource table, rather than
 // binding the SDK to numeric IDs from an unrelated Android release.
 extra += ':lookup\ninvoke-static {}, Landroid/content/res/Resources;->getSystem()Landroid/content/res/Resources;\nmove-result-object v1\n'
 extra += 'const-string v2, "string"\nconst-string v3, "android"\ninvoke-virtual {v1, v0, v2, v3}, Landroid/content/res/Resources;->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I\nmove-result v0\n'
 extra += 'if-nez v0, :found\nnew-instance v0, Landroid/content/res/Resources$NotFoundException;\nconst-string v1, "Contact type label resource is missing"\ninvoke-direct {v0, v1}, Landroid/content/res/Resources$NotFoundException;-><init>(Ljava/lang/String;)V\nthrow v0\n:found\nreturn v0\n'
 extra += ':types\n.packed-switch 0x1\n'
 for i in 0 .. names.len { extra += ':type_' + (i+1).str() + '\n' }
 extra += '.end packed-switch\n.end method\n'
 extra += '\n.method public static getTypeLabel(Landroid/content/res/Resources;ILjava/lang/CharSequence;)Ljava/lang/CharSequence;\n.locals 2\n'
 extra += 'if-eqz p1, :custom\n'
 if kind == 'Phone' { extra += 'const/16 v0, 19\nif-eq p1, v0, :custom\n' }
 extra += 'goto :resource\n:custom\ninvoke-static {p2}, Landroid/text/TextUtils;->isEmpty(Ljava/lang/CharSequence;)Z\nmove-result v0\nif-nez v0, :resource\nreturn-object p2\n'
 extra += ':resource\ninvoke-static {p1}, ' + owner + '->getTypeLabelResource(I)I\nmove-result v0\ninvoke-virtual {p0, v0}, Landroid/content/res/Resources;->getText(I)Ljava/lang/CharSequence;\nmove-result-object v0\nreturn-object v0\n.end method\n'
 return original + extra
}

pub fn framework_contact_labels(smali string) ! {
 for kind in ['Email', 'Phone'] {
  path := smali + '/android/provider/ContactsContract$CommonDataKinds$' + kind + '.smali'
  os.write_file(path, framework_contact_labels_source(os.read_file(path)!, kind)!)!
 }
}
