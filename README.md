# ReadButton

ReadButton 是一个面向 Sony Digital Paper 用户的轻量 Apple Watch 遥控器。它让你在阅读、演讲或双手不方便触碰电纸书时，直接从手腕控制 DPT-RP1 翻页和切换文档。

ReadButton 是纯 watchOS App：运行时由 Apple Watch 通过局域网直接连接 DPT，不需要 iPhone、Mac、云端服务或 ESP32 作为中间设备。

它不是 PDF 阅读器，也不会把 PDF 下载到 Watch。PDF 始终保存在 DPT 上，ReadButton 只负责发送阅读控制指令。

## 工具定位

ReadButton 适合以下场景：

- 坐在沙发或书桌前，把 DPT 放在支架上阅读；
- 演讲时使用 Apple Watch 遥控 DPT 翻页；
- 阅读过程中减少频繁抬手触摸大屏设备；
- 用 Watch 快速恢复一本书的阅读位置或跳转页码。

ReadButton 优先保证翻页按钮明显、网络请求少和日常操作简单。它不会在后台持续轮询 DPT，以减少 Apple Watch 和 DPT 的额外耗电。

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

## 使用教程

### 1. 准备网络

1. 在 DPT 上打开 Wi-Fi。
2. 将 DPT 和 Apple Watch 连接到同一个 Wi-Fi。
3. 在 DPT 的 Wi-Fi 详情中记录设备 IP 地址，例如 `192.168.31.227`。

若路由器开启了客户端隔离、访客网络隔离或 AP Isolation，Watch 将无法访问 DPT。请将两台设备放在允许局域网互访的普通 Wi-Fi 中。

### 2. 构建和安装

1. 用 Xcode 打开 `ReadButton.xcodeproj`。
2. 在 Signing & Capabilities 中选择你的 Apple Developer Team。
3. 若 Bundle Identifier 与其他应用冲突，将 `com.readbutton.watchapp` 改成你自己的唯一标识。
4. 选择真实 Apple Watch 作为运行目标。
5. 点击 Build and Run。

命令行构建：

```bash
xcodebuild \
  -project ReadButton.xcodeproj \
  -scheme ReadButton \
  -destination 'generic/platform=watchOS' \
  build
```

首次构建需要通过 Swift Package Manager 下载 `CryptoSwift`。

### 3. 首次配对

1. 在 ReadButton 配置页输入 DPT 的 IP 地址。
2. 点击“测试连接”。若成功，Watch 会显示设备型号和序列号。
3. 点击“开始配对”。
4. DPT 屏幕会显示一个 PIN。
5. 在 Apple Watch 输入这个 PIN 并完成配对。
6. 配对完成后，点击顶部书本图标进入书库。
7. 选择正在阅读的 PDF，DPT 会打开该文档保存的阅读页。

配对密钥保存在 Apple Watch Keychain 中。

### 4. 日常阅读

- 主屏显示当前书名和页码；
- 左侧大按钮上一页；
- 右侧大按钮下一页；
- 点击页码跳转到指定页；
- 点击顶部书本图标进入书库并切换 PDF；
- 设置页面可以修改地址、测试连接、调整最近阅读排序或清除配对。

如果你直接在 DPT 上手动翻页，重新打开 ReadButton 或让 App 回到前台即可同步最新页码。

### 5. 常见问题

**测试连接失败**

- 检查 Watch 和 DPT 是否连接同一个 Wi-Fi；
- 检查 DPT Wi-Fi 是否保持开启；
- 重新确认 DPT IP 地址；
- 检查路由器是否启用了客户端隔离。

**DPT 地址发生变化**

路由器 DHCP 可能会为 DPT 分配新地址。进入 ReadButton 设置，输入新的 IP 并重新测试连接。也可以在路由器中为 DPT 设置固定 DHCP 租约。

**切换书籍后位置不正确**

ReadButton 使用 DPT 保存的 `current_page` 恢复阅读位置。如果 DPT 尚未写入最新页码，可以在书库中刷新后重新选择。

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

## 参考与致谢

ReadButton 的 DPT-RP1 设备发现、注册认证和 REST API 调用方式，主要参考并移植自开源项目 [janten/dpt-rp1-py](https://github.com/janten/dpt-rp1-py)。感谢该项目作者和贡献者对 Sony Digital Paper 通信协议的长期研究与维护。

ReadButton 使用 [CryptoSwift](https://github.com/krzyzanowskim/CryptoSwift) 实现 Diffie-Hellman、PBKDF2、HMAC、AES 等密码算法。

ReadButton 是独立的社区项目，与 Sony、Fujitsu、Apple 及上述开源项目的作者没有官方隶属关系。

## License

MIT License
