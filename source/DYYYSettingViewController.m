#import "DYYYSettingViewController.h"
#import <Foundation/Foundation.h>
#import <Photos/Photos.h>
#import <UIKit/UIKit.h>
#import "DYYYBackupPickerDelegate.h"
#import "DYYYBottomAlertView.h"
#import "DYYYConstants.h"
#import "DYYYCustomInputView.h"
#import "GHLAboutViewController.h"
#import "DYYYFloatClearButton.h"
#import "DYYYFloatSpeedButton.h"
#import "DYYYImagePickerDelegate.h"
#import "DYYYSettingsHelper.h"
#import "DYYYUtils.h"
#import "GHLFeatures.h"

typedef NS_ENUM(NSInteger, DYYYSettingItemType) { DYYYSettingItemTypeSwitch, DYYYSettingItemTypeTextField, DYYYSettingItemTypePicker };

@interface DYYYSettingItem : NSObject

@property(nonatomic, copy) NSString *title;
@property(nonatomic, copy) NSString *key;
@property(nonatomic, assign) DYYYSettingItemType type;
@property(nonatomic, copy, nullable) NSString *placeholder;
// 1.0.28：行提示文案（有值时开关左边并排一个 ⓘ 按钮，点它弹这段文案）。
@property(nonatomic, copy, nullable) NSString *infoText;

+ (instancetype)itemWithTitle:(NSString *)title key:(NSString *)key type:(DYYYSettingItemType)type;
+ (instancetype)itemWithTitle:(NSString *)title key:(NSString *)key type:(DYYYSettingItemType)type placeholder:(nullable NSString *)placeholder;
+ (instancetype)itemWithTitle:(NSString *)title key:(NSString *)key type:(DYYYSettingItemType)type infoText:(nullable NSString *)infoText;
+ (instancetype)itemWithTitle:(NSString *)title key:(NSString *)key type:(DYYYSettingItemType)type placeholder:(nullable NSString *)placeholder infoText:(nullable NSString *)infoText;

@end

@implementation DYYYSettingItem

+ (instancetype)itemWithTitle:(NSString *)title key:(NSString *)key type:(DYYYSettingItemType)type {
    return [self itemWithTitle:title key:key type:type placeholder:nil];
}

+ (instancetype)itemWithTitle:(NSString *)title key:(NSString *)key type:(DYYYSettingItemType)type placeholder:(nullable NSString *)placeholder {
    return [self itemWithTitle:title key:key type:type placeholder:placeholder infoText:nil];
}

+ (instancetype)itemWithTitle:(NSString *)title key:(NSString *)key type:(DYYYSettingItemType)type infoText:(nullable NSString *)infoText {
    return [self itemWithTitle:title key:key type:type placeholder:nil infoText:infoText];
}

+ (instancetype)itemWithTitle:(NSString *)title key:(NSString *)key type:(DYYYSettingItemType)type placeholder:(nullable NSString *)placeholder infoText:(nullable NSString *)infoText {
    DYYYSettingItem *item = [[DYYYSettingItem alloc] init];
    item.title = title;
    item.key = key;
    item.type = type;
    item.placeholder = placeholder;
    item.infoText = infoText;
    return item;
}

@end

@interface DYYYSettingViewController () <UITableViewDelegate, UITableViewDataSource, UISearchBarDelegate, UIColorPickerViewControllerDelegate>

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
// 1.0.31：头卡名字（点一下改自定义显示名，见 ghlNameLabelTapped）。
@property(nonatomic, strong, nullable) UILabel *nameLabel;
// 1.0.4：头卡龙头（点一下换图、长按恢复默认）、相册/文件选择器的 delegate（要强引用留着，等回调）。
@property(nonatomic, strong, nullable) UIImageView *logoImageView;
@property(nonatomic, strong, nullable) UIImage *backgroundImage;
// 1.0.22：上次排过的表宽——viewDidLayoutSubviews 里表宽变了才 reload（子页 view 在 viewDidLoad
// 时还是屏幕宽，表按屏幕宽建；排到卡片宽之后行要重建，不然开关/输入框按屏幕宽排、右边被裁）。
@property(nonatomic, assign) CGFloat ghlLastTableWidth;
@property(nonatomic, strong, nullable) DYYYImagePickerDelegate *imagePickerDelegate;
@property(nonatomic, assign) NSInteger pendingImagePickerKind; // 0 = 换龙头，2 = 快捷面板背景图

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

// 1.0.20：卡片记住上次停在哪一页（主页 NSNotFound，分类子页是分区下标）。
- (NSInteger)ghlDisplaySectionIndex {
    return self.displaySectionIndex;
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
        [self refreshHeaderStats];
    }
    // 1.0.4：深色跟随 + 自定义背景（主页和子页都走同一套）。
    [self ghlApplySettingsAppearance];
    [self ghlApplySettingsBackground];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // 从子页返回时刷新头卡统计（已开启数可能变了）。
    if ([self isHomeMode]) {
        [self refreshHeaderStats];
        // 1.0.31：自定义名称可能在基本设置子页里改过，回来刷新头卡名字。
        [self ghlRefreshHeaderName];
        // 龙头可能在子页里换过（恢复默认龙头行），回来刷新。
        self.logoImageView.image = GHLLogoImage();
    }
    [self ghlApplySettingsAppearance];
    [self ghlApplySettingsBackground];
}

// 1.0.22：表按 view 的最终尺寸排（viewDidLoad 时 view 还是屏幕宽，表按屏幕宽建；
// 排到卡片宽之后行要重建一次，不然开关/输入框/附属值按屏幕宽排、右边被卡片裁掉，录屏实锤）。
// 宽度没变时不 reload，免得每次排版都重建行；高度只跟 view 走，不改 contentSize。
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    if (!self.tableView) return;
    self.tableView.frame = self.view.bounds;
    CGFloat width = self.view.bounds.size.width;
    if (width > 0 && fabs(width - self.ghlLastTableWidth) > 0.5) {
        self.ghlLastTableWidth = width;
        [self.tableView reloadData];
    }
    // 第 8 项：卡片内列表底部留 16pt——最底下一行滚到底时不贴着「完成」按钮，
    // 也不被导航栈底边裁掉一半（录屏里常用功能最底下一行就是这么被盖住的）。
    if (self.ghlInFloatPanel) {
        UIEdgeInsets bottomInset = UIEdgeInsetsMake(0, 0, 16, 0);
        if (!UIEdgeInsetsEqualToEdgeInsets(self.tableView.contentInset, bottomInset)) {
            self.tableView.contentInset = bottomInset;
            self.tableView.scrollIndicatorInsets = bottomInset;
        }
    }
}

// 系统深浅变了（跟随系统深色开着时），重刷颜色和背景遮罩。
- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if (GHLFollowSystemDarkEnabled()) {
        [self ghlApplySettingsAppearance];
        [self ghlApplySettingsBackground];
    }
}

// 1.0.4：当前是不是深色（跟随系统深色开着、且系统/抖音是深色）。
// 1.0.21：卡片内永远按浅色算（卡片本身就是浅色玻璃，深色字才看得清）。
- (BOOL)ghlDarkModeActive {
    if (self.ghlInFloatPanel) return NO;
    return GHLFollowSystemDarkEnabled() && [DYYYUtils isDarkMode];
}

// 1.0.4：统一视觉——深色跟随（关了就强制浅色：overrideUserInterfaceStyle 让系统颜色也跟着浅）。
- (void)ghlApplySettingsAppearance {
    // 1.0.24：卡片内页底改透明（卡片底已经铺了整张自定义背景图 + 淡白遮罩，
    // 页底透明才能让图从列表后面透出来；行底是半透明白，字看得清）。
    // 没自选图时卡片底是实心浅灰，透明页底露出来就是浅灰，和原来一样。
    if (self.ghlInFloatPanel) {
        self.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
        self.view.backgroundColor = [UIColor clearColor];
        return;
    }
    self.overrideUserInterfaceStyle = GHLFollowSystemDarkEnabled() ? UIUserInterfaceStyleUnspecified : UIUserInterfaceStyleLight;
    BOOL dark = [self ghlDarkModeActive];
    self.view.backgroundColor = dark ? [UIColor colorWithRed:28 / 255.0 green:28 / 255.0 blue:30 / 255.0 alpha:1.0] : [UIColor systemGroupedBackgroundColor];
}

// 1.0.4：自定义背景铺底（有自选图就铺图 + 遮罩，没有就回默认分组底色）。
- (void)ghlApplySettingsBackground {
    // 1.0.24：卡片内不自己铺图（整张图已经铺在卡片底，见 GHLFeatures.xm；
    // 这里再铺一张会和卡片底图错位出两道边），表底改透明让卡片底图透出来。
    if (self.ghlInFloatPanel) {
        self.tableView.backgroundView = nil;
        self.tableView.backgroundColor = [UIColor clearColor];
        [self.tableView reloadData];
        return;
    }
    BOOL dark = [self ghlDarkModeActive];
    self.backgroundImage = GHLCustomBackgroundImage();
    self.tableView.backgroundView = [DYYYUtils dYYYSettingsBackgroundViewForImage:self.backgroundImage darkMode:dark];
    self.tableView.backgroundColor = self.backgroundImage ? [UIColor clearColor] : [UIColor systemGroupedBackgroundColor];
    [self.tableView reloadData];
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

    // 1.0.4：跟随系统深色默认开
    if (![defaults objectForKey:GHL_KEY_FOLLOW_SYSTEM_DARK]) {
        [defaults setBool:YES forKey:GHL_KEY_FOLLOW_SYSTEM_DARK];
    }

}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];

    if (!self.isAgreementShown) {
        [self checkFirstLaunch];
        self.isAgreementShown = YES;
    }

    // 1.0.4 更新日志：版本号变了，进设置主页时弹一次（只在主页、且已同意过协议时弹）。
    if ([self isHomeMode]) {
        [self ghlShowChangelogIfNeeded];
    }
}

// 1.0.4：版本号变了就弹一次更新日志（记录上次见过的版本号，下次不再弹）。
- (void)ghlShowChangelogIfNeeded {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (![defaults boolForKey:@"DYYYUserAgreementAccepted"]) return;
    NSString *lastSeen = [defaults stringForKey:GHL_KEY_LAST_SEEN_VERSION];
    if ([lastSeen isEqualToString:DYYY_VERSION]) return;
    [defaults setObject:DYYY_VERSION forKey:GHL_KEY_LAST_SEEN_VERSION];
    [DYYYSettingsHelper showAboutDialog:@"更新日志" message:GHLChangelogText() onConfirm:nil];
}

- (void)setupAppearance {
    // 1.0.2 白色卡片样式：系统默认白底导航栏 + 黑字大标题（旧的深色毛玻璃 + 金色渐变标题已去掉）。
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeAlways;
    // 1.0.31：大标题字缩小到 26（原来 34 号字，「SeaDragon Douyin 设置」一行放不下被截成
    // 「SeaDragon Douyi…」；大标题保留，不改标题文字）。
    self.navigationController.navigationBar.largeTitleTextAttributes = @{NSFontAttributeName : [UIFont boldSystemFontOfSize:26]};
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
            // 顾海龙抖音新增功能（1.0.35 恢复后留着的；(31) 语音包：xuu 式管理器，内置本机音色 + Fish Audio 在线音色）
            // 1.0.35：画中画装回来（皇上点名留着；系统回调至今 0 次，从没成功过）——切后台触发画中画／后台听视频，各管各的。
            [DYYYSettingItem itemWithTitle:@"后台听视频" key:GHL_KEY_BACKGROUND_LISTEN type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"切后台触发画中画" key:GHL_KEY_BACKGROUND_AUDIO type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"自动跳过开屏广告" key:GHL_KEY_NO_SPLASH_AD type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"评论图片一键存原图" key:GHL_KEY_COMMENT_IMAGE_SAVE type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"弹幕浮层（评论飘在视频上）" key:GHL_KEY_COMMENT_DANMAKU type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"侧边栏自定义排序" key:GHL_KEY_SIDEBAR_REORDER type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"侧边栏顺序（逗号分隔，从上到下）" key:GHL_KEY_SIDEBAR_ORDER type:DYYYSettingItemTypeTextField placeholder:@"如：评论,点赞,分享,收藏"],
            [DYYYSettingItem itemWithTitle:@"视频截图去水印" key:GHL_KEY_SCREENSHOT_CLEAN type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"语音包（选变音器发语音/配音）" key:GHL_KEY_VOICE_PACKAGE type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"语音包变音器（选完自动试听）" key:GHL_KEY_VOICE_PACKAGE_ID type:DYYYSettingItemTypePicker],
            // 1.0.28：长按导入至语音包（开后长按视频就能把当前作品的音频存进语音包）。
            [DYYYSettingItem itemWithTitle:@"音色库" key:GHL_KEY_IMPORT_TO_VOICE_PACKAGE type:DYYYSettingItemTypeSwitch infoText:@"启用后，长按视频点击音色库，输入你要设置的语音名称，则将当前作品的语音导入到语音包"],
            // 1.0.2 语音四项（对方 xuu 卡片上的语音功能）：1.0.28 下架转发/秒数/替换三项
            // （没做成）；保存语音评论的 AWECommentAudioModel 已确认有 audioFilePath
            // （本地文件路径），1.0.25 起开关连到长按菜单的保存代码（本地文件优先，
            // 拿不到再走 content 解析）。1.0.39：替换语音评论正式做了（录完换成语音包
            // 里选好的本地音频，开关默认关；替换音频只认我的导入里的本地文件）。
            [DYYYSettingItem itemWithTitle:@"保存语音评论（实验，需真机日志验证）" key:GHL_KEY_COMMENT_VOICE_SAVE type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"替换语音评论" key:GHL_KEY_COMMENT_VOICE_REPLACE type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"替换用语音（我的导入里的本地文件）" key:GHL_KEY_COMMENT_VOICE_REPLACE_PATH type:DYYYSettingItemTypePicker],
            [DYYYSettingItem itemWithTitle:@"双击下载当前视频（开后双击不再快进）" key:GHL_KEY_DOUBLE_TAP_DOWNLOAD type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"长按下载" key:GHL_KEY_LONG_PRESS_DOWNLOAD type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"下载进度日志+提示" key:GHL_KEY_DOWNLOAD_PROGRESS type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"Fish Audio API Key（在线变音器用）" key:GHL_KEY_FISH_AUDIO_API_KEY type:DYYYSettingItemTypeTextField placeholder:@"没有 key 就只用内置变音器"],
            // 1.0.16：抖音日志已移到关于页（本行拿掉，不是复制）。
        ],
        @[
            // 顾海龙抖音（二）：1.0.35 恢复后留着的（自动抢红包／自动开直播抽奖）
            [DYYYSettingItem itemWithTitle:@"自动抢红包" key:GHL_KEY_AUTO_RED_PACKET type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"抢红包延迟（秒）" key:GHL_KEY_RED_PACKET_DELAY type:DYYYSettingItemTypeTextField placeholder:@"默认1"],
            [DYYYSettingItem itemWithTitle:@"抢到红包自动回复" key:GHL_KEY_RED_PACKET_AUTO_REPLY type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"自动回复内容" key:GHL_KEY_RED_PACKET_REPLY_TEXT type:DYYYSettingItemTypeTextField placeholder:@"默认谢谢老板"],
            [DYYYSettingItem itemWithTitle:@"自动开直播抽奖" key:GHL_KEY_AUTO_LIVE_LOTTERY type:DYYYSettingItemTypeSwitch],
        ],
        @[
            // 1.0.8 美化：主题预设（点一套就把现有颜色类 key 一次设好）
            [DYYYSettingItem itemWithTitle:@"主题预设" key:GHL_KEY_THEME_PRESET type:DYYYSettingItemTypePicker],
            [DYYYSettingItem itemWithTitle:@"视频背景颜色" key:@"DYYYVideoBGColor" type:DYYYSettingItemTypeTextField],
            [DYYYSettingItem itemWithTitle:@"启用弹幕改色" key:@"DYYYEnableDanmuColor" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"自定弹幕颜色" key:@"DYYYDanmuColor" type:DYYYSettingItemTypeTextField],
            [DYYYSettingItem itemWithTitle:@"设置默认倍速" key:@"DYYYDefaultSpeed" type:DYYYSettingItemTypePicker],
            [DYYYSettingItem itemWithTitle:@"设置长按倍速" key:@"DYYYLongPressSpeed" type:DYYYSettingItemTypePicker],
            [DYYYSettingItem itemWithTitle:@"上下控制倍速" key:@"DYYYEnableLongPressSpeedGesture" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"显示进度时长" key:@"DYYYShowScheduleDisplay" type:DYYYSettingItemTypeSwitch],
            // 1.0.37：长按面板作品日期显示（默认开；createTime 为 0/缺失时那行不显示）。
            [DYYYSettingItem itemWithTitle:@"作品日期显示" key:@"DYYYShowWorkDate" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"显示详细互动数" key:@"DYYYShowExactInteractionCounts" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"查看评论暂停播放" key:@"DYYYCommentPausePlayback" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"进度时长样式" key:@"DYYYScheduleStyle" type:DYYYSettingItemTypeTextField placeholder:@"默认"],
            [DYYYSettingItem itemWithTitle:@"进度纵轴位置" key:@"DYYYTimelineVerticalPosition" type:DYYYSettingItemTypeTextField placeholder:@"-12.5"],
            [DYYYSettingItem itemWithTitle:@"进度标签颜色" key:@"DYYYProgressLabelColor" type:DYYYSettingItemTypeTextField],
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
            [DYYYSettingItem itemWithTitle:@"时间标签颜色" key:@"DYYYLabelColor" type:DYYYSettingItemTypeTextField],
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
            [DYYYSettingItem itemWithTitle:@"修改底栏高度" key:@"DYYYTabBarHeight" type:DYYYSettingItemTypeTextField placeholder:@"20-150，默认为空"],
            [DYYYSettingItem itemWithTitle:@"设置首页标题" key:@"DYYYIndexTitle" type:DYYYSettingItemTypeTextField placeholder:@"不填默认"],
            [DYYYSettingItem itemWithTitle:@"设置朋友标题" key:@"DYYYFriendsTitle" type:DYYYSettingItemTypeTextField placeholder:@"不填默认"],
            [DYYYSettingItem itemWithTitle:@"设置消息标题" key:@"DYYYMsgTitle" type:DYYYSettingItemTypeTextField placeholder:@"不填默认"],
            [DYYYSettingItem itemWithTitle:@"设置我的标题" key:@"DYYYSelfTitle" type:DYYYSettingItemTypeTextField placeholder:@"不填默认"],
            // 1.0.31：头卡自定义名称（和点名字改是同一把 key，留空恢复默认 SeaDragon Douyin）。
            [DYYYSettingItem itemWithTitle:@"自定义名称" key:GHL_KEY_CUSTOM_DISPLAY_NAME type:DYYYSettingItemTypeTextField placeholder:@"默认 SeaDragon Douyin"],
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
            [DYYYSettingItem itemWithTitle:@"长按面板网格风格（龙头）" key:GHL_KEY_LONG_PRESS_GRID_PANEL type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"长按面板头像" key:GHL_KEY_GRID_PANEL_AVATAR type:DYYYSettingItemTypePicker],
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
            // 1.0.23 第二批：快捷面板外观（只用在长按网格面板表面，不动设置卡片）——
            // 51 背景图、53 材质三选一。
            [DYYYSettingItem itemWithTitle:@"快捷面板背景图片" key:GHL_KEY_QUICK_PANEL_BG type:DYYYSettingItemTypePicker],
            [DYYYSettingItem itemWithTitle:@"恢复面板默认背景" key:GHL_KEY_QUICK_PANEL_BG_CLEAR type:DYYYSettingItemTypePicker],
            [DYYYSettingItem itemWithTitle:@"面板材质" key:GHL_KEY_QUICK_PANEL_MATERIAL type:DYYYSettingItemTypePicker],
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
            // 1.0.43 C17：按 v3.0 补回自动勾选原图行（功能本身已有，见 DYYY.xm）。
            [DYYYSettingItem itemWithTitle:@"启用自动勾选原图" key:@"DYYYAutoSelectOriginalPhoto" type:DYYYSettingItemTypeSwitch],
            // 1.0.24：按位置双击（左半边直接保存，右半边弹菜单）；弹窗精简（只留下载相关）。
            [DYYYSettingItem itemWithTitle:@"按位置双击（左存右弹）" key:GHL_KEY_DOUBLE_TAP_POSITION type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"双击弹窗精简（只留下载）" key:GHL_KEY_DOUBLE_TAP_POPUP_COMPACT type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"资料默认进入作品" key:@"DYYYDefaultEnterWorks" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"禁用自动进入直播" key:@"DYYYDisableAutoEnterLive" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"左侧边栏快捷入口" key:@"DYYYEntrance" type:DYYYSettingItemTypeSwitch],
            // 1.0.24：默认接皇上给的原画质接口（行上显示默认地址，可改可清空）。
            // 1.0.43 C17：按 v3.0 补回接口解析行（功能本身已有，见 DYYYManager/DYYY.xm）。
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
            // 1.0.43 C17：按 v3.0 补回长按评论复制行（功能本身已有，见 DYYY.xm）。
            [DYYYSettingItem itemWithTitle:@"长按评论复制评论" key:@"DYYYCommentCopyText" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"长按简介复制简介" key:@"DYYYBioCopyText" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"长按文案复制文案" key:@"DYYYLongPressCopyTextEnabled" type:DYYYSettingItemTypeSwitch],
            [DYYYSettingItem itemWithTitle:@"下载完成震动反馈" key:@"DYYYHapticFeedbackEnabled" type:DYYYSettingItemTypeSwitch]
        ],
        @[
            [DYYYSettingItem itemWithTitle:@"启用快捷倍速按钮" key:@"DYYYEnableFloatSpeedButton" type:DYYYSettingItemTypeSwitch],
            // 1.0.43 C4：自动隐藏两行已删（v3.0 模型无贴边自动隐藏，开关无人读）。
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
            [DYYYSettingItem itemWithTitle:@"清屏隐藏倍速按钮" key:@"DYYYHideSpeed" type:DYYYSettingItemTypeSwitch],
            // 1.0.4 悬浮按钮自定义：每个按钮点一下/长按各选一个动作
            [DYYYSettingItem itemWithTitle:@"倍速按钮点一下" key:GHL_KEY_SPEED_BUTTON_TAP type:DYYYSettingItemTypePicker],
            [DYYYSettingItem itemWithTitle:@"倍速按钮长按" key:GHL_KEY_SPEED_BUTTON_LONGPRESS type:DYYYSettingItemTypePicker],
            [DYYYSettingItem itemWithTitle:@"清屏按钮点一下" key:GHL_KEY_CLEAR_BUTTON_TAP type:DYYYSettingItemTypePicker],
            [DYYYSettingItem itemWithTitle:@"清屏按钮长按" key:GHL_KEY_CLEAR_BUTTON_LONGPRESS type:DYYYSettingItemTypePicker]
        ],
        @[
            // 1.0.14 关于分区：只剩单一入口行「关于顾海龙抖音」，点整行直接进深色品牌页
            // （右边的「查看关于」附属文字已拿掉，只留右箭头；1.0.12 的关于弹窗、声明行和
            // 配置三行废弃：配置三行搬进关于页的配置管理区，逻辑不动）。
            // 1.0.15：主页点「关于」分类行时不再进这个子页（didSelectRowAtIndexPath 里
            // 直接 push GHLAboutViewController），这个分区只剩搜索结果的兜底入口。
            [DYYYSettingItem itemWithTitle:@"关于 SeaDragon Douyin" key:GHL_KEY_ABOUT_PAGE type:DYYYSettingItemTypePicker]
        ]
    ];
}

- (void)setupSectionTitles {
    self.sectionTitles = [@[ @"常用功能", @"自动功能", @"基本设置", @"界面设置", @"隐藏设置", @"顶栏移除", @"隐藏面板", @"面板设置", @"功能设置", @"悬浮按钮", @"关于" ] mutableCopy];
}

// 1.0.2 白色卡片主页头：龙头 logo 招牌 + 名字 + 版本 + 统计，
// 下面是搜索框（样式照 xuu 卡片的搜索框）。
- (void)setupHeaderCardAndSearch {
    CGFloat width = self.view.bounds.size.width;
    UIView *header = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, 172)];
    header.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    // 头卡：毛玻璃（1.0.5）：系统材质模糊，背景图从卡片里透出来、是糊的；
    // 圆角 16、金边保留；没有自定义背景时糊在白底上，看起来跟原来差不多。
    // 外层容器扛阴影（毛玻璃自己 masksToBounds 会把阴影裁掉）。
    UIView *cardContainer = [[UIView alloc] initWithFrame:CGRectMake(16, 12, width - 32, 96)];
    cardContainer.backgroundColor = [UIColor clearColor];
    cardContainer.layer.cornerRadius = [DYYYUtils dYYYSettingsCardCornerRadius];
    cardContainer.layer.shadowColor = [UIColor blackColor].CGColor;
    cardContainer.layer.shadowOpacity = 0.08;
    cardContainer.layer.shadowOffset = CGSizeMake(0, 2);
    cardContainer.layer.shadowRadius = 8;
    cardContainer.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [header addSubview:cardContainer];

    UIVisualEffectView *card = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial]];
    card.frame = cardContainer.bounds;
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    card.layer.cornerRadius = [DYYYUtils dYYYSettingsCardCornerRadius];
    card.layer.masksToBounds = YES;
    card.layer.borderWidth = 0.5;
    card.layer.borderColor = [[DYYYUtils dYYYGoldAccentColor] colorWithAlphaComponent:0.35].CGColor;
    [cardContainer addSubview:card];

    // 淡色 tint：背景图太花时也保证对比度（浅色白、深色黑，动态色自动跟深浅）。
    UIView *tintView = [[UIView alloc] initWithFrame:card.bounds];
    tintView.backgroundColor = [DYYYUtils dYYYSettingsHeaderCardTintColor];
    tintView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [card.contentView addSubview:tintView];

    // 招牌：我们自己的龙头 logo，64pt 圆形 + 金边（一眼认出是顾海龙抖音）
    // 1.0.4：点一下换图（相册选图），长按恢复默认龙头。
    UIImageView *logoView = [[UIImageView alloc] initWithFrame:CGRectMake(16, 16, 64, 64)];
    logoView.image = GHLLogoImage();
    logoView.layer.cornerRadius = 32;
    logoView.layer.masksToBounds = YES;
    logoView.layer.borderWidth = 1.5;
    logoView.layer.borderColor = [UIColor colorWithRed:212 / 255.0 green:175 / 255.0 blue:55 / 255.0 alpha:1.0].CGColor;
    logoView.contentMode = UIViewContentModeScaleAspectFill;
    logoView.userInteractionEnabled = YES;
    [card.contentView addSubview:logoView];
    self.logoImageView = logoView;

    CGFloat textX = 92;
    CGFloat textW = card.bounds.size.width - textX - 16;
    UILabel *nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(textX, 14, textW, 24)];
    nameLabel.text = [self ghlDisplayName];
    nameLabel.font = [UIFont boldSystemFontOfSize:20];
    nameLabel.textColor = [DYYYUtils dYYYSettingsHeaderTitleColor];
    nameLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    // 1.0.31：名字太长自动缩字不截断；点一下改自定义显示名。
    nameLabel.adjustsFontSizeToFitWidth = YES;
    nameLabel.minimumScaleFactor = 0.7;
    nameLabel.userInteractionEnabled = YES;
    [nameLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(ghlNameLabelTapped)]];
    [card.contentView addSubview:nameLabel];
    self.nameLabel = nameLabel;

    UILabel *versionLabel = [[UILabel alloc] initWithFrame:CGRectMake(textX, 40, textW, 18)];
    versionLabel.text = [NSString stringWithFormat:@"Version: %@", DYYY_VERSION];
    versionLabel.font = [UIFont systemFontOfSize:13];
    versionLabel.textColor = [DYYYUtils dYYYSettingsHeaderSubtitleColor];
    versionLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [card.contentView addSubview:versionLabel];

    self.statsLabel = [[UILabel alloc] initWithFrame:CGRectMake(textX, 60, textW, 18)];
    self.statsLabel.font = [UIFont systemFontOfSize:13];
    self.statsLabel.textColor = [DYYYUtils dYYYSettingsHeaderSubtitleColor];
    self.statsLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [card.contentView addSubview:self.statsLabel];

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

// 1.0.31：头卡显示名——自定义名称（GHL_KEY_CUSTOM_DISPLAY_NAME）没填/留空就显示默认名。
- (NSString *)ghlDisplayName {
    NSString *customName = GHLGetString(GHL_KEY_CUSTOM_DISPLAY_NAME);
    if (customName.length > 0) return customName;
    return DYYY_NAME;
}

// 1.0.31：刷新头卡名字（头卡不在本页时 self.nameLabel 为空，直接跳过）。
- (void)ghlRefreshHeaderName {
    if (!self.nameLabel) return;
    self.nameLabel.text = [self ghlDisplayName];
}

// 1.0.31：点头卡名字改自定义显示名（留空恢复默认）。
- (void)ghlNameLabelTapped {
    NSString *currentCustomName = GHLGetString(GHL_KEY_CUSTOM_DISPLAY_NAME) ?: @"";
    DYYYCustomInputView *inputView = [[DYYYCustomInputView alloc] initWithTitle:@"自定义名称" defaultText:currentCustomName placeholder:@"默认 SeaDragon Douyin"];
    __weak typeof(self) weakSelf = self;
    inputView.onConfirm = ^(NSString *text) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *name = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        if (name.length == 0) {
            [defaults removeObjectForKey:GHL_KEY_CUSTOM_DISPLAY_NAME];
            [DYYYUtils showToast:@"已恢复默认名字"];
        } else {
            [defaults setObject:name forKey:GHL_KEY_CUSTOM_DISPLAY_NAME];
            [DYYYUtils showToast:@"名字已保存"];
        }
        [strongSelf ghlRefreshHeaderName];
    };
    inputView.onCancel = ^{};
    [inputView show];
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

#pragma mark - Helper Methods

- (NSArray *)optionsForKey:(NSString *)key {
    if ([key isEqualToString:@"DYYYDefaultSpeed"] || [key isEqualToString:@"DYYYLongPressSpeed"]) {
        // 倍速选项
        return @[ @0.75, @1.0, @1.25, @1.5, @2.0, @2.5, @3.0 ];
    } else if ([key isEqualToString:GHL_KEY_VOICE_PACKAGE_ID]) {
        // 1.0.28：语音包音色行不再弹 Picker（点开直接进语音包页），这里不再给选项。
        return @[];
    } else if ([key isEqualToString:GHL_KEY_GRID_PANEL_AVATAR]) {
        // 1.0.11 长按面板头像：从相册选图换头像，或恢复默认龙头
        return @[ @"从相册选图", @"恢复默认龙头" ];
    } else if ([key isEqualToString:GHL_KEY_ABOUT_PAGE]) {
        // 1.0.14：关于入口行直接进关于页，不弹选择框，没有候选项。
        return @[];
    } else if ([key isEqualToString:@"DYYYLiveQuality"]) {
    } else if ([key isEqualToString:GHL_KEY_THEME_PRESET]) {
        // 1.0.8 主题预设：点一套就把现有颜色类 key 一次设好
        return @[ @"无", @"金龙", @"冰蓝", @"樱粉", @"暗夜" ];
    } else if ([key isEqualToString:GHL_KEY_SPEED_BUTTON_TAP] || [key isEqualToString:GHL_KEY_SPEED_BUTTON_LONGPRESS] ||
               [key isEqualToString:GHL_KEY_CLEAR_BUTTON_TAP] || [key isEqualToString:GHL_KEY_CLEAR_BUTTON_LONGPRESS]) {
        // 1.0.4 悬浮按钮自定义：动作候选只给已经存在的功能
        return @[ GHL_FLOAT_ACTION_DEFAULT, GHL_FLOAT_ACTION_DOWNLOAD, GHL_FLOAT_ACTION_CLEAR, GHL_FLOAT_ACTION_SPEED, GHL_FLOAT_ACTION_DANMAKU, GHL_FLOAT_ACTION_SCREENSHOT ];
    } else if ([key isEqualToString:GHL_KEY_QUICK_PANEL_BG]) {
        // 1.0.23 第二批：51 快捷面板背景图片（相册选图）
        return @[ @"从相册选图" ];
    } else if ([key isEqualToString:GHL_KEY_QUICK_PANEL_BG_CLEAR]) {
        // 1.0.23 第二批：51 恢复面板默认背景
        return @[ @"恢复默认背景" ];
    } else if ([key isEqualToString:GHL_KEY_QUICK_PANEL_MATERIAL]) {
        // 1.0.23 第二批：53 面板材质三选一
        return @[ @"磨砂", @"液态玻璃", @"清透玻璃" ];
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
    } else if ([key isEqualToString:GHL_KEY_VOICE_PACKAGE_ID]) {
        return GHLVoicePackageDisplayNameForID(value) ?: @"未选择";
    } else if ([key isEqualToString:GHL_KEY_COMMENT_VOICE_REPLACE_PATH]) {
        // 1.0.39：替换用音频行显示选好的音频名，没选过显示未选择。
        NSString *name = [[NSUserDefaults standardUserDefaults] stringForKey:GHL_KEY_COMMENT_VOICE_REPLACE_NAME];
        return name.length > 0 ? name : @"未选择";
    } else if ([key isEqualToString:GHL_KEY_GRID_PANEL_AVATAR]) {
        // 1.0.11：选单里的两个动作原样显示；没选过动作时行上显示当前头像状态
        if ([value isKindOfClass:[NSString class]] && ([value isEqualToString:@"从相册选图"] || [value isEqualToString:@"恢复默认龙头"])) return value;
        return GHLHasCustomLogo() ? @"已换自选图" : @"默认龙头";
    } else if ([key isEqualToString:GHL_KEY_ABOUT_PAGE]) {
        // 1.0.14：关于入口行不显示附属值。
        return @"";
    } else if ([key isEqualToString:@"DYYYLiveQuality"]) {
    } else if ([key isEqualToString:GHL_KEY_THEME_PRESET]) {
        // 1.0.8 主题预设：没选过就是无
        return value ?: @"无";
    } else if ([key isEqualToString:GHL_KEY_SPEED_BUTTON_TAP] || [key isEqualToString:GHL_KEY_SPEED_BUTTON_LONGPRESS] ||
               [key isEqualToString:GHL_KEY_CLEAR_BUTTON_TAP] || [key isEqualToString:GHL_KEY_CLEAR_BUTTON_LONGPRESS]) {
        // 悬浮按钮动作：没配过就是默认
        return value ?: GHL_FLOAT_ACTION_DEFAULT;
    } else if ([key isEqualToString:GHL_KEY_QUICK_PANEL_BG]) {
        // 1.0.23 第二批：51 换过自选图就显示状态，没换过就显示动作
        if ([value isKindOfClass:[NSString class]] && [(NSString *)value isEqualToString:@"从相册选图"]) {
            return GHLHasCustomQuickPanelBackground() ? @"已换自选图" : @"从相册选图";
        }
        return GHLHasCustomQuickPanelBackground() ? @"已换自选图" : @"从相册选图";
    } else if ([key isEqualToString:GHL_KEY_QUICK_PANEL_BG_CLEAR]) {
        return @"恢复默认背景";
    } else if ([key isEqualToString:GHL_KEY_QUICK_PANEL_MATERIAL]) {
        return value ?: @"磨砂";
    } else if ([key isEqualToString:@"DYYYLiveQuality"]) {
    } else if ([key isEqualToString:@"DYYYHDRMode"]) {
        return value ?: @"关闭";
    }
    return [NSString stringWithFormat:@"%@", value];
}

- (id)defaultValueForKey:(NSString *)key {
    if ([key isEqualToString:@"DYYYDefaultSpeed"] || [key isEqualToString:@"DYYYLongPressSpeed"]) {
        return @1.0;
    } else if ([key isEqualToString:GHL_KEY_VOICE_PACKAGE_ID]) {
        return GHLVoicePackageIDs().firstObject ?: @"sys:default-zh-CN";
    } else if ([key isEqualToString:GHL_KEY_COMMENT_VOICE_REPLACE_PATH]) {
        return @"未选择";
    } else if ([key isEqualToString:GHL_KEY_GRID_PANEL_AVATAR]) {
        return @"默认龙头";
    } else if ([key isEqualToString:GHL_KEY_ABOUT_PAGE]) {
        // 1.0.14：关于入口行没有默认值（值无意义，直接进关于页）。
        return nil;
    } else if ([key isEqualToString:@"DYYYLiveQuality"]) {
    } else if ([key isEqualToString:GHL_KEY_THEME_PRESET]) {
        return @"无";
    } else if ([key isEqualToString:GHL_KEY_SPEED_BUTTON_TAP] || [key isEqualToString:GHL_KEY_SPEED_BUTTON_LONGPRESS] ||
               [key isEqualToString:GHL_KEY_CLEAR_BUTTON_TAP] || [key isEqualToString:GHL_KEY_CLEAR_BUTTON_LONGPRESS]) {
        return GHL_FLOAT_ACTION_DEFAULT;
    } else if ([key isEqualToString:GHL_KEY_QUICK_PANEL_BG]) {
        return @"从相册选图";
    } else if ([key isEqualToString:GHL_KEY_QUICK_PANEL_BG_CLEAR]) {
        return @"恢复默认背景";
    } else if ([key isEqualToString:GHL_KEY_QUICK_PANEL_MATERIAL]) {
        return @"磨砂";
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
            cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        }
        // 1.0.4 统一视觉：颜色跟随深色/自定义背景（每次配行时都算，别只在创建时设一次）。
        // 1.0.21：卡片内用半透明白（ghlDarkModeActive 在卡片内已返回 NO，字是深色）。
        BOOL dark = [self ghlDarkModeActive];
        cell.backgroundColor = self.ghlInFloatPanel ? [DYYYUtils dYYYSettingsCellBackgroundColorForFloatPanel] : [DYYYUtils dYYYSettingsCellBackgroundColorForBackgroundImage:self.backgroundImage darkMode:dark];
        cell.textLabel.textColor = [DYYYUtils dYYYSettingsPrimaryTextColorDarkMode:dark];
        cell.detailTextLabel.textColor = [DYYYUtils dYYYSettingsSecondaryTextColorDarkMode:dark];
        if (!cell.selectedBackgroundView) cell.selectedBackgroundView = [[UIView alloc] init];
        cell.selectedBackgroundView.backgroundColor = dark ? [UIColor colorWithWhite:1 alpha:0.12] : [UIColor colorWithWhite:0.9 alpha:1.0];
        cell.textLabel.text = self.sectionTitles[indexPath.row];
        cell.detailTextLabel.text = [NSString stringWithFormat:@"%ld", (long)self.settingSections[indexPath.row].count];
        return cell;
    }
    return [self itemCellForIndexPath:indexPath tableView:tableView];
}

// 选择器行的右端附属值（当前值文字，右对齐 13pt；关于入口行不走这里）。
- (void)ghlConfigurePickerAccessoryForCell:(UITableViewCell *)cell item:(DYYYSettingItem *)item dark:(BOOL)dark tag:(NSInteger)tag {
    UILabel *pickerLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 140, 44)];
    // 获取当前值
    id currentValue = [[NSUserDefaults standardUserDefaults] objectForKey:item.key];
    if (!currentValue) {
        currentValue = [self defaultValueForKey:item.key];
    }

    pickerLabel.text = [self displayValueForKey:item.key value:currentValue];
    pickerLabel.font = [UIFont systemFontOfSize:13];
    pickerLabel.textColor = [DYYYUtils dYYYSettingsPrimaryTextColorDarkMode:dark];
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
            cell.detailTextLabel.numberOfLines = 2;

            UIView *selectedBackgroundView = [[UIView alloc] init];
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
            cell.selectedBackgroundView = selectedBackgroundView;
        }
        cell.textLabel.text = item.title;
    }

    // 1.0.4 统一视觉：颜色跟随深色/自定义背景（每次配行时都算，别只在创建时设一次）。
    // 1.0.21：卡片内用半透明白（ghlDarkModeActive 在卡片内已返回 NO，字是深色）。
    BOOL dark = [self ghlDarkModeActive];
    cell.textLabel.textColor = [DYYYUtils dYYYSettingsPrimaryTextColorDarkMode:dark];
    cell.detailTextLabel.textColor = [DYYYUtils dYYYSettingsSecondaryTextColorDarkMode:dark];
    cell.backgroundColor = self.ghlInFloatPanel ? [DYYYUtils dYYYSettingsCellBackgroundColorForFloatPanel] : [DYYYUtils dYYYSettingsCellBackgroundColorForBackgroundImage:self.backgroundImage darkMode:dark];
    cell.selectedBackgroundView.backgroundColor = dark ? [UIColor colorWithWhite:1 alpha:0.12] : [UIColor colorWithWhite:0.9 alpha:1.0];

    if (item.type == DYYYSettingItemTypeSwitch) {
        UISwitch *switchView = [[UISwitch alloc] init];
        [switchView setOn:[[NSUserDefaults standardUserDefaults] boolForKey:item.key]];
        // 1.0.4 统一视觉：开关统一用龙头金 accent。
        switchView.onTintColor = [DYYYUtils dYYYGoldAccentColor];
        [switchView addTarget:self action:@selector(switchToggled:) forControlEvents:UIControlEventValueChanged];
        switchView.tag = tag;
        if (item.infoText.length > 0) {
            // 1.0.28：带 (i) 提示的开关行——开关左边并排一个 ⓘ 按钮，点它弹提示文案。
            UIView *container = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 90, 44)];
            UIButton *infoButton = [UIButton buttonWithType:UIButtonTypeSystem];
            infoButton.frame = CGRectMake(0, 8, 28, 28);
            [infoButton setTitle:@"ⓘ" forState:UIControlStateNormal];
            infoButton.titleLabel.font = [UIFont systemFontOfSize:20];
            [infoButton setTitleColor:[DYYYUtils dYYYGoldAccentColor] forState:UIControlStateNormal];
            infoButton.tag = tag;
            [infoButton addTarget:self action:@selector(ghlInfoButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
            [container addSubview:infoButton];
            switchView.frame = CGRectMake(36, 6.5, 51, 31);
            [container addSubview:switchView];
            cell.accessoryView = container;
        } else {
            cell.accessoryView = switchView;
        }
    } else if (item.type == DYYYSettingItemTypeTextField) {
        UITextField *textField = [[UITextField alloc] initWithFrame:CGRectMake(0, 0, 120, 30)];
        textField.borderStyle = UITextBorderStyleRoundedRect;
        textField.font = [UIFont systemFontOfSize:14];
        textField.placeholder = item.placeholder;
        textField.attributedPlaceholder = [[NSAttributedString alloc] initWithString:item.placeholder attributes:@{NSForegroundColorAttributeName : [DYYYUtils dYYYSettingsSecondaryTextColorDarkMode:dark]}];
        textField.text = [[NSUserDefaults standardUserDefaults] objectForKey:item.key];
        textField.textAlignment = NSTextAlignmentRight;
        textField.backgroundColor = dark ? [UIColor colorWithWhite:1 alpha:0.08] : [UIColor colorWithWhite:0.94 alpha:1.0];
        textField.textColor = [DYYYUtils dYYYSettingsPrimaryTextColorDarkMode:dark];

        [textField addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingDidEnd];
        textField.tag = tag;
        cell.accessoryView = textField;
    } else if (item.type == DYYYSettingItemTypePicker) {
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;

        // 1.0.14：关于入口行不要右边的「查看关于」附属文字，整行可点直接进关于页
        // （点行在 didSelectRowAtIndexPath 里直接 push GHLAboutViewController，不弹选择框）；
        // 只留标准右箭头。复用的 cell 要把旧 accessoryView 清掉，不然会留着别行的附属控件。
        if ([item.key isEqualToString:GHL_KEY_ABOUT_PAGE]) {
            cell.accessoryView = nil;
        } else {
            [self ghlConfigurePickerAccessoryForCell:cell item:item dark:dark tag:tag];
        }
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
        // 1.0.15：关于分类行直接进深色品牌页，不再进「关于」子页中转——
        // 子页里只有一行「关于顾海龙抖音」，多一层没有意义（皇上 20:02–20:05
        // 明确不要这个页面：「我不要点关于，又要点关于顾海龙抖音」）。
        // 判断不写死下标：关于分区就是那个只有一行、且那行 key 是 GHL_KEY_ABOUT_PAGE 的分区。
        if (indexPath.row < (NSInteger)self.settingSections.count) {
            NSArray<DYYYSettingItem *> *sectionItems = self.settingSections[indexPath.row];
            if (sectionItems.count == 1 && [sectionItems[0].key isEqualToString:GHL_KEY_ABOUT_PAGE]) {
                GHLAboutViewController *aboutVC = [[GHLAboutViewController alloc] init];
                // 1.0.24：卡片内推关于页也带上卡片标记，页底透明、卡半透明白，共用卡片底图。
                aboutVC.ghlInFloatPanel = self.ghlInFloatPanel;
                [self.navigationController pushViewController:aboutVC animated:YES];
                [tableView deselectRowAtIndexPath:indexPath animated:YES];
                return;
            }
        }
        DYYYSettingViewController *subVC = [[DYYYSettingViewController alloc] initWithSectionIndex:indexPath.row];
        // 1.0.24：子页继承卡片标记（以前没传，子页按全屏走、自己又铺一张图；
        // 现在卡片底图只有一张，子页页底透明共用它，行半透明白）。
        subVC.ghlInFloatPanel = self.ghlInFloatPanel;
        [self.navigationController pushViewController:subVC animated:YES];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }
    DYYYSettingItem *item = [self itemForIndexPath:indexPath];
    // 1.0.14：关于入口行直接推进深色品牌页，不弹选择框（主页分类行和搜索结果都走这里）。
    // 1.0.15：主页分类行已在上面直接拦截，这里只剩搜索结果的兜底入口。
    if ([item.key isEqualToString:GHL_KEY_ABOUT_PAGE]) {
        GHLAboutViewController *aboutVC = [[GHLAboutViewController alloc] init];
        // 1.0.24：卡片内推关于页也带上卡片标记（同上）。
        aboutVC.ghlInFloatPanel = self.ghlInFloatPanel;
        [self.navigationController pushViewController:aboutVC animated:YES];
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }
    // 1.0.39：替换用音频行点开进语音包挑选页（只挑我的导入里的本地音频）。
    if ([item.key isEqualToString:GHL_KEY_COMMENT_VOICE_REPLACE_PATH]) {
        GHLPresentReplaceAudioPickerFromViewController(self);
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }
    // 1.0.28：语音包音色行点开直接进极简语音包页，不再弹系统 Picker（试听在页里点行就有）。
    if ([item.key isEqualToString:GHL_KEY_VOICE_PACKAGE_ID]) {
        GHLPresentSimpleVoicePackagePageFromViewController(self);
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
        return;
    }
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
                                                         if ([item.key isEqualToString:GHL_KEY_GRID_PANEL_AVATAR]) {
                                                             // 1.0.11 长按面板头像：从相册选图（复用换龙头 picker，kind 0）或恢复默认龙头；
                                                             // 换完头卡 logo 已刷新（picker 回调 / ghlRestoreDefaultLogo），网格下次长按直接读 GHLLogoImage()，不用重启抖音
                                                             if ([(NSString *)option isEqualToString:@"恢复默认龙头"]) {
                                                                 [self ghlRestoreDefaultLogo];
                                                             } else {
                                                                 [self ghlPresentImagePickerForKind:0];
                                                             }
                                                         } else if ([item.key isEqualToString:GHL_KEY_QUICK_PANEL_BG]) {
                                                             // 1.0.23 第二批：51 快捷面板背景图片（相册选图，kind 2）
                                                             [self ghlPresentImagePickerForKind:2];
                                                         } else if ([item.key isEqualToString:GHL_KEY_QUICK_PANEL_BG_CLEAR]) {
                                                             // 1.0.23 第二批：51 恢复面板默认背景
                                                             GHLClearCustomQuickPanelBackground();
                                                             [DYYYUtils showToast:@"已恢复面板默认背景"];
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

                                                         // 1.0.8 主题预设：一次改了好几个颜色 key，整表刷新让各颜色行显示新 hex。
                                                         if ([item.key isEqualToString:GHL_KEY_THEME_PRESET]) {
                                                             GHLApplyThemePreset((NSString *)option);
                                                             [self.tableView reloadData];
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

// 1.0.28：带 (i) 提示的开关行——点 ⓘ 弹提示文案（不改开关状态）。
- (void)ghlInfoButtonTapped:(UIButton *)sender {
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:sender.tag % 1000 inSection:sender.tag / 1000];
    DYYYSettingItem *item = self.settingSections[indexPath.section][indexPath.row];
    if (!item.infoText.length) return;
    [DYYYBottomAlertView showAlertWithTitle:item.title
                                    message:item.infoText
                                  avatarURL:nil
                           cancelButtonText:@"知道了"
                          confirmButtonText:nil
                               cancelAction:nil
                                closeAction:nil
                              confirmAction:nil];
}

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
    if ([item.key isEqualToString:GHL_KEY_COMMENT_IMAGE_SAVE]) {
        [defaults setBool:sender.isOn forKey:@"DYYYForceDownloadCommentImage"];
    } else if ([item.key isEqualToString:GHL_KEY_COMMENT_DANMAKU]) {
        [defaults setBool:sender.isOn forKey:@"DYYYCommentShowDanmaku"];
    } else if ([item.key isEqualToString:GHL_KEY_VOICE_PACKAGE]) {
        if (sender.isOn) GHLProbeLiveVoiceSender();
    } else if ([item.key isEqualToString:GHL_KEY_BACKGROUND_LISTEN]) {
        // 1.0.20：后台听视频开关才写 DYYYEnableBackgroundListen 镜像
        // （setListenVideoStatus 的改写跟它走；上游「基本设置」里也有同一 key 的行）。
        [defaults setBool:sender.isOn forKey:@"DYYYEnableBackgroundListen"];
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
    // 1.0.31：自定义名称改了就刷新头卡名字（子页里改时头卡不在本页，刷新是空操作，
    // 回主页时 viewWillAppear 再刷一次）。
    if ([item.key isEqualToString:GHL_KEY_CUSTOM_DISPLAY_NAME]) {
        [self ghlRefreshHeaderName];
    }
    // 顾海龙抖音：输入值同步到上游键
    if ([item.key isEqualToString:@"DYYYSpeedSettings"] || [item.key isEqualToString:@"DYYYSpeedButtonSize"]) {
        [FloatingSpeedButton reloadConfiguration];
    }
    if ([item.key isEqualToString:@"DYYYEnableFloatClearButtonSize"]) {
        reloadClearButtonConfiguration();
    }
}

// 导入配置：系统文件选择器选 .plist。

// 导出配置：写成“顾海龙抖音配置.plist”，用系统分享调出来（存到“文件”或发给别人）。

// 恢复默认配置：先弹确认框（全部设置项、自选龙头、自定义背景都会恢复默认，不能撤销），点了确认才执行。

#pragma mark - 1.0.4 换龙头 / 换背景图

// 点头卡 logo：打开相册选图换龙头。

// 长按头卡 logo：确认后恢复默认龙头。

- (void)ghlRestoreDefaultLogo {
    GHLClearCustomLogo();
    self.logoImageView.image = GHLLogoImage();
    [DYYYUtils showToast:@"已恢复默认龙头"];
}

// 相册选图（kind 0 = 换龙头，2 = 快捷面板背景图）。拒绝了相册权限就提示，不硬打开。
- (void)ghlPresentImagePickerForKind:(NSInteger)kind {
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    if (status == PHAuthorizationStatusDenied || status == PHAuthorizationStatusRestricted) {
        [DYYYUtils showToast:@"需要相册权限才能换图"];
        return;
    }
    self.pendingImagePickerKind = kind;
    self.imagePickerDelegate = [[DYYYImagePickerDelegate alloc] init];
    __weak typeof(self) weakSelf = self;
    self.imagePickerDelegate.completionBlock = ^(NSDictionary *info) {
      __strong typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) return;
      UIImage *image = info[UIImagePickerControllerOriginalImage];
      if (!image) {
          [DYYYUtils showToast:@"选图失败"];
          return;
      }
      // 存图放后台线程，别卡界面；存完回主线程刷新。
      NSInteger pickedKind = strongSelf.pendingImagePickerKind;
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL ok = NO;
        if (pickedKind == 0) {
            ok = GHLSaveCustomLogoImage(image);
        } else if (pickedKind == 2) {
            // 1.0.23 第二批：51 快捷面板背景图
            ok = GHLSaveCustomQuickPanelBackgroundImage(image);
        }
        GHLRunOnMain(^{
          if (!ok) {
              [DYYYUtils showToast:@"保存失败，换图没成功"];
              return;
          }
          if (pickedKind == 0) {
              strongSelf.logoImageView.image = GHLLogoImage();
              [DYYYUtils showToast:@"龙头已更换"];
          } else if (pickedKind == 2) {
              [DYYYUtils showToast:@"面板背景图已更换，下次长按就生效"];
          }
        });
      });
    };
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self.imagePickerDelegate;
    [self presentViewController:picker animated:YES completion:nil];
}

@end
