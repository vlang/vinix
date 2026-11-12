// SPDX-License-Identifier: GPL-2.0-or-later
module lookupconstantsprobe

import os

pub fn install(root string) ! {
	mut text := '.class public Lorg/vinix/bootstrap/LookupConstantsProbe;\n.super Ljava/lang/Object;\n.method public static check(Landroid/content/Context;)V\n.locals 4\n'
	for entry in [
		['Landroid/content/Context;', 'APP_OPS_SERVICE', 'appops']!,
		[r'Landroid/provider/Settings$Global;', 'BOOT_COUNT', 'boot_count']!,
	] {
		text += 'sget-object v0, ' + entry[0] + '->' + entry[1] + ':Ljava/lang/String;\nconst-string v1, "' + entry[2] + '"\n' +
			'invoke-virtual {v0, v1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v0\nconst/4 v1, 1\ninvoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V\n' +
			'const-class v0, ' + entry[0] + '\nconst-string v1, "' + entry[1] + '"\n' + r'
invoke-virtual {v0, v1}, Ljava/lang/Class;->getField(Ljava/lang/String;)Ljava/lang/reflect/Field;
move-result-object v0
invoke-virtual {v0}, Ljava/lang/reflect/Field;->getModifiers()I
move-result v1
const/16 v2, 0x19
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
invoke-virtual {v0}, Ljava/lang/reflect/Field;->getType()Ljava/lang/Class;
move-result-object v1
const-class v2, Ljava/lang/String;
invoke-virtual {v1, v2}, Ljava/lang/Object;->equals(Ljava/lang/Object;)Z
move-result v1
const/4 v2, 1
invoke-static {v1, v2}, Lorg/vinix/bootstrap/Main;->expect(II)V
const/4 v1, 0
invoke-virtual {v0, v1}, Ljava/lang/reflect/Field;->get(Ljava/lang/Object;)Ljava/lang/Object;
move-result-object v0
' + 'const-string v1, "' + entry[2] + '"\n' + r'
invoke-virtual {v0, v1}, Ljava/lang/Object;->equals(Ljava/lang/Object;)Z
move-result v0
const/4 v1, 1
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
'
	}
	text += r'
sget-object v0, Landroid/content/Context;->APP_OPS_SERVICE:Ljava/lang/String;
invoke-virtual {p0, v0}, Landroid/content/Context;->getSystemService(Ljava/lang/String;)Ljava/lang/Object;
move-result-object v0
instance-of v0, v0, Landroid/app/AppOpsManager;
const/4 v1, 1
invoke-static {v0, v1}, Lorg/vinix/bootstrap/Main;->expect(II)V
sget-object v0, Ljava/lang/System;->out:Ljava/io/PrintStream;
const-string v1, "LOOKUP-CONSTANTS-PASS static-field-access reflection-type-modifiers-values appops-service"
invoke-virtual {v0, v1}, Ljava/io/PrintStream;->println(Ljava/lang/String;)V
return-void
.end method
'
	os.write_file(root + '/smali/LookupConstantsProbe.smali', text)!
}
