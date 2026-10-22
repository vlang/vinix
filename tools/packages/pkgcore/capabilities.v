// SPDX-License-Identifier: GPL-2.0-or-later
module pkgcore

import tools.packages.appsdk
import tools.packages.pkgprotocol

// Read-only build interface discovery. These versions describe parsers and
// launch protocols, not available foreign runtimes or an enrolled publisher.
pub fn capabilities() pkgprotocol.Capabilities {
	return pkgprotocol.Capabilities{
		package_formats: [format_version]
		application_sdks: [appsdk.context_version]
		native_window_protocols: [appsdk.window_protocol, appsdk.window_text_protocol]
		deployment_formats: [1, 2]
	}
}
