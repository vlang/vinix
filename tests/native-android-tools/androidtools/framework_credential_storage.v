// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn credential_storage_class(source string, declaration string, parent string) ! {
	if source.split_into_lines().filter(it.starts_with('.class ')) != [declaration]
		|| source.split_into_lines().filter(it.starts_with('.super ')) != ['.super L' + parent + ';']
		|| source.count('.method ') != source.count('.end method')
		|| source.contains('createCredentialProtectedStorageContext(')
		|| source.contains('isCredentialProtectedStorage(') {
		return error('unexpected or already extended credential storage class')
	}
}

pub fn framework_credential_storage_context(source string) !string {
	credential_storage_class(source, '.class public abstract Landroid/content/Context;', 'java/lang/Object')!
	if source.count('.method public abstract createDeviceProtectedStorageContext()Landroid/content/Context;') != 1
		|| source.count('.method public abstract isDeviceProtectedStorage()Z') != 1 {
		return error('missing Context device storage API')
	}
	return source + '\n.method public abstract createCredentialProtectedStorageContext()Landroid/content/Context;\n.end method\n\n.method public abstract isCredentialProtectedStorage()Z\n.end method\n'
}

pub fn framework_credential_storage_wrapper(source string) !string {
	credential_storage_class(source, '.class public Landroid/content/ContextWrapper;', 'android/content/Context')!
	if source.count('.field private baseContext:Landroid/content/Context;') != 1 {
		return error('unexpected ContextWrapper base field')
	}
	return source + '
.method public createCredentialProtectedStorageContext()Landroid/content/Context;
    .registers 2
    iget-object v0, p0, Landroid/content/ContextWrapper;->baseContext:Landroid/content/Context;
    invoke-virtual {v0}, Landroid/content/Context;->createCredentialProtectedStorageContext()Landroid/content/Context;
    move-result-object v0
    return-object v0
.end method

.method public isCredentialProtectedStorage()Z
    .registers 2
    iget-object v0, p0, Landroid/content/ContextWrapper;->baseContext:Landroid/content/Context;
    invoke-virtual {v0}, Landroid/content/Context;->isCredentialProtectedStorage()Z
    move-result v0
    return v0
.end method
'
}

// This runtime already models CE at the app root and DE at its private child.
// Clear only its DE flag and allocate a fresh ContextImpl, avoiding inherited
// directory/preference caches while preserving app, resources and other flags.
pub fn framework_credential_storage_impl(source string) !string {
	credential_storage_class(source, '.class public final Landroid/app/ContextImpl;', 'android/content/Context')!
	for anchor in ['.field private static final ATL_FLAG_PROTECTED_STORAGE:I = 0x4',
		'.field private final atl_flags:I', '.field private final atl_loaded_app:Landroid/atl/ATLLoadedApp;',
		'.method private constructor <init>(Landroid/content/res/Resources;Landroid/atl/ATLLoadedApp;Landroid/content/res/Resources$Theme;I)V',
		'.method public createDeviceProtectedStorageContext()Landroid/content/Context;',
		'.method public isDeviceProtectedStorage()Z'] {
		if source.count(anchor) != 1 { return error('unexpected ContextImpl credential storage anchor') }
	}
	return source + '
.method public createCredentialProtectedStorageContext()Landroid/content/Context;
    .registers 6
    new-instance v0, Landroid/app/ContextImpl;
    invoke-virtual {p0}, Landroid/app/ContextImpl;->getResources()Landroid/content/res/Resources;
    move-result-object v1
    iget-object v2, p0, Landroid/app/ContextImpl;->atl_loaded_app:Landroid/atl/ATLLoadedApp;
    invoke-virtual {p0}, Landroid/app/ContextImpl;->getTheme()Landroid/content/res/Resources$Theme;
    move-result-object v3
    iget v4, p0, Landroid/app/ContextImpl;->atl_flags:I
    and-int/lit8 v4, v4, -0x5
    invoke-direct {v0, v1, v2, v3, v4}, Landroid/app/ContextImpl;-><init>(Landroid/content/res/Resources;Landroid/atl/ATLLoadedApp;Landroid/content/res/Resources$Theme;I)V
    return-object v0
.end method

.method public isCredentialProtectedStorage()Z
    .registers 2
    invoke-virtual {p0}, Landroid/app/ContextImpl;->isDeviceProtectedStorage()Z
    move-result v0
    xor-int/lit8 v0, v0, 0x1
    return v0
.end method
'
}

fn framework_credential_storage(smali string) ! {
	for name, source in {
		'android/content/Context.smali': framework_credential_storage_context(os.read_file(smali + '/android/content/Context.smali')!)!
		'android/content/ContextWrapper.smali': framework_credential_storage_wrapper(os.read_file(smali + '/android/content/ContextWrapper.smali')!)!
		'android/app/ContextImpl.smali': framework_credential_storage_impl(os.read_file(smali + '/android/app/ContextImpl.smali')!)!
	} {
		os.write_file(smali + '/' + name, source)!
	}
}
