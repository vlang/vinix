// SPDX-License-Identifier: GPL-2.0-or-later
module contactlabelsprobe
import os
pub fn install(root string) ! {
 mut cases := ''
 // Independent expectations from the bundled framework strings and public API.
 for phone in [false, true] {
  names := if phone { ['Home', 'Mobile', 'Work', 'FaxWork', 'FaxHome', 'Pager', 'Other', 'Callback', 'Car', 'CompanyMain', 'Isdn', 'Main', 'OtherFax', 'Radio', 'Telex', 'TtyTdd', 'WorkMobile', 'WorkPager', 'Assistant', 'Mms'] } else { ['Home', 'Work', 'Other', 'Mobile'] }
  texts := if phone { ['Home', 'Mobile', 'Work', 'Work Fax', 'Home Fax', 'Pager', 'Other', 'Callback', 'Car', 'Company Main', 'ISDN', 'Main', 'Other Fax', 'Radio', 'Telex', 'TTY TDD', 'Work Mobile', 'Work Pager', 'Assistant', 'MMS'] } else { ['Home', 'Work', 'Other', 'Mobile'] }
  prefix := if phone { 'phoneType' } else { 'emailType' }
  for i, name in names {
   cases += 'const/4 v1, ' + if phone { '1' } else { '0' } + '\nconst/16 v2, ' + (i+1).str() + '\nconst-string v3, "' + prefix + name + '"\nconst-string v4, "' + texts[i] + '"\ninvoke-static {v0, v1, v2, v3, v4}, Lorg/vinix/bootstrap/ContactLabelsProbe;->one(Landroid/content/res/Resources;ZILjava/lang/String;Ljava/lang/String;)V\n'
  }
  for value in ['0', '-1', '99', '-2147483648', '2147483647'] {
   cases += 'const/4 v1, ' + if phone { '1' } else { '0' } + '\nconst v2, ' + value + '\nconst-string v3, "' + prefix + 'Custom"\nconst-string v4, "Custom"\ninvoke-static {v0, v1, v2, v3, v4}, Lorg/vinix/bootstrap/ContactLabelsProbe;->one(Landroid/content/res/Resources;ZILjava/lang/String;Ljava/lang/String;)V\n'
  }
 }
 os.write_file(root + '/smali/ContactLabelsProbe.smali', r'
.class public final Lorg/vinix/bootstrap/ContactLabelsProbe;
.super Ljava/lang/Object;
.implements Ljava/lang/Runnable;
.field private resources:Landroid/content/res/Resources;
.field private volatile done:Z
.method public constructor <init>(Landroid/content/res/Resources;)V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
iput-object p1, p0, Lorg/vinix/bootstrap/ContactLabelsProbe;->resources:Landroid/content/res/Resources;
return-void
.end method
.method public static one(Landroid/content/res/Resources;ZILjava/lang/String;Ljava/lang/String;)V
.locals 5
const/4 v0, 0
if-eqz p1, :email
invoke-static {p0, p2, v0}, Landroid/provider/ContactsContract$CommonDataKinds$Phone;->getTypeLabel(Landroid/content/res/Resources;ILjava/lang/CharSequence;)Ljava/lang/CharSequence;
move-result-object v0
invoke-static {p2}, Landroid/provider/ContactsContract$CommonDataKinds$Phone;->getTypeLabelResource(I)I
move-result v1
goto :check
:email
invoke-static {p0, p2, v0}, Landroid/provider/ContactsContract$CommonDataKinds$Email;->getTypeLabel(Landroid/content/res/Resources;ILjava/lang/CharSequence;)Ljava/lang/CharSequence;
move-result-object v0
invoke-static {p2}, Landroid/provider/ContactsContract$CommonDataKinds$Email;->getTypeLabelResource(I)I
move-result v1
:check
if-lez v1, :bad
invoke-interface {v0}, Ljava/lang/CharSequence;->toString()Ljava/lang/String;
move-result-object v0
invoke-virtual {p4, v0}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z
move-result v0
const/4 v2, 1
invoke-static {v0, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const-string v3, "string"
const-string v4, "android"
invoke-virtual {p0, p3, v3, v4}, Landroid/content/res/Resources;->getIdentifier(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;)I
move-result v0
invoke-static {v1, v0}, Lorg/vinix/bootstrap/Main;->expect(II)V
return-void
:bad
new-instance v0, Ljava/lang/AssertionError;
invoke-direct {v0}, Ljava/lang/AssertionError;-><init>()V
throw v0
.end method
.method public run()V
.locals 6
iget-object v0, p0, Lorg/vinix/bootstrap/ContactLabelsProbe;->resources:Landroid/content/res/Resources;
const/4 v1, 0
const/4 v2, 1
const-string v3, "emailTypeHome"
const-string v4, "Home"
invoke-static {v0, v1, v2, v3, v4}, Lorg/vinix/bootstrap/ContactLabelsProbe;->one(Landroid/content/res/Resources;ZILjava/lang/String;Ljava/lang/String;)V
const/4 v1, 1
const/4 v2, 3
const-string v3, "phoneTypeWork"
const-string v4, "Work"
invoke-static {v0, v1, v2, v3, v4}, Lorg/vinix/bootstrap/ContactLabelsProbe;->one(Landroid/content/res/Resources;ZILjava/lang/String;Ljava/lang/String;)V
iput-boolean v1, p0, Lorg/vinix/bootstrap/ContactLabelsProbe;->done:Z
return-void
.end method
.method public static check(Landroid/content/Context;)V
.locals 10
invoke-virtual {p0}, Landroid/content/Context;->getResources()Landroid/content/res/Resources;
move-result-object v0
' + cases + r'
# A non-String custom label is returned unchanged, without dereferencing res.
new-instance v1, Ljava/lang/StringBuilder;
const-string v2, "custom label"
invoke-direct {v1, v2}, Ljava/lang/StringBuilder;-><init>(Ljava/lang/String;)V
const/4 v2, 0
const/4 v3, 0
invoke-static {v2, v3, v1}, Landroid/provider/ContactsContract$CommonDataKinds$Email;->getTypeLabel(Landroid/content/res/Resources;ILjava/lang/CharSequence;)Ljava/lang/CharSequence;
move-result-object v4
invoke-static {v4, v1}, Lorg/vinix/bootstrap/WindowDecorProbe;->same(Ljava/lang/Object;Ljava/lang/Object;)V
invoke-static {v2, v3, v1}, Landroid/provider/ContactsContract$CommonDataKinds$Phone;->getTypeLabel(Landroid/content/res/Resources;ILjava/lang/CharSequence;)Ljava/lang/CharSequence;
move-result-object v4
invoke-static {v4, v1}, Lorg/vinix/bootstrap/WindowDecorProbe;->same(Ljava/lang/Object;Ljava/lang/Object;)V
const/16 v3, 19
invoke-static {v2, v3, v1}, Landroid/provider/ContactsContract$CommonDataKinds$Phone;->getTypeLabel(Landroid/content/res/Resources;ILjava/lang/CharSequence;)Ljava/lang/CharSequence;
move-result-object v4
invoke-static {v4, v1}, Lorg/vinix/bootstrap/WindowDecorProbe;->same(Ljava/lang/Object;Ljava/lang/Object;)V
# Resource text must come from the supplied Resources, retaining its identity.
new-instance v2, Lorg/vinix/bootstrap/ContactLabelResources;
invoke-virtual {v0}, Landroid/content/res/Resources;->getAssets()Landroid/content/res/AssetManager;
move-result-object v3
invoke-virtual {v0}, Landroid/content/res/Resources;->getDisplayMetrics()Landroid/util/DisplayMetrics;
move-result-object v4
invoke-virtual {v0}, Landroid/content/res/Resources;->getConfiguration()Landroid/content/res/Configuration;
move-result-object v5
invoke-direct {v2, v3, v4, v5}, Lorg/vinix/bootstrap/ContactLabelResources;-><init>(Landroid/content/res/AssetManager;Landroid/util/DisplayMetrics;Landroid/content/res/Configuration;)V
iput-object v1, v2, Lorg/vinix/bootstrap/ContactLabelResources;->marker:Ljava/lang/CharSequence;
const/4 v3, 2
const/4 v5, 0
invoke-static {v2, v3, v5}, Landroid/provider/ContactsContract$CommonDataKinds$Email;->getTypeLabel(Landroid/content/res/Resources;ILjava/lang/CharSequence;)Ljava/lang/CharSequence;
move-result-object v4
invoke-static {v4, v1}, Lorg/vinix/bootstrap/WindowDecorProbe;->same(Ljava/lang/Object;Ljava/lang/Object;)V
invoke-static {v3}, Landroid/provider/ContactsContract$CommonDataKinds$Email;->getTypeLabelResource(I)I
move-result v3
iget v4, v2, Lorg/vinix/bootstrap/ContactLabelResources;->last:I
invoke-static {v4, v3}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/4 v3, 3
invoke-static {v2, v3, v5}, Landroid/provider/ContactsContract$CommonDataKinds$Phone;->getTypeLabel(Landroid/content/res/Resources;ILjava/lang/CharSequence;)Ljava/lang/CharSequence;
move-result-object v4
invoke-static {v4, v1}, Lorg/vinix/bootstrap/WindowDecorProbe;->same(Ljava/lang/Object;Ljava/lang/Object;)V
# Empty custom labels fall through to Resources instead of being returned.
const-string v5, ""
const/4 v3, 0
invoke-static {v2, v3, v5}, Landroid/provider/ContactsContract$CommonDataKinds$Email;->getTypeLabel(Landroid/content/res/Resources;ILjava/lang/CharSequence;)Ljava/lang/CharSequence;
move-result-object v4
invoke-static {v4, v1}, Lorg/vinix/bootstrap/WindowDecorProbe;->same(Ljava/lang/Object;Ljava/lang/Object;)V
invoke-static {v2, v3, v5}, Landroid/provider/ContactsContract$CommonDataKinds$Phone;->getTypeLabel(Landroid/content/res/Resources;ILjava/lang/CharSequence;)Ljava/lang/CharSequence;
move-result-object v4
invoke-static {v4, v1}, Lorg/vinix/bootstrap/WindowDecorProbe;->same(Ljava/lang/Object;Ljava/lang/Object;)V
new-instance v1, Lorg/vinix/bootstrap/ContactLabelsProbe;
invoke-direct {v1, v0}, Lorg/vinix/bootstrap/ContactLabelsProbe;-><init>(Landroid/content/res/Resources;)V
new-instance v2, Ljava/lang/Thread;
invoke-direct {v2, v1}, Ljava/lang/Thread;-><init>(Ljava/lang/Runnable;)V
invoke-virtual {v2}, Ljava/lang/Thread;->start()V
const-wide/16 v3, 3000
invoke-virtual {v2, v3, v4}, Ljava/lang/Thread;->join(J)V
iget-boolean v3, v1, Lorg/vinix/bootstrap/ContactLabelsProbe;->done:Z
const/4 v4, 1
invoke-static {v3, v4}, Lorg/vinix/bootstrap/Main;->expect(II)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "CONTACT-LABELS-PASS email-4 phone-20 unknown custom-identity assistant supplied-resources empty-label worker"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
.end method
')!
 os.write_file(root + '/smali/ContactLabelResources.smali', r'
.class public Lorg/vinix/bootstrap/ContactLabelResources;
.super Landroid/content/res/Resources;
.field public marker:Ljava/lang/CharSequence;
.field public last:I
.method public constructor <init>(Landroid/content/res/AssetManager;Landroid/util/DisplayMetrics;Landroid/content/res/Configuration;)V
.locals 0
invoke-direct {p0, p1, p2, p3}, Landroid/content/res/Resources;-><init>(Landroid/content/res/AssetManager;Landroid/util/DisplayMetrics;Landroid/content/res/Configuration;)V
return-void
.end method
.method public getText(I)Ljava/lang/CharSequence;
.locals 1
iput p1, p0, Lorg/vinix/bootstrap/ContactLabelResources;->last:I
iget-object v0, p0, Lorg/vinix/bootstrap/ContactLabelResources;->marker:Ljava/lang/CharSequence;
return-object v0
.end method
')!
}
