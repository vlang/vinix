// Copyright (c) 2026 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL v2 license
// that can be found in the LICENSE file.

// SPDX-License-Identifier: GPL-2.0-or-later
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

// The "About N hours" estimates, made once per language for each hour shown:
// the pane is rebuilt every frame, and its estimate is text the renderer does
// not free. Hour 0 is "Less than 1 hour", which needs no filling.
struct BatteryHourLabels {
mut:
	language DesktopLanguage
	labels   [battery_estimate_maximum_hours + 1]string
}

__global battery_hour_labels = BatteryHourLabels{}

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
		return tr('battery.status.reported')
	}
	return match percent {
		battery_unavailable { tr('battery.status.unavailable') }
		battery_permission { tr('battery.status.permission') }
		battery_invalid { tr('battery.status.invalid') }
		else { tr('battery.status.failed') }
	}
}

fn battery_remaining_text(estimate int) string {
	return match estimate {
		battery_estimate_unavailable { tr('battery.remaining.unavailable') }
		battery_estimate_calculating { tr('battery.remaining.calculating') }
		battery_estimate_charging { tr('battery.remaining.charging') }
		battery_estimate_full { tr('battery.remaining.full') }
		else {
			if estimate == 0 {
				tr('battery.remaining.less_than_hour')
			} else if estimate > 0 && estimate < battery_hour_labels.labels.len {
				battery_hours_text(estimate)
			} else {
				tr('battery.remaining.calculating')
			}
		}
	}
}

// battery_hours_text is the estimate for hours, from the labels made in the
// desktop's language. A change of language releases those made in the last.
fn battery_hours_text(hours int) string {
	if battery_hour_labels.language != desktop_language {
		for i in 0 .. battery_hour_labels.labels.len {
			if battery_hour_labels.labels[i].len > 0 {
				unsafe { battery_hour_labels.labels[i].free() }
				battery_hour_labels.labels[i] = ''
			}
		}
		battery_hour_labels.language = desktop_language
	}
	if battery_hour_labels.labels[hours].len == 0 {
		battery_hour_labels.labels[hours] = tr_count('battery.remaining.about_hours', hours)
	}
	return battery_hour_labels.labels[hours]
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
	children << ui2.label('settings.battery.title', tr('settings.category.battery'), ui2.rect(f64(x), 16, f64(inner), 28), ui2.TextStyle{ color: body_heading, size: 20, bold: true })
	children << settings_label(tr('settings.battery.built_in'), x, 46, inner, body_muted)
	children << ui2.view('', ui2.rect(f64(x), 76, f64(inner), 1), ui2.BoxStyle{
		bg: body_rule
	}, [])
	children << settings_label(tr('settings.battery.current_charge'), x, 88, stat_width, body_heading)
	children << ui2.label('settings.battery.percent', if available {
		battery_percentage_text(percent)
	} else {
		tr('settings.battery.unavailable')
	}, ui2.rect(f64(x), 108, f64(stat_width), 34), ui2.TextStyle{
		color: if available { body_heading } else { body_muted }
		size: 28
		bold: true
	})
	children << settings_label(tr('settings.battery.estimated_remaining'), x + stat_width + 16, 88, stat_width, body_heading)
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
	children << settings_label(tr('settings.battery.history'), x, 190, inner, body_heading)
	children << battery_graph(history, x, 214, inner, 76)
	children << settings_label(tr('settings.battery.day_ago'), x, 294, inner / 2, body_muted)
	children << ui2.label('', tr('settings.battery.now'), ui2.rect(f64(x + inner / 2), 294, f64(inner / 2), 16), ui2.TextStyle{ color: body_muted, size: 11, align: .right })
	children << settings_button('settings.refresh', tr('settings.battery.refresh'), ui2.rect(f64(x), 326, 80, 30), true)
	if available && percent > 0 {
		children << ui2.view('settings.battery.fill', ui2.rect(f64(x), 148, f64(inner * percent / 100), 10), ui2.BoxStyle{ bg: battery_level, radius: 4 }, [])
	}
	if percent == battery_unavailable {
		children << settings_label(tr('settings.battery.check_smc'), x + 96, 333, inner - 96, body_muted)
	} else {
		children << settings_label(tr('settings.battery.footer'), x + 96, 333, inner - 96, body_muted)
	}
	return children
}
