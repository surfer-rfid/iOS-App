//////////////////////////////////////////////////////////////////////////////////////
//                                                                                  //
//  Module: SURFERControl                                                           //
//                                                                                  //
//  File: RFIDTagList.h                                                             //
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
//  This class defines a store of RFID tags that have been recently read by the     //
//  RFID reader.                                                                    //
//                                                                                  //
//////////////////////////////////////////////////////////////////////////////////////

#import <Foundation/Foundation.h>

@protocol RFIDTagListDelegateTLVC
- (void)addNewTagToTable:(NSInteger)row;
- (void)reloadTableTagData;
@end

@protocol RFIDTagListDelegateTIVC
- (void)displayTagInformation;
@optional

@end

@class RFIDTag;

@interface RFIDTagList : NSObject

@property (nonatomic, readonly, copy) NSArray *allRFIDTags; //Provides a copy of the array of RFID tags, not to be manipulated
@property (nonatomic,weak) id<RFIDTagListDelegateTLVC> delegateTLVC;
@property (nonatomic,weak) id<RFIDTagListDelegateTIVC> delegateTIVC;

+ (instancetype)theOnlyRFIDTagListWithDelegateTLVC:(id<RFIDTagListDelegateTLVC>) delegateTLVC; //A class method for either creating or returning the RFID Tag List singleton object
+ (instancetype)theOnlyRFIDTagListWithDelegateTIVC:(id<RFIDTagListDelegateTIVC>) delegateTIVC; //A class method for either creating or returning the RFID Tag List singleton object
+ (instancetype)theOnlyRFIDTagList;
- (RFIDTag *)createFakeDebugTag; //For debugging, we'll want to generate fake tags at random intervals.
- (void)clearRFIDTagList;
- (void)saveTagWithEPC: (NSString *)epc withFreqSlot: (uint8_t)freqSlot //When we get a tag read, we'll want to dump the data
        withHopNotSkip: (BOOL)hopNotSkip withHopSkipNonce: (uint8_t)hopSkipNonce //This class will take the data and store it in the list of tags.
           withAntMagI: (int32_t)antMagI withAntMagQ: (int32_t)antMagQ//If the tag is already present, this method will update the
           withCalMagI: (int32_t)calMagI withCalMagQ: (int32_t)calMagQ;//tag information.

@end

