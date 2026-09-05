const std = @import("std");
const AutoConfigHeaderStep = @import("autoconfigheader").AutoConfigHeaderStep;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage = b.option(std.builtin.LinkMode, "linkage", "Linkage type for the library") orelse .static;
    const pic = b.option(bool, "pic", "Enable PIC") orelse (if (linkage == .dynamic) true else null);
    const loadable_i18n = b.option(bool, "loadable-i18n", "Controls loadable i18n module support") orelse false;
    const loadable_xcursor = b.option(bool, "loadable-xcursor", "Controls loadable xcursor module support") orelse false;
    const locale_lib_dir = b.option([]const u8, "locale-lib-dir", "Directory where locale libraries files are installed") orelse "/usr/lib/X11/locale";
    const thread_safety_constructor = b.option(bool, "thread-safety-constructor", "Controls mandatory thread safety support") orelse true;
    const launchd = b.option(bool, "launchd", "Build with support for Apple's launchd") orelse target.result.os.tag.isDarwin();
    const xthreads = b.option(bool, "xthreads", "Controls Xlib support for Multithreading") orelse true;
    const xlocaledir = b.option(bool, "xlocaledir", "Controls XLOCALEDIR environment variable support") orelse true;
    const xf86bigfont = b.option(bool, "xf86bigfont", "Controls XF86BigFont extension support") orelse true;
    const composecache = b.option(bool, "composecache", "Controls compose table cache support") orelse true;

    const flags = .{
        "-DHAVE_CONFIG_H",
        "-DXKB",
    };

    const x11_dep = b.dependency("x11", .{});

    const xorgproto_dep = b.dependency("xorgproto", .{
        .target = target,
        .optimize = optimize,
    });
    const xorgproto = xorgproto_dep.artifact("xorgproto");

    const xcb_dep = b.dependency("xcb", .{
        .target = target,
        .optimize = optimize,
        .linkage = linkage,
    });
    const xcb = xcb_dep.artifact("xcb");

    const xtrans_dep = b.dependency("xtrans", .{
        .target = target,
        .optimize = optimize,
    });
    const xtrans = xtrans_dep.artifact("xtrans");

    const config_h = AutoConfigHeaderStep.create(b, target, .{
        .style = .blank,
        .include_path = "config.h",
    });
    if (loadable_xcursor) {
        config_h.config_header.addValues(.{
            .USE_DYNAMIC_XCURSOR = true,
        });
    }
    if (thread_safety_constructor) {
        config_h.config_header.addValues(.{
            .USE_THREAD_SAFETY_CONSTRUCTOR = true,
        });
    }
    if (launchd) {
        config_h.config_header.addValues(.{
            .HAVE_LAUNCHD = true,
            .TRANS_REOPEN = true,
        });
    }
    if (xthreads) {
        config_h.config_header.addValues(.{ .XTHREADS = true });
        config_h.addHaveFunction("XUSE_MTSAFE_API", "&getpwuid_r", &.{ "sys/types.h", "pwd.h" });
    }
    if (!xlocaledir) {
        config_h.config_header.addValues(.{
            .NO_XLOCALEDIR = true,
        });
    }
    if (xf86bigfont) {
        config_h.config_header.addValues(.{
            .XF86BIGFONT = true,
        });
    }
    if (composecache) {
        config_h.config_header.addValues(.{
            .COMPOSECACHE = true,
        });
    }
    config_h.addHaveHeader("HAVE_DLFCN_H", "dlfcn.h");
    config_h.addHaveHeader("HAVE_SYS_FILIO_H", "sys/filio.h");
    config_h.addHaveHeader("HAVE_SYS_SELECT_H", "sys/select.h");
    config_h.addHaveHeader("HAVE_SYS_IOCTL_H", "sys/ioctl.h");
    config_h.addHaveHeader("HAVE_SYS_SOCKET_H", "sys/socket.h");
    config_h.addHaveHeader("HAVE_UNISTD_H", "unistd.h");
    config_h.addHaveFunction("HAVE___BUILTIN_POPCOUNTL", "__builtin_popcountl(0)", &.{});
    config_h.addHaveFunction("HAVE_SETEUID", "&seteuid", &.{"unistd.h"});
    config_h.addHaveFunction("HASSETUGID", "&issetugid", &.{"unistd.h"});
    config_h.addHaveFunction("HASGETRESUID", "&getresuid", &.{"unistd.h"});
    config_h.addHaveFunction("HAS_SHM", "&shmat", &.{ "sys/types.h", "sys/shm.h" });
    config_h.addHaveFunction("USE_POLL", "&poll", &.{"poll.h"});
    config_h.addHaveFunction("HAVE_REALLOCARRAY", "&reallocarray", &.{"stdlib.h"});

    const xlib_conf_h = b.addConfigHeader(.{
        .style = .{ .autoconf_undef = x11_dep.path("include/X11/XlibConf.h.in") },
        .include_path = "X11/XlibConf.h",
    }, .{
        .XTHREADS = null,
        .XUSE_MTSAFE_API = null,
    });

    const makekeys_mod = b.createModule(.{
        .target = b.graph.host,
        .optimize = .Debug,
        .link_libc = true,
    });
    makekeys_mod.addCSourceFiles(.{
        .root = x11_dep.path("src/util"),
        .files = &.{"makekeys.c"},
    });
    const makekeys = b.addExecutable(.{
        .name = "makekeys",
        .root_module = makekeys_mod,
    });
    const makekeys_run = b.addRunArtifact(makekeys);
    makekeys_run.addFileArg(xorgproto.getEmittedIncludeTree().path(b, "X11/keysymdef.h"));
    makekeys_run.addFileArg(xorgproto.getEmittedIncludeTree().path(b, "X11/XF86keysym.h"));
    makekeys_run.addFileArg(xorgproto.getEmittedIncludeTree().path(b, "X11/Sunkeysym.h"));
    makekeys_run.addFileArg(xorgproto.getEmittedIncludeTree().path(b, "X11/DECkeysym.h"));
    makekeys_run.addFileArg(xorgproto.getEmittedIncludeTree().path(b, "X11/HPkeysym.h"));
    const ks_tables = makekeys_run.captureStdOut(.{
        .basename = "ks_tables.h",
        .trim_whitespace = .none,
    });

    const xkb_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = pic,
    });
    xkb_mod.linkLibrary(xorgproto);
    xkb_mod.addIncludePath(x11_dep.path("include/X11"));
    xkb_mod.addIncludePath(x11_dep.path("include"));
    xkb_mod.addIncludePath(x11_dep.path("src"));
    xkb_mod.addIncludePath(x11_dep.path("src/xlibi18n"));
    xkb_mod.addConfigHeader(xlib_conf_h);
    xkb_mod.addConfigHeader(config_h.config_header);
    xkb_mod.addCMacro("_Xconst", "");

    xkb_mod.addCSourceFiles(.{
        .root = x11_dep.path("src/xkb"),
        .files = &xkb_sources,
        .flags = &flags,
    });
    const xkb = b.addLibrary(.{
        .name = "xkb",
        .root_module = xkb_mod,
    });

    const im_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = pic,
    });
    im_mod.linkLibrary(xorgproto);
    im_mod.linkLibrary(xtrans);
    im_mod.addIncludePath(x11_dep.path("include/X11"));
    im_mod.addIncludePath(x11_dep.path("include"));
    im_mod.addIncludePath(x11_dep.path("src"));
    im_mod.addIncludePath(x11_dep.path("src/xlibi18n"));
    im_mod.addConfigHeader(xlib_conf_h);
    im_mod.addConfigHeader(config_h.config_header);
    im_mod.addCMacro("TRANS_CLIENT", "");
    im_mod.addCMacro("XIM_t", "");
    im_mod.addCSourceFiles(.{
        .root = x11_dep.path("modules/im/ximcp"),
        .files = &ximcp_sources,
        .flags = &flags,
    });

    const im = b.addLibrary(.{
        .name = "ximcp",
        .root_module = im_mod,
    });

    const lc_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = pic,
    });
    lc_mod.linkLibrary(xorgproto);
    lc_mod.addIncludePath(x11_dep.path("include/X11"));
    lc_mod.addIncludePath(x11_dep.path("include"));
    lc_mod.addIncludePath(x11_dep.path("src"));
    lc_mod.addIncludePath(x11_dep.path("src/xlibi18n"));
    lc_mod.addConfigHeader(xlib_conf_h);
    lc_mod.addConfigHeader(config_h.config_header);
    lc_mod.addCSourceFiles(.{
        .root = x11_dep.path("modules/lc/def"),
        .files = &lc_def_sources,
        .flags = &flags,
    });
    lc_mod.addCSourceFiles(.{
        .root = x11_dep.path("modules/lc/gen"),
        .files = &lc_gen_sources,
        .flags = &flags,
    });
    lc_mod.addCSourceFiles(.{
        .root = x11_dep.path("modules/lc/Utf8"),
        .files = &lc_utf8_sources,
        .flags = &flags,
    });
    const lc = b.addLibrary(.{
        .name = "lc",
        .root_module = lc_mod,
    });

    const om_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = pic,
    });
    om_mod.linkLibrary(xorgproto);
    om_mod.addIncludePath(x11_dep.path("include/X11"));
    om_mod.addIncludePath(x11_dep.path("include"));
    om_mod.addIncludePath(x11_dep.path("src"));
    om_mod.addIncludePath(x11_dep.path("src/xlibi18n"));
    om_mod.addConfigHeader(xlib_conf_h);
    om_mod.addConfigHeader(config_h.config_header);
    om_mod.addCSourceFiles(.{
        .root = x11_dep.path("modules/om/generic"),
        .files = &om_generic_sources,
        .flags = &flags,
    });
    const om = b.addLibrary(.{
        .name = "om",
        .root_module = om_mod,
    });

    const i18n_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = pic,
    });
    i18n_mod.linkLibrary(xorgproto);
    i18n_mod.linkLibrary(xtrans);
    if (!loadable_i18n) {
        i18n_mod.linkLibrary(im);
        i18n_mod.linkLibrary(lc);
        i18n_mod.linkLibrary(om);
    }
    i18n_mod.addIncludePath(x11_dep.path("include/X11"));
    i18n_mod.addIncludePath(x11_dep.path("include"));
    i18n_mod.addIncludePath(x11_dep.path("src"));
    i18n_mod.addIncludePath(x11_dep.path("src/xlibi18n"));
    i18n_mod.addConfigHeader(xlib_conf_h);
    i18n_mod.addConfigHeader(config_h.config_header);
    i18n_mod.addCMacro("_Xconst", "const");
    i18n_mod.addCMacro("XLOCALELIBDIR", b.fmt("\"{s}\"", .{locale_lib_dir}));

    i18n_mod.addCSourceFiles(.{
        .root = x11_dep.path("src/xlibi18n"),
        .files = &i18n_sources,
        .flags = &flags,
    });
    if (loadable_i18n) {
        i18n_mod.addCSourceFiles(.{
            .root = x11_dep.path("src/xlibi18n"),
            .files = &i18n_dl_sources,
            .flags = &flags,
        });
    }
    const i18n = b.addLibrary(.{
        .name = "xlibi18n",
        .root_module = i18n_mod,
    });

    const x11_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = pic,
    });
    x11_mod.linkLibrary(xorgproto);
    x11_mod.linkLibrary(xcb);
    x11_mod.linkLibrary(xkb);
    x11_mod.linkLibrary(i18n);
    // TODO: bigfont integration
    x11_mod.addIncludePath(xcb.getEmittedIncludeTree().path(b, "xcb"));
    x11_mod.addIncludePath(x11_dep.path("include/X11"));
    x11_mod.addIncludePath(x11_dep.path("include"));
    x11_mod.addIncludePath(x11_dep.path("src"));
    x11_mod.addIncludePath(x11_dep.path("src/xcms"));
    x11_mod.addIncludePath(x11_dep.path("src/xlibi18n"));
    x11_mod.addIncludePath(x11_dep.path("src/xkb"));
    x11_mod.addIncludePath(ks_tables.dirname());
    x11_mod.addConfigHeader(xlib_conf_h);
    x11_mod.addConfigHeader(config_h.config_header);

    if (xthreads) {
        switch (target.result.os.tag) {
            .netbsd => x11_mod.addCMacro("_POSIX_THREAD_SAFE_FUNCTIONS", "1"),
            .freebsd => x11_mod.addCMacro("_THREAD_SAFE", "1"),
            // .solaris => {
            //     x11_mod.addCMacro("_REENTRANT", "1");
            //     x11_mod.addCMacro("_POSIX_PTHREAD_SEMANTICS", "1");
            // },
            else => {},
        }
    }

    x11_mod.addCSourceFiles(.{
        .root = x11_dep.path("src"),
        .files = &x11_sources,
        .flags = &flags,
    });

    const x11_lib = b.addLibrary(.{
        .name = "x11",
        .root_module = x11_mod,
        .linkage = linkage,
    });
    x11_lib.installHeadersDirectory(x11_dep.path("include/X11"), "X11", .{});
    x11_lib.installConfigHeader(xlib_conf_h);
    b.installArtifact(x11_lib);
}

const x11_sources = .{
    "AllCells.c",
    "AllowEv.c",
    "AllPlanes.c",
    "AutoRep.c",
    "Backgnd.c",
    "BdrWidth.c",
    "Bell.c",
    "Border.c",
    "ChAccCon.c",
    "ChActPGb.c",
    "ChClMode.c",
    "ChCmap.c",
    "ChGC.c",
    "ChKeyCon.c",
    "ChkIfEv.c",
    "ChkMaskEv.c",
    "ChkTypEv.c",
    "ChkTypWEv.c",
    "ChkWinEv.c",
    "ChPntCon.c",
    "ChProp.c",
    "ChSaveSet.c",
    "ChWAttrs.c",
    "ChWindow.c",
    "CirWin.c",
    "CirWinDn.c",
    "CirWinUp.c",
    "ClDisplay.c",
    "ClearArea.c",
    "Clear.c",
    "ConfWind.c",
    "Context.c",
    "ConvSel.c",
    "CopyArea.c",
    "CopyCmap.c",
    "CopyGC.c",
    "CopyPlane.c",
    "CrBFData.c",
    "CrCmap.c",
    "CrCursor.c",
    "CrGC.c",
    "CrGlCur.c",
    "CrPFBData.c",
    "CrPixmap.c",
    "CrWindow.c",
    "Cursor.c",
    "DefCursor.c",
    "DelProp.c",
    "Depths.c",
    "DestSubs.c",
    "DestWind.c",
    "DisName.c",
    "DrArc.c",
    "DrArcs.c",
    "DrLine.c",
    "DrLines.c",
    "DrPoint.c",
    "DrPoints.c",
    "DrRect.c",
    "DrRects.c",
    "DrSegs.c",
    "ErrDes.c",
    "ErrHndlr.c",
    "evtomask.c",
    "EvToWire.c",
    "FetchName.c",
    "FillArc.c",
    "FillArcs.c",
    "FillPoly.c",
    "FillRct.c",
    "FillRcts.c",
    "FilterEv.c",
    "Flush.c",
    "Font.c",
    "FontInfo.c",
    "FontNames.c",
    "FreeCmap.c",
    "FreeCols.c",
    "FreeCurs.c",
    "FreeEData.c",
    "FreeEventData.c",
    "FreeGC.c",
    "FreePix.c",
    "FSSaver.c",
    "FSWrap.c",
    "GCMisc.c",
    "Geom.c",
    "GetAtomNm.c",
    "GetColor.c",
    "GetDflt.c",
    "GetEventData.c",
    "GetFPath.c",
    "GetFProp.c",
    "GetGCVals.c",
    "GetGeom.c",
    "GetHColor.c",
    "GetHints.c",
    "GetIFocus.c",
    "GetImage.c",
    "GetKCnt.c",
    "GetMoEv.c",
    "GetNrmHint.c",
    "GetPCnt.c",
    "GetPntMap.c",
    "GetProp.c",
    "GetRGBCMap.c",
    "GetSOwner.c",
    "GetSSaver.c",
    "GetStCmap.c",
    "GetTxtProp.c",
    "GetWAttrs.c",
    "GetWMCMapW.c",
    "GetWMProto.c",
    "globals.c",
    "GrButton.c",
    "GrKeybd.c",
    "GrKey.c",
    "GrPointer.c",
    "GrServer.c",
    "Host.c",
    "Iconify.c",
    "IfEvent.c",
    "imConv.c",
    "ImText16.c",
    "ImText.c",
    "ImUtil.c",
    "InitExt.c",
    "InsCmap.c",
    "IntAtom.c",
    "KeyBind.c",
    "KeysymStr.c",
    "KillCl.c",
    "LiHosts.c",
    "LiICmaps.c",
    "LiProps.c",
    "ListExt.c",
    "LoadFont.c",
    "LockDis.c",
    "locking.c",
    "LookupCol.c",
    "LowerWin.c",
    "Macros.c",
    "MapRaised.c",
    "MapSubs.c",
    "MapWindow.c",
    "MaskEvent.c",
    "Misc.c",
    "ModMap.c",
    "MoveWin.c",
    "NextEvent.c",
    "OCWrap.c",
    "OMWrap.c",
    "OpenDis.c",
    "ParseCmd.c",
    "ParseCol.c",
    "ParseGeom.c",
    "PeekEvent.c",
    "PeekIfEv.c",
    "Pending.c",
    "PixFormats.c",
    "PmapBgnd.c",
    "PmapBord.c",
    "PolyReg.c",
    "PolyTxt16.c",
    "PolyTxt.c",
    "PropAlloc.c",
    "PutBEvent.c",
    "PutImage.c",
    "Quarks.c",
    "QuBest.c",
    "QuColor.c",
    "QuColors.c",
    "QuCurShp.c",
    "QuExt.c",
    "QuKeybd.c",
    "QuPntr.c",
    "QuStipShp.c",
    "QuTextE16.c",
    "QuTextExt.c",
    "QuTileShp.c",
    "QuTree.c",
    "RaiseWin.c",
    "RdBitF.c",
    "RecolorC.c",
    "ReconfWin.c",
    "ReconfWM.c",
    "Region.c",
    "RegstFlt.c",
    "RepWindow.c",
    "RestackWs.c",
    "RotProp.c",
    "ScrResStr.c",
    "SelInput.c",
    "SendEvent.c",
    "SetBack.c",
    "SetClMask.c",
    "SetClOrig.c",
    "SetCRects.c",
    "SetDashes.c",
    "SetFont.c",
    "SetFore.c",
    "SetFPath.c",
    "SetFunc.c",
    "SetHints.c",
    "SetIFocus.c",
    "SetLocale.c",
    "SetLStyle.c",
    "SetNrmHint.c",
    "SetPMask.c",
    "SetPntMap.c",
    "SetRGBCMap.c",
    "SetSOwner.c",
    "SetSSaver.c",
    "SetState.c",
    "SetStCmap.c",
    "SetStip.c",
    "SetTile.c",
    "SetTSOrig.c",
    "SetTxtProp.c",
    "SetWMCMapW.c",
    "SetWMProto.c",
    "StBytes.c",
    "StColor.c",
    "StColors.c",
    "StName.c",
    "StNColor.c",
    "StrKeysym.c",
    "StrToText.c",
    "Sync.c",
    "Synchro.c",
    "Text16.c",
    "Text.c",
    "TextExt16.c",
    "TextExt.c",
    "TextToStr.c",
    "TrCoords.c",
    "UndefCurs.c",
    "UngrabBut.c",
    "UngrabKbd.c",
    "UngrabKey.c",
    "UngrabPtr.c",
    "UngrabSvr.c",
    "UninsCmap.c",
    "UnldFont.c",
    "UnmapSubs.c",
    "UnmapWin.c",
    "VisUtil.c",
    "WarpPtr.c",
    "Window.c",
    "WinEvent.c",
    "Withdraw.c",
    "WMGeom.c",
    "WMProps.c",
    "WrBitF.c",
    "xcb_disp.c",
    "xcb_io.c",
    "XlibAsync.c",
    "XlibInt.c",
    "Xrm.c",
};

const xkb_sources = .{
    "XKB.c",
    "XKBBind.c",
    "XKBCompat.c",
    "XKBCtrls.c",
    "XKBCvt.c",
    "XKBGetMap.c",
    "XKBGetByName.c",
    "XKBNames.c",
    "XKBRdBuf.c",
    "XKBSetMap.c",
    "XKBUse.c",
    "XKBleds.c",
    "XKBBell.c",
    "XKBGeom.c",
    "XKBSetGeom.c",
    "XKBExtDev.c",
    "XKBList.c",
    "XKBMisc.c",
    "XKBMAlloc.c",
    "XKBGAlloc.c",
    "XKBAlloc.c",
};

const i18n_sources = .{
    "XDefaultIMIF.c",
    "XDefaultOMIF.c",
    "xim_trans.c",
    "ICWrap.c",
    "IMWrap.c",
    "imKStoUCS.c",
    "lcCT.c",
    "lcCharSet.c",
    "lcConv.c",
    "lcDB.c",
    "lcDynamic.c",
    "lcFile.c",
    "lcGeneric.c",
    "lcInit.c",
    "lcPrTxt.c",
    "lcPubWrap.c",
    "lcPublic.c",
    "lcRM.c",
    "lcStd.c",
    "lcTxtPr.c",
    "lcUTF8.c",
    "lcUtil.c",
    "lcWrap.c",
    "mbWMProps.c",
    "mbWrap.c",
    "utf8WMProps.c",
    "utf8Wrap.c",
    "wcWrap.c",
};

const i18n_dl_sources = .{
    "XlcDL.c",
    "XlcSL.c",
};

const ximcp_sources = .{
    "imCallbk.c",
    "imDefFlt.c",
    "imDefIc.c",
    "imDefIm.c",
    "imDefLkup.c",
    "imDispch.c",
    "imEvToWire.c",
    "imExten.c",
    "imImSw.c",
    "imInsClbk.c",
    "imInt.c",
    "imLcFlt.c",
    "imLcGIc.c",
    "imLcIc.c",
    "imLcIm.c",
    "imLcLkup.c",
    "imLcPrs.c",
    "imLcSIc.c",
    "imRmAttr.c",
    "imRm.c",
    "imThaiFlt.c",
    "imThaiIc.c",
    "imThaiIm.c",
    "imTrans.c",
    "imTransR.c",
    "imTrX.c",
};

const lc_def_sources = .{
    "lcDefConv.c",
};

const lc_gen_sources = .{
    "lcGenConv.c",
};

const lc_utf8_sources = .{
    "lcUTF8Load.c",
};

const om_generic_sources = .{
    "omDefault.c",
    "omGeneric.c",
    "omImText.c",
    "omText.c",
    "omTextEsc.c",
    "omTextExt.c",
    "omTextPer.c",
    "omXChar.c",
};
