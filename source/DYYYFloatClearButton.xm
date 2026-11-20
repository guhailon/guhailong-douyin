/*
 * Tweak Name: 1KeyHideDYUI
 * Target App: com.ss.iphone.ugc.Aweme
 * Dev: @c00kiec00k 曲奇的坏品味🍻
 * iOS Version: 16.5
 */
#import "DYYYFloatSpeedButton.h"
#import "DYYYFloatClearButton.h"
#import "DYYYConstants.h"
#import "DYYYUtils.h"
#import "GHLFeatures.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <float.h>
#import <math.h>
#import <objc/runtime.h>
#import <signal.h>

static const CGFloat kDYYYClearButtonEdgeInset = 8.0;
static const CGFloat kDYYYClearButtonDefaultYFromBottomPercent = 0.75;

typedef NS_ENUM(NSInteger, DYYYClearButtonEdge) {
    DYYYClearButtonEdgeLeft = 0,
    DYYYClearButtonEdgeRight,
    DYYYClearButtonEdgeTop,
    DYYYClearButtonEdgeBottom,
};

@interface HideUIButton ()
@property(nonatomic, assign) DYYYClearButtonEdge dyyyActiveDragEdge;
@property(nonatomic, assign) BOOL manualClearActive;
- (void)updateClearState;
@property(nonatomic, strong) NSHashTable<UIView *> *progressViews;
@property(nonatomic, strong) NSMapTable<Class, NSNumber *> *classifications;
@property(nonatomic, strong) NSSet<NSString *> *targetNames;
@property(nonatomic, assign) BOOL needsDiscovery;
@property(nonatomic, assign) BOOL refreshScheduled;
- (void)invalidateTargetCache;
- (void)restoreCachedTargetViews;
@end

BOOL dyyyIsPerformingFloatClearOperation = NO;
// v3.0 共享显示标志：由 DYYY.xm 的页面钩子与 App 生命周期通知维护。
BOOL isInPlayInteractionVC = NO;
BOOL isPureViewVisible = NO;
BOOL clearButtonForceHidden = NO;
BOOL isAppActive = YES;
BOOL isAppInTransition = NO;

static NSInteger dyyyClearButtonMutationDepth = 0;

static inline void DYYYBeginClearButtonMutation(void) {
    dyyyClearButtonMutationDepth++;
    dyyyIsPerformingFloatClearOperation = YES;
}

static inline void DYYYEndClearButtonMutation(void) {
    if (dyyyClearButtonMutationDepth > 0) {
        dyyyClearButtonMutationDepth--;
    }
    dyyyIsPerformingFloatClearOperation = dyyyClearButtonMutationDepth > 0;
}

static void DYYYPerformClearButtonMutation(dispatch_block_t block) {
    if (!block) {
        return;
    }
    DYYYBeginClearButtonMutation();
    @try {
        block();
    } @finally {
        DYYYEndClearButtonMutation();
    }
}


HideUIButton *hideButton = nil;
NSArray *targetClassNames;
static NSUInteger dyyyTargetClassConfiguration = NSUIntegerMax;

typedef NS_ENUM(NSInteger, DYYYClearProgressMode) {
    DYYYClearProgressModeNone = 0,
    DYYYClearProgressModeRemove,
    DYYYClearProgressModeHide,
};

// 清屏隐藏状态栏：遍历所有 window 的 VC 层级，触发系统重新评估状态栏显隐
static void DYYYRefreshStatusBarVisibility(void) {
    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideStatusBarOnClear"] ||
        [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideStatusbar"]) {
        return;
    }
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        UIViewController *rootVC = window.rootViewController;
        if (!rootVC) continue;
        [rootVC setNeedsStatusBarAppearanceUpdate];
        for (UIViewController *child in rootVC.childViewControllers) {
            [child setNeedsStatusBarAppearanceUpdate];
        }
    }
}

static char dyyyProgressModeKey;
static char dyyyProgressOriginalHiddenKey;
static char dyyyProgressOriginalInteractionKey;
static char dyyyProgressOriginalLayerOpacityKey;
char dyyyClearOriginalAlphaKey;
static char dyyyClearOriginalHiddenKey;
static char dyyyClearStateCapturedKey;

// AWEAwemePlayVideoPauseIcon 的 alpha 由抖音业务层动态控制（播放=0、暂停=1），
// 对这类视图使用 hidden 属性隐藏而非修改 alpha，避免与业务层 alpha 控制冲突。
BOOL DYYYIsDynamicAlphaView(UIView *view) {
    static Class pauseIconClass = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        pauseIconClass = NSClassFromString(@"AWEAwemePlayVideoPauseIcon");
    });
    return pauseIconClass && [view isKindOfClass:pauseIconClass];
}

static BOOL DYYYHasCapturedClearTargetViewState(UIView *view) {
    return view && objc_getAssociatedObject(view, &dyyyClearStateCapturedKey) != nil;
}

static void DYYYCaptureClearTargetViewStateIfNeeded(UIView *view) {
    if (!view || DYYYHasCapturedClearTargetViewState(view)) {
        return;
    }

    objc_setAssociatedObject(view, &dyyyClearStateCapturedKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &dyyyClearOriginalAlphaKey, @(view.alpha), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &dyyyClearOriginalHiddenKey, @(view.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

void DYYYApplyClearTargetViewHiddenState(UIView *view) {
    if (!view) {
        return;
    }

    DYYYCaptureClearTargetViewStateIfNeeded(view);
    if (DYYYIsDynamicAlphaView(view)) {
        if (!view.hidden) view.hidden = YES;
    } else if (view.alpha != 0) {
        view.alpha = 0.0;
    }
}

void DYYYRestoreClearTargetViewStateIfNeeded(UIView *view) {
    if (!view || !DYYYHasCapturedClearTargetViewState(view)) {
        return;
    }

    NSNumber *originalHidden = objc_getAssociatedObject(view, &dyyyClearOriginalHiddenKey);
    NSNumber *originalAlpha = objc_getAssociatedObject(view, &dyyyClearOriginalAlphaKey);
    if (originalHidden) {
        view.hidden = originalHidden.boolValue;
    }
    if (originalAlpha) {
        view.alpha = originalAlpha.floatValue;
    }

    objc_setAssociatedObject(view, &dyyyClearOriginalHiddenKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(view, &dyyyClearOriginalAlphaKey, nil, OBJC_ASSOCIATION_ASSIGN);
    objc_setAssociatedObject(view, &dyyyClearStateCapturedKey, nil, OBJC_ASSOCIATION_ASSIGN);
}

static DYYYClearProgressMode DYYYCurrentClearProgressMode(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults boolForKey:@"DYYYRemoveTimeProgress"]) {
        return DYYYClearProgressModeRemove;
    }
    if ([defaults boolForKey:@"DYYYHideTimeProgress"]) {
        return DYYYClearProgressModeHide;
    }
    return DYYYClearProgressModeNone;
}

static BOOL DYYYIsClearProgressView(UIView *view) {
    static NSArray<NSString *> *classNames;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
      classNames = @[
          @"AWEPlayInteractionProgressContainerView",
          @"AWEDPlayerProgressContainerView",
          @"AWEFeedProgressSlider",
          @"AWEFeedProgressSliderForLongPress",
          @"AWEFakeProgressSliderView",
          @"AWEProgressContainerView",
          @"AWEProgressPlayBackSlider",
      ];
    });

    for (NSString *className in classNames) {
        Class progressClass = NSClassFromString(className);
        if (progressClass && [view isKindOfClass:progressClass]) {
            return YES;
        }
    }
    return NO;
}

static void DYYYRestoreClearProgressViewState(UIView *view) {
    NSNumber *appliedMode = objc_getAssociatedObject(view, &dyyyProgressModeKey);
    if (!appliedMode) {
        return;
    }

    NSNumber *originalLayerOpacity = objc_getAssociatedObject(view, &dyyyProgressOriginalLayerOpacityKey);
    if (originalLayerOpacity) {
        view.layer.opacity = originalLayerOpacity.floatValue;
    }

    if (appliedMode.integerValue == DYYYClearProgressModeRemove) {
        NSNumber *originalHidden = objc_getAssociatedObject(view, &dyyyProgressOriginalHiddenKey);
        NSNumber *originalInteraction = objc_getAssociatedObject(view, &dyyyProgressOriginalInteractionKey);
        if (originalHidden) {
            view.hidden = originalHidden.boolValue;
        }
        if (originalInteraction) {
            view.userInteractionEnabled = originalInteraction.boolValue;
        }
    }

    objc_setAssociatedObject(view, &dyyyProgressModeKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &dyyyProgressOriginalHiddenKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &dyyyProgressOriginalInteractionKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    objc_setAssociatedObject(view, &dyyyProgressOriginalLayerOpacityKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

static void DYYYApplyClearProgressViewState(UIView *view, DYYYClearProgressMode mode) {
    NSNumber *appliedMode = objc_getAssociatedObject(view, &dyyyProgressModeKey);
    if (appliedMode && appliedMode.integerValue != mode) {
        DYYYRestoreClearProgressViewState(view);
        appliedMode = nil;
    }

    if (mode == DYYYClearProgressModeNone) {
        DYYYRestoreClearProgressViewState(view);
        return;
    }

    if (!appliedMode) {
        objc_setAssociatedObject(view, &dyyyProgressModeKey, @(mode), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(view, &dyyyProgressOriginalLayerOpacityKey, @(view.layer.opacity), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        if (mode == DYYYClearProgressModeRemove) {
            objc_setAssociatedObject(view, &dyyyProgressOriginalHiddenKey, @(view.hidden), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
            objc_setAssociatedObject(view, &dyyyProgressOriginalInteractionKey, @(view.userInteractionEnabled), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        }
    }

    view.layer.opacity = 0.0f;
    if (mode == DYYYClearProgressModeRemove) {
        view.hidden = YES;
        view.userInteractionEnabled = NO;
    }
}

void DYYYApplyFloatClearProgressStateToView(UIView *view) {
    if (!view || !DYYYIsClearProgressView(view)) {
        return;
    }
    DYYYClearProgressMode mode = hideButton.isElementsHidden ? DYYYCurrentClearProgressMode() : DYYYClearProgressModeNone;
    DYYYApplyClearProgressViewState(view, mode);
}

UIWindow *getKeyWindow(void) {
    UIWindow *activeWindow = [DYYYUtils getActiveWindow];
    if (activeWindow) {
        return activeWindow;
    }

    UIWindow *keyWindow = nil;
    for (UIWindow *window in [UIApplication sharedApplication].windows) {
        if (window.isKeyWindow) {
            keyWindow = window;
            break;
        }
    }
    return keyWindow;
}

#pragma mark - v3.0 显示／隐藏模型

static void DYYYApplyClearButtonHiddenState(HideUIButton *button, BOOL hidden) {
    if (!button) {
        return;
    }
    void (^applyBlock)(HideUIButton *) = ^(HideUIButton *target) {
        if (!target) {
            return;
        }
        if (target.hidden != hidden) {
            target.hidden = hidden;
        }
    };

    if ([NSThread isMainThread]) {
        applyBlock(button);
    } else {
        __weak HideUIButton *weakButton = button;
        dispatch_async(dispatch_get_main_queue(), ^{
            applyBlock(weakButton);
        });
    }
}

static BOOL DYYYShouldHideClearButton(void) {
    // v3.0 规则：清屏状态下只留退出入口（只看前后台和强制隐藏）；
    // 普通状态下，播放页、评论、纯净模式、前后台都可能隐藏按钮。
    if (!isAppActive) {
        return YES;
    }
    // 我们的自动净化：净化进行时不显示手动清屏入口（旧协调器行为，v3.0 没有这一项）。
    if (hideButton && hideButton.homePurificationActive) {
        return YES;
    }
    BOOL clearModeActive = (hideButton && hideButton.isElementsHidden);
    if (clearModeActive) {
        return clearButtonForceHidden;
    }
    if (!dyyyInteractionViewVisible) {
        return YES;
    }
    if (dyyyCommentViewVisible) {
        return YES;
    }
    if (isPureViewVisible) {
        return YES;
    }
    if (clearButtonForceHidden) {
        return YES;
    }
    return NO;
}

void updateClearButtonVisibility(void) {
    if (!hideButton) {
        return;
    }
    DYYYApplyClearButtonHiddenState(hideButton, DYYYShouldHideClearButton());
}

void showClearButton(void) {
    clearButtonForceHidden = NO;
    updateClearButtonVisibility();
}

void hideClearButton(void) {
    clearButtonForceHidden = YES;
    updateClearButtonVisibility();
}

static void forceResetAllUIElements(void) {
    DYYYPerformClearButtonMutation(^{ [hideButton restoreCachedTargetViews]; });
}
static void reapplyHidingToAllElements(HideUIButton *button) {
    if (!button || !button.isElementsHidden)
        return;
    [button hideUIElements];
}
void initTargetClassNames(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSUInteger configuration = 0;
    configuration |= [defaults boolForKey:@"DYYYHideTabBar"] ? (1U << 0) : 0;
    configuration |= [defaults boolForKey:@"DYYYHideDanmaku"] ? (1U << 1) : 0;
    configuration |= [defaults boolForKey:@"DYYYHideSlider"] ? (1U << 2) : 0;
    configuration |= [defaults boolForKey:@"DYYYHideChapter"] ? (1U << 3) : 0;
    configuration |= [defaults boolForKey:@"DYYYHidePauseVideoIcon"] ? (1U << 4) : 0;
    if (targetClassNames && dyyyTargetClassConfiguration == configuration) {
        return;
    }

    NSMutableArray<NSString *> *list = [@[
        @"AWEHPTopBarCTAContainer", @"AWEHPDiscoverFeedEntranceView", @"AWELeftSideBarEntranceView", @"DUXBadge", @"AWEBaseElementView", @"AWEElementStackView", @"AWEPlayInteractionDescriptionLabel",
        @"AWEUserNameLabel", @"ACCEditTagStickerView", @"AWEFeedTemplateAnchorView", @"AWESearchFeedTagView", @"AWEPlayInteractionSearchAnchorView", @"AFDRecommendToFriendTagView",
        @"AWELandscapeFeedEntryView", @"AWEFeedAnchorContainerView", @"AFDAIbumFolioView", @"DUXPopover", @"AWEMixVideoPanelMoreView", @"AWEHotSearchInnerBottomView", @"AWEHPSegmentControlScrollView"
    ] mutableCopy];
    if (configuration & (1U << 0)) {
        [list addObject:@"AWENormalModeTabBar"];
    }
    if (configuration & (1U << 1)) {
        [list addObject:@"AWEVideoPlayDanmakuContainerView"];
        [list addObject:@"AWEDanmakuContainerView"];
    }
    if (configuration & (1U << 2)) {
        [list addObject:@"AWEStoryProgressSlideView"];
        [list addObject:@"AWEStoryProgressContainerView"];
    }
    if (configuration & (1U << 3)) {
        [list addObject:@"AWEDemaciaChapterProgressSlider"];
    }
    if (configuration & (1U << 4)) {
        // 视频中央的播放/暂停图标
        [list addObject:@"AWEAwemePlayVideoPauseIcon"];
    }

    targetClassNames = [list copy];
    dyyyTargetClassConfiguration = configuration;
    [hideButton invalidateTargetCache];
}

void reloadClearButtonConfiguration(void) {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{
          reloadClearButtonConfiguration();
        });
        return;
    }

    initTargetClassNames();

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL isEnabled = [defaults boolForKey:@"DYYYEnableFloatClearButton"];
    BOOL purificationEnabled = [defaults boolForKey:@"DYYYEnablePure"];
    if (!isEnabled && !purificationEnabled) {
        if (hideButton) {
            if (hideButton.isElementsHidden) {
                [hideButton safeResetState];
            }
            [hideButton removeFromSuperview];
            hideButton = nil;
        }
        return;
    }

    UIWindow *activeWindow = [DYYYUtils getActiveWindow];
    if (!activeWindow) {
        return;
    }

    CGFloat buttonSize = [defaults floatForKey:@"DYYYEnableFloatClearButtonSize"];
    if (buttonSize <= 0.0) {
        buttonSize = 40.0;
    }
    buttonSize = MIN(MAX(buttonSize, 20.0), 60.0);

    if (!hideButton) {
        hideButton = [[HideUIButton alloc] initWithFrame:CGRectMake(0, 0, buttonSize, buttonSize)];
    } else if (fabs(hideButton.bounds.size.width - buttonSize) > FLT_EPSILON) {
        hideButton.bounds = CGRectMake(0, 0, buttonSize, buttonSize);
        hideButton.layer.cornerRadius = buttonSize / 2.0;
    }

    // 净化也复用同一清屏实例，按钮是否显示仍由 updateClearButtonVisibility 决定。
    if (!isEnabled && hideButton.manualClearActive) {
        hideButton.manualClearActive = NO;
        [hideButton updateClearState];
    }
    if (hideButton.superview) [hideButton loadSavedPosition];
    if (![hideButton isDescendantOfView:activeWindow]) {
        [activeWindow addSubview:hideButton];
        [hideButton loadSavedPosition];
    }

    [activeWindow bringSubviewToFront:hideButton];
    if (hideButton.isElementsHidden) {
        [hideButton hideUIElements];
    }
    updateClearButtonVisibility();
}
@implementation HideUIButton
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.accessibilityLabel = @"DYYYClearScreenButton";
        self.backgroundColor = [UIColor clearColor];
        self.layer.cornerRadius = frame.size.width / 2;
        self.layer.masksToBounds = YES;
        self.isElementsHidden = NO;
        self.hiddenViewsList = [NSHashTable weakObjectsHashTable];
        self.progressViews = [NSHashTable weakObjectsHashTable];
        self.classifications = [NSMapTable strongToStrongObjectsMapTable];
        self.targetNames = [NSSet setWithArray:targetClassNames ?: @[]];
        self.needsDiscovery = YES;

        self.originalAlpha = 1.0;
        self.alpha = 0.5;
        
        [self loadLockState];
        [self loadIcons];
        [self setImage:self.showIcon forState:UIControlStateNormal];
        
        UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
        [self addGestureRecognizer:panGesture];
        
        [self addTarget:self action:@selector(handleTap) forControlEvents:UIControlEventTouchUpInside];
        [self addTarget:self action:@selector(handleTouchDown) forControlEvents:UIControlEventTouchDown];
        [self addTarget:self action:@selector(handleTouchUpInside) forControlEvents:UIControlEventTouchUpInside];
        [self addTarget:self action:@selector(handleTouchUpOutside) forControlEvents:UIControlEventTouchUpOutside];
        
        UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
        [self addGestureRecognizer:longPressGesture];
        
        [self startPeriodicCheck];
        [self resetFadeTimer];

        // 新控件先隐藏，是否显示由 updateClearButtonVisibility 决定
        self.hidden = YES;
    }
    return self;
}

- (void)didMoveToSuperview {
    [super didMoveToSuperview];
    if (self.superview) {
        [self loadSavedPosition];
    }
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) {
        [self stopTimers];
        return;
    }
    [self startPeriodicCheck];
    [self resetFadeTimer];
}

- (void)startPeriodicCheck {
    if (self.checkTimer) {
        [self.checkTimer invalidate];
        self.checkTimer = nil;
    }
    __weak __typeof(self) weakSelf = self;
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:0.2
                                                    repeats:YES
                                                      block:^(NSTimer *timer) {
                                                        __strong __typeof(weakSelf) strongSelf = weakSelf;
                                                        if (!strongSelf) {
                                                            return;
                                                        }
                                                        if (strongSelf.isElementsHidden) {
                                                            [strongSelf hideUIElements];
                                                        }
                                                      }];
    self.checkTimer = timer;
}

- (void)resetFadeTimer {
    if (self.fadeTimer) {
        [self.fadeTimer invalidate];
        self.fadeTimer = nil;
    }
    __weak __typeof(self) weakSelf = self;
    NSTimer *fadeTimer = [NSTimer scheduledTimerWithTimeInterval:3.0
                                                         repeats:NO
                                                           block:^(NSTimer *timer) {
                                                             __strong __typeof(weakSelf) strongSelf = weakSelf;
                                                             if (!strongSelf) {
                                                                 return;
                                                             }
                                                             [UIView animateWithDuration:0.3
                                                                              animations:^{
                                                                                strongSelf.alpha = 0.5;
                                                                              }];
                                                             strongSelf.fadeTimer = nil;
                                                           }];
    self.fadeTimer = fadeTimer;
    if (self.alpha != self.originalAlpha) {
        [UIView animateWithDuration:0.2
                         animations:^{
                           self.alpha = self.originalAlpha;
                         }];
    }
}

- (void)stopTimers {
    if (self.checkTimer) {
        [self.checkTimer invalidate];
        self.checkTimer = nil;
    }
    if (self.fadeTimer) {
        [self.fadeTimer invalidate];
        self.fadeTimer = nil;
    }
}

- (void)saveButtonPosition {
    if (self.superview) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        // 位置改存一个字串 DYYYHideUIButtonPosition，与 v3.0 的 DYYY.xm 创建时读取的键一致。
        [defaults setObject:NSStringFromCGPoint(self.center) forKey:@"DYYYHideUIButtonPosition"];
        [defaults removeObjectForKey:@"DYYYHideButtonCenterXPercent"];
        [defaults removeObjectForKey:@"DYYYHideButtonCenterYPercent"];
    }
}

- (void)loadSavedPosition {
    if (!self.superview) {
        return;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    CGPoint targetCenter;
    NSString *savedPosition = [defaults objectForKey:@"DYYYHideUIButtonPosition"];
    if (savedPosition.length > 0) {
        targetCenter = CGPointFromString(savedPosition);
    } else if ([self dyyyHasSavedPosition]) {
        // 旧版本百分比位置一次性迁移为字串，迁移后删除旧键。
        targetCenter = CGPointMake([defaults floatForKey:@"DYYYHideButtonCenterXPercent"] * self.superview.bounds.size.width,
                                   [defaults floatForKey:@"DYYYHideButtonCenterYPercent"] * self.superview.bounds.size.height);
        [defaults setObject:NSStringFromCGPoint(targetCenter) forKey:@"DYYYHideUIButtonPosition"];
        [defaults removeObjectForKey:@"DYYYHideButtonCenterXPercent"];
        [defaults removeObjectForKey:@"DYYYHideButtonCenterYPercent"];
    } else {
        targetCenter = [self dyyyDefaultCenter];
    }
    self.center = [self dyyyConstrainedCenterForProposedCenter:targetCenter];
}

- (void)saveLockState {
    [[NSUserDefaults standardUserDefaults] setBool:self.isLocked forKey:@"DYYYHideUIButtonLockState"];
}

- (void)loadLockState {
    self.isLocked = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideUIButtonLockState"];
}

- (void)loadIcons {
    NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *iconPath = [documentsPath stringByAppendingPathComponent:@"DYYY/qingping.gif"];
    NSData *gifData = [NSData dataWithContentsOfFile:iconPath];

    NSArray<UIImage *> *frames = nil;
    CGFloat totalDuration = 0.0;
    BOOL hasFrames = gifData.length > 0 &&
                     [DYYYUtils framesFromAnimatedData:gifData
                                                scale:[UIScreen mainScreen].scale
                                               images:&frames
                                        totalDuration:&totalDuration];

    if (hasFrames && frames.count > 0) {
        UIImageView *animatedImageView = [[UIImageView alloc] initWithFrame:self.bounds];
        animatedImageView.animationImages = frames;
        animatedImageView.animationDuration = totalDuration;
        animatedImageView.animationRepeatCount = 0;
        [self addSubview:animatedImageView];

        animatedImageView.translatesAutoresizingMaskIntoConstraints = NO;
        [NSLayoutConstraint activateConstraints:@[
            [animatedImageView.centerXAnchor constraintEqualToAnchor:self.centerXAnchor], [animatedImageView.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
            [animatedImageView.widthAnchor constraintEqualToAnchor:self.widthAnchor], [animatedImageView.heightAnchor constraintEqualToAnchor:self.heightAnchor]
        ]];

        [animatedImageView startAnimating];
        return;
    }

    [self setTitle:@"隐藏" forState:UIControlStateNormal];
    [self setTitle:@"显示" forState:UIControlStateSelected];
    self.titleLabel.font = [UIFont systemFontOfSize:10];
}

- (void)handleTouchDown {
    [self resetFadeTimer];
}

- (void)handleTouchUpInside {
    [self resetFadeTimer];
}

- (void)handleTouchUpOutside {
    [self resetFadeTimer];
}

- (UIViewController *)findViewController:(UIView *)view {
    __weak UIResponder *responder = view;
    while (responder) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)responder;
        }
        responder = [responder nextResponder];
        if (!responder)
            break;
    }
    return nil;
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    if (self.isLocked)
        return;

    [self resetFadeTimer];
    if (gesture.state == UIGestureRecognizerStateBegan) {
        if ([self dyyyStickToEdgeEnabled]) {
            self.dyyyActiveDragEdge = [self dyyyNearestEdgeForPoint:self.center];
            self.center = [self dyyyCenterOnEdge:self.dyyyActiveDragEdge forPoint:self.center];
        }
    } else if (gesture.state == UIGestureRecognizerStateChanged) {
        CGPoint touchPoint = [gesture locationInView:self.superview];
        if ([self dyyyStickToEdgeEnabled]) {
            DYYYClearButtonEdge nearestEdge = [self dyyyNearestEdgeForPoint:touchPoint];
            CGFloat currentDistance = [self dyyyDistanceFromPoint:touchPoint toEdge:self.dyyyActiveDragEdge];
            CGFloat nearestDistance = [self dyyyDistanceFromPoint:touchPoint toEdge:nearestEdge];
            if (nearestEdge != self.dyyyActiveDragEdge && nearestDistance + 12.0 < currentDistance) {
                self.dyyyActiveDragEdge = nearestEdge;
            }
            self.center = [self dyyyCenterOnEdge:self.dyyyActiveDragEdge forPoint:touchPoint];
        } else {
            self.center = [self dyyyClampedCenterForProposedCenter:touchPoint];
        }
    }

    if (gesture.state == UIGestureRecognizerStateEnded || gesture.state == UIGestureRecognizerStateCancelled) {
        self.center = [self dyyyConstrainedCenterForProposedCenter:self.center];
        [self saveButtonPosition];
    }
}

// 自动净化和手动清屏分别记录意图，共用隐藏、缓存和恢复流程。
- (void)setHomePurificationActive:(BOOL)active {
    if (!NSThread.isMainThread) {
        __weak HideUIButton *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{ weakSelf.homePurificationActive = active; });
        return;
    }
    if (_homePurificationActive == active) return;
    _homePurificationActive = active;
    [self updateClearState];
    updateClearButtonVisibility();
}

- (void)updateClearState {
    BOOL shouldHide = self.manualClearActive || self.homePurificationActive;
    if (self.isElementsHidden == shouldHide) return;
    if (shouldHide) {
        [self hideUIElements];
        self.selected = YES;
        DYYYRefreshStatusBarVisibility();
    } else {
        [self safeResetState];
    }
}

- (void)handleTap {
    // 1.0.4 悬浮按钮自定义：配了动作就执行动作，不走默认清屏切换。
    if (GHLPerformFloatButtonAction(GHLGetString(GHL_KEY_CLEAR_BUTTON_TAP))) {
        [self resetFadeTimer];
        return;
    }
    // v3.0 做法：页面切换过渡期间忽略默认清屏切换，避免连点。
    if (isAppInTransition)
        return;
    self.manualClearActive = !self.manualClearActive;
    [self resetFadeTimer];
    [self updateClearState];
    // v3.0 做法：清屏时按 DYYYHideSpeed 同步倍速按钮，再统一刷新两个按钮的可见性。
    BOOL hideSpeed = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideSpeed"];
    if (hideSpeed) {
        if (self.isElementsHidden) {
            hideSpeedButton();
        } else {
            showSpeedButton();
        }
    }
    updateSpeedButtonVisibility();
    updateClearButtonVisibility();
}

- (void)restoreAWEPlayInteractionProgressContainerView {
    DYYYPerformClearButtonMutation(^{
        for (UIView *view in self.progressViews.allObjects) DYYYRestoreClearProgressViewState(view);
        [self.progressViews removeAllObjects];
    });
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self resetFadeTimer];
        // 1.0.4 悬浮按钮自定义：配了长按动作就执行动作，不走默认锁定/解锁。
        if (GHLPerformFloatButtonAction(GHLGetString(GHL_KEY_CLEAR_BUTTON_LONGPRESS))) return;
        self.isLocked = !self.isLocked;
        [self saveLockState];
        NSString *toastMessage = self.isLocked ? @"按钮已锁定" : @"按钮已解锁";
        [DYYYUtils showToast:toastMessage];
        if (@available(iOS 10.0, *)) {
            UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
            [generator prepare];
            [generator impactOccurred];
        }
    }
}
#pragma mark - 清屏实例缓存

- (void)invalidateTargetCache {
    [self restoreCachedTargetViews];
    [self restoreAWEPlayInteractionProgressContainerView];
    [self.classifications removeAllObjects];
    self.targetNames = [NSSet setWithArray:targetClassNames ?: @[]];
    self.needsDiscovery = YES;
}

- (NSUInteger)classificationForView:(UIView *)view {
    Class type = view.class;
    NSNumber *cached = [self.classifications objectForKey:type];
    if (cached) return cached.unsignedIntegerValue;
    NSUInteger classification = DYYYIsClearProgressView(view) ? 2 : 0;
    for (Class ancestor = type; ancestor; ancestor = class_getSuperclass(ancestor)) {
        if ([self.targetNames containsObject:NSStringFromClass(ancestor)]) { classification |= 1; break; }
    }
    if (self.classifications.count >= 512) [self.classifications removeAllObjects];
    [self.classifications setObject:@(classification) forKey:type];
    return classification;
}

- (void)applyHiddenStateToView:(UIView *)view {
    static Class entranceClass, feedClass;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        entranceClass = NSClassFromString(@"AWELeftSideBarEntranceView");
        feedClass = NSClassFromString(@"AWEFeedContainerViewController");
    });
    if ([view isKindOfClass:entranceClass] && ![[self findViewController:view] isKindOfClass:feedClass]) return;
    DYYYApplyClearTargetViewHiddenState(view);
}

- (void)registerViewForHiding:(UIView *)view {
    if (!NSThread.isMainThread) {
        __weak UIView *weakView = view;
        __weak HideUIButton *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf registerViewForHiding:weakView]; });
        return;
    }
    if (!self.isElementsHidden || !view || view == self) return;
    NSUInteger classification = [self classificationForView:view];
    DYYYPerformClearButtonMutation(^{
        if (classification & 2) {
            [self.progressViews addObject:view];
            if (view.window) DYYYApplyClearProgressViewState(view, DYYYCurrentClearProgressMode());
        }
        if (!(classification & 1)) return;
        [self.hiddenViewsList addObject:view];
        // init 时先弱引用登记；预加载视图进入窗口后再应用，避免依赖子类是否调用 super。
        if (view.window) [self applyHiddenStateToView:view];
    });
}

- (void)restoreCachedTargetViews {
    DYYYPerformClearButtonMutation(^{
        for (UIView *view in self.hiddenViewsList.allObjects) {
            DYYYRestoreClearTargetViewStateIfNeeded(view);
        }
        [self.hiddenViewsList removeAllObjects];
        self.needsDiscovery = YES;
    });
}

- (void)applyCachedHiding {
    if (!self.isElementsHidden) return;
    DYYYPerformClearButtonMutation(^{
        for (UIView *view in self.hiddenViewsList.allObjects) if (view.window) [self applyHiddenStateToView:view];
        for (UIView *view in self.progressViews.allObjects) if (view.window) DYYYApplyClearProgressViewState(view, DYYYCurrentClearProgressMode());
        if (self.superview && self.superview.subviews.lastObject != self) [self.superview bringSubviewToFront:self];
    });
}

- (void)hideUIElements {
    if (!NSThread.isMainThread) {
        __weak HideUIButton *weakSelf = self;
        dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf hideUIElements]; });
        return;
    }
    initTargetClassNames();
    BOOL entering = !self.isElementsHidden;
    self.isElementsHidden = YES;
    if (self.needsDiscovery) {
        self.needsDiscovery = NO;
        [self findAndHideViews:targetClassNames];
    }
    if (entering) { [self applyCachedHiding]; return; }
    if (self.refreshScheduled) return;
    self.refreshScheduled = YES;
    __weak HideUIButton *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        HideUIButton *button = weakSelf;
        button.refreshScheduled = NO;
        [button applyCachedHiding];
    });
}

- (void)findAndHideViews:(NSArray *)classNames {
    // 仅在进入清屏或配置改变后发现一次；后续刷新只访问弱引用实例缓存。
    NSMutableArray<UIView *> *pending = [UIApplication.sharedApplication.windows mutableCopy];
    while (pending.count) {
        UIView *view = pending.lastObject;
        [pending removeLastObject];
        [self registerViewForHiding:view];
        [pending addObjectsFromArray:view.subviews];
    }
}

- (void)safeResetState {
    self.manualClearActive = NO;
    _homePurificationActive = NO;
    self.isElementsHidden = NO;
    forceResetAllUIElements();
    [self restoreAWEPlayInteractionProgressContainerView];
    [self.hiddenViewsList removeAllObjects];
    self.selected = NO;

    if (self.superview) {
        [self.superview bringSubviewToFront:self];
    }

    // 切场景/重置状态时，确保按钮自隐藏 alpha 也被恢复，避免按钮一直处于近乎透明的状态
    if (self.alpha < 0.1) {
        self.alpha = self.originalAlpha;
        [self resetFadeTimer];
    }

    // 清屏隐藏状态栏：触发系统重新评估状态栏显隐
    DYYYRefreshStatusBarVisibility();
    // v3.0 做法：退出清屏时按 DYYYHideSpeed 恢复倍速按钮，再统一刷新两个按钮的可见性。
    BOOL hideSpeed = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideSpeed"];
    if (hideSpeed) {
        showSpeedButton();
    }
    updateSpeedButtonVisibility();
    updateClearButtonVisibility();
}
- (void)dealloc {
    [self stopTimers];
}
- (BOOL)dyyyEdgeMetricsWithLeftX:(CGFloat *)leftX
                          rightX:(CGFloat *)rightX
                            topY:(CGFloat *)topY
                         bottomY:(CGFloat *)bottomY
                            minX:(CGFloat *)minX
                            maxX:(CGFloat *)maxX
                            minY:(CGFloat *)minY
                            maxY:(CGFloat *)maxY {
    if (!self.superview) {
        return NO;
    }

    CGSize size = self.superview.bounds.size;
    CGFloat halfWidth = CGRectGetWidth(self.bounds) * 0.5;
    CGFloat halfHeight = CGRectGetHeight(self.bounds) * 0.5;
    *leftX = halfWidth + kDYYYClearButtonEdgeInset;
    *rightX = size.width - halfWidth - kDYYYClearButtonEdgeInset;
    *topY = halfHeight + kDYYYClearButtonEdgeInset;
    *bottomY = size.height - halfHeight - kDYYYClearButtonEdgeInset;
    *minX = halfWidth + kDYYYClearButtonEdgeInset;
    *maxX = size.width - halfWidth - kDYYYClearButtonEdgeInset;
    *minY = halfHeight + kDYYYClearButtonEdgeInset;
    *maxY = size.height - halfHeight - kDYYYClearButtonEdgeInset;
    return YES;
}

- (CGFloat)dyyyDistanceFromPoint:(CGPoint)point toEdge:(DYYYClearButtonEdge)edge {
    CGFloat leftX, rightX, topY, bottomY, minX, maxX, minY, maxY;
    if (![self dyyyEdgeMetricsWithLeftX:&leftX rightX:&rightX topY:&topY bottomY:&bottomY minX:&minX maxX:&maxX minY:&minY maxY:&maxY]) {
        return CGFLOAT_MAX;
    }

    switch (edge) {
        case DYYYClearButtonEdgeLeft:
            return fabs(point.x - leftX);
        case DYYYClearButtonEdgeRight:
            return fabs(point.x - rightX);
        case DYYYClearButtonEdgeTop:
            return fabs(point.y - topY);
        case DYYYClearButtonEdgeBottom:
            return fabs(point.y - bottomY);
    }
}

- (DYYYClearButtonEdge)dyyyNearestEdgeForPoint:(CGPoint)point {
    DYYYClearButtonEdge edge = DYYYClearButtonEdgeLeft;
    CGFloat minDistance = [self dyyyDistanceFromPoint:point toEdge:edge];
    for (NSInteger rawEdge = DYYYClearButtonEdgeRight; rawEdge <= DYYYClearButtonEdgeBottom; rawEdge++) {
        DYYYClearButtonEdge candidate = (DYYYClearButtonEdge)rawEdge;
        CGFloat distance = [self dyyyDistanceFromPoint:point toEdge:candidate];
        if (distance < minDistance) {
            minDistance = distance;
            edge = candidate;
        }
    }
    return edge;
}

- (CGPoint)dyyyCenterOnEdge:(DYYYClearButtonEdge)edge forPoint:(CGPoint)point {
    CGFloat leftX, rightX, topY, bottomY, minX, maxX, minY, maxY;
    if (![self dyyyEdgeMetricsWithLeftX:&leftX rightX:&rightX topY:&topY bottomY:&bottomY minX:&minX maxX:&maxX minY:&minY maxY:&maxY]) {
        return point;
    }

    switch (edge) {
        case DYYYClearButtonEdgeLeft:
            return CGPointMake(leftX, MIN(MAX(point.y, minY), maxY));
        case DYYYClearButtonEdgeRight:
            return CGPointMake(rightX, MIN(MAX(point.y, minY), maxY));
        case DYYYClearButtonEdgeTop:
            return CGPointMake(MIN(MAX(point.x, minX), maxX), topY);
        case DYYYClearButtonEdgeBottom:
            return CGPointMake(MIN(MAX(point.x, minX), maxX), bottomY);
    }
}

- (CGPoint)dyyySnappedCenterForProposedCenter:(CGPoint)center {
    return [self dyyyCenterOnEdge:[self dyyyNearestEdgeForPoint:center] forPoint:center];
}

- (CGPoint)dyyyClampedCenterForProposedCenter:(CGPoint)center {
    CGFloat minX, maxX, minY, maxY;
    CGFloat unusedLeft, unusedRight, unusedTop, unusedBottom;
    if (![self dyyyEdgeMetricsWithLeftX:&unusedLeft rightX:&unusedRight topY:&unusedTop bottomY:&unusedBottom minX:&minX maxX:&maxX minY:&minY maxY:&maxY]) {
        return center;
    }
    return CGPointMake(MIN(MAX(center.x, minX), maxX), MIN(MAX(center.y, minY), maxY));
}

- (BOOL)dyyyStickToEdgeEnabled {
    return [[NSUserDefaults standardUserDefaults] boolForKey:DYYY_CLEAR_BUTTON_STICK_TO_EDGE_KEY];
}

- (CGPoint)dyyyConstrainedCenterForProposedCenter:(CGPoint)center {
    if ([self dyyyStickToEdgeEnabled]) {
        return [self dyyySnappedCenterForProposedCenter:center];
    }
    return [self dyyyClampedCenterForProposedCenter:center];
}

- (BOOL)dyyyHasSavedPosition {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return [defaults objectForKey:@"DYYYHideButtonCenterXPercent"] != nil &&
           [defaults objectForKey:@"DYYYHideButtonCenterYPercent"] != nil;
}

- (CGPoint)dyyyDefaultCenter {
    CGFloat leftX, rightX, topY, bottomY, minX, maxX, minY, maxY;
    if (![self dyyyEdgeMetricsWithLeftX:&leftX rightX:&rightX topY:&topY bottomY:&bottomY minX:&minX maxX:&maxX minY:&minY maxY:&maxY]) {
        return self.center;
    }
    CGFloat defaultY = MIN(MAX(self.superview.bounds.size.height * (1.0 - kDYYYClearButtonDefaultYFromBottomPercent), minY), maxY);
    return CGPointMake(rightX, defaultY);
}

- (void)resetToDefaultPosition {
    if (!self.superview) {
        return;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:@"DYYYHideUIButtonPosition"];
    [defaults removeObjectForKey:@"DYYYHideButtonCenterXPercent"];
    [defaults removeObjectForKey:@"DYYYHideButtonCenterYPercent"];
    self.center = [self dyyyDefaultCenter];
    [self resetFadeTimer];
}

@end
