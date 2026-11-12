// SPDX-License-Identifier: GPL-2.0-or-later
module androidtools

import os

pub fn framework_display_sms(smali string) ! {
	display := 'Landroid/view/Display;'
	path := smali + '/android/view/Display.smali'
	mut source := os.read_file(path)!
	if source.contains(' getState()I') { return error('display state already exists') }
	// The current desktop adapter exposes one continuously driven display,
	// without suspend, hotplug or display-power control.
	source += signature_method('public getState()I', 'const/4 v0, 2\nreturn v0')
	for name, value in {'STATE_UNKNOWN': 0, 'STATE_OFF': 1, 'STATE_ON': 2, 'STATE_DOZE': 3,
		'STATE_DOZE_SUSPEND': 4, 'STATE_VR': 5, 'STATE_ON_SUSPEND': 6, 'DEFAULT_DISPLAY': 0, 'INVALID_DISPLAY': -1} {
		source += '\n.field public static final ${name}:I = ${value}\n'
	}
	os.write_file(path, source)!
	manager := smali + '/android/hardware/display/DisplayManager.smali'
	mut catalog := os.read_file(manager)!
	catalog = framework_replace_method(catalog, 'getDisplay(I)' + display,
		signature_method('public getDisplay(I)' + display,
			'if-nez p1, :missing\nnew-instance v0, ${display}\ninvoke-direct {v0}, ${display}-><init>()V\nreturn-object v0\n:missing\nconst/4 v0, 0\nreturn-object v0'))!
	catalog = framework_replace_method(catalog, 'getDisplays()[' + display,
		signature_method('public getDisplays()[' + display,
			'const/4 v0, 1\nnew-array v0, v0, [${display}\nnew-instance v1, ${display}\ninvoke-direct {v1}, ${display}-><init>()V\nconst/4 v2, 0\naput-object v1, v0, v2\nreturn-object v0'))!
	os.write_file(manager, catalog)!
	sms := smali + '/android/provider/Telephony$Sms.smali'
	mut metadata := os.read_file(sms)!
	if metadata.contains('CONTENT_URI:') || metadata.contains(' <clinit>()V') {
		return error('unexpected SMS metadata initialization')
	}
	metadata += '\n.field public static final CONTENT_URI:Landroid/net/Uri;\n' +
		signature_method('static constructor <clinit>()V',
			'const-string v0, "content://sms"\ninvoke-static {v0}, Landroid/net/Uri;->parse(Ljava/lang/String;)Landroid/net/Uri;\nmove-result-object v0\nsput-object v0, Landroid/provider/Telephony$Sms;->CONTENT_URI:Landroid/net/Uri;\nreturn-void')
	os.write_file(sms, metadata)!
}
