/*
 Licensed to the Apache Software Foundation (ASF) under one
 or more contributor license agreements.  See the NOTICE file
 distributed with this work for additional information
 regarding copyright ownership.  The ASF licenses this file
 to you under the Apache License, Version 2.0 (the
 "License"); you may not use this file except in compliance
 with the License.  You may obtain a copy of the License at
 
 http://www.apache.org/licenses/LICENSE-2.0
 
 Unless required by applicable law or agreed to in writing,
 software distributed under the License is distributed on an
 "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 KIND, either express or implied.  See the License for the
 specific language governing permissions and limitations
 under the License.
 */

#import "UIImage+CropScaleOrientation.h"

@implementation UIImage (CropScaleOrientation)

- (UIImage*)imageStandardizedWithOrientation:(bool)reorient
{
    NSDictionary* imageOptions = nil;
    
    if (reorient) {
        CGImagePropertyOrientation orientation = CGImagePropertyOrientationForUIImageOrientation(self.imageOrientation);
        
        imageOptions = @{
            kCIImageApplyOrientationProperty : @true,
            kCIImageProperties : @{
                (__bridge NSString*)kCGImagePropertyOrientation : @(orientation)
            }
        };
    }
    
    CIImage* reorientated = [[CIImage alloc]
        initWithImage:self
        options:imageOptions
    ];
    
    CIContext* context = [CIContext contextWithOptions:nil];
    CGImageRef colorCorrected = [context
        createCGImage:reorientated
        fromRect:[reorientated extent]
        format:kCIFormatRGBA8
        colorSpace:CGColorSpaceCreateWithName(kCGColorSpaceSRGB)
    ];
    
    if (!colorCorrected) {
        return nil;
    }
    
    UIImage* standardized = [UIImage imageWithCGImage:colorCorrected];
    CGImageRelease(colorCorrected);
    
    return standardized;
}

- (UIImage*)imageByScalingAndCroppingForSize:(CGSize)targetSize
{
    UIImage* sourceImage = self;
    UIImage* newImage = nil;
    CGSize imageSize = sourceImage.size;
    CGFloat width = imageSize.width;
    CGFloat height = imageSize.height;
    CGFloat targetWidth = MIN(targetSize.width, width);
    CGFloat targetHeight = MIN(targetSize.height, height);
    CGFloat scaleFactor = 0.0;
    CGFloat scaledWidth = targetWidth;
    CGFloat scaledHeight = targetHeight;
    CGPoint thumbnailPoint = CGPointMake(0.0, 0.0);
    
    if (CGSizeEqualToSize(imageSize, targetSize) == NO) {
        CGFloat widthFactor = targetWidth / width;
        CGFloat heightFactor = targetHeight / height;
        
        if (widthFactor > heightFactor) {
            scaleFactor = widthFactor; // scale to fit height
        } else {
            scaleFactor = heightFactor; // scale to fit width
        }
        scaledWidth = width * scaleFactor;
        scaledHeight = height * scaleFactor;
        
        // center the image
        if (widthFactor > heightFactor) {
            thumbnailPoint.y = (targetHeight - scaledHeight) * 0.5;
        } else if (widthFactor < heightFactor) {
            thumbnailPoint.x = (targetWidth - scaledWidth) * 0.5;
        }
    }
        
    CGRect thumbnailRect = CGRectZero;
    thumbnailRect.origin = thumbnailPoint;
    thumbnailRect.size.width = scaledWidth;
    thumbnailRect.size.height = scaledHeight;

    CGFloat scale = [UIScreen mainScreen].scale;
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(sourceImage.CGImage);
    CGBitmapInfo bitmapInfo = CGImageGetBitmapInfo(sourceImage.CGImage);
    
    CGContextRef context = CGBitmapContextCreate(
        NULL,
        targetSize.width,
        targetSize.height,
        CGImageGetBitsPerComponent(sourceImage.CGImage),
        0,
        colorSpace,
        bitmapInfo
    );

    if (!context) {
        // this will ignore color space used in source and probably fallback to sRGB
        NSLog(@"Falling back to UIGraphicsImageContext: propably ignoring color profile");
        UIGraphicsBeginImageContext(targetSize);
        context = UIGraphicsGetCurrentContext();
    }

    CGContextDrawImage(context, thumbnailRect, sourceImage.CGImage);

    CGImageRef cgImage = CGBitmapContextCreateImage(context);
    newImage = [UIImage
        imageWithCGImage:cgImage
        scale:scale
        orientation:UIImageOrientationUp
    ];
    
    if (newImage == nil) {
        NSLog(@"could not scale and crop image");
    }
    
    CGImageRelease(cgImage);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    
    UIGraphicsPopContext();
    UIGraphicsEndImageContext();
    
    return newImage;
}

- (UIImage*)imageCorrectedForCaptureOrientation:(UIImageOrientation)imageOrientation
{
    float rotationInRadiens = 0;
    bool aspectChange = false;
    
    switch (imageOrientation) {
        case UIImageOrientationUp :
            rotationInRadiens = 0.0;
            break;
            
        case UIImageOrientationDown:
            rotationInRadiens = M_PI; // don't be scared of radians, if you're reading this, you're good at math
            break;
            
        case UIImageOrientationRight:
            rotationInRadiens = -M_PI_2;
            aspectChange = true;
            break;
            
        case UIImageOrientationLeft:
            rotationInRadiens = M_PI_2;
            aspectChange = true;
            break;
            
        default:
            break;
    }
    
    CGImageRef sourceImage = self.CGImage;

    CGColorSpaceRef colorSpace = CGImageGetColorSpace(sourceImage);
    CGBitmapInfo bitmapInfo = CGImageGetBitmapInfo(sourceImage);
    
    CGSize bitmapSize = aspectChange ? CGSizeMake(self.size.height, self.size.width) : self.size;
    NSLog(@"Got image size %@ and bitmap size %@", NSStringFromCGSize(bitmapSize), NSStringFromCGSize(bitmapSize));
    
    CGContextRef context = CGBitmapContextCreate(
        NULL,
        self.size.width,
        self.size.height,
        CGImageGetBitsPerComponent(sourceImage),
        0,
        colorSpace,
        bitmapInfo
    );

    if (!context) {
        // this will ignore color space used in source and probably fallback to sRGB
        NSLog(@"Falling back to UIGraphicsImageContext: propably ignoring color profile");
        UIGraphicsBeginImageContext(self.size);
        context = UIGraphicsGetCurrentContext();
    }
    
    CGContextTranslateCTM(context, self.size.width/2, self.size.height/2);
    CGContextRotateCTM(context, rotationInRadiens);
    
    CGRect drawRect = CGRectMake(-bitmapSize.width/2, -bitmapSize.height/2, bitmapSize.width, bitmapSize.height);
    CGContextDrawImage(context, drawRect, self.CGImage);
    
    CGImageRef rotatedImageRef = CGBitmapContextCreateImage(context);
    UIImage *newImage = [UIImage imageWithCGImage:rotatedImageRef scale:self.scale orientation:UIImageOrientationUp];
    
    if (newImage == nil) {
        NSLog(@"could not rotate image");
    }

    CGImageRelease(rotatedImageRef);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    
    UIGraphicsPopContext();
    UIGraphicsEndImageContext();

    return newImage;
}

- (UIImage*)imageCorrectedForCaptureOrientation
{
    return [self imageCorrectedForCaptureOrientation:[self imageOrientation]];
}

- (UIImage*)imageByScalingNotCroppingForSize:(CGSize)targetSize
{
    UIImage* sourceImage = self;
    UIImage* newImage = nil;
    CGSize imageSize = sourceImage.size;
    CGFloat width = imageSize.width;
    CGFloat height = imageSize.height;
    CGFloat targetWidth = MIN(targetSize.width, width);
    CGFloat targetHeight = MIN(targetSize.height, height);
    CGFloat scaleFactor = 0.0;
    CGSize scaledSize = targetSize;
    
    if (CGSizeEqualToSize(imageSize, targetSize) == NO) {
        CGFloat widthFactor = targetWidth / width;
        CGFloat heightFactor = targetHeight / height;
        
        // opposite comparison to imageByScalingAndCroppingForSize in order to contain the image within the given bounds
        if (widthFactor > heightFactor) {
            scaleFactor = heightFactor; // scale to fit height
        } else {
            scaleFactor = widthFactor; // scale to fit width
        }
        if (scaleFactor >= 1.0) {
            // do not upscale image
            return nil;
        }
        scaledSize = CGSizeMake(MIN(width * scaleFactor, targetWidth), MIN(height * scaleFactor, targetHeight));
    }
    
    // If the pixels are floats, it causes a white line in iOS8 and probably other versions too
    scaledSize.width = (int)scaledSize.width;
    scaledSize.height = (int)scaledSize.height;
    
    CGColorSpaceRef colorSpace = CGImageGetColorSpace(sourceImage.CGImage);
    CGBitmapInfo bitmapInfo = CGImageGetBitmapInfo(sourceImage.CGImage);
    
    CGContextRef context = CGBitmapContextCreate(
        NULL,
        scaledSize.width,
        scaledSize.height,
        CGImageGetBitsPerComponent(sourceImage.CGImage),
        0,
        colorSpace,
        bitmapInfo
    );

    if (!context) {
        // this will ignore color space used in source and probably fallback to sRGB
        NSLog(@"Falling back to UIGraphicsImageContext: propably ignoring color profile");
        UIGraphicsBeginImageContext(scaledSize);
        context = UIGraphicsGetCurrentContext();
    }
    
    CGRect drawRect = CGRectMake(0, 0, scaledSize.width, scaledSize.height);
    CGContextDrawImage(context, drawRect, self.CGImage);
    
    CGImageRef rotatedImageRef = CGBitmapContextCreateImage(context);
    newImage = [UIImage imageWithCGImage:rotatedImageRef scale:self.scale orientation:UIImageOrientationUp];
    
    if (newImage == nil) {
        NSLog(@"could not scale image");
    }
    
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);
    
    UIGraphicsPopContext();
    UIGraphicsEndImageContext();
    
    return newImage;
}

CGImagePropertyOrientation CGImagePropertyOrientationForUIImageOrientation(UIImageOrientation orientation) {
    switch (orientation) {
        case UIImageOrientationUp: return kCGImagePropertyOrientationUp;
        case UIImageOrientationDown: return kCGImagePropertyOrientationDown;
        case UIImageOrientationLeft: return kCGImagePropertyOrientationLeft;
        case UIImageOrientationRight: return kCGImagePropertyOrientationRight;
        case UIImageOrientationUpMirrored: return kCGImagePropertyOrientationUpMirrored;
        case UIImageOrientationDownMirrored: return kCGImagePropertyOrientationDownMirrored;
        case UIImageOrientationLeftMirrored: return kCGImagePropertyOrientationLeftMirrored;
        case UIImageOrientationRightMirrored: return kCGImagePropertyOrientationRightMirrored;
    }
}

@end
