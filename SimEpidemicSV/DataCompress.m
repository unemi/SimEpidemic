//
//  DataCompress.m
//  LoversFlow
//
//  Created by Tatsuo Unemi on 2017/02/21.
//  Copyright © 2017, Tatsuo Unemi. All rights reserved.
// modified for simepidemic 2020/9/10.

#import "DataCompress.h"
#import <zlib.h>
#define CHUNK 256*1024

@implementation NSData (CompressExtension)
- (NSData *)zippedDataWithLevel:(int)level {
	z_stream strm;
    strm.zalloc = Z_NULL;
    strm.zfree = Z_NULL;
    strm.opaque = Z_NULL;
    strm.data_type = Z_TEXT;
    int ret = deflateInit(&strm, level);
    if (ret != Z_OK) @throw @(ret);
	uInt dataLen = (uInt)self.length;
	unsigned char *outBuf = malloc(dataLen);
	strm.next_in = (z_const Bytef *)self.bytes;
	strm.avail_in = dataLen;
	strm.avail_out = dataLen;
	strm.next_out = outBuf;
	while (strm.avail_in > 0) {
		ret = deflate(&strm, Z_FINISH);
		if (ret == Z_STREAM_END) break;
		else if (ret != Z_OK) { free(outBuf); @throw @(ret); }
	}
	(void)deflateEnd(&strm);
	if (ret == Z_STREAM_ERROR) { free(outBuf); @throw @(ret); }
	NSData *data = [NSData dataWithBytes:outBuf length:dataLen - strm.avail_out];
	free(outBuf);
	return data;
}
- (NSData *)zippedData {
	return [self zippedDataWithLevel:Z_BEST_COMPRESSION];
}
- (NSData *)unzippedData {
	z_stream strm;
    strm.zalloc = Z_NULL;
    strm.zfree = Z_NULL;
    strm.opaque = Z_NULL;
	strm.avail_in = 0;
	strm.next_in = Z_NULL;
    int ret = inflateInit(&strm);
    if (ret != Z_OK) @throw @(ret);
	uInt dataLen = 0, bufLen = CHUNK, restLen;
	unsigned char *outBuf = malloc(CHUNK);
	strm.avail_in = (uInt)self.length;
	strm.next_in = (z_const Bytef *)self.bytes;
	do {
		strm.next_out = outBuf + dataLen;
		strm.avail_out = (restLen = bufLen - dataLen);
		ret = inflate(&strm, Z_NO_FLUSH);
		dataLen += restLen - strm.avail_out;
		if (ret == Z_STREAM_END) break;
		else if (ret != Z_OK) { free(outBuf); @throw @(ret); }
		if (ret != Z_STREAM_END && strm.avail_out < CHUNK)
			outBuf = realloc(outBuf, (bufLen += CHUNK));
	} while (ret != Z_STREAM_END);
	(void)inflateEnd(&strm);
	NSData *data = [NSData dataWithBytes:outBuf length:dataLen];
	free(outBuf);
	return data;
}
@end
