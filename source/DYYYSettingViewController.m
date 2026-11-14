#import "DYYYSettingViewController.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "DYYYConstants.h"
#import "DYYYFloatClearButton.h"
#import "DYYYFloatSpeedButton.h"
#import "DYYYSettingsHelper.h"
#import "GHLFeatures.h"

typedef NS_ENUM(NSInteger, DYYYSettingItemType) { DYYYSettingItemTypeSwitch, DYYYSettingItemTypeTextField, DYYYSettingItemTypePicker };

@interface DYYYSettingItem : NSObject

@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *key;
@property(nonatomic, assign) DYYYSettingItemType type;
@property(nonatomic, copy, nullable) NSString *placeholder;

+ (instancetype)itemWithTitle:(NSString *)title key:(NSString *)key type:(DYYYSettingItemType)type;
+ (instancetype)itemWithTitle:(NSString *)title key:(NSString *)key type:(DYYYSettingItemType)type placeholder:(nullable NSString *)placeholder;

@end

@implementation DYYYSettingItem

+ (instancetype)itemWithTitle:(NSString *)title key:(NSString *)key type:(DYYYSettingItemType)type {
    return [self itemWithTitle:title key:key type:type placeholder:nil];
}

+ (instancetype)itemWithTitle:(NSString *)title key:(NSString *)key type:(DYYYSettingItemType)type placeholder:(nullable NSString *)placeholder {
    DYYYSettingItem *item = [[DYYYSettingItem alloc] init];
    item.title = title;
    item.key = key;
    item.type = type;
    item.placeholder = placeholder;
    return item;
}

@end

@interface DYYYSettingViewController () <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate>

@property(nonatomic, strong) UITableView *tableView;
@property(nonatomic, strong) NSArray<NSArray<DYYYSettingItem *> *> *settingSections;
@property(nonatomic, strong) NSMutableArray<NSString *> *sectionTitles;
@property(nonatomic, assign) BOOL isAgreementShown;

// 1.0.2 白色卡片主页：NSNotFound = 主页；>=0 = 某个分类的子页（只显示该分区）。
@property(nonatomic, assign) NSInteger displaySectionIndex;
// 主页搜索：搜索中的过滤结果，每项 @{@"item": DYYYSettingItem, @"section": @(分区), @"row": @(行)}
@property(nonatomic, strong, nullable) NSArray<NSDictionary *> *searchResults;
@property(nonatomic, strong, nullable) UISearchBar *searchBar;
@property(nonatomic, strong, nullable) UILabel *statsLabel;

@end

@implementation DYYYSettingViewController

- (instancetype)init {
    self = [super init];
    if (self) {
        _displaySectionIndex = NSNotFound;
    }
    return self;
}

- (instancetype)initWithSectionIndex:(NSInteger)sectionIndex {
    self = [super init];
    if (self) {
        _displaySectionIndex = sectionIndex;
    }
    return self;
}

- (void)ghlDismissSettings {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (BOOL)isHomeMode {
    return self.displaySectionIndex == NSNotFound;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.isAgreementShown = NO;

    [self setupDefaultValues];
    [self setupSettingItems];
    [self setupSectionTitles];
    self.title = [self isHomeMode] ? DYYY_SETTINGS_NAME : self.sectionTitles[self.displaySectionIndex];

    [self setupAppearance];
    [self setupTableView];
    if ([self isHomeMode]) {
        [self setupHeaderCardAndSearch];
        [self setupFooterButtons];
        [self refreshHeaderStats];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 从子页返回时刷新头卡统计（已开启数可能变了）。
    if ([self isHomeMode]) {
        [self refreshHeaderStats];
    }
}

- (void)setupDefaultValues {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];

    // 如果快捷倍速数值未设置，设置默认值
    if (![defaults objectForKey:@"DYYYSpeedSettings"]) {
        [defaults setObject:@"1.0,1.25,1.5,2.0" forKey:@"DYYYSpeedSettings"];
    }

    // 如果按钮大小未设置，设置默认值
    if (![defaults objectForKey:@"DYYYSpeedButtonSize"]) {
        [defaults setFloat:32.0 forKey:@"DYYYSpeedButtonSize"];
    }

}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    if (!self.isAgreementShown) {
        [self checkFirstLaunch];
        self.isAgreementShown = YES;
    }
}

- (void)setupAppearance {
    // 1.0.2 白色卡片样式：系统默认白底导航栏 + 黑字大标题（旧的深色毛玻璃 + 金色渐变标题已去掉）。
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    self.view.backgroundColor = [UIColor systemGroupedBackgroundColor];
}

- (void)setupTableView {
    self.tableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStyleGrouped];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.backgroundColor = [UIColor systemGroupedBackgroundColor];
    self.tableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.tableView];
}

- (void)setupSettingItems {
    self.settingSections = @[
        @[
            // 顾海龙抖音新增功能（22 个，(31) 语音包：xuu 式管理器，内置本机音色 + Fish Audio 在线音色）
            [DYYYSettingItem itemWithTitle:@"睡眠定时" key:GHL_KEY_SLEEP_TIMER type:DYYYSettingItemTypePicker],
            [DYYYSettingItem itemWithTitle:@"画中画 + 后台播放" key:GHL_KEY_BACKGROUND_AUDIO type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"快进手势（长按倍速/双击左右快进10秒）" key:GHL_KEY_SEEK_GESTURES type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"记忆倍速（按作者）" key:GHL_KEY_REMEMBER_SPEED_PER_AUTHOR type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"关键词过滤总开关" key:GHL_KEY_KEYWORD_FILTER type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"过滤关键词（逗号分隔）" key:@"DYYYFilterKeywords" type:DYYYSettingItemTypeTextField placeholder:@"如：广告,抽奖"],
            [DYYYSettingItem itemWithTitle:@"过滤用户（昵称-抖音号）" key:@"DYYYFilterUsers" type:DYYYSettingItemTypeTextField placeholder:@"如：某某-123456"],
            [DYYYSettingItem itemWithTitle:@"推荐过滤直播" key:@"DYYYSkipLive" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"推荐过滤全部直播" key:@"DYYYSkipAllLive" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"一键清爽模式" key:GHL_KEY_CLEAN_MODE type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"评论关键词屏蔽（逗号分隔）" key:GHL_KEY_COMMENT_BLOCK_KEYWORDS type:DYYYSettingItemTypeTextField placeholder:@"如：喷子,引战"],
            [DYYYSettingItem itemWithTitle:@"长评论自动展开" key:GHL_KEY_COMMENT_AUTO_EXPAND type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"点赞自动保存视频" key:GHL_KEY_AUTO_SAVE_LIKED type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"夜间护眼" key:GHL_KEY_NIGHT_MODE type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"夜间亮度（0-1小数）" key:GHL_KEY_NIGHT_BRIGHTNESS type:DYYYSettingItemTypeTextField placeholder:@"默认0.3"],
            [DYYYSettingItem itemWithTitle:@"三指双击清屏" key:GHL_KEY_TRIPLE_TAP_CLEAR type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"边缘滑动切下一个视频" key:GHL_KEY_EDGE_SWIPE_NEXT type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"音量键调进度" key:GHL_KEY_VOLUME_SEEK type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"直播间净化" key:GHL_KEY_LIVE_PURIFY type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"BGM 一键保存" key:GHL_KEY_BGM_SAVE type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"自动跳过开屏广告" key:GHL_KEY_NO_SPLASH_AD type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"去水印分享直链" key:GHL_KEY_NO_WATERMARK_SHARE_LINK type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"评论图片一键存原图" key:GHL_KEY_COMMENT_IMAGE_SAVE type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"弹幕浮层（评论飘在视频上）" key:GHL_KEY_COMMENT_DANMAKU type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"侧边栏自定义排序" key:GHL_KEY_SIDEBAR_REORDER type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"侧边栏顺序（逗号分隔，从上到下）" key:GHL_KEY_SIDEBAR_ORDER type:DYYYSettingItemTypeTextField placeholder:@"如：评论,点赞,分享,收藏"],
            [DYYYSettingItem itemWithTitle:@"私信防撤回（实验，需真机日志验证）" key:GHL_KEY_ANTI_RECALL type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"视频截图去水印" key:GHL_KEY_SCREENSHOT_CLEAN type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"楼中楼一键展开" key:GHL_KEY_EXPAND_REPLIES type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"视频原声提取" key:GHL_KEY_EXTRACT_AUDIO type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"语音包（选音色发语音/配音）" key:GHL_KEY_VOICE_PACKAGE type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"语音包音色（选完自动试听）" key:GHL_KEY_VOICE_PACKAGE_ID type:DYYYSettingItemTypePicker],
            [DYYYSettingItem itemWithTitle:@"语音包管理（列表/搜索/试听）" key:GHL_KEY_VOICE_PACKAGE_MANAGER type:DYYYSettingItemTypePicker],
            // 1.0.2 语音四项（对方 xuu 卡片上的语音功能）：探针，未验证——
            // 语音转发/语音秒数/替换语音评论没有可验证的 hook 点；保存语音评论的
            // AWECommentAudioModel 只确认有 content 字段，未确认音频 URL 字段。
            // 开关打开只记运行期探针日志（GHLProbeVoiceFeatures），不注入、不发包。
            [DYYYSettingItem itemWithTitle:@"语音消息转发（实验，需真机日志验证）" key:GHL_KEY_VOICE_FORWARD type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"设置语音秒数（实验，需真机日志验证）" key:GHL_KEY_VOICE_DURATION type:DYYYSettingItemTypeTextField placeholder:@"默认60"],
            [DYYYSettingItem itemWithTitle:@"替换语音评论（实验，需真机日志验证）" key:GHL_KEY_VOICE_REPLACE_COMMENT type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"保存语音评论（实验，需真机日志验证）" key:GHL_KEY_COMMENT_VOICE_SAVE type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"Fish Audio API Key（在线音色用）" key:GHL_KEY_FISH_AUDIO_API_KEY type:DYYYSettingItemTypeTextField placeholder:@"没有 key 就只用内置音色"]
        ],
        @[
            // 顾海龙抖音（二）：32-43（xuu 行为参考，代码自己写）
            [DYYYSettingItem itemWithTitle:@"自动点赞" key:GHL_KEY_AUTO_LIKE type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"自动点赞每会话上限" key:GHL_KEY_AUTO_LIKE_MAX type:DYYYSettingItemTypeTextField placeholder:@"默认100"],
            [DYYYSettingItem itemWithTitle:@"自动抢红包" key:GHL_KEY_AUTO_RED_PACKET type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"抢红包黑名单（作者抖音号，逗号分隔）" key:GHL_KEY_RED_PACKET_BLACKLIST type:DYYYSettingItemTypeTextField placeholder:@"如：123456,789012"],
            [DYYYSettingItem itemWithTitle:@"抢红包延迟（秒）" key:GHL_KEY_RED_PACKET_DELAY type:DYYYSettingItemTypeTextField placeholder:@"默认1"],
            [DYYYSettingItem itemWithTitle:@"抢到红包自动回复" key:GHL_KEY_RED_PACKET_AUTO_REPLY type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"自动回复内容" key:GHL_KEY_RED_PACKET_REPLY_TEXT type:DYYYSettingItemTypeTextField placeholder:@"默认谢谢老板"],
            [DYYYSettingItem itemWithTitle:@"自动开直播抽奖" key:GHL_KEY_AUTO_LIVE_LOTTERY type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏“正在输入”（实验，未验证）" key:GHL_KEY_HIDE_TYPING type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏已读回执（实验，未验证）" key:GHL_KEY_HIDE_READ_RECEIPT type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"不上报访客记录" key:GHL_KEY_DISABLE_VISIT_REPORT type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"评论语音播放（实验，未验证）" key:GHL_KEY_COMMENT_VOICE type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"评论语音保存（实验，未验证）" key:GHL_KEY_COMMENT_VOICE_SAVE type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"双击下载当前视频（开后双击不再快进）" key:GHL_KEY_DOUBLE_TAP_DOWNLOAD type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"长按下载" key:GHL_KEY_LONG_PRESS_DOWNLOAD type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"下载进度日志+提示" key:GHL_KEY_DOWNLOAD_PROGRESS type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"保存头像（长按面板）" key:GHL_KEY_SAVE_AVATAR type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"复制个人资料（长按面板）" key:GHL_KEY_COPY_PROFILE type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"左滑返回" key:GHL_KEY_LEFT_SWIPE_BACK type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"界面元素缩放" key:GHL_KEY_INTERFACE_SCALE type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"缩放比例（0.5-2.0）" key:GHL_KEY_INTERFACE_SCALE_VALUE type:DYYYSettingItemTypeTextField placeholder:@"默认1.0"],
            [DYYYSettingItem itemWithTitle:@"深色键盘" key:GHL_KEY_DARK_KEYBOARD type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"自定义底栏" key:GHL_KEY_CUSTOM_TAB_BAR type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏的底栏项（逗号分隔）" key:GHL_KEY_HIDDEN_TABS type:DYYYSettingItemTypeTextField placeholder:@"如：商城,消息"],
            [DYYYSettingItem itemWithTitle:@"直播时长显示" key:GHL_KEY_LIVE_DURATION type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"直播录制（进直播间开录，离开弹保存）" key:GHL_KEY_LIVE_RECORD type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"跳过直播" key:GHL_KEY_SKIP_LIVE type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"直播间发消息" key:GHL_KEY_LIVE_SEND_MESSAGE type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"直播间自动发的内容" key:GHL_KEY_LIVE_SEND_MESSAGE_TEXT type:DYYYSettingItemTypeTextField placeholder:@"如：主播好"],
            [DYYYSettingItem itemWithTitle:@"弹幕颜色" key:GHL_KEY_DANMAKU_COLOR type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"弹幕颜色值（十六进制或 random）" key:GHL_KEY_DANMAKU_COLOR_VALUE type:DYYYSettingItemTypeTextField placeholder:@"如：FF0000 或 random"],
            [DYYYSettingItem itemWithTitle:@"评论区模糊" key:GHL_KEY_COMMENT_BLUR type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"顶栏透明" key:GHL_KEY_TOP_BAR_TRANSPARENT type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"顶栏透明度（0-1小数）" key:GHL_KEY_TOP_BAR_TRANSPARENCY type:DYYYSettingItemTypeTextField placeholder:@"默认0.5"],
            [DYYYSettingItem itemWithTitle:@"隐藏状态栏" key:GHL_KEY_HIDE_STATUS_BAR type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"防阅后即焚（实验，未验证）" key:GHL_KEY_ANTI_BURN type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"改数字显示（点赞/播放数）" key:GHL_KEY_FAKE_STATS type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"点赞数改成" key:GHL_KEY_FAKE_LIKE_COUNT type:DYYYSettingItemTypeTextField placeholder:@"如：99999"],
            [DYYYSettingItem itemWithTitle:@"播放数改成" key:GHL_KEY_FAKE_PLAY_COUNT type:DYYYSettingItemTypeTextField placeholder:@"如：100万"],
            [DYYYSettingItem itemWithTitle:@"改直播间人数显示" key:GHL_KEY_FAKE_LIVE_USER_COUNT type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"直播间人数改成" key:GHL_KEY_FAKE_LIVE_USER_COUNT_VALUE type:DYYYSettingItemTypeTextField placeholder:@"如：10万"],
            [DYYYSettingItem itemWithTitle:@"音频分享（长按面板）" key:GHL_KEY_AUDIO_SHARE type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"直播音频单独静音" key:GHL_KEY_LIVE_AUDIO_MUTE type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"评论音频单独静音（实验，未验证）" key:GHL_KEY_COMMENT_AUDIO_MUTE type:DYYYSettingItemTypeSwitch]
        ],
        @[
            [DYYYSettingItem itemWithTitle:@"视频背景颜色" key:@"DYYYVideoBGColor" type:DYYYSettingItemTypeTextField placeholder:@"十六进制"],
            [DYYYSettingItem itemWithTitle:@"启用弹幕改色" key:@"DYYYEnableDanmuColor" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"自定弹幕颜色" key:@"DYYYDanmuColor" type:DYYYSettingItemTypeTextField placeholder:@"十六进制"],
            [DYYYSettingItem itemWithTitle:@"设置默认倍速" key:@"DYYYDefaultSpeed" type:DYYYSettingItemTypePicker],
            [DYYYSettingItem itemWithTitle:@"设置长按倍速" key:@"DYYYLongPressSpeed" type:DYYYSettingItemTypePicker],
            [DYYYSettingItem itemWithTitle:@"上下控制倍速" key:@"DYYYEnableLongPressSpeedGesture" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"显示进度时长" key:@"DYYYShowScheduleDisplay" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"显示详细互动数" key:@"DYYYShowExactInteractionCounts" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"查看评论暂停播放" key:@"DYYYCommentPausePlayback" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"进度时长样式" key:@"DYYYScheduleStyle" type:DYYYSettingItemTypeTextField placeholder:@"默认"],
            [DYYYSettingItem itemWithTitle:@"进度纵轴位置" key:@"DYYYTimelineVerticalPosition" type:DYYYSettingItemTypeTextField placeholder:@"-12.5"],
            [DYYYSettingItem itemWithTitle:@"进度标签颜色" key:@"DYYYProgressLabelColor" type:DYYYSettingItemTypeTextField placeholder:@"十六进制"],
            [DYYYSettingItem itemWithTitle:@"隐藏视频进度" key:@"DYYYHideVideoProgress" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"启用自动播放" key:@"DYYYEnableAutoPlay" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"忽略投屏 VPN 检测" key:@"DYYYDisableCastVPNCheck" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"推荐过滤直播" key:@"DYYYSkipLive" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"推荐过滤热点" key:@"DYYYSkipHotSpot" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"推荐过滤朋友视频" key:@"DYYYSkipFriendsVideo" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"推荐过滤低赞" key:@"DYYYFilterLowLikes" type:DYYYSettingItemTypeTextField placeholder:@"填0关闭"],
            [DYYYSettingItem itemWithTitle:@"推荐视频时限" key:@"DYYYFilterTimeLimit" type:DYYYSettingItemTypeTextField placeholder:@"填0关闭，单位为天"],
            [DYYYSettingItem itemWithTitle:@"全局HDR设置" key:@"DYYYHDRMode" type:DYYYSettingItemTypePicker],
            [DYYYSettingItem itemWithTitle:@"启用首页净化" key:@"DYYYEnablePure" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"启用首页全屏" key:@"DYYYEnableFullScreen" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"启用屏蔽广告" key:@"DYYYNoAds" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"屏蔽检测更新" key:@"DYYYNoUpdates" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"禁用作品浏览记录上传" key:@"DYYYDisableAwemeViewRecordUpload" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"启用绕登录" key:@"DYYYEnableLoginBypass" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"去青少年弹窗" key:@"DYYYHideTeenMode" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"评论区毛玻璃" key:@"DYYYEnableCommentBlur" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"通知玻璃效果" key:@"DYYYEnableNotificationTransparency" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"毛玻璃透明度" key:@"DYYYCommentBlurTransparent" type:DYYYSettingItemTypeTextField placeholder:@"0-1小数"],
            [DYYYSettingItem itemWithTitle:@"通知圆角半径" key:@"DYYYNotificationCornerRadius" type:DYYYSettingItemTypeTextField placeholder:@"默认12"],
            [DYYYSettingItem itemWithTitle:@"时间属地显示" key:@"DYYYEnableArea" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"国外解析账号" key:@"DYYYGeonamesUsername" type:DYYYSettingItemTypeTextField placeholder:@"需填写才能解析国外"],
            [DYYYSettingItem itemWithTitle:@"时间标签颜色" key:@"DYYYLabelColor" type:DYYYSettingItemTypeTextField placeholder:@"十六进制"],
            [DYYYSettingItem itemWithTitle:@"属地随机渐变" key:@"DYYYEnableRandomGradient" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏系统顶栏" key:@"DYYYHideStatusbar" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"关注二次确认" key:@"DYYYFollowTips" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"收藏二次确认" key:@"DYYYCollectTips" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"默认直播画质" key:@"DYYYLiveQuality" type:DYYYSettingItemTypePicker],
            [DYYYSettingItem itemWithTitle:@"提高视频画质" key:@"DYYYEnableVideoHighestQuality" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"禁用直播PCDN功能" key:@"DYYYDisableLivePCDN" type:DYYYSettingItemTypeSwitch]
        ],
        @[
            [DYYYSettingItem itemWithTitle:@"设置顶栏透明" key:@"DYYYTopBarTransparent" type:DYYYSettingItemTypeTextField placeholder:@"0-1小数"],
            [DYYYSettingItem itemWithTitle:@"设置全局透明" key:@"DYYYGlobalTransparency" type:DYYYSettingItemTypeTextField placeholder:@"0-1小数"],
            [DYYYSettingItem itemWithTitle:@"首页头像透明" key:@"DYYYAvatarViewTransparency" type:DYYYSettingItemTypeTextField placeholder:@"0-1小数"],
            [DYYYSettingItem itemWithTitle:@"右侧栏缩放度" key:@"DYYYElementScale" type:DYYYSettingItemTypeTextField placeholder:@"不填默认"],
            [DYYYSettingItem itemWithTitle:@"昵称文案缩放" key:@"DYYYNicknameScale" type:DYYYSettingItemTypeTextField placeholder:@"不填默认"],
            [DYYYSettingItem itemWithTitle:@"昵称下移距离" key:@"DYYYNicknameVerticalOffset" type:DYYYSettingItemTypeTextField placeholder:@"不填默认"],
            [DYYYSettingItem itemWithTitle:@"文案下移距离" key:@"DYYYDescriptionVerticalOffset" type:DYYYSettingItemTypeTextField placeholder:@"不填默认"],
            [DYYYSettingItem itemWithTitle:@"属地上移距离" key:@"DYYYIPLabelVerticalOffset" type:DYYYSettingItemTypeTextField placeholder:@"不填默认"],
            [DYYYSettingItem itemWithTitle:@"修改底栏高度" key:@"DYYYTabBarHeight" type:DYYYSettingItemTypeTextField placeholder:@"默认为空"],
            [DYYYSettingItem itemWithTitle:@"设置首页标题" key:@"DYYYIndexTitle" type:DYYYSettingItemTypeTextField placeholder:@"不填默认"],
            [DYYYSettingItem itemWithTitle:@"设置朋友标题" key:@"DYYYFriendsTitle" type:DYYYSettingItemTypeTextField placeholder:@"不填默认"],
            [DYYYSettingItem itemWithTitle:@"设置消息标题" key:@"DYYYMsgTitle" type:DYYYSettingItemTypeTextField placeholder:@"不填默认"],
            [DYYYSettingItem itemWithTitle:@"设置我的标题" key:@"DYYYSelfTitle" type:DYYYSettingItemTypeTextField placeholder:@"不填默认"]
        ],
        @[
            [DYYYSettingItem itemWithTitle:@"隐藏全屏观看" key:@"DYYYHideEntry" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏底栏商城" key:@"DYYYHideShopButton" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏双列箭头" key:@"DYYYHideDoubleColumnEntry" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏底栏消息" key:@"DYYYHideMessageButton" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏底栏朋友" key:@"DYYYHideFriendsButton" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏底栏我的" key:@"DYYYHideMyButton" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏底栏加号" key:@"DYYYHidePlusButton" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏底栏热榜" key:@"DYYYHideHotSearch" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏底栏评论" key:@"DYYYHideComment" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏底栏红点" key:@"DYYYHideBottomDot" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏底栏背景" key:@"DYYYHideBottomBg" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"精简平板底栏" key:@"DYYYHidePadTabBarElements" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏常用小程序" key:@"DYYYHideSidebarRecentApps" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏常访问的人" key:@"DYYYHideSidebarRecentUsers" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏侧栏红点" key:@"DYYYHideSidebarDot" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏发作品框" key:@"DYYYHidePostView" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏头像加号" key:@"DYYYHideLOTAnimationView" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"移除头像加号" key:@"DYYYHideFollowPromptView" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏点赞数值" key:@"DYYYHideLikeLabel" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏评论数值" key:@"DYYYHideCommentLabel" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏收藏数值" key:@"DYYYHideCollectLabel" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏分享数值" key:@"DYYYHideShareLabel" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏点赞按钮" key:@"DYYYHideLikeButton" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏评论按钮" key:@"DYYYHideCommentButton" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏收藏按钮" key:@"DYYYHideCollectButton" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏头像及周边" key:@"DYYYHideAvatarButton" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏音乐按钮" key:@"DYYYHideMusicButton" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏推荐应用下载" key:@"DYYYHideRecommendAppDownload" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏分享按钮" key:@"DYYYHideShareButton" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏定位与同城" key:@"DYYYHideLocation" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏右上搜索" key:@"DYYYHideDiscover" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏相关搜索" key:@"DYYYHideInteractionSearch" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏弹出热搜" key:@"DYYYHideSearchBubble" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏搜索同款" key:@"DYYYHideSearchSame" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏长框搜索" key:@"DYYYHideSearchEntrance" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏进入直播" key:@"DYYYHideEnterLive" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏评论视图" key:@"DYYYHideCommentViews" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏通知提示" key:@"DYYYHidePushBanner" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏消息顶栏红包" key:@"DYYYHideMessageTabRedPacket" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏我的创作AI作品" key:@"DYYYHideMineAICreation" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏我的页头像加号" key:@"DYYYHideMineAvatarPlus" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏消息星光商城" key:@"DYYYHideMessageTabStarMall" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏头像列表" key:@"DYYYHideAvatarList" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏头像气泡" key:@"DYYYHideAvatarBubble" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏左侧边栏" key:@"DYYYHideLeftSideBar" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏吃喝玩乐" key:@"DYYYHideNearbyCapsuleView" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏弹幕按钮" key:@"DYYYHideDanmuButton" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏取消静音" key:@"DYYYHideCancelMute" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏去汽水听" key:@"DYYYHideQuqishuiting" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏共创头像" key:@"DYYYHideGongChuang" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏热点提示" key:@"DYYYHideHotspot" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏推荐提示" key:@"DYYYHideRecommendTips" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏分享提示" key:@"DYYYHideShareContentView" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏作者声明" key:@"DYYYHideAntiAddictedNotice" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏底部相关" key:@"DYYYHideBottomRelated" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏视频锚点" key:@"DYYYHideFeedAnchorContainer" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏挑战贴纸" key:@"DYYYHideChallengeStickers" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏图文标签" key:@"DYYYHideEditTags" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏校园提示" key:@"DYYYHideTemplateTags" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏作者店铺" key:@"DYYYHideHisShop" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏顶栏横线" key:@"DYYYHideTopBarLine" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏视频合集" key:@"DYYYHideTemplateVideo" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏短剧合集" key:@"DYYYHideTemplatePlaylet" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏动图标签" key:@"DYYYHideLiveGIF" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏笔记标签" key:@"DYYYHideItemTag" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏底部话题" key:@"DYYYHideTemplateGroup" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏相机定位" key:@"DYYYHideCameraLocation" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏视频滑条" key:@"DYYYHideStoryProgressSlide" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏图片滑条" key:@"DYYYHideDotsIndicator" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏分享私信" key:@"DYYYHidePrivateMessages" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏昵称右侧" key:@"DYYYHideRightLabel" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏群聊商店" key:@"DYYYHideGroupShop" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏直播胶囊" key:@"DYYYHideLiveCapsuleView" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏关注顶端" key:@"DYYYHideLiveView" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏关注直播" key:@"DYYYHideConcernCapsuleView" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏同城顶端" key:@"DYYYHideMenuView" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏群直播中" key:@"DYYYHideGroupLiveIndicator" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏聊天底栏" key:@"DYYYHideGroupInputActionBar" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏添加朋友" key:@"DYYYHideButton" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏日常按钮" key:@"DYYYHideFamiliar" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏直播广场" key:@"DYYYHideLivePlayground" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏礼物展馆" key:@"DYYYHideGiftPavilion" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏顶栏红点" key:@"DYYYHideTopBarBadge" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏退出清屏" key:@"DYYYHideLiveRoomClear" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏投屏按钮" key:@"DYYYHideLiveRoomMirroring" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏直播伴侣提示" key:@"DYYYHideLiveRoomShareCompanion" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏直播发现" key:@"DYYYHideLiveDiscovery" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏直播点歌" key:@"DYYYHideKTVSongIndicator" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏流量提醒" key:@"DYYYHideCellularAlert" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏红包悬浮" key:@"DYYYHidePendantGroup" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏章节进度" key:@"DYYYHideChapterProgress" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏键盘AI" key:@"DYYYHideKeyboardAI" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏上次看到" key:@"DYYYHidePopover" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏展开渐变" key:@"DYYYHideGradient" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏关闭按钮" key:@"DYYYHideLiveRoomClose" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏横屏按钮" key:@"DYYYHideLiveRoomFullscreen" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏返回按钮" key:@"DYYYHideBack" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏商品信息" key:@"DYYYHideLiveGoodsMsg" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏点赞动画" key:@"DYYYHideLiveLikeAnimation" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏输入扫码" key:@"DYYYHideScancode" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏私信回复" key:@"DYYYHideReply" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏暂停相关" key:@"DYYYHidePauseVideoRelatedWord" type:DYYYSettingItemTypeSwitch]
        ],
        @[
            [DYYYSettingItem itemWithTitle:@"移除推荐" key:@"DYYYHideHotContainer" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"移除关注" key:@"DYYYHideFollow" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"移除精选" key:@"DYYYHideMediumVideo" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"移除商城" key:@"DYYYHideMall" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"移除朋友" key:@"DYYYHideFriend" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"移除同城" key:@"DYYYHideNearby" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"移除团购" key:@"DYYYHideGroupon" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"移除直播" key:@"DYYYHideTabLive" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"移除热点" key:@"DYYYHidePadHot" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"移除经验" key:@"DYYYHideHangout" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"移除短剧" key:@"DYYYHidePlaylet" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"移除看剧" key:@"DYYYHideCinema" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"移除少儿" key:@"DYYYHideKidsV2" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"移除游戏" key:@"DYYYHideGame" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"移除长视频" key:@"DYYYHideMediumVideo" type:DYYYSettingItemTypeSwitch]
        ],
        @[
            [DYYYSettingItem itemWithTitle:@"精简长按面板" key:@"DYYYSimplifyLongPressPanel" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏面板项目" key:@"DYYYHidePanelItems" type:DYYYSettingItemTypeTextField placeholder:@"逗号分隔按钮名"],
            [DYYYSettingItem itemWithTitle:@"隐藏评论分享" key:@"DYYYHideCommentShareToFriends" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏评论复制" key:@"DYYYHideCommentLongPressCopy" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏评论收藏" key:@"DYYYHideCommentLongPressFavorite" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏评论保存" key:@"DYYYHideCommentLongPressSaveImage" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏评论举报" key:@"DYYYHideCommentLongPressReport" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏评论搜索" key:@"DYYYHideCommentLongPressSearch" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏评论转发日常" key:@"DYYYHideCommentLongPressDaily" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏评论视频回复" key:@"DYYYHideCommentLongPressVideoReply" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏评论识别图片" key:@"DYYYHideCommentLongPressPictureSearch" type:DYYYSettingItemTypeSwitch]
        ],
        @[
            [DYYYSettingItem itemWithTitle:@"启用新版长按面板" key:@"DYYYEnableModernPanel" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"长按面板玻璃效果" key:@"DYYYLongPressPanelBlur" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"长按面板深色模式" key:@"DYYYLongPressPanelDark" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"保存面板玻璃效果" key:@"DYYYEnableSheetBlur" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"面板毛玻璃透明度" key:@"DYYYSheetBlurTransparent" type:DYYYSettingItemTypeTextField placeholder:@"0-1小数"],
            [DYYYSettingItem itemWithTitle:@"长按面板保存视频" key:@"DYYYLongPressSaveVideo" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"长按面板保存封面" key:@"DYYYLongPressSaveCover" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"长按面板保存音频" key:@"DYYYLongPressSaveAudio" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"长按面板保存图片" key:@"DYYYLongPressSaveCurrentImage" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"长按保存所有图片" key:@"DYYYLongPressSaveAllImages" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"长按面板生成视频" key:@"DYYYLongPressCreateVideo" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"长按面板复制文案" key:@"DYYYLongPressCopyText" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"长按面板复制链接" key:@"DYYYLongPressCopyLink" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"长按面板接口解析" key:@"DYYYLongPressApiDownload" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"长按面板定时关闭" key:@"DYYYLongPressTimerClose" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"长按面板过滤文案" key:@"DYYYLongPressFilterTitle" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"长按面板过滤作者" key:@"DYYYLongPressFilterUser" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"双击面板保存视频" key:@"DYYYDoubleTapDownload" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"双击面板保存音频" key:@"DYYYDoubleTapDownloadAudio" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"双击面板接口解析" key:@"DYYYDoubleInterfaceDownload" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"双击面板制作视频" key:@"DYYYDoubleCreateVideo" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"双击面板复制文案" key:@"DYYYDoubleTapCopyDesc" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"双击面板打开评论" key:@"DYYYDoubleTapComment" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"双击面板点赞视频" key:@"DYYYDoubleTapLike" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"双击面板分享视频" key:@"DYYYDoubleTapshowSharePanel" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"双击面板长按面板" key:@"DYYYDoubleTapshowDislikeOnVideo" type:DYYYSettingItemTypeSwitch]
        ],
        @[
            [DYYYSettingItem itemWithTitle:@"启用双击打开评论" key:@"DYYYEnableDoubleOpenComment" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"启用双击打开菜单" key:@"DYYYEnableDoubleTapMenu" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"启用自动勾选原图" key:@"DYYYAutoSelectOriginalPhoto" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"资料默认进入作品" key:@"DYYYDefaultEnterWorks" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"禁用自动进入直播" key:@"DYYYDisableAutoEnterLive" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"左侧边栏快捷入口" key:@"DYYYEntrance" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"接口解析保存媒体" key:@"DYYYInterfaceDownload" type:DYYYSettingItemTypeTextField placeholder:@"不填关闭"],
            [DYYYSettingItem itemWithTitle:@"接口显示清晰选项" key:@"DYYYShowAllVideoQuality" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"保存作品信息" key:@"DYYYAlbumMediaDescription" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"移除评论实况水印" key:@"DYYYCommentLivePhotoNotWaterMark" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"移除评论图片水印" key:@"DYYYCommentNotWaterMark" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"禁用点击首页刷新" key:@"DYYYDisableHomeRefresh" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"禁用双击视频点赞" key:@"DYYYDisableDoubleTapLike" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"启用保存他人头像" key:@"DYYYEnableSaveAvatar" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"保存评论区表情包" key:@"DYYYForceDownloadEmotion" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"保存预览页表情包" key:@"DYYYForceDownloadPreviewEmotion" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"保存聊天页表情包" key:@"DYYYForceDownloadIMEmotion" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"长按评论复制评论" key:@"DYYYCommentCopyText" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"长按简介复制简介" key:@"DYYYBioCopyText" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"长按文案复制文案" key:@"DYYYLongPressCopyTextEnabled" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"下载完成震动反馈" key:@"DYYYHapticFeedbackEnabled" type:DYYYSettingItemTypeSwitch]
        ],
        @[
            [DYYYSettingItem itemWithTitle:@"启用快捷倍速按钮" key:@"DYYYEnableFloatSpeedButton" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"隐藏快捷倍速按钮时间" key:@"DYYYAutoHideSpeedButtonTime" type:DYYYSettingItemTypeTextField placeholder:@"s"],
            [DYYYSettingItem itemWithTitle:@"自动隐藏快捷倍速按钮" key:@"DYYYAutoHideSpeedButton" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"快捷倍速数值设置" key:@"DYYYSpeedSettings" type:DYYYSettingItemTypeTextField placeholder:@"逗号分隔"],
            [DYYYSettingItem itemWithTitle:@"自动恢复默认倍速" key:@"DYYYAutoRestoreSpeed" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"倍速按钮显示后缀" key:@"DYYYSpeedButtonShowX" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"快捷倍速按钮大小" key:@"DYYYSpeedButtonSize" type:DYYYSettingItemTypeTextField placeholder:@"默认32"],
            [DYYYSettingItem itemWithTitle:@"启用一键清屏按钮" key:@"DYYYEnableFloatClearButton" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"快捷清屏按钮大小" key:@"DYYYEnableFloatClearButtonSize" type:DYYYSettingItemTypeTextField placeholder:@"默认40"],
            [DYYYSettingItem itemWithTitle:@"清屏隐藏弹幕" key:@"DYYYHideDanmaku" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"清屏移除时间进度" key:@"DYYYRemoveTimeProgress" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"清屏隐藏时间进度" key:@"DYYYHideTimeProgress" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"清屏隐藏滑条" key:@"DYYYHideSlider" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"清屏隐藏底栏" key:@"DYYYHideTabBar" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"清屏隐藏倍速按钮" key:@"DYYYHideSpeed" type:DYYYSettingItemTypeSwitch]
        ]
    ];
}

- (void)setupSectionTitles {
    self.sectionTitles = [@[ @"常用功能", @"自动功能", @"基本设置", @"界面设置", @"隐藏设置", @"顶栏移除", @"隐藏面板", @"面板设置", @"功能设置", @"悬浮按钮" ] mutableCopy];
}

// 1.0.2 白色卡片主页头：龙头 logo 招牌 + 名字 + 版本 + 统计，
// 下面是搜索框（样式照 xuu 卡片的搜索框）。
- (void)setupHeaderCardAndSearch {
    CGFloat width = self.view.bounds.size.width;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 172)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    // 头卡：白底圆角卡片
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(16, 12, width - 32, 96)];
    card.backgroundColor = [UIColor whiteColor];
    card.layer.cornerRadius = 16;
    card.layer.borderWidth = 0.5;
    card.layer.borderColor = [UIColor colorWithWhite:0 alpha:0.08].CGColor;
    card.layer.shadowColor = [UIColor blackColor].CGColor;
    card.layer.shadowOpacity = 0.08;
    card.layer.shadowOffset = CGSizeMake(0, 2);
    card.layer.shadowRadius = 8;
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:card];

    // 招牌：我们自己的龙头 logo，64pt 圆形 + 金边（一眼认出是顾海龙抖音）
    UIImageView *logoView = [[UIImageView alloc] initWithFrame:CGRectMake(16, 16, 64, 64)];
    logoView.image = GHLLogoImage();
    logoView.layer.cornerRadius = 32;
    logoView.layer.masksToBounds = YES;
    logoView.layer.borderWidth = 1.5;
    logoView.layer.borderColor = [UIColor colorWithRed:212 / 255.0 green:175 / 255.0 blue:55 / 255.0 alpha:1.0].CGColor;
    logoView.contentMode = UIViewContentModeScaleAspectFill;
    [card addSubview:logoView];

    CGFloat textX = 92;
    CGFloat textW = card.bounds.size.width - textX - 16;
    UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(textX, 14, textW, 24)];
    nameLabel.text = @"顾海龙抖音";
    nameLabel.font = [UIFont boldSystemFontOfSize:20];
    nameLabel.textColor = [UIColor blackColor];
    nameLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [card addSubview:nameLabel];

    UILabel *versionLabel = [[UILabel alloc] initWithFrame:CGRectMake(textX, 40, textW, 18)];
    versionLabel.text = [NSString stringWithFormat:@"Version: %@", DYYY_VERSION];
    versionLabel.font = [UIFont systemFontOfSize:13];
    versionLabel.textColor = [UIColor grayColor];
    versionLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [card addSubview:versionLabel];

    self.statsLabel = [[UILabel alloc] initWithFrame:CGRectMake(textX, 60, textW, 18)];
    self.statsLabel.font = [UIFont systemFontOfSize:13];
    self.statsLabel.textColor = [UIColor grayColor];
    self.statsLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [card addSubview:self.statsLabel];

    // 搜索框
    UISearchBar *searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(16, 116, width - 32, 44)];
    searchBar.placeholder = @"搜索设置项";
    searchBar.searchBarStyle = UISearchBarStyleMinimal;
    searchBar.delegate = self;
    searchBar.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:searchBar];
    self.searchBar = searchBar;

    self.tableView.tableHeaderView = header;
}

- (void)refreshHeaderStats {
    if (!self.statsLabel) return;
    NSInteger total = 0;
    NSInteger enabled = 0;
    for (NSArray<DYYYSettingItem *> *section in self.settingSections) {
        total += (NSInteger)section.count;
        for (DYYYSettingItem *item in section) {
            if (item.type == DYYYSettingItemTypeSwitch && [[NSUserDefaults standardUserDefaults] boolForKey:item.key]) {
                enabled++;
            }
        }
    }
    self.statsLabel.text = [NSString stringWithFormat:@"%ld 项设置 · %ld 项已开启", (long)total, (long)enabled];
}

// 底部一排按钮：关于 / 基于DYYY / MIT 声明（照 xuu 卡片底部三个按钮的样子）。
- (void)setupFooterButtons {
    CGFloat width = self.view.bounds.size.width;
    UIView *footer = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 116)];
    footer.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    NSArray<NSString *> *titles = @[ @"关于", @"基于DYYY", @"MIT 声明" ];
    CGFloat buttonWidth = (width - 32 - 16) / 3.0;
    for (NSInteger i = 0; i < 3; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.frame = CGRectMake(16 + i * (buttonWidth + 8), 12, buttonWidth, 44);
        [button setTitle:titles[i] forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
        [button setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        button.backgroundColor = [UIColor colorWithWhite:0.93 alpha:1.0];
        button.layer.cornerRadius = 12;
        button.tag = i;
        [button addTarget:self action:@selector(footerButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        button.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [footer addSubview:button];
    }

    UILabel *attributionLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 68, width - 32, 16)];
    attributionLabel.text = @"基于 DYYY (MIT, Copyright (c) 2024 huami)，仅自用";
    attributionLabel.font = [UIFont systemFontOfSize:12];
    attributionLabel.textColor = [UIColor grayColor];
    attributionLabel.textAlignment = NSTextAlignmentCenter;
    attributionLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [footer addSubview:attributionLabel];

    self.tableView.tableFooterView = footer;
}

- (void)footerButtonTapped:(UIButton *)sender {
    if (sender.tag == 0) {
        [DYYYSettingsHelper showAboutDialog:@"关于顾海龙抖音"
                                    message:[NSString stringWithFormat:@"版本：%@\n\n顾海龙抖音是基于 DYYY (MIT, Copyright (c) 2024 huami) 的个人二创，仅自用，不对外发布。\n\n感谢 huami 开源 DYYY。\n\nQQ交流：2309103548", DYYY_VERSION]
                                  onConfirm:nil];
    } else if (sender.tag == 1) {
        [DYYYSettingsHelper showAboutDialog:@"基于 DYYY"
                                    message:@"本插件基于 DYYY (MIT, Copyright (c) 2024 huami) 二次开发，原作者 huami，源码仓库 Wtrwx/DYYY。\n\n顾海龙抖音只做个人二创，不对外发布；原作者版权声明保留在 LICENSE 中。"
                                  onConfirm:nil];
    } else {
        [DYYYSettingsHelper showAboutDialog:@"MIT License"
                                    message:@"Copyright (c) 2024 huami.\n\n"
                                            @"Permission is hereby granted, free of charge, to any person obtaining a copy "
                                            @"of this software and associated documentation files (the \"Software\"), to deal "
                                            @"in the Software without restriction, including without limitation the rights "
                                            @"to use, copy, modify, merge, publish, distribute, sublicense, and/or sell "
                                            @"copies of the Software, and to permit persons to whom the Software is "
                                            @"furnished to do so, subject to the following conditions:\n\n"
                                            @"The above copyright notice and this permission notice shall be included in all "
                                            @"copies or substantial portions of the Software.\n\n"
                                            @"THE SOFTWARE IS PROVIDED \"AS IS\", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR "
                                            @"IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, "
                                            @"FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE "
                                            @"AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER "
                                            @"LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, "
                                            @"OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE "
                                            @"SOFTWARE."
                                  onConfirm:nil];
    }
}

#pragma mark - Helper Methods

- (NSArray *)optionsForKey:(NSString *)key {
    if ([key isEqualToString:@"DYYYDefaultSpeed"] || [key isEqualToString:@"DYYYLongPressSpeed"]) {
        // 倍速选项
        return @[ @0.75, @1.0, @1.25, @1.5, @2.0, @2.5, @3.0 ];
    } else if ([key isEqualToString:GHL_KEY_SLEEP_TIMER]) {
        // 睡眠定时选项
        return @[ @"关闭", @"15分钟", @"30分钟", @"60分钟" ];
    } else if ([key isEqualToString:GHL_KEY_VOICE_PACKAGE_ID]) {
        // 语音包音色选项（动态：内置本机音色 + 已缓存的在线音色，见 GHLFeatures.h）
        return GHLVoicePackageIDs();
    } else if ([key isEqualToString:GHL_KEY_VOICE_PACKAGE_MANAGER]) {
        // 语音包管理器入口（点开进列表页，值本身无意义）
        return @[ @"打开语音包管理器" ];
    } else if ([key isEqualToString:@"DYYYLiveQuality"]) {
        // 直播清晰度选项
        return @[ @"蓝光帧彩", @"蓝光", @"超清", @"高清", @"标清", @"自动" ];
    } else if ([key isEqualToString:@"DYYYHDRMode"]) {
        return @[ @"关闭", @"全局屏蔽HDR效果", @"全局过滤HDR作品" ];
    }
    return @[];
}

- (NSString *)displayValueForKey:(NSString *)key value:(id)value {
    if ([key isEqualToString:@"DYYYDefaultSpeed"] || [key isEqualToString:@"DYYYLongPressSpeed"]) {
        // 倍速显示格式
        float speedValue = [value floatValue];
        return [NSString stringWithFormat:@"%.2f", speedValue];
    } else if ([key isEqualToString:GHL_KEY_SLEEP_TIMER]) {
        return value ?: @"关闭";
    } else if ([key isEqualToString:GHL_KEY_VOICE_PACKAGE_ID]) {
        return GHLVoicePackageDisplayNameForID(value) ?: @"未选择";
    } else if ([key isEqualToString:GHL_KEY_VOICE_PACKAGE_MANAGER]) {
        return @"打开语音包管理器";
    } else if ([key isEqualToString:@"DYYYLiveQuality"]) {
    } else if ([key isEqualToString:@"DYYYHDRMode"]) {
        return value ?: @"关闭";
    }
    return [NSString stringWithFormat:@"%@", value];
}

- (id)defaultValueForKey:(NSString *)key {
    if ([key isEqualToString:@"DYYYDefaultSpeed"] || [key isEqualToString:@"DYYYLongPressSpeed"]) {
        return @1.0;
    } else if ([key isEqualToString:GHL_KEY_SLEEP_TIMER]) {
        return @"关闭";
    } else if ([key isEqualToString:GHL_KEY_VOICE_PACKAGE_ID]) {
        return GHLVoicePackageIDs().firstObject ?: @"sys:default-zh-CN";
    } else if ([key isEqualToString:GHL_KEY_VOICE_PACKAGE_MANAGER]) {
        return @"打开语音包管理器";
    } else if ([key isEqualToString:@"DYYYLiveQuality"]) {
        return @"自动";
    } else if ([key isEqualToString:@"DYYYHDRMode"]) {
        return @"关闭";
    }
    return nil;
}

#pragma mark - First Launch Agreement

- (void)checkFirstLaunch {
    BOOL hasAgreed = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYUserAgreementAccepted"];

    if (!hasAgreed) {
        dispatch_async(dispatch_get_main_queue(), ^{
          [self showAgreementAlert];
        });
    }
}

- (void)showAgreementAlert {
    UIAlertController *alertController =
        [UIAlertController alertControllerWithTitle:@"用户协议"
                                            message:@"本插件为开源项目\n仅供学习交流用途\n如有侵权请联系, GitHub 仓库：huami1314/DYYY\n请遵守当地法律法规, "
                                                    @"逆向工程仅为学习目的\n盗用源码进行商业用途/发布但未标记开源项目必究\n详情请参阅项目内 MIT 许可证\n\n请输入\"我已阅读并同意继续使用\"以继续使用"
                                     preferredStyle:UIAlertControllerStyleAlert];

    [alertController addTextFieldWithConfigurationHandler:^(UITextField *_Nonnull textField) {
      textField.clearButtonMode = UITextFieldViewModeWhileEditing;
    }];

    UIAlertAction *confirmAction = [UIAlertAction actionWithTitle:@"确认"
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction *_Nonnull action) {
                                                            UITextField *textField = alertController.textFields.firstObject;
                                                            NSString *inputText = textField.text;

                                                            if ([inputText isEqualToString:@"我已阅读并同意继续使用"]) {
                                                                [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"DYYYUserAgreementAccepted"];
                                                            } else {
                                                                UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"输入错误"
                                                                                                                                    message:@"请正确输入"
                                                                                                                             preferredStyle:UIAlertControllerStyleAlert];

                                                                UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定"
                                                                                                                   style:UIAlertActionStyleDefault
                                                                                                                 handler:^(UIAlertAction *_Nonnull action) {
                                                                                                                   [self showAgreementAlert];
                                                                                                                 }];

                                                                [errorAlert addAction:okAction];
                                                                [self presentViewController:errorAlert animated:YES completion:nil];
                                                            }
                                                          }];

    UIAlertAction *exitAction = [UIAlertAction actionWithTitle:@"退出"
                                                         style:UIAlertActionStyleDestructive
                                                       handler:^(UIAlertAction *_Nonnull action) {
                                                         exit(0);
                                                       }];

    [alertController addAction:confirmAction];
    [alertController addAction:exitAction];

    [self presentViewController:alertController animated:YES completion:nil];
}

#pragma mark - UITableViewDataSource

// 当前行对应的设置项（主页分类行返回 nil；子页/搜索返回真实项）。
- (nullable DYYYSettingItem *)itemForIndexPath:(NSIndexPath *)indexPath {
    if ([self isHomeMode] && ![self isSearching]) return nil;
    if ([self isSearching]) {
        return self.searchResults[indexPath.row][@"item"];
    }
    return self.settingSections[self.displaySectionIndex][indexPath.row];
}

// 当前行对应项的真实分区/行号（开关、输入框的 tag 用真实号编码，事件处理才能找到原项）。
- (NSInteger)realSectionForIndexPath:(NSIndexPath *)indexPath {
    if ([self isSearching]) return [self.searchResults[indexPath.row][@"section"] integerValue];
    return self.displaySectionIndex;
}

- (NSInteger)realRowForIndexPath:(NSIndexPath *)indexPath {
    if ([self isSearching]) return [self.searchResults[indexPath.row][@"row"] integerValue];
    return indexPath.row;
}

- (BOOL)isSearching {
    return self.searchResults != nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if ([self isHomeMode]) {
        if ([self isSearching]) return (NSInteger)self.searchResults.count;
        return (NSInteger)self.sectionTitles.count;
    }
    return (NSInteger)self.settingSections[self.displaySectionIndex].count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    DYYYSettingItem *item = [self itemForIndexPath:indexPath];
    if (!item) return 56;  // 主页分类行
    // 带括号标注的行用两行显示（主标题 + 第二行小字标注），行高要够放两行
    NSRange noteRange = [item.title rangeOfString:@"（"];
    return (noteRange.location != NSNotFound && noteRange.location > 0) ? 60 : 44;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // 主页分类行：标题 + 右端数量 + 箭头（照 xuu 卡片各行右端带数字的样子）
    if ([self isHomeMode] && ![self isSearching]) {
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"GHLCategoryCell"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:@"GHLCategoryCell"];
            cell.textLabel.font = [UIFont systemFontOfSize:17];
            cell.detailTextLabel.font = [UIFont systemFontOfSize:15];
            cell.detailTextLabel.textColor = [UIColor grayColor];
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        cell.textLabel.text = self.sectionTitles[indexPath.row];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld", (long)self.settingSections[indexPath.row].count];
        return cell;
    }
    return [self itemCellForIndexPath:indexPath tableView:tableView];
}

// 子页/搜索里某一项的白底行（开关/输入框/选择器），与 1.0.1 同一套交互。
- (UITableViewCell *)itemCellForIndexPath:(NSIndexPath *)indexPath tableView:(UITableView *)tableView {
    DYYYSettingItem *item = [self itemForIndexPath:indexPath];
    NSInteger realSection = [self realSectionForIndexPath:indexPath];
    NSInteger realRow = [self realRowForIndexPath:indexPath];
    NSInteger tag = realSection * 1000 + realRow;

    // 括号里的标注太长会被截断：把“（...）”拆出来放第二行 12pt 小字显示，
    // 主标题只留名称。没标注的行保持原来单行样式。搜索时无标注的行第二行显示所属分类。
    NSString *mainTitle = item.title;
    NSString *noteTitle = nil;
    NSRange noteRange = [item.title rangeOfString:@"（"];
    if (noteRange.location != NSNotFound && noteRange.location > 0) {
        mainTitle = [item.title substringToIndex:noteRange.location];
        noteTitle = [item.title substringFromIndex:noteRange.location];
    } else if ([self isSearching]) {
        noteTitle = self.sectionTitles[realSection];
    }

    UITableViewCell *cell = nil;
    if (noteTitle) {
        cell = [tableView dequeueReusableCellWithIdentifier:@"SettingCellNote"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"SettingCellNote"];
            cell.textLabel.font = [UIFont systemFontOfSize:17];
            cell.detailTextLabel.font = [UIFont systemFontOfSize:12];
            cell.detailTextLabel.textColor = [UIColor grayColor];
            cell.detailTextLabel.numberOfLines = 2;

            UIView *selectedBackgroundView = [[UIView alloc] init];
            selectedBackgroundView.backgroundColor = [UIColor colorWithWhite:0.9 alpha:1.0];
            cell.selectedBackgroundView = selectedBackgroundView;
        }
        cell.textLabel.text = mainTitle;
        cell.detailTextLabel.text = noteTitle;
    } else {
        cell = [tableView dequeueReusableCellWithIdentifier:@"SettingCell"];
        if (!cell) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"SettingCell"];
            cell.textLabel.translatesAutoresizingMaskIntoConstraints = NO;
            [cell.textLabel.leadingAnchor constraintEqualToAnchor:cell.contentView.leadingAnchor constant:16].active = YES;
            [cell.textLabel.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor].active = YES;

            UIView *selectedBackgroundView = [[UIView alloc] init];
            selectedBackgroundView.backgroundColor = [UIColor colorWithWhite:0.9 alpha:1.0];
            cell.selectedBackgroundView = selectedBackgroundView;
        }
        cell.textLabel.text = item.title;
    }

    cell.textLabel.textColor = [UIColor blackColor];
    cell.backgroundColor = [UIColor whiteColor];

    if (item.type == DYYYSettingItemTypeSwitch) {
        UISwitch *switchView = [[UISwitch alloc] init];
        [switchView setOn:[[NSUserDefaults standardUserDefaults] boolForKey:item.key]];
        [switchView addTarget:self action:@selector(switchToggled:) forControlEvents:UIControlEventValueChanged];
        switchView.tag = tag;
        cell.accessoryView = switchView;
    } else if (item.type == DYYYSettingItemTypeTextField) {
        UITextField *textField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 120, 30)];
        textField.borderStyle = UITextBorderStyleRoundedRect;
        textField.font = [UIFont systemFontOfSize:14];
        textField.placeholder = item.placeholder;
        textField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:item.placeholder attributes:@{NSForegroundColorAttributeName : [UIColor grayColor]}];
        textField.text = [[NSUserDefaults standardUserDefaults] objectForKey:item.key];
        textField.textAlignment = NSTextAlignmentRight;
        textField.backgroundColor = [UIColor colorWithWhite:0.94 alpha:1.0];
        textField.textColor = [UIColor blackColor];

        [textField addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingDidEnd];
        textField.tag = tag;
        cell.accessoryView = textField;
    } else if (item.type == DYYYSettingItemTypePicker) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

        UILabel *pickerLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 140, 44)];
        // 获取当前值
        id currentValue = [[NSUserDefaults standardUserDefaults] objectForKey:item.key];
        if (!currentValue) {
            currentValue = [self defaultValueForKey:item.key];
        }

        pickerLabel.text = [self displayValueForKey:item.key value:currentValue];
        pickerLabel.font = [UIFont systemFontOfSize:13];
        pickerLabel.textColor = [UIColor blackColor];
        pickerLabel.textAlignment = NSTextAlignmentRight;
        pickerLabel.tag = tag;
        // 值太长（例如音色名“李牧 (z…)”）时自动缩小字号显示，不截断
        pickerLabel.adjustsFontSizeToFitWidth = YES;
        pickerLabel.minimumScaleFactor = 0.7;

        // 添加垂直居中约束
        pickerLabel.translatesAutoresizingMaskIntoConstraints = NO;
        UIView *containerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 140, 44)];
        [containerView addSubview:pickerLabel];

        [NSLayoutConstraint activateConstraints:@[
            [pickerLabel.centerYAnchor constraintEqualToAnchor:containerView.centerYAnchor], [pickerLabel.leadingAnchor constraintEqualToAnchor:containerView.leadingAnchor],
            [pickerLabel.trailingAnchor constraintEqualToAnchor:containerView.trailingAnchor]
        ]];

        cell.accessoryView = containerView;
    }

    return cell;
}

#pragma mark - UISearchBarDelegate

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    searchBar.showsCancelButton = YES;
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar {
    searchBar.showsCancelButton = NO;
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    if (searchText.length == 0) {
        self.searchResults = nil;
    } else {
        NSMutableArray<NSDictionary *> *results = [NSMutableArray array];
        for (NSInteger s = 0; s < (NSInteger)self.settingSections.count; s++) {
            NSArray<DYYYSettingItem *> *items = self.settingSections[s];
            for (NSInteger r = 0; r < (NSInteger)items.count; r++) {
                DYYYSettingItem *item = items[r];
                if ([item.title rangeOfString:searchText options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    [results addObject:@{@"item": item, @"section": @(s), @"row": @(r)}];
                }
            }
        }
        self.searchResults = results;
    }
    [self.tableView reloadData];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    searchBar.text = @"";
    self.searchResults = nil;
    [searchBar resignFirstResponder];
    [self.tableView reloadData];
}

#pragma mark - UITableViewDelegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    // 主页分类行：直接进该分类的子页，不再中转旧深色页。
    if ([self isHomeMode] && ![self isSearching]) {
        DYYYSettingViewController *subVC = [[DYYYSettingViewController alloc] initWithSectionIndex:indexPath.row];
        [self.navigationController pushViewController:subVC animated:YES];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }
    DYYYSettingItem *item = [self itemForIndexPath:indexPath];
    if (item.type == DYYYSettingItemTypePicker) {
        [self showUniversalPickerForIndexPath:indexPath];
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)showUniversalPickerForIndexPath:(NSIndexPath *)indexPath {
    DYYYSettingItem *item = [self itemForIndexPath:indexPath];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:[NSString stringWithFormat:@"选择%@", item.title] message:nil preferredStyle:UIAlertControllerStyleActionSheet];

    NSArray *options = [self optionsForKey:item.key];
    for (id option in options) {
        NSString *title = [self displayValueForKey:item.key value:option];
        UIAlertAction *action = [UIAlertAction actionWithTitle:title
                                                         style:UIAlertActionStyleDefault
                                                       handler:^(UIAlertAction *_Nonnull action) {
                                                         // 保存到对应的key
                                                         [[NSUserDefaults standardUserDefaults] setObject:option forKey:item.key];
                                                         // 顾海龙抖音：选完睡眠定时立即重启动时；选完语音包音色立即试听；选管理器打开列表页
                                                         if ([item.key isEqualToString:GHL_KEY_VOICE_PACKAGE_MANAGER]) {
                                                             GHLPresentVoicePackageManagerFromViewController(self);
                                                         } else if ([item.key isEqualToString:GHL_KEY_SLEEP_TIMER]) {
                                                             GHLRestartSleepTimer();
                                                         } else if ([item.key isEqualToString:GHL_KEY_VOICE_PACKAGE_ID]) {
                                                             GHLPreviewVoicePackage((NSString *)option);
                                                         }

                                                         // 更新对应的cell显示
                                                         UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
                                                         UIView *containerView = cell.accessoryView;
                                                         if (containerView && containerView.subviews.count > 0) {
                                                             UILabel *pickerLabel = (UILabel *)containerView.subviews.firstObject;
                                                             if ([pickerLabel isKindOfClass:[UILabel class]]) {
                                                                 pickerLabel.text = [self displayValueForKey:item.key value:option];
                                                             }
                                                         }
                                                       }];
        [alert addAction:action];
    }

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
    [alert addAction:cancelAction];

    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        UITableViewCell *selectedCell = [self.tableView cellForRowAtIndexPath:indexPath];
        alert.popoverPresentationController.sourceView = selectedCell;
        alert.popoverPresentationController.sourceRect = selectedCell.bounds;
    }

    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - Actions

- (void)switchToggled:(UISwitch *)sender {
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:sender.tag % 1000 inSection:sender.tag / 1000];
    DYYYSettingItem *item = self.settingSections[indexPath.section][indexPath.row];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:sender.isOn forKey:item.key];
    if ([item.key isEqualToString:@"DYYYEnableFloatSpeedButton"] || [item.key isEqualToString:@"DYYYSpeedButtonShowX"]) {
        [FloatingSpeedButton reloadConfiguration];
    }
    if ([item.key isEqualToString:@"DYYYEnableFloatClearButton"] ||
        [item.key isEqualToString:@"DYYYHideDanmaku"] ||
        [item.key isEqualToString:@"DYYYRemoveTimeProgress"] ||
        [item.key isEqualToString:@"DYYYHideTimeProgress"] ||
        [item.key isEqualToString:@"DYYYHideSlider"] ||
        [item.key isEqualToString:@"DYYYHideTabBar"] ||
        [item.key isEqualToString:@"DYYYHideSpeed"] ||
        [item.key isEqualToString:@"DYYYHideChapter"]) {
        reloadClearButtonConfiguration();
    }

    // 顾海龙抖音：开关联动
    if ([item.key isEqualToString:GHL_KEY_LIVE_PURIFY]) {
        GHLApplyLivePurification(sender.isOn);
    } else if ([item.key isEqualToString:GHL_KEY_CLEAN_MODE]) {
        GHLApplyCleanMode(sender.isOn);
    } else if ([item.key isEqualToString:GHL_KEY_NIGHT_MODE]) {
        GHLApplyNightMode(sender.isOn);
    } else if ([item.key isEqualToString:GHL_KEY_BGM_SAVE]) {
        [defaults setBool:sender.isOn forKey:@"DYYYLongPressSaveAudio"];
    } else if ([item.key isEqualToString:GHL_KEY_COMMENT_IMAGE_SAVE]) {
        [defaults setBool:sender.isOn forKey:@"DYYYForceDownloadCommentImage"];
    } else if ([item.key isEqualToString:GHL_KEY_COMMENT_DANMAKU]) {
        [defaults setBool:sender.isOn forKey:@"DYYYCommentShowDanmaku"];
    } else if ([item.key isEqualToString:GHL_KEY_ANTI_RECALL]) {
        if (sender.isOn) GHLProbeAntiRecall();
    } else if ([item.key isEqualToString:GHL_KEY_VOICE_PACKAGE]) {
        if (sender.isOn) GHLProbeLiveVoiceSender();
    } else if ([item.key isEqualToString:GHL_KEY_BACKGROUND_AUDIO]) {
        [defaults setBool:sender.isOn forKey:@"DYYYEnableBackgroundListen"];
    } else if ([item.key isEqualToString:GHL_KEY_DISABLE_VISIT_REPORT]) {
        [defaults setBool:sender.isOn forKey:@"DYYYDisableProfileVisitRecordUpload"];
        [defaults setBool:sender.isOn forKey:@"DYYYDisableAwemeViewRecordUpload"];
    } else if ([item.key isEqualToString:GHL_KEY_LONG_PRESS_DOWNLOAD]) {
        [defaults setBool:sender.isOn forKey:@"DYYYLongPressSaveVideo"];
    } else if ([item.key isEqualToString:GHL_KEY_SKIP_LIVE]) {
        [defaults setBool:sender.isOn forKey:@"DYYYSkipLive"];
    } else if ([item.key isEqualToString:GHL_KEY_DANMAKU_COLOR]) {
        [defaults setBool:sender.isOn forKey:@"DYYYEnableDanmuColor"];
        NSString *color = GHLGetString(GHL_KEY_DANMAKU_COLOR_VALUE);
        if (color.length > 0) [defaults setObject:color forKey:@"DYYYDanmuColor"];
    } else if ([item.key isEqualToString:GHL_KEY_COMMENT_BLUR]) {
        [defaults setBool:sender.isOn forKey:@"DYYYEnableCommentBlur"];
    } else if ([item.key isEqualToString:GHL_KEY_TOP_BAR_TRANSPARENT]) {
        NSString *alpha = GHLGetString(GHL_KEY_TOP_BAR_TRANSPARENCY);
        if (alpha.length == 0) alpha = @"0.5";
        [defaults setObject:alpha forKey:@"DYYYGlobalTransparency"];
    } else if ([item.key isEqualToString:GHL_KEY_HIDE_STATUS_BAR]) {
        [defaults setBool:sender.isOn forKey:@"DYYYHideStatusbar"];
    }

    if (sender.isOn) {
        NSString *conflictingKey = nil;
        if ([item.key isEqualToString:@"DYYYHideLOTAnimationView"]) {
            conflictingKey = @"DYYYHideFollowPromptView";
        } else if ([item.key isEqualToString:@"DYYYHideFollowPromptView"]) {
            conflictingKey = @"DYYYHideLOTAnimationView";
        }

        if (conflictingKey) {
            [defaults setBool:NO forKey:conflictingKey];
            [self.tableView reloadData];
        }
    }
}

- (void)textFieldDidChange:(UITextField *)textField {
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:textField.tag % 1000 inSection:textField.tag / 1000];
    DYYYSettingItem *item = self.settingSections[indexPath.section][indexPath.row];
    [[NSUserDefaults standardUserDefaults] setObject:textField.text forKey:item.key];
    // 顾海龙抖音：输入值同步到上游键
    if ([item.key isEqualToString:GHL_KEY_DANMAKU_COLOR_VALUE]) {
        [[NSUserDefaults standardUserDefaults] setObject:textField.text forKey:@"DYYYDanmuColor"];
    }
    if ([item.key isEqualToString:GHL_KEY_TOP_BAR_TRANSPARENCY]) {
        [[NSUserDefaults standardUserDefaults] setObject:textField.text forKey:@"DYYYGlobalTransparency"];
    }
    if ([item.key isEqualToString:@"DYYYSpeedSettings"] || [item.key isEqualToString:@"DYYYSpeedButtonSize"]) {
        [FloatingSpeedButton reloadConfiguration];
    }
    if ([item.key isEqualToString:@"DYYYEnableFloatClearButtonSize"]) {
        reloadClearButtonConfiguration();
    }
}

@end
