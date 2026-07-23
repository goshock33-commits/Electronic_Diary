// <!-- agentID: HUI-026 -->
// 组件：任务来源指示器（QQ/微信/小艺/剪贴板 — 4来源图标+颜色差异化）
// 关联设计稿：UX-001_prototype.html
// 关联任务：F12（PLN-002 阶段6 任务提取模块UI）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 无障碍：accessibilityText
// 深色适配：HUI-023 改为读 theme_tokens（黑白手绘主题，来源差异由图标+文案承担，颜色不再作唯一区分）

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-029：追加 SKETCH_BODY=清松手写体2（来源名称标签）。
import { IconMapper, SKETCH_BODY } from '@ohos/shared';

/**
 * 来源配置接口
 */
interface SourceConfig {
  icon: Resource;
  label: string;
  color: string;
  /** 浅底色（用于文字+图标背景） */
  bgColor: string;
}

/**
 * 任务来源指示器组件
 *
 * HUI-023：原四来源各有品牌色（QQ蓝/微信青/小艺紫/剪贴板青），已改为手绘黑白主题——
 * 文字与图标统一读 tokens.textPrimary（墨色），背景读 tokens.accent（浅墨底），
 * 来源差异改由「图标 + 文案」承担（颜色非唯一区分手段）。config 内保留的字面量仅作 token 缺失兜底。
 */
@Component
export struct TaskSourceIndicator {
  @Prop source: string = 'clipboard';
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  /** 四来源配置表（color/bgColor 已改黑白兜底；实际渲染优先读 token） */
  private sourceConfigMap: Record<string, SourceConfig> = {
    'qq': {
      icon: $r('sys.symbol.message_fill'),
      label: 'QQ',
      color: '#000000',
      bgColor: '#F2F2F2'
    },
    'wechat': {
      icon: $r('sys.symbol.ellipsis_message_1'),
      label: '微信',
      color: '#000000',
      bgColor: '#F2F2F2'
    },
    'voice': {
      icon: IconMapper.MIC,
      label: '小艺语音',
      color: '#000000',
      bgColor: '#F2F2F2'
    },
    'clipboard': {
      icon: $r('sys.symbol.doc_text_fill'),  // grep验证: doc_fill不在全量图标库, 替换为doc_text_fill(F00BF)
      label: '剪贴板',
      color: '#000000',
      bgColor: '#F2F2F2'
    }
  };

  /** 兜底来源配置 */
  private fallbackConfig: SourceConfig = {
    icon: $r('sys.symbol.doc_text_fill'),  // grep验证: doc_fill不在全量图标库, 替换为doc_text_fill(F00BF)
    label: '未知来源',
    color: '#8A8A8A',
    bgColor: '#F2F2F2'
  };

  build() {
    Row() {
      SymbolGlyph(this.getSourceCfg().icon)
        .fontSize(12)
        .fontColor([this.tokens ? this.tokens.textPrimary : this.getSourceCfg().color])
        .margin({ right: 4 })

      Text(this.getSourceCfg().label)
        .fontSize(10)
        .fontWeight(600)
        .fontColor(this.tokens ? this.tokens.textPrimary : this.getSourceCfg().color)
        .attributeModifier(SKETCH_BODY) // HUI-029：来源名称标签→清松手写体2
    }
    .padding({ left: 8, right: 8, top: 3, bottom: 3 })
    .borderRadius(10)
    .backgroundColor(this.tokens ? this.tokens.accent : this.getSourceCfg().bgColor)
    .border({
      width: 1,
      color: this.tokens ? this.tokens.border : (this.getSourceCfg().color + '40')
    })
    .accessibilityText('任务来源：' + this.getSourceCfg().label)
  }

  private getSourceCfg(): SourceConfig {
    return this.sourceConfigMap[this.source] ?? this.fallbackConfig;
  }
}
