# env

Linux 服务器开发语言自动安装工具。

## 功能

- 交互式菜单选择安装语言
- 支持 C/C++, Python, Node.js, Go
- 可选版本管理工具（Miniconda, nvm）
- 国内镜像源自动切换（清华 TUNA, 阿里云）
- 错误日志记录到 `error.log`
- 幂等性设计，重复运行安全

## 使用

```bash
chmod +x install-langs.sh
sudo ./install-langs.sh
```

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
