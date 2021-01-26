//////////////////////////////////////////////////////////////////////////////////////
//                                                                                  //
//  Module: SURFERControl                                                           //
//                                                                                  //
//  File: RFIDTag.m                                                                 //
//  Creation date: 7/12/2020                                                        //
//  Author: Edward Keehr                                                            //
//                                                                                  //
//                                                                                  //
//    Copyright 2021 Superlative Semiconductor LLC                                  //
//                                                                                  //
//    Licensed under the Apache License, Version 2.0 (the "License");               //
//    you may not use this file except in compliance with the License.              //
//    You may obtain a copy of the License at                                       //
//                                                                                  //
//       http://www.apache.org/licenses/LICENSE-2.0                                 //
//                                                                                  //
//    Unless required by applicable law or agreed to in writing, software           //
//    distributed under the License is distributed on an "AS IS" BASIS,             //
//    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.      //
//    See the License for the specific language governing permissions and           //
//    limitations under the License.                                                //
//                                                                                  //
//                                                                                  //
//  Description:                                                                    //
//  This class defines an RFID Tag in the iOS software. Each instance of this class //
//  represents an RFID Tag that was read recently by the reader.                    //
//                                                                                  //
//////////////////////////////////////////////////////////////////////////////////////

#import "RFIDTag.h"

@implementation RFIDTag

+ (instancetype)fakeDebugTag
{
    #define EPC_LENGTH 12
    uint8_t *fakeEPC=malloc(EPC_LENGTH * sizeof(uint8_t));
    
    for (uint8_t loop_epc=0;loop_epc<EPC_LENGTH;loop_epc++){
        fakeEPC[loop_epc]=arc4random() % 256;
    }
    
    NSString *fakeEPCString = [NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
                          fakeEPC[0], fakeEPC[1], fakeEPC[2], fakeEPC[3], fakeEPC[4], fakeEPC[5],
                          fakeEPC[6], fakeEPC[7], fakeEPC[8], fakeEPC[9], fakeEPC[10], fakeEPC[11]];
                          
    RFIDTag *newFakeDebugTag = [[self alloc] initTagWithEPC:fakeEPCString];
    
    newFakeDebugTag.freqHopMHz=902.5+(arc4random() % 24);
    newFakeDebugTag.magAntHop=-30-(50*(double)arc4random()/UINT32_MAX);
    newFakeDebugTag.phaseAntHop=3.14*(double)arc4random()/UINT32_MAX;
    newFakeDebugTag.magCalHop=-30-(50*(double)arc4random()/UINT32_MAX);
    newFakeDebugTag.phaseCalHop=3.14*(double)arc4random()/UINT32_MAX;
    newFakeDebugTag.nonceHop=0; //This nonce is to help the pdoa calculation determine how close the hop and skip are in time.
    newFakeDebugTag.freqSkipMHz=newFakeDebugTag.freqHopMHz+1;
    newFakeDebugTag.magAntSkip=-30-(50*(double)arc4random()/UINT32_MAX);
    newFakeDebugTag.phaseAntSkip=3.14*(double)arc4random()/UINT32_MAX;
    newFakeDebugTag.magCalSkip=-30-(50*(double)arc4random()/UINT32_MAX);
    newFakeDebugTag.phaseCalSkip=3.14*(double)arc4random()/UINT32_MAX;
    newFakeDebugTag.nonceSkip=0; //This nonce is to help the pdoa calculation determine how close the hop and skip are in time.
    newFakeDebugTag.pdoaRangeMeters=10*(double)arc4random()/UINT32_MAX;
    newFakeDebugTag.lastInterrogation = [[NSDate alloc] init];
    
    return newFakeDebugTag;
}

- (instancetype)initTagWithEPC:(NSString *)tag_epc
{
    //Call NSObject's initializer
    self = [super init];
    
    //If the superclass initializer succeeded, complete the initialization
    if(self){
        _epc = tag_epc;
        _firstInterrogation = [[NSDate alloc] init];
        _freqHopMHz     = 0;
        _magAntHop      = 0;
        _phaseAntHop    = 0;
        _magCalHop      = 0;
        _phaseCalHop    = 0;
        _nonceHop       = 0; //This nonce is to help the pdoa calculation determine how close the hop and skip are in time.
        _freqSkipMHz    = 0;
        _magAntSkip     = 0;
        _phaseAntSkip   = 0;
        _magCalSkip     = 0;
        _phaseCalSkip   = 0;
        _nonceSkip      = 0; //This nonce is to help the pdoa calculation determine how close the hop and skip are in time.
        
        _lastInterrogation = nil;

    }
    
    //Return the RFID tag object
    
    return self;
}

- (instancetype)init
{
    //We need to override the default initializer, but tell the programmer that doing this is considered a no-no.
    return [self initTagWithEPC:@"ERROR"];
}

//We need to use existing tag characteristics to compute the
//range of the tag from the reader. In this case, we throw a nil if we get a bad access

@end
