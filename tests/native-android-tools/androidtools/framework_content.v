// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

fn framework_content_clients(smali string) ! {
	resolver := smali + '/android/content/ContentResolver.smali'
	mut text := os.read_file(resolver)!
	for name in ['acquireContentProviderClient', 'acquireUnstableContentProviderClient'] {
		for argument in ['Landroid/net/Uri;', 'Ljava/lang/String;'] {
			signature := name + '(' + argument + ')Landroid/content/ContentProviderClient;'
			text = framework_replace_method(text, signature, '.method public native ' + signature + '\n.end method')!
		}
	}
	os.write_file(resolver, text)!
	mut client := '.class public Landroid/content/ContentProviderClient;\n.super Ljava/lang/Object;\n.implements Ljava/lang/AutoCloseable;\n'
	client += '.field private vinixProvider:Landroid/content/ContentProvider;\n.field private vinixClosed:I\n'
	client += '.method public constructor <init>(Landroid/content/ContentProvider;)V\n.locals 0\ninvoke-direct {p0}, Ljava/lang/Object;-><init>()V\niput-object p1, p0, Landroid/content/ContentProviderClient;->vinixProvider:Landroid/content/ContentProvider;\nreturn-void\n.end method\n'
	for signature in ['close()V', 'release()Z',
		'getLocalContentProvider()Landroid/content/ContentProvider;',
		'getType(Landroid/net/Uri;)Ljava/lang/String;',
		'call(Ljava/lang/String;Ljava/lang/String;Landroid/os/Bundle;)Landroid/os/Bundle;'] {
		client += '.method public native ' + signature + '\n.end method\n'
	}
	os.write_file(smali + '/android/content/ContentProviderClient.smali', client)!
	// Android's base provider has no implementation-specific call operations.
	// Subclasses overriding call still receive the normal virtual dispatch.
	provider := smali + '/android/content/ContentProvider.smali'
	signature := 'call(Ljava/lang/String;Ljava/lang/String;Landroid/os/Bundle;)Landroid/os/Bundle;'
	os.write_file(provider, framework_replace_method(os.read_file(provider)!, signature,
		'.method public native ' + signature + '\n.end method')!)!
}
