# Firefox Local Editor

在 Firefox 里直接编辑本地 `txt/md/ini/yaml/toml/json/log` 文件。打开 `file://` 页面后点右下角 `✏ Edit`，在 Firefox 内修改，`Ctrl+S` 原地保存。

## 当前功能

- 支持 `file://` 本地文本文件
- 点击 `✏ Edit` 进入全屏编辑器
- 默认亮色主题，可切换深色主题
- `Ctrl+S` 保存
- `Esc` 或“关闭”退出编辑器，并自动刷新当前文件页面
- 外部程序修改文件后提示“重新加载”

支持后缀：

```text
.txt .md .ini .conf .yaml .yml .toml .json .log
```

## 项目结构

```text
firefox-local-editor/
├── firefox-extension/          # Firefox 扩展
│   ├── manifest.json
│   ├── background.js
│   ├── content.js
│   └── style.css
├── host/                       # Go Native Messaging host
│   ├── go.mod
│   └── main.go
├── native-manifest/
│   └── local_editor.json       # Firefox native host 清单模板
├── scripts/
│   ├── build-host.sh           # 编译 Go host
│   ├── package-xpi.sh          # 生成未签名 XPI
│   └── sign-xpi.sh             # 通过 AMO 生成正式签名 XPI
└── dist/                       # 构建产物
```

## Deepin 64 位安装
### 1. 安装依赖

```bash
sudo apt update
sudo apt install -y golang-go zip nodejs npm
```

说明：

- Go 用于编译 `local-editor-host`
- `zip` 用于打 `.xpi`
- `nodejs/npm` 只在需要正式签名时使用 `web-ext`

### 2. 编译 Native Host

```bash
cd /path/to/firefox-local-editor
bash scripts/build-host.sh
```

成功后会生成：

```text
dist/local-editor-host
```

### 3. 安装 Native Messaging 清单

Firefox 扩展不能直接写本地文件，必须通过 Native Messaging 调用 Go host。

创建 Firefox native host 目录：

```bash
mkdir -p ~/.mozilla/native-messaging-hosts
```

复制清单：

```bash
cp native-manifest/local_editor.json ~/.mozilla/native-messaging-hosts/local_editor.json
```

编辑清单：

```bash
nano ~/.mozilla/native-messaging-hosts/local_editor.json
```

确认 `path` 是 Go host 的绝对路径：

```json
{
  "name": "local_editor",
  "description": "Firefox Local Editor native host",
  "path": "/path/to/local-editor-host",
  "type": "stdio",
  "allowed_extensions": ["local-editor@example.com"]
}
```

### 4. 调试方式加载扩展

Firefox 打开：

```text
about:debugging#/runtime/this-firefox
```

点击：

```text
Load Temporary Add-on...
```

选择：

```text
/path/to/firefox-local-editor/firefox-extension/manifest.json
```

这种方式适合开发测试。缺点是 Firefox 重启后需要重新加载。

### 5. 使用

打开本地文件，例如：

```text
file:///home/user/Desktop/test.md
```

右下角出现：

```text
✏ Edit
```

操作：

- 点击 `✏ Edit`：进入编辑器
- `Ctrl+S`：保存到原文件
- `Esc`：退出编辑器并刷新当前文件页
- “关闭”：退出编辑器并刷新当前文件页
- “切换深色 / 切换亮色”：切换主题

## 打包 XPI

### 本地未签名 XPI

```bash
cd /path/to/firefox-local-editor
bash scripts/package-xpi.sh
```

输出类似：

```text
dist/firefox-local-editor-0.1.0.xpi
```

注意：Firefox 正式版通常不能长期安装未签名 XPI。未签名 XPI 主要用于：

- `about:debugging` 临时加载
- Firefox Developer Edition / Nightly / 部分 ESR 环境中关闭签名校验后测试

### 正式可安装 XPI：Mozilla 签名

Firefox 正式版长期安装扩展，需要 Mozilla 签名。推荐使用 `web-ext sign` 的 unlisted 方式：不公开上架，只生成可自己安装的已签名 XPI。

1. 登录 AMO 开发者后台并创建 API key：

```text
https://addons.mozilla.org/developers/addon/api/key/
```

2. 导出 API 凭据：

```bash
export AMO_JWT_ISSUER="你的 API key"
export AMO_JWT_SECRET="你的 API secret"
```

3. 提交签名：

```bash
cd /path/to/firefox-local-editor
bash scripts/sign-xpi.sh
```

成功后，已签名 XPI 会下载到：

```text
dist/signed/
```

然后可以在 Firefox 中打开这个 `.xpi` 安装。

## 常见问题

### 看不到 `✏ Edit`

检查：

1. URL 必须是 `file:///...`
2. 后缀必须是支持列表里的文本后缀
3. 扩展必须已加载

### 点保存失败

通常是 Native Host 没配好。检查：

```bash
cat ~/.mozilla/native-messaging-hosts/local_editor.json
```

重点确认：

- `path` 是绝对路径
- `path` 指向的 `dist/local-editor-host` 存在
- `allowed_extensions` 包含 `local-editor@example.com`

### 修改了扩展代码但没生效

如果用 `about:debugging` 临时加载，需要在调试页面点 Reload，或者删除后重新加载 `manifest.json`。

### 正式签名失败

常见原因：

- AMO API key/secret 填错
- 扩展版本号没有递增
- 网络无法访问 AMO
- manifest 中权限或 ID 不符合 AMO 校验要求
