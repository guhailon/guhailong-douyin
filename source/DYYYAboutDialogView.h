// 自定义关于弹窗类
#import <UIKit/UIKit.h>

@interface DYYYAboutDialogView : UIView
@property(nonatomic, strong) UIVisualEffectView *blurView;
@property(nonatomic, strong) UIView *contentView;
@property(nonatomic, strong) UILabel *titleLabel;
@property(nonatomic, strong) UITextView *messageTextView;
@property(nonatomic, strong) UIButton *confirmButton;
// 1.0.4：关于弹窗专用的“加入QQ群”按钮（只在关于弹窗显示；其他弹窗传 nil 就没有）。
@property(nonatomic, copy, nullable) NSString *joinGroupURL;
@property(nonatomic, strong, nullable) UIButton *joinGroupButton;
@property(nonatomic, copy) void (^onConfirm)(void);

- (instancetype)initWithTitle:(NSString *)title message:(NSString *)message;
- (instancetype)initWithTitle:(NSString *)title message:(NSString *)message joinGroupURL:(nullable NSString *)joinGroupURL;
- (void)show;
- (void)dismiss;
- (void)confirmTapped;
@end
