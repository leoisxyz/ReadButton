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
- 不后台轮询，只在启动、恢复、选择文档或翻页时访问网络。

## 环境要求

- macOS 和 Xcode 16 或更新版本；
- Apple Watch，watchOS 10 或更新版本；
- Sony DPT-RP1/CP1 或兼容 Digital Paper 设备；
- Watch 与 DPT 连接同一个局域网 Wi-Fi；
- DPT 的 Wi-Fi 已开启。

## 构建和安装

1. 用 Xcode 打开 `ReadButton.xcodeproj`。
2. 在 Signing & Capabilities 中选择你的 Apple Developer Team。
3. 选择真实 Apple Watch 作为运行目标。
4. 点击 Build and Run。

命令行构建：

```bash
xcodebuild \
  -project ReadButton.xcodeproj \
  -scheme ReadButton \
  -destination 'generic/platform=watchOS' \
  build
```

首次构建需要通过 Swift Package Manager 下载 `CryptoSwift`。

## 首次配对

1. 确认 DPT 和 Apple Watch 连接同一个 Wi-Fi。
2. 在 DPT 的 Wi-Fi 设置中查看设备 IP 地址。
3. 在 ReadButton 配置页输入该 IP，例如 `192.168.31.227`。
4. 点击“测试连接”。
5. 点击“开始配对”。
6. 查看 DPT 屏幕上的 PIN，并在 Watch 输入。
7. 配对完成后进入书库，选择正在阅读的 PDF。

配对密钥保存在 Apple Watch Keychain 中。

## 日常使用

- 主屏显示当前书名和页码；
- 左侧大按钮上一页；
- 右侧大按钮下一页；
- 点击页码跳转到指定页；
- 点击顶部书本图标进入书库并切换 PDF；
- 设置页面可以修改地址、测试连接、调整最近阅读排序或清除配对。

## 网络与耗电

ReadButton 不保持后台网络轮询。DPT 长时间开启 Wi-Fi 仍会增加耗电，不阅读时建议关闭 DPT Wi-Fi 或让设备进入待机。

如果路由器通过 DHCP 更换了 DPT 地址，请在设置中更新地址。

## 已知限制

DPT 的公开接口没有提供“当前阅读器正在打开的文档 ID”。因此 ReadButton 无法百分之百自动知道你是否在 DPT 上手动切换了书籍。应用通过页码变化和最近阅读记录进行推测；需要时可以从书库手动选择文档。

## 技术实现

- `8080`：DPT 配对注册接口；
- `8443`：认证后的设备 API；
- `PUT /viewer/controls/open2`：打开指定文档和页码；
- CryptoSwift：Diffie-Hellman、PBKDF2、HMAC、AES 和 RSA 支持。

## License

MIT License
