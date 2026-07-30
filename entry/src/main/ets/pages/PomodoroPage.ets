// <!-- agentID: HUI-062 -->
// fix: HUI-FRONTEND
// agentID: HUI-041（T-D05：返回箭头统一 — 裸 arrow_left 加粗 ICON.navBack）
// agentID: HUI-042（T-D07：系统分钟选择弹窗主题化换肤——showTextPickerDialog 读 theme_tokens，经 PickerDialogTheme 统一映射）
// @Entry 番茄钟页（P2-10 薄荷青皮肤：eyebrow「FOCUS TIMER」+ H1「专注时钟」
//        + PresetSelector + PomodoroTimer）
// 关联任务：UX-001 §6.4 / PLN-003 P2-10
// §1.4 三者一致：模块 name = features/pomodoro = 依赖 key = import 路径
// §9.4：@StorageLink tokens 读取全部判空兜底
// 图标：clock_fill(CLOCK✅) / chevron_left(BACK✅)
// 令牌：IconMapper / RADIUS / SPACING / TYPO / FONT —— 全引用，禁散写魔数
//
// === 崩溃防范（PROJECT_SPEC §9）===
//   §9.1 无 getter-in-build：secondsFor 为普通方法
//   §9.4 @StorageLink tokens 全判空

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-027：引入手绘标题字体助手 SKETCH_TITLE=猫啃什锦黑(eyebrow/H1)；倒计时大数字在 PomodoroTimer 内保留 mono。
import { IconMapper, RADIUS, SPACING, TYPO, ICON, SKETCH_TITLE, PickerDialogTheme, reportPawTouch, PawOverlayLayer } from '@ohos/shared';
// fix: HUI-FRONTEND — F9：累计番茄数 DB 真值 + 完成落库 + SETTINGS_CHANGED 通知资料卡刷新
import { PomodoroDao, PomodoroSession, EventBus } from '@ohos/shared';
import { PomodoroTimer, PresetSelector } from 'features/pomodoro';
import type { PresetOption } from 'features/pomodoro';
import { router } from '@kit.ArkUI';

@Entry
@Component
struct PomodoroPageEntry {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  /** 当前选中的预设类型（focus / short_break / long_break / custom） */
  @State activeType: string = 'focus';
  /** 累计番茄数（fix: HUI-FRONTEND — F9：DB 真值，替换 mock 12；onPageShow 重拉） */
  @State cumulativeTotal: number = 0;
  /** HUI-001：上次自定义分钟数（0 = 无历史）。
   *  持久化：@StorageLink 键 = PersistentState.KEY_POMODORO_CUSTOM_MINUTES
   *  （'persist_pomodoro_custom_minutes'，StartupTasks → PersistentState.initialize 已 persistProp 注册，
   *  写入即自动落盘，重启保留）。 */
  @StorageLink('persist_pomodoro_custom_minutes') customMinutes: number = 0;

  // fix: HUI-FRONTEND — F9：@Entry 页每次显示重拉累计真值（含从设置页返回等场景）
  onPageShow(): void {
    this.loadCumulative();
  }

  /** fix: HUI-FRONTEND — F9：累计番茄数 = DB 已完成会话数（PomodoroDao 真值） */
  private async loadCumulative(): Promise<void> {
    try {
      const total: number = await PomodoroDao.countCompleted('1970-01-01', '9999-12-31');
      this.cumulativeTotal = total;
    } catch (_err) {
      // 读取失败保持旧值
    }
  }

  /**
   * fix: HUI-FRONTEND — F9：番茄完成回调——专注类（focus/custom）完成会话落库，
   * 重拉累计 + 发 SETTINGS_CHANGED 通知「我的」页资料卡番茄数刷新；休息类不计番茄。
   */
  private async onPomodoroComplete(): Promise<void> {
    if (this.activeType === 'focus' || this.activeType === 'custom') {
      try {
        const seconds: number = this.secondsFor(this.activeType);
        const session: PomodoroSession = new PomodoroSession(
          this.getTodayDate(), 'focus', Math.round(seconds / 60));
        session.actual_seconds = seconds;
        session.completed = 1;
        session.ended_at = Date.now();
        await PomodoroDao.insert(session);
      } catch (_err) {
        // 落库失败不阻断 UI
      }
      this.loadCumulative();
      const payload: Record<string, Object> = {};
      payload['source'] = 'pomodoro_complete';
      EventBus.emit(EventBus.EventNames.SETTINGS_CHANGED, payload);
    }
  }

  private getTodayDate(): string {
    const d: Date = new Date();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }

  /**
   * 根据预设类型返回倒计时总秒数。
   * 用 if 分支渲染不同 totalSeconds 的 PomodoroTimer 实例，
   * 切换预设时组件重建 → aboutToAppear 重新初始化 remainingSeconds。
   * HUI-001：custom 分支取持久化分钟数（无历史兜底 25）；
   * custom→custom 改分钟走 PomodoroTimer 内 @Watch(totalSeconds) 重置，行为同切预设。
   */
  private secondsFor(type: string): number {
    if (type === 'short_break') {
      return 5 * 60;
    }
    if (type === 'long_break') {
      return 15 * 60;
    }
    if (type === 'custom') {
      const minutes: number = this.customMinutes > 0 ? this.customMinutes : 25;
      return minutes * 60;
    }
    return 25 * 60;
  }

  /**
   * HUI-001：弹系统分钟选择器（1~120 分钟，滚轮默认定位上次值/25）。
   * 项目现有弹窗模式：同 SearchPage.openDatePicker 的 this.getUIContext().showXxxPickerDialog 通路。
   * API24 本地 .d.ts 已验：
   *   @ohos.arkui.UIContext.d.ts:4336 showTextPickerDialog(options: TextPickerDialogOptions)
   *   component/text_picker.d.ts:1380 onAccept?: (value: TextPickerResult) => void
   *   component/text_picker.d.ts:1103 TextPickerResult { value: string|string[], index: number|number[] }
   * 确定后仅设置倒计时（不自动开跑），与现有切预设语义一致；取消则维持当前预设不变。
   * HUI-042（T-D07）：主题化换肤——样式项经 PickerDialogTheme 读 theme_tokens（判空兜底 §9.4），
   * 保留系统滚轮交互；API24 已验 text_picker.d.ts:1193 TextPickerDialogOptions 各样式项。
   */
  private openCustomMinutePicker(): void {
    const range: string[] = [];
    for (let i = 1; i <= 120; i++) {
      range.push(i + ' 分钟');
    }
    const last: number = this.customMinutes > 0 ? this.customMinutes : 25;
    this.getUIContext().showTextPickerDialog({
      range: range,
      selected: last - 1,
      canLoop: false,
      backgroundColor: PickerDialogTheme.bg(this.tokens),
      backgroundBlurStyle: PickerDialogTheme.blur(),
      textStyle: PickerDialogTheme.textStyle(this.tokens),
      selectedTextStyle: PickerDialogTheme.selectedTextStyle(this.tokens),
      disappearTextStyle: PickerDialogTheme.disappearTextStyle(this.tokens),
      acceptButtonStyle: PickerDialogTheme.acceptButtonStyle(this.tokens),
      cancelButtonStyle: PickerDialogTheme.cancelButtonStyle(this.tokens),
      onAccept: (result: TextPickerResult) => {
        const idx: number = typeof result.index === 'number' ? result.index : result.index[0];
        const minutes: number = idx + 1;
        if (minutes >= 1 && minutes <= 120) {
          // @StorageLink → PersistentStorage 自动落盘，chip 文案同步刷成「自定义 Xmin」
          this.customMinutes = minutes;
          this.activeType = 'custom';
        }
      }
    });
  }

  build() {
    // HUI-001: 最小外包 Stack——原根 Column 原样保留，仅为叠加同树猫爪视觉层
    Stack({ alignContent: Alignment.TopStart }) {
    Column() {
      // ── 顶部：返回按钮 ──
      Row() {
        Button() {
          SymbolGlyph(IconMapper.ARROW_BACK)
            .fontSize(ICON.navBack)
            .fontWeight(FontWeight.Bold) // HUI-041：系统裸箭头加粗
            .fontColor([this.tokens ? this.tokens.textPrimary : '#1A1A1A'])
        }
        .width(48)
        .height(48)
        .borderRadius(24)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          router.back();
        })
        .accessibilityText('返回')
      }
      .width('100%')
      .height(48)
      .alignItems(VerticalAlign.Center)
      .margin({ bottom: 12 })

      // ── Eyebrow：FOCUS TIMER（大写英文 + 时钟图标 + 宽字距） ──
      Row() {
        SymbolGlyph(IconMapper.CLOCK)
          .fontSize(14)
          .fontColor([this.tokens ? this.tokens.primary : '#00C2B8'])
          .margin({ right: 6 })
        Text('FOCUS TIMER')
          .fontSize(TYPO.eyebrow.size)
          .fontWeight(TYPO.eyebrow.weight)
          .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
          .opacity(0.6)
          .letterSpacing(3)
          .attributeModifier(SKETCH_TITLE) // HUI-027：eyebrow 微标→猫啃什锦黑
      }

      // ── H1：专注时钟（TYPO.h1，primary 薄荷青） ──
      Text('专注时钟')
        .fontSize(TYPO.h1.size)
        .fontWeight(TYPO.h1.weight)
        .fontColor(this.tokens ? this.tokens.primary : '#00C2B8')
        .width('100%')
        .margin({ top: 4, bottom: SPACING.sectionGap })
        .attributeModifier(SKETCH_TITLE) // HUI-027：页面 H1 标题→猫啃什锦黑

      // ── 预设选择器（HUI-001：含第 4 个「自定义」chip，点击弹分钟选择器） ──
      PresetSelector({
        activeType: this.activeType,
        customMinutes: this.customMinutes,
        onSelect: (preset: PresetOption) => {
          this.activeType = preset.type;
        },
        onCustomSelect: () => {
          this.openCustomMinutePicker();
        }
      })
        .margin({ bottom: SPACING.sectionGap })

      // ── 倒计时环（按预设重建，保证切换即重置）──
      // fix: HUI-FRONTEND — F9：四分支统一接 onComplete（handler 内区分专注/休息，休息不计番茄）
      if (this.activeType === 'short_break') {
        PomodoroTimer({
          totalSeconds: this.secondsFor('short_break'),
          cumulativeCount: this.cumulativeTotal,
          onComplete: () => { this.onPomodoroComplete(); }
        })
      } else if (this.activeType === 'long_break') {
        PomodoroTimer({
          totalSeconds: this.secondsFor('long_break'),
          cumulativeCount: this.cumulativeTotal,
          onComplete: () => { this.onPomodoroComplete(); }
        })
      } else if (this.activeType === 'custom') {
        // HUI-001：自定义时长分支——走同一 totalSeconds 入参通路；
        // 同分支内改分钟由 PomodoroTimer @Watch(totalSeconds) 重置
        PomodoroTimer({
          totalSeconds: this.secondsFor('custom'),
          cumulativeCount: this.cumulativeTotal,
          onComplete: () => { this.onPomodoroComplete(); }
        })
      } else {
        PomodoroTimer({
          totalSeconds: this.secondsFor('focus'),
          cumulativeCount: this.cumulativeTotal,
          onComplete: () => { this.onPomodoroComplete(); }
        })
      }

      Blank()
    }
    .width('100%')
    .height('100%')
    .padding({
      left: SPACING.pageH,
      right: SPACING.pageH,
      top: SPACING.pageTop
    })
    .backgroundColor(this.tokens ? this.tokens.bg : '#FAF8F5')
    .accessibilityGroup(true)
    .accessibilityText('番茄钟页面')
    // HUI-001: 猫爪特效触摸捕获（页面树内监听 Down，不消费；视觉层在外包 Stack 顶层）
    .onTouch((event: TouchEvent) => reportPawTouch(event))

    // HUI-001: 猫爪视觉层（同树最上层子节点，整层 None 不参与命中，不挡交互）
    // PawOverlayLayer()
    }
    .width('100%')
    .height('100%')
  }
}
