// SPDX-License-Identifier: GPL-2.0-or-later
// One read-only client shared by Settings and the bottom-right taskbar clock.
module main

import ui2

#flag -I @VMODROOT
#include "battery_client.h"

fn C.vd_battery_get(force int) int

const battery_unavailable = -1
const battery_permission = -2
const battery_invalid = -3
const battery_io = -4

// Static strings survive the element tree and do not allocate on every frame.
const battery_percentage_labels = [
	'0%', '1%', '2%', '3%', '4%', '5%', '6%', '7%', '8%', '9%',
	'10%', '11%', '12%', '13%', '14%', '15%', '16%', '17%', '18%', '19%',
	'20%', '21%', '22%', '23%', '24%', '25%', '26%', '27%', '28%', '29%',
	'30%', '31%', '32%', '33%', '34%', '35%', '36%', '37%', '38%', '39%',
	'40%', '41%', '42%', '43%', '44%', '45%', '46%', '47%', '48%', '49%',
	'50%', '51%', '52%', '53%', '54%', '55%', '56%', '57%', '58%', '59%',
	'60%', '61%', '62%', '63%', '64%', '65%', '66%', '67%', '68%', '69%',
	'70%', '71%', '72%', '73%', '74%', '75%', '76%', '77%', '78%', '79%',
	'80%', '81%', '82%', '83%', '84%', '85%', '86%', '87%', '88%', '89%',
	'90%', '91%', '92%', '93%', '94%', '95%', '96%', '97%', '98%', '99%',
	'100%',
]

fn read_battery(force bool) int {
	return C.vd_battery_get(if force { 1 } else { 0 })
}

fn battery_percentage_text(percent int) string {
	if percent < 0 || percent > 100 {
		return '--%'
	}
	return battery_percentage_labels[percent]
}

fn battery_clock_label(percent int, clock string) string {
	return '${battery_percentage_text(percent)}  |  ${clock}'
}

fn battery_status_text(percent int) string {
	if percent >= 0 && percent <= 100 {
		return 'Percentage reported by the battery driver.'
	}
	return match percent {
		battery_unavailable { 'Battery driver not available.' }
		battery_permission { 'Permission denied reading the battery.' }
		battery_invalid { 'Invalid battery response.' }
		else { 'Battery read failed or the sample is stale.' }
	}
}

fn battery_settings_elements(percent int, x int, inner int) []ui2.Element {
	available := percent >= 0 && percent <= 100
	mut children := [
		ui2.label('settings.battery.title', 'Battery', ui2.rect(f64(x), 16, f64(inner), 28),
			ui2.TextStyle{color: body_heading, size: 20, bold: true}),
		settings_label('Built-in battery', x, 46, inner, body_muted),
		ui2.view('', ui2.rect(f64(x), 76, f64(inner), 1), ui2.BoxStyle{bg: body_rule}, []),
		settings_label('Remaining charge', x, 90, inner, body_heading),
		ui2.label('settings.battery.percent',
			if available { battery_percentage_text(percent) } else { 'Unavailable' },
			ui2.rect(f64(x), 118, f64(inner), 40),
			ui2.TextStyle{color: if available { body_heading } else { body_muted },
				size: 28, bold: true}),
		ui2.view('settings.battery.track', ui2.rect(f64(x), 172, f64(inner), 12),
			ui2.BoxStyle{bg: body_rule, radius: 4}, []),
		settings_label(battery_status_text(percent), x, 200, inner,
			if available { body_muted } else { files_error }),
		settings_button('settings.refresh', 'Refresh', ui2.rect(f64(x), 238, 80, 30), true),
		settings_label('Read-only. Updates every 5 seconds.', x, 280, inner, body_muted),
	]
	if available && percent > 0 {
		children << ui2.view('settings.battery.fill',
			ui2.rect(f64(x), 172, f64(inner * percent / 100), 12),
			ui2.BoxStyle{bg: accent, radius: 4}, [])
	}
	if percent == battery_unavailable {
		children << settings_label('M1: boot with vinix.apple_battery=1.', x, 308, inner, body_muted)
	} else {
		children << settings_label('Source: /dev/battery', x, 308, inner, body_muted)
	}
	return children
}
