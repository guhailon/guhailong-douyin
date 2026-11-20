#import <UIKit/UIKit.h>

@interface FloatingSpeedButton : UIButton
@property(nonatomic, assign) CGPoint lastLocation;
@property(nonatomic, weak) id interactionController;
@property(nonatomic, assign) BOOL isLocked;
@property(nonatomic, assign) BOOL justToggledLock;
@property(nonatomic, assign) BOOL originalLockState;
@property(nonatomic, assign) BOOL isResponding;
@property(nonatomic, strong) NSTimer *statusCheckTimer;
@property(nonatomic, strong) NSTimer *fadeTimer;
@property(nonatomic, assign) CGFloat originalAlpha;
+ (void)reloadConfiguration;
+ (void)attachToWindow:(UIWindow *)window interactionController:(UIViewController *)controller;
- (void)saveButtonPosition;
- (void)loadSavedPosition;
- (void)resetButtonState;
- (void)toggleLockState;
- (void)resetFadeTimer;
- (void)resetToDefaultPosition;
@end

#ifdef __cplusplus
extern "C" {
#endif

extern FloatingSpeedButton *speedButton;
extern BOOL isFloatSpeedButtonEnabled;
extern BOOL showSpeedX;
extern CGFloat speedButtonSize;
// v3.0 共享显示标志：由 DYYY.xm 的页面钩子维护，本文件只读。
extern BOOL dyyyCommentViewVisible;
extern BOOL dyyyInteractionViewVisible;
extern BOOL speedButtonForceHidden;

extern NSArray *getSpeedOptions(void);
extern NSString *DYYYDefaultSpeedSettingsString(void);
extern BOOL DYYYNormalizeSpeedSettingsForRequiredSpeeds(void);

extern FloatingSpeedButton *getSpeedButton(void);
extern NSArray *findViewControllersInHierarchy(UIViewController *rootViewController);
extern float getCurrentSpeed(void);
extern NSInteger getCurrentSpeedIndex(void);
extern void setCurrentSpeedIndex(NSInteger index);
extern BOOL setCurrentSpeedValue(float speed);
extern void updateSpeedButtonUI(void);
extern void showSpeedButton(void);
extern void hideSpeedButton(void);
extern void toggleSpeedButtonVisibility(void);
extern void updateSpeedButtonVisibility(void);
extern id DYYYCurrentSpeedInteractionController(void);

#ifdef __cplusplus
}
#endif
