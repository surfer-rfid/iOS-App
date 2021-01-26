//////////////////////////////////////////////////////////////////////////////////////
//                                                                                  //
//  Module: SURFERControl                                                           //
//                                                                                  //
//  File: TagListViewController.h                                                   //
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
//  This class defines a view controller for displaying information on all of the   //
//  recently read RFID tags together.                                               //
//                                                                                  //
//////////////////////////////////////////////////////////////////////////////////////

#import <UIKit/UIKit.h>
#import <AssetsLibrary/AssetsLibrary.h>

#import "RFIDTagList.h"

@protocol TagListViewControllerDelegate <NSObject>

@end

@interface TagListViewController : UITableViewController <RFIDTagListDelegateTLVC>

@property (nonatomic,weak) id<TagListViewControllerDelegate> delegate;

@end
