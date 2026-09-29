// SPDX-License-Identifier: GPL-2.0-or-later
// Copyright (c) 2026 Alexander Medvednikov
module userland

// Linux's numbers, which every program on either architecture uses.

pub const wnohang = 1

// rt_sigprocmask's `how`.
pub const sig_block = 0

pub const sig_unblock = 1

pub const sig_setmask = 2

pub const sighup = 1

pub const sigint = 2

pub const sigquit = 3

pub const sigill = 4

pub const sigtrap = 5

pub const sigabrt = 6

pub const sigbus = 7

pub const sigfpe = 8

pub const sigkill = 9

pub const sigusr1 = 10

pub const sigsegv = 11

pub const sigusr2 = 12

pub const sigpipe = 13

pub const sigalrm = 14

pub const sigterm = 15

pub const sigstkflt = 16

pub const sigchld = 17

pub const sigcont = 18

pub const sigstop = 19

pub const sigtstp = 20

pub const sigttin = 21

pub const sigttou = 22

pub const sigurg = 23

pub const sigxcpu = 24

pub const sigxfsz = 25

pub const sigvtalrm = 26

pub const sigprof = 27

pub const sigwinch = 28

pub const sigio = 29

pub const sigpoll = sigio

pub const sigpwr = 30

pub const sigsys = 31

pub const sigrtmin = 32

pub const sigrtmax = 33

pub const sigcancel = 34

pub const sig_err = voidptr(-1)

pub const sig_dfl = voidptr(0)

pub const sig_ign = voidptr(1)

// The arm64 handlers test these alongside Linux's own SA_* values, which
// differ; see userland_arm64.v.
pub const sa_nocldstop = 1 << 0

pub const sa_onstack = 1 << 1

pub const sa_resethand = 1 << 2

pub const sa_restart = 1 << 3

pub const sa_siginfo = 1 << 4

pub const sa_nocldwait = 1 << 5

pub const sa_nodefer = 1 << 6
