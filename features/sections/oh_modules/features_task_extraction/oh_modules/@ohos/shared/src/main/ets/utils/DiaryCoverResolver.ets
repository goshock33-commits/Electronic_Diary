// <!-- agentID: DEV-001 -->
// 文件: shared/src/main/ets/utils/DiaryCoverResolver.ets
// 任务: 日记卡片封面解析工具（业务逻辑层，UI 无关）
// 契约: resolveDiaryCover(diary, indexInRecentList) → string | Resource，可直接喂 ArkUI Image()
// 关联模型: shared/src/main/ets/data/Diary.ets（id: number / images: string / getImageList(): string[]）
// Skill 参考：frontend-design / ui-ux-pro-max
// 规范参考：PROJECT_SPEC §8 严格模式（无 any/Object；字符串数组元素类型可推断）
//           PROJECT_SPEC §9.3 崩溃防范（$rawfile 不落字段/模块初值，仅在函数调用时用字符串变量构造 Resource）
// API 依据：本地 SDK ets/component/common.d.ts:2414 `declare function $rawfile(value: string): Resource;`（接受字符串变量）
//           跨模块 rawfile 先例：entry/.../EntryAbility.ets 用 $rawfile('fonts/...')；shared/LottieAnimation 引用 rawfile/animations/*
//           返回类型 string | Resource 即 ArkUI ResourceStr，Image() 直接可用

import { Diary } from '../data/Diary';

// 内置封面文件名（部署于 entry/src/main/resources/rawfile/covers/，随 HAP 自动打包）。
// 顺序 = 复制顺序：cover_00..cover_17 为 18 张编号原图，cover_18 为 猫爪。
// 存字符串而非 Resource：规避在模块加载/字段初始化期创建 $rawfile 资源（PROJECT_SPEC §9.3），
// Resource 仅在 resolveDiaryCover 被调用时按需构造。
const BUILTIN_COVER_FILES: string[] = [
  'covers/cover_00.jpeg', 'covers/cover_01.jpeg', 'covers/cover_02.jpeg',
  'covers/cover_03.jpeg', 'covers/cover_04.jpeg', 'covers/cover_05.jpeg',
  'covers/cover_06.jpeg', 'covers/cover_07.jpeg', 'covers/cover_08.jpeg',
  'covers/cover_09.jpeg', 'covers/cover_10.jpeg', 'covers/cover_11.jpeg',
  'covers/cover_12.jpeg', 'covers/cover_13.jpeg', 'covers/cover_14.jpeg',
  'covers/cover_15.jpeg', 'covers/cover_16.jpeg', 'covers/cover_17.jpeg',
  'covers/cover_18.jpeg'
];

// 内置封面总数（19）。对外只读常量，供上层需要时参考。
export const BUILTIN_COVER_COUNT: number = BUILTIN_COVER_FILES.length;

/**
 * 解析日记卡片封面。
 *
 * 规则：
 *   ① diary.getImageList() 非空 → 返回首张上传图 URI（string），用户自定义封面优先；
 *   ② 否则按稳定 id 从 19 张内置封面确定性取图：idx = id % 19。
 *      - 同一篇日记恒定同图（id 稳定不漂移）；
 *      - 相邻 id 映射相邻封面，相邻篇尽量不撞图；
 *      - id 未落库（<=0）时退化用 indexInRecentList，保证列表内仍确定。
 *
 * 返回 string | Resource（即 ArkUI ResourceStr），两者均可直接作为 Image() 入参。
 *
 * @param diary 日记实体（@ohos/shared Diary）
 * @param indexInRecentList 该日记在最近列表中的下标，仅在 id 未落库（<=0）时用作稳定回退
 * @returns 上传图 URI（string）或内置封面（Resource）
 */
export function resolveDiaryCover(diary: Diary, indexInRecentList: number): string | Resource {
  const uploaded: string[] = diary.getImageList();
  if (uploaded.length > 0) {
    const first: string = uploaded[0];
    if (first.length > 0) {
      return first;
    }
  }
  const seed: number = diary.id > 0 ? diary.id : indexInRecentList;
  const count: number = BUILTIN_COVER_COUNT;
  const idx: number = ((seed % count) + count) % count;
  return $rawfile(BUILTIN_COVER_FILES[idx]);
}
