//
//  DataCompress.h
//  LoversFlow
//
//  Created by Tatsuo Unemi on 2017/02/21.
//  Copyright © 2017, Tatsuo Unemi. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSData (CompressExtension)
- (NSData *)zippedData;
- (NSData *)zippedDataWithLevel:(int)level;
- (NSData *)unzippedData;
@end
