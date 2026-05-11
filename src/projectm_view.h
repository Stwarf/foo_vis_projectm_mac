#pragma once

#import "stdafx.h"

#include "projectm_audio_bridge.h"
#include <projectM-4/projectM.h>

@interface ProjectMOpenGLView : NSOpenGLView
- (void)loadPresetPath:(NSString*)path smooth:(BOOL)smooth;
- (void)setTextureDirectory:(NSString*)path;
@end

@interface ProjectMViewController : NSViewController
@property(nonatomic, readonly) ProjectMOpenGLView* projectMView;
- (void)add_audio_chunk:(const audio_chunk&)chunk;
@end
