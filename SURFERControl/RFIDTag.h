//////////////////////////////////////////////////////////////////////////////////////
//                                                                                  //
//  Module: SURFERControl                                                           //
//                                                                                  //
//  File: RFIDTag.h                                                                 //
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

#import <Foundation/Foundation.h>

@interface RFIDTag : NSObject

@property (nonatomic, copy)                 NSString *epc; //The tag's EPC
@property (nonatomic, readonly, strong)     NSDate  *firstInterrogation; //The time/date the tag was first interrogated.
@property (nonatomic, strong)               NSDate  *lastInterrogation; //The time/date the tag was last interrogated.
@property (nonatomic)                       float_t freqHopMHz;
//The frequency used in the PDOA "hop" (need to hop for FCC, skip for small enough PDOA step).
@property (nonatomic)                       float_t magAntHop; //The received tag magnitude for antenna operations in dBm.
@property (nonatomic)                       float_t phaseAntHop; //The received tag phase for antenna operations in radians (0 to pi only).
@property (nonatomic)                       float_t magCalHop; //The calibration magnitude for this frequency hop in dBm.
@property (nonatomic)                       float_t phaseCalHop; //The calibration phase for this frequency hop in radians (0 to pi only).
@property (nonatomic)                       uint8_t nonceHop; //This nonce is to help the pdoa calculation determine how close the hop and skip are.
@property (nonatomic)                       float_t freqSkipMHz;
//The frequency used in the PDOA "hop" (need to hop for FCC, skip for small enough PDOA step).
@property (nonatomic)                       float_t magAntSkip; //The received tag magnitude for antenna operations in dBm.
@property (nonatomic)                       float_t phaseAntSkip; //The received tag phase for antenna operations in radians (0 to pi only).
@property (nonatomic)                       float_t magCalSkip; //The calibration magnitude for this frequency hop in dBm.
@property (nonatomic)                       float_t phaseCalSkip; //The calibration phase for this frequency hop in radians (0 to pi only).
@property (nonatomic)                       uint8_t nonceSkip; //This nonce is to help the pdoa calculation determine how close the hop and skip are.
@property (nonatomic)                       float_t pdoaRangeMeters; //The range computed by PDOA, in meters.

+ (instancetype)fakeDebugTag;

//The below will override the initializer - we only want to initialize with the EPC and
//add all the fields to NULL. Then the TagList class will fill out the rest of the fields.
//This initializer will also write the first Interrogation field.
//Subsequent saves by the TagList class will only write the last interrogation field.
- (instancetype)initTagWithEPC:(NSString *)tag_epc;

- (instancetype)init;

@end

