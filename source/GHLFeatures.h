// 顾海龙抖音 (GHL) — 新增功能
// 基于 DYYY (MIT, Copyright (c) 2024 huami) 的个人二创，免费使用，仅限学习交流。
// 原 MIT 声明与 huami 版权行保留在 LICENSE 文件中，未做任何改动。
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

// 注意：GHLFeatures.xm 按 ObjC++ 编译，声明必须用 extern "C" 包住，
// 否则函数名会被 C++ 修饰，.m 文件调用方链接不到。
#ifdef __cplusplus
extern "C" {
#endif

@class AWEAwemeModel;

// MARK: - 设置键 (GHL*，与上游 DYYY* 键区分开)
// 睡眠定时 (1) — 值：@"关闭"/@"15分钟"/@"30分钟"/@"60分钟"
#define GHL_KEY_SLEEP_TIMER @"GHLSleepTimer"
// 画中画+后台播放 (2)
// 1.0.20：拆成两个开关，各管各的——
//   GHLBackgroundAudio = 切后台触发画中画；GHLBackgroundListen = 后台听视频
//   （setListenVideoStatus 的改写跟后台听视频走，经 DYYYEnableBackgroundListen 镜像，
//   上游「基本设置」里也有同一 key 的「启用后台播放」行，三处同写一个 key）。
#define GHL_KEY_BACKGROUND_AUDIO @"GHLBackgroundAudio"
#define GHL_KEY_BACKGROUND_LISTEN @"GHLBackgroundListen"
// 快进手势 (3)：长按倍速 + 双击左右快进 10 秒
#define GHL_KEY_SEEK_GESTURES @"GHLSeekGestures"
// 关键词过滤总开关 (5)：关掉则标题/用户/话题/直播过滤全部暂停
#define GHL_KEY_KEYWORD_FILTER @"GHLKeywordFilter"
// 一键清爽模式 (6)
#define GHL_KEY_CLEAN_MODE @"GHLCleanMode"
// 评论区增强 (7)
#define GHL_KEY_COMMENT_BLOCK_KEYWORDS @"GHLCommentBlockKeywords" // 逗号分隔
#define GHL_KEY_COMMENT_AUTO_EXPAND @"GHLCommentAutoExpand"     // 长评论自动展开
// 批量下载 (8)：点赞自动保存
#define GHL_KEY_AUTO_SAVE_LIKED @"GHLAutoSaveLiked"
// 夜间护眼 (9)
#define GHL_KEY_NIGHT_MODE @"GHLNightMode"
#define GHL_KEY_NIGHT_BRIGHTNESS @"GHLNightBrightness" // 0-1 小数，默认 0.3
// 更多手势 (10)
#define GHL_KEY_TRIPLE_TAP_CLEAR @"GHLTripleTapClear" // 三指双击清屏
#define GHL_KEY_EDGE_SWIPE_NEXT @"GHLEdgeSwipeNext"   // 边缘滑动切下一个视频
#define GHL_KEY_VOLUME_SEEK @"GHLVolumeSeek"         // 音量键调进度
// 直播间净化 (12)
#define GHL_KEY_LIVE_PURIFY @"GHLLivePurify"
// BGM 一键保存 (15)
#define GHL_KEY_BGM_SAVE @"GHLBGMSave"
// 自动跳过开屏广告 (16)
#define GHL_KEY_NO_SPLASH_AD @"GHLNoSplashAd"
// 去水印分享直链 (18)
#define GHL_KEY_NO_WATERMARK_SHARE_LINK @"GHLNoWatermarkShareLink"
// 评论区图片一键存原图 (19)
#define GHL_KEY_COMMENT_IMAGE_SAVE @"GHLCommentImageSave"
// 弹幕浮层 (20)
#define GHL_KEY_COMMENT_DANMAKU @"GHLCommentDanmaku"
// 侧边栏自定义排序 (22)
#define GHL_KEY_SIDEBAR_REORDER @"GHLSidebarReorder"
#define GHL_KEY_SIDEBAR_ORDER @"GHLSidebarOrder" // 如：评论,点赞,分享,收藏（从上到下）
// 私信防撤回 (24)：实验功能，目前只有启动探针日志，待真机日志验证
#define GHL_KEY_ANTI_RECALL @"GHLAntiRecall"
// 视频截图去水印 (25)
#define GHL_KEY_SCREENSHOT_CLEAN @"GHLScreenshotClean"
// 1.0.23：跳过 AD 章节（清单 2 号）——探测：广告章节没有可确认的识别点，
// 开关开后只在日志里 dump 章节模型字段，不谎称做成；等真机日志定下识别字段再接跳过。
#define GHL_KEY_SKIP_AD_CHAPTER @"GHLSkipAdChapter"
// 1.0.23：评论文字变蓝（清单 5 号）——启发式定位评论正文标签，需真机验证
#define GHL_KEY_BLUE_COMMENT_TEXT @"GHLBlueCommentText"
// 楼中楼一键展开 (29)
#define GHL_KEY_EXPAND_REPLIES @"GHLExpandReplies"
// 视频原声提取 (30)
#define GHL_KEY_EXTRACT_AUDIO @"GHLExtractAudio"
// 语音包 (31)：xuu 式管理器——语音包列表（文件夹/分类、按名字或 voiceId 搜索）、
// 试听、选中后输入文字合成语音、发到私信/直播。音色分两档：
//   a. 内置档：iOS 自带 AVSpeechSynthesisVoice（本机中文音色），不联网、不用 key；
//   b. 在线档：Fish Audio（api.fish.audio/v1/tts，列表 GET /model），key 已填好
//      （设置页“Fish Audio API Key”显示的就是默认 key，皇上想换随时改）。
// 没有 key 只用内置档；绝不用 xuu 的 token、不调它那个要验证的远程服务、不复制它的代码。
// 诚实说明：这不是真人声音克隆——在线音色是 Fish Audio 的 TTS 模型音色。
// 直播里发语音目前只做运行期探针（GHLProbeLiveVoiceSender），不注入、不发包。
#define GHL_KEY_VOICE_PACKAGE @"GHLVoicePackage"       // 总开关
#define GHL_KEY_VOICE_PACKAGE_ID @"GHLVoicePackageID"  // 选中的语音包 id，如 @"sys:<系统语音 identifier>" 或 @"fish:<Fish Audio 模型 id>"
#define GHL_KEY_FISH_AUDIO_API_KEY @"GHLFishAudioAPIKey" // 皇上自己的 Fish Audio key（在线音色用）；设置页改了就用改后的
#define GHL_DEFAULT_FISH_AUDIO_API_KEY @"sk-fish-7Ncx6vznkdiz1H0xD5ua8G8oSuovY5IaLRDBx7-WTKU" // 皇上自己的 Fish Audio key，已填好（免费账号，永不过期）；只放皇上自己的私有仓库和包里
#define GHL_KEY_FISH_AUDIO_VOICES_CACHE @"GHLFishAudioVoicesCache" // 在线语音包列表缓存（NSArray<NSDictionary：id/title>）
#define GHL_KEY_VOICE_PACKAGE_MANAGER @"GHLVoicePackageManager" // 打开语音包管理器（Picker 入口，值无意义）
// 1.0.2 新增语音四项（照 xuu 卡片的语音功能；接口未验证，先做探针，见 GHLProbeVoiceFeatures）：
// 语音消息转发 / 设置语音秒数 / 替换语音评论 / 保存语音评论（保存复用 (36) 的 GHL_KEY_COMMENT_VOICE_SAVE）。
#define GHL_KEY_VOICE_FORWARD @"GHLVoiceForward"                 // 语音消息转发（实验，需真机日志验证）
#define GHL_KEY_VOICE_DURATION @"GHLVoiceDuration"               // 设置语音秒数（实验，需真机日志验证）
#define GHL_KEY_VOICE_REPLACE_COMMENT @"GHLVoiceReplaceComment" // 替换语音评论（实验，需真机日志验证）
// 1.0.4 语音包收藏：收藏的 voiceId 列表（NSArray<NSString *>），收藏的排在管理器最前面
#define GHL_KEY_VOICE_FAVORITES @"GHLVoiceFavorites"

// MARK: - 1.0.4 新增（设置备份/恢复、下载管理、深色模式、悬浮按钮自定义、更新日志、换龙头/换背景）
// 跟随系统深色（设置主页和子页；默认开；关了就强制浅色）
#define GHL_KEY_FOLLOW_SYSTEM_DARK @"GHLFollowSystemDark"
// 悬浮按钮自定义：每个按钮点一下/长按各选一个动作，值见下面的 GHL_FLOAT_ACTION_*（@"默认" = 原来功能）
#define GHL_KEY_SPEED_BUTTON_TAP @"GHLSpeedButtonTapAction"
#define GHL_KEY_SPEED_BUTTON_LONGPRESS @"GHLSpeedButtonLongPressAction"
#define GHL_KEY_CLEAR_BUTTON_TAP @"GHLClearButtonTapAction"
#define GHL_KEY_CLEAR_BUTTON_LONGPRESS @"GHLClearButtonLongPressAction"
#define GHL_FLOAT_ACTION_DEFAULT @"默认"
#define GHL_FLOAT_ACTION_DOWNLOAD @"下载当前视频"
#define GHL_FLOAT_ACTION_CLEAR @"清屏"
#define GHL_FLOAT_ACTION_SPEED @"倍速切换"
#define GHL_FLOAT_ACTION_DANMAKU @"弹幕开关"
#define GHL_FLOAT_ACTION_SCREENSHOT @"截图去水印"
// 1.0.18 浮动按钮＋卡片面板：视频页左上角龙头浮动钮（默认开，设置页「悬浮按钮」分区可关）
#define GHL_KEY_FLOAT_PANEL_BUTTON @"GHLFloatPanelButton"
// 动作型入口（Picker 行，值本身无意义，选完即执行）
#define GHL_KEY_DOWNLOAD_MANAGER @"GHLDownloadManager"   // 打开下载管理页
#define GHL_KEY_LOG_VIEWER @"GHLLogViewer"             // 打开抖音日志查看页（1.0.6）
#define GHL_KEY_IMPORT_SETTINGS @"GHLImportSettings"     // 导入配置（系统文件选择器选 .plist）
#define GHL_KEY_EXPORT_SETTINGS @"GHLExportSettings"     // 导出配置（分享“顾海龙抖音配置.plist”）
#define GHL_KEY_RESET_SETTINGS @"GHLResetSettings"       // 恢复默认配置（先弹确认框）
#define GHL_KEY_CHANGE_BACKGROUND @"GHLChangeBackground" // 更换背景图（相册选图）
#define GHL_KEY_RESET_BACKGROUND @"GHLResetBackground"   // 恢复默认背景
#define GHL_KEY_RESET_LOGO @"GHLResetLogo"               // 恢复默认龙头
// 更新日志：上次见过的版本号（变了就进设置主页时弹一次）
#define GHL_KEY_LAST_SEEN_VERSION @"GHLLastSeenVersion"
// 下载管理：经本插件成功保存的媒体数量（自 1.0.4 起统计；1.0.4 之前没有记录，做不出历史数）
#define GHL_KEY_DOWNLOAD_SAVED_COUNT @"GHLDownloadSavedCount"

// MARK: - 1.0.5 新增（手势自定义）
// 手势自定义：每个手势选一个动作，值见下面的 GHL_GESTURE_ACTION_*（@"默认" = 不做任何事）。
// 三击默认不开识别器（不拖慢双击点赞）；双指双击、左滑、右滑识别器常驻，处理时读 live 设置。
#define GHL_KEY_GESTURE_TRIPLE_TAP @"GHLGestureTripleTap"                       // 三击
#define GHL_KEY_GESTURE_TWO_FINGER_DOUBLE_TAP @"GHLGestureTwoFingerDoubleTap"   // 双指双击
#define GHL_KEY_GESTURE_SWIPE_LEFT @"GHLGestureSwipeLeft"                       // 左滑
#define GHL_KEY_GESTURE_SWIPE_RIGHT @"GHLGestureSwipeRight"                     // 右滑
#define GHL_GESTURE_ACTION_MUTE @"静音开关"
#define GHL_GESTURE_ACTION_NEXT @"下一个视频"

// MARK: - 语音包 (31)
typedef NS_ENUM(NSInteger, GHLVoicePackageSource) {
    GHLVoicePackageSourceBuiltIn = 0,   // 内置：iOS 自带 TTS 语音
    GHLVoicePackageSourceFishAudio = 1, // 在线：Fish Audio 模型音色
    GHLVoicePackageSourceCustom = 2,    // 1.0.24：导入：录好的音频文件（点一下就播放，不能合成文字）
};
// 一个语音包（管理器列表里的一项）。内置档 voiceId 形如 @"sys:<系统语音 identifier>"，
// 在线档 voiceId 形如 @"fish:<Fish Audio 模型 id>"，导入档形如 @"custom:<文件名>"。
@interface GHLVoicePackageInfo : NSObject
@property(nonatomic, copy) NSString *voiceId;
@property(nonatomic, copy) NSString *displayName;
@property(nonatomic, copy) NSString *category; // 文件夹/分类：@"内置" / @"在线" / @"我的导入" / 自建文件夹名
@property(nonatomic, assign) GHLVoicePackageSource source;
@property(nonatomic, copy, nullable) NSString *systemVoiceIdentifier; // 内置档
@property(nonatomic, copy, nullable) NSString *fishModelId;           // 在线档
@property(nonatomic, copy, nullable) NSString *audioFilePath;         // 1.0.24：导入档（本地音频文件全路径）
+ (instancetype)packageWithVoiceId:(NSString *)voiceId
                       displayName:(NSString *)displayName
                          category:(NSString *)category
                            source:(GHLVoicePackageSource)source
             systemVoiceIdentifier:(nullable NSString *)systemVoiceIdentifier
                       fishModelId:(nullable NSString *)fishModelId;
// 1.0.24：导入档构造（name 显示名，filePath 音频文件全路径，folder 文件夹名）
+ (instancetype)customPackageWithName:(NSString *)name filePath:(NSString *)filePath folder:(NSString *)folder;
@end
// 全部语音包（内置在前、在线在后、导入最后；在线档只在有缓存列表时出现）
// 1.0.24：内置/在线音色被移进文件夹时，category 就是文件夹名（见 GHL_KEY_VOICE_FOLDER_MAP）。
NSArray<GHLVoicePackageInfo *> *GHLVoicePackageList(void);
// 按分类取（@"内置" / @"在线" / @"我的导入" / 自建文件夹名）
NSArray<GHLVoicePackageInfo *> *GHLVoicePackagesInCategory(NSString *category);
// 按名字或 voiceId 搜索（大小写不敏感）
NSArray<GHLVoicePackageInfo *> *GHLSearchVoicePackages(NSString *query);
// 语音包 id 列表（设置页 Picker 用；1.0.24：只给能合成文字的，导入的录音不进）
NSArray<NSString *> *GHLVoicePackageIDs(void);
NSString *GHLVoicePackageDisplayNameForID(NSString *voiceId);
GHLVoicePackageInfo *GHLVoicePackageForID(NSString *voiceId);
// 用选中语音包把一段文字念出来（试听用；在线档需 key，没有 key 会 Toast 提示；
// 1.0.24：导入档直接播文件）
void GHLPreviewVoicePackage(NSString *voiceId);
// 用选中语音包把一段文字合成语音文件（内置 .caf / 在线 .mp3），完成回调给文件 URL
// 1.0.24：导入档合成不了文字，直接回调 nil。
void GHLSynthesizeVoicePackageText(NSString *text, NSString *voiceId, void (^completion)(NSURL *fileURL));
// 从 Fish Audio 拉在线语音包列表（需 key；成功后缓存并回调，失败回调 error）
void GHLFetchFishAudioVoiceListWithCompletion(void (^completion)(NSArray<GHLVoicePackageInfo *> *voices, NSError *error));
// 打开语音包管理器（列表/分类/搜索/试听/选中）
void GHLPresentVoicePackageManagerFromViewController(UIViewController *viewController);
// 1.0.24：导入的语音 + 文件夹（文件夹分组、导入导出都在管理器里）
// 导入的语音存在 Documents/DYYY/VoicePackages/，记录在 GHL_KEY_CUSTOM_VOICES。
#define GHL_KEY_CUSTOM_VOICES @"GHLCustomVoices" // 导入的语音：数组，字典 @{@"name", @"file", @"folder"}
#define GHL_KEY_VOICE_CUSTOM_FOLDERS @"GHLCustomVoiceFolders" // 自建文件夹名数组（“我的导入”是内置的，不存这里）
#define GHL_KEY_VOICE_FOLDER_MAP @"GHLVoiceFolderMap" // voiceId -> 文件夹（内置/在线音色移入文件夹用）
#define GHL_KEY_VOICE_ADD_MENU_LAST @"GHLVoiceAddMenuLast" // + 菜单上次选的项（选项表要存一个值，无实际意义）
#define GHL_KEY_VOICE_ROW_MENU_LAST @"GHLVoiceRowMenuLast" // 行长按菜单上次选的项（同上）
NSString *GHLCustomVoicePackagesDirectory(void);
NSArray<NSString *> *GHLCustomVoiceFolders(void); // “我的导入”在前，自建文件夹按建的顺序
void GHLCreateVoiceFolder(NSString *name);
void GHLDeleteVoiceFolder(NSString *name); // 里面的语音回“我的导入”
void GHLMoveVoiceToFolder(NSString *voiceId, NSString *folder); // folder 空 = 移出，回默认分类
void GHLDeleteCustomVoice(NSString *voiceId); // 删记录 + 删文件 + 清收藏/选中
NSString *GHLFolderForVoiceId(NSString *voiceId); // 当前所在文件夹（分类名）
void GHLImportVoiceAudioFileAtURL(NSURL *url, void (^done)(BOOL success, NSString * _Nullable name)); // mp4/mov 转音频，其他音频直接复制
void GHLExportCustomVoices(UIViewController *presenter, NSArray<NSString *> *voiceIds); // 分享文件；voiceIds 为空 = 全部
NSString *GHLFileSizeText(NSString *path); // “1.2 MB”这种
// 运行期探针：抖音里有没有直播发语音的相关类（只记日志，不 hook、不发包）
void GHLProbeLiveVoiceSender(void);
// 运行期探针：语音消息转发/语音秒数/替换语音评论/保存语音评论相关类（只记日志，不 hook、不发包）
void GHLProbeVoiceFeatures(void);

// MARK: - 32-43（xuu 抖音助手行为参考，代码全部自己写；只学功能清单，不抄它的代码）
// (32) 自动点赞
#define GHL_KEY_AUTO_LIKE @"GHLAutoLike"
#define GHL_KEY_AUTO_LIKE_MAX @"GHLAutoLikeMaxCount" // 每会话上限，默认 100
// (33) 自动抢红包
#define GHL_KEY_AUTO_RED_PACKET @"GHLAutoRedPacket"
#define GHL_KEY_RED_PACKET_BLACKLIST @"GHLRedPacketBlacklist" // 逗号分隔的作者抖音号
#define GHL_KEY_RED_PACKET_DELAY @"GHLRedPacketDelay"         // 秒，默认 1
#define GHL_KEY_RED_PACKET_AUTO_REPLY @"GHLRedPacketAutoReply"
#define GHL_KEY_RED_PACKET_REPLY_TEXT @"GHLRedPacketReplyText" // 默认 谢谢老板
// (34) 自动开直播抽奖
#define GHL_KEY_AUTO_LIVE_LOTTERY @"GHLAutoLiveLottery"
// (35) 防撤回全套
#define GHL_KEY_HIDE_TYPING @"GHLHideTyping"             // 隐藏“正在输入”（探针，未验证）
#define GHL_KEY_HIDE_READ_RECEIPT @"GHLHideReadReceipt" // 隐藏已读回执（探针，未验证）
#define GHL_KEY_DISABLE_VISIT_REPORT @"GHLDisableVisitReport" // 不上报访客记录（接上游隐私拦截）
// (36) 评论语音播放/保存
#define GHL_KEY_COMMENT_VOICE @"GHLCommentVoice"
#define GHL_KEY_COMMENT_VOICE_SAVE @"GHLCommentVoiceSave"
// (37) 下载增强
#define GHL_KEY_DOUBLE_TAP_DOWNLOAD @"GHLDoubleTapDownload" // 双击下载（开后双击不再快进）
#define GHL_KEY_LONG_PRESS_DOWNLOAD @"GHLLongPressDownload" // 长按下载（接上游）
#define GHL_KEY_LONG_PRESS_GRID_PANEL @"GHLLongPressGridPanel" // 长按面板网格风格（龙头，1.0.9；默认开，%ctor 里 registerDefaults）
#define GHL_KEY_GRID_PANEL_AVATAR @"GHLGridPanelAvatar"     // 长按面板头像（1.0.11；Picker 入口，值无意义）
#define GHL_KEY_ABOUT_PAGE @"GHLAboutPage"                 // 关于顾海龙抖音（1.0.14；深色品牌页入口，值无意义）
#define GHL_KEY_DOWNLOAD_PROGRESS @"GHLDownloadProgress"   // 下载进度日志+提示
#define GHL_KEY_SAVE_AVATAR @"GHLSaveAvatar"               // 保存头像（长按面板）
#define GHL_KEY_COPY_PROFILE @"GHLCOPYProfile"             // 复制个人资料（长按面板）
// 1.0.23：长按面板新增两项（清单 9 号，按抖音图层的做法）——获取作品数据、图片预览
#define GHL_KEY_AWEME_DATA @"GHLAwemeData"                 // 获取作品数据（长按面板）
#define GHL_KEY_IMAGE_PREVIEW @"GHLImagePreview"           // 图片预览（长按面板，图集才有）
// MARK: - 1.0.23 第二批（影片清单 42–78 号，Lee 2026-11-15 勾中 22 项并进同一版，版本号不变）
// 48 自动连播：播完自动切下一个（按视频时长累计，2 秒巡检采样，需真机验证）
#define GHL_KEY_AUTO_PLAY_NEXT @"GHLAutoPlayNext"
// 51 快捷面板背景图片（长按网格面板的背景自选图；只用在面板表面，不动设置卡片）
#define GHL_KEY_QUICK_PANEL_BG @"GHLQuickPanelBackground"       // Picker 入口：从相册选图
#define GHL_KEY_QUICK_PANEL_BG_CLEAR @"GHLQuickPanelBackgroundClear" // Picker 入口：恢复默认背景
// 53 面板材质三选一（只用在长按网格面板）：磨砂 / 液态玻璃 / 清透玻璃
// （真液态玻璃是 iOS 26 的 UIGlassEffect，iOS 16.5 上用加厚材质＋淡白 tint 近似）
#define GHL_KEY_QUICK_PANEL_MATERIAL @"GHLQuickPanelMaterial"
// 54 功能排列（长按网格面板）：每排2个 / 每排3个 / 每排4个 / 横向等列 / 自定义
#define GHL_KEY_QUICK_PANEL_COLUMNS @"GHLQuickPanelColumns"
#define GHL_KEY_QUICK_PANEL_COLUMNS_CUSTOM @"GHLQuickPanelColumnsCustom" // 自定义时的列数（1-6，默认 3）
// 56 背景模糊度（长按网格面板，0-100，默认 58，跟他演示的 58% 一致）
#define GHL_KEY_QUICK_PANEL_BLUR @"GHLQuickPanelBlur"
// 1.0.24：下载面板可调——格子高度 72-120（默认 92）、左右边距 0-48（默认 16）、
// 格子透明度 0.1-1.0（空=跟微透明开关）、格子颜色 白色/金色/深灰（默认 白色）。
#define GHL_KEY_QUICK_PANEL_CELL_HEIGHT @"GHLQuickPanelCellHeight"
#define GHL_KEY_QUICK_PANEL_SIDE_MARGIN @"GHLQuickPanelSideMargin"
#define GHL_KEY_QUICK_PANEL_CELL_ALPHA @"GHLQuickPanelCellAlpha"
#define GHL_KEY_QUICK_PANEL_CELL_COLOR @"GHLQuickPanelCellColor"
// 59 仅看一次开启下载按钮（探测：查看器类没找到，开关只做探针日志）
#define GHL_KEY_VIEW_ONCE_DOWNLOAD @"GHLViewOnceDownload"
// 61 推荐页跳过购物视频（按 ecommerceBelowLabel 认购物视频，只在推荐页）
#define GHL_KEY_SKIP_SHOPPING @"GHLSkipShopping"
// 64 长按菜单微透明（长按网格面板格子底更透）
#define GHL_KEY_LONG_PRESS_PANEL_TRANSLUCENT @"GHLLongPressPanelTranslucent"
// 66 评论区视图微透（评论面板背景更透一点）
#define GHL_KEY_COMMENT_VIEW_TRANSLUCENT @"GHLCommentViewTranslucent"
// 67 显示功能按钮（视频页浮动按钮三档）：关闭 / 倍速 / 快进
#define GHL_KEY_FLOAT_FUNCTION_BUTTON @"GHLFloatFunctionButton"
// 70 双击消息快捷回复（消息列表/聊天页双击消息，打开输入框）
#define GHL_KEY_IM_DOUBLE_TAP_REPLY @"GHLIMDoubleTapReply"
// 71 消息界面点加号弹出相册图片（探测：加号按钮类没确认，开关只记探针日志）
#define GHL_KEY_IM_PLUS_ALBUM_PROBE @"GHLIMPlusAlbumProbe"
// 73 续火花自动发消息（长按联系人头像才触发；模板为空或找不到发送按钮时只填文字不自动发）
#define GHL_KEY_STREAK_AUTO_SEND @"GHLStreakAutoSend"
#define GHL_KEY_STREAK_TEMPLATES @"GHLStreakTemplates" // 多条模板用 | 分隔
// 75 玻璃评论面板 + AI 解析
#define GHL_KEY_COMMENT_GLASS_PANEL @"GHLCommentGlassPanel" // 玻璃评论面板（浅色玻璃＋顶部 评论/AI 解析 双页签）
#define GHL_KEY_AI_PARSE_KEY @"GHLAIParseKey"               // AI 解析 API Key（OpenAI 兼容接口，用户自己填）
#define GHL_KEY_AI_PARSE_BASE_URL @"GHLAIParseBaseURL"       // 接口地址，如 https://api.openai.com/v1
#define GHL_KEY_AI_PARSE_MODEL @"GHLAIParseModel"           // 模型，默认 gpt-3.5-turbo
// 78 底部悬浮毛玻璃胶囊栏（底栏收成悬浮圆角毛玻璃条）
#define GHL_KEY_TABBAR_CAPSULE @"GHLTabBarCapsule"
// (38) 左滑返回、界面缩放、深色键盘、自定义底栏
#define GHL_KEY_LEFT_SWIPE_BACK @"GHLLeftSwipeBack"
#define GHL_KEY_INTERFACE_SCALE @"GHLInterfaceScale"
#define GHL_KEY_INTERFACE_SCALE_VALUE @"GHLInterfaceScaleValue" // 默认 1.0
#define GHL_KEY_DARK_KEYBOARD @"GHLDarkKeyboard"
#define GHL_KEY_CUSTOM_TAB_BAR @"GHLCUSTOMTabBar"
#define GHL_KEY_HIDDEN_TABS @"GHLHiddenTabs" // 逗号分隔，如 商城,消息
// (39) 直播工具
#define GHL_KEY_LIVE_DURATION @"GHLLiveDuration"
#define GHL_KEY_LIVE_RECORD @"GHLLiveRecord"
#define GHL_KEY_SKIP_LIVE @"GHLSkipLive" // 跳过直播（接上游）
#define GHL_KEY_LIVE_SEND_MESSAGE @"GHLLiveSendMessage"
#define GHL_KEY_LIVE_SEND_MESSAGE_TEXT @"GHLLiveSendMessageText"
// (40) 弹幕颜色、评论区模糊、顶栏透明、隐藏状态栏（均接上游已有实现）
#define GHL_KEY_DANMAKU_COLOR @"GHLDanmakuColor"
#define GHL_KEY_DANMAKU_COLOR_VALUE @"GHLDanmakuColorValue" // 十六进制或 random
#define GHL_KEY_COMMENT_BLUR @"GHLCommentBlur"
#define GHL_KEY_TOP_BAR_TRANSPARENT @"GHLTopBarTransparent"
#define GHL_KEY_TOP_BAR_TRANSPARENCY @"GHLTopBarTransparency" // 0-1，默认 0.5
#define GHL_KEY_HIDE_STATUS_BAR @"GHLHideStatusBar"
// (41) 防阅后即焚（探针，未验证）
#define GHL_KEY_ANTI_BURN @"GHLAntiBurn"
// (42) 改数字显示
#define GHL_KEY_FAKE_STATS @"GHLFakeStats" // 改视频点赞/播放数显示
#define GHL_KEY_FAKE_LIKE_COUNT @"GHLFakeLikeCount"
#define GHL_KEY_FAKE_PLAY_COUNT @"GHLFakePlayCount"
#define GHL_KEY_FAKE_LIVE_USER_COUNT @"GHLFakeLiveUserCount" // 改直播间人数显示
#define GHL_KEY_FAKE_LIVE_USER_COUNT_VALUE @"GHLFakeLiveUserCountValue"
// (43) 音频管理
#define GHL_KEY_AUDIO_SHARE @"GHLAudioShare" // 音频分享（长按面板）
#define GHL_KEY_LIVE_AUDIO_MUTE @"GHLLiveAudioMute" // 直播音频单独静音
#define GHL_KEY_COMMENT_AUDIO_MUTE @"GHLCommentAudioMute" // 评论音频单独静音（探针，未验证）
// (44) 1.0.8 美化：调色盘 / 主题预设 / 侧边栏 / 进度条 / 头像金边 / 弹幕样式 / 底栏毛玻璃 / 双击爱心探针
#define GHL_KEY_THEME_PRESET @"GHLThemePreset" // none=无 gold=金龙 ice=冰蓝 pink=樱粉 night=暗夜
#define GHL_KEY_SIDEBAR_BEAUTIFY @"GHLSidebarBeautify"
#define GHL_KEY_SIDEBAR_ICON_SCALE @"GHLSidebarIconScale" // 0.5-1.5，默认 1.0
#define GHL_KEY_SIDEBAR_SPACING @"GHLSidebarSpacing" // pt，默认 0
#define GHL_KEY_SIDEBAR_PILL_BG @"GHLSidebarPillBackground"
#define GHL_KEY_PROGRESS_BAR_BEAUTIFY @"GHLProgressBarBeautify"
#define GHL_KEY_PROGRESS_BAR_COLOR @"GHLProgressBarColor" // 十六进制，默认 D4AF37
#define GHL_KEY_PROGRESS_BAR_THICKNESS @"GHLProgressBarThickness" // 细/标准/粗
#define GHL_KEY_AVATAR_GOLD_RING @"GHLAvatarGoldRing"
#define GHL_KEY_DANMAKU_STYLE @"GHLDanmakuStyle"
#define GHL_KEY_DANMAKU_FONT_SCALE @"GHLDanmakuFontScale" // 0.5-2.0，默认 1.0
#define GHL_KEY_TAB_BAR_FONT_SCALE @"GHLTabBarFontScale" // 1.0.24：底部字体大小 0.8-1.3，默认 1.0
// 1.0.24：双击下载——按位置（左半边直接保存，右半边弹菜单）；弹窗精简（只留下载相关）。
#define GHL_KEY_DOUBLE_TAP_POSITION @"GHLDoubleTapPosition"
#define GHL_KEY_DOUBLE_TAP_POPUP_COMPACT @"GHLDoubleTapPopupCompact"
// 1.0.24：文案备忘录——只做备忘（定时发送不做）；行入口 + 存储数组（字典 text/date）。
#define GHL_KEY_MEMO_PAGE @"GHLMemoPage"
#define GHL_KEY_MEMO_LIST @"GHLMemoList"
#define GHL_KEY_DANMAKU_STROKE @"GHLDanmakuStroke" // pt，空=原生
#define GHL_KEY_DANMAKU_ALPHA @"GHLDanmakuAlpha" // 0-1，默认 1.0
#define GHL_KEY_DANMAKU_AUTO_FADE @"GHLDanmakuAutoFade"
#define GHL_KEY_TABBAR_GLASS @"GHLTabBarGlass"
#define GHL_KEY_DOUBLE_TAP_HEART_PROBE @"GHLDoubleTapHeartProbe" // 双击爱心探针（实验，需真机日志验证）

// MARK: - 32-43 功能入口
void GHLMaybeAutoLike(void); // (32) 切视频后自动点赞（带每会话上限，已点赞的不重复点）
void GHLStartHousekeepingTimer(void); // (33)(34)(38)(39)(42) 每 2 秒跑一次的巡检
void GHLHousekeepingTick(void);
BOOL GHLIsInLiveRoom(void); // (39)(42) 是否在直播间（按顶层 VC 类名含 Live 判断）
void GHLUpdateLiveDurationLabel(void); // (39) 直播时长悬浮显示
void GHLTrySendLiveMessage(NSString *text); // (33)(39) 尽力往直播间输入框发一条消息（遍历找输入框+发送按钮）
void GHLDownloadCurrentVideoWithProgress(void); // (37) 双击下载当前视频（带进度日志）
void GHLApplyInterfaceScaleInView(UIView *view); // (38) 侧边按钮缩放
void GHLApplyDarkKeyboardInView(UIView *view); // (38) 评论输入框深色键盘
void GHLApplyFakeStatsInView(UIView *view); // (42) 点赞数/播放数显示改写
void GHLProbePrivacyFeatures(void); // (35)(41) 探针：正在输入/已读回执/阅后即焚相关类
void GHLProbeCommentVoice(void); // (36) 探针：评论语音相关类
void GHLProbeLiveRoom(void); // (39)(42) 探针：直播间相关类

// MARK: - 通用工具
BOOL GHLGetBool(NSString *key);
NSString *GHLGetString(NSString *key);
// 在主线程跑 block（已在主线程就直接跑）
void GHLRunOnMain(dispatch_block_t block);
// 关键词过滤总开关：键不存在时默认开（保持上游已有过滤行为不变）
BOOL GHLKeywordFilterEnabled(void);
// 跟随系统深色：键不存在时默认开（1.0.4 新增开关，没设过就跟随系统）
BOOL GHLFollowSystemDarkEnabled(void);
// 诊断日志主路径（Documents/DYYY/GuHaiLongDouyin.log；拿不到就返回 nil）
NSString *GHLLogFilePath(void);
// 写诊断日志到 Documents/DYYY/GuHaiLongDouyin.log（App 沙盒内；旧路径只作兜底）
void GHLLog(NSString *format, ...);

// MARK: - 播放器
// 找到当前正在播放的 AVPlayer（1.0.15：全部窗口递归找 AVPlayerLayer，不只 keyWindow；
// 画中画专用查找另见 GHLFeatures.xm 里的 GHLFindPlayingAVPlayerForPiP，会多走一路控制器 KVC 探针）
AVPlayer *GHLFindPlayingAVPlayer(void);
// 找到当前播放视频的 AVPlayerLayer（1.0.15：全部窗口递归找，不只 keyWindow）
AVPlayerLayer *GHLFindPlayingAVPlayerLayer(void);
// 当前播放进度（秒），找不到返回 -1
double GHLCurrentPlayerTime(void);
// 快进/快退 N 秒（可正可负）
void GHLSeekCurrentPlayerBySeconds(double seconds);
// 暂停当前播放
void GHLPauseCurrentPlayer(void);
// 当前视频的 AwemeModel（通过悬浮按钮协调器拿当前 interaction controller）
AWEAwemeModel *GHLCurrentAwemeModel(void);

// MARK: - 各功能入口（供设置页开关回调调用）
void GHLRestartSleepTimer(void);        // (1) 按 GHLSleepTimer 的值重建/取消定时
void GHLApplyNightMode(BOOL on);       // (9)
void GHLApplyLivePurification(BOOL on); // (12) 开：记下现有值并全开隐藏项；关：恢复
void GHLApplyCleanMode(BOOL on);       // (6) 开：首页净化+清屏按钮；关：只关首页净化
// 1.0.20：统一卡片——所有入口都开卡片（浮动钮、抖音设置行、双指长按、其他调用方），
// 不再全屏推设置页。实现在 GHLFeatures.xm（卡片自己的 UIWindow 里嵌设置页导航栈）。
void GHLShowFloatPanel(void);
// 1.0.23：卡片首页（8 按键）已拿掉，卡片根就是设置页本身；关卡片、取卡片共用的
// 设置页实例（关于页拿它当配置三行的帮手）这两个入口还在。
void GHLCloseFloatPanel(void);
@class DYYYSettingViewController;
DYYYSettingViewController *GHLFloatPanelSharedSettingsViewController(void);
// 1.0.24：换背景图后重铺卡片底图（卡片没建好时什么都不做）。
void GHLRefreshFloatPanelCardBackground(void);
// 1.0.21：第 7 项音频状态行用的抖音自己后台听视频 status（DYYY.xm 里 setListenVideoStatus
// 钩子记下的改写后值；-1 表示还没见过）。
NSInteger GHLCurrentListenVideoStatus(void);
void GHLStartPiP(void);                // (2) 画中画
// 1.0.16：画中画带调用方（网格点按 / 切后台），查找日志记调用方，判别触发路。
void GHLStartPiPWithCaller(NSString * _Nullable caller);
void GHLProbeAntiRecall(void);         // (24) 启动时探针：记下疑似撤回相关类名

// MARK: - 长按面板动作
// (18) 解析分享链接，复制无水印视频直链到剪贴板
void GHLCopyNoWatermarkLinkForAwemeModel(AWEAwemeModel *model);
// (25) 用解析接口拿无水印视频，在指定时间点截一帧存相册
void GHLSaveCleanScreenshotForAwemeModel(AWEAwemeModel *model, double seconds);
// (30) 下载当前视频并只导出音轨（.m4a），用分享面板交出去
void GHLExtractOriginalAudioForAwemeModel(AWEAwemeModel *model);
// 1.0.23：长按面板新增两项（清单 9 号）——弹窗显示作品数据并复制到剪贴板；
// 图集的图片全屏翻页预览（不是图集就提示没有图片）。
void GHLShowAwemeDataForAwemeModel(AWEAwemeModel *model);
void GHLPreviewAwemeImagesForAwemeModel(AWEAwemeModel *model);

// MARK: - 1.0.23 第二批（影片清单 42–78 号）
// 51 快捷面板背景图（存在 Documents/DYYY/ghl-quick-panel-bg.jpg，不进仓库；
// 读不到、损坏一律回退默认——面板照常用毛玻璃，不崩）
UIImage *GHLCustomQuickPanelBackgroundImage(void);
BOOL GHLSaveCustomQuickPanelBackgroundImage(UIImage *image); // 长边缩到 1242 → JPEG q85
void GHLClearCustomQuickPanelBackground(void);
BOOL GHLHasCustomQuickPanelBackground(void);
// (48) 自动连播：2 秒巡检里按视频时长累计，播完切下一个（见 GHLHousekeepingTick）
void GHLCheckAutoPlayNext(void);
// (59)(70)(71)(73) 私信手势与探针：2 秒巡检里找消息列表/聊天页装手势（只装一次）
void GHLInstallIMGesturesIfNeeded(void);
// (59) 仅看一次探针：dump 仅看一次/闪照相关类（只记日志，不 hook）
void GHLProbeViewOnce(void);
// (75) AI 解析：收评论区文字调 LLM 总结（需要用户自己填 Key 和接口地址）
void GHLAIParseCommentsFromView(UIView *panelView, UITextView *resultView, UILabel *statusLabel);
// (75) 评论面板顶部 评论/AI 解析 双页签（只装一次；开关在调用方 hook 里判断）
void GHLInstallCommentAIParseSegment(UIViewController *commentVC);

// MARK: - Logo
UIImage *GHLLogoImage(void);
// 关于深色品牌页横幅（1.0.13；base64 内嵌的 640x360 雷鸣绿龙横幅，裁自公司 logo 海报）
UIImage *GHLAboutBannerImage(void);
// 1.0.15 关于横幅可换：自选横幅（存在 Documents/DYYY/ghl-about-banner.jpg，不进仓库；
// 读不到、损坏一律回退内置展翅龙）
UIImage *GHLCustomAboutBannerImage(void);
BOOL GHLSaveCustomAboutBannerImage(UIImage *image); // 居中裁 16:9 → 640x360 → JPEG q85
void GHLClearCustomAboutBanner(void);
BOOL GHLHasCustomAboutBanner(void);
// 1.0.4 自选龙头 / 自定义背景（存在 Documents/DYYY/ 里，不进仓库；读不到、损坏一律回退内置/默认）
UIImage *GHLCustomLogoImage(void);
BOOL GHLSaveCustomLogoImage(UIImage *image);     // 居中裁正方形 → 256x256 → JPEG q88
void GHLClearCustomLogo(void);
BOOL GHLHasCustomLogo(void);
UIImage *GHLCustomBackgroundImage(void);         // 有自选背景图就返回，否则 nil
BOOL GHLSaveCustomBackgroundImage(UIImage *image); // 长边缩到 1242 → JPEG q85
void GHLClearCustomBackground(void);
BOOL GHLHasCustomBackground(void);

// MARK: - 1.0.4 悬浮按钮自定义 / 更新日志 / 语音包收藏
// 执行一个悬浮按钮动作（下载/清屏/倍速/弹幕/截图）；返回 YES 表示已处理，调用方跳过默认行为
BOOL GHLPerformFloatButtonAction(NSString *action);
// 1.0.5 手势自定义：执行一个手势动作（前 5 个复用悬浮按钮那套 + 静音开关 + 下一个视频）；返回 YES 表示已处理
BOOL GHLPerformGestureAction(NSString *action);
// MARK: - 1.0.8 美化
// 主题预设：一次把现有颜色类 key 写好（视频背景 / 弹幕 / 进度标签 / 时间标签 / 进度条颜色）；选完仍可在各行单独微调
void GHLApplyThemePreset(NSString *preset);
// 右侧边栏美化（图标缩放 / 间距 / 圆角底），在侧边栏排序之后跑
void GHLApplySidebarBeautifyInView(UIView *view);
// 双击爱心探针：双击后扫一遍互动层，记下疑似爱心动画的视图类名和位置（需真机日志确认，见抖音日志）
void GHLProbeDoubleTapHeartInView(UIView *view);
// 更新日志文本（1.0.1–1.0.6 各一行真实改动）
NSString *GHLChangelogText(void);
// 语音包收藏
BOOL GHLIsVoiceFavorite(NSString *voiceId);
void GHLSetVoiceFavorite(NSString *voiceId, BOOL favorite);
NSSet<NSString *> *GHLVoiceFavorites(void);

#ifdef __cplusplus
}
#endif
