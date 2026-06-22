// ============================================================
//  Notepad — a minimal plain-text editor for macOS (arm64)
//  Build:  make   (see Makefile)
//  Deps:   Cocoa (system), clang++ / Apple LLVM
// ============================================================

#import <Cocoa/Cocoa.h>
#import <Foundation/Foundation.h>
#include <sys/stat.h>

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
        // Redraw whenever text changes
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

    // Background
    [[NSColor colorWithWhite:0.95 alpha:1.0] setFill];
    NSRectFill(self.bounds);

    // Separator line
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

        // Translate from text-view coords to ruler coords
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

        // Advance: find next line by scanning \n in char range
        NSRange charRange = [lm characterRangeForGlyphRange:lineGlyphRange
                                           actualGlyphRange:nil];
        NSUInteger nextCharIdx = NSMaxRange(charRange);

        if (nextCharIdx < len) {
            unichar ch = [str characterAtIndex:nextCharIdx - 1];
            if (ch == '\n') lineNumber++;
        } else {
            // Last line
        }

        glyphIdx = NSMaxRange(lineGlyphRange);

        // Count newlines we skipped (wrapped lines don't increment)
        if (glyphIdx < lm.numberOfGlyphs) {
            NSRange nextCharRange = [lm characterRangeForGlyphRange:
                                        NSMakeRange(glyphIdx, 1)
                                               actualGlyphRange:nil];
            NSUInteger prevEnd = NSMaxRange(charRange);
            NSUInteger nextStart = nextCharRange.location;
            // count newlines between prevEnd and nextStart
            for (NSUInteger i = prevEnd; i < nextStart && i < len; i++) {
                if ([str characterAtIndex:i] == '\n') lineNumber++;
            }
        }
    }

    // Handle empty document: draw line 1
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

    // Labels
    NSTextField *findLabel    = [self labelWithString:@"Find:"    frame:NSMakeRect(12, 96, 70, 20)];
    NSTextField *replaceLabel = [self labelWithString:@"Replace:" frame:NSMakeRect(12, 64, 70, 20)];
    [content addSubview:findLabel];
    [content addSubview:replaceLabel];

    // Find field
    _findField = [[NSTextField alloc] initWithFrame:NSMakeRect(88, 93, 316, 24)];
    _findField.delegate = self;
    [content addSubview:_findField];

    // Replace field
    _replaceField = [[NSTextField alloc] initWithFrame:NSMakeRect(88, 61, 316, 24)];
    [content addSubview:_replaceField];

    // Buttons
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
    // Reset search position when find text changes
    _lastFoundLocation = 0;
}

- (IBAction)findNext:(id)sender {
    NSString *needle = _findField.stringValue;
    if (needle.length == 0) return;

    NSString *haystack = _targetTextView.string;
    NSUInteger searchFrom = _lastFoundLocation;

    // If we had a previous selection that matches, advance past it
    NSRange sel = _targetTextView.selectedRange;
    if (sel.length > 0 && sel.location == _lastFoundLocation)
        searchFrom = NSMaxRange(sel);

    NSRange found = [haystack rangeOfString:needle
                                    options:NSCaseInsensitiveSearch
                                      range:NSMakeRange(searchFrom, haystack.length - searchFrom)];

    if (found.location == NSNotFound && searchFrom > 0) {
        // Wrap around
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
// MARK: - Application Delegate / Main Editor Window
// ============================================================

@interface AppDelegate : NSObject <NSApplicationDelegate, NSTextViewDelegate, NSWindowDelegate>
@property (nonatomic, strong) NSWindow              *window;
@property (nonatomic, strong) NSTextView            *textView;
@property (nonatomic, strong) NSScrollView          *scrollView;
@property (nonatomic, strong) LineNumberRulerView   *rulerView;
@property (nonatomic, strong) FindReplaceController *findReplace;
@property (nonatomic, copy)   NSString              *currentFilePath;
@property (nonatomic, assign) BOOL                   isDirty;
// Font state
@property (nonatomic, assign) CGFloat                currentFontSize;
@property (nonatomic, copy)   NSString              *fontFamily;  // @"mono", @"sans", @"serif"
@property (nonatomic, assign) CGFloat                currentLineSpacing;
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
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)app {
    return YES;
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
    if (!_isDirty) return NSTerminateNow;
    NSAlert *alert = [self unsavedChangesAlertWithAction:@"quit"];
    NSModalResponse r = [alert runModal];
    if (r == NSAlertFirstButtonReturn)  { [self saveDocument:nil]; return NSTerminateNow; }
    if (r == NSAlertSecondButtonReturn) { return NSTerminateNow; }
    return NSTerminateCancel;
}

// ── Window & Views ────────────────────────────────────────

- (void)buildWindow {
    NSRect frame = NSMakeRect(0, 0, 900, 700);
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

    // Scroll view
    _scrollView = [[NSScrollView alloc] initWithFrame:_window.contentView.bounds];
    _scrollView.autoresizingMask      = NSViewWidthSizable | NSViewHeightSizable;
    _scrollView.hasVerticalScroller   = YES;
    _scrollView.hasHorizontalScroller = NO;
    _scrollView.autohidesScrollers    = YES;

    // Text view
    NSSize contentSize = _scrollView.contentSize;
    NSTextContainer *tc = [[NSTextContainer alloc] initWithSize:
                             NSMakeSize(contentSize.width, CGFLOAT_MAX)];
    tc.widthTracksTextView = YES;

    NSLayoutManager *lm = [[NSLayoutManager alloc] init];
    NSTextStorage   *ts = [[NSTextStorage alloc] init];
    [ts addLayoutManager:lm];
    [lm addTextContainer:tc];

    _textView = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, contentSize.width, contentSize.height)
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

    // Line number ruler
    _rulerView = [[LineNumberRulerView alloc] initWithScrollView:_scrollView
                                                  clientTextView:_textView];
    _scrollView.verticalRulerView  = _rulerView;
    _scrollView.rulersVisible      = YES;

    [_window.contentView addSubview:_scrollView];

    // Apply initial font / typing attributes
    [self applyFont];

    // Find & Replace controller
    _findReplace = [[FindReplaceController alloc] initWithTargetTextView:_textView];
}

// ── Menu ──────────────────────────────────────────────────

- (void)buildMenu {
    NSMenu *main = [[NSMenu alloc] init];
    [NSApp setMainMenu:main];

    // App menu
    NSMenuItem *appItem = [main addItemWithTitle:@"" action:nil keyEquivalent:@""];
    NSMenu *appMenu = [[NSMenu alloc] init];
    [appMenu addItemWithTitle:@"About Notepad" action:@selector(orderFrontStandardAboutPanel:) keyEquivalent:@""];
    [appMenu addItem:[NSMenuItem separatorItem]];
    [appMenu addItemWithTitle:@"Quit Notepad" action:@selector(terminate:) keyEquivalent:@"q"];
    appItem.submenu = appMenu;

    // File menu
    NSMenuItem *fileItem = [main addItemWithTitle:@"File" action:nil keyEquivalent:@""];
    NSMenu *fileMenu = [[NSMenu alloc] initWithTitle:@"File"];
    [fileMenu addItemWithTitle:@"New"     action:@selector(newDocument:)    keyEquivalent:@"n"];
    [fileMenu addItemWithTitle:@"Open…"   action:@selector(openDocument:)   keyEquivalent:@"o"];
    [fileMenu addItem:[NSMenuItem separatorItem]];
    [fileMenu addItemWithTitle:@"Save"    action:@selector(saveDocument:)   keyEquivalent:@"s"];
    NSMenuItem *saveAs = [fileMenu addItemWithTitle:@"Save As…" action:@selector(saveDocumentAs:) keyEquivalent:@"s"];
    saveAs.keyEquivalentModifierMask = NSEventModifierFlagCommand | NSEventModifierFlagShift;
    fileItem.submenu = fileMenu;

    // Edit menu
    NSMenuItem *editItem = [main addItemWithTitle:@"Edit" action:nil keyEquivalent:@""];
    NSMenu *editMenu = [[NSMenu alloc] initWithTitle:@"Edit"];
    [editMenu addItemWithTitle:@"Undo"  action:@selector(undo:)  keyEquivalent:@"z"];
    [editMenu addItemWithTitle:@"Redo"  action:@selector(redo:)  keyEquivalent:@"Z"];
    [editMenu addItem:[NSMenuItem separatorItem]];
    [editMenu addItemWithTitle:@"Cut"   action:@selector(cut:)   keyEquivalent:@"x"];
    [editMenu addItemWithTitle:@"Copy"  action:@selector(copy:)  keyEquivalent:@"c"];
    [editMenu addItemWithTitle:@"Paste" action:@selector(paste:) keyEquivalent:@"v"];
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

    // -- Font family submenu
    NSMenuItem *familyItem = [formatMenu addItemWithTitle:@"Font" action:nil keyEquivalent:@""];
    NSMenu *familyMenu = [[NSMenu alloc] initWithTitle:@"Font"];
    NSMenuItem *monoItem  = [familyMenu addItemWithTitle:@"Monospaced"  action:@selector(setFontMono:)  keyEquivalent:@""];
    NSMenuItem *sansItem  = [familyMenu addItemWithTitle:@"Sans-Serif"  action:@selector(setFontSans:)  keyEquivalent:@""];
    NSMenuItem *serifItem = [familyMenu addItemWithTitle:@"Serif"       action:@selector(setFontSerif:) keyEquivalent:@""];
    for (NSMenuItem *it in @[monoItem, sansItem, serifItem]) it.target = self;
    familyItem.submenu = familyMenu;

    // -- Size submenu
    NSMenuItem *sizeItem = [formatMenu addItemWithTitle:@"Size" action:nil keyEquivalent:@""];
    NSMenu *sizeMenu = [[NSMenu alloc] initWithTitle:@"Size"];
    NSMenuItem *biggerItem  = [sizeMenu addItemWithTitle:@"Bigger"   action:@selector(fontSizeUp:)   keyEquivalent:@"+"];
    NSMenuItem *smallerItem = [sizeMenu addItemWithTitle:@"Smaller"  action:@selector(fontSizeDown:) keyEquivalent:@"-"];
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

    // -- Line spacing submenu
    [formatMenu addItem:[NSMenuItem separatorItem]];
    NSMenuItem *spacingItem = [formatMenu addItemWithTitle:@"Line Spacing" action:nil keyEquivalent:@""];
    NSMenu *spacingMenu = [[NSMenu alloc] initWithTitle:@"Line Spacing"];
    NSDictionary *spacings = @{@"Tight (1.0)": @0.0, @"Normal (1.2)": @3.0, @"Relaxed (1.5)": @7.0, @"Double (2.0)": @14.0};
    NSArray *spacingOrder  = @[@"Tight (1.0)", @"Normal (1.2)", @"Relaxed (1.5)", @"Double (2.0)"];
    for (NSString *label in spacingOrder) {
        NSMenuItem *it = [spacingMenu addItemWithTitle:label
                                               action:@selector(setLineSpacing:)
                                        keyEquivalent:@""];
        it.tag    = (NSInteger)([spacings[label] doubleValue] * 10);  // encode as tenths
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
}

- (IBAction)openDocument:(id)sender {
    if (_isDirty && ![self confirmDiscardWithAction:@"open another file"]) return;

    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.allowsMultipleSelection = NO;
    panel.canChooseDirectories    = NO;
    panel.allowedContentTypes     = @[];   // Any file

    if ([panel runModal] != NSModalResponseOK) return;

    NSString *path = panel.URL.path;

    static const long long kMaxFileSize = 100LL * 1024 * 1024; // 100 MB
    struct stat st;
    if (stat(path.fileSystemRepresentation, &st) == 0 && st.st_size > kMaxFileSize) {
        NSAlert *sizeAlert = [[NSAlert alloc] init];
        sizeAlert.messageText = @"File Too Large";
        sizeAlert.informativeText = [NSString stringWithFormat:
            @"This file is %lld MB. Opening very large files may use excessive memory. Continue?",
            st.st_size / (1024 * 1024)];
        [sizeAlert addButtonWithTitle:@"Cancel"];
        [sizeAlert addButtonWithTitle:@"Open Anyway"];
        if ([sizeAlert runModal] == NSAlertFirstButtonReturn) return;
    }

    NSError  *err  = nil;
    NSString *text = [NSString stringWithContentsOfFile:path
                                               encoding:NSUTF8StringEncoding
                                                  error:&err];
    if (err) {
        // Try latin-1 fallback
        text = [NSString stringWithContentsOfFile:path
                                         encoding:NSISOLatin1StringEncoding
                                            error:&err];
    }
    if (err || !text) {
        [self showError:[NSString stringWithFormat:@"Could not open file:\n%@", err.localizedDescription]];
        return;
    }

    [_textView.textStorage replaceCharactersInRange:NSMakeRange(0, _textView.string.length)
                                         withString:text];
    [_textView.undoManager removeAllActions];
    _currentFilePath = path;
    _isDirty = NO;
    [self updateTitle];
}

- (IBAction)saveDocument:(id)sender {
    if (_currentFilePath) {
        [self writeToPath:_currentFilePath];
    } else {
        [self saveDocumentAs:sender];
    }
}

- (IBAction)saveDocumentAs:(id)sender {
    NSSavePanel *panel = [NSSavePanel savePanel];
    panel.nameFieldStringValue = _currentFilePath
        ? _currentFilePath.lastPathComponent
        : @"Untitled.txt";

    if ([panel runModal] != NSModalResponseOK) return;
    _currentFilePath = panel.URL.path;
    [self writeToPath:_currentFilePath];
}

- (void)writeToPath:(NSString *)path {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSDictionary *origAttrs = [fm attributesOfItemAtPath:path error:nil];

    NSError *err = nil;
    BOOL ok = [_textView.string writeToFile:path
                                 atomically:YES
                                   encoding:NSUTF8StringEncoding
                                      error:&err];
    if (!ok) {
        [self showError:[NSString stringWithFormat:@"Could not save:\n%@", err.localizedDescription]];
        return;
    }

    if (origAttrs) {
        NSMutableDictionary *restore = [NSMutableDictionary dictionary];
        NSNumber *perms = origAttrs[NSFilePosixPermissions];
        if (perms) restore[NSFilePosixPermissions] = perms;
        NSString *owner = origAttrs[NSFileOwnerAccountName];
        if (owner) restore[NSFileOwnerAccountName] = owner;
        NSString *group = origAttrs[NSFileGroupOwnerAccountName];
        if (group) restore[NSFileGroupOwnerAccountName] = group;
        if (restore.count > 0)
            [fm setAttributes:restore ofItemAtPath:path error:nil];
    }

    _isDirty = NO;
    [self updateTitle];
}

- (IBAction)showFindReplace:(id)sender {
    [_findReplace showPanel];
}

// ── Font helpers ──────────────────────────────────────────

- (NSFont *)currentFont {
    if ([_fontFamily isEqualToString:@"sans"])
        return [NSFont systemFontOfSize:_currentFontSize weight:NSFontWeightRegular];
    if ([_fontFamily isEqualToString:@"serif"])
        return [NSFont fontWithName:@"Georgia" size:_currentFontSize]
            ?: [NSFont userFontOfSize:_currentFontSize];
    // mono (default)
    return [NSFont monospacedSystemFontOfSize:_currentFontSize weight:NSFontWeightRegular];
}

- (void)applyFont {
    NSFont *font = [self currentFont];
    // Apply to entire text storage preserving content
    NSMutableParagraphStyle *para = [[NSMutableParagraphStyle alloc] init];
    para.lineSpacing = _currentLineSpacing;
    NSDictionary *attrs = @{
        NSFontAttributeName            : font,
        NSForegroundColorAttributeName : [NSColor textColor],
        NSParagraphStyleAttributeName  : para,
    };
    NSRange all = NSMakeRange(0, _textView.textStorage.length);
    [_textView.textStorage setAttributes:attrs range:all];
    // Also set as typing attributes so new text matches
    _textView.typingAttributes = attrs;
    // Keep the text view's font property in sync (used by ruler height calc)
    _textView.font = font;
    [_rulerView setNeedsDisplay:YES];
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
    // tag was stored as tenths
    _currentLineSpacing = [(NSMenuItem *)sender tag] / 10.0;
    [self applyFont];
}

// ── View ──────────────────────────────────────────────────

- (IBAction)toggleLineNumbers:(id)sender {
    _scrollView.rulersVisible = !_scrollView.rulersVisible;
}

// ── NSWindowDelegate ──────────────────────────────────────

- (BOOL)windowShouldClose:(NSWindow *)sender {
    if (!_isDirty) return YES;
    NSAlert *alert = [self unsavedChangesAlertWithAction:@"close"];
    NSModalResponse r = [alert runModal];
    if (r == NSAlertFirstButtonReturn)  { [self saveDocument:nil]; return YES; }
    if (r == NSAlertSecondButtonReturn) { return YES; }
    return NO;
}

// ── Helpers ───────────────────────────────────────────────

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

        if (@available(macOS 14.0, *)) {
            [app activate];
        } else {
            [app activateIgnoringOtherApps:YES];
        }
        [app run];
    }
    return 0;
}
