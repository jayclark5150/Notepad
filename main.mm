// ============================================================
//  Notepad — minimal document editor for macOS
//  Supports: .txt, .md, .docx (read/write), .doc (read-only)
//  Dark/light theme with centered column
// ============================================================

#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#import <WebKit/WebKit.h>

// ============================================================
// MARK: - NSUserDefaults Keys
// ============================================================

static NSString *const kFontFamilyKey      = @"FontFamily";
static NSString *const kFontSizeKey        = @"FontSize";
static NSString *const kLineSpacingKey     = @"LineSpacing";
static NSString *const kTypewriterModeKey  = @"TypewriterMode";
static NSString *const kSpellCheckKey      = @"SpellChecking";

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

    [[NSColor controlBackgroundColor] setFill];
    NSRectFill(self.bounds);

    [[NSColor separatorColor] setStroke];
    [NSBezierPath strokeLineFromPoint:NSMakePoint(kRulerWidth - 0.5, 0)
                              toPoint:NSMakePoint(kRulerWidth - 0.5, self.bounds.size.height)];

    NSDictionary *attrs = @{
        NSFontAttributeName            : [NSFont monospacedDigitSystemFontOfSize:11.0
                                                                           weight:NSFontWeightRegular],
        NSForegroundColorAttributeName : [NSColor secondaryLabelColor]
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
- (IBAction)findNext:(id)sender;
- (IBAction)findPrevious:(id)sender;
- (void)setFindString:(NSString *)string;
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

- (IBAction)findPrevious:(id)sender {
    NSString *needle = _findField.stringValue;
    if (needle.length == 0) return;

    NSString *haystack = _targetTextView.string;
    NSRange sel = _targetTextView.selectedRange;
    NSUInteger searchEnd = (sel.location != NSNotFound) ? sel.location : _lastFoundLocation;

    NSRange found = NSMakeRange(NSNotFound, 0);
    if (searchEnd > 0)
        found = [haystack rangeOfString:needle
                                options:NSCaseInsensitiveSearch | NSBackwardsSearch
                                  range:NSMakeRange(0, searchEnd)];
    if (found.location == NSNotFound)
        found = [haystack rangeOfString:needle
                                options:NSCaseInsensitiveSearch | NSBackwardsSearch
                                  range:NSMakeRange(0, haystack.length)];

    if (found.location != NSNotFound) {
        _lastFoundLocation = found.location;
        [_targetTextView setSelectedRange:found];
        [_targetTextView scrollRangeToVisible:found];
    } else {
        NSBeep();
    }
}

- (void)setFindString:(NSString *)string {
    _findField.stringValue = string;
    _lastFoundLocation = 0;
}

- (IBAction)closePanel:(id)sender {
    [_panel orderOut:nil];
}

@end

// ============================================================
// MARK: - Weak Script Message Handler Proxy
// ============================================================

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
// MARK: - Drop Target View
// ============================================================

@protocol DropTargetDelegate <NSObject>
- (BOOL)loadFileAtPath:(NSString *)path;
@end

@interface DropTargetView : NSView
@property (nonatomic, weak) id<DropTargetDelegate> dropDelegate;
@end

@implementation DropTargetView
- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
    return self;
}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    if ([sender.draggingPasteboard canReadObjectForClasses:@[[NSURL class]]
         options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}])
        return NSDragOperationCopy;
    return NSDragOperationNone;
}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    NSArray *urls = [sender.draggingPasteboard readObjectsForClasses:@[[NSURL class]]
        options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    if (urls.firstObject) {
        [_dropDelegate loadFileAtPath:[(NSURL *)urls.firstObject path]];
        return YES;
    }
    return NO;
}
@end

// ============================================================
// MARK: - Application Delegate / Main Editor Window
// ============================================================

@interface AppDelegate : NSObject <NSApplicationDelegate, NSTextViewDelegate, NSWindowDelegate, WKScriptMessageHandler, NSToolbarDelegate, NSMenuDelegate, DropTargetDelegate>
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
// Preview
@property (nonatomic, strong) WKWebView             *previewWebView;
@property (nonatomic, strong) NSTimer               *previewTimer;
@property (nonatomic, strong) NSMenuItem            *previewMenuItem;
@property (nonatomic, assign) BOOL                   editMode;          // YES=editor, NO=preview
@property (nonatomic, assign) CGFloat                previewFontSize;
// Format
@property (nonatomic, copy)   NSString              *fileFormat;        // txt, md, docx, doc
// Custom text color (nil = use theme default)
@property (nonatomic, strong) NSColor               *customTextColor;
// Syntax highlighting guard
@property (nonatomic, assign) BOOL                   isHighlighting;
// New features
@property (nonatomic, assign) BOOL                   typewriterMode;
@property (nonatomic, strong) NSPopUpButton         *headingStylePopup;
@property (nonatomic, strong) NSMenu                *recentSubmenu;
@property (nonatomic, strong) NSPanel               *prefsPanel;
@property (nonatomic, assign) CGFloat                columnWidth;
@end

static NSString *gPendingOpenPath = nil;
static NSString *const kPreviewFontSizeKey     = @"PreviewFontSize";
static const CGFloat   kPreviewFontSizeDefault = 15.0;
static const CGFloat   kPreviewFontSizeMin     = 8.0;
static const CGFloat   kPreviewFontSizeMax     = 72.0;
static const CGFloat   kVInset                 = 24.0;
static NSString *const kColumnWidthKey         = @"ColumnWidth";
static const CGFloat   kColumnWidthDefault     = 720.0;
static const CGFloat   kColumnWidthMin         = 300.0;
static const CGFloat   kColumnWidthMax         = 1200.0;
static NSString *const kCustomTextColorKey     = @"CustomTextColor";

@implementation AppDelegate

// ── Lifecycle ─────────────────────────────────────────────

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    _currentFontSize    = 18.0;
    _fontFamily         = @"mono";
    _currentLineSpacing = 0.0;
    _editMode           = YES;
    _fileFormat         = @"txt";
    NSData *colorData = [[NSUserDefaults standardUserDefaults] dataForKey:kCustomTextColorKey];
    if (colorData) {
        _customTextColor = [NSKeyedUnarchiver unarchivedObjectOfClass:[NSColor class]
                                                             fromData:colorData error:nil];
    }
    double savedPreviewSize = [[NSUserDefaults standardUserDefaults] doubleForKey:kPreviewFontSizeKey];
    _previewFontSize    = (savedPreviewSize >= kPreviewFontSizeMin && savedPreviewSize <= kPreviewFontSizeMax)
                              ? savedPreviewSize : kPreviewFontSizeDefault;

    // Load persisted preferences
    NSString *savedFamily = [[NSUserDefaults standardUserDefaults] stringForKey:kFontFamilyKey];
    if (savedFamily) _fontFamily = savedFamily;
    double savedSize = [[NSUserDefaults standardUserDefaults] doubleForKey:kFontSizeKey];
    if (savedSize >= 8 && savedSize <= 72) _currentFontSize = savedSize;
    double savedSpacing = [[NSUserDefaults standardUserDefaults] doubleForKey:kLineSpacingKey];
    if (savedSpacing >= 0) _currentLineSpacing = savedSpacing;
    _typewriterMode = [[NSUserDefaults standardUserDefaults] boolForKey:kTypewriterModeKey];
    double savedColWidth = [[NSUserDefaults standardUserDefaults] doubleForKey:kColumnWidthKey];
    _columnWidth = (savedColWidth >= kColumnWidthMin && savedColWidth <= kColumnWidthMax)
                       ? savedColWidth : kColumnWidthDefault;

    [self buildMenu];
    [self buildWindow];

    // Apply spell check pref after textView is created
    _textView.continuousSpellCheckingEnabled = [[NSUserDefaults standardUserDefaults] boolForKey:kSpellCheckKey];

    [self.window makeKeyAndOrderFront:nil];
    if (@available(macOS 14.0, *)) {
        [NSApp activate];
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        [NSApp activateIgnoringOtherApps:YES];
#pragma clang diagnostic pop
    }
    if (gPendingOpenPath) {
        NSString *path = gPendingOpenPath; gPendingOpenPath = nil;
        [self loadFileAtPath:path];
    }
    // Observe system appearance changes
    [NSApp addObserver:self forKeyPath:@"effectiveAppearance" options:0 context:nil];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object
                        change:(NSDictionary *)change context:(void *)context {
    if ([keyPath isEqualToString:@"effectiveAppearance"]) {
        [self applyTheme];
        [self applyWYSIWYMFormatting];
        if (!_editMode) [self updatePreview];
    }
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
    if (!_textView) {
        gPendingOpenPath = [filename copy];
        return YES;
    }
    if (_isDirty && ![self confirmDiscardWithAction:@"open another file"]) return NO;
    return [self loadFileAtPath:filename];
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
    NSRect frame = NSMakeRect(0, 0, 820, 700);
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

    // Full-screen support + frame persistence
    _window.collectionBehavior |= NSWindowCollectionBehaviorFullScreenPrimary;
    [_window setFrameAutosaveName:@"MainWindow"];

    // Set up drop target as content view
    DropTargetView *dropView = [[DropTargetView alloc] initWithFrame:_window.contentView.frame];
    dropView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    dropView.dropDelegate = self;
    _window.contentView = dropView;

    static const CGFloat kStatusBarHeight = 22.0;
    NSRect cb = _window.contentView.bounds;
    CGFloat editH = cb.size.height - kStatusBarHeight;
    NSRect editFrame = NSMakeRect(0, kStatusBarHeight, cb.size.width, editH);

    // ── Editor scroll view ─────────────────────────────────
    _scrollView = [[NSScrollView alloc] initWithFrame:editFrame];
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
    _textView.font                         = [NSFont monospacedSystemFontOfSize:_currentFontSize
                                                                         weight:NSFontWeightRegular];
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
    _scrollView.rulersVisible      = NO;   // off by default

    // ── Preview web view (same frame, hidden while editing) ──
    WKWebViewConfiguration *wkConfig = [[WKWebViewConfiguration alloc] init];
    WKUserContentController *ucc = [[WKUserContentController alloc] init];
    [ucc addScriptMessageHandler:[[WeakScriptMessageHandler alloc] initWithDelegate:self]
                             name:@"copyCode"];
    wkConfig.userContentController = ucc;
    _previewWebView = [[WKWebView alloc] initWithFrame:editFrame configuration:wkConfig];
    _previewWebView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    _previewWebView.hidden           = YES;

    [_window.contentView addSubview:_scrollView];
    [_window.contentView addSubview:_previewWebView];

    // ── Status bar ─────────────────────────────────────────
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

    [self applyTheme];
    [self applyFont];
    [self updateTextContainerInset];

    _findReplace = [[FindReplaceController alloc] initWithTargetTextView:_textView];
    [self updateStatusBar];

    // Set up NSToolbar
    [self setupToolbar];
}

// ── Toolbar ───────────────────────────────────────────────

- (void)setupToolbar {
    NSToolbar *tb = [[NSToolbar alloc] initWithIdentifier:@"MainToolbar"];
    tb.delegate = self;
    tb.allowsUserCustomization = NO;
    tb.displayMode = NSToolbarDisplayModeIconOnly;
    _window.toolbar = tb;
}

// NSToolbarDelegate

- (NSArray<NSToolbarItemIdentifier> *)toolbarAllowedItemIdentifiers:(NSToolbar *)toolbar {
    return @[@"Bold", @"Italic", @"Underline", @"Strikethrough",
             NSToolbarSpaceItemIdentifier,
             @"AlignLeft", @"AlignCenter", @"AlignRight",
             NSToolbarFlexibleSpaceItemIdentifier,
             @"HeadingStyle"];
}

- (NSArray<NSToolbarItemIdentifier> *)toolbarDefaultItemIdentifiers:(NSToolbar *)toolbar {
    return [self toolbarAllowedItemIdentifiers:toolbar];
}

- (NSToolbarItem *)toolbar:(NSToolbar *)toolbar
     itemForItemIdentifier:(NSToolbarItemIdentifier)ident
 willBeInsertedIntoToolbar:(BOOL)flag {
    NSToolbarItem *item = [[NSToolbarItem alloc] initWithItemIdentifier:ident];
    if ([ident isEqualToString:@"Bold"]) {
        item.image = [NSImage imageWithSystemSymbolName:@"bold" accessibilityDescription:@"Bold"];
        item.label = @"Bold"; item.action = @selector(toggleBoldface:); item.target = nil;
        item.toolTip = @"Bold (⌘B)";
    } else if ([ident isEqualToString:@"Italic"]) {
        item.image = [NSImage imageWithSystemSymbolName:@"italic" accessibilityDescription:@"Italic"];
        item.label = @"Italic"; item.action = @selector(toggleItalic:); item.target = nil;
    } else if ([ident isEqualToString:@"Underline"]) {
        item.image = [NSImage imageWithSystemSymbolName:@"underline" accessibilityDescription:@"Underline"];
        item.label = @"Underline"; item.action = @selector(toggleUnderline:); item.target = nil;
    } else if ([ident isEqualToString:@"Strikethrough"]) {
        item.image = [NSImage imageWithSystemSymbolName:@"strikethrough" accessibilityDescription:@"Strikethrough"];
        item.label = @"Strike"; item.action = @selector(toggleStrikethrough:); item.target = nil;
    } else if ([ident isEqualToString:@"AlignLeft"]) {
        item.image = [NSImage imageWithSystemSymbolName:@"text.alignleft" accessibilityDescription:@"Left"];
        item.label = @"Left"; item.action = @selector(alignLeft:); item.target = nil;
    } else if ([ident isEqualToString:@"AlignCenter"]) {
        item.image = [NSImage imageWithSystemSymbolName:@"text.aligncenter" accessibilityDescription:@"Center"];
        item.label = @"Center"; item.action = @selector(alignCenter:); item.target = nil;
    } else if ([ident isEqualToString:@"AlignRight"]) {
        item.image = [NSImage imageWithSystemSymbolName:@"text.alignright" accessibilityDescription:@"Right"];
        item.label = @"Right"; item.action = @selector(alignRight:); item.target = nil;
    } else if ([ident isEqualToString:@"HeadingStyle"]) {
        _headingStylePopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(0,0,130,24) pullsDown:NO];
        NSArray *titles = @[@"Normal", @"Heading 1", @"Heading 2", @"Heading 3", @"Heading 4", @"Heading 5", @"Heading 6"];
        for (NSUInteger i = 0; i < titles.count; i++) {
            [_headingStylePopup addItemWithTitle:titles[i]];
            [_headingStylePopup itemAtIndex:i].tag = (NSInteger)i;
        }
        _headingStylePopup.target = self;
        _headingStylePopup.action = @selector(headingPopupChanged:);
        item.view = _headingStylePopup;
        item.label = @"Style";
        item.minSize = NSMakeSize(130, 24);
        item.maxSize = NSMakeSize(130, 24);
    }
    return item;
}

- (BOOL)validateToolbarItem:(NSToolbarItem *)item {
    if ([item.itemIdentifier isEqualToString:@"HeadingStyle"])
        return [self isRichTextMode] && _editMode;
    return [self isRichTextMode] && _editMode;
}

- (IBAction)headingPopupChanged:(id)sender {
    NSInteger level = [_headingStylePopup selectedItem].tag;
    NSRange sel = _textView.selectedRange;
    NSRange paraRange = [_textView.string paragraphRangeForRange:sel];
    static CGFloat sizes[] = {0, 28, 22, 18, 14, 13, 12};
    NSFont *font = (level == 0) ? [self currentFont] : [NSFont boldSystemFontOfSize:sizes[level]];
    [_textView.textStorage addAttribute:NSFontAttributeName value:font range:paraRange];
    _isDirty = YES;
    [self updateTitle];
}

// ── Theme ──────────────────────────────────────────────────

- (BOOL)isRichTextMode {
    return [_fileFormat isEqualToString:@"docx"] || [_fileFormat isEqualToString:@"doc"];
}

- (BOOL)isDarkMode {
    NSAppearanceName matched = [_window.effectiveAppearance
        bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
    return [matched isEqualToString:NSAppearanceNameDarkAqua];
}

- (NSColor *)iaBgColor {
    return [self isDarkMode]
        ? [NSColor colorWithRed:0x1A/255.0 green:0x1A/255.0 blue:0x1A/255.0 alpha:1.0]
        : [NSColor whiteColor];
}

- (NSColor *)iaTextColor {
    if (_customTextColor) return _customTextColor;
    return [self isDarkMode]
        ? [NSColor colorWithRed:0xD7/255.0 green:0xD5/255.0 blue:0xCF/255.0 alpha:1.0]
        : [NSColor colorWithRed:0x1A/255.0 green:0x1A/255.0 blue:0x1A/255.0 alpha:1.0];
}

- (NSColor *)iaHeadingColor {
    return [self isDarkMode]
        ? [NSColor colorWithRed:0x7F/255.0 green:0xBB/255.0 blue:0xE0/255.0 alpha:1.0]
        : [NSColor colorWithRed:0x24/255.0 green:0x58/255.0 blue:0xA5/255.0 alpha:1.0];
}

- (NSColor *)iaCodeColor {
    return [self isDarkMode]
        ? [NSColor colorWithRed:0xE8/255.0 green:0xA8/255.0 blue:0x57/255.0 alpha:1.0]
        : [NSColor colorWithRed:0xA0/255.0 green:0x52/255.0 blue:0x2D/255.0 alpha:1.0];
}

- (void)applyTheme {
    NSColor *bg   = [self iaBgColor];
    NSColor *text = [self iaTextColor];
    _textView.backgroundColor     = bg;
    _textView.insertionPointColor = text;
    _scrollView.backgroundColor   = bg;
    _window.backgroundColor       = bg;
    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.lineSpacing = _currentLineSpacing;
    NSDictionary *typingAttrs = @{
        NSFontAttributeName            : [self currentFont],
        NSForegroundColorAttributeName : text,
        NSParagraphStyleAttributeName  : para,
    };
    _textView.typingAttributes = typingAttrs;
    // Only force text color in plain-text mode; rich text carries its own colours
    if (![self isRichTextMode]) {
        _textView.textColor = text;
    }
}

// ── Centered Column ────────────────────────────────────────

- (void)updateTextContainerInset {
    CGFloat availW = _scrollView.contentSize.width;
    CGFloat hInset = MAX(0.0, (availW - _columnWidth) / 2.0);
    _textView.textContainerInset = NSMakeSize(hInset, kVInset);
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
    NSMenuItem *prefsItem = [appMenu addItemWithTitle:@"Preferences…" action:@selector(showPreferences:) keyEquivalent:@","];
    prefsItem.target = self;
    [appMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *servicesItem = [appMenu addItemWithTitle:@"Services" action:nil keyEquivalent:@""];
    NSMenu *servicesMenu = [[NSMenu alloc] initWithTitle:@"Services"];
    servicesItem.submenu = servicesMenu;
    [NSApp setServicesMenu:servicesMenu];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Hide Notepad"  action:@selector(hide:)                  keyEquivalent:@"h"];
    NSMenuItem *hideOthers = [appMenu addItemWithTitle:@"Hide Others"
                                                action:@selector(hideOtherApplications:)
                                         keyEquivalent:@"h"];
    hideOthers.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    [appMenu addItemWithTitle:@"Show All"      action:@selector(unhideAllApplications:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit Notepad"  action:@selector(terminate:)             keyEquivalent:@"q"];
    appItem.submenu = appMenu;

    // File menu
    NSMenuItem *fileItem = [main addItemWithTitle:@"File" action:nil keyEquivalent:@""];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"New"   action:@selector(newDocument:)  keyEquivalent:@"n"];
    [fileMenu addItemWithTitle:@"Open…" action:@selector(openDocument:) keyEquivalent:@"o"];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Close" action:@selector(performClose:) keyEquivalent:@"w"];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Save"  action:@selector(saveDocument:) keyEquivalent:@"s"];
    NSMenuItem *saveAs = [fileMenu addItemWithTitle:@"Save As…"
                                             action:@selector(saveDocumentAs:)
                                      keyEquivalent:@"s"];
    saveAs.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    NSMenuItem *revertItem = [fileMenu addItemWithTitle:@"Revert to Saved"
                                                 action:@selector(revertDocumentToSaved:)
                                          keyEquivalent:@""];
    revertItem.target = self;
    [fileMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *printItem = [fileMenu addItemWithTitle:@"Print…" action:@selector(printDocument:) keyEquivalent:@"p"];
    printItem.target = self;
    [fileMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *recentItem = [fileMenu addItemWithTitle:@"Open Recent" action:nil keyEquivalent:@""];
    _recentSubmenu = [[NSMenu alloc] initWithTitle:@"Open Recent"];
    _recentSubmenu.delegate = self;
    recentItem.submenu = _recentSubmenu;
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
    NSMenuItem *pasteMatchItem = [editMenu addItemWithTitle:@"Paste and Match Style"
                                                     action:@selector(pasteAsPlainText:)
                                              keyEquivalent:@"v"];
    pasteMatchItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    [editMenu addItemWithTitle:@"Select All" action:@selector(selectAll:) keyEquivalent:@"a"];
    [editMenu addItem:[NSMenuItem separatorItem]];

    // Find submenu
    NSMenuItem *findItem = [editMenu addItemWithTitle:@"Find" action:nil keyEquivalent:@""];
    NSMenu *findMenu = [[NSMenu alloc] initWithTitle:@"Find"];
    NSMenuItem *findPanelItem = [findMenu addItemWithTitle:@"Find…"
                                                    action:@selector(showFindReplace:)
                                             keyEquivalent:@"f"];
    findPanelItem.target = self;
    NSMenuItem *findNextItem = [findMenu addItemWithTitle:@"Find Next"
                                                   action:@selector(findNextOccurrence:)
                                            keyEquivalent:@"g"];
    findNextItem.target = self;
    NSMenuItem *findPrevItem = [findMenu addItemWithTitle:@"Find Previous"
                                                   action:@selector(findPreviousOccurrence:)
                                            keyEquivalent:@"G"];
    findPrevItem.target = self;
    NSMenuItem *useSelItem = [findMenu addItemWithTitle:@"Use Selection for Find"
                                                 action:@selector(useSelectionForFind:)
                                          keyEquivalent:@"e"];
    useSelItem.target = self;
    NSMenuItem *jumpSelItem = [findMenu addItemWithTitle:@"Jump to Selection"
                                                  action:@selector(jumpToSelection:)
                                           keyEquivalent:@"j"];
    jumpSelItem.target = self;
    findItem.submenu = findMenu;
    [editMenu addItem:[NSMenuItem separatorItem]];

    // Spelling and Grammar submenu
    NSMenuItem *spellingItem = [editMenu addItemWithTitle:@"Spelling and Grammar" action:nil keyEquivalent:@""];
    NSMenu *spellingMenu = [[NSMenu alloc] initWithTitle:@"Spelling and Grammar"];
    [spellingMenu addItemWithTitle:@"Show Spelling and Grammar" action:@selector(showGuessPanel:) keyEquivalent:@":"];
    [spellingMenu addItemWithTitle:@"Check Document Now"        action:@selector(checkSpelling:)  keyEquivalent:@";"];
    [spellingMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *spellCheckItem = [spellingMenu addItemWithTitle:@"Check Spelling While Typing"
                                                         action:@selector(toggleSpellChecking:)
                                                  keyEquivalent:@""];
    spellCheckItem.target = self;
    [spellingMenu addItemWithTitle:@"Check Grammar With Spelling"    action:@selector(toggleGrammarChecking:)             keyEquivalent:@""];
    [spellingMenu addItemWithTitle:@"Correct Spelling Automatically" action:@selector(toggleAutomaticSpellingCorrection:) keyEquivalent:@""];
    spellingItem.submenu = spellingMenu;

    // Transformations submenu
    NSMenuItem *transformItem = [editMenu addItemWithTitle:@"Transformations" action:nil keyEquivalent:@""];
    NSMenu *transformMenu = [[NSMenu alloc] initWithTitle:@"Transformations"];
    [transformMenu addItemWithTitle:@"Make Upper Case" action:@selector(uppercaseWord:)  keyEquivalent:@""];
    [transformMenu addItemWithTitle:@"Make Lower Case" action:@selector(lowercaseWord:)  keyEquivalent:@""];
    [transformMenu addItemWithTitle:@"Capitalize"      action:@selector(capitalizeWord:) keyEquivalent:@""];
    transformItem.submenu = transformMenu;
    [editMenu addItem:[NSMenuItem separatorItem]];

    [editMenu addItemWithTitle:@"Start Dictation…" action:@selector(startDictation:) keyEquivalent:@""];
    NSMenuItem *emojiItem = [editMenu addItemWithTitle:@"Emoji & Symbols"
                                                action:@selector(orderFrontCharacterPalette:)
                                         keyEquivalent:@" "];
    emojiItem.keyEquivalentModifierMask = NSEventModifierFlagControl | NSEventModifierFlagCommand;
    editItem.submenu = editMenu;

    // Format menu
    NSMenuItem *formatItem = [main addItemWithTitle:@"Format" action:nil keyEquivalent:@""];
    NSMenu *formatMenu = [[NSMenu alloc] initWithTitle:@"Format"];

    // Inline formatting at top
    NSMenuItem *boldFmt = [formatMenu addItemWithTitle:@"Bold" action:@selector(toggleBoldface:) keyEquivalent:@"b"];
    boldFmt.target = nil;
    NSMenuItem *italicFmt = [formatMenu addItemWithTitle:@"Italic" action:@selector(toggleItalic:) keyEquivalent:@"i"];
    italicFmt.target = nil;
    NSMenuItem *underlineFmt = [formatMenu addItemWithTitle:@"Underline" action:@selector(toggleUnderline:) keyEquivalent:@"u"];
    underlineFmt.target = nil;
    NSMenuItem *strikeFmt = [formatMenu addItemWithTitle:@"Strikethrough" action:@selector(toggleStrikethrough:) keyEquivalent:@""];
    strikeFmt.target = nil;
    [formatMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *alignLeftFmt = [formatMenu addItemWithTitle:@"Align Left" action:@selector(alignLeft:) keyEquivalent:@""];
    alignLeftFmt.target = nil;
    NSMenuItem *alignCenterFmt = [formatMenu addItemWithTitle:@"Align Center" action:@selector(alignCenter:) keyEquivalent:@""];
    alignCenterFmt.target = nil;
    NSMenuItem *alignRightFmt = [formatMenu addItemWithTitle:@"Align Right" action:@selector(alignRight:) keyEquivalent:@""];
    alignRightFmt.target = nil;
    [formatMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *fontPanelItem = [formatMenu addItemWithTitle:@"Show Fonts…" action:@selector(orderFrontFontPanel:) keyEquivalent:@"t"];
    fontPanelItem.target = nil;
    [formatMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *styleItem = [formatMenu addItemWithTitle:@"Paragraph Style" action:nil keyEquivalent:@""];
    NSMenu *styleMenu = [[NSMenu alloc] initWithTitle:@"Paragraph Style"];
    NSArray *styleNames = @[@"Normal Text", @"Heading 1", @"Heading 2",
                            @"Heading 3", @"Heading 4", @"Heading 5", @"Heading 6"];
    for (NSUInteger i = 0; i < styleNames.count; i++) {
        NSMenuItem *si = [styleMenu addItemWithTitle:styleNames[i]
                                             action:@selector(applyParagraphStyle:)
                                      keyEquivalent:@""];
        si.tag    = (NSInteger)i;
        si.target = self;
    }
    styleItem.submenu = styleMenu;

    [formatMenu addItem:[NSMenuItem separatorItem]];

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

    [formatMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *colorItem = [formatMenu addItemWithTitle:@"Text Color…"
                                                  action:@selector(showTextColorPicker:)
                                           keyEquivalent:@""];
    colorItem.target = self;
    NSMenuItem *resetColorItem = [formatMenu addItemWithTitle:@"Reset Text Color"
                                                       action:@selector(resetTextColor:)
                                                keyEquivalent:@""];
    resetColorItem.target = self;

    formatItem.submenu = formatMenu;

    // View menu
    NSMenuItem *viewItem = [main addItemWithTitle:@"View" action:nil keyEquivalent:@""];
    NSMenu *viewMenu = [[NSMenu alloc] initWithTitle:@"View"];

    NSMenuItem *lineNumItem = [viewMenu addItemWithTitle:@"Toggle Line Numbers"
                                                  action:@selector(toggleLineNumbers:)
                                           keyEquivalent:@"l"];
    lineNumItem.target = self;
    lineNumItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;

    NSMenuItem *twItem = [viewMenu addItemWithTitle:@"Typewriter Mode"
                                             action:@selector(toggleTypewriterMode:)
                                      keyEquivalent:@"t"];
    twItem.target = self;
    twItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;

    [viewMenu addItem:[NSMenuItem separatorItem]];

    _previewMenuItem = [viewMenu addItemWithTitle:@"Show Preview"
                                           action:@selector(toggleEditPreview:)
                                    keyEquivalent:@"\\"];
    _previewMenuItem.target = self;

    [viewMenu addItem:[NSMenuItem separatorItem]];

    NSMenuItem *previewBigger  = [viewMenu addItemWithTitle:@"Preview Larger"
                                                     action:@selector(previewFontSizeUp:)
                                              keyEquivalent:@"="];
    NSMenuItem *previewSmaller = [viewMenu addItemWithTitle:@"Preview Smaller"
                                                     action:@selector(previewFontSizeDown:)
                                              keyEquivalent:@"-"];
    NSMenuItem *previewActual  = [viewMenu addItemWithTitle:@"Preview Actual Size"
                                                     action:@selector(previewFontSizeReset:)
                                              keyEquivalent:@"0"];
    for (NSMenuItem *it in @[previewBigger, previewSmaller, previewActual]) {
        it.target = self;
        it.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;
    }

    [viewMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *toolbarItem = [viewMenu addItemWithTitle:@"Show/Hide Toolbar"
                                                  action:@selector(toggleToolbarShown:)
                                           keyEquivalent:@"t"];
    toolbarItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagOption;

    viewItem.submenu = viewMenu;

    // Window menu
    NSMenuItem *windowItem = [main addItemWithTitle:@"Window" action:nil keyEquivalent:@""];
    NSMenu *windowMenu = [[NSMenu alloc] initWithTitle:@"Window"];
    [windowMenu addItemWithTitle:@"Minimize"        action:@selector(miniaturize:) keyEquivalent:@"m"];
    [windowMenu addItemWithTitle:@"Zoom"            action:@selector(zoom:)        keyEquivalent:@""];
    [windowMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *fsItem = [windowMenu addItemWithTitle:@"Enter Full Screen"
                                               action:@selector(toggleFullScreen:)
                                        keyEquivalent:@"f"];
    fsItem.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagControl;
    [windowMenu addItem:[NSMenuItem separatorItem]];
    [windowMenu addItemWithTitle:@"Bring All to Front" action:@selector(arrangeInFront:) keyEquivalent:@""];
    windowItem.submenu = windowMenu;
    [NSApp setWindowsMenu:windowMenu];

    (void)boldFmt; (void)italicFmt; (void)underlineFmt; (void)strikeFmt;
    (void)alignLeftFmt; (void)alignCenterFmt; (void)alignRightFmt;
    (void)fontPanelItem;
}

// ── NSMenuDelegate (Open Recent) ──────────────────────────

- (void)menuNeedsUpdate:(NSMenu *)menu {
    if (menu != _recentSubmenu) return;
    [menu removeAllItems];
    NSArray<NSURL *> *recent = [[NSDocumentController sharedDocumentController] recentDocumentURLs];
    for (NSURL *url in recent) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:url.lastPathComponent
                                                     action:@selector(openRecentFile:)
                                              keyEquivalent:@""];
        item.representedObject = url;
        item.target = self;
        [menu addItem:item];
    }
    if (recent.count > 0) [menu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *clear = [[NSMenuItem alloc] initWithTitle:@"Clear Menu"
                                                   action:@selector(clearRecentDocuments:)
                                            keyEquivalent:@""];
    clear.target = [NSDocumentController sharedDocumentController];
    [menu addItem:clear];
}

- (IBAction)openRecentFile:(id)sender {
    NSURL *url = [(NSMenuItem *)sender representedObject];
    if (_isDirty && ![self confirmDiscardWithAction:@"open another file"]) return;
    [self loadFileAtPath:url.path];
}

// ── NSTextViewDelegate ────────────────────────────────────

- (void)textDidChange:(NSNotification *)note {
    if (!_isDirty) {
        _isDirty = YES;
        [self updateTitle];
    }
    [_rulerView setNeedsDisplay:YES];
    [self updateStatusBar];
    if (!_isHighlighting && ![self isRichTextMode]) {
        [self applyWYSIWYMFormatting];
    }
    [self schedulePreviewUpdate];
    if (_typewriterMode && _editMode) [self scrollCursorToCenter];
}

- (void)textViewDidChangeSelection:(NSNotification *)note {
    [self updateStatusBar];
    if (_typewriterMode && _editMode) [self scrollCursorToCenter];
    if (!_isHighlighting && ![self isRichTextMode] && _editMode)
        [self applyWYSIWYMFormatting];
    if (_headingStylePopup && [self isRichTextMode] && _editMode) {
        NSUInteger pos = _textView.selectedRange.location;
        if (pos < _textView.textStorage.length || pos == 0) {
            NSUInteger safePos = MIN(pos, _textView.textStorage.length > 0 ? _textView.textStorage.length - 1 : 0);
            NSFont *font = [_textView.textStorage attribute:NSFontAttributeName atIndex:safePos effectiveRange:nil];
            CGFloat sz = font ? font.pointSize : 12.0;
            NSInteger tag = 0;
            if (sz >= 24) tag = 1;
            else if (sz >= 19) tag = 2;
            else if (sz >= 16) tag = 3;
            else if (sz >= 13) tag = 4;
            [_headingStylePopup selectItemWithTag:tag];
        }
    }
}

// ── Actions ───────────────────────────────────────────────

- (IBAction)newDocument:(id)sender {
    if (_isDirty && ![self confirmDiscardWithAction:@"create a new document"]) return;
    _currentFilePath = nil;
    _fileFormat      = @"txt";
    _isDirty = NO;
    _textView.richText = NO;
    [_textView.textStorage replaceCharactersInRange:NSMakeRange(0, _textView.string.length)
                                         withString:@""];
    [_textView.undoManager removeAllActions];
    [self applyTheme];
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

    NSString *ext  = path.pathExtension.lowercaseString;
    NSError  *err  = nil;

    if ([ext isEqualToString:@"docx"] || [ext isEqualToString:@"doc"]) {
        _fileFormat = ext;
        NSURL *url  = [NSURL fileURLWithPath:path];
        NSString *docType = [ext isEqualToString:@"docx"]
            ? NSOfficeOpenXMLTextDocumentType
            : NSDocFormatTextDocumentType;
        NSDictionary *docAttrs = nil;
        NSAttributedString *attrStr = [[NSAttributedString alloc]
            initWithURL:url
                options:@{NSDocumentTypeDocumentAttribute: docType}
     documentAttributes:&docAttrs
                  error:&err];
        if (err || !attrStr) {
            [self showError:[NSString stringWithFormat:@"Could not open file:\n%@",
                err.localizedDescription ?: @"Unknown error"]];
            return NO;
        }
        _textView.richText = YES;
        [_textView.textStorage setAttributedString:attrStr];
        [_textView.undoManager removeAllActions];
        _currentFilePath = path;
        _isDirty = NO;
        [self applyTheme];
        [self fixDocxColorsForDarkMode];
        [self updateTitle];
        [self updateStatusBar];
        [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL fileURLWithPath:path]];
        return YES;
    }

    // Plain text / Markdown
    _fileFormat = ([ext isEqualToString:@"md"] || [ext isEqualToString:@"markdown"]) ? @"md" : @"txt";
    NSString *text = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:&err];
    if (err) {
        text = nil; err = nil;
        text = [NSString stringWithContentsOfFile:path encoding:NSISOLatin1StringEncoding error:&err];
    }
    if (err || !text) {
        [self showError:[NSString stringWithFormat:@"Could not open file:\n%@",
            err.localizedDescription ?: @"Unknown error"]];
        return NO;
    }
    text = [text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    text = [text stringByReplacingOccurrencesOfString:@"\r"   withString:@"\n"];

    _textView.richText = NO;
    [_textView.textStorage replaceCharactersInRange:NSMakeRange(0, _textView.string.length)
                                         withString:text];
    [_textView.undoManager removeAllActions];
    _currentFilePath = path;
    _isDirty = NO;
    [self applyFont];
    [self schedulePreviewUpdate];
    [self updateTitle];
    [self updateStatusBar];
    [[NSDocumentController sharedDocumentController] noteNewRecentDocumentURL:[NSURL fileURLWithPath:path]];
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
    NSString *defaultName;
    if (_currentFilePath) {
        defaultName = _currentFilePath.lastPathComponent;
    } else if ([_fileFormat isEqualToString:@"doc"]) {
        defaultName = @"Untitled.docx";
    } else if ([_fileFormat isEqualToString:@"docx"]) {
        defaultName = @"Untitled.docx";
    } else if ([_fileFormat isEqualToString:@"md"]) {
        defaultName = @"Untitled.md";
    } else {
        defaultName = @"Untitled.txt";
    }
    panel.nameFieldStringValue = defaultName;

    if ([panel runModal] != NSModalResponseOK) return NO;
    NSString *prevPath   = _currentFilePath;
    NSString *prevFormat = _fileFormat;
    _currentFilePath = panel.URL.path;

    // Derive format from chosen extension
    NSString *newExt = _currentFilePath.pathExtension.lowercaseString;
    if ([newExt isEqualToString:@"docx"])                                         _fileFormat = @"docx";
    else if ([newExt isEqualToString:@"doc"])                                     _fileFormat = @"doc";
    else if ([newExt isEqualToString:@"md"] || [newExt isEqualToString:@"markdown"]) _fileFormat = @"md";
    else                                                                           _fileFormat = @"txt";

    if (![self writeToPath:_currentFilePath]) {
        _currentFilePath = prevPath;
        _fileFormat      = prevFormat;
        return NO;
    }
    return YES;
}

- (IBAction)saveDocumentAs:(id)sender {
    [self doSaveAs];
}

- (BOOL)writeToPath:(NSString *)path {
    if ([_fileFormat isEqualToString:@"doc"]) {
        [self showError:@".doc files are read-only.\nUse File > Save As… to save as .docx or .txt."];
        return NO;
    }

    if ([_fileFormat isEqualToString:@"docx"]) {
        // Rich-text mode: save attributed string directly.
        // Plain-text mode (e.g. TXT saved-as DOCX): wrap in a body-font attributed string.
        NSAttributedString *attrStr = [self isRichTextMode]
            ? _textView.textStorage
            : [[NSAttributedString alloc] initWithString:_textView.string
                                              attributes:@{NSFontAttributeName: [NSFont systemFontOfSize:12]}];
        NSError *err = nil;
        NSData *data = [attrStr dataFromRange:NSMakeRange(0, attrStr.length)
                           documentAttributes:@{NSDocumentTypeDocumentAttribute: NSOfficeOpenXMLTextDocumentType}
                                        error:&err];
        if (!data || err) {
            [self showError:[NSString stringWithFormat:@"Could not build DOCX:\n%@",
                err.localizedDescription ?: @"Unknown error"]];
            return NO;
        }
        if (![data writeToFile:path atomically:YES]) {
            [self showError:@"Could not write file."];
            return NO;
        }
        _isDirty = NO;
        [self updateTitle];
        return YES;
    }

    // txt / md plain-text save
    NSFileManager *fm = [NSFileManager defaultManager];
    NSNumber *origPerms = [fm attributesOfItemAtPath:path error:nil][NSFilePosixPermissions];

    NSError *err = nil;
    BOOL ok = [_textView.string writeToFile:path
                                 atomically:YES
                                   encoding:NSUTF8StringEncoding
                                      error:&err];
    if (!ok) {
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

- (IBAction)findNextOccurrence:(id)sender {
    if (_findReplace.findField.stringValue.length == 0) { [_findReplace showPanel]; return; }
    [_findReplace findNext:sender];
}

- (IBAction)findPreviousOccurrence:(id)sender {
    if (_findReplace.findField.stringValue.length == 0) { [_findReplace showPanel]; return; }
    [_findReplace findPrevious:sender];
}

- (IBAction)useSelectionForFind:(id)sender {
    NSRange sel = _textView.selectedRange;
    if (sel.length == 0) return;
    [_findReplace setFindString:[_textView.string substringWithRange:sel]];
    [_findReplace showPanel];
}

- (IBAction)jumpToSelection:(id)sender {
    [_textView scrollRangeToVisible:_textView.selectedRange];
}

- (IBAction)revertDocumentToSaved:(id)sender {
    if (!_currentFilePath) return;
    if (_isDirty) {
        NSAlert *alert = [[NSAlert alloc] init];
        alert.messageText = @"Revert to Saved";
        alert.informativeText = [NSString stringWithFormat:
            @"Revert to the saved version of \"%@\"? Your current changes will be lost.",
            _currentFilePath.lastPathComponent];
        [alert addButtonWithTitle:@"Revert"];
        [alert addButtonWithTitle:@"Cancel"];
        if ([alert runModal] != NSAlertFirstButtonReturn) return;
    }
    [self loadFileAtPath:_currentFilePath];
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(revertDocumentToSaved:)) return _currentFilePath != nil;
    if (item.action == @selector(findNextOccurrence:) ||
        item.action == @selector(findPreviousOccurrence:))
        return _findReplace.findField.stringValue.length > 0;
    return YES;
}

// ── Dark Mode DOCX Color Fix ──────────────────────────────

- (void)fixDocxColorsForDarkMode {
    if (![self isDarkMode]) return;
    NSColor *light = [self iaTextColor];
    NSTextStorage *ts = _textView.textStorage;
    [ts beginEditing];
    [ts enumerateAttribute:NSForegroundColorAttributeName inRange:NSMakeRange(0, ts.length)
                   options:0 usingBlock:^(id val, NSRange r, BOOL *stop) {
        (void)stop;
        if (!val) return;
        NSColor *c = [(NSColor *)val colorUsingColorSpace:[NSColorSpace deviceRGBColorSpace]];
        if (c && c.redComponent < 0.25 && c.greenComponent < 0.25 && c.blueComponent < 0.25)
            [ts addAttribute:NSForegroundColorAttributeName value:light range:r];
    }];
    [ts endEditing];
}

// ── Print ────────────────────────────────────────────────

- (IBAction)printDocument:(id)sender {
    NSPrintOperation *op = [NSPrintOperation printOperationWithView:_textView];
    [op runOperationModalForWindow:_window delegate:nil didRunSelector:nil contextInfo:nil];
}

// ── Spell Checking ────────────────────────────────────────

- (IBAction)toggleSpellChecking:(id)sender {
    BOOL on = !_textView.continuousSpellCheckingEnabled;
    _textView.continuousSpellCheckingEnabled = on;
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:kSpellCheckKey];
}

// ── Typewriter Mode ───────────────────────────────────────

- (IBAction)toggleTypewriterMode:(id)sender {
    _typewriterMode = !_typewriterMode;
    [[NSUserDefaults standardUserDefaults] setBool:_typewriterMode forKey:kTypewriterModeKey];
}

- (void)scrollCursorToCenter {
    NSRange sel = _textView.selectedRange;
    if (sel.location == NSNotFound) return;
    NSLayoutManager *lm = _textView.layoutManager;
    NSRect lineRect;
    // Cursor past end of laid-out glyphs (blank line after a trailing newline)
    if (sel.location >= _textView.string.length && !NSIsEmptyRect(lm.extraLineFragmentRect)) {
        lineRect = lm.extraLineFragmentRect;
    } else {
        NSRange gr = [lm glyphRangeForCharacterRange:NSMakeRange(sel.location, 0)
                                actualCharacterRange:nil];
        lineRect = [lm lineFragmentRectForGlyphAtIndex:gr.location effectiveRange:nil];
    }
    CGFloat cursorY = lineRect.origin.y + _textView.textContainerInset.height;
    CGFloat viewH = _scrollView.contentSize.height;
    CGFloat targetY = MAX(0, cursorY - viewH / 2.0);
    [_scrollView.contentView scrollToPoint:NSMakePoint(0, targetY)];
    [_scrollView reflectScrolledClipView:_scrollView.contentView];
}

// ── Preferences Window ────────────────────────────────────

- (IBAction)showPreferences:(id)sender {
    if (_prefsPanel) { [_prefsPanel makeKeyAndOrderFront:nil]; return; }
    _prefsPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0,0,300,280)
                                             styleMask:NSWindowStyleMaskTitled|NSWindowStyleMaskClosable
                                               backing:NSBackingStoreBuffered defer:NO];
    _prefsPanel.title = @"Preferences";
    [_prefsPanel center];
    NSView *cv = _prefsPanel.contentView;

    // Font Family
    NSTextField *famLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 232, 100, 20)];
    famLabel.stringValue = @"Font Family:"; famLabel.editable = NO; famLabel.bordered = NO;
    famLabel.backgroundColor = [NSColor clearColor];
    [cv addSubview:famLabel];
    NSPopUpButton *famPop = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(120, 228, 160, 26)];
    [famPop addItemsWithTitles:@[@"Monospaced", @"Sans-Serif", @"Serif"]];
    [famPop selectItemWithTitle:[_fontFamily isEqualToString:@"sans"] ? @"Sans-Serif" :
                                 [_fontFamily isEqualToString:@"serif"] ? @"Serif" : @"Monospaced"];
    famPop.target = self; famPop.action = @selector(prefsFontFamilyChanged:);
    [cv addSubview:famPop];

    // Font Size
    NSTextField *szLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 192, 100, 20)];
    szLabel.stringValue = @"Font Size:"; szLabel.editable = NO; szLabel.bordered = NO;
    szLabel.backgroundColor = [NSColor clearColor];
    [cv addSubview:szLabel];
    NSTextField *szField = [[NSTextField alloc] initWithFrame:NSMakeRect(120, 190, 60, 24)];
    szField.doubleValue = _currentFontSize; szField.tag = 101;
    szField.target = self; szField.action = @selector(prefsFontSizeChanged:);
    [cv addSubview:szField];
    NSStepper *szStep = [[NSStepper alloc] initWithFrame:NSMakeRect(184, 190, 19, 24)];
    szStep.minValue = 8; szStep.maxValue = 72; szStep.increment = 1;
    szStep.doubleValue = _currentFontSize; szStep.tag = 102;
    szStep.target = self; szStep.action = @selector(prefsFontSizeChanged:);
    [cv addSubview:szStep];

    // Typewriter
    NSButton *twCheck = [[NSButton alloc] initWithFrame:NSMakeRect(20, 152, 260, 22)];
    [twCheck setButtonType:NSButtonTypeSwitch];
    twCheck.title = @"Typewriter Mode"; twCheck.state = _typewriterMode ? NSControlStateValueOn : NSControlStateValueOff;
    twCheck.target = self; twCheck.action = @selector(prefsTypewriterChanged:);
    [cv addSubview:twCheck];

    // Spell check
    NSButton *spCheck = [[NSButton alloc] initWithFrame:NSMakeRect(20, 120, 260, 22)];
    [spCheck setButtonType:NSButtonTypeSwitch];
    spCheck.title = @"Check Spelling While Typing";
    spCheck.state = _textView.continuousSpellCheckingEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    spCheck.target = self; spCheck.action = @selector(prefsSpellChanged:);
    [cv addSubview:spCheck];

    // Column Width
    NSTextField *colLabel = [[NSTextField alloc] initWithFrame:NSMakeRect(20, 88, 120, 20)];
    colLabel.stringValue = @"Column Width:"; colLabel.editable = NO; colLabel.bordered = NO;
    colLabel.backgroundColor = [NSColor clearColor];
    [cv addSubview:colLabel];
    NSTextField *colValue = [[NSTextField alloc] initWithFrame:NSMakeRect(210, 88, 70, 20)];
    colValue.stringValue = [NSString stringWithFormat:@"%.0f px", _columnWidth];
    colValue.editable = NO; colValue.bordered = NO; colValue.alignment = NSTextAlignmentRight;
    colValue.backgroundColor = [NSColor clearColor]; colValue.tag = 103;
    [cv addSubview:colValue];
    NSSlider *colSlider = [[NSSlider alloc] initWithFrame:NSMakeRect(20, 60, 260, 22)];
    colSlider.minValue = kColumnWidthMin; colSlider.maxValue = kColumnWidthMax;
    colSlider.doubleValue = _columnWidth; colSlider.tag = 104;
    colSlider.target = self; colSlider.action = @selector(prefsColumnWidthChanged:);
    [cv addSubview:colSlider];

    [_prefsPanel makeKeyAndOrderFront:nil];
}

- (IBAction)prefsFontFamilyChanged:(id)sender {
    NSPopUpButton *pop = (NSPopUpButton *)sender;
    NSString *title = pop.titleOfSelectedItem;
    if ([title isEqualToString:@"Sans-Serif"]) _fontFamily = @"sans";
    else if ([title isEqualToString:@"Serif"])  _fontFamily = @"serif";
    else                                         _fontFamily = @"mono";
    [self applyFont];
}

- (IBAction)prefsFontSizeChanged:(id)sender {
    NSView *cv = _prefsPanel.contentView;
    NSTextField *field = (NSTextField *)[cv viewWithTag:101];
    NSStepper  *step  = (NSStepper *)[cv viewWithTag:102];
    if ([sender isKindOfClass:[NSStepper class]])
        field.doubleValue = step.doubleValue;
    else
        step.doubleValue = field.doubleValue;
    _currentFontSize = MAX(8, MIN(72, field.doubleValue));
    [self applyFont];
}

- (IBAction)prefsTypewriterChanged:(id)sender {
    _typewriterMode = ([(NSButton *)sender state] == NSControlStateValueOn);
    [[NSUserDefaults standardUserDefaults] setBool:_typewriterMode forKey:kTypewriterModeKey];
}

- (IBAction)prefsSpellChanged:(id)sender {
    BOOL on = ([(NSButton *)sender state] == NSControlStateValueOn);
    _textView.continuousSpellCheckingEnabled = on;
    [[NSUserDefaults standardUserDefaults] setBool:on forKey:kSpellCheckKey];
}

- (IBAction)prefsColumnWidthChanged:(id)sender {
    _columnWidth = [(NSSlider *)sender doubleValue];
    [[NSUserDefaults standardUserDefaults] setDouble:_columnWidth forKey:kColumnWidthKey];
    NSTextField *valLabel = (NSTextField *)[_prefsPanel.contentView viewWithTag:103];
    valLabel.stringValue = [NSString stringWithFormat:@"%.0f px", _columnWidth];
    [self updateTextContainerInset];
}

// ── (DOCX conversion methods removed — now using NSAttributedString natively) ──

- (NSString *)attributedStringToMarkdown_unused:(NSAttributedString *)attrStr {
    NSMutableString *md  = [NSMutableString string];
    NSString        *str = attrStr.string;
    NSUInteger       len = str.length;
    NSUInteger       pos = 0;

    while (pos < len) {
        NSUInteger paraEnd, paraContentsEnd;
        [str getParagraphStart:NULL end:&paraEnd contentsEnd:&paraContentsEnd
                      forRange:NSMakeRange(pos, 0)];

        NSUInteger contentLen = paraContentsEnd - pos;
        if (contentLen == 0) {
            [md appendString:@"\n"];
            pos = paraEnd;
            continue;
        }

        // Sample font at paragraph start to detect heading level
        NSFont *paraFont = [attrStr attribute:NSFontAttributeName atIndex:pos effectiveRange:nil];
        CGFloat ptSize = paraFont ? paraFont.pointSize : 12.0;
        NSString *headPrefix = @"";
        if      (ptSize >= 22) headPrefix = @"# ";
        else if (ptSize >= 17) headPrefix = @"## ";
        else if (ptSize >= 14) headPrefix = @"### ";

        [md appendString:headPrefix];

        NSRange contentRange = NSMakeRange(pos, contentLen);
        [attrStr enumerateAttributesInRange:contentRange options:0
                                 usingBlock:^(NSDictionary *attrs, NSRange runRange, BOOL *stop) {
            (void)stop;
            NSFont *runFont = attrs[NSFontAttributeName];
            NSFontSymbolicTraits traits = runFont ? runFont.fontDescriptor.symbolicTraits : 0;
            BOOL bold   = (traits & NSFontBoldTrait)   != 0;
            BOOL italic = (traits & NSFontItalicTrait) != 0;
            NSString *text = [str substringWithRange:runRange];
            if (!text.length) return;
            if (headPrefix.length) {
                // Heading — don't re-wrap in bold markers
                [md appendString:text];
            } else if (bold && italic) {
                [md appendFormat:@"***%@***", text];
            } else if (bold) {
                [md appendFormat:@"**%@**", text];
            } else if (italic) {
                [md appendFormat:@"*%@*", text];
            } else {
                [md appendString:text];
            }
        }];

        [md appendString:@"\n"];
        pos = paraEnd;
    }

    return [md copy];
}

- (NSMutableAttributedString *)markdownToAttributedString_unused:(NSString *)markdown {
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    NSFont *bodyFont = [NSFont systemFontOfSize:12.0 weight:NSFontWeightRegular];

    NSArray<NSString *> *lines = [markdown componentsSeparatedByString:@"\n"];
    for (NSUInteger i = 0; i < lines.count; i++) {
        NSString *line = lines[i];

        // Detect heading
        NSUInteger h = 0;
        while (h < 6 && h < line.length && [line characterAtIndex:h] == '#') h++;

        NSMutableAttributedString *paraAS;
        BOOL isLast = (i == lines.count - 1);
        NSString *sep = isLast ? @"" : @"\n";

        if (h > 0 && h < line.length && [line characterAtIndex:h] == ' ') {
            static CGFloat sizes[] = {24, 20, 16, 14, 13, 12};
            CGFloat sz = sizes[MIN(h - 1, 5)];
            NSFont *headFont = [NSFont boldSystemFontOfSize:sz];
            NSString *text = [[line substringFromIndex:h + 1]
                stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            paraAS = [[NSMutableAttributedString alloc]
                initWithString:[text stringByAppendingString:sep]
                    attributes:@{NSFontAttributeName: headFont}];
        } else {
            // List item
            NSString *content = line;
            if ([line hasPrefix:@"- "] || [line hasPrefix:@"* "] || [line hasPrefix:@"+ "])
                content = [line substringFromIndex:2];
            paraAS = [self parseMarkdownInline_unused:[content stringByAppendingString:sep]
                                      baseFont:bodyFont];
        }
        [result appendAttributedString:paraAS];
    }
    return result;
}

- (NSMutableAttributedString *)parseMarkdownInline_unused:(NSString *)text baseFont:(NSFont *)base {
    NSMutableAttributedString *result = [[NSMutableAttributedString alloc] init];
    NSFontManager *fm = [NSFontManager sharedFontManager];
    NSFont *boldFont   = [fm convertFont:base toHaveTrait:NSBoldFontMask];
    NSFont *italicFont = [fm convertFont:base toHaveTrait:NSItalicFontMask];
    NSFont *bItalic    = [fm convertFont:boldFont toHaveTrait:NSItalicFontMask];

    NSUInteger pos = 0, len = text.length;

    while (pos < len) {
        unichar c = [text characterAtIndex:pos];
        if (c == '*') {
            NSUInteger stars = 0;
            while (pos + stars < len && [text characterAtIndex:pos + stars] == '*') stars++;

            if (stars >= 3) {
                NSRange closeRange = [text rangeOfString:@"***" options:0
                    range:NSMakeRange(pos + 3, len - pos - 3)];
                if (closeRange.location != NSNotFound) {
                    NSString *inner = [text substringWithRange:
                        NSMakeRange(pos + 3, closeRange.location - pos - 3)];
                    [result appendAttributedString:[self parseMarkdownInline_unused:inner baseFont:bItalic]];
                    pos = closeRange.location + 3;
                    continue;
                }
            } else if (stars == 2) {
                NSRange closeRange = [text rangeOfString:@"**" options:0
                    range:NSMakeRange(pos + 2, len - pos - 2)];
                if (closeRange.location != NSNotFound) {
                    NSString *inner = [text substringWithRange:
                        NSMakeRange(pos + 2, closeRange.location - pos - 2)];
                    [result appendAttributedString:[self parseMarkdownInline_unused:inner baseFont:boldFont]];
                    pos = closeRange.location + 2;
                    continue;
                }
            } else if (stars == 1) {
                NSUInteger search = pos + 1;
                NSRange closeRange = NSMakeRange(NSNotFound, 0);
                while (search < len) {
                    NSRange r = [text rangeOfString:@"*" options:0
                        range:NSMakeRange(search, len - search)];
                    if (r.location == NSNotFound) break;
                    BOOL isDouble = (r.location + 1 < len && [text characterAtIndex:r.location + 1] == '*');
                    if (!isDouble) { closeRange = r; break; }
                    search = r.location + 1;
                }
                if (closeRange.location != NSNotFound) {
                    NSString *inner = [text substringWithRange:
                        NSMakeRange(pos + 1, closeRange.location - pos - 1)];
                    [result appendAttributedString:[self parseMarkdownInline_unused:inner baseFont:italicFont]];
                    pos = closeRange.location + 1;
                    continue;
                }
            }
        }
        // Literal character
        NSString *ch = [text substringWithRange:NSMakeRange(pos, 1)];
        [result appendAttributedString:[[NSMutableAttributedString alloc]
            initWithString:ch attributes:@{NSFontAttributeName: base}]];
        pos++;
    }
    return result;
}

// ── Edit / Preview Toggle ─────────────────────────────────

- (IBAction)toggleEditPreview:(id)sender {
    _editMode = !_editMode;
    _scrollView.hidden     = !_editMode;
    _previewWebView.hidden =  _editMode;
    _previewMenuItem.title = _editMode ? @"Show Preview" : @"Show Editor";
    if (!_editMode) [self updatePreview];
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
    if (_editMode || [self isRichTextMode]) return;

    BOOL dark = [self isDarkMode];
    NSString *fg           = dark ? @"#D7D5CF" : @"#1A1A1A";
    NSString *bg           = dark ? @"#1A1A1A" : @"#FFFFFF";
    NSString *headingColor = dark ? @"#7FBBE0" : @"#2458A5";
    NSString *codeBg       = dark ? @"#242424" : @"#E8E6E3";
    NSString *codeFg       = dark ? @"#E8A857" : @"#A0522D";
    NSString *borderColor  = dark ? @"#333333" : @"#C8C6C3";

    NSString *body = [self markdownToHTML:_textView.string];

    NSString *html = [NSString stringWithFormat:
        @"<html><head><meta charset='utf-8'><style>"
        "body{font-family:-apple-system,sans-serif;font-size:%gpx;line-height:1.7;"
        "max-width:720px;margin:0 auto;padding:32px 24px;color:%@;background:%@;}"
        "h1,h2,h3,h4,h5,h6{font-weight:700;margin-top:1.4em;margin-bottom:.3em;color:%@;}"
        "h1{font-size:1.7em;}h2{font-size:1.3em;}h3{font-size:1.1em;}"
        "p{margin:.5em 0;}"
        "code{font-family:Menlo,Monaco,monospace;background:%@;color:%@;padding:1px 5px;font-size:.88em;border-radius:4px;}"
        "hr{border:none;border-top:1px solid %@;margin:1.2em 0;}"
        "del{opacity:.55;}"
        ".code-block{position:relative;border-radius:8px;margin:1em 0;overflow:hidden;}"
        ".code-pre{margin:0;padding:14px 16px;font-family:Menlo,Monaco,monospace;font-size:.88em;overflow-x:auto;white-space:pre-wrap;overflow-wrap:break-word;background:%@;color:%@;}"
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
        (double)_previewFontSize, fg, bg, headingColor,
        codeBg, codeFg,
        borderColor,
        codeBg, codeFg,
        body];

    [_previewWebView loadHTMLString:html baseURL:nil];
}

- (void)setPreviewFontSizeTo:(CGFloat)size {
    _previewFontSize = MIN(MAX(size, kPreviewFontSizeMin), kPreviewFontSizeMax);
    [[NSUserDefaults standardUserDefaults] setDouble:_previewFontSize forKey:kPreviewFontSizeKey];
    if (_editMode) return;
    NSString *js = [NSString stringWithFormat:@"document.body.style.fontSize='%gpx';",
                                              (double)_previewFontSize];
    [_previewWebView evaluateJavaScript:js completionHandler:nil];
}

- (IBAction)previewFontSizeUp:(id)sender    { [self setPreviewFontSizeTo:_previewFontSize + 1.0]; }
- (IBAction)previewFontSizeDown:(id)sender  { [self setPreviewFontSizeTo:_previewFontSize - 1.0]; }
- (IBAction)previewFontSizeReset:(id)sender { [self setPreviewFontSizeTo:kPreviewFontSizeDefault]; }

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

    NSMutableString *(^sub)(NSString *, NSString *) = ^(NSString *pat, NSString *tpl) {
        NSRegularExpression *rx = [NSRegularExpression
            regularExpressionWithPattern:pat options:0 error:nil];
        return [[rx stringByReplacingMatchesInString:s
                                             options:0
                                               range:NSMakeRange(0, s.length)
                                        withTemplate:tpl] mutableCopy];
    };

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

    for (NSUInteger i = 0; i < slots.count; i++) {
        NSString *key = [NSString stringWithFormat:@"\x02%lu\x03", (unsigned long)i];
        [s replaceOccurrencesOfString:key withString:slots[i]
                              options:0 range:NSMakeRange(0, s.length)];
    }

    return [s copy];
}

- (NSString *)markdownToHTML:(NSString *)rawMD {
    BOOL dark = [self isDarkMode];
    NSString *codeBg     = dark ? @"#242424" : @"#E8E6E3";
    NSString *codeFg     = dark ? @"#E8A857" : @"#A0522D";
    NSString *tableBdr   = dark ? @"#444444" : @"#C8C6C3";
    NSString *borderColor= dark ? @"#444444" : @"#C8C6C3";
    NSString *checkColor = dark ? @"#7FBBE0" : @"#2458A5";

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

        if ([line hasPrefix:@"```"] || [line hasPrefix:@"~~~"]) {
            flushPara(); closeLists();
            [out appendFormat:
                @"<div class='code-block'>"
                "<button class='copy-btn' onclick='copyCode(this)'>Copy</button>"
                "<pre class='code-pre' style='background:%@;color:%@;'>",
                codeBg, codeFg];
            inFence = YES;
            continue;
        }

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

        // Setext headers
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

        // Horizontal rule
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

        // GFM table
        if ([trimmed hasPrefix:@"|"] && i + 1 < n) {
            NSString *nextTrimmed = [[lines[i + 1] stringByTrimmingCharactersInSet:
                                      [NSCharacterSet whitespaceCharacterSet]]
                                     stringByReplacingOccurrencesOfString:@" " withString:@""];
            BOOL isSep = nextTrimmed.length > 0;
            for (NSUInteger k = 0; k < nextTrimmed.length && isSep; k++) {
                unichar c = [nextTrimmed characterAtIndex:k];
                if (c != '|' && c != '-' && c != ':') isSep = NO;
            }
            if (isSep) {
                flushPara(); closeLists();
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
                i += 2;
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
                i--;
                continue;
            }
        }

        // GFM task list
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

        // Unordered list
        if (line.length >= 2 &&
            ([line hasPrefix:@"- "] || [line hasPrefix:@"* "] || [line hasPrefix:@"+ "])) {
            flushPara();
            if (inOL) { inOL = NO; olCounter = 0; }
            [out appendFormat:@"<p style='margin:0 0 .15em 20px;'>&#x2013;&nbsp;%@</p>\n",
                [self applyInlineMarkdown:[line substringFromIndex:2]]];
            continue;
        }

        // Ordered list
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

        // Paragraph
        closeLists();
        if (para.length) [para appendString:@" "];
        [para appendString:line];
    }

    flushPara();
    if (inFence) [out appendString:@"</pre></div>\n"];
    return [out copy];
}

// ── WYSIWYM Markdown Formatting ───────────────────────────

- (void)applyWYSIWYMFormatting {
    if ([self isRichTextMode]) return;
    NSTextStorage *ts  = _textView.textStorage;
    NSString      *str = [ts.string copy];
    NSUInteger     len = str.length;
    if (!len) return;

    NSRange    cursorRange = _textView.selectedRange;
    NSUInteger cursorLoc   = (cursorRange.location != NSNotFound) ? cursorRange.location : 0;

    _isHighlighting = YES;
    [ts beginEditing];

    NSColor *baseFg     = [self iaTextColor];
    NSColor *bgColor    = [self iaBgColor];
    NSFont  *baseFont   = [self currentFont];
    NSColor *headColor  = [self iaHeadingColor];
    NSColor *codeColor  = [self iaCodeColor];
    NSColor *dimColor   = [NSColor tertiaryLabelColor];
    NSColor *quoteColor = [NSColor secondaryLabelColor];

    NSFontManager *fm      = [NSFontManager sharedFontManager];
    NSFont *boldFont       = [fm convertFont:baseFont toHaveTrait:NSBoldFontMask];
    NSFont *italicFont     = [fm convertFont:baseFont toHaveTrait:NSItalicFontMask];
    NSFont *boldItalicFont = [fm convertFont:boldFont toHaveTrait:NSItalicFontMask];
    NSFont *monoFont       = [NSFont monospacedSystemFontOfSize:_currentFontSize * 0.9
                                                         weight:NSFontWeightRegular];

    // Reset to base
    [ts addAttribute:NSFontAttributeName            value:baseFont range:NSMakeRange(0, len)];
    [ts addAttribute:NSForegroundColorAttributeName value:baseFg   range:NSMakeRange(0, len)];
    [ts removeAttribute:NSStrikethroughStyleAttributeName          range:NSMakeRange(0, len)];

    NSMutableIndexSet *fenceIdx      = [NSMutableIndexSet indexSet];
    NSMutableIndexSet *claimedInline = [NSMutableIndexSet indexSet];

    // ── Line-level pass (headings, fences, blockquotes, HRs) ────
    NSArray<NSString *> *lines = [str componentsSeparatedByString:@"\n"];
    NSUInteger lineStart = 0;
    BOOL       inFence   = NO;

    for (NSString *line in lines) {
        NSUInteger lineLen   = line.length;
        NSRange    lineRange = NSMakeRange(lineStart, lineLen);

        BOOL cursorOnLine = (cursorLoc >= lineStart && cursorLoc <= lineStart + lineLen);
        if (!cursorOnLine && cursorRange.length > 0)
            cursorOnLine = (NSIntersectionRange(cursorRange, lineRange).length > 0);

        if (inFence) {
            [fenceIdx addIndexesInRange:lineRange];
            if ([line hasPrefix:@"```"] || [line hasPrefix:@"~~~"]) {
                [ts addAttribute:NSForegroundColorAttributeName
                           value:cursorOnLine ? dimColor : bgColor
                           range:lineRange];
                inFence = NO;
            } else {
                [ts addAttribute:NSFontAttributeName            value:monoFont  range:lineRange];
                [ts addAttribute:NSForegroundColorAttributeName value:codeColor range:lineRange];
            }
            lineStart += lineLen + 1;
            continue;
        }

        if ([line hasPrefix:@"```"] || [line hasPrefix:@"~~~"]) {
            [fenceIdx addIndexesInRange:lineRange];
            [ts addAttribute:NSForegroundColorAttributeName
                       value:cursorOnLine ? dimColor : bgColor
                       range:lineRange];
            inFence = YES;
            lineStart += lineLen + 1;
            continue;
        }

        // ATX heading  #  ##  ###  …
        {
            NSUInteger h = 0;
            while (h < 6 && h < lineLen && [line characterAtIndex:h] == '#') h++;
            if (h > 0 && h < lineLen && [line characterAtIndex:h] == ' ') {
                static CGFloat kScale[] = {0, 1.75, 1.45, 1.2, 1.05, 1.0, 1.0};
                NSFont *hFont = [NSFont boldSystemFontOfSize:
                                    floor(_currentFontSize * kScale[MIN(h, 6)])];
                NSRange markerRange  = NSMakeRange(lineStart, h + 1);
                NSUInteger cLen      = lineLen > h + 1 ? lineLen - h - 1 : 0;
                NSRange contentRange = NSMakeRange(lineStart + h + 1, cLen);
                [ts addAttribute:NSFontAttributeName            value:hFont     range:lineRange];
                [ts addAttribute:NSForegroundColorAttributeName value:headColor range:contentRange];
                [ts addAttribute:NSForegroundColorAttributeName
                           value:cursorOnLine ? dimColor : bgColor
                           range:markerRange];
                lineStart += lineLen + 1;
                continue;
            }
        }

        // Blockquote  > …
        if (lineLen >= 2 && [line hasPrefix:@"> "]) {
            NSRange markerRange  = NSMakeRange(lineStart, 2);
            NSRange contentRange = NSMakeRange(lineStart + 2, lineLen - 2);
            [ts addAttribute:NSForegroundColorAttributeName value:quoteColor range:contentRange];
            [ts addAttribute:NSForegroundColorAttributeName
                       value:cursorOnLine ? dimColor : bgColor
                       range:markerRange];
            lineStart += lineLen + 1;
            continue;
        }

        // Horizontal rule  ---  ***  ___
        {
            NSString *t = [line stringByTrimmingCharactersInSet:
                           [NSCharacterSet whitespaceCharacterSet]];
            if (t.length >= 3) {
                unichar fc = [t characterAtIndex:0];
                if (fc == '-' || fc == '*' || fc == '_') {
                    BOOL isHR = YES;
                    for (NSUInteger j = 1; j < t.length && isHR; j++)
                        if ([t characterAtIndex:j] != fc) isHR = NO;
                    if (isHR) {
                        [ts addAttribute:NSForegroundColorAttributeName
                                   value:cursorOnLine ? dimColor : bgColor
                                   range:lineRange];
                        lineStart += lineLen + 1;
                        continue;
                    }
                }
            }
        }

        lineStart += lineLen + 1;
    }

    // ── Inline pass ──────────────────────────────────────────

    BOOL (^skip)(NSRange) = ^BOOL(NSRange r) {
        return [fenceIdx intersectsIndexesInRange:r] ||
               [claimedInline intersectsIndexesInRange:r];
    };

    void (^applyInline)(NSRange, NSUInteger, NSUInteger, NSFont *, NSArray *) =
        ^(NSRange full, NSUInteger openLen, NSUInteger closeLen,
          NSFont *font, NSArray *extraAttrs) {
        if (full.length < openLen + closeLen + 1) return;
        NSRange openR    = NSMakeRange(full.location, openLen);
        NSRange closeR   = NSMakeRange(NSMaxRange(full) - closeLen, closeLen);
        NSRange contentR = NSMakeRange(full.location + openLen,
                                       full.length - openLen - closeLen);
        BOOL active = (cursorLoc >= full.location && cursorLoc <= NSMaxRange(full));
        if (!active && cursorRange.length > 0)
            active = NSIntersectionRange(cursorRange, full).length > 0;
        if (font) {
            [ts addAttribute:NSFontAttributeName value:font range:contentR];
            [ts addAttribute:NSFontAttributeName value:font range:openR];
            [ts addAttribute:NSFontAttributeName value:font range:closeR];
        }
        for (NSUInteger k = 0; k + 1 < extraAttrs.count; k += 2)
            [ts addAttribute:extraAttrs[k] value:extraAttrs[k+1] range:contentR];
        NSColor *mc = active ? dimColor : bgColor;
        [ts addAttribute:NSForegroundColorAttributeName value:mc range:openR];
        [ts addAttribute:NSForegroundColorAttributeName value:mc range:closeR];
    };

    NSRegularExpression *r;

    // Inline code  `…`
    r = [NSRegularExpression regularExpressionWithPattern:@"`([^`\\n]+)`" options:0 error:nil];
    [r enumerateMatchesInString:str options:0 range:NSMakeRange(0, len)
                     usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
        (void)f; (void)stop;
        if (skip(m.range)) return;
        [claimedInline addIndexesInRange:m.range];
        applyInline(m.range, 1, 1, monoFont,
                    @[NSForegroundColorAttributeName, codeColor]);
    }];

    // Bold+italic  ***…***
    r = [NSRegularExpression regularExpressionWithPattern:@"\\*{3}(.+?)\\*{3}" options:0 error:nil];
    [r enumerateMatchesInString:str options:0 range:NSMakeRange(0, len)
                     usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
        (void)f; (void)stop;
        if (skip(m.range)) return;
        [claimedInline addIndexesInRange:m.range];
        applyInline(m.range, 3, 3, boldItalicFont, @[]);
    }];

    // Bold  **…**  or  __…__
    r = [NSRegularExpression regularExpressionWithPattern:@"\\*\\*(.+?)\\*\\*|__(.+?)__" options:0 error:nil];
    [r enumerateMatchesInString:str options:0 range:NSMakeRange(0, len)
                     usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
        (void)f; (void)stop;
        if (skip(m.range)) return;
        [claimedInline addIndexesInRange:m.range];
        applyInline(m.range, 2, 2, boldFont, @[]);
    }];

    // Italic  *…*  or  _…_
    r = [NSRegularExpression
         regularExpressionWithPattern:@"(?<!\\*)\\*([^\\*\\n]+)\\*(?!\\*)|(?<!_)_([^_\\n]+)_(?!_)"
                              options:0 error:nil];
    [r enumerateMatchesInString:str options:0 range:NSMakeRange(0, len)
                     usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
        (void)f; (void)stop;
        if (skip(m.range)) return;
        [claimedInline addIndexesInRange:m.range];
        applyInline(m.range, 1, 1, italicFont, @[]);
    }];

    // Strikethrough  ~~…~~
    r = [NSRegularExpression regularExpressionWithPattern:@"~~(.+?)~~" options:0 error:nil];
    [r enumerateMatchesInString:str options:0 range:NSMakeRange(0, len)
                     usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
        (void)f; (void)stop;
        if (skip(m.range)) return;
        applyInline(m.range, 2, 2, nil,
                    @[NSStrikethroughStyleAttributeName, @(NSUnderlineStyleSingle),
                      NSForegroundColorAttributeName, quoteColor]);
    }];

    // Links  [text](url)  and images  ![alt](url)
    r = [NSRegularExpression
         regularExpressionWithPattern:@"!?\\[([^\\]\\n]*)\\]\\(([^\\)\\n]*)\\)"
                              options:0 error:nil];
    [r enumerateMatchesInString:str options:0 range:NSMakeRange(0, len)
                     usingBlock:^(NSTextCheckingResult *m, NSMatchingFlags f, BOOL *stop) {
        (void)f; (void)stop;
        if ([fenceIdx intersectsIndexesInRange:m.range]) return;
        NSRange full      = m.range;
        NSRange textRange = [m rangeAtIndex:1];
        BOOL active = (cursorLoc >= full.location && cursorLoc <= NSMaxRange(full));
        if (!active && cursorRange.length > 0)
            active = NSIntersectionRange(cursorRange, full).length > 0;
        if (active) {
            [ts addAttribute:NSForegroundColorAttributeName value:headColor range:full];
        } else {
            [ts addAttribute:NSForegroundColorAttributeName value:bgColor range:full];
            if (textRange.location != NSNotFound && textRange.length > 0)
                [ts addAttribute:NSForegroundColorAttributeName value:headColor range:textRange];
        }
    }];

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
    // Save font prefs
    [[NSUserDefaults standardUserDefaults] setObject:_fontFamily forKey:kFontFamilyKey];
    [[NSUserDefaults standardUserDefaults] setDouble:_currentFontSize forKey:kFontSizeKey];

    NSFont *font = [self currentFont];
    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.lineSpacing = _currentLineSpacing;
    NSDictionary *attrs = @{
        NSFontAttributeName            : font,
        NSForegroundColorAttributeName : [self iaTextColor],
        NSParagraphStyleAttributeName  : para,
    };
    _textView.typingAttributes = attrs;
    _textView.font = font;
    [_rulerView setNeedsDisplay:YES];
    if ([self isRichTextMode]) return;  // don't flatten rich-text attributes
    NSRange all = NSMakeRange(0, _textView.textStorage.length);
    [_textView.textStorage setAttributes:attrs range:all];
    [self applyWYSIWYMFormatting];
}

- (IBAction)applyParagraphStyle:(id)sender {
    NSInteger level = [(NSMenuItem *)sender tag];  // 0 = Normal, 1-6 = H1-H6
    static CGFloat sizes[] = {0, 28, 22, 18, 14, 13, 12};
    NSRange sel = _textView.selectedRange;
    NSString *str = _textView.string;
    NSRange paraRange = [str paragraphRangeForRange:sel];
    NSFont *font = (level == 0)
        ? [self currentFont]
        : [NSFont boldSystemFontOfSize:sizes[level]];
    [_textView.textStorage addAttribute:NSFontAttributeName value:font range:paraRange];
    _isDirty = YES;
    [self updateTitle];
}

- (IBAction)showTextColorPicker:(id)sender {
    NSColorPanel *cp = [NSColorPanel sharedColorPanel];
    cp.color      = [self iaTextColor];
    cp.target     = self;
    cp.action     = @selector(colorPanelColorChanged:);
    cp.continuous = YES;
    [cp orderFront:nil];
}

- (void)colorPanelColorChanged:(id)sender {
    _customTextColor = [NSColorPanel sharedColorPanel].color;
    NSError *err = nil;
    NSData *data = [NSKeyedArchiver archivedDataWithRootObject:_customTextColor
                                         requiringSecureCoding:NO error:&err];
    if (data) [[NSUserDefaults standardUserDefaults] setObject:data forKey:kCustomTextColorKey];
    [self applyTheme];
    [self applyFont];
}

- (IBAction)resetTextColor:(id)sender {
    _customTextColor = nil;
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kCustomTextColorKey];
    [self applyTheme];
    [self applyFont];
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
    // Save line spacing pref
    [[NSUserDefaults standardUserDefaults] setDouble:_currentLineSpacing forKey:kLineSpacingKey];
    [self applyFont];
}

// ── View ──────────────────────────────────────────────────

- (IBAction)toggleLineNumbers:(id)sender {
    _scrollView.rulersVisible = !_scrollView.rulersVisible;
}

// ── NSWindowDelegate ──────────────────────────────────────

- (void)windowDidResize:(NSNotification *)note {
    [self updateTextContainerInset];
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
    NSString *fmt = _fileFormat ? _fileFormat.uppercaseString : @"TXT";
    _statusBar.stringValue = [NSString stringWithFormat:
        @"v%@  [%@]     Words: %lu     Chars: %lu     Ln %lu, Col %lu",
        ver, fmt, (unsigned long)words, (unsigned long)chars, (unsigned long)ln, (unsigned long)col];
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
