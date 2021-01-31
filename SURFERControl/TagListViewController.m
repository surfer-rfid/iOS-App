//////////////////////////////////////////////////////////////////////////////////////
//                                                                                  //
//  Module: SURFERControl                                                           //
//                                                                                  //
//  File: TagListViewController.m                                                   //
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
//  recently read RFID tags together. This file uses many of the coding styles and  //
//  concepts from "iOS Programming, The Big Nerd Ranch Guide" 4th edition, chapter  //
//  8.                                                                              //
//                                                                                  //
//////////////////////////////////////////////////////////////////////////////////////

#import "TagListViewController.h"
#import "TagInfoViewController.h"
#import "RFIDTagList.h"
#import "RFIDTag.h"

@interface TagListViewController ()

@end

@implementation TagListViewController

- (id)initWithStyle:(UITableViewStyle)style
{
    self = [super initWithStyle:style];
    if (self) {
        // Custom initialization
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    //[self.tableView registerClass:[UITableViewCell class] forCellReuseIdentifier:@"TagViewCell"];
}

- (IBAction)dismissTL:(id)sender
{
    [self.presentingViewController dismissViewControllerAnimated:YES completion:NULL];
}

- (IBAction)clearRFIDTagList
{
    //Begin operations
    [self.tableView beginUpdates];
    
    //Delete the rows
    //First we have to look at our array of tags and work back to find their rows then indexPaths
    NSArray *tags   = [[RFIDTagList theOnlyRFIDTagListWithDelegateTLVC:self] allRFIDTags];
    //Loop through all of the tags
    for (RFIDTag *tag in tags) {
        NSInteger row=[tags indexOfObject:tag];
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
        [self.tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }
    
    //Delete the data store
    [[RFIDTagList theOnlyRFIDTagListWithDelegateTLVC:self] clearRFIDTagList];
    
    //Check that everything is n'sync.
    [self.tableView endUpdates];
}

#pragma mark - Table view data source

- (NSString *)createTableRowDetailString:(RFIDTag *)tag
{
    NSString *rssiString;
    NSString *rangeString;
    
    if(tag.magAntHop < 0){
        //We have a valid RSSI value in the tag.
        rssiString  = [[NSString alloc] initWithFormat:@"RSSI: %2.1fdBm ",tag.magAntHop];
    } else {
        rssiString  = [[NSString alloc] initWithFormat:@"RSSI: Invalid "];
    }
    
    if(tag.pdoaRangeMeters > 0){
        //We have a valid pdoaRange for the tag.
        rangeString  = [[NSString alloc] initWithFormat:@"Range: %2.1fm ",tag.pdoaRangeMeters];
    } else {
        rangeString  = [[NSString alloc] initWithFormat:@"Range: Invalid"];
    }
    
    return [[NSString alloc] initWithFormat:@"%@ %@  Last Time: %@",rssiString,rangeString,
            [NSDateFormatter localizedStringFromDate:tag.lastInterrogation
                                           dateStyle:NSDateFormatterShortStyle
                                           timeStyle:NSDateFormatterMediumStyle]];
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return [[[RFIDTagList theOnlyRFIDTagListWithDelegateTLVC:self] allRFIDTags] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    
    static NSString *CellIdentifier = @"TagViewCell";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:CellIdentifier];
        cell.textLabel.font = [UIFont systemFontOfSize:16.0];
        cell.detailTextLabel.font = [UIFont systemFontOfSize:12.0];
    }
    
    //Pull out the tag corresponding to the row in question.
    
    NSArray *tags   = [[RFIDTagList theOnlyRFIDTagListWithDelegateTLVC:self] allRFIDTags]; //May want to point theOnlyRFIDTagList to null in between radio operations.
    RFIDTag *tag    = tags[indexPath.row];
    
    cell.textLabel.text         = [[NSString alloc] initWithFormat:@"Tag %ld: %@",indexPath.row,tag.epc];
    cell.detailTextLabel.text   = [self createTableRowDetailString:tag];
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    TagInfoViewController *tivc = [self.storyboard instantiateViewControllerWithIdentifier:@"TagInfoViewController"];
    
    tivc.row = indexPath.row;
    
    [self.navigationController pushViewController:tivc animated:YES];
}

//If we get a new EPC value, add a new row to the table
- (void)addNewTagToTable:(NSInteger)row
{
    NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
    //Insert the new row into the table.
    
    [self.tableView beginUpdates];
    
    [self.tableView insertRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationTop];
    
    [self.tableView endUpdates];
}

- (void)reloadTableTagData
{
    [self.tableView reloadData];
}

/*
// Override to support conditional editing of the table view.
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    // Return NO if you do not want the specified item to be editable.
    return YES;
}
*/

/*
// Override to support editing the table view.
- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        // Delete the row from the data source
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
    } else if (editingStyle == UITableViewCellEditingStyleInsert) {
        // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
    }   
}
*/

/*
// Override to support rearranging the table view.
- (void)tableView:(UITableView *)tableView moveRowAtIndexPath:(NSIndexPath *)fromIndexPath toIndexPath:(NSIndexPath *)toIndexPath {
}
*/

/*
// Override to support conditional rearranging of the table view.
- (BOOL)tableView:(UITableView *)tableView canMoveRowAtIndexPath:(NSIndexPath *)indexPath {
    // Return NO if you do not want the item to be re-orderable.
    return YES;
}
*/

/*
#pragma mark - Navigation

// In a storyboard-based application, you will often want to do a little preparation before navigation
- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    // Get the new view controller using [segue destinationViewController].
    // Pass the selected object to the new view controller.
}
*/

@end
