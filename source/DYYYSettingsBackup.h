// DYYYSettingsBackup — 设置导入 / 导出 / 恢复默认（1.0.4）
// 备份/恢复的完整做法就是导入 + 导出两行，不要另做一套。
// 导出：把 settingSections 里全部 key 的当前值写成一个 .plist（“顾海龙抖音配置.plist”，
// 存在 Documents/DYYY/），用系统分享调出来；导入：系统文件选择器选 .plist 读回来。
// 导入只认我们自己的 key（调用方传 allowedKeys，只写这些），不认识的 key 忽略，
// 不动抖音自己的设置；文件格式不对、读不出来返回错误，不崩。
#import <Foundation/Foundation.h>

@interface DYYYSettingsBackup : NSObject

// 导出配置：返回写好的 .plist 文件 URL（失败返回 nil 并填 error）。
+ (nullable NSURL *)exportSettingsForKeys:(NSArray<NSString *> *)keys error:(NSError **)error;

// 导入配置：读文件里的设置字典，只写 allowedKeys 里的 key；返回实际写入的项数。
// 文件格式不对、没有合法项返回 0 并填 error。
+ (NSInteger)importSettingsFromURL:(NSURL *)url allowedKeys:(NSSet<NSString *> *)allowedKeys error:(NSError **)error;

// 恢复默认配置：删掉 keys + additionalKeys 里的全部 key（回到未设置 = 现有代码的默认值），
// 并删掉自选龙头和自定义背景文件。DYYYUserAgreementAccepted、GHLLastSeenVersion 不在这里，
// 调用方不要把它们传进来（协议只弹一次、更新日志只弹一次）。
+ (void)resetSettingsForKeys:(NSArray<NSString *> *)keys additionalKeys:(NSArray<NSString *> *)additionalKeys;

@end
