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
// 画中画+后台播放 (2)
// 1.0.20：拆成两个开关，各管各的——
//   GHLBackgroundAudio = 切后台触发画中画；GHLBackgroundListen = 后台听视频
//   （setListenVideoStatus 的改写跟后台听视频走，经 DYYYEnableBackgroundListen 镜像，
//   上游「基本设置」里也有同一 key 的「启用后台播放」行，三处同写一个 key）。
// 1.0.35：画中画装回来（皇上点名留着；系统回调至今 0 次，从没成功过）。
#define GHL_KEY_BACKGROUND_AUDIO @"GHLBackgroundAudio"
#define GHL_KEY_BACKGROUND_LISTEN @"GHLBackgroundListen"
// 快进手势 (3)：长按倍速 + 双击左右快进 10 秒
#define GHL_KEY_SEEK_GESTURES @"GHLSeekGestures"
// 自动跳过开屏广告 (16)
#define GHL_KEY_NO_SPLASH_AD @"GHLNoSplashAd"
// 评论区图片一键存原图 (19)
#define GHL_KEY_COMMENT_IMAGE_SAVE @"GHLCommentImageSave"
// 弹幕浮层 (20)
#define GHL_KEY_COMMENT_DANMAKU @"GHLCommentDanmaku"
// 侧边栏自定义排序 (22)
#define GHL_KEY_SIDEBAR_REORDER @"GHLSidebarReorder"
#define GHL_KEY_SIDEBAR_ORDER @"GHLSidebarOrder" // 如：评论,点赞,分享,收藏（从上到下）
// 视频截图去水印 (25)
#define GHL_KEY_SCREENSHOT_CLEAN @"GHLScreenshotClean"
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
// 1.0.2 新增语音四项（照 xuu 卡片的语音功能；接口未验证，先做探针，见 GHLProbeVoiceFeatures）。
// 1.0.28：转发/秒数/替换三项下架（没做成），只剩保存语音评论（GHL_KEY_COMMENT_VOICE_SAVE）。
// 1.0.28 新增：长按导入至语音包（开关，默认开；格子项 696）。
#define GHL_KEY_IMPORT_TO_VOICE_PACKAGE @"GHLImportToVoicePackage" // 长按导入至语音包（默认开）
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
#define GHL_KEY_LOG_VIEWER @"GHLLogViewer"             // 打开抖音日志查看页（1.0.6）
// 更新日志：上次见过的版本号（变了就进设置主页时弹一次）
#define GHL_KEY_LAST_SEEN_VERSION @"GHLLastSeenVersion"


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
@property(nonatomic, copy) NSString *category; // 分类：@"内置" / @"在线" / @"我的导入"（1.0.28：文件夹已砍）
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
// 1.0.24：导入档构造（name 显示名，filePath 音频文件全路径；1.0.28：folder 固定传 @"我的导入"）
+ (instancetype)customPackageWithName:(NSString *)name filePath:(NSString *)filePath folder:(NSString *)folder;
@end
// 全部语音包（内置在前、在线在后、导入最后；在线档只在有缓存列表时出现）
// 1.0.28：文件夹已砍，内置/在线/导入的分类固定。
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
// 1.0.28：打开极简语音包页（★收藏/内置/在线/我的导入，搜索/试听/选中/刷新在线）
void GHLPresentSimpleVoicePackagePageFromViewController(UIViewController *viewController);
// 1.0.24：导入的语音（1.0.28：文件夹那套和导出都砍了，只剩长按导入；导入档都归“我的导入”）
// 导入的语音存在 Documents/DYYY/VoicePackages/，记录在 GHL_KEY_CUSTOM_VOICES。
#define GHL_KEY_CUSTOM_VOICES @"GHLCustomVoices" // 导入的语音：数组，字典 @{@"name", @"file"}
NSString *GHLCustomVoicePackagesDirectory(void);
// 1.0.40：把已存进语音包目录的文件登记到「我的导入」（只拷文件不登记，列表里看不到；同名文件只登记一次）
void GHLRegisterCustomVoiceFile(NSString *fileName, NSString *displayName);
void GHLImportVoiceAudioFileAtURL(NSURL *url, void (^done)(BOOL success, NSString * _Nullable name)); // mp4/mov 转音频，其他音频直接复制
NSString *GHLFileSizeText(NSString *path); // “1.2 MB”这种
// 运行期探针：保存语音评论相关类（只记日志，不 hook、不发包；1.0.28：转发/秒数/替换三项已下架）
void GHLProbeVoiceFeatures(void);
// 运行期探针：抖音里有没有直播发语音的相关类（只记日志，不 hook、不发包；语音包开关开时跑一次）
void GHLProbeLiveVoiceSender(void);
// 1.0.38 探针版：语音评论录制探针（只记日志，不改行为；无开关，常驻）
void GHLProbeCommentVoiceInputOpened(UIViewController *inputVC);
void GHLProbeCommentVoiceInputClosed(void);
void GHLProbeCommentVoiceRecorderInit(NSURL *url);
void GHLProbeCommentVoiceRecordStarted(NSURL *url);
void GHLProbeCommentVoiceRecordStopped(NSURL *url, NSTimeInterval duration);
void GHLProbeCommentVoiceRecordPaused(void);
// 1.0.39：替换语音评论——录音停下后把录好的文件换成选好的本地音频（只换评论录音）
void GHLReplaceCommentVoiceRecording(NSURL *recordedURL);
// 1.0.39：把语音包里选中的本地音频设为替换源（.m4a 直接存，不是就先转成 .m4a 再存）
void GHLSelectVoicePackageForReplace(GHLVoicePackageInfo *info);
// 1.0.39：打开替换音频挑选页（只列我的导入里的本地音频）
void GHLPresentReplaceAudioPickerFromViewController(UIViewController *viewController);

// MARK: - 32-43（xuu 抖音助手行为参考，代码全部自己写；只学功能清单，不抄它的代码）
// (33) 自动抢红包
#define GHL_KEY_AUTO_RED_PACKET @"GHLAutoRedPacket"
#define GHL_KEY_RED_PACKET_DELAY @"GHLRedPacketDelay"         // 秒，默认 1
#define GHL_KEY_RED_PACKET_AUTO_REPLY @"GHLRedPacketAutoReply"
#define GHL_KEY_RED_PACKET_REPLY_TEXT @"GHLRedPacketReplyText" // 默认 谢谢老板
// (34) 自动开直播抽奖
#define GHL_KEY_AUTO_LIVE_LOTTERY @"GHLAutoLiveLottery"
// (36) 评论语音保存（1.0.35：播放是实验，已取消，只留保存）
#define GHL_KEY_COMMENT_VOICE_SAVE @"GHLCommentVoiceSave"
// 1.0.39：替换语音评论（录完把录好的文件换成语音包里选的本地音频；默认关）
#define GHL_KEY_COMMENT_VOICE_REPLACE @"GHLCommentVoiceReplace"
#define GHL_KEY_COMMENT_VOICE_REPLACE_PATH @"GHLCommentVoiceReplacePath" // 替换用的 .m4a 全路径
#define GHL_KEY_COMMENT_VOICE_REPLACE_NAME @"GHLCommentVoiceReplaceName" // 替换用的音频显示名
#define GHL_KEY_DOUBLE_TAP_DOWNLOAD @"GHLDoubleTapDownload" // 双击下载（开后双击不再快进）
#define GHL_KEY_LONG_PRESS_DOWNLOAD @"GHLLongPressDownload" // 长按下载（接上游）
#define GHL_KEY_LONG_PRESS_GRID_PANEL @"GHLLongPressGridPanel" // 长按面板网格风格（龙头，1.0.9；默认开，%ctor 里 registerDefaults）
#define GHL_KEY_GRID_PANEL_AVATAR @"GHLGridPanelAvatar"     // 长按面板头像（1.0.11；Picker 入口，值无意义）
#define GHL_KEY_ABOUT_PAGE @"GHLAboutPage"                 // 关于顾海龙抖音（1.0.14；深色品牌页入口，值无意义）
#define GHL_KEY_DOWNLOAD_PROGRESS @"GHLDownloadProgress"   // 下载进度日志+提示
// MARK: - 1.0.23 第二批（影片清单 42–78 号，Lee 2026-11-15 勾中 22 项并进同一版，版本号不变）
// 48 自动连播：播完自动切下一个（按视频时长累计，2 秒巡检采样，需真机验证）
// 51 快捷面板背景图片（长按网格面板的背景自选图；只用在面板表面，不动设置卡片）
#define GHL_KEY_QUICK_PANEL_BG @"GHLQuickPanelBackground"       // Picker 入口：从相册选图
#define GHL_KEY_QUICK_PANEL_BG_CLEAR @"GHLQuickPanelBackgroundClear" // Picker 入口：恢复默认背景
// 53 面板材质三选一（只用在长按网格面板）：磨砂 / 液态玻璃 / 清透玻璃
// （真液态玻璃是 iOS 26 的 UIGlassEffect，iOS 16.5 上用加厚材质＋淡白 tint 近似）
#define GHL_KEY_QUICK_PANEL_MATERIAL @"GHLQuickPanelMaterial"
// (44) 1.0.8 美化：主题预设（1.0.35：侧边栏 / 进度条 / 头像金边 / 弹幕样式 / 底栏毛玻璃已拿掉，只留主题预设）
#define GHL_KEY_THEME_PRESET @"GHLThemePreset" // none=无 gold=金龙 ice=冰蓝 pink=樱粉 night=暗夜
// 1.0.24：双击下载——按位置（左半边直接保存，右半边弹菜单）；弹窗精简（只留下载相关）。
#define GHL_KEY_DOUBLE_TAP_POSITION @"GHLDoubleTapPosition"
#define GHL_KEY_DOUBLE_TAP_POPUP_COMPACT @"GHLDoubleTapPopupCompact"

// MARK: - 32-43 功能入口
void GHLStartHousekeepingTimer(void); // (33)(34)(38)(39)(42) 每 2 秒跑一次的巡检
void GHLHousekeepingTick(void);
BOOL GHLIsInLiveRoom(void); // (39)(42) 是否在直播间（按顶层 VC 类名含 Live 判断）
void GHLTrySendLiveMessage(NSString *text); // (33) 尽力往直播间输入框发一条消息（自动抢红包回覆用）
void GHLDownloadCurrentVideoWithProgress(void); // (37) 双击下载当前视频（带进度日志）

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
// 1.0.28：画中画下架，B 路控制器 KVC 探针也一起删了，只剩 A 路窗口图层扫描）
AVPlayer *GHLFindPlayingAVPlayer(void);
// 找到当前播放视频的 AVPlayerLayer（1.0.15：全部窗口递归找，不只 keyWindow）
AVPlayerLayer *GHLFindPlayingAVPlayerLayer(void);
// 当前播放进度（秒），找不到返回 -1
double GHLCurrentPlayerTime(void);
// 快进/快退 N 秒（可正可负）
void GHLSeekCurrentPlayerBySeconds(double seconds);
// 暂停当前播放
void GHLPauseCurrentPlayer(void);
// 1.0.21：第 7 项音频状态行用的抖音自己后台听视频 status（DYYY.xm 里 setListenVideoStatus
// 钩子记下的改写后值；-1 表示还没见过）。
NSInteger GHLCurrentListenVideoStatus(void);
// 1.0.35：画中画装回来（122）
void GHLStartPiP(void);                // (2) 画中画
// 1.0.16：画中画带调用方（网格点按 / 切后台），查找日志记调用方，判别触发路。
void GHLStartPiPWithCaller(NSString * _Nullable caller);
// 当前视频的 AwemeModel（通过悬浮按钮协调器拿当前 interaction controller）
AWEAwemeModel *GHLCurrentAwemeModel(void);

// MARK: - 各功能入口（供设置页开关回调调用）
// 1.0.20：统一卡片——所有入口都开卡片（浮动钮、抖音设置行、双指长按、其他调用方），
// 不再全屏推设置页。实现在 GHLFeatures.xm（卡片自己的 UIWindow 里嵌设置页导航栈）。
void GHLShowFloatPanel(void);
// 1.0.23：卡片首页（8 按键）已拿掉，卡片根就是设置页本身；关卡片、取卡片共用的
// 设置页实例（关于页拿它当配置三行的帮手）这两个入口还在。
void GHLCloseFloatPanel(void);
@class DYYYSettingViewController;
DYYYSettingViewController *GHLFloatPanelSharedSettingsViewController(void);
// MARK: - 长按面板动作
// 1.0.28：长按导入至语音包——下载当前视频、抽音轨成 .m4a 存进语音包（名字是皇上输的那个）。
void GHLImportVideoAudioToVoicePackage(AWEAwemeModel *model, NSString *name);
// (25) 截图去水印：用解析接口拿无水印视频，在指定时间点截一帧存相册（89 留着）
void GHLSaveCleanScreenshotForAwemeModel(AWEAwemeModel *model, double seconds);

// MARK: - 1.0.23 第二批（影片清单 42–78 号）
// 51 快捷面板背景图（存在 Documents/DYYY/ghl-quick-panel-bg.jpg，不进仓库；
// 读不到、损坏一律回退默认——面板照常用毛玻璃，不崩）
UIImage *GHLCustomQuickPanelBackgroundImage(void);
NSString *GHLCustomQuickPanelBackgroundPath(void); // 1.0.27：面板比 mtime＋大小用（文件没变就跳过重读）
BOOL GHLSaveCustomQuickPanelBackgroundImage(UIImage *image); // 长边缩到 1242 → JPEG q85
void GHLClearCustomQuickPanelBackground(void);
BOOL GHLHasCustomQuickPanelBackground(void);

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

// MARK: - 1.0.4 悬浮按钮自定义 / 更新日志 / 语音包收藏
// 执行一个悬浮按钮动作（下载/清屏/倍速/弹幕/截图）；返回 YES 表示已处理，调用方跳过默认行为
BOOL GHLPerformFloatButtonAction(NSString *action);
// MARK: - 1.0.8 美化
// 主题预设：一次把现有颜色类 key 写好（视频背景 / 弹幕 / 进度标签 / 时间标签 / 进度条颜色）；选完仍可在各行单独微调
void GHLApplyThemePreset(NSString *preset);
// 更新日志文本（1.0.1–1.0.6 各一行真实改动）
NSString *GHLChangelogText(void);
// 语音包收藏
BOOL GHLIsVoiceFavorite(NSString *voiceId);
void GHLSetVoiceFavorite(NSString *voiceId, BOOL favorite);
NSSet<NSString *> *GHLVoiceFavorites(void);

#ifdef __cplusplus
}
#endif
