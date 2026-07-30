// <!-- agentID: HUI-LOGIN -->
// @Entry 手机号密码登录/注册页（黑白主题：eyebrow「ACCOUNT LOGIN/REGISTER」+ H1「密码登录/注册账号」
//        + 表单卡［+86 手机号 / 6-20 位密码］+ 黑底白字主按钮 + 注册/登录切换文字按钮）
// 入口：features/settings SettingsPage 账号行 → entry SettingsPage onNavigateLogin → router.pushUrl('pages/LoginPage')
// 业务：AccountManager（@ohos/shared，四期密码方案——注册登录走 Cloud DB Account 表）
//   · register(phone, pwd) → 云表查重 + AES 加密落云表 + 本地缓存登录态 → 成功 router.back()
//   · login(phone, pwd) → 云表查询验密 + 本地缓存登录态 → 成功 router.back()
//   （验证码链路已删：无发码按钮/无 60s 倒计时/无 setInterval 句柄）
//
// === 图标来源（resource/HarmonyOS_全量图标库.md，均为 IconMapper 已验证图标）===
//   · arrow_left（ARROW_BACK ✅）返回
//   · person（NAV_PROFILE ✅）eyebrow 徽标
//
// === 令牌驱动（PLN-003 阅读须知1）===
//   · 圆角走 RADIUS；间距走 SPACING；字号/字重走 TYPO；返回箭头走 ICON；数字走 FONT.mono
//   · 尺寸常量集中文件头，禁散写魔数；触控热区 ≥48vp
//
// === 崩溃防范（PROJECT_SPEC §9）===
//   · §9.1 无 getter-in-build：所有颜色/状态均为 build 内显式三元表达式
//   · §9.3 struct 字段初值无 $r()（SymbolGlyph 的 $r() 仅经 IconMapper 静态量出现在 build 中）
//   · §9.4 🔴 @StorageLink tokens 读取全部逐处判空：this.tokens ? this.tokens.xxx : '#fallback'
//     （每条单独判空，无 getter / ?? / 方法中间层；兜底为黑白中性色）
//
// 开发范式：ArkTS 声明式开发范式（Stage 模型）

import type { ThemeColorTokens, Result } from '@ohos/shared';
import { AccountManager, IconMapper, RADIUS, SPACING, TYPO, ICON, FONT, SKETCH_TITLE, reportPawTouch, PawOverlayLayer } from '@ohos/shared';
import { router, promptAction } from '@kit.ArkUI';

// ── 尺寸常量（集中定义，避免散写魔数）──
const SZ_BACK: number = 48;          // 返回按钮触控热区（≥48vp）
const SZ_INPUT: number = 48;         // 输入行高度
const SZ_BTN: number = 52;           // 主按钮（登录/注册）高度
const SZ_TOGGLE_H: number = 48;      // 注册/登录切换按钮触控热区（≥48vp）
const SZ_ERR_H: number = 18;         // 错误提示占位高度（固定高避免布局跳动）
const PHONE_LEN: number = 11;        // 手机号位数
const PWD_MIN_LEN: number = 6;       // 密码最短位数（与 AccountManager 校验口径一致）
const PWD_MAX_LEN: number = 20;      // 密码最长位数
const PHONE_PATTERN: RegExp = /^1\d{10}$/;   // 大陆手机号：1 开头 11 位
// T701+T702+T703 注册增强
const NICKNAME_MAX_LEN: number = 12;        // 用户名最大字符数
const VERIFY_CODE_LEN: number = 6;          // 验证码位数
const MOCK_CODE: string = '622893';         // 预设验证码
const COUNTDOWN_SECONDS: number = 60;       // 倒计时秒数

@Entry
@Component
struct LoginPage {
  // §9.4：@StorageLink 空值防御——声明为 nullable，读取逐处三元判空
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  // 表单状态（初值全为空/零，符合 §9.3 无 $r()）
  @State private phone: string = '';
  @State private password: string = '';
  @State private errorMsg: string = '';
  @State private isRegisterMode: boolean = false;
  @State private isSubmitting: boolean = false;
  // T701：注册用户名（1-12 字符，仅注册模式）
  @State private nickname: string = '';
  // T702：Mock 验证码（注册/登录均需）
  @State private verifyCode: string = '';
  @State private countdown: number = 0;
  // T703：确认密码（仅注册模式）
  @State private confirmPassword: string = '';
  // T702：倒计时 setInterval 句柄（aboutToDisappear 清除）
  private countdownTimer: number = -1;

  /** T702：启动验证码倒计时（setInterval 60s → 0 自动停止） */
  private startCountdown(): void {
    if (this.countdownTimer !== -1) {
      clearInterval(this.countdownTimer);
    }
    this.countdown = COUNTDOWN_SECONDS;
    this.countdownTimer = setInterval(() => {
      this.countdown--;
      if (this.countdown <= 0) {
        clearInterval(this.countdownTimer);
        this.countdownTimer = -1;
      }
    }, 1000);
  }

  /** 组件销毁时清除倒计时定时器 */
  aboutToDisappear(): void {
    if (this.countdownTimer !== -1) {
      clearInterval(this.countdownTimer);
      this.countdownTimer = -1;
    }
  }

  /** 注册 ⇆ 登录模式切换（清错误提示、密码、验证码、用户名、确认密码，避免跨模式误提交） */
  private toggleMode(): void {
    if (this.isSubmitting) {
      return;
    }
    this.isRegisterMode = !this.isRegisterMode;
    this.errorMsg = '';
    this.password = '';
    this.confirmPassword = '';
    this.nickname = '';
    this.verifyCode = '';
    if (this.countdownTimer !== -1) {
      clearInterval(this.countdownTimer);
      this.countdownTimer = -1;
    }
    this.countdown = 0;
  }

  /** 主按钮启用条件（T701+T702+T703）：
   *   登录模式：phone(11位) + verifyCode(6位) + password(≥6位)
   *   注册模式：phone(11位) + nickname(trim后1-12字符) + verifyCode(6位) + password(≥6位) + confirmPassword(一致) */
  private isFormValid(): boolean {
    if (this.isSubmitting) {
      return false;
    }
    if (this.phone.length !== PHONE_LEN) {
      return false;
    }
    if (this.verifyCode.length !== VERIFY_CODE_LEN) {
      return false;
    }
    if (this.password.length < PWD_MIN_LEN) {
      return false;
    }
    if (this.isRegisterMode) {
      const n: string = this.nickname.trim();
      if (n.length === 0 || n.length > NICKNAME_MAX_LEN) {
        return false;
      }
      if (this.password !== this.confirmPassword) {
        return false;
      }
    }
    return true;
  }

  /** 提交：注册模式走 register，登录模式走 login；成功返回上一页 */
  private async doSubmit(): Promise<void> {
    if (this.isSubmitting) {
      return;
    }
    if (!PHONE_PATTERN.test(this.phone)) {
      this.errorMsg = '请输入 11 位有效手机号';
      return;
    }
    if (this.isRegisterMode) {
      const n: string = this.nickname.trim();
      if (n.length === 0 || n.length > NICKNAME_MAX_LEN) {
        this.errorMsg = '请输入 1-12 字符用户名';
        return;
      }
    }
    // T702：验证码校验（注册/登录均需）
    if (this.verifyCode !== MOCK_CODE) {
      promptAction.showToast({ message: '验证码错误', duration: 1500 });
      return;
    }
    if (this.password.length < PWD_MIN_LEN || this.password.length > PWD_MAX_LEN) {
      this.errorMsg = `请输入 ${PWD_MIN_LEN}-${PWD_MAX_LEN} 位密码`;
      return;
    }
    // T703：注册模式确认密码一致
    if (this.isRegisterMode && this.password !== this.confirmPassword) {
      promptAction.showToast({ message: '两次密码不一致', duration: 1500 });
      return;
    }
    this.errorMsg = '';
    this.isSubmitting = true;
    const mgr: AccountManager = AccountManager.getInstance();
    const result: Result<string> = this.isRegisterMode
      ? await mgr.register(this.phone, this.password, this.nickname.trim())
      : await mgr.login(this.phone, this.password);
    this.isSubmitting = false;
    if (result.success) {
      promptAction.showToast({
        message: this.isRegisterMode ? '注册成功，已自动登录' : '登录成功',
        duration: 1500
      });
      router.back();
    } else {
      this.errorMsg = result.message.length > 0 ? result.message
        : (this.isRegisterMode ? '注册失败，请稍后重试' : '登录失败，请稍后重试');
    }
  }

  build() {
    // 最小外包 Stack——同树叠加猫爪视觉层（壳页先例：FamilyPage / SecurityLockPage）
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
          .width(SZ_BACK)
          .height(SZ_BACK)
          .borderRadius(SZ_BACK / 2)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            router.back();
          })
          .accessibilityText('返回')

          Blank()
        }
        .width('100%')
        .height(SZ_BACK)
        .alignItems(VerticalAlign.Center)
        .margin({ bottom: 12 })

        // ── Eyebrow：ACCOUNT LOGIN / REGISTER（大写英文 + 成员图标 + 宽字距）──
        Row() {
          SymbolGlyph(IconMapper.NAV_PROFILE)
            .fontSize(14)
            .fontColor([this.tokens ? this.tokens.primary : '#000000'])
            .margin({ right: 6 })
          Text(this.isRegisterMode ? 'ACCOUNT REGISTER' : 'ACCOUNT LOGIN')
            .fontSize(TYPO.eyebrow.size)
            .fontWeight(TYPO.eyebrow.weight)
            .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
            .opacity(0.6)
            .letterSpacing(3)
            .attributeModifier(SKETCH_TITLE)
        }
        .width('100%')

        // ── H1：密码登录 / 注册账号 ──
        Text(this.isRegisterMode ? '注册账号' : '密码登录')
          .fontSize(TYPO.h1.size)
          .fontWeight(TYPO.h1.weight)
          .fontColor(this.tokens ? this.tokens.primary : '#000000')
          .width('100%')
          .margin({ top: 4 })
          .attributeModifier(SKETCH_TITLE)

        // 副文案
        Text(this.isRegisterMode
          ? `设置 ${PWD_MIN_LEN}-${PWD_MAX_LEN} 位密码，注册成功自动登录`
          : '手机号 + 密码登录，新用户请先注册')
          .fontSize(TYPO.body.size)
          .fontWeight(TYPO.body.weight)
          .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
          .width('100%')
          .margin({ top: 8, bottom: SPACING.sectionGap })

        // ── 表单卡（白底 + 细描边 + 大圆角 bento 卡）──
        Column() {
          // 手机号行：+86 前缀 + 分隔线 + 输入
          Row() {
            Text('+86')
              .fontSize(TYPO.body.size)
              .fontWeight(600)
              .fontFamily(FONT.mono)
              .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
              .margin({ left: SPACING.cardPadSm })
            Divider()
              .vertical(true)
              .height(18)
              .color(this.tokens ? this.tokens.border : '#EAEAE6')
              .margin({ left: 10, right: 4 })
            TextInput({ placeholder: '请输入手机号', text: $$this.phone })
              .type(InputType.PhoneNumber)
              .maxLength(PHONE_LEN)
              .fontSize(TYPO.body.size)
              .fontFamily(FONT.mono)
              .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
              .placeholderColor(this.tokens ? this.tokens.textTertiary : '#BDBDBD')
              .placeholderFont({ size: TYPO.body.size, weight: TYPO.body.weight })
              .caretColor(this.tokens ? this.tokens.primary : '#000000')
              .backgroundColor(Color.Transparent)
              .layoutWeight(1)
              .height(SZ_INPUT)
              .onChange(() => {
                this.errorMsg = '';
              })
          }
          .width('100%')
          .height(SZ_INPUT)
          .backgroundColor(this.tokens ? this.tokens.surface : '#F2F4F3')
          .borderRadius(RADIUS.input)
          .border({ width: 1, color: this.tokens ? this.tokens.border : '#EAEAE6' })
          .alignItems(VerticalAlign.Center)

          // T701：用户名行（仅注册模式）—— trim 后 1-12 字符
          if (this.isRegisterMode) {
            TextInput({ placeholder: '请输入用户名', text: $$this.nickname })
              .type(InputType.Normal)
              .maxLength(NICKNAME_MAX_LEN)
              .fontSize(TYPO.body.size)
              .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
              .placeholderColor(this.tokens ? this.tokens.textTertiary : '#BDBDBD')
              .placeholderFont({ size: TYPO.body.size, weight: TYPO.body.weight })
              .caretColor(this.tokens ? this.tokens.primary : '#000000')
              .backgroundColor(Color.Transparent)
              .width('100%')
              .height(SZ_INPUT)
              .padding({ left: SPACING.cardPadSm, right: SPACING.cardPadSm })
              .onChange(() => {
                this.errorMsg = '';
              })
              .margin({ top: SPACING.cardGap })
          }

          // T702：Mock 验证码行（注册/登录均显示）—— 6 位 + 获取/重新发送按钮
          Row() {
            TextInput({ placeholder: '6 位验证码', text: $$this.verifyCode })
              .type(InputType.Number)
              .maxLength(VERIFY_CODE_LEN)
              .fontSize(TYPO.body.size)
              .fontFamily(FONT.mono)
              .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
              .placeholderColor(this.tokens ? this.tokens.textTertiary : '#BDBDBD')
              .placeholderFont({ size: TYPO.body.size, weight: TYPO.body.weight })
              .caretColor(this.tokens ? this.tokens.primary : '#000000')
              .backgroundColor(Color.Transparent)
              .layoutWeight(1)
              .height(SZ_INPUT)
              .margin({ left: SPACING.cardPadSm })
              .onChange(() => {
                this.errorMsg = '';
              })
            Button(this.countdown > 0
              ? `重新发送(${this.countdown}s)`
              : '获取验证码')
              .type(ButtonType.Normal)
              .fontSize(TYPO.eyebrow.size)
              .fontWeight(TYPO.eyebrow.weight)
              .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
              .backgroundColor(Color.Transparent)
              .border({ width: 1, color: this.tokens ? this.tokens.border : '#EAEAE6' })
              .borderRadius(RADIUS.input)
              .height(32)
              .padding({ left: 12, right: 12 })
              .margin({ right: 4 })
              .enabled(this.countdown === 0)
              .opacity(this.countdown === 0 ? 1 : 0.5)
              .onClick(() => {
                promptAction.showToast({ message: '验证码已发送', duration: 1500 });
                this.startCountdown();
              })
          }
          .width('100%')
          .height(SZ_INPUT)
          .backgroundColor(this.tokens ? this.tokens.surface : '#F2F4F3')
          .borderRadius(RADIUS.input)
          .border({ width: 1, color: this.tokens ? this.tokens.border : '#EAEAE6' })
          .alignItems(VerticalAlign.Center)
          .margin({ top: SPACING.cardGap })

          // 密码行：掩码输入（系统自带明/密切换小眼睛）
          Row() {
            TextInput({ placeholder: `请输入密码（${PWD_MIN_LEN}-${PWD_MAX_LEN} 位）`, text: $$this.password })
              .type(InputType.Password)
              .maxLength(PWD_MAX_LEN)
              .fontSize(TYPO.body.size)
              .fontFamily(FONT.mono)
              .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
              .placeholderColor(this.tokens ? this.tokens.textTertiary : '#BDBDBD')
              .placeholderFont({ size: TYPO.body.size, weight: TYPO.body.weight })
              .caretColor(this.tokens ? this.tokens.primary : '#000000')
              .backgroundColor(Color.Transparent)
              .layoutWeight(1)
              .height(SZ_INPUT)
              .margin({ left: 4 })
              .onChange(() => {
                this.errorMsg = '';
              })
          }
          .width('100%')
          .height(SZ_INPUT)
          .backgroundColor(this.tokens ? this.tokens.surface : '#F2F4F3')
          .borderRadius(RADIUS.input)
          .border({ width: 1, color: this.tokens ? this.tokens.border : '#EAEAE6' })
          .alignItems(VerticalAlign.Center)
          .margin({ top: SPACING.cardGap })

          // T703：确认密码行（仅注册模式）—— 掩码输入，提交时校验与密码一致
          if (this.isRegisterMode) {
            TextInput({ placeholder: '请再次输入密码', text: $$this.confirmPassword })
              .type(InputType.Password)
              .maxLength(PWD_MAX_LEN)
              .fontSize(TYPO.body.size)
              .fontFamily(FONT.mono)
              .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
              .placeholderColor(this.tokens ? this.tokens.textTertiary : '#BDBDBD')
              .placeholderFont({ size: TYPO.body.size, weight: TYPO.body.weight })
              .caretColor(this.tokens ? this.tokens.primary : '#000000')
              .backgroundColor(Color.Transparent)
              .width('100%')
              .height(SZ_INPUT)
              .padding({ left: SPACING.cardPadSm, right: SPACING.cardPadSm })
              .onChange(() => {
                this.errorMsg = '';
              })
              .margin({ top: SPACING.cardGap })
          }

          // 错误提示（固定占位高度，避免布局跳动）
          Text(this.errorMsg)
            .fontSize(TYPO.eyebrow.size)
            .fontColor(this.tokens ? this.tokens.danger : '#5A5A5A')
            .width('100%')
            .height(SZ_ERR_H)
            .margin({ top: 10 })
            .opacity(this.errorMsg.length > 0 ? 1 : 0)

          // 主按钮：登录/注册（黑白主题：primary 黑底 + bg 白字；深色模式随 tokens 反转）
          Button(this.isSubmitting
            ? (this.isRegisterMode ? '注册中…' : '登录中…')
            : (this.isRegisterMode ? '注册' : '登录'))
            .type(ButtonType.Normal)
            .fontSize(TYPO.cardTitle.size)
            .fontWeight(TYPO.cardTitle.weight)
            .fontFamily(FONT.sketchBody)
            .fontColor(this.tokens ? this.tokens.bg : '#FFFFFF')
            .backgroundColor(this.tokens ? this.tokens.primary : '#000000')
            .borderRadius(SZ_BTN / 2)
            .width('100%')
            .height(SZ_BTN)
            .margin({ top: SPACING.cardGap })
            .enabled(this.isFormValid())
            .opacity(this.isFormValid() ? 1 : 0.35)
            .onClick(() => {
              this.doSubmit();
            })
            .accessibilityText(this.isSubmitting
              ? (this.isRegisterMode ? '注册中' : '登录中')
              : (this.isRegisterMode ? '注册' : '登录'))

          // 注册 ⇆ 登录切换（纯文字按钮，黑白弱化为二级文字色，触控热区 ≥48vp）
          Button(this.isRegisterMode ? '已有账号？去登录' : '没有账号？去注册')
            .type(ButtonType.Normal)
            .fontSize(TYPO.body.size)
            .fontWeight(TYPO.body.weight)
            .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
            .backgroundColor(Color.Transparent)
            .borderRadius(SZ_TOGGLE_H / 2)
            .width('100%')
            .height(SZ_TOGGLE_H)
            .margin({ top: 4 })
            .enabled(!this.isSubmitting)
            .onClick(() => {
              this.toggleMode();
            })
            .accessibilityText(this.isRegisterMode ? '切换到登录' : '切换到注册')
        }
        .width('100%')
        .padding(SPACING.cardPadLg)
        .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
        .borderRadius(RADIUS.card)
        .border({ width: 1, color: this.tokens ? this.tokens.border : '#EAEAE6' })
        .alignItems(HorizontalAlign.Start)

        // 协议小字（登录/注册即视为同意；黑白弱化为三级文字色）
        Text(this.isRegisterMode
          ? '注册即代表同意《用户协议》与《隐私政策》'
          : '登录即代表同意《用户协议》与《隐私政策》')
          .fontSize(TYPO.eyebrow.size)
          .fontWeight(TYPO.eyebrow.weight)
          .fontColor(this.tokens ? this.tokens.textTertiary : '#BDBDBD')
          .width('100%')
          .textAlign(TextAlign.Center)
          .margin({ top: SPACING.sectionGap })

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
      .accessibilityText(this.isRegisterMode ? '手机号密码注册页面' : '手机号密码登录页面')
      // 猫爪特效触摸捕获（页面树内监听 Down，不消费；视觉层在外包 Stack 顶层）
      .onTouch((event: TouchEvent) => reportPawTouch(event))

      // 猫爪视觉层（同树最上层子节点，不参与命中，不挡交互）
      // PawOverlayLayer()
    }
    .width('100%')
    .height('100%')
  }
}
