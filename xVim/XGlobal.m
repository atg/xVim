//
//  Created by Morris on 11-12-17.
//  Copyright (c) 2011年 http://warwithinme.com . All rights reserved.
//

// xVim uses 64-bit runtime features, which doesn't agree with Chocolat's 32-bit build
#ifdef __LP64__

#import "XGlobal.h"
#import "XTextViewBridge.h"
#import "XVimController.h"
#import <objc/runtime.h>

#import "CHFullTextView.h"
#import "CHTextViewController.h"


// Hijacking parameters
static Class bridgeClass = nil;
static XTextViewDelegate* delegate = nil;
static BOOL  createBridgeWhenNeeded = NO;


// Replace target selector of a target class with our function
// the overriden method is returned.
void* methodSwizzle(Class c, SEL sel, void* overrideFunction);
void* methodSwizzle(Class c, SEL sel, void* overrideMethod)
{
    Method origM   = class_getInstanceMethod(c, sel);
    void*  origIMP = method_getImplementation(origM);
    
    if (!class_addMethod(c, sel, (IMP)overrideMethod, method_getTypeEncoding(origM)))
    {
        method_setImplementation(origM, (IMP)overrideMethod);
    }
    return origIMP;
}


// ====================
// These methods are used to associate a XTextViewBridge and NSTextView
// without using the cocoa system.
// Associate a bridge with a textview in the hijacked init method.
void associateBridgeAndView(XTextViewBridge*, NSTextView*);
// Retreive the associated bridge object in the hijacked keydown method.
XTextViewBridge* getBridgeForView(NSTextView*);
// Free the bridge for a textview in the hijacked finalize method.
void removeBridgeForView(NSTextView*);
// --------------------

NSMutableDictionary* bridgeDict = 0;

void associateBridgeAndView(XTextViewBridge* b, NSTextView* tv)
{
    [bridgeDict setObject:b forKey:[NSValue valueWithNonretainedObject:tv]];
}
XTextViewBridge* getBridgeForView(NSTextView* tv)
{
    XTextViewBridge* b = [bridgeDict objectForKey:[NSValue valueWithNonretainedObject:tv]];
    if (b == nil && createBridgeWhenNeeded)
    {
        DLog(@"Creating a new bridge when needed");
        b = [[bridgeClass alloc] initWithTextView:tv];
        associateBridgeAndView(b, tv);
    }
    return b;
}
void removeBridgeForView(NSTextView* tv)
{
    [bridgeDict removeObjectForKey:[NSValue valueWithNonretainedObject:tv]];
}


// Original methods:
typedef void  (*O_Finalize)                  (id __unsafe_unretained, SEL);
typedef void  (*O_Dealloc)                   (id __unsafe_unretained, SEL);
typedef void  (*O_KeyDown)                   (id __unsafe_unretained, SEL, NSEvent*);
typedef void  (*O__DrawInsertionPointInRect) (NSTextView*, SEL, NSRect, NSColor*); // This one is for private api.
typedef void  (*O_DrawInsertionPointInRect)  (NSTextView*, SEL, NSRect, NSColor*, BOOL);
typedef id (*O_WillChangeSelection)       (id __unsafe_unretained, SEL, NSTextView*, NSArray* oldRanges, NSArray* newRanges);
typedef void  (*O_TextViewDidChangeSelection)(id __unsafe_unretained, SEL, NSNotification*);
typedef id (*O_SelRangeForProposedRange)  (NSTextView*, SEL, NSRange, NSSelectionGranularity);
static O_Finalize                  orig_finalize            = 0;
static O_Dealloc                   orig_dealloc             = 0;
static O_KeyDown                   orig_keyDown             = 0;
static O__DrawInsertionPointInRect orig_DIPIR_private       = 0;
static O_DrawInsertionPointInRect  orig_DIPIR               = 0;
static O_WillChangeSelection       orig_willChangeSelection = 0;
static O_TextViewDidChangeSelection orig_didChangeSelection = 0;
static O_SelRangeForProposedRange  orig_selRangeForProposedRange = 0;
// Hijackers:
// void  configureInsertionPointRect(NSTextView* view, NSRect*);
static void  hj_finalize(id __unsafe_unretained, SEL);
static void  hj_dealloc(id __unsafe_unretained, SEL);
static void  hj_keyDown(id __unsafe_unretained, SEL, NSEvent*);
static void  hj_DIPIR_private(NSTextView*, SEL, NSRect, NSColor*);
static void  hj_DIPIR(NSTextView*, SEL, NSRect, NSColor*, BOOL);
static id hj_willChangeSelection(id __unsafe_unretained, SEL, NSTextView*, NSArray* oldRanges, NSArray* newRanges);
static void  hj_didChangeSelection(id __unsafe_unretained, SEL, NSNotification*);
static id hj_selRangeForProposedRange(NSTextView*, SEL, NSRange, NSSelectionGranularity);

// Special init methods:
static void* orig_init = 0;

typedef id (*O_Init)          (id __unsafe_unretained, SEL);
typedef id (*O_InitWithCoder) (id __unsafe_unretained, SEL, id);
typedef id (*O_InitWithFrame) (id __unsafe_unretained, SEL, NSRect);
typedef id (*O_InitWithFTC)   (id __unsafe_unretained, SEL, NSRect, id);
typedef id (*O_InitWithFM)    (id __unsafe_unretained, SEL, NSRect, BOOL);

static id hj_init          (id __unsafe_unretained, SEL);
static id hj_initWithCoder (id __unsafe_unretained, SEL, id);
static id hj_initWithFrame (id __unsafe_unretained, SEL, NSRect);
static id hj_initWithFTC   (id __unsafe_unretained, SEL, NSRect, id);
static id hj_initWithFM    (id __unsafe_unretained, SEL, NSRect, BOOL);


// Hijack info:
/*
typedef struct s_HijackInfo {
    NSString* bridgeClassName;       // Can be nil
    NSString* textViewSubclassName;
    NSString* delegateClassName;     // Can be nil
    
    void*     initHijackFunc;        // If this is nil,
                                     // we create the bridge the first time we need it.
    NSString* initSelectorName;      // This can be nil if initHijackFunc is nil.
    
    NSString* appIdentifier;
} HijackInfo;

// The hijack info map
#define SUPPORTED_APP_COUNT 3

// The map:
static HijackInfo s_hijackInfo_map[SUPPORTED_APP_COUNT] =
{
    {nil,
        @"DVTSourceTextView",
        @"IDESourceCodeEditor", 
        hj_initWithCoder, 
        @"initWithCoder:",
        @"com.apple.dt.Xcode"}, // XCode
    
    {nil,
        @"EKTextView",
        nil,
        hj_initWithFM,
        @"initWithFrame:makeFieldEditor:",
        @"com.macrabbit.Espresso"}, // Espresso
    
    {@"XChocolatBridge",
        @"CHFullTextView",
        @"CHTextViewController",
        nil,
        nil,
        @"com.chocolatapp.Chocolat"} // Chocolat use GC, but finalize never calls.
};
*/

// The entry point of this plugin.
// In the load method, we call XXXBridge's(subclass of XTextViewBridge) hijack class method
// to inject our code to init/dealloc/finalize/keydown method.
// Basically:
// In init, we alloc a new XXXBridge and associate it with the hijacked textview.
// In dealloc and finalize, we free that XXXBridge.
// In keydown, we ask the associated XXXBridge to process the keydown method.
@interface XVimPlugin : NSObject
@end
@implementation XVimPlugin
// The entry point of our plugin
+(void) load
{
// Disable this code if this is being loaded into a cooperative editor
#ifndef VIM_COOPERATIVE
    // [XVimController load];
    bridgeDict = [[NSMutableDictionary alloc] init];
    
    // Warning: When hijacking, we must not hijack NSTextView
    // directly. Because that will affect line editor control.
    
    NSString* id = [[NSBundle mainBundle] bundleIdentifier];
    for (int i = 0; i < SUPPORTED_APP_COUNT; ++i)
    {
        HijackInfo* info = s_hijackInfo_map + i;
        
        if ([id isEqualToString:info->appIdentifier])
        {
            DLog(@"xVim hijacking app: %@", id);
            
            bridgeClass = info->bridgeClassName == nil ? 
                              [XTextViewBridge class] : NSClassFromString(info->bridgeClassName);
            
            Class tvSubClass  = NSClassFromString(info->textViewSubclassName);
            
            if (info->initHijackFunc)
            {
                orig_init = methodSwizzle(tvSubClass, 
                                          NSSelectorFromString(info->initSelectorName), 
                                          info->initHijackFunc);
            } else {
                createBridgeWhenNeeded = YES;
            }
            
            
            
            orig_dealloc  = methodSwizzle(tvSubClass, @selector(dealloc),  hj_dealloc);
            orig_finalize = methodSwizzle(tvSubClass, @selector(finalize), hj_finalize);
            
            orig_keyDown  = methodSwizzle(tvSubClass, @selector(keyDown:), hj_keyDown);
            orig_DIPIR    = methodSwizzle(tvSubClass, 
                                          @selector(drawInsertionPointInRect:color:turnedOn:), 
                                          hj_DIPIR);
            orig_DIPIR_private = methodSwizzle(tvSubClass, 
                                               @selector(_drawInsertionPointInRect:color:), 
                                               hj_DIPIR_private);
            orig_selRangeForProposedRange = methodSwizzle(tvSubClass,
                                                          @selector(selectionRangeForProposedRange:granularity:),
                                                          hj_selRangeForProposedRange);
            
            if (info->delegateClassName == nil)
            {
                delegate = [[XTextViewDelegate alloc] init];
            } else {
                
                Class delegateClass = NSClassFromString(info->delegateClassName);
                orig_willChangeSelection = methodSwizzle(delegateClass, 
                                                         @selector(textView:willChangeSelectionFromCharacterRanges:toCharacterRanges:), 
                                                         hj_willChangeSelection);
                orig_didChangeSelection = methodSwizzle(delegateClass, 
                                                        @selector(textViewDidChangeSelection:), 
                                                        hj_didChangeSelection);
            }
            
            break;
        }
    }
#endif
}
@end

// ========== XTextViewBridge ==========
@interface XTextViewBridge()
{
@private
    XVimController*    controller;
    __weak CHTextViewController* tvc;
//    __weak NSTextView* targetView;
}
@end
@implementation XTextViewBridge

-(NSTextView*)     targetView    { return tvc.textView; }
-(XVimController*) vimController { return controller; }

-(XTextViewBridge*) initWithTextView:(CHFullTextView*) view
{
    if (self = [super init]) {
        tvc = view.controller; // Must assigned this before creating the XVimController.
        controller = [[XVimController alloc] initWithBridge:self];
    }
    return self;
}

-(void)    dealloc  { DLog(@"Deallocing XTexViewBridge: %@", self);  }
-(void)    processKeyEvent:(NSEvent*)event { [controller processKeyEvent:event]; }
-(BOOL)    closePopup { return NO; }

-(void) handleFakeKeyEvent:(NSEvent*) fakeEvent {
    CHFullTextView* tv = (CHFullTextView*)(self.targetView);
    // Give them a chance to cooperate with us
    if ([tv respondsToSelector:@selector(handleVimKeyEvent:)]) {
        [tv performSelector:@selector(handleVimKeyEvent:) withObject:fakeEvent];
    }
    // Pleading the 5th? Hit 'em with the swizzle stick. 
    else if (orig_keyDown) {
        orig_keyDown(tv, @selector(keyDown:), fakeEvent);
    }
}

-(BOOL) ignoreString:(NSString*) string selection:(NSRange) range
{
    // In Xcode, the user can select a token which is generated by the editor
    // The selection will be a char an it's 0xFFFC
    return range.length == 1 && [string characterAtIndex:range.location] == 0xFFFC;
}

@end

@implementation XTextViewDelegate
-(NSArray*) textView:(NSTextView*) view willChangeSelectionFromCharacterRanges:(NSArray*) old toCharacterRanges:(NSArray*) new
{
    return hj_willChangeSelection(nil, nil, view, old, new);
}
-(void) textViewDidChangeSelection:(NSNotification*) aNotification
{
    hj_didChangeSelection(nil, nil, aNotification);
}
@end

@implementation XChocolatBridge

-(BOOL) ignoreString:(NSString*) string selection:(NSRange) range
{
    return NO;
}

@end

// ========== General Hijack Functions ==========
void configureInsertionPointRect(XTextViewBridge* bridge, NSTextView* view, NSRect* rect)
{
    XVimController* controller = [bridge vimController];
    
    VimMode mode = [controller mode];
    if (mode == InsertMode) {
        rect->size.width = 1;
    } else {
        
        NSRange   range  = [view selectedRange];
        NSString* string = [[view textStorage] string];
        
        if (range.location + 1 >= [string length]) {
            rect->size.width = 8;
        } else {
            unichar ch = [string characterAtIndex:range.location];
            
            if ((ch >= 0xA && ch <= 0xD) || ch == 0x85) {
                // This is new line
                rect->size.width = 8;
            } else {
                NSUInteger glyphIndex = [[view layoutManager] glyphIndexForCharacterAtIndex:range.location];
                NSRect glyphRect = [[view layoutManager] boundingRectForGlyphRange:NSMakeRange(glyphIndex, 1)
                                                                   inTextContainer:[view textContainer]];
                rect->size.width = glyphRect.size.width;
            }
        }
            
        if (mode == ReplaceMode || mode == SingleReplaceMode) {
            rect->origin.y += rect->size.height;
            rect->origin.y -= 3;
            rect->size.height = 3;
        }
    }
}

void hj_DIPIR_private(NSTextView* self, SEL sel, NSRect rect, NSColor* color)
{
    XTextViewBridge* bridge = getBridgeForView(self);
    configureInsertionPointRect(bridge, self, &rect);
    orig_DIPIR_private(self, sel, rect, color);
}

void hj_DIPIR(NSTextView* self, SEL sel, NSRect rect, NSColor* color, BOOL turnedOn)
{
    XTextViewBridge* bridge = getBridgeForView(self);
    configureInsertionPointRect(bridge, self, &rect);
    orig_DIPIR(self, sel, rect, color, turnedOn);
}

void hj_finalize(id __unsafe_unretained self, SEL sel)
{
    DLog(@"HJ_Finalize");
    removeBridgeForView(self);
    if(orig_finalize) orig_finalize(self, sel);
}

void hj_dealloc(id __unsafe_unretained self, SEL sel)
{
    DLog(@"Hj_Dealloc");
    removeBridgeForView(self);
    if(orig_dealloc) orig_dealloc(self, sel);
}

void hj_keyDown(id __unsafe_unretained self, SEL sel, NSEvent* event)
{
    DLog(@"HJ_KeyDown");
    [getBridgeForView(self) processKeyEvent:event];
}

id hj_willChangeSelection(id __unsafe_unretained self, SEL sel, NSTextView* view, NSArray* oldRanges, NSArray* newRanges)
{
    XTextViewBridge* bridge = getBridgeForView(view);
    if (bridge != nil) {
        newRanges = [[bridge vimController] selectionChangedFrom:oldRanges to:newRanges];
    }
    if (orig_willChangeSelection) { return orig_willChangeSelection(self, sel, view, oldRanges, newRanges); }
    return newRanges;
}

void hj_didChangeSelection(id __unsafe_unretained self, SEL sel, NSNotification* n)
{
    XTextViewBridge* bridge = getBridgeForView([n object]);
    if (bridge != nil) {
        [[bridge vimController] didChangedSelection];
    }
    if (orig_didChangeSelection) { orig_didChangeSelection(self, sel, n); }
}

id hj_selRangeForProposedRange(NSTextView* self, SEL sel, NSRange proposed, NSSelectionGranularity g)
{
    [[getBridgeForView(self) vimController] selRangeForProposed:proposed];
    return orig_selRangeForProposedRange(self, sel, proposed, g);
}


// ========== Special Init Methods ==========
static id hj_init(id __unsafe_unretained self, SEL sel)
{
    DLog(@"HJ_init");
    
    O_Init o_init = (O_Init) orig_init;
    NSTextView* r = o_init(self, sel);
    
    if (r == nil) { return nil; }
    
    XTextViewBridge* bridge = [[bridgeClass alloc] initWithTextView:r];
    
    if (bridge != nil) {
        associateBridgeAndView(bridge, r);
    }
    if (delegate != nil) { [r setDelegate:delegate]; }
    
    return CFBridgingRelease(CFBridgingRetain(r));
}

static id hj_initWithCoder(id __unsafe_unretained self, SEL sel, id p1)
{
    DLog(@"HJ_initWithCoder");
    
    O_InitWithCoder o_init = (O_InitWithCoder) orig_init;
    NSTextView* r = o_init(self, sel, p1);
    
    if (r == nil) { return nil; }
    
    XTextViewBridge* bridge = [[bridgeClass alloc] initWithTextView:r];
    
    if (bridge != nil) {
        associateBridgeAndView(bridge, r);
    }
    if (delegate != nil) { [r setDelegate:delegate]; }
    
    return CFBridgingRelease(CFBridgingRetain(r));
}

static id hj_initWithFrame(id __unsafe_unretained self, SEL sel, NSRect p1)
{
    DLog(@"HJ_initWithFrame");
    
    O_InitWithFrame o_init = (O_InitWithFrame) orig_init;
    NSTextView* r = o_init(self, sel, p1);
    
    if (r == nil) { return nil; }
    
    XTextViewBridge* bridge = [[bridgeClass alloc] initWithTextView:r];
    
    if (bridge != nil) {
        associateBridgeAndView(bridge, r);
    }
    if (delegate != nil) { [r setDelegate:delegate]; }
    
    return CFBridgingRelease(CFBridgingRetain(r));
}

static id hj_initWithFTC(id __unsafe_unretained self, SEL sel, NSRect p1, id p2)
{
    DLog(@"HJ_initWithFTC");
    
    O_InitWithFTC o_init = (O_InitWithFTC) orig_init;
    NSTextView* r = o_init(self, sel, p1, p2);
    
    if (r == nil) { return nil; }
    
    XTextViewBridge* bridge = [[bridgeClass alloc] initWithTextView:r];
    
    if (bridge != nil) {
        associateBridgeAndView(bridge, r);
    }
    if (delegate != nil) { [r setDelegate:delegate]; }
    
    return CFBridgingRelease(CFBridgingRetain(r));
}

static id hj_initWithFM(id __unsafe_unretained self, SEL sel, NSRect p1, BOOL makeFieldEditor)
{
    DLog(@"HJ_initWithFM");
    
    O_InitWithFM o_init = (O_InitWithFM) orig_init;
    NSTextView* r = o_init(self, sel, p1, makeFieldEditor);
    
    if (makeFieldEditor == YES || r == nil) { return r; }
    
    XTextViewBridge* bridge = [[bridgeClass alloc] initWithTextView:r];
    
    if (bridge != nil) {
        associateBridgeAndView(bridge, r);
    }
    if (delegate != nil) { [r setDelegate:delegate]; }
    
    return CFBridgingRelease(CFBridgingRetain(r));
}

#endif
