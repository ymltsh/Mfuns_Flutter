#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Mfuns Flutter 一键发布工具（单文件，仅依赖标准库）。

支持两种模式：
  1. 引导模式（无参数运行）：交互式问答，按步骤完成发布。
  2. CLI 模式：通过命令行参数指定版本、类型与说明，非交互执行。

发布流程：
  版本号 + 构建号 → 静态检查/测试 → 构建 APK → 构建 Windows → 打包 zip
  → 创建 GitHub Release（含资产上传）→ 更新 version.json → 提交并推送

用法示例：
  python release.py                              # 引导模式
  python release.py --version 1.1.7 --notes "更新说明"        # 正式版
  python release.py --version 1.1.7 --beta --notes "测试"     # Beta
  python release.py --version 1.1.7 --beta2 --notes "测试"    # Beta2
  python release.py --version 1.1.7 --dry-run                 # 仅预览不执行
  python release.py --version 1.1.7 --skip-build --no-push    # 复用产物、不推送
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = os.path.dirname(os.path.abspath(__file__))
PUBSPEC = os.path.join(ROOT, "pubspec.yaml")
APP_CONFIG = os.path.join(ROOT, "lib", "core", "config", "app_config.dart")
VERSION_JSON = os.path.join(ROOT, "version.json")
APK_PATH = os.path.join(ROOT, "build", "app", "outputs", "flutter-apk",
                        "app-release.apk")
WINDOWS_RELEASE = os.path.join(ROOT, "build", "windows", "x64", "runner",
                               "Release")

VER_RE = re.compile(r"^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$", re.M)
APP_VER_RE = re.compile(r"static const appVersion = '([\d.]+)';")
APP_BUILD_RE = re.compile(r"static const appBuild = (\d+);")

GH_API = "https://api.github.com"
GH_UPLOAD = "https://uploads.github.com"


def log(message):
    print(message, flush=True)


def die(message):
    print(f"[错误] {message}", file=sys.stderr)
    sys.exit(1)


def run(cmd, cwd=None, check=True):
    log(f"$ {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=cwd, text=True, encoding="utf-8",
                            errors="replace")
    if check and result.returncode != 0:
        die(f"命令失败：{' '.join(cmd)}（退出码 {result.returncode}）")
    return result


def run_capture(cmd, cwd=None, input_data=None):
    return subprocess.run(cmd, cwd=cwd, text=True, capture_output=True,
                          encoding="utf-8", errors="replace",
                          input=input_data)


def find_flutter():
    configured = os.environ.get("FLUTTER_BIN")
    if configured and os.path.exists(configured):
        return configured
    found = shutil.which("flutter")
    if found:
        return found
    die("未找到 flutter，请将其加入 PATH 或设置环境变量 FLUTTER_BIN")


def read_file(path):
    with open(path, "r", encoding="utf-8") as f:
        return f.read()


def write_file(path, content):
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(content)


def current_version():
    text = read_file(PUBSPEC)
    match = VER_RE.search(text)
    if not match:
        die("pubspec.yaml 中未找到 version 字段")
    return (int(match.group(1)), int(match.group(2)), int(match.group(3)),
            int(match.group(4)))


def version_string(parts):
    return ".".join(str(p) for p in parts[:3])


def bump_pubspec(version, build):
    text = read_file(PUBSPEC)
    text = VER_RE.sub(f"version: {version}+{build}", text, count=1)
    write_file(PUBSPEC, text)


def bump_app_config(version, build):
    text = read_file(APP_CONFIG)
    text = APP_VER_RE.sub(f"static const appVersion = '{version}';", text)
    text = APP_BUILD_RE.sub(f"static const appBuild = {build};", text)
    write_file(APP_CONFIG, text)


def git_credential_token():
    result = run_capture(
        ["git", "credential", "fill"], cwd=ROOT,
        input_data="protocol=https\nhost=github.com\n\n")
    if result.returncode != 0:
        return None
    for line in result.stdout.splitlines():
        if line.startswith("password="):
            return line[len("password="):]
    return None


def github_token(arg_token):
    token = (arg_token or "").strip()
    if token:
        return token
    token = git_credential_token()
    if token:
        return token
    die("未提供 GitHub Token（用 --token 或 git 凭据）")


def api_request(url, token, method="GET", body=None):
    request = urllib.request.Request(url, method=method)
    request.add_header("Authorization", f"Bearer {token}")
    request.add_header("User-Agent", "mfuns-release-tool")
    data = None
    if body is not None:
        data = json.dumps(body, ensure_ascii=False).encode("utf-8")
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, data=data, timeout=60) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        die(f"GitHub API {method} {url} 失败：{error.code} {detail[:300]}")


def create_release(token, repo, tag, name, body, prerelease):
    payload = {
        "tag_name": tag,
        "name": name,
        "body": body,
        "prerelease": prerelease,
    }
    release = api_request(f"{GH_API}/repos/{repo}/releases", token,
                          method="POST", body=payload)
    log(f"已创建 Release：{release['html_url']}")
    return release


def upload_asset(token, repo, release_id, file_path, asset_name):
    url = (f"{GH_UPLOAD}/repos/{repo}/releases/{release_id}/assets?"
           f"name={urllib.parse.quote(asset_name)}")
    with open(file_path, "rb") as f:
        data = f.read()
    request = urllib.request.Request(url, method="POST", data=data)
    request.add_header("Authorization", f"Bearer {token}")
    request.add_header("Content-Type", "application/octet-stream")
    try:
        with urllib.request.urlopen(request, timeout=600) as resp:
            asset = json.loads(resp.read().decode("utf-8"))
            log(f"已上传资产：{asset['name']}（{asset['size']} 字节）")
    except urllib.error.HTTPError as error:
        detail = error.read().decode("utf-8", errors="replace")
        die(f"资产上传失败：{error.code} {detail[:300]}")


def update_version_json(version, build, name, notes, tag, page):
    manifest = json.loads(read_file(VERSION_JSON))
    old_latest = manifest.get("latest")
    if old_latest:
        history = manifest.get("history", [])
        history.insert(0, old_latest)
        manifest["history"] = history
    manifest["latest"] = {
        "version": version,
        "build": build,
        "name": name,
        "date": time.strftime("%Y-%m-%d"),
        "notes": notes,
        "urls": {
            "android":
                f"https://github.com/{args_repo()}/releases/download/{tag}/"
                f"mfuns-flutter-{asset_suffix()}.apk",
            "windows":
                f"https://github.com/{args_repo()}/releases/download/{tag}/"
                f"mfuns-flutter-windows-{asset_suffix()}.zip",
        },
        "page": f"https://github.com/{args_repo()}/releases/tag/{tag}",
    }
    write_file(VERSION_JSON,
               json.dumps(manifest, ensure_ascii=False, indent=2) + "\n")
    log("已更新 version.json")


def repo_from_remote():
    result = run_capture(["git", "remote", "get-url", "origin"], cwd=ROOT)
    url = result.stdout.strip()
    match = re.search(r"(?:github\.com[/:])([^/]+)/([^/]+?)(?:\.git)?$", url)
    if match:
        return f"{match.group(1)}/{match.group(2)}"
    die(f"无法从 git remote 解析仓库：{url}")


# 全局参数（由 main 填充，供部分函数使用）
_ARGS = {}


def args_repo():
    return _ARGS["repo"]


def asset_suffix():
    return _ARGS["asset"]


def build_windows_zip(version_asset):
    release_dir = WINDOWS_RELEASE
    if not os.path.isdir(release_dir):
        die(f"Windows 产物目录不存在：{release_dir}，请先构建")
    zip_path = os.path.join(ROOT, f"mfuns_flutter-windows-{version_asset}.zip")
    if os.path.exists(zip_path):
        os.remove(zip_path)
    # 排除目录内残留的旧 Release.zip，避免套娃打包。
    stale = os.path.join(release_dir, "Release.zip")
    if os.path.exists(stale):
        os.remove(stale)
    shutil.make_archive(zip_path[:-4], "zip", root_dir=release_dir)
    log(f"已打包：{zip_path}（{os.path.getsize(zip_path)} 字节）")
    return zip_path


def kill_running_instance(interactive):
    if os.name != "nt":
        return
    try:
        result = subprocess.run(
            ["tasklist", "/FI", "IMAGENAME eq mfuns_flutter.exe", "/FO",
             "CSV"], capture_output=True, text=True, encoding="utf-8",
            errors="replace")
        running = "mfuns_flutter.exe" in result.stdout and \
            "INFO: No tasks" not in result.stdout
    except Exception:
        return
    if not running:
        return
    if interactive:
        answer = input("检测到正在运行的 mfuns_flutter 实例，是否结束以继续构建？"
                       "（y/N）：").strip().lower()
        if answer not in ("y", "yes"):
            die("已取消：请先关闭运行中的 mfuns_flutter")
    log("正在结束 mfuns_flutter 进程…")
    subprocess.run(["taskkill", "/F", "/IM", "mfuns_flutter.exe"],
                   capture_output=True)
    time.sleep(2)


def guided_input(prompt, default=None):
    suffix = f"（回车使用默认：{default}）" if default is not None else ""
    value = input(f"{prompt}{suffix}：").strip()
    return value if value else (default if default is not None else "")


def guided_notes():
    log("请输入发布说明（多行，输入空行结束；直接回车使用默认说明）：")
    lines = []
    while True:
        line = input()
        if line == "":
            break
        lines.append(line)
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(
        description="Mfuns Flutter 一键发布工具（引导或 CLI 模式）")
    parser.add_argument("--version", help="新版本号，如 1.1.7")
    parser.add_argument("--build", type=int, help="构建号（默认当前+1）")
    parser.add_argument("--beta", action="store_true", help="Beta 发布（预发布）")
    parser.add_argument("--beta2", action="store_true", help="Beta2 发布（预发布）")
    parser.add_argument("--name", help="发布标题（默认 Mfuns Flutter vX）")
    parser.add_argument("--notes", help="发布说明（多行用 \\n）")
    parser.add_argument("--repo", help="GitHub 仓库 owner/repo（默认读取 git remote）")
    parser.add_argument("--token", help="GitHub Token（默认读取 git 凭据）")
    parser.add_argument("--dry-run", action="store_true", help="仅预览，不执行")
    parser.add_argument("--skip-build", action="store_true", help="跳过构建，复用现有产物")
    parser.add_argument("--skip-checks", action="store_true", help="跳过 analyze/test")
    parser.add_argument("--no-push", action="store_true", help="不提交/推送 version.json")
    args = parser.parse_args()

    interactive = not (args.version or args.build or args.beta or args.beta2
                       or args.name or args.notes)

    current = current_version()
    cur_ver = version_string(current)
    cur_build = current[3]
    log(f"当前版本：v{cur_ver}+{cur_build}")

    if interactive:
        suggested = f"{current[0]}.{current[1]}.{current[2] + 1}"
        version = guided_input("新版本号", suggested)
        if not version:
            version = suggested
        build = guided_input("构建号", str(cur_build + 1))
        build = int(build) if build.isdigit() else cur_build + 1
        kind = guided_input("发布类型（1 正式版 / 2 Beta / 3 Beta2）", "1")
        beta2 = kind == "3"
        beta = kind == "2" or beta2
        name = guided_input("发布标题", f"Mfuns Flutter v{version}")
        notes = guided_notes() or f"v{version} 更新发布"
        dry_run = guided_input("仅预览不执行（y/N）", "N").strip().lower() in (
            "y", "yes")
    else:
        version = args.version
        if not version:
            version = f"{current[0]}.{current[1]}.{current[2] + 1}"
        if not re.match(r"^\d+\.\d+\.\d+$", version):
            die(f"版本号格式不正确：{version}")
        build = args.build or cur_build + 1
        beta2 = args.beta2
        beta = args.beta or args.beta2
        name = args.name or f"Mfuns Flutter v{version}"
        notes = (args.notes or f"v{version} 更新发布").replace("\\n", "\n")
        dry_run = args.dry_run

    suffix = "-beta2" if beta2 else ("-beta" if beta else "")
    tag = f"v{version}{suffix}"
    asset = f"{version}{suffix}"

    repo = args.repo or repo_from_remote()
    _ARGS["repo"] = repo
    _ARGS["asset"] = asset

    log("")
    log("========== 发布计划 ==========")
    log(f"版本：{version}+{build}（tag: {tag}）")
    log(f"类型：{'Beta2' if beta2 else 'Beta' if beta else '正式版'}"
        f"{'（预发布）' if beta else ''}")
    log(f"仓库：{repo}")
    log(f"发布标题：{name}")
    log(f"说明：\n{notes}")
    log("==============================")

    if not dry_run and interactive:
        confirm = input("确认发布？输入 y 开始：").strip().lower()
        if confirm not in ("y", "yes"):
            die("已取消发布")

    if dry_run:
        log("\n[dry-run] 以上为将执行的内容，未做任何修改。")
        sys.exit(0)

    log("\n[1/7] 更新版本号…")
    bump_pubspec(version, build)
    bump_app_config(version, build)
    log(f"已更新 pubspec.yaml / app_config.dart → {version}+{build}")

    flutter = find_flutter()

    if not args.skip_checks:
        log("\n[2/7] 静态检查与测试…")
        run([flutter, "analyze"], cwd=ROOT)
        run([flutter, "test"], cwd=ROOT)

    if args.skip_build:
        log("\n[3/7] 跳过构建，复用现有产物…")
    else:
        log("\n[3/7] 构建 Android APK…")
        run([flutter, "build", "apk", "--release"], cwd=ROOT)
        log("\n[4/7] 构建 Windows…")
        kill_running_instance(interactive)
        run([flutter, "build", "windows"], cwd=ROOT)
        log("\n[5/7] 打包 Windows 压缩包…")
        build_windows_zip(asset)

    if not os.path.exists(APK_PATH):
        die(f"未找到 APK：{APK_PATH}，请先构建")

    token = github_token(args.token)

    log("\n[6/7] 创建 GitHub Release 并上传资产…")
    release = create_release(token, repo, tag, name, notes, beta)
    upload_asset(token, repo, release["id"], APK_PATH,
                 f"mfuns-flutter-{asset}.apk")
    zip_path = os.path.join(ROOT, f"mfuns_flutter-windows-{asset}.zip")
    if os.path.exists(zip_path):
        upload_asset(token, repo, release["id"], zip_path,
                     f"mfuns-flutter-windows-{asset}.zip")
        os.remove(zip_path)

    log("\n[7/7] 更新 version.json 并推送…")
    update_version_json(version, build, name, notes, tag,
                        f"https://github.com/{repo}/releases/tag/{tag}")
    if not args.no_push:
        run(["git", "add", "version.json"], cwd=ROOT)
        run(["git", "commit", "-m", f"Bump update manifest to v{version}"
             f"{suffix}"], cwd=ROOT)
        run(["git", "push", "origin", "main"], cwd=ROOT)
        log("已推送 version.json")

    log("")
    log("========== 发布完成 ==========")
    log(f"Release：https://github.com/{repo}/releases/tag/{tag}")
    log(f"版本：v{version}+{build}（{name}）")


if __name__ == "__main__":
    main()
