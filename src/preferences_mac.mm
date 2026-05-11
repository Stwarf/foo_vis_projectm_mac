#import "stdafx.h"

static NSString* const ProjectMStartAtStartupKey = @"foo_vis_projectm_mac.startAtStartup";

@interface ProjectMPreferencesViewController : NSViewController
@end

@implementation ProjectMPreferencesViewController {
    NSButton* _startAtStartupButton;
}

- (void)loadView {
    NSView* root = [[NSView alloc] initWithFrame:NSZeroRect];
    root.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

    NSTextField* title = [NSTextField labelWithString:@"projectM Visualisation"];
    title.font = [NSFont boldSystemFontOfSize:14.0];
    title.translatesAutoresizingMaskIntoConstraints = NO;

    _startAtStartupButton = [NSButton checkboxWithTitle:@"Start visualizer automatically when foobar2000 starts" target:self action:@selector(onStartAtStartup:)];
    _startAtStartupButton.translatesAutoresizingMaskIntoConstraints = NO;
    _startAtStartupButton.state = [[NSUserDefaults standardUserDefaults] boolForKey:ProjectMStartAtStartupKey] ? NSControlStateValueOn : NSControlStateValueOff;

    NSTextField* note = [NSTextField labelWithString:@"When this is off, projectM stays idle until you turn it on from the toolbar, right-click menu, or V shortcut."];
    note.font = [NSFont systemFontOfSize:11.0];
    note.textColor = NSColor.secondaryLabelColor;
    note.lineBreakMode = NSLineBreakByWordWrapping;
    note.maximumNumberOfLines = 0;
    note.translatesAutoresizingMaskIntoConstraints = NO;

    [root addSubview:title];
    [root addSubview:_startAtStartupButton];
    [root addSubview:note];

    [NSLayoutConstraint activateConstraints:@[
        [title.leadingAnchor constraintEqualToAnchor:root.leadingAnchor constant:24.0],
        [title.trailingAnchor constraintLessThanOrEqualToAnchor:root.trailingAnchor constant:-24.0],
        [title.topAnchor constraintEqualToAnchor:root.topAnchor constant:24.0],

        [_startAtStartupButton.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [_startAtStartupButton.trailingAnchor constraintLessThanOrEqualToAnchor:root.trailingAnchor constant:-24.0],
        [_startAtStartupButton.topAnchor constraintEqualToAnchor:title.bottomAnchor constant:18.0],

        [note.leadingAnchor constraintEqualToAnchor:title.leadingAnchor],
        [note.trailingAnchor constraintLessThanOrEqualToAnchor:root.trailingAnchor constant:-24.0],
        [note.topAnchor constraintEqualToAnchor:_startAtStartupButton.bottomAnchor constant:16.0],
        [note.widthAnchor constraintLessThanOrEqualToConstant:620.0]
    ]];

    self.view = root;
}

- (void)onStartAtStartup:(id)sender {
    (void)sender;
    [[NSUserDefaults standardUserDefaults] setBool:_startAtStartupButton.state == NSControlStateValueOn forKey:ProjectMStartAtStartupKey];
}

@end

namespace {
class projectm_preferences_page : public preferences_page {
public:
    service_ptr instantiate() override {
        return fb2k::wrapNSObject([ProjectMPreferencesViewController new]);
    }

    const char* get_name() override {
        return "projectM Visualisation";
    }

    GUID get_guid() override {
        return {0x01fd81c5, 0xf0ef, 0x459a, {0xb3, 0x4a, 0x64, 0x79, 0x2a, 0xb0, 0x5f, 0x1d}};
    }

    GUID get_parent_guid() override {
        return preferences_page::guid_visualisations;
    }
};

FB2K_SERVICE_FACTORY(projectm_preferences_page);
}
