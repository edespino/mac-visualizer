//
// Copyright 2026 Ed Espino
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
// implied. See the License for the specific language governing
// permissions and limitations under the License.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` under an Objective-C @try/@catch. Swift cannot catch Obj-C
/// exceptions at all — one raised through a Swift frame terminates the
/// process — so dynamic Obj-C calls that can raise (ScriptingBridge KVC)
/// must be routed through this shim. Returns nil on success, or the caught
/// NSException.
NSException * _Nullable MVCatchObjCException(void (NS_NOESCAPE ^block)(void));

NS_ASSUME_NONNULL_END
