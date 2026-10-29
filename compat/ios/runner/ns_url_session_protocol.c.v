// SPDX-License-Identifier: GPL-2.0-or-later
module main

enum URLSessionProtocolRoute { unsupported custom http https }

// A default configuration, and an explicit nil/empty protocolClasses override,
// retain Foundation's built-in URL handling. The transport can select HTTP(S)
// without synthesizing private Foundation protocol class identities. A nonempty
// custom list requires its own selection/loading implementation; never skip it.
fn (snapshot &URLSessionRequestSnapshot) protocol_route() URLSessionProtocolRoute {
	if snapshot.issue != .none { return .unsupported }
	if snapshot.configuration.custom_protocols { return .custom }
	url := data_http_url(snapshot.url) or { return .unsupported }
	return if url.tls { URLSessionProtocolRoute.https } else { URLSessionProtocolRoute.http }
}
