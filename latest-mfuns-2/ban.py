"""
屏蔽词/屏蔽内容管理模块
管理 ban.json 中的屏蔽词与手动屏蔽的内容条目，并提供数据库查询排除条件
"""
import asyncio
import json
import logging
import os
from typing import Any, Dict, List, Tuple

from paths import BAN_PATH

logger = logging.getLogger(__name__)


class BanManager:
    """管理屏蔽词与手动屏蔽的内容条目"""

    def __init__(self, path: str = BAN_PATH):
        self.path = path
        self._lock = asyncio.Lock()
        self._words: List[str] = []
        self._blocked_items: List[Dict[str, Any]] = []

    def load(self) -> None:
        """从 ban.json 加载配置，不存在则创建默认文件"""
        if os.path.exists(self.path):
            try:
                with open(self.path, "r", encoding="utf-8") as f:
                    data = json.load(f)
                words = data.get("words", [])
                items = data.get("blocked_items", [])
                self._words = [str(w).strip() for w in words if str(w).strip()]
                self._blocked_items = [
                    {"id": int(it.get("id", 0)), "type": str(it.get("type", "feed"))}
                    for it in items
                    if it.get("id") is not None
                ]
            except Exception as e:
                logger.warning(f"读取 ban.json 失败: {e}")
                self._words = []
                self._blocked_items = []
        else:
            self._words = []
            self._blocked_items = []
        self._save()

    def _save(self) -> None:
        try:
            with open(self.path, "w", encoding="utf-8") as f:
                json.dump(
                    {"words": self._words, "blocked_items": self._blocked_items},
                    f, ensure_ascii=False, indent=2
                )
        except Exception as e:
            logger.error(f"保存 ban.json 失败: {e}")

    def get_words(self) -> List[str]:
        return list(self._words)

    def get_blocked_items(self) -> List[Dict[str, Any]]:
        return list(self._blocked_items)

    def is_blocked(self, item_id: int, content_type: str) -> bool:
        return {"id": int(item_id), "type": str(content_type)} in self._blocked_items

    async def add_word(self, word: str) -> bool:
        word = word.strip()
        if not word or word in self._words:
            return False
        async with self._lock:
            if word not in self._words:
                self._words.append(word)
                self._save()
                return True
        return False

    async def remove_word(self, word: str) -> bool:
        async with self._lock:
            if word in self._words:
                self._words.remove(word)
                self._save()
                return True
        return False

    async def add_blocked_item(self, item_id: int, content_type: str) -> bool:
        entry = {"id": int(item_id), "type": str(content_type)}
        async with self._lock:
            if entry not in self._blocked_items:
                self._blocked_items.append(entry)
                self._save()
                return True
        return False

    async def remove_blocked_item(self, item_id: int, content_type: str) -> bool:
        entry = {"id": int(item_id), "type": str(content_type)}
        async with self._lock:
            if entry in self._blocked_items:
                self._blocked_items.remove(entry)
                self._save()
                return True
        return False

    def build_exclusion_sql(self) -> Tuple[str, List[Any]]:
        """生成用于数据库查询的排除条件，返回 (sql片段, 参数)"""
        conditions = []
        params = []
        search_cols = ("title", "description", "tags", "author")
        for word in self._words:
            escaped = word.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
            like = f"%{escaped}%"
            col_conds = [f"{col} NOT LIKE ? ESCAPE '\\'" for col in search_cols]
            conditions.append("(" + " AND ".join(col_conds) + ")")
            params.extend([like] * len(search_cols))
        for entry in self._blocked_items:
            conditions.append("NOT (id = ? AND type = ?)")
            params.append(entry["id"])
            params.append(entry["type"])
        if conditions:
            return "(" + " AND ".join(conditions) + ")", params
        return "", []


ban_manager = BanManager()
ban_manager.load()
