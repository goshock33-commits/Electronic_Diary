// <!-- agentID: HUI-001 -->
// 模块：沉浸光感毛玻璃工具类
// 关联设计稿：UX-001_prototype.html（--blur-light/--blur-medium/--blur-heavy）
// 关联任务：T006a
// 关联需求：需求 11 全局设计要求（沉浸光感材质）
// 关联架构：4.1 主题系统 API（FrostedGlassUtils.applyFrostedEffect）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式

import { LengthMetricsUnit } from '@kit.ArkUI';
import type { FrostedBlurPack } from './ThemeConfig';
import { FrostedBlurLevel } from './ThemeConfig';

/**
 * 沉浸光感毛玻璃工具类
 * 提供三级毛玻璃效果参数（强/均衡/弱），与主题色板协调适配
 *
 * 设计原则（参照 HarmonyOS 沉浸光感材质规范）：
 * - 轻模糊：背景隐约可见，适用于导航栏、小卡片，模糊半径 4vp
 * - 均衡模糊：背景半透，适用于弹窗、面板，模糊半径 8vp
 * - 强模糊：背景高度雾化，适用于全屏覆盖层，模糊半径 12vp
 *
 * 使用方式：
 * ```typescript
 * // 方式1：获取 BlurStyle（用于 .backgroundBlurStyle()）
 * .backgroundBlurStyle(FrostedGlassUtils.getBlurStyle(FrostedBlurLevel.MEDIUM))
 *
 * // 方式2：获取完整参数包（用于手动组合效果）
 * const pack = FrostedGlassUtils.getBlurPack(FrostedBlurLevel.LIGHT);
 * .backdropBlur(pack.blurRadius)
 * .backgroundColor(Color.alpha(pack.backgroundOpacity))
 * .saturate(pack.saturation)
 * .brightness(pack.brightness)
 * ```
 */
export class FrostedGlassUtils {

  /**
   * 获取对应等级的 ArkUI 系统 BlurStyle
   * 用于 .backgroundBlurStyle() 链式调用
   *
   * @param level 模糊等级 (1=轻, 2=均衡, 3=强)
   * @returns ArkUI BlurStyle 枚举值
   */
  static getBlurStyle(level: FrostedBlurLevel): BlurStyle {
    switch (level) {
      case FrostedBlurLevel.LIGHT:
        return BlurStyle.Thin;
      case FrostedBlurLevel.MEDIUM:
        return BlurStyle.Regular;
      case FrostedBlurLevel.HEAVY:
        return BlurStyle.Thick;
      default:
        return BlurStyle.Regular;
    }
  }

  /**
   * 获取对应等级的背景模糊半径（vp）
   * 用于 .backdropBlur() 链式调用
   *
   * @param level 模糊等级 (1=轻, 2=均衡, 3=强)
   * @returns 模糊半径值（单位 vp）
   */
  static getBackdropBlurRadius(level: FrostedBlurLevel): number {
    switch (level) {
      case FrostedBlurLevel.LIGHT:
        return 4;
      case FrostedBlurLevel.MEDIUM:
        return 8;
      case FrostedBlurLevel.HEAVY:
        return 12;
      default:
        return 8;
    }
  }

  /**
   * 获取对应等级的完整毛玻璃参数包
   * 包含背景模糊、透明度、饱和度、亮度参数
   *
   * @param level 模糊等级 (1=轻, 2=均衡, 3=强)
   * @returns 毛玻璃参数包
   */
  static getBlurPack(level: FrostedBlurLevel): FrostedBlurPack {
    switch (level) {
      case FrostedBlurLevel.LIGHT:
        return {
          blurRadius: 4,
          backgroundOpacity: 0.65,
          saturation: 1.0,
          brightness: 1.0
        };
      case FrostedBlurLevel.MEDIUM:
        return {
          blurRadius: 8,
          backgroundOpacity: 0.75,
          saturation: 1.1,
          brightness: 1.0
        };
      case FrostedBlurLevel.HEAVY:
        return {
          blurRadius: 12,
          backgroundOpacity: 0.85,
          saturation: 1.2,
          brightness: 0.95
        };
      default:
        return {
          blurRadius: 8,
          backgroundOpacity: 0.75,
          saturation: 1.1,
          brightness: 1.0
        };
    }
  }

  /**
   * 获取对应等级的背景不透明度
   * 用于 .backgroundColor() 配合半透明颜色
   *
   * @param level 模糊等级
   * @returns 不透明度值 (0-1)
   */
  static getBackgroundOpacity(level: FrostedBlurLevel): number {
    return FrostedGlassUtils.getBlurPack(level).backgroundOpacity;
  }

  /**
   * 组合应用毛玻璃效果到组件的 Builder 方法
   * 在 ArkUI 声明式范式下，建议直接在组件链式调用中分散使用上述方法
   * 本方法仅供简单的通用场景使用
   *
   * @param level 模糊等级
   * @returns 毛玻璃参数配置
   */
  static applyFrostedEffect(level: FrostedBlurLevel): FrostedBlurPack {
    return FrostedGlassUtils.getBlurPack(level);
  }
}
