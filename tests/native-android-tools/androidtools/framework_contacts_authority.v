// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools
import os

// URI identity is available independently of a running Contacts provider.
pub fn framework_contacts_authority(smali string) ! {
	path := smali + '/android/provider/ContactsContract.smali'
	mut source := os.read_file(path)!
	if source.contains(' AUTHORITY_URI:') || source.contains(' <clinit>()V') {
		return error('ContactsContract authority initialization already present')
	}
	source += r'
.field public static final AUTHORITY:Ljava/lang/String; = "com.android.contacts"
.field public static final AUTHORITY_URI:Landroid/net/Uri;
.method static constructor <clinit>()V
.locals 1
const-string v0, "content://com.android.contacts"
invoke-static {v0}, Landroid/net/Uri;->parse(Ljava/lang/String;)Landroid/net/Uri;
move-result-object v0
sput-object v0, Landroid/provider/ContactsContract;->AUTHORITY_URI:Landroid/net/Uri;
return-void
.end method
'
	os.write_file(path, source)!
}
