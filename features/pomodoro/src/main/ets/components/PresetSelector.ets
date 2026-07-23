// <!-- agentID: HUI-062 -->
// 组件：番茄钟预设选择器（25min专注 / 5min短休 / 15min长休 / 自定义1~120min）
// 关联任务：F13（第6批 — 番茄钟模块UI）→ P2-10 薄荷青皮肤统一 → HUI-001 自定义时长
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 令牌：FONT / TYPO —— 全引用，禁散写魔数
//
// === 皮肤 §6.4（薄荷青统一）===
//   选中态：主色 primary (#00C2B8) 填充 + 白色文字 + primaryLight 阴影
//   未选中态：透明背景 + 次要文字色
//   容器：bgCard 底 + primary-tint 边框
//   切换动画：200ms EaseInOut
//
// === 交互设计 ===
//   四个胶囊按钮组（3 预设 + 自定义），选中态高亮（主色填充 + 白色文字 + 阴影）。
//   未选中态透明背景 + 次要文字色。切换有 200ms EaseInOut 过渡动画。
//   容器为带圆角背景 + 细边框的 Row（外包横向 Scroll 防窄屏溢出），内边距 4vp。
//   「自定义」chip：无历史显示「自定义」，有历史显示「自定义 Xmin」；点击（含选中态再点）
//   由页面弹 1~120 分钟选择器（getUIContext().showTextPickerDialog）。
//
// === 无障碍 ===
//   每个按钮 accessibilityText 含预设名称 + 分钟数 + 选中状态提示。

import type { ThemeColorTokens } from '@ohos/shared';

/**
 * 预设选项数据结构
 */
export interface PresetOption {
  /** 显示标签 */
  label: string;
  /** 分钟数 */
  minutes: number;
  /** 预设类型标识 */
  type: string;
}

@Component
export struct PresetSelector {
  /** 预设选项列表 */
  @Prop presets: PresetOption[] = [
    { label: '专注', minutes: 25, type: 'focus' },
    { label: '短休', minutes: 5, type: 'short_break' },
    { label: '长休', minutes: 15, type: 'long_break' }
  ];
  /** 当前选中的预设类型 */
  @Prop activeType: string = 'focus';
  /** 上次自定义分钟数（0 = 无历史，chip 仅显示「自定义」）— HUI-001 自定义时长 */
  @Prop customMinutes: number = 0;
  /** 选中回调 */
  onSelect?: (preset: PresetOption) => void;
  /** 自定义 chip 点击回调（由页面弹分钟选择器；已选中时再点可重新选择）— HUI-001 */
  onCustomSelect?: () => void;
  /** 主题 token */
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  /**
   * 判断指定预设是否为当前选中项
   */
  private isActive(preset: PresetOption): boolean {
    return preset.type === this.activeType;
  }

  /**
   * 获取按钮显示文字（如 "专注 25min"）
   */
  private getButtonLabel(preset: PresetOption): string {
    return preset.label + ' ' + preset.minutes + 'min';
  }

  /**
   * 获取无障碍说明文字
   */
  private getAccessibilityLabel(preset: PresetOption): string {
    const base = preset.label + ' ' + preset.minutes + '分钟';
    return this.isActive(preset) ? base + '，已选中' : base;
  }

  /**
   * 自定义 chip 是否选中 — HUI-001
   */
  private isCustomActive(): boolean {
    return this.activeType === 'custom';
  }

  /**
   * 自定义 chip 文案：有历史值显示「自定义 Xmin」，无历史显示「自定义」— HUI-001
   */
  private getCustomLabel(): string {
    return this.customMinutes > 0 ? '自定义 ' + this.customMinutes + 'min' : '自定义';
  }

  /**
   * 自定义 chip 无障碍说明 — HUI-001
   */
  private getCustomAccessibilityLabel(): string {
    const base = this.customMinutes > 0
      ? '自定义 ' + this.customMinutes + '分钟'
      : '自定义时长';
    return this.isCustomActive()
      ? base + '，已选中，点击可重新选择分钟数'
      : base + '，点击选择分钟数';
  }

  build() {
    // HUI-001：4 个 chip 在窄屏可能超宽，外包横向 Scroll（隐藏滚动条、无回弹），
    //   宽屏下内容不足一屏时表现与原 Row 完全一致。
    //   API24 已验：scroll.d.ts:1302 scrollable / 1645 scrollBar / 1749 edgeEffect。
    Scroll() {
      Row() {
      ForEach(this.presets, (preset: PresetOption) => {
        Button(this.getButtonLabel(preset))
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          // HUI-034：预设 pill 选中 btnPrimaryText 白字，未选中次要墨字
          .fontColor(this.isActive(preset)
            ? (this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
            : (this.tokens ? this.tokens.textSecondary : '#5A5A5A'))
          // HUI-041：预设 pill 未选中底由死白 #FFFFFF 改读 surface token（浅色 #F7F7F7 / 深色 #242424），修深色白底浅灰字不可见
          .backgroundColor(this.isActive(preset)
            ? (this.tokens ? this.tokens.btnPrimary : '#738A9C')
            : (this.tokens ? this.tokens.surface : '#FFFFFF'))
          .borderRadius(20)
          .height(40)
          .padding({ left: 16, right: 16 })
          .shadow(this.isActive(preset) ? {
            radius: 8,
            color: this.tokens ? this.tokens.primaryLight : '#4FD8CE',
            offsetX: 0,
            offsetY: 2
          } : undefined)
          .onClick(() => {
            if (this.onSelect) {
              this.onSelect(preset);
            }
          })
          .accessibilityText(this.getAccessibilityLabel(preset))
          .animation({ duration: 200, curve: Curve.EaseInOut })
      })

      // HUI-001：第 4 个「自定义」chip —— 样式与预设 chip 完全一致（同款选中态/未选中态）。
      //   点击（含已选中再点）交给页面弹分钟选择器，可修改上次自定义值。
      Button(this.getCustomLabel())
        .fontSize(13)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.isCustomActive()
          ? (this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
          : (this.tokens ? this.tokens.textSecondary : '#5A5A5A'))
        .backgroundColor(this.isCustomActive()
          ? (this.tokens ? this.tokens.btnPrimary : '#738A9C')
          : (this.tokens ? this.tokens.surface : '#FFFFFF'))
        .borderRadius(20)
        .height(40)
        .padding({ left: 16, right: 16 })
        .shadow(this.isCustomActive() ? {
          radius: 8,
          color: this.tokens ? this.tokens.primaryLight : '#4FD8CE',
          offsetX: 0,
          offsetY: 2
        } : undefined)
        .onClick(() => {
          if (this.onCustomSelect) {
            this.onCustomSelect();
          }
        })
        .accessibilityText(this.getCustomAccessibilityLabel())
        .animation({ duration: 200, curve: Curve.EaseInOut })
    }
    .borderRadius(24)
    .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
    .border({
      width: 1,
      color: this.tokens ? this.tokens.border : 'rgba(0,194,184,0.15)'
    })
    .padding(4)
    .accessibilityGroup(true)
    }
    .scrollable(ScrollDirection.Horizontal)
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.None)
  }
}
