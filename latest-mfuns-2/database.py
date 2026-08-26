"""
数据库模块 - 负责 SQLite 数据库的初始化和数据操作
使用 aiosqlite 实现异步数据库操作，支持去重存储
"""
import aiosqlite
from typing import Optional, List, Dict, Any

from ban import ban_manager
from marks import marks_manager
from paths import DATABASE_PATH

CREATE_TABLE_SQL = """
CREATE TABLE IF NOT EXISTS items (
    id INTEGER,
    type TEXT,
    title TEXT,
    url TEXT,
    description TEXT,
    cover TEXT,
    created_at REAL,
    author TEXT DEFAULT '',
    author_id TEXT DEFAULT '',
    author_avatar TEXT DEFAULT '',
    author_bio TEXT DEFAULT '',
    author_fans INTEGER DEFAULT 0,
    likes INTEGER DEFAULT 0,
    dislikes INTEGER DEFAULT 0,
    views INTEGER DEFAULT 0,
    comments INTEGER DEFAULT 0,
    favorites INTEGER DEFAULT 0,
    rewards INTEGER DEFAULT 0,
    danmaku INTEGER DEFAULT 0,
    duration INTEGER DEFAULT 0,
    category TEXT DEFAULT '',
    tags TEXT DEFAULT '',
    PRIMARY KEY (id, type)
);
"""

DEFAULT_START_IDS = {
    "feed": 256900,
    "video": 57996,
    "article": 119436
}

ALL_COLUMNS = [
    "id", "type", "title", "url", "description", "cover", "created_at",
    "author", "author_id", "author_avatar", "author_bio", "author_fans",
    "likes", "dislikes", "views", "comments", "favorites", "rewards",
    "danmaku", "duration", "category", "tags"
]


class Database:
    """数据库管理类，提供异步数据库操作接口"""

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
        await self._connection.execute(CREATE_TABLE_SQL)
        await self._connection.execute(
            "CREATE INDEX IF NOT EXISTS idx_items_type_created ON items(type, created_at DESC)"
        )
        await self._connection.commit()
        await marks_manager.initialize()

    async def get_max_id(self, content_type: str) -> int:
        await self.connect()
        cursor = await self._connection.execute(
            "SELECT MAX(id) as max_id FROM items WHERE type = ?",
            (content_type,)
        )
        row = await cursor.fetchone()
        max_id = row["max_id"] if row["max_id"] is not None else 0
        if max_id == 0:
            return DEFAULT_START_IDS.get(content_type, 0)
        return max_id

    async def insert_item(
        self,
        item_id: int,
        content_type: str,
        title: str,
        url: str,
        created_at: float,
        description: str = "",
        cover: str = "",
        author: str = "",
        author_id: str = "",
        author_avatar: str = "",
        author_bio: str = "",
        author_fans: int = 0,
        likes: int = 0,
        dislikes: int = 0,
        views: int = 0,
        comments: int = 0,
        favorites: int = 0,
        rewards: int = 0,
        danmaku: int = 0,
        duration: int = 0,
        category: str = "",
        tags: str = "",
    ) -> bool:
        await self.connect()
        cursor = await self._connection.execute(
            """INSERT OR IGNORE INTO items
               (id, type, title, url, description, cover, created_at,
                author, author_id, author_avatar, author_bio, author_fans,
                likes, dislikes, views, comments, favorites, rewards,
                danmaku, duration, category, tags)
               VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)""",
            (item_id, content_type, title, url, description, cover, created_at,
             author, author_id, author_avatar, author_bio, author_fans,
             likes, dislikes, views, comments, favorites, rewards,
             danmaku, duration, category, tags)
        )
        await self._connection.commit()
        return cursor.rowcount > 0

    def _row_to_dict(self, row) -> Dict[str, Any]:
        result = {}
        for col in ALL_COLUMNS:
            if col in row.keys():
                val = row[col]
                if val is None:
                    if col in ("description", "cover", "author", "author_id",
                               "author_avatar", "author_bio", "category", "tags"):
                        val = ""
                    else:
                        val = 0
                result[col] = val
        return result

    async def get_item_title(self, item_id: int, content_type: str) -> str:
        await self.connect()
        cursor = await self._connection.execute(
            "SELECT title FROM items WHERE id = ? AND type = ?",
            (item_id, content_type)
        )
        row = await cursor.fetchone()
        return row["title"] if row else ""

    async def search_items(
        self,
        keyword: str,
        limit: int = 20,
        offset: int = 0,
    ) -> List[Dict[str, Any]]:
        """按关键词检索内容（不过滤屏蔽，供管理后台使用），支持分页"""
        await self.connect()
        escaped = keyword.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        like = f"%{escaped}%"
        query = """SELECT * FROM items
                   WHERE title LIKE ? ESCAPE '\\'
                      OR description LIKE ? ESCAPE '\\'
                      OR tags LIKE ? ESCAPE '\\'
                      OR author LIKE ? ESCAPE '\\'
                   ORDER BY created_at DESC LIMIT ? OFFSET ?"""
        params = [like, like, like, like, limit, offset]
        cursor = await self._connection.execute(query, params)
        rows = await cursor.fetchall()
        return [self._row_to_dict(row) for row in rows]

    async def get_latest_items(
        self,
        limit: int = 50,
        content_type: Optional[str] = None,
        since: Optional[float] = None,
        before: Optional[float] = None
    ) -> List[Dict[str, Any]]:
        await self.connect()

        query = "SELECT * FROM items WHERE 1=1"
        params = []

        if content_type:
            query += " AND type = ?"
            params.append(content_type)

        if since is not None:
            query += " AND created_at > ?"
            params.append(since)

        if before is not None:
            query += " AND created_at < ?"
            params.append(before)

        ban_sql, ban_params = ban_manager.build_exclusion_sql()
        if ban_sql:
            query += f" AND {ban_sql}"
            params.extend(ban_params)

        query += " ORDER BY created_at DESC LIMIT ?"
        params.append(limit)

        cursor = await self._connection.execute(query, params)
        rows = await cursor.fetchall()
        return [self._row_to_dict(row) for row in rows]

    async def get_stats(self) -> Dict[str, int]:
        await self.connect()
        query = "SELECT type, COUNT(*) as count FROM items WHERE 1=1"
        params = []
        ban_sql, ban_params = ban_manager.build_exclusion_sql()
        if ban_sql:
            query += f" AND {ban_sql}"
            params.extend(ban_params)
        query += " GROUP BY type"
        cursor = await self._connection.execute(query, params)
        rows = await cursor.fetchall()

        stats = {"feed": 0, "video": 0, "article": 0}
        for row in rows:
            if row["type"] in stats:
                stats[row["type"]] = row["count"]
        return stats


db_instance = Database()
