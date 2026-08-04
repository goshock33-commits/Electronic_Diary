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
import {LogUtil} from './LogUtil';

/**
 * 判断Rawfile目录下该文件是否存在
 *
 * @param context 上下文
 * @param filePath 文件路径
 * @returns 存在返回true，不存在返回false
 */
export const isRawFileExist = (context, filePath) => {
    try {
        context.resourceManager?.getRawFileContentSync(filePath);
        return true;
    } catch (err) {
        return false;
    }
};

/**
 * 判断沙箱路径下该文件是否存在
 *
 * @param filePath 文件路径
 * @returns 存在返回true，不存在返回false
 */
export const isSandboxFileExist = (filePath) => {
    try {
        let isExist = fs.accessSync(filePath);
        return isExist;
    } catch (err) {
        return false;
    }
};

/**
 * 同步写入文件
 *
 * @param filePath 文件路径
 * @param data 要写入的数据
 * @returns 写入成功返回true，失败返回false
 */
export const writeFileSync = (filePath, data) => {
    try {
        let file = fs.openSync(filePath, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE);
        fs.writeSync(file.fd, data);
        fs.close(file);
        return true;
    } catch (err) {
        return false;
    }
};

/**
 * 同步读取文件
 *
 * @param filePath 文件路径
 * @returns 读取成功返回数据，失败返回false
 */
export const readFileSync = (filePath) => {
    try {
        // 打开文件
        let file = fs.openSync(filePath, fs.OpenMode.READ_ONLY);
        // 以同步方法获取文件详细属性信息
        let stat = fs.statSync(filePath);
        // 读取文件
        let arrayBuffer = new ArrayBuffer(stat.size);
        // 以同步方法从文件读取数据
        fs.readSync(file.fd, arrayBuffer);
        fs.close(file);
        return arrayBuffer;
    } catch (err) {
        return false;
    }
};

/**
 * 同步移动文件到指定路径
 *
 * @param srcPath - 源文件的路径
 * @param destPath - 目标路径，文件将被移动到此处
 */
export const moveFileSync = (srcPath, destPath) => {
    try {
        fs.moveFileSync(srcPath, destPath);
    } catch (err) {
        LogUtil.error(`Method moveFileSync err: ${JSON.stringify(err)}`);
    }
};

/**
 * 同步创建目录
 *
 * @param path - 要创建的目录路径
 * @param rescursion - 是否递归创建目录及其父目录
 */
export const mkdirSync = (path, rescursion) => {
    try {
        if (!fs.accessSync(path)) {
            fs.mkdirSync(path, rescursion);
        }
    } catch (err) {
        LogUtil.error(`Method mkdirSync err: ${JSON.stringify(err)}`);
    }
};

/**
 * 同步列出指定目录下的文件，并支持根据后缀名过滤文件
 *
 * @param path - 要列出文件的目录路径
 * @param suffix - 文件后缀名过滤条件（例如 '.png', '.jpg', '.jpeg'）
 * @returns 返回匹配的文件列表，如果发生错误则返回空数组
 */
export const listFileSync = (path, suff) => {
    try {
        let listFileOption = {
            recursion: false, // 是否递归列出子目录中的文件
            listNum: 0, // 返回的文件数量限制，0 表示无限制
            filter: {
                suffix: suff, // 匹配指定后缀名的文件
                displayName: ['*'], // 匹配所有文件名
                fileSizeOver: 0, // 匹配文件大小大于等于 0 的文件
                lastModifiedAfter: new Date(0).getTime(), // 匹配文件最近修改时间在1970年1月1日之后
            },
        };
        return fs.listFileSync(path, listFileOption);
    } catch (err) {
        LogUtil.error(`Method listFileSync err: ${JSON.stringify(err)}`);
        return [];
    }
};

/**
 * 同步删除文件（封装fs.unlinkSync并添加错误处理）
 * @param {string} filePath - 要删除的文件绝对路径
 */
export const unlinkSync = (filePath) => {
    try {
        fs.unlinkSync(filePath);
    } catch (err) {
        LogUtil.error(`Method unlinkSync err: ${JSON.stringify(err)}`);
    }
};

/**
 * 异步删除文件（封装fs.unlink并添加错误处理）
 * @param {string} filePath - 要删除的文件绝对路径
 */
export const unlink = (filePath) => {
    fs.unlink(filePath)
        .catch((err) => {
            LogUtil.error(`Method unlink err: ${JSON.stringify(err)}`);
        });
};

/**
 * 同步删除目录
 * @param {string} filePath - 要删除的文件绝对路径
 */
export const rmdirSync = (filePath) => {
    try {
        fs.rmdirSync(filePath);
    } catch (err) {
        LogUtil.error(`Method rmdirSync err: ${JSON.stringify(err)}`);
    }
};

/**
 * 同步获取目录文件列表
 * @param {string} filePath - 要扫描的目标目录绝对路径
 * @returns {Array<string>} 成功时返回文件名列数组，失败时返回空数组
 */
export const listFileSyncs = (filePath) => {
    try {
        let filenames = fs.listFileSync(filePath);
        return filenames;
    } catch (err) {
        LogUtil.error(`Method rmdirSync err: ${JSON.stringify(err)}`);
        return [];
    }
};