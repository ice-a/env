# env

Linux 服务器开发语言自动安装工具。

## 功能

- 交互式空格选中菜单（↑↓ 移动，空格选中，Enter 确认）
- 支持安装：
  - C/C++ (gcc, g++, make, cmake)
  - Python (系统版本 或 Miniconda)
  - Node.js (通过 nvm)
  - Go
  - Java (OpenJDK)
  - Rust (通过 rustup)
  - Docker
  - Git
  - Make & CMake
- 国内镜像源自动切换
- 错误日志记录到 `error.log`
- 幂等性设计，重复运行安全

## 使用

```bash
chmod +x install-langs.sh
sudo ./install-langs.sh
```

### 菜单操作

| 按键 | 功能 |
|------|------|
| ↑ ↓ | 移动光标 |
| 空格 | 选中/取消选中 |
| a | 全选/全不选 |
| Enter | 确认安装 |

## 支持系统

- Ubuntu / Debian
- CentOS / RHEL / Rocky / AlmaLinux

## 镜像源

| 语言/工具 | 镜像源 |
|-----------|--------|
| APT | 清华 TUNA |
| YUM/DNF | 阿里云 |
| PyPI | 清华 TUNA |
| npm | npmmirror |
| Go | goproxy.cn |
| nvm Node | npmmirror |
| Miniconda | 清华 TUNA |
| Rust | USTC |
| Docker | USTC / 163 / 腾讯云 |
| crates.io | USTC |

## 错误日志

安装过程中的错误会记录到 `error.log`，格式：

```
2026-06-09T12:30:45+08:00 level=ERROR lang=go phase=download exit=22 msg="download failed"
```
