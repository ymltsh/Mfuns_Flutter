"""
本地内容聚合服务 - 主程序入口
整合数据库、爬虫、调度器和API模块

启动命令:
    python main.py                # 默认 0.0.0.0:8000
    python main.py --host 127.0.0.1 --port 8080
"""
import argparse
import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse

from database import db_instance
from scheduler import scheduler_instance
from scraper import scraper_instance
from api import app as api_app, llm_router, flutter_router
from webui import router as webui_router, HTML_CONTENT as WEBUI_CONTENT, MANAGE_CONTENT
from admin import router as admin_router

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(levelname)s - %(message)s"
)
logger = logging.getLogger(__name__)


async def startup_event():
    """FastAPI启动时执行的事件处理"""
    logger.info("正在初始化数据库...")
    await db_instance.initialize()
    logger.info("数据库初始化完成")

    logger.info("正在启动后台调度器...")
    asyncio.create_task(scheduler_instance.run())
    logger.info("后台调度器已启动")


async def shutdown_event():
    """FastAPI关闭时执行的事件处理"""
    logger.info("正在停止调度器...")
    scheduler_instance.stop()

    logger.info("正在关闭爬虫客户端...")
    await scraper_instance.close()

    logger.info("正在关闭数据库连接...")
    await db_instance.close()

    logger.info("资源清理完成")


app = FastAPI(
    title="本地内容聚合服务",
    description="持续抓取指定网站的Feed、Video、Article内容并提供统一时间线接口",
    version="1.0.0"
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

app.router.add_event_handler("startup", startup_event)
app.router.add_event_handler("shutdown", shutdown_event)

app.include_router(api_app.router)
app.include_router(webui_router)
app.include_router(admin_router)
app.include_router(llm_router)
app.include_router(flutter_router)


@app.get("/", response_class=HTMLResponse)
async def root():
    """根路径，直接返回WebUI内容"""
    return WEBUI_CONTENT


@app.get("/manage", response_class=HTMLResponse)
async def manage():
    """管理后台页面，独立于主UI"""
    return MANAGE_CONTENT


def main():
    """命令行入口：python main.py 直接启动服务"""
    parser = argparse.ArgumentParser(description="本地内容聚合服务")
    parser.add_argument("--host", default="0.0.0.0", help="监听地址 (默认 0.0.0.0)")
    parser.add_argument("--port", type=int, default=8000, help="监听端口 (默认 8000)")
    args = parser.parse_args()

    import uvicorn
    uvicorn.run(
        app,
        host=args.host,
        port=args.port,
        reload=False,
        log_level="info",
    )


if __name__ == "__main__":
    main()
