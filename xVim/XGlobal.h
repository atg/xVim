//
//  Created by Morris on 11-12-17.
//  Copyright (c) 2011年 http://warwithinme.com . All rights reserved.
//

#ifdef DEBUG
#   define DLog(fmt, ...) NSLog(fmt, ##__VA_ARGS__);
#else
#   define DLog(...)
#endif

@class XTextViewBridge;

// Replace target selector of a target class with our function
// the overriden method is returned.
void* methodSwizzle(Class c, SEL sel, void* overrideFunction);


// These methods are used to associate a XTextViewBridge and NSTextView
// without using the cocoa system.

// Associate a bridge with a textview in the hijacked init method.
void associateBridgeAndView(XTextViewBridge*, NSTextView*);
// Retreive the associated bridge object in the hijacked keydown method.
XTextViewBridge* getBridgeForView(NSTextView*);
// Free the bridge for a textview in the hijacked finalize method.
void removeBridgeForView(NSTextView*);