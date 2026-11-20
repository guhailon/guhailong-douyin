#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

@class HideUIButton;

extern HideUIButton *hideButton;
extern BOOL dyyyIsPerformingFloatClearOperation;
extern NSArray *targetClassNames;
extern char dyyyClearOriginalAlphaKey;
// v3.0 共享显示标志：定义在 DYYYFloatClearButton.xm（isPureViewVisible 等）和
// DYYYFloatSpeedButton.m（dyyyCommentViewVisible、dyyyInteractionViewVisible）。
extern BOOL isInPlayInteractionVC;
extern BOOL isPureViewVisible;
extern BOOL clearButtonForceHidden;
extern BOOL isAppActive;
extern BOOL isAppInTransition;
extern BOOL dyyyInteractionViewVisible;
extern BOOL dyyyCommentViewVisible;

BOOL DYYYIsDynamicAlphaView(UIView *view);
void DYYYApplyClearTargetViewHiddenState(UIView *view);
void DYYYRestoreClearTargetViewStateIfNeeded(UIView *view);

UIWindow *getKeyWindow(void);

void initTargetClassNames(void);
void reloadClearButtonConfiguration(void);
void updateClearButtonVisibility(void);
void showClearButton(void);
void hideClearButton(void);
void DYYYApplyFloatClearProgressStateToView(UIView *view);

#ifdef __cplusplus
}
#endif

@interface HideUIButton : UIButton
@property(nonatomic, assign) BOOL isElementsHidden;
@property(nonatomic, assign) BOOL homePurificationActive;
@property(nonatomic, assign) BOOL isLocked;
@property(nonatomic, strong) NSHashTable<UIView *> *hiddenViewsList;
- (void)registerViewForHiding:(UIView *)view;
@property(nonatomic, strong) UIImage *showIcon;
@property(nonatomic, strong) UIImage *hideIcon;
@property(nonatomic, assign) CGFloat originalAlpha;
@property(nonatomic, strong) NSTimer *checkTimer;
@property(nonatomic, strong) NSTimer *fadeTimer;
- (void)resetFadeTimer;
- (void)loadSavedPosition;
- (void)resetToDefaultPosition;
- (void)hideUIElements;
- (void)findAndHideViews:(NSArray *)classNames;
- (void)safeResetState;
- (void)startPeriodicCheck;
- (UIViewController *)findViewController:(UIView *)view;
- (void)loadIcons;
- (void)handlePan:(UIPanGestureRecognizer *)gesture;
- (void)handleTap;
- (void)handleLongPress:(UILongPressGestureRecognizer *)gesture;
- (void)handleTouchDown;
- (void)handleTouchUpInside;
- (void)handleTouchUpOutside;
- (void)saveLockState;
- (void)loadLockState;
@end
