//////////////////////////////////////////////////////////////////////////////////////
//                                                                                  //
//  Module: SURFERControl                                                           //
//                                                                                  //
//  File: TagInfoViewController.m                                                   //
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
//  This class defines a view controller for displaying information on just one tag.//
//                                                                                  //
//////////////////////////////////////////////////////////////////////////////////////

#import "TagInfoViewController.h"
#import "RFIDTagList.h"
#import "RFIDTag.h"

@interface TagInfoViewController ()

@end

@implementation TagInfoViewController

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [self displayTagInformation];
}

- (void)displayTagInformation
{
    //Pull out the tag corresponding to the row in question.
    
    NSArray *tags   = [[RFIDTagList theOnlyRFIDTagListWithDelegateTIVC:self] allRFIDTags]; //May want to point theOnlyRFIDTagList to null in between radio operations.
    RFIDTag *tag    = tags[self.row];
    
    self.epcTextView.text       = tag.epc;
    self.firstTextView.text     = [NSDateFormatter localizedStringFromDate:tag.firstInterrogation
                                                                 dateStyle:NSDateFormatterShortStyle
                                                                 timeStyle:NSDateFormatterFullStyle];
    self.lastTextView.text      = [NSDateFormatter localizedStringFromDate:tag.lastInterrogation
                                                                 dateStyle:NSDateFormatterShortStyle
                                                                 timeStyle:NSDateFormatterFullStyle];
    NSString *rssiString;
    NSString *rangeString;
    NSString *messageString;
    BOOL isError = FALSE;
    
    if(tag.magAntHop < 0){
        //We have a valid RSSI value in the tag.
        rssiString  = [[NSString alloc] initWithFormat:@"RSSI: %2.1fdBm ",tag.magAntHop];
    } else {
        rssiString  = [[NSString alloc] initWithFormat:@"RSSI: Invalid "];
        isError = TRUE;
    }
    
    if(tag.pdoaRangeMeters > 0){
        //We have a valid pdoaRange for the tag.
        rangeString  = [[NSString alloc] initWithFormat:@"Range: %2.1fm ",tag.pdoaRangeMeters];
    } else {
        rangeString  = [[NSString alloc] initWithFormat:@"Range: Invalid"];
        isError = TRUE;
    }
    
    if(isError){
        messageString  = [[NSString alloc] initWithFormat:@"There is an error."];
    } else {
        messageString  = [[NSString alloc] initWithFormat:@"No errors."];
    }
        
    self.pdoaTextView.text      = rangeString;
    self.rssiTextView.text      = rssiString;
    self.messagesTextView.text  = messageString;
}

@end
