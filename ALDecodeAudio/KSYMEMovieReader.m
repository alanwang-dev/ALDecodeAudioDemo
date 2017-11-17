//
//  KSYMEMovieReader.m
//  KSYMediaEditorKit
//
//  Created by iVermisseDich on 2017/10/18.
//  Copyright © 2017年 ksyun. All rights reserved.
//

#import "KSYMEMovieReader.h"
#import "GPUImageMovieWriter.h"
#import "GPUImageFilter.h"
#import "GPUImageVideoCamera.h"
#import <pthread.h>

@interface KSYMEMovieReader () <AVPlayerItemOutputPullDelegate>
{
    BOOL audioEncodingIsFinished, videoEncodingIsFinished;
    CMTime previousFrameTime, processingFrameTime;
    CFAbsoluteTime previousActualFrameTime;
    BOOL keepLooping;
    BOOL _stoped;
    dispatch_queue_t readerQueue;
    
    int imageBufferWidth, imageBufferHeight;
    AVAssetReaderOutput *readerVideoTrackOutput;
    AVAssetReaderOutput *readerAudioTrackOutput;
    
}
@property (nonatomic) AVAssetReader *reader;
@property (nonatomic, assign) pthread_mutex_t lock;

@end

@implementation KSYMEMovieReader

@synthesize url = _url;
@synthesize asset = _asset;
@synthesize delegate = _delegate;
@synthesize shouldRepeat = _shouldRepeat;
@synthesize readerVideoTrackOutput = _readerVideoTrackOutput;
@synthesize readerAudioTrackOutput = _readerAudioTrackOutput;
#pragma mark -
#pragma mark Initialization and teardown

- (id)initWithURL:(NSURL *)url {
    if (!(self = [super init])) {
        return nil;
    }
    
    self.url = url;
    self.asset = nil;
    [self initialLock];
    
    return self;
}

- (id)initWithAsset:(AVAsset *)asset;{
    if (!(self = [super init])) {
        return nil;
    }
    
    self.url = nil;
    self.asset = asset;
    [self initialLock];
    
    return self;
}

- (void)initialLock{
    pthread_mutexattr_t attr;
    pthread_mutexattr_init (&attr);
    pthread_mutexattr_settype (&attr, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init (&_lock, &attr);
    pthread_mutexattr_destroy (&attr);
}

- (void)dealloc{
    pthread_mutex_destroy(&_lock);
    NSLog(@"movie reader dealloc");
}

#pragma mark -
#pragma mark Movie processing

- (void)startProcessing {
    if (self.asset) {
        [self processAsset];
        return;
    }
    if (!self.url) {
        NSLog(@"nothing to process");
        return;
    }
    
    if (_shouldRepeat) keepLooping = YES;
    
    NSDictionary *inputOptions = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES] forKey:AVURLAssetPreferPreciseDurationAndTimingKey];
    AVURLAsset *inputAsset = [[AVURLAsset alloc] initWithURL:self.url options:inputOptions];
    
//    KSYMEMovieReader __block *blockSelf = self;
//
//    [inputAsset loadValuesAsynchronouslyForKeys:[NSArray arrayWithObject:@"tracks"] completionHandler: ^{
//        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
//            NSError *error = nil;
//            AVKeyValueStatus tracksStatus = [inputAsset statusOfValueForKey:@"tracks" error:&error];
//            if (tracksStatus != AVKeyValueStatusLoaded)
//            {
//                return;
//            }
            self.asset = inputAsset;
            [self processAsset];
//            blockSelf = nil;
//        });
//    }];
}

- (AVAssetReader*)createAssetReader
{
    NSError *error = nil;
    AVAssetReader *assetReader = [AVAssetReader assetReaderWithAsset:self.asset error:&error];
    
    NSMutableDictionary *videoSettings = [NSMutableDictionary dictionary];
    [videoSettings setObject:@(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange) forKey:(id)kCVPixelBufferPixelFormatTypeKey];
    
    // Maybe set alwaysCopiesSampleData to NO on iOS 5.0 for faster video decoding
    _vTrack = [[self.asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    if (_vTrack){
        AVAssetReaderTrackOutput *readerVideoTrackOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:_vTrack outputSettings:videoSettings];
        
        readerVideoTrackOutput.alwaysCopiesSampleData = NO;
        [assetReader addOutput:readerVideoTrackOutput];
    }
    
    NSArray *audioTracks = [self.asset tracksWithMediaType:AVMediaTypeAudio];
    BOOL shouldRecordAudioTrack = (([audioTracks count] > 0));
    AVAssetReaderTrackOutput *readerAudioTrackOutput = nil;
    
    if (shouldRecordAudioTrack)
    {
        // This might need to be extended to handle movies with more than one audio track
        NSDictionary *audioSetting = @{AVFormatIDKey :@(kAudioFormatLinearPCM),
                                       AVLinearPCMBitDepthKey :@(16),
                                       //                                       AVLinearPCMIsBigEndianKey : @(NO),
                                       AVLinearPCMIsFloatKey : @(NO),
                                       };
        _aTrack = [audioTracks objectAtIndex:0];
        if (_aTrack) {
            readerAudioTrackOutput = [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:_aTrack outputSettings:audioSetting];
            readerAudioTrackOutput.alwaysCopiesSampleData = NO;
            [assetReader addOutput:readerAudioTrackOutput];
        }
    }
    
    return assetReader;
}

- (void)processAsset{
    dispatch_async(dispatch_get_global_queue(0, 0), ^(){
//        _totalFrames = [self getTotalFrame];
//        NSLog(@"_totalFrames %d", _totalFrames);
    });
    _reader = [self createAssetReader];
    
    AVAssetReaderOutput *readerVideoTrackOutput = nil;
    AVAssetReaderOutput *readerAudioTrackOutput = nil;
    
    audioEncodingIsFinished = YES;
    for( AVAssetReaderOutput *output in _reader.outputs ) {
        if( [output.mediaType isEqualToString:AVMediaTypeAudio] ) {
            audioEncodingIsFinished = NO;
            readerAudioTrackOutput = output;
            _readerAudioTrackOutput = output;
        }
        else if( [output.mediaType isEqualToString:AVMediaTypeVideo] ) {
            readerVideoTrackOutput = output;
            _readerVideoTrackOutput = output;
        }
    }
    
    
    if ([_reader startReading] == NO)
    {
        NSLog(@"Error reading from file at URL: %@", self.url);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self restartReader];
            NSLog(@"restart reader ===>");
        });
        return;
    }
    
    if (_reader.status == AVAssetReaderStatusCompleted) {
        [_reader cancelReading];
        
        if (keepLooping) {
            _reader = nil;
            dispatch_async(dispatch_get_main_queue(), ^{
                [self startProcessing];
            });
        } else {
            [self endProcessing];
        }
        
    }
}

- (CMSampleBufferRef)readNextVideoFrame{
    if (_readerVideoTrackOutput) {
        pthread_mutex_lock(&_lock);
        CMSampleBufferRef buf = [_readerVideoTrackOutput copyNextSampleBuffer];
        while (_reader.status == AVAssetReaderStatusReading
               && (!CMSampleBufferIsValid(buf) || CMSampleBufferGetNumSamples(buf) == 0)) {
            if (buf) {
                CFRelease(buf);
                buf = [_readerVideoTrackOutput copyNextSampleBuffer];
            }else{
                if (_reader.status == AVAssetReaderStatusFailed) {
                    NSLog(@"[ERROR] : decode error %@",_reader.error);
                }
            }
        }
        _frameProgress++;
        pthread_mutex_unlock(&_lock);
        return buf;
    }
    return nil;
}

- (CMSampleBufferRef)readNextAudioFrame{
    if (_readerVideoTrackOutput) {
        pthread_mutex_lock(&_lock);
        CMSampleBufferRef buf = [_readerAudioTrackOutput copyNextSampleBuffer];
        pthread_mutex_unlock(&_lock);
        return buf;
    }
    return nil;
}

- (void)restartReader{
    _reader = nil;
    _asset = nil;
    [self startProcessing];
}

- (void)endProcessing;
{
    keepLooping = NO;
        
    if ([self.delegate respondsToSelector:@selector(didCompletePlayingMovie)]) {
        [self.delegate didCompletePlayingMovie];
    }
    self.delegate = nil;
}

- (void)cancelProcessing{
    _stoped = YES;
    if (_reader) {
        pthread_mutex_lock(&_lock);
        [self.reader cancelReading];
        pthread_mutex_unlock(&_lock);
    }
    [self endProcessing];
}

- (AVAssetReader*)assetReader {
    return _reader;
}

- (BOOL)audioEncodingIsFinished {
    return audioEncodingIsFinished;
}

- (BOOL)videoEncodingIsFinished {
    return videoEncodingIsFinished;
}

@end
