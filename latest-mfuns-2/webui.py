"""
WebUI 模块 - v2: 真实用户名/头像 + 交互数据展示
网页源码内嵌于本文件（与 templates/ 目录保持同步），打包后无需附带模板文件
标题与副标题从 config.json 的 webui 字段读取
"""
import json
import os

from fastapi import APIRouter
from fastapi.responses import HTMLResponse

from paths import CONFIG_PATH

router = APIRouter(prefix="/webui", tags=["webui"])

DEFAULT_TITLE = "MfunsNew"
DEFAULT_SUBTITLE = "Powered by 微风与少年"

INDEX_TEMPLATE = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>MFUNS NEW</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        :root {
            --ink: #2c2c2c;
            --paper: #f5f0e8;
            --paper-deep: #e8e2d8;
            --red: #e74c3c;
            --blue: #3498db;
            --green: #27ae60;
            --yellow: #f39c12;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC', 'Hiragino Sans GB', 'Microsoft YaHei', sans-serif;
            background-color: var(--paper);
            background-image: url("data:image/svg+xml;utf8,%3Csvg%20xmlns='http://www.w3.org/2000/svg'%20width='220'%20height='220'%3E%3Cfilter%20id='n'%3E%3CfeTurbulence%20type='fractalNoise'%20baseFrequency='0.85'%20numOctaves='2'%20stitchTiles='stitch'/%3E%3CfeColorMatrix%20type='saturate'%20values='0'/%3E%3CfeComponentTransfer%3E%3CfeFuncA%20type='linear'%20slope='0.05'/%3E%3C/feComponentTransfer%3E%3C/filter%3E%3Crect%20width='220'%20height='220'%20filter='url(%23n)'/%3E%3C/svg%3E");
            color: var(--ink); line-height: 1.5;
        }
        .container { max-width: 720px; margin: 0 auto; padding: 0 16px; }
        header {
            background-color: var(--paper);
            padding: 16px 0; position: sticky; top: 0; z-index: 100;
            border-bottom: 2px dashed var(--ink);
        }
        header h1 {
            font-family: Georgia, 'Songti SC', 'Noto Serif SC', 'STSong', SimSun, serif;
            font-size: 20px; font-weight: 700; display: flex; align-items: center; gap: 8px;
            text-decoration: underline wavy var(--red);
            text-decoration-thickness: 2px; text-underline-offset: 5px;
        }
        header .subtitle {
            font-size: 12px; color: #6b6b6b; margin-left: auto;
            text-decoration: none; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC', 'Microsoft YaHei', sans-serif;
        }
        .stats-bar { display: grid; grid-template-columns: repeat(3, 1fr); gap: 12px; margin: 20px 0; }
        .stat-card {
            background-color: var(--paper-deep);
            border: 2px dashed var(--ink); border-radius: 2px;
            padding: 16px; text-align: center; position: relative; overflow: hidden;
            box-shadow: 2px 2px 0 rgba(44,44,44,0.3);
            transform: rotate(-1deg);
            transition: background-color 120ms ease, box-shadow 120ms ease, transform 120ms ease;
        }
        .stat-card:nth-child(2) { transform: rotate(1deg); }
        .stat-card:nth-child(3) { transform: rotate(-0.7deg); }
        .stat-card::after {
            content: ''; position: absolute; inset: 0; pointer-events: none;
            background-image: url("data:image/svg+xml;utf8,%3Csvg%20xmlns='http://www.w3.org/2000/svg'%20width='9'%20height='9'%3E%3Cpath%20d='M0%209L9%200'%20stroke='%232c2c2c'%20stroke-width='1.2'/%3E%3C/svg%3E");
            opacity: 0.07;
            transition: opacity 120ms ease;
        }
        .stat-card:hover { background-color: var(--ink); box-shadow: 2px 2px 0 rgba(44,44,44,0.5); }
        .stat-card:hover::after { opacity: 0; }
        .stat-card:hover .stat-value, .stat-card:hover .stat-label { color: var(--paper); }
        .stat-value {
            font-family: Georgia, 'Songti SC', 'Noto Serif SC', serif;
            font-size: 22px; font-weight: 700; color: var(--ink);
            transition: color 120ms ease;
        }
        .stat-label { color: #6b6b6b; font-size: 12px; margin-top: 4px; transition: color 120ms ease; }
        .filters {
            background-color: var(--paper);
            border: 2px dashed var(--ink); border-radius: 2px;
            padding: 12px 16px; margin-bottom: 14px;
            display: flex; gap: 12px; align-items: center; flex-wrap: wrap;
            box-shadow: 2px 2px 0 rgba(44,44,44,0.3);
            transform: rotate(0.5deg);
        }
        .filters label { font-weight: 600; color: var(--ink); font-size: 14px; }
        .filters select {
            padding: 8px 32px 8px 12px; background-color: var(--paper-deep);
            border: 2px dashed var(--ink); border-radius: 2px;
            font-size: 14px; color: var(--ink); font-family: inherit; appearance: none;
            background-image: url("data:image/svg+xml;charset=US-ASCII,%3Csvg%20xmlns='http://www.w3.org/2000/svg'%20width='24'%20height='24'%20viewBox='0%200%2024%2024'%20fill='none'%20stroke='%232c2c2c'%20stroke-width='2'%20stroke-linecap='round'%20stroke-linejoin='round'%3E%3Cpolyline%20points='6%209%2012%2015%2018%209'/%3E%3C/svg%3E");
            background-repeat: no-repeat; background-position: right 8px center; background-size: 14px; outline: none;
            transition: background-color 120ms ease;
        }
        .filters select:focus-visible { outline: 2px dashed var(--blue); outline-offset: 2px; }
        .filters button {
            padding: 8px 20px; background-color: var(--ink); color: var(--paper);
            border: 2px dashed var(--ink); border-radius: 2px;
            cursor: pointer; font-size: 14px; font-weight: 600; margin-left: auto;
            box-shadow: 2px 2px 0 rgba(44,44,44,0.3);
            transition: box-shadow 120ms ease, transform 120ms ease, opacity 120ms ease;
        }
        .filters button:hover { opacity: 0.9; }
        .filters button:active { box-shadow: none; transform: translate(2px, 2px) rotate(0.5deg); }
        .filters button:focus-visible { outline: 2px dashed var(--blue); outline-offset: 2px; }
        .feed { display: flex; flex-direction: column; gap: 14px; padding-bottom: 48px; }
        .post-card {
            background-color: var(--paper);
            border: 2px dashed var(--ink); border-radius: 2px;
            padding: 16px; position: relative; overflow: hidden;
            box-shadow: 2px 2px 0 rgba(44,44,44,0.3);
            cursor: pointer; text-decoration: none; color: inherit; display: block;
            transform: rotate(-0.6deg);
            transition: background-color 150ms ease, box-shadow 150ms ease, transform 150ms ease;
        }
        .post-card:nth-child(even) { transform: rotate(0.7deg); }
        .post-card::after {
            content: ''; position: absolute; inset: 0; pointer-events: none;
            background-image: url("data:image/svg+xml;utf8,%3Csvg%20xmlns='http://www.w3.org/2000/svg'%20width='9'%20height='9'%3E%3Cpath%20d='M0%209L9%200'%20stroke='%232c2c2c'%20stroke-width='1.2'/%3E%3C/svg%3E");
            opacity: 0.05;
            transition: opacity 150ms ease;
        }
        .post-card:hover {
            background-color: var(--ink);
            box-shadow: 2px 2px 0 rgba(44,44,44,0.5);
        }
        .post-card:hover::after { opacity: 0; }
        .post-card:hover .user-name, .post-card:hover .post-meta,
        .post-card:hover .post-content, .post-card:hover .post-stats { color: var(--paper); }
        .post-card:hover .post-tag { border-color: var(--paper); color: var(--paper); }
        .post-card:hover .more-btn { color: var(--paper); }
        .post-card:active { box-shadow: none; transform: rotate(1.2deg) translate(2px, 2px); }
        .post-card:focus-visible { outline: 2px dashed var(--blue); outline-offset: 2px; }
        .post-header { display: flex; align-items: center; gap: 12px; margin-bottom: 12px; }
        .avatar {
            width: 44px; height: 44px; object-fit: cover; background-color: var(--paper-deep);
            border: 2px dashed var(--ink); border-radius: 2px; flex-shrink: 0;
            transform: rotate(-2deg);
        }
        .user-info { flex: 1; min-width: 0; }
        .user-name {
            font-family: Georgia, 'Songti SC', 'Noto Serif SC', serif;
            font-size: 15px; font-weight: 700; color: var(--ink);
            transition: color 150ms ease;
        }
        .user-fans { font-size: 12px; color: #8a8a8a; margin-left: 6px; }
        .post-meta { font-size: 13px; color: #6b6b6b; margin-top: 2px; transition: color 150ms ease; }
        .more-btn {
            color: #8a8a8a; font-size: 20px; cursor: pointer; padding: 4px 8px;
            line-height: 1; border-radius: 2px; position: relative; z-index: 2;
            transition: color 150ms ease, background-color 150ms ease;
        }
        .more-btn:hover { color: var(--ink); background-color: var(--paper-deep); }
        .more-btn:focus-visible { outline: 2px dashed var(--blue); outline-offset: 2px; }
        .more-menu {
            position: absolute; top: 48px; right: 12px;
            background-color: var(--paper);
            border: 2px dashed var(--ink); border-radius: 2px;
            box-shadow: 2px 2px 0 rgba(44,44,44,0.3);
            padding: 6px 0; min-width: 140px; z-index: 10; display: none;
            transform: rotate(-0.5deg);
        }
        .more-menu.show { display: block; }
        .more-menu-item { padding: 10px 16px; font-size: 14px; color: var(--ink); cursor: pointer; white-space: nowrap; }
        .more-menu-item:hover { background-color: var(--ink); color: var(--paper); }
        .post-content {
            font-family: Georgia, 'Songti SC', 'Noto Serif SC', serif;
            font-size: 15px; line-height: 1.7; word-break: break-word; margin-bottom: 10px;
            transition: color 150ms ease;
        }
        .post-tags { display: flex; gap: 6px; flex-wrap: wrap; margin-bottom: 8px; }
        .post-tag {
            font-size: 12px; padding: 3px 10px; border-radius: 2px;
            background-color: transparent; color: var(--blue);
            border: 2px dashed var(--blue);
            transition: color 150ms ease, border-color 150ms ease;
        }
        .post-stats {
            display: flex; gap: 16px; font-size: 13px; color: #6b6b6b;
            padding-top: 10px; border-top: 2px dashed rgba(44,44,44,0.35); flex-wrap: wrap;
            transition: color 150ms ease;
        }
        .post-stats span { display: flex; align-items: center; gap: 4px; }
        .post-cover {
            width: 100%; max-height: 300px; object-fit: cover;
            border-radius: 2px; border: 2px dashed rgba(44,44,44,0.4); margin: 10px 0;
        }
        .loading, .empty {
            text-align: center; padding: 48px 20px; color: #6b6b6b; font-size: 15px;
            background-color: var(--paper); border: 2px dashed var(--ink); border-radius: 2px;
            box-shadow: 2px 2px 0 rgba(44,44,44,0.3); transform: rotate(-0.5deg);
        }
        .error {
            background-color: var(--paper); color: var(--red);
            border: 2px dashed var(--red); border-radius: 2px;
            padding: 16px; margin-bottom: 12px; font-size: 14px;
            box-shadow: 2px 2px 0 rgba(231,76,60,0.25);
        }
        @media (max-width: 600px) {
            .container { padding: 0 12px; }
            .post-card { padding: 14px; }
            .stats-bar { gap: 8px; }
            .stat-card { padding: 12px; }
            .filters { margin: 0 -12px 14px -12px; }
        }
        @media (prefers-reduced-motion: reduce) {
            *, *::before, *::after {
                transition-duration: 0.01ms !important;
                animation-duration: 0.01ms !important;
            }
        }
    </style>
</head>
<body>
    <header>
        <div class="container">
            <h1>{{TITLE}} <span class="subtitle">{{SUBTITLE}}</span></h1>
        </div>
    </header>
    <div class="container">
        <div class="stats-bar" id="statsBar">
            <div class="stat-card"><div class="stat-value" id="feedCount">-</div><div class="stat-label">动态</div></div>
            <div class="stat-card"><div class="stat-value" id="videoCount">-</div><div class="stat-label">视频</div></div>
            <div class="stat-card"><div class="stat-value" id="articleCount">-</div><div class="stat-label">文章</div></div>
        </div>
        <div class="filters">
            <label>类型</label>
            <select id="typeFilter">
                <option value="">全部</option>
                <option value="feed">动态</option>
                <option value="video">视频</option>
                <option value="article">文章</option>
            </select>
            <label>数量</label>
            <select id="limitSelect">
                <option value="20">20</option>
                <option value="50">50</option>
                <option value="100" selected>100</option>
                <option value="500">500</option>
            </select>
            <button onclick="loadItems()">刷新内容</button>
        </div>
        <div class="feed" id="feed"><div class="loading">加载中...</div></div>
    </div>
    <script>
        const API_BASE = '';
        const DEFAULT_AVATAR = 'https://ymltsh.top/staticSource/default_avatar.webp';

        function h(text) {
            if (!text) return '';
            var div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }

        function formatRelativeTime(timestamp) {
            var now = Date.now() / 1000;
            var diff = now - timestamp;
            if (diff < 60) return '刚刚';
            if (diff < 3600) return Math.floor(diff / 60) + '分钟前';
            if (diff < 86400) return Math.floor(diff / 3600) + '小时前';
            if (diff < 604800) return Math.floor(diff / 86400) + '天前';
            var d = new Date(timestamp * 1000);
            return d.toLocaleString('zh-CN', { month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' });
        }

        function formatCount(n) {
            if (!n) return '';
            if (n >= 10000) return (n / 10000).toFixed(1) + '万';
            return n.toString();
        }

        function getTypeName(type) {
            return {'feed':'动态','video':'视频','article':'文章'}[type] || '';
        }

        var ACTIVE_MENU = null;

        function createPostCard(item) {
            var card = document.createElement('a');
            card.className = 'post-card';
            card.href = item.url;
            card.target = '_blank';
            card.dataset.url = item.url;

            // Header
            var header = document.createElement('div');
            header.className = 'post-header';

            var avatar = document.createElement('img');
            avatar.className = 'avatar';
            avatar.src = item.author_avatar || DEFAULT_AVATAR;
            avatar.onerror = function() { this.src = DEFAULT_AVATAR; };
            header.appendChild(avatar);

            var userInfo = document.createElement('div');
            userInfo.className = 'user-info';

            var userName = document.createElement('div');
            userName.className = 'user-name';
            userName.innerHTML = h(item.author || '未知作者');
            userInfo.appendChild(userName);

            var meta = document.createElement('div');
            meta.className = 'post-meta';
            var metaText = formatRelativeTime(item.created_at) + ' · ' + getTypeName(item.type);
            if (item.author_fans) metaText += ' · ' + formatCount(item.author_fans) + '粉丝';
            meta.textContent = metaText;
            userInfo.appendChild(meta);

            header.appendChild(userInfo);

            // More button
            var moreBtn = document.createElement('span');
            moreBtn.className = 'more-btn';
            moreBtn.textContent = '...';
            moreBtn.onclick = function(e) {
                e.preventDefault();
                e.stopPropagation();
                toggleMenu(this);
            };
            header.appendChild(moreBtn);

            // More menu
            var menu = document.createElement('div');
            menu.className = 'more-menu';
            var menuItem = document.createElement('div');
            menuItem.className = 'more-menu-item';
            menuItem.textContent = '复制链接';
            menuItem.onclick = function(e) {
                e.stopPropagation();
                copyUrl(item.url);
            };
            menu.appendChild(menuItem);
            header.appendChild(menu);

            card.appendChild(header);

            // Tags
            if (item.tags) {
                var tagNames = item.tags.split(',').filter(function(t) { return t.trim(); });
                if (tagNames.length > 0) {
                    var tagsDiv = document.createElement('div');
                    tagsDiv.className = 'post-tags';
                    tagNames.forEach(function(t) {
                        var tag = document.createElement('span');
                        tag.className = 'post-tag';
                        tag.textContent = t.trim();
                        tagsDiv.appendChild(tag);
                    });
                    card.appendChild(tagsDiv);
                }
            }

            // Content
            var content = document.createElement('div');
            content.className = 'post-content';

            var skipTitles = ['动态详情', '加载中', '视频详情', '文章详情'];
            if (item.title && skipTitles.indexOf(item.title) === -1) {
                var titleEl = document.createElement('div');
                titleEl.style.cssText = 'font-weight:700;margin-bottom:6px;font-family:Georgia,"Songti SC","Noto Serif SC",serif;';
                titleEl.textContent = item.title;
                content.appendChild(titleEl);
            }
            if (item.description) {
                var desc = document.createElement('div');
                desc.textContent = item.description;
                content.appendChild(desc);
            }
            if (item.cover) {
                var coverImg = document.createElement('img');
                coverImg.className = 'post-cover';
                coverImg.src = item.cover;
                coverImg.alt = 'cover';
                coverImg.loading = 'lazy';
                content.appendChild(coverImg);
            }
            card.appendChild(content);

            // Stats
            var statsEl = document.createElement('div');
            statsEl.className = 'post-stats';

            if (item.views) statsEl.appendChild(statSpan('👁', formatCount(item.views)));
            if (item.likes) statsEl.appendChild(statSpan('❤', formatCount(item.likes)));
            if (item.comments) statsEl.appendChild(statSpan('💬', formatCount(item.comments)));
            if (item.favorites) statsEl.appendChild(statSpan('⭐', formatCount(item.favorites)));
            if (item.rewards) statsEl.appendChild(statSpan('🎁', formatCount(item.rewards)));
            if (item.category) statsEl.appendChild(statSpan('📂', h(item.category)));
            if (item.duration) {
                var m = Math.floor(item.duration / 60);
                var s = String(item.duration % 60).padStart(2, '0');
                statsEl.appendChild(statSpan('⏱', m + ':' + s));
            }
            if (statsEl.children.length > 0) {
                card.appendChild(statsEl);
            }

            return card;
        }

        function statSpan(icon, text) {
            var span = document.createElement('span');
            span.textContent = icon + ' ' + text;
            return span;
        }

        function toggleMenu(btn) {
            var menu = btn.parentNode.querySelector('.more-menu');
            if (!menu) return;
            if (ACTIVE_MENU && ACTIVE_MENU !== menu) ACTIVE_MENU.classList.remove('show');
            menu.classList.toggle('show');
            ACTIVE_MENU = menu.classList.contains('show') ? menu : null;
        }

        function copyUrl(url) {
            if (navigator.clipboard) {
                navigator.clipboard.writeText(url).then(function() { showToast('链接已复制'); }).catch(function() {});
            }
            if (ACTIVE_MENU) { ACTIVE_MENU.classList.remove('show'); ACTIVE_MENU = null; }
        }

        function showToast(msg) {
            var t = document.querySelector('.toast-msg');
            if (t) t.remove();
            t = document.createElement('div');
            t.className = 'toast-msg';
            t.textContent = msg;
            t.style.cssText = 'position:fixed;bottom:80px;left:50%;transform:translateX(-50%) rotate(-1deg);background:#2c2c2c;color:#f5f0e8;border:2px dashed #f5f0e8;border-radius:2px;padding:10px 20px;font-size:14px;z-index:999;opacity:0;transition:opacity 0.15s;';
            document.body.appendChild(t);
            requestAnimationFrame(function() { t.style.opacity = '1'; });
            setTimeout(function() { t.style.opacity = '0'; setTimeout(function() { t.remove(); }, 300); }, 1500);
        }

        document.addEventListener('click', function(e) {
            if (ACTIVE_MENU && !e.target.closest('.more-btn') && !e.target.closest('.more-menu')) {
                ACTIVE_MENU.classList.remove('show');
                ACTIVE_MENU = null;
            }
        });

        async function loadStats() {
            try {
                var res = await fetch(API_BASE + '/stats');
                if (!res.ok) return;
                var data = await res.json();
                document.getElementById('feedCount').textContent = data.feed || 0;
                document.getElementById('videoCount').textContent = data.video || 0;
                document.getElementById('articleCount').textContent = data.article || 0;
            } catch (e) {}
        }

        async function loadItems() {
            var feed = document.getElementById('feed');
            feed.innerHTML = '<div class="loading">加载中...</div>';
            var type = document.getElementById('typeFilter').value;
            var limit = document.getElementById('limitSelect').value;
            try {
                var url = API_BASE + '/latest?limit=' + limit;
                if (type) url += '&type=' + type;
                var res = await fetch(url);
                if (!res.ok) throw new Error('HTTP ' + res.status);
                var items = await res.json();
                if (!items || items.length === 0) {
                    feed.innerHTML = '<div class="empty">暂无内容</div>';
                    return;
                }
                feed.innerHTML = '';
                items.forEach(function(item) {
                    feed.appendChild(createPostCard(item));
                });
            } catch (e) {
                feed.innerHTML = '<div class="error">加载失败: ' + e.message + '</div>';
            }
        }

        loadStats();
        loadItems();
    </script>
</body>
</html>
"""

MANAGE_TEMPLATE = """<!DOCTYPE html>
<html lang="zh-CN">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{{TITLE}} 管理后台</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        :root {
            --ink: #2c2c2c;
            --paper: #f5f0e8;
            --paper-deep: #e8e2d8;
            --red: #e74c3c;
            --blue: #3498db;
            --green: #27ae60;
            --yellow: #f39c12;
        }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'PingFang SC', 'Hiragino Sans GB', 'Microsoft YaHei', sans-serif;
            background-color: var(--paper);
            background-image: url("data:image/svg+xml;utf8,%3Csvg%20xmlns='http://www.w3.org/2000/svg'%20width='220'%20height='220'%3E%3Cfilter%20id='n'%3E%3CfeTurbulence%20type='fractalNoise'%20baseFrequency='0.85'%20numOctaves='2'%20stitchTiles='stitch'/%3E%3CfeColorMatrix%20type='saturate'%20values='0'/%3E%3CfeComponentTransfer%3E%3CfeFuncA%20type='linear'%20slope='0.05'/%3E%3C/feComponentTransfer%3E%3C/filter%3E%3Crect%20width='220'%20height='220'%20filter='url(%23n)'/%3E%3C/svg%3E");
            color: var(--ink); line-height: 1.5;
        }
        .container { max-width: 1200px; margin: 0 auto; padding: 24px 16px; }
        header {
            background-color: var(--paper);
            padding: 14px 0; border-bottom: 2px dashed var(--ink);
        }
        header .container { display: flex; align-items: center; gap: 12px; padding-top: 0; padding-bottom: 0; }
        header h1 {
            font-family: Georgia, 'Songti SC', 'Noto Serif SC', 'STSong', SimSun, serif;
            font-size: 18px; font-weight: 700;
            text-decoration: underline wavy var(--red);
            text-decoration-thickness: 2px; text-underline-offset: 4px;
        }
        .user-area { margin-left: auto; display: flex; gap: 8px; align-items: center; font-size: 13px; color: #6b6b6b; }
        .card {
            background-color: var(--paper);
            border: 2px dashed var(--ink); border-radius: 2px;
            padding: 20px; margin-bottom: 16px; position: relative;
            box-shadow: 2px 2px 0 rgba(44,44,44,0.3);
            transform: rotate(-0.4deg);
        }
        .card:nth-of-type(2n) { transform: rotate(0.3deg); }
        .card:nth-of-type(3n) { transform: rotate(0.6deg); }
        .card::after {
            content: ''; position: absolute; inset: 0; pointer-events: none;
            background-image: url("data:image/svg+xml;utf8,%3Csvg%20xmlns='http://www.w3.org/2000/svg'%20width='9'%20height='9'%3E%3Cpath%20d='M0%209L9%200'%20stroke='%232c2c2c'%20stroke-width='1.2'/%3E%3C/svg%3E");
            opacity: 0.05;
        }
        .card h2 {
            font-family: Georgia, 'Songti SC', 'Noto Serif SC', serif;
            font-size: 15px; font-weight: 700; margin-bottom: 14px; display: inline-block;
            text-decoration: underline wavy rgba(231,76,60,0.85);
            text-decoration-thickness: 1.5px; text-underline-offset: 4px;
        }
        .card h3 {
            font-family: Georgia, 'Songti SC', 'Noto Serif SC', serif;
            font-size: 13px; font-weight: 700; margin: 16px 0 8px; color: #6b6b6b;
        }
        .row { display: flex; gap: 8px; align-items: center; margin-bottom: 10px; flex-wrap: wrap; }
        input, select {
            padding: 8px 12px; border: 2px dashed var(--ink); border-radius: 2px;
            font-size: 14px; outline: none; background-color: var(--paper-deep); color: var(--ink); font-family: inherit;
            transition: background-color 120ms ease;
        }
        input::placeholder { color: #8a8a8a; }
        input:focus, select:focus { background-color: var(--paper); outline: 2px dashed var(--blue); outline-offset: 2px; }
        input.wide { flex: 1; min-width: 160px; }
        input.id-input { width: 120px; }
        button {
            padding: 8px 18px; border: 2px dashed var(--ink); border-radius: 2px;
            background-color: transparent; color: var(--ink);
            font-size: 14px; font-weight: 600; cursor: pointer; min-height: 44px;
            box-shadow: 1px 1px 0 rgba(44,44,44,0.3);
            transition: background-color 120ms ease, color 120ms ease, box-shadow 120ms ease, transform 120ms ease, opacity 120ms ease;
        }
        button:hover { background-color: var(--ink); color: var(--paper); }
        button:active { box-shadow: none; transform: translate(2px, 2px) rotate(0.5deg); }
        button:focus-visible { outline: 2px dashed var(--blue); outline-offset: 2px; }
        button:disabled { opacity: 0.45; cursor: not-allowed; }
        button.primary { background-color: var(--ink); color: var(--paper); }
        button.primary:hover { opacity: 0.9; background-color: var(--ink); }
        button.sm { padding: 4px 12px; font-size: 13px; min-height: 34px; }
        button.danger { color: var(--red); border-color: var(--red); box-shadow: 1px 1px 0 rgba(231,76,60,0.3); }
        button.danger:hover { background-color: var(--red); border-color: var(--red); color: var(--paper); }
        .msg { font-size: 12px; color: var(--red); min-height: 18px; margin-top: 8px; }
        .list { list-style: none; display: flex; flex-wrap: wrap; gap: 8px; }
        .list li {
            background-color: var(--paper-deep);
            border: 2px dashed rgba(44,44,44,0.5); border-radius: 2px;
            padding: 6px 12px; font-size: 13px; display: flex; align-items: center; gap: 8px;
        }
        .list li.empty { color: #8a8a8a; background: none; border-style: none; padding: 4px 0; }
        .list li.search-item {
            width: 100%; display: flex; align-items: center; gap: 12px;
            padding: 10px 12px; background-color: var(--paper);
        }
        .search-info { flex: 1; min-width: 0; }
        .search-title {
            font-family: Georgia, 'Songti SC', 'Noto Serif SC', serif;
            font-size: 13px; font-weight: 700;
            overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
        }
        .search-meta { font-size: 12px; color: #6b6b6b; margin-top: 2px; }
        .remove-x { cursor: pointer; color: #8a8a8a; font-size: 16px; line-height: 1; padding: 0 2px; }
        .remove-x:hover { color: var(--red); }
        .login-box { max-width: 320px; margin: 80px auto 0; transform: rotate(-0.8deg); }
        #panelCard {
            display: grid; grid-template-columns: 1fr; gap: 16px;
            align-items: start;
        }
        #panelCard[hidden] { display: none; }
        #panelCard > .card { margin-bottom: 0; }
        @media (min-width: 900px) {
            #panelCard { grid-template-columns: repeat(2, 1fr); }
        }
        .login-box h2 {
            font-size: 17px; margin-bottom: 16px; text-align: center; display: block;
            text-decoration: underline wavy var(--red);
            text-decoration-thickness: 2px; text-underline-offset: 4px;
        }
        .login-box input { width: 100%; margin-bottom: 12px; min-height: 44px; }
        .login-box button { width: 100%; }
        @media (prefers-reduced-motion: reduce) {
            *, *::before, *::after {
                transition-duration: 0.01ms !important;
                animation-duration: 0.01ms !important;
            }
        }
    </style>
</head>
<body>
    <header>
        <div class="container">
            <h1>{{TITLE}} 管理后台</h1>
            <div class="user-area" id="userArea"></div>
        </div>
    </header>
    <div class="container">
        <div class="card login-box" id="loginCard">
            <h2>管理员登录</h2>
            <div><input id="loginUser" placeholder="用户名" autocomplete="username" /></div>
            <div><input id="loginPass" type="password" placeholder="密码" autocomplete="current-password" /></div>
            <button class="primary" id="loginBtn" onclick="doLogin()">登录</button>
            <div class="msg" id="loginMsg"></div>
        </div>

        <div id="panelCard" hidden>
            <div class="card">
                <h2>内容检索屏蔽</h2>
                <div class="row">
                    <input class="wide" id="searchInput" placeholder="输入关键词检索内容（标题/简介/标签/作者）" />
                    <button class="primary" onclick="searchItems()">搜索</button>
                </div>
                <ul class="list" id="searchList"><li class="empty">输入关键词检索要屏蔽的内容</li></ul>
            </div>

            <div class="card">
                <h2>被标记内容</h2>
                <div class="row"><span class="search-meta">被用户标记但未达 5 人的内容，可手动屏蔽</span></div>
                <ul class="list" id="markedList"><li class="empty">加载中...</li></ul>
            </div>

            <div class="card">
                <h2>屏蔽词管理</h2>
                <div class="row">
                    <input class="wide" id="wordInput" placeholder="输入要屏蔽的词" />
                    <button class="primary" onclick="addWord()">添加</button>
                </div>
                <ul class="list" id="wordList"><li class="empty">加载中...</li></ul>
            </div>

            <div class="card">
                <h2>屏蔽内容管理</h2>
                <div class="row">
                    <select id="blockType">
                        <option value="feed">动态</option>
                        <option value="video">视频</option>
                        <option value="article">文章</option>
                    </select>
                    <input class="id-input" id="blockId" placeholder="内容ID" />
                    <button class="primary" onclick="blockItem()">屏蔽</button>
                </div>
                <ul class="list" id="blockedList"><li class="empty">加载中...</li></ul>
            </div>
        </div>
    </div>
    <script>
        var TYPE_NAMES = {'feed': '动态', 'video': '视频', 'article': '文章'};
        var IS_ADMIN = false;
        var SEARCH_LIMIT = 200;
        var searchOffset = 0;

        function h(text) {
            if (!text) return '';
            var div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }

        function showLogin() {
            document.getElementById('loginCard').hidden = false;
            document.getElementById('panelCard').hidden = true;
            document.getElementById('loginUser').focus();
        }

        function showPanel() {
            document.getElementById('loginCard').hidden = true;
            document.getElementById('panelCard').hidden = false;
            loadBanned();
        }

        async function checkSession() {
            try {
                var res = await fetch('/admin/session', {credentials: 'same-origin'});
                var data = await res.json();
                IS_ADMIN = !!data.logged_in;
                var name = data.username || '';
                if (IS_ADMIN) {
                    showPanel();
                    renderUserArea(name);
                } else {
                    showLogin();
                }
            } catch (e) {
                showLogin();
            }
        }

        function renderUserArea(name) {
            var area = document.getElementById('userArea');
            area.innerHTML = '';
            var span = document.createElement('span');
            span.textContent = name;
            area.appendChild(span);
            var logoutBtn = document.createElement('button');
            logoutBtn.className = 'sm';
            logoutBtn.textContent = '退出';
            logoutBtn.onclick = function() { doLogout(); };
            area.appendChild(logoutBtn);
        }

        async function doLogin() {
            var user = document.getElementById('loginUser').value.trim();
            var pass = document.getElementById('loginPass').value;
            var btn = document.getElementById('loginBtn');
            var msgEl = document.getElementById('loginMsg');
            msgEl.textContent = '';
            btn.disabled = true;
            try {
                var res = await fetch('/admin/login', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({username: user, password: pass}),
                    credentials: 'same-origin'
                });
                if (!res.ok) {
                    var err = await res.json().catch(function() { return {}; });
                    msgEl.textContent = err.detail || '登录失败';
                    return;
                }
                var data = await res.json();
                IS_ADMIN = true;
                showPanel();
                renderUserArea(data.username);
            } catch (e) {
                msgEl.textContent = '请求失败: ' + e.message;
            } finally {
                btn.disabled = false;
            }
        }

        async function doLogout() {
            try {
                await fetch('/admin/logout', {method: 'POST', credentials: 'same-origin'});
            } catch (e) {}
            IS_ADMIN = false;
            showLogin();
        }

        async function loadBanned() {
            try {
                var res = await fetch('/admin/banned', {credentials: 'same-origin'});
                if (!res.ok) return;
                var data = await res.json();
                renderWords(data.words || []);
                renderBlockedItems(data.items || []);
                loadMarked();
            } catch (e) {}
        }

        async function loadMarked() {
            try {
                var res = await fetch('/admin/marked', {credentials: 'same-origin'});
                if (!res.ok) return;
                var data = await res.json();
                renderMarkedItems(data.items || []);
            } catch (e) {}
        }

        function renderMarkedItems(items) {
            var list = document.getElementById('markedList');
            list.innerHTML = '';
            if (items.length === 0) {
                list.innerHTML = '<li class="empty">暂无被标记内容</li>';
                return;
            }
            items.forEach(function(it) {
                var li = document.createElement('li');
                li.className = 'search-item';
                var info = document.createElement('div');
                info.className = 'search-info';
                var title = document.createElement('div');
                title.className = 'search-title';
                title.textContent = TYPE_NAMES[it.type] + ' · ' +
                    (it.title || '#' + it.id) + '（' + it.mark_count + '/5 人标记）';
                info.appendChild(title);
                li.appendChild(info);
                var btn = document.createElement('button');
                btn.className = 'primary sm';
                btn.textContent = '屏蔽';
                btn.onclick = function() { blockFromSearch(it, li); };
                li.appendChild(btn);
                list.appendChild(li);
            });
        }

        function renderWords(words) {
            var list = document.getElementById('wordList');
            list.innerHTML = '';
            if (words.length === 0) {
                list.innerHTML = '<li class="empty">暂无屏蔽词</li>';
                return;
            }
            words.forEach(function(word) {
                var li = document.createElement('li');
                var text = document.createElement('span');
                text.textContent = word;
                li.appendChild(text);
                var remove = document.createElement('span');
                remove.className = 'remove-x';
                remove.textContent = '×';
                remove.onclick = function() { removeWord(word); };
                li.appendChild(remove);
                list.appendChild(li);
            });
        }

        function renderBlockedItems(items) {
            var list = document.getElementById('blockedList');
            list.innerHTML = '';
            if (items.length === 0) {
                list.innerHTML = '<li class="empty">暂无屏蔽内容</li>';
                return;
            }
            items.forEach(function(it) {
                var li = document.createElement('li');
                var text = document.createElement('span');
                var title = it.title ? it.title : '#' + it.id;
                text.textContent = TYPE_NAMES[it.type] + ' · ' + title;
                li.appendChild(text);
                var remove = document.createElement('span');
                remove.className = 'remove-x';
                remove.textContent = '×';
                remove.onclick = function() { unblockItem(it); };
                li.appendChild(remove);
                list.appendChild(li);
            });
        }

        async function searchItems() {
            var q = document.getElementById('searchInput').value.trim();
            var list = document.getElementById('searchList');
            if (!q) return;
            searchOffset = 0;
            list.innerHTML = '<li class="empty">搜索中...</li>';
            await fetchSearch(q, true);
        }

        async function loadMoreSearch() {
            var q = document.getElementById('searchInput').value.trim();
            await fetchSearch(q, false);
        }

        async function fetchSearch(q, firstPage) {
            var list = document.getElementById('searchList');
            try {
                var res = await fetch('/admin/search?q=' + encodeURIComponent(q) +
                    '&limit=' + SEARCH_LIMIT + '&offset=' + searchOffset,
                    {credentials: 'same-origin'});
                if (!res.ok) {
                    if (firstPage) list.innerHTML = '<li class="empty">搜索失败</li>';
                    return;
                }
                var data = await res.json();
                var items = data.items || [];
                if (items.length === 0) {
                    if (firstPage) {
                        list.innerHTML = '<li class="empty">无匹配内容</li>';
                    } else {
                        removeLoadMore();
                    }
                    return;
                }
                searchOffset += items.length;
                if (firstPage) list.innerHTML = '';
                items.forEach(function(it) {
                    list.appendChild(searchItemEl(it));
                });
                if (items.length === SEARCH_LIMIT) {
                    appendLoadMore();
                } else {
                    removeLoadMore();
                }
            } catch (e) {
                if (firstPage) list.innerHTML = '<li class="empty">请求失败</li>';
            }
        }

        function appendLoadMore() {
            removeLoadMore();
            var li = document.createElement('li');
            li.className = 'search-item';
            li.id = 'loadMoreLi';
            var btn = document.createElement('button');
            btn.className = 'primary sm';
            btn.textContent = '加载更多';
            btn.onclick = function() {
                btn.disabled = true;
                btn.textContent = '加载中...';
                loadMoreSearch();
            };
            li.appendChild(btn);
            document.getElementById('searchList').appendChild(li);
        }

        function removeLoadMore() {
            var el = document.getElementById('loadMoreLi');
            if (el) el.remove();
        }

        function searchItemEl(it) {
            var li = document.createElement('li');
            li.className = 'search-item';
            var info = document.createElement('div');
            info.className = 'search-info';
            var title = document.createElement('div');
            title.className = 'search-title';
            title.textContent = (TYPE_NAMES[it.type] || it.type) + ' · ' + (it.title || '#' + it.id);
            info.appendChild(title);
            var meta = document.createElement('div');
            meta.className = 'search-meta';
            meta.textContent = (it.author || '未知作者') + ' · ' + new Date(it.created_at * 1000).toLocaleString('zh-CN');
            info.appendChild(meta);
            li.appendChild(info);
            var btn = document.createElement('button');
            if (it.blocked) {
                btn.textContent = '已屏蔽';
                btn.disabled = true;
            } else {
                btn.className = 'primary sm';
                btn.textContent = '屏蔽';
                btn.onclick = function() { blockFromSearch(it, li); };
            }
            li.appendChild(btn);
            return li;
        }

        async function blockFromSearch(it, li) {
            try {
                var res = await fetch('/admin/banned/items', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({id: it.id, type: it.type}),
                    credentials: 'same-origin'
                });
                if (!res.ok) {
                    var err = await res.json().catch(function() { return {}; });
                    alert(err.detail || '屏蔽失败');
                    return;
                }
                it.blocked = true;
                var btn = li.querySelector('button');
                btn.textContent = '已屏蔽';
                btn.disabled = true;
                btn.className = '';
                loadBanned();
            } catch (e) {}
        }

        async function addWord() {
            var input = document.getElementById('wordInput');
            var word = input.value.trim();
            if (!word) return;
            try {
                var res = await fetch('/admin/banned/words', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({word: word}),
                    credentials: 'same-origin'
                });
                if (!res.ok) {
                    var err = await res.json().catch(function() { return {}; });
                    alert(err.detail || '添加失败');
                    return;
                }
                input.value = '';
                renderWords((await res.json()).words || []);
            } catch (e) {}
        }

        async function removeWord(word) {
            try {
                var res = await fetch('/admin/banned/words/' + encodeURIComponent(word), {
                    method: 'DELETE',
                    credentials: 'same-origin'
                });
                if (!res.ok) return;
                renderWords((await res.json()).words || []);
            } catch (e) {}
        }

        async function blockItem() {
            var id = document.getElementById('blockId').value.trim();
            var type = document.getElementById('blockType').value;
            if (!id) return;
            try {
                var res = await fetch('/admin/banned/items', {
                    method: 'POST',
                    headers: {'Content-Type': 'application/json'},
                    body: JSON.stringify({id: parseInt(id, 10), type: type}),
                    credentials: 'same-origin'
                });
                if (!res.ok) {
                    var err = await res.json().catch(function() { return {}; });
                    alert(err.detail || '屏蔽失败');
                    return;
                }
                document.getElementById('blockId').value = '';
                loadBanned();
            } catch (e) {}
        }

        async function unblockItem(it) {
            try {
                var res = await fetch('/admin/banned/items/' + it.type + '/' + it.id, {
                    method: 'DELETE',
                    credentials: 'same-origin'
                });
                if (!res.ok) return;
                loadBanned();
            } catch (e) {}
        }

        document.getElementById('loginPass').addEventListener('keydown', function(e) {
            if (e.key === 'Enter') doLogin();
        });
        document.getElementById('searchInput').addEventListener('keydown', function(e) {
            if (e.key === 'Enter') searchItems();
        });

        checkSession();
    </script>
</body>
</html>
"""

def _load_webui_config() -> dict:
    try:
        if os.path.exists(CONFIG_PATH):
            with open(CONFIG_PATH, "r", encoding="utf-8") as f:
                return json.load(f).get("webui", {}) or {}
    except Exception:
        pass
    return {}


def build_html_content() -> str:
    config = _load_webui_config()
    title = str(config.get("title") or DEFAULT_TITLE)
    subtitle = str(config.get("subtitle") or DEFAULT_SUBTITLE)
    return INDEX_TEMPLATE.replace("{{TITLE}}", title).replace("{{SUBTITLE}}", subtitle)


def build_manage_html_content() -> str:
    config = _load_webui_config()
    title = str(config.get("title") or DEFAULT_TITLE)
    return MANAGE_TEMPLATE.replace("{{TITLE}}", title)


HTML_CONTENT = build_html_content()
MANAGE_CONTENT = build_manage_html_content()


@router.get("/", response_class=HTMLResponse)
async def webui():
    return HTML_CONTENT
