// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_restrictions_service(smali string) ! {
	context_path := smali + '/android/app/ContextImpl.smali'
	mut context := os.read_file(context_path)!
	if context.contains('vinixRestrictionsManager') { return error('restrictions service already installed') }
	for argument in ['Ljava/lang/String;', 'Ljava/lang/Class;'] {
		signature := 'getSystemService(' + argument + ')Ljava/lang/Object;'
		mut original := ''
		for block in context.split('.method ')[1..] {
			if block.all_before('\n') != 'public ' + signature { continue }
			end := block.index('.end method') or { return error('unterminated service lookup') }
			if original != '' { return error('duplicate service lookup') }
			original = '.method ' + block[..end] + '.end method'
		}
		if original == '' { return error('service lookup missing') }
		registers := if original.contains('.locals 1') { '.locals 1' } else { '.registers 3' }
		if original.count(registers) != 1 { return error('one-local service lookup required') }
		guard := if argument == 'Ljava/lang/String;' {
			'const-string v0, "restrictions"\ninvoke-virtual {v0, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v0\nif-eqz v0, :vinix_restrictions_other\n'
		} else {
			'const-class v0, Landroid/content/RestrictionsManager;\nif-ne p1, v0, :vinix_restrictions_other\n'
		}
		context = context.replace(original, original.replace(registers, registers + '\n' + guard +
			'invoke-direct {p0}, Landroid/app/ContextImpl;->vinixRestrictionsService()Landroid/content/RestrictionsManager;\nmove-result-object v0\nreturn-object v0\n:vinix_restrictions_other\n'))
	}
	context += r'
.field private vinixRestrictionsManager:Landroid/content/RestrictionsManager;
.method private vinixRestrictionsService()Landroid/content/RestrictionsManager;
.locals 1
monitor-enter p0
:locked
iget-object v0, p0, Landroid/app/ContextImpl;->vinixRestrictionsManager:Landroid/content/RestrictionsManager;
if-nez v0, :ready
new-instance v0, Landroid/content/RestrictionsManager;
invoke-direct {v0, p0}, Landroid/content/RestrictionsManager;-><init>(Landroid/content/Context;)V
iput-object v0, p0, Landroid/app/ContextImpl;->vinixRestrictionsManager:Landroid/content/RestrictionsManager;
:ready
monitor-exit p0
return-object v0
:failed
move-exception v0
monitor-exit p0
throw v0
.catchall {:locked .. :ready} :failed
.end method
'
	manager_path := smali + '/android/content/RestrictionsManager.smali'
	mut manager := os.read_file(manager_path)! + r'
.field private final context:Landroid/content/Context;
.method public constructor <init>(Landroid/content/Context;)V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
invoke-static {p1}, Ljava/util/Objects;->requireNonNull(Ljava/lang/Object;)Ljava/lang/Object;
iput-object p1, p0, Landroid/content/RestrictionsManager;->context:Landroid/content/Context;
return-void
.end method
'
	// The existing UserManager owns application-restriction snapshots. This
	// target has no administrator/provider; do not invent a second policy store.
	manager = framework_replace_method(manager, 'getApplicationRestrictions()Landroid/os/Bundle;', r'
.method public getApplicationRestrictions()Landroid/os/Bundle;
.locals 3
iget-object v0, p0, Landroid/content/RestrictionsManager;->context:Landroid/content/Context;
if-eqz v0, :absent
invoke-virtual {v0}, Landroid/content/Context;->getPackageName()Ljava/lang/String;
move-result-object v1
const-string v2, "user"
invoke-virtual {v0, v2}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
check-cast v0, Landroid/os/UserManager;
if-eqz v0, :absent
invoke-virtual {v0, v1}, Landroid/os/UserManager;->getApplicationRestrictions(Ljava/lang/String;)Landroid/os/Bundle;
move-result-object v0
return-object v0
:absent
const/4 v0, 0
return-object v0
.end method')!
	manager = framework_replace_method(manager, 'hasRestrictionsProvider()Z',
		'.method public hasRestrictionsProvider()Z\n.locals 1\nconst/4 v0, 0\nreturn v0\n.end method')!
	os.write_file(context_path, context)!
	os.write_file(manager_path, manager)!
}
