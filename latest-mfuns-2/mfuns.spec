# -*- mode: python ; coding: utf-8 -*-
# PyInstaller 打包配置
# 构建命令: pyinstaller mfuns.spec
# 产物: dist/mfuns/mfuns.exe，配置文件(config.json 等)首次运行时自动在 exe 同目录生成
# 网页源码已内嵌于 webui.py，无需打包 templates 目录
import sys

from PyInstaller.utils.hooks import collect_submodules

hiddenimports = (
    collect_submodules("uvicorn")
    + collect_submodules("uvicorn.logging")
    + collect_submodules("uvicorn.loops")
    + collect_submodules("uvicorn.protocols")
    + collect_submodules("uvicorn.lifespan")
    + collect_submodules("httpx")
    + collect_submodules("aiosqlite")
    + collect_submodules("bs4")
)

a = Analysis(
    ["main.py"],
    pathex=[],
    binaries=[],
    datas=[],
    hiddenimports=hiddenimports,
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
)

pyz = PYZ(a.pure)

exe = EXE(
    pyz,
    a.scripts,
    a.binaries,
    a.datas,
    [],
    name="mfuns",
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=True,
    upx_exclude=[],
    runtime_tmpdir=None,
    console=True,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
