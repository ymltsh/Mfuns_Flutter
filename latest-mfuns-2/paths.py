"""
路径模块 - 统一管理运行时的文件路径

- 源码运行 (python main.py): 数据文件位于项目根目录
- PyInstaller 打包 (exe):   数据文件固定位于可执行文件所在目录
"""
import os
import sys
from pathlib import Path


def is_frozen() -> bool:
    """是否运行在 PyInstaller 打包后的环境中"""
    return getattr(sys, "frozen", False)


def get_base_dir() -> Path:
    """数据/配置文件目录：
    打包后固定为 exe 所在目录，源码运行时为项目根目录"""
    if is_frozen():
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent


BASE_DIR = get_base_dir()

CONFIG_PATH = str(BASE_DIR / "config.json")
DATABASE_PATH = str(BASE_DIR / "aggregator.db")
BAN_PATH = str(BASE_DIR / "ban.json")
LAST_JSON_PATH = str(BASE_DIR / "last.json")
TOKEN_PATH = str(BASE_DIR / "mfuns_token.pkl")
DEVICE_ID_PATH = str(BASE_DIR / "device_id.cache")
