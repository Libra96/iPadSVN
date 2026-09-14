/* iOS stubs for APIs unavailable in the iOS SDK. */
#ifndef IPADSVN_IOS_COMPAT_H
#define IPADSVN_IOS_COMPAT_H

#include <TargetConditionals.h>

#if TARGET_OS_IPHONE

static inline int ipadsvn_system_stub(const char *command)
{
  (void)command;
  return -1;
}

#define system(command) ipadsvn_system_stub(command)

#endif

#endif
