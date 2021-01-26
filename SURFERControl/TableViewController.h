//////////////////////////////////////////////////////////////////////////////////////
//                                                                                  //
//  Module: SURFERControl                                                           //
//                                                                                  //
//  File: TableViewController.m                                                     //
//  Creation date: circa 10/31/2016                                                 //
//  Author: Edward Keehr                                                            //
//                                                                                  //
//    This file was derived from the Nordic Semiconductor example code in their     //
//    nRF UART app. Specifically, this file was derived from "ViewController.h".    //
//    While this file uses the template from ViewController.h, since all of the     //
//    function and variable names have been changed, none of the original code      //
//    remains.                                                                      //
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

#import <UIKit/UIKit.h>
#import <AssetsLibrary/AssetsLibrary.h>

#import "SURFERPeripheral.h"
#import "TagListViewController.h"

#define WAVEFORM_FIFO_SIZE      65536
#define LOG_MESSAGE_FIFO_SIZE   256
#define MAX_NUM_BYTES_IN_EPC    12
#define NUM_PCKT1_DATA_BYTES    20
#define NUM_PCKT2_DATA_BYTES    16
#define MAX_WAVEFORM_DATA_BYTES 20
#define MAX_LOG_MESSAGE_BYTES   20

@interface TableViewController : UITableViewController <UITextFieldDelegate, CBCentralManagerDelegate, SURFERPeripheralDelegate, NSStreamDelegate,UIImagePickerControllerDelegate,UINavigationControllerDelegate,
    TagListViewControllerDelegate>
@property (strong, nonatomic) IBOutlet UITableView *tableView;
@property (weak, nonatomic) IBOutlet UIButton *connectButton;
@property (weak, nonatomic) IBOutlet UITextView *consoleTextView;
@property (weak, nonatomic) IBOutlet UITextField *targetEPCTextField;
@property (weak, nonatomic) IBOutlet UIButton *targetEPCButton;
@property (weak, nonatomic) IBOutlet UITextField *thenewEPCTextField;
@property (weak, nonatomic) IBOutlet UIButton *thenewEPCButton;
@property (weak, nonatomic) IBOutlet UIButton *initializeButton;
@property (weak, nonatomic) IBOutlet UIButton *searchButton;
@property (weak, nonatomic) IBOutlet UIButton *inventoryButton;
@property (weak, nonatomic) IBOutlet UIButton *testDTCButton;
@property (weak, nonatomic) IBOutlet UIButton *appSpecdLastInvToggleButton;
@property (weak, nonatomic) IBOutlet UIButton *programButton;
@property (weak, nonatomic) IBOutlet UIButton *killTagButton;
@property (weak, nonatomic) IBOutlet UIButton *programTagKillPWButton;
@property (weak, nonatomic) IBOutlet UIButton *recoverWaveformMemoryButton;
@property (weak, nonatomic) IBOutlet UIButton *resetASICsButton;
@property (weak, nonatomic) IBOutlet UIButton *clearButton;
@property (weak, nonatomic) IBOutlet UIButton *trackButton;

- (IBAction)connectButtonPressed:(id)sender;

- (IBAction)targetEPCButtonTouched:(id)sender;
- (IBAction)thenewEPCButtonTouched:(id)sender;
- (IBAction)initializeButtonPressed:(id)sender;
- (IBAction)searchButtonPressed:(id)sender;
- (IBAction)inventoryButtonPressed:(id)sender;
- (IBAction)testDTCButtonPressed:(id)sender;
- (IBAction)appSpecdLastInvToggleButtonPressed:(id)sender;
- (IBAction)programButtonPressed:(id)sender;
- (IBAction)killTagButtonPressed:(id)sender;
- (IBAction)programTagKillPWButtonPressed:(id)sender;
- (IBAction)recoverWaveformMemoryButtonPressed:(id)sender;
- (IBAction)resetASICsButtonPressed:(id)sender;
- (IBAction)clearButtonPressed:(id)sender;
- (IBAction)trackButtonPressed:(id)sender;

@end
