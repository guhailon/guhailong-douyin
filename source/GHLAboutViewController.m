// GHLAboutViewController — 关于深色品牌页（1.0.13，方案四）
// 1.0.14：标题/版本行按横幅里龙头中心对齐；QQ 行标签改成「QQ：QQ群交流：」+ 号码；
// 原作者行改成「原作者（huami）」，下面加一行只展示的「现作者（顾海龙总监）」。
// 显式深色，不跟随系统：顶上雷鸣绿龙横幅（base64 内嵌，裁自公司 logo 海报，
// 标题金字＋灰字版本叠在横幅下半部）＋两张深色金边卡＋页底小灰字声明摘要。
// 第一张卡：关于/联系（基于 DYYY、原作者、源码、越狱源、QQ交流、QQ群）＋金色加群大按钮；
// 第二张卡：配置管理（导出/导入/恢复默认/重启抖音）＋更新日志＋检查更新＋声明（声明在最下面）。
// 检查更新、越狱源、重启抖音、点版本行复制信息是 1.0.13 新增；
// 首次打开弹声明不要做（皇上没批）；Fish Audio、reference-xuu/ 一律不动。
#import "GHLAboutViewController.h"

#import <stdlib.h>
#import <sys/sysctl.h>

#import "DYYYBottomAlertView.h"
#import "DYYYConstants.h"
#import "DYYYSettingViewController.h"
#import "DYYYSettingsHelper.h"
#import "DYYYUtils.h"
#import "GHLFeatures.h"

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
};

// 1.0.12 的声明全文（措辞不动，皇上可改）。
static NSString *const kGHLAboutDisclaimerText = @"声明：顾海龙抖音基于开源项目 DYYY（MIT 协议，Copyright (c) 2024 huami）二次开发，仅供个人学习交流使用，不对外发布。使用第三方插件可能违反抖音用户协议，存在账号限制风险，请自行承担风险；作者与本插件不承担任何责任。";

@interface GHLAboutViewController ()

@property(nonatomic, strong) UIScrollView *scrollView;
@property(nonatomic, assign) BOOL checkingUpdate;
@property(nonatomic, weak, nullable) UIButton *checkRowButton;
@property(nonatomic, weak, nullable) UILabel *checkRowTitleLabel;
@property(nonatomic, weak, nullable) UIImageView *checkRowChevron;
@property(nonatomic, weak, nullable) UIActivityIndicatorView *checkRowSpinner;

@end

// 横幅里龙头中心（实测）：两只红眼睛的中点在 640x360 横幅图的 x=280（280/640），
 // 不在图正中心（320）。标题/版本行按龙头中心对齐，不要按横幅 view 居中——
 // 否则字看起来相对龙头偏右（1.0.13 真机反馈「没对准好」）。换横幅图时要重测这个值。
static const CGFloat kGHLBannerDragonHeadCenterXFraction = 280.0 / 640.0;

@implementation GHLAboutViewController

#pragma mark - 深色品牌色（本页显式深色，不跟随系统；金色走统一的 dYYYGoldAccentColor）

- (UIColor *)ghlPageBackgroundColor {
    return [UIColor colorWithRed:10 / 255.0 green:10 / 255.0 blue:18 / 255.0 alpha:1.0];
}

- (UIColor *)ghlCardBackgroundColor {
    return [UIColor colorWithRed:23 / 255.0 green:23 / 255.0 blue:36 / 255.0 alpha:1.0];
}

- (UIColor *)ghlSecondaryTextColor {
    return [UIColor colorWithWhite:0.62 alpha:1.0];
}

- (UIColor *)ghlSeparatorColor {
    return [UIColor colorWithWhite:1.0 alpha:0.08];
}

#pragma mark - 页面结构

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"关于";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    // 深色品牌页：显式深色，不跟随系统。
    self.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
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
    banner.frame = CGRectMake(16, 16, width - 32, (width - 32) * 360.0 / 640.0);
    [scrollView addSubview:banner];
    y = CGRectGetMaxY(banner.frame) + 16;

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
                                                      width:width - 32];
    card1.frame = CGRectMake(16, y, width - 32, card1.frame.size.height);
    [scrollView addSubview:card1];
    y = CGRectGetMaxY(card1.frame) + 16;

    // 第二张卡：配置管理＋更新日志＋检查更新＋声明（声明在最下面）。
    UIView *card2 = [self ghlBuildCardWithRows:@[
        [self ghlRowSpecWithTitle:@"导出配置" icon:@"square.and.arrow.down" tag:GHLAboutRowExport chevron:YES],
        [self ghlRowSpecWithTitle:@"导入配置" icon:@"square.and.arrow.up" tag:GHLAboutRowImport chevron:YES],
        [self ghlRowSpecWithTitle:@"恢复默认配置" icon:@"arrow.counterclockwise" tag:GHLAboutRowReset chevron:YES],
        [self ghlRowSpecWithTitle:@"重启抖音" icon:@"power" tag:GHLAboutRowRestart chevron:YES],
        [self ghlRowSpecWithTitle:@"更新日志" icon:@"list.clipboard" tag:GHLAboutRowChangelog chevron:YES],
        [self ghlRowSpecWithTitle:@"检查更新" icon:@"sparkles" tag:GHLAboutRowCheckUpdate chevron:YES],
        [self ghlRowSpecWithTitle:@"声明" icon:@"doc.text" tag:GHLAboutRowDisclaimer chevron:YES],
    ]
                                               joinButton:NO
                                                      width:width - 32];
    card2.frame = CGRectMake(16, y, width - 32, card2.frame.size.height);
    [scrollView addSubview:card2];
    y = CGRectGetMaxY(card2.frame) + 16;

    // 页底一行小灰字：声明摘要。
    UILabel *footerLabel = [[UILabel alloc] initWithFrame:CGRectMake(24, y, width - 48, 28)];
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
- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    UIView *banner = [self.scrollView viewWithTag:1000];
    if (!banner) return;
    UILabel *titleLabel = (UILabel *)[banner viewWithTag:1001];
    UILabel *versionLabel = (UILabel *)[banner viewWithTag:1002];
    if (!titleLabel || !versionLabel) return;
    CGFloat bannerWidth = banner.bounds.size.width;
    CGFloat bannerHeight = banner.bounds.size.height;
    // 标题/版本行以横幅里龙头中心为中心（不是横幅 view 的中心）——
    // 龙头在 640x360 图里偏左，字按 view 居中会相对龙头偏右（1.0.13 真机反馈）。
    // label 宽取龙头中心到横幅两边最小距离的两倍，保证不超出横幅。
    CGFloat headCenterX = bannerWidth * kGHLBannerDragonHeadCenterXFraction;
    CGFloat labelWidth = 2.0 * MIN(headCenterX, bannerWidth - headCenterX);
    CGFloat labelX = headCenterX - labelWidth / 2.0;
    titleLabel.frame = CGRectMake(labelX, bannerHeight - 66, labelWidth, 38);
    versionLabel.frame = CGRectMake(labelX, bannerHeight - 28, labelWidth, 20);
    for (CALayer *layer in banner.layer.sublayers) {
        if ([layer isKindOfClass:[CAGradientLayer class]]) layer.frame = banner.bounds;
    }
}

#pragma mark - 卡片与行

- (NSDictionary *)ghlRowSpecWithTitle:(NSString *)title icon:(NSString *)icon tag:(NSInteger)tag chevron:(BOOL)chevron {
    return @{@"title": title, @"icon": icon, @"tag": @(tag), @"chevron": @(chevron)};
}

// 深色卡：深底＋金边＋圆角 16；行高 52；可选底部金色加群大按钮。
- (UIView *)ghlBuildCardWithRows:(NSArray<NSDictionary *> *)rows joinButton:(BOOL)joinButton width:(CGFloat)width {
    CGFloat rowHeight = 52;
    CGFloat height = rows.count * rowHeight + (joinButton ? (12 + 56 + 16) : 0);
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(0, 0, width, height)];
    card.backgroundColor = [self ghlCardBackgroundColor];
    card.layer.cornerRadius = 16;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [[DYYYUtils dYYYGoldAccentColor] colorWithAlphaComponent:0.45].CGColor;
    card.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    CGFloat y = 0;
    for (NSInteger i = 0; i < (NSInteger)rows.count; i++) {
        NSDictionary *spec = rows[i];
        UIButton *row = [self ghlRowButtonWithTitle:spec[@"title"] icon:spec[@"icon"] tag:[spec[@"tag"] integerValue] hasChevron:[spec[@"chevron"] boolValue] width:width];
        row.frame = CGRectMake(0, y, width, rowHeight);
        [card addSubview:row];
        if (i + 1 < (NSInteger)rows.count) {
            UIView *sep = [[UIView alloc] initWithFrame:CGRectMake(52, y + rowHeight - 0.5, width - 52 - 16, 0.5)];
            sep.backgroundColor = [self ghlSeparatorColor];
            sep.autoresizingMask = UIViewAutoresizingFlexibleWidth;
            [card addSubview:sep];
        }
        y += rowHeight;
    }
    if (joinButton) {
        UIButton *join = [UIButton buttonWithType:UIButtonTypeCustom];
        join.frame = CGRectMake(16, y + 12, width - 32, 56);
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

// 卡内一行：金图标＋白字＋（有动作时）金色箭头。
- (UIButton *)ghlRowButtonWithTitle:(NSString *)title icon:(NSString *)iconName tag:(NSInteger)tag hasChevron:(BOOL)hasChevron width:(CGFloat)width {
    UIButton *row = [UIButton buttonWithType:UIButtonTypeCustom];
    row.frame = CGRectMake(0, 0, width, 52);
    row.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    row.tag = tag;
    [row addTarget:self action:@selector(ghlRowTapped:) forControlEvents:UIControlEventTouchUpInside];

    UIImageView *iconView = [[UIImageView alloc] initWithFrame:CGRectMake(16, 14, 24, 24)];
    iconView.image = [UIImage systemImageNamed:iconName];
    iconView.tintColor = [DYYYUtils dYYYGoldAccentColor];
    iconView.contentMode = UIViewContentModeScaleAspectFit;
    [row addSubview:iconView];

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(52, 0, width - 52 - 36, 52)];
    label.text = title;
    label.font = [UIFont systemFontOfSize:17];
    label.textColor = [UIColor whiteColor];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [row addSubview:label];

    UIImageView *chevron = nil;
    if (hasChevron) {
        chevron = [[UIImageView alloc] initWithFrame:CGRectMake(width - 28, 17, 12, 18)];
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
        spinner.frame = CGRectMake(width - 34, 16, 20, 20);
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
        case GHLAboutRowChangelog:
            [DYYYSettingsHelper showAboutDialog:@"更新日志" message:GHLChangelogText() onConfirm:nil];
            break;
        case GHLAboutRowCheckUpdate:
            [self ghlCheckForUpdate];
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
