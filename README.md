# env

Linux 服务器开发环境一键安装工具。

## 功能特性

- 🖱️ **交互式 TUI 菜单** — 方向键移动、空格选中、Enter 确认
- 📦 **一站式安装** — 开发语言 + 数据库 + 工具链
- 🚀 **国内镜像加速** — 所有包管理器默认使用国内镜像
- 📝 **错误日志** — 安装失败自动记录到 `error.log`
- 🔒 **安全兼容** — 支持 `sudo` 环境，自动检测真实用户

## 支持安装

### 开发语言
| 语言 | 安装方式 | 说明 |
|------|---------|------|
| C/C++ | 系统包管理器 | gcc, g++, make, cmake |
| Python | 系统 Python 或 Miniconda | 双模式可选 |
| Node.js | nvm | 支持多版本切换 |
| Go | 官方二进制 | 配置 goproxy.cn |
| Java | OpenJDK | 系统包管理器 |
| Rust | rustup | 配置 USTC 镜像 |

### 数据库
- MySQL
- MongoDB
- Redis

### 工具链
- Docker
- Git
- Make & CMake

## 快速开始

```bash
# 1. 克隆仓库
git clone https://github.com/ice-a/env.git
cd env

# 2. 添加执行权限
chmod +x install-langs.sh

# 3. 执行安装（需要 root 权限）
sudo ./install-langs.sh
```

## 菜单操作

| 按键 | 功能 |
|------|------|
| ↑ ↓ | 移动光标 |
| 空格 | 选中/取消选中 |
| a / A | 全选 / 全不选 |
| Enter | 确认安装 |

## 支持系统

| 系统 | 包管理器 | 状态 |
|------|---------|------|
| Ubuntu / Debian | apt | ✅ 完全支持 |
| CentOS / RHEL / Rocky / AlmaLinux | dnf / yum | ✅ 完全支持 |

## 镜像源配置

| 工具 | 镜像源 |
|------|--------|
| APT | 清华 TUNA |
| YUM / DNF | 阿里云 |
| PyPI | 清华 TUNA |
| npm | npmmirror |
| Go | goproxy.cn |
| nvm Node | npmmirror |
| Miniconda | 清华 TUNA |
| Rust / crates.io | USTC |
| Docker | USTC / 163 / 腾讯云 |

## 错误日志

安装过程中的错误会自动记录到 `error.log`，格式：

```
2026-06-09T12:30:45+08:00 level=ERROR lang=go phase=download exit=22 msg="download failed"
```

## 常见问题

### Q: 交互菜单卡住无法选择？

已修复 Linux 终端兼容性问题。如果仍有问题，请确保使用标准终端（xterm-256color）。

### Q: sudo 环境下提示权限问题？

脚本会自动检测 `SUDO_USER`，切换到真实用户执行用户级安装（如 nvm）。

## License

MIT
