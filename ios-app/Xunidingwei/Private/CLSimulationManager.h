#import <Foundation/Foundation.h>

/// CoreLocation 的私有类，系统在运行时提供实现，这里只做声明。
/// 声明成真实的 ObjC 类型后，Swift 可以直接实例化，
/// 不必走 NSClassFromString + 协议元类型转换
/// （元类型转协议元类型对未声明遵循的系统私有类永远失败）。
@interface CLSimulationManager : NSObject

- (void)clearSimulatedLocations;
- (void)appendSimulatedLocation:(id)location;
- (void)flush;
- (void)startLocationSimulation;
- (void)stopLocationSimulation;

@end
