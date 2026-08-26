"""
后台管理模块 - 管理员登录与屏蔽词/屏蔽内容管理
管理员账号密码从 config.json 的 admin 字段读取
"""
import json
import logging
import os
import secrets
import time
from typing import Dict, Optional, Tuple

from fastapi import APIRouter, HTTPException, Query, Request, Response
from pydantic import BaseModel

from ban import ban_manager
from database import db_instance
from marks import marks_manager
from paths import CONFIG_PATH

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/admin", tags=["admin"])

COOKIE_NAME = "admin_token"
SESSION_TTL = 24 * 3600  # 24小时

# 内存会话表: token -> (username, expire_at)
_sessions: Dict[str, Tuple[str, float]] = {}


def _load_admin_config() -> dict:
    try:
        if os.path.exists(CONFIG_PATH):
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                return json.load(f).get("admin", {}) or {}
    except Exception:
        pass
    return {}


ADMIN_CONFIG = _load_admin_config()


def _verify_login(username: str, password: str) -> bool:
    expected_user = ADMIN_CONFIG.get("username", "admin")
    expected_pass = ADMIN_CONFIG.get("password", "admin123")
    return username == expected_user and password == expected_pass


def _create_session(username: str) -> str:
    token = secrets.token_urlsafe(32)
    _sessions[token] = (username, time.time() + SESSION_TTL)
    return token


def get_current_admin(request: Request) -> str:
    token = request.cookies.get(COOKIE_NAME)
    if not token:
        raise HTTPException(status_code=401, detail="未登录")
    session = _sessions.get(token)
    if not session:
        raise HTTPException(status_code=401, detail="会话已失效，请重新登录")
    username, expire_at = session
    if time.time() > expire_at:
        _sessions.pop(token, None)
        raise HTTPException(status_code=401, detail="会话已过期，请重新登录")
    return username


class LoginRequest(BaseModel):
    username: str
    password: str


class WordRequest(BaseModel):
    word: str


class BlockItemRequest(BaseModel):
    id: int
    type: str


@router.post("/login")
async def login(body: LoginRequest, response: Response):
    if not _verify_login(body.username, body.password):
        raise HTTPException(status_code=401, detail="用户名或密码错误")
    token = _create_session(body.username)
    response.set_cookie(COOKIE_NAME, token, httponly=True,
                        max_age=SESSION_TTL, samesite="lax")
    return {"success": True, "username": body.username}


@router.post("/logout")
async def logout(response: Response):
    response.delete_cookie(COOKIE_NAME)
    return {"success": True}


@router.get("/session")
async def session_status(request: Request):
    try:
        username = get_current_admin(request)
        return {"logged_in": True, "username": username}
    except HTTPException:
        return {"logged_in": False}


@router.get("/banned")
async def get_banned(request: Request):
    get_current_admin(request)
    words = ban_manager.get_words()
    items = []
    for entry in ban_manager.get_blocked_items():
        title = await db_instance.get_item_title(entry["id"], entry["type"])
        items.append({**entry, "title": title})
    return {"words": words, "items": items}


@router.get("/search")
async def search_items(
    request: Request,
    q: str = Query("", max_length=100),
    limit: int = Query(200, ge=1, le=500),
    offset: int = Query(0, ge=0),
):
    get_current_admin(request)
    q = q.strip()
    if not q:
        return {"items": []}
    items = await db_instance.search_items(q, limit, offset)
    blocked_set = {
        (entry["id"], entry["type"]) for entry in ban_manager.get_blocked_items()
    }
    for item in items:
        item["blocked"] = (item["id"], item["type"]) in blocked_set
    return {"items": items}


@router.get("/marked")
async def get_marked(request: Request):
    """被用户标记但未达阈值（未自动屏蔽）的内容，管理员可手动屏蔽。"""
    get_current_admin(request)
    blocked_set = {
        (entry["id"], entry["type"]) for entry in ban_manager.get_blocked_items()
    }
    items = []
    for entry in await marks_manager.marked_items():
        key = (entry["id"], entry["type"])
        if key in blocked_set:
            continue
        title = await db_instance.get_item_title(entry["id"], entry["type"])
        items.append({**entry, "title": title})
    return {"items": items}


@router.post("/banned/words")
async def add_word(body: WordRequest, request: Request):
    get_current_admin(request)
    word = body.word.strip()
    if not word:
        raise HTTPException(status_code=400, detail="屏蔽词不能为空")
    if not await ban_manager.add_word(word):
        raise HTTPException(status_code=400, detail="屏蔽词已存在或为空")
    return {"success": True, "words": ban_manager.get_words()}


@router.delete("/banned/words/{word}")
async def remove_word(word: str, request: Request):
    get_current_admin(request)
    await ban_manager.remove_word(word)
    return {"success": True, "words": ban_manager.get_words()}


@router.post("/banned/items")
async def block_item(body: BlockItemRequest, request: Request):
    get_current_admin(request)
    if body.type not in ("feed", "video", "article"):
        raise HTTPException(status_code=400, detail="type 无效")
    if not await ban_manager.add_blocked_item(body.id, body.type):
        raise HTTPException(status_code=400, detail="该内容已在屏蔽列表")
    return {"success": True}


@router.delete("/banned/items/{content_type}/{item_id}")
async def unblock_item(content_type: str, item_id: int, request: Request):
    get_current_admin(request)
    if content_type not in ("feed", "video", "article"):
        raise HTTPException(status_code=400, detail="type 无效")
    await ban_manager.remove_blocked_item(item_id, content_type)
    return {"success": True}
