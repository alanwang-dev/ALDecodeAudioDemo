//
//  ViewController.m
//  ALDecodeAudio
//
//  Created by iVermisseDich on 2017/11/17.
//  Copyright © 2017年 com.ksyun. All rights reserved.
//

#import "ViewController.h"
#import <libksygpulive.h>
#import <libksygpufilter.h>
#import <libksystreamerengine.h>
#import <TPCircularBuffer.h>
#import <pthread.h>
#import "KSYMEMovieReader.h"

@interface ViewController ()
@property (nonatomic) KSYAQPlayer *audioPlayer;                     // audio play
@property (nonatomic, assign) TPCircularBuffer pcmBuf;              // audio buf
@property (nonatomic) AudioStreamBasicDescription* fmt;             // current reader's audio format
@property (nonatomic) BOOL isPlaying;
@property (nonatomic) KSYMEMovieReader *audioReader;

@property (nonatomic, assign) pthread_mutex_t lock;

@property (nonatomic) KSYClipWriter *writer;
@property (nonatomic) KSYAudioMixer *mixer;
@property (nonatomic, assign) int bgmLayer;
@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    // mutex lock
    pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&_lock, &attr);
    pthread_mutexattr_destroy (&attr);

    _writer = [[KSYClipWriter alloc] initWithDefaultCfg];
    _writer.bWithVideo = NO;
    _bgmLayer = 0;
    __weak typeof(self) wSelf = self;
    _mixer = [[KSYAudioMixer alloc] init];
    [_mixer setTrack:_bgmLayer enable:YES];
    [_mixer setAudioProcessingCallback:^(CMSampleBufferRef sampleBuffer) {
        [wSelf.writer processAudioSampleBuffer:sampleBuffer];
    }];
}

- (IBAction)startPlay:(id)sender {
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"xxx" withExtension:@"MOV"];
//    NSURL *url = [[NSBundle mainBundle] URLForResource:@"xxx" withExtension:@"mp3"];

    _audioReader = [[KSYMEMovieReader alloc] initWithURL:url];
    [_audioReader startProcessing];
    self.audioPlayer = [[KSYAQPlayer alloc] init];
    __weak typeof(self) wSelf = self;
    self.audioPlayer.pullDataCB = ^BOOL(AudioQueueBufferRef buf) {
        return [wSelf readData:buf];
    };
    TPCircularBufferInit(&_pcmBuf, 2048 * 8 * 2);
    [_writer startWritingWith:[NSURL URLWithString:[NSHomeDirectory() stringByAppendingFormat:@"/Documents/xxx.mp4"]]];
    [self decodeAudio];
}

- (IBAction)stopPlay:(id)sender {
    pthread_mutex_lock(&_lock);
    self.isPlaying = NO;
    [self.audioPlayer stop];
    TPCircularBufferClear(&_pcmBuf);
    [self.audioReader cancelProcessing];
    NSLog(@"clear buffer 1");
    pthread_mutex_unlock(&_lock);
}


#pragma mark - Process Audio
- (BOOL)readData:(AudioQueueBufferRef)buf{
    if (!_isPlaying) {
        return NO;
    }
    int ret = [self readPCMData:buf->mAudioData
                       capacity:buf->mAudioDataBytesCapacity];
    buf->mAudioDataByteSize = ret;
    if ( ret < buf->mAudioDataBytesCapacity ) { // eof
        [self eofProcess];
    }
    return YES;
}

- (void)eofProcess{
    [_writer stopWriting];
    NSLog(@"--audio--eof");
}

- (int)readPCMData:(void*)buf capacity:(UInt32)cap {
    int bytesNeed = cap;
    int availableBytes   = 0;
    int16_t *pSrc = NULL;
    
    if (cap > _pcmBuf.length ){
        TPCircularBufferCleanup(&_pcmBuf);
        TPCircularBufferInit(&_pcmBuf, bytesNeed);
    }
    
    CMTime dur = CMTimeMake(cap / (_fmt->mBytesPerFrame * _fmt->mChannelsPerFrame), _fmt->mSampleRate);
    
    while (availableBytes < bytesNeed) {
        pSrc = TPCircularBufferTail(&_pcmBuf, &availableBytes);
        if ( availableBytes <  bytesNeed ) {
            // read more
            int ret = [self decodeAudio];
            if (ret <= 0 ) { //  no more data
                bytesNeed = availableBytes;
                break;
            }
        }
    }
    memcpy(buf, pSrc, bytesNeed);
    TPCircularBufferConsume(&_pcmBuf,bytesNeed);
    return bytesNeed;
}

- (int)decodeAudio{
    if (_audioReader.assetReader.status == AVAssetReaderStatusReading){
        CMSampleBufferRef audioSampleBufferRef = [_audioReader readNextAudioFrame];
        [_mixer processAudioSampleBuffer:audioSampleBufferRef of:_bgmLayer];
        if (audioSampleBufferRef && CMSampleBufferIsValid(audioSampleBufferRef) && CMSampleBufferGetNumSamples(audioSampleBufferRef) > 0) {
            CMTime pts = CMSampleBufferGetPresentationTimeStamp(audioSampleBufferRef);
            //            NSLog(@"[READ] audio pts %f",CMTimeGetSeconds(pts));
            //            [self.clock updateAudioPts:CMTimeGetSeconds(pts)];
            int ret = [self pushAudioBuffer:audioSampleBufferRef];
            CFRelease(audioSampleBufferRef);
            return ret;
        }else{
            return 0;
        }
    }else{
        return 0;
    }
}

- (int)pushAudioBuffer:(CMSampleBufferRef)buf{
    if (!self.isPlaying) {
        CMAudioFormatDescriptionRef audioFormat = CMSampleBufferGetFormatDescription(buf);
        AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(audioFormat);
        if (!_fmt) {
            _fmt = (AudioStreamBasicDescription *)malloc(sizeof(AudioStreamBasicDescription));
        }
        memset(_fmt, 0, sizeof(AudioStreamBasicDescription));
        _fmt->mSampleRate       = asbd->mSampleRate;
        _fmt->mFormatID         = asbd->mFormatID;
        _fmt->mFormatFlags      = asbd->mFormatFlags;
        _fmt->mBytesPerPacket   = asbd->mBytesPerPacket;
        _fmt->mFramesPerPacket  = asbd->mFramesPerPacket;
        _fmt->mBytesPerFrame    = asbd->mBytesPerFrame;
        _fmt->mChannelsPerFrame = asbd->mChannelsPerFrame;
        _fmt->mBitsPerChannel   = asbd->mBitsPerChannel;
        _fmt->mReserved         = asbd->mReserved;
        
        self.isPlaying = YES;
        [self.audioPlayer play:asbd];
    }
    pthread_mutex_lock(&_lock);
    CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(buf);
    int32_t length = CMBlockBufferGetDataLength(blockBuffer);
    int space =0;
    void* pDst = TPCircularBufferHead( &_pcmBuf, &space);
    space /= _fmt->mBytesPerFrame;
    OSStatus ret =CMBlockBufferCopyDataBytes(blockBuffer, 0, length, pDst);
    TPCircularBufferProduce(&_pcmBuf, length);
    pthread_mutex_unlock(&_lock);
    return length;
}

@end
