// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
// Battery presentation shared by Settings and the device-backed client.
module main

import ui2

// Static strings survive the element tree and do not allocate on every frame.
const battery_percentage_labels = [
	'0%',
	'1%',
	'2%',
	'3%',
	'4%',
	'5%',
	'6%',
	'7%',
	'8%',
	'9%',
	'10%',
	'11%',
	'12%',
	'13%',
	'14%',
	'15%',
	'16%',
	'17%',
	'18%',
	'19%',
	'20%',
	'21%',
	'22%',
	'23%',
	'24%',
	'25%',
	'26%',
	'27%',
	'28%',
	'29%',
	'30%',
	'31%',
	'32%',
	'33%',
	'34%',
	'35%',
	'36%',
	'37%',
	'38%',
	'39%',
	'40%',
	'41%',
	'42%',
	'43%',
	'44%',
	'45%',
	'46%',
	'47%',
	'48%',
	'49%',
	'50%',
	'51%',
	'52%',
	'53%',
	'54%',
	'55%',
	'56%',
	'57%',
	'58%',
	'59%',
	'60%',
	'61%',
	'62%',
	'63%',
	'64%',
	'65%',
	'66%',
	'67%',
	'68%',
	'69%',
	'70%',
	'71%',
	'72%',
	'73%',
	'74%',
	'75%',
	'76%',
	'77%',
	'78%',
	'79%',
	'80%',
	'81%',
	'82%',
	'83%',
	'84%',
	'85%',
	'86%',
	'87%',
	'88%',
	'89%',
	'90%',
	'91%',
	'92%',
	'93%',
	'94%',
	'95%',
	'96%',
	'97%',
	'98%',
	'99%',
	'100%',
]

const battery_remaining_labels = [
	'Less than 1 hour',
	'About 1 hour',
	'About 2 hours',
	'About 3 hours',
	'About 4 hours',
	'About 5 hours',
	'About 6 hours',
	'About 7 hours',
	'About 8 hours',
	'About 9 hours',
	'About 10 hours',
	'About 11 hours',
	'About 12 hours',
	'About 13 hours',
	'About 14 hours',
	'About 15 hours',
	'About 16 hours',
	'About 17 hours',
	'About 18 hours',
	'About 19 hours',
	'About 20 hours',
	'About 21 hours',
	'About 22 hours',
	'About 23 hours',
	'About 24 hours',
	'About 25 hours',
	'About 26 hours',
	'About 27 hours',
	'About 28 hours',
	'About 29 hours',
	'About 30 hours',
	'About 31 hours',
	'About 32 hours',
	'About 33 hours',
	'About 34 hours',
	'About 35 hours',
	'About 36 hours',
	'About 37 hours',
	'About 38 hours',
	'About 39 hours',
	'About 40 hours',
	'About 41 hours',
	'About 42 hours',
	'About 43 hours',
	'About 44 hours',
	'About 45 hours',
	'About 46 hours',
	'About 47 hours',
	'About 48 hours',
]

fn read_battery(force bool) int {
	return battery_get(force)
}

fn battery_percentage_text(percent int) string {
	if percent < 0 || percent > 100 {
		return '--%'
	}
	return battery_percentage_labels[percent]
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

fn battery_remaining_text(estimate int) string {
	return match estimate {
		battery_estimate_unavailable { 'Unavailable' }
		battery_estimate_calculating { 'Calculating…' }
		battery_estimate_charging { 'Charging' }
		battery_estimate_full { 'Fully charged' }
		else {
			if estimate >= 0 && estimate < battery_remaining_labels.len {
				battery_remaining_labels[estimate]
			} else {
				'Calculating…'
			}
		}
	}
}

fn battery_graph_y(percent int, height int) int {
	return 2 + (100 - percent) * (height - 4) / 100
}

fn battery_graph_x(at_ms u64, end_ms u64, width int) int {
	if width <= 1 || at_ms > end_ms {
		return -1
	}
	age_ms := end_ms - at_ms
	if age_ms > battery_history_window_ms {
		return -1
	}
	return int((battery_history_window_ms - age_ms) * u64(width - 1) / battery_history_window_ms)
}

// A 24-hour step graph mirrors what the integer-only battery device actually
// knows: horizontal segments between observed percentage changes. It does not
// invent intermediate precision or turn gaps into zero charge.
fn battery_graph(history &BatteryHistory, x int, y int, width int, height int) ui2.Element {
	mut lines := frame_elements(battery_history_capacity * 2 + 8)
	for quarter in 1 .. 4 {
		grid_y := quarter * height / 4
		lines << ui2.view('', ui2.rect(0, f64(grid_y), f64(width), 1), ui2.BoxStyle{
			bg: battery_graph_rule
		}, [])
	}
	for quarter in 1 .. 4 {
		grid_x := quarter * width / 4
		lines << ui2.view('', ui2.rect(f64(grid_x), 0, 1, f64(height)), ui2.BoxStyle{
			bg: battery_graph_rule
		}, [])
	}

	if history.initialized && history.count > 0 {
		end_ms := history.observed_ms
		mut previous_percent := -1
		mut previous_x := 0
		for index in 0 .. history.count {
			sample := history.sample(index)
			sample_x := battery_graph_x(sample.at_ms, end_ms, width)
			if sample_x < 0 && sample.at_ms <= end_ms {
				previous_percent = sample.percent
				previous_x = 0
				continue
			}
			if sample_x < 0 {
				continue
			}
			if previous_percent < 0 {
				previous_percent = sample.percent
				previous_x = sample_x
				continue
			}
			if !sample.connected {
				previous_percent = sample.percent
				previous_x = sample_x
				continue
			}
			previous_y := battery_graph_y(previous_percent, height)
			segment_width := if sample_x > previous_x { sample_x - previous_x + 1 } else { 2 }
			lines << ui2.view('', ui2.rect(f64(previous_x), f64(previous_y), f64(segment_width), 2), ui2.BoxStyle{ bg: battery_level }, [])
			if sample.percent != previous_percent {
				sample_y := battery_graph_y(sample.percent, height)
				top := if sample_y < previous_y { sample_y } else { previous_y }
				bottom := if sample_y > previous_y { sample_y } else { previous_y }
				lines << ui2.view('', ui2.rect(f64(sample_x), f64(top), 2, f64(bottom - top + 2)), ui2.BoxStyle{ bg: battery_level }, [])
			}
			previous_percent = sample.percent
			previous_x = sample_x
		}
		if previous_percent >= 0 {
			line_end_ms := if history.contiguous { end_ms } else { history.last_valid_ms }
			line_end_x := battery_graph_x(line_end_ms, end_ms, width)
			if line_end_x >= 0 {
				previous_y := battery_graph_y(previous_percent, height)
				segment_width := if line_end_x > previous_x {
					line_end_x - previous_x + 1
				} else {
					2
				}
				lines << ui2.view('', ui2.rect(f64(previous_x), f64(previous_y), f64(segment_width), 2), ui2.BoxStyle{ bg: battery_level }, [])
				if history.contiguous {
					lines << ui2.view('settings.battery.graph.current', ui2.rect(f64(width - 5), f64(previous_y - 2), 6, 6), ui2.BoxStyle{
						bg: battery_level
						radius: 3
					}, [])
				}
			}
		}
	}
	return ui2.view('settings.battery.graph', ui2.rect(f64(x), f64(y), f64(width), f64(height)), ui2.BoxStyle{
		bg: body_panel
		radius: 6
	}, lines)
}

fn battery_settings_elements(percent int, history &BatteryHistory, x int, inner int) []ui2.Element {
	available := percent >= 0 && percent <= 100
	estimate := history.remaining_hours(percent)
	stat_width := (inner - 16) / 2
	mut children := frame_elements(16)
	children << ui2.label('settings.battery.title', 'Battery', ui2.rect(f64(x), 16, f64(inner), 28), ui2.TextStyle{ color: body_heading, size: 20, bold: true })
	children << settings_label('Built-in battery', x, 46, inner, body_muted)
	children << ui2.view('', ui2.rect(f64(x), 76, f64(inner), 1), ui2.BoxStyle{
		bg: body_rule
	}, [])
	children << settings_label('Current charge', x, 88, stat_width, body_heading)
	children << ui2.label('settings.battery.percent', if available {
		battery_percentage_text(percent)
	} else {
		'Unavailable'
	}, ui2.rect(f64(x), 108, f64(stat_width), 34), ui2.TextStyle{
		color: if available { body_heading } else { body_muted }
		size: 28
		bold: true
	})
	children << settings_label('Estimated remaining', x + stat_width + 16, 88, stat_width, body_heading)
	children << ui2.label('settings.battery.estimate', battery_remaining_text(estimate), ui2.rect(f64(x + stat_width + 16), 110, f64(stat_width), 30), ui2.TextStyle{
		color: if estimate == battery_estimate_unavailable { body_muted } else { body_heading }
		size: 19
		bold: true
	})
	children << ui2.view('settings.battery.track', ui2.rect(f64(x), 148, f64(inner), 10), ui2.BoxStyle{ bg: body_rule, radius: 4 }, [])
	children << settings_label(battery_status_text(percent), x, 164, inner, if available {
		body_muted
	} else {
		files_error
	})
	children << settings_label('Battery level — last 24 hours', x, 190, inner, body_heading)
	children << battery_graph(history, x, 214, inner, 76)
	children << settings_label('24 hours ago', x, 294, inner / 2, body_muted)
	children << ui2.label('', 'Now', ui2.rect(f64(x + inner / 2), 294, f64(inner / 2), 16), ui2.TextStyle{ color: body_muted, size: 11, align: .right })
	children << settings_button('settings.refresh', 'Refresh', ui2.rect(f64(x), 326, 80, 30), true)
	if available && percent > 0 {
		children << ui2.view('settings.battery.fill', ui2.rect(f64(x), 148, f64(inner * percent / 100), 10), ui2.BoxStyle{ bg: battery_level, radius: 4 }, [])
	}
	if percent == battery_unavailable {
		children << settings_label('Check apple-smc boot diagnostics.', x + 96, 333, inner - 96, body_muted)
	} else {
		children << settings_label('Read-only · /dev/battery · updates every 5 seconds.', x + 96, 333, inner - 96, body_muted)
	}
	return children
}
