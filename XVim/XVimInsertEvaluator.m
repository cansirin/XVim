//
//  XVimInsertEvaluator.m
//  XVim
//
//  Created by Shuichiro Suzuki on 3/1/12.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import "XVimInsertEvaluator.h"
#import "XVimSourceView.h"
#import "XVimSourceView+Vim.h"
#import "XVimSourceView+Xcode.h"
#import "XVimWindow.h"
#import "XVim.h"
#import "Logger.h"
#import "XVimKeyStroke.h"
#import "XVimKeymapProvider.h"
#import "XVimVisualEvaluator.h"

@interface XVimInsertEvaluator()
@property (nonatomic) NSRange startRange;
@property (nonatomic) BOOL movementKeyPressed;
@property (nonatomic, strong) NSString *lastInsertedText;
@property (nonatomic, readonly, strong) NSArray *cancelKeys;
@property (nonatomic, readonly, strong) NSArray *movementKeys;
@end

@implementation XVimInsertEvaluator

@synthesize startRange = _startRange;
@synthesize cancelKeys = _cancelKeys;
@synthesize movementKeys = _movementKeys;
@synthesize lastInsertedText = _lastInsertedText;
@synthesize movementKeyPressed = _movementKeyPressed;



- (id)initWithContext:(XVimEvaluatorContext*)context
{
    return [self initWithContext:context oneCharMode:NO];
}

- (id)initWithContext:(XVimEvaluatorContext*)context
		  oneCharMode:(BOOL)oneCharMode
{
    self = [super initWithContext:context];
    if (self) {
        _lastInsertedText = @"";
        _oneCharMode = oneCharMode;
        _movementKeyPressed = NO;
        _insertedEventsAbort = NO;
        _cancelKeys = [NSArray arrayWithObjects:
                       [NSValue valueWithPointer:@selector(ESC:)],
                       [NSValue valueWithPointer:@selector(C_LSQUAREBRACKET:)],
                       [NSValue valueWithPointer:@selector(C_c:)],
                       nil];
        _movementKeys = [NSArray arrayWithObjects:
                         [NSValue valueWithPointer:@selector(Up:)],
                         [NSValue valueWithPointer:@selector(Down:)],
                         [NSValue valueWithPointer:@selector(Left:)],
                         [NSValue valueWithPointer:@selector(Right:)],
                         nil];
    }
    return self;
}

- (NSString*)modeString
{
	return @"-- INSERT --";
}

- (void)becameHandlerInWindow:(XVimWindow*)window{
	[super becameHandlerInWindow:window];
    self.startRange = [[window sourceView] selectedRange];
}

- (XVimEvaluator*)handleMouseEvent:(NSEvent*)event inWindow:(XVimWindow*)window
{
	NSRange range = [[window sourceView] selectedRange];
	return range.length == 0 ? self : [[XVimVisualEvaluator alloc] initWithContext:[[XVimEvaluatorContext alloc] init]
																			  mode:MODE_CHARACTER 
																	  withRange:range];
}

// Move to insert mode, have it call insertion point on sourceView
- (void)drawInsertionPointInRect:(NSRect)rect color:(NSColor*)color inWindow:(XVimWindow*)window heightRatio:(float)heightRatio
{
	if (_oneCharMode)
	{
		[super drawInsertionPointInRect:rect color:color inWindow:window heightRatio:.25];
	}
	else
	{
		XVimSourceView *sourceView = [window sourceView];
		[sourceView drawInsertionPointInRect:rect color:color];
	}
}

- (NSRange)restrictSelectedRange:(NSRange)range inWindow:(XVimWindow*)window
{
	return range;
}

- (XVimKeymap*)selectKeymapWithProvider:(id<XVimKeymapProvider>)keymapProvider
{
	return [keymapProvider keymapForMode:MODE_INSERT];
}

- (NSString*)getInsertedTextInWindow:(XVimWindow*)window {
    XVimSourceView* view = [window sourceView];
    NSUInteger startLoc = self.startRange.location;
    NSUInteger endLoc = [view selectedRange].location;
    NSRange textRange = NSMakeRange(NSNotFound, 0);
    
    if( [[view string] length] == 0 ){
        return @"";
    }
    // If some text are deleted while editing startLoc could be out of range of the view's string.
    if( ( startLoc >= [[view string] length] ) ){
        startLoc = [[view string] length] - 1;
    }
    
    // Is this really what we want to do?
    // This means just moving cursor forward or backward and escape from insert mode generates the inserted test this method return.
    //    -> The answer is 'OK'. see onMovementKeyPressed: method how it treats the inserted text.
    if (endLoc > startLoc ){
        textRange = NSMakeRange(startLoc, endLoc - startLoc);
    }else{
        textRange = NSMakeRange(endLoc , startLoc - endLoc);
    }
    
	XVimSourceView *sourceView = [window sourceView];
    NSString *text = [[sourceView string] substringWithRange:textRange];
    return text;
    
}

- (void)recordTextIntoRegister:(XVimRegister*)xregister inWindow:(XVimWindow*)window {
    NSString *text = [self getInsertedTextInWindow:window];
    if (text.length > 0){
        [xregister appendText:text];
    }
}

- (void)onMovementKeyPressed:(XVimWindow*)window {
    // TODO: we also have to handle when cursor is movieng by mouse clicking.
    //       it should have the same effect on movementKeyPressed property.
    _insertedEventsAbort = YES;
    if (!self.movementKeyPressed){
        self.movementKeyPressed = YES;
        
        // Store off any needed text
        self.lastInsertedText = [self getInsertedTextInWindow:window];
        [self recordTextIntoRegister:[XVim instance].recordingRegister inWindow:window];
    }
    
    // Store off the new start range
    self.startRange = [[window sourceView] selectedRange];
}

- (void)willEndHandlerInWindow:(XVimWindow*)window 
{
	[super willEndHandlerInWindow:window];
	XVimSourceView *sourceView = [window sourceView];
	
    if( !_insertedEventsAbort ){
        NSString *text = [self getInsertedTextInWindow:window];
        for( int i = 0 ; i < [self numericArg]-1; i++ ){
            [sourceView insertText:text];
        }
    }
    
    // Store off any needed text
    XVim *xvim = [XVim instance];
    if (!self.movementKeyPressed){
        [self recordTextIntoRegister:xvim.recordingRegister inWindow:window];
        [self recordTextIntoRegister:xvim.repeatRegister inWindow:window];
    }else if(self.lastInsertedText.length > 0){
        [xvim.repeatRegister appendText:self.lastInsertedText];
    }
    [sourceView hideCompletions];
	
	// Set selection to one-before-where-we-were
	NSUInteger insertionPoint = [self insertionPointInWindow:window];
	NSUInteger headOfLine = [sourceView headOfLine:insertionPoint];
	if (insertionPoint > 0 
		&& headOfLine != insertionPoint && headOfLine != NSNotFound
		&& !_oneCharMode)
	{
		--insertionPoint;
	}
	[sourceView setSelectedRange:NSMakeRange(insertionPoint, 0)];
	
	NSRange r = [[window sourceView] selectedRange];
	NSValue *v =[NSValue valueWithRange:r];
	[[window getLocalMarks] setValue:v forKey:@"."];

	[[window sourceView] adjustCursorPosition];
}

- (XVimEvaluator*)eval:(XVimKeyStroke*)keyStroke inWindow:(XVimWindow*)window{
    XVimEvaluator *nextEvaluator = self;
    SEL keySelector = [keyStroke selectorForInstance:self];
    if (keySelector){
        nextEvaluator = [self performSelector:keySelector withObject:window];
    }else if(self.movementKeyPressed){
        // Flag movement key as not pressed until the next movement key is pressed
        self.movementKeyPressed = NO;
        
        // Store off the new start range
        self.startRange = [[window sourceView] selectedRange];
    }
    
    if (nextEvaluator != nil){
        NSEvent *event = [keyStroke toEvent];
        if (_oneCharMode == TRUE) {
            NSRange save = [[window sourceView] selectedRange];
            for (NSUInteger i = 0; i < [self numericArg]; ++i) {
                [[window sourceView] deleteForward];
                [[window sourceView] keyDown:event];
                
                save.location += 1;
                [[window sourceView] setSelectedRange:save];
            }
            save.location -= 1;
            [[window sourceView] setSelectedRange:save];
            nextEvaluator = nil;
        } else if ([self windowShouldReceive:keySelector]) {
            [[window sourceView] keyDown:event];
        }
    }
    return nextEvaluator;
}

- (BOOL)windowShouldReceive:(SEL)keySelector {
  return ![NSStringFromSelector(keySelector) isEqualToString:@"C_e:"] ||
         ![NSStringFromSelector(keySelector) isEqualToString:@"C_y:"];
}

- (XVimEvaluator*)ESC:(XVimWindow*)window{
    return nil;
}

- (XVimEvaluator*)C_LSQUAREBRACKET:(XVimWindow*)window{
    return nil;
}

- (XVimEvaluator*)C_c:(XVimWindow*)window{
    return nil;
}

- (XVimEvaluator*)Up:(XVimWindow*)window{
    [self onMovementKeyPressed:window];
    return self;
}

- (XVimEvaluator*)Down:(XVimWindow*)window{
    [self onMovementKeyPressed:window];
    return self;
}

- (XVimEvaluator*)Left:(XVimWindow*)window{
    [self onMovementKeyPressed:window];
    return self;
}

- (XVimEvaluator*)Right:(XVimWindow*)window{
    [self onMovementKeyPressed:window];
    return self;
}

// TODO - I think I'll have to grab the glyph above/below using rectangles, etc.
- (XVimEvaluator*)C_y:(XVimWindow*)window{
  NSLog(@"XVimInsertEvaluator [line 267] - C_y called");
  [self insertionPointInWindow:window];
  
  
  [[window sourceView] insertText:@"###"];
  return self;
}

// TODO - C_e is mapped to "end of paragraph" by default in Xcode - not sure how to preclude this from happening after XVim does the insertion
- (XVimEvaluator*)C_e:(XVimWindow*)window{
  NSLog(@"XVimInsertEvaluator [line 272] - C_e called");
  [[window sourceView] insertText:@"%%%"];
  return self;
}

- (XVimRegisterOperation)shouldRecordEvent:(XVimKeyStroke*)keyStroke inRegister:(XVimRegister*)xregister{
    // Do not record key strokes for insert. Instead we will directly append the inserted text into the register.
    NSValue *keySelector = [NSValue valueWithPointer:[keyStroke selectorForInstance:self]];
    if ([self.cancelKeys containsObject:keySelector]){
        return REGISTER_APPEND;
    }else if (xregister.isReadOnly == NO && ([self.movementKeys containsObject:keySelector] || _oneCharMode)){
        return REGISTER_APPEND;
    }else if (xregister.isRepeat && _oneCharMode){
        return REGISTER_APPEND;
    }
    
    return REGISTER_IGNORE;
}

@end
