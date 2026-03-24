# DiskTester

一个用 SwiftUI 实现的 macOS 原生磁盘测速 MVP。
<img width="1483" height="970" alt="image" src="https://github.com/user-attachments/assets/4578876e-dfd5-40d9-9e48-24a83b9e7d26" />


当前版本已经支持：

- 顺序写入
- 顺序读取
- 随机写入
- 随机读取
- 实时吞吐曲线
- 卷信息识别
- 场景化结果解读

## 运行

在当前目录执行：

```bash
swift run
```

如果你安装了 Xcode，也可以直接用 Xcode 打开 [Package.swift](/Users/ibuprofen/syncSpace/souceCode/diskTester/Package.swift)。

## 默认参数

- 测试文件大小：`1024 MB`
- 顺序块大小：`1024 KB`
- 随机块大小：`4 KB`
- 随机操作次数：`25000`

测速时会在你选择的目录下创建一个隐藏临时文件，完成后自动删除。

## 当前实现重点

- 使用 `F_NOCACHE` 尽量降低页面缓存对结果的干扰
- 写入测试结束后执行 `F_FULLFSYNC` / `fsync`
- 随机测试使用 `pread` / `pwrite`
- UI 会显示卷名、文件系统、容量、实时速度和结果卡片

## 后续很适合继续加的功能

- 持续写入掉速测试
- 多轮测试与中位数结果
- 历史记录
- CSV / JSON 导出
- 更细的队列深度与并发配置
