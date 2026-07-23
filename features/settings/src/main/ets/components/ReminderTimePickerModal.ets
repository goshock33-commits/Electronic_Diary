// <!-- agentID: HUI-001 -->
// 组件：每日提醒-时间选择模态框（居中毛玻璃 · 时/分双框 + 可转动阻尼圆盘）—— T-FEAT-002
// 关联需求：HARMONYOS_REQUIREMENTS §11 弹窗毛玻璃 / §10.6 每日提醒；用户已确认交互规格
// 关联规范：PROJECT_SPEC §8 ArkTS 严格模式 / §9 崩溃防范
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 系统组件：Stack / Column / Row / Circle / Text / Button；手势：PanGesture；动效：animateTo + curves.springMotion
// 交互（用户确认）：
//   · 上方两个圆角方框（左=时/右=分），点击切换「当前调节对象」并高亮；
//   · 下方圆盘 PanGesture 跟手旋转，实时增减当前对象数值（时 0–23 循环 / 分 0–59 循环）；
//   · 转动自然柔和：拖拽跟手（直接更新角度），松手 springMotion 阻尼吸附到最近刻度（不生硬、有缓冲）。
// 崩溃防范：@StorageLink tokens 判空回退；无 getter-in-build（角度/数值经普通方法）；
//   @Prop 默认值为 number，不含 $r()；fingerList 判空兜底。
// 无障碍：时/分框、圆盘、取消/确定均含 accessibilityText；框热区 96x84vp。

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-029：追加 SKETCH_TITLE=猫啃什锦黑（弹窗标题）、SKETCH_BODY=清松手写体2（提示 + 时/分单位与小时/分钟标签）；时/分数字与冒号保留不动，Button('取消'/'确定') 不动。
import { RADIUS, SPACING, TYPO, SKETCH_TITLE, SKETCH_BODY } from '@ohos/shared';
import { curves } from '@kit.ArkUI';

/** 圆盘直径(vp) */
const DIAL_SIZE: number = 236;
/** 旋钮直径(vp) */
const KNOB_SIZE: number = 26;
/** 圆盘吸附/回弹曲线：springMotion(response=0.5, dampingFraction=0.72) —— 自然阻尼、松手有缓冲不生硬 */
const DIAL_SPRING: ICurve = curves.springMotion(0.5, 0.72);

@Component
export struct ReminderTimePickerModal {
  /** 初始小时（0–23） */
  @Prop initialHour: number = 20;
  /** 初始分钟（0–59） */
  @Prop initialMinute: number = 0;
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  /** 确定回调（回传选定的时、分） */
  onConfirm?: (hour: number, minute: number) => void;
  /** 取消回调 */
  onCancel?: () => void;

  @State private hour: number = 20;
  @State private minute: number = 0;
  /** 当前调节对象：'hour' | 'minute' */
  @State private activeField: string = 'hour';
  /** 圆盘视觉旋转角(度)，与当前对象数值绑定 */
  @State private dialAngle: number = 0;
  @State private cardScale: number = 0.92;

  /** 上一帧指针角(度)，用于计算旋转增量 */
  private lastPointerAngle: number = 0;

  aboutToAppear(): void {
    this.hour = this.clamp(this.initialHour, 24);
    this.minute = this.clamp(this.initialMinute, 60);
    this.dialAngle = this.hour * this.stepAngle();
    animateTo({ duration: 240, curve: Curve.EaseOut }, () => {
      this.cardScale = 1;
    });
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      // 遮罩：半透明黑 + 毛玻璃（点击取消）
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.45)')
        .backdropBlur(10)
        .onClick(() => {
          this.cancel();
        })
        .transition(TransitionEffect.OPACITY.animation({ duration: 200, curve: Curve.EaseInOut }))
        .accessibilityText('弹窗遮罩，点击取消')

      // 弹窗卡片
      Column() {
        Text('设置提醒时间')
          .fontSize(TYPO.cardTitle.size)
          .fontWeight(TYPO.cardTitle.weight)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .margin({ bottom: 18 })
          .attributeModifier(SKETCH_TITLE) // HUI-029：弹窗标题→猫啃什锦黑

        // ── 上方：时 / 分 双框 ──
        Row() {
          this.buildValueBox('hour', this.pad2(this.hour), '时')
          Text(':')
            .fontSize(TYPO.numCard.size)
            .fontWeight(900)
            .fontColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
            .margin({ left: 12, right: 12 })
          this.buildValueBox('minute', this.pad2(this.minute), '分')
        }
        .justifyContent(FlexAlign.Center)
        .margin({ bottom: 22 })

        // ── 下方：可转动阻尼圆盘 ──
        this.buildDial()

        Text('转动圆盘调整' + (this.activeField === 'hour' ? '小时' : '分钟'))
          .fontSize(TYPO.eyebrow.size)
          .fontColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
          .margin({ top: 14 })
          .attributeModifier(SKETCH_BODY) // HUI-029：操作提示→清松手写体2

        // ── 取消 / 确定 ──
        Row() {
          Button('取消')
            .fontSize(TYPO.body.size)
            .fontWeight(500)
            .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
            .backgroundColor(this.tokens ? this.tokens.btnAux : '#C6BBAE')
            .layoutWeight(1)
            .height(48)
            .borderRadius(RADIUS.item)
            .onClick(() => {
              this.cancel();
            })
            .accessibilityText('取消')

          Button('确定')
            .fontSize(TYPO.body.size)
            .fontWeight(600)
            .fontColor(this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF') // HUI-035：主按钮文字→白
            .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#738A9C') // HUI-035：确定主按钮→雾霾蓝 btnPrimary
            .layoutWeight(1)
            .height(48)
            .borderRadius(RADIUS.item)
            .margin({ left: 12 })
            .onClick(() => {
              this.confirm();
            })
            .accessibilityText('确定，保存提醒时间 ' + this.pad2(this.hour) + ':' + this.pad2(this.minute))
        }
        .width('100%')
        .margin({ top: 22 })
      }
      .width('86%')
      .constraintSize({ maxWidth: 440 })
      .padding(SPACING.cardPadLg)
      .borderRadius(RADIUS.cardLg)
      .backgroundColor(this.tokens ? this.tokens.bgCard : 'rgba(255,255,255,0.9)')
      .backdropBlur(24)
      .border({ width: 1, color: this.tokens ? this.tokens.border : 'rgba(0,194,184,0.15)' })
      .shadow({
        radius: 48,
        color: this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.15)',
        offsetX: 0,
        offsetY: 16
      })
      .alignItems(HorizontalAlign.Center)
      .scale({ x: this.cardScale, y: this.cardScale })
      .transition(
        TransitionEffect.OPACITY
          .combine(TransitionEffect.scale({ x: 0.92, y: 0.92 }))
          .animation({ duration: 240, curve: Curve.EaseOut })
      )
    }
    .width('100%')
    .height('100%')
  }

  /** 时/分数值框（点击切换当前调节对象并高亮） */
  @Builder
  buildValueBox(field: string, valueText: string, unit: string) {
    Column() {
      Text(valueText)
        .fontSize(TYPO.numCard.size)
        .fontWeight(900)
        .fontColor(this.isActive(field)
          ? (this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
          : (this.tokens ? this.tokens.textPrimary : '#1A1A1A'))
      Text(unit)
        .fontSize(TYPO.eyebrow.size)
        .fontColor(this.isActive(field)
          ? (this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
          : (this.tokens ? this.tokens.textTertiary : '#8A8A8A'))
        .opacity(this.isActive(field) ? 0.85 : 1)
        .margin({ top: 2 })
        .attributeModifier(SKETCH_BODY) // HUI-029：时/分单位→清松手写体2
    }
    .width(96)
    .height(84)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .borderRadius(RADIUS.item)
    .backgroundColor(this.isActive(field)
      ? (this.tokens ? this.tokens.btnPrimary : '#738A9C')
      : (this.tokens ? this.tokens.surface : '#F2F4F3')) // HUI-035：时/分调节框激活→雾霾蓝 btnPrimary（非激活留 surface）
    .border({
      width: this.isActive(field) ? 0 : 1,
      color: this.tokens ? this.tokens.border : 'rgba(0,194,184,0.15)'
    })
    .onClick(() => {
      this.switchField(field);
    })
    .accessibilityText((field === 'hour' ? '小时' : '分钟') + valueText
      + (this.isActive(field) ? '，当前调节中' : '，点击切换为调节对象'))
  }

  /** 可转动圆盘（PanGesture 跟手 + 松手 spring 吸附刻度） */
  @Builder
  buildDial() {
    Stack({ alignContent: Alignment.Center }) {
      // 盘面
      Circle()
        .width(DIAL_SIZE)
        .height(DIAL_SIZE)
        .fill(this.tokens ? this.tokens.surface : '#F2F4F3')
        .stroke(this.tokens ? this.tokens.border : 'rgba(0,194,184,0.15)')
        .strokeWidth(1)
        .hitTestBehavior(HitTestMode.None)

      // 内圈装饰
      Circle()
        .width(DIAL_SIZE - 56)
        .height(DIAL_SIZE - 56)
        .fill(Color.Transparent)
        .stroke(this.tokens ? this.tokens.divider : 'rgba(0,0,0,0.06)')
        .strokeWidth(1)
        .hitTestBehavior(HitTestMode.None)

      // 旋转指针层（旋钮在顶部，随 dialAngle 绕盘心旋转）
      Column() {
        Column()
          .width(KNOB_SIZE)
          .height(KNOB_SIZE)
          .borderRadius(KNOB_SIZE / 2)
          .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#738A9C') // HUI-035：旋钮调节钮→雾霾蓝 btnPrimary
          .shadow({
            radius: 8,
            color: this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.25)',
            offsetX: 0,
            offsetY: 2
          })
      }
      .width(DIAL_SIZE)
      .height(DIAL_SIZE)
      .justifyContent(FlexAlign.Start)
      .alignItems(HorizontalAlign.Center)
      .padding({ top: 12 })
      .rotate({ angle: this.dialAngle, centerX: '50%', centerY: '50%' })
      .hitTestBehavior(HitTestMode.None)

      // 盘心大数值
      Column() {
        Text(this.activeField === 'hour' ? this.pad2(this.hour) : this.pad2(this.minute))
          .fontSize(TYPO.numHero.size)
          .fontWeight(900)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
        Text(this.activeField === 'hour' ? '小时' : '分钟')
          .fontSize(TYPO.eyebrow.size)
          .fontColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
          .margin({ top: 2 })
          .attributeModifier(SKETCH_BODY) // HUI-029：盘心单位标签→清松手写体2
      }
      .hitTestBehavior(HitTestMode.None)
    }
    .width(DIAL_SIZE)
    .height(DIAL_SIZE)
    .gesture(
      PanGesture({ distance: 1 })
        .onActionStart((event: GestureEvent) => {
          this.lastPointerAngle = this.pointerAngle(event);
        })
        .onActionUpdate((event: GestureEvent) => {
          const cur: number = this.pointerAngle(event);
          let delta: number = cur - this.lastPointerAngle;
          // 归一化到 [-180,180]，跨 0/360 边界平滑
          while (delta > 180) { delta -= 360; }
          while (delta < -180) { delta += 360; }
          this.dialAngle += delta;
          this.lastPointerAngle = cur;
          this.syncValueFromAngle();
        })
        .onActionEnd(() => {
          this.snapToTick();
        })
    )
    .accessibilityText('时间调节圆盘，转动以增减当前' + (this.activeField === 'hour' ? '小时' : '分钟'))
  }

  // ════════════════════════════════════════════════════════════
  // 圆盘计算（普通方法，非 build 内 getter）
  // ════════════════════════════════════════════════════════════

  /** 当前对象每刻度角度：时 360/24=15°，分 360/60=6° */
  private stepAngle(): number {
    return this.activeField === 'hour' ? 15 : 6;
  }

  /** 当前对象刻度总数 */
  private stepCount(): number {
    return this.activeField === 'hour' ? 24 : 60;
  }

  private isActive(field: string): boolean {
    return this.activeField === field;
  }

  /** 指针相对盘心的角度(度) */
  private pointerAngle(event: GestureEvent): number {
    const fingers = event.fingerList;
    if (!fingers || fingers.length === 0) {
      return this.lastPointerAngle;
    }
    const f = fingers[0];
    const cx: number = DIAL_SIZE / 2;
    const cy: number = DIAL_SIZE / 2;
    const dx: number = f.localX - cx;
    const dy: number = f.localY - cy;
    return Math.atan2(dy, dx) * 180 / Math.PI;
  }

  /** 由当前 dialAngle 实时推导数值（循环取模） */
  private syncValueFromAngle(): void {
    const step: number = this.stepAngle();
    const steps: number = this.stepCount();
    let idx: number = Math.round(this.dialAngle / step);
    idx = ((idx % steps) + steps) % steps;
    if (this.activeField === 'hour') {
      this.hour = idx;
    } else {
      this.minute = idx;
    }
  }

  /** 松手：spring 阻尼吸附到最近刻度，并落定数值 */
  private snapToTick(): void {
    const step: number = this.stepAngle();
    const steps: number = this.stepCount();
    const idxRaw: number = Math.round(this.dialAngle / step);
    const snapped: number = idxRaw * step;
    const idx: number = ((idxRaw % steps) + steps) % steps;
    if (this.activeField === 'hour') {
      this.hour = idx;
    } else {
      this.minute = idx;
    }
    animateTo({ curve: DIAL_SPRING }, () => {
      this.dialAngle = snapped;
    });
  }

  /** 切换调节对象：圆盘平滑转到新对象当前值对应角度 */
  private switchField(field: string): void {
    if (this.activeField === field) {
      return;
    }
    this.activeField = field;
    const value: number = field === 'hour' ? this.hour : this.minute;
    const target: number = value * this.stepAngle();
    animateTo({ curve: DIAL_SPRING }, () => {
      this.dialAngle = target;
    });
  }

  private clamp(v: number, mod: number): number {
    const r: number = Math.round(v) % mod;
    return r < 0 ? r + mod : r;
  }

  /** 补零两位 */
  private pad2(n: number): string {
    return n < 10 ? '0' + n.toString() : n.toString();
  }

  private cancel(): void {
    if (this.onCancel) {
      this.onCancel();
    }
  }

  private confirm(): void {
    if (this.onConfirm) {
      this.onConfirm(this.hour, this.minute);
    }
  }
}
