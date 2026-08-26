"""
调度器模块 - 负责后台轮询任务的管理和执行
使用 asyncio 实现定时增量抓取任务
"""
import asyncio
import logging
import json
import os
from typing import Dict

from database import db_instance
from scraper import scraper_instance
from paths import LAST_JSON_PATH, CONFIG_PATH

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)

CONTENT_TYPES = ["feed", "video", "article"]

DEFAULT_POLL_INTERVAL = 1200


def _load_poll_interval() -> int:
    if os.path.exists(CONFIG_PATH):
        try:
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
                interval = data.get("poll_interval", DEFAULT_POLL_INTERVAL)
                if isinstance(interval, (int, float)) and interval > 0:
                    return int(interval)
        except Exception:
            pass
    return DEFAULT_POLL_INTERVAL


class Scheduler:
    """调度器类，管理后台抓取任务"""

    def __init__(self):
        self.running = False
        self.current_max_ids: Dict[str, int] = {}

    def read_last_json(self) -> Dict[str, int]:
        """从 last.json 读取保存的最大ID"""
        if os.path.exists(LAST_JSON_PATH):
            try:
                with open(LAST_JSON_PATH, "r", encoding="utf-8") as f:
                    data = json.load(f)
                    logger.info(f"从 last.json 读取到: {data}")
                    return data
            except Exception as e:
                logger.warning(f"读取 last.json 失败: {e}")
        return {}

    def save_last_json(self):
        """将当前最大ID保存到 last.json"""
        try:
            with open(LAST_JSON_PATH, "w", encoding="utf-8") as f:
                json.dump(self.current_max_ids, f, indent=2)
            logger.info("已保存到 last.json")
        except Exception as e:
            logger.error(f"保存 last.json 失败: {e}")

    async def initialize_state(self):
        """
        初始化状态：优先从 last.json 读取，其次从数据库获取每种type的当前最大ID
        如果数据库为空，则使用默认起始ID
        """
        logger.info("正在初始化爬虫状态...")

        last_json_data = self.read_last_json()

        for content_type in CONTENT_TYPES:
            if content_type in last_json_data:
                max_id = last_json_data[content_type]
                logger.info(f"{content_type} 使用 last.json 中的ID: {max_id}")
            else:
                max_id = await db_instance.get_max_id(content_type)
                logger.info(f"{content_type} 使用数据库中的ID: {max_id}")
            self.current_max_ids[content_type] = max_id

        logger.info("状态初始化完成")

    async def crawl_all_types(self):
        """并发触发三种类型的内容抓取"""
        logger.info("开始增量抓取...")

        tasks = []
        for content_type in CONTENT_TYPES:
            start_id = self.current_max_ids[content_type] + 1
            task = self.crawl_single_type(content_type, start_id)
            tasks.append(task)

        await asyncio.gather(*tasks)

        # 保存到 last.json
        self.save_last_json()

        logger.info("增量抓取完成")

    async def crawl_single_type(self, content_type: str, start_id: int):
        """
        抓取单个类型的内容

        Args:
            content_type: 内容类型
            start_id: 起始ID
        """
        try:
            logger.info(f"开始抓取 {content_type}，起始ID: {start_id}")
            max_id = await scraper_instance.crawl_type(content_type, start_id)
            self.current_max_ids[content_type] = max_id
            logger.info(f"{content_type} 抓取完成，最大ID: {max_id}")
        except Exception as e:
            logger.error(f"抓取 {content_type} 时发生错误: {e}")

    async def run(self):
        """
        运行调度器的主循环
        启动时先执行一次抓取，然后每隔5分钟执行一次
        """
        self.running = True

        logger.info("调度器启动")

        await self.initialize_state()

        await self.crawl_all_types()

        poll_interval = _load_poll_interval()
        logger.info(f"轮询间隔: {poll_interval}s")

        while self.running:
            await asyncio.sleep(poll_interval)

            if self.running:
                await self.crawl_all_types()

    def stop(self):
        """停止调度器"""
        self.running = False
        logger.info("调度器已停止")


scheduler_instance = Scheduler()
