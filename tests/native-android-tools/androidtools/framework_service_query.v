// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

// Explicit component queries do not depend on intent filters. Reuse the
// existing metadata/package loader, including its package visibility policy;
// querying metadata neither starts the Application nor grants service access.
// The implicit resolver and its existing scope remain unchanged.
pub fn framework_service_query(source string) !string {
	if source.split_into_lines().filter(it.starts_with('.class ')) != ['.class public Landroid/content/pm/PackageManager;']
		|| source.split_into_lines().filter(it.starts_with('.super ')) != ['.super Ljava/lang/Object;']
		|| source.count('.method ') != source.count('.end method') {
		return error('unexpected service query PackageManager class')
	}
	if source.contains(':vinix_service_query_') { return error('service query already extended') }
	signature := 'queryIntentServices(Landroid/content/Intent;I)Ljava/util/List;'
	mut original := ''
	for block in source.split('.method ')[1..] {
		if !block.all_before('\n').ends_with(' ' + signature) { continue }
		if original != '' { return error('duplicate service query method') }
		end := block.index('.end method') or { return error('unterminated service query') }
		original = '.method ' + block[..end + '.end method'.len]
	}
	anchor := '    new-instance v2, Ljava/util/ArrayList;'
	if original == '' || original.count('    .registers 10\n') != 1 || original.count(anchor) != 1
		|| original.count('->getComponent()Landroid/content/ComponentName;') != 1
		|| original.count('->intents:Ljava/util/ArrayList;') != 1 {
		return error('unexpected service query input contract')
	}
	guard := '
    invoke-virtual {p1}, Landroid/content/Intent;->getComponent()Landroid/content/ComponentName;
    move-result-object v0
    if-eqz v0, :vinix_service_query_implicit
    new-instance v2, Ljava/util/ArrayList;
    invoke-direct {v2}, Ljava/util/ArrayList;-><init>()V
    :vinix_service_query_lookup
    invoke-virtual {p0, v0, p2}, Landroid/content/pm/PackageManager;->getServiceInfo(Landroid/content/ComponentName;I)Landroid/content/pm/ServiceInfo;
    move-result-object v1
    :vinix_service_query_lookup_end
    .catch Landroid/content/pm/PackageManager$NameNotFoundException; {:vinix_service_query_lookup .. :vinix_service_query_lookup_end} :vinix_service_query_missing
    if-eqz v1, :vinix_service_query_done
    and-int/lit16 v3, p2, 0x200
    if-nez v3, :vinix_service_query_found
    iget-boolean v3, v1, Landroid/content/pm/ComponentInfo;->enabled:Z
    if-eqz v3, :vinix_service_query_done
    iget-object v3, v1, Landroid/content/pm/ComponentInfo;->applicationInfo:Landroid/content/pm/ApplicationInfo;
    if-eqz v3, :vinix_service_query_done
    iget-boolean v3, v3, Landroid/content/pm/ApplicationInfo;->enabled:Z
    if-eqz v3, :vinix_service_query_done
    :vinix_service_query_found
    new-instance v0, Landroid/content/pm/ResolveInfo;
    invoke-direct {v0}, Landroid/content/pm/ResolveInfo;-><init>()V
    iput-object v1, v0, Landroid/content/pm/ResolveInfo;->serviceInfo:Landroid/content/pm/ServiceInfo;
    invoke-interface {v2, v0}, Ljava/util/List;->add(Ljava/lang/Object;)Z
    :vinix_service_query_done
    return-object v2
    :vinix_service_query_missing
    move-exception v0
    goto :vinix_service_query_done
    :vinix_service_query_implicit
'
	return framework_replace_method(source, signature, original.replace(anchor, guard + anchor))!
}

fn framework_service_queries(smali string) ! {
	path := smali + '/android/content/pm/PackageManager.smali'
	os.write_file(path, framework_service_query(os.read_file(path)!)!)!
}
