// SPDX-License-Identifier: GPL-2.0-or-later
// On-demand vendor installs. Nothing here runs while the picker is displayed.
module main

import crypto.sha256
import json2
import os

struct FirstRunDownload {
	url     string
	sha256  string
	deb     bool
	arch    string
	binary  string
	command string
}

struct FirstRunReleaseAsset {
	name                 string
	browser_download_url string
	digest               string
}

struct FirstRunRelease {
	assets []FirstRunReleaseAsset
}

fn first_run_vendor_names() []string {
	return ['vscodium', 'zed', 'discord', 'slack', 'spotify', 'steam']
}

fn first_run_tool(argv []string) !string {
	mut process := os.new_process(argv[0])
	defer { process.close() }
	process.set_args(argv[1..])
	process.set_redirect_stdio_merged()
	process.run()
	output := process.stdout_slurp()
	process.wait()
	if process.code != 0 { return error('${argv[0]} failed (${process.code}): ${output}') }
	return output
}

fn first_run_download(url string, destination string) ! {
	if !url.starts_with('https://') { return error('setup downloads require HTTPS') }
	println('Downloading ${url}')
	// Follow only HTTPS redirects; never run a vendor installation script.
	first_run_tool(['/usr/bin/curl', '--fail', '--location', '--proto', '=https', '--proto-redir',
		'=https', '--retry', '3', '--connect-timeout', '20', '--speed-limit', '1024', '--speed-time',
		'60', '--silent', '--show-error', '--output', destination, url])!
}

fn first_run_file_hash(path string) !string {
	mut file := os.open(path)!
	defer { file.close() }
	mut digest := sha256.new()
	defer { unsafe { digest.free() } }
	mut buffer := []u8{len: 64 * 1024}
	defer { unsafe { buffer.free() } }
	for {
		count := file.read(mut buffer) or {
			if err is os.Eof { break }
			return err
		}
		if count == 0 { break }
		digest.write(buffer[..count])!
	}
	return digest.sum([]u8{}).hex()
}

fn first_run_verify_hash(path string, expected string) ! {
	if expected.len != 64 || !expected.bytes().all((it >= `0` && it <= `9`) || (it >= `a` && it <= `f`))
		|| first_run_file_hash(path)! != expected {
		return error('setup download checksum mismatch: ${os.file_name(path)}')
	}
}

fn first_run_release_download(metadata string, prefix string, suffix string) !FirstRunDownload {
	release := json2.decode[FirstRunRelease](metadata)!
	for asset in release.assets {
		if asset.name.starts_with(prefix) && asset.name.ends_with(suffix)
			&& asset.browser_download_url.starts_with('https://github.com/VSCodium/vscodium/releases/download/') {
			return FirstRunDownload{
				url:    asset.browser_download_url
				sha256: if asset.digest.starts_with('sha256:') { asset.digest[7..] } else { '' }
			}
		}
	}
	return error('the official release has no matching ${prefix} download')
}

fn first_run_slack_download(html string) !string {
	for part in html.split('"') {
		if part.starts_with('https://downloads.slack-edge.com/desktop-releases/linux/')
			&& part.ends_with('-amd64.deb') {
			return part
		}
	}
	return error('Slack did not publish a Linux download on its official download page')
}

fn first_run_vendor_download(name string, work string) !FirstRunDownload {
	arch := $if arm64 { 'aarch64' } $else { 'x86_64' }
	match name {
		'vscodium' {
			metadata := work + '/release.json'
			codium_arch := if arch == 'aarch64' { 'arm64' } else { 'x64' }
			mut asset := FirstRunDownload{}
			first_run_download('https://api.github.com/repos/VSCodium/vscodium/releases/latest', metadata) or {
				// GitHub can rate-limit the unauthenticated API. Its ordinary
				// latest-release redirect provides the same version without a token.
				latest := first_run_tool(['/usr/bin/curl', '--fail', '--location', '--silent',
					'--show-error', '--proto', '=https', '--proto-redir', '=https', '--output',
					'/dev/null', '--write-out', '%{url_effective}',
					'https://github.com/VSCodium/vscodium/releases/latest'])!
				version := latest.all_after_last('/tag/')
				if version == '' || version == latest || !version.bytes().all((it >= `0` && it <= `9`) || it == `.`) {
					return error('cannot determine the official VSCodium release')
				}
				asset = FirstRunDownload{
					url: 'https://github.com/VSCodium/vscodium/releases/download/${version}/VSCodium-linux-${codium_arch}-${version}.tar.gz'
				}
			}
			if asset.url == '' {
				asset = first_run_release_download(os.read_file(metadata)!, 'VSCodium-linux-${codium_arch}-', '.tar.gz')!
			}
			if asset.sha256 == '' {
				checksum := work + '/codium.sha256'
				first_run_download(asset.url + '.sha256', checksum)!
				fields := os.read_file(checksum)!.fields()
				if fields.len == 0 { return error('VSCodium checksum is missing') }
				asset = FirstRunDownload{ ...asset, sha256: fields[0] }
			}
			return FirstRunDownload{ ...asset, arch: arch, binary: 'codium', command: 'codium' }
		}
		'zed' {
			return FirstRunDownload{
				url:     'https://cloud.zed.dev/releases/stable/latest/download?asset=zed&arch=${arch}&os=linux&source=docs'
				arch:    arch
				binary:  'zed.app/libexec/zed-editor'
				command: 'zed'
			}
		}
		'discord' {
			return FirstRunDownload{
				url:     'https://discord.com/api/download?platform=linux&format=tar.gz'
				arch:    'x86_64'
				binary:  'Discord/Discord'
				command: 'discord'
			}
		}
		'slack' {
			page := work + '/slack.html'
			first_run_download('https://slack.com/downloads/instructions/linux?build=deb&ddl=1', page)!
			return FirstRunDownload{
				url:     first_run_slack_download(os.read_file(page)!)!
				deb:     true
				arch:    'x86_64'
				binary:  'usr/lib/slack/slack'
				command: 'slack'
			}
		}
		'spotify' {
			index := work + '/spotify.Packages'
			first_run_download('https://repository.spotify.com/dists/stable/non-free/binary-amd64/Packages', index)!
			for package in first_run_debian_packages(os.read_file(index)!) {
				if package.name == 'spotify-client' {
					return FirstRunDownload{
						url:     'https://repository.spotify.com/' + package.filename
						sha256:  package.sha256
						deb:     true
						arch:    'x86_64'
						binary:  'usr/share/spotify/spotify'
						command: 'spotify'
					}
				}
			}
			return error('the official Spotify repository has no Linux client')
		}
		'steam' {
			return FirstRunDownload{
				url:     'https://cdn.fastly.steamstatic.com/client/installer/steam.deb'
				deb:     true
				arch:    'i386'
				binary:  'usr/lib/steam/bootstraplinux_ubuntu12_32.tar.xz'
				command: 'steam'
			}
		}
		else { return error('unknown setup app: ${name}') }
	}
}

fn first_run_unpack(archive string, destination string, deb bool) ! {
	os.mkdir_all(destination)!
	bsdtar := $if macos { '/usr/bin/tar' } $else { '/usr/bin/bsdtar' }
	if !deb {
		first_run_tool([bsdtar, '-xf', archive, '-C', destination, '--no-same-owner',
			'--no-same-permissions'])!
		return
	}
	// A .deb is an ar container. Extract only its data archive, never maintainer
	// scripts, and then let bsdtar apply its path and symlink traversal checks.
	listing := first_run_tool([bsdtar, '-tf', archive])!
	for member in listing.split_into_lines() {
		if member in ['data.tar.xz', 'data.tar.gz', 'data.tar.zst', 'data.tar.bz2', 'data.tar'] {
			container := destination + '/.deb-data'
			os.mkdir_all(container)!
			defer { os.rmdir_all(container) or {} }
			first_run_tool([bsdtar, '-xf', archive, '-C', container, member])!
			first_run_unpack(container + '/' + member, destination, false)!
			return
		}
	}
	return error('vendor package has no data archive')
}

fn first_run_elf_arch(path string, arch string) ! {
	mut file := os.open(path)!
	defer { file.close() }
	header := file.read_bytes(64)
	machine := match arch {
		'aarch64' { 183 }
		'x86_64' { 62 }
		'i386' { 3 }
		else { 0 }
	}
	if header.len != 64 || header[..4] != [u8(127), `E`, `L`, `F`]
		|| header[4] != (if arch == 'i386' { 1 } else { 2 }) || header[5] != 1
		|| header[6] != 1 || header[16] !in [u8(2), 3] || header[17] != 0
		|| int(header[18]) + int(header[19]) * 256 != machine || !os.is_executable(path) {
		return error('download contains the wrong Linux executable architecture')
	}
}

fn first_run_stage_vendor(download FirstRunDownload, archive string, payload string, steam bool) ! {
	if download.sha256 != '' { first_run_verify_hash(archive, download.sha256)! }
	first_run_unpack(archive, payload, download.deb)!
	if steam {
		first_run_unpack(payload + '/' + download.binary, payload + '/client', false)!
		first_run_elf_arch(payload + '/client/linux32/steam', 'i386')!
	} else {
		first_run_elf_arch(payload + '/' + download.binary, download.arch)!
	}
}

fn first_run_publish_vendor(name string, download FirstRunDownload, payload string, root string) ! {
	base := root + '/opt/vinix-apps'
	os.mkdir_all(base)!
	destination := base + '/' + name
	backup := base + '/.' + name + '-previous'
	if os.exists(backup) { return error('previous setup installation needs recovery: ${backup}') }
	had_previous := os.exists(destination)
	if had_previous { os.mv(destination, backup)! }
	os.mv(payload, destination) or {
		if had_previous { os.mv(backup, destination) or {} }
		return err
	}
	mut complete := false
	defer {
		if !complete {
			os.rmdir_all(destination) or {}
			if had_previous { os.mv(backup, destination) or {} }
		}
	}
	// The entry point reuses this V executable; there are no downloaded scripts
	// or generated shell wrappers. Publish it only after the payload is complete.
	bin := root + '/usr/bin'
	os.mkdir_all(bin)!
	mut commands := [download.command]
	if name == 'zed' { commands << 'run-zed' }
	if name == 'steam' { commands << 'steam-hosted' }
	for command in commands {
		alias := bin + '/' + command
		temporary := alias + '.setup'
		os.rm(temporary) or {}
		os.symlink('/usr/bin/vinix-desktop', temporary)!
		os.mv(temporary, alias, overwrite: true)!
	}
	applications := root + '/usr/share/applications'
	os.mkdir_all(applications)!
	title := first_run_app_catalogue.filter(it.package_name == name)[0].title
	os.write_file(applications + '/vinix-${name}.desktop', '[Desktop Entry]\nType=Application\nName=${title}\nExec=/usr/bin/vinix-desktop --run-setup-app ${name}\nIcon=${name}\nTerminal=false\n')!
	manifest := root + '/var/lib/vinix-pkg'
	os.mkdir_all(manifest)!
	paths := commands.map('usr/bin/' + it).join('\n')
	os.write_file(manifest + '/${name}.files', 'opt/vinix-apps/${name}\n${paths}\nusr/share/applications/vinix-${name}.desktop\n')!
	complete = true
	if had_previous { os.rmdir_all(backup)! }
}

fn first_run_install_vendor(name string) ! {
	if !first_run_apps.any(it.package_name == name) { return error('unknown setup app: ${name}') }
	if name == 'ios-runtime' {
		first_run_install_ios_runtime('')!
		if os.is_executable('/usr/libexec/vinix-persist-packages') {
			first_run_tool(['/usr/libexec/vinix-persist-packages', 'save'])!
		}
		return
	}
	if name !in first_run_vendor_names() {
		mut packages := [name]
		if name == 'libreoffice' {
			packages << ['libreoffice-gtk', 'libreoffice-lang-en_us', 'ttf-liberation', 'font-dejavu', 'adwaita-icon-theme']
		}
		if name in ['vlc-qt', 'keepassxc'] { packages << ['qt5-qtbase-x11', 'font-dejavu'] }
		if name == 'telegram-desktop' { packages << ['qt6-qtbase-x11', 'font-dejavu'] }
		first_run_tool(['pkg', 'install', ...packages])!
		return
	}
	// Refresh first: an empty/stale local index is not evidence a package is
	// unavailable. Do not mix edge repositories into a stable installation.
	first_run_tool(['pkg', 'update'])!
	available := first_run_tool(['/sbin/apk', 'search', '--exact', name])!
	if available.trim_space() != '' {
		println('Installing ${name} from Alpine')
		first_run_tool(['pkg', 'install', name])!
		return
	}
	// Vendor Linux applications are X11 clients the desktop hosts on Xvfb, and
	// unlike Alpine's they do not bring X11 through apk.
	first_run_tool(['pkg', 'install', 'libarchive-tools', 'font-dejavu', 'bash', 'x11'])!
	os.mkdir_all('/var/cache/vinix-setup')!
	work := '/var/cache/vinix-setup/${name}-${os.getpid()}'
	os.mkdir(work)!
	defer { os.rmdir_all(work) or {} }
	download := first_run_vendor_download(name, work)!
	archive := work + '/download'
	first_run_download(download.url, archive)!
	payload := work + '/payload'
	first_run_stage_vendor(download, archive, payload, name == 'steam')!
	first_run_install_linux_runtime(download.arch, work)!
	if name == 'steam' { first_run_install_linux_runtime('x86_64', work)! }
	first_run_publish_vendor(name, download, payload, '')!
	if os.is_executable('/usr/libexec/vinix-persist-packages') {
		first_run_tool(['/usr/libexec/vinix-persist-packages', 'save'])!
	}
	println('Installed ${name}')
}

fn first_run_launch_vendor(name string, args []string) ! {
	if name !in first_run_vendor_names() { return error('unknown setup app: ${name}') }
	base := '/opt/vinix-apps/' + name
	arch := if name in ['discord', 'slack', 'spotify'] {
		'x86_64'
	} else if name == 'steam' {
		'i386'
	} else {
		$if arm64 {
			'aarch64'
		} $else {
			'x86_64'
		}
	}
	binary := match name {
		'vscodium' { 'codium' }
		'zed' { 'zed.app/libexec/zed-editor' }
		'discord' { 'Discord/Discord' }
		'slack' { 'usr/lib/slack/slack' }
		'spotify' { 'usr/share/spotify/spotify' }
		else { 'client/steam.sh' }
	}
	runtime := '/opt/vinix-linux/' + arch
	triplet := first_run_debian_triplet(arch)
	libraries := '${base}/${os.dir(binary)}:${runtime}/usr/lib/${triplet}:${runtime}/lib/${triplet}:${runtime}/usr/lib:${runtime}/lib'
	os.setenv('VINIX_X86_64_ROOT', '/opt/vinix-linux/x86_64', true)
	os.setenv('VINIX_I386_ROOT', '/opt/vinix-linux/i386', true)
	os.setenv('VINIX_X86_MULTIARCH', '1', true)
	os.setenv('VINIX_ALLOW_WX', '1', true)
	os.setenv('QEMU_CPU', 'max', false)
	os.unsetenv('WAYLAND_DISPLAY')
	os.setenv('LIBGL_DRIVERS_PATH', runtime + '/usr/lib/' + triplet + '/dri', true)
	if name == 'zed' {
		os.setenv('VK_ICD_FILENAMES', runtime + '/usr/share/vulkan/icd.d/lvp_icd.' + arch + '.json', true)
	}
	if name == 'steam' {
		os.setenv('STEAMSCRIPT', '/usr/bin/steam', true)
		os.execvp('/bin/bash', [base + '/' + binary, ...args])!
		return
	}
	loader := runtime + '/usr/lib/' + triplet + '/' + first_run_linux_loader(arch)
	mut launch_args := ['--library-path', libraries, base + '/' + binary]
	if name in ['vscodium', 'discord', 'slack'] {
		launch_args << ['--no-sandbox', '--disable-dev-shm-usage', '--ozone-platform=x11']
		if name == 'vscodium' {
			launch_args << '--user-data-dir=' + desktop_home + '/.config/VSCodium'
		}
	}
	launch_args << args
	$if arm64 {
		if arch == 'x86_64' {
			os.execvp('/usr/bin/qemu-x86_64', ['-L', runtime, loader, ...launch_args])!
			return
		}
	}
	os.execvp(loader, launch_args)!
}
