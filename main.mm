// ============================================================
//  Notepad — a minimal plain-text editor for macOS (arm64)
//  Build:  make   (see Makefile)
//  Deps:   Cocoa, WebKit (system), clang++ / Apple LLVM
// ============================================================

#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

// ============================================================
// MARK: - Line Number Ruler View
// ============================================================

@interface LineNumberRulerView : NSRulerView
@property (nonatomic, weak) NSTextView *clientTextView;
@end

@implementation LineNumberRulerView

static const CGFloat kRulerWidth = 50.0;

- (instancetype)initWithScrollView:(NSScrollView *)sv clientTextView:(NSTextView *)tv {
    self = [super initWithScrollView:sv orientation:NSVerticalRuler];
    if (self) {
        _clientTextView = tv;
        self.clientView  = tv;
        self.ruleThickness = kRulerWidth;
        [[NSNotificationCenter defaultCenter]
            addObserver:self
               selector:@selector(textDidChange:)
                   name:NSTextStorageDidProcessEditingNotification
                 object:tv.textStorage];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)textDidChange:(NSNotification *)note {
    [self setNeedsDisplay:YES];
}

- (void)drawHashMarksAndLabelsInRect:(NSRect)rect {
    NSTextView *tv = self.clientTextView;
    if (!tv) return;

    NSLayoutManager *lm  = tv.layoutManager;
    (void)tv.textContainer;
    NSString        *str = tv.string;
    NSUInteger       len = str.length;

    [[NSColor colorWithWhite:0.95 alpha:1.0] setFill];
    NSRectFill(self.bounds);

    [[NSColor colorWithWhite:0.75 alpha:1.0] setStroke];
    [NSBezierPath strokeLineFromPoint:NSMakePoint(kRulerWidth - 0.5, 0)
                              toPoint:NSMakePoint(kRulerWidth - 0.5, self.bounds.size.height)];

    NSDictionary *attrs = @{
        NSFontAttributeName            : [NSFont monospacedDigitSystemFontOfSize:11.0
                                                                           weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : [NSColor colorWithWhite:0.5 alpha:1.0]
    };

    NSPoint containerOrigin = tv.textContainerOrigin;
    NSUInteger glyphIdx     = 0;
    NSUInteger lineNumber   = 1;

    while (glyphIdx < lm.numberOfGlyphs) {
        NSRange lineGlyphRange;
        NSRect  lineRect = [lm lineFragmentRectForGlyphAtIndex:glyphIdx
                                                 effectiveRange:&lineGlyphRange];

        CGFloat yInRuler = lineRect.origin.y + containerOrigin.y
                         - self.scrollView.documentVisibleRect.origin.y;

        if (yInRuler + lineRect.size.height >= rect.origin.y &&
            yInRuler <= rect.origin.y + rect.size.height) {

            NSString *label   = [NSString stringWithFormat:@"%lu", (unsigned long)lineNumber];
            NSSize    labSize = [label sizeWithAttributes:attrs];
            NSRect    labRect = NSMakeRect(kRulerWidth - labSize.width - 6.0,
                                          yInRuler + (lineRect.size.height - labSize.height) / 2.0,
                                          labSize.width, labSize.height);
            [label drawInRect:labRect withAttributes:attrs];
        }

        NSRange charRange = [lm characterRangeForGlyphRange:lineGlyphRange
                                           actualGlyphRange:nil];
        NSUInteger nextCharIdx = NSMaxRange(charRange);

        if (nextCharIdx < len) {
            unichar ch = [str characterAtIndex:nextCharIdx - 1];
            if (ch == '\n') lineNumber++;
        }

        glyphIdx = NSMaxRange(lineGlyphRange);

        if (glyphIdx < lm.numberOfGlyphs) {
            NSRange nextCharRange = [lm characterRangeForGlyphRange:
                                        NSMakeRange(glyphIdx, 1)
                                               actualGlyphRange:nil];
            NSUInteger prevEnd   = NSMaxRange(charRange);
            NSUInteger nextStart = nextCharRange.location;
            for (NSUInteger i = prevEnd; i < nextStart && i < len; i++) {
                if ([str characterAtIndex:i] == '\n') lineNumber++;
            }
        }
    }

    if (len == 0) {
        NSString *label   = @"1";
        NSSize    labSize = [label sizeWithAttributes:attrs];
        NSRect    labRect = NSMakeRect(kRulerWidth - labSize.width - 6.0,
                                      containerOrigin.y - self.scrollView.documentVisibleRect.origin.y
                                          + (tv.font.ascender + tv.font.descender) / 2.0,
                                      labSize.width, labSize.height);
        [label drawInRect:labRect withAttributes:attrs];
    }
}

@end

// ============================================================
// MARK: - Find & Replace Panel Controller
// ============================================================

@interface FindReplaceController : NSObject <NSTextFieldDelegate>
@property (nonatomic, strong) NSPanel       *panel;
@property (nonatomic, strong) NSTextField   *findField;
@property (nonatomic, strong) NSTextField   *replaceField;
@property (nonatomic, weak)   NSTextView    *targetTextView;
@property (nonatomic, assign) NSUInteger     lastFoundLocation;
- (instancetype)initWithTargetTextView:(NSTextView *)tv;
- (void)showPanel;
@end

@implementation FindReplaceController

- (instancetype)initWithTargetTextView:(NSTextView *)tv {
    self = [super init];
    if (self) {
        _targetTextView  = tv;
        _lastFoundLocation = 0;
        [self buildPanel];
    }
    return self;
}

- (void)buildPanel {
    NSRect panelFrame = NSMakeRect(0, 0, 420, 140);
    _panel = [[NSPanel alloc] initWithContentRect:panelFrame
                                        styleMask:NSWindowStyleMaskTitled
                                                 | NSWindowStyleMaskClosable
                                                 | NSWindowStyleMaskUtilityWindow
                                          backing:NSBackingStoreBuffered
                                            defer:NO];
    _panel.title       = @"Find & Replace";
    _panel.floatingPanel = YES;
    _panel.becomesKeyOnlyIfNeeded = YES;

    NSView *content = _panel.contentView;

    NSTextField *findLabel    = [self labelWithString:@"Find:"    frame:NSMakeRect(12, 96, 70, 20)];
    NSTextField *replaceLabel = [self labelWithString:@"Replace:" frame:NSMakeRect(12, 64, 70, 20)];
    [content addSubview:findLabel];
    [content addSubview:replaceLabel];

    _findField = [[NSTextField alloc] initWithFrame:NSMakeRect(88, 93, 316, 24)];
    _findField.delegate = self;
    [content addSubview:_findField];

    _replaceField = [[NSTextField alloc] initWithFrame:NSMakeRect(88, 61, 316, 24)];
    [content addSubview:_replaceField];

    NSButton *btnFind    = [self buttonWithTitle:@"Find Next"   action:@selector(findNext:)   frame:NSMakeRect(12,  16, 100, 32)];
    NSButton *btnReplace = [self buttonWithTitle:@"Replace"     action:@selector(replaceOne:)  frame:NSMakeRect(120, 16, 100, 32)];
    NSButton *btnAll     = [self buttonWithTitle:@"Replace All" action:@selector(replaceAll:)  frame:NSMakeRect(228, 16, 108, 32)];
    NSButton *btnClose   = [self buttonWithTitle:@"Close"       action:@selector(closePanel:)  frame:NSMakeRect(344, 16,  64, 32)];

    for (NSButton *b in @[btnFind, btnReplace, btnAll, btnClose])
        [content addSubview:b];

    btnFind.keyEquivalent = @"\r";
}

- (NSTextField *)labelWithString:(NSString *)s frame:(NSRect)r {
    NSTextField *tf = [[NSTextField alloc] initWithFrame:r];
    tf.stringValue   = s;
    tf.editable      = NO;
    tf.bordered      = NO;
    tf.backgroundColor = [NSColor clearColor];
    tf.alignment     = NSTextAlignmentRight;
    return tf;
}

- (NSButton *)buttonWithTitle:(NSString *)title action:(SEL)action frame:(NSRect)frame {
    NSButton *btn = [[NSButton alloc] initWithFrame:frame];
    btn.title  = title;
    btn.target = self;
    btn.action = action;
    btn.bezelStyle = NSBezelStyleRounded;
    return btn;
}

- (void)showPanel {
    [_panel center];
    [_panel makeKeyAndOrderFront:nil];
    [_findField becomeFirstResponder];
}

- (void)controlTextDidChange:(NSNotification *)note {
    _lastFoundLocation = 0;
}

- (IBAction)findNext:(id)sender {
    NSString *needle = _findField.stringValue;
    if (needle.length == 0) return;

    NSString *haystack = _targetTextView.string;
    NSUInteger searchFrom = _lastFoundLocation;

    NSRange sel = _targetTextView.selectedRange;
    if (sel.length > 0 && sel.location == _lastFoundLocation)
        searchFrom = NSMaxRange(sel);

    NSRange found = [haystack rangeOfString:needle
                                    options:NSCaseInsensitiveSearch
                                      range:NSMakeRange(searchFrom, haystack.length - searchFrom)];

    if (found.location == NSNotFound && searchFrom > 0) {
        found = [haystack rangeOfString:needle
                                options:NSCaseInsensitiveSearch
                                  range:NSMakeRange(0, haystack.length)];
    }

    if (found.location != NSNotFound) {
        _lastFoundLocation = found.location;
        [_targetTextView setSelectedRange:found];
        [_targetTextView scrollRangeToVisible:found];
    } else {
        NSBeep();
    }
}

- (IBAction)replaceOne:(id)sender {
    NSRange sel = _targetTextView.selectedRange;
    NSString *needle = _findField.stringValue;
    if (needle.length == 0 || sel.length == 0) { [self findNext:sender]; return; }

    NSString *selected = [_targetTextView.string substringWithRange:sel];
    if ([selected caseInsensitiveCompare:needle] == NSOrderedSame) {
        NSString *replacement = _replaceField.stringValue;
        if ([_targetTextView shouldChangeTextInRange:sel replacementString:replacement]) {
            [_targetTextView.textStorage replaceCharactersInRange:sel withString:replacement];
            [_targetTextView didChangeText];
            _lastFoundLocation = sel.location + replacement.length;
        }
    }
    [self findNext:sender];
}

- (IBAction)replaceAll:(id)sender {
    NSString *needle      = _findField.stringValue;
    NSString *replacement = _replaceField.stringValue;
    if (needle.length == 0) return;

    NSString *original = _targetTextView.string;
    NSString *result   = [original stringByReplacingOccurrencesOfString:needle
                                                             withString:replacement
                                                                options:NSCaseInsensitiveSearch
                                                                  range:NSMakeRange(0, original.length)];
    if (![result isEqualToString:original]) {
        [_targetTextView.textStorage replaceCharactersInRange:NSMakeRange(0, original.length)
                                                   withString:result];
        [_targetTextView didChangeText];
    }
    _lastFoundLocation = 0;
}

- (IBAction)closePanel:(id)sender {
    [_panel orderOut:nil];
}

@end

// ============================================================
// MARK: - Weak Script Message Handler Proxy
// ============================================================

// WKUserContentController retains its handlers strongly, which would create a
// retain cycle (AppDelegate → WKWebView → config → ucc → AppDelegate).
// This proxy holds a weak reference so the cycle is broken.
@interface WeakScriptMessageHandler : NSObject <WKScriptMessageHandler>
- (instancetype)initWithDelegate:(id<WKScriptMessageHandler>)delegate;
@end

@implementation WeakScriptMessageHandler {
    __weak id<WKScriptMessageHandler> _delegate;
}
- (instancetype)initWithDelegate:(id<WKScriptMessageHandler>)delegate {
    self = [super init];
    if (self) _delegate = delegate;
    return self;
}
- (void)userContentController:(WKUserContentController *)ucc
      didReceiveScriptMessage:(WKScriptMessage *)message {
    [_delegate userContentController:ucc didReceiveScriptMessage:message];
}
@end

// ============================================================
// MARK: - Application Delegate / Main Editor Window
// ============================================================

@interface AppDelegate : NSObject <NSApplicationDelegate, NSTextViewDelegate, NSWindowDelegate, WKScriptMessageHandler>
@property (nonatomic, strong) NSWindow              *window;
@property (nonatomic, strong) NSTextView            *textView;
@property (nonatomic, strong) NSScrollView          *scrollView;
@property (nonatomic, strong) LineNumberRulerView   *rulerView;
@property (nonatomic, strong) FindReplaceController *findReplace;
@property (nonatomic, copy)   NSString              *currentFilePath;
@property (nonatomic, assign) BOOL                   isDirty;
// Font state
@property (nonatomic, assign) CGFloat                currentFontSize;
@property (nonatomic, copy)   NSString              *fontFamily;
@property (nonatomic, assign) CGFloat                currentLineSpacing;
@property (nonatomic, strong) NSTextField           *statusBar;
// Markdown preview
@property (nonatomic, strong) WKWebView             *previewWebView;
@property (nonatomic, strong) NSView                *dividerView;
@property (nonatomic, strong) NSTimer               *previewTimer;
@property (nonatomic, strong) NSMenuItem            *previewMenuItem;
@property (nonatomic, assign) BOOL                   previewVisible;
// Syntax highlighting guard
@property (nonatomic, assign) BOOL                   isHighlighting;
@end

@implementation AppDelegate

// ── Lifecycle ─────────────────────────────────────────────

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    _currentFontSize    = 14.0;
    _fontFamily         = @"mono";
    _currentLineSpacing = 0.0;
    [self buildMenu];
    [self buildWindow];
    [self.window makeKeyAndOrderFront:nil];
    if (@available(macOS 14.0, *)) {
        [NSApp activate];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [NSApp activateIgnoringOtherApps:YES];
#pragma clang diagnostic pop
    }
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {
    return YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    if (!_isDirty) return NSTerminateNow;
    NSAlert *alert = [self unsavedChangesAlertWithAction:@"quit"];
    NSModalResponse r = [alert runModal];
    if (r == NSAlertFirstButtonReturn)  { return [self doSave] ? NSTerminateNow : NSTerminateCancel; }
    if (r == NSAlertSecondButtonReturn) { return NSTerminateNow; }
    return NSTerminateCancel;
}

// ── Window & Views ────────────────────────────────────────

- (void)buildWindow {
    NSRect frame = NSMakeRect(0, 0, 1100, 700);
    _window = [[NSWindow alloc] initWithContentRect:frame
                                          styleMask:NSWindowStyleMaskTitled
                                                   | NSWindowStyleMaskResizable
                                                   | NSWindowStyleMaskClosable
                                                   | NSWindowStyleMaskMiniaturizable
                                            backing:NSBackingStoreBuffered
                                              defer:NO];
    _window.title    = @"Untitled — Notepad";
    _window.delegate = self;
    [_window center];

    static const CGFloat kStatusBarHeight = 22.0;
    static const CGFloat kDividerWidth    = 1.0;
    NSRect cb = _window.contentView.bounds;
    CGFloat editH = cb.size.height - kStatusBarHeight;

    // ── Editor scroll view — fills window; shrinks when preview is shown ──
    _scrollView = [[NSScrollView alloc] initWithFrame:
                    NSMakeRect(0, kStatusBarHeight, cb.size.width, editH)];
    _scrollView.autoresizingMask      = NSViewWidthSizable | NSViewHeightSizable;
    _scrollView.hasVerticalScroller   = YES;
    _scrollView.hasHorizontalScroller = NO;
    _scrollView.autohidesScrollers    = YES;

    NSSize contentSize = _scrollView.contentSize;
    NSTextContainer *tc = [[NSTextContainer alloc] initWithSize:
                             NSMakeSize(contentSize.width, CGFLOAT_MAX)];
    tc.widthTracksTextView = YES;

    NSLayoutManager *lm = [[NSLayoutManager alloc] init];
    NSTextStorage   *ts = [[NSTextStorage alloc] init];
    [ts addLayoutManager:lm];
    [lm addTextContainer:tc];

    _textView = [[NSTextView alloc] initWithFrame:
                    NSMakeRect(0, 0, contentSize.width, contentSize.height)
                                    textContainer:tc];
    _textView.autoresizingMask             = NSViewWidthSizable;
    _textView.minSize                      = NSMakeSize(0, contentSize.height);
    _textView.maxSize                      = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    _textView.verticallyResizable          = YES;
    _textView.horizontallyResizable        = NO;
    _textView.font                         = [NSFont monospacedSystemFontOfSize:14.0
                                                                         weight:NSFontWeightRegular];
    _textView.textColor                    = [NSColor textColor];
    _textView.backgroundColor              = [NSColor textBackgroundColor];
    _textView.automaticSpellingCorrectionEnabled = NO;
    _textView.automaticQuoteSubstitutionEnabled  = NO;
    _textView.automaticDashSubstitutionEnabled   = NO;
    _textView.richText                     = NO;
    _textView.allowsUndo                   = YES;
    _textView.delegate                     = self;

    _scrollView.documentView = _textView;

    _rulerView = [[LineNumberRulerView alloc] initWithScrollView:_scrollView
                                                  clientTextView:_textView];
    _scrollView.verticalRulerView  = _rulerView;
    _scrollView.rulersVisible      = YES;

    // ── Divider and preview — hidden until toggled ───────
    _dividerView = [[NSView alloc] initWithFrame:
                     NSMakeRect(0, kStatusBarHeight, kDividerWidth, editH)];
    _dividerView.autoresizingMask = NSViewHeightSizable;
    _dividerView.wantsLayer       = YES;
    _dividerView.hidden           = YES;

    WKWebViewConfiguration *wkConfig = [[WKWebViewConfiguration alloc] init];
    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    [ucc addScriptMessageHandler:[[WeakScriptMessageHandler alloc] initWithDelegate:self]
                             name:@"copyCode"];
    wkConfig.userContentController = ucc;
    _previewWebView = [[WKWebView alloc] initWithFrame:NSMakeRect(0, kStatusBarHeight, 0, editH)
                                         configuration:wkConfig];
    _previewWebView.autoresizingMask = NSViewHeightSizable;
    _previewWebView.hidden           = YES;

    [_window.contentView addSubview:_scrollView];
    [_window.contentView addSubview:_dividerView];
    [_window.contentView addSubview:_previewWebView];

    // ── Status bar ───────────────────────────────────────
    _statusBar = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, cb.size.width, kStatusBarHeight)];
    _statusBar.editable         = NO;
    _statusBar.bordered         = NO;
    _statusBar.drawsBackground  = YES;
    _statusBar.backgroundColor  = [NSColor controlBackgroundColor];
    _statusBar.font             = [NSFont monospacedDigitSystemFontOfSize:11.0
                                                                   weight:NSFontWeightRegular];
    _statusBar.textColor        = [NSColor secondaryLabelColor];
    _statusBar.alignment        = NSTextAlignmentCenter;
    _statusBar.autoresizingMask = NSViewWidthSizable;
    [_window.contentView addSubview:_statusBar];

    NSBox *separator = [[NSBox alloc] initWithFrame:NSMakeRect(0, kStatusBarHeight - 1,
                                                                cb.size.width, 1)];
    separator.boxType          = NSBoxSeparator;
    separator.autoresizingMask = NSViewWidthSizable;
    [_window.contentView addSubview:separator];

    [self applyFont];

    _findReplace = [[FindReplaceController alloc] initWithTargetTextView:_textView];

    [self updateStatusBar];
}

// ── Menu ──────────────────────────────────────────────────

- (void)buildMenu {
    NSMenu *main = [[NSMenu alloc] init];
    [NSApp setMainMenu:main];

    // App menu
    NSMenuItem *appItem = [main addItemWithTitle:@"" action:nil keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] init];
    [appMenu addItemWithTitle:@"About Notepad"
                       action:@selector(orderFrontStandardAboutPanel:)
                keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit Notepad" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;

    // File menu
    NSMenuItem *fileItem = [main addItemWithTitle:@"File" action:nil keyEquivalent:@""];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"New"   action:@selector(newDocument:)  keyEquivalent:@"n"];
    [fileMenu addItemWithTitle:@"Open…" action:@selector(openDocument:) keyEquivalent:@"o"];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Save"  action:@selector(saveDocument:) keyEquivalent:@"s"];
    NSMenuItem *saveAs = [fileMenu addItemWithTitle:@"Save As…"
                                             action:@selector(saveDocumentAs:)
                                      keyEquivalent:@"s"];
    saveAs.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    fileItem.submenu = fileMenu;

    // Edit menu
    NSMenuItem *editItem = [main addItemWithTitle:@"Edit" action:nil keyEquivalent:@""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Undo"       action:@selector(undo:)      keyEquivalent:@"z"];
    [editMenu addItemWithTitle:@"Redo"       action:@selector(redo:)      keyEquivalent:@"Z"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Cut"        action:@selector(cut:)       keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy"       action:@selector(copy:)      keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste"      action:@selector(paste:)     keyEquivalent:@"v"];
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *findItem = [editMenu addItemWithTitle:@"Find & Replace…"
                                               action:@selector(showFindReplace:)
                                        keyEquivalent:@"f"];
    findItem.target = self;
    editItem.submenu = editMenu;

    // Format menu
    NSMenuItem *formatItem = [main addItemWithTitle:@"Format" action:nil keyEquivalent:@""];
    NSMenu *formatMenu = [[NSMenu alloc] initWithTitle:@"Format"];

    NSMenuItem *familyItem = [formatMenu addItemWithTitle:@"Font" action:nil keyEquivalent:@""];
    NSMenu *familyMenu = [[NSMenu alloc] initWithTitle:@"Font"];
    NSMenuItem *monoItem  = [familyMenu addItemWithTitle:@"Monospaced"
                                                  action:@selector(setFontMono:)
                                           keyEquivalent:@""];
    NSMenuItem *sansItem  = [familyMenu addItemWithTitle:@"Sans-Serif"
                                                  action:@selector(setFontSans:)
                                           keyEquivalent:@""];
    NSMenuItem *serifItem = [familyMenu addItemWithTitle:@"Serif"
                                                  action:@selector(setFontSerif:)
                                           keyEquivalent:@""];
    for (NSMenuItem *it in @[monoItem, sansItem, serifItem]) it.target = self;
    familyItem.submenu = familyMenu;

    NSMenuItem *sizeItem = [formatMenu addItemWithTitle:@"Size" action:nil keyEquivalent:@""];
    NSMenu *sizeMenu = [[NSMenu alloc] initWithTitle:@"Size"];
    NSMenuItem *biggerItem  = [sizeMenu addItemWithTitle:@"Bigger"
                                                  action:@selector(fontSizeUp:)
                                           keyEquivalent:@"+"];
    NSMenuItem *smallerItem = [sizeMenu addItemWithTitle:@"Smaller"
                                                  action:@selector(fontSizeDown:)
                                           keyEquivalent:@"-"];
    biggerItem.target  = self;
    smallerItem.target = self;
    [sizeMenu addItem:[NSMenuItem separatorItem]];
    for (NSNumber *pt in @[@10, @12, @14, @16, @18, @24, @36]) {
        NSMenuItem *it = [sizeMenu addItemWithTitle:[NSString stringWithFormat:@"%@ pt", pt]
                                            action:@selector(setFontSize:)
                                     keyEquivalent:@""];
        it.tag    = pt.integerValue;
        it.target = self;
    }
    sizeItem.submenu = sizeMenu;

    [formatMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *spacingItem = [formatMenu addItemWithTitle:@"Line Spacing"
                                                    action:nil
                                             keyEquivalent:@""];
    NSMenu *spacingMenu = [[NSMenu alloc] initWithTitle:@"Line Spacing"];
    NSDictionary *spacings = @{
        @"Tight (1.0)":   @0.0,
        @"Normal (1.2)":  @3.0,
        @"Relaxed (1.5)": @7.0,
        @"Double (2.0)":  @14.0
    };
    NSArray *spacingOrder = @[@"Tight (1.0)", @"Normal (1.2)", @"Relaxed (1.5)", @"Double (2.0)"];
    for (NSString *label in spacingOrder) {
        NSMenuItem *it = [spacingMenu addItemWithTitle:label
                                               action:@selector(setLineSpacing:)
                                        keyEquivalent:@""];
        it.tag    = (NSInteger)([spacings[label] doubleValue] * 10);
        it.target = self;
    }
    spacingItem.submenu = spacingMenu;

    formatItem.submenu = formatMenu;

    // View menu
    NSMenuItem *viewItem = [main addItemWithTitle:@"View" action:nil keyEquivalent:@""];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];

    NSMenuItem *lineNumItem = [viewMenu addItemWithTitle:@"Toggle Line Numbers"
                                                  action:@selector(toggleLineNumbers:)
                                           keyEquivalent:@"l"];
    lineNumItem.target = self;
    lineNumItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;

    [viewMenu addItem:[NSMenuItem separatorItem]];

    _previewMenuItem = [viewMenu addItemWithTitle:@"Show Markdown Preview"
                                           action:@selector(toggleMarkdownPreview:)
                                    keyEquivalent:@"p"];
    _previewMenuItem.target = self;
    _previewMenuItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;

    viewItem.submenu = viewMenu;

    (void)findItem;
}

// ── NSTextViewDelegate ────────────────────────────────────

- (void)textDidChange:(NSNotification *)note {
    if (!_isDirty) {
        _isDirty = YES;
        [self updateTitle];
    }
    [_rulerView setNeedsDisplay:YES];
    [self updateStatusBar];
    if (!_isHighlighting) {
        [self applyMarkdownHighlighting];
    }
    [self schedulePreviewUpdate];
}

- (void)textViewDidChangeSelection:(NSNotification *)note {
    [self updateStatusBar];
}

// ── Actions ───────────────────────────────────────────────

- (IBAction)newDocument:(id)sender {
    if (_isDirty && ![self confirmDiscardWithAction:@"create a new document"]) return;
    _currentFilePath = nil;
    _isDirty = NO;
    [_textView.textStorage replaceCharactersInRange:NSMakeRange(0, _textView.string.length)
                                         withString:@""];
    [_textView.undoManager removeAllActions];
    [self updateTitle];
    [self updateStatusBar];
}

- (BOOL)loadFileAtPath:(NSString *)path {
    static const long long kMaxFileSize = 100LL * 1024 * 1024;
    NSNumber *fileSize = [[NSFileManager defaultManager]
        attributesOfItemAtPath:path error:nil][NSFileSize];
    if (fileSize && fileSize.longLongValue > kMaxFileSize) {
        NSAlert *sizeAlert = [[NSAlert alloc] init];
        sizeAlert.messageText = @"File Too Large";
        sizeAlert.informativeText = [NSString stringWithFormat:
            @"This file is %lld MB. Opening very large files may use excessive memory. Continue?",
            fileSize.longLongValue / (1024 * 1024)];
        [sizeAlert addButtonWithTitle:@"Cancel"];
        [sizeAlert addButtonWithTitle:@"Open Anyway"];
        if ([sizeAlert runModal] == NSAlertFirstButtonReturn) return NO;
    }

    NSError  *err  = nil;
    NSString *text = [NSString stringWithContentsOfFile:path
                                               encoding:NSUTF8StringEncoding
                                                  error:&err];
    if (err) {
        text = nil; err = nil;
        text = [NSString stringWithContentsOfFile:path
                                         encoding:NSISOLatin1StringEncoding
                                            error:&err];
    }
    if (err || !text) {
        [self showError:[NSString stringWithFormat:@"Could not open file:\n%@",
            err.localizedDescription]];
        return NO;
    }

    [_textView.textStorage replaceCharactersInRange:NSMakeRange(0, _textView.string.length)
                                         withString:text];
    [_textView.undoManager removeAllActions];
    _currentFilePath = path;
    _isDirty = NO;
    [self updateTitle];
    [self updateStatusBar];
    [self applyMarkdownHighlighting];
    [self schedulePreviewUpdate];
    return YES;
}

- (IBAction)openDocument:(id)sender {
    if (_isDirty && ![self confirmDiscardWithAction:@"open another file"]) return;

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories    = NO;
    panel.allowedContentTypes     = @[];

    if ([panel runModal] != NSModalResponseOK) return;
    [self loadFileAtPath:panel.URL.path];
}

- (BOOL)doSave {
    return _currentFilePath ? [self writeToPath:_currentFilePath] : [self doSaveAs];
}

- (IBAction)saveDocument:(id)sender {
    [self doSave];
}

- (BOOL)doSaveAs {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = _currentFilePath
        ? _currentFilePath.lastPathComponent
        : @"Untitled.txt";

    if ([panel runModal] != NSModalResponseOK) return NO;
    NSString *prevPath = _currentFilePath;
    _currentFilePath = panel.URL.path;
    if (![self writeToPath:_currentFilePath]) {
        _currentFilePath = prevPath;
        return NO;
    }
    return YES;
}

- (IBAction)saveDocumentAs:(id)sender {
    [self doSaveAs];
}

- (BOOL)writeToPath:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSNumber *origPerms = [fm attributesOfItemAtPath:path error:nil][NSFilePosixPermissions];

    NSError *err = nil;
    BOOL ok = [_textView.string writeToFile:path
                                 atomically:YES
                                   encoding:NSUTF8StringEncoding
                                      error:&err];
    if (!ok) {
        // Retry without atomicity if sandbox denied parent-directory access
        err = nil;
        ok = [_textView.string writeToFile:path
                                atomically:NO
                                  encoding:NSUTF8StringEncoding
                                     error:&err];
    }
    if (!ok) {
        [self showError:[NSString stringWithFormat:@"Could not save:\n%@", err.localizedDescription]];
        return NO;
    }

    if (origPerms)
        [fm setAttributes:@{NSFilePosixPermissions: origPerms} ofItemAtPath:path error:nil];

    _isDirty = NO;
    [self updateTitle];
    return YES;
}

- (IBAction)showFindReplace:(id)sender {
    [_findReplace showPanel];
}

// ── Markdown Preview ──────────────────────────────────────

- (IBAction)toggleMarkdownPreview:(id)sender {
    if (_previewVisible) {
        _previewWebView.hidden = YES;
        _dividerView.hidden    = YES;
        _scrollView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        _scrollView.frame    = [self editorFrameForFullWidth];
        _previewMenuItem.title = @"Show Markdown Preview";
        _previewVisible = NO;
    } else {
        _scrollView.autoresizingMask = NSViewHeightSizable;
        [self applyPreviewLayout];
        _previewWebView.hidden = NO;
        _dividerView.hidden    = NO;
        _previewMenuItem.title = @"Hide Markdown Preview";
        _previewVisible = YES;
        [self updatePreview];
    }
}

- (NSRect)editorFrameForFullWidth {
    static const CGFloat kStatusBarHeight = 22.0;
    NSRect cb = _window.contentView.bounds;
    return NSMakeRect(0, kStatusBarHeight, cb.size.width, cb.size.height - kStatusBarHeight);
}

- (void)applyPreviewLayout {
    static const CGFloat kStatusBarHeight = 22.0;
    static const CGFloat kDividerWidth    = 1.0;
    NSRect cb    = _window.contentView.bounds;
    CGFloat editH = cb.size.height - kStatusBarHeight;
    CGFloat total = cb.size.width;
    CGFloat previewW = floor(total * 0.45);
    CGFloat editorW  = total - previewW - kDividerWidth;

    _scrollView.frame        = NSMakeRect(0, kStatusBarHeight, editorW, editH);
    _dividerView.frame       = NSMakeRect(editorW, kStatusBarHeight, kDividerWidth, editH);
    _previewWebView.frame = NSMakeRect(editorW + kDividerWidth, kStatusBarHeight, previewW, editH);

    _dividerView.layer.backgroundColor = [NSColor separatorColor].CGColor;
}

- (void)schedulePreviewUpdate {
    [_previewTimer invalidate];
    _previewTimer = [NSTimer scheduledTimerWithTimeInterval:0.4
                                                     target:self
                                                   selector:@selector(updatePreview)
                                                   userInfo:nil
                                                    repeats:NO];
}

- (void)updatePreview {
    if (!_previewVisible) return;

    NSString *body = [self markdownToHTML:_textView.string];

    NSAppearanceName matched = [_window.effectiveAppearance
        bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    BOOL dark = [matched isEqualToString:NSAppearanceNameDarkAqua];
    NSString *fg            = dark ? @"#f0f0f0" : @"#1a1a1a";
    NSString *bg            = dark ? @"#1c1c1e" : @"#ffffff";
    NSString *inlineCodeBg  = dark ? @"#3d1a28" : @"#fce8f0";
    NSString *inlineCodeFg  = dark ? @"#ff7faa" : @"#c0395b";
    NSString *borderColor   = dark ? @"#444444" : @"#d0d0d0";
    NSString *linkColor     = dark ? @"#ffa040" : @"#e07b00";

    NSString *html = [NSString stringWithFormat:
        @"<html><head><meta charset='utf-8'><style>"
        "body{font-family:-apple-system,sans-serif;font-size:15px;line-height:1.65;"
        "padding:20px 28px;color:%@;background:%@;}"
        "h1,h2,h3,h4,h5,h6{font-weight:700;margin-top:1.3em;margin-bottom:.2em;color:%@;}"
        "h1{font-size:1.6em;}h2{font-size:1.25em;}h3{font-size:1.1em;}"
        "p{margin:.5em 0;}"
        "code{font-family:Menlo,Monaco,monospace;background:%@;color:%@;padding:1px 5px;font-size:.88em;border-radius:4px;}"
        "a{color:%@;text-decoration:underline;}"
        "hr{border:none;border-top:1px solid %@;margin:1.2em 0;}"
        "del{opacity:.6;}"
        ".code-block{position:relative;border-radius:10px;margin:1em 0;overflow:hidden;}"
        ".code-pre{margin:0;padding:14px 16px;font-family:Menlo,Monaco,monospace;font-size:.88em;overflow-x:auto;white-space:pre-wrap;overflow-wrap:break-word;}"
        ".copy-btn{position:absolute;top:8px;right:8px;border:none;border-radius:6px;"
        "padding:3px 10px;font-size:11px;cursor:pointer;background:rgba(128,128,128,0.25);"
        "color:inherit;font-family:-apple-system,sans-serif;opacity:0;transition:opacity 0.15s;}"
        ".code-block:hover .copy-btn{opacity:1;}"
        ".copy-btn.copied{background:rgba(52,199,89,0.35);}"
        "</style></head><body>%@"
        "<script>"
        "function copyCode(btn){"
        "var pre=btn.parentElement.querySelector('pre');"
        "window.webkit.messageHandlers.copyCode.postMessage(pre.textContent);"
        "btn.textContent='Copied!';"
        "btn.classList.add('copied');"
        "setTimeout(function(){btn.textContent='Copy';btn.classList.remove('copied');},2000);}"
        "</script>"
        "</body></html>",
        fg, bg, fg, inlineCodeBg, inlineCodeFg, linkColor, borderColor, body];

    [_previewWebView loadHTMLString:html baseURL:nil];
}

// ── WKScriptMessageHandler ────────────────────────────────

- (void)userContentController:(WKUserContentController *)userContentController
      didReceiveScriptMessage:(WKScriptMessage *)message {
    (void)userContentController;
    if ([message.name isEqualToString:@"copyCode"] &&
        [message.body isKindOfClass:[NSString class]]) {
        NSPasteboard *pb = [NSPasteboard generalPasteboard];
        [pb clearContents];
        [pb setString:(NSString *)message.body forType:NSPasteboardTypeString];
    }
}

// ── Markdown → HTML ───────────────────────────────────────

- (NSString *)htmlEscape:(NSString *)str {
    NSMutableString *s = [str mutableCopy];
    [s replaceOccurrencesOfString:@"&"  withString:@"&amp;"  options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@"<"  withString:@"&lt;"   options:0 range:NSMakeRange(0, s.length)];
    [s replaceOccurrencesOfString:@">"  withString:@"&gt;"   options:0 range:NSMakeRange(0, s.length)];
    return [s copy];
}

- (NSString *)applyInlineMarkdown:(NSString *)text {
    __block NSMutableString *s = [[self htmlEscape:text] mutableCopy];

    // Helper: regex replace — uses __block s so each call sees the previous result
    NSMutableString *(^sub)(NSString *, NSString *) = ^(NSString *pat, NSString *tpl) {
        NSRegularExpression *rx = [NSRegularExpression
            regularExpressionWithPattern:pat options:0 error:nil];
        return [[rx stringByReplacingMatchesInString:s
                                             options:0
                                               range:NSMakeRange(0, s.length)
                                        withTemplate:tpl] mutableCopy];
    };

    // Extract inline code spans first (protect from bold/italic)
    NSMutableArray<NSString *> *slots = [NSMutableArray array];
    {
        NSRegularExpression *rx = [NSRegularExpression
            regularExpressionWithPattern:@"`([^`\n]+)`" options:0 error:nil];
        NSMutableString *buf = [NSMutableString string];
        __block NSUInteger last = 0;
        [rx enumerateMatchesInString:s options:0 range:NSMakeRange(0, s.length)
                          usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop){
            (void)f; (void)stop;
            [buf appendString:[s substringWithRange:NSMakeRange(last, m.range.location - last)]];
            NSString *inner = [s substringWithRange:[m rangeAtIndex:1]];
            [buf appendFormat:@"\x02%lu\x03", (unsigned long)slots.count];
            [slots addObject:[NSString stringWithFormat:@"<code>%@</code>", inner]];
            last = NSMaxRange(m.range);
        }];
        [buf appendString:[s substringFromIndex:last]];
        [s setString:buf];
    }

    s = sub(@"\\*{3}(.+?)\\*{3}",                     @"<strong><em>$1</em></strong>");
    s = sub(@"\\*{2}(.+?)\\*{2}",                     @"<strong>$1</strong>");
    s = sub(@"__(.+?)__",                              @"<strong>$1</strong>");
    s = sub(@"(?<!\\*)\\*([^\\*\n]+)\\*(?!\\*)",       @"<em>$1</em>");
    s = sub(@"(?<!_)_([^_\n]+)_(?!_)",                 @"<em>$1</em>");
    s = sub(@"~~(.+?)~~",                              @"<del>$1</del>");
    s = sub(@"!\\[([^\\]]*)\\]\\(([^\\)]+)\\)",        @"<img alt=\"$1\" src=\"$2\">");
    s = sub(@"\\[([^\\]]+)\\]\\(([^\\)]+)\\)",         @"<a href=\"$2\">$1</a>");

    // Restore code slots
    for (NSUInteger i = 0; i < slots.count; i++) {
        NSString *key = [NSString stringWithFormat:@"\x02%lu\x03", (unsigned long)i];
        [s replaceOccurrencesOfString:key withString:slots[i]
                              options:0 range:NSMakeRange(0, s.length)];
    }

    return [s copy];
}

- (NSString *)markdownToHTML:(NSString *)rawMD {
    NSAppearanceName matched = [_window.effectiveAppearance
        bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    BOOL dark = [matched isEqualToString:NSAppearanceNameDarkAqua];
    NSString *codeBg     = dark ? @"#2a2a2e" : @"#f2f2f2";
    NSString *codeFg     = dark ? @"#e0e0e0" : @"#1a1a1a";
    NSString *tableBdr   = dark ? @"#444444" : @"#d0d0d0";
    NSString *borderColor= dark ? @"#444444" : @"#d0d0d0";
    NSString *checkColor = dark ? @"#ffa040" : @"#e07b00";

    NSMutableString *out = [NSMutableString string];
    NSArray<NSString *> *lines = [rawMD componentsSeparatedByString:@"\n"];
    NSUInteger n = lines.count;

    __block BOOL inFence  = NO;
    __block BOOL inOL     = NO;
    __block NSUInteger olCounter = 0;
    __block NSMutableString *para = [NSMutableString string];

    void (^flushPara)(void) = ^{
        if (!para.length) return;
        [out appendFormat:@"<p>%@</p>\n", [self applyInlineMarkdown:[para copy]]];
        [para setString:@""];
    };
    void (^closeLists)(void) = ^{
        if (inOL) { inOL = NO; olCounter = 0; }
    };

    for (NSUInteger i = 0; i < n; i++) {
        NSString *line = lines[i];

        // Fenced code block body
        if (inFence) {
            if ([line hasPrefix:@"```"] || [line hasPrefix:@"~~~"]) {
                [out appendString:@"</pre></div>\n"];
                inFence = NO;
            } else {
                [out appendString:[self htmlEscape:line]];
                [out appendString:@"\n"];
            }
            continue;
        }

        // Fenced code block start
        if ([line hasPrefix:@"```"] || [line hasPrefix:@"~~~"]) {
            flushPara(); closeLists();
            [out appendFormat:
                @"<div class='code-block' style='background:%@;'>"
                "<button class='copy-btn' onclick='copyCode(this)'>Copy</button>"
                "<pre class='code-pre' style='color:%@;'>",
                codeBg, codeFg];
            inFence = YES;
            continue;
        }

        // Blank line
        NSString *trimmed = [line stringByTrimmingCharactersInSet:
                             [NSCharacterSet whitespaceCharacterSet]];
        if (!trimmed.length) {
            flushPara(); closeLists();
            continue;
        }

        // ATX headers
        {
            NSUInteger h = 0;
            while (h < 6 && h < line.length && [line characterAtIndex:h] == '#') h++;
            if (h > 0 && h < line.length && [line characterAtIndex:h] == ' ') {
                flushPara(); closeLists();
                NSString *text = [[line substringFromIndex:h + 1]
                    stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                [out appendFormat:@"<h%lu>%@</h%lu>\n",
                    (unsigned long)h, [self applyInlineMarkdown:text], (unsigned long)h];
                continue;
            }
        }

        // Setext headers (=== or ---)
        if (i + 1 < n && !para.length) {
            NSString *next = [lines[i + 1] stringByTrimmingCharactersInSet:
                              [NSCharacterSet whitespaceCharacterSet]];
            if (next.length >= 2) {
                BOOL allEq = YES, allDash = YES;
                for (NSUInteger j = 0; j < next.length; j++) {
                    unichar c = [next characterAtIndex:j];
                    if (c != '=') allEq   = NO;
                    if (c != '-') allDash = NO;
                }
                if (allEq) {
                    flushPara(); closeLists();
                    [out appendFormat:@"<h1>%@</h1>\n", [self applyInlineMarkdown:line]];
                    i++; continue;
                }
                if (allDash) {
                    flushPara(); closeLists();
                    [out appendFormat:@"<h2>%@</h2>\n", [self applyInlineMarkdown:line]];
                    i++; continue;
                }
            }
        }

        // Horizontal rule (---, ***, ___ with optional spaces)
        {
            NSString *t = [trimmed stringByReplacingOccurrencesOfString:@" " withString:@""];
            if (t.length >= 3) {
                unichar fc = [t characterAtIndex:0];
                if (fc == '-' || fc == '*' || fc == '_') {
                    BOOL hr = YES;
                    for (NSUInteger j = 0; j < t.length; j++)
                        if ([t characterAtIndex:j] != fc) { hr = NO; break; }
                    if (hr) {
                        flushPara(); closeLists();
                        [out appendString:@"<hr>\n"];
                        continue;
                    }
                }
            }
        }

        // Blockquote
        if ([line hasPrefix:@"> "]) {
            flushPara(); closeLists();
            [out appendFormat:
                @"<table width='100%%' cellpadding='0' cellspacing='0' border='0'"
                " style='margin:.6em 0;'><tr>"
                "<td bgcolor='%@' style='width:3px;'>&nbsp;&nbsp;</td>"
                "<td style='padding:2px 0 2px 12px;'>%@</td>"
                "</tr></table>\n",
                borderColor,
                [self applyInlineMarkdown:[line substringFromIndex:2]]];
            continue;
        }

        // GFM table: header row starts with '|'
        if ([trimmed hasPrefix:@"|"] && i + 1 < n) {
            NSString *nextTrimmed = [[lines[i + 1] stringByTrimmingCharactersInSet:
                                      [NSCharacterSet whitespaceCharacterSet]]
                                     stringByReplacingOccurrencesOfString:@" " withString:@""];
            // Separator row must be all dashes/pipes/colons
            BOOL isSep = nextTrimmed.length > 0;
            for (NSUInteger k = 0; k < nextTrimmed.length && isSep; k++) {
                unichar c = [nextTrimmed characterAtIndex:k];
                if (c != '|' && c != '-' && c != ':') isSep = NO;
            }
            if (isSep) {
                flushPara(); closeLists();
                // Parse header cells
                NSArray<NSString *> *hCells = [trimmed componentsSeparatedByString:@"|"];
                [out appendFormat:
                    @"<table cellpadding='6' cellspacing='0' border='1'"
                    " bordercolor='%@' style='border-collapse:collapse;margin:1em 0;'>",
                    tableBdr];
                [out appendString:@"<tr>"];
                for (NSString *cell in hCells) {
                    NSString *ct = [cell stringByTrimmingCharactersInSet:
                                    [NSCharacterSet whitespaceCharacterSet]];
                    if (!ct.length) continue;
                    [out appendFormat:@"<th style='padding:6px 12px;"
                        "text-align:left;border:1px solid %@;font-weight:600;'>%@</th>",
                        tableBdr, [self applyInlineMarkdown:ct]];
                }
                [out appendString:@"</tr>\n"];
                i += 2; // skip header + separator
                // Data rows
                while (i < n) {
                    NSString *row = [lines[i] stringByTrimmingCharactersInSet:
                                     [NSCharacterSet whitespaceCharacterSet]];
                    if (!row.length || ![row hasPrefix:@"|"]) break;
                    NSArray<NSString *> *cells = [row componentsSeparatedByString:@"|"];
                    [out appendString:@"<tr>"];
                    for (NSString *cell in cells) {
                        NSString *ct = [cell stringByTrimmingCharactersInSet:
                                        [NSCharacterSet whitespaceCharacterSet]];
                        if (!ct.length) continue;
                        [out appendFormat:@"<td style='padding:6px 12px;"
                            "border:1px solid %@;'>%@</td>",
                            tableBdr, [self applyInlineMarkdown:ct]];
                    }
                    [out appendString:@"</tr>\n"];
                    i++;
                }
                [out appendString:@"</table>\n"];
                i--; // outer loop will i++
                continue;
            }
        }

        // GFM task list item: - [ ] or - [x]
        if (line.length >= 6 &&
            ([line hasPrefix:@"- [ ] "] || [line hasPrefix:@"- [x] "] || [line hasPrefix:@"- [X] "])) {
            flushPara();
            if (inOL) { inOL = NO; olCounter = 0; }
            BOOL checked = ![line hasPrefix:@"- [ ] "];
            NSString *bullet = checked
                ? [NSString stringWithFormat:@"<font color='%@'>&#x25cf;</font>", checkColor]
                : @"<font color='#999999'>&#x25cb;</font>";
            [out appendFormat:@"<p style='margin:0 0 .3em 4px;'>%@&nbsp;%@</p>\n",
                bullet, [self applyInlineMarkdown:[line substringFromIndex:6]]];
            continue;
        }

        // Unordered list item
        if (line.length >= 2 &&
            ([line hasPrefix:@"- "] || [line hasPrefix:@"* "] || [line hasPrefix:@"+ "])) {
            flushPara();
            if (inOL) { inOL = NO; olCounter = 0; }
            [out appendFormat:@"<p style='margin:0 0 .15em 20px;'>&#x2013;&nbsp;%@</p>\n",
                [self applyInlineMarkdown:[line substringFromIndex:2]]];
            continue;
        }

        // Ordered list item
        {
            NSRange dot = [line rangeOfString:@". "];
            if (dot.location != NSNotFound && dot.location > 0 && dot.location <= 9) {
                NSString *num = [line substringToIndex:dot.location];
                BOOL allDigits = YES;
                for (NSUInteger j = 0; j < num.length; j++) {
                    unichar c = [num characterAtIndex:j];
                    if (c < '0' || c > '9') { allDigits = NO; break; }
                }
                if (allDigits) {
                    flushPara();
                    if (!inOL) { inOL = YES; olCounter = 0; }
                    olCounter++;
                    [out appendFormat:@"<p style='margin:0 0 .15em 20px;'>%lu.&nbsp;%@</p>\n",
                        (unsigned long)olCounter,
                        [self applyInlineMarkdown:[line substringFromIndex:dot.location + 2]]];
                    continue;
                }
            }
        }

        // Paragraph text
        closeLists();
        if (para.length) [para appendString:@" "];
        [para appendString:line];
    }

    flushPara();
    if (inFence) [out appendString:@"</pre></div>\n"];

    return [out copy];
}

// ── Markdown Syntax Highlighting ─────────────────────────

- (void)applyMarkdownHighlighting {
    NSTextStorage *ts = _textView.textStorage;
    NSString *str     = [ts.string copy];
    NSUInteger len    = str.length;
    if (len == 0) return;

    _isHighlighting = YES;
    [ts beginEditing];

    // Reset all to base color
    [ts addAttribute:NSForegroundColorAttributeName
               value:[NSColor textColor]
               range:NSMakeRange(0, len)];

    NSFont *base   = [self currentFont];
    NSFont *bold   = [[NSFontManager sharedFontManager] convertFont:base
                                                       toHaveTrait:NSBoldFontMask];
    NSFont *italic = [[NSFontManager sharedFontManager] convertFont:base
                                                       toHaveTrait:NSItalicFontMask];

    NSColor *blue   = [NSColor systemBlueColor];
    NSColor *orange = [NSColor systemOrangeColor];
    NSColor *green  = [NSColor systemGreenColor];
    NSColor *quote  = [NSColor secondaryLabelColor];
    NSColor *meta   = [NSColor tertiaryLabelColor];

    NSArray<NSString *> *lines = [str componentsSeparatedByString:@"\n"];
    NSUInteger pos   = 0;
    BOOL       fence = NO;

    for (NSString *line in lines) {
        NSUInteger lineLen = line.length;
        NSRange    lr      = NSMakeRange(pos, lineLen);

        if (fence) {
            if ([line hasPrefix:@"```"] || [line hasPrefix:@"~~~"]) {
                [ts addAttribute:NSForegroundColorAttributeName value:meta  range:lr];
                fence = NO;
            } else {
                [ts addAttribute:NSForegroundColorAttributeName value:green range:lr];
            }
            pos += lineLen + 1;
            continue;
        }

        if ([line hasPrefix:@"```"] || [line hasPrefix:@"~~~"]) {
            [ts addAttribute:NSForegroundColorAttributeName value:meta range:lr];
            fence = YES;
            pos += lineLen + 1;
            continue;
        }

        // ATX header
        NSUInteger h = 0;
        while (h < 6 && h < lineLen && [line characterAtIndex:h] == '#') h++;
        if (h > 0 && h < lineLen && [line characterAtIndex:h] == ' ') {
            [ts addAttribute:NSForegroundColorAttributeName value:blue range:lr];
            if (bold) [ts addAttribute:NSFontAttributeName value:bold range:lr];
            pos += lineLen + 1;
            continue;
        }

        // Blockquote
        if ([line hasPrefix:@"> "]) {
            [ts addAttribute:NSForegroundColorAttributeName value:quote range:lr];
            pos += lineLen + 1;
            continue;
        }

        // Inline code: `...`
        {
            NSRegularExpression *rx = [NSRegularExpression
                regularExpressionWithPattern:@"`[^`\n]+`" options:0 error:nil];
            [rx enumerateMatchesInString:str options:0 range:lr
                              usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop){
                (void)f; (void)stop;
                [ts addAttribute:NSForegroundColorAttributeName value:orange range:m.range];
            }];
        }

        // Bold: **...** or __...__
        {
            NSRegularExpression *rx = [NSRegularExpression
                regularExpressionWithPattern:@"(\\*\\*|__)(.+?)(\\*\\*|__)"
                                     options:0 error:nil];
            [rx enumerateMatchesInString:str options:0 range:lr
                              usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop){
                (void)f; (void)stop;
                if (bold) [ts addAttribute:NSFontAttributeName value:bold range:m.range];
                NSRange open  = NSMakeRange(m.range.location, 2);
                NSRange close = NSMakeRange(NSMaxRange(m.range) - 2, 2);
                [ts addAttribute:NSForegroundColorAttributeName value:meta range:open];
                [ts addAttribute:NSForegroundColorAttributeName value:meta range:close];
            }];
        }

        // Italic: *...* or _..._
        {
            NSRegularExpression *rx = [NSRegularExpression
                regularExpressionWithPattern:@"(?<!\\*)\\*([^\\*\n]+)\\*(?!\\*)|(?<!_)_([^_\n]+)_(?!_)"
                                     options:0 error:nil];
            [rx enumerateMatchesInString:str options:0 range:lr
                              usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop){
                (void)f; (void)stop;
                if (italic) [ts addAttribute:NSFontAttributeName value:italic range:m.range];
                NSRange open  = NSMakeRange(m.range.location, 1);
                NSRange close = NSMakeRange(NSMaxRange(m.range) - 1, 1);
                [ts addAttribute:NSForegroundColorAttributeName value:meta range:open];
                [ts addAttribute:NSForegroundColorAttributeName value:meta range:close];
            }];
        }

        // Links / images
        {
            NSRegularExpression *rx = [NSRegularExpression
                regularExpressionWithPattern:@"!?\\[[^\\]]*\\]\\([^\\)]*\\)"
                                     options:0 error:nil];
            [rx enumerateMatchesInString:str options:0 range:lr
                              usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop){
                (void)f; (void)stop;
                [ts addAttribute:NSForegroundColorAttributeName value:blue range:m.range];
            }];
        }

        pos += lineLen + 1;
    }

    [ts endEditing];
    _isHighlighting = NO;
}

// ── Font helpers ──────────────────────────────────────────

- (NSFont *)currentFont {
    if ([_fontFamily isEqualToString:@"sans"])
        return [NSFont systemFontOfSize:_currentFontSize weight:NSFontWeightRegular];
    if ([_fontFamily isEqualToString:@"serif"])
        return [NSFont fontWithName:@"Georgia" size:_currentFontSize]
            ?: [NSFont userFontOfSize:_currentFontSize];
    return [NSFont monospacedSystemFontOfSize:_currentFontSize weight:NSFontWeightRegular];
}

- (void)applyFont {
    NSFont *font = [self currentFont];
    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.lineSpacing = _currentLineSpacing;
    NSDictionary *attrs = @{
        NSFontAttributeName            : font,
        NSForegroundColorAttributeName : [NSColor textColor],
        NSParagraphStyleAttributeName  : para,
    };
    NSRange all = NSMakeRange(0, _textView.textStorage.length);
    [_textView.textStorage setAttributes:attrs range:all];
    _textView.typingAttributes = attrs;
    _textView.font = font;
    [_rulerView setNeedsDisplay:YES];
    // Re-apply syntax colors on top of the new font
    [self applyMarkdownHighlighting];
}

- (IBAction)setFontMono:(id)sender  { _fontFamily = @"mono";  [self applyFont]; }
- (IBAction)setFontSans:(id)sender  { _fontFamily = @"sans";  [self applyFont]; }
- (IBAction)setFontSerif:(id)sender { _fontFamily = @"serif"; [self applyFont]; }

- (IBAction)fontSizeUp:(id)sender {
    _currentFontSize = MIN(_currentFontSize + 2.0, 72.0);
    [self applyFont];
}
- (IBAction)fontSizeDown:(id)sender {
    _currentFontSize = MAX(_currentFontSize - 2.0, 8.0);
    [self applyFont];
}
- (IBAction)setFontSize:(id)sender {
    _currentFontSize = (CGFloat)[(NSMenuItem *)sender tag];
    [self applyFont];
}

- (IBAction)setLineSpacing:(id)sender {
    _currentLineSpacing = [(NSMenuItem *)sender tag] / 10.0;
    [self applyFont];
}

// ── View ──────────────────────────────────────────────────

- (IBAction)toggleLineNumbers:(id)sender {
    _scrollView.rulersVisible = !_scrollView.rulersVisible;
}

// ── NSWindowDelegate ──────────────────────────────────────

- (void)windowDidResize:(NSNotification *)note {
    if (_previewVisible) [self applyPreviewLayout];
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
    if (!_isDirty) return YES;
    NSAlert *alert = [self unsavedChangesAlertWithAction:@"close"];
    NSModalResponse r = [alert runModal];
    if (r == NSAlertFirstButtonReturn)  { return [self doSave]; }
    if (r == NSAlertSecondButtonReturn) { return YES; }
    return NO;
}

// ── Helpers ───────────────────────────────────────────────

- (void)updateStatusBar {
    NSString *text = _textView.string ?: @"";
    NSUInteger chars = text.length;

    NSUInteger words = 0;
    BOOL inWord = NO;
    for (NSUInteger i = 0; i < chars; i++) {
        unichar c = [text characterAtIndex:i];
        BOOL space = (c == ' ' || c == '\t' || c == '\n' || c == '\r');
        if (!space && !inWord) { words++; inWord = YES; }
        else if (space)        { inWord = NO; }
    }

    NSRange sel = _textView.selectedRange;
    NSUInteger pos = (sel.location == NSNotFound) ? 0 : sel.location;
    NSUInteger ln = 1, col = 1;
    for (NSUInteger i = 0; i < pos && i < chars; i++) {
        if ([text characterAtIndex:i] == '\n') { ln++; col = 1; }
        else                                    { col++; }
    }

    NSString *ver = [[NSBundle mainBundle]
        objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @"?";
    _statusBar.stringValue = [NSString stringWithFormat:
        @"v%@     Words: %lu     Chars: %lu     Ln %lu, Col %lu",
        ver, (unsigned long)words, (unsigned long)chars, (unsigned long)ln, (unsigned long)col];
}

- (void)updateTitle {
    NSString *name = _currentFilePath ? _currentFilePath.lastPathComponent : @"Untitled";
    _window.title = _isDirty
        ? [NSString stringWithFormat:@"%@ — Notepad •", name]
        : [NSString stringWithFormat:@"%@ — Notepad",   name];
    [_window setDocumentEdited:_isDirty];
}

- (BOOL)confirmDiscardWithAction:(NSString *)action {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText     = @"Unsaved Changes";
    alert.informativeText = [NSString stringWithFormat:
        @"You have unsaved changes. Are you sure you want to %@?", action];
    [alert addButtonWithTitle:@"Discard Changes"];
    [alert addButtonWithTitle:@"Cancel"];
    return [alert runModal] == NSAlertFirstButtonReturn;
}

- (NSAlert *)unsavedChangesAlertWithAction:(NSString *)action {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText     = @"Unsaved Changes";
    alert.informativeText = [NSString stringWithFormat:
        @"Do you want to save your changes before you %@?", action];
    [alert addButtonWithTitle:@"Save"];
    [alert addButtonWithTitle:@"Don't Save"];
    [alert addButtonWithTitle:@"Cancel"];
    return alert;
}

- (void)showError:(NSString *)message {
    NSAlert *alert = [[NSAlert alloc] init];
    alert.messageText     = @"Error";
    alert.informativeText = message;
    alert.alertStyle      = NSAlertStyleCritical;
    [alert runModal];
}

@end

// ============================================================
// MARK: - main
// ============================================================

int main(int /*argc*/, const char * /*argv*/[]) {
    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        app.activationPolicy = NSApplicationActivationPolicyRegular;

        AppDelegate *delegate = [[AppDelegate alloc] init];
        app.delegate = delegate;

        [app run];
    }
    return 0;
}
