//
//  CDAddFriendController.m
//  AVOSChatDemo
//
//  Created by lzw on 14-10-23.
//  Copyright (c) 2014年 AVOS. All rights reserved.
//

#import "CDAddFriendVC.h"
#import "CDUserService.h"
#import "CDBaseNavC.h"
#import "CDUserInfoVC.h"
#import "CDImageLabelTableCell.h"
#import "CDUtils.h"

@interface CDAddFriendVC ()

@property (nonatomic, strong) NSArray *users;

@end

static NSString *cellIndentifier = @"cellIndentifier";

@implementation CDAddFriendVC

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"查找好友";
    [_searchBar setDelegate:self];
    [_tableView setDelegate:self];
    [_tableView setDataSource:self];
    [self.tableView registerNib:[UINib nibWithNibName:NSStringFromClass([CDImageLabelTableCell class]) bundle:nil] forCellReuseIdentifier:cellIndentifier];
    [self searchUser:@""];
}

- (void)searchUser:(NSString *)name {
    [CDUserService findUsersByPartname:name withBlock: ^(NSArray *objects, NSError *error) {
        if ([self filterError:error]) {
            if (objects) {
                self.users = objects;
                [_tableView reloadData];
            }
        }
    }];
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [self.users count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    CDImageLabelTableCell *cell = [tableView dequeueReusableCellWithIdentifier:cellIndentifier forIndexPath:indexPath];
    if (!cell) {
        cell = [[CDImageLabelTableCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellIndentifier];
    }
    AVUser *user = self.users[indexPath.row];
    cell.myLabel.text = user.username;
    [CDUserService displayAvatarOfUser:user avatarView:cell.myImageView];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    CDUserInfoVC *controller = [[CDUserInfoVC alloc] initWithUser:self.users[indexPath.row]];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    NSString *content = searchBar.text;
    [self searchUser:content];
}

@end
