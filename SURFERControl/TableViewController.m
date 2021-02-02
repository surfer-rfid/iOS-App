//////////////////////////////////////////////////////////////////////////////////////
//                                                                                  //
//  Module: SURFERControl                                                           //
//                                                                                  //
//  File: TableViewController.m                                                     //
//  Creation date: circa 10/31/2016                                                 //
//  Author: Edward Keehr                                                            //
//                                                                                  //
//    This file was derived from the Nordic Semiconductor example code in their     //
//    nRF UART app. Specifically, this file was derived from "ViewController.m".    //
//    Very little of this file comes from the original Nordic code, although what   //
//    does remain is called out explicitly.                                         //
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
//  This class represents main portion of the application functionality on the iOS  //
//  device.                                                                         //
//                                                                                  //
//////////////////////////////////////////////////////////////////////////////////////

#include <mach/mach.h>
#include <mach/mach_time.h>

#import "TagListViewController.h"
#import "TableViewController.h"
#import "RFIDTagList.h"
#import <math.h>

#pragma mark - Typedef enums of states

//  The connection state.
//  The goal here is to mirror the state of the SURFER MCU firmware and the iOS software.
//  This particular typedef below comes from Nordic Semiconductor.
typedef enum
{
    IDLE = 0,
    SCANNING,
    CONNECTED,
} ConnectionState;

// The application state.
// These states should largely reflect those in the SURFER MCU firmware.

typedef enum
{
    IDLE_UNCONFIGURED   =   0, //Couldn't use IDLE, TX, or RX again
    IDLE_CONFIGURED     =   1,
    INITIALIZING_A      =   2,
    SEARCHING_APP_SPECD =   3,
    SEARCHING_LAST_INV  =   4,
    INVENTORYING        =   5,
    TESTING_DTC         =   6,
    PROG_APP_SPECD      =   7,
    PROG_LAST_INV       =   8,
    RECOV_WVFM_MEM      =   9,
    RESET_ASICS         =   10,
    KILL_TAG            =   11,
    PROG_TAG_KILL_PW    =   12,
    TRACK_APP_SPECD     =   13,
    TRACK_LAST_INV      =   14,
    UNKNOWN             =   15
} AppState;

//This "operation" state reflects the buttons that are enabled and how they are painted.
//In APP_SPECD state, transitions from the buttons SEARCH, PROGRAM, and TRACK will enter states
//in which the iPhone-app-specified EPC is used to singulate tags.
//In LAST_INV state, transitions from the buttons SEARCH, PROGRAM, and TRACK will enter states
//in which the last inventoried EPC is used to singulate tags.
typedef enum
{
    APP_SPECD           =   0,
    LAST_INV            =   1
} OperationState;

//This state reflects the tag data coming in. We need to know if we got supplementary data while we were waiting for it.
typedef enum
{
    WAIT_PKT1           =   0,
    WAIT_PKT2           =   1
} TagDataState;

#pragma mark - Properties and Interfaces

@interface TableViewController ()
@property CBCentralManager *cm;
@property ConnectionState c_state;
@property AppState a_state;
@property OperationState o_state;
@property TagDataState t_state;
@property SURFERPeripheral *currentPeripheral;
@property NSTimer *txTimer;
@property NSTimer *debugTimer; //This timer is used to create fake BTLE tag sends for debugging the app in simulation
@property NSString *rxFilename;

@end

@implementation TableViewController
@dynamic tableView;

//The current peripheral refers to the BLTE connection to the MCU firmware.
@synthesize cm = _cm;
@synthesize currentPeripheral = _currentPeripheral;

#pragma mark - Static Variable Declarations

//These values are static variables representing various 96-bit EPCs of interest.

//This first EPC is for a targeted tag operations.
//The intent is that it can be variable-length to support inventories and tracking of defined tag groups.
//This is why we also need a state variable for the target EPC length.
static uint8_t m_targetEPC[MAX_NUM_BYTES_IN_EPC]    =    {0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF, 0x89, 0xAB, 0xCD, 0xEF};
static uint8_t m_targetEPC_length                   =    MAX_NUM_BYTES_IN_EPC;
//The "new EPC" to be written is for programming tags.
//The only length of this will be MAX_NUM_BYTES_IN_EPC since we don't want to program an incomplete EPC into a tag.
static uint8_t m_thenewEPC[MAX_NUM_BYTES_IN_EPC]     =   {0x01, 0x23, 0x45, 0x67, 0x89, 0xAB, 0xCD, 0xEF, 0x89, 0xAB, 0xCD, 0xEF};

//This is a FIFO for recovering the waveform data from the reader.
static uint8_t m_WaveformDataFifo[3*WAVEFORM_FIFO_SIZE]   =   {0};
//This is the write pointer for the FIFO
static int  m_waveformFifoWP                            =   0;

//This is a FIFO for recovering log messages from the reader.
static uint8_t m_logMessageFifo[LOG_MESSAGE_FIFO_SIZE]  =   {0};
//This is the write pointer for the FIFO.
static int m_logMessageFifoWP                           =   0;

//During the invertory state, we keep track of the number of inventoried tags.
//This number should get reset in between inventory operations.
static uint32_t m_numTagsInventoried                    =   0;

//It looks like we keep track of transmitted packets per connection interval.
//If we recall correctly, each connection interval is on the order of 30ms.
//If we recall correctly, this counter is needed because we can only send 6 packets per connection interval.
static uint8_t m_txPktsPerCnxnIntvl                     =   0;

//We time the inventory for benchmarking purposes.
//Ultimately this time is dictated by the BTLE packet interval rate allowed by Apple.
static uint64_t m_startInventoryTime                    =   0;

//These are state variables for holding tag data in between a 2-packet data push
static NSString *m_currentEpc                           =   @"ABCDEF012345ABCDEF678901";
static uint8_t m_frequencySlot                          =   0;
static int32_t m_antMagI                                =   0;
static int32_t m_antMagQ                                =   0;
static uint8_t m_dataIdOld                              =   0;
static uint8_t m_dataIdNew                              =   0;

#pragma mark - Init, View Loads and Segues

//This function can be thought of as an initialization that occurs when the app starts,
//or if the app has been hidden, put to sleep, then brought into view again.

- (void)viewDidLoad {
    [super viewDidLoad];
    //The comment and line below came from Nordic Semiconductor's ViewController.m file.
    // Do any additional setup after loading the view, typically from a nib.
    self.cm = [[CBCentralManager alloc] initWithDelegate:self queue:nil];

    self.a_state            =   UNKNOWN;
    self.o_state            =   APP_SPECD;
    self.t_state            =   WAIT_PKT1;
    self.rxFilename         =   nil;
    m_numTagsInventoried    =   0;
    m_currentEpc            =   @"ABCDEF012345ABCDEF678901";
    m_frequencySlot         =   0;
    m_antMagI               =   0;
    m_antMagQ               =   0;
    m_dataIdOld             =   255; //Start at 255 so that the first packet is 0
    m_dataIdNew             =   255; //start at 255 so that the first packet is 0
    
    //Load dummy values into EPC state variables in case syncing with the reader doesn't work.
    
    m_targetEPC[0]   =   m_thenewEPC[0]     =   0x01;
    m_targetEPC[1]   =   m_thenewEPC[1]     =   0x23;
    m_targetEPC[2]   =   m_thenewEPC[2]     =   0x45;
    m_targetEPC[3]   =   m_thenewEPC[3]     =   0x67;
    m_targetEPC[4]   =   m_thenewEPC[4]     =   0x89;
    m_targetEPC[5]   =   m_thenewEPC[5]     =   0xAB;
    m_targetEPC[6]   =   m_thenewEPC[6]     =   0xCD;
    m_targetEPC[7]   =   m_thenewEPC[7]     =   0xEF;
    m_targetEPC[8]   =   m_thenewEPC[8]     =   0x89;
    m_targetEPC[9]   =   m_thenewEPC[9]     =   0xAB;
    m_targetEPC[10]  =   m_thenewEPC[10]    =   0xCD;
    m_targetEPC[11]  =   m_thenewEPC[11]    =   0xEF;
    
    m_targetEPC_length  = MAX_NUM_BYTES_IN_EPC;

    //Sync state with the reader
    [_currentPeripheral readStateData];
    [_currentPeripheral readTargetEPCData];
    [_currentPeripheral readNewEPCData];
    
    //This is setting the BTLE packet timer. Experimentation showed us that 30ms is about the correct setting here.
    [self.txTimer invalidate];
    self.txTimer=[NSTimer scheduledTimerWithTimeInterval:0.03 target:self selector:@selector(txTimerFireMethod:) userInfo:nil repeats:YES];
    
    //This is setting the debug timer. We want to send packets about 30s after starting the app
    //FOr now we do not have it repeat.
    [self.debugTimer invalidate];
    //Also for now, we don't have it run. 110920
    //self.debugTimer=[NSTimer scheduledTimerWithTimeInterval:10 target:self selector:@selector(debugTimerFireMethod:) userInfo:nil repeats:NO];
    
    //The line below came from Nordic Semiconductor's ViewController.m file.
    [self addTextToConsole:@"Did start application"];
    
    //Set up various aspects of the application
    [self.tableView setSeparatorStyle:UITableViewCellSeparatorStyleNone];
    [self.tableView setSeparatorColor:[UIColor clearColor]];
    
    [self.targetEPCTextField setDelegate:self];
    [self.targetEPCTextField setKeyboardType:UIKeyboardTypeNamePhonePad]; //In the future, maybe make a custom UIView for a hex keypad.
    [self.thenewEPCTextField setDelegate:self];
    [self.thenewEPCTextField setKeyboardType:UIKeyboardTypeNamePhonePad]; //In the future, maybe make a custom UIView for a hex keypad.
    
    //Use Key-Value-Observing for the three state variable properties.
    //We want to register these properties here because we want the buttons to enable/disable and change color depending on the states.
    [self addObserver:self forKeyPath:@"c_state" options:NSKeyValueObservingOptionNew context:nil];
    [self addObserver:self forKeyPath:@"a_state" options:NSKeyValueObservingOptionNew context:nil];
    [self addObserver:self forKeyPath:@"o_state" options:NSKeyValueObservingOptionNew context:nil];
}

//This code handle the reset case when bringing up the app is handled by viewWillAppear.
//To be honest, it's been a while since we wrote this code so we can't recall at this moment (mid-2019) exactly which cases these are.
- (void)viewWillAppear:(BOOL)animated{
    
    //Do we need [super viewWillAppear]? Try it out when we have a chance.
    
    //self.navigationController.navigationBar.hidden = YES;
    
    //Following code added 083017
    
    self.a_state            =   UNKNOWN;
    self.rxFilename         =   nil;
    m_numTagsInventoried    =   0;
    
    //Above code added 083017
    
    //Load dummy values into EPC state variables in case syncing with the reader doesn't work.
    
    m_targetEPC[0]   =   m_thenewEPC[0]     =   0x01;
    m_targetEPC[1]   =   m_thenewEPC[1]     =   0x23;
    m_targetEPC[2]   =   m_thenewEPC[2]     =   0x45;
    m_targetEPC[3]   =   m_thenewEPC[3]     =   0x67;
    m_targetEPC[4]   =   m_thenewEPC[4]     =   0x89;
    m_targetEPC[5]   =   m_thenewEPC[5]     =   0xAB;
    m_targetEPC[6]   =   m_thenewEPC[6]     =   0xCD;
    m_targetEPC[7]   =   m_thenewEPC[7]     =   0xEF;
    m_targetEPC[8]   =   m_thenewEPC[8]     =   0x89;
    m_targetEPC[9]   =   m_thenewEPC[9]     =   0xAB;
    m_targetEPC[10]  =   m_thenewEPC[10]    =   0xCD;
    m_targetEPC[11]  =   m_thenewEPC[11]    =   0xEF;
    
    m_targetEPC_length  = MAX_NUM_BYTES_IN_EPC;
    
    //Sync state with the reader
    [_currentPeripheral readStateData];
    [_currentPeripheral readTargetEPCData];
    [_currentPeripheral readNewEPCData];
}

- (void)viewWillDisappear:(BOOL)animated{
    [super viewWillDisappear:animated];
    // Move the below commands elsewhere for when the app is shut down
    // May want to consider disabling TX or whatever while selecting other datas in the image picks or directory browser
    
  //  [self.heartbeatTimer invalidate];
  //  self.heartbeatTimer=nil;
  //  self.fileNameToSend=nil;
  //  self.fileDataToSend=nil;
  //  self.heartbeatTimerTXBlock=NO;
  //  self.heartbeatTimerIDLEBlock=NO;
    
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:@"SegueToTagArchive"]){
        UINavigationController *nc=(UINavigationController *)segue.destinationViewController;
        TagListViewController *tlvc=(TagListViewController *)[nc topViewController];
        tlvc.delegate=self;
    }
}

#pragma mark - Timers and Time Mgmt.

//This appears to be a function which returns the time in milliseconds.
uint64_t getTickCount(void)
{
    static mach_timebase_info_data_t sTimebaseInfo;
    uint64_t machTime = mach_absolute_time();
    
    // Convert to nanoseconds - if this is the first time we've run, get the timebase.
    if (sTimebaseInfo.denom == 0 )
    {
        (void) mach_timebase_info(&sTimebaseInfo);
    }
    
    // Convert the mach time to milliseconds
    uint64_t millis = ((machTime / 1000000) * sTimebaseInfo.numer) / sTimebaseInfo.denom;
    return millis;
}

#pragma mark - Button Enable/Disable

//The function below causes all of the buttons to refresh upon a state change.

-(void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context{

    if ([keyPath isEqualToString:@"c_state"] || [keyPath isEqualToString:@"a_state"] || [keyPath isEqualToString:@"o_state"]) {
        NSLog(@"A state variable has been changed. Update buttons");
        [self updateButtons];
    }

}

//This is a function that encapsulates painting and enabling/disabling all buttons in the app.
//Button state depends on the self.a_state, o_state, and c_state.

- (void) updateButtons{
    //We group the buttons into 9 groups.
    //Many of the buttons have unique behaviors and so fit into groups of their own.
    
    //Clear and archive buttons. These are always enabled by the XIB. No need to change them.
    //Connect button. Just responds to changes in c_state.
    
    switch(self.c_state){
        case IDLE:
            [self.connectButton setTitle:@"Connect" forState:UIControlStateNormal];
            break;
        case SCANNING:
            [self.connectButton setTitle:@"Scanning ..." forState:UIControlStateNormal];
            break;
        case CONNECTED:
            [self.connectButton setTitle:@"Disconnect" forState:UIControlStateNormal];
            break;
        default:
            [self.connectButton setTitle:@"Connect" forState:UIControlStateNormal];
            break;
    }
    
    //In case the RFID reader is not connected, we want to grey out and disable most of the
    //other switches. We'll also disable the App Spec'd/Last Inv switch to make things easier, also.
    
    if(self.c_state != CONNECTED){
        //DISABLING
        //Top two rows of buttons
        [self.initializeButton setUserInteractionEnabled:NO];
        [self.testDTCButton setUserInteractionEnabled:NO];
        [self.appSpecdLastInvToggleButton setUserInteractionEnabled:NO];
        [self.resetASICsButton setUserInteractionEnabled:NO];
        [self.recoverWaveformMemoryButton setUserInteractionEnabled:NO];
        
        //Text field buttons
        [self.targetEPCButton setUserInteractionEnabled:NO];
        [self.thenewEPCButton setUserInteractionEnabled:NO];
        
        //Bottom two rows of buttons
        [self.searchButton setUserInteractionEnabled:NO];
        [self.inventoryButton setUserInteractionEnabled:NO];
        [self.programButton setUserInteractionEnabled:NO];
        [self.trackButton setUserInteractionEnabled:NO];
        [self.killTagButton setUserInteractionEnabled:NO];
        [self.programTagKillPWButton setUserInteractionEnabled:NO];
        
        //GREYING OUT DISABLED BUTTONS
        //Top two rows of buttons
        [self.initializeButton setTitleColor:[UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0] forState:UIControlStateNormal];
        [self.testDTCButton setTitleColor:[UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0] forState:UIControlStateNormal];
        [self.resetASICsButton setTitleColor:[UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0] forState:UIControlStateNormal];
        [self.recoverWaveformMemoryButton setTitleColor:[UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0] forState:UIControlStateNormal];
        [self.appSpecdLastInvToggleButton setTitleColor:[UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0] forState:UIControlStateNormal];
        
        //Text field buttons
        [self.targetEPCButton setTitleColor:[UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0] forState:UIControlStateNormal];
        [self.thenewEPCButton setTitleColor:[UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0] forState:UIControlStateNormal];
        
        //Bottom two rows of buttons
        [self.searchButton setTitleColor:[UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0] forState:UIControlStateNormal];
        [self.inventoryButton setTitleColor:[UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0] forState:UIControlStateNormal];
        [self.programButton setTitleColor:[UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0] forState:UIControlStateNormal];
        [self.trackButton setTitleColor:[UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0] forState:UIControlStateNormal];
        [self.killTagButton setTitleColor:[UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0] forState:UIControlStateNormal];
        [self.programTagKillPWButton setTitleColor:[UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0] forState:UIControlStateNormal];
    } else { //In the event we are connected, buttons are in general enabled, except during state operation
        //The first class of button is the Initialize button.
        //We only want this enabled when we are in the IDLE_UNCONFIGURED or UNKNOWN state.
        
        if(self.a_state == IDLE_UNCONFIGURED || self.a_state == UNKNOWN){
            [self.initializeButton setUserInteractionEnabled:YES];
            [self.initializeButton setTitleColor:[UIColor colorWithRed:0/255.0 green:0/255.0 blue:255/255.0 alpha:1.0] forState:UIControlStateNormal];
        } else {
            [self.initializeButton setUserInteractionEnabled:NO];
            [self.initializeButton setTitleColor:[UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0] forState:UIControlStateNormal];
        }
        
        //The second class of button is the Reset button.
        //We only want this on if we are in IDLE_CONFIGURED or one of the sticky states.
        
        if(self.a_state == IDLE_CONFIGURED || self.a_state == IDLE_UNCONFIGURED ||
           self.a_state == TESTING_DTC || self.a_state == TRACK_APP_SPECD || self.a_state == TRACK_LAST_INV){
            
            [self.resetASICsButton setUserInteractionEnabled:YES];
            [self.resetASICsButton setTitleColor:[UIColor colorWithRed:0/255.0 green:0/255.0 blue:255/255.0 alpha:1.0] forState:UIControlStateNormal];
        } else {
            [self.resetASICsButton setUserInteractionEnabled:NO];
            [self.resetASICsButton setTitleColor:[UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0] forState:UIControlStateNormal];
        }
        
        //The third class of button is the DTC button.
        //We only want this on if we are in IDLE_CONFIGURED or TESTING_DTC states.
        
        if(self.a_state == IDLE_CONFIGURED || self.a_state == TESTING_DTC){
             [self.testDTCButton setUserInteractionEnabled:YES];
             [self.testDTCButton setTitleColor:[UIColor colorWithRed:0/255.0 green:0/255.0 blue:255/255.0 alpha:1.0] forState:UIControlStateNormal];
         } else {
             [self.testDTCButton setUserInteractionEnabled:NO];
             [self.testDTCButton setTitleColor:[UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0] forState:UIControlStateNormal];
         }

        //The fourth class of button are the TRACK buttons.
        //We only want these on if we are in IDLE_CONFIGURED or one of the tracking states.
        //In addition, this button changes color based on the operation state (o_state).
        
        if(self.a_state == IDLE_CONFIGURED || self.a_state == TRACK_APP_SPECD || self.a_state == TRACK_LAST_INV){
            [self.trackButton setUserInteractionEnabled:YES];
            if(self.o_state==APP_SPECD){
                [self.trackButton setTitleColor:[UIColor colorWithRed:0/255.0 green:0/255.0 blue:255/255.0 alpha:1.0] forState:UIControlStateNormal];
            } else {
                [self.trackButton setTitleColor:[UIColor colorWithRed:255/255.0 green:0/255.0 blue:0/255.0 alpha:1.0] forState:UIControlStateNormal];
            }
        } else {
            [self.trackButton setUserInteractionEnabled:NO];
            [self.trackButton setTitleColor:[UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0] forState:UIControlStateNormal];
        }
        
        //The final class of buttons are nonsticky action buttons
        //These buttons are only available in the IDLE_CONFIGURED state
        //Some of them do change color and wording based on App Specd/Last Inv button status
        if(self.a_state == IDLE_CONFIGURED){
            //Enable buttons
            [self.appSpecdLastInvToggleButton setUserInteractionEnabled:YES];
            [self.recoverWaveformMemoryButton setUserInteractionEnabled:YES];
            [self.targetEPCButton setUserInteractionEnabled:YES];
            [self.thenewEPCButton setUserInteractionEnabled:YES];
            [self.searchButton setUserInteractionEnabled:YES];
            [self.inventoryButton setUserInteractionEnabled:YES];
            [self.programButton setUserInteractionEnabled:YES];
            [self.killTagButton setUserInteractionEnabled:YES];
            [self.programTagKillPWButton setUserInteractionEnabled:YES];
            
            //Color buttons
            [self.recoverWaveformMemoryButton setTitleColor:[UIColor colorWithRed:0/255.0 green:0/255.0 blue:255/255.0 alpha:1.0] forState:UIControlStateNormal];
            [self.targetEPCButton setTitleColor:[UIColor colorWithRed:0/255.0 green:0/255.0 blue:255/255.0 alpha:1.0] forState:UIControlStateNormal];
            [self.thenewEPCButton setTitleColor:[UIColor colorWithRed:0/255.0 green:0/255.0 blue:255/255.0 alpha:1.0] forState:UIControlStateNormal];
            [self.killTagButton setTitleColor:[UIColor colorWithRed:0/255.0 green:0/255.0 blue:255/255.0 alpha:1.0] forState:UIControlStateNormal];
            [self.programTagKillPWButton setTitleColor:[UIColor colorWithRed:0/255.0 green:0/255.0 blue:255/255.0 alpha:1.0] forState:UIControlStateNormal];
            
            if(self.o_state==APP_SPECD){
                [self.appSpecdLastInvToggleButton setTitle:@"App Spec'd." forState:UIControlStateNormal];
                [self.appSpecdLastInvToggleButton setTitleColor:[UIColor colorWithRed:0/255.0 green:0/255.0 blue:255/255.0 alpha:1.0] forState:UIControlStateNormal];
                [self.searchButton setTitleColor:[UIColor colorWithRed:0/255.0 green:0/255.0 blue:255/255.0 alpha:1.0] forState:UIControlStateNormal];
                [self.inventoryButton setTitleColor:[UIColor colorWithRed:0/255.0 green:0/255.0 blue:255/255.0 alpha:1.0] forState:UIControlStateNormal];
                [self.programButton setTitleColor:[UIColor colorWithRed:0/255.0 green:0/255.0 blue:255/255.0 alpha:1.0] forState:UIControlStateNormal];
            } else {
                [self.appSpecdLastInvToggleButton setTitle:@"Last Inv'd." forState:UIControlStateNormal];
                [self.appSpecdLastInvToggleButton setTitleColor:[UIColor colorWithRed:255/255.0 green:0/255.0 blue:0/255.0 alpha:1.0] forState:UIControlStateNormal];
                [self.searchButton setTitleColor:[UIColor colorWithRed:255/255.0 green:0/255.0 blue:0/255.0 alpha:1.0] forState:UIControlStateNormal];
                [self.inventoryButton setTitleColor:[UIColor colorWithRed:255/255.0 green:0/255.0 blue:0/255.0 alpha:1.0] forState:UIControlStateNormal];
                [self.programButton setTitleColor:[UIColor colorWithRed:255/255.0 green:0/255.0 blue:0/255.0 alpha:1.0] forState:UIControlStateNormal];
            }
            
        } else {
            //DISABLING
            //Top two rows of buttons
            [self.appSpecdLastInvToggleButton setUserInteractionEnabled:NO];
            [self.recoverWaveformMemoryButton setUserInteractionEnabled:NO];
            
            //Text field buttons
            [self.targetEPCButton setUserInteractionEnabled:NO];
            [self.thenewEPCButton setUserInteractionEnabled:NO];
            
            //Bottom two rows of buttons
            [self.searchButton setUserInteractionEnabled:NO];
            [self.inventoryButton setUserInteractionEnabled:NO];
            [self.programButton setUserInteractionEnabled:NO];
            [self.killTagButton setUserInteractionEnabled:NO];
            [self.programTagKillPWButton setUserInteractionEnabled:NO];
            
            //GREYING OUT DISABLED BUTTONS
            //Top two rows of buttons
            [self.recoverWaveformMemoryButton setTitleColor:[UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0] forState:UIControlStateNormal];
            [self.appSpecdLastInvToggleButton setTitleColor:[UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0] forState:UIControlStateNormal];
            
            //Text field buttons
            [self.targetEPCButton setTitleColor:[UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0] forState:UIControlStateNormal];
            [self.thenewEPCButton setTitleColor:[UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0] forState:UIControlStateNormal];
            
            //Bottom two rows of buttons
            [self.searchButton setTitleColor:[UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0] forState:UIControlStateNormal];
            [self.inventoryButton setTitleColor:[UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0] forState:UIControlStateNormal];
            [self.programButton setTitleColor:[UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0] forState:UIControlStateNormal];
            [self.killTagButton setTitleColor:[UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0] forState:UIControlStateNormal];
            [self.programTagKillPWButton setTitleColor:[UIColor colorWithRed:128/255.0 green:128/255.0 blue:128/255.0 alpha:1.0] forState:UIControlStateNormal];
        }
    }
}

#pragma mark - Text Field Management

//This code causes the textfield to close the keypad after return has been pressed
- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

//This code updates the EPC-to-be-sent state variables after their respective text fields have received entries.
//Only one byte is updated in each case.
- (BOOL)textFieldShouldEndEditing:(UITextField *)textField{
    uint8_t     temp_2x_length          =   0;
    uint8_t     temp_byte               =   0;
    NSString    *EPCText          =   textField.text;
    const char  *EPCchars         =   [EPCText UTF8String]; //Get a null-terminated version of the string, like in C.
    
    //In the case where no EPC is written, text will be blank and length will be zero.
    //This is a special case in which we wish to pull data from the reader again.
    //In the event reading back from the reader barfs, we will keep the text blank and length zero.
    //This mirrors set_sfw_specd_target_epc in MCU firmware.
    
    //We can get up to 24 characters that will be placed into 12 bytes.
    //For each byte, examine up to 2 possible characters
    //For an incomplete byte, the final character will be zero.
    
    //First, we wipe the state variable to ensure nothing weird happens if there is a bug elsewhere in the code.
    
    for(int loop_tfsee=0; loop_tfsee < MAX_NUM_BYTES_IN_EPC; loop_tfsee++){
        if(textField==self.targetEPCTextField){
            m_targetEPC[loop_tfsee]=0;
        } else {
             m_thenewEPC[loop_tfsee]=0;
        }
    }
    
    for(int loop_tfsee=0; loop_tfsee < 2*MAX_NUM_BYTES_IN_EPC; loop_tfsee++){ //Go through each byte
        if(EPCchars[loop_tfsee]==0){break;} //If we hit the end of the string early, bail from the for loop.
        
        temp_2x_length++;   //We got something that we'll add to the EPC, so let's increment the length.
        
        if(isalpha(EPCchars[loop_tfsee])){ //If the character is a letter
            //Then convert it to an uppercase letter, cast it to uint8_t, then convert to an equivalent hex value. Mask with a nibble.
            temp_byte   =   (uint8_t)toupper(EPCchars[loop_tfsee]+10-'A') & 15;
        }
        else if(isdigit(EPCchars[loop_tfsee])){ //If the character is a digit
            //Then convert the digit to its uint8_t equivalent. Mask with a nibble.
            temp_byte   =   (uint8_t)(EPCchars[loop_tfsee]-'0') & 15;
        }
        else{
            //If we get something weird, sanitize it to a zero.
            temp_byte   =   0;
        }
        
        if(textField==self.targetEPCTextField && ((loop_tfsee % 2) == 0)){ //Assuming we are on the first nibble of a byte
            m_targetEPC[loop_tfsee >> 1] = temp_byte << 4; //Push that nibble into the MSB of the byte and set the LSB to zero.
        }
        else if(textField==self.targetEPCTextField && ((loop_tfsee % 2) != 0)){
            m_targetEPC[loop_tfsee >> 1] |= temp_byte << 0; //Merge the current nibble into the LSB of the byte.
        }
        else if(textField!=self.targetEPCTextField && ((loop_tfsee % 2) == 0)){ //Assuming we are on the first nibble of a byte
            m_thenewEPC[loop_tfsee >> 1] = temp_byte << 4; //Push that nibble into the MSB of the byte and set the LSB to zero.
        }
        else if(textField!=self.targetEPCTextField && ((loop_tfsee % 2) != 0)){
            m_thenewEPC[loop_tfsee >> 1] |= temp_byte << 0; //Merge the current nibble into the LSB of the byte.
        }
        
    }
    
    //But wait, we still need to display an EPC in the window.
    //Since the EPC state variable is sanitized, we reuse the code from the peripheral EPC readback.
    
    NSMutableString *hex = [NSMutableString string];
    
    if(textField==self.targetEPCTextField){
        
        m_targetEPC_length = ((temp_2x_length+1) >> 1); //How far we've counted (plus rounding up) is how long the EPC is.
        
        for (int loop_tfsee=0; loop_tfsee < m_targetEPC_length; loop_tfsee++){
            [hex appendFormat:@"%02X" , (*(m_targetEPC+loop_tfsee) & 0x00FF)];
        }
        self.targetEPCTextField.text=hex;
        self.targetEPCTextField.textColor=[UIColor redColor]; //Color text red until reply provided by reader.
        
        //If a zero-length EPC is entered, that's OK. This means that no masking operations will be performed
        //during search, inventory, etc.
        
    } else {
        for (int loop_tfsee=0; loop_tfsee < MAX_NUM_BYTES_IN_EPC; loop_tfsee++){
            [hex appendFormat:@"%02X" , (*(m_thenewEPC+loop_tfsee) & 0x00FF)];
        }
        self.thenewEPCTextField.text=hex;
        self.thenewEPCTextField.textColor=[UIColor redColor]; //Color text red until reply provided by reader.
        
        //Recall that if an EPC was entered without the full 12 bytes (24 characters), it will be zero padded.
    }
        
    return true;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string {
    // Prevent crashing undo bug – see note below.
    if(range.length + range.location > textField.text.length){
        return NO;
    }
    
    NSUInteger newLength = [textField.text length] + [string length] - range.length;
    return newLength <= 2*MAX_NUM_BYTES_IN_EPC;
}

#pragma mark - View Button Press Handlers

//This section handles state transitions and state variable updates in response to app button presses.

//Scan to connect for the reader.
//The function below came from Nordic Semiconductor's ViewController.m file.
- (IBAction)connectButtonPressed:(id)sender
{
    
    switch (self.c_state) {
        case IDLE:
            self.c_state = SCANNING;
            
            NSLog(@"Started scan ...");
            [self.cm scanForPeripheralsWithServices:@[SURFERPeripheral.surferServiceUUID] options:@{CBCentralManagerScanOptionAllowDuplicatesKey: [NSNumber numberWithBool:NO]}];
            break;
            
        case SCANNING:
            self.c_state = IDLE;
            
            NSLog(@"Stopped scan");
            [self.cm stopScan];
            break;
            
        case CONNECTED:
            NSLog(@"Disconnect peripheral %@", self.currentPeripheral.peripheral.name);
            [self.cm cancelPeripheralConnection:self.currentPeripheral.peripheral];
            break;
    }
}

- (IBAction)targetEPCButtonTouched:(id)sender {
    if(self.a_state==IDLE_CONFIGURED){
     
        [_currentPeripheral writeTargetEPCData: [[NSData alloc] initWithBytes:&m_targetEPC length:m_targetEPC_length]];
        NSLog(@"Yes you actually sent a target epc");
        //[_currentPeripheral readTargetEPCData];
    }
}

- (IBAction)thenewEPCButtonTouched:(id)sender{
    if(self.a_state==IDLE_CONFIGURED){
        
        [_currentPeripheral writeNewEPCData: [[NSData alloc] initWithBytes:&m_thenewEPC length:MAX_NUM_BYTES_IN_EPC]];
        NSLog(@"Yes you actually sent a new epc");
        //[_currentPeripheral readNewEPCData];
    }
}

- (IBAction)initializeButtonPressed:(id)sender {
    
    NSLog(@"Yes you pressed the initialize button");
    
    if(self.a_state==IDLE_UNCONFIGURED || self.a_state==UNKNOWN){
        uint8_t byteToSend  =   (uint8_t)INITIALIZING_A;
        
        [_currentPeripheral writeStateData: [[NSData alloc] initWithBytes:&byteToSend length:1]];
        NSLog(@"Yes you actually sent an initalize");
    }
    
}

- (IBAction)searchButtonPressed:(id)sender {

    if(self.a_state==IDLE_CONFIGURED && self.o_state==APP_SPECD){
        uint8_t byteToSend  =   (uint8_t)SEARCHING_APP_SPECD;
        
        [_currentPeripheral writeStateData: [[NSData alloc] initWithBytes:&byteToSend length:1]];
    } else if(self.a_state==IDLE_CONFIGURED && self.o_state==LAST_INV){
        uint8_t byteToSend  =   (uint8_t)SEARCHING_LAST_INV;
        
        [_currentPeripheral writeStateData: [[NSData alloc] initWithBytes:&byteToSend length:1]];
    }
    
}

- (IBAction)inventoryButtonPressed:(id)sender{
    
    if(self.a_state==IDLE_CONFIGURED){
        uint8_t byteToSend  =   (uint8_t)INVENTORYING;
        
        [_currentPeripheral writeStateData: [[NSData alloc] initWithBytes:&byteToSend length:1]];
    }
    
}

- (IBAction)testDTCButtonPressed:(id)sender{
    
    if(self.a_state==IDLE_CONFIGURED || self.a_state==TESTING_DTC){
        uint8_t byteToSend  =   (uint8_t)TESTING_DTC;
        
        [_currentPeripheral writeStateData: [[NSData alloc] initWithBytes:&byteToSend length:1]];
    }
    
}

- (IBAction)appSpecdLastInvToggleButtonPressed:(id)sender{
    
    if(self.a_state==IDLE_CONFIGURED && self.o_state == APP_SPECD){
        self.o_state = LAST_INV;
    } else if(self.a_state==IDLE_CONFIGURED && self.o_state == LAST_INV){
        self.o_state = APP_SPECD;
    }
    
}

- (IBAction)programButtonPressed:(id)sender{
    
    if(self.a_state==IDLE_CONFIGURED && self.o_state==APP_SPECD){
        uint8_t byteToSend  =   (uint8_t)PROG_APP_SPECD;
        
        [_currentPeripheral writeStateData: [[NSData alloc] initWithBytes:&byteToSend length:1]];
    } else if(self.a_state==IDLE_CONFIGURED && self.o_state==LAST_INV){
        uint8_t byteToSend  =   (uint8_t)PROG_LAST_INV;
        
        [_currentPeripheral writeStateData: [[NSData alloc] initWithBytes:&byteToSend length:1]];
    }
    
}

- (IBAction)trackButtonPressed:(id)sender{
    
    if((self.a_state==IDLE_CONFIGURED && self.o_state==APP_SPECD) || self.a_state==TRACK_APP_SPECD){
        uint8_t byteToSend  =   (uint8_t)TRACK_APP_SPECD;
        
        [_currentPeripheral writeStateData: [[NSData alloc] initWithBytes:&byteToSend length:1]];
    } else if((self.a_state==IDLE_CONFIGURED && self.o_state==LAST_INV) || self.a_state==TRACK_LAST_INV){
        uint8_t byteToSend  =   (uint8_t)TRACK_LAST_INV;
        
        [_currentPeripheral writeStateData: [[NSData alloc] initWithBytes:&byteToSend length:1]];
    }
    
}

- (IBAction)killTagButtonPressed:(id)sender{
    
    if(self.a_state==IDLE_CONFIGURED){
        uint8_t byteToSend  =   (uint8_t)KILL_TAG;
        
        [_currentPeripheral writeStateData: [[NSData alloc] initWithBytes:&byteToSend length:1]];
    }
    
}

- (IBAction)programTagKillPWButtonPressed:(id)sender{
    
    if(self.a_state==IDLE_CONFIGURED){
        uint8_t byteToSend  =   (uint8_t)PROG_TAG_KILL_PW;
        
        [_currentPeripheral writeStateData: [[NSData alloc] initWithBytes:&byteToSend length:1]];
    }
    
}

- (IBAction)recoverWaveformMemoryButtonPressed:(id)sender{
    
    if(self.a_state==IDLE_CONFIGURED){
        uint8_t byteToSend  =   (uint8_t)RECOV_WVFM_MEM;
        
        [_currentPeripheral writeStateData: [[NSData alloc] initWithBytes:&byteToSend length:1]];
    }
    
}


- (IBAction)resetASICsButtonPressed:(id)sender {
    if(self.a_state == IDLE_CONFIGURED || self.a_state == IDLE_UNCONFIGURED ||
       self.a_state == TESTING_DTC || self.a_state == TRACK_APP_SPECD || self.a_state == TRACK_LAST_INV){
        uint8_t byteToSend  =   (uint8_t)RESET_ASICS;
        
        [_currentPeripheral writeStateData: [[NSData alloc] initWithBytes:&byteToSend length:1]];
        NSLog(@"Yes you actually sent a reset");
    }
}

#pragma mark - BTLE EPC Readback

//This section contains handlers related to the MCU pushing data back over chactreristics.

- (void) didReceiveTargetEPCData:(NSData *)data
{
    int dataLength = (int)[data length]; //assume length < buffer size for the time being
    uint8_t *dataBuf=malloc(dataLength * sizeof(uint8_t));
    [data getBytes:dataBuf length:dataLength];
    
    NSLog(@"Did in fact receive target epc data");
    
    m_targetEPC_length = MIN(dataLength,MAX_NUM_BYTES_IN_EPC);
    
    for (int loop_tfsee=0; loop_tfsee<m_targetEPC_length; loop_tfsee++){
        m_targetEPC[loop_tfsee]=dataBuf[loop_tfsee];
    }
    
    //Also update the display
    //121720 - If we get a blank EPC sent back, make this clear by printing "Empty EPC" instead of showing nothing in the field
    NSMutableString *hex = [NSMutableString string];
    
    if(m_targetEPC_length != 0){
        for (int loop_tfsee=0; loop_tfsee<m_targetEPC_length; loop_tfsee++){
            [hex appendFormat:@"%02X" , (*(m_targetEPC+loop_tfsee) & 0x00FF)];
        }
    } else {
        [hex appendFormat:@"Empty EPC"];
    }

    
    self.targetEPCTextField.text=hex;
    self.targetEPCTextField.textColor=[UIColor greenColor]; //Color text green with reply provided by reader.
}

- (void) didReceiveNewEPCData:(NSData *)data
{
    //For now, we are going to rely on the RFID reader peripheral to send back 12 bytes here.
    //If it does not, we're going to get a weird bug that should be visible in the text field.
    
    bool localEPCFix = FALSE;
    int dataLength = (int)[data length]; //assume length < buffer size for the time being
    uint8_t *dataBuf=malloc(dataLength * sizeof(uint8_t));
    [data getBytes:dataBuf length:dataLength];
    
    NSLog(@"Did in fact receive new epc data");
    
    for (int loop_tfsee=0; loop_tfsee<MIN(dataLength,MAX_NUM_BYTES_IN_EPC); loop_tfsee++){
        m_thenewEPC[loop_tfsee]=dataBuf[loop_tfsee];
    }
    //In case we get a bogus EPC sent back with less than 12 data bytes, tack on zeros at the end.
    
    for (int loop_tfsee=dataLength; loop_tfsee<MAX_NUM_BYTES_IN_EPC; loop_tfsee++){
        localEPCFix = TRUE;
        m_thenewEPC[loop_tfsee]=0x00;
    }
    
    //Also update the display
    NSMutableString *hex = [NSMutableString string];
    for (int loop_tfsee=0; loop_tfsee<MAX_NUM_BYTES_IN_EPC; loop_tfsee++){
        [hex appendFormat:@"%02X" , (*(m_thenewEPC+loop_tfsee) & 0x00FF)];
    }
    
    self.thenewEPCTextField.text=hex;
    if(localEPCFix == FALSE){
        self.thenewEPCTextField.textColor=[UIColor greenColor]; //Color text green with reply provided by reader.
    } else {
        self.thenewEPCTextField.textColor=[UIColor orangeColor]; //Color text green with reply provided by reader.
    }
}

#pragma mark - BTLE State Readback

//In addition to receiving state data from the reader, this function synchronizes state changes in the reader
//with state changes in the iOS app.
- (void) didReceiveReadStateData:(NSData *)data
{
    int dataLength = (int)[data length];
    uint64_t        elapsedInventoryTime =  0;
    NSData          *waveformDataAsObject;
    NSDateFormatter *formatter;
    NSString        *dateString;
    NSArray         *paths;
    NSString        *documentsDirectory;
    NSString        *fileName;
    NSString        *FilePath;
    uint8_t         *peripheral_state;
    
    if(dataLength != 1){
        [self addTextToConsole:[NSString stringWithFormat:@"Error: Got a receive state data with the wrong number of bytes"]];
        return;
    }
    
    peripheral_state    =   malloc(sizeof(uint8_t));
    [data getBytes:peripheral_state length:dataLength];
    
    //Run the state machine governing operation of the SURFER app
    
    [self addTextToConsole:[NSString stringWithFormat:@"Got a receive state data with state %d",*peripheral_state]];
    
    switch(self.a_state){
        case IDLE_UNCONFIGURED:
            switch(*peripheral_state){
                case(INITIALIZING_A):
                    self.a_state=INITIALIZING_A;
                    break;
                case(RESET_ASICS):
                    self.a_state=RESET_ASICS;
                    break;
                case(IDLE_UNCONFIGURED):
                    self.a_state=IDLE_UNCONFIGURED;
                    break;
                default:
                    [self addTextToConsole:[NSString stringWithFormat:@"Error: illegal state transition from IDLE_UNCONFIGURED detected"]];
                    self.a_state=*peripheral_state; //Go there anyway so we don't lock up our app.
                    break;
            }
            break;
        case(IDLE_CONFIGURED):
            switch(*peripheral_state){
                case(IDLE_CONFIGURED):
                    self.a_state=IDLE_CONFIGURED;
                    break;
                case(INITIALIZING_A):
                    self.a_state=INITIALIZING_A;
                    break;
                case(SEARCHING_APP_SPECD):
                    self.a_state=SEARCHING_APP_SPECD;
                    break;
                case(SEARCHING_LAST_INV):
                    self.a_state=SEARCHING_LAST_INV;
                    break;
                case(INVENTORYING):
                    m_startInventoryTime =   getTickCount();
                    self.a_state=INVENTORYING;
                    break;
                case(TESTING_DTC):
                    self.a_state=TESTING_DTC;
                    break;
                case(PROG_APP_SPECD):
                    self.a_state=PROG_APP_SPECD;
                    break;
                case(PROG_LAST_INV):
                    self.a_state=PROG_LAST_INV;
                    break;
                case(RECOV_WVFM_MEM):
                    self.a_state=RECOV_WVFM_MEM;
                    break;
                case(RESET_ASICS):
                    self.a_state=RESET_ASICS;
                    break;
                case(KILL_TAG):
                    self.a_state=KILL_TAG;
                    break;
                case(PROG_TAG_KILL_PW):
                    self.a_state=PROG_TAG_KILL_PW;
                    break;
                case(TRACK_APP_SPECD):
                    self.a_state=TRACK_APP_SPECD;
                    break;
                case(TRACK_LAST_INV):
                    self.a_state=TRACK_LAST_INV;
                    break;
                default:
                    [self addTextToConsole:[NSString stringWithFormat:@"Error: illegal state transition from IDLE_CONFIGURED detected"]];
                    self.a_state=*peripheral_state; //Go there anyway so we don't lock up our app.
                    break;
            }
            break;
        case(INITIALIZING_A):
            switch(*peripheral_state){
                case(IDLE_CONFIGURED):
                    self.a_state=IDLE_CONFIGURED;
                    break;
                case(IDLE_UNCONFIGURED):
                    self.a_state=IDLE_UNCONFIGURED;
                    break;
                default:
                    [self addTextToConsole:[NSString stringWithFormat:@"Error: illegal state transition from INITIALIZING detected"]];
                    self.a_state=*peripheral_state; //Go there anyway so we don't lock up our app.
                    break;
            }
            break;
        case(SEARCHING_APP_SPECD):
        case(SEARCHING_LAST_INV):
            switch(*peripheral_state){
                case(IDLE_CONFIGURED):
                    self.a_state=IDLE_CONFIGURED;
                    break;
                default:
                    [self addTextToConsole:[NSString stringWithFormat:@"Error: illegal state transition from SEARCHING detected"]];
                    self.a_state=*peripheral_state; //Go there anyway so we don't lock up our app.
                    break;
            }
            break;
        case(INVENTORYING):
            switch(*peripheral_state){
                case(IDLE_CONFIGURED):
                    elapsedInventoryTime = (getTickCount()-m_startInventoryTime)/1000;
                    [self addTextToConsole:[NSString stringWithFormat:@"Inventory over: counted %d tags in %llu seconds",m_numTagsInventoried,elapsedInventoryTime]];
                    m_numTagsInventoried=0;
                    self.a_state=IDLE_CONFIGURED;
                    break;
                default:
                    [self addTextToConsole:[NSString stringWithFormat:@"Error: illegal state transition from INVENTORYING detected"]];
                    self.a_state=*peripheral_state; //Go there anyway so we don't lock up our app.
                    break;
            }
            break;
        case(TESTING_DTC):
            switch(*peripheral_state){
                case(IDLE_CONFIGURED):
                    self.a_state=IDLE_CONFIGURED;
                    break;
                case(TESTING_DTC):
                    self.a_state=TESTING_DTC;
                    break;
                case(RESET_ASICS):
                    self.a_state=RESET_ASICS;
                    break;
                default:
                    [self addTextToConsole:[NSString stringWithFormat:@"Error: illegal state transition from TESTING_DTC detected"]];
                    self.a_state=*peripheral_state; //Go there anyway so we don't lock up our app.
                    break;
            }
            break;
        case(PROG_APP_SPECD):
        case(PROG_LAST_INV):
            switch(*peripheral_state){
                case(IDLE_CONFIGURED):
                    self.a_state=IDLE_CONFIGURED;
                    break;
                default:
                    [self addTextToConsole:[NSString stringWithFormat:@"Error: illegal state transition from PROGRAMMING detected"]];
                    self.a_state=*peripheral_state; //Go there anyway so we don't lock up our app.
                    break;
            }
            break;
        case(RECOV_WVFM_MEM):
            switch(*peripheral_state){
                case(IDLE_CONFIGURED):
                    //Dump fifo to file and reset the fifo pointer
                    waveformDataAsObject    = [NSData dataWithBytes:m_WaveformDataFifo length:3*m_waveformFifoWP];
                    // and then you can…
                    formatter               = [[NSDateFormatter alloc] init];
                    [formatter setDateFormat:@"MM-dd-yyyy-HH-mm"];
                    dateString              = [formatter stringFromDate:[NSDate date]];
                    
                    paths                   = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
                    documentsDirectory      = [paths objectAtIndex:0];
                    fileName                = [NSString stringWithFormat:@"waveform%@.txt",dateString];
                    FilePath                = [documentsDirectory stringByAppendingPathComponent:fileName];
                    
                    [waveformDataAsObject writeToFile:FilePath atomically:YES];
                    
                    m_waveformFifoWP    =   0;
                    self.a_state=IDLE_CONFIGURED;
                    break;
                default:
                    [self addTextToConsole:[NSString stringWithFormat:@"Error: illegal state transition from RECOV_WVFM_MEM detected"]];
                    self.a_state=*peripheral_state; //Go there anyway so we don't lock up our app.
                    break;
            }
            break;
        case(RESET_ASICS):
            switch(*peripheral_state){
                case(IDLE_UNCONFIGURED):
                    self.a_state=IDLE_UNCONFIGURED;
                    break;
                default:
                    [self addTextToConsole:[NSString stringWithFormat:@"Error: illegal state transition from RESET_ASICS detected"]];
                    self.a_state=*peripheral_state; //Go there anyway so we don't lock up our app.
                    break;
            }
            break;
        case(KILL_TAG):
            switch(*peripheral_state){
                case(IDLE_CONFIGURED):
                    self.a_state=IDLE_CONFIGURED;
                    break;
                default:
                    [self addTextToConsole:[NSString stringWithFormat:@"Error: illegal state transition from KILL_TAG detected"]];
                    self.a_state=*peripheral_state; //Go there anyway so we don't lock up our app.
                    break;
            }
            break;
        case(PROG_TAG_KILL_PW):
            switch(*peripheral_state){
                case(IDLE_CONFIGURED):
                    self.a_state=IDLE_CONFIGURED;
                    break;
                default:
                    [self addTextToConsole:[NSString stringWithFormat:@"Error: illegal state transition from PROG_TAG_KILL_PW detected"]];
                    self.a_state=*peripheral_state; //Go there anyway so we don't lock up our app.
                    break;
            }
            break;
        case(TRACK_APP_SPECD):
            switch(*peripheral_state){
                case(IDLE_CONFIGURED):
                    self.a_state=IDLE_CONFIGURED;
                    break;
                case(TRACK_APP_SPECD):
                    self.a_state=TRACK_APP_SPECD;
                    break;
                case(RESET_ASICS):
                    self.a_state=RESET_ASICS;
                    break;
                default:
                    [self addTextToConsole:[NSString stringWithFormat:@"Error: illegal state transition from TRACK_APP_SPECD detected"]];
                    self.a_state=*peripheral_state; //Go there anyway so we don't lock up our app.
                    break;
            }
            break;
        case(TRACK_LAST_INV):
            switch(*peripheral_state){
                case(IDLE_CONFIGURED):
                    self.a_state=IDLE_CONFIGURED;
                    break;
                case(TRACK_LAST_INV):
                    self.a_state=TRACK_LAST_INV;
                    break;
                case(RESET_ASICS):
                    self.a_state=RESET_ASICS;
                    break;
                default:
                    [self addTextToConsole:[NSString stringWithFormat:@"Error: illegal state transition from TRACK_LAST_INV detected"]];
                    self.a_state=*peripheral_state; //Go there anyway so we don't lock up our app.
                    break;
            }
            break;
        case(UNKNOWN):
            [self addTextToConsole:[NSString stringWithFormat:@"Exiting Unknown State"]];
            switch(*peripheral_state){
                case(IDLE_UNCONFIGURED):
                    self.a_state=IDLE_UNCONFIGURED;
                    break;
                case(IDLE_CONFIGURED):
                    self.a_state=IDLE_CONFIGURED;
                    break;
                case(TESTING_DTC):
                    self.a_state=TESTING_DTC;
                    break;
                case(TRACK_APP_SPECD):
                    self.a_state=TRACK_APP_SPECD;
                    break;
                case(TRACK_LAST_INV):
                    self.a_state=TRACK_LAST_INV;
                    break;
                case(INITIALIZING_A):
                    self.a_state=INITIALIZING_A; //111020 - We include this here since typically when we start up the reader and app,
                    //This is the first state transition from UNKNOWN. Since this is expected behavior, we don't flag it.
                    break;
                default:
                    [self addTextToConsole:[NSString stringWithFormat:@"Error: unusual state transition from UNKNOWN detected"]];
                    self.a_state=*peripheral_state; //Go there anyway so we don't lock up our app.
                    break;
                }
            break;
        default: break;
    }
}

#pragma mark - BTLE Tag Data Handlers

//When we read a tag either in search or inventory, the reader pushes data back over a BTLE indication.
//The first data back is the EPC, the exit code, and the RFID operation number.
- (void) didReceivePacketData1Data:(NSData *)data
{
    int dataLength = (int)[data length]; //assume length < buffer size for the time being
    
    if(dataLength != NUM_PCKT1_DATA_BYTES) {
        [self addTextToConsole:[NSString stringWithFormat:@"Received Data 1 but wrong # bytes"]];
        return;
    }
    else {
            
        if(self.a_state==INVENTORYING){
            m_numTagsInventoried++; //If we are doing an inventory, let's count up the number of tags we are inventorying.
        }
        
        uint8_t *dataBuf=malloc(dataLength * sizeof(uint8_t));
        [data getBytes:dataBuf length:dataLength];
        
        //Unpack the data from the packet
        
        m_currentEpc = [NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
        dataBuf[0], dataBuf[1], dataBuf[2], dataBuf[3], dataBuf[4], dataBuf[5],
        dataBuf[6], dataBuf[7], dataBuf[8], dataBuf[9], dataBuf[10], dataBuf[11]];
        
        BOOL expectingSupplementData = (dataBuf[12] & 128) != 0; //Supplement data indicator is contained in the msb of this byte
        m_frequencySlot = dataBuf[12] & 31; //Mask off the lower 5 bits - frequencySlot can only go up to 31.
        m_antMagI = (int32_t)(((uint32_t)dataBuf[13] << 24)+((uint32_t)dataBuf[14] << 16)+((uint32_t)dataBuf[15] << 8));
        m_antMagQ = (int32_t)(((uint32_t)dataBuf[16] << 24)+((uint32_t)dataBuf[17] << 16)+((uint32_t)dataBuf[18] << 8));
        m_dataIdOld=m_dataIdNew;
        m_dataIdNew=dataBuf[19]; //A nonce that we can use if we get packets out of order
        
        if(m_dataIdNew != ((m_dataIdOld+1) % 256)){
            [self addTextToConsole:[NSString stringWithFormat:@"Got data packets out of order. May be due to reader reset."]];
        }
        
        switch(self.t_state){
            case WAIT_PKT2:
                //Uh-oh, we were waiting for PKT2 but got a packet 1? Disregard the previous packet 1 and proceed as normal.
                //Do make a note of the incident in the console, however.
                [self addTextToConsole:[NSString stringWithFormat:@"Got PKT1 while expecting PKT2."]];
              
            case WAIT_PKT1:
                
                if(!expectingSupplementData){
                    
                    //If we're not expecting supplemental data, write the tag data to the tag list now
                    //If we're not doing supplemental tag data, we're only doing hops (no PDOA)
                    //If we're not doing supplemental data, we don't have cal data.
                    
                    //BELOW IS A METHOD - MUST SEND TO THE RIGHT OBJECT
                    [[RFIDTagList theOnlyRFIDTagList] saveTagWithEPC: m_currentEpc
                                                        withFreqSlot: m_frequencySlot
                                                      withHopNotSkip: TRUE
                                                    withHopSkipNonce: 128
                                                    //We put a dummy value in here that is unlikely to result in an unflagged scenario in which
                                                    //a non-supplement hop read is combined with a supplement skip read to result in
                                                    //a valid-seeming ranging measurement. (Recall hop and skip nonce must be same to
                                                    //produce a valid range measurement).
                                                    //Also with CalMag=0, attempting to make any ranging measurement with this
                                                    //information should result in an error (99.9m being displayed).
                                                         withAntMagI: m_antMagI
                                                         withAntMagQ: m_antMagQ
                                                         withCalMagI: 0
                                                         withCalMagQ: 0];
                    self.t_state=WAIT_PKT1;
                } else {
                    //If we are expecting supplemental data, then wait until the next packet to send it to the iDevice.
                    self.t_state=WAIT_PKT2;
                }
                
                break;
                
            default:
                [self addTextToConsole:[NSString stringWithFormat:@"Got unknown packet state"]];
                break;
                
        }
        
    }
}

//When we read a tag either in search or inventory, the reader pushes data back over a BTLE indication.
//The second data back is the I and Q magnitude data.
//Note that this data is sent as the "main" and "alt" data, which correpond to I and Q respectively only when the MCU formware sets
//the "use_i" flag.
//In the future, we will need to sync up the use_i flag in iOS software so that we can accurately
//report I and Q data to higher-level software.

- (void) didReceivePacketData2Data:(NSData *)data
{
    int dataLength = (int)[data length]; //assume length < buffer size for the time being
    
    if(dataLength != NUM_PCKT2_DATA_BYTES) {
        [self addTextToConsole:[NSString stringWithFormat:@"Received Data 2 but wrong # bytes"]];
        return;
    } else {
        uint8_t *dataBuf=malloc(dataLength * sizeof(uint8_t));
        [data getBytes:dataBuf length:dataLength];
        
        //Unpack the data from the packet.
        //Bytes 1 and 2 are acutally the LSB of the antenna magI and magQ
        
        //Don't add LSB for now. Actually this turned out not to really matter so try to add in when possible.
        m_antMagI += (uint32_t)dataBuf[1];
        m_antMagQ += (uint32_t)dataBuf[2];
        //Next, get the calibration magI and magQ
        int32_t calMagI = (int32_t)(((uint32_t)dataBuf[4] << 24)+((uint32_t)dataBuf[5] << 16)+((uint32_t)dataBuf[6] << 8)+((uint32_t)dataBuf[7] << 0));
        int32_t calMagQ = (int32_t)(((uint32_t)dataBuf[8] << 24)+((uint32_t)dataBuf[9] << 16)+((uint32_t)dataBuf[10] << 8)+((uint32_t)dataBuf[11] << 0));
        BOOL hopNotSkip = (dataBuf[12] == 255);
        m_dataIdOld=m_dataIdNew;
        uint8_t hopSkipNonce=dataBuf[14];
        m_dataIdNew=dataBuf[15]; //A nonce that we can use if we get packets out of order
        
        //For debug. DOn't do this in tracking mode though or it will slow down the app a lot.
        if(self.a_state != TRACK_APP_SPECD && self.a_state != TRACK_LAST_INV){
            [self addTextToConsole:[NSString stringWithFormat:@"freqSlot: %d",m_frequencySlot]];
            [self addTextToConsole:[NSString stringWithFormat:@"antMagI: %d",m_antMagI]];
            [self addTextToConsole:[NSString stringWithFormat:@"antMagQ: %d",m_antMagQ]];
            [self addTextToConsole:[NSString stringWithFormat:@"calMagI: %d",calMagI]];
            [self addTextToConsole:[NSString stringWithFormat:@"calMagQ: %d",calMagQ]];
        }
        
        if(m_dataIdNew != (m_dataIdOld+1) % 256){
            [self addTextToConsole:[NSString stringWithFormat:@"Got data packets out of order. May be due to reader reset."]];
        }
        
        switch(self.t_state){
            case WAIT_PKT1:
                //Uh-oh, we were waiting for PKT1 but got a packet 2?
                //Disregard this packet 2 and exit this function.
                //We retain state as waiting for packaet 1.
                [self addTextToConsole:[NSString stringWithFormat:@"Got PKT2 while expecting PKT1"]];
                break;
                
            case WAIT_PKT2:
                           
                //If we're not expecting supplemental data, write the tag data to the tag list now
                //If we're not doing supplemental tag data, we're only doing hops (no PDOA)
                //If we're not doing supplemental data, we don't have cal data.
                           
                //BELOW IS A METHOD - MUST SEND TO THE RIGHT OBJECT
                [[RFIDTagList theOnlyRFIDTagList] saveTagWithEPC: m_currentEpc
                                                        withFreqSlot: m_frequencySlot
                                                        withHopNotSkip: hopNotSkip
                                                        withHopSkipNonce: hopSkipNonce
                                                        withAntMagI: m_antMagI
                                                        withAntMagQ: m_antMagQ
                                                        withCalMagI: calMagI
                                                        withCalMagQ: calMagQ];
                //OK, everything worked out. Now we wait for packet 1 again.
                self.t_state=WAIT_PKT1;
                break;
                       
            default:
                [self addTextToConsole:[NSString stringWithFormat:@"Got unknown packet state"]];
                break;
                       
               }
    }
}

#pragma mark - BTLE Waveform Data Handler

//This function handles streaming data from the waveform memory on the FPGA through the MCU over BTLE back to the iPhone here.
//When the MCU and the iOS software enters the RECOV_WVFM_MEM state, the MCU firmware sends indications as fast as it can
//containing the sequential bytes that were in the waveform RAM.
- (void) didReceiveWaveformDataData:(NSData *)data
{
    //Fill up waveform buffer. When we transition back to idle, we dump the buffer to a file
    //Check that we are in the waveform receive state
    if(self.a_state==RECOV_WVFM_MEM){
        int dataLength = (int)[data length]; //assume length < buffer size for the time being
        uint8_t *dataBuf=malloc(dataLength * sizeof(uint8_t));
        [data getBytes:dataBuf length:dataLength];
        
        for(int i=0; i<dataLength; i++){
            for(int j=0; j<8; j++){
                if(m_waveformFifoWP < WAVEFORM_FIFO_SIZE){
                    //For each bit, sub in the appropriate ASCII 0 or 1
                    //In other words, we get a binary 0 or 1 in, and we need to turn that into an ASCII 0 or 1
                    m_WaveformDataFifo[(3*m_waveformFifoWP)+0]=0x30+((dataBuf[i] >> j) & 1);
                    //After each ASCII 0 or 1, we "hit return" so that the bits are all in a vertical column in the text file.
                    m_WaveformDataFifo[(3*m_waveformFifoWP)+1]=0x0D;    //Carriage return
                    m_WaveformDataFifo[(3*m_waveformFifoWP)+2]=0x0A;    //line feed
                    m_waveformFifoWP++;
                    //Indeed, the earliest bits in time are the LSBs
                }
                //Don't have the buffer overflow else check here otherwise we will have a million of them maybe.
            }
        }
        
        //Have buffer overflow check here so that we only get one of them.
        if(m_waveformFifoWP > WAVEFORM_FIFO_SIZE){
            [self addTextToConsole:[NSString stringWithFormat:@"Program attempted a waveform data buffer overflow"]];
        }
        
    }
    else{
        [self addTextToConsole:[NSString stringWithFormat:@"Error: Got waveform data while outside of the waveform data state"]];
    }
}

//This code allows setting the name of the file which will contain data from the waveform capture.

void setRxFilename(char* file_name, void *uData){
    TableViewController *obj = (__bridge TableViewController *)(uData);
    obj.rxFilename=[[NSString alloc] initWithCString:file_name encoding:NSUTF8StringEncoding];
}

-(void) dataFromDBTVC:(NSData *)data withFileName:(NSString *)fileName {

}

#pragma mark - BTLE Log Message Handler

//For the most part, log messages are sent as notifications from the MCU.
//When these messages are received, we buffer them up in a FIFO and print them when we see a null character.

- (void) didReceiveLogMessageData:(NSData *)data
{
    //Fill up log message buffer.
    //When we see a null character, dump the data to the console and reset the fifo pointer
    //The other thing we need to do is to ensure that data beyond the fifo pointer is not printed
    
        NSString        *logMessage;
        int dataLength = (int)[data length]; //assume length < buffer size for the time being
        uint8_t *dataBuf=malloc(dataLength * sizeof(uint8_t));
        [data getBytes:dataBuf length:dataLength];
    
        NSLog(@"Did in fact get a log message at the iphone");
        
        for(int i=0; i<dataLength; i++){
            if(m_logMessageFifoWP < LOG_MESSAGE_FIFO_SIZE){
                m_logMessageFifo[m_logMessageFifoWP++]=dataBuf[i];
            }
            if(dataBuf[i]==0){
                //uint8_t *cleanLogMessageBuf=malloc(m_logMessageFifoWP * sizeof(uint8_t));
                //memcpy(cleanLogMessageBuf,m_logMessageFifo,m_logMessageFifoWP);
                logMessage = [NSString stringWithUTF8String:(char *)m_logMessageFifo];
                [self addTextToConsole:[NSString stringWithFormat:@"SURFER: %@",logMessage]];
                m_logMessageFifoWP  =   0;
            }
        }
    
        if(m_logMessageFifoWP >= LOG_MESSAGE_FIFO_SIZE){
            [self addTextToConsole:[NSString stringWithFormat:@"Program attempted a log message data buffer overflow"]];
            //Ensure the final character is a null data character, dump the data and reset the fifo pointer.
            m_logMessageFifo[LOG_MESSAGE_FIFO_SIZE-1]=0;
            logMessage = [NSString stringWithUTF8String:(char *)m_logMessageFifo];
            [self addTextToConsole:[NSString stringWithFormat:@"SURFER: %@",logMessage]];
            m_logMessageFifoWP  =   0;
        }
    
    free(dataBuf);
    
}

//The function below came from Nordic Semiconductor's ViewController.m file.
//In this case, we merely print text while prepending a timestamp.

- (void) addTextToConsole:(NSString *) string
{

    NSDateFormatter *formatter;
    formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"HH:mm:ss.SSS"];
    
    self.consoleTextView.text = [self.consoleTextView.text stringByAppendingFormat:@"[%@]: %@\n",[formatter stringFromDate:[NSDate date]], string];
    
}

//This button clears the log screen. It fills up pretty fast.
- (IBAction)clearButtonPressed:(id)sender {
 // Clear the console
    self.consoleTextView.text = [NSString stringWithFormat:@"Cleared\n"];
    
    [self.consoleTextView setScrollEnabled:NO];
    NSRange bottom = NSMakeRange(self.consoleTextView.text.length-1, self.consoleTextView.text.length);
    [self.consoleTextView scrollRangeToVisible:bottom];
    [self.consoleTextView setScrollEnabled:YES];
}

#pragma mark - Bluetooth Connection

//It's been a while since we looked at this part of the code.
//Apple uses something called a Central Manager to manage its connections to BTLE peripherals.
//When this manager is up and running, enable to Connect button, so that it can be pressed to search for the RFID reader.
//We never actually disable this button, so we leave this here.
//The function below came from Nordic Semiconductor's ViewController.m file.

- (void) centralManagerDidUpdateState:(CBCentralManager *)central
{
    if (central.state == CBManagerStatePoweredOn) //Was CBCentralManagerStatePoweredOn but I got a deprecation warning
    {
        [self.connectButton setEnabled:YES];
    }
    
}

//When the iDevice discovers the reader, print a log message and make an object to represent the reader from the iOS software side.
//Also attempt to connect to the peripheral.
//The function below came from Nordic Semiconductor's ViewController.m file.
- (void) centralManager:(CBCentralManager *)central didDiscoverPeripheral:(CBPeripheral *)peripheral advertisementData:(NSDictionary *)advertisementData RSSI:(NSNumber *)RSSI
{
    NSLog(@"Did discover peripheral %@ with RSSI: %@", peripheral.name, RSSI);
    [self addTextToConsole:[NSString stringWithFormat:@"Did discover peripheral %@ with RSSI: %@", peripheral.name, RSSI]];
    
    [self.cm stopScan];
    
    self.currentPeripheral = [[SURFERPeripheral alloc] initWithPeripheral:peripheral delegate:self];
    
    [self.cm connectPeripheral:peripheral options:@{CBConnectPeripheralOptionNotifyOnDisconnectionKey: [NSNumber numberWithBool:YES]}];
}

//Usually, this function will be seen to execute right after didDiscoverPeripheral
//This is also a reset function.
//No state-syncing is performed yet (the iOS state is the UNKNOWN state at the moment) because
//(we recall) that we need to tell the reader peripheral object in iOS software that it has been
//connected before we receive any data from the reader.
//Upon thinking about it, it may be possible to attempt a synchronization after [self.currentPeripheral didConnect]
//We also change the "Connect" button label to "Disconnect"
//The basic portions of the function below came from Nordic Semiconductor's ViewController.m file.
- (void) centralManager:(CBCentralManager *)central didConnectPeripheral:(CBPeripheral *)peripheral
{
    NSLog(@"Did connect peripheral %@", peripheral.name);
    
    [self addTextToConsole:[NSString stringWithFormat:@"Did connect to %@", peripheral.name]];
    
    self.c_state = CONNECTED;
    
    
    self.a_state            =   UNKNOWN;
    m_numTagsInventoried    =   0;
    
    //Following code added 083017
    self.rxFilename         =   nil;
    
    //Load dummy values into EPC state variables in case syncing with the reader doesn't work.
    
    m_targetEPC[0]   =   m_thenewEPC[0]     =   0x01;
    m_targetEPC[1]   =   m_thenewEPC[1]     =   0x23;
    m_targetEPC[2]   =   m_thenewEPC[2]     =   0x45;
    m_targetEPC[3]   =   m_thenewEPC[3]     =   0x67;
    m_targetEPC[4]   =   m_thenewEPC[4]     =   0x89;
    m_targetEPC[5]   =   m_thenewEPC[5]     =   0xAB;
    m_targetEPC[6]   =   m_thenewEPC[6]     =   0xCD;
    m_targetEPC[7]   =   m_thenewEPC[7]     =   0xEF;
    m_targetEPC[8]   =   m_thenewEPC[8]     =   0x89;
    m_targetEPC[9]   =   m_thenewEPC[9]     =   0xAB;
    m_targetEPC[10]  =   m_thenewEPC[10]    =   0xCD;
    m_targetEPC[11]  =   m_thenewEPC[11]    =   0xEF;
    
    m_targetEPC_length  = MAX_NUM_BYTES_IN_EPC;
    
    [_currentPeripheral readStateData];
    [_currentPeripheral readTargetEPCData];
    [_currentPeripheral readNewEPCData];
    
    if ([self.currentPeripheral.peripheral isEqual:peripheral])
    {
        [self.currentPeripheral didConnect];
    }
}

//This function is pretty self-explanatory.
//If we manually disconnect the reader from the iPhone app, we change the Connect button label back to "Connect"
//and set the iOS state to UNKNOWN (because we no longer know the reader state).
//The function below came from Nordic Semiconductor's ViewController.m file.
- (void) centralManager:(CBCentralManager *)central didDisconnectPeripheral:(CBPeripheral *)peripheral error:(NSError *)error
{
    NSLog(@"Did disconnect peripheral %@", peripheral.name);
    
    [self addTextToConsole:[NSString stringWithFormat:@"Did disconnect from %@, error code %ld", peripheral.name, (long)error.code]];
    
    self.c_state            =   IDLE;
    self.a_state            =   UNKNOWN;
    
    m_numTagsInventoried    =   0;
    
    if ([self.currentPeripheral.peripheral isEqual:peripheral])
    {
        [self.currentPeripheral didDisconnect];
    }
}

//This resets the BTLE packet counter for a given connection interval.
- (void)txTimerFireMethod:(NSTimer *)timer{
    if (timer==self.txTimer){
        m_txPktsPerCnxnIntvl=0;
    }
}

#pragma mark - Miscellaneous

- (void) didReadHardwareRevisionString:(NSString *)string
{
    [self addTextToConsole:[NSString stringWithFormat:@"Hardware revision: %@", string]];
}

    //The function below came from Nordic Semiconductor's ViewController.m file.
- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Debugging

//Send dummy packets a few seconds after starting the app
- (void)debugTimerFireMethod:(NSTimer *)timer{
    if (timer==self.debugTimer){
        
        //Allocate memory for the byte-wise packet data
        //For one tag, read twice
        uint8_t *dataBuft1p1d1=malloc(NUM_PCKT1_DATA_BYTES * sizeof(uint8_t));
        uint8_t *dataBuft1p1d2=malloc(NUM_PCKT2_DATA_BYTES * sizeof(uint8_t));
        uint8_t *dataBuft1p2d1=malloc(NUM_PCKT1_DATA_BYTES * sizeof(uint8_t));
        uint8_t *dataBuft1p2d2=malloc(NUM_PCKT2_DATA_BYTES * sizeof(uint8_t));
        //For another tag, read twice
        uint8_t *dataBuft2p1d1=malloc(NUM_PCKT1_DATA_BYTES * sizeof(uint8_t));
        uint8_t *dataBuft2p1d2=malloc(NUM_PCKT2_DATA_BYTES * sizeof(uint8_t));
        uint8_t *dataBuft2p2d1=malloc(NUM_PCKT1_DATA_BYTES * sizeof(uint8_t));
        uint8_t *dataBuft2p2d2=malloc(NUM_PCKT2_DATA_BYTES * sizeof(uint8_t));
        
        //write tag EPCs. Make them funny if possible
        //First tag EPC - Bad boys for life
        dataBuft1p1d1[0] = dataBuft1p2d1[0] = 0xBA;
        dataBuft1p1d1[1] = dataBuft1p2d1[1] = 0xDB;
        dataBuft1p1d1[2] = dataBuft1p2d1[2] = 0x01;
        dataBuft1p1d1[3] = dataBuft1p2d1[3] = 0x54;
        dataBuft1p1d1[4] = dataBuft1p2d1[4] = 0x11;
        dataBuft1p1d1[5] = dataBuft1p2d1[5] = 0xFE;
        dataBuft1p1d1[6] = dataBuft1p2d1[6] = 0xBA;
        dataBuft1p1d1[7] = dataBuft1p2d1[7] = 0xDB;
        dataBuft1p1d1[8] = dataBuft1p2d1[8] = 0x01;
        dataBuft1p1d1[9] = dataBuft1p2d1[9] = 0x54;
        dataBuft1p1d1[10] = dataBuft1p2d1[10] = 0x11;
        dataBuft1p1d1[11] = dataBuft1p2d1[11] = 0xFE;
        //Second tags EPC - Can't stop dancing all night
        dataBuft2p1d1[0] = dataBuft2p2d1[0] = 0xCA;
        dataBuft2p1d1[1] = dataBuft2p2d1[1] = 0x27;
        dataBuft2p1d1[2] = dataBuft2p2d1[2] = 0x57;
        dataBuft2p1d1[3] = dataBuft2p2d1[3] = 0x01;
        dataBuft2p1d1[4] = dataBuft2p2d1[4] = 0x7D;
        dataBuft2p1d1[5] = dataBuft2p2d1[5] = 0xA2;
        dataBuft2p1d1[6] = dataBuft2p2d1[6] = 0xC1;
        dataBuft2p1d1[7] = dataBuft2p2d1[7] = 0x26;
        dataBuft2p1d1[8] = dataBuft2p2d1[8] = 0xA1;
        dataBuft2p1d1[9] = dataBuft2p2d1[9] = 0x12;
        dataBuft2p1d1[10] = dataBuft2p2d1[10] = 0x16;
        dataBuft2p1d1[11] = dataBuft2p2d1[11] = 0x87;
        
        //Frequency slots - first tag 5 and 6, second tag 12 and 13
        //Also need to indicate that supplemental data will be used on each one
        dataBuft1p1d1[12]   =   128+5;
        dataBuft1p2d1[12]   =   128+6;
        dataBuft2p1d1[12]   =   128+12;
        dataBuft2p2d1[12]   =   128+13;
        
        //Data IDs - just do 1 2 3 4 5 6 7 8
        
        dataBuft1p1d1[19]   =   1;
        dataBuft1p1d2[14]   =   2;
        dataBuft1p2d1[19]   =   3;
        dataBuft1p2d2[14]   =   4;
        dataBuft2p1d1[19]   =   5;
        dataBuft2p1d2[14]   =   6;
        dataBuft2p2d1[19]   =   7;
        dataBuft2p2d2[14]   =   8;
        
        //For the bytes we aren't using at the moment, set them to 0
        
        dataBuft1p1d2[0]    =   dataBuft1p1d2[3]    =   dataBuft1p1d2[13]   =   0;
        dataBuft1p2d2[0]    =   dataBuft1p2d2[3]    =   dataBuft1p2d2[13]   =   0;
        dataBuft2p1d2[0]    =   dataBuft2p1d2[3]    =   dataBuft2p1d2[13]   =   0;
        dataBuft2p2d2[0]    =   dataBuft2p2d2[3]    =   dataBuft2p2d2[13]   =   0;
        
        //For the byte to tell us whether the packet data is a hop or a skip
        
        dataBuft1p1d2[12]   =   dataBuft2p1d2[12]   =   255;    //hops
        dataBuft1p2d2[12]   =   dataBuft2p2d2[12]   =   1;      //skips
        
        //OK, we need magI and magQ that will equate to reasonable ranges and RSSI values.
        //Say -40 to -60dBm RSSI and 6, 12 meter ranges.
        
        int32_t tag1AntPhase1MagI   =   67744408;
        int32_t tag1AntPhase1MagQ   =   -153092960;
        int32_t tag1CalPhase1MagI   =   38753322;
        int32_t tag1CalPhase1MagQ   =   -162864788;
        int32_t tag1AntPhase2MagI   =   135843950;
        int32_t tag1AntPhase2MagQ   =   -97842631;
        int32_t tag1CalPhase2MagI   =   81347083;
        int32_t tag1CalPhase2MagQ   =   -146319552;
        
        int32_t tag2AntPhase1MagI   =   12597378;
        int32_t tag2AntPhase1MagQ   =   11026043;
        int32_t tag2CalPhase1MagI   =   51882310;
        int32_t tag2CalPhase1MagQ   =   159169674;
        int32_t tag2AntPhase2MagI   =   13209048;
        int32_t tag2AntPhase2MagQ   =   -10286679;
        int32_t tag2CalPhase2MagI   =   135017289;
        int32_t tag2CalPhase2MagQ   =   -98980255;
        
        dataBuft1p1d1[13]           =   (uint8_t)(255 & tag1AntPhase1MagI >> 24);
        dataBuft1p1d1[14]           =   (uint8_t)(255 & tag1AntPhase1MagI >> 16);
        dataBuft1p1d1[15]           =   (uint8_t)(255 & tag1AntPhase1MagI >> 8);
        dataBuft1p1d2[1]            =   (uint8_t)(255 & tag1AntPhase1MagI >> 0);
        
        dataBuft1p1d1[16]           =   (uint8_t)(255 & tag1AntPhase1MagQ >> 24);
        dataBuft1p1d1[17]           =   (uint8_t)(255 & tag1AntPhase1MagQ >> 16);
        dataBuft1p1d1[18]           =   (uint8_t)(255 & tag1AntPhase1MagQ >> 8);
        dataBuft1p1d2[2]            =   (uint8_t)(255 & tag1AntPhase1MagQ >> 0);
        
        dataBuft1p1d2[4]            =   (uint8_t)(255 & tag1CalPhase1MagI >> 24);
        dataBuft1p1d2[5]            =   (uint8_t)(255 & tag1CalPhase1MagI >> 16);
        dataBuft1p1d2[6]            =   (uint8_t)(255 & tag1CalPhase1MagI >> 8);
        dataBuft1p1d2[7]            =   (uint8_t)(255 & tag1CalPhase1MagI >> 0);
        
        dataBuft1p1d2[8]            =   (uint8_t)(255 & tag1CalPhase1MagQ >> 24);
        dataBuft1p1d2[9]            =   (uint8_t)(255 & tag1CalPhase1MagQ >> 16);
        dataBuft1p1d2[10]           =   (uint8_t)(255 & tag1CalPhase1MagQ >> 8);
        dataBuft1p1d2[11]           =   (uint8_t)(255 & tag1CalPhase1MagQ >> 0);
        
        dataBuft1p2d1[13]           =   (uint8_t)(255 & tag1AntPhase2MagI >> 24);
        dataBuft1p2d1[14]           =   (uint8_t)(255 & tag1AntPhase2MagI >> 16);
        dataBuft1p2d1[15]           =   (uint8_t)(255 & tag1AntPhase2MagI >> 8);
        dataBuft1p2d2[1]            =   (uint8_t)(255 & tag1AntPhase2MagI >> 0);
        
        dataBuft1p2d1[16]           =   (uint8_t)(255 & tag1AntPhase2MagQ >> 24);
        dataBuft1p2d1[17]           =   (uint8_t)(255 & tag1AntPhase2MagQ >> 16);
        dataBuft1p2d1[18]           =   (uint8_t)(255 & tag1AntPhase2MagQ >> 8);
        dataBuft1p2d2[2]            =   (uint8_t)(255 & tag1AntPhase2MagQ >> 0);
        
        dataBuft1p2d2[4]            =   (uint8_t)(255 & tag1CalPhase2MagI >> 24);
        dataBuft1p2d2[5]            =   (uint8_t)(255 & tag1CalPhase2MagI >> 16);
        dataBuft1p2d2[6]            =   (uint8_t)(255 & tag1CalPhase2MagI >> 8);
        dataBuft1p2d2[7]            =   (uint8_t)(255 & tag1CalPhase2MagI >> 0);
        
        dataBuft1p2d2[8]            =   (uint8_t)(255 & tag1CalPhase2MagQ >> 24);
        dataBuft1p2d2[9]            =   (uint8_t)(255 & tag1CalPhase2MagQ >> 16);
        dataBuft1p2d2[10]           =   (uint8_t)(255 & tag1CalPhase2MagQ >> 8);
        dataBuft1p2d2[11]           =   (uint8_t)(255 & tag1CalPhase2MagQ >> 0);
        
        dataBuft2p1d1[13]           =   (uint8_t)(255 & tag2AntPhase1MagI >> 24);
        dataBuft2p1d1[14]           =   (uint8_t)(255 & tag2AntPhase1MagI >> 16);
        dataBuft2p1d1[15]           =   (uint8_t)(255 & tag2AntPhase1MagI >> 8);
        dataBuft2p1d2[1]            =   (uint8_t)(255 & tag2AntPhase1MagI >> 0);
        
        dataBuft2p1d1[16]           =   (uint8_t)(255 & tag2AntPhase1MagQ >> 24);
        dataBuft2p1d1[17]           =   (uint8_t)(255 & tag2AntPhase1MagQ >> 16);
        dataBuft2p1d1[18]           =   (uint8_t)(255 & tag2AntPhase1MagQ >> 8);
        dataBuft2p1d2[2]            =   (uint8_t)(255 & tag2AntPhase1MagQ >> 0);
        
        dataBuft2p1d2[4]            =   (uint8_t)(255 & tag2CalPhase1MagI >> 24);
        dataBuft2p1d2[5]            =   (uint8_t)(255 & tag2CalPhase1MagI >> 16);
        dataBuft2p1d2[6]            =   (uint8_t)(255 & tag2CalPhase1MagI >> 8);
        dataBuft2p1d2[7]            =   (uint8_t)(255 & tag2CalPhase1MagI >> 0);
        
        dataBuft2p1d2[8]            =   (uint8_t)(255 & tag2CalPhase1MagQ >> 24);
        dataBuft2p1d2[9]            =   (uint8_t)(255 & tag2CalPhase1MagQ >> 16);
        dataBuft2p1d2[10]           =   (uint8_t)(255 & tag2CalPhase1MagQ >> 8);
        dataBuft2p1d2[11]           =   (uint8_t)(255 & tag2CalPhase1MagQ >> 0);
        
        dataBuft2p2d1[13]           =   (uint8_t)(255 & tag2AntPhase2MagI >> 24);
        dataBuft2p2d1[14]           =   (uint8_t)(255 & tag2AntPhase2MagI >> 16);
        dataBuft2p2d1[15]           =   (uint8_t)(255 & tag2AntPhase2MagI >> 8);
        dataBuft2p2d2[1]            =   (uint8_t)(255 & tag2AntPhase2MagI >> 0);
        
        dataBuft2p2d1[16]           =   (uint8_t)(255 & tag2AntPhase2MagQ >> 24);
        dataBuft2p2d1[17]           =   (uint8_t)(255 & tag2AntPhase2MagQ >> 16);
        dataBuft2p2d1[18]           =   (uint8_t)(255 & tag2AntPhase2MagQ >> 8);
        dataBuft2p2d2[2]            =   (uint8_t)(255 & tag2AntPhase2MagQ >> 0);
        
        dataBuft2p2d2[4]            =   (uint8_t)(255 & tag2CalPhase2MagI >> 24);
        dataBuft2p2d2[5]            =   (uint8_t)(255 & tag2CalPhase2MagI >> 16);
        dataBuft2p2d2[6]            =   (uint8_t)(255 & tag2CalPhase2MagI >> 8);
        dataBuft2p2d2[7]            =   (uint8_t)(255 & tag2CalPhase2MagI >> 0);
        
        dataBuft2p2d2[8]            =   (uint8_t)(255 & tag2CalPhase2MagQ >> 24);
        dataBuft2p2d2[9]            =   (uint8_t)(255 & tag2CalPhase2MagQ >> 16);
        dataBuft2p2d2[10]           =   (uint8_t)(255 & tag2CalPhase2MagQ >> 8);
        dataBuft2p2d2[11]           =   (uint8_t)(255 & tag2CalPhase2MagQ >> 0);
        
        //Load the byte-wise packet data into NSData structures
        NSData *tag1Packet1Data1 = [[NSData alloc] initWithBytes:dataBuft1p1d1 length:NUM_PCKT1_DATA_BYTES];
        NSData *tag1Packet1Data2 = [[NSData alloc] initWithBytes:dataBuft1p1d2 length:NUM_PCKT2_DATA_BYTES];
        NSData *tag1Packet2Data1 = [[NSData alloc] initWithBytes:dataBuft1p2d1 length:NUM_PCKT1_DATA_BYTES];
        NSData *tag1Packet2Data2 = [[NSData alloc] initWithBytes:dataBuft1p2d2 length:NUM_PCKT2_DATA_BYTES];
        
        NSData *tag2Packet1Data1 = [[NSData alloc] initWithBytes:dataBuft2p1d1 length:NUM_PCKT1_DATA_BYTES];
        NSData *tag2Packet1Data2 = [[NSData alloc] initWithBytes:dataBuft2p1d2 length:NUM_PCKT2_DATA_BYTES];
        NSData *tag2Packet2Data1 = [[NSData alloc] initWithBytes:dataBuft2p2d1 length:NUM_PCKT1_DATA_BYTES];
        NSData *tag2Packet2Data2 = [[NSData alloc] initWithBytes:dataBuft2p2d2 length:NUM_PCKT2_DATA_BYTES];
        
        //Call the methods - we're mocking BTLE data transfers here
        [self didReceivePacketData1Data:tag1Packet1Data1];
        [self didReceivePacketData2Data:tag1Packet1Data2];
        [self didReceivePacketData1Data:tag1Packet2Data1];
        [self didReceivePacketData2Data:tag1Packet2Data2];
        
        [self didReceivePacketData1Data:tag2Packet1Data1];
        [self didReceivePacketData2Data:tag2Packet1Data2];
        [self didReceivePacketData1Data:tag2Packet2Data1];
        [self didReceivePacketData2Data:tag2Packet2Data2];
    }
}

@end
