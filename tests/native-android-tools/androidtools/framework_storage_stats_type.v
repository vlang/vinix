// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_storage_stats_type(smali string) ! {
	path := smali + '/android/app/usage/StorageStatsManager.smali'
	if os.exists(path) { return error('storage statistics type already installed') }
	context := smali + '/android/content/Context.smali'
	mut text := os.read_file(context)!
	if text.contains(' STORAGE_STATS_SERVICE:') { return error('storage statistics service constant already installed') }
	text += '\n.field public static final STORAGE_STATS_SERVICE:Ljava/lang/String; = "storagestats"\n'
	implementation := smali + '/android/app/ContextImpl.smali'
	mut lookups := os.read_file(implementation)!
	if lookups.contains(':vinix_storage_stats_other') { return error('storage statistics absence already installed') }
	// The generic typed fallback reflectively constructs unknown services.
	// Handle this unavailable service explicitly before that fallback.
	for argument in ['Ljava/lang/Class;', 'Ljava/lang/String;'] {
		signature := 'getSystemService(' + argument + ')Ljava/lang/Object;'
		mut original := ''
		for block in lookups.split('.method ')[1..] {
			if block.all_before('\n') != 'public ' + signature { continue }
			end := block.index('.end method') or { return error('unterminated service lookup') }
			if original != '' { return error('duplicate service lookup') }
			original = '.method ' + block[..end] + '.end method'
		}
		if original == '' || original.count('.registers 3') != 1 {
			return error('one-local service lookup required')
		}
		guard := if argument == 'Ljava/lang/Class;' {
			'const-class v0, Landroid/app/usage/StorageStatsManager;\nif-ne p1, v0, :vinix_storage_stats_other\n'
		} else {
			'const-string v0, "storagestats"\ninvoke-virtual {v0, p1}, Ljava/lang/String;->equals(Ljava/lang/Object;)Z\nmove-result v0\nif-eqz v0, :vinix_storage_stats_other\n'
		}
		lookups = lookups.replace(original, original.replace('.registers 3', '.registers 3\n' +
			guard + 'const/4 v0, 0\nreturn-object v0\n:vinix_storage_stats_other\n'))
	}
	os.mkdir_all(os.dir(path))!
	// A null optional service still needs a resolvable class for its class
	// literal and check-cast. No per-package/UID statistics backend exists.
	// Do not instantiate a manager, grant usage access or fabricate byte counts.
	os.write_file(path, r'.class public Landroid/app/usage/StorageStatsManager;
.super Ljava/lang/Object;
.method private constructor <init>()V
.locals 0
invoke-direct {p0}, Ljava/lang/Object;-><init>()V
return-void
.end method
')!
	os.write_file(context, text)!
	os.write_file(implementation, lookups)!
}
