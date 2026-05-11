#import "stdafx.h"

static NSString* const ProjectMEnabledKey = @"foo_vis_projectm_mac.enabled";
static NSString* const ProjectMStartAtStartupKey = @"foo_vis_projectm_mac.startAtStartup";

@interface ProjectMPreferencesViewController : NSViewController
@end

@implementation ProjectMPreferencesViewController {
    NSButton* _startAtStartupButton;
    NSButton* _enabledButton;
}

- (void)loadView {
    NSView* root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 420, 150)];
    root.translatesAutoresizingMaskIntoConstraints = NO;

    NSTextField* title = [NSTextField labelWithString:@"projectM Visualisation"];
    title.font = [NSFont boldSystemFontOfSize:14.0];
    title.translatesAutoresizingMaskIntoConstraints = NO;

    _startAtStartupButton = [NSButton checkboxWithTitle:@"Start visualizer automatically when foobar2000 starts" target:self action:@selector(onStartAtStartup:)];
    _startAtStartupButton.translatesAutoresizingMaskIntoConstraints = NO;
    _startAtStartupButton.state = [[NSUserDefaults standardUserDefaults] boolForKey:ProjectMStartAtStartupKey] ? NSControlStateValueOn : NSControlStateValueOff;

    _enabledButton = [NSButton checkboxWithTitle:@"Default to enabled when automatic startup is on" target:self action:@selector(onEnabled:)];
    _enabledButton.translatesAutoresizingMaskIntoConstraints = NO;
    _enabledButton.state = [[NSUserDefaults standardUserDefaults] objectForKey:ProjectMEnabledKey] == nil || [[NSUserDefaults standardUserDefaults] boolForKey:ProjectMEnabledKey] ? NSControlStateValueOn : NSControlStateValueOff;

    NSTextField* note = [NSTextField labelWithString:@"Manual startup keeps the component idle until you turn it on from the toolbar or right-click menu."];
    note.font = [NSFont systemFontOfSize:11.0];
    note.textColor = NSColor.secondaryLabelColor;
    note.lineBreakMode = NSLineBreakByWordWrapping;
    note.maximumNumberOfLines = 0;
    note.translatesAutoresizingMaskIntoConstraints = NO;

    [root addSubview:title];
    [root addSubview:_startAtStartupButton];
    [root addSubview:_enabledButton];
    [root addSubview:note];

    NSDictionary* views = NSDictionaryOfVariableBindings(title, _startAtStartupButton, _enabledButton, note);
    [root addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-20-[title]-20-|" options:0 metrics:nil views:views]];
    [root addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-20-[_startAtStartupButton]-20-|" options:0 metrics:nil views:views]];
    [root addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-20-[_enabledButton]-20-|" options:0 metrics:nil views:views]];
    [root addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-20-[note]-20-|" options:0 metrics:nil views:views]];
    [root addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|-20-[title]-16-[_startAtStartupButton]-8-[_enabledButton]-14-[note]" options:0 metrics:nil views:views]];

    self.view = root;
}

- (void)onStartAtStartup:(id)sender {
    (void)sender;
    [[NSUserDefaults standardUserDefaults] setBool:_startAtStartupButton.state == NSControlStateValueOn forKey:ProjectMStartAtStartupKey];
}

- (void)onEnabled:(id)sender {
    (void)sender;
    [[NSUserDefaults standardUserDefaults] setBool:_enabledButton.state == NSControlStateValueOn forKey:ProjectMEnabledKey];
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
