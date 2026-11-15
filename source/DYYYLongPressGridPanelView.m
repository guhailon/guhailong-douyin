// 顾海龙抖音长按下载面板：网格风格（1.0.9）
// 浅色毛玻璃底板 + 可调列数金色图标网格 + 顶部金色龙头（复用 GHLLogoImage()，圆形金边，和设置页头卡同一套）。
// 1.0.23 第二批：面板外观可调（背景图 51、材质三选一 53、排列 54、模糊度 56、微透明 64），
// 只改这个面板表面，不动设置卡片。
// 1.0.21：深色改浅色（和卡片首页／关于页同款 iOS 文件夹式浅色玻璃）。
// 效果图：workspace/imagine_media/media-generation-download-menu-grid-dragon-0-168c78e9-fb05-4e57-8b23-f8476d304c10.webp
// 与效果图的一处差别：龙头没有探出面板顶边（贴边 10pt 放在毛玻璃里），避免 sheet 容器裁切导致龙头被切一半。
// 1.0.15：没有「更多」了——自定义项和抖音原生项全在网格里，长按只出网格，不再回到原生列表页。
#import "DYYYLongPressGridPanelView.h"
#import "DYYYUtils.h"
#import "GHLFeatures.h"

static const CGFloat kDYYYGridSpacing = 12.0;
static const CGFloat kDYYYGridDragonSize = 76.0;
static const CGFloat kDYYYGridDragonTop = 10.0;
static const CGFloat kDYYYGridTopGap = 14.0; // 龙头底部到网格的距离

// 1.0.24：格子高度（72-120，默认 92，和 1.0.11 定的一样）/ 左右边距（0-48，默认 16）
// 改设置可调；格子底色（默认白色，金色是淡金底，深灰是深灰底；透明度另由格子透明度/微透明开关管）。
static CGFloat GHLQuickPanelCellHeight(void) {
    NSString *v = [[NSUserDefaults standardUserDefaults] stringForKey:GHL_KEY_QUICK_PANEL_CELL_HEIGHT];
    CGFloat f = v.length > 0 ? [v floatValue] : 92;
    if (f < 72) f = 72;
    if (f > 120) f = 120;
    return f;
}
static CGFloat GHLQuickPanelSideMargin(void) {
    NSString *v = [[NSUserDefaults standardUserDefaults] stringForKey:GHL_KEY_QUICK_PANEL_SIDE_MARGIN];
    CGFloat f = v.length > 0 ? [v floatValue] : 16;
    if (f < 0) f = 0;
    if (f > 48) f = 48;
    return f;
}
static UIColor *GHLQuickPanelCellBaseColor(void) {
    NSString *c = [[NSUserDefaults standardUserDefaults] stringForKey:GHL_KEY_QUICK_PANEL_CELL_COLOR] ?: @"白色";
    if ([c isEqualToString:@"金色"]) return [DYYYUtils dYYYGoldAccentColor];
    if ([c isEqualToString:@"深灰"]) return [UIColor colorWithWhite:0.2 alpha:1.0];
    return [UIColor whiteColor];
}

// 1.0.23 第二批：快捷面板外观（只用在长按网格面板表面，不动设置卡片）。
// 53 材质：磨砂 / 液态玻璃 / 清透玻璃（真液态玻璃是 iOS 26 的 UIGlassEffect，
// iOS 16.5 上用加厚材质＋淡白 tint 近似，见 GHLQuickPanelBlurStyle）。
static NSString *GHLQuickPanelMaterial(void) {
    NSString *m = [[NSUserDefaults standardUserDefaults] stringForKey:GHL_KEY_QUICK_PANEL_MATERIAL];
    return m.length > 0 ? m : @"磨砂";
}
// 54 排列：返回列数；横向等列返回 -1（横向单行，见 horizontalLayout）。
static NSInteger GHLQuickPanelColumns(void) {
    NSString *layout = [[NSUserDefaults standardUserDefaults] stringForKey:GHL_KEY_QUICK_PANEL_COLUMNS] ?: @"每排3个";
    if ([layout isEqualToString:@"每排2个"]) return 2;
    if ([layout isEqualToString:@"每排4个"]) return 4;
    if ([layout isEqualToString:@"横向等列"]) return -1;
    if ([layout isEqualToString:@"自定义"]) {
        NSInteger custom = [[[NSUserDefaults standardUserDefaults] stringForKey:GHL_KEY_QUICK_PANEL_COLUMNS_CUSTOM] integerValue];
        if (custom < 1) custom = 3;
        if (custom > 6) custom = 6;
        return custom;
    }
    return 3;
}
// 56 背景模糊度 0-100（默认 58，跟他演示的 58% 一致；实现成毛玻璃视图的 alpha）。
// 1.0.26：钳下限 20（防调到 0 全透，面板糊黑空）。
static CGFloat GHLQuickPanelBlurAmount(void) {
    NSString *v = [[NSUserDefaults standardUserDefaults] stringForKey:GHL_KEY_QUICK_PANEL_BLUR];
    if (!v || v.length == 0) return 58;
    CGFloat f = [v floatValue];
    if (f < 20) f = 20;
    if (f > 100) f = 100;
    return f;
}
static UIBlurEffectStyle GHLQuickPanelBlurStyle(BOOL *outLiquidTint) {
    NSString *m = GHLQuickPanelMaterial();
    if (outLiquidTint) *outLiquidTint = NO;
    if ([m isEqualToString:@"清透玻璃"]) return UIBlurEffectStyleSystemUltraThinMaterialLight;
    if ([m isEqualToString:@"液态玻璃"]) {
        if (outLiquidTint) *outLiquidTint = YES;
        return UIBlurEffectStyleSystemThickMaterial;
    }
    return UIBlurEffectStyleSystemMaterial; // 磨砂（默认）
}

@interface DYYYLongPressGridPanelView () <UIScrollViewDelegate, UIGestureRecognizerDelegate>

@property(nonatomic, copy) NSArray<NSDictionary *> *items;
@property(nonatomic, copy) void (^itemActionHandler)(NSInteger actionType, NSString *title);
@property(nonatomic, copy, nullable) void (^dismissHandler)(void);
@property(nonatomic, assign) BOOL didDismiss;
@property(nonatomic, strong, nullable) UIPanGestureRecognizer *dismissPan;

@property(nonatomic, strong) UIVisualEffectView *blurView;
@property(nonatomic, strong, nullable) UIView *backingView; // 1.0.26：不透浅色底板（实白），垫在毛玻璃下面
@property(nonatomic, strong, nullable) UIImageView *backgroundImageView; // 51 自选背景图（在毛玻璃下面，糊出来）
@property(nonatomic, strong, nullable) UIView *liquidTintView;           // 53 液态玻璃的淡白 tint
@property(nonatomic, strong) UIImageView *dragonImageView;
@property(nonatomic, strong) UIScrollView *gridScrollView;
@property(nonatomic, strong) NSMutableArray<UIButton *> *cells;
@property(nonatomic, assign) BOOL didLogLayout; // 1.0.26：layout 日志每面板只记一次
@property(nonatomic, assign) BOOL didLogSettings; // 1.0.27：设置日志每面板只记一次（设置没变就不重记）
@property(nonatomic, copy, nullable) NSString *lastSettingsMaterial; // 1.0.27：上次记过的面板设置（比对用）
@property(nonatomic, assign) CGFloat lastSettingsBlur;
@property(nonatomic, copy, nullable) NSString *lastSettingsCellColor;
@property(nonatomic, assign) CGFloat lastSettingsAlpha;
@property(nonatomic, assign) BOOL lastSettingsHasBG;
@property(nonatomic, strong, nullable) NSDate *bgCachedModDate; // 1.0.27：背景图文件上次读到的 mtime＋大小（没变就跳过重读）
@property(nonatomic, assign) unsigned long long bgCachedFileSize;
@property(nonatomic, assign) NSInteger gridColumns;     // 54 排列的列数（横向等列时为 4，仅作单行格宽参考）
@property(nonatomic, assign) BOOL horizontalLayout;     // 54 横向等列：单行横滑
@property(nonatomic, assign) CGFloat cellBackgroundAlpha; // 64 微透明：格子底透明度（默认 0.55，开了 0.40）

@end

@implementation DYYYLongPressGridPanelView

#pragma mark - 图标

// 按 actionType 找 SF Symbol（金色线条图标，和效果图一致）；找不到就按标题关键字兜底
// （1.0.15 起原生项也进网格，原生项没有约定的 actionType，按标题认图标）；
// 最后兜底下载图标。
// actionType 见 DYYYLongPressPanel.xm：666-679 是 DYYY 长按项，686-695 是顾海龙长按项。
+ (nullable UIImage *)ghl_iconForActionType:(NSInteger)actionType title:(nullable NSString *)title {
    NSArray<NSString *> *names = nil;
    switch (actionType) {
        case 666: names = @[ @"arrow.down.to.line", @"square.and.arrow.down" ]; break; // 保存视频
        case 679: names = @[ @"livephoto", @"photo" ]; break; // 保存实况
        case 669: names = @[ @"photo", @"image" ]; break; // 保存图片 / 保存当前图片
        case 670: names = @[ @"square.stack.3d.down.right", @"photo.on.rectangle.angled", @"photo" ]; break; // 保存所有图片 / 实况
        case 673: names = @[ @"icloud.and.arrow.down", @"cloud.download" ]; break; // 接口保存
        case 667: names = @[ @"photo", @"image" ]; break; // 保存封面
        case 668: names = @[ @"waveform", @"music.note" ]; break; // 保存音频
        case 677: names = @[ @"film", @"video" ]; break; // 制作视频
        case 671: names = @[ @"doc.on.doc", @"doc.text" ]; break; // 复制文案
        case 672: names = @[ @"link" ]; break; // 复制链接
        case 674: names = @[ @"person.crop.circle.badge.xmark", @"person.slash" ]; break; // 过滤用户
        case 675: names = @[ @"doc.text.magnifyingglass", @"text.magnifyingglass" ]; break; // 过滤文案
        case 676: names = @[ @"timer", @"clock" ]; break; // 定时关闭 / 取消定时
        case 686: names = @[ @"music.note", @"waveform" ]; break; // 提取原声
        case 687: names = @[ @"link.badge.plus", @"link" ]; break; // 复制无水印链接
        case 688: names = @[ @"rectangle.on.rectangle", @"pip" ]; break; // 画中画播放
        case 689: names = @[ @"speaker.wave.2", @"waveform" ]; break; // 语音包试听
        case 690: names = @[ @"square.and.arrow.up" ]; break; // 语音包读文案并分享
        case 691: names = @[ @"person.crop.circle", @"person" ]; break; // 保存头像
        case 692: names = @[ @"person.text.rectangle", @"person.crop.rectangle", @"person" ]; break; // 复制个人资料
        case 693: names = @[ @"square.and.arrow.up", @"music.note" ]; break; // 分享音频
        case 694: names = @[ @"chart.bar.doc.horizontal", @"doc.text" ]; break; // 获取作品数据
        case 695: names = @[ @"photo", @"eye" ]; break; // 图片预览
        default:
            // 未知 actionType（多半是抖音原生项）：按标题关键字认图标，认不出再兜底下载图标。
            // 1.0.16：原生标题补映射（之前 10/12 个原生标题全掉进下载箭头兜底，皇上不要统一箭头）——
            // 全用 SF Symbol，名字不存在时下面的循环会顺延到下一个候选再兜底下载箭头。
            if ([title containsString:@"倍速"]) names = @[ @"gauge", @"speedometer" ];
            else if ([title containsString:@"清屏播放"]) names = @[ @"rectangle.expand.vertical", @"arrow.up.left.and.arrow.down.right" ];
            else if ([title containsString:@"投屏"]) names = @[ @"tv", @"airplayvideo" ];
            else if ([title containsString:@"定时"]) names = @[ @"timer", @"clock" ];
            else if ([title containsString:@"合拍"]) names = @[ @"person.2", @"rectangle.on.rectangle" ];
            else if ([title containsString:@"识别图片"]) names = @[ @"viewfinder", @"photo" ];
            else if ([title containsString:@"稍后再看"]) names = @[ @"bookmark", @"clock" ];
            else if ([title containsString:@"缓存"]) names = @[ @"arrow.down.circle", @"tray.and.arrow.down" ];
            else if ([title containsString:@"电脑"] || [title containsString:@"Pad"]) names = @[ @"desktopcomputer", @"laptopcomputer" ];
            else if ([title containsString:@"弹幕"]) names = @[ @"text.bubble", @"captions.bubble" ];
            else if ([title containsString:@"推荐"]) names = @[ @"hand.thumbsup", @"star" ];
            else if ([title containsString:@"转发"]) names = @[ @"square.and.arrow.up" ];
            else if ([title containsString:@"自动连播"]) names = @[ @"repeat", @"play.fill" ];
            else if ([title containsString:@"后台音频"]) names = @[ @"speaker.wave.2", @"music.note" ];
            else if ([title containsString:@"后台小窗"]) names = @[ @"macwindow", @"rectangle.on.rectangle" ];
            else if ([title containsString:@"听抖音"]) names = @[ @"headphones", @"music.note" ];
            else if ([title containsString:@"不感兴趣"] || [title containsString:@"不喜欢"]) names = @[ @"eye.slash", @"hand.thumbsdown" ];
            else if ([title containsString:@"举报"]) names = @[ @"flag", @"exclamationmark.triangle" ];
            else if ([title containsString:@"收藏"]) names = @[ @"star", @"star.fill" ];
            else if ([title containsString:@"分享"]) names = @[ @"square.and.arrow.up" ];
            else if ([title containsString:@"屏蔽"] || [title containsString:@"拉黑"] || [title containsString:@"黑名单"]) names = @[ @"person.slash", @"nosign" ];
            else if ([title containsString:@"壁纸"]) names = @[ @"photo", @"image" ];
            else names = @[ @"square.and.arrow.down" ];
            break;
    }
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:28 weight:UIImageSymbolWeightRegular];
    for (NSString *name in names) {
        UIImage *image = [UIImage systemImageNamed:name withConfiguration:config];
        if (image) return image;
    }
    return [UIImage systemImageNamed:@"square.and.arrow.down" withConfiguration:config];
}

#pragma mark - 初始化

- (instancetype)initWithItems:(NSArray<NSDictionary *> *)items
            itemActionHandler:(void (^)(NSInteger actionType, NSString *title))itemActionHandler
               dismissHandler:(nullable void (^)(void))dismissHandler {
    self = [super initWithFrame:CGRectZero];
    if (!self) return nil;
    _items = [items copy];
    _itemActionHandler = [itemActionHandler copy];
    _dismissHandler = [dismissHandler copy];
    _cells = [NSMutableArray array];
    _didLogLayout = NO;
    _didLogSettings = NO; // 1.0.27：设置日志每面板只记一次，实例新建时清零

    self.backgroundColor = [UIColor clearColor];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    // 1.0.23 第二批：54 排列（列数在 init 时读一次；横向等列 = 单行横滑）。
    NSInteger columns = GHLQuickPanelColumns();
    _horizontalLayout = (columns == -1);
    _gridColumns = _horizontalLayout ? 4 : columns;
    // 64 长按菜单微透明：格子底从 0.55 降到 0.40。
    // 1.0.24：格子透明度填了就按填的（0.1-1.0），没填才跟微透明开关。
    NSString *cellAlphaValue = [[NSUserDefaults standardUserDefaults] stringForKey:GHL_KEY_QUICK_PANEL_CELL_ALPHA];
    if (cellAlphaValue.length > 0) {
        CGFloat a = [cellAlphaValue floatValue];
        if (a < 0.1) a = 0.1;
        if (a > 1.0) a = 1.0;
        _cellBackgroundAlpha = a;
    } else {
        _cellBackgroundAlpha = GHLGetBool(GHL_KEY_LONG_PRESS_PANEL_TRANSLUCENT) ? 0.40 : 0.55;
    }

    // 1.0.26：不透浅色底板（实白）垫在毛玻璃下面——面板自己没有实底色，底色全靠毛玻璃糊
    // 背后的东西；1.0.24 藏表后背后只剩没设颜色的黑空，糊出来就是黑。有了这层底，
    // 底板永远是亮的，藏表照样藏、重影照样不回来。
    _backingView = [[UIView alloc] init];
    _backingView.backgroundColor = [UIColor whiteColor];
    _backingView.userInteractionEnabled = NO;
    _backingView.layer.cornerRadius = 24;
    _backingView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    _backingView.layer.masksToBounds = YES;
    _backingView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_backingView];

    // 51 自选背景图（在毛玻璃下面，糊出来；没选就只有毛玻璃）。
    UIImage *panelBG = GHLCustomQuickPanelBackgroundImage();
    if (panelBG) {
        _backgroundImageView = [[UIImageView alloc] initWithImage:panelBG];
        _backgroundImageView.contentMode = UIViewContentModeScaleAspectFill;
        _backgroundImageView.clipsToBounds = YES;
        _backgroundImageView.layer.cornerRadius = 24;
        _backgroundImageView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        _backgroundImageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_backgroundImageView];
    }

    // 浅色毛玻璃底板（1.0.22：SystemMaterialLight 太实、渲染出来像平灰块，换更透的 ExtraLight，
    // 和卡片壳同款；格子底还是半透明白，字要看得清）。
    // 1.0.23 第二批：53 材质三选一（磨砂/液态玻璃/清透玻璃）＋56 背景模糊度（毛玻璃 alpha）。
    BOOL liquidTint = NO;
    UIBlurEffectStyle panelStyle = GHLQuickPanelBlurStyle(&liquidTint);
    _blurView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:panelStyle]];
    _blurView.alpha = GHLQuickPanelBlurAmount() / 100.0;
    _blurView.userInteractionEnabled = NO;
    _blurView.layer.cornerRadius = 24;
    _blurView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    _blurView.layer.masksToBounds = YES;
    _blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_blurView];
    if (liquidTint) {
        // 液态玻璃近似：淡白 tint 盖在加厚糊上，带一点水光感（真 UIGlassEffect 要 iOS 26）。
        _liquidTintView = [[UIView alloc] init];
        _liquidTintView.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.10];
        _liquidTintView.userInteractionEnabled = NO;
        _liquidTintView.layer.cornerRadius = 24;
        _liquidTintView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
        _liquidTintView.layer.masksToBounds = YES;
        _liquidTintView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        [self addSubview:_liquidTintView];
    }

    // 龙头：复用设置页头卡同一张图（GHLLogoImage()，含用户自选龙头），圆形 + 金边。
    _dragonImageView = [[UIImageView alloc] initWithImage:GHLLogoImage()];
    _dragonImageView.contentMode = UIViewContentModeScaleAspectFill;
    _dragonImageView.layer.cornerRadius = kDYYYGridDragonSize / 2;
    _dragonImageView.layer.masksToBounds = YES;
    _dragonImageView.layer.borderWidth = 2;
    _dragonImageView.layer.borderColor = [DYYYUtils dYYYGoldAccentColor].CGColor;
    _dragonImageView.accessibilityLabel = @"顾海龙抖音";
    [self addSubview:_dragonImageView];

    _gridScrollView = [[UIScrollView alloc] initWithFrame:CGRectZero];
    _gridScrollView.showsVerticalScrollIndicator = YES; // 1.0.11：下面还有格子时一眼能看出来
    _gridScrollView.showsHorizontalScrollIndicator = NO;
    _gridScrollView.delegate = self; // 1.0.16：滚动吸附（scrollViewWillEndDragging 里对齐行高，不留半行）
    [self addSubview:_gridScrollView];

    // 网格格子：每格一个圆角浅色半透明底 + 细亮边 + 金色图标 + 深色字标题。
    // 1.0.21：深色改浅色（和卡片首页／关于页同款）。
    // 1.0.15：没有「更多」格了——items 里就是全部项（自定义＋原生），有几项就出几格；
    // 超出 4 行时纵向滚动（scrollView 带滚动条），不截断。
    UIColor *gold = [DYYYUtils dYYYGoldAccentColor];
    NSInteger totalCells = (NSInteger)items.count;
    for (NSInteger i = 0; i < totalCells; i++) {
        NSString *title = items[i][@"title"];
        NSInteger actionType = [items[i][@"actionType"] integerValue];
        if (!title || title.length == 0) title = @"未命名";

        UIButton *cell = [UIButton buttonWithType:UIButtonTypeCustom];
        // 1.0.24：格子底色按设置来（白色/金色/深灰），透明度另管。
        cell.backgroundColor = [GHLQuickPanelCellBaseColor() colorWithAlphaComponent:self.cellBackgroundAlpha];
        cell.layer.cornerRadius = 16;
        cell.layer.masksToBounds = YES;
        cell.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.6].CGColor;
        cell.layer.borderWidth = 0.6;
        cell.accessibilityLabel = title;
        cell.tag = i; // 格子序号：点按时按序号找回 items 里的标题和 actionType。

        UIImageView *iconView = [[UIImageView alloc] init];
        iconView.contentMode = UIViewContentModeScaleAspectFit;
        iconView.tintColor = gold;
        iconView.image = [[self class] ghl_iconForActionType:actionType title:title];
        iconView.tag = 1001;
        [cell addSubview:iconView];

        UILabel *label = [[UILabel alloc] init];
        label.text = title;
        label.textColor = [UIColor colorWithWhite:0.15 alpha:1.0];
        label.font = [UIFont systemFontOfSize:13];
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 1;
        label.tag = 1002;
        [cell addSubview:label];

        [cell addTarget:self action:@selector(ghl_cellTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_gridScrollView addSubview:cell];
        [_cells addObject:cell];
    }

    // 下滑收起（原生面板点空白处/下滑也能收；我们盖住了面板，下滑手势自己补一个）。
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(ghl_pan:)];
    pan.delegate = self; // 1.0.16：列表滑到下面时往下拖是翻列表，不是收起（见 gestureRecognizerShouldBegin）
    [self addGestureRecognizer:pan];
    self.dismissPan = pan;
    return self;
}

#pragma mark - 建议的 sheet 高度

// 1.0.16：首屏露 5 行（再多就快佔滿屏了；行數少就按實際行數算，不留空）。
// 数字和 layoutSubviews 里的同一套：龙头区 10+76+14，行高 92、间距 12，底部留 16。
// 1.0.23 第二批：54 横向等列只 1 行（横滑），列数按当前设置算。
+ (CGFloat)ghl_preferredSheetHeightForItemCount:(NSInteger)count safeAreaBottom:(CGFloat)safeAreaBottom {
    NSInteger columns = GHLQuickPanelColumns();
    NSInteger rows;
    if (columns == -1) {
        rows = 1; // 横向等列：单行横滑
    } else {
        rows = (NSInteger)ceil((double)MAX(count, 0) / (double)columns);
    }
    NSInteger visibleRows = MIN(rows, 5);
    CGFloat height = kDYYYGridDragonTop + kDYYYGridDragonSize + kDYYYGridTopGap
        + visibleRows * GHLQuickPanelCellHeight()
        + (visibleRows > 0 ? (visibleRows - 1) * kDYYYGridSpacing : 0)
        + 16 + safeAreaBottom;
    return height;
}

#pragma mark - 布局

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    if (bounds.size.width <= 0) return;
    // 1.0.27：格子保险——格子不在滚动区里时点按和渲染都没它，先补加回去。
    for (UIButton *cell in self.cells) {
        if (cell.superview != self.gridScrollView) [self.gridScrollView addSubview:cell];
    }
    self.blurView.frame = bounds;
    if (self.backingView) self.backingView.frame = bounds;
    if (self.backgroundImageView) self.backgroundImageView.frame = bounds;
    if (self.liquidTintView) self.liquidTintView.frame = bounds;

    // 龙头居中在面板顶部。
    self.dragonImageView.frame = CGRectMake((bounds.size.width - kDYYYGridDragonSize) / 2, kDYYYGridDragonTop, kDYYYGridDragonSize, kDYYYGridDragonSize);

    CGFloat gridTop = kDYYYGridDragonTop + kDYYYGridDragonSize + kDYYYGridTopGap;
    CGFloat bottomInset = 0;
    if (@available(iOS 11.0, *)) {
        bottomInset = self.safeAreaInsets.bottom;
    }
    CGFloat gridHeight = bounds.size.height - gridTop - bottomInset - 16;
    if (gridHeight < 0) gridHeight = 0;
    self.gridScrollView.frame = CGRectMake(0, gridTop, bounds.size.width, gridHeight);

    // 1.0.23 第二批：54 排列——列数按设置来；横向等列是单行横滑（格子按格子高度宽，横向滚）。
    NSInteger columns = self.gridColumns;
    if (self.horizontalLayout) {
        CGFloat cellWidth = GHLQuickPanelCellHeight();
        CGFloat contentWidth = self.cells.count * cellWidth + (self.cells.count > 0 ? (self.cells.count - 1) * kDYYYGridSpacing : 0) + GHLQuickPanelSideMargin() * 2;
        self.gridScrollView.contentSize = CGSizeMake(MAX(contentWidth, bounds.size.width), GHLQuickPanelCellHeight());
        // 1.0.24：格子改高了图标/标题才居中（92 时保持原来 16/50，一点不动）。
        CGFloat iconY = (GHLQuickPanelCellHeight() <= 92.0) ? 16 : (GHLQuickPanelCellHeight() - 52) / 2;
        for (NSInteger i = 0; i < (NSInteger)self.cells.count; i++) {
            UIButton *cell = self.cells[i];
            CGFloat x = GHLQuickPanelSideMargin() + i * (cellWidth + kDYYYGridSpacing);
            cell.frame = CGRectMake(x, 0, cellWidth, GHLQuickPanelCellHeight());
            UIImageView *iconView = [cell viewWithTag:1001];
            UILabel *label = [cell viewWithTag:1002];
            iconView.frame = CGRectMake((cellWidth - 28) / 2, iconY, 28, 28);
            label.frame = CGRectMake(4, iconY + 34, cellWidth - 8, 18);
        }
        [self ghl_logLayoutOnce];
        return;
    }
    CGFloat cellWidth = (bounds.size.width - GHLQuickPanelSideMargin() * 2 - kDYYYGridSpacing * (columns - 1)) / columns;
    NSInteger rows = (NSInteger)ceil((double)self.cells.count / (double)columns);
    CGFloat contentHeight = rows * GHLQuickPanelCellHeight() + (rows > 0 ? (rows - 1) * kDYYYGridSpacing : 0);
    self.gridScrollView.contentSize = CGSizeMake(bounds.size.width, contentHeight);
    // 1.0.24：格子改高了图标/标题才居中（92 时保持原来 16/50，一点不动）。
    CGFloat iconY = (GHLQuickPanelCellHeight() <= 92.0) ? 16 : (GHLQuickPanelCellHeight() - 52) / 2;

    for (NSInteger i = 0; i < (NSInteger)self.cells.count; i++) {
        NSInteger row = i / columns;
        NSInteger col = i % columns;
        CGFloat x = GHLQuickPanelSideMargin() + col * (cellWidth + kDYYYGridSpacing);
        CGFloat y = row * (GHLQuickPanelCellHeight() + kDYYYGridSpacing);
        UIButton *cell = self.cells[i];
        cell.frame = CGRectMake(x, y, cellWidth, GHLQuickPanelCellHeight());
        // 图标在上、标题在下（和效果图一致）。
        UIImageView *iconView = [cell viewWithTag:1001];
        UILabel *label = [cell viewWithTag:1002];
        iconView.frame = CGRectMake((cellWidth - 28) / 2, iconY, 28, 28);
        label.frame = CGRectMake(4, iconY + 34, cellWidth - 8, 18);
    }
    [self ghl_logLayoutOnce];
}

#pragma mark - 1.0.26：面板设置日志 / 背景图刷新

// Show 时记一行解析到的面板设置（材质/模糊度/格子颜色/透明度/背景图有无），下次日志不用猜。
// 1.0.27：每面板实例只记一次；设置没变就不重记（Show 在 sheet 动画期间每帧都调，
// -15.log 里一行设置日志刷了约 83 次）。
- (void)ghl_logResolvedSettings {
    NSString *cellColor = [[NSUserDefaults standardUserDefaults] stringForKey:GHL_KEY_QUICK_PANEL_CELL_COLOR] ?: @"白色";
    NSString *material = GHLQuickPanelMaterial();
    CGFloat blur = GHLQuickPanelBlurAmount();
    BOOL hasBG = self.backgroundImageView != nil;
    if (self.didLogSettings
        && [material isEqualToString:self.lastSettingsMaterial]
        && blur == self.lastSettingsBlur
        && [cellColor isEqualToString:self.lastSettingsCellColor]
        && self.cellBackgroundAlpha == self.lastSettingsAlpha
        && hasBG == self.lastSettingsHasBG) {
        return;
    }
    self.didLogSettings = YES;
    self.lastSettingsMaterial = material;
    self.lastSettingsBlur = blur;
    self.lastSettingsCellColor = cellColor;
    self.lastSettingsAlpha = self.cellBackgroundAlpha;
    self.lastSettingsHasBG = hasBG;
    GHLLog(@"长按面板：材质=%@，模糊度=%.0f，格子颜色=%@，格子透明度=%.2f，背景图=%@",
           material, blur, cellColor, self.cellBackgroundAlpha,
           hasBG ? @"有" : @"无");
}

// 每面板只记一次 bounds＋首格 frame（格子看不见时，日志能定论是布局还是渲染问题）。
// 1.0.27：扩展成可见性诊断行——除 bounds＋首格 frame 外，再记 window、superview 是否等于
// 当前面板页（vc 指针也记）、hidden、alpha、滚动区实际子视图数 vs 格子数；bounds 还没
// 有效尺寸时不记（Show 在 viewDidLoad 里调时宽可能是 0，记了就把唯一一次机会占了）。
- (void)ghl_logLayoutOnce {
    if (self.didLogLayout || self.cells.count == 0) return;
    if (self.bounds.size.width <= 0) return;
    self.didLogLayout = YES;
    UIViewController *hostVC = self.ghl_hostVC;
    GHLLog(@"长按面板：bounds=%@，首格 frame=%@，window=%@，superview 是当前面板页=%@（vc=%p），hidden=%@，alpha=%.2f，滚动区子视图 %lu／格子 %lu",
           NSStringFromCGRect(self.bounds), NSStringFromCGRect(self.cells[0].frame),
           self.window ? @"有" : @"无",
           (hostVC && self.superview == hostVC.view) ? @"是" : @"否", hostVC,
           self.hidden ? @"是" : @"否", self.alpha,
           (unsigned long)self.gridScrollView.subviews.count, (unsigned long)self.cells.count);
}

// 每次 Show 都刷新背景图：只在 init 读一次时，换图后旧面板一直沿用旧图（1.0.24 换图失败的主因）。
// 1.0.27：文件没变就跳过重读（Show 在 sheet 动画期间每帧都调一次，每次都解一次 JPEG 是浪费；
// 只比文件 mtime＋大小，换图后 mtime 会变，照样能刷到新图）。
- (void)ghl_refreshBackgroundImage {
    NSString *path = GHLCustomQuickPanelBackgroundPath();
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    NSDate *modDate = attrs[NSFileModificationDate];
    unsigned long long fileSize = [attrs[NSFileSize] unsignedLongLongValue];
    if (self.backgroundImageView && modDate && self.bgCachedModDate
        && [self.bgCachedModDate isEqualToDate:modDate] && self.bgCachedFileSize == fileSize) {
        return; // 文件没变，图已经在位
    }
    UIImage *panelBG = GHLCustomQuickPanelBackgroundImage();
    if (panelBG) {
        if (self.backgroundImageView) {
            self.backgroundImageView.image = panelBG;
        } else {
            UIImageView *iv = [[UIImageView alloc] initWithImage:panelBG];
            iv.contentMode = UIViewContentModeScaleAspectFill;
            iv.clipsToBounds = YES;
            iv.layer.cornerRadius = 24;
            iv.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
            iv.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            iv.frame = self.bounds;
            // 插在底板上面、毛玻璃下面。
            if (self.backingView) [self insertSubview:iv aboveSubview:self.backingView];
            else [self insertSubview:iv atIndex:0];
            _backgroundImageView = iv;
        }
    } else if (self.backgroundImageView) {
        [self.backgroundImageView removeFromSuperview];
        self.backgroundImageView = nil;
    }
    self.bgCachedModDate = modDate;
    self.bgCachedFileSize = fileSize;
}

#pragma mark - 交互

- (void)ghl_cellTapped:(UIButton *)sender {
    if (sender.tag < 0 || sender.tag >= (NSInteger)self.items.count) return;
    NSDictionary *item = self.items[sender.tag];
    // 1.0.16：点按入口记一行——之前整个文件一个 GHLLog 都没有，点了没反应时日志里什么都看不出来。
    GHLLog(@"长按面板：网格点按 actionType %ld「%@」", (long)[item[@"actionType"] integerValue], item[@"title"] ?: @"");
    if (self.itemActionHandler) {
        // 标题和 actionType 一起交出去：Hook 方按两个条件找回原 viewModel，
        // 原生项和自定义项 actionType 万一撞号也不会点错。
        self.itemActionHandler([item[@"actionType"] integerValue], item[@"title"]);
    }
}

- (void)ghl_pan:(UIPanGestureRecognizer *)pan {
    if (self.didDismiss) return;
    if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        CGPoint translation = [pan translationInView:self];
        CGPoint velocity = [pan velocityInView:self];
        if (translation.y > 60 || velocity.y > 600) {
            self.didDismiss = YES;
            if (self.dismissHandler) {
                self.dismissHandler();
            }
        }
    }
}

#pragma mark - UIScrollViewDelegate / UIGestureRecognizerDelegate（1.0.16）

// 滚动吸附：停下时对齐到行高，不留半行（28 项 10 行时第四行被切一半就是这么来的）。
// 1.0.23 第二批：54 横向等列是横滑，改对齐横向偏移。
- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset {
    if (scrollView != self.gridScrollView) return;
    CGFloat pitch = GHLQuickPanelCellHeight() + kDYYYGridSpacing;
    if (self.horizontalLayout) {
        CGFloat maxOffset = MAX(0, scrollView.contentSize.width - scrollView.bounds.size.width);
        CGFloat snapped = round(targetContentOffset->x / pitch) * pitch;
        targetContentOffset->x = MIN(MAX(snapped, 0), maxOffset);
        return;
    }
    CGFloat maxOffset = MAX(0, scrollView.contentSize.height - scrollView.bounds.size.height);
    CGFloat snapped = round(targetContentOffset->y / pitch) * pitch;
    targetContentOffset->y = MIN(MAX(snapped, 0), maxOffset);
}

// 下滑收起只在列表顶端才认：滑到下面时往下拖是翻列表，不是收起（修快滑误收起）。
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer == self.dismissPan) {
        return self.gridScrollView.contentOffset.y <= 0;
    }
    return YES;
}

// 下滑收起和列表滑动可以同时认（都在顶端往下拖时，列表回弹、面板收起，各干各的）。
- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if (otherGestureRecognizer == self.gridScrollView.panGestureRecognizer) return YES;
    return NO;
}

@end
