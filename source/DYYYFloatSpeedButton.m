#import "AwemeHeaders.h"
#import "DYYYConstants.h"
#import "DYYYFloatClearButton.h"
#import "DYYYFloatSpeedButton.h"
#import "DYYYUtils.h"
#import "GHLFeatures.h"
#import <UIKit/UIKit.h>
#import <float.h>
#import <math.h>
#import <objc/runtime.h>

@class AWEFeedCellViewController;

FloatingSpeedButton *speedButton = nil;
BOOL showSpeedX = NO;
CGFloat speedButtonSize = 32.0;
BOOL isFloatSpeedButtonEnabled = NO;
// v3.0 共享显示标志：定义在这里，DYYYFloatClearButton.h 也声明 extern。
BOOL dyyyCommentViewVisible = NO;
BOOL dyyyInteractionViewVisible = NO;
BOOL speedButtonForceHidden = NO;
static NSString *const kDYYYDefaultSpeedSettingsString = @"0.75,1.0,1.25,1.5,2.0,2.5,3.0";

static NSString *DYYYFormatSpeedOption(double speed) {
    NSString *speedString = [NSString stringWithFormat:@"%.2f", speed];
    while ([speedString containsString:@"."] && [speedString hasSuffix:@"0"]) {
        speedString = [speedString substringToIndex:speedString.length - 1];
    }
    if ([speedString hasSuffix:@"."]) {
        speedString = [speedString substringToIndex:speedString.length - 1];
    }
    return speedString;
}

static BOOL DYYYSpeedValuesMatch(double lhs, double rhs) {
    return fabs(lhs - rhs) <= 0.001;
}

NSString *DYYYDefaultSpeedSettingsString(void) {
    return kDYYYDefaultSpeedSettingsString;
}

static NSString *DYYYSpeedSettingsStringFromValue(id value) {
    if ([value isKindOfClass:[NSString class]]) {
        return [(NSString *)value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    if ([value respondsToSelector:@selector(stringValue)]) {
        return [[value stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    return nil;
}

static NSArray<NSString *> *DYYYParsedSpeedOptionsFromString(NSString *speedConfig) {
    NSMutableArray<NSString *> *validSpeeds = [NSMutableArray array];
    NSCharacterSet *whitespace = [NSCharacterSet whitespaceAndNewlineCharacterSet];

    for (NSString *component in [speedConfig componentsSeparatedByString:@","]) {
        NSString *trimmedValue = [component stringByTrimmingCharactersInSet:whitespace];
        if (trimmedValue.length == 0) {
            continue;
        }

        NSScanner *scanner = [NSScanner scannerWithString:trimmedValue];
        double speed = 0.0;
        if ([scanner scanDouble:&speed] && scanner.isAtEnd && isfinite(speed) && speed > 0.0) {
            [validSpeeds addObject:DYYYFormatSpeedOption(speed)];
        }
    }
    return validSpeeds;
}

static double DYYYSpeedPreferenceValue(NSString *key, double fallback) {
    id value = [[NSUserDefaults standardUserDefaults] objectForKey:key];
    double speed = [value respondsToSelector:@selector(doubleValue)] ? [value doubleValue] : fallback;
    if (!isfinite(speed) || speed <= 0.0) {
        return fallback;
    }
    return speed;
}

static BOOL DYYYSpeedOptionsContainSpeed(NSArray<NSString *> *speedOptions, double speed) {
    if (!isfinite(speed) || speed <= 0.0) {
        return YES;
    }

    for (NSString *speedString in speedOptions) {
        if (DYYYSpeedValuesMatch([speedString doubleValue], speed)) {
            return YES;
        }
    }
    return NO;
}

static BOOL DYYYSpeedOptionsCoverRequiredPlaybackSpeeds(NSArray<NSString *> *speedOptions) {
    double defaultSpeed = DYYYSpeedPreferenceValue(@"DYYYDefaultSpeed", 1.0);
    double longPressSpeed = DYYYSpeedPreferenceValue(@"DYYYLongPressSpeed", 2.0);
    return DYYYSpeedOptionsContainSpeed(speedOptions, defaultSpeed) &&
           DYYYSpeedOptionsContainSpeed(speedOptions, longPressSpeed);
}

BOOL DYYYNormalizeSpeedSettingsForRequiredSpeeds(void) {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *speedConfig = DYYYSpeedSettingsStringFromValue([defaults objectForKey:@"DYYYSpeedSettings"]);
    NSArray<NSString *> *validSpeeds = DYYYParsedSpeedOptionsFromString(speedConfig ?: @"");
    BOOL shouldUseDefaultSettings = speedConfig.length == 0 ||
                                    validSpeeds.count == 0 ||
                                    !DYYYSpeedOptionsCoverRequiredPlaybackSpeeds(validSpeeds);

    if (!shouldUseDefaultSettings) {
        return NO;
    }

    if (![speedConfig isEqualToString:kDYYYDefaultSpeedSettingsString]) {
        [defaults setObject:kDYYYDefaultSpeedSettingsString forKey:@"DYYYSpeedSettings"];
        return YES;
    }
    return NO;
}

NSArray *getSpeedOptions() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    DYYYNormalizeSpeedSettingsForRequiredSpeeds();

    NSString *speedConfig = DYYYSpeedSettingsStringFromValue([defaults objectForKey:@"DYYYSpeedSettings"]) ?: kDYYYDefaultSpeedSettingsString;
    NSArray<NSString *> *validSpeeds = DYYYParsedSpeedOptionsFromString(speedConfig);
    if (validSpeeds.count == 0) {
        [defaults setObject:kDYYYDefaultSpeedSettingsString forKey:@"DYYYSpeedSettings"];
        validSpeeds = DYYYParsedSpeedOptionsFromString(kDYYYDefaultSpeedSettingsString);
    }

    return validSpeeds;
}

NSInteger getCurrentSpeedIndex() {
    NSInteger index = [[NSUserDefaults standardUserDefaults] integerForKey:@"DYYYCurrentSpeedIndex"];
    NSArray *speeds = getSpeedOptions();

    if (index >= speeds.count || index < 0) {
        index = 0;
        [[NSUserDefaults standardUserDefaults] setInteger:index forKey:@"DYYYCurrentSpeedIndex"];
    }

    return index;
}

float getCurrentSpeed() {
    NSArray *speeds = getSpeedOptions();
    NSInteger index = getCurrentSpeedIndex();

    if (speeds.count == 0)
        return 1.0;
    float speed = [speeds[index] floatValue];
    return speed > 0 ? speed : 1.0;
}

void setCurrentSpeedIndex(NSInteger index) {
    NSArray *speeds = getSpeedOptions();

    if (speeds.count == 0)
        return;
    index = index % speeds.count;
    if (index < 0) {
        index += speeds.count;
    }

    [[NSUserDefaults standardUserDefaults] setInteger:index forKey:@"DYYYCurrentSpeedIndex"];
}

BOOL setCurrentSpeedValue(float speed) {
    if (!isfinite(speed) || speed <= 0.0f) {
        return NO;
    }

    NSArray *speeds = getSpeedOptions();
    for (NSInteger index = 0; index < speeds.count; index++) {
        if (DYYYSpeedValuesMatch([speeds[index] floatValue], speed)) {
            setCurrentSpeedIndex(index);
            return YES;
        }
    }
    return NO;
}

void updateSpeedButtonUI() {
    if (!speedButton)
        return;

    float currentSpeed = getCurrentSpeed();

    NSString *formattedSpeed;
    if (fmodf(currentSpeed, 1.0) == 0) {
        // 整数值 (1.0, 2.0) -> "1", "2"
        formattedSpeed = [NSString stringWithFormat:@"%.0f", currentSpeed];
    } else if (fmodf(currentSpeed * 10, 1.0) == 0) {
        // 一位小数 (1.5) -> "1.5"
        formattedSpeed = [NSString stringWithFormat:@"%.1f", currentSpeed];
    } else {
        // 两位小数 (1.25) -> "1.25"
        formattedSpeed = [NSString stringWithFormat:@"%.2f", currentSpeed];
    }

    if (showSpeedX) {
        formattedSpeed = [formattedSpeed stringByAppendingString:@"x"];
    }

    if ([NSThread isMainThread]) {
        [speedButton setTitle:formattedSpeed forState:UIControlStateNormal];
    } else {
        __weak FloatingSpeedButton *weakButton = speedButton;
        dispatch_async(dispatch_get_main_queue(), ^{
          FloatingSpeedButton *strongButton = weakButton;
          if (!strongButton) {
              return;
          }
          [strongButton setTitle:formattedSpeed forState:UIControlStateNormal];
        });
    }
}

FloatingSpeedButton *getSpeedButton(void) { return speedButton; }

NSArray *findViewControllersInHierarchy(UIViewController *rootViewController) {
    if (!rootViewController) {
        return @[];
    }

    NSMutableArray *viewControllers = [NSMutableArray array];
    [viewControllers addObject:rootViewController];

    for (UIViewController *childVC in rootViewController.childViewControllers) {
        [viewControllers addObjectsFromArray:findViewControllersInHierarchy(childVC)];
    }

    return viewControllers;
}

#pragma mark - v3.0 显示／隐藏模型

static void DYYYApplySpeedButtonHiddenState(UIView *button, BOOL hidden) {
    if (!button) {
        return;
    }
    void (^applyBlock)(UIView *) = ^(UIView *target) {
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
        __weak UIView *weakButton = button;
        dispatch_async(dispatch_get_main_queue(), ^{
            applyBlock(weakButton);
        });
    }
}

static BOOL DYYYShouldHideSpeedButton(void) {
    // v3.0 规则：清屏状态下只看 DYYYHideSpeed；其余只看播放页、评论和强制隐藏。
    BOOL clearModeActive = (hideButton && hideButton.isElementsHidden);
    if (clearModeActive) {
        BOOL hideSpeedInClearMode = [[NSUserDefaults standardUserDefaults] boolForKey:@"DYYYHideSpeed"];
        if (hideSpeedInClearMode) {
            return YES;
        }
        return speedButtonForceHidden;
    }
    if (!dyyyInteractionViewVisible) {
        return YES;
    }
    if (dyyyCommentViewVisible) {
        return YES;
    }
    if (speedButtonForceHidden) {
        return YES;
    }
    return NO;
}

void showSpeedButton(void) {
    speedButtonForceHidden = NO;
    updateSpeedButtonVisibility();
}

void hideSpeedButton(void) {
    speedButtonForceHidden = YES;
    updateSpeedButtonVisibility();
}

void toggleSpeedButtonVisibility(void) {
    // v3.0 只在头文件声明了本函数，未给实现；这里按“翻转强制隐藏”实现。
    speedButtonForceHidden = !speedButtonForceHidden;
    updateSpeedButtonVisibility();
}

void updateSpeedButtonVisibility(void) {
    if (!speedButton || !isFloatSpeedButtonEnabled)
        return;

    DYYYApplySpeedButtonHiddenState(speedButton, DYYYShouldHideSpeedButton());
}

static const CGFloat kDYYYSpeedButtonEdgeInset = 10.0;
static const CGFloat kDYYYSpeedButtonDefaultYFromBottomPercent = 0.65;

typedef NS_ENUM(NSInteger, DYYYSpeedButtonEdge) {
    DYYYSpeedButtonEdgeLeft = 0,
    DYYYSpeedButtonEdgeRight,
    DYYYSpeedButtonEdgeTop,
    DYYYSpeedButtonEdgeBottom,
};

static BOOL DYYYSpeedButtonStickToEdgeEnabled(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:DYYY_SPEED_BUTTON_STICK_TO_EDGE_KEY];
}

static const CGFloat kDYYYSpeedButtonEdgeSwitchHysteresis = 12.0;

@interface FloatingSpeedButton ()
@property(nonatomic, assign) DYYYSpeedButtonEdge dyyyActiveDragEdge;
@end

@implementation FloatingSpeedButton

+ (void)reloadConfiguration {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self reloadConfiguration]; });
        return;
    }
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    BOOL enabled = [defaults boolForKey:@"DYYYEnableFloatSpeedButton"];
    BOOL showX = [defaults boolForKey:@"DYYYSpeedButtonShowX"];
    CGFloat configuredSize = [defaults floatForKey:@"DYYYSpeedButtonSize"];
    CGFloat size = MIN(MAX(configuredSize > 0 ? configuredSize : 32.0, 20.0), 60.0);
    BOOL changed = enabled != isFloatSpeedButtonEnabled || showX != showSpeedX || fabs(size - speedButtonSize) > FLT_EPSILON;
    isFloatSpeedButtonEnabled = enabled;
    showSpeedX = showX;
    speedButtonSize = size;
    if (speedButton) {
        [speedButton loadSavedPosition];
        [speedButton resetFadeTimer];
    }
    if (!enabled) {
        // 开关关闭时直接隐藏，不再等协调器刷新。
        if (speedButton) speedButton.hidden = YES;
        return;
    }
    if (!changed) {
        updateSpeedButtonVisibility();
        return;
    }
    if (speedButton && fabs(speedButton.bounds.size.width - size) > FLT_EPSILON) {
        speedButton.bounds = CGRectMake(0, 0, size, size);
        speedButton.layer.cornerRadius = size / 2.0;
        [speedButton loadSavedPosition];
    }
    updateSpeedButtonUI();
    updateSpeedButtonVisibility();
}

+ (void)attachToWindow:(UIWindow *)window interactionController:(UIViewController *)controller {
    if (!window) {
        return;
    }
    if (!speedButton) {
        CGFloat size = speedButtonSize;
        CGRect frame = CGRectMake((window.bounds.size.width - size) / 2.0, (window.bounds.size.height - size) / 2.0, size, size);
        speedButton = [[self alloc] initWithFrame:frame];
        // 新控件先隐藏，是否显示由 updateSpeedButtonVisibility 决定。
        speedButton.hidden = YES;
        updateSpeedButtonUI();
    }
    if (speedButton.interactionController != controller) {
        speedButton.interactionController = controller;
        [speedButton resetButtonState];
    }
    if (speedButton.window != window) {
        [window addSubview:speedButton];
        [speedButton loadSavedPosition];
        [speedButton resetFadeTimer];
    }
    updateSpeedButtonVisibility();
}

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.accessibilityLabel = @"DYYYSpeedSwitchButton";
        self.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.1];
        self.layer.cornerRadius = frame.size.width / 2;
        self.layer.masksToBounds = YES;
        self.layer.borderWidth = 1.0;
        self.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.2].CGColor;

        [self setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.3] forState:UIControlStateNormal];
        self.titleLabel.font = [UIFont boldSystemFontOfSize:15];

        self.layer.shadowColor = [UIColor blackColor].CGColor;
        self.layer.shadowOffset = CGSizeMake(0, 2);
        self.layer.shadowOpacity = 0.2;

        self.userInteractionEnabled = YES;
        self.isResponding = YES;

        self.originalAlpha = 1.0;
        self.alpha = 0.5;

        [self resetFadeTimer];
        [self ensureStatusCheckTimerRunning];

        [self setupGestureRecognizers];

        [self loadSavedPosition];

        self.justToggledLock = NO;
    }
    return self;
}
- (void)setupGestureRecognizers {
    for (UIGestureRecognizer *recognizer in [self.gestureRecognizers copy]) {
        [self removeGestureRecognizer:recognizer];
    }
    [self removeTarget:self action:@selector(handleTouchUpInside:) forControlEvents:UIControlEventTouchUpInside];
    [self removeTarget:self action:@selector(handleTouchDown:) forControlEvents:UIControlEventTouchDown];
    [self removeTarget:self action:@selector(handleTouchUpOutside:) forControlEvents:UIControlEventTouchUpOutside];

    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self addGestureRecognizer:panGesture];

    UILongPressGestureRecognizer *longPressGesture = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPressGesture.minimumPressDuration = 0.5;
    [self addGestureRecognizer:longPressGesture];

    [self addTarget:self action:@selector(handleTouchUpInside:) forControlEvents:UIControlEventTouchUpInside];
    [self addTarget:self action:@selector(handleTouchDown:) forControlEvents:UIControlEventTouchDown];
    [self addTarget:self action:@selector(handleTouchUpOutside:) forControlEvents:UIControlEventTouchUpOutside];

    panGesture.delegate = (id<UIGestureRecognizerDelegate>)self;
    longPressGesture.delegate = (id<UIGestureRecognizerDelegate>)self;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer {
    if ([gestureRecognizer isKindOfClass:[UIPanGestureRecognizer class]]) {
        return YES;
    }
    return NO;
}

- (void)handleTouchDown:(UIButton *)sender {
    self.isResponding = YES;
    [self resetFadeTimer];
}

- (void)handleTouchUpInside:(UIButton *)sender {
    if (self.justToggledLock) {
        self.justToggledLock = NO;
        return;
    }

    [self resetFadeTimer];

    [UIView animateWithDuration:0.08
        animations:^{
          self.transform = CGAffineTransformMakeScale(1.15, 1.15);
        }
        completion:^(BOOL finished) {
          [UIView animateWithDuration:0.08
                           animations:^{
                             self.transform = CGAffineTransformIdentity;
                           }];
        }];

    // 1.0.4 悬浮按钮自定义：配了动作就执行动作，不走默认倍速切换。
    if (GHLPerformFloatButtonAction(GHLGetString(GHL_KEY_SPEED_BUTTON_TAP))) return;

    id currentController = DYYYCurrentSpeedInteractionController();
    if (currentController) {
        self.interactionController = currentController;
    }

    if (self.interactionController) {
        @try {
            [self.interactionController speedButtonTapped:self];
        } @catch (NSException *exception) {
            self.isResponding = NO;
        }
    } else {
        self.isResponding = NO;
    }
}

- (void)handleTouchUpOutside:(UIButton *)sender {
    self.justToggledLock = NO;
    [self resetFadeTimer];
}

- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture {
    self.isResponding = YES;

    if (gesture.state == UIGestureRecognizerStateBegan) {
        [self resetFadeTimer];

        // 1.0.4 悬浮按钮自定义：配了长按动作就执行动作，不走默认锁定/解锁。
        if (GHLPerformFloatButtonAction(GHLGetString(GHL_KEY_SPEED_BUTTON_LONGPRESS))) return;

        self.originalLockState = self.isLocked;

        [self toggleLockState];
    }
}

- (void)toggleLockState {
    self.isLocked = !self.isLocked;
    self.justToggledLock = YES;

    NSString *toastMessage = self.isLocked ? @"按钮已锁定" : @"按钮已解锁";
    [DYYYUtils showToast:toastMessage];

    if (self.isLocked) {
        [self saveButtonPosition];
    }

    if (@available(iOS 10.0, *)) {
        UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [generator prepare];
        [generator impactOccurred];
    }

    __weak __typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
      __strong __typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) {
          return;
      }
      strongSelf.justToggledLock = NO;
    });
}

- (void)resetToggleLockFlag {
    __weak __typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
      __strong __typeof(weakSelf) strongSelf = weakSelf;
      if (!strongSelf) {
          return;
      }
      strongSelf.justToggledLock = NO;
    });
}

- (void)resetButtonState {
    self.justToggledLock = NO;
    self.isResponding = YES;
    self.userInteractionEnabled = YES;
    self.transform = CGAffineTransformIdentity;
    self.alpha = self.originalAlpha;

    [self resetFadeTimer];

    [self setupGestureRecognizers];
}

- (void)resetFadeTimer {
    if (self.fadeTimer) {
        [self.fadeTimer invalidate];
        self.fadeTimer = nil;
    }

    if (self.alpha != self.originalAlpha) {
        [UIView animateWithDuration:0.2
                         animations:^{
                           self.alpha = self.originalAlpha;
                         }];
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
    [[NSRunLoop mainRunLoop] addTimer:fadeTimer forMode:NSRunLoopCommonModes];
}

- (void)handlePan:(UIPanGestureRecognizer *)pan {
    if (self.isLocked)
        return;

    self.justToggledLock = NO;
    [self resetFadeTimer];

    if (pan.state == UIGestureRecognizerStateBegan) {
        self.transform = CGAffineTransformIdentity;
        if (DYYYSpeedButtonStickToEdgeEnabled()) {
            self.dyyyActiveDragEdge = [self dyyyEdgeForCenter:self.center];
            self.center = [self dyyyCenterOnEdge:self.dyyyActiveDragEdge forPoint:self.center];
        }
    } else if (pan.state == UIGestureRecognizerStateChanged) {
        CGPoint touchPoint = [pan locationInView:self.superview];
        if (DYYYSpeedButtonStickToEdgeEnabled()) {
            DYYYSpeedButtonEdge nearestEdge = [self dyyyNearestEdgeForPoint:touchPoint];
            if (nearestEdge != self.dyyyActiveDragEdge) {
                CGFloat currentDist = [self dyyyDistanceFromPoint:touchPoint toEdge:self.dyyyActiveDragEdge];
                CGFloat nearestDist = [self dyyyDistanceFromPoint:touchPoint toEdge:nearestEdge];
                if (nearestDist + kDYYYSpeedButtonEdgeSwitchHysteresis < currentDist) {
                    self.dyyyActiveDragEdge = nearestEdge;
                }
            }
            self.center = [self dyyyCenterOnEdge:self.dyyyActiveDragEdge forPoint:touchPoint];
        } else {
            self.center = [self dyyyClampedCenterForProposedCenter:touchPoint];
        }
        self.alpha = self.originalAlpha;
    } else if (pan.state == UIGestureRecognizerStateEnded || pan.state == UIGestureRecognizerStateCancelled) {
        self.center = [self dyyyConstrainedCenterForProposedCenter:self.center];
        self.alpha = self.originalAlpha;
        [self saveButtonPosition];
    }
}

- (void)saveButtonPosition {
    if (self.superview) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        // 位置改存一个字串，不再存横纵百分比。
        [defaults setObject:NSStringFromCGPoint(self.center) forKey:@"DYYYSpeedButtonPosition"];
        [defaults removeObjectForKey:@"DYYYSpeedButtonCenterXPercent"];
        [defaults removeObjectForKey:@"DYYYSpeedButtonCenterYPercent"];
        [defaults setBool:self.isLocked forKey:@"DYYYSpeedButtonLocked"];
    }
}

- (void)loadSavedPosition {
    if (!self.superview) {
        return;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.isLocked = [defaults boolForKey:@"DYYYSpeedButtonLocked"];

    CGPoint targetCenter;
    NSString *savedPosition = [defaults objectForKey:@"DYYYSpeedButtonPosition"];
    if (savedPosition.length > 0) {
        targetCenter = CGPointFromString(savedPosition);
    } else if ([self dyyyHasSavedPosition]) {
        // 旧版本百分比位置一次性迁移为字串，迁移后删除旧键。
        float centerXPercent = [defaults floatForKey:@"DYYYSpeedButtonCenterXPercent"];
        float centerYPercent = [defaults floatForKey:@"DYYYSpeedButtonCenterYPercent"];
        targetCenter = CGPointMake(centerXPercent * self.superview.bounds.size.width,
                                   centerYPercent * self.superview.bounds.size.height);
        [defaults setObject:NSStringFromCGPoint(targetCenter) forKey:@"DYYYSpeedButtonPosition"];
        [defaults removeObjectForKey:@"DYYYSpeedButtonCenterXPercent"];
        [defaults removeObjectForKey:@"DYYYSpeedButtonCenterYPercent"];
    } else {
        targetCenter = [self dyyyDefaultCenter];
    }

    self.center = [self dyyyConstrainedCenterForProposedCenter:targetCenter];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    if (!self.window) {
        [self stopTimers];
        return;
    }
    [self ensureStatusCheckTimerRunning];
    [self resetFadeTimer];
}

- (void)ensureStatusCheckTimerRunning {
    if (self.statusCheckTimer && [self.statusCheckTimer isValid]) {
        return;
    }
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:60.0 target:self selector:@selector(checkAndRecoverButtonStatus) userInfo:nil repeats:YES];
    [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    self.statusCheckTimer = timer;
}

- (void)stopTimers {
    if (self.statusCheckTimer) {
        [self.statusCheckTimer invalidate];
        self.statusCheckTimer = nil;
    }
    if (self.fadeTimer) {
        [self.fadeTimer invalidate];
        self.fadeTimer = nil;
    }
}

- (void)checkAndRecoverButtonStatus {
    if (!self.isResponding) {
        [self resetButtonState];
        self.isResponding = YES;
    }

    if (!self.interactionController) {
        self.interactionController = DYYYCurrentSpeedInteractionController();
    }
}

- (void)dealloc {
    [self stopTimers];
}
- (void)resetToDefaultPosition {
    if (!self.superview) {
        return;
    }

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:@"DYYYSpeedButtonPosition"];
    [defaults removeObjectForKey:@"DYYYSpeedButtonCenterXPercent"];
    [defaults removeObjectForKey:@"DYYYSpeedButtonCenterYPercent"];
    self.center = [self dyyyDefaultCenter];
    [self resetFadeTimer];
}

- (void)dyyyEdgeGeometryForSuperviewSize:(CGSize)size
                               halfWidth:(CGFloat)hw
                              halfHeight:(CGFloat)hh
                             leftCenterX:(CGFloat *)leftCenterX
                            rightCenterX:(CGFloat *)rightCenterX
                               topCenterY:(CGFloat *)topCenterY
                            bottomCenterY:(CGFloat *)bottomCenterY
                          minAlongEdgeX:(CGFloat *)minAlongEdgeX
                          maxAlongEdgeX:(CGFloat *)maxAlongEdgeX
                          minAlongEdgeY:(CGFloat *)minAlongEdgeY
                          maxAlongEdgeY:(CGFloat *)maxAlongEdgeY {
    CGFloat inset = kDYYYSpeedButtonEdgeInset;
    *leftCenterX = hw + inset;
    *rightCenterX = size.width - hw - inset;
    *topCenterY = hh + inset;
    *bottomCenterY = size.height - hh - inset;
    *minAlongEdgeX = hw + inset;
    *maxAlongEdgeX = size.width - hw - inset;
    *minAlongEdgeY = hh + inset;
    *maxAlongEdgeY = size.height - hh - inset;
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
    CGFloat hw = CGRectGetWidth(self.bounds) * 0.5;
    CGFloat hh = CGRectGetHeight(self.bounds) * 0.5;
    [self dyyyEdgeGeometryForSuperviewSize:size
                                 halfWidth:hw
                                halfHeight:hh
                               leftCenterX:leftX
                              rightCenterX:rightX
                                 topCenterY:topY
                              bottomCenterY:bottomY
                            minAlongEdgeX:minX
                            maxAlongEdgeX:maxX
                            minAlongEdgeY:minY
                            maxAlongEdgeY:maxY];
    return YES;
}

- (CGFloat)dyyyDistanceFromPoint:(CGPoint)point toEdge:(DYYYSpeedButtonEdge)edge {
    CGFloat leftX, rightX, topY, bottomY, minX, maxX, minY, maxY;
    if (![self dyyyEdgeMetricsWithLeftX:&leftX rightX:&rightX topY:&topY bottomY:&bottomY minX:&minX maxX:&maxX minY:&minY maxY:&maxY]) {
        return CGFLOAT_MAX;
    }

    switch (edge) {
        case DYYYSpeedButtonEdgeLeft:
            return fabs(point.x - leftX);
        case DYYYSpeedButtonEdgeRight:
            return fabs(point.x - rightX);
        case DYYYSpeedButtonEdgeTop:
            return fabs(point.y - topY);
        case DYYYSpeedButtonEdgeBottom:
            return fabs(point.y - bottomY);
    }
}

- (DYYYSpeedButtonEdge)dyyyNearestEdgeForPoint:(CGPoint)point {
    DYYYSpeedButtonEdge edge = DYYYSpeedButtonEdgeLeft;
    CGFloat minDist = [self dyyyDistanceFromPoint:point toEdge:edge];

    for (DYYYSpeedButtonEdge candidate = DYYYSpeedButtonEdgeRight; candidate <= DYYYSpeedButtonEdgeBottom; candidate++) {
        CGFloat dist = [self dyyyDistanceFromPoint:point toEdge:candidate];
        if (dist < minDist) {
            minDist = dist;
            edge = candidate;
        }
    }
    return edge;
}

- (DYYYSpeedButtonEdge)dyyyEdgeForCenter:(CGPoint)center {
    return [self dyyyNearestEdgeForPoint:center];
}

- (CGPoint)dyyyCenterOnEdge:(DYYYSpeedButtonEdge)edge forPoint:(CGPoint)point {
    CGFloat leftX, rightX, topY, bottomY, minX, maxX, minY, maxY;
    if (![self dyyyEdgeMetricsWithLeftX:&leftX rightX:&rightX topY:&topY bottomY:&bottomY minX:&minX maxX:&maxX minY:&minY maxY:&maxY]) {
        return point;
    }

    switch (edge) {
        case DYYYSpeedButtonEdgeLeft:
            return CGPointMake(leftX, MIN(MAX(point.y, minY), maxY));
        case DYYYSpeedButtonEdgeRight:
            return CGPointMake(rightX, MIN(MAX(point.y, minY), maxY));
        case DYYYSpeedButtonEdgeTop:
            return CGPointMake(MIN(MAX(point.x, minX), maxX), topY);
        case DYYYSpeedButtonEdgeBottom:
            return CGPointMake(MIN(MAX(point.x, minX), maxX), bottomY);
    }
}

- (CGPoint)dyyySnappedCenterForProposedCenter:(CGPoint)proposed {
    DYYYSpeedButtonEdge edge = [self dyyyNearestEdgeForPoint:proposed];
    return [self dyyyCenterOnEdge:edge forPoint:proposed];
}

- (CGPoint)dyyyClampedCenterForProposedCenter:(CGPoint)proposed {
    CGFloat minX, maxX, minY, maxY;
    CGFloat unusedLeft, unusedRight, unusedTop, unusedBottom;
    if (![self dyyyEdgeMetricsWithLeftX:&unusedLeft rightX:&unusedRight topY:&unusedTop bottomY:&unusedBottom minX:&minX maxX:&maxX minY:&minY maxY:&maxY]) {
        return proposed;
    }
    return CGPointMake(MIN(MAX(proposed.x, minX), maxX), MIN(MAX(proposed.y, minY), maxY));
}

- (CGPoint)dyyyConstrainedCenterForProposedCenter:(CGPoint)proposed {
    if (DYYYSpeedButtonStickToEdgeEnabled()) {
        return [self dyyySnappedCenterForProposedCenter:proposed];
    }
    return [self dyyyClampedCenterForProposedCenter:proposed];
}

- (CGPoint)dyyyDefaultCenter {
    if (!self.superview) {
        return self.center;
    }

    CGSize size = self.superview.bounds.size;
    CGFloat hw = CGRectGetWidth(self.bounds) * 0.5;
    CGFloat hh = CGRectGetHeight(self.bounds) * 0.5;
    CGFloat leftX, rightX, topY, bottomY, minX, maxX, minY, maxY;
    [self dyyyEdgeGeometryForSuperviewSize:size
                                 halfWidth:hw
                                halfHeight:hh
                               leftCenterX:&leftX
                              rightCenterX:&rightX
                                 topCenterY:&topY
                              bottomCenterY:&bottomY
                            minAlongEdgeX:&minX
                            maxAlongEdgeX:&maxX
                            minAlongEdgeY:&minY
                            maxAlongEdgeY:&maxY];

    CGFloat defaultY = size.height * (1.0 - kDYYYSpeedButtonDefaultYFromBottomPercent);
    defaultY = MIN(MAX(defaultY, minY), maxY);
    return CGPointMake(rightX, defaultY);
}

- (BOOL)dyyyHasSavedPosition {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return [defaults objectForKey:@"DYYYSpeedButtonCenterXPercent"] != nil &&
           [defaults objectForKey:@"DYYYSpeedButtonCenterYPercent"] != nil;
}

@end
