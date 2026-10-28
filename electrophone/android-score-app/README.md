# 电子琴曲谱 Android App

这个 App 用于从在线 `catalog.json` 曲谱目录中搜索曲谱，下载已经转换好的
`NOTE` 文本，保存到手机，并通过经典蓝牙 SPP 直接发送给 JDY-31。2.0 还支持
八路实体压力键映射、八路手机虚拟琴键和演奏录音回传。

已发布在线曲谱目录：

```text
https://1q2w3e-wed.github.io/electrophone-scores/catalog.json
```

首次打开 App 会自动填写这个地址。将输入框清空并点击“联网更新曲谱目录”，
可以改用 App 内置的离线曲谱。

远程演奏和录音回传要求先烧录工程中的新版
`impl/pnr/electrophone.fs`。App 连接后会发送 `VERSION`；旧码流仍可发送
曲谱，但会禁用远程演奏和录音回传。

## 使用

1. 在手机系统蓝牙设置中先配对 `JDY-31-SPP`。
2. 安装 `电子琴曲谱.apk`。
3. 打开 App，点击“选择已配对蓝牙设备”并选择 JDY-31。
4. 在“在线曲谱目录”中填写 HTTPS 的 `catalog.json` 地址；留空则使用内置曲谱。
5. 输入歌名或别名，点击“搜索曲谱”。
6. 点击搜索结果，App 会下载并校验曲谱。
7. 点击“下载保存”。Android 10 及以上会保存到手机的“下载”目录：

```text
下载/ElectrophoneScores
```

   Android 9 及以下保存到 App 自己的 Documents 目录：

```text
Android/data/com.electrophone.scoreapp/files/Documents/ElectrophoneScores
```

8. 点击“蓝牙发送”可直接把 `SCORE CLEAR`、全部 `NOTE` 和 `PLAY SCORE`
   发送给设备。
9. 点击“复制内容”可复制完整 NOTE 文本，粘贴到现有通用蓝牙串口 App。

## 手机演奏

- “演奏”页可设置 `CH1～CH8 → 音符0～7` 的实体键映射；它只影响实体压力键。
- 演奏模式可选择“自由演奏”或“曲谱跟弹”。
- 曲谱跟弹使用当前选中的曲谱，按对当前音并松开后进入下一组。
- 实体键与手机键按错会提示但不会中断。
- 八个手机虚拟琴键支持多指按下和松开。
- 点击“编辑琴键”后再点目标琴键可设置名称、音高、力度、音色和效果；
  编辑模式下琴键不会发声；配置保存在手机中。
- 新音高已被其他虚拟琴键使用时，会自动交换两个琴键的音高，避免保存失败。
- 每个键的配置独立保存，效果器仍由 FPGA 全局共享，以最后按下的琴键为准。

## 32 音测试

3.3 版 App 可直接启停 FPGA 的 32 音测试，不需要另开蓝牙串口助手。

1. 在 App 中选择并连接 `JDY-31-SPP`。
2. 进入“演奏”页，点击“进入32音测试”。
3. 在 FPGA 上把左旋钮切到实时频谱页，顶部应显示 `ON 32/32`，并出现 32 个独立谱峰。
4. 测试完成后点击“退出32音测试”，实体键和手机虚拟琴键会恢复演奏。

测试期间 App 会锁定手机虚拟琴键、琴键编辑、曲谱跟弹和录音，避免测试音与演奏混在一起。
该功能需要烧录支持 `TEST 32`、`TEST OFF` 命令的新版 FPGA 固件。

## 录音回传

1. 在“录音”页点击“开始录音”，确认覆盖 FPGA 原事件。
2. 同时使用实体压力键和手机虚拟琴键演奏。
3. 点击“停止并取回”，FPGA 以二进制事件流上传录音。
4. App 自动还原成可编辑的 `NOTE delta,duration_ms,note,velocity,tone,effect`。
5. 可保存到手机、复制，或点击“发送回放”重新发送到 FPGA。
6. 点击“清除”只清空手机中已取回的内容，FPGA 内原始录音不会被删除。

录音保存的是音符事件，不是 WAV 音频。最多 1024 条事件。

## 在线目录

`score-site` 目录是可以上传到任意 HTTPS 静态网站或对象存储的完整示例：

```text
score-site/
├── catalog.json
└── scores/
    ├── 小星星.txt
    ├── 两只老虎.txt
    └── ...
```

上传后，在 App 中填写类似下面的地址：

```text
https://你的域名/曲谱/catalog.json
```

App 会相对 `catalog.json` 的地址解析曲谱文件路径。为了安全，App 拒绝 HTTP
地址和跳转到 HTTP 的请求。

## catalog.json

示例：

```json
{
  "version": 1,
  "scores": [
    {
      "title": "小星星",
      "aliases": ["Twinkle Twinkle Little Star", "一闪一闪亮晶晶"],
      "file": "scores/小星星.txt",
      "tags": ["儿歌", "入门"]
    }
  ]
}
```

App 会在 `title`、`aliases` 和 `tags` 中搜索。新增曲谱时上传对应 txt，
再往 `catalog.json` 增加一条记录即可。

演奏录音回传使用紧凑二进制协议：`A5 5A COUNT_HI COUNT_LO` 后跟
`COUNT` 条大端 32 位事件。App 会校验帧头、数量和完整长度后再显示。

## 曲谱限制

上传的文件必须已经是设备支持的 NOTE 格式。App 不抓取普通网页简谱，也不直接
转换 MusicXML、MIDI 或图片简谱。每个曲谱最多 1024 条 `NOTE`。

## 构建

要求 JDK 17、Android SDK 35。项目目录中已包含 Gradle Wrapper：

```text
gradlew.bat testDebugUnitTest assembleDebug
```

Debug APK 输出：

```text
app/build/outputs/apk/debug/app-debug.apk
```
