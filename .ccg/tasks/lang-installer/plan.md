# 实施计划：Linux 语言自动安装工具

## 需求
创建一个 bash 脚本，支持交互式选择安装 C/C++, Python, Node.js, Go 等语言，可选版本管理工具，网络问题自动切换国内镜像，错误记录到 error.log。

## 方案
单文件模块化 Bash 脚本（`install-langs.sh`），函数划分清晰，每个语言安装函数独立事务。

## 文件结构
- `install-langs.sh` — 主脚本（约 500-600 行）
- `error.log` — 运行时自动生成

## 实施步骤

### 1. 基础框架（~100 行）
- 脚本头部：`set -u -o pipefail`（不用 `-e` 避免单语言失败中断整体）
- 颜色输出函数：`log_info`, `log_warn`, `log_error`
- OS 检测：`detect_os()` — 识别 Ubuntu/Debian/CentOS/RHEL
- 包管理器抽象：`pkg_update()`, `pkg_install()`
- 权限检查：开头检测 root 或 sudo

### 2. 网络与镜像层（~80 行）
- `check_network()` — 检测网络连通性
- `switch_mirror()` — 切换到国内镜像（备份原源文件）
- 镜像配置：
  - APT: 清华 TUNA (`mirrors.tuna.tsinghua.edu.cn`)
  - YUM/DNF: 阿里云 (`mirrors.aliyun.com`)
  - PyPI: `https://mirrors.tuna.tsinghua.edu.cn/pypi/web/simple`
  - npm: `https://registry.npmmirror.com`
  - Go: `https://goproxy.cn,direct`
  - nvm: `NVM_NODEJS_ORG_MIRROR=https://npmmirror.com/mirrors/node`
  - Miniconda: TUNA Anaconda 镜像

### 3. 环境变量工具（~40 行）
- `append_once()` — 检查后追加，避免重复
- `ensure_path_entry()` — PATH 专用
- `ensure_profile_block()` — 多行配置块

### 4. 语言安装函数（每个 ~60-80 行）
- `install_cpp()` — build-essential / Development Tools
- `install_python()` — 系统 python3 + pip，或 miniconda
- `install_node()` — nvm + node
- `install_go()` — 官方 tarball，版本化安装 + 软链

### 5. 验证函数（每个 ~10 行）
- `verify_cpp()` — `gcc --version`
- `verify_python()` — `python3 --version` 或 `conda --version`
- `verify_node()` — `node --version`, `npm --version`
- `verify_go()` — `go version`

### 6. 主流程与菜单（~80 行）
- `show_menu()` — 交互式选择语言
- `confirm_options()` — 确认安装选项
- `run_language_step()` — 包装器：捕获退出码、写日志、继续下一个
- `main()` — 主循环

### 7. 错误日志（~20 行）
- 格式：`2026-06-09T12:30:45+08:00 level=ERROR lang=go phase=download exit=22 msg="..."`
- 写入 `error.log`（脚本同目录）

## 影响范围
- 新增: `install-langs.sh`
- 运行时生成: `error.log`
