"""
爬虫核心模块 - 负责HTTP请求、HTML解析和内容提取
使用 httpx 异步客户端和 BeautifulSoup4 解析器
从 __NUXT__ SSR 提取作者、交互数据等增强信息
"""
import httpx
import asyncio
import random
import time
import re
import os
import pickle
import uuid
import json
from typing import Optional, Dict, Any, Tuple
from bs4 import BeautifulSoup

from paths import CONFIG_PATH, TOKEN_PATH, DEVICE_ID_PATH

BASE_URL = "https://m.mfuns.net/{type}/{id}"
LOOKAHEAD_THRESHOLD = 10

LOGIN_URL = "https://api.mfuns.net/v1/auth/login"
VALIDATE_URL = "https://api.mfuns.net/v1/user/info"

AVATAR_BASE = "https://resource.mfuns.net"


def clean_text(text: str) -> str:
    if not text:
        return text
    try:
        return text.encode("utf-8", errors="replace").decode("utf-8")
    except Exception:
        return text


def _resolve_avatar(avatar: str) -> str:
    if not avatar:
        return ""
    avatar = avatar.replace("\\u002F", "/")
    if avatar.startswith("http"):
        return avatar
    if avatar.startswith("/"):
        avatar = AVATAR_BASE + avatar
    return avatar


def _parse_nuxt_params(html: str, nuxt_start: int) -> Dict[str, Any]:
    """解析 __NUXT__ 函数参数映射，用于还原变量引用"""
    end_pos = html.find("</script>", nuxt_start)
    if end_pos < 0:
        end_pos = nuxt_start + 50000
    block = html[nuxt_start:end_pos]

    # 提取参数名列表: function(a,b,c,...)
    params_m = re.search(r'function\s*\(([^)]*)\)', block)
    if not params_m:
        return {}
    param_names = [p.strip() for p in params_m.group(1).split(",")]

    # 找最后的 }( 序列: function body 结束 + 调用开始
    # 格式: ...config:{...}}}(0,1,...);
    # 注意: Nuxt 使用 =function(){}()  (无外层包裹括号)
    last_close = block.rfind("}(")
    if last_close < 0:
        return {}
    arg_start = last_close + 1
    arg_end = block.find(")", arg_start)
    if arg_end < 0:
        return {}
    args_str = block[arg_start + 1:arg_end].strip()
    if args_str.endswith(";"):
        args_str = args_str[:-1].strip()

    args = _split_nuxt_args(args_str)
    mapping = {}
    for idx, name in enumerate(param_names):
        if idx < len(args):
            mapping[name] = args[idx]
    return mapping


def _split_nuxt_args(s: str) -> list:
    """分割 __NUXT__ 调用参数列表"""
    args = []
    i = 0
    while i < len(s):
        c = s[i]
        if c == ",":
            args.append(None)
            i += 1
            continue
        elif c == '"':
            j = i + 1
            while j < len(s):
                if s[j] == "\\":
                    j += 2
                elif s[j] == '"':
                    break
                else:
                    j += 1
            args.append(s[i+1:j])
            i = j + 1
        elif c == "{":
            depth = 1
            j = i + 1
            while j < len(s) and depth > 0:
                if s[j] == "{":
                    depth += 1
                elif s[j] == "}":
                    depth -= 1
                elif s[j] == '"':
                    j += 1
                    while j < len(s) and s[j] != '"':
                        if s[j] == "\\":
                            j += 1
                        j += 1
                j += 1
            args.append(s[i:j])
            i = j
        elif c.isdigit() or (c == "-" and i + 1 < len(s) and s[i+1].isdigit()):
            j = i + 1
            while j < len(s) and (s[j].isdigit() or s[j] == "."):
                j += 1
            args.append(int(s[i:j]))
            i = j
        else:
            j = i + 1
            while j < len(s) and s[j] not in (",",):
                j += 1
            val = s[i:j].strip()
            if val in ("true",):
                args.append(True)
            elif val in ("false",):
                args.append(False)
            elif val in ("null", "void 0"):
                args.append(None)
            else:
                try:
                    args.append(int(val))
                except ValueError:
                    args.append(val)
            i = j
        while i < len(s) and s[i] == ",":
            i += 1
    return args


def _resolve_var(val: Any, mapping: Dict[str, Any]) -> Any:
    """如果值是单字母变量名，从 mapping 中解析"""
    if isinstance(val, str) and len(val) == 1 and val.isalpha() and val in mapping:
        return mapping[val]
    return val


def parse_nuxt_ssr(html: str) -> Dict[str, Any]:
    """从 __NUXT__ SSR 状态中提取作者、标签、交互数据"""
    result = {}

    nuxt_start = html.find("__NUXT__")
    if nuxt_start < 0:
        return result

    param_map = _parse_nuxt_params(html, nuxt_start)

    state_start = html.find("state:{", nuxt_start)
    fetch_end = state_start if state_start > 0 else nuxt_start + 20000
    fetch_zone = html[nuxt_start:fetch_end]

    # --- 用户信息 (user / userinfo) ---
    # 找最后一个匹配的块 (转发feed有多个user:{}, 最后一个是实际发布者)
    best_block = None
    for key in ("user:{", "userinfo:{"):
        idx = 0
        while True:
            idx = fetch_zone.find(key, idx)
            if idx < 0:
                break
            depth = 0
            end = idx + len(key)
            while end < len(fetch_zone):
                c = fetch_zone[end]
                if c == "{":
                    depth += 1
                elif c == "}":
                    if depth == 0:
                        break
                    depth -= 1
                end += 1
            best_block = fetch_zone[idx:end + 1]
            idx = end + 1

    if best_block:
        block = best_block

        # 尝试字面量匹配
        name_m = re.search(r'name\s*:\s*"([^"]+)"', block)
        uid_m = re.search(r'(?:"id"|user_id)\s*:\s*(\d+)', block)
        avatar_m = re.search(r'avatar\s*:\s*"([^"]+)"', block)
        bio_m = re.search(r'info\s*:\s*"([^"]*)"', block)
        fans_m = re.search(r'fans\s*:\s*(\d+)', block)

        # 字面量未找到时，尝试变量引用 name:X -> 从 param_map 解析
        if not name_m:
            var_name_m = re.search(r'name\s*:\s*([a-zA-Z_])(?:\s*[,}])', block)
            if var_name_m:
                resolved = _resolve_var(var_name_m.group(1), param_map)
                if isinstance(resolved, str) and resolved:
                    result["author"] = resolved
        else:
            result["author"] = name_m.group(1)

        if not uid_m:
            var_uid_m = re.search(r'(?:"id"|user_id)\s*:\s*([a-zA-Z_])(?:\s*[,}])', block)
            if var_uid_m:
                resolved = _resolve_var(var_uid_m.group(1), param_map)
                if isinstance(resolved, int):
                    result["author_id"] = str(resolved)
        else:
            result["author_id"] = uid_m.group(1)

        if not avatar_m:
            var_av_m = re.search(r'avatar\s*:\s*([a-zA-Z_])(?:\s*[,}])', block)
            if var_av_m:
                resolved = _resolve_var(var_av_m.group(1), param_map)
                if isinstance(resolved, str):
                    result["author_avatar"] = _resolve_avatar(resolved)
        else:
            result["author_avatar"] = _resolve_avatar(avatar_m.group(1))

        if not bio_m:
            var_bio_m = re.search(r'info\s*:\s*"([^"]*)"', block)
            if var_bio_m:
                result["author_bio"] = var_bio_m.group(1)
        else:
            result["author_bio"] = bio_m.group(1)

        if not fans_m:
            var_fans_m = re.search(r'fans\s*:\s*([a-zA-Z_])(?:\s*[,}])', block)
            if var_fans_m:
                resolved = _resolve_var(var_fans_m.group(1), param_map)
                if isinstance(resolved, int):
                    result["author_fans"] = resolved
        else:
            result["author_fans"] = int(fans_m.group(1))

    # --- 标签 ---
    tags_block = re.search(r'tags\s*:\s*(\[[^\]]*\])', fetch_zone)
    if tags_block:
        tag_names = re.findall(r'"([^"]+)"', tags_block.group(1))
        if tag_names:
            result["tags"] = ",".join(tag_names)

    # --- 阅读量 ---
    views_m = re.search(r'(?:views|view_count|viewCount)\s*:\s*(\d+)', fetch_zone)
    if views_m:
        result["views"] = int(views_m.group(1))
    else:
        views_var = re.search(r'(?:views|view_count|viewCount)\s*:\s*([a-zA-Z_])\s*[,}]', fetch_zone)
        if views_var:
            resolved = _resolve_var(views_var.group(1), param_map)
            if isinstance(resolved, int):
                result["views"] = resolved

    # --- 点赞/踩 ---
    like_m = re.search(r'(?:\w+\.)?like\s*=\s*\{count\s*:\s*(\d+)', fetch_zone)
    if like_m:
        result["likes"] = int(like_m.group(1))
    else:
        like_m2 = re.search(r'like\s*:\s*\{count\s*:\s*(\d+)', fetch_zone)
        if like_m2:
            result["likes"] = int(like_m2.group(1))

    dislike_m = re.search(r'(?:\w+\.)?dislike\s*=\s*\{count\s*:\s*(\d+)', fetch_zone)
    if dislike_m:
        result["dislikes"] = int(dislike_m.group(1))
    else:
        dislike_m2 = re.search(r'dislike\s*:\s*\{count\s*:\s*(\d+)', fetch_zone)
        if dislike_m2:
            result["dislikes"] = int(dislike_m2.group(1))

    # --- 评论 ---
    floor_m = re.search(r'floor_count\s*:\s*(\d+)', fetch_zone)
    if floor_m:
        result["comments"] = int(floor_m.group(1))
    else:
        floor_var = re.search(r'floor_count\s*:\s*([a-zA-Z_])\s*[,}]', fetch_zone)
        if floor_var:
            resolved = _resolve_var(floor_var.group(1), param_map)
            if isinstance(resolved, int):
                result["comments"] = resolved

    # --- 收藏 ---
    fav_m = re.search(r'favorite_count\s*:\s*(\d+)', fetch_zone)
    if fav_m:
        result["favorites"] = int(fav_m.group(1))

    # --- 打赏 ---
    reward_m = re.search(r'reward_count\s*:\s*(\d+)', fetch_zone)
    if reward_m:
        result["rewards"] = int(reward_m.group(1))

    # --- 弹幕 ---
    danmaku_m = re.search(r'danmaku_count\s*:\s*(\d+)', fetch_zone)
    if danmaku_m:
        result["danmaku"] = int(danmaku_m.group(1))

    # --- 时长 ---
    dur_m = re.search(r'duration\s*:\s*(\d+)', fetch_zone)
    if dur_m:
        result["duration"] = int(dur_m.group(1))

    # --- 分类 ---
    cat_m = re.search(r'category:\{[^}]*?name:"([^"]*)"', fetch_zone)
    if cat_m:
        result["category"] = cat_m.group(1)

    return result


class CookieManager:
    """Cookie管理类，负责获取和刷新mfuns_token"""

    def __init__(self):
        self.token: Optional[str] = None
        self.device_id: Optional[str] = None
        self._initialize_device_id()

    def _initialize_device_id(self):
        cache_file = DEVICE_ID_PATH
        if os.path.exists(cache_file):
            try:
                with open(cache_file, "r") as f:
                    self.device_id = f.read().strip()
            except:
                pass

        if not self.device_id:
            mac_address = uuid.getnode()
            self.device_id = f"f282feac-2f2e-4dec-ad39-{mac_address:012x}"[:36]
            try:
                with open(cache_file, "w") as f:
                    f.write(self.device_id)
            except:
                pass

    def _generate_client_id(self) -> str:
        try:
            mac_address = uuid.getnode()
            return f"mfuns-crawl-{mac_address:x}"
        except Exception:
            return f"mfuns-crawl-{int(time.time())}"

    def save_token(self, token: str):
        with open(TOKEN_PATH, "wb") as f:
            pickle.dump(token, f)
        self.token = token

    def load_token(self) -> Optional[str]:
        if os.path.exists(TOKEN_PATH):
            try:
                with open(TOKEN_PATH, "rb") as f:
                    token = pickle.load(f)
                    self.token = token
                    return token
            except:
                pass
        return None

    def is_token_valid(self, token: str) -> bool:
        headers = {
            "Authorization": token,
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/113.0.5672.127 Safari/537.36"
        }
        try:
            response = httpx.get(VALIDATE_URL, headers=headers, timeout=10.0)
            if response.status_code == 200:
                data = response.json()
                return data.get("code") == 1
            return False
        except:
            return False

    def get_active_token(self) -> Optional[str]:
        cached_token = self.load_token()
        if cached_token and self.is_token_valid(cached_token):
            return cached_token
        return self.login_and_get_token()

    def _load_config(self) -> dict:
        if os.path.exists(CONFIG_PATH):
            try:
                with open(config_path, "r", encoding="utf-8") as f:
                    return json.load(f)
            except Exception:
                pass
        return {}

    def login_and_get_token(self) -> Optional[str]:
        try:
            import requests
            config = self._load_config()
            account = config.get("account", "")
            password = config.get("password", "")
            if not account or not password:
                print("[CookieManager] config.json 缺少 account/password")
                return None
            data = {"account": account, "password": password}
            headers = {
                "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/113.0.5672.127 Safari/537.36"
            }
            response = requests.post(LOGIN_URL, headers=headers, data=data, timeout=10)
            res = response.json()

            if response.status_code == 200 and "data" in res and "access_token" in res["data"]:
                token = res["data"]["access_token"]
                self.save_token(token)
                return token
        except Exception as e:
            print(f"[CookieManager] 登录失败: {e}")
        return None


cookie_manager = CookieManager()


def parse_page(html: str, type_: str, id_: int) -> Optional[Dict[str, Any]]:
    """解析页面内容，提取标题、简介、封面、作者、交互数据"""
    if '_error:{message:"Cannot read' in html or 'statusCode:500' in html:
        return None

    soup = BeautifulSoup(html, "html.parser")

    if type_ != "feed" and soup.find("div", class_=lambda c: c and "v-progress-linear__indeterminate" in c):
        return None

    title_tag = soup.title
    raw_title = title_tag.text if title_tag else ""

    clean_title = re.sub(r'[-\s]*喵御宅\s*Mfuns$', '', raw_title).strip()
    clean_title = clean_title.replace("加载中", "").strip()

    if not clean_title or "404" in clean_title:
        return None

    h1_tag = soup.find("h1")
    if h1_tag is not None and not h1_tag.text.strip():
        return None

    item_data = {
        "id": id_,
        "type": type_,
        "url": f"https://m.mfuns.net/{type_}/{id_}",
        "title": clean_title,
        "description": "",
        "cover": "",
        "created_at": time.time(),
        "author": "",
        "author_id": "",
        "author_avatar": "",
        "author_bio": "",
        "author_fans": 0,
        "likes": 0,
        "dislikes": 0,
        "views": 0,
        "comments": 0,
        "favorites": 0,
        "rewards": 0,
        "danmaku": 0,
        "duration": 0,
        "category": "",
        "tags": "",
    }

    # --- JSON-LD 提取 ---
    ld_json_tags = soup.find_all("script", type="application/ld+json")
    data_dict = None

    for tag in ld_json_tags:
        if not tag.string or tag.string.strip() == "null":
            continue
        if "VideoObject" in tag.string or "Article" in tag.string or "NewsArticle" in tag.string:
            try:
                data_dict = json.loads(tag.string)
                break
            except json.JSONDecodeError:
                continue

    if data_dict:
        if data_dict.get("name"):
            item_data["title"] = data_dict.get("name").strip()
        elif data_dict.get("headline"):
            item_data["title"] = data_dict.get("headline").strip()

        item_data["description"] = data_dict.get("description", "").strip()

        if data_dict.get("thumbnailUrl"):
            item_data["cover"] = data_dict.get("thumbnailUrl").strip()
        elif isinstance(data_dict.get("image"), list) and len(data_dict["image"]) > 0:
            item_data["cover"] = data_dict["image"][0]
        elif isinstance(data_dict.get("image"), str):
            item_data["cover"] = data_dict.get("image").strip()

        author = data_dict.get("author")
        if isinstance(author, dict):
            item_data["author"] = author.get("name", "")
            item_data["author_bio"] = author.get("description", "")
            author_url = author.get("url", "")
            uid_m = re.search(r'/member/(\d+)', author_url)
            if uid_m:
                item_data["author_id"] = uid_m.group(1)
            if author.get("image"):
                item_data["author_avatar"] = author["image"]

        if isinstance(data_dict.get("interactionStatistic"), list):
            for stat in data_dict["interactionStatistic"]:
                it = stat.get("interactionType", "")
                count = stat.get("userInteractionCount", 0)
                if "Like" in it:
                    item_data["likes"] = int(count)
                elif "View" in it:
                    item_data["views"] = int(count)
    else:
        meta_desc = soup.find("meta", attrs={"name": "description"})
        if meta_desc and meta_desc.get("content"):
            item_data["description"] = meta_desc.get("content").strip()

        cover_img = soup.find("img", alt="Video Cover") or soup.find("img", alt="Article Cover")
        if cover_img and cover_img.get("src"):
            item_data["cover"] = cover_img.get("src")

    # --- __NUXT__ SSR 提取 (补充/覆盖 JSON-LD 没拿到的数据) ---
    ssr_data = parse_nuxt_ssr(html)

    for key in ("author", "author_id", "author_avatar", "author_bio", "author_fans",
                 "likes", "dislikes", "views", "comments", "favorites",
                 "rewards", "danmaku", "duration", "category", "tags"):
        val = ssr_data.get(key)
        if val or (key not in ("author", "author_id", "tags", "category")):
            if key in ("author", "author_id", "author_avatar", "author_bio",
                        "tags", "category"):
                item_data[key] = val or item_data.get(key, "")
            else:
                if val:
                    item_data[key] = val

    if not item_data["title"]:
        return None

    item_data["title"] = clean_text(item_data["title"])
    item_data["description"] = clean_text(item_data["description"])
    item_data["cover"] = clean_text(item_data["cover"])
    item_data["author"] = clean_text(item_data["author"])
    item_data["author_bio"] = clean_text(item_data["author_bio"])
    item_data["tags"] = clean_text(item_data["tags"])
    item_data["category"] = clean_text(item_data["category"])

    return item_data


class ContentScraper:
    """内容爬虫类，负责抓取和解析网页内容"""

    def __init__(self):
        self.client: Optional[httpx.AsyncClient] = None
        self.cookie_manager = cookie_manager

    def _get_static_headers(self) -> Dict[str, str]:
        return {
            "Host": "m.mfuns.net",
            "Cache-Control": "max-age=0",
            "Sec-Ch-Ua": '"Chromium";v="113", "Not-A.Brand";v="24"',
            "Sec-Ch-Ua-Mobile": "?0",
            "Sec-Ch-Ua-Platform": '"Windows"',
            "Upgrade-Insecure-Requests": "1",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7",
            "Sec-Fetch-Site": "same-origin",
            "Sec-Fetch-Mode": "navigate",
            "Sec-Fetch-User": "?1",
            "Sec-Fetch-Dest": "document",
            "Accept-Encoding": "gzip, deflate",
            "Accept-Language": "zh-CN,zh;q=0.9",
        }

    def _get_user_agent(self) -> str:
        return "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/113.0.5672.127 Safari/537.36"

    def _generate_cookies(self) -> Dict[str, str]:
        token = self.cookie_manager.get_active_token()
        cookies = {
            "device_client_type": "web",
            "device_id": self.cookie_manager.device_id or "f282feac-2f2e-4dec-ad39-006d58cba381",
            "device_os_name": "windows",
            "device_os_version": "10.0",
            "device_model": "PC",
        }
        if token:
            cookies["mfuns_token"] = token
        return cookies

    async def get_client(self) -> httpx.AsyncClient:
        if self.client is None or self.client.is_closed:
            cookies = self._generate_cookies()
            cookie_str = "; ".join([f"{k}={v}" for k, v in cookies.items()])

            headers = self._get_static_headers()
            headers["User-Agent"] = self._get_user_agent()
            headers["Cookie"] = cookie_str

            self.client = httpx.AsyncClient(
                timeout=httpx.Timeout(30.0, connect=10.0),
                headers=headers,
                follow_redirects=True
            )
        return self.client

    async def close(self):
        if self.client and not self.client.is_closed:
            await self.client.aclose()
            self.client = None

    async def fetch_page(self, content_type: str, item_id: int) -> Tuple[Optional[int], Optional[Dict[str, Any]]]:
        url = BASE_URL.format(type=content_type, id=item_id)
        client = await self.get_client()

        try:
            response = await client.get(url)
            status_code = response.status_code

            if status_code == 403 or status_code == 401:
                print(f"[Scraper] 检测到风控，尝试刷新Token...")
                self.cookie_manager.token = None
                await self.close()
                token = self.cookie_manager.get_active_token()
                if token:
                    await self.close()
                    client = await self.get_client()
                    response = await client.get(url)
                    status_code = response.status_code

            if status_code != 200:
                return status_code, None

            data = parse_page(response.text, content_type, item_id)
            if data is None:
                return 404, None
            return status_code, data

        except httpx.TimeoutException:
            return 408, None
        except httpx.RequestError as e:
            print(f"[Scraper] 请求错误: {e}")
            return 500, None

    async def crawl_type(self, content_type: str, start_id: int) -> int:
        from database import db_instance

        current_id = start_id
        consecutive_errors = 0
        max_successful_id = start_id - 1

        while consecutive_errors < LOOKAHEAD_THRESHOLD:
            status_code, data = await self.fetch_page(content_type, current_id)

            if status_code == 200 and data:
                consecutive_errors = 0
                max_successful_id = current_id

                await db_instance.insert_item(
                    item_id=data["id"],
                    content_type=data["type"],
                    title=data["title"],
                    url=data["url"],
                    created_at=data["created_at"],
                    description=data.get("description", ""),
                    cover=data.get("cover", ""),
                    author=data.get("author", ""),
                    author_id=data.get("author_id", ""),
                    author_avatar=data.get("author_avatar", ""),
                    author_bio=data.get("author_bio", ""),
                    author_fans=data.get("author_fans", 0),
                    likes=data.get("likes", 0),
                    dislikes=data.get("dislikes", 0),
                    views=data.get("views", 0),
                    comments=data.get("comments", 0),
                    favorites=data.get("favorites", 0),
                    rewards=data.get("rewards", 0),
                    danmaku=data.get("danmaku", 0),
                    duration=data.get("duration", 0),
                    category=data.get("category", ""),
                    tags=data.get("tags", ""),
                )

                await asyncio.sleep(random.uniform(0.5, 1.5))
            else:
                consecutive_errors += 1
                if status_code != 200:
                    await asyncio.sleep(random.uniform(0.5, 1.5))

            current_id += 1

        return max_successful_id


scraper_instance = ContentScraper()
