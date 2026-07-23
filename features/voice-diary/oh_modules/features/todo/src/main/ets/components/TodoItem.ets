// agentID: HUI-054
// agentID: HUI-078：标题下新增元信息行——截止日 M/D + 时间 + 地点 + 自定义标签 chip（图标+文字，
//   黑白中性配色），与来源徽标同 Flex 换行行；TodoItemData 扩展可选 time/location/customTag。
// HUI-001 改造（四轮·停抖链路重构）：删除交互与日记翻卡一致（长按抖动+右上角叉号+确认弹窗）。
//   四轮修「取消后仍抖」：真机证实 页面@State→TodoList@Prop→ForEach内TodoItem@Prop 三层下发链不可靠，
//   删除态改走 AppStorage 框架级广播——@StorageLink('todo_active_delete_id')@Watch 直达本组件（项目
//   theme_is_dark 同机制真机已验），长按本地直写、全局互斥自动成立，不再经父子传参/回调链。
//   双保险：build 用 if/else 拆抖动包装层——删除态主体包在带 rotate 的 Column 独立节点内，退出删除态
//   该节点整个销毁（节点亡=iterations:-1 残留动画必死），常态分支无 rotate 纯净渲染。
//   API24 已验：gesture.d.ts:2234 LongPressGesture；common.d.ts:3841 AnimateParam(iterations/playMode)、
//   :7443/7477 TransitionEffect scale/opacity；图标 sys.symbol.xmark（本地图标库 L293）。
// 组件：待办项卡片（勾选圆圈+标题+6色分类徽标+长按删除+缩放动画）
// 关联设计稿：UX-001 §2.3 TodoView 复刻
// 关联任务：P2-01 待办「时光轴」TodoView 复刻
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 无障碍：accessibilityText + 触控热区 >= 48x48vp
// 深色适配：ThemeColorTokens + 硬编码回退色

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-029：追加 SKETCH_BODY=清松手写体2（待办标题 + 来源徽标标签）。
import { IconMapper, RADIUS, SKETCH_BODY } from '@ohos/shared';

/**
 * 待办项数据接口
 * HUI-078：扩展可选展示字段 time/location/customTag（可选防破坏既有对象字面量构造点；
 *   模型层暂无对应持久化字段，DEV 接线后由页面层填充）。
 */
export interface TodoItemData {
  id: number;
  title: string;
  completed: boolean;
  sourceLabel: string;
  date: string;
  time?: string;
  location?: string;
  customTag?: string;
  dueDateFmt?: string;
  /** HUI-079：执行人昵称（可选，空/未填不显示徽标） */
  assigneeName?: string;
}

/**
 * 分类徽标样式
 */
interface CategoryBadge {
  icon: Resource;
  textColor: string;
  bgTint: string;
  borderColor: string;
}

// HUI-001：长按删除抖动参数（同 DiaryCarouselModal）
const SHAKE_ANGLE: number = 1.6;   // 抖动摆幅(deg)
const SHAKE_PERIOD: number = 110;  // 抖动半周期(ms)

@Component
export struct TodoItem {
  @Prop todoId: number = 0;
  @Prop title: string = '';
  @Prop @Watch('onCompletedChange') completed: boolean = false;
  @Prop sourceLabel: string = '';
  /** HUI-078：截止日期 YYYY-MM-DD（展示为 M/D，空=不显示） */
  @Prop dueDate: string = '';
  /** HUI-078：时间文本（如 14:30，空=不显示） */
  @Prop timeText: string = '';
  /** HUI-078：地点（空=不显示） */
  @Prop location: string = '';
  /** HUI-078：自定义标签（空=不显示） */
  @Prop customTag: string = '';
  /** HUI-079：执行人昵称（空=不显示；灰度中性徽标，人物图标+昵称） */
  @Prop assigneeName: string = '';
  /** HUI-001（四轮）：当前删除态条目 id（全局唯一，-1=无）——AppStorage 框架级双向同步，
   *  绕开 页面@State→TodoList@Prop→ForEach内@Prop 三层链（真机证实该链退出方向不同步） */
  @StorageLink('todo_active_delete_id') @Watch('onActiveDeleteChange') activeDeleteId: number = -1;
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  /** 勾选缩放值 */
  @State private checkScale: number = 1;
  /** HUI-001：抖动摆角(deg)，animateTo 无限交替驱动（同日记卡） */
  @State private shakeAngle: number = 0;

  onToggle?: (todoId: number) => void;
  onDelete?: (todoId: number) => void;
  /** HUI-001：点击项进入编辑（由页面层弹出编辑弹窗） */
  onEdit?: (todoId: number) => void;

  build() {
    // HUI-001（三轮）：根 Stack 改 TopEnd——叉号浮于条目右上角（同日记卡）；左滑背景层已拆除。
    //   叉号固定 44vp < 最小行高(~46vp，padding24+勾选圈22)，参与测量不撑行高（二轮结论沿用）。
    Stack({ alignContent: Alignment.TopEnd }) {
      // HUI-001（四轮·停抖双保险）：if/else 拆抖动包装层——删除态主体挂在带 rotate 的独立 Column 节点内，
      //   退出删除态该节点整个销毁（节点亡=iterations:-1 残留动画必死）；常态分支无 rotate 纯净渲染。
      if (this.isDeleteActive()) {
        Column() {
          this.buildCardBody()
        }
        .width('100%')
        .rotate({
          x: 0,
          y: 0,
          z: 1,
          angle: this.shakeAngle,
          centerX: '50%',
          centerY: '50%'
        })
      } else {
        this.buildCardBody()
      }

      // ── HUI-001（三轮）：删除态右上角叉号（同日记卡：黑白灰中性小圆钮 44vp 热区，200ms 缩放渐隐浮现/退场；
      //   底=tokens.textPrimary 浅色近黑/深色近白，叉=tokens.bgCard 反色，对比度≥4.5:1，禁大红）──
      if (this.isDeleteActive()) {
        Button() {
          SymbolGlyph(IconMapper.CLOSE)
            .fontSize(18)
            .fontColor([this.tokens ? this.tokens.bgCard : '#FFFFFF'])
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor(this.tokens ? this.tokens.textPrimary : '#3C3C3C')
        .margin({ top: 2, right: 6 })
        .transition(
          TransitionEffect.opacity(0)
            .animation({ duration: 200, curve: Curve.EaseOut })
            .combine(TransitionEffect.scale({ x: 0.6, y: 0.6 }))
        )
        .onClick(() => {
          if (this.onDelete) {
            this.onDelete(this.todoId);
          }
        })
        .accessibilityText('删除待办：' + this.title)
      }
    }
    .width('100%')
  }

  // ═══ 主体卡片 @Builder（删除态/常态两分支复用；rotate 由删除态包装层承担，本体不挂动画属性）═══
  @Builder
  buildCardBody() {
    Row() {
      // 勾选圆圈（22x22，带缩放动画）
      Column() {
        if (this.completed) {
          SymbolGlyph(IconMapper.CHECKMARK)
            .fontSize(11)
            // HUI-034：完成态勾选套 btnPrimaryText 白勾（与 btnPrimary 底成对比）
            .fontColor([this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF'])
        }
      }
      .width(22)
      .height(22)
      .borderRadius(11)
      // HUI-034：待办勾选圈完成态套 btnPrimary 雾霾蓝底（未完成留白描边）
      .backgroundColor(this.completed ?
        (this.tokens ? this.tokens.btnPrimary : '#738A9C') :
        Color.Transparent)
      .border({
        width: this.completed ? 0 : 2,
        color: this.tokens ? this.tokens.border : '#E0E0E0'
      })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .scale({ x: this.checkScale, y: this.checkScale })
      .onClick(() => {
        if (this.onToggle) {
          this.onToggle(this.todoId);
        }
      })
      .animation({ duration: 200, curve: Curve.EaseInOut })
      .accessibilityText(this.completed ?
        '已完成：' + this.title :
        '未完成：' + this.title + '，点击标记完成')
      .accessibilityLevel('yes')

      Column() {
        // 标题文字（完成态：删除线 + 灰色）
        Text(this.title)
          .fontSize(14)
          .fontWeight(this.completed ? 400 : 600)
          .fontColor(this.completed ?
            (this.tokens ? this.tokens.textTertiary : '#8A8A8A') :
            (this.tokens ? this.tokens.textPrimary : '#1A1A1A'))
          .decoration(this.completed ? {
            type: TextDecorationType.LineThrough,
            color: this.tokens ? this.tokens.textTertiary : '#8A8A8A'
          } : undefined)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .accessibilityLevel('no')
          .attributeModifier(SKETCH_BODY) // HUI-029：待办标题→清松手写体2

        // HUI-078：标题下元信息行（截止日 M/D + 时间 + 地点 + 自定义标签 + 来源徽标，Flex 换行）
        //   图标验证（本地 resource/HarmonyOS_全量图标库.md）：calendar L311 / clock L323 / map L1929 /
        //   bookmark L61（location 裸名不在库，地点语义降级 map）✅
        if (this.hasMetaInfo()) {
          Flex({ wrap: FlexWrap.Wrap }) {
            if (this.dueDate.length > 0) {
              this.buildMetaChip($r('sys.symbol.calendar'), this.getDueShort(), '截止日期' + this.getDueShort())
            }
            if (this.timeText.length > 0) {
              this.buildMetaChip($r('sys.symbol.clock'), this.timeText, '时间' + this.timeText)
            }
            if (this.location.length > 0) {
              this.buildMetaChip($r('sys.symbol.map'), this.location, '地点' + this.location)
            }
            if (this.customTag.length > 0) {
              this.buildMetaChip(IconMapper.TAG, this.customTag, '标签' + this.customTag)
            }
            // HUI-079：执行人徽标（人物图标+昵称，复用 buildMetaChip 黑白灰中性配色；
            //   图标验证：person 在本地图标库 L1853 ✅，同 IconMapper.NAV_PROFILE 既有用法）
            if (this.assigneeName.length > 0) {
              this.buildMetaChip($r('sys.symbol.person'), this.assigneeName, '执行人' + this.assigneeName)
            }

            // 来源分类徽标（6色轻底 + 边框 + 小图标，原逻辑保留）
            if (this.sourceLabel.length > 0) {
              Row() {
                SymbolGlyph(this.getBadge().icon)
                  .fontSize(10)
                  .fontColor([this.getBadge().textColor])
                Text(this.sourceLabel)
                  .fontSize(9)
                  .fontWeight(700)
                  .fontColor(this.getBadge().textColor)
                  .margin({ left: 2 })
                  .attributeModifier(SKETCH_BODY) // HUI-029：来源徽标标签→清松手写体2
              }
              .backgroundColor(this.getBadge().bgTint)
              .border({
                width: 1,
                color: this.getBadge().borderColor
              })
              .borderRadius(10)
              .padding({ left: 6, right: 8, top: 2, bottom: 2 })
              .margin({ right: 4, bottom: 2 })
              .accessibilityText('来源：' + this.sourceLabel)
            }
          }
          .margin({ top: 4 })
        }
      }
      .layoutWeight(1)
      .margin({ left: 12 })
      .alignItems(HorizontalAlign.Start)

      Blank()
    }
    .width('100%')
    .padding({ left: RADIUS.item, right: RADIUS.item, top: 12, bottom: 12 })
    .backgroundColor(this.tokens ? this.tokens.bgCard : '#FAFAFA')
    .border({
      width: 1,
      color: this.tokens ? this.tokens.border : '#E0E0E0'
    })
    .borderRadius(RADIUS.item)
    // HUI-001：短按=编辑；本条删除态下点其他区域=退出；别条删除态下点击=仅全局退出不进编辑；
    //   勾选圆圈子组件 onClick 自行消费，不会冒泡到此。
    .onClick(() => {
      if (this.activeDeleteId !== -1) {
        this.requestDeleteMode(-1);
        return;
      }
      if (this.onEdit) {
        this.onEdit(this.todoId);
      }
    })
    // HUI-001：长按进入/退出删除态（LongPressGesture 与 onClick 短按天然区分，同日记卡）
    .gesture(
      LongPressGesture({ repeat: false })
        .onAction(() => {
          this.requestDeleteMode(this.isDeleteActive() ? -1 : this.todoId);
        })
    )
    .accessibilityGroup(true)
  }

  // ═══ HUI-078：元信息小 chip @Builder（图标+文字，黑白中性配色——用户偏好黑白无青）═══
  @Builder
  buildMetaChip(icon: Resource, text: string, a11yText: string) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(10)
        .fontColor([this.tokens ? this.tokens.textSecondary : '#5A5A5A'])
      Text(text)
        .fontSize(9)
        .fontWeight(600)
        .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
        .margin({ left: 2 })
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .constraintSize({ maxWidth: 120 })
        .attributeModifier(SKETCH_BODY) // HUI-029 沿用：徽标标签→清松手写体2
    }
    .backgroundColor(this.tokens ? this.tokens.surface : '#F2F2F2')
    .border({
      width: 1,
      color: this.tokens ? this.tokens.border : '#E0E0E0'
    })
    .borderRadius(10)
    .padding({ left: 6, right: 8, top: 2, bottom: 2 })
    .margin({ right: 4, bottom: 2 })
    .accessibilityText(a11yText)
  }

  /** HUI-078：是否有任一元信息可展示（普通方法非 getter · §9.1）；HUI-079 掺入 assigneeName */
  private hasMetaInfo(): boolean {
    return this.dueDate.length > 0 || this.timeText.length > 0 ||
      this.location.length > 0 || this.customTag.length > 0 ||
      this.assigneeName.length > 0 || this.sourceLabel.length > 0;
  }

  /** HUI-078：截止日短格式 M/D（如 7/20；解析失败回原串） */
  private getDueShort(): string {
    const parts: string[] = this.dueDate.split('-');
    if (parts.length !== 3) {
      return this.dueDate;
    }
    return parseInt(parts[1]).toString() + '/' + parseInt(parts[2]).toString();
  }

  /** HUI-001：本条是否处于删除态（普通方法非 getter · §9.1） */
  private isDeleteActive(): boolean {
    return this.activeDeleteId === this.todoId;
  }

  /** HUI-001（四轮）：切换删除态——直写 @StorageLink（AppStorage 广播，全局互斥/跨条退出自动成立），
   *  不再经 onDeleteModeChange 回调链上传页面 */
  private requestDeleteMode(id: number): void {
    this.activeDeleteId = id;
  }

  /** HUI-001：activeDeleteId 变化回调——本条进入删除态启动无限交替抖动，退出摆角归零（同日记卡启停） */
  private onActiveDeleteChange(): void {
    if (this.isDeleteActive()) {
      this.shakeAngle = -SHAKE_ANGLE;
      animateTo({
        duration: SHAKE_PERIOD,
        curve: Curve.Linear,
        iterations: -1,
        playMode: PlayMode.Alternate
      }, () => {
        this.shakeAngle = SHAKE_ANGLE;
      });
    } else if (this.shakeAngle !== 0) {
      animateTo({ duration: SHAKE_PERIOD, curve: Curve.Linear }, () => {
        this.shakeAngle = 0;
      });
    }
  }

  /**
   * completed 变化回调：触发勾选缩放动画
   */
  private onCompletedChange(): void {
    this.playCheckAnimation();
  }

  /**
   * 触发勾选缩放动画（0.5 → 1.2 → 1.0 弹性效果）
   */
  private playCheckAnimation(): void {
    animateTo({ duration: 150, curve: Curve.EaseIn }, () => {
      this.checkScale = 0.5;
    });
    animateTo({ duration: 250, curve: Curve.EaseOut }, () => {
      this.checkScale = 1.2;
    });
    animateTo({ duration: 200, curve: Curve.EaseInOut }, () => {
      this.checkScale = 1.0;
    });
  }

  /**
   * 获取来源分类徽标样式（图标+颜色，6色对齐 UX-001 §1.1 语义色）
   * 日记=青(primary)、微信=emerald、语音=purple、学习=blue、工作=orange、其他=gray
   */
  private getBadge(): CategoryBadge {
    const label: string = this.sourceLabel;

    if (label === '日记') {
      return {
        icon: IconMapper.NAV_DIARY,
        textColor: this.tokens ? this.tokens.primary : '#00C2B8',
        bgTint: this.tokens ? this.tokens.accent : '#E6F9F8',
        borderColor: this.tokens ? this.tokens.primaryLight : '#A2ECE9'
      };
    }
    if (label === '微信') {
      // HUI-023：死值青 #00C2B8 → 读 token 墨色（黑白主题；来源差异由图标+文案承担）
      return {
        icon: $r('sys.symbol.ellipsis_bubble'),
        textColor: this.tokens ? this.tokens.primary : '#000000',
        bgTint: this.tokens ? this.tokens.accent : '#F2F2F2',
        borderColor: this.tokens ? this.tokens.border : '#CCCCCC'
      };
    }
    if (label === '语音') {
      // HUI-023：死值蓝灰 #90A4AE → 读 token 墨色
      return {
        icon: IconMapper.MIC,
        textColor: this.tokens ? this.tokens.primary : '#000000',
        bgTint: this.tokens ? this.tokens.accent : '#F2F2F2',
        borderColor: this.tokens ? this.tokens.border : '#CCCCCC'
      };
    }
    if (label === '学习') {
      // HUI-023：死值蓝 #4FC3F7 → 读 token 墨色
      return {
        icon: IconMapper.COPY,
        textColor: this.tokens ? this.tokens.primary : '#000000',
        bgTint: this.tokens ? this.tokens.accent : '#F2F2F2',
        borderColor: this.tokens ? this.tokens.border : '#CCCCCC'
      };
    }
    if (label === '工作') {
      // HUI-023：死值青 #80CBC4 → 读 token 墨色
      return {
        icon: $r('sys.symbol.briefcase'),
        textColor: this.tokens ? this.tokens.primary : '#000000',
        bgTint: this.tokens ? this.tokens.accent : '#F2F2F2',
        borderColor: this.tokens ? this.tokens.border : '#CCCCCC'
      };
    }
    // 通用 / 日常
    // HUI-023：死值灰 #6B7280 → 读 token 次要墨色
    return {
      icon: IconMapper.TAG,
      textColor: this.tokens ? this.tokens.textSecondary : '#666666',
      bgTint: this.tokens ? this.tokens.accent : '#F2F2F2',
      borderColor: this.tokens ? this.tokens.border : '#CCCCCC'
    };
  }
}
