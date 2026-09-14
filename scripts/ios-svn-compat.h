/* iOS stubs for APIs unavailable in the iOS SDK. */
#ifndef IPADSVN_IOS_COMPAT_H
#define IPADSVN_IOS_COMPAT_H

#include <TargetConditionals.h>

#if TARGET_OS_IPHONE
#define system(command) (-1)
#endif

#endif
