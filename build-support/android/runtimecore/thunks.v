// SPDX-License-Identifier: GPL-2.0-or-later
// Stable native function addresses for the original fixed 128-slot registry.
@[translated]
module runtimecore

$if arm64 {
    fn prepare_0() { fork_prepare(0) }
    fn parent_0() { fork_finish(0, false) }
    fn child_0() { fork_finish(0, true) }
    fn prepare_1() { fork_prepare(1) }
    fn parent_1() { fork_finish(1, false) }
    fn child_1() { fork_finish(1, true) }
    fn prepare_2() { fork_prepare(2) }
    fn parent_2() { fork_finish(2, false) }
    fn child_2() { fork_finish(2, true) }
    fn prepare_3() { fork_prepare(3) }
    fn parent_3() { fork_finish(3, false) }
    fn child_3() { fork_finish(3, true) }
    fn prepare_4() { fork_prepare(4) }
    fn parent_4() { fork_finish(4, false) }
    fn child_4() { fork_finish(4, true) }
    fn prepare_5() { fork_prepare(5) }
    fn parent_5() { fork_finish(5, false) }
    fn child_5() { fork_finish(5, true) }
    fn prepare_6() { fork_prepare(6) }
    fn parent_6() { fork_finish(6, false) }
    fn child_6() { fork_finish(6, true) }
    fn prepare_7() { fork_prepare(7) }
    fn parent_7() { fork_finish(7, false) }
    fn child_7() { fork_finish(7, true) }
    fn prepare_8() { fork_prepare(8) }
    fn parent_8() { fork_finish(8, false) }
    fn child_8() { fork_finish(8, true) }
    fn prepare_9() { fork_prepare(9) }
    fn parent_9() { fork_finish(9, false) }
    fn child_9() { fork_finish(9, true) }
    fn prepare_10() { fork_prepare(10) }
    fn parent_10() { fork_finish(10, false) }
    fn child_10() { fork_finish(10, true) }
    fn prepare_11() { fork_prepare(11) }
    fn parent_11() { fork_finish(11, false) }
    fn child_11() { fork_finish(11, true) }
    fn prepare_12() { fork_prepare(12) }
    fn parent_12() { fork_finish(12, false) }
    fn child_12() { fork_finish(12, true) }
    fn prepare_13() { fork_prepare(13) }
    fn parent_13() { fork_finish(13, false) }
    fn child_13() { fork_finish(13, true) }
    fn prepare_14() { fork_prepare(14) }
    fn parent_14() { fork_finish(14, false) }
    fn child_14() { fork_finish(14, true) }
    fn prepare_15() { fork_prepare(15) }
    fn parent_15() { fork_finish(15, false) }
    fn child_15() { fork_finish(15, true) }
    fn prepare_16() { fork_prepare(16) }
    fn parent_16() { fork_finish(16, false) }
    fn child_16() { fork_finish(16, true) }
    fn prepare_17() { fork_prepare(17) }
    fn parent_17() { fork_finish(17, false) }
    fn child_17() { fork_finish(17, true) }
    fn prepare_18() { fork_prepare(18) }
    fn parent_18() { fork_finish(18, false) }
    fn child_18() { fork_finish(18, true) }
    fn prepare_19() { fork_prepare(19) }
    fn parent_19() { fork_finish(19, false) }
    fn child_19() { fork_finish(19, true) }
    fn prepare_20() { fork_prepare(20) }
    fn parent_20() { fork_finish(20, false) }
    fn child_20() { fork_finish(20, true) }
    fn prepare_21() { fork_prepare(21) }
    fn parent_21() { fork_finish(21, false) }
    fn child_21() { fork_finish(21, true) }
    fn prepare_22() { fork_prepare(22) }
    fn parent_22() { fork_finish(22, false) }
    fn child_22() { fork_finish(22, true) }
    fn prepare_23() { fork_prepare(23) }
    fn parent_23() { fork_finish(23, false) }
    fn child_23() { fork_finish(23, true) }
    fn prepare_24() { fork_prepare(24) }
    fn parent_24() { fork_finish(24, false) }
    fn child_24() { fork_finish(24, true) }
    fn prepare_25() { fork_prepare(25) }
    fn parent_25() { fork_finish(25, false) }
    fn child_25() { fork_finish(25, true) }
    fn prepare_26() { fork_prepare(26) }
    fn parent_26() { fork_finish(26, false) }
    fn child_26() { fork_finish(26, true) }
    fn prepare_27() { fork_prepare(27) }
    fn parent_27() { fork_finish(27, false) }
    fn child_27() { fork_finish(27, true) }
    fn prepare_28() { fork_prepare(28) }
    fn parent_28() { fork_finish(28, false) }
    fn child_28() { fork_finish(28, true) }
    fn prepare_29() { fork_prepare(29) }
    fn parent_29() { fork_finish(29, false) }
    fn child_29() { fork_finish(29, true) }
    fn prepare_30() { fork_prepare(30) }
    fn parent_30() { fork_finish(30, false) }
    fn child_30() { fork_finish(30, true) }
    fn prepare_31() { fork_prepare(31) }
    fn parent_31() { fork_finish(31, false) }
    fn child_31() { fork_finish(31, true) }
    fn prepare_32() { fork_prepare(32) }
    fn parent_32() { fork_finish(32, false) }
    fn child_32() { fork_finish(32, true) }
    fn prepare_33() { fork_prepare(33) }
    fn parent_33() { fork_finish(33, false) }
    fn child_33() { fork_finish(33, true) }
    fn prepare_34() { fork_prepare(34) }
    fn parent_34() { fork_finish(34, false) }
    fn child_34() { fork_finish(34, true) }
    fn prepare_35() { fork_prepare(35) }
    fn parent_35() { fork_finish(35, false) }
    fn child_35() { fork_finish(35, true) }
    fn prepare_36() { fork_prepare(36) }
    fn parent_36() { fork_finish(36, false) }
    fn child_36() { fork_finish(36, true) }
    fn prepare_37() { fork_prepare(37) }
    fn parent_37() { fork_finish(37, false) }
    fn child_37() { fork_finish(37, true) }
    fn prepare_38() { fork_prepare(38) }
    fn parent_38() { fork_finish(38, false) }
    fn child_38() { fork_finish(38, true) }
    fn prepare_39() { fork_prepare(39) }
    fn parent_39() { fork_finish(39, false) }
    fn child_39() { fork_finish(39, true) }
    fn prepare_40() { fork_prepare(40) }
    fn parent_40() { fork_finish(40, false) }
    fn child_40() { fork_finish(40, true) }
    fn prepare_41() { fork_prepare(41) }
    fn parent_41() { fork_finish(41, false) }
    fn child_41() { fork_finish(41, true) }
    fn prepare_42() { fork_prepare(42) }
    fn parent_42() { fork_finish(42, false) }
    fn child_42() { fork_finish(42, true) }
    fn prepare_43() { fork_prepare(43) }
    fn parent_43() { fork_finish(43, false) }
    fn child_43() { fork_finish(43, true) }
    fn prepare_44() { fork_prepare(44) }
    fn parent_44() { fork_finish(44, false) }
    fn child_44() { fork_finish(44, true) }
    fn prepare_45() { fork_prepare(45) }
    fn parent_45() { fork_finish(45, false) }
    fn child_45() { fork_finish(45, true) }
    fn prepare_46() { fork_prepare(46) }
    fn parent_46() { fork_finish(46, false) }
    fn child_46() { fork_finish(46, true) }
    fn prepare_47() { fork_prepare(47) }
    fn parent_47() { fork_finish(47, false) }
    fn child_47() { fork_finish(47, true) }
    fn prepare_48() { fork_prepare(48) }
    fn parent_48() { fork_finish(48, false) }
    fn child_48() { fork_finish(48, true) }
    fn prepare_49() { fork_prepare(49) }
    fn parent_49() { fork_finish(49, false) }
    fn child_49() { fork_finish(49, true) }
    fn prepare_50() { fork_prepare(50) }
    fn parent_50() { fork_finish(50, false) }
    fn child_50() { fork_finish(50, true) }
    fn prepare_51() { fork_prepare(51) }
    fn parent_51() { fork_finish(51, false) }
    fn child_51() { fork_finish(51, true) }
    fn prepare_52() { fork_prepare(52) }
    fn parent_52() { fork_finish(52, false) }
    fn child_52() { fork_finish(52, true) }
    fn prepare_53() { fork_prepare(53) }
    fn parent_53() { fork_finish(53, false) }
    fn child_53() { fork_finish(53, true) }
    fn prepare_54() { fork_prepare(54) }
    fn parent_54() { fork_finish(54, false) }
    fn child_54() { fork_finish(54, true) }
    fn prepare_55() { fork_prepare(55) }
    fn parent_55() { fork_finish(55, false) }
    fn child_55() { fork_finish(55, true) }
    fn prepare_56() { fork_prepare(56) }
    fn parent_56() { fork_finish(56, false) }
    fn child_56() { fork_finish(56, true) }
    fn prepare_57() { fork_prepare(57) }
    fn parent_57() { fork_finish(57, false) }
    fn child_57() { fork_finish(57, true) }
    fn prepare_58() { fork_prepare(58) }
    fn parent_58() { fork_finish(58, false) }
    fn child_58() { fork_finish(58, true) }
    fn prepare_59() { fork_prepare(59) }
    fn parent_59() { fork_finish(59, false) }
    fn child_59() { fork_finish(59, true) }
    fn prepare_60() { fork_prepare(60) }
    fn parent_60() { fork_finish(60, false) }
    fn child_60() { fork_finish(60, true) }
    fn prepare_61() { fork_prepare(61) }
    fn parent_61() { fork_finish(61, false) }
    fn child_61() { fork_finish(61, true) }
    fn prepare_62() { fork_prepare(62) }
    fn parent_62() { fork_finish(62, false) }
    fn child_62() { fork_finish(62, true) }
    fn prepare_63() { fork_prepare(63) }
    fn parent_63() { fork_finish(63, false) }
    fn child_63() { fork_finish(63, true) }
    fn prepare_64() { fork_prepare(64) }
    fn parent_64() { fork_finish(64, false) }
    fn child_64() { fork_finish(64, true) }
    fn prepare_65() { fork_prepare(65) }
    fn parent_65() { fork_finish(65, false) }
    fn child_65() { fork_finish(65, true) }
    fn prepare_66() { fork_prepare(66) }
    fn parent_66() { fork_finish(66, false) }
    fn child_66() { fork_finish(66, true) }
    fn prepare_67() { fork_prepare(67) }
    fn parent_67() { fork_finish(67, false) }
    fn child_67() { fork_finish(67, true) }
    fn prepare_68() { fork_prepare(68) }
    fn parent_68() { fork_finish(68, false) }
    fn child_68() { fork_finish(68, true) }
    fn prepare_69() { fork_prepare(69) }
    fn parent_69() { fork_finish(69, false) }
    fn child_69() { fork_finish(69, true) }
    fn prepare_70() { fork_prepare(70) }
    fn parent_70() { fork_finish(70, false) }
    fn child_70() { fork_finish(70, true) }
    fn prepare_71() { fork_prepare(71) }
    fn parent_71() { fork_finish(71, false) }
    fn child_71() { fork_finish(71, true) }
    fn prepare_72() { fork_prepare(72) }
    fn parent_72() { fork_finish(72, false) }
    fn child_72() { fork_finish(72, true) }
    fn prepare_73() { fork_prepare(73) }
    fn parent_73() { fork_finish(73, false) }
    fn child_73() { fork_finish(73, true) }
    fn prepare_74() { fork_prepare(74) }
    fn parent_74() { fork_finish(74, false) }
    fn child_74() { fork_finish(74, true) }
    fn prepare_75() { fork_prepare(75) }
    fn parent_75() { fork_finish(75, false) }
    fn child_75() { fork_finish(75, true) }
    fn prepare_76() { fork_prepare(76) }
    fn parent_76() { fork_finish(76, false) }
    fn child_76() { fork_finish(76, true) }
    fn prepare_77() { fork_prepare(77) }
    fn parent_77() { fork_finish(77, false) }
    fn child_77() { fork_finish(77, true) }
    fn prepare_78() { fork_prepare(78) }
    fn parent_78() { fork_finish(78, false) }
    fn child_78() { fork_finish(78, true) }
    fn prepare_79() { fork_prepare(79) }
    fn parent_79() { fork_finish(79, false) }
    fn child_79() { fork_finish(79, true) }
    fn prepare_80() { fork_prepare(80) }
    fn parent_80() { fork_finish(80, false) }
    fn child_80() { fork_finish(80, true) }
    fn prepare_81() { fork_prepare(81) }
    fn parent_81() { fork_finish(81, false) }
    fn child_81() { fork_finish(81, true) }
    fn prepare_82() { fork_prepare(82) }
    fn parent_82() { fork_finish(82, false) }
    fn child_82() { fork_finish(82, true) }
    fn prepare_83() { fork_prepare(83) }
    fn parent_83() { fork_finish(83, false) }
    fn child_83() { fork_finish(83, true) }
    fn prepare_84() { fork_prepare(84) }
    fn parent_84() { fork_finish(84, false) }
    fn child_84() { fork_finish(84, true) }
    fn prepare_85() { fork_prepare(85) }
    fn parent_85() { fork_finish(85, false) }
    fn child_85() { fork_finish(85, true) }
    fn prepare_86() { fork_prepare(86) }
    fn parent_86() { fork_finish(86, false) }
    fn child_86() { fork_finish(86, true) }
    fn prepare_87() { fork_prepare(87) }
    fn parent_87() { fork_finish(87, false) }
    fn child_87() { fork_finish(87, true) }
    fn prepare_88() { fork_prepare(88) }
    fn parent_88() { fork_finish(88, false) }
    fn child_88() { fork_finish(88, true) }
    fn prepare_89() { fork_prepare(89) }
    fn parent_89() { fork_finish(89, false) }
    fn child_89() { fork_finish(89, true) }
    fn prepare_90() { fork_prepare(90) }
    fn parent_90() { fork_finish(90, false) }
    fn child_90() { fork_finish(90, true) }
    fn prepare_91() { fork_prepare(91) }
    fn parent_91() { fork_finish(91, false) }
    fn child_91() { fork_finish(91, true) }
    fn prepare_92() { fork_prepare(92) }
    fn parent_92() { fork_finish(92, false) }
    fn child_92() { fork_finish(92, true) }
    fn prepare_93() { fork_prepare(93) }
    fn parent_93() { fork_finish(93, false) }
    fn child_93() { fork_finish(93, true) }
    fn prepare_94() { fork_prepare(94) }
    fn parent_94() { fork_finish(94, false) }
    fn child_94() { fork_finish(94, true) }
    fn prepare_95() { fork_prepare(95) }
    fn parent_95() { fork_finish(95, false) }
    fn child_95() { fork_finish(95, true) }
    fn prepare_96() { fork_prepare(96) }
    fn parent_96() { fork_finish(96, false) }
    fn child_96() { fork_finish(96, true) }
    fn prepare_97() { fork_prepare(97) }
    fn parent_97() { fork_finish(97, false) }
    fn child_97() { fork_finish(97, true) }
    fn prepare_98() { fork_prepare(98) }
    fn parent_98() { fork_finish(98, false) }
    fn child_98() { fork_finish(98, true) }
    fn prepare_99() { fork_prepare(99) }
    fn parent_99() { fork_finish(99, false) }
    fn child_99() { fork_finish(99, true) }
    fn prepare_100() { fork_prepare(100) }
    fn parent_100() { fork_finish(100, false) }
    fn child_100() { fork_finish(100, true) }
    fn prepare_101() { fork_prepare(101) }
    fn parent_101() { fork_finish(101, false) }
    fn child_101() { fork_finish(101, true) }
    fn prepare_102() { fork_prepare(102) }
    fn parent_102() { fork_finish(102, false) }
    fn child_102() { fork_finish(102, true) }
    fn prepare_103() { fork_prepare(103) }
    fn parent_103() { fork_finish(103, false) }
    fn child_103() { fork_finish(103, true) }
    fn prepare_104() { fork_prepare(104) }
    fn parent_104() { fork_finish(104, false) }
    fn child_104() { fork_finish(104, true) }
    fn prepare_105() { fork_prepare(105) }
    fn parent_105() { fork_finish(105, false) }
    fn child_105() { fork_finish(105, true) }
    fn prepare_106() { fork_prepare(106) }
    fn parent_106() { fork_finish(106, false) }
    fn child_106() { fork_finish(106, true) }
    fn prepare_107() { fork_prepare(107) }
    fn parent_107() { fork_finish(107, false) }
    fn child_107() { fork_finish(107, true) }
    fn prepare_108() { fork_prepare(108) }
    fn parent_108() { fork_finish(108, false) }
    fn child_108() { fork_finish(108, true) }
    fn prepare_109() { fork_prepare(109) }
    fn parent_109() { fork_finish(109, false) }
    fn child_109() { fork_finish(109, true) }
    fn prepare_110() { fork_prepare(110) }
    fn parent_110() { fork_finish(110, false) }
    fn child_110() { fork_finish(110, true) }
    fn prepare_111() { fork_prepare(111) }
    fn parent_111() { fork_finish(111, false) }
    fn child_111() { fork_finish(111, true) }
    fn prepare_112() { fork_prepare(112) }
    fn parent_112() { fork_finish(112, false) }
    fn child_112() { fork_finish(112, true) }
    fn prepare_113() { fork_prepare(113) }
    fn parent_113() { fork_finish(113, false) }
    fn child_113() { fork_finish(113, true) }
    fn prepare_114() { fork_prepare(114) }
    fn parent_114() { fork_finish(114, false) }
    fn child_114() { fork_finish(114, true) }
    fn prepare_115() { fork_prepare(115) }
    fn parent_115() { fork_finish(115, false) }
    fn child_115() { fork_finish(115, true) }
    fn prepare_116() { fork_prepare(116) }
    fn parent_116() { fork_finish(116, false) }
    fn child_116() { fork_finish(116, true) }
    fn prepare_117() { fork_prepare(117) }
    fn parent_117() { fork_finish(117, false) }
    fn child_117() { fork_finish(117, true) }
    fn prepare_118() { fork_prepare(118) }
    fn parent_118() { fork_finish(118, false) }
    fn child_118() { fork_finish(118, true) }
    fn prepare_119() { fork_prepare(119) }
    fn parent_119() { fork_finish(119, false) }
    fn child_119() { fork_finish(119, true) }
    fn prepare_120() { fork_prepare(120) }
    fn parent_120() { fork_finish(120, false) }
    fn child_120() { fork_finish(120, true) }
    fn prepare_121() { fork_prepare(121) }
    fn parent_121() { fork_finish(121, false) }
    fn child_121() { fork_finish(121, true) }
    fn prepare_122() { fork_prepare(122) }
    fn parent_122() { fork_finish(122, false) }
    fn child_122() { fork_finish(122, true) }
    fn prepare_123() { fork_prepare(123) }
    fn parent_123() { fork_finish(123, false) }
    fn child_123() { fork_finish(123, true) }
    fn prepare_124() { fork_prepare(124) }
    fn parent_124() { fork_finish(124, false) }
    fn child_124() { fork_finish(124, true) }
    fn prepare_125() { fork_prepare(125) }
    fn parent_125() { fork_finish(125, false) }
    fn child_125() { fork_finish(125, true) }
    fn prepare_126() { fork_prepare(126) }
    fn parent_126() { fork_finish(126, false) }
    fn child_126() { fork_finish(126, true) }
    fn prepare_127() { fork_prepare(127) }
    fn parent_127() { fork_finish(127, false) }
    fn child_127() { fork_finish(127, true) }

    const fork_thunks = [
        ForkThunks{prepare_0, parent_0, child_0},
        ForkThunks{prepare_1, parent_1, child_1},
        ForkThunks{prepare_2, parent_2, child_2},
        ForkThunks{prepare_3, parent_3, child_3},
        ForkThunks{prepare_4, parent_4, child_4},
        ForkThunks{prepare_5, parent_5, child_5},
        ForkThunks{prepare_6, parent_6, child_6},
        ForkThunks{prepare_7, parent_7, child_7},
        ForkThunks{prepare_8, parent_8, child_8},
        ForkThunks{prepare_9, parent_9, child_9},
        ForkThunks{prepare_10, parent_10, child_10},
        ForkThunks{prepare_11, parent_11, child_11},
        ForkThunks{prepare_12, parent_12, child_12},
        ForkThunks{prepare_13, parent_13, child_13},
        ForkThunks{prepare_14, parent_14, child_14},
        ForkThunks{prepare_15, parent_15, child_15},
        ForkThunks{prepare_16, parent_16, child_16},
        ForkThunks{prepare_17, parent_17, child_17},
        ForkThunks{prepare_18, parent_18, child_18},
        ForkThunks{prepare_19, parent_19, child_19},
        ForkThunks{prepare_20, parent_20, child_20},
        ForkThunks{prepare_21, parent_21, child_21},
        ForkThunks{prepare_22, parent_22, child_22},
        ForkThunks{prepare_23, parent_23, child_23},
        ForkThunks{prepare_24, parent_24, child_24},
        ForkThunks{prepare_25, parent_25, child_25},
        ForkThunks{prepare_26, parent_26, child_26},
        ForkThunks{prepare_27, parent_27, child_27},
        ForkThunks{prepare_28, parent_28, child_28},
        ForkThunks{prepare_29, parent_29, child_29},
        ForkThunks{prepare_30, parent_30, child_30},
        ForkThunks{prepare_31, parent_31, child_31},
        ForkThunks{prepare_32, parent_32, child_32},
        ForkThunks{prepare_33, parent_33, child_33},
        ForkThunks{prepare_34, parent_34, child_34},
        ForkThunks{prepare_35, parent_35, child_35},
        ForkThunks{prepare_36, parent_36, child_36},
        ForkThunks{prepare_37, parent_37, child_37},
        ForkThunks{prepare_38, parent_38, child_38},
        ForkThunks{prepare_39, parent_39, child_39},
        ForkThunks{prepare_40, parent_40, child_40},
        ForkThunks{prepare_41, parent_41, child_41},
        ForkThunks{prepare_42, parent_42, child_42},
        ForkThunks{prepare_43, parent_43, child_43},
        ForkThunks{prepare_44, parent_44, child_44},
        ForkThunks{prepare_45, parent_45, child_45},
        ForkThunks{prepare_46, parent_46, child_46},
        ForkThunks{prepare_47, parent_47, child_47},
        ForkThunks{prepare_48, parent_48, child_48},
        ForkThunks{prepare_49, parent_49, child_49},
        ForkThunks{prepare_50, parent_50, child_50},
        ForkThunks{prepare_51, parent_51, child_51},
        ForkThunks{prepare_52, parent_52, child_52},
        ForkThunks{prepare_53, parent_53, child_53},
        ForkThunks{prepare_54, parent_54, child_54},
        ForkThunks{prepare_55, parent_55, child_55},
        ForkThunks{prepare_56, parent_56, child_56},
        ForkThunks{prepare_57, parent_57, child_57},
        ForkThunks{prepare_58, parent_58, child_58},
        ForkThunks{prepare_59, parent_59, child_59},
        ForkThunks{prepare_60, parent_60, child_60},
        ForkThunks{prepare_61, parent_61, child_61},
        ForkThunks{prepare_62, parent_62, child_62},
        ForkThunks{prepare_63, parent_63, child_63},
        ForkThunks{prepare_64, parent_64, child_64},
        ForkThunks{prepare_65, parent_65, child_65},
        ForkThunks{prepare_66, parent_66, child_66},
        ForkThunks{prepare_67, parent_67, child_67},
        ForkThunks{prepare_68, parent_68, child_68},
        ForkThunks{prepare_69, parent_69, child_69},
        ForkThunks{prepare_70, parent_70, child_70},
        ForkThunks{prepare_71, parent_71, child_71},
        ForkThunks{prepare_72, parent_72, child_72},
        ForkThunks{prepare_73, parent_73, child_73},
        ForkThunks{prepare_74, parent_74, child_74},
        ForkThunks{prepare_75, parent_75, child_75},
        ForkThunks{prepare_76, parent_76, child_76},
        ForkThunks{prepare_77, parent_77, child_77},
        ForkThunks{prepare_78, parent_78, child_78},
        ForkThunks{prepare_79, parent_79, child_79},
        ForkThunks{prepare_80, parent_80, child_80},
        ForkThunks{prepare_81, parent_81, child_81},
        ForkThunks{prepare_82, parent_82, child_82},
        ForkThunks{prepare_83, parent_83, child_83},
        ForkThunks{prepare_84, parent_84, child_84},
        ForkThunks{prepare_85, parent_85, child_85},
        ForkThunks{prepare_86, parent_86, child_86},
        ForkThunks{prepare_87, parent_87, child_87},
        ForkThunks{prepare_88, parent_88, child_88},
        ForkThunks{prepare_89, parent_89, child_89},
        ForkThunks{prepare_90, parent_90, child_90},
        ForkThunks{prepare_91, parent_91, child_91},
        ForkThunks{prepare_92, parent_92, child_92},
        ForkThunks{prepare_93, parent_93, child_93},
        ForkThunks{prepare_94, parent_94, child_94},
        ForkThunks{prepare_95, parent_95, child_95},
        ForkThunks{prepare_96, parent_96, child_96},
        ForkThunks{prepare_97, parent_97, child_97},
        ForkThunks{prepare_98, parent_98, child_98},
        ForkThunks{prepare_99, parent_99, child_99},
        ForkThunks{prepare_100, parent_100, child_100},
        ForkThunks{prepare_101, parent_101, child_101},
        ForkThunks{prepare_102, parent_102, child_102},
        ForkThunks{prepare_103, parent_103, child_103},
        ForkThunks{prepare_104, parent_104, child_104},
        ForkThunks{prepare_105, parent_105, child_105},
        ForkThunks{prepare_106, parent_106, child_106},
        ForkThunks{prepare_107, parent_107, child_107},
        ForkThunks{prepare_108, parent_108, child_108},
        ForkThunks{prepare_109, parent_109, child_109},
        ForkThunks{prepare_110, parent_110, child_110},
        ForkThunks{prepare_111, parent_111, child_111},
        ForkThunks{prepare_112, parent_112, child_112},
        ForkThunks{prepare_113, parent_113, child_113},
        ForkThunks{prepare_114, parent_114, child_114},
        ForkThunks{prepare_115, parent_115, child_115},
        ForkThunks{prepare_116, parent_116, child_116},
        ForkThunks{prepare_117, parent_117, child_117},
        ForkThunks{prepare_118, parent_118, child_118},
        ForkThunks{prepare_119, parent_119, child_119},
        ForkThunks{prepare_120, parent_120, child_120},
        ForkThunks{prepare_121, parent_121, child_121},
        ForkThunks{prepare_122, parent_122, child_122},
        ForkThunks{prepare_123, parent_123, child_123},
        ForkThunks{prepare_124, parent_124, child_124},
        ForkThunks{prepare_125, parent_125, child_125},
        ForkThunks{prepare_126, parent_126, child_126},
        ForkThunks{prepare_127, parent_127, child_127},
    ]!
}
