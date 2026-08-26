"""
不友好标记模块 - 记录用户对内容的标记
user 字段为 Mfuns UID（需登录，由调用方校验），以 (id, type, user) 联合主键
保证同一用户对同一帖子只计一次；达到阈值（默认 5 人）后自动加入屏蔽列表，
帖子将从公开列表中消失
"""
import logging
import time
from typing import Any, Dict, List, Optional, Set, Tuple

import aiosqlite

from ban import ban_manager
from paths import DATABASE_PATH

logger = logging.getLogger(__name__)

MARK_LIMIT = 5
MARK_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS marks (
    id INTEGER,
    type TEXT,
    user TEXT,
    created_at REAL DEFAULT 0,
    PRIMARY KEY (id, type, user)
);
"""


class MarksManager:
    """管理用户对内容的标记，达到阈值自动屏蔽"""

    def __init__(self, db_path: str = DATABASE_PATH):
        self.db_path = db_path
        self._connection: Optional[aiosqlite.Connection] = None

    async def connect(self):
        if self._connection is None:
            self._connection = await aiosqlite.connect(self.db_path)
            self._connection.row_factory = aiosqlite.Row

    async def close(self):
        if self._connection:
            await self._connection.close()
            self._connection = None

    async def initialize(self):
        await self.connect()
        await self._connection.execute(MARK_TABLE_SQL)
        await self._connection.execute(
            "CREATE INDEX IF NOT EXISTS idx_marks_item ON marks(id, type)"
        )
        await self._connection.commit()

    async def add_mark(
        self, item_id: int, content_type: str, user: str
    ) -> Dict[str, Any]:
        """记录一次标记；达到阈值自动屏蔽。返回 (mark_count, added, blocked)。"""
        user = (user or "").strip()
        if not user:
            return {"mark_count": 0, "added": False, "blocked": False}
        await self.connect()
        cursor = await self._connection.execute(
            "INSERT OR IGNORE INTO marks (id, type, user, created_at) "
            "VALUES (?,?,?,?)",
            (int(item_id), str(content_type), user, time.time()),
        )
        await self._connection.commit()
        added = cursor.rowcount > 0
        count = await self.count(item_id, content_type)
        blocked = False
        if count >= MARK_LIMIT:
            blocked = await ban_manager.add_blocked_item(
                int(item_id), str(content_type)
            )
        return {"mark_count": count, "added": added, "blocked": blocked}

    async def remove_mark(
        self, item_id: int, content_type: str, user: str
    ) -> Dict[str, Any]:
        """取消标记：删除当前用户的标记记录。返回 (mark_count, removed)。
        已屏蔽的帖子不做自动解封（避免覆盖管理员手动屏蔽）。"""
        user = (user or "").strip()
        if not user:
            return {"mark_count": 0, "removed": False}
        await self.connect()
        cursor = await self._connection.execute(
            "DELETE FROM marks WHERE id = ? AND type = ? AND user = ?",
            (int(item_id), str(content_type), user),
        )
        await self._connection.commit()
        return {
            "mark_count": await self.count(item_id, content_type),
            "removed": cursor.rowcount > 0,
        }

    async def count(self, item_id: int, content_type: str) -> int:
        await self.connect()
        cursor = await self._connection.execute(
            "SELECT COUNT(*) as c FROM marks WHERE id = ? AND type = ?",
            (int(item_id), str(content_type)),
        )
        row = await cursor.fetchone()
        return row["c"] if row else 0

    async def has_marked(self, item_id: int, content_type: str, user: str) -> bool:
        user = (user or "").strip()
        if not user:
            return False
        await self.connect()
        cursor = await self._connection.execute(
            "SELECT 1 FROM marks WHERE id = ? AND type = ? AND user = ?",
            (int(item_id), str(content_type), user),
        )
        return await cursor.fetchone() is not None

    async def mark_status(
        self, item_id: int, content_type: str, user: str
    ) -> Dict[str, Any]:
        return {
            "mark_count": await self.count(item_id, content_type),
            "marked_by_me": await self.has_marked(item_id, content_type, user),
            "blocked": ban_manager.is_blocked(int(item_id), str(content_type)),
        }

    async def marked_items(self) -> List[Dict[str, Any]]:
        """返回所有被用户标记的内容 (id, type, mark_count)，
        未达阈值（未自动屏蔽）的按标记数倒序排列。"""
        await self.connect()
        cursor = await self._connection.execute(
            "SELECT id, type, COUNT(*) as c FROM marks "
            "GROUP BY id, type HAVING c < ? "
            "ORDER BY c DESC, MAX(created_at) DESC",
            (MARK_LIMIT,),
        )
        rows = await cursor.fetchall()
        return [
            {
                "id": int(row["id"]),
                "type": str(row["type"]),
                "mark_count": int(row["c"]),
            }
            for row in rows
        ]

    async def counts_for(
        self, keys: List[Tuple[int, str]]
    ) -> Dict[Tuple[int, str], int]:
        """批量查询标记数，keys 为 (id, type) 列表。"""
        if not keys:
            return {}
        result = {}
        for item_id, content_type in keys:
            result[(item_id, content_type)] = await self.count(item_id, content_type)
        return result

    async def marked_set_for(
        self, keys: List[Tuple[int, str]], user: str
    ) -> Set[Tuple[int, str]]:
        """批量查询当前用户已标记的 (id, type) 集合。"""
        user = (user or "").strip()
        if not user or not keys:
            return set()
        await self.connect()
        result = set()
        for item_id, content_type in keys:
            if await self.has_marked(item_id, content_type, user):
                result.add((item_id, content_type))
        return result


marks_manager = MarksManager()
