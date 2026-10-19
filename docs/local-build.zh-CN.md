# 本机编译与安装

## Google Authenticator 迁移导入（0.2.3-local）

添加窗口支持 `otpauth-migration://offline?data=...`。直接粘贴完整迁移链接，或通过二维码图片/截图识别后，会显示包内账户列表；点击“导入”才写入账户。同名账户会跳过，单账户包可修改显示标识。多二维码分批迁移会显示当前批次，需要依次导入其余二维码。

解析在核心模块 `GoogleAuthMigration` 中离线完成，将二进制密钥转换为 Base32 并生成标准验证器地址。保留账户名称、发行方、算法和位数，未知扩展字段可跳过。仅支持 TOTP；含 HOTP、未知类型或无效参数的包整体拒绝，不部分导入。

Base32 编码与标准地址生成器由直接密钥添加和迁移导入共用。验收使用合成密钥覆盖标准验证码、中文名称、多账户、批次、重复导入、损坏 Protobuf、算法/类型拒绝与迁移二维码识别。

## 截图识别（0.2.2-local）

添加窗口在“从二维码图片识别”旁增加“截图识别”按钮。点击后添加窗口暂时隐藏，使用 macOS 自带截图选择器框选网页中的二维码；识别完成后窗口恢复，验证器地址自动填入，确认标识后点击添加。按 Esc 取消会保留原来的输入。

首次使用需要在“系统设置 → 隐私与安全性 → 屏幕录制”允许 GoldenPassport，并按系统提示重新启动应用。截图仅放在当前用户可访问的临时目录，识别完成或取消后自动删除，不写入桌面、不上传。框选范围应完整包含一个验证器二维码；未找到或找到多个会提示重新框选。

二维码图片导入与截图共用核心模块 `QRCodeReader`；本机验收使用合成二维码和模拟屏幕图片，不使用真实账户密钥。

## 直接添加密钥（0.2.1-local）

添加窗口的“密钥或 OTPAuth URL”支持完整验证器地址，也支持直接粘贴 Base32 密钥。仅输入密钥时，填写“标识”（例如服务名称），点击添加即可。密钥允许小写、空格、换行及分组连字符，默认 SHA1、6 位、30 秒。

完整验证器地址中的自定义算法、位数和刷新周期保持不变。统一转换逻辑位于核心模块的 `OTPAuthInput.normalizedURL`，供后续 CLI/MCP 复用。

## macOS 13 / Intel / Command Line Tools

本 fork 支持使用 Swift 5.8 的 Command Line Tools 构建桌面应用，不要求升级系统或安装完整 Xcode。

```sh
make release
bash scripts/install.sh "$HOME/Library/Caches/GoldenPassport-build/release/GoldenPassport.app"
```

默认构建当前机器的架构。需要通用版时：

```sh
ARCHS="arm64 x86_64" make release
```

完整 Xcode 环境使用 SwiftPM；缺少 Xcode 平台目录的 Command Line Tools 环境使用共享的 `scripts/native-build.sh`，静态链接核心模块。输出仍在用户缓存目录，不进入源码仓库。

包清单兼容 Swift 5.8，并对旧 SDK 不包含的 macOS 14 API 增加编译条件；新版 SDK 保持原有行为。

## 验证

```sh
make test
make test-native
```

`make test` 在完整 Xcode + Swift 6 环境运行上游 Swift Testing 测试；其他环境明确提示后运行原生兼容性验收，覆盖 RFC 6238 的 18 组算法向量、旧账户迁移、账户编辑与排序持久化、文件权限、HTTP Host 拒绝和真实回环 HTTP 请求。原生验收不等同于上游完整测试集。

验收只使用临时目录中的合成账户，结束时清除，不读取真实账户密钥。

安装脚本会停止并替换旧应用、备份数据、校验迁移、启动新版。账户数据不会作为卸载旧应用的一部分删除。辅助功能权限需在系统设置中重新授予，才能用快捷键直接输入验证码。
