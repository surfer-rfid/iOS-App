//////////////////////////////////////////////////////////////////////////////////////
//                                                                                  //
//  Module: SURFERControl                                                           //
//                                                                                  //
//  File: RFIDTagList.m                                                             //
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
//  RFID reader. This file uses of of the coding style and concepts from Big Nerd   //
//  Ranch's "iOS Programming, 4th Edition" Chapter 8.                               //
//                                                                                  //
//////////////////////////////////////////////////////////////////////////////////////

#import "RFIDTagList.h"
#import "RFIDTag.h"
#import <math.h>

@interface RFIDTagList ()

@property (nonatomic) NSMutableArray *privateRFIDTags;

@end

@implementation RFIDTagList

@synthesize delegateTLVC = _delegateTLVC;
@synthesize delegateTIVC = _delegateTIVC;

static RFIDTagList *theOnlyRFIDTagList; //Only want one of these so keep it out here.

+ (instancetype)theOnlyRFIDTagListWithDelegateTLVC:(id<RFIDTagListDelegateTLVC>) delegateTLVC
{
    //static RFIDTagList *theOnlyRFIDTagList;
    
    //Is there already one of these? If so, return the existing one.
    //If not, create!
    
    theOnlyRFIDTagList = [self theOnlyRFIDTagList];

    theOnlyRFIDTagList.delegateTLVC=delegateTLVC;
    
    return theOnlyRFIDTagList;
}

+ (instancetype)theOnlyRFIDTagListWithDelegateTIVC:(id<RFIDTagListDelegateTIVC>) delegateTIVC
{
    //static RFIDTagList *theOnlyRFIDTagList;
    
    //Is there already one of these? If so, return the existing one.
    //If not, create!
    
    theOnlyRFIDTagList = [self theOnlyRFIDTagList];

    theOnlyRFIDTagList.delegateTIVC=delegateTIVC;
    
    return theOnlyRFIDTagList;
}

+ (instancetype)theOnlyRFIDTagList
{
    //static RFIDTagList *theOnlyRFIDTagList;
    
    //Is there already one of these? If so, return the existing one.
    //If not, create!
    
    if(!theOnlyRFIDTagList) {
        theOnlyRFIDTagList = [[self alloc] initPrivate];
    }
    
    return theOnlyRFIDTagList;
}

//If the default initializer gets called, flag an exception

- (instancetype)init
{
    [NSException raise:@"Singleton"
                format:@"Use +[RFIDTagList theOnlyRFIDTagList(WithDelegate)]"];
    
    return nil;
}

//Here is the internal, private initializer

-(instancetype)initPrivate
{
    self = [super init];
    
    if(self) {
        _privateRFIDTags = [[NSMutableArray alloc] init];
    }
    
    return self;
}

//Here is the function to clear the list of RFID tags

-(void)clearRFIDTagList
{
    if(self) {
        _privateRFIDTags = [[NSMutableArray alloc] init];
    }
}

//Here is the function to return a copy of the array of tags

-(NSArray *)allRFIDTags
{
    return [self.privateRFIDTags copy];
}

//Below is the main function we'll use when taking in a packet from the bluetooth interface and converting it into
//tag information. This function below will have a fair amount of intelligence in order to:
//1. Act differently depending on whether the packet is a hop or skip.
//2. Translate I and Q magnitude to an RSSI value in dBm.
//3. Translate I and Q magnitude to a phase between 0 and pi.
//4. Compute PDOA range if enough information exists to do so.
//5. Compute operational frequency from slot value.

- (void)saveTagWithEPC: (NSString *)epc withFreqSlot: (uint8_t)freqSlot //When we get a tag read, we'll want to dump the data
        withHopNotSkip: (BOOL)hopNotSkip withHopSkipNonce: (uint8_t)hopSkipNonce //This class will take the data and store it in the list of tags.
           withAntMagI: (int32_t)antMagI withAntMagQ: (int32_t)antMagQ//If the tag is already present, this method will update the
           withCalMagI: (int32_t)calMagI withCalMagQ: (int32_t)calMagQ//tag information.
{
    //First, find the tag we are looking for.
    RFIDTag *tag = [self findOrCreateActualTagWithEPC:epc];
    //Next, create useable metrics from the raw values return by the reader.
    float_t antRSSIdBm  = [self computeTagRSSIFromMagI: antMagI andMagQ: antMagQ];
    float_t calRSSIdBm  = [self computeTagRSSIFromMagI: calMagI andMagQ: calMagQ];
    float_t antPhaseDeg = [self computeTagPhaseFromMagI: antMagI andMagQ: antMagQ];
    float_t calPhaseDeg = [self computeTagPhaseFromMagI: calMagI andMagQ: calMagQ];
    float_t freqInMHz = [self computeFreqMHzFromSlot: freqSlot];
    
    //Next, record the time at which the tag was read
    
    tag.lastInterrogation = [[NSDate alloc] init];
    
    //Next, enter the data into the tag object
    if(hopNotSkip){
        tag.freqHopMHz  =   freqInMHz;
        tag.magAntHop   =   antRSSIdBm; //This is the data from which tag RSSI is reported.
        tag.magCalHop   =   calRSSIdBm;
        tag.phaseAntHop =   antPhaseDeg;
        tag.phaseCalHop =   calPhaseDeg;
        tag.nonceHop    =   hopSkipNonce;
        //Note that since hop must come first, we clear out the skip data from before
        //However, we don't clear out the computed PDOA range from before
        tag.freqSkipMHz  =   0;
        tag.magAntSkip   =   0; //This is the data from which tag RSSI is reported.
        tag.magCalSkip   =   0;
        tag.phaseAntSkip =   0;
        tag.phaseCalSkip =   0;
        //Don't do anything with the nonce. Setting it to 0 may cause bugs.
    } else {
        tag.freqSkipMHz  =   freqInMHz;
        tag.magAntSkip   =   antRSSIdBm; //This is the data from which tag RSSI is reported.
        tag.magCalSkip   =   calRSSIdBm;
        tag.phaseAntSkip =   antPhaseDeg;
        tag.phaseCalSkip =   calPhaseDeg;
        tag.nonceSkip    =   hopSkipNonce;
        
        //Now we also compute PDOA range
        tag.pdoaRangeMeters = [self computeTagPDOARange:tag];
    }
    
    //If we have view controllers, update the data
    
    if(self.delegateTLVC){
        [self.delegateTLVC reloadTableTagData];
    }
    
    if(self.delegateTIVC){
        [self.delegateTIVC displayTagInformation];
    }
}

//Method to find the tag we are looking for in the RFID tag list. If the tag isn't there, create it.
-(RFIDTag *)findOrCreateActualTagWithEPC: (NSString *)epc
{
    for(RFIDTag *tag in self.privateRFIDTags){
        //If the tag EPC is in the list, return it.
        if([tag.epc isEqualToString:epc]){
            return tag;
        }
    }
    //If we go through the list and there was no such tag, create the tag
    RFIDTag *tag=[[RFIDTag alloc] initTagWithEPC:epc];
    //And add it to the collection of tags
    [self.privateRFIDTags addObject:tag];
    //And add a row to the TagListViewController, if it's been instantiated.
    if(self.delegateTLVC){
        [self.delegateTLVC addNewTagToTable:[self.privateRFIDTags indexOfObject:tag]];
    }
    //Then return this
    return tag;
}

//And when we want to create a random item for testing out the code, we do it here.

-(RFIDTag *)createFakeDebugTag
{
    RFIDTag *tag = [RFIDTag fakeDebugTag];
    [self.privateRFIDTags addObject:tag];
    
    return tag;
}

//Compute the phase of the I/Q magnitudes. Return a value that's between 0 and pi.

-(float_t)computeTagRSSIFromMagI: (int32_t) magI andMagQ: (int32_t) magQ
{
    #define PCEPC_ACK_BITS 128.0  //The number of received data bits in the packet to be used for computing RSSI.
    #define MILLER_M 8.0          //Miller modulation index. Currently we have it set to 8, the maximum.
    #define DBE_OSR 24.0         //The oversampling ratio of the digital back end (4.5MHz for tag BLE of 187.5kHz)
    #define RCVR_GAIN_DB 131.5
    
    float_t rssiInWatts          = 0;
    float_t rssiIndBm            = 0;
    float_t nChipsPerPacket     = PCEPC_ACK_BITS * MILLER_M * DBE_OSR;
    float_t receiverPowerGain   = 50.0*(64.0/(pow(M_PI,4)))*pow(10,RCVR_GAIN_DB/10);
    
    rssiInWatts = (1/receiverPowerGain)*(pow(magI/nChipsPerPacket,2)+pow(magQ/nChipsPerPacket,2));
    
    rssiIndBm   =  10*log10f(rssiInWatts)+30;
    
    return rssiIndBm;
    
}

-(float_t)computeTagPhaseFromMagI: (int32_t) magI andMagQ: (int32_t) magQ
{
    //We know that the minus sign is wrong but we realized late in the game that the SX1257
    //I and Q RX ADC outputs are misnamed (I and Q are switched).
    //Rather than going through and renaming everything, since the only angle-dependent feature
    //of the system (as of 110920) is this, we just compensate for this by adding a minus sign
    //in the angle calculation.
    return fmod(atan(-(double)magQ/(double)magI)+M_PI,M_PI);
}

//Compute the range of the tag from the antenna using the PDOA technique.

-(float_t)computeTagPDOARange: (RFIDTag *)tag
{
    #define SPEED_LIGHT_VAC 299792458
    #define ER_PCB 4.2 //Will need to change to 4.2 for actual operation
    #define ER_CAB 2.0 //Need to check if this is PTFE or not. Same for cable and connector. Will need to change for actual operation (2.0).
    #define ANT_PCB_ROUTE_M 0.0095
    #define ANT_CAB_ROUTE_M 0.2286
    #define CAL_PCB_ROUTE_M 0.0095
    #define CAL_CAB_ROUTE_M 0.254
    
    //#define CAL_PCB_ROUTE_M 0.0292
    //#define CAL_CAB_ROUTE_M 0.0254
    
    float_t ant_known_phase_hop = 0.0;
    float_t ant_known_phase_skip = 0.0;
    float_t cal_known_phase_hop = 0.0;
    float_t cal_known_phase_skip = 0.0;
    float_t corrected_phase_hop = 0.0;
    float_t corrected_phase_skip = 0.0;
    
    //First thing is we need to determine whether or not we can compute the range.
    //What are the cases in which we should fail (return a dummy value that can be tested for)?
    //1. Hop/skip nonce don't match
    //2. No skip data (skip data is nil'd out).
    //3. Frequency difference between hop and skip is less than 3.1MHz (otherwise it causes aliasing at range with a big patch antenna.
    
    if(tag.nonceHop != tag.nonceSkip){
        return tag.pdoaRangeMeters; //If the nonces don't match, don't update the range.
        //In rare cases, there may be a bug in which the nonces wrap around but we imagine that will be rare enough to be acceptable.
    }
    
    if(!tag.phaseAntHop || !tag.phaseAntSkip || !tag.phaseCalHop || !tag.phaseCalSkip
       || !tag.freqHopMHz || !tag.freqSkipMHz || tag.magCalHop < -70 || tag.magCalSkip < -70){
        NSLog(@"Attempted to compute PDOA ranging for a tag with incomplete phase data");
        //Note that if the returned calibration RSSI is too low, phase data is likely also invalid.
        return 99.9;
    }

    if(fabsf(tag.freqHopMHz - tag.freqSkipMHz) > 3.1){
        NSLog(@"Attempted to compute PDOA ranging for a tag with too large of a hop/skip frequency delta");
        return 99.9;
    }
    
    if(fabsf(tag.freqHopMHz - tag.freqSkipMHz) < 0.9){
        NSLog(@"Attempted to compute PDOA ranging for a tag with too small of a hop/skip frequency delta");
        return 99.9;
    }
    
    //Second thing is we need to compute the phase of the signal on the PCB/cabling that is not part of a shared path.
    //In other words, we wish to compute the distance of the antenna to the tag, but both the antenna and calibration device
    //exist at finite and known distances from the RF receiver.
    
    //For the moment, we're going to try a calibration device being a tag that sits right outside of the antenna.
    //We'll leave the distance between the antenna and the tag as an error for the moment.
    
    //4 Pi is actually 2*2pi, the 2 coming from out and back phase changes.
    
    ant_known_phase_hop =
    fmod(4.0*M_PI*tag.freqHopMHz*(1e6)*(ANT_PCB_ROUTE_M/(SPEED_LIGHT_VAC/sqrt(ER_PCB))+ANT_CAB_ROUTE_M/(SPEED_LIGHT_VAC/sqrt(ER_CAB))),M_PI);
    ant_known_phase_skip=
    fmod(4.0*M_PI*tag.freqSkipMHz*(1e6)*(ANT_PCB_ROUTE_M/(SPEED_LIGHT_VAC/sqrt(ER_PCB))+ANT_CAB_ROUTE_M/(SPEED_LIGHT_VAC/sqrt(ER_CAB))),M_PI);
    cal_known_phase_hop =
    fmod(4.0*M_PI*tag.freqHopMHz*(1e6)*(ANT_PCB_ROUTE_M/(SPEED_LIGHT_VAC/sqrt(ER_PCB))+ANT_CAB_ROUTE_M/(SPEED_LIGHT_VAC/sqrt(ER_CAB))),M_PI);
    //fmod(4.0*M_PI*tag.freqHopMHz*(1e6)*(CAL_PCB_ROUTE_M/(SPEED_LIGHT_VAC/sqrt(ER_PCB))+CAL_CAB_ROUTE_M/(SPEED_LIGHT_VAC/sqrt(ER_CAB))),M_PI);
    
    cal_known_phase_skip =
    fmod(4.0*M_PI*tag.freqSkipMHz*(1e6)*(ANT_PCB_ROUTE_M/(SPEED_LIGHT_VAC/sqrt(ER_PCB))+ANT_CAB_ROUTE_M/(SPEED_LIGHT_VAC/sqrt(ER_CAB))),M_PI);
    //fmod(4.0*M_PI*tag.freqSkipMHz*(1e6)*(CAL_PCB_ROUTE_M/(SPEED_LIGHT_VAC/sqrt(ER_PCB))+CAL_CAB_ROUTE_M/(SPEED_LIGHT_VAC/sqrt(ER_CAB))),M_PI);
    
    //Third thing is that we need to compute the corrected hop frequency phase and the corrected skip frequency phase.
    //Because TX and RX phase in the receiver varies randomly with respect to each other, and because the SAW filter
    //phase varies all over the place, the calibration phase must be removed from the antenna phase
    
    corrected_phase_hop     =   fmod((tag.phaseAntHop - tag.phaseCalHop) - (ant_known_phase_hop - cal_known_phase_hop)+2*M_PI,M_PI);
    corrected_phase_skip    =   fmod((tag.phaseAntSkip - tag.phaseCalSkip) - (ant_known_phase_skip - cal_known_phase_skip)+2*M_PI,M_PI);
    
    //Fourth thing is to finally subtract the hop and skip phases from one another
    //Div by 4 is for out and back phase change, otherwise it would just be 2*pi.
    
    if(tag.freqHopMHz > tag.freqSkipMHz){
        return SPEED_LIGHT_VAC/4/M_PI/((tag.freqHopMHz - tag.freqSkipMHz)*(1e6))*fmod(corrected_phase_hop-corrected_phase_skip+2*M_PI,M_PI);
    } else {
        return SPEED_LIGHT_VAC/4/M_PI/((tag.freqSkipMHz - tag.freqHopMHz)*(1e6))*fmod(corrected_phase_skip-corrected_phase_hop+2*M_PI,M_PI);
    }
}

//Compute the frequency of the tag read from the frequency slot

-(float_t)computeFreqMHzFromSlot: (uint8_t)slot
{
    float_t freqMHz = 0.0;
    
    switch (slot){
        case 0:     freqMHz = 903.0; break;
        case 1:     freqMHz = 904.0; break;
        case 2:     freqMHz = 905.0; break;
        case 3:     freqMHz = 906.0; break;
        case 4:     freqMHz = 907.0; break;
        case 5:     freqMHz = 908.0; break;
        case 6:     freqMHz = 909.0; break;
        case 7:     freqMHz = 910.0; break;
        case 8:     freqMHz = 911.0; break;
        case 9:     freqMHz = 912.0; break;
        case 10:    freqMHz = 913.0; break;
        case 11:    freqMHz = 914.0; break;
        case 12:    freqMHz = 915.0; break;
        case 13:    freqMHz = 916.0; break;
        case 14:    freqMHz = 917.0; break;
        case 15:    freqMHz = 918.0; break;
        case 16:    freqMHz = 919.0; break;
        case 17:    freqMHz = 920.0; break;
        case 18:    freqMHz = 921.0; break;
        case 19:    freqMHz = 922.0; break;
        case 20:    freqMHz = 923.0; break;
        case 21:    freqMHz = 924.0; break;
        case 22:    freqMHz = 925.0; break;
        case 23:    freqMHz = 926.0; break;
        case 24:    freqMHz = 927.0; break;
        default:    freqMHz = 915.0; break;
    }

    return freqMHz;
    
}



@end
