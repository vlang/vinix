module time

fn test_frequency_and_fraction_survive_small_samples() {
	mut once := ClockDiscipline{ realtime: TimeSpec{100, 0} }
	mut often := once
	assert once.set_frequency(max_clock_frequency)
	assert often.set_frequency(max_clock_frequency)
	once.sample(TimeSpec{1, 0})
	for ns := i64(1000); ns <= 1000000000; ns += 1000 {
		often.sample(TimeSpec{ns / 1000000000, ns % 1000000000})
	}
	assert once.monotonic == TimeSpec{1, 500000}
	assert often.monotonic == once.monotonic
	assert often.realtime == TimeSpec{101, 500000}
	assert !often.set_frequency(max_clock_frequency + 1)
	assert often.frequency == max_clock_frequency
}

fn test_negative_frequency_and_slew_never_move_backwards() {
	mut clock := ClockDiscipline{}
	assert clock.set_frequency(-max_clock_frequency)
	clock.set_slew(-1000000)
	mut previous := clock.monotonic
	for ns := i64(1); ns <= 100000; ns++ {
		clock.sample(TimeSpec{0, ns})
		assert !timespec_before(clock.monotonic, previous)
		previous = clock.monotonic
	}
	clock.sample(TimeSpec{3, 0})
	assert clock.slew_remaining == 0
	assert clock.monotonic.tv_sec >= 2
}

fn test_negative_adjustments_are_independent_of_read_cadence() {
	mut once := ClockDiscipline{}
	mut often := ClockDiscipline{}
	assert once.set_frequency(-max_clock_frequency)
	assert often.set_frequency(-max_clock_frequency)
	once.set_slew(-1000000)
	often.set_slew(-1000000)
	once.sample(TimeSpec{0, 1000000})
	for ns := i64(1); ns <= 1000000; ns++ {
		often.sample(TimeSpec{0, ns})
	}
	assert once.monotonic == TimeSpec{0, 999000}
	assert often.monotonic == once.monotonic
	assert often.slew_remaining == once.slew_remaining
}

fn test_slew_is_bounded_and_can_be_cancelled() {
	mut clock := ClockDiscipline{}
	assert clock.set_slew(1000000) == 0
	clock.sample(TimeSpec{1, 0})
	assert clock.monotonic == TimeSpec{1, 500000}
	assert clock.slew_remaining == 500000
	assert clock.set_slew(0) == 500000
	clock.sample(TimeSpec{2, 0})
	assert clock.monotonic == TimeSpec{2, 500000}
}

fn test_wall_steps_leave_monotonic_and_securelevel_checks_intact() {
	mut clock := ClockDiscipline{ realtime: TimeSpec{100, 0} }
	clock.sample(TimeSpec{1, 0})
	assert !clock.set_realtime(TimeSpec{100, 0}, true)
	assert clock.set_realtime(TimeSpec{200, 0}, true)
	assert clock.monotonic == TimeSpec{1, 0}
	assert clock.set_realtime(TimeSpec{50, 0}, false)
	assert !clock.set_realtime(TimeSpec{-1, 0}, false)
	assert !clock.set_realtime(TimeSpec{50, 1000000000}, false)
	assert clock.monotonic == TimeSpec{1, 0}
	clock.sample(TimeSpec{0, 0})
	assert clock.realtime == TimeSpec{50, 0}
}

fn test_timespec_subtraction_borrows_exactly_one_second() {
	mut value := TimeSpec{1, 1}
	assert !value.sub(TimeSpec{0, 2})
	assert value == TimeSpec{0, 999999999}
}
