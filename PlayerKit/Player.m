//
//  Player.m
//  PlayerKit
//
//  Created by Jett on 14/12/2017.
//  Copyright © 2018 <https://github.com/mutating>. All rights reserved.
//

#import "Player.h"
#import "PlayerAssetLoaderDelegate.h"

#import "PlayerFileManager.h"
#import "PlayerLogger.h"

NSString * const PLAYERKITDOMAIN = @"PLAYERKIT DOMAIN";

/* Asset keys */
NSString * const kPlayerPlayableKey       = @"playable";

/* PlayerItem keys */
NSString * const kPlayerStatusKey         = @"status";
NSString * const kPlayerBufferEmptyKey    = @"playbackBufferEmpty";
NSString * const kPlayerLikelyKeepUpKey   = @"playbackLikelyToKeepUp";

/* AVPlayer keys */
NSString * const kPlayerRateKey           = @"rate";
NSString * const kPlayerCurrentItemKey    = @"currentItem";

/* URL Schemes */
NSString * const kPlayerFileScheme        = @"file";
NSString * const kPlayerHttpScheme        = @"http";
NSString * const kPlayerHttpsScheme       = @"https";
NSString * const kPlayerCustomScheme      = @"streaming";

/* Play back space time */
float const kPlayerBackSpaceTime    = 0.4;

/* Context */
static void *kPlayerStatusObservationContext      = &kPlayerStatusObservationContext;
static void *kPlayerRateObservationContext        = &kPlayerRateObservationContext;
static void *kPlayerCurrentItemObservationContext = &kPlayerCurrentItemObservationContext;
static void *kPlayerPlaybackBufferEmptyContext    = &kPlayerPlaybackBufferEmptyContext;
static void *kPlayerPlaybackLikelyToKeepUpContext = &kPlayerPlaybackLikelyToKeepUpContext;

@interface Player () {
    PlayerAssetLoaderDelegate *assetLoaderDelegate;
}

@end

@interface Player (PixelBuffer)

- (void)frameAtTime:(CMTime)time;

@end

@interface Player (Headphones)

@end

@implementation Player {
    NSString *_destDirectory;
    NSString *_cacheDirectory;
    
    id _itemObserver;
    BOOL _autoPlaying;
    BOOL _isInitialize;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        [self initialize];
    }
    return self;
}

- (instancetype)initWithURL:(NSURL *)url {
    self = [super init];
    if (self) {
        [self initialize];
        [self prepareWithURL:url];
    }
    return self;
}

- (void)initialize {
    _player = [[AVPlayer alloc] init];
    _running = NO;
    _beginTimeInterval = -1;
    
    _destDirectory = PlayerFileManager.sharedInstance.destDirectory;
    _cacheDirectory = PlayerFileManager.sharedInstance.cacheDirectory;
    
    [self configAudioSessionCategory];
}

- (void)dealloc {
    if (_item) {
        [_item removeObserver:self forKeyPath:kPlayerStatusKey context:kPlayerStatusObservationContext];
        [_item removeObserver:self forKeyPath:kPlayerBufferEmptyKey context:kPlayerPlaybackBufferEmptyContext];
        [_item removeObserver:self forKeyPath:kPlayerLikelyKeepUpKey context:kPlayerPlaybackLikelyToKeepUpContext];
        
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:AVPlayerItemDidPlayToEndTimeNotification
                                                      object:_item];
        [_item removeOutput:_itemOutput];
        
        [_player removeObserver:self forKeyPath:kPlayerCurrentItemKey context:kPlayerCurrentItemObservationContext];
        [_player removeObserver:self forKeyPath:kPlayerRateKey context:kPlayerRateObservationContext];
        [_player removeTimeObserver:_itemObserver];
        
        [self->assetLoaderDelegate invalidate];
        self->assetLoaderDelegate = nil;
    }
    NSLog(@"%@ dealloc", NSStringFromClass(self.class));
}

- (void)play:(NSURL *)url {
    _autoPlaying = YES;
    [self prepareWithURL:url];
}

- (void)resume {
    if (!_running) {
        [self seekTo:-1];
    }
}

- (void)pause {
    if (_running) {
        _running = NO;
        [_player pause];
    }
}

- (void)seekTo:(NSTimeInterval)seconds {
    _running = YES;
    if (_item) {
        CMTime time = _item.currentTime;
        CMTimeScale timeScale = time.timescale;
        if (seconds < 0) {
            seconds = CMTimeGetSeconds(time);
        }
        
        seconds = MIN(seconds, self.playerLoadedSeconds);
        seconds = MAX(0, (seconds - kPlayerBackSpaceTime));
        CMTime seekTime = CMTimeMakeWithSeconds(seconds, timeScale);
        
        __weak typeof(self) weakSelf = self;
        [_player seekToTime:seekTime
            toleranceBefore:kCMTimeZero
             toleranceAfter:kCMTimeZero
          completionHandler:^(BOOL finished) {
              if (finished) {
                  [weakSelf.player play];
              }
          }];
    }
}

- (float)duration {
    float duration = CMTimeGetSeconds(_player.currentItem.duration);
    return duration;
}

- (void)setVolume:(float)volume {
    _player.volume = volume;
}

- (float)playerLoadedSeconds {
    CMTimeRange loadedTimeRange = _item.loadedTimeRanges.firstObject.CMTimeRangeValue;
    float loadedStart = CMTimeGetSeconds(loadedTimeRange.start);
    float loadedDuration = CMTimeGetSeconds(loadedTimeRange.duration);
    float loadedSeconds = loadedStart + loadedDuration;
    return loadedSeconds;
}

- (void)configAudioSessionCategory {
    NSError *error;
    BOOL success = [AVAudioSession.sharedInstance setActive:YES error:&error];
    if (!success) {
        NSLog(@"Audio Session set active with error: %@", error);
    } else {
        success = [AVAudioSession.sharedInstance setCategory:AVAudioSessionCategoryPlayback
                                                       error:&error];
        if (!success) {
            NSLog(@"Audio Session set category with error: %@", error.localizedDescription);
        }
    }
}

- (void)configDelegates:(AVURLAsset *)asset originScheme:(NSString *)scheme {
    self->assetLoaderDelegate = [[PlayerAssetLoaderDelegate alloc] initWithOriginScheme:scheme
                                                                         cacheDirectory:_cacheDirectory
                                                                          destDirectory:_destDirectory];
    AVAssetResourceLoader *loader = asset.resourceLoader;
    [loader setDelegate:assetLoaderDelegate queue:dispatch_queue_create("com.PlayerKit.AssetLoaderDelegate", nil)];
}

- (void)prepareWithURL:(NSURL *)url {
    if (url) {
        AVURLAsset *asset;
        
        if (_allowDownloadWhilePlaying) {
            if ([url.scheme isEqualToString:kPlayerHttpScheme] ||
                [url.scheme isEqualToString:kPlayerHttpsScheme]) {
                NSString *videoPath = [_destDirectory stringByAppendingPathComponent:url.lastPathComponent];
                BOOL isDirectory;
                BOOL isExist = [[NSFileManager defaultManager] fileExistsAtPath:videoPath isDirectory:&isDirectory];
                if (isExist && !isDirectory) {
                    url = [NSURL fileURLWithPath:videoPath isDirectory:NO];
                    asset = [AVURLAsset URLAssetWithURL:url options:nil];
                } else {
                    NSString *scheme = url.scheme;
                    NSURL *schemeURL = [self customSchemeWithURL:url];
                    asset = [AVURLAsset URLAssetWithURL:schemeURL options:nil];
                    [self configDelegates:asset originScheme:scheme];
                }
            } else if ([url.scheme isEqualToString:kPlayerFileScheme]) {
                asset = [AVURLAsset URLAssetWithURL:url options:nil];
            } else {
                url = [NSURL fileURLWithPath:url.path isDirectory:NO];
                asset = [AVURLAsset URLAssetWithURL:url options:nil];
            }
        } else {
            if (![url.scheme isEqualToString:kPlayerHttpScheme] &&
                ![url.scheme isEqualToString:kPlayerHttpsScheme] &&
                ![url.scheme isEqualToString:kPlayerFileScheme]) {
                url = [NSURL fileURLWithPath:url.path isDirectory:NO];
            }
            asset = [AVURLAsset URLAssetWithURL:url options:nil];
        }
        
        /*
         Create an asset for inspection of a resource referenced by a given URL.
         Load the values for the asset keys  "playable".
         */
        NSArray *requestedKeys = [NSArray arrayWithObjects:kPlayerPlayableKey, nil];
        
        __weak typeof(self) weakSelf = self;
        /* Tells the asset to load the values of any of the specified keys that are not already loaded. */
        [asset loadValuesAsynchronouslyForKeys:requestedKeys completionHandler: ^{
            dispatch_async( dispatch_get_main_queue(), ^{
                /* IMPORTANT: Must dispatch to main queue in order to operate on the AVPlayer and AVPlayerItem. */
                [weakSelf prepareWithAsset:asset withKeys:requestedKeys];
            });
        }];
    }
}

- (void)prepareWithAsset:(AVURLAsset *)asset withKeys:(NSArray *)requestedKeys {
    /* Make sure that the value of each key has loaded successfully. */
    for (NSString *thisKey in requestedKeys) {
        NSError *error = nil;
        AVKeyValueStatus keyStatus = [asset statusOfValueForKey:thisKey error:&error];
        if (keyStatus == AVKeyValueStatusFailed) {
            NSError *failedPrepareAsset = [NSError errorWithDomain:PLAYERKITDOMAIN
                                                               code:PlayerErrorCodePrepareAssetFailed
                                                           userInfo:error.userInfo];
            [self interruptedWithError:failedPrepareAsset];
            return;
        }
        /* If you are also implementing -[AVAsset cancelLoading], add your code here to bail out properly in the case of cancellation. */
    }
    
    /* Use the AVAsset playable property to detect whether the asset can be played. */
    if (!asset.playable) {
        /* Generate an error describing the failure. */
        NSString *localizedDescription = NSLocalizedString(@"Item cannot be played", @"Item cannot be played description");
        NSString *localizedFailureReason = NSLocalizedString(@"The contents of the resource at the specified URL are not playable.", @"Item cannot be played failure reason");
        NSDictionary *errorDict = [NSDictionary dictionaryWithObjectsAndKeys:
                                   localizedDescription, NSLocalizedDescriptionKey,
                                   localizedFailureReason, NSLocalizedFailureReasonErrorKey,
                                   nil];
        NSError *assetCannotBePlayedError = [NSError errorWithDomain:PLAYERKITDOMAIN
                                                                code:PlayerErrorCodeAssetCannotBePlayed
                                                            userInfo:errorDict];
        
        /* Display the error to the user. */
        [self interruptedWithError:assetCannotBePlayedError];
        return;
    }
    
    for (AVAssetTrack *track in asset.tracks) {
        if ([track.mediaType isEqualToString:AVMediaTypeVideo]) {
            CGAffineTransform transform = track.preferredTransform;
            _preferredTransform = transform;
            if (transform.a == 0 && transform.b == 1.0 && transform.c == -1.0 && transform.d == 0) {
                _preferredTransformOrientation = PreferredTransformOrientationPortrait;
            } else if (transform.a == 0 && transform.b == -1.0 && transform.c == 1.0 && transform.d == 0) {
                _preferredTransformOrientation = PreferredTransformOrientationPortraitUpsideDown;
            } else if (transform.a == 1.0 && transform.b == 0 && transform.c == 0 && transform.d == 1.0) {
                _preferredTransformOrientation = PreferredTransformOrientationLandscapeRight;
            } else if (transform.a == -1.0 && transform.b == 0 && transform.c == 0 && transform.d == -1.0) {
                _preferredTransformOrientation = PreferredTransformOrientationLandscapeLeft;
            } else {
                _preferredTransformOrientation = PreferredTransformOrientationUnknown;
            }
        }
    }
    
    /* At this point we're ready to set up for playback of the asset. */
    
    /* Stop observing our prior AVPlayerItem, if we have one. */
    if (_item) {
        [_item removeObserver:self forKeyPath:kPlayerStatusKey context:kPlayerStatusObservationContext];
        [_item removeObserver:self forKeyPath:kPlayerBufferEmptyKey context:kPlayerPlaybackBufferEmptyContext];
        [_item removeObserver:self forKeyPath:kPlayerLikelyKeepUpKey context:kPlayerPlaybackLikelyToKeepUpContext];
        
        [[NSNotificationCenter defaultCenter] removeObserver:self
                                                        name:AVPlayerItemDidPlayToEndTimeNotification
                                                      object:_item];
        [_item removeOutput:_itemOutput];
    }
    
    /* Create a new instance of AVPlayerItem from the now successfully loaded AVAsset. */
    _item = [AVPlayerItem playerItemWithAsset:asset];
    [_item addObserver:self
            forKeyPath:kPlayerStatusKey
               options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
               context:kPlayerStatusObservationContext];
    [_item addObserver:self
            forKeyPath:kPlayerBufferEmptyKey
               options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
               context:kPlayerPlaybackBufferEmptyContext];
    [_item addObserver:self
            forKeyPath:kPlayerLikelyKeepUpKey
               options:NSKeyValueObservingOptionNew | NSKeyValueObservingOptionNew
               context:kPlayerPlaybackLikelyToKeepUpContext];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(playerItemDidReachEnd:)
                                                 name:AVPlayerItemDidPlayToEndTimeNotification
                                               object:_item];
    
    if (_outputFormatType <= 0) {
        _outputFormatType = kCVPixelFormatType_32BGRA;
    }
    _itemOutput = [[AVPlayerItemVideoOutput alloc] initWithPixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey:[NSNumber numberWithInt:_outputFormatType]}];
    [_item addOutput:_itemOutput];
    
    if (_player.currentItem != _item) {
        [_player replaceCurrentItemWithPlayerItem:_item];
        
        /* Observe the AVPlayer "currentItem" property to find out when any
         AVPlayer replaceCurrentItemWithPlayerItem: replacement will/did
         occur.*/
        [_player addObserver:self
                      forKeyPath:kPlayerCurrentItemKey
                         options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                         context:kPlayerCurrentItemObservationContext];
        
        /* Observe the AVPlayer "rate" property to update the scrubber control. */
        [_player addObserver:self
                      forKeyPath:kPlayerRateKey
                         options:NSKeyValueObservingOptionInitial | NSKeyValueObservingOptionNew
                         context:kPlayerRateObservationContext];
        
        __weak typeof(self) weakSelf = self;
        _itemObserver = [_player addPeriodicTimeObserverForInterval:CMTimeMake(1, 30)
                                                              queue:dispatch_get_main_queue()
                                                         usingBlock:^(CMTime time) {
                                                             if (weakSelf.isRunning) {
                                                                 [weakSelf frameAtTime:time];
                                                             }
        }];
    }
}

- (void)playerItemDidReachEnd:(NSNotification *)notification {
    [self pause];
    [self seekTo:MAX(0, _beginTimeInterval)];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary<NSKeyValueChangeKey,id> *)change
                       context:(void *)context {
    if (context == kPlayerStatusObservationContext) {
        NSLog(@"Player Observe Content kPlayerStatusObservationContext");
        AVPlayerItem *playerItem = (AVPlayerItem *)object;
        AVPlayerItemStatus status = playerItem.status;
        switch (status) {
            case AVPlayerItemStatusUnknown: {
                NSLog(@"Status unknown");
            }
                break;
            case AVPlayerItemStatusReadyToPlay: {
                NSLog(@"Status readyToPlay");
                if([_delegate respondsToSelector:@selector(playerReadyToPlay:)]) {
                    [_delegate playerReadyToPlay:_player];
                }
                if (_autoPlaying) {
                    if (_beginTimeInterval < 0) {
                        [self resume];
                    } else {
                        if (!_isInitialize) {
                            _isInitialize = YES;
                            [self seekTo:_beginTimeInterval];
                        }
                    }
                }
            }
                break;
            case AVPlayerItemStatusFailed: {
                NSLog(@"Status failed");
                [self pause];
                NSError *statusFailedError = [NSError errorWithDomain:PLAYERKITDOMAIN
                                                                 code:PlayerErrorCodePlayerItemStatusFailed
                                                             userInfo:playerItem.error.userInfo];
                [self interruptedWithError:statusFailedError];
            }
                break;
            default:
                break;
        }
    } else if (context == kPlayerRateObservationContext) {
        NSLog(@"Player Observe Content kPlayerRateObservationContext");
    } else if (context == kPlayerCurrentItemObservationContext) {
        NSLog(@"Player Observe Content kPlayerCurrentItemObservationContext");
    } else if (context == kPlayerPlaybackBufferEmptyContext) {
        NSLog(@"Player Observe Content kPlayerPlaybackBufferEmptyContext");
    } else if (context == kPlayerPlaybackLikelyToKeepUpContext) {
        NSLog(@"Player Observe Content kPlayerPlaybackLikelyToKeepUpContext");
    } else {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
    }
}

/*!
 *  Called when an asset fails to prepare for playback for any of
 *  the following reasons:
 *
 *  1) values of asset keys did not load successfully,
 *  2) the asset keys did load successfully, but the asset is not
 *     playable
 *  3) the item did not become ready to play.
 */
- (void)interruptedWithError:(NSError *)error {
    /* Display the error. */
    if ([_delegate respondsToSelector:@selector(playerInterruptedWithError:)]) {
        [_delegate playerInterruptedWithError:error];
    }
}

- (NSURL *)customSchemeWithURL:(NSURL *)url {
    NSURLComponents *components = [[NSURLComponents alloc] initWithURL:url resolvingAgainstBaseURL:NO];
    components.scheme = kPlayerCustomScheme;
    return [components URL];
}

@end

@implementation Player (PixelBuffer)

- (void)frameAtTime:(CMTime)time {
    if([_delegate respondsToSelector:@selector(player:didOutputPixelBuffer:)]) {
        if ([_itemOutput hasNewPixelBufferForItemTime:time]) {
            const CVPixelBufferRef pixelBuffer = [_itemOutput copyPixelBufferForItemTime:time itemTimeForDisplay:nil];
            if (pixelBuffer) {
                CVPixelBufferLockBaseAddress(pixelBuffer, 0);
                [_delegate player:_player didOutputPixelBuffer:pixelBuffer];
                CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
                CVBufferRelease(pixelBuffer);
            }
        }
    }
}

@end

@implementation Player (Headphones)

- (void)configHeadphones {
    if ([self isHeadSetPlugging]) {
        NSLog(@"🎧");
    } else {
        NSLog(@"📱");
    }
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(audioRouteChangeListenerCallback:)
                                                 name:AVAudioSessionRouteChangeNotification
                                               object:nil];
}

- (BOOL)isHeadSetPlugging {
    AVAudioSessionRouteDescription *route = [[AVAudioSession sharedInstance] currentRoute];
    for (AVAudioSessionPortDescription *desc in [route outputs]) {
        if ([[desc portType] isEqualToString:AVAudioSessionPortHeadphones])
            return YES;
    }
    return NO;
}

- (void)audioRouteChangeListenerCallback:(NSNotification*)notification {
    NSDictionary *interuptionDict = notification.userInfo;
    NSInteger routeChangeReason = [[interuptionDict valueForKey:AVAudioSessionRouteChangeReasonKey] integerValue];
    switch (routeChangeReason) {
        case AVAudioSessionRouteChangeReasonNewDeviceAvailable:
            NSLog(@"AVAudioSessionRouteChangeReasonNewDeviceAvailable");
            break;
        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable:
            NSLog(@"AVAudioSessionRouteChangeReasonOldDeviceUnavailable");
            break;
        case AVAudioSessionRouteChangeReasonCategoryChange:
            // called at start - also when other audio wants to play
            NSLog(@"AVAudioSessionRouteChangeReasonCategoryChange");
            break;
    }
}

@end
