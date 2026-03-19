# 环境安装与卸载脚本

这个仓库提供了一组独立的 Shell 脚本，用于安装和卸载常见开发环境工具，适合在 Linux 和 macOS 上快速初始化开发机器。

## 文件说明

- `install.sh`：总安装入口，支持交互式选择或命令行按需安装。
- `install-docker.sh`：单独安装 Docker。
- `install-nvm.sh`：单独安装 NVM，并自动安装 Node.js LTS。
- `install-mambaconda.sh`：单独安装 Mambaconda，默认安装到 `$HOME/mambaconda`。
- `tmp.log`：安装过程日志示例文件，用于排查安装问题和核对执行输出。
- `uninstall.sh`：总卸载入口，支持交互式选择或命令行按需卸载。
- `uninstall-docker.sh`：单独卸载 Docker，默认保留 Docker 数据。
- `uninstall-nvm.sh`：单独卸载 NVM，并清理脚本追加的 Shell 初始化配置。
- `uninstall-mambaconda.sh`：单独卸载 Mambaconda，并清理脚本追加的 Shell 初始化配置。

## 支持平台

- Linux
- macOS

## 安装用法

总入口安装：

```bash
bash install.sh
```

常见用法：

```bash
bash install.sh all
bash install.sh docker
bash install.sh nvm mambaconda
```

也可以直接执行单独脚本：

```bash
bash install-docker.sh
bash install-nvm.sh
bash install-mambaconda.sh
```

`install.sh` 支持以下模式：

- 不带参数：交互式选择安装项
- `all`：安装全部工具
- `docker` / `nvm` / `mambaconda`：安装指定工具
- 多个参数组合：安装多个指定工具

## 卸载用法

总入口卸载：

```bash
bash uninstall.sh
```

常见用法：

```bash
bash uninstall.sh all
bash uninstall.sh docker
bash uninstall.sh nvm mambaconda
```

也可以直接执行单独脚本：

```bash
bash uninstall-docker.sh
bash uninstall-nvm.sh
bash uninstall-mambaconda.sh
```

`uninstall.sh` 支持以下模式：

- 不带参数：交互式选择卸载项
- `all`：卸载全部工具
- `docker` / `nvm` / `mambaconda`：卸载指定工具
- 多个参数组合：卸载多个指定工具

## 默认行为说明

- `install-nvm.sh` 会配置 Node.js 国内镜像和 npm 国内源。
- `install-mambaconda.sh` 会写入 `~/.condarc`，并使用国内镜像源。
- `install-mambaconda.sh` 默认会安装 Python 3.10。
- `uninstall-docker.sh` 默认不会删除 Docker 数据目录。

## 关于 `tmp.log`

仓库中的 `tmp.log` 是一次安装过程的输出日志示例，主要用于：

- 查看脚本在真实环境中的执行顺序
- 排查下载失败、权限不足、源不可达等问题
- 核对安装完成后的版本输出和提示信息

常见查看方式：

```bash
cat tmp.log
tail -n 50 tmp.log
grep ERROR tmp.log
grep WARN tmp.log
```

说明：

- `tmp.log` 不是脚本运行时强制生成的文件，它更像一份调试或留档日志。
- 如果你需要记录自己的安装过程，可以手动重定向输出，例如：

```bash
bash install.sh all > tmp.log 2>&1
```

- 如果终端里看到中文乱码，通常是终端编码问题，不一定是日志内容损坏。

如果需要在卸载 Docker 时同时删除数据，可使用：

```bash
REMOVE_DOCKER_DATA=1 bash uninstall-docker.sh
```

## 安装后验证

```bash
docker --version
docker compose version
nvm --version && node --version && npm --version
conda --version && python --version
```

## 输出风格

现在所有入口脚本和子脚本都会使用统一的输出格式：

- `INFO`：普通步骤提示
- `WARN`：非阻断警告
- `ERROR`：错误并退出
- `DONE`：当前脚本执行完成

同时会显示阶段标题，便于在安装或卸载过程中快速定位当前步骤。
