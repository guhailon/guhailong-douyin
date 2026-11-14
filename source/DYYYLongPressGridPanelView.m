// 顾海龙抖音长按下载面板：网格风格（1.0.9）
// 浅色毛玻璃底板 + 三列金色图标网格 + 顶部金色龙头（复用 GHLLogoImage()，圆形金边，和设置页头卡同一套）。
// 1.0.21：深色改浅色（和卡片首页／关于页同款 iOS 文件夹式浅色玻璃）。
// 效果图：workspace/imagine_media/media-generation-download-menu-grid-dragon-0-168c78e9-fb05-4e57-8b23-f8476d304c10.webp
// 与效果图的一处差别：龙头没有探出面板顶边（贴边 10pt 放在毛玻璃里），避免 sheet 容器裁切导致龙头被切一半。
// 1.0.15：没有「更多」了——自定义项和抖音原生项全在网格里，长按只出网格，不再回到原生列表页。
#import "DYYYLongPressGridPanelView.h"
#import "DYYYUtils.h"
#import "GHLFeatures.h"

static const NSInteger kDYYYGridColumns = 3;
static const CGFloat kDYYYGridSideMargin = 16.0;
static const CGFloat kDYYYGridSpacing = 12.0;
static const CGFloat kDYYYGridCellHeight = 92.0; // 1.0.11：104 收小到 92，4 行在 iPhone 11 的 sheet 里基本不用滑也能看到
static const CGFloat kDYYYGridDragonSize = 76.0;
static const CGFloat kDYYYGridDragonTop = 10.0;
static const CGFloat kDYYYGridTopGap = 14.0; // 龙头底部到网格的距离

@interface DYYYLongPressGridPanelView () <UIScrollViewDelegate, UIGestureRecognizerDelegate>

@property(nonatomic, copy) NSArray<NSDictionary *> *items;
@property(nonatomic, copy) void (^itemActionHandler)(NSInteger actionType, NSString *title);
@property(nonatomic, copy, nullable) void (^dismissHandler)(void);
@property(nonatomic, assign) BOOL didDismiss;
@property(nonatomic, strong, nullable) UIPanGestureRecognizer *dismissPan;

@property(nonatomic, strong) UIVisualEffectView *blurView;
@property(nonatomic, strong) UIImageView *dragonImageView;
@property(nonatomic, strong) UIScrollView *gridScrollView;
@property(nonatomic, strong) NSMutableArray<UIButton *> *cells;

@end

@implementation DYYYLongPressGridPanelView

#pragma mark - 图标

// 按 actionType 找 SF Symbol（金色线条图标，和效果图一致）；找不到就按标题关键字兜底
// （1.0.15 起原生项也进网格，原生项没有约定的 actionType，按标题认图标）；
// 最后兜底下载图标。
// actionType 见 DYYYLongPressPanel.xm：666-679 是 DYYY 长按项，686-693 是顾海龙长按项。
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

    self.backgroundColor = [UIColor clearColor];
    self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    // 浅色毛玻璃底板（1.0.22：SystemMaterialLight 太实、渲染出来像平灰块，换更透的 ExtraLight，
    // 和卡片壳同款；格子底还是半透明白，字要看得清）。
    _blurView = [[UIVisualEffectView alloc] initWithEffect:[UIBlurEffect effectWithStyle:UIBlurEffectStyleExtraLight]];
    _blurView.userInteractionEnabled = NO;
    _blurView.layer.cornerRadius = 24;
    _blurView.layer.maskedCorners = kCALayerMinXMinYCorner | kCALayerMaxXMinYCorner;
    _blurView.layer.masksToBounds = YES;
    _blurView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:_blurView];

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
        cell.backgroundColor = [[UIColor whiteColor] colorWithAlphaComponent:0.55];
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
+ (CGFloat)ghl_preferredSheetHeightForItemCount:(NSInteger)count safeAreaBottom:(CGFloat)safeAreaBottom {
    NSInteger rows = (NSInteger)ceil((double)MAX(count, 0) / (double)kDYYYGridColumns);
    NSInteger visibleRows = MIN(rows, 5);
    CGFloat height = kDYYYGridDragonTop + kDYYYGridDragonSize + kDYYYGridTopGap
        + visibleRows * kDYYYGridCellHeight
        + (visibleRows > 0 ? (visibleRows - 1) * kDYYYGridSpacing : 0)
        + 16 + safeAreaBottom;
    return height;
}

#pragma mark - 布局

- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    if (bounds.size.width <= 0) return;
    self.blurView.frame = bounds;

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

    // 三列网格。
    CGFloat cellWidth = (bounds.size.width - kDYYYGridSideMargin * 2 - kDYYYGridSpacing * (kDYYYGridColumns - 1)) / kDYYYGridColumns;
    NSInteger rows = (NSInteger)ceil((double)self.cells.count / (double)kDYYYGridColumns);
    CGFloat contentHeight = rows * kDYYYGridCellHeight + (rows > 0 ? (rows - 1) * kDYYYGridSpacing : 0);
    self.gridScrollView.contentSize = CGSizeMake(bounds.size.width, contentHeight);

    for (NSInteger i = 0; i < (NSInteger)self.cells.count; i++) {
        NSInteger row = i / kDYYYGridColumns;
        NSInteger col = i % kDYYYGridColumns;
        CGFloat x = kDYYYGridSideMargin + col * (cellWidth + kDYYYGridSpacing);
        CGFloat y = row * (kDYYYGridCellHeight + kDYYYGridSpacing);
        UIButton *cell = self.cells[i];
        cell.frame = CGRectMake(x, y, cellWidth, kDYYYGridCellHeight);
        // 图标在上、标题在下（和效果图一致）。
        UIImageView *iconView = [cell viewWithTag:1001];
        UILabel *label = [cell viewWithTag:1002];
        iconView.frame = CGRectMake((cellWidth - 28) / 2, 16, 28, 28);
        label.frame = CGRectMake(4, 50, cellWidth - 8, 18);
    }
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
- (void)scrollViewWillEndDragging:(UIScrollView *)scrollView withVelocity:(CGPoint)velocity targetContentOffset:(inout CGPoint *)targetContentOffset {
    if (scrollView != self.gridScrollView) return;
    CGFloat pitch = kDYYYGridCellHeight + kDYYYGridSpacing;
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
