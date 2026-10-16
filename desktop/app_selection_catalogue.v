// SPDX-License-Identifier: GPL-2.0-or-later
module main

enum FirstRunCategory {
	browsers
	productivity
	development
	communication
	creation
	media
	games
	runtimes
}

const first_run_categories = [FirstRunCategory.browsers, .productivity, .development, .communication,
	.creation, .media, .games, .runtimes]
const first_run_category_headers = ['apps.heading.browsers', 'apps.heading.productivity',
	'apps.heading.development', 'apps.heading.communication', 'apps.heading.creation', 'apps.heading.media',
	'apps.heading.games', 'apps.heading.runtimes']

const first_run_app_order = first_run_app_display_order()

fn first_run_app_display_order() []int {
	mut order := []int{cap: first_run_apps.len}
	for category in first_run_categories {
		for i, app in first_run_apps {
			if app.category == category { order << i }
		}
	}
	return order
}

fn (category FirstRunCategory) text() string {
	return match category {
		.browsers { tr('app_selection.category.browsers') }
		.productivity { tr('app_selection.category.productivity') }
		.development { tr('app_selection.category.development') }
		.communication { tr('app_selection.category.communication') }
		.creation { tr('app_selection.category.creation') }
		.media { tr('app_selection.category.media') }
		.games { tr('app_selection.category.games') }
		.runtimes { tr('app_selection.category.runtimes') }
	}
}

enum FirstRunRequirement {
	alpine
	testing
	external
	steam
	ios
}

// Retain the original first four identities for existing setup automation.
// Categories control presentation independently of installation order.
// open_source describes the app itself, including Vinix's native iOS runner,
// rather than the services, documents or games it may connect to or run.
const first_run_app_catalogue = [
	FirstRunApp{
		title:           'Firefox'
		icon:            'asset:firefox'
		package_name:    'firefox'
		open_source:     true
		action:          'apps.toggle.firefox'
		installed_paths: ['/usr/lib/firefox-esr/firefox-esr', '/usr/lib/firefox/firefox']
	},
	FirstRunApp{
		title:           'Chromium'
		icon:            'asset:chromium'
		package_name:    'chromium'
		open_source:     true
		action:          'apps.toggle.chromium'
		installed_paths: ['/usr/lib/chromium/chrome']
	},
	FirstRunApp{
		title:           'VOffice'
		icon:            'asset:voffice'
		package_name:    'voffice'
		action:          'apps.toggle.voffice'
		installed_paths: ['/usr/bin/voffice-writer']
		arm64_only:      true
		category:        .productivity
	},
	FirstRunApp{
		title:           'Minecraft'
		icon:            'asset:minecraft'
		package_name:    'minecraft'
		action:          'apps.toggle.minecraft'
		installed_paths: ['/usr/bin/minecraft']
		arm64_only:      true
		category:        .games
	},
	FirstRunApp{
		title:           'Blender'
		icon:            'asset:blender'
		package_name:    'blender'
		open_source:     true
		action:          'apps.toggle.blender'
		installed_paths: ['/usr/bin/blender', '/usr/libexec/vinix-blender-native']
		category:        .creation
	},
	FirstRunApp{
		title:           'VLC'
		icon:            'asset:vlc'
		package_name:    'vlc-qt'
		open_source:     true
		action:          'apps.toggle.vlc'
		installed_paths: ['/usr/bin/qvlc']
		category:        .media
	},
	FirstRunApp{
		title:           'VSCodium'
		icon:            'asset:vscodium'
		package_name:    'vscodium'
		open_source:     true
		action:          'apps.toggle.vscodium'
		installed_paths: ['/usr/bin/codium']
		category:        .development
		requirement:     .testing
	},
	FirstRunApp{
		title:           'Zed'
		icon:            'asset:zed'
		package_name:    'zed'
		open_source:     true
		action:          'apps.toggle.zed'
		installed_paths: ['/usr/bin/zed-editor', '/usr/bin/zed', '/usr/bin/run-zed']
		category:        .development
		requirement:     .testing
	},
	FirstRunApp{
		title:           'Neovim'
		icon:            'asset:neovim'
		package_name:    'neovim'
		open_source:     true
		action:          'apps.toggle.neovim'
		installed_paths: ['/usr/bin/nvim']
		category:        .development
	},
	FirstRunApp{
		title:           'KeePassXC'
		icon:            'asset:keepassxc'
		package_name:    'keepassxc'
		open_source:     true
		action:          'apps.toggle.keepassxc'
		installed_paths: ['/usr/bin/keepassxc']
		category:        .productivity
	},
	FirstRunApp{
		title:           'LibreOffice'
		icon:            'asset:libreoffice'
		package_name:    'libreoffice'
		open_source:     true
		action:          'apps.toggle.libreoffice'
		installed_paths: ['/usr/lib/libreoffice/program/soffice.bin', '/usr/bin/libreoffice']
		category:        .productivity
	},
	FirstRunApp{
		title:           'Discord'
		icon:            'asset:discord'
		package_name:    'discord'
		action:          'apps.toggle.discord'
		installed_paths: ['/usr/bin/discord', '/opt/discord/Discord']
		category:        .communication
		requirement:     .external
	},
	FirstRunApp{
		title:           'Telegram'
		icon:            'asset:telegram'
		package_name:    'telegram-desktop'
		open_source:     true
		action:          'apps.toggle.telegram'
		installed_paths: ['/usr/bin/telegram-desktop']
		category:        .communication
	},
	FirstRunApp{
		title:           'Slack'
		icon:            'asset:slack'
		package_name:    'slack'
		action:          'apps.toggle.slack'
		installed_paths: ['/usr/bin/slack', '/opt/slack/slack']
		category:        .communication
		requirement:     .external
	},
	FirstRunApp{
		title:           'mpv'
		icon:            'asset:mpv'
		package_name:    'mpv'
		open_source:     true
		action:          'apps.toggle.mpv'
		installed_paths: ['/usr/bin/mpv']
		category:        .media
	},
	FirstRunApp{
		title:           'Spotify'
		icon:            'asset:spotify'
		package_name:    'spotify'
		action:          'apps.toggle.spotify'
		installed_paths: ['/usr/bin/spotify', '/opt/spotify/spotify']
		category:        .media
		requirement:     .external
	},
	FirstRunApp{
		title:           'OBS Studio'
		icon:            'asset:obs'
		package_name:    'obs-studio'
		open_source:     true
		action:          'apps.toggle.obs'
		installed_paths: ['/usr/bin/obs']
		category:        .creation
	},
	FirstRunApp{
		title:           'Steam'
		icon:            'asset:steam'
		package_name:    'steam'
		action:          'apps.toggle.steam'
		installed_paths: ['/usr/bin/steam']
		category:        .games
		requirement:     .steam
	},
	FirstRunApp{
		title:           'iOS'
		icon:            'asset:ios'
		package_name:    'ios-runtime'
		open_source:     true
		action:          'apps.toggle.ios'
		installed_paths: ['/usr/bin/run-ios']
		arm64_only:      true
		category:        .runtimes
		requirement:     .ios
	},
]

fn (app FirstRunApp) requirement_text() string {
	return match app.requirement {
		.alpine { '' }
		.testing { tr('app_selection.requires.testing') }
		.external { tr('app_selection.requires.external') }
		.steam { tr('app_selection.requires.steam') }
		.ios { tr('app_selection.requires.ios') }
	}
}
