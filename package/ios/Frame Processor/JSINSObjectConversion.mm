//
//  JSINSObjectConversion.mm
//  VisionCamera
//
//  Forked and Adjusted by Marc Rousavy on 02.05.21.
//  Copyright © 2021 mrousavy & Facebook. All rights reserved.
//
//  Forked and adjusted from:
//  https://github.com/facebook/react-native/blob/900210cacc4abca0079e3903781bc223c80c8ac7/ReactCommon/react/nativemodule/core/platform/ios/RCTTurboModule.mm
//  Original Copyright Notice:
//
//  Copyright (c) Facebook, Inc. and its affiliates.
//
//  This source code is licensed under the MIT license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "JSINSObjectConversion.h"
#import "../Frame Processor/Frame.h"
#import "../Frame Processor/FrameHostObject.h"
#import "../Frame Processor/SharedArray.h"
#import "JSITypedArray.h"
#import <Foundation/Foundation.h>
#import <React/RCTBridge.h>
#import <ReactCommon/CallInvoker.h>
#import <ReactCommon/RCTBlockGuard.h>
#import <ReactCommon/TurboModuleUtils.h>
#import <jsi/jsi.h>

using namespace facebook;
using namespace facebook::react;

namespace JSINSObjectConversion {

jsi::Value convertNSNumberToJSIBoolean(jsi::Runtime& runtime, NSNumber* value) {
  return jsi::Value((bool)[value boolValue]);
}

jsi::Value convertNSNumberToJSINumber(jsi::Runtime& runtime, NSNumber* value) {
  return jsi::Value([value doubleValue]);
}

jsi::String convertNSStringToJSIString(jsi::Runtime& runtime, NSString* value) {
  return jsi::String::createFromUtf8(runtime, [value UTF8String] ?: "");
}

jsi::Object convertNSDictionaryToJSIObject(jsi::Runtime& runtime, NSDictionary* value) {
  jsi::Object result = jsi::Object(runtime);
  for (NSString* k in value) {
    result.setProperty(runtime, [k UTF8String], convertObjCObjectToJSIValue(runtime, value[k]));
  }
  return result;
}

jsi::Array convertNSArrayToJSIArray(jsi::Runtime& runtime, NSArray* value) {
  jsi::Array result = jsi::Array(runtime, value.count);
  for (size_t i = 0; i < value.count; i++) {
    result.setValueAtIndex(runtime, i, convertObjCObjectToJSIValue(runtime, value[i]));
  }
  return result;
}

jsi::Object convertSharedArrayToJSIArrayBuffer(jsi::Runtime& runtime, SharedArray* sharedArray) {
  std::shared_ptr<vision::TypedArrayBase> array = sharedArray.typedArray;
  return array->getBuffer(runtime);
}

jsi::Value convertObjCObjectToJSIValue(jsi::Runtime& runtime, id value) {
  if (value == nil) {
    return jsi::Value::undefined();
  } else if ([value isKindOfClass:[NSString class]]) {
    return convertNSStringToJSIString(runtime, (NSString*)value);
  } else if ([value isKindOfClass:[NSNumber class]]) {
    if ([value isKindOfClass:[@YES class]]) {
      return convertNSNumberToJSIBoolean(runtime, (NSNumber*)value);
    }
    return convertNSNumberToJSINumber(runtime, (NSNumber*)value);
  } else if ([value isKindOfClass:[NSDictionary class]]) {
    return convertNSDictionaryToJSIObject(runtime, (NSDictionary*)value);
  } else if ([value isKindOfClass:[NSArray class]]) {
    return convertNSArrayToJSIArray(runtime, (NSArray*)value);
  } else if (value == (id)kCFNull) {
    return jsi::Value::null();
  } else if ([value isKindOfClass:[Frame class]]) {
    auto frameHostObject = std::make_shared<FrameHostObject>((Frame*)value);
    return jsi::Object::createFromHostObject(runtime, frameHostObject);
  } else if ([value isKindOfClass:[SharedArray class]]) {
    return convertSharedArrayToJSIArrayBuffer(runtime, (SharedArray*)value);
  }
  return jsi::Value::undefined();
}

NSString* convertJSIStringToNSString(jsi::Runtime& runtime, const jsi::String& value) {
  return [NSString stringWithUTF8String:value.utf8(runtime).c_str()];
}

NSArray* convertJSICStyleArrayToNSArray(jsi::Runtime& runtime, const jsi::Value* array, size_t length,
                                        std::shared_ptr<CallInvoker> jsInvoker) {
  if (length < 1)
    return @[];
  NSMutableArray* result = [NSMutableArray new];
  for (size_t i = 0; i < length; i++) {
    // Insert kCFNull when it's `undefined` value to preserve the indices.
    [result addObject:convertJSIValueToObjCObject(runtime, array[i], jsInvoker) ?: (id)kCFNull];
  }
  return [result copy];
}

jsi::Value* convertNSArrayToJSICStyleArray(jsi::Runtime& runtime, NSArray* array) {
  auto result = new jsi::Value[array.count];
  for (size_t i = 0; i < array.count; i++) {
    result[i] = convertObjCObjectToJSIValue(runtime, array[i]);
  }
  return result;
}

NSArray* convertJSIArrayToNSArray(jsi::Runtime& runtime, const jsi::Array& value, std::shared_ptr<CallInvoker> jsInvoker) {
  size_t size = value.size(runtime);
  NSMutableArray* result = [NSMutableArray new];
  for (size_t i = 0; i < size; i++) {
    // Insert kCFNull when it's `undefined` value to preserve the indices.
    [result addObject:convertJSIValueToObjCObject(runtime, value.getValueAtIndex(runtime, i), jsInvoker) ?: (id)kCFNull];
  }
  return [result copy];
}

NSDictionary* convertJSIObjectToNSDictionary(jsi::Runtime& runtime, const jsi::Object& value, std::shared_ptr<CallInvoker> jsInvoker) {
  jsi::Array propertyNames = value.getPropertyNames(runtime);
  size_t size = propertyNames.size(runtime);
  NSMutableDictionary* result = [NSMutableDictionary new];
  for (size_t i = 0; i < size; i++) {
    jsi::String name = propertyNames.getValueAtIndex(runtime, i).getString(runtime);
    NSString* k = convertJSIStringToNSString(runtime, name);
    id v = convertJSIValueToObjCObject(runtime, value.getProperty(runtime, name), jsInvoker);
    if (v) {
      result[k] = v;
    }
  }
  return [result copy];
}

id convertJSIValueToObjCObject(jsi::Runtime& runtime, const jsi::Value& value, std::shared_ptr<CallInvoker> jsInvoker) {
  if (value.isUndefined() || value.isNull()) {
    // undefined/null
    return nil;
  } else if (value.isBool()) {
    // bool
    return @(value.getBool());
  } else if (value.isNumber()) {
    // number
    return @(value.getNumber());
  } else if (value.isString()) {
    // string
    return convertJSIStringToNSString(runtime, value.getString(runtime));
  } else if (value.isObject()) {
    // object
    jsi::Object o = value.getObject(runtime);
    if (o.isArray(runtime)) {
      // array[]
      return convertJSIArrayToNSArray(runtime, o.getArray(runtime), jsInvoker);
    } else if (o.isFunction(runtime)) {
      // function () => {}
      return convertJSIFunctionToCallback(runtime, std::move(o.getFunction(runtime)), jsInvoker);
    } else if (o.isHostObject(runtime)) {
      if (o.isHostObject<FrameHostObject>(runtime)) {
        // Frame
        auto hostObject = o.getHostObject<FrameHostObject>(runtime);
        return hostObject->frame;
      } else {
        throw std::runtime_error("The given HostObject is not supported by a Frame Processor Plugin!");
      }
    } else if (o.isArrayBuffer(runtime)) {
      // ArrayBuffer
      auto typedArray = std::make_shared<vision::TypedArrayBase>(vision::getTypedArray(runtime, o));
      return [[SharedArray alloc] initWithRuntime:runtime typedArray:typedArray];
    } else {
      // object
      return convertJSIObjectToNSDictionary(runtime, o, jsInvoker);
    }
  }

  auto stringRepresentation = value.toString(runtime).utf8(runtime);
  throw std::runtime_error("Failed to convert jsi::Value to JNI value - unsupported type! " + stringRepresentation);
}

RCTResponseSenderBlock convertJSIFunctionToCallback(jsi::Runtime& runtime, const jsi::Function& value,
                                                    std::shared_ptr<CallInvoker> jsInvoker) {
  auto weakWrapper = CallbackWrapper::createWeak(value.getFunction(runtime), runtime, jsInvoker);
  RCTBlockGuard* blockGuard = [[RCTBlockGuard alloc] initWithCleanup:^() {
    auto strongWrapper = weakWrapper.lock();
    if (strongWrapper) {
      strongWrapper->destroy();
    }
  }];

  BOOL __block wrapperWasCalled = NO;
  RCTResponseSenderBlock callback = ^(NSArray* responses) {
    if (wrapperWasCalled) {
      throw std::runtime_error("callback arg cannot be called more than once");
    }

    auto strongWrapper = weakWrapper.lock();
    if (!strongWrapper) {
      return;
    }

    strongWrapper->jsInvoker().invokeAsync([weakWrapper, responses, blockGuard]() {
      auto strongWrapper2 = weakWrapper.lock();
      if (!strongWrapper2) {
        return;
      }

      const jsi::Value* args = convertNSArrayToJSICStyleArray(strongWrapper2->runtime(), responses);
      strongWrapper2->callback().call(strongWrapper2->runtime(), args, static_cast<size_t>(responses.count));
      strongWrapper2->destroy();
      delete[] args;

      // Delete the CallbackWrapper when the block gets dealloced without being invoked.
      (void)blockGuard;
    });

    wrapperWasCalled = YES;
  };

  return [callback copy];
}

} // namespace JSINSObjectConversion
