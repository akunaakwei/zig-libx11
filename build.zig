const std = @import("std");
const AutoConfigHeaderStep = @import("autoconfigheader").AutoConfigHeaderStep;

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const linkage = b.option(std.builtin.LinkMode, "linkage", "Linkage type for the library") orelse .static;
    // const loadable_i18n = b.option(bool, "loadable-i18n", "Controls loadable i18n module support") orelse false;
    // const loadable_xcursor = b.option(bool, "loadable-xcursor", "Controls loadable xcursor module support") orelse false;
    const thread_safety_constructor = b.option(bool, "thread-safety-constructor", "Controls mandatory thread safety support") orelse true;
    const launchd = b.option(bool, "launchd", "Build with support for Apple's launchd") orelse target.result.os.tag.isDarwin();
    const xthreads = b.option(bool, "xthreads", "Controls Xlib support for Multithreading") orelse true;
    const xlocaledir = b.option(bool, "xlocaledir", "Controls XLOCALEDIR environment variable support") orelse true;
    const xf86bigfont = b.option(bool, "xf86bigfont", "Controls XF86BigFont extension support") orelse true;
    const composecache = b.option(bool, "composecache", "Controls compose table cache support") orelse true;

    const flags = .{""};

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

    const config_h = AutoConfigHeaderStep.create(b, target, .{
        .style = .blank,
        .include_path = "config.h",
    });
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

    const x11_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .pic = if (linkage == .dynamic) true else null,
    });
    x11_mod.linkLibrary(xorgproto);
    x11_mod.linkLibrary(xcb);
    // TODO: bigfont integration
    x11_mod.addIncludePath(xcb.getEmittedIncludeTree().path(b, "xcb"));
    x11_mod.addIncludePath(x11_dep.path("include/X11"));
    x11_mod.addIncludePath(x11_dep.path("include"));
    x11_mod.addIncludePath(x11_dep.path("src/xcms"));
    x11_mod.addIncludePath(x11_dep.path("src/xlibi18n"));
    x11_mod.addIncludePath(ks_tables.dirname());
    x11_mod.addConfigHeader(xlib_conf_h);

    x11_mod.addCMacro("HAVE_CONFIG_H", "1");
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
