# 顾海龙抖音 BUILD_LOG

## 1.0.20（分支 douyin-1.0.20，基底 966caf8）

### 双指长按——没有新加手势（重要，跟任务原定做法不同）
- 任务原定「feed 上加 UILongPressGestureRecognizer（numberOfTouchesRequired=2）」。
- 实际查代码：DYYY.xm 里早就有一个双指长按手势（%group DYYYSettingsGesture，
  %hook UIWindow -initWithFrame:，每个窗口都挂一个 numberOfTouchesRequired=2 的
  UILongPressGestureRecognizer，触发调 presentGHLSettingsHomeWithViewController: 开全屏设置页，
  %init 在 DYYY.xm:13355，已生效）。皇上 01:43 也确认了：「双指长按不是出现界面吗？」
- 所以没加新手势——把 presentGHLSettingsHomeWithViewController: 的实现改成开卡片，
  双指长按就直接开卡片界面。另加新手势会同时触发两个（全屏设置＋卡片），所以不加。
- 「抖音自己的双指长按是倍速」：查遍代码没找到——抖音/DYYY 的长按倍速是单指长按
  （handleLongPressFastSpeed，只剩方法定义，没找到注册处，疑似死代码）；双指长按
  只有 DYYY 自己这一个开设置的手势。若皇上真机发现双指长按同时触发倍速，发日志再查。

### 统一卡片的收口
- 三个入口都改成开卡片：抖音设置行「顾海龙抖音」（DYYYSettings.xm cellTappedBlock）、
  presentGHLSettingsHomeWithViewController:（双指长按、左栏入口、其他调用方全走它）、
  GHLShowFloatPanel 对外公开（GHLFeatures.h）。
- openSettingsWithViewController: / openSettingsFromView: 在代码里已无调用方（只剩定义），
  跟着 helper 一起改成开卡片，不留全屏入口。

### 画中画宿主 320×180（探针，未证实）
- 1.0.19 的 2×2 小宿主 11 次调用 0 回调；1.0.20 改成 320×180 可见尺寸，放在 feed 底部、
  底栏上方（居中，userInteractionEnabled=NO，不挡操作），宿主创建时记一行
  「画中画：宿主改成可见尺寸 320x180」。这只是最可能的方向——系统每次 start 都建了
  hosted window 但不显示、不回调；真机测了才算。宿主 view 常驻窗口（空的时候是透明的，
  看不见）；图层挂上去才看得见（显示视频内容，像个小预览窗）。

### 后台音频拆开关
- 「画中画 + 后台播放」一键拆成「切后台触发画中画」（GHLBackgroundAudio）＋「后台听视频」
  （GHLBackgroundListen，新 key）。setListenVideoStatus 的改写跟后台听视频走
  （经 DYYYEnableBackgroundListen 镜像；上游「基本设置」里也有同一 key 的「启用后台播放」行，
  三处同写一个 key）。
- 两个开关默认都开（registerDefaults）；后台听视频首次出现时沿用旧开关的值
  （皇上现在开着就继续开着，关着就继续关着），从没存过旧值才默认开。

### 卡片记住上次那页
- 关卡片时记顶页标识（root / section:N / about / log），下次打开恢复；恢复失败回根。
- 分区下标只认 0–10（11 个分区，11/11 对齐）；越界、旧版删掉的页一律回根，不崩。

### 日志页
- 刷新＋分享保留（右上角图标）；底部工具列加「复制日志」文字按钮（整份日志拷到剪贴簿，
  不过滤）＋顶部搜索框（过滤行，搜「画中画」「错误」等；大小写不敏感）。
- 诊断原话「右上角按钮不見」代码解释不了（按钮无条件设进 navigationItem，全代码无
  navigationBarHidden、无清按钮的 hook）——最可能是导航栏底色把图标糊掉；文字按钮
  不受这个影响。等皇上截图再定要不要改图标颜色。

### 其余
- 卡片：dimTap 加 delegate（卡片内触摸不接）＋cancelsTouchesInView=NO（双保险）；
  深色毛玻璃（UIVisualEffectView dark blur）＋去金边；导航栈缩进 10pt 露出毛玻璃边框、
  圆角 16；底部「完成」按钮（金字，点关卡片）。
- 画中画：C 路（A／C 共用那次 start）补 GHLNotePiPStartAttempted()（修 17:18:30 新 start
  1 秒被误杀）；后台任务抽成 helper，WillResignActive 和 DidEnterBackground 两条路都开；
  切后台触发加 10 秒冷却（距上次 start 未满 10 秒直接忽略，记一行）。
- 版本号 1.0.20（control＋DYYY_VERSION＋「1.0.20 已加载」＋更新日志加一行）。
