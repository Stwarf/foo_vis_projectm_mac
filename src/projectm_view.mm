#import "projectm_view.h"

#include <algorithm>
#include <filesystem>
#include <cmath>
#include <memory>
#include <mutex>
#include <random>
#include <vector>

static NSString* const ProjectMPresetDirectoryKey = @"foo_vis_projectm_mac.presetDirectory";
static NSString* const ProjectMTextureDirectoryKey = @"foo_vis_projectm_mac.textureDirectory";
static NSString* const ProjectMShuffleKey = @"foo_vis_projectm_mac.shuffle";
static NSString* const ProjectMAutoRotateKey = @"foo_vis_projectm_mac.autoRotate";
static NSString* const ProjectMRotationIntervalKey = @"foo_vis_projectm_mac.rotationInterval";
static NSString* const ProjectMQualityKey = @"foo_vis_projectm_mac.quality";
static NSString* const ProjectMStartAtStartupKey = @"foo_vis_projectm_mac.startAtStartup";

@interface ProjectMViewController (ProjectMPrivate)
- (void)visualizerRenderTick;
- (void)closeFullscreen;
- (void)onPreviousPreset:(id)sender;
- (void)onNextPreset:(id)sender;
- (void)onToggleShuffle:(id)sender;
- (void)onToggleAutoRotate:(id)sender;
- (void)onToggleEnabled:(id)sender;
- (void)onFullscreen:(id)sender;
- (void)onFullscreenMouseActivity;
- (BOOL)handleProjectMKeyEvent:(NSEvent*)event;
- (void)showContextMenuForEvent:(NSEvent*)event view:(NSView*)view;
- (void)syncRuntimeState;
- (void)onMenuToggleShuffle:(id)sender;
- (void)onMenuToggleAutoRotate:(id)sender;
- (void)onMenuToggleEnabled:(id)sender;
- (void)onStartupModeMenuItem:(id)sender;
- (void)onQualityMenuItem:(id)sender;
- (void)onIntervalMenuItem:(id)sender;
- (void)restoreVisualizerFromFullscreen;
- (void)hideFullscreenCursor;
- (void)restoreFullscreenCursor;
@end

@interface ProjectMFullscreenWindow : NSWindow
@end

@implementation ProjectMFullscreenWindow
- (BOOL)canBecomeKeyWindow {
    return YES;
}

- (BOOL)canBecomeMainWindow {
    return YES;
}
@end

@interface ProjectMFullscreenContentView : NSView
@property(nonatomic, weak) ProjectMViewController* controller;
@end

@implementation ProjectMFullscreenContentView
- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)keyDown:(NSEvent*)event {
    if (![self.controller handleProjectMKeyEvent:event]) {
        [super keyDown:event];
    }
}

- (void)mouseDown:(NSEvent*)event {
    [self.window makeFirstResponder:self];
    [self.controller onFullscreenMouseActivity];
    if (event.clickCount == 2) {
        [self.controller onFullscreen:self];
        return;
    }
    [super mouseDown:event];
}

- (void)rightMouseDown:(NSEvent*)event {
    [self.window makeFirstResponder:self];
    [self.controller onFullscreenMouseActivity];
    [self.controller showContextMenuForEvent:event view:self];
}

- (void)mouseMoved:(NSEvent*)event {
    (void)event;
    [self.controller onFullscreenMouseActivity];
}
@end

@interface ProjectMOpenGLView ()
@property(nonatomic) CVDisplayLinkRef displayLink;
@property(nonatomic) projectm_handle projectM;
@property(nonatomic) BOOL projectMReady;
@property(nonatomic) BOOL visualizerEnabled;
@property(nonatomic) NSInteger qualityLevel;
@property(nonatomic, copy) NSString* pendingPresetPath;
@property(nonatomic, copy) NSString* pendingTextureDirectory;
@property(nonatomic, weak) ProjectMViewController* controller;
- (void)setProjectMQualityLevel:(NSInteger)qualityLevel;
- (void)setVisualizerEnabled:(BOOL)enabled;
- (void)createProjectMIfNeeded;
- (void)destroyProjectM;
- (void)applyQualitySettings;
@end

class ProjectMAudioSinkAdapter : public projectm_audio_sink {
public:
    explicit ProjectMAudioSinkAdapter(ProjectMViewController* controller) : m_controller(controller) {}

    void add_audio_chunk(const audio_chunk& chunk) override {
        ProjectMViewController* controller = m_controller;
        if (controller != nil) {
            [controller add_audio_chunk:chunk];
        }
    }

    void detach() {
        m_controller = nil;
    }

private:
    __unsafe_unretained ProjectMViewController* m_controller = nil;
};

static CVReturn ProjectMDisplayLinkCallback(CVDisplayLinkRef,
                                            const CVTimeStamp*,
                                            const CVTimeStamp*,
                                            CVOptionFlags,
                                            CVOptionFlags*,
                                            void* context) {
    ProjectMOpenGLView* view = (__bridge ProjectMOpenGLView*)context;
    dispatch_async(dispatch_get_main_queue(), ^{
        if (view.visualizerEnabled) {
            [view.controller visualizerRenderTick];
            [view setNeedsDisplay:YES];
        }
    });
    return kCVReturnSuccess;
}

@implementation ProjectMOpenGLView {
    std::mutex _audioMutex;
    std::vector<float> _pendingSamples;
}

- (BOOL)acceptsFirstResponder {
    return YES;
}

- (void)keyDown:(NSEvent*)event {
    if (![self.controller handleProjectMKeyEvent:event]) {
        [super keyDown:event];
    }
}

- (void)rightMouseDown:(NSEvent*)event {
    [self.window makeFirstResponder:self];
    [self.controller onFullscreenMouseActivity];
    [self.controller showContextMenuForEvent:event view:self];
}

- (void)mouseDown:(NSEvent*)event {
    [self.window makeFirstResponder:self];
    [self.controller onFullscreenMouseActivity];
    if (event.clickCount == 2) {
        [self.controller onFullscreen:self];
        return;
    }
    [super mouseDown:event];
}

- (void)mouseMoved:(NSEvent*)event {
    (void)event;
    [self.controller onFullscreenMouseActivity];
}

- (instancetype)initWithFrame:(NSRect)frameRect {
    NSOpenGLPixelFormatAttribute attrs[] = {
        NSOpenGLPFAOpenGLProfile, NSOpenGLProfileVersion3_2Core,
        NSOpenGLPFAColorSize, 24,
        NSOpenGLPFAAlphaSize, 8,
        NSOpenGLPFADoubleBuffer,
        NSOpenGLPFAAccelerated,
        0
    };
    NSOpenGLPixelFormat* pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attrs];
    self = [super initWithFrame:frameRect pixelFormat:pixelFormat];
    return self;
}

- (void)prepareOpenGL {
    [super prepareOpenGL];
    [[self openGLContext] makeCurrentContext];

    GLint swapInterval = 1;
    [[self openGLContext] setValues:&swapInterval forParameter:NSOpenGLContextParameterSwapInterval];

    if (self.visualizerEnabled) {
        [self createProjectMIfNeeded];
    }

    CVDisplayLinkCreateWithActiveCGDisplays(&_displayLink);
    if (_displayLink != nullptr) {
        CVDisplayLinkSetOutputCallback(_displayLink, ProjectMDisplayLinkCallback, (__bridge void*)self);
        if (self.visualizerEnabled) {
            CVDisplayLinkStart(_displayLink);
        }
    }
}

- (void)reshape {
    [super reshape];
    [[self openGLContext] makeCurrentContext];
    NSRect bounds = [self convertRectToBacking:self.bounds];
    glViewport(0, 0, bounds.size.width, bounds.size.height);
    [self applyQualitySettings];
}

- (void)setProjectMQualityLevel:(NSInteger)qualityLevel {
    _qualityLevel = MAX(0, MIN(3, qualityLevel));
    if (self.projectM != nullptr) {
        [[self openGLContext] makeCurrentContext];
        [self applyQualitySettings];
    }
}

- (void)setVisualizerEnabled:(BOOL)enabled {
    _visualizerEnabled = enabled;
    if (enabled) {
        [self createProjectMIfNeeded];
    }
    if (_displayLink != nullptr) {
        if (enabled && !CVDisplayLinkIsRunning(_displayLink)) {
            CVDisplayLinkStart(_displayLink);
        } else if (!enabled && CVDisplayLinkIsRunning(_displayLink)) {
            CVDisplayLinkStop(_displayLink);
        }
    }
    if (!enabled) {
        [self destroyProjectM];
    }
    [self setNeedsDisplay:YES];
}

- (void)createProjectMIfNeeded {
    if (self.projectM != nullptr) {
        return;
    }

    [[self openGLContext] makeCurrentContext];
    self.projectM = projectm_create();
    if (self.projectM == nullptr) {
        self.projectMReady = NO;
        return;
    }

    [self applyQualitySettings];
    projectm_set_aspect_correction(self.projectM, true);
    projectm_set_preset_duration(self.projectM, 30.0);
    projectm_set_soft_cut_duration(self.projectM, 5.0);
    projectm_set_hard_cut_enabled(self.projectM, true);
    projectm_set_hard_cut_duration(self.projectM, 12.0);
    if (self.pendingTextureDirectory.length > 0) {
        [self setTextureDirectory:self.pendingTextureDirectory];
    }
    projectm_load_preset_file(self.projectM, "idle://", false);
    if (self.pendingPresetPath.length > 0) {
        [self loadPresetPath:self.pendingPresetPath smooth:NO];
    }
    self.projectMReady = YES;
}

- (void)destroyProjectM {
    {
        std::lock_guard<std::mutex> lock(_audioMutex);
        _pendingSamples.clear();
        _pendingSamples.shrink_to_fit();
    }

    if (self.projectM != nullptr) {
        [[self openGLContext] makeCurrentContext];
        projectm_destroy(self.projectM);
        self.projectM = nullptr;
    }
    self.projectMReady = NO;
    [[self openGLContext] clearDrawable];
    [NSOpenGLContext clearCurrentContext];
}

- (void)applyQualitySettings {
    if (self.projectM == nullptr) {
        return;
    }

    NSRect bounds = [self convertRectToBacking:self.bounds];
    size_t meshWidth = 64;
    size_t meshHeight = 48;

    switch (self.qualityLevel) {
        case 0:
            meshWidth = 24;
            meshHeight = 18;
            break;
        case 1:
            meshWidth = 40;
            meshHeight = 30;
            break;
        case 3:
            meshWidth = 96;
            meshHeight = 72;
            break;
        case 2:
        default:
            meshWidth = 64;
            meshHeight = 48;
            break;
    }

    const double width = MAX(1.0, bounds.size.width);
    const double height = MAX(1.0, bounds.size.height);
    projectm_set_window_size(self.projectM, width, height);
    projectm_set_mesh_size(self.projectM, meshWidth, meshHeight);
}

- (void)drawRect:(NSRect)dirtyRect {
    (void)dirtyRect;
    [[self openGLContext] makeCurrentContext];

    if (!self.visualizerEnabled) {
        glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
    } else if (self.projectMReady) {
        NSRect bounds = [self convertRectToBacking:self.bounds];
        glViewport(0, 0, bounds.size.width, bounds.size.height);
        glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);

        std::vector<float> samples;
        {
            std::lock_guard<std::mutex> lock(_audioMutex);
            samples.swap(_pendingSamples);
        }
        if (!samples.empty()) {
            unsigned int frames = static_cast<unsigned int>(samples.size() / 2);
            projectm_pcm_add_float(self.projectM, samples.data(), frames, PROJECTM_STEREO);
        }

        projectm_opengl_render_frame(self.projectM);
    } else {
        glClearColor(0.03f, 0.03f, 0.035f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
    }

    [[self openGLContext] flushBuffer];
}

- (void)addStereoSamples:(const float*)samples count:(size_t)sampleCount {
    std::lock_guard<std::mutex> lock(_audioMutex);
    _pendingSamples.insert(_pendingSamples.end(), samples, samples + sampleCount);

    const size_t maxBufferedSamples = 48000 * 2;
    if (_pendingSamples.size() > maxBufferedSamples) {
        _pendingSamples.erase(_pendingSamples.begin(), _pendingSamples.end() - maxBufferedSamples);
    }
}

- (void)loadPresetPath:(NSString*)path smooth:(BOOL)smooth {
    if (path.length == 0) {
        return;
    }
    self.pendingPresetPath = path;
    if (self.projectM != nullptr) {
        [[self openGLContext] makeCurrentContext];
        projectm_load_preset_file(self.projectM, path.fileSystemRepresentation, smooth);
    }
}

- (void)setTextureDirectory:(NSString*)path {
    self.pendingTextureDirectory = path;
    if (self.projectM != nullptr && path.length > 0) {
        [[self openGLContext] makeCurrentContext];
        const char* texturePath = path.fileSystemRepresentation;
        projectm_set_texture_search_paths(self.projectM, &texturePath, 1);
    }
}

- (void)dealloc {
    if (_displayLink != nullptr) {
        CVDisplayLinkStop(_displayLink);
        CVDisplayLinkRelease(_displayLink);
        _displayLink = nullptr;
    }
    if (_projectM != nullptr) {
        projectm_destroy(_projectM);
        _projectM = nullptr;
    }
}

@end

@implementation ProjectMViewController {
    std::unique_ptr<ProjectMAudioSinkAdapter> _audioSink;
    ProjectMOpenGLView* _projectMView;
    NSView* _visualizerContainer;
    NSArray<NSLayoutConstraint*>* _visualizerConstraints;
    NSMutableArray<NSString*>* _presets;
    NSInteger _presetIndex;
    BOOL _shuffle;
    BOOL _autoRotate;
    BOOL _enabled;
    BOOL _startAtStartup;
    NSInteger _qualityLevel;
    NSTimeInterval _lastPresetSwitch;
    NSTimer* _rotationTimer;
    NSButton* _previousButton;
    NSButton* _nextButton;
    NSButton* _choosePresetsButton;
    NSButton* _chooseTexturesButton;
    NSButton* _enabledButton;
    NSButton* _shuffleButton;
    NSButton* _autoRotateButton;
    NSButton* _fullscreenButton;
    NSPopUpButton* _qualityPopup;
    NSPopUpButton* _presetPopup;
    NSTextField* _intervalField;
    NSTextField* _statusLabel;
    NSWindow* _fullscreenWindow;
    NSApplicationPresentationOptions _previousPresentationOptions;
    NSTimer* _cursorHideTimer;
    BOOL _fullscreenCursorHidden;
}

- (void)loadView {
    _presets = [NSMutableArray array];
    _presetIndex = NSNotFound;
    _shuffle = [[NSUserDefaults standardUserDefaults] boolForKey:ProjectMShuffleKey];
    _autoRotate = [[NSUserDefaults standardUserDefaults] objectForKey:ProjectMAutoRotateKey] == nil ? YES : [[NSUserDefaults standardUserDefaults] boolForKey:ProjectMAutoRotateKey];
    _startAtStartup = [[NSUserDefaults standardUserDefaults] boolForKey:ProjectMStartAtStartupKey];
    _enabled = _startAtStartup;
    _qualityLevel = [[NSUserDefaults standardUserDefaults] objectForKey:ProjectMQualityKey] == nil ? 2 : [[NSUserDefaults standardUserDefaults] integerForKey:ProjectMQualityKey];
    _qualityLevel = MAX(0, MIN(3, _qualityLevel));
    _lastPresetSwitch = [NSDate timeIntervalSinceReferenceDate];

    NSView* root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 760, 430)];
    root.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    NSView* controls = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 760, 36)];
    controls.translatesAutoresizingMaskIntoConstraints = NO;
    controls.wantsLayer = YES;
    controls.layer.masksToBounds = YES;
    _visualizerContainer = [[NSView alloc] initWithFrame:NSMakeRect(0, 36, 760, 394)];
    _visualizerContainer.translatesAutoresizingMaskIntoConstraints = NO;
    ProjectMOpenGLView* glView = [[ProjectMOpenGLView alloc] initWithFrame:NSMakeRect(0, 36, 760, 394)];
    _projectMView = glView;
    glView.controller = self;
    [glView setVisualizerEnabled:_enabled];
    [glView setProjectMQualityLevel:_qualityLevel];
    glView.translatesAutoresizingMaskIntoConstraints = NO;

    _previousButton = [self buttonWithTitle:@"Prev" action:@selector(onPreviousPreset:)];
    _nextButton = [self buttonWithTitle:@"Next" action:@selector(onNextPreset:)];
    _choosePresetsButton = [self buttonWithTitle:@"Presets" action:@selector(onChoosePresetFolder:)];
    _chooseTexturesButton = [self buttonWithTitle:@"Textures" action:@selector(onChooseTextureFolder:)];
    _enabledButton = [self buttonWithTitle:@"On" action:@selector(onToggleEnabled:)];
    _shuffleButton = [self buttonWithTitle:@"Shuffle" action:@selector(onToggleShuffle:)];
    _autoRotateButton = [self buttonWithTitle:@"Auto" action:@selector(onToggleAutoRotate:)];
    _fullscreenButton = [self buttonWithTitle:@"Full" action:@selector(onFullscreen:)];
    _enabledButton.buttonType = NSButtonTypeSwitch;
    _enabledButton.state = _enabled ? NSControlStateValueOn : NSControlStateValueOff;
    _shuffleButton.buttonType = NSButtonTypeSwitch;
    _shuffleButton.state = _shuffle ? NSControlStateValueOn : NSControlStateValueOff;
    _autoRotateButton.buttonType = NSButtonTypeSwitch;
    _autoRotateButton.state = _autoRotate ? NSControlStateValueOn : NSControlStateValueOff;
    _presetPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    _presetPopup.target = self;
    _presetPopup.action = @selector(onPresetPopup:);
    _presetPopup.translatesAutoresizingMaskIntoConstraints = NO;
    [_presetPopup setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    _qualityPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [_qualityPopup addItemsWithTitles:@[@"Low", @"Med", @"High", @"Ultra"]];
    [_qualityPopup selectItemAtIndex:_qualityLevel];
    _qualityPopup.target = self;
    _qualityPopup.action = @selector(onQualityChanged:);
    _qualityPopup.translatesAutoresizingMaskIntoConstraints = NO;
    _intervalField = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _intervalField.placeholderString = @"30";
    _intervalField.stringValue = [NSString stringWithFormat:@"%ld", (long)[self rotationInterval]];
    _intervalField.alignment = NSTextAlignmentRight;
    _intervalField.translatesAutoresizingMaskIntoConstraints = NO;
    _intervalField.target = self;
    _intervalField.action = @selector(onIntervalChanged:);
    _intervalField.enabled = _autoRotate;
    _statusLabel = [[NSTextField alloc] initWithFrame:NSZeroRect];
    _statusLabel.editable = NO;
    _statusLabel.bezeled = NO;
    _statusLabel.drawsBackground = NO;
    _statusLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    _statusLabel.font = [NSFont systemFontOfSize:11.0];
    _statusLabel.stringValue = @"No presets loaded";
    _statusLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [_statusLabel setContentCompressionResistancePriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    NSArray<NSView*>* controlViews = @[
        _previousButton, _nextButton, _presetPopup, _statusLabel,
        _choosePresetsButton, _chooseTexturesButton, _enabledButton, _shuffleButton, _autoRotateButton, _intervalField, _qualityPopup, _fullscreenButton
    ];
    for (NSView* view in controlViews) {
        [controls addSubview:view];
    }
    [_visualizerContainer addSubview:glView];
    [root addSubview:controls];
    [root addSubview:_visualizerContainer];

    NSDictionary* views = NSDictionaryOfVariableBindings(controls, _visualizerContainer);
    [root addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[controls]|" options:0 metrics:nil views:views]];
    [root addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_visualizerContainer]|" options:0 metrics:nil views:views]];
    [root addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[controls(36)][_visualizerContainer]|" options:0 metrics:nil views:views]];

    NSDictionary* visualizerViews = NSDictionaryOfVariableBindings(glView);
    _visualizerConstraints = @[
        [NSLayoutConstraint constraintWithItem:glView attribute:NSLayoutAttributeLeading relatedBy:NSLayoutRelationEqual toItem:_visualizerContainer attribute:NSLayoutAttributeLeading multiplier:1.0 constant:0.0],
        [NSLayoutConstraint constraintWithItem:glView attribute:NSLayoutAttributeTrailing relatedBy:NSLayoutRelationEqual toItem:_visualizerContainer attribute:NSLayoutAttributeTrailing multiplier:1.0 constant:0.0],
        [NSLayoutConstraint constraintWithItem:glView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:_visualizerContainer attribute:NSLayoutAttributeTop multiplier:1.0 constant:0.0],
        [NSLayoutConstraint constraintWithItem:glView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:_visualizerContainer attribute:NSLayoutAttributeBottom multiplier:1.0 constant:0.0]
    ];
    (void)visualizerViews;
    [NSLayoutConstraint activateConstraints:_visualizerConstraints];

    NSDictionary* controlMetrics = @{@"gap": @4};
    NSDictionary* controlBindings = NSDictionaryOfVariableBindings(_previousButton, _nextButton, _presetPopup, _statusLabel, _choosePresetsButton, _chooseTexturesButton, _enabledButton, _shuffleButton, _autoRotateButton, _intervalField, _qualityPopup, _fullscreenButton);
    [controls addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-gap-[_previousButton(48)]-gap-[_nextButton(48)]-gap-[_presetPopup(110)]-gap-[_statusLabel(50)]-gap-[_choosePresetsButton(64)]-gap-[_chooseTexturesButton(66)]-gap-[_enabledButton(42)]-gap-[_shuffleButton(62)]-gap-[_autoRotateButton(50)]-gap-[_intervalField(36)]-gap-[_qualityPopup(62)]-gap-[_fullscreenButton(44)]" options:NSLayoutFormatAlignAllCenterY metrics:controlMetrics views:controlBindings]];
    for (NSView* view in controlViews) {
        [controls addConstraint:[NSLayoutConstraint constraintWithItem:view attribute:NSLayoutAttributeCenterY relatedBy:NSLayoutRelationEqual toItem:controls attribute:NSLayoutAttributeCenterY multiplier:1.0 constant:0.0]];
    }

    self.view = root;
    [self loadSavedDirectories];
}

- (ProjectMOpenGLView*)projectMView {
    return _projectMView;
}

- (void)viewDidAppear {
    [super viewDidAppear];
    if (!_audioSink) {
        _audioSink = std::make_unique<ProjectMAudioSinkAdapter>(self);
    }
    [self syncRuntimeState];
    [self startRotationTimer];
}

- (void)viewWillDisappear {
    [super viewWillDisappear];
    if (_audioSink) {
        projectm_audio_bridge::instance().remove_sink(_audioSink.get());
    }
    [_rotationTimer invalidate];
    _rotationTimer = nil;
}

- (void)dealloc {
    if (_audioSink) {
        projectm_audio_bridge::instance().remove_sink(_audioSink.get());
        _audioSink->detach();
    }
}

- (NSButton*)buttonWithTitle:(NSString*)title action:(SEL)action {
    NSButton* button = [NSButton buttonWithTitle:title target:self action:action];
    button.translatesAutoresizingMaskIntoConstraints = NO;
    button.bezelStyle = NSBezelStyleRounded;
    return button;
}

- (NSInteger)rotationInterval {
    NSInteger fieldValue = _intervalField != nil ? _intervalField.integerValue : 0;
    if (fieldValue > 0) {
        return MAX(5, fieldValue);
    }

    NSInteger value = [[NSUserDefaults standardUserDefaults] integerForKey:ProjectMRotationIntervalKey];
    return value > 0 ? value : 30;
}

- (void)loadSavedDirectories {
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSString* textureDirectory = [defaults stringForKey:ProjectMTextureDirectoryKey];
    if (textureDirectory.length > 0) {
        [self.projectMView setTextureDirectory:textureDirectory];
    }
    NSString* presetDirectory = [defaults stringForKey:ProjectMPresetDirectoryKey];
    if (presetDirectory.length > 0) {
        [self loadPresetDirectory:presetDirectory];
    } else {
        [self refreshPresetPopup];
    }
}

- (void)loadPresetDirectory:(NSString*)directory {
    [_presets removeAllObjects];
    std::error_code ec;
    std::filesystem::path root(directory.fileSystemRepresentation);
    if (!std::filesystem::exists(root, ec)) {
        [self refreshPresetPopup];
        return;
    }
    for (const auto& entry : std::filesystem::recursive_directory_iterator(root, ec)) {
        if (ec) {
            break;
        }
        if (!entry.is_regular_file(ec)) {
            continue;
        }
        std::filesystem::path path = entry.path();
        std::string extension = path.extension().string();
        std::transform(extension.begin(), extension.end(), extension.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
        if (extension == ".milk" || extension == ".prjm") {
            [_presets addObject:[NSString stringWithUTF8String:path.string().c_str()]];
        }
    }
    [_presets sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    _presetIndex = _presets.count > 0 ? 0 : NSNotFound;
    [self refreshPresetPopup];
    if (_presetIndex != NSNotFound) {
        [self loadPresetAtIndex:_presetIndex smooth:NO];
    }
}

- (void)refreshPresetPopup {
    [_presetPopup removeAllItems];
    if (_presets.count == 0) {
        [_presetPopup addItemWithTitle:@"No presets loaded"];
        _presetPopup.enabled = NO;
        _statusLabel.stringValue = @"No presets loaded";
        return;
    }
    _presetPopup.enabled = YES;
    for (NSString* path in _presets) {
        [_presetPopup addItemWithTitle:path.lastPathComponent.stringByDeletingPathExtension];
    }
    if (_presetIndex != NSNotFound && _presetIndex < (NSInteger)_presets.count) {
        [_presetPopup selectItemAtIndex:_presetIndex];
    }
}

- (void)loadPresetAtIndex:(NSInteger)index smooth:(BOOL)smooth {
    if (index < 0 || index >= (NSInteger)_presets.count) {
        return;
    }
    _presetIndex = index;
    [_presetPopup selectItemAtIndex:index];
    _statusLabel.stringValue = _presets[index].lastPathComponent;
    _lastPresetSwitch = [NSDate timeIntervalSinceReferenceDate];
    [self.projectMView loadPresetPath:_presets[index] smooth:smooth];
}

- (void)advancePreset:(NSInteger)direction smooth:(BOOL)smooth {
    if (_presets.count == 0) {
        return;
    }
    NSInteger nextIndex = 0;
    if (_shuffle && _presets.count > 1) {
        nextIndex = arc4random_uniform((uint32_t)_presets.count);
        if (nextIndex == _presetIndex) {
            nextIndex = (nextIndex + 1) % (NSInteger)_presets.count;
        }
    } else if (_presetIndex == NSNotFound) {
        nextIndex = 0;
    } else {
        nextIndex = (_presetIndex + direction + (NSInteger)_presets.count) % (NSInteger)_presets.count;
    }
    [self loadPresetAtIndex:nextIndex smooth:smooth];
}

- (void)startRotationTimer {
    [_rotationTimer invalidate];
    _rotationTimer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(onRotationTimer:) userInfo:nil repeats:YES];
}

- (void)visualizerRenderTick {
    if (!_enabled || !_autoRotate || _presets.count == 0) {
        return;
    }
    NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
    if (now - _lastPresetSwitch >= [self rotationInterval]) {
        [self advancePreset:1 smooth:YES];
    }
}

- (void)onRotationTimer:(NSTimer*)timer {
    (void)timer;
    [self visualizerRenderTick];
}

- (void)onPreviousPreset:(id)sender {
    (void)sender;
    if (!_enabled) {
        _enabledButton.state = NSControlStateValueOn;
        [self onToggleEnabled:self];
    }
    [self advancePreset:-1 smooth:NO];
}

- (void)onNextPreset:(id)sender {
    (void)sender;
    if (!_enabled) {
        _enabledButton.state = NSControlStateValueOn;
        [self onToggleEnabled:self];
    }
    [self advancePreset:1 smooth:NO];
}

- (void)onPresetPopup:(id)sender {
    (void)sender;
    [self loadPresetAtIndex:_presetPopup.indexOfSelectedItem smooth:NO];
}

- (void)syncRuntimeState {
    [self.projectMView setVisualizerEnabled:_enabled];
    if (_enabled && _audioSink) {
        projectm_audio_bridge::instance().add_sink(_audioSink.get());
        projectm_audio_bridge::instance().start();
    } else if (_audioSink) {
        projectm_audio_bridge::instance().remove_sink(_audioSink.get());
    }
}

- (void)onToggleEnabled:(id)sender {
    (void)sender;
    _enabled = _enabledButton.state == NSControlStateValueOn;
    [self syncRuntimeState];
}

- (void)onToggleShuffle:(id)sender {
    (void)sender;
    _shuffle = _shuffleButton.state == NSControlStateValueOn;
    [[NSUserDefaults standardUserDefaults] setBool:_shuffle forKey:ProjectMShuffleKey];
}

- (void)onToggleAutoRotate:(id)sender {
    (void)sender;
    _autoRotate = _autoRotateButton.state == NSControlStateValueOn;
    _intervalField.enabled = _autoRotate;
    _lastPresetSwitch = [NSDate timeIntervalSinceReferenceDate];
    [[NSUserDefaults standardUserDefaults] setBool:_autoRotate forKey:ProjectMAutoRotateKey];
}

- (void)onIntervalChanged:(id)sender {
    (void)sender;
    NSInteger value = MAX(5, _intervalField.integerValue);
    _intervalField.stringValue = [NSString stringWithFormat:@"%ld", (long)value];
    [[NSUserDefaults standardUserDefaults] setInteger:value forKey:ProjectMRotationIntervalKey];
}

- (void)onQualityChanged:(id)sender {
    (void)sender;
    _qualityLevel = _qualityPopup.indexOfSelectedItem;
    [[NSUserDefaults standardUserDefaults] setInteger:_qualityLevel forKey:ProjectMQualityKey];
    [self.projectMView setProjectMQualityLevel:_qualityLevel];
}

- (void)onFullscreen:(id)sender {
    (void)sender;
    if (_fullscreenWindow != nil) {
        [self closeFullscreen];
        return;
    }

    [NSLayoutConstraint deactivateConstraints:_visualizerConstraints];
    [_projectMView removeFromSuperview];
    _projectMView.translatesAutoresizingMaskIntoConstraints = YES;

    NSScreen* screen = self.view.window.screen ?: NSScreen.mainScreen;
    ProjectMFullscreenContentView* contentView = [[ProjectMFullscreenContentView alloc] initWithFrame:screen.frame];
    contentView.controller = self;
    contentView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    contentView.wantsLayer = YES;
    contentView.layer.backgroundColor = NSColor.blackColor.CGColor;

    _projectMView.frame = contentView.bounds;
    _projectMView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [contentView addSubview:_projectMView];

    ProjectMFullscreenWindow* window = [[ProjectMFullscreenWindow alloc] initWithContentRect:screen.frame
                                                                                   styleMask:NSWindowStyleMaskBorderless
                                                                                     backing:NSBackingStoreBuffered
                                                                                       defer:NO
                                                                                      screen:screen];
    window.level = NSScreenSaverWindowLevel;
    window.collectionBehavior = NSWindowCollectionBehaviorCanJoinAllSpaces |
                                NSWindowCollectionBehaviorFullScreenAuxiliary |
                                NSWindowCollectionBehaviorStationary |
                                NSWindowCollectionBehaviorIgnoresCycle;
    window.contentView = contentView;
    window.acceptsMouseMovedEvents = YES;
    window.releasedWhenClosed = NO;
    _fullscreenWindow = window;

    [[NSNotificationCenter defaultCenter] addObserverForName:NSWindowWillCloseNotification
                                                      object:window
                                                       queue:nil
                                                  usingBlock:^(NSNotification*) {
        [self restoreVisualizerFromFullscreen];
    }];
    _previousPresentationOptions = NSApp.presentationOptions;
    NSApp.presentationOptions = NSApplicationPresentationHideDock | NSApplicationPresentationHideMenuBar;
    [window setFrame:screen.frame display:YES];
    [window makeKeyAndOrderFront:nil];
    [window makeFirstResponder:contentView];
    [window orderFrontRegardless];
    [self onFullscreenMouseActivity];
}

- (void)onFullscreenMouseActivity {
    if (_fullscreenWindow == nil) {
        return;
    }
    if (_fullscreenCursorHidden) {
        [NSCursor unhide];
        _fullscreenCursorHidden = NO;
    }
    [_cursorHideTimer invalidate];
    _cursorHideTimer = [NSTimer scheduledTimerWithTimeInterval:2.0 target:self selector:@selector(hideFullscreenCursor) userInfo:nil repeats:NO];
}

- (void)hideFullscreenCursor {
    [_cursorHideTimer invalidate];
    _cursorHideTimer = nil;
    if (_fullscreenWindow != nil && !_fullscreenCursorHidden) {
        [NSCursor hide];
        _fullscreenCursorHidden = YES;
    }
}

- (BOOL)handleProjectMKeyEvent:(NSEvent*)event {
    NSString* characters = event.charactersIgnoringModifiers.lowercaseString;
    if (event.keyCode == 53 || [characters isEqualToString:@"f"]) {
        [self onFullscreen:self];
        return YES;
    }
    if (event.keyCode == 124 || [characters isEqualToString:@"n"]) {
        [self onNextPreset:self];
        return YES;
    }
    if (event.keyCode == 123 || [characters isEqualToString:@"p"]) {
        [self onPreviousPreset:self];
        return YES;
    }
    if ([characters isEqualToString:@"s"]) {
        [self onToggleShuffle:self];
        return YES;
    }
    if ([characters isEqualToString:@"a"]) {
        _autoRotateButton.state = _autoRotate ? NSControlStateValueOff : NSControlStateValueOn;
        [self onToggleAutoRotate:self];
        return YES;
    }
    if ([characters isEqualToString:@"q"]) {
        NSInteger nextQuality = (_qualityLevel + 1) % 4;
        [_qualityPopup selectItemAtIndex:nextQuality];
        [self onQualityChanged:self];
        return YES;
    }
    if ([characters isEqualToString:@"v"]) {
        _enabledButton.state = _enabled ? NSControlStateValueOff : NSControlStateValueOn;
        [self onToggleEnabled:self];
        return YES;
    }
    return NO;
}

- (NSMenuItem*)menuItemWithTitle:(NSString*)title action:(SEL)action key:(NSString*)key {
    NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
    item.target = self;
    return item;
}

- (void)showContextMenuForEvent:(NSEvent*)event view:(NSView*)view {
    NSMenu* menu = [[NSMenu alloc] initWithTitle:@"ProjectM"];

    NSMenuItem* previousItem = [self menuItemWithTitle:@"Previous Preset" action:@selector(onPreviousPreset:) key:@""];
    previousItem.enabled = _presets.count > 0;
    [menu addItem:previousItem];

    NSMenuItem* nextItem = [self menuItemWithTitle:@"Next Preset" action:@selector(onNextPreset:) key:@""];
    nextItem.enabled = _presets.count > 0;
    [menu addItem:nextItem];

    [menu addItem:[NSMenuItem separatorItem]];

    NSMenuItem* enabledItem = [self menuItemWithTitle:@"Enabled" action:@selector(onMenuToggleEnabled:) key:@""];
    enabledItem.state = _enabled ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:enabledItem];

    NSMenuItem* shuffleItem = [self menuItemWithTitle:@"Shuffle" action:@selector(onMenuToggleShuffle:) key:@""];
    shuffleItem.state = _shuffle ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:shuffleItem];

    NSMenuItem* autoItem = [self menuItemWithTitle:@"Auto Rotate" action:@selector(onMenuToggleAutoRotate:) key:@""];
    autoItem.state = _autoRotate ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:autoItem];

    NSMenu* startupMenu = [[NSMenu alloc] initWithTitle:@"Startup"];
    NSMenuItem* manualItem = [self menuItemWithTitle:@"Manual" action:@selector(onStartupModeMenuItem:) key:@""];
    manualItem.tag = 0;
    manualItem.state = _startAtStartup ? NSControlStateValueOff : NSControlStateValueOn;
    [startupMenu addItem:manualItem];
    NSMenuItem* startupItem = [self menuItemWithTitle:@"Start at Startup" action:@selector(onStartupModeMenuItem:) key:@""];
    startupItem.tag = 1;
    startupItem.state = _startAtStartup ? NSControlStateValueOn : NSControlStateValueOff;
    [startupMenu addItem:startupItem];
    NSMenuItem* startupRoot = [[NSMenuItem alloc] initWithTitle:@"Startup Behavior" action:nil keyEquivalent:@""];
    startupRoot.submenu = startupMenu;
    [menu addItem:startupRoot];

    NSMenu* intervalMenu = [[NSMenu alloc] initWithTitle:@"Interval"];
    for (NSNumber* value in @[@5, @10, @30, @60]) {
        NSString* title = [NSString stringWithFormat:@"%@ seconds", value];
        NSMenuItem* item = [self menuItemWithTitle:title action:@selector(onIntervalMenuItem:) key:@""];
        item.tag = value.integerValue;
        item.state = [self rotationInterval] == value.integerValue ? NSControlStateValueOn : NSControlStateValueOff;
        [intervalMenu addItem:item];
    }
    NSMenuItem* intervalRoot = [[NSMenuItem alloc] initWithTitle:@"Interval" action:nil keyEquivalent:@""];
    intervalRoot.submenu = intervalMenu;
    [menu addItem:intervalRoot];

    NSMenu* qualityMenu = [[NSMenu alloc] initWithTitle:@"Quality"];
    NSArray<NSString*>* qualityTitles = @[@"Low", @"Medium", @"High", @"Ultra"];
    for (NSInteger index = 0; index < (NSInteger)qualityTitles.count; ++index) {
        NSMenuItem* item = [self menuItemWithTitle:qualityTitles[index] action:@selector(onQualityMenuItem:) key:@""];
        item.tag = index;
        item.state = _qualityLevel == index ? NSControlStateValueOn : NSControlStateValueOff;
        [qualityMenu addItem:item];
    }
    NSMenuItem* qualityRoot = [[NSMenuItem alloc] initWithTitle:@"Quality" action:nil keyEquivalent:@""];
    qualityRoot.submenu = qualityMenu;
    [menu addItem:qualityRoot];

    [menu addItem:[NSMenuItem separatorItem]];
    [menu addItem:[self menuItemWithTitle:@"Choose Preset Folder..." action:@selector(onChoosePresetFolder:) key:@""]];
    [menu addItem:[self menuItemWithTitle:@"Choose Texture Folder..." action:@selector(onChooseTextureFolder:) key:@""]];

    [menu addItem:[NSMenuItem separatorItem]];
    NSString* fullscreenTitle = _fullscreenWindow == nil ? @"Enter Fullscreen" : @"Exit Fullscreen";
    [menu addItem:[self menuItemWithTitle:fullscreenTitle action:@selector(onFullscreen:) key:@""]];

    [NSMenu popUpContextMenu:menu withEvent:event forView:view];
}

- (void)onMenuToggleShuffle:(id)sender {
    (void)sender;
    _shuffleButton.state = _shuffle ? NSControlStateValueOff : NSControlStateValueOn;
    [self onToggleShuffle:self];
}

- (void)onMenuToggleEnabled:(id)sender {
    (void)sender;
    _enabledButton.state = _enabled ? NSControlStateValueOff : NSControlStateValueOn;
    [self onToggleEnabled:self];
}

- (void)onStartupModeMenuItem:(id)sender {
    NSMenuItem* item = (NSMenuItem*)sender;
    _startAtStartup = item.tag == 1;
    [[NSUserDefaults standardUserDefaults] setBool:_startAtStartup forKey:ProjectMStartAtStartupKey];
}

- (void)onMenuToggleAutoRotate:(id)sender {
    (void)sender;
    _autoRotateButton.state = _autoRotate ? NSControlStateValueOff : NSControlStateValueOn;
    [self onToggleAutoRotate:self];
}

- (void)onQualityMenuItem:(id)sender {
    NSMenuItem* item = (NSMenuItem*)sender;
    [_qualityPopup selectItemAtIndex:item.tag];
    [self onQualityChanged:self];
}

- (void)onIntervalMenuItem:(id)sender {
    NSMenuItem* item = (NSMenuItem*)sender;
    _intervalField.stringValue = [NSString stringWithFormat:@"%ld", (long)item.tag];
    [self onIntervalChanged:self];
}

- (void)restoreVisualizerFromFullscreen {
    [self restoreFullscreenCursor];
    if (_projectMView.superview == _visualizerContainer) {
        _fullscreenWindow = nil;
        return;
    }

    [_projectMView removeFromSuperview];
    _projectMView.translatesAutoresizingMaskIntoConstraints = NO;
    _projectMView.autoresizingMask = NSViewNotSizable;
    [_visualizerContainer addSubview:_projectMView];
    [NSLayoutConstraint activateConstraints:_visualizerConstraints];
    NSApp.presentationOptions = _previousPresentationOptions;
    _fullscreenWindow = nil;
}

- (void)restoreFullscreenCursor {
    [_cursorHideTimer invalidate];
    _cursorHideTimer = nil;
    if (_fullscreenCursorHidden) {
        [NSCursor unhide];
        _fullscreenCursorHidden = NO;
    }
}

- (void)closeFullscreen {
    NSWindow* window = _fullscreenWindow;
    if (window == nil) {
        return;
    }
    _fullscreenWindow = nil;
    [window close];
    [self restoreVisualizerFromFullscreen];
}

- (void)onChoosePresetFolder:(id)sender {
    (void)sender;
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.prompt = @"Use Presets";
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL != nil) {
            NSString* path = panel.URL.path;
            [[NSUserDefaults standardUserDefaults] setObject:path forKey:ProjectMPresetDirectoryKey];
            [self loadPresetDirectory:path];
        }
    }];
}

- (void)onChooseTextureFolder:(id)sender {
    (void)sender;
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.allowsMultipleSelection = NO;
    panel.prompt = @"Use Textures";
    [panel beginSheetModalForWindow:self.view.window completionHandler:^(NSModalResponse result) {
        if (result == NSModalResponseOK && panel.URL != nil) {
            NSString* path = panel.URL.path;
            [[NSUserDefaults standardUserDefaults] setObject:path forKey:ProjectMTextureDirectoryKey];
            [self.projectMView setTextureDirectory:path];
        }
    }];
}

- (void)add_audio_chunk:(const audio_chunk&)chunk {
    const t_size channels = chunk.get_channels();
    const t_size sampleCount = chunk.get_sample_count();
    const audio_sample* input = chunk.get_data();
    if (channels == 0 || sampleCount == 0 || input == nullptr) {
        return;
    }

    std::vector<float> stereo;
    stereo.reserve(sampleCount * 2);
    for (t_size frame = 0; frame < sampleCount; ++frame) {
        const audio_sample left = input[frame * channels];
        const audio_sample right = channels > 1 ? input[frame * channels + 1] : left;
        stereo.push_back(static_cast<float>(std::clamp(left, -1.0, 1.0)));
        stereo.push_back(static_cast<float>(std::clamp(right, -1.0, 1.0)));
    }

    [self.projectMView addStereoSamples:stereo.data() count:stereo.size()];
}

@end
