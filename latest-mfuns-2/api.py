"""
FastAPI 接口模块 - 提供 RESTful API 给前端调用
包含 /latest 和 /stats 两个核心接口
"""
import asyncio
import logging
import time
from typing import Optional, List, Dict, Any, Literal, Tuple
from datetime import datetime
import requests
from fastapi import FastAPI, APIRouter, Query, HTTPException
from fastapi.responses import PlainTextResponse
from pydantic import BaseModel

logger = logging.getLogger(__name__)

from database import db_instance
from marks import marks_manager, MARK_LIMIT
from ban import ban_manager

app = FastAPI(
    title="本地内容聚合服务",
    description="持续抓取指定网站的Feed、Video、Article内容并提供统一时间线接口",
    version="2.0.0"
)

llm_router = APIRouter(prefix="/llm", tags=["llm"])
flutter_router = APIRouter(prefix="/api/v1/flutter", tags=["flutter"])


class ItemResponse(BaseModel):
    id: int
    type: str
    title: str
    url: str
    description: str = ""
    cover: str = ""
    created_at: float
    author: str = ""
    author_id: str = ""
    author_avatar: str = ""
    author_bio: str = ""
    author_fans: int = 0
    likes: int = 0
    dislikes: int = 0
    views: int = 0
    comments: int = 0
    favorites: int = 0
    rewards: int = 0
    danmaku: int = 0
    duration: int = 0
    category: str = ""
    tags: str = ""


class StatsResponse(BaseModel):
    feed: int
    video: int
    article: int


class FlutterAuthorResponse(BaseModel):
    id: int = 0
    name: str = ""
    avatar: str = ""
    info: str = ""
    fans: int = 0


class FlutterLatestItemResponse(BaseModel):
    id: int
    type: Literal["feed", "video", "article"]
    resource_type: int
    title: str = ""
    content: str = ""
    cover: str = ""
    created_at: float
    user: FlutterAuthorResponse
    like_count: int = 0
    comment_count: int = 0
    view_count: int = 0
    category_name: str = ""
    tags: List[str] = []
    source_url: str = ""


class FlutterLatestPayload(BaseModel):
    list: List[FlutterLatestItemResponse]
    next_before: Optional[float] = None


class FlutterLatestResponse(BaseModel):
    code: int = 1
    msg: str = "获取成功"
    data: FlutterLatestPayload


class MarkRequest(BaseModel):
    id: int
    type: Literal["feed", "video", "article"]
    user: str = ""


def format_timestamp(timestamp: float) -> str:
    return datetime.fromtimestamp(timestamp).strftime("%Y-%m-%d %H:%M:%S")


def get_type_display_name(content_type: str) -> str:
    type_names = {"feed": "动态", "video": "视频", "article": "文章"}
    return type_names.get(content_type, content_type)


def format_number(n: int) -> str:
    if n >= 10000:
        return f"{n/10000:.1f}万"
    return str(n)


def to_markdown(items: List[Dict[str, Any]]) -> str:
    lines = ["# Latest MFuns Content", ""]
    for idx, item in enumerate(items, 1):
        type_display = get_type_display_name(item["type"])
        author = item.get("author", "") or "未知"
        lines.append(f"## {idx}. {type_display} by {author}")
        if item.get("title"):
            lines.append(f"标题: {item['title']}")
        lines.append(f"发布时间: {format_timestamp(item['created_at'])}")
        lines.append(f"链接: `{item['url']}`")
        stats_parts = []
        if item.get("views"):
            stats_parts.append(f"阅读 {format_number(item['views'])}")
        if item.get("likes"):
            stats_parts.append(f"赞 {item['likes']}")
        if item.get("comments"):
            stats_parts.append(f"评论 {item['comments']}")
        if stats_parts:
            lines.append(f"数据: {' | '.join(stats_parts)}")
        if item.get("tags"):
            lines.append(f"标签: {item['tags']}")
        lines.append("")
        description = item.get("description", "").strip()
        if description:
            lines.append("简介:")
            lines.append("")
            lines.append(description)
        lines.append("")
        lines.append("---")
        lines.append("")
    return "\n".join(lines)


def to_json_format(items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    result = []
    for item in items:
        result.append({
            "id": item["id"],
            "type": item["type"],
            "type_name": get_type_display_name(item["type"]),
            "title": item["title"],
            "url": item["url"],
            "description": item.get("description", ""),
            "cover": item.get("cover", ""),
            "created_at": format_timestamp(item["created_at"]),
            "created_at_timestamp": item["created_at"],
            "author": item.get("author", ""),
            "author_id": item.get("author_id", ""),
            "author_avatar": item.get("author_avatar", ""),
            "author_bio": item.get("author_bio", ""),
            "author_fans": item.get("author_fans", 0),
            "likes": item.get("likes", 0),
            "dislikes": item.get("dislikes", 0),
            "views": item.get("views", 0),
            "comments": item.get("comments", 0),
            "favorites": item.get("favorites", 0),
            "rewards": item.get("rewards", 0),
            "danmaku": item.get("danmaku", 0),
            "duration": item.get("duration", 0),
            "category": item.get("category", ""),
            "tags": item.get("tags", ""),
        })
    return result


def _as_int(value: Any) -> int:
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


def _image_url(value: Any) -> str:
    """Normalize Mfuns static paths to image bytes served by the CDN."""
    url = str(value or "").strip()
    if not url:
        return ""
    if url.startswith("//"):
        return f"https:{url}"
    if url.startswith("/static/"):
        return f"https://cdn2.mfuns.net{url}"
    if url.startswith("static/"):
        return f"https://cdn2.mfuns.net/{url}"
    if url.startswith("https://resource.mfuns.net/static/"):
        return url.replace("https://resource.mfuns.net", "https://cdn2.mfuns.net", 1)
    return url


def _tags(value: Any) -> List[str]:
    if isinstance(value, list):
        return [str(item).strip() for item in value if str(item).strip()]
    return [tag.strip() for tag in str(value or "").split(",") if tag.strip()]


_uid_cache: Dict[int, Tuple[bool, float]] = {}
_UID_CACHE_TTL = 24 * 3600


async def _uid_exists(uid: int) -> Optional[bool]:
    """尽力校验 UID 是否真实存在（调用 Mfuns 公开接口），仅供日志记录，
    不阻塞标记操作。校验失败/接口异常不返回 400，只打印日志。
    带缓存避免每次标记都请求外部接口而被限流。"""
    now = time.time()
    cached = _uid_cache.get(uid)
    if cached is not None:
        verified, ts = cached
        if now - ts < _UID_CACHE_TTL:
            return verified
    try:
        resp = await asyncio.to_thread(
            requests.get,
            "https://api.mfuns.net/v1/user/get_user",
            params={"id": uid},
            headers={
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/113.0.5672.127 Safari/537.36",
                "Accept": "application/json, text/plain, */*",
                "Accept-Language": "zh-CN,zh;q=0.9",
            },
            timeout=5,
        )
        verified = resp.status_code == 200 and resp.json().get("code") == 1
        _uid_cache[uid] = (verified, now)
        if not verified:
            logger.warning("校验 UID %s 失败：Mfuns 接口返回异常", uid)
        return verified
    except Exception:
        logger.warning("校验 UID %s 失败：无法连接 Mfuns 接口", uid, exc_info=True)
        return None


def to_flutter_format(items: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Map scraper rows to the stable, token-free Flutter app contract."""
    resource_types = {"article": 0, "video": 1, "feed": 3}
    result = []
    for item in items:
        content_type = str(item.get("type") or "feed")
        if content_type not in resource_types:
            continue
        description = str(item.get("description") or "")
        title = str(item.get("title") or "").strip()
        result.append({
            "id": _as_int(item.get("id")),
            "type": content_type,
            "resource_type": resource_types[content_type],
            "title": title or description[:80],
            "content": description,
            "cover": _image_url(item.get("cover")),
            "created_at": float(item.get("created_at") or 0),
            "user": {
                "id": _as_int(item.get("author_id")),
                "name": str(item.get("author") or ""),
                "avatar": _image_url(item.get("author_avatar")),
                "info": str(item.get("author_bio") or ""),
                "fans": _as_int(item.get("author_fans")),
            },
            "like_count": _as_int(item.get("likes")),
            "comment_count": _as_int(item.get("comments")),
            "view_count": _as_int(item.get("views")),
            "category_name": str(item.get("category") or ""),
            "tags": _tags(item.get("tags")),
            "source_url": str(item.get("url") or ""),
        })
    return result


@llm_router.get(
    "/latest",
    summary="LLM-friendly latest content",
    description="获取最新内容，专为 LLM/AI Agent 优化，支持 Markdown 和 JSON 格式"
)
async def llm_latest(
    limit: int = Query(20, ge=1, le=200),
    type: str = Query("all"),
    format: str = Query("markdown")
):
    valid_types = ["all", "feed", "video", "article"]
    if type not in valid_types:
        raise HTTPException(status_code=400,
                            detail=f"type 参数无效，可选值: {', '.join(valid_types)}")
    valid_formats = ["markdown", "json"]
    if format not in valid_formats:
        raise HTTPException(status_code=400,
                            detail=f"format 参数无效，可选值: {', '.join(valid_formats)}")
    content_type = None if type == "all" else type
    items = await db_instance.get_latest_items(limit=limit, content_type=content_type)
    if format == "markdown":
        return PlainTextResponse(content=to_markdown(items), media_type="text/markdown")
    return to_json_format(items)


@app.get("/latest", response_model=List[ItemResponse])
async def get_latest(
    limit: int = Query(default=50, ge=1, le=500),
    type: Optional[str] = Query(default=None),
    since: Optional[float] = Query(default=None),
    before: Optional[float] = Query(default=None)
) -> List[Dict[str, Any]]:
    if type and type not in ["feed", "video", "article"]:
        raise HTTPException(status_code=400,
                            detail="type 参数无效，可选值: feed, video, article")
    return await db_instance.get_latest_items(limit=limit, content_type=type,
                                              since=since, before=before)


@flutter_router.get("/latest", response_model=FlutterLatestResponse)
async def flutter_latest(
    limit: int = Query(default=20, ge=1, le=50),
    before: Optional[float] = Query(default=None),
    user: Optional[str] = Query(default=None),
) -> Dict[str, Any]:
    """Latest unified content for Mfuns-Flutter, without user credentials.
    附带不友好标记数（mark_count）与当前用户标记状态（marked_by_me）。"""
    items = await db_instance.get_latest_items(limit=limit, before=before)
    payload = to_flutter_format(items)
    if payload:
        keys = [(item["id"], item["type"]) for item in payload]
        counts = await marks_manager.counts_for(keys)
        marked = await marks_manager.marked_set_for(keys, user or "")
        for item in payload:
            key = (item["id"], item["type"])
            item["mark_count"] = counts.get(key, 0)
            item["marked_by_me"] = key in marked
    next_before = payload[-1]["created_at"] if payload else None
    return {
        "code": 1,
        "msg": "获取成功",
        "data": {"list": payload, "next_before": next_before},
    }


@flutter_router.post("/marks")
async def flutter_mark(body: MarkRequest) -> Dict[str, Any]:
    """不友好标记（需登录）：user 为 Mfuns UID，服务端校验并去重，
    同一用户对同一帖子只计一次；达到阈值自动屏蔽。
    UID 仅校验格式，存在性校验为尽力而为（失败只记日志，不阻塞标记）。"""
    uid = body.user.strip()
    if not uid.isdigit() or int(uid) <= 0:
        raise HTTPException(status_code=400, detail="UID 无效，请登录后标记")
    await _uid_exists(int(uid))
    result = await marks_manager.add_mark(body.id, body.type, uid)
    count = result["mark_count"]
    if result["blocked"]:
        msg = f"标记成功，该帖子已被 {count} 位喵友标记并屏蔽处理"
    else:
        msg = f"标记成功，已有 {count}/{MARK_LIMIT} 位喵友标记此帖子"
    return {
        "code": 1,
        "msg": msg,
        "data": {
            "mark_count": count,
            "marked_by_me": True,
            "blocked": result["blocked"],
        },
    }


@flutter_router.post("/marks/cancel")
async def flutter_mark_cancel(body: MarkRequest) -> Dict[str, Any]:
    """取消不友好标记（需登录）：删除当前 UID 的标记记录。"""
    uid = body.user.strip()
    if not uid.isdigit() or int(uid) <= 0:
        raise HTTPException(status_code=400, detail="UID 无效，请登录后操作")
    result = await marks_manager.remove_mark(body.id, body.type, uid)
    return {
        "code": 1,
        "msg": "已取消标记",
        "data": {
            "mark_count": result["mark_count"],
            "marked_by_me": False,
            "blocked": ban_manager.is_blocked(body.id, body.type),
        },
    }


@flutter_router.get("/marks/status")
async def flutter_mark_status(
    item_id: int = Query(...),
    type: str = Query(...),
    user: Optional[str] = Query(default=None),
) -> Dict[str, Any]:
    """查询单个帖子的不友好标记状态。"""
    status = await marks_manager.mark_status(item_id, type, user or "")
    return {"code": 1, "msg": "获取成功", "data": status}


@app.get("/stats", response_model=StatsResponse)
async def get_stats() -> Dict[str, int]:
    return await db_instance.get_stats()
