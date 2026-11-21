// macOS media integration. Public APIs only; no global keyboard hooks.
#import <AppKit/AppKit.h>
#import <MediaPlayer/MediaPlayer.h>
#import <AudioToolbox/AudioToolbox.h>
#include "gdextension_interface.h"
#include <vector>
#include <atomic>

static GDExtensionInterfaceGetProcAddress api;
static GDExtensionClassLibraryPtr library;
static void *class_name;
static NSMutableArray *commands;
static NSMutableArray *remote_targets;
static NSMenuItem *settings_item;
static std::atomic_bool active(false);
#define PROC(type, name) ((type)api(name))

struct Name {
    void *data;
    Name(const char *s) { PROC(GDExtensionInterfaceStringNameNewWithUtf8Chars,"string_name_new_with_utf8_chars")(&data,s); }
    ~Name() { PROC(GDExtensionInterfaceVariantGetPtrDestructor,"variant_get_ptr_destructor")(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&data); }
};
static bool is_editor() {
    Name engine("Engine"), method("is_editor_hint");
    auto object = PROC(GDExtensionInterfaceGlobalGetSingleton,"global_get_singleton")(&engine.data);
    auto bind = PROC(GDExtensionInterfaceClassdbGetMethodBind,"classdb_get_method_bind")(&engine.data,&method.data,36873697);
    GDExtensionBool result = true;
    if (object && bind) PROC(GDExtensionInterfaceObjectMethodBindPtrcall,"object_method_bind_ptrcall")(bind,object,nullptr,&result);
    return result;
}
static void enqueue(NSDictionary *command) {
    @synchronized(commands) { if (commands.count < 32) [commands addObject:command]; }
}
@interface S4USettingsTarget : NSObject
- (void)openSettings:(id)sender;
@end
@implementation S4USettingsTarget
- (void)openSettings:(id)sender { enqueue(@{@"action":@"settings"}); }
@end
static S4USettingsTarget *settings_target;

static void setup_remote() {
    if (commands) return;
    commands = [NSMutableArray new]; remote_targets = [NSMutableArray new];
    settings_target = [S4USettingsTarget new];
    MPRemoteCommandCenter *center = MPRemoteCommandCenter.sharedCommandCenter;
    NSArray *items = @[center.togglePlayPauseCommand,center.playCommand,center.pauseCommand,center.nextTrackCommand,center.previousTrackCommand];
    NSArray *actions = @[@"toggle",@"play",@"pause",@"next",@"previous"];
    for (NSUInteger i=0; i<items.count; ++i) {
        MPRemoteCommand *command = items[i]; NSString *action = actions[i];
        command.enabled = YES;
        id target = [command addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
            if (!active) return MPRemoteCommandHandlerStatusNoSuchContent;
            enqueue(@{@"action":action}); return MPRemoteCommandHandlerStatusSuccess;
        }];
        [remote_targets addObject:@[command,target]];
    }
    center.changePlaybackPositionCommand.enabled = YES;
    id target = [center.changePlaybackPositionCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent *event) {
        if (!active) return MPRemoteCommandHandlerStatusNoSuchContent;
        enqueue(@{@"action":@"seek",@"position":@(((MPChangePlaybackPositionCommandEvent *)event).positionTime)});
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    [remote_targets addObject:@[center.changePlaybackPositionCommand,target]];
}
static NSDictionary *decode(NSDictionary *request) {
    NSString *source = request[@"source"], *destination = request[@"destination"];
    if (!source.length || !destination.length) return @{@"ok":@NO};
    ExtAudioFileRef input = nullptr, output = nullptr;
    OSStatus status = ExtAudioFileOpenURL((__bridge CFURLRef)[NSURL fileURLWithPath:source], &input);
    AudioStreamBasicDescription original = {}, pcm = {};
    UInt32 size = sizeof(original);
    if (!status) status = ExtAudioFileGetProperty(input,kExtAudioFileProperty_FileDataFormat,&size,&original);
    if (!status) {
        pcm.mSampleRate = original.mSampleRate;
        pcm.mFormatID = kAudioFormatLinearPCM;
        pcm.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
        pcm.mChannelsPerFrame = MIN(2,original.mChannelsPerFrame);
        pcm.mBitsPerChannel = 16; pcm.mFramesPerPacket = 1;
        pcm.mBytesPerFrame = pcm.mBytesPerPacket = 2 * pcm.mChannelsPerFrame;
        status = ExtAudioFileSetProperty(input,kExtAudioFileProperty_ClientDataFormat,sizeof(pcm),&pcm);
    }
    if (!status) status = ExtAudioFileCreateWithURL((__bridge CFURLRef)[NSURL fileURLWithPath:destination],kAudioFileWAVEType,&pcm,nullptr,kAudioFileFlags_EraseFile,&output);
    if (!status) status = ExtAudioFileSetProperty(output,kExtAudioFileProperty_ClientDataFormat,sizeof(pcm),&pcm);
    std::vector<uint8_t> buffer(4096 * MAX(1,pcm.mBytesPerFrame));
    while (!status) {
        UInt32 frames = 4096;
        AudioBufferList list = {1,{{pcm.mChannelsPerFrame,(UInt32)buffer.size(),buffer.data()}}};
        status = ExtAudioFileRead(input,&frames,&list);
        if (status || !frames) break;
        status = ExtAudioFileWrite(output,frames,&list);
    }
    if (input) ExtAudioFileDispose(input);
    if (output) { OSStatus close = ExtAudioFileDispose(output); if (!status) status = close; }
    if (status) [NSFileManager.defaultManager removeItemAtPath:destination error:nil];
    return @{@"ok":@(status == noErr),@"status":@(status)};
}
static NSString *exchange(NSString *json) {
    NSDictionary *r = [NSJSONSerialization JSONObjectWithData:[json dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
    if (![r isKindOfClass:NSDictionary.class]) return @"{}";
    NSDictionary *reply = @{};
    NSString *op = r[@"op"];
    if ([op isEqual:@"decode"]) reply = decode(r);
    else if ([op isEqual:@"poll"]) {
        @synchronized(commands) { reply = @{@"commands":[commands copy] ?: @[]}; [commands removeAllObjects]; }
    } else if ([op isEqual:@"publish"]) {
        active = true;
        BOOL playing = [r[@"playing"] boolValue];
        MPNowPlayingInfoCenter *center = MPNowPlayingInfoCenter.defaultCenter;
        center.nowPlayingInfo = @{
            MPMediaItemPropertyTitle:r[@"title"] ?: @"",
            MPMediaItemPropertyAlbumTitle:r[@"album"] ?: @"",
            MPMediaItemPropertyPlaybackDuration:r[@"duration"] ?: @0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime:r[@"position"] ?: @0,
            MPNowPlayingInfoPropertyPlaybackRate:playing ? @1 : @0,
            MPNowPlayingInfoPropertyMediaType:@(MPNowPlayingInfoMediaTypeAudio)
        };
        MPNowPlayingPlaybackState state = playing ? MPNowPlayingPlaybackStatePlaying : MPNowPlayingPlaybackStatePaused;
        if (center.playbackState != state) center.playbackState = state;
    } else if ([op isEqual:@"clear"]) {
        active = false;
        MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo = nil;
        MPNowPlayingInfoCenter.defaultCenter.playbackState = MPNowPlayingPlaybackStateStopped;
    } else if ([op isEqual:@"settings_title"]) {
        NSMenu *app_menu = NSApp.mainMenu.itemArray.firstObject.submenu;
        if (app_menu && !settings_item) {
            settings_item = [[NSMenuItem alloc] initWithTitle:r[@"title"] ?: @"Settings…" action:@selector(openSettings:) keyEquivalent:@","];
            settings_item.target = settings_target;
            [app_menu insertItem:settings_item atIndex:MIN(2,app_menu.numberOfItems)];
        }
        settings_item.title = r[@"title"] ?: @"Settings…";
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:reply options:0 error:nil];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"{}";
}
static NSString *read_string(const void *str) {
    auto utf8 = PROC(GDExtensionInterfaceStringToUtf8Chars,"string_to_utf8_chars");
    auto length = utf8(str,nullptr,0);
    std::vector<char> bytes(length+1,0); utf8(str,bytes.data(),length);
    return [[NSString alloc] initWithBytes:bytes.data() length:length encoding:NSUTF8StringEncoding] ?: @"";
}
static void call_exchange(void *, void *, const GDExtensionConstVariantPtr *args, GDExtensionInt count, GDExtensionVariantPtr result, GDExtensionCallError *error) {
    error->error = GDEXTENSION_CALL_OK;
    if (count != 1 || PROC(GDExtensionInterfaceVariantGetType,"variant_get_type")(args[0]) != GDEXTENSION_VARIANT_TYPE_STRING) {
        error->error = GDEXTENSION_CALL_ERROR_INVALID_ARGUMENT; error->argument=0; error->expected=GDEXTENSION_VARIANT_TYPE_STRING;
        PROC(GDExtensionInterfaceVariantNewNil,"variant_new_nil")(result); return;
    }
    void *input;
    PROC(GDExtensionInterfaceGetVariantToTypeConstructor,"get_variant_to_type_constructor")(GDEXTENSION_VARIANT_TYPE_STRING)(&input,const_cast<void *>(args[0]));
    NSString *response = exchange(read_string(&input));
    auto destroy = PROC(GDExtensionInterfaceVariantGetPtrDestructor,"variant_get_ptr_destructor")(GDEXTENSION_VARIANT_TYPE_STRING);
    destroy(&input);
    void *output;
    PROC(GDExtensionInterfaceStringNewWithUtf8Chars,"string_new_with_utf8_chars")(&output,response.UTF8String);
    PROC(GDExtensionInterfaceGetVariantFromTypeConstructor,"get_variant_from_type_constructor")(GDEXTENSION_VARIANT_TYPE_STRING)(result,&output);
    destroy(&output);
}
static GDExtensionObjectPtr create(void *) {
    Name base("RefCounted");
    auto object = PROC(GDExtensionInterfaceClassdbConstructObject,"classdb_construct_object")(&base.data);
    PROC(GDExtensionInterfaceObjectSetInstance,"object_set_instance")(object,&class_name,new int(0));
    return object;
}
static void free_instance(void *, void *instance) { delete (int *)instance; }
static void initialize(void *, GDExtensionInitializationLevel level) {
    if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
    PROC(GDExtensionInterfaceStringNameNewWithUtf8Chars,"string_name_new_with_utf8_chars")(&class_name,"S4UMacBridge");
    Name base("RefCounted"), method("exchange"), argument("request"), empty("");
    GDExtensionClassCreationInfo2 cls = {};
    cls.is_exposed=true; cls.create_instance_func=create; cls.free_instance_func=free_instance;
    PROC(GDExtensionInterfaceClassdbRegisterExtensionClass2,"classdb_register_extension_class2")(library,&class_name,&base.data,&cls);
    void *empty_string;
    PROC(GDExtensionInterfaceStringNewWithUtf8Chars,"string_new_with_utf8_chars")(&empty_string,"");
    GDExtensionPropertyInfo arg = {GDEXTENSION_VARIANT_TYPE_STRING,&argument.data,&empty.data,0,&empty_string,6};
    GDExtensionPropertyInfo ret = {GDEXTENSION_VARIANT_TYPE_STRING,&empty.data,&empty.data,0,&empty_string,6};
    GDExtensionClassMethodArgumentMetadata metadata = GDEXTENSION_METHOD_ARGUMENT_METADATA_NONE;
    GDExtensionClassMethodInfo info = {};
    info.name=&method.data; info.call_func=call_exchange;
    info.method_flags=GDEXTENSION_METHOD_FLAG_NORMAL | GDEXTENSION_METHOD_FLAG_VARARG; info.has_return_value=true;
    info.return_value_info=&ret; info.argument_count=1; info.arguments_info=&arg; info.arguments_metadata=&metadata;
    PROC(GDExtensionInterfaceClassdbRegisterExtensionClassMethod,"classdb_register_extension_class_method")(library,&class_name,&info);
    PROC(GDExtensionInterfaceVariantGetPtrDestructor,"variant_get_ptr_destructor")(GDEXTENSION_VARIANT_TYPE_STRING)(&empty_string);
    if (!is_editor()) setup_remote();
}
static void deinitialize(void *, GDExtensionInitializationLevel level) {
    if (level != GDEXTENSION_INITIALIZATION_SCENE) return;
    if (commands) {
        active=false;
        MPNowPlayingInfoCenter.defaultCenter.nowPlayingInfo=nil;
        MPNowPlayingInfoCenter.defaultCenter.playbackState=MPNowPlayingPlaybackStateStopped;
        for (NSArray *pair in remote_targets) [(MPRemoteCommand *)pair[0] removeTarget:pair[1]];
        [settings_item.menu removeItem:settings_item]; settings_item=nil; settings_target=nil;
        remote_targets=nil; commands=nil;
    }
    PROC(GDExtensionInterfaceClassdbUnregisterExtensionClass,"classdb_unregister_extension_class")(library,&class_name);
    PROC(GDExtensionInterfaceVariantGetPtrDestructor,"variant_get_ptr_destructor")(GDEXTENSION_VARIANT_TYPE_STRING_NAME)(&class_name);
}
extern "C" GDExtensionBool macos_media_keys_init(GDExtensionInterfaceGetProcAddress proc,GDExtensionClassLibraryPtr lib,GDExtensionInitialization *init) {
    api=proc; library=lib;
    init->minimum_initialization_level=GDEXTENSION_INITIALIZATION_SCENE;
    init->userdata=nullptr; init->initialize=initialize; init->deinitialize=deinitialize;
    return true;
}
