# ReadButton

ReadButton 是一个纯 watchOS Apple Watch App，用 Apple Watch 直接遥控 Sony Digital Paper DPT-RP1。它不依赖 iPhone、Mac 或 ESP32 转发。

## 功能

- 在 Watch 上完成 DPT-RP1 配对和认证；
- 从 DPT-RP1 读取 PDF 文档列表；
- 按最近选择和最近阅读位置排列文档；
- 切换文档时恢复该文档的上次页码；
- 上一页/下一页遥控；
- 点击页码跳转到指定页面；
- 书库刷新和 DPT 地址配置；
- 低功耗设计：不后台轮询，只在启动、恢复、选择文档或翻页时访问网络。

## 环境要求

- macOS；
- Xcode 16 或更新版本；
- Apple Watch，watchOS 10 或更新版本；
- Sony DPT-RP1/CP1 或兼容 Digital Paper 设备；
- Watch 与 DPT 连接同一个局域网 Wi-Fi；
- DPT-RP1 的 Wi-Fi 已开启。

## 构建

1. 用 Xcode 打开 `ReadButton.xcodeproj`。
2. 在 Xcode 的 Signing & Capabilities 中选择你的 Apple Developer Team。
3. 确认 Bundle Identifier 可用，例如 `com.readbutton.watchapp`。
4. 选择真实 Apple Watch 作为运行目标。
5. Build and Run。

也可以使用命令行构建：

```bash
xcodebuild \
  -project ReadButton.xcodeproj \
  -scheme ReadButton \
  -destination 'generic/platform=watchOS' \
  build
```

项目使用 Swift Package Manager 拉取 `CryptoSwift`。首次构建需要网络访问 GitHub。

## 首次配对

1. 确认 DPT-RP1 和 Apple Watch 连接同一个 Wi-Fi。
2. 在 DPT-RP1 上打开 Wi-Fi 设置，并确认设备 IP 地址。
3. 在 ReadButton 配置页面输入 DPT 地址，例如 `192.168.31.227`。
4. 点击“测试连接”，确认能看到 DPT-RP1 型号和序列号。
5. 点击“开始配对”。
6. 查看 DPT 屏幕显示的 PIN，并在 Watch 输入。
7. 配对完成后进入书库，选择正在阅读的 PDF。

配对密钥保存在 Apple Watch Keychain 中。ReadButton 不需要读取 Digital Paper App 的电脑凭据。

## 日常使用

- 主屏显示当前书名和页码；
- 点击左侧大按钮上一页；
- 点击右侧大按钮下一页；
- 点击页码可跳转；
- 点击顶部书本图标进入书库并切换 PDF；
- 设置页面可以修改设备地址、测试连接、调整最近阅读排序或清除配对。

ReadButton 会在启动或从后台恢复时同步页码。连续翻页时使用一次请求直接调用 DPT 的阅读器控制接口，减少延迟。

## 网络与耗电

DPT-RP1 的网络地址可能由路由器 DHCP 改变。若地址变化，在设置中更新 DPT 地址。

应用不会保持后台网络轮询，但 DPT 长时间开启 Wi-Fi 仍会增加耗电；不阅读时建议关闭 DPT Wi-Fi 或让设备进入待机。

## 已知限制

DPT-RP1 的公开接口没有提供“当前阅读器正在打开的文档 ID”。因此 ReadButton 无法百分之百自动知道你是否在 DPT 上手动切换了书籍。应用通过页码变化和最近阅读记录进行推测；需要时可以从书库手动选择文档。

## 技术实现

ReadButton 使用 DPT-RP1 的局域网 HTTP/HTTPS 接口：

- `8080`：配对注册接口；
- `8443`：认证后的设备 API；
- `PUT /viewer/controls/open2`：打开指定文档和页码；
- CryptoSwift：Diffie-Hellman、PBKDF2、HMAC、AES 和大整数 RSA 支持。

## License

本项目代码采用 MIT License。
