// <!-- agentID: HUI-065 -->
// fix: HUI-FRONTEND
// agentID: HUI-041（T-D05：返回箭头统一 — 裸 arrow_left 加粗 ICON.navBack）
// @Entry 安全锁页（P2-11 薄荷青皮肤：eyebrow「PRIVACY LOCK」+ H1「安全验证」
//        + 青 lock_fill 圆徽标 + 4 位密码点 + 数字键盘 + 生物识别 + 错误抖动）
// 关联任务：UX-001 §6.7 安全锁 / PLN-003 P2-11
// 入口：features/settings SettingsPage 安全锁行 onClick → 本壳（entry）SettingsPage onNavigateSecurityLock → router.pushUrl('pages/SecurityLockPage')
//
// === 图标来源（本地库 resource/HarmonyOS_全量图标库.md 已 grep 验证，PROJECT_SPEC §10）===
//   · lock_fill（行1775，F04C1）圆徽标 —— IconMapper.LOCK 已在用 ✅
//   · touchid（行1803，F0507）生物识别 —— 本地库无 fingerprint（grep 0 命中），按 §10 用最贴切且已验证的 touchid 兜底
//   · delete_left（行1049，F00DD）键盘退格 ✅
//   · chevron_left（BACK✅）返回
//   · 密码点用 Circle 图形（非 symbol）；圆勾选亦为图形，无需额外图标
//
// === 令牌驱动（PLN-003 阅读须知1）===
//   · 圆角走 RADIUS；间距走 SPACING；字号/字重走 TYPO；键盘数字走 FONT.monoBold（mono 数字精致感）
//   · 颜色走 @StorageLink tokens（判空兜底）；触控热区 ≥48vp
//   · §1.4 三者一致：本壳位于 entry（HAP），仅依赖 @ohos/shared，无新增跨 feature 依赖
//
// === 崩溃防范（PROJECT_SPEC §9）===
//   · §9.1 无 getter-in-build：颜色/状态均经普通方法或 build 内三元
//   · §9.3 字段初值无 $r()（SymbolGlyph 的 $r() 仅出现在 build 中）
//   · §9.4 @StorageLink tokens 读取全判空
//   · §9 定时器清理：错误清空 PIN 的 setTimeout + 抖动序列 setTimeout 句柄在 aboutToDisappear 统一清理
//
// 开发范式：ArkTS 声明式开发范式（Stage 模型）

import type { ThemeColorTokens } from '@ohos/shared';
import { IconMapper, RADIUS, SPACING, TYPO, FONT, ICON, reportPawTouch, PawOverlayLayer } from '@ohos/shared';
import { SettingsViewModel } from 'features/settings';
import { router, promptAction } from '@kit.ArkUI';

// ── 尺寸常量（集中定义，避免散写魔数）──
const SZ_BADGE: number = 64;        // lock_fill 圆徽标尺寸
const SZ_BADGE_ICON: number = 30;   // 徽标内图标
const SZ_DOT: number = 16;          // 密码点直径
const SZ_KEY: number = 68;          // 数字键直径（≥48 触控热区）
const SZ_KEY_ICON: number = 24;     // 键内图标（退格/生物识别）
const SZ_BACK: number = 48;         // 返回按钮（≥48 触控热区）
const PIN_LENGTH: number = 4;       // PIN 位数
// 抖动位移序列（左右各 3 次后归位；animateTo 逐帧调度）
const SHAKE_SEQ: number[] = [-10, 10, -10, 10, -10, 10, 0];
const SHAKE_STEP_MS: number = 50;

@Entry
@Component
struct SecurityLockPage {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  // 已输入 PIN（字符串，初值为空 → 符合 §9.3 无 $r()）
  @State private pin: string = '';
  // 错误提示文案（空则不显示）
  @State private errorMsg: string = '';
  // 密码点容器横向抖动位移
  @State private shakeOffset: number = 0;

  // M15: Real PIN verification via SettingsViewModel (replaces hardcoded mock correctPin)
  private settingsVM: SettingsViewModel = new SettingsViewModel();
  @State private remainingAttempts: number = 5;
  @State private lockoutSeconds: number = 0;
  // F1: 入口模式（冷启动 PIN gate，EntryAbility 置 lockEntryMode=1）→ 隐藏返回、成功后 replaceUrl 进主页
  @State private isEntryMode: boolean = false;

  // 定时器句柄（§9 aboutToDisappear 清理）
  private clearPinTimerId: number = -1;
  private shakeTimerId: number = -1;

  // M15: Check lockout state on page entry
  async aboutToAppear(): Promise<void> {
    // F1: 同步读入口模式标志（EntryAbility 冷启动 PIN gate 置 1）
    this.isEntryMode = AppStorage.get<number>('lockEntryMode') === 1;
    const lockoutRemaining = await this.settingsVM.getLockoutRemaining();
    if (lockoutRemaining > 0) {
      this.lockoutSeconds = lockoutRemaining;
      this.errorMsg = `已锁定，请等待 ${Math.ceil(lockoutRemaining / 60)} 分钟`;
    }
    this.remainingAttempts = await this.settingsVM.getRemainingAttempts();
  }

  aboutToDisappear(): void {
    this.clearTimers();
  }

  private clearTimers(): void {
    if (this.clearPinTimerId !== -1) {
      clearTimeout(this.clearPinTimerId);
      this.clearPinTimerId = -1;
    }
    if (this.shakeTimerId !== -1) {
      clearTimeout(this.shakeTimerId);
      this.shakeTimerId = -1;
    }
  }

  // ==== 颜色兜底（普通方法，非 getter；§9.1 / §9.4）====
  private getBg(): string {
    return this.tokens ? this.tokens.bg : '#FAF8F5';
  }

  private getPrimary(): string {
    return this.tokens ? this.tokens.primary : '#00C2B8';
  }

  private getAccent(): string {
    return this.tokens ? this.tokens.accent : '#E6F9F8';
  }

  private getSurface(): string {
    return this.tokens ? this.tokens.surface : '#F2F4F3';
  }

  private getTextPrimary(): string {
    return this.tokens ? this.tokens.textPrimary : '#1A1A1A';
  }

  private getTextSecondary(): string {
    return this.tokens ? this.tokens.textSecondary : '#5A5A5A';
  }

  private getBorder(): string {
    return this.tokens ? this.tokens.border : '#EAEAE6';
  }

  private getDanger(): string {
    return this.tokens ? this.tokens.danger : '#78909C';
  }

  /** 半透明版本：ArkUI hex-alpha 为 #AARRGGBB，需前置 alpha */
  private withAlpha(hex: string, alphaHex: string): string {
    return '#' + alphaHex + hex.replace('#', '');
  }

  // ==== PIN 输入逻辑 ====
  private onDigit(d: string): void {
    if (this.pin.length >= PIN_LENGTH) {
      return;
    }
    this.errorMsg = '';
    this.pin = this.pin + d;
    if (this.pin.length === PIN_LENGTH) {
      this.verify();
    }
  }

  private onDelete(): void {
    if (this.pin.length === 0) {
      return;
    }
    this.errorMsg = '';
    this.pin = this.pin.substring(0, this.pin.length - 1);
  }

  private async verify(): Promise<void> {
    // M15: Check lockout state first
    const lockoutRemaining = await this.settingsVM.getLockoutRemaining();
    if (lockoutRemaining > 0) {
      this.lockoutSeconds = lockoutRemaining;
      this.errorMsg = `已锁定，请等待 ${Math.ceil(lockoutRemaining / 60)} 分钟`;
      this.triggerShake();
      return;
    }

    // M15: Real PIN verification via SettingsViewModel (replaces hardcoded mock)
    try {
      const isValid = await this.settingsVM.verifyPin(this.pin);
      if (isValid) {
        promptAction.showToast({ message: '验证通过', duration: 1200 });
        // F1: 入口模式（冷启动解锁）无上一页可退，replaceUrl 进主页并清标志；设置内验证维持 back
        if (AppStorage.get<number>('lockEntryMode') === 1) {
          AppStorage.setOrCreate('lockEntryMode', 2);
          router.replaceUrl({ url: 'pages/MainPage' });
        } else {
          router.back();
        }
        return;
      }
    } catch (_err) {
      // Fall through to error handling
    }

    // Update remaining attempts (M15: error count from SettingsViewModel)
    const remaining = await this.settingsVM.getRemainingAttempts();
    this.remainingAttempts = remaining;

    if (remaining <= 0) {
      const lockout = await this.settingsVM.getLockoutRemaining();
      this.lockoutSeconds = lockout;
      this.errorMsg = `已锁定，请等待 ${Math.ceil(lockout / 60)} 分钟`;
    } else {
      this.errorMsg = `PIN 码错误，还剩 ${remaining} 次机会`;
    }

    // 错误：抖动 + 清空 + 提示
    this.triggerShake();
    if (this.clearPinTimerId !== -1) {
      clearTimeout(this.clearPinTimerId);
    }
    this.clearPinTimerId = setTimeout(() => {
      this.clearPinTimerId = -1;
      this.pin = '';
    }, SHAKE_SEQ.length * SHAKE_STEP_MS);
  }

  /** 生物识别（待真机 userIAM 接入；当前禁用避免绕过 PIN） */
  private onBiometric(): void {
    promptAction.showToast({ message: '生物识别暂不可用，请使用 PIN 解锁', duration: 1500 });
    // router.back(); // Disabled: real userIAM required before enabling biometric bypass
  }

  /** 错误抖动：逐帧 animateTo 左右位移 3 次后归位（§9 定时器清理） */
  private triggerShake(): void {
    let i: number = 0;
    if (this.shakeTimerId !== -1) {
      clearTimeout(this.shakeTimerId);
      this.shakeTimerId = -1;
    }
    const step = (): void => {
      if (i >= SHAKE_SEQ.length) {
        this.shakeTimerId = -1;
        return;
      }
      const target: number = SHAKE_SEQ[i];
      animateTo({ duration: SHAKE_STEP_MS, curve: Curve.Sharp }, () => {
        this.shakeOffset = target;
      });
      i = i + 1;
      this.shakeTimerId = setTimeout(step, SHAKE_STEP_MS);
    };
    step();
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
            .fontColor([this.getTextPrimary()])
        }
        .width(SZ_BACK)
        .height(SZ_BACK)
        .borderRadius(SZ_BACK / 2)
        .backgroundColor(Color.Transparent)
        // F1: 入口模式下隐藏并禁用返回按钮（无上一页可退，防绕过锁屏）
        .visibility(this.isEntryMode ? Visibility.Hidden : Visibility.Visible)
        .enabled(!this.isEntryMode)
        .onClick(() => {
          router.back();
        })
        .accessibilityText('返回')

        Blank()
      }
      .width('100%')
      .height(SZ_BACK)
      .alignItems(VerticalAlign.Center)

      // ── 中部：徽标 + 标题 + 密码点（居中） ──
      Column() {
        // 青 lock_fill 圆徽标（青浅底 accent + RADIUS.cardLg）
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph(IconMapper.LOCK)
            .fontSize(SZ_BADGE_ICON)
            .fontColor([this.getPrimary()])
        }
        .width(SZ_BADGE)
        .height(SZ_BADGE)
        .backgroundColor(this.getAccent())
        .borderRadius(RADIUS.cardLg)
        .shadow({ radius: 18, color: this.withAlpha(this.getPrimary(), '26'), offsetX: 0, offsetY: 6 })

        // eyebrow「PRIVACY LOCK」
        Text('PRIVACY LOCK')
          .fontSize(TYPO.eyebrow.size)
          .fontWeight(TYPO.eyebrow.weight)
          .fontColor(this.getTextSecondary())
          .letterSpacing(2)
          .opacity(0.6)
          .margin({ top: SPACING.sectionGap })

        // H1「安全验证」
        Text('安全验证')
          .fontSize(TYPO.h1.size)
          .fontWeight(TYPO.h1.weight)
          .fontColor(this.getTextPrimary())
          .margin({ top: 4 })

        Text('输入 4 位 PIN 码解锁日记')
          .fontSize(TYPO.body.size)
          .fontWeight(TYPO.body.weight)
          .fontColor(this.getTextSecondary())
          .margin({ top: 8 })

        // 密码点（4 位；输入变实心）—— 抖动容器
        Row() {
          ForEach([0, 1, 2, 3], (i: number) => {
            Circle({ width: SZ_DOT, height: SZ_DOT })
              .fill(i < this.pin.length ? this.getPrimary() : Color.Transparent)
              .stroke(i < this.pin.length ? this.getPrimary() : this.getBorder())
              .strokeWidth(2)
              .margin({ left: 12, right: 12 })
          }, (i: number) => i.toString())
        }
        .translate({ x: this.shakeOffset })
        .margin({ top: SPACING.sectionGap })
        .accessibilityText('已输入 ' + this.pin.length + ' 位，共 4 位')

        // 错误提示（占位固定高度，避免布局跳动）
        Text(this.errorMsg)
          .fontSize(TYPO.eyebrow.size)
          .fontColor(this.getDanger())
          .height(20)
          .margin({ top: 10 })
          .opacity(this.errorMsg.length > 0 ? 1 : 0)
      }
      .width('100%')
      .layoutWeight(1)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)

      // ── 底部：数字键盘 ──
      this.Keypad()
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.getBg())
    .padding({
      left: SPACING.pageH,
      right: SPACING.pageH,
      top: SPACING.pageTop,
      bottom: SPACING.sectionGap
    })
    // HUI-001: 猫爪特效触摸捕获（页面树内监听 Down，不消费；视觉层在外包 Stack 顶层）
    .onTouch((event: TouchEvent) => reportPawTouch(event))

    // HUI-001: 猫爪视觉层（同树最上层子节点，整层 None 不参与命中，不挡交互）
    PawOverlayLayer()
    }
    .width('100%')
    .height('100%')
  }

  // ==== 数字键盘（3×4：1-9 / 生物识别·0·退格）====
  @Builder
  Keypad() {
    Column() {
      Row() {
        this.DigitKey('1')
        this.DigitKey('2')
        this.DigitKey('3')
      }
      .justifyContent(FlexAlign.SpaceEvenly)
      .width('100%')

      Row() {
        this.DigitKey('4')
        this.DigitKey('5')
        this.DigitKey('6')
      }
      .justifyContent(FlexAlign.SpaceEvenly)
      .width('100%')
      .margin({ top: SPACING.cardGap })

      Row() {
        this.DigitKey('7')
        this.DigitKey('8')
        this.DigitKey('9')
      }
      .justifyContent(FlexAlign.SpaceEvenly)
      .width('100%')
      .margin({ top: SPACING.cardGap })

      Row() {
        this.BiometricKey()
        this.DigitKey('0')
        this.DeleteKey()
      }
      .justifyContent(FlexAlign.SpaceEvenly)
      .width('100%')
      .margin({ top: SPACING.cardGap })
    }
    .width('100%')
  }

  @Builder
  DigitKey(d: string) {
    Button(d)
      .type(ButtonType.Circle)
      .fontSize(TYPO.numCard.size)
      .fontFamily(FONT.monoBold)
      .fontColor(this.getTextPrimary())
      .backgroundColor(this.getSurface())
      .width(SZ_KEY)
      .height(SZ_KEY)
      .onClick(() => {
        this.onDigit(d);
      })
      .accessibilityText('数字 ' + d)
  }

  @Builder
  BiometricKey() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.touchid'))
        .fontSize(SZ_KEY_ICON)
        .fontColor([this.getPrimary()])
    }
    .width(SZ_KEY)
    .height(SZ_KEY)
    .backgroundColor(this.withAlpha(this.getPrimary(), '14'))
    .onClick(() => {
      this.onBiometric();
    })
    .accessibilityText('生物识别解锁')
  }

  @Builder
  DeleteKey() {
    Button({ type: ButtonType.Circle }) {
      SymbolGlyph($r('sys.symbol.delete_left'))
        .fontSize(SZ_KEY_ICON)
        .fontColor([this.getTextSecondary()])
    }
    .width(SZ_KEY)
    .height(SZ_KEY)
    .backgroundColor(Color.Transparent)
    .onClick(() => {
      this.onDelete();
    })
    .accessibilityText('删除一位')
  }
}
