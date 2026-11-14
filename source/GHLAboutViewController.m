// GHLAboutViewController — 关于浅色玻璃页（1.0.13 方案四；1.0.21 深色改浅色，
// 和卡片首页／长按面板同款 iOS 文件夹式浅色玻璃：半透明白卡、深色字、金色点缀）
// 1.0.14：标题/版本行按横幅里龙头中心对齐；QQ 行标签改成「QQ：QQ群交流：」+ 号码；
// 原作者行改成「原作者（huami）」，下面加一行只展示的「现作者（顾海龙总监）」。
// 1.0.15：横幅换成展翅绿龙（雷雨海面＋红眼睛，标题按重测的龙头中心 x=358 对齐）；
// 关于页加「更换横幅背景」（相册选图，存 Documents/DYYY/ghl-about-banner.jpg）和
// 「恢复默认横幅」（删自选图回内置展翅龙；自选图时标题按横幅中心对齐）。
// 1.0.21：深色改浅色——页底/卡底改半透明白、字改深色、显式浅色不跟随系统；
// 1.0.22：页底/卡底改不透明——半透明让首页按键从下面透上来（录屏实锤），玻璃感只留给
// 卡片外壳和首页；导航栏也不透明了（GHLFeatures.xm 里改），顶部内容不再被导航栏盖住；
// 对齐：行图标/文字/箭头/转圈共用同一套常量（转圈中心＝箭头中心，长标题太长时自动缩字不截断，
// 分隔线左端＝文字左端、右端＝卡片右内边）；横幅标题/版本行仍按龙头中心对齐（1.0.14/1.0.15 实测值不动）。
// 顶上雷鸣绿龙横幅（base64 内嵌，裁自公司 logo 海报，
// 标题金字＋灰字版本叠在横幅下半部）＋两张浅色玻璃卡＋页底小灰字声明摘要。
// 第一张卡：关于/联系（基于 DYYY、原作者、源码、越狱源、QQ交流、QQ群）＋金色加群大按钮；
// 第二张卡：配置管理（导出/导入/恢复默认/重启抖音）＋更新日志＋检查更新＋声明（声明在最下面）。
// 检查更新、越狱源、重启抖音、点版本行复制信息是 1.0.13 新增；
// 首次打开弹声明不要做（皇上没批）；Fish Audio、reference-xuu/ 一律不动。
#import "GHLAboutViewController.h"

#import <Photos/Photos.h>
#import <stdlib.h>
#import <sys/sysctl.h>

#import "DYYYBottomAlertView.h"
#import "DYYYConstants.h"
#import "DYYYImagePickerDelegate.h"
#import "DYYYSettingViewController.h"
#import "DYYYSettingsHelper.h"
#import "DYYYUtils.h"
#import "GHLFeatures.h"
#import "GHLLogViewerViewController.h"

// 行动作
typedef NS_ENUM(NSInteger, GHLAboutRowAction) {
    GHLAboutRowDYYY = 100,         // 基于 DYYY
    GHLAboutRowAuthor = 101,       // 原作者 huami（只展示）
    GHLAboutRowCurrentAuthor = 106, // 现作者（顾海龙总监，只展示）
    GHLAboutRowSource = 102,       // 源码 Wtrwx / DYYY
    GHLAboutRowRepo = 103,         // 顾海龙集团越狱源
    GHLAboutRowQQContact = 104,    // QQ交流
    GHLAboutRowQQGroup = 105,      // QQ群
    GHLAboutRowExport = 200,       // 导出配置
    GHLAboutRowImport = 201,       // 导入配置
    GHLAboutRowReset = 202,        // 恢复默认配置
    GHLAboutRowRestart = 203,      // 重启抖音
    GHLAboutRowChangelog = 204,    // 更新日志
    GHLAboutRowCheckUpdate = 205,  // 检查更新
    GHLAboutRowDisclaimer = 206,   // 声明（放在最后）
    GHLAboutRowChangeBanner = 207, // 更换横幅背景（1.0.15）
    GHLAboutRowResetBanner = 208,  // 恢复默认横幅（1.0.15）
    GHLAboutRowLogViewer = 209,    // 顾海龙日志（1.0.16，从设置页常用功能移过来）
};

// 1.0.12 的声明全文；1.0.16 皇上改措辞：改成「免费使用，仅限学习交流」。
static NSString *const kGHLAboutDisclaimerText = @"声明：顾海龙抖音基于开源项目 DYYY（MIT 协议，Copyright (c) 2024 huami）二次开发，免费使用，仅限学习交流。使用第三方插件可能违反抖音用户协议，存在账号限制风险，请自行承担风险；作者与本插件不承担任何责任。";

@interface GHLAboutViewController ()

@property(nonatomic, strong) UIScrollView *scrollView;
@property(nonatomic, assign) BOOL checkingUpdate;
@property(nonatomic, weak, nullable) UIButton *checkRowButton;
@property(nonatomic, weak, nullable) UILabel *checkRowTitleLabel;
@property(nonatomic, weak, nullable) UIImageView *checkRowChevron;
@property(nonatomic, weak, nullable) UIActivityIndicatorView *checkRowSpinner;
// 1.0.15：换横幅背景的相册选择器 delegate（要强引用留着，等回调）。
@property(nonatomic, strong, nullable) DYYYImagePickerDelegate *imagePickerDelegate;

@end

// 1.0.21：行对齐常量——图标/文字/箭头/转圈/分隔线都从这里算，改一处全页都对齐。
// （皇上 1.0.20「关于那边都没有对齐」；截图未到，先把系统性的几处修掉：
//  转圈中心比箭头中心偏左 2pt、长标题在小屏上被截断、分隔线右端和卡片右内边没对上。）
static const CGFloat kGHLAboutRowHeight = 52;
static const CGFloat kGHLAboutRowIconX = 16;
static const CGFloat kGHLAboutRowIconSize = 24;
static const CGFloat kGHLAboutRowLabelX = 52; // 图标右端（16+24）+12 间距＝文字左端；分隔线也从这里起
static const CGFloat kGHLAboutCardMargin = 16; // 卡片/横幅左右边距；行右内边也是 16
static const CGFloat kGHLAboutCardSpacing = 16; // 横幅/卡片/页底之间的纵向间距
static const CGFloat kGHLAboutChevronWidth = 12;
static const CGFloat kGHLAboutChevronHeight = 18;
static const CGFloat kGHLAboutSpinnerSize = 20;
// 不在图正中心（320）。标题/版本行按龙头中心对齐，不要按横幅 view 居中——
// 否则字看起来相对龙头偏右（1.0.13 真机反馈「没对准好」）。换横幅图时要重测这个值。
// （1.0.14 的旧图是 280/640；1.0.15 换成展翅龙后重测为 358/640。
//  测法：原图 2736x912 里两只红眼睛在 x=1387 和 x=1538，中点 1463；
//  16:9 居中裁切（x0=557）再缩到 640 宽，龙头中心落在 x=358。）
static const CGFloat kGHLBannerDragonHeadCenterXFraction = 358.0 / 640.0;

@implementation GHLAboutViewController

#pragma mark - 浅色玻璃色（1.0.21：深色改浅色；本页显式浅色，不跟随系统；金色走统一的 dYYYGoldAccentColor）

- (UIColor *)ghlPageBackgroundColor {
    // 1.0.22：页底改不透明（1.0.21 是透明，首页的按键从下面透上来，录屏实锤；
    // 玻璃感只留给卡片外壳和首页，推上来的页面要盖实）。
    return [UIColor systemGroupedBackgroundColor];
}

- (UIColor *)ghlCardBackgroundColor {
    // 1.0.22：卡底改不透明白（1.0.21 的半透明白让上一页透出来，字难读）。
    return [UIColor whiteColor];
}

- (UIColor *)ghlSecondaryTextColor {
    return [UIColor colorWithWhite:0.45 alpha:1.0];
}

- (UIColor *)ghlSeparatorColor {
    return [UIColor colorWithWhite:0.0 alpha:0.08];
}

#pragma mark - 页面结构

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"关于";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    // 浅色玻璃页：显式浅色，不跟随系统。
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleLight;
    self.view.backgroundColor = [self ghlPageBackgroundColor];

    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    scrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    scrollView.backgroundColor = [self ghlPageBackgroundColor];
    [self.view addSubview:scrollView];
    self.scrollView = scrollView;

    CGFloat width = self.view.bounds.size.width;
    CGFloat y = 0;

    // 顶上横幅：雷鸣绿龙图＋金字标题＋灰字版本（点版本行复制信息）。
    UIView *banner = [self ghlBannerView];
    banner.frame = CGRectMake(kGHLAboutCardMargin, kGHLAboutCardMargin, width - kGHLAboutCardMargin * 2, (width - kGHLAboutCardMargin * 2) * 360.0 / 640.0);
    [scrollView addSubview:banner];
    y = CGRectGetMaxY(banner.frame) + kGHLAboutCardSpacing;

    // 第一张卡：关于/联系＋金色加群大按钮。
    UIView *card1 = [self ghlBuildCardWithRows:@[
        [self ghlRowSpecWithTitle:@"基于 DYYY (MIT 协议）" icon:@"gearshape" tag:GHLAboutRowDYYY chevron:NO],
        [self ghlRowSpecWithTitle:@"原作者（huami）" icon:@"person" tag:GHLAboutRowAuthor chevron:NO],
        [self ghlRowSpecWithTitle:@"现作者（顾海龙总监）" icon:@"person.fill" tag:GHLAboutRowCurrentAuthor chevron:NO],
        [self ghlRowSpecWithTitle:@"源码 Wtrwx / DYYY" icon:@"arrow.branch" tag:GHLAboutRowSource chevron:NO],
        [self ghlRowSpecWithTitle:@"顾海龙集团越狱源" icon:@"link" tag:GHLAboutRowRepo chevron:NO],
        // 1.0.14：QQ 行标签改成「QQ：QQ群交流：」+ 号码，点按复制不变。
        [self ghlRowSpecWithTitle:[NSString stringWithFormat:@"QQ：QQ群交流：%@", GHL_QQ_CONTACT_NUMBER] icon:@"message" tag:GHLAboutRowQQContact chevron:NO],
        [self ghlRowSpecWithTitle:[NSString stringWithFormat:@"QQ群 %@", GHL_QQ_GROUP_NUMBER] icon:@"person.2" tag:GHLAboutRowQQGroup chevron:NO],
    ]
                                               joinButton:YES
                                                      width:width - kGHLAboutCardMargin * 2];
    card1.frame = CGRectMake(kGHLAboutCardMargin, y, width - kGHLAboutCardMargin * 2, card1.frame.size.height);
    [scrollView addSubview:card1];
    y = CGRectGetMaxY(card1.frame) + kGHLAboutCardSpacing;

    // 第二张卡：配置管理＋更新日志＋检查更新＋声明（声明在最下面）。
    UIView *card2 = [self ghlBuildCardWithRows:@[
        [self ghlRowSpecWithTitle:@"导出配置" icon:@"square.and.arrow.down" tag:GHLAboutRowExport chevron:YES],
        [self ghlRowSpecWithTitle:@"导入配置" icon:@"square.and.arrow.up" tag:GHLAboutRowImport chevron:YES],
        [self ghlRowSpecWithTitle:@"恢复默认配置" icon:@"arrow.counterclockwise" tag:GHLAboutRowReset chevron:YES],
        [self ghlRowSpecWithTitle:@"重启抖音" icon:@"power" tag:GHLAboutRowRestart chevron:YES],
        // 1.0.15：横幅背景可自己换（相册选图）/恢复默认横幅（回内置展翅龙）。
        [self ghlRowSpecWithTitle:@"更换横幅背景" icon:@"photo" tag:GHLAboutRowChangeBanner chevron:YES],
        [self ghlRowSpecWithTitle:@"恢复默认横幅" icon:@"arrow.uturn.backward" tag:GHLAboutRowResetBanner chevron:YES],
        [self ghlRowSpecWithTitle:@"更新日志" icon:@"list.clipboard" tag:GHLAboutRowChangelog chevron:YES],
        [self ghlRowSpecWithTitle:@"检查更新" icon:@"sparkles" tag:GHLAboutRowCheckUpdate chevron:YES],
        // 1.0.16：顾海龙日志从设置页常用功能移过来（检查更新之后、声明之前；声明必须在最下面）。
        // 图标不用 list.clipboard（更新日志占了）和 doc.text（声明占了），用 doc.text.magnifyingglass。
        [self ghlRowSpecWithTitle:@"顾海龙日志" icon:@"doc.text.magnifyingglass" tag:GHLAboutRowLogViewer chevron:YES],
        [self ghlRowSpecWithTitle:@"声明" icon:@"doc.text" tag:GHLAboutRowDisclaimer chevron:YES],
    ]
                                               joinButton:NO
                                                      width:width - kGHLAboutCardMargin * 2];
    card2.frame = CGRectMake(kGHLAboutCardMargin, y, width - kGHLAboutCardMargin * 2, card2.frame.size.height);
    [scrollView addSubview:card2];
    y = CGRectGetMaxY(card2.frame) + kGHLAboutCardSpacing;

    // 页底一行小灰字：声明摘要（框和卡片左右对齐，文字本身居中）。
    UILabel *footerLabel = [[UILabel alloc] initWithFrame:CGRectMake(kGHLAboutCardMargin, y, width - kGHLAboutCardMargin * 2, 28)];
    footerLabel.text = @"基于开源项目 DYYY 二次开发，仅供学习交流使用";
    footerLabel.font = [UIFont systemFontOfSize:12];
    footerLabel.textColor = [self ghlSecondaryTextColor];
    footerLabel.textAlignment = NSTextAlignmentCenter;
    footerLabel.numberOfLines = 0;
    footerLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [scrollView addSubview:footerLabel];

    scrollView.contentSize = CGSizeMake(width, CGRectGetMaxY(footerLabel.frame) + 24);
}

// 横幅：雷鸣绿龙图（裁自公司 logo 海报；解不出来就回退龙头图）＋金字标题＋灰字版本。
// 底部渐隐，保证金字标题和灰字版本读得清。
- (UIView *)ghlBannerView {
    UIView *banner = [[UIView alloc] initWithFrame:CGRectZero];
    banner.tag = 1000;
    banner.layer.cornerRadius = 16;
    banner.layer.masksToBounds = YES;
    banner.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    UIImageView *imageView = [[UIImageView alloc] initWithFrame:banner.bounds];
    imageView.image = GHLAboutBannerImage() ?: GHLLogoImage();
    imageView.contentMode = UIViewContentModeScaleAspectFill;
    imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    imageView.tag = 1003; // 1.0.15：换横幅/恢复默认后按 tag 找到它刷新图。
    [banner addSubview:imageView];

    CAGradientLayer *fade = [CAGradientLayer layer];
    fade.frame = banner.bounds;
    fade.colors = @[ (id)[UIColor colorWithWhite:0 alpha:0].CGColor, (id)[UIColor colorWithWhite:0 alpha:0.75].CGColor ];
    fade.locations = @[ @0.45, @1.0 ];
    [banner.layer addSublayer:fade];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 0, 0, 38)];
    titleLabel.text = @"顾海龙抖音";
    titleLabel.font = [UIFont boldSystemFontOfSize:30];
    titleLabel.textColor = [DYYYUtils dYYYGoldAccentColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    titleLabel.tag = 1001;
    [banner addSubview:titleLabel];

    UILabel *versionLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 0, 0, 20)];
    versionLabel.text = [NSString stringWithFormat:@"版本 %@", DYYY_VERSION];
    versionLabel.font = [UIFont systemFontOfSize:14];
    versionLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    versionLabel.textAlignment = NSTextAlignmentCenter;
    versionLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    versionLabel.userInteractionEnabled = YES;
    versionLabel.tag = 1002;
    [versionLabel addGestureRecognizer:[[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(ghlVersionLabelTapped)]];
    [banner addSubview:versionLabel];

    return banner;
}

// 横幅里的标题/版本行按横幅实际高度摆（viewDidLayoutSubviews 时横幅已有最终尺寸；
// 渐隐层也跟上横幅尺寸——建横幅时它的 bounds 还是 0，autoresizing 管不到 CALayer）。
// 1.0.22：内容宽也在这里跟 view 走——viewDidLoad 时 view 还是屏幕宽，contentSize 按
// 屏幕宽算，排到卡片宽之后右边会多出一段横向滚动；高度不动（只改宽）。
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    CGFloat viewWidth = self.view.bounds.size.width;
    if (viewWidth > 0 && fabs(self.scrollView.contentSize.width - viewWidth) > 0.5) {
        self.scrollView.contentSize = CGSizeMake(viewWidth, self.scrollView.contentSize.height);
    }
    UIView *banner = [self.scrollView viewWithTag:1000];
    if (!banner) return;
    UILabel *titleLabel = (UILabel *)[banner viewWithTag:1001];
    UILabel *versionLabel = (UILabel *)[banner viewWithTag:1002];
    if (!titleLabel || !versionLabel) return;
    CGFloat bannerWidth = banner.bounds.size.width;
    CGFloat bannerHeight = banner.bounds.size.height;
    // 标题/版本行以横幅里龙头中心为中心（不是横幅 view 的中心）——
    // 龙头在 640x360 图里偏左，字按 view 居中会相对龙头偏右（1.0.13 真机反馈）。
    // 自选横幅图龙头位置未知，改按横幅中心对齐（见 ghlBannerTitleCenterXFraction）。
    // label 宽取龙头中心到横幅两边最小距离的两倍，保证不超出横幅。
    CGFloat headCenterX = bannerWidth * [self ghlBannerTitleCenterXFraction];
    CGFloat labelWidth = 2.0 * MIN(headCenterX, bannerWidth - headCenterX);
    CGFloat labelX = headCenterX - labelWidth / 2.0;
    titleLabel.frame = CGRectMake(labelX, bannerHeight - 66, labelWidth, 38);
    versionLabel.frame = CGRectMake(labelX, bannerHeight - 28, labelWidth, 20);
    for (CALayer *layer in banner.layer.sublayers) {
        if ([layer isKindOfClass:[CAGradientLayer class]]) layer.frame = banner.bounds;
    }
}

// 横幅标题对准的中心：内置展翅龙按实测龙头中心；自选图龙头位置未知，按横幅中心对齐。
- (CGFloat)ghlBannerTitleCenterXFraction {
    if (GHLHasCustomAboutBanner()) return 0.5;
    return kGHLBannerDragonHeadCenterXFraction;
}

// 换横幅/恢复默认后刷新横幅图（标题对准跟着换：自选图按横幅中心，内置图按龙头中心）。
- (void)ghlRefreshBannerImage {
    UIView *banner = [self.scrollView viewWithTag:1000];
    UIImageView *imageView = (UIImageView *)[banner viewWithTag:1003];
    if (!imageView) return;
    imageView.image = GHLAboutBannerImage() ?: GHLLogoImage();
    [self.view setNeedsLayout];
}

#pragma mark - 卡片与行

- (NSDictionary *)ghlRowSpecWithTitle:(NSString *)title icon:(NSString *)icon tag:(NSInteger)tag chevron:(BOOL)chevron {
    return @{@"title": title, @"icon": icon, @"tag": @(tag), @"chevron": @(chevron)};
}

// 浅色玻璃卡：半透明白底＋细金边＋圆角 16；行高 52；可选底部金色加群大按钮。
- (UIView *)ghlBuildCardWithRows:(NSArray<NSDictionary *> *)rows joinButton:(BOOL)joinButton width:(CGFloat)width {
    CGFloat rowHeight = kGHLAboutRowHeight;
    CGFloat height = rows.count * rowHeight + (joinButton ? (12 + 56 + 16) : 0);
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
    card.backgroundColor = [self ghlCardBackgroundColor];
    card.layer.cornerRadius = 16;
    card.layer.borderWidth = 0.6;
    card.layer.borderColor = [[DYYYUtils dYYYGoldAccentColor] colorWithAlphaComponent:0.35].CGColor;
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    CGFloat y = 0;
    for (NSInteger i = 0; i < (NSInteger)rows.count; i++) {
        NSDictionary *spec = rows[i];
        UIButton *row = [self ghlRowButtonWithTitle:spec[@"title"] icon:spec[@"icon"] tag:[spec[@"tag"] integerValue] hasChevron:[spec[@"chevron"] boolValue] width:width];
        row.frame = CGRectMake(0, y, width, rowHeight);
        [card addSubview:row];
        if (i + 1 < (NSInteger)rows.count) {
            // 分隔线：左端＝文字左端（52），右端＝卡片右内边（16），和文字/箭头对齐。
            UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(kGHLAboutRowLabelX, y + rowHeight - 0.5, width - kGHLAboutRowLabelX - kGHLAboutCardMargin, 0.5)];
            sep.backgroundColor = [self ghlSeparatorColor];
            sep.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [card addSubview:sep];
        }
        y += rowHeight;
    }
    if (joinButton) {
        UIButton *join = [UIButton buttonWithType:UIButtonTypeCustom];
        join.frame = CGRectMake(kGHLAboutCardMargin, y + 12, width - kGHLAboutCardMargin * 2, 56);
        join.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        join.backgroundColor = [DYYYUtils dYYYGoldAccentColor];
        join.layer.cornerRadius = 16;
        [join setTitle:@"加入 QQ 交流群" forState:UIControlStateNormal];
        [join setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        join.titleLabel.font = [UIFont boldSystemFontOfSize:18];
        [join addTarget:self action:@selector(ghlJoinGroupTapped) forControlEvents:UIControlEventTouchUpInside];
        [card addSubview:join];
    }
    return card;
}

// 卡内一行：金图标＋深色字＋（有动作时）金色箭头。
// 对齐：图标 x=16（24×24，行高 52 里垂直居中）；文字 x=52；箭头右端＝卡片右内边 16；
// 转圈中心＝箭头中心（以前转圈中心比箭头偏左 2pt）；长标题太长时自动缩字不截断。
- (UIButton *)ghlRowButtonWithTitle:(NSString *)title icon:(NSString *)iconName tag:(NSInteger)tag hasChevron:(BOOL)hasChevron width:(CGFloat)width {
    UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
    row.frame = CGRectMake(0, 0, width, kGHLAboutRowHeight);
    row.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    row.tag = tag;
    [row addTarget:self action:@selector(ghlRowTapped:) forControlEvents:UIControlEventTouchUpInside];

    UIImageView *iconView = [[UIImageView alloc] initWithFrame:CGRectMake(kGHLAboutRowIconX, (kGHLAboutRowHeight - kGHLAboutRowIconSize) / 2, kGHLAboutRowIconSize, kGHLAboutRowIconSize)];
    iconView.image = [UIImage systemImageNamed:iconName];
    iconView.tintColor = [DYYYUtils dYYYGoldAccentColor];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    [row addSubview:iconView];

    CGFloat labelRightInset = hasChevron ? (kGHLAboutCardMargin + kGHLAboutChevronWidth + 8) : kGHLAboutCardMargin;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(kGHLAboutRowLabelX, 0, width - kGHLAboutRowLabelX - labelRightInset, kGHLAboutRowHeight)];
    label.text = title;
    label.font = [UIFont systemFontOfSize:17];
    label.textColor = [UIColor colorWithWhite:0.15 alpha:1.0];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    // 长标题（QQ 行 19 字）在小屏上会超宽：自动缩字到 0.85 倍，不截断。
    label.adjustsFontSizeToFitWidth = YES;
    label.minimumScaleFactor = 0.85;
    [row addSubview:label];

    UIImageView *chevron = nil;
    if (hasChevron) {
        CGFloat chevronX = width - kGHLAboutCardMargin - kGHLAboutChevronWidth;
        chevron = [[UIImageView alloc] initWithFrame:CGRectMake(chevronX, (kGHLAboutRowHeight - kGHLAboutChevronHeight) / 2, kGHLAboutChevronWidth, kGHLAboutChevronHeight)];
        chevron.image = [UIImage systemImageNamed:@"chevron.right"];
        chevron.tintColor = [[DYYYUtils dYYYGoldAccentColor] colorWithAlphaComponent:0.55];
        chevron.contentMode = UIViewContentModeScaleAspectFit;
        chevron.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [row addSubview:chevron];
    }
    if (tag == GHLAboutRowCheckUpdate) {
        self.checkRowButton = row;
        self.checkRowTitleLabel = label;
        self.checkRowChevron = chevron;
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
        // 转圈中心和箭头中心同一个点（箭头中心 x＝卡片右内边 16＋箭头宽 12 的一半＝宽-22）。
        CGFloat spinnerCenterX = width - kGHLAboutCardMargin - kGHLAboutChevronWidth / 2;
        spinner.frame = CGRectMake(spinnerCenterX - kGHLAboutSpinnerSize / 2, (kGHLAboutRowHeight - kGHLAboutSpinnerSize) / 2, kGHLAboutSpinnerSize, kGHLAboutSpinnerSize);
        spinner.color = [DYYYUtils dYYYGoldAccentColor];
        spinner.hidden = YES;
        spinner.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [row addSubview:spinner];
        self.checkRowSpinner = spinner;
        if (self.checkingUpdate) {
            label.text = @"正在检查…";
            row.enabled = NO;
            chevron.hidden = YES;
            spinner.hidden = NO;
            [spinner startAnimating];
        }
    }
    return row;
}

#pragma mark - 行动作

- (void)ghlRowTapped:(UIButton *)sender {
    switch (sender.tag) {
        case GHLAboutRowDYYY:
        case GHLAboutRowSource:
            // 基于 DYYY / 源码 Wtrwx / DYYY：跳上游仓库。
            [self ghlOpenURLString:GHL_DYYY_SOURCE_URL fallbackMessage:@"打开失败，请检查网络后重试"];
            break;
        case GHLAboutRowAuthor:
            break;  // 原作者 huami 只是展示，没有动作。
        case GHLAboutRowCurrentAuthor:
            break;  // 现作者（顾海龙总监）只是展示，没有动作。
        case GHLAboutRowRepo:
            [self ghlShowRepoSourceOptionsFromView:sender];
            break;
        case GHLAboutRowQQContact:
            [UIPasteboard generalPasteboard].string = GHL_QQ_CONTACT_NUMBER;
            [DYYYUtils showToast:@"已复制"];
            break;
        case GHLAboutRowQQGroup:
            [UIPasteboard generalPasteboard].string = GHL_QQ_GROUP_NUMBER;
            [DYYYUtils showToast:@"已复制"];
            break;
        case GHLAboutRowExport:
            // 导出配置：复用设置主页的逻辑（key 与逻辑不动）。
            if ([self ghlSettingsAvailable]) [self.settingsViewController ghlExportAndShareFromIndexPath:nil];
            break;
        case GHLAboutRowImport:
            // 导入配置：复用设置主页的逻辑。
            if ([self ghlSettingsAvailable]) [self.settingsViewController ghlPresentImportPicker];
            break;
        case GHLAboutRowReset:
            // 恢复默认配置：复用设置主页的逻辑（自带二次确认）。
            if ([self ghlSettingsAvailable]) [self.settingsViewController ghlConfirmResetSettings];
            break;
        case GHLAboutRowRestart:
            [self ghlConfirmRestartDouyin];
            break;
        case GHLAboutRowChangeBanner:
            [self ghlPresentBannerImagePicker];
            break;
        case GHLAboutRowResetBanner:
            [self ghlResetBanner];
            break;
        case GHLAboutRowChangelog:
            [DYYYSettingsHelper showAboutDialog:@"更新日志" message:GHLChangelogText() onConfirm:nil];
            break;
        case GHLAboutRowCheckUpdate:
            [self ghlCheckForUpdate];
            break;
        case GHLAboutRowLogViewer:
            // 1.0.16：顾海龙日志从设置页移过来（日志查看器是普通 VC，关于页是浅色玻璃页，
            // 进出外观是否跳变要真机看一眼）。
            // 1.0.22：卡片内打开，页底改不透明（和设置列表/关于页同款）。
            {
                GHLLogViewerViewController *logVC = [[GHLLogViewerViewController alloc] init];
                logVC.ghlInFloatPanel = YES;
                [self.navigationController pushViewController:logVC animated:YES];
            }
            break;
        case GHLAboutRowDisclaimer:
            // 声明在最下面，点开看 1.0.12 的声明全文（措辞不动）。
            [DYYYSettingsHelper showAboutDialog:@"声明" message:kGHLAboutDisclaimerText onConfirm:nil];
            break;
        default:
            break;
    }
}

- (BOOL)ghlSettingsAvailable {
    if (self.settingsViewController) return YES;
    [DYYYUtils showToast:@"打不开，请重试"];
    return NO;
}

#pragma mark - 点版本行复制信息

// 点版本行复制：版本＋运行时读到的机型标识＋系统版本，不写死机型。
- (void)ghlVersionLabelTapped {
    NSString *info = [NSString stringWithFormat:@"顾海龙抖音 %@／%@／iOS %@", DYYY_VERSION, [self ghlDeviceModelIdentifier], [UIDevice currentDevice].systemVersion];
    [UIPasteboard generalPasteboard].string = info;
    [DYYYUtils showToast:@"已复制"];
}

- (NSString *)ghlDeviceModelIdentifier {
    size_t size = 0;
    sysctlbyname("hw.machine", NULL, &size, NULL, 0);
    if (size == 0) return @"未知机型";
    char *machine = malloc(size);
    if (!machine) return @"未知机型";
    sysctlbyname("hw.machine", machine, &size, NULL, 0);
    NSString *result = [NSString stringWithUTF8String:machine];
    free(machine);
    return result.length > 0 ? result : @"未知机型";
}

#pragma mark - 加入 QQ 群 / 打开链接

- (void)ghlJoinGroupTapped {
    [self ghlOpenURLString:GHL_QQ_GROUP_JOIN_URL fallbackMessage:@"打开失败，请检查网络后重试"];
}

// 打开链接：打不开就如实提示（openURL 的 completion 也可能不在主线程回调，UI 回主线程）。
- (void)ghlOpenURLString:(NSString *)urlString fallbackMessage:(NSString *)fallbackMessage {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url) {
        [DYYYUtils showToast:fallbackMessage];
        return;
    }
    [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
        if (!success) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [DYYYUtils showToast:fallbackMessage];
            });
        }
    }];
}

#pragma mark - 越狱源

- (void)ghlShowRepoSourceOptionsFromView:(UIView *)sourceView {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"顾海龙集团越狱源" message:GHL_REPO_URL preferredStyle:UIAlertControllerStyleActionSheet];
    UIAlertAction *copyAction = [UIAlertAction actionWithTitle:@"复制源地址" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        [UIPasteboard generalPasteboard].string = GHL_REPO_URL;
        [DYYYUtils showToast:@"已复制"];
    }];
    [alert addAction:copyAction];
    __weak typeof(self) weakSelf = self;
    UIAlertAction *sileoAction = [UIAlertAction actionWithTitle:@"在 Sileo 中打开" style:UIAlertActionStyleDefault handler:^(__unused UIAlertAction *action) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *sileoURLString = [NSString stringWithFormat:@"sileo://source/%@", GHL_REPO_URL];
        NSURL *sileoURL = [NSURL URLWithString:sileoURLString];
        if (!sileoURL) {
            [UIPasteboard generalPasteboard].string = GHL_REPO_URL;
            [DYYYUtils showToast:@"已复制源地址，请在 Sileo 中手动添加"];
            return;
        }
        [[UIApplication sharedApplication] openURL:sileoURL options:@{} completionHandler:^(BOOL success) {
            if (!success) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [UIPasteboard generalPasteboard].string = GHL_REPO_URL;
                    [DYYYUtils showToast:@"已复制源地址，请在 Sileo 中手动添加"];
                });
            }
        }];
    }];
    [alert addAction:sileoAction];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil];
    [alert addAction:cancelAction];
    if (UIDevice.currentDevice.userInterfaceIdiom == UIUserInterfaceIdiomPad) {
        alert.popoverPresentationController.sourceView = sourceView ?: self.view;
        alert.popoverPresentationController.sourceRect = sourceView ? sourceView.bounds : self.view.bounds;
    }
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 检查更新

// 检查更新：异步拉源里的 Packages，比对 com.guhailong.douyin 的 Version。
// 有新版就提示去 Sileo 刷新，已是最新就说已是最新，联网失败或解析不到就如实报失败，绝不谎报。
- (void)ghlCheckForUpdate {
    if (self.checkingUpdate) return;
    self.checkingUpdate = YES;
    [self ghlSetCheckButtonChecking:YES];
    [DYYYUtils showToast:@"正在检查更新…"];
    NSURL *url = [NSURL URLWithString:[GHL_REPO_URL stringByAppendingString:@"/Packages"]];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.timeoutInterval = 15;
    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) return;
        NSString *remoteVersion = nil;
        BOOL httpOK = [response isKindOfClass:[NSHTTPURLResponse class]] && ((NSHTTPURLResponse *)response).statusCode == 200;
        if (!error && httpOK && data.length > 0) {
            NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            remoteVersion = [strongSelf ghlParseDouyinVersionFromPackagesText:text];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            strongSelf.checkingUpdate = NO;
            [strongSelf ghlSetCheckButtonChecking:NO];
            if (!remoteVersion) {
                [DYYYSettingsHelper showAboutDialog:@"检查更新" message:@"检查失败，请检查网络后重试" onConfirm:nil];
                GHLLog(@"检查更新：失败（%@）", error ? error.localizedDescription : @"解析不到版本号");
                return;
            }
            NSComparisonResult cmp = [strongSelf ghlCompareVersion:remoteVersion toVersion:DYYY_VERSION];
            if (cmp == NSOrderedDescending) {
                [DYYYSettingsHelper showAboutDialog:@"检查更新" message:[NSString stringWithFormat:@"发现新版本 %@，请到 Sileo 刷新源更新", remoteVersion] onConfirm:nil];
            } else {
                [DYYYSettingsHelper showAboutDialog:@"检查更新" message:[NSString stringWithFormat:@"已是最新版本（%@）", DYYY_VERSION] onConfirm:nil];
            }
            GHLLog(@"检查更新：本地 %@，源里 %@", DYYY_VERSION, remoteVersion);
        });
    }];
    [task resume];
}

// 检查中：行标题换成「正在检查…」，箭头换成转圈，行不可再点。
- (void)ghlSetCheckButtonChecking:(BOOL)checking {
    UIButton *button = self.checkRowButton;
    if (button) button.enabled = !checking;
    if (self.checkRowTitleLabel) self.checkRowTitleLabel.text = checking ? @"正在检查…" : @"检查更新";
    if (self.checkRowChevron) self.checkRowChevron.hidden = checking;
    if (self.checkRowSpinner) {
        self.checkRowSpinner.hidden = !checking;
        if (checking) [self.checkRowSpinner startAnimating];
        else [self.checkRowSpinner stopAnimating];
    }
}

- (nullable NSString *)ghlParseDouyinVersionFromPackagesText:(nullable NSString *)text {
    if (!text) return nil;
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    for (NSInteger i = 0; i < (NSInteger)lines.count; i++) {
        if ([lines[i] isEqualToString:@"Package: com.guhailong.douyin"]) {
            for (NSInteger j = i + 1; j < (NSInteger)lines.count && j < i + 10; j++) {
                if (lines[j].length == 0) break;
                if ([lines[j] hasPrefix:@"Version: "]) return [lines[j] substringFromIndex:@"Version: ".length];
            }
            break;
        }
    }
    return nil;
}

- (NSComparisonResult)ghlCompareVersion:(NSString *)a toVersion:(NSString *)b {
    NSArray<NSString *> *pa = [a componentsSeparatedByString:@"."];
    NSArray<NSString *> *pb = [b componentsSeparatedByString:@"."];
    NSUInteger n = MAX(pa.count, pb.count);
    for (NSUInteger i = 0; i < n; i++) {
        NSInteger va = i < pa.count ? pa[i].integerValue : 0;
        NSInteger vb = i < pb.count ? pb[i].integerValue : 0;
        if (va < vb) return NSOrderedAscending;
        if (va > vb) return NSOrderedDescending;
    }
    return NSOrderedSame;
}

#pragma mark - 更换横幅背景 / 恢复默认横幅

// 更换横幅背景：相册选图（照设置主页换龙头/换背景的做法：拒绝了相册权限就提示，不硬打开；
// 存图放后台线程，存完回主线程刷新横幅；自选图按 16:9 居中裁成 640x360 再存）。
- (void)ghlPresentBannerImagePicker {
    PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
    if (status == PHAuthorizationStatusDenied || status == PHAuthorizationStatusRestricted) {
        [DYYYUtils showToast:@"需要相册权限才能换图"];
        return;
    }
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
      dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        BOOL ok = GHLSaveCustomAboutBannerImage(image);
        GHLRunOnMain(^{
          if (!ok) {
              [DYYYUtils showToast:@"保存失败，换图没成功"];
              return;
          }
          [strongSelf ghlRefreshBannerImage];
          [DYYYUtils showToast:@"横幅背景已更换"];
        });
      });
    };
    UIImagePickerController *picker = [[UIImagePickerController alloc] init];
    picker.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
    picker.delegate = self.imagePickerDelegate;
    [self presentViewController:picker animated:YES completion:nil];
}

// 恢复默认横幅：删掉自选图，横幅回到内置展翅龙（标题对准也回到龙头中心）。
- (void)ghlResetBanner {
    GHLClearCustomAboutBanner();
    [self ghlRefreshBannerImage];
    [DYYYUtils showToast:@"已恢复默认横幅"];
}

#pragma mark - 重启抖音

// 重启抖音：先弹确认，确认后 exit(0)（抖音下次启动即重进）。
- (void)ghlConfirmRestartDouyin {
    [DYYYBottomAlertView showAlertWithTitle:@"重启抖音"
                                     message:@"抖音将立即重启。"
                                   avatarURL:nil
                            cancelButtonText:@"取消"
                           confirmButtonText:@"重启"
                                cancelAction:nil
                                 closeAction:nil
                               confirmAction:^{
                                 exit(0);
                               }];
}

@end
