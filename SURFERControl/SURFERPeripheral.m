//////////////////////////////////////////////////////////////////////////////////////
//                                                                                  //
//  Module: SURFERControl                                                           //
//                                                                                  //
//  File: SURFERPeripheral.m                                                        //
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
//  Most of the functions here mirror the characteristics defined in the MCU        //
//  firmware.                                                                       //
//                                                                                  //
//////////////////////////////////////////////////////////////////////////////////////

#import "SURFERPeripheral.h"

//------------------------------------------------------------------------------------------------------------------
//Declarations

@interface SURFERPeripheral ()
@property CBService *surferService;
@property CBCharacteristic *writeStateCharacteristic;
@property CBCharacteristic *writeTargetEPCCharacteristic;
@property CBCharacteristic *writeNewEPCCharacteristic;
@property CBCharacteristic *readStateCharacteristic;
@property CBCharacteristic *packetData1Characteristic;
@property CBCharacteristic *packetData2Characteristic;
@property CBCharacteristic *waveformDataCharacteristic;
@property CBCharacteristic *logMessageCharacteristic;

@end

@implementation SURFERPeripheral
@synthesize peripheral = _peripheral;
@synthesize delegate = _delegate;

@synthesize surferService = _surferService;
@synthesize writeStateCharacteristic        = _writeStateCharacteristic;
@synthesize writeTargetEPCCharacteristic    = _writeTargetEPCCharacteristic;
@synthesize writeNewEPCCharacteristic       = _writeNewEPCCharacteristic;
@synthesize readStateCharacteristic         = _readStateCharacteristic;
@synthesize packetData1Characteristic       = _packetData1Characteristic;
@synthesize packetData2Characteristic       = _packetData2Characteristic;
@synthesize waveformDataCharacteristic      = _waveformDataEPCCharacteristic;
@synthesize logMessageCharacteristic        = _logMessageEPCCharacteristic;

//------------------------------------------------------------------------------------------------------------------

//Define various UUIDs. These need to match with the UUIDs provided in firmware.
//If we end up distributing many of these readers, we may need to find a way to provision unique IDs to all of them.

+ (CBUUID *) surferServiceUUID
{
    return [CBUUID UUIDWithString:@"e7560001-fc1d-8db5-ad46-26e5843b5915"];
}

+ (CBUUID *) writeStateCharacteristicUUID
{
    return [CBUUID UUIDWithString:@"e7560002-fc1d-8db5-ad46-26e5843b5915"];
}

+ (CBUUID *) writeTargetEPCCharacteristicUUID
{
    return [CBUUID UUIDWithString:@"e7560003-fc1d-8db5-ad46-26e5843b5915"];
}

+ (CBUUID *) writeNewEPCCharacteristicUUID
{
    return [CBUUID UUIDWithString:@"e7560004-fc1d-8db5-ad46-26e5843b5915"];
}

+ (CBUUID *) readStateCharacteristicUUID
{
    return [CBUUID UUIDWithString:@"e7560005-fc1d-8db5-ad46-26e5843b5915"];
}

+ (CBUUID *) packetData1CharacteristicUUID
{
    return [CBUUID UUIDWithString:@"e7560006-fc1d-8db5-ad46-26e5843b5915"];
}

+ (CBUUID *) packetData2CharacteristicUUID
{
    return [CBUUID UUIDWithString:@"e7560007-fc1d-8db5-ad46-26e5843b5915"];
}

+ (CBUUID *) waveformDataCharacteristicUUID
{
    return [CBUUID UUIDWithString:@"e7560008-fc1d-8db5-ad46-26e5843b5915"];
}

+ (CBUUID *) logMessageCharacteristicUUID
{
    return [CBUUID UUIDWithString:@"e7560009-fc1d-8db5-ad46-26e5843b5915"];
}

+ (CBUUID *) deviceInformationServiceUUID
{
    return [CBUUID UUIDWithString:@"180A"];
}

+ (CBUUID *) hardwareRevisionStringUUID
{
    return [CBUUID UUIDWithString:@"2A27"];
}

//---------------------------------------------------------------------------------------------------------------
//Various fundamental functions regarding management of the reader abstraction in iOS software.

- (SURFERPeripheral *) initWithPeripheral:(CBPeripheral*)peripheral delegate:(id<SURFERPeripheralDelegate>) delegate
{
    if (self = [super init])
    {
        _peripheral = peripheral;
        _peripheral.delegate = self;
        _delegate = delegate;
    }
    return self;
}

- (void) didConnect
{
    [_peripheral discoverServices:@[self.class.surferServiceUUID, self.class.deviceInformationServiceUUID]];
    NSLog(@"Did start service discovery.");
}

- (void) didDisconnect
{
    
}

//----------------------------------------------------------------------------------------------------------------
//
//These are functions used to send data from the iOS application software to the reader.

- (void) writeStateData:(NSData *) data
{
    if ((self.writeStateCharacteristic.properties & CBCharacteristicPropertyWriteWithoutResponse) != 0)
    {
        [self.peripheral writeValue:data forCharacteristic:self.writeStateCharacteristic type:CBCharacteristicWriteWithoutResponse];
        //NSLog(@"Wrote %d chars",[data length]);
        
    }
    else if ((self.writeStateCharacteristic.properties & CBCharacteristicPropertyWrite) != 0)
    {
        [self.peripheral writeValue:data forCharacteristic:self.writeStateCharacteristic type:CBCharacteristicWriteWithResponse];
    }
    else
    {
        NSLog(@"No write property on Write State characteristic, %lu.", (unsigned long)self.writeStateCharacteristic.properties);
    }
}

- (void) writeTargetEPCData:(NSData *) data
{
    if ((self.writeTargetEPCCharacteristic.properties & CBCharacteristicPropertyWriteWithoutResponse) != 0)
    {
        [self.peripheral writeValue:data forCharacteristic:self.writeTargetEPCCharacteristic type:CBCharacteristicWriteWithoutResponse];
        //NSLog(@"Wrote %d chars",[data length]);
        
    }
    else if ((self.writeTargetEPCCharacteristic.properties & CBCharacteristicPropertyWrite) != 0)
    {
        [self.peripheral writeValue:data forCharacteristic:self.writeTargetEPCCharacteristic type:CBCharacteristicWriteWithResponse];
    }
    else
    {
        NSLog(@"No write property on Write Target EPC characteristic, %lu.", (unsigned long)self.writeTargetEPCCharacteristic.properties);
    }
}

- (void) writeNewEPCData:(NSData *) data
{
    if ((self.writeNewEPCCharacteristic.properties & CBCharacteristicPropertyWriteWithoutResponse) != 0)
    {
        [self.peripheral writeValue:data forCharacteristic:self.writeNewEPCCharacteristic type:CBCharacteristicWriteWithoutResponse];
        //NSLog(@"Wrote %d chars",[data length]);
        
    }
    else if ((self.writeNewEPCCharacteristic.properties & CBCharacteristicPropertyWrite) != 0)
    {
        [self.peripheral writeValue:data forCharacteristic:self.writeNewEPCCharacteristic type:CBCharacteristicWriteWithResponse];
    }
    else
    {
        NSLog(@"No write property on Write New EPC characteristic, %lu.", (unsigned long)self.writeStateCharacteristic.properties);
    }
}

- (void) readTargetEPCData
{
    if (self.writeTargetEPCCharacteristic.properties != 0)
    {
        [self.peripheral readValueForCharacteristic:self.writeTargetEPCCharacteristic];
    }
}

- (void) readNewEPCData
{
    if (self.writeNewEPCCharacteristic.properties != 0)
    {
        [self.peripheral readValueForCharacteristic:self.writeNewEPCCharacteristic];
    }
}

- (void) readStateData
{
    NSLog(@"Got to readStateData");
    if (self.readStateCharacteristic.properties != 0)
    {
        [self.peripheral readValueForCharacteristic:self.readStateCharacteristic];
        NSLog(@"Actually reading readStateData");
    }
}

//-------------------------------------------------------------------------------------------------------
//
// This function is called when the iOS software discovers the RFID reader service.
// The service information obtained over the air is then loaded into the abstraction of the reader in the iOS software.


- (void) peripheral:(CBPeripheral *)peripheral didDiscoverServices:(NSError *)error
{
    if (error)
    {
        NSLog(@"Error discovering services: %@", error);
        return;
    }
    
    for (CBService *s in [peripheral services])
    {
        if ([s.UUID isEqual:self.class.surferServiceUUID])
        {
            NSLog(@"Found correct service");
            self.surferService = s;
            
            [self.peripheral discoverCharacteristics:@[self.class.writeStateCharacteristicUUID, self.class.writeTargetEPCCharacteristicUUID, self.class.writeNewEPCCharacteristicUUID, self.class.readStateCharacteristicUUID, self.class.packetData1CharacteristicUUID, self.class.packetData2CharacteristicUUID, self.class.waveformDataCharacteristicUUID, self.class.logMessageCharacteristicUUID] forService:self.surferService];
        }
        else if ([s.UUID isEqual:self.class.deviceInformationServiceUUID])
        {
            [self.peripheral discoverCharacteristics:@[self.class.hardwareRevisionStringUUID] forService:s];
        }
    }
}

//----------------------------------------------------------------------------------------------------------
// This function is called when the iOS software discovers the RFID reader service characteristics.
// The characteristics information obtained over the air is then loaded into the abstraction of the reader in the iOS software.

- (void) peripheral:(CBPeripheral *)peripheral didDiscoverCharacteristicsForService:(CBService *)service error:(NSError *)error
{
    if (error)
    {
        NSLog(@"Error discovering characteristics: %@", error);
        return;
    }
    
    for (CBCharacteristic *c in [service characteristics])
    {
        if ([c.UUID isEqual:self.class.writeStateCharacteristicUUID])
        {
            NSLog(@"Found write state characteristic");
            self.writeStateCharacteristic = c;
            
            //[self.peripheral setNotifyValue:YES forCharacteristic:self.rxCharacteristic];
        }
        else if ([c.UUID isEqual:self.class.writeTargetEPCCharacteristicUUID])
        {
            NSLog(@"Found Target EPC characteristic");
            self.writeTargetEPCCharacteristic = c;
            [self.peripheral setNotifyValue:YES forCharacteristic:self.writeTargetEPCCharacteristic];
            [self readTargetEPCData];
        }
        else if ([c.UUID isEqual:self.class.writeNewEPCCharacteristicUUID])
        {
            NSLog(@"Found New EPC characteristic");
            self.writeNewEPCCharacteristic = c;
            [self.peripheral setNotifyValue:YES forCharacteristic:self.writeNewEPCCharacteristic];
            [self readNewEPCData];
        }
        else if ([c.UUID isEqual:self.class.readStateCharacteristicUUID])
        {
            NSLog(@"Found Read State characteristic");
            self.readStateCharacteristic = c;
            
            [self.peripheral setNotifyValue:YES forCharacteristic:self.readStateCharacteristic];
            //Note - this supposedly also turns on the indication
            [self readStateData];
        }
        else if ([c.UUID isEqual:self.class.packetData1CharacteristicUUID])
        {
            NSLog(@"Found Packet Data 1 characteristic");
            self.packetData1Characteristic = c;
            
            [self.peripheral setNotifyValue:YES forCharacteristic:self.packetData1Characteristic];
        }
        else if ([c.UUID isEqual:self.class.packetData2CharacteristicUUID])
        {
            NSLog(@"Found Packet Data 2 characteristic");
            self.packetData2Characteristic = c;
            
            [self.peripheral setNotifyValue:YES forCharacteristic:self.packetData2Characteristic];
        }
        else if ([c.UUID isEqual:self.class.waveformDataCharacteristicUUID])
        {
            NSLog(@"Found waveform data characteristic");
            self.waveformDataCharacteristic = c;
            
            [self.peripheral setNotifyValue:YES forCharacteristic:self.waveformDataCharacteristic];
        }
        else if ([c.UUID isEqual:self.class.logMessageCharacteristicUUID])
        {
            NSLog(@"Found Log Message characteristic");
            self.logMessageCharacteristic = c;
            
            [self.peripheral setNotifyValue:YES forCharacteristic:self.logMessageCharacteristic];
        }
        else if ([c.UUID isEqual:self.class.hardwareRevisionStringUUID])
        {
            NSLog(@"Found Hardware Revision String characteristic");
            [self.peripheral readValueForCharacteristic:c];
        }
    }
}

//---------------------------------------------------------------------------------------------------
//
// In general, this is the function that gets called when the reader tries to send data to the iDevice.
// In this function, we have to determine over which characteristic the data was sent and deal with the
// data appropriately, which usually involves sending the data to the appropriate application function in
// TableViewController.m

- (void) peripheral:(CBPeripheral *)peripheral didUpdateValueForCharacteristic:(CBCharacteristic *)characteristic error:(NSError *)error
{
    if (error)
    {
        NSLog(@"Error receiving notification for characteristic %@: %@", characteristic, error);
        return;
    }
    
    //NSLog(@"Received data on a characteristic.");
    
    if (characteristic == self.writeTargetEPCCharacteristic)
    {
        NSData *data = [characteristic value];
        [self.delegate didReceiveTargetEPCData:data];
    }
    else if (characteristic == self.writeNewEPCCharacteristic)
    {
        NSData *data = [characteristic value];
        [self.delegate didReceiveNewEPCData:data];
    }
    else if (characteristic == self.readStateCharacteristic)
    {
        
        NSData *data = [characteristic value];
        [self.delegate didReceiveReadStateData:data];
        //NSLog(@"Received %lu bytes of data",(unsigned long)[data length]);
        //NSString *string = [NSString stringWithUTF8String:[[characteristic value] bytes]];
        //NSLog(@"Received %s",[[characteristic value] bytes]);
    }
    else if (characteristic == self.packetData1Characteristic)
    {
    
        NSData *data = [characteristic value];
        [self.delegate didReceivePacketData1Data:data];
    }
    else if (characteristic == self.packetData2Characteristic)
    {
        
        NSData *data = [characteristic value];
        [self.delegate didReceivePacketData2Data:data];
    }
    else if (characteristic == self.waveformDataCharacteristic)
    {
        
        NSData *data = [characteristic value];
        [self.delegate didReceiveWaveformDataData:data];
    }
    else if (characteristic == self.logMessageCharacteristic)
    {
        
        NSData *data = [characteristic value];
        [self.delegate didReceiveLogMessageData:data];
    }
    
    else if ([characteristic.UUID isEqual:self.class.hardwareRevisionStringUUID])
    {
        NSString *hwRevision = @"";
        const uint8_t *bytes = characteristic.value.bytes;
        for (int i = 0; i < characteristic.value.length; i++)
        {
            NSLog(@"%x", bytes[i]);
            hwRevision = [hwRevision stringByAppendingFormat:@"0x%02x, ", bytes[i]];
        }
        
        [self.delegate didReadHardwareRevisionString:[hwRevision substringToIndex:hwRevision.length-2]];
    }
}
@end

