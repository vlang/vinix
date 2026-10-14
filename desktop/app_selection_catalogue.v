// SPDX-License-Identifier: GPL-2.0-or-later
module main

enum FirstRunCategory {
	browsers
	productivity
	development
	communication
	media
	games
	runtimes
}

const first_run_categories = [FirstRunCategory.browsers, .productivity, .development, .communication,
	.media, .games, .runtimes]
const first_run_category_actions = ['apps.category.browsers', 'apps.category.productivity',
	'apps.category.development', 'apps.category.communication', 'apps.category.media',
	'apps.category.games', 'apps.category.runtimes']

fn (category FirstRunCategory) text() string {
	return match category {
		.browsers { tr('app_selection.category.browsers') }
		.productivity { tr('app_selection.category.productivity') }
		.development { tr('app_selection.category.development') }
		.communication { tr('app_selection.category.communication') }
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
const first_run_app_catalogue = [
	FirstRunApp{
		title:           'Firefox'
		icon:            'asset:firefox'
		package_name:    'firefox'
		action:          'apps.toggle.firefox'
		installed_paths: ['/usr/lib/firefox-esr/firefox-esr', '/usr/lib/firefox/firefox']
	},
	FirstRunApp{
		title:           'Chromium'
		icon:            'asset:chromium'
		package_name:    'chromium'
		action:          'apps.toggle.chromium'
		installed_paths: ['/usr/lib/chromium/chrome']
	},
	FirstRunApp{
		title:           'VOffice'
		icon:            'builtin:editor'
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
		action:          'apps.toggle.blender'
		installed_paths: ['/usr/bin/blender', '/usr/libexec/vinix-blender-native']
		category:        .media
	},
	FirstRunApp{
		title:           'VLC'
		icon:            'asset:vlc'
		package_name:    'vlc-qt'
		action:          'apps.toggle.vlc'
		installed_paths: ['/usr/bin/qvlc']
		category:        .media
	},
	FirstRunApp{
		title:           'VSCodium'
		icon:            'asset:vscodium'
		package_name:    'vscodium'
		action:          'apps.toggle.vscodium'
		installed_paths: ['/usr/bin/codium']
		category:        .development
		requirement:     .testing
	},
	FirstRunApp{
		title:           'Zed'
		icon:            'asset:zed'
		package_name:    'zed'
		action:          'apps.toggle.zed'
		installed_paths: ['/usr/bin/zed-editor', '/usr/bin/zed']
		category:        .development
		requirement:     .testing
	},
	FirstRunApp{
		title:           'Neovim'
		icon:            'asset:neovim'
		package_name:    'neovim'
		action:          'apps.toggle.neovim'
		installed_paths: ['/usr/bin/nvim']
		category:        .development
	},
	FirstRunApp{
		title:           'KeePassXC'
		icon:            'asset:keepassxc'
		package_name:    'keepassxc'
		action:          'apps.toggle.keepassxc'
		installed_paths: ['/usr/bin/keepassxc']
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
		action:          'apps.toggle.obs'
		installed_paths: ['/usr/bin/obs']
		category:        .media
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
		title:           'iOS runtime'
		icon:            'asset:ios'
		package_name:    'ios-runtime'
		action:          'apps.toggle.ios'
		installed_paths: ['/usr/bin/run-ios']
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

// Testing packages are offered only on an image already configured for edge;
// setup must not mix an edge dependency closure into the stable Alpine base.
fn first_run_testing_repositories(repositories string) bool {
	mut main_repo := false
	mut community := false
	mut testing := false
	for line in repositories.split_into_lines() {
		entry := line.all_before('#').trim_space()
		if entry.starts_with('@') { continue }
		main_repo = main_repo || entry.ends_with('/edge/main')
		community = community || entry.ends_with('/edge/community')
		testing = testing || entry.ends_with('/edge/testing')
	}
	return main_repo && community && testing
}
