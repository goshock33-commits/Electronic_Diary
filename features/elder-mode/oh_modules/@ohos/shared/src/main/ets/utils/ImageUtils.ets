// <!-- agentID: DEV-001 -->
// File: ImageUtils.ets
// Task: T007b Media utility - Image compression, path handling, sandbox storage, thumbnails
// Architecture: ARC-001 4.4 ImageKit
// Skill Ref: frontend-design / ui-ux-pro-max

import { image } from '@kit.ImageKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { fileIo } from '@kit.CoreFileKit';

const TAG = 'ImageUtils';

export interface ImageInfo {
  width: number;
  height: number;
  fileSize: number;
  mimeType: string;
}

export interface ThumbnailResult {
  originalUri: string;
  thumbnailUri: string;
  width: number;
  height: number;
}

/**
 * ImageUtils - Image processing utilities.
 * Handles: compression, path handling, sandbox storage, thumbnail generation.
 */
export class ImageUtils {
  private static readonly THUMBNAIL_DIR = 'thumbnails';
  private static readonly IMAGE_DIR = 'images';

  /** Maximum dimensions for diary images (limits file size). */
  static readonly MAX_IMAGE_WIDTH = 1920;
  static readonly MAX_IMAGE_HEIGHT = 1920;

  /** Thumbnail dimensions. */
  static readonly THUMBNAIL_WIDTH = 240;
  static readonly THUMBNAIL_HEIGHT = 240;

  /** JPEG compression quality (0-100). */
  static readonly COMPRESSION_QUALITY = 85;

  /**
   * Generate a sandbox file path for storing an image.
   * @param baseDir Application files directory.
   * @param prefix File name prefix.
   * @returns Full sandbox file path.
   */
  static generateImagePath(baseDir: string, prefix: string = 'img'): string {
    const timestamp = Date.now();
    const random = Math.floor(Math.random() * 10000);
    const fileName = `${prefix}_${timestamp}_${random}.jpg`;
    const imageDir = baseDir + '/' + ImageUtils.IMAGE_DIR;
    ImageUtils.ensureDir(imageDir);
    return imageDir + '/' + fileName;
  }

  /**
   * Generate a thumbnail file path for a given image.
   */
  static generateThumbnailPath(baseDir: string, originalName: string): string {
    const thumbDir = baseDir + '/' + ImageUtils.THUMBNAIL_DIR;
    ImageUtils.ensureDir(thumbDir);
    const baseName = originalName.substring(originalName.lastIndexOf('/') + 1);
    return thumbDir + '/thumb_' + baseName;
  }

  /**
   * Get basic image information (dimensions, file size, MIME type).
   * @param imageUri URI of the image (file:// or sandbox path).
   */
  static async getImageInfo(imageUri: string): Promise<ImageInfo | null> {
    try {
      let filePath = imageUri;
      if (imageUri.startsWith('file://')) {
        filePath = imageUri.substring(7);
      }
      const stat = fileIo.statSync(filePath);
      const imageSource = image.createImageSource(filePath);
      const imageInfo = await imageSource.getImageInfo();

      return {
        width: imageInfo.size.width,
        height: imageInfo.size.height,
        fileSize: stat.size,
        mimeType: imageInfo.mimeType ?? 'image/jpeg'
      };
    } catch (err) {
      hilog.error(0x0000, TAG, 'Failed to get image info: %{public}s', JSON.stringify(err));
      return null;
    }
  }

  /**
   * Compress an image to fit within max dimensions and target file size.
   * Creates a compressed copy in the target path.
   *
   * @param sourceUri Source image URI.
   * @param targetPath Output path for compressed image.
   * @param maxWidth Maximum width in pixels.
   * @param maxHeight Maximum height in pixels.
   * @param quality JPEG quality (0-100).
   */
  static async compressImage(
    sourceUri: string,
    targetPath: string,
    maxWidth: number = ImageUtils.MAX_IMAGE_WIDTH,
    maxHeight: number = ImageUtils.MAX_IMAGE_HEIGHT,
    quality: number = ImageUtils.COMPRESSION_QUALITY
  ): Promise<string | null> {
    try {
      let filePath = sourceUri;
      if (sourceUri.startsWith('file://')) {
        filePath = sourceUri.substring(7);
      }
      const imageSource = image.createImageSource(filePath);
      const imageInfo = await imageSource.getImageInfo();
      let scale = 1.0;
      if (imageInfo.size.width > maxWidth) {
        scale = maxWidth / imageInfo.size.width;
      }
      if (imageInfo.size.height * scale > maxHeight) {
        scale = maxHeight / imageInfo.size.height;
      }

      const decodeOpts: image.DecodingOptions = {
        desiredSize: {
          width: Math.floor(imageInfo.size.width * scale),
          height: Math.floor(imageInfo.size.height * scale)
        }
      };
      const pixelMap = await imageSource.createPixelMap(decodeOpts);

      const packOpts: image.PackingOption = {
        format: 'image/jpeg',
        quality: quality
      };
      const imagePacker = image.createImagePacker();
      const arrayBuffer = await imagePacker.packing(pixelMap, packOpts);

      // Write compressed data to target path
      const file = fileIo.openSync(targetPath, fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY);
      fileIo.writeSync(file.fd, arrayBuffer);
      fileIo.closeSync(file);

      // Clean up
      pixelMap.release();
      imagePacker.release();

      hilog.info(0x0000, TAG, 'Image compressed: %{public}s -> %{public}s', sourceUri, targetPath);
      return targetPath;
    } catch (err) {
      hilog.error(0x0000, TAG, 'Image compression failed: %{public}s', JSON.stringify(err));
      return null;
    }
  }

  /**
   * Generate a thumbnail for an image.
   * @param sourceUri Source image URI.
   * @param baseDir Application files directory.
   * @returns Thumbnail result or null on failure.
   */
  static async generateThumbnail(sourceUri: string, baseDir: string): Promise<ThumbnailResult | null> {
    try {
      const thumbPath = ImageUtils.generateThumbnailPath(baseDir, sourceUri);
      const result = await ImageUtils.compressImage(
        sourceUri,
        thumbPath,
        ImageUtils.THUMBNAIL_WIDTH,
        ImageUtils.THUMBNAIL_HEIGHT,
        70
      );
      if (result) {
        const info = await ImageUtils.getImageInfo(result);
        return {
          originalUri: sourceUri,
          thumbnailUri: 'file://' + result,
          width: info?.width ?? ImageUtils.THUMBNAIL_WIDTH,
          height: info?.height ?? ImageUtils.THUMBNAIL_HEIGHT
        };
      }
      return null;
    } catch (err) {
      hilog.error(0x0000, TAG, 'Thumbnail generation failed: %{public}s', JSON.stringify(err));
      return null;
    }
  }

  /**
   * Delete an image file from sandbox storage.
   * @param imageUri URI of the image to delete.
   */
  static deleteImage(imageUri: string): boolean {
    try {
      let filePath = imageUri;
      if (imageUri.startsWith('file://')) {
        filePath = imageUri.substring(7);
      }
      fileIo.unlinkSync(filePath);
      hilog.info(0x0000, TAG, 'Image deleted: %{public}s', filePath);
      return true;
    } catch (err) {
      hilog.error(0x0000, TAG, 'Failed to delete image: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  /**
   * Copy an image to sandbox storage (for imported/shared images).
   * @param sourceUri Source image URI.
   * @param baseDir Application files directory.
   * @returns New sandbox URI or null on failure.
   */
  static async copyToSandbox(sourceUri: string, baseDir: string): Promise<string | null> {
    try {
      let srcPath = sourceUri;
      if (sourceUri.startsWith('file://')) {
        srcPath = sourceUri.substring(7);
      }
      const destPath = ImageUtils.generateImagePath(baseDir);
      fileIo.copyFileSync(srcPath, destPath);
      hilog.info(0x0000, TAG, 'Image copied to sandbox: %{public}s', destPath);
      return 'file://' + destPath;
    } catch (err) {
      hilog.error(0x0000, TAG, 'Failed to copy image to sandbox: %{public}s', JSON.stringify(err));
      return null;
    }
  }

  /**
   * Get total size of all stored images (excluding thumbnails).
   */
  static getTotalImageSize(baseDir: string): number {
    try {
      const imageDir = baseDir + '/' + ImageUtils.IMAGE_DIR;
      ImageUtils.ensureDir(imageDir);
      const files = fileIo.listFileSync(imageDir);
      let totalSize = 0;
      for (const file of files) {
        totalSize += fileIo.statSync(imageDir + '/' + file).size;
      }
      return totalSize;
    } catch (_err) {
      return 0;
    }
  }

  private static ensureDir(dirPath: string): void {
    try {
      fileIo.mkdirSync(dirPath, true);
    } catch (_err) {
      // Directory already exists
    }
  }
}
