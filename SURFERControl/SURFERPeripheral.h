//////////////////////////////////////////////////////////////////////////////////////
//                                                                                  //
//  Module: SURFERControl                                                           //
//                                                                                  //
//  File: SURFERPeripheral.h                                                        //
//  Creation date: circa 10/31/2016                                                 //
//  Author: Edward Keehr                                                            //
//                                                                                  //
//    This file was derived from the Nordic Semiconductor example code in their     //
//    nRF UART app. Specifically, this file was derived from "UARTPeripheral.m".    //
//    The code in this file is basically the code in that file pattern-matched all  //
//    the way through to apply to this project.                                     //
//                                                                                  //
//     The required notice to be reproduced for Nordic Semiconductor code is        //
//     given below:                                                                 //
//                                                                                  //
//     Created by Ole Morten on 1/12/13.                                            //
//     Copyright (c) 2013 Nordic Semiconductor. All rights reserved.                //
//                                                                                  //
//    For components of the code modified or authored by Superlative                //
//    Semiconductor LLC, the copyright notice is as follows:                        //
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
//  This class represents the RFID reader from the standpoint of the iOS            //
//  software.                                                                       //
//                                                                                  //
//////////////////////////////////////////////////////////////////////////////////////

@import CoreBluetooth;
#import <Foundation/Foundation.h>

@protocol SURFERPeripheralDelegate
- (void) didReceiveTargetEPCData:(NSData *) data;
- (void) didReceiveNewEPCData:(NSData *) data;
- (void) didReceiveReadStateData:(NSData *) data;
- (void) didReceivePacketData1Data:(NSData *) data;
- (void) didReceivePacketData2Data:(NSData *) data;
- (void) didReceiveWaveformDataData:(NSData *) data;
- (void) didReceiveLogMessageData:(NSData *) data;
@optional
- (void) didReadHardwareRevisionString:(NSString *) string;
@end


@interface SURFERPeripheral : NSObject <CBPeripheralDelegate>
@property CBPeripheral *peripheral;
@property id<SURFERPeripheralDelegate> delegate;

+ (CBUUID *) surferServiceUUID;

- (SURFERPeripheral *) initWithPeripheral:(CBPeripheral*)peripheral delegate:(id<SURFERPeripheralDelegate>) delegate;

- (void) writeStateData:(NSData *) data;
- (void) writeTargetEPCData:(NSData *) data;
- (void) writeNewEPCData:(NSData *) data;
- (void) readTargetEPCData;
- (void) readNewEPCData;
- (void) readStateData;

- (void) didConnect;
- (void) didDisconnect;
@end
