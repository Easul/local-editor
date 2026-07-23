# Local Editor

Local Editor 是一个浏览器扩展，用来在 Firefox、Chrome、Edge、Chromium 中直接编辑本地文本文件。打开 `file://` 页面后，页面右下角会出现 `✏ Edit` 按钮；点击后进入全屏编辑器，修改内容并用 `Ctrl+S` 保存回原文件。

扩展本身不能直接写本地文件，所以需要配合本项目的 Go Native Messaging Host 使用。

## 功能

- 支持 `file://` 本地文件页面
- 支持后缀：`.txt .md .ini .conf .yaml .yml .toml .json .log`
- 点击 `✏ Edit` 进入全屏编辑器
- `Ctrl+S` 保存到原文件
- `Esc` 或“关闭”退出编辑器，并刷新当前文件页面
- 支持亮色 / 深色主题切换
- 文件被外部程序修改后提示重新加载

## 项目结构

```text
local-editor/
├── extension/
│   ├── firefox/                 # Firefox 扩展源码，Manifest V2
│   │   ├── manifest.json
│   │   ├── background.js
│   │   ├── content.js
│   │   └── style.css
│   └── chromium/                # Chrome / Edge / Chromium 扩展源码，Manifest V3
│       ├── manifest.json
│       ├── background.js
│       ├── content.js
│       └── style.css
├── host/                        # Go Native Messaging Host
│   ├── go.mod
│   └── main.go
├── native-manifest/
│   ├── local_editor_firefox.json
│   └── local_editor_chromium.json
├── scripts/
│   └── build.sh                 # 单入口构建脚本
└── dist/                        # 构建产物
```

## 依赖

Deepin / Debian / Ubuntu：

```bash
sudo apt update
sudo apt install -y golang-go zip python3 nodejs npm
```

依赖用途：

- `go`：编译 Native Messaging Host
- `zip`：生成 Firefox debug XPI 和 Chromium debug ZIP
- `python3`：读取扩展版本号、校验/辅助打包
- `nodejs/npm`：只有生成 Firefox release XPI 时才需要 `web-ext sign`

## 构建入口

所有构建都通过一个脚本执行：

```bash
bash scripts/build.sh [host|firefox|chromium|all]
```

不传参数时默认是 `all`。

### 构建目标说明

| 目标 | 作用 | 主要产物 |
|---|---|---|
| `host` | 编译 Go Native Messaging Host，并去掉符号 | `dist/local-editor-host`、`dist/host/*` |
| `firefox` | 构建 Firefox debug XPI；有 AMO 凭据时同时构建 release XPI | `dist/firefox/` |
| `chromium` | 构建 Chromium debug ZIP；有 Chromium CRX key 时同时构建 release CRX | `dist/chromium/` |
| `all` | 依次执行 `host`、`firefox`、`chromium` | 全部产物 |

### Host 构建

```bash
bash scripts/build.sh host
```

输出：

```text
dist/local-editor-host
dist/host/local-editor-host-linux-amd64
dist/host/local-editor-host-darwin-amd64
dist/host/local-editor-host-windows-amd64.exe
```

`dist/local-editor-host` 是当前平台可直接使用的 host；`dist/host/` 下是 linux / macOS / Windows 的 amd64 包。

### Firefox 构建

```bash
bash scripts/build.sh firefox
```

始终生成 debug 包：

```text
dist/firefox/local-editor-0.1.0-firefox-debug.xpi
```

如果提供 AMO 凭据，还会生成 release 包：

```text
dist/firefox/local-editor-0.1.0-firefox-release.xpi
```

AMO 凭据可以用环境变量：

```bash
AMO_JWT_ISSUER="..." AMO_JWT_SECRET="..." bash scripts/build.sh firefox
```

也可以用 key 文件：

```bash
AMO_KEY_FILE=temp/key.md bash scripts/build.sh firefox
```

key.md 的内容为

```markdown
# firefox凭据
```yaml
AMO_JWT_ISSUER: user:12345678:345
AMO_JWT_SECRET: 123asdf54568eed1228412123asdf54568eed1228412123asdf54568eed1228412
```
```

### Chromium 构建

```bash
bash scripts/build.sh chromium
```

始终生成 debug ZIP 和可直接加载的目录：

```text
dist/chromium/local-editor-0.1.0-chromium-debug.zip
dist/chromium/debug/
```

如果提供 Chromium CRX 私钥，还会生成 release CRX：

```text
dist/chromium/local-editor-0.1.0-chromium-release.crx
```

示例：

```bash
CHROMIUM_CRX_KEY=/path/to/key.pem bash scripts/build.sh chromium
```

Chromium debug 包是 ZIP，release 包是 CRX。Chromium 浏览器不使用 XPI；XPI 只用于 Firefox。

## 手动安装

### 1. 准备 Native Messaging Host

先构建 host：

```bash
bash scripts/build.sh host
```

可以直接使用绝对路径：

```text
/path/to/local-editor/dist/local-editor-host
```

也可以手动复制到系统路径：

```bash
sudo cp dist/local-editor-host /usr/local/bin/local-editor-host
sudo chmod 755 /usr/local/bin/local-editor-host
```

后续 native manifest 里的 `path` 必须写实际 host 的绝对路径。

### 2. Firefox 手动安装

构建 Firefox 包：

```bash
bash scripts/build.sh firefox
```

复制 Firefox native manifest 模板：

```bash
mkdir -p ~/.mozilla/native-messaging-hosts
cp native-manifest/local_editor_firefox.json ~/.mozilla/native-messaging-hosts/local_editor.json
```

手动编辑：

```bash
nano ~/.mozilla/native-messaging-hosts/local_editor.json
```

确认 `path` 是 host 的绝对路径，`allowed_extensions` 保持不变：

```json
{
  "name": "local_editor",
  "description": "Local Editor native host for Firefox",
  "path": "/usr/local/bin/local-editor-host",
  "type": "stdio",
  "allowed_extensions": ["local-editor@example.com"]
}
```

开发加载方式：

```text
about:debugging#/runtime/this-firefox
Load Temporary Add-on...
/path/to/local-editor/extension/firefox/manifest.json
```

如果使用 XPI，则选择：

```text
dist/firefox/local-editor-0.1.0-firefox-debug.xpi
dist/firefox/local-editor-0.1.0-firefox-release.xpi
```

#### Firefox 153 及以上版本的本地文件权限

从 Firefox 153 开始，扩展访问 `file://` 本地文件需要用户单独授权，并且该权限默认关闭。如果扩展已经加载，但打开受支持的本地文件时没有出现 `✏ Edit` 按钮，请按以下步骤开启权限：

1. 打开 `about:addons`。
2. 找到 Local Editor，进入扩展详情页的“权限”。
3. 开启“访问您计算机上的本地文件”（`Access local files on your computer`）。
4. 刷新已经打开的 `file://` 页面。

如果 `about:addons` 中没有 Local Editor，并且此前使用的是 `about:debugging` 的临时加载方式，则 Firefox 更新重启后需要重新加载扩展。

### 3. Chrome / Edge / Chromium 手动安装

构建 Chromium 包：

```bash
bash scripts/build.sh chromium
```

打开扩展管理页：

```text
Chrome:   chrome://extensions
Edge:     edge://extensions
Chromium: chrome://extensions
```

开启“开发者模式”，点击“加载已解压的扩展程序”，选择：

```text
/path/to/local-editor/dist/chromium/debug/
```

加载后进入扩展详情页，复制 Extension ID，并开启：

```text
允许访问文件网址 / Allow access to file URLs
```

复制 Chromium native manifest 模板：

```bash
# Chrome
mkdir -p ~/.config/google-chrome/NativeMessagingHosts
cp native-manifest/local_editor_chromium.json ~/.config/google-chrome/NativeMessagingHosts/local_editor.json

# Chromium
mkdir -p ~/.config/chromium/NativeMessagingHosts
cp native-manifest/local_editor_chromium.json ~/.config/chromium/NativeMessagingHosts/local_editor.json

# Edge
mkdir -p ~/.config/microsoft-edge/NativeMessagingHosts
cp native-manifest/local_editor_chromium.json ~/.config/microsoft-edge/NativeMessagingHosts/local_editor.json
```

手动编辑对应目录里的 `local_editor.json`：

```json
{
  "name": "local_editor",
  "description": "Local Editor native host for Chromium browsers",
  "path": "/usr/local/bin/local-editor-host",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://REPLACE_WITH_EXTENSION_ID/"]
}
```

需要修改两处：

- `path`：改成 host 的绝对路径
- `REPLACE_WITH_EXTENSION_ID`：改成扩展详情页里的 Extension ID

## 使用

打开本地文件，例如：

```text
file:///home/user/Desktop/test.md
```

页面右下角会出现：

```text
✏ Edit
```

常用操作：

- 点击 `✏ Edit`：进入编辑器
- `Ctrl+S`：保存到原文件
- `Esc`：退出编辑器并刷新当前文件页
- “关闭”：退出编辑器并刷新当前文件页
- “切换深色 / 切换亮色”：切换主题
