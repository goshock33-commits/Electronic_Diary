/*
 * Copyright (C) 2025 Huawei Device Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the 'License');
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an 'AS IS' BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import fs from '@ohos.file.fs';
import util from '@ohos.util';
import zlib from '@ohos.zlib';
import { moveFileSync, mkdirSync, listFileSync, readFileSync, isSandboxFileExist } from './FileUtil';
import {LogUtil} from './LogUtil';

/**
 * 过滤并返回指定目录下的 JSON 文件
 *
 * @param way - 要扫描的目录路径
 * @param isDotLottiePath - 是否为 .lottie 文件路径的标志
 * @returns 返回找到的 JSON 文件名，如果没有找到则返回 undefined
 */
const filterJson = function (way, isDotLottiePath) {
  try {
    // 以同步方式列出文件夹下所有文件名
    let files = listFileSync(way, ['.json']);
    if (isDotLottiePath) {
      return files.find(item => {
        return item !== 'manifest.json' && item.endsWith('.json');
      });
    } else {
      return files.find(item => item.endsWith('.json'));
    }
  } catch (err) {
    LogUtil.error(`Method filterJson err: ${JSON.stringify(err)}`);
    return undefined;
  }
};

/**
 * 检查指定目录下是否存在包含 JSON 文件的子目录
 *
 * @param way - 要扫描的目录路径
 * @param isDotLottiePath - 是否为 .lottie 文件路径的标志
 * @returns 返回找到的包含 JSON 文件的子目录名，如果没有找到则返回 null
 */
const isHaveDirectory = function (way, isDotLottiePath) {
  try {
    // 以同步方式列出文件夹下所有文件名
    let files = listFileSync(way, ['.json']);
    for (let i = 0; i < files.length; i++) {
      let isDirectory = fs.statSync(`${way}/${files[i]}`).isDirectory();
      if (isDirectory && files[i] !== '__MACOSX' && files[i] !== 'images') {
        if (filterJson(`${way}/${files[i]}`, isDotLottiePath)) {
          return files[i];
        }
      }
    }
  } catch (err) {
    LogUtil.error(`Method isHaveDirectory err: ${JSON.stringify(err)}`);
  }
  return null;
};

/**
 * 将指定目录下的图片文件移动到目标目录的 images 文件夹中
 *
 * @param routerDir  - 目标目录路径
 * @param way - 相对路径，用于指定源目录的位置
 */
const moveImages = function (routerDir, way) {
  try {
    // files创建新images文件夹
    let dirPath = `${routerDir}/images`;
    mkdirSync(dirPath);
    let newWay = `${routerDir}/${way}/images`;
    let files = listFileSync(newWay, ['.png', '.jpg', '.jpeg']);
    for (let i = 0; i < files.length; i++) {
      let srcPath = `${newWay}/${files[i]}`;
      let destPath = `${dirPath}/${files[i]}`;
      moveFileSync(srcPath, destPath);
    }
  } catch (err) {
    LogUtil.error(`Method moveImages err: ${JSON.stringify(err)}`);
  }
};

/**
 * 将指定目录下的 JSON 文件移动到目标目录中
 *
 * @param routerDir - 目标目录路径
 * @param way - 相对路径，用于指定源目录的位置
 */
const moveJson = function (routerDir, way) {
  try {
    let jsonWay = `${routerDir}/${way}`;
    let jsonFile = listFileSync(jsonWay, ['.json']);
    let newJson = jsonFile.find(item => item.endsWith('.json'));
    let srcPath = `${jsonWay}/${newJson}`;
    let destPath = `${routerDir}/${newJson}`;
    moveFileSync(srcPath, destPath);
  } catch (err) {
    LogUtil.error(`Method moveJson err: ${JSON.stringify(err)}`);
  }
};

/**
 *  解压缩并读取 JSON 文件
 *
 * @param url - 文件的 URL 地址
 * @param cacheDir - 缓存目录路径
 * @param fileDir - 目标目录路径
 * @returns 返回一个 Promise，解析为处理后的 JSON 数据
 */
export const decompressAndReadJson = function (url, cacheDir, fileDir) {
  const lastIndex = url.lastIndexOf('/');
  const result = url.substring(lastIndex + 1);
  let isDotLottiePath = url.endsWith('.lottie');
  let inFile = `${cacheDir}/${result}`;
  let outFile = fileDir;
  let options = {
    level: zlib.CompressLevel.COMPRESS_LEVEL_DEFAULT_COMPRESSION,
    memLevel: zlib.MemLevel.MEM_LEVEL_MAX,
    strategy: zlib.CompressStrategy.COMPRESS_STRATEGY_DEFAULT_STRATEGY,
  };
  return new Promise((resolve, reject) => {
    zlib.decompressFile(inFile, outFile, options).then((data) => {
      // 解压完成之后读取 json 数据
      if (isHaveDirectory(fileDir, isDotLottiePath)) {
        let newFileDir = isHaveDirectory(fileDir, isDotLottiePath);
        moveImages(fileDir, newFileDir);
        moveJson(fileDir, newFileDir);
        let zipData = readJson(url, fileDir);
        // 修改u路径
        let newZipData = handleZipAssets(zipData, fileDir);
        resolve(newZipData);
      } else {
        let zipData = readJson(url, fileDir);
        // 修改u路径
        let newZipData = handleZipAssets(zipData, fileDir);
        resolve(newZipData);
      }
    }).catch((errData) => {
      reject(errData);
    });
  });
};

/**
 * 读取并解析 JSON 文件
 *
 * @param url - 文件的 URL 地址
 * @param readPath - 读取路径
 * @param errCallBack - 错误回调函数
 * @returns 返回解析后的 JSON 对象，如果没有解析成功则返回 undefined
 */
export const readJson = function (url, readPath, errCallBack) {
  try {
    let textDecoderOptions = {
      fatal: false,
      ignoreBOM : true,
    };
    let resStr = util.TextDecoder.create('utf-8', textDecoderOptions);
    let existResult = isCacheExist(url, readPath);
    if (existResult?.isExist) {
      let arrayBuffer = readFileSync(existResult.filePath);
      // 解码的json数据
      let lottieStr = resStr.decodeToString(new Uint8Array(arrayBuffer));
      return JSON.parse(lottieStr);
    }
    return undefined;
  } catch (err) {
    LogUtil.error(`Method readJson err: ${JSON.stringify(err)}`);
    if (errCallBack) {
      errCallBack('error', err);
    }
    return undefined;
  }
};

/**
 * 检查指定 URL 对应的文件是否存在于缓存中
 *
 * @param url - 文件的 URL 地址
 * @param readPath - 读取路径
 * @returns 返回一个包含是否存在文件和文件路径的对象，如果出错则返回 undefined
 */
export const isCacheExist = function (url, readPath) {
  try {
    const lastIndex = url.lastIndexOf('/');
    const result = url.substring(lastIndex + 1); // 最后一个斜杠后的字符串  `${readPath}/${filterJson(readPath, url.endsWith('.lottie'))}`
    // 通过沙箱中下载或者解压的文件名来找到文件所在路径
    let filePath = hasSuffix(url, ['.json', '.js']) ? `${readPath}/${result}` :
      `${readPath}/${filterJson(readPath, url.endsWith('.lottie'))}`;
    // 同步方法判断沙箱里的文件是否存在
    let isExist = isSandboxFileExist(filePath);
    return {
      isExist,
      filePath,
    };
  } catch (err) {
    LogUtil.error(`Method isCacheExist err: ${JSON.stringify(err)}`);
    return undefined;
  }
};

/**
 * 检查指定路径下是否存在图片文件
 *
 * @param way - 目标路径
 * @returns 返回一个布尔值，表示是否存在图片文件，如果出错则返回 undefined
 */
export const isHaveImg = function (way) {
  try {
    let imgFiles = listFileSync(way, ['.png', '.jpg', '.jpeg']);
    return imgFiles.some(item => {
      return item.endsWith('.png') || item.endsWith('.jpg') || item.endsWith('.jpeg');
    });
  } catch (err) {
    LogUtil.error(`Method isCacheExist err: ${JSON.stringify(err)}`);
    return undefined;
  }
};


/**
 * 检查URL是否以指定的后缀结尾
 *
 * @param url - 需要检查的URL字符串
 * @param suffixes - 允许的文件后缀数组（如['.json', '.js']）
 * @returns 如果URL以指定后缀之一结尾则返回true，否则返回false
 */
const hasSuffix = function (url, suffixes) {
  const lastDotIndex = url.lastIndexOf('.');
  return lastDotIndex !== -1 && lastDotIndex < url.length - 1 && suffixes.includes(url.substring(lastDotIndex));
};


/**
 * 处理 Lottie 动画数据中的资源路径
 *
 * @param lottieData - Lottie 动画数据对象
 * @returns 返回处理后的 Lottie 动画数据对象
 */
export const handleAssets = function (lottieData) {
  let updatedAssets = lottieData?.assets?.map((item, index) => {
    if (item.id && item.p && item.p.startsWith('http')) {
      item.p = `${item.id}.png`;
      if (!item.u) {
        item.u = 'lottie/loadImages/';
        item.e = 0;
      }
    }
    return item;
  });
  if (lottieData) {
    lottieData.assets = updatedAssets;
  }
  return lottieData;
};

/**
 * 处理 ZIP 压缩包中的 Lottie 动画资源路径
 *
 * @param lottieData - Lottie 动画数据对象
 * @param zipRoute - ZIP 文件的路径
 * @returns 返回处理后的 Lottie 动画数据对象
 */
export const handleZipAssets = function (lottieData, zipRoute) {
  let lastPartStr = `/${zipRoute.split('/files/')[1]}`;

  // 修改u路径
  let updatedZipAssets = lottieData?.assets?.map((item, index) => {
    if (item.id && item.u) {
      item.u = `${lastPartStr}/images/`;
    }
    return item;
  });
  if (lottieData) {
    lottieData.assets = updatedZipAssets;
  }
  return lottieData;
};

/**
 * 创建文件的目录结构
 *
 * @param url - 文件的 URL 地址
 * @returns 返回一个包含文件名和完整路径的对象
 */
export const createFilesDir = function(url) {
  // 提取路径各部分并过滤空值
  const parts = url.split('/').filter(Boolean);

  // 获取文件名（移除最后一部分并处理扩展名）
  const fileNameWithExtension = parts.pop() || '';
  const fileName = fileNameWithExtension.replace(/\.(?:zip|json|lottie)$/i, '');

  // 构建目录路径
  const contextFilesDir = getContext()?.filesDir || '';

  // 根据目录层级构建相对路径
  let relativePath = '';
  if (parts.length >= 2) {
    // 取倒数两个目录
    relativePath = parts.slice(-2).join('/');
  } else if (parts.length === 1) {
    // 只有一个目录
    [relativePath] = parts;
  }
  // 构建完整路径
  const fullPath = `${contextFilesDir}/lottie${relativePath ? `/${relativePath}` : ''}/${fileName}`;

  // 创建目录
  mkdirSync(fullPath, true);

  return {
    dataName: fileNameWithExtension,
    route: fullPath,
  };
};

/**
 * 创建用于加载图片的目录
 * @returns 返回创建的图片目录路径
 */
export const createImageFilesDir = function () {
  let dirImgPath = `${getContext()?.filesDir}/lottie/loadImages`;
  mkdirSync(dirImgPath, true);
  return dirImgPath;
};

/**
 * 合并多个 ArrayBuffer 对象为一个新的 ArrayBuffer
 *
 * @param arrayBuffers - 要合并的 ArrayBuffer 数组
 * @returns 返回合并后的 ArrayBuffer
 */
export const combineArrayBuffers = function (arrayBuffers) {
  // 计算多个ArrayBuffer的总字节大小
  let totalByteLength = 0;
  for (const arrayBuffer of arrayBuffers) {
    totalByteLength += arrayBuffer.byteLength;
  }
  // 创建一个新的ArrayBuffer
  const combinedArrayBuffer = new ArrayBuffer(totalByteLength);
  // 创建一个Uint8Array来操作新的ArrayBuffer
  const combinedUint8Array = new Uint8Array(combinedArrayBuffer);
  // 依次复制每个ArrayBuffer的内容到新的ArrayBuffer中
  let offset = 0;
  for (const arrayBuffer of arrayBuffers) {
    const sourceUint8Array = new Uint8Array(arrayBuffer);
    combinedUint8Array.set(sourceUint8Array, offset);
    offset += sourceUint8Array.length;
  }
  return combinedArrayBuffer;
};

/**
 * 检查给定的 URI 是否为JSON文件
 *
 * @param uri - 要检查的文件 URI
 * @returns 返回一个布尔值，表示 URI 是否以 .json 或 .js 结尾
 */
export const isJsonFile = function (uri) {
  return uri.endsWith('.json') || uri.endsWith('.js');
};

/**
 * 检查给定的 URI 是否为压缩文件或 Lottie 动画文件
 * @param uri - 要检查的文件 URI
 * @returns 返回一个布尔值，表示 URI 是否以 .zip 或 .lottie 结尾
 */
export const isCompressdFile = function (uri) {
  return uri.endsWith('.zip') || uri.endsWith('.lottie');
};

/**
 * 检查给定的资源数组中是否存在网络资源
 *
 * @param assets - 资源数组，每个资源对象包含属性 p
 * @returns 返回一个布尔值，表示资源数组中是否存在以 'http' 开头的网络资源
 */
export const isExistNetworkAssets = function (assets) {
  return assets?.some((item) => {
    return item.p && item.p.startsWith('http');
  });
};
