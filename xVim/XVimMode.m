//
//  Created by Morris on 11-12-16.
//  Copyright (c) 2011年 http://warwithinme.com . All rights reserved.
//

#import "XGlobal.h"
#import "XVimMode.h"
#import "XVimController.h"
#import "XTextViewBridge.h"
#import "vim.h"

@implementation XVimModeHandler
-(void) enter{}
-(void) reset{}
-(BOOL) processKey:(unichar)k modifiers:(NSUInteger)f forController:(XVimController*) c { return NO; }
@end

@implementation XVimVisualModeHandler
@end
@implementation XVimExModeHandler
@end



@implementation XVimInsertModeHandler
-(BOOL) processKey:(unichar)key modifiers:(NSUInteger)flags forController:(XVimController*)controller
{
    if (key == XEsc && (flags & XImportantMask) == 0)
    {
        XTextViewBridge* bridge = [controller bridge];
        if ([bridge closePopup] == NO)
        {
            // There's no popup, so we now switch to Normal Mode.
            NSTextView* view     = [bridge targetView];
            NSString*   string   = [[view textStorage] string];
            NSUInteger  index    = [view selectedRange].location;
            NSUInteger  maxIndex = [string length] - 1;
            if (index > maxIndex) {
                index = maxIndex;
            }
            if (index > 0) {
                if (testNewLine([string characterAtIndex:index - 1]) == NO) {
                    [view setSelectedRange:NSMakeRange(index - 1, 0)];
                }
            }
            
            [controller switchToMode:NormalMode];
        }
        return YES;
    }
    
    if(flags == (XMaskNumeric | XMaskFn))
    {
        NSTextView* view     = [[controller bridge] targetView];
        NSString*   string   = [[view textStorage] string];
        NSUInteger  index    = [view selectedRange].location;
        NSUInteger  maxIndex = [string length] - 1;
        if (key == NSLeftArrowFunctionKey)
        {
            if (index > 0 && testNewLine([string characterAtIndex:index - 1]) == NO) {
                return NO;
            } else {
                return YES;
            }
        } else if (key == NSRightArrowFunctionKey) {
            if (index <= maxIndex && testNewLine([string characterAtIndex:index]) == NO) {
                return NO;
            } else {
                return YES;
            }
        }
    }
    
    return NO;
}
@end



@implementation XVimReplaceModeHandler
-(BOOL) processKey:(unichar)key modifiers:(NSUInteger)flags forController:(XVimController*)controller
{
    if ((flags & XImportantMask) != 0) {
        // This may not be a visible character, let the NSTextView process it.
        return NO;
    }
    
    if (key == XEsc)
    {
        if ([[controller bridge] closePopup] == NO) {
            [controller switchToMode:NormalMode];
        }
        return YES;
    }
    
    // Replace mode behaviour:
    // 1. Typing will replace the character after the caret.
    // 2. If the character after the caret is newline, we insert char instead of replacing.
    // 3. We can move the caret by using arrow keys and home key and ...
    // 4. Deleting a replaced character is restoring it (We can't restore the char after
    //    moving the caret)
    
    // Extra: if the caret doesn't moved, all the change should be grouped together, so that
    //        undo once can return to the state before replace mode.
    
    // FIXME: Almost none of the beviour above is supported right now.
    
    NSTextView* hijackedView = [[controller bridge] targetView];
    NSString*   string       = [[hijackedView textStorage] string];
    NSUInteger  maxIndex     = [string length] - 1;
    NSRange     range        = [hijackedView selectedRange];
    if (range.location >= maxIndex || testNewLine([string characterAtIndex:range.location]))
    {
        // Let the textview process the key input, that is inserting the char.
        return NO;
    } else {
        range.length = 1;
        NSString* ch = [NSString stringWithCharacters:&key length:1];
        [hijackedView insertText:ch replacementRange:range];
        return YES;
    }
}
@end



@implementation XVimSReplaceModeHandler
-(BOOL) processKey:(unichar)key modifiers:(NSUInteger)flags forController:(XVimController*)controller
{
    if ((flags & XImportantMask) != 0) {
        // This may not be a visible character, let the NSTextView process it.
        return NO;
    }
    
    if (key == XEsc)
    {
        if ([[controller bridge] closePopup] == NO) {
            [controller switchToMode:NormalMode];
        }
        return YES;
    }
    
    NSTextView* hijackedView = [[controller bridge] targetView];
    NSRange range = [hijackedView selectedRange];
    range.length = 1;
    
    NSString* ch = [NSString stringWithCharacters:&key length:1];
    [hijackedView insertText:ch replacementRange:range];
    range.length = 0;
    [hijackedView setSelectedRange:range];
    [controller switchToMode:NormalMode];
    return YES;
}
@end
