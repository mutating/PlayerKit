//
//  Player.h
//  PlayerKit
//
//  Created by Jett on 14/12/2017.
//  Copyright © 2018 <https://github.com/mutating>. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSString * const PLAYERKITDOMAIN;

typedef enum : NSUInteger {
    PlayerErrorCodeUnknown                = -1000,
    PlayerErrorCodePrepareAssetFailed     = -1001,
    PlayerErrorCodeAssetCannotBePlayed    = -1002,
    PlayerErrorCodePlayerItemStatusFailed = -1003,
} PlayerErrorCode;

@protocol PlayerDelegate <NSObject>

@optional

- (void)playerReadyToPlay:(AVPlayer *)player;

- (void)player:(AVPlayer *)player didOutputPixelBuffer:(CVPixelBufferRef)pixelBuffer;

- (void)playerInterruptedWithError:(NSError *)error;

@end

typedef enum : NSUInteger {
    PreferredTransformOrientationPortrait,
    PreferredTransformOrientationPortraitUpsideDown,
    PreferredTransformOrientationLandscapeRight,
    PreferredTransformOrientationLandscapeLeft,
    PreferredTransformOrientationUnknown,
} PreferredTransformOrientation;

@interface Player : NSObject

@property (nonatomic, readonly) AVPlayer *player;
@property (nonatomic, readonly) AVPlayerItem *item;
@property (nonatomic, readonly) AVPlayerItemVideoOutput *itemOutput;

/*!
 Indicates the current audio volume of the player; 0.0 means "silence all audio", 1.0 means "play at the full volume of the current item".
 */
@property (nonatomic) float volume;

/*!
 Indicates the loop playback of the player; NO means "play once then done", YES means "play the medie file in a loop".
 */
@property (nonatomic) BOOL loop;

/*!
 Indicates the duration of the player item, not considering either its forwardPlaybackEndTime or reversePlaybackEndTime.
 */
@property (nonatomic, readonly) float duration;

/*!
 Indicates when the videovisual starts playing.
 */
@property (nonatomic) NSTimeInterval beginTimeInterval;

/*!
 Indicates whether the player is currently running.
 */
@property (nonatomic, readonly, getter=isRunning) BOOL running;

/*!
 Indicates whether the player is allowed to download while playing.
 */
@property (nonatomic, getter=isAllowedDownloadWhilePlaying) BOOL allowDownloadWhilePlaying;

/*!
 Indicates the preferred transform orientation in the video.
 */
@property (nonatomic, readonly) PreferredTransformOrientation preferredTransformOrientation;

/*!
 Indicates the transform specified in the video track's storage container as the preferred transformation of the visual media data for display purposes.
 */
@property (nonatomic, readonly) CGAffineTransform preferredTransform;

/*!
 Indicates the output pixel format.
 */
@property (nonatomic) int outputFormatType;

/*!
 The delegate of Player.
 */
@property (nonatomic, weak) id<PlayerDelegate> delegate;

/*!
 @method       initWithURL:
 @return       An instance of Player
 @abstract     Initializes a Player
 */
- (instancetype)init;

/*!
 @method       initWithURL:
 @param        url reference
 @return       An instance of Player
 @abstract     Initializes a Player taht plays a single audiovisual resource referenced by URL
 */
- (instancetype)initWithURL:(NSURL *)url;

/*!
 @method        play
 @abstract      Signals the desire to begin playback at the new item's natural rate. If player is running that will replace the player's current item with the specified player item.
 */
- (void)play:(NSURL *)url;

/*!
 @method        play
 @abstract      Signals the desire to begin playback at the current item's natural rate.
 */
- (void)resume;

/*!
 @method        pause
 @abstract      Pauses playback.
 */
- (void)pause;

/*!
 @method        seekTo:
 @abstract      Moves the playback cursor.
 @param         seconds time
 */
- (void)seekTo:(NSTimeInterval)seconds;

@end

NS_ASSUME_NONNULL_END
