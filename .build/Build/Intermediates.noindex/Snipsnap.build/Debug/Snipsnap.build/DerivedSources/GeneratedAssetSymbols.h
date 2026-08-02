#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The "MenuBarIcon" asset catalog image resource.
static NSString * const ACImageNameMenuBarIcon AC_SWIFT_PRIVATE = @"MenuBarIcon";

/// The "RabbitHop0" asset catalog image resource.
static NSString * const ACImageNameRabbitHop0 AC_SWIFT_PRIVATE = @"RabbitHop0";

/// The "RabbitHop1" asset catalog image resource.
static NSString * const ACImageNameRabbitHop1 AC_SWIFT_PRIVATE = @"RabbitHop1";

/// The "RabbitHop2" asset catalog image resource.
static NSString * const ACImageNameRabbitHop2 AC_SWIFT_PRIVATE = @"RabbitHop2";

/// The "RabbitHop3" asset catalog image resource.
static NSString * const ACImageNameRabbitHop3 AC_SWIFT_PRIVATE = @"RabbitHop3";

/// The "RabbitHop4" asset catalog image resource.
static NSString * const ACImageNameRabbitHop4 AC_SWIFT_PRIVATE = @"RabbitHop4";

#undef AC_SWIFT_PRIVATE
