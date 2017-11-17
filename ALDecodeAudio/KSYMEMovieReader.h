//
//  KSYMovieReader.h
//  KSYMediaEditorKit
//
//  Created by iVermisseDich on 2017/10/18.
//  Copyright © 2017年 ksyun. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

/** Protocol for getting Movie played callback.
 */
@protocol KSYMEMovieReaderDelegate <NSObject>

- (void)didCompletePlayingMovie;
@end

/** Source object for filtering movies
 */
@interface KSYMEMovieReader : NSObject

@property (readwrite, retain) AVAsset *asset;
@property (readwrite, retain) NSURL *url;

@property (nonatomic, weak) AVAssetTrack *vTrack;
@property (nonatomic, weak) AVAssetTrack *aTrack;

@property (nonatomic, readonly) AVAssetReaderOutput *readerVideoTrackOutput;
@property (nonatomic, readonly) AVAssetReaderOutput *readerAudioTrackOutput;

/** This determines whether the video should repeat (loop) at the end and restart from the beginning. Defaults to NO.
 */
@property(readwrite, nonatomic) BOOL shouldRepeat;

/// 读取是否暂停 默认NO
@property(readwrite, nonatomic) BOOL paused;


@property (nonatomic, assign) int totalFrames;
@property (nonatomic, assign) int frameProgress;

/** This is used to send the delete Movie did complete playing alert
 */
@property (readwrite, nonatomic, weak) id <KSYMEMovieReaderDelegate>delegate;

@property (readonly, nonatomic) AVAssetReader *assetReader;
@property (readwrite, nonatomic) BOOL audioEncodingIsFinished;
@property (readwrite, nonatomic) BOOL videoEncodingIsFinished;

/// @name Initialization and teardown
- (id)initWithAsset:(AVAsset *)asset;
- (id)initWithURL:(NSURL *)url;

- (void)startProcessing;
- (void)endProcessing;
- (void)cancelProcessing;

- (CMSampleBufferRef)readNextVideoFrame;
- (CMSampleBufferRef)readNextAudioFrame;

@end
