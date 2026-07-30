// agentID: HUI-076
// agentID: HUI-041（T-D05：返回箭头→裸 arrow_left 加粗；添加按钮→空心描边圆圈+粗加号）
// agentID: HUI-042（T-D07 三轮：系统 DatePickerDialog 顶部标题区不可换肤（.d.ts 全字段穷举无 title/header 样式项）→ 按用户既定决策升级自绘 ThemedDatePickerModal（shared），滚轮交互不变、全量主题化）
// HUI-077 修订：待办条目改为「一条接一条从左向右滑入」的错峰入场动画（每条间隔 80ms，
//   springMotion 弹性）。单条卡片抽为子组件 TodoAnimCard 自带入场动画，删除原整板右→0 滑入逻辑。
// 组件：待办 / 日程「面板」共享内容（日期头 + 日历选择 + 勾选卡片列表 + 空态 + 底部输入栏）
// 说明：待办页 TodoPage 与明日日程页 TomorrowPage 交互完全一致，抽为可复用 @Component，
//       仅由 pageTitle / dayOffset 两个入参区分默认日期与标题（DRY，避免两页重复实现）。
// 关联任务：HUI-076（待办页 + 明日日程页 · 菜单入口独立路由）
// 开发范式：ArkTS 声明式开发范式
// 令牌驱动：颜色读 @StorageLink('theme_tokens')（判空回退）；圆角 RADIUS / 间距 SPACING / 排版 TYPO
// 图标：全部走 IconMapper（本地图标库，禁 emoji），日历 calendar / 添加 plus_circle_fill
// 崩溃防范（PROJECT_SPEC §9）：
//   · §9.4 @StorageLink tokens 读取全判空回退；
//   · §9.3 字段初值不含 $r()（图标经 IconMapper 常量、selectedDate/items 于 aboutToAppear 赋值）；
//   · 无 getter-in-build（数据经 getVisibleItems() 普通方法取值，卡片入场经 aboutToAppear 调度）。

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-027：引入手绘字体助手——SKETCH_TITLE=猫啃什锦黑(eyebrow 页标)，SKETCH_BODY=清松手写体2(待办标题)；日期数字头保留系统字。
import { IconMapper, DateUtils, EmptyStateView, RADIUS, SPACING, TYPO, ICON, TodoItem, EventBus, SKETCH_TITLE, SKETCH_BODY, ThemedDatePickerModal } from '@ohos/shared';
import { TodoViewModel } from 'features/todo';
import { curves } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'TodoBoard';

/** 面板内待办条目（UI 展示结构） */
interface BoardTodoItem {
  id: number;
  title: string;
  completed: boolean;
  /** 归属日期 YYYY-MM-DD */
  date: string;
}

/** 待办条目入场动画：相邻条目错峰间隔(ms) */
const ITEM_STAGGER_STEP: number = 80;

@Component
export struct TodoBoard {
  /** 页面标题（eyebrow 小标） */
  @Prop pageTitle: string = '待办';
  /** 默认日期偏移：0=今天 / 1=明天 */
  @Prop dayOffset: number = 0;

  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  /** 返回回调（独立路由页传入 router.back；未传则不渲染返回按钮） */
  onBack?: () => void;

  /** 当前选中日期 YYYY-MM-DD（aboutToAppear 赋值，避免字段初值副作用） */
  @State private selectedDate: string = '';
  /** 当前板待办（真实数据源，aboutToAppear/loadData 从 TodoViewModel 拉取；R1 必须 @State 才刷新） */
  @State private items: BoardTodoItem[] = [];
  /** 底部输入框文本 */
  @State private inputText: string = '';
  /** HUI-042（T-D07 三轮）：主题化日期选择弹窗显隐 */
  @State private showDatePicker: boolean = false;

  /** 待办业务 VM（默认空构造，init() 后 getter 才有数据） */
  private vm: TodoViewModel = new TodoViewModel();

  aboutToAppear(): void {
    // 默认日期：今天 + dayOffset（dayOffset=0→今天 / 1→明天）
    this.selectedDate = DateUtils.daysFromNow(this.dayOffset);
    // 异步拉真实待办（不阻塞首帧）
    this.loadData();
    // R2：订阅 TODO_* 跨页刷新（其它页写待办时重载本板）
    EventBus.on(EventBus.EventNames.TODO_CREATED, (data: Record<string, Object>) => {
      this.loadData();
    });
    EventBus.on(EventBus.EventNames.TODO_COMPLETED, (data: Record<string, Object>) => {
      this.loadData();
    });
    EventBus.on(EventBus.EventNames.TODO_DELETED, (data: Record<string, Object>) => {
      this.loadData();
    });
  }

  aboutToDisappear(): void {
    EventBus.off(EventBus.EventNames.TODO_CREATED);
    EventBus.off(EventBus.EventNames.TODO_COMPLETED);
    EventBus.off(EventBus.EventNames.TODO_DELETED);
  }

  // ═══════════════════════════════════════════════════
  // 数据加载（§6 R5：统一以 today 为参考日 init，按 dayOffset/type 取列表，勿 init(明日日期) 造二次偏移）
  // ═══════════════════════════════════════════════════

  /** 本板类型：0→'today' / 1→'tomorrow' */
  private getBoardType(): string {
    return this.dayOffset === 0 ? 'today' : 'tomorrow';
  }

  /**
   * VM init 参考日：
   * · 今日板（type=today）：参考日 = 选中日，getTodayTodos() 查(选中日,'today')；
   * · 明日板（type=tomorrow）：参考日 = 选中日-1，getTomorrowTodos() 查(参考日+1=选中日,'tomorrow')。
   * 二者最终都取「date=选中日」的对应 type 待办，且 add 落库日期与之一致（明日新增重启仍在）。
   */
  private getReferenceDate(): string {
    return this.dayOffset === 0 ? this.selectedDate : DateUtils.daysAgo(1, this.selectedDate);
  }

  /** 从 DB 拉取当前板待办并填充 @State（异常兜底空态） */
  private async loadData(): Promise<void> {
    try {
      await this.vm.init(this.getReferenceDate());
      this.applyVmData();
    } catch (err) {
      this.items = [];
      hilog.error(0x0000, TAG, 'loadData failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 用 VM 内存态回填 items（写操作后即时刷新用） */
  private applyVmData(): void {
    const list: TodoItem[] = this.dayOffset === 0
      ? this.vm.getTodayTodos()
      : this.vm.getTomorrowTodos();
    this.items = list.map((t: TodoItem): BoardTodoItem => this.toBoardItem(t));
  }

  /** R3 字段映射：TodoItem（DB 蛇形/0-1）→ BoardTodoItem（驼峰/bool） */
  private toBoardItem(t: TodoItem): BoardTodoItem {
    const item: BoardTodoItem = {
      id: t.id,
      title: t.title,
      completed: t.isCompleted(),
      date: t.date
    };
    return item;
  }

  // ═══════════════════════════════════════════════════
  // 计算（普通方法，规避 §9.1 getter-in-build）
  // ═══════════════════════════════════════════════════

  private getVisibleItems(): BoardTodoItem[] {
    // items 已按当前板日期/类型从 VM 拉取，直接返回（date 与 selectedDate 一致）
    return this.items;
  }

  private getHeaderDateText(): string {
    if (this.selectedDate.length === 0) {
      return '';
    }
    return DateUtils.formatDateCN(this.selectedDate) + ' ' + DateUtils.getWeekdayName(this.selectedDate);
  }

  // ═══════════════════════════════════════════════════
  // 操作
  // ═══════════════════════════════════════════════════

  /** 打开主题化日期选择弹窗
   *  HUI-042（T-D07 三轮）：原 showDatePickerDialog 顶部标题区不可换肤（date_picker.d.ts:721
   *  DatePickerDialogOptions 全字段穷举无 title/header 样式项），按用户既定决策升级自绘
   *  ThemedDatePickerModal（shared）——内联系统 DatePicker 滚轮，交互不变，全量主题化。 */
  private openDatePicker(): void {
    this.showDatePicker = true;
  }

  /** 弹窗确定回调：选中值处理逻辑与原 onDateAccept 完全一致（功能等价，仅换弹窗壳） */
  private onDateConfirmed(value: Date): void {
    this.showDatePicker = false;
    animateTo({ duration: 260, curve: Curve.EaseOut }, () => {
      this.selectedDate = DateUtils.formatDate(value);
    });
    // 切换日期后按新参考日重拉当前板待办
    this.loadData();
  }

  /** 切换完成状态：调 VM 落库后回读刷新 */
  private toggleItem(id: number): void {
    this.toggleAsync(id);
  }

  private async toggleAsync(id: number): Promise<void> {
    try {
      await this.vm.toggleComplete(id);
      animateTo({ duration: 220, curve: Curve.EaseInOut }, () => {
        this.applyVmData();
      });
    } catch (err) {
      hilog.error(0x0000, TAG, 'toggle failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 添加待办：调 VM 按本板 type 落库，写入当前选中日期 */
  private addItem(): void {
    const title: string = this.inputText.trim();
    if (title.length === 0) {
      return;
    }
    this.addAsync(title);
  }

  /** 调 VM add（L2 取返回 TodoItem.id），成功后回读刷新并清空输入 */
  private async addAsync(title: string): Promise<void> {
    try {
      const created: TodoItem | null = await this.vm.add(title, this.getBoardType());
      if (created !== null) {
        animateTo({ duration: 300, curve: Curve.FastOutSlowIn }, () => {
          this.applyVmData();
          this.inputText = '';
        });
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'add failed: %{public}s', JSON.stringify(err));
    }
  }

  // ═══════════════════════════════════════════════════
  // 构建
  // ═══════════════════════════════════════════════════

  build() {
    // HUI-042（T-D07 三轮）：根节点包 Stack，为主题化日期弹窗提供全屏覆盖层（同 SettingsPage 先例）
    Stack() {
      Column() {
      this.buildHeader()

      // 列表区（撑满剩余空间，可滚动）
      Column() {
        if (this.getVisibleItems().length > 0) {
          Scroll() {
            Column() {
              ForEach(this.getVisibleItems(), (item: BoardTodoItem, index: number) => {
                TodoAnimCard({
                  title: item.title,
                  completed: item.completed,
                  animIndex: index,
                  onToggle: () => {
                    this.toggleItem(item.id);
                  }
                })
              }, (item: BoardTodoItem) => {
                // HUI-001 修「勾选圆圈点击不重绘」：ForEach key 原只含 id（TodoList 同病，真机实证）——
                //   completed/title 变化 key 不变 → itemGenerator 不重执行 → 嵌套 @Prop 收不到更新。
                //   掺入变化字段即触发该条销毁重建强制重绘。
                return item.id.toString() + '_' + (item.completed ? '1' : '0') + '_' + item.title;
              })
            }
            .width('100%')
            .padding({
              left: SPACING.pageH,
              right: SPACING.pageH,
              top: SPACING.cardGap,
              bottom: SPACING.cardGap
            })
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
          .edgeEffect(EdgeEffect.Spring)
          .align(Alignment.Top)
        } else {
          Column() {
            EmptyStateView({
              icon: IconMapper.EMPTY,
              animPath: 'animations/小猫探头.json',
              title: '这一天还没有安排',
              description: '在下方输入框添加一条新的待办吧',
              showAction: false
            })
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        }
      }
      .width('100%')
      .layoutWeight(1)

      this.buildInputBar()
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.tokens ? this.tokens.bg : '#F5F7FA')

      // 主题化日期选择弹窗（覆盖层，条件渲染——同 SettingsPage ReminderTimePickerModal 先例）
      if (this.showDatePicker) {
        ThemedDatePickerModal({
          initialDate: this.selectedDate,
          onConfirm: (value: Date) => {
            this.onDateConfirmed(value);
          },
          onCancel: () => {
            this.showDatePicker = false;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  // 顶部：标题 eyebrow + 当前日期 + 右上角日历图标
  @Builder
  buildHeader() {
    Row() {
      // 返回按钮（仅独立路由页渲染）
      if (this.onBack !== undefined) {
        Button() {
          SymbolGlyph(IconMapper.ARROW_BACK)
            .fontSize(ICON.navBack)
            .fontWeight(FontWeight.Bold) // HUI-041：系统裸箭头加粗
            .fontColor([this.tokens ? this.tokens.textPrimary : '#1A1A1A'])
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .margin({ right: 8 })
        // HUI-041：去圆形填充底，保留 44vp 透明热区
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          if (this.onBack !== undefined) {
            this.onBack();
          }
        })
        .accessibilityText('返回')
      }

      Column() {
        Text(this.pageTitle)
          .fontSize(TYPO.eyebrow.size)
          .fontWeight(700)
          .fontColor(this.tokens ? this.tokens.textSecondary : '#666666')
          .opacity(0.6)
          .letterSpacing(2)
          .attributeModifier(SKETCH_TITLE) // HUI-027：页面 eyebrow 小标→猫啃什锦黑

        Text(this.getHeaderDateText())
          .fontSize(TYPO.sectionTitle.size)
          .fontWeight(TYPO.sectionTitle.weight)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .margin({ top: 4 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 右上角日历图标（点击弹出日期选择器）
      Button() {
        SymbolGlyph(IconMapper.TAB_CALENDAR)
          .fontSize(20)
          // HUI-034：日期调节触发图标套 btnPrimary 雾霾蓝
          .fontColor([this.tokens ? this.tokens.btnPrimary : '#0A59F7'])
      }
      .width(44)
      .height(44)
      .borderRadius(22)
      .backgroundColor(this.tokens ? this.tokens.accent : '#EBF5FF')
      .onClick(() => {
        this.openDatePicker();
      })
      .accessibilityText('选择日期')
    }
    .width('100%')
    .alignItems(VerticalAlign.Center)
    .padding({
      left: SPACING.pageH,
      right: SPACING.pageH,
      top: SPACING.pageTop,
      bottom: 4
    })
  }

  // 底部固定输入栏：TextInput + 添加按钮（HUI-041：空心描边圆圈 + 粗加号，大档 ICON.plusRingLg）
  @Builder
  buildInputBar() {
    Row() {
      TextInput({ text: this.inputText, placeholder: '添加新的待办事项...' })
        .layoutWeight(1)
        .height(46)
        .fontSize(TYPO.body.size)
        .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
        .placeholderColor(this.tokens ? this.tokens.textTertiary : '#999999')
        .backgroundColor(this.tokens ? this.tokens.bg : '#F5F7FA')
        .borderRadius(RADIUS.input)
        .padding({ left: 16, right: 16 })
        .onChange((value: string) => {
          this.inputText = value;
        })
        .onSubmit(() => {
          this.addItem();
        })

      Button() {
        SymbolGlyph(IconMapper.PLUS)
          .fontSize(ICON.plusLg)
          .fontWeight(FontWeight.Bold) // HUI-041：粗加号
          .fontColor([this.tokens ? this.tokens.btnPrimary : '#0A59F7'])
      }
      .width(ICON.plusRingLg)
      .height(ICON.plusRingLg)
      .borderRadius(ICON.plusRingLg / 2)
      .margin({ left: 12 })
      // HUI-041：去实心填充，保留一圈细描边空心圆（按钮即空心圆，46vp 热区不缩水）
      .backgroundColor(Color.Transparent)
      .border({
        width: ICON.ringStroke,
        color: this.tokens ? this.tokens.btnPrimary : '#0A59F7'
      })
      .onClick(() => {
        this.addItem();
      })
      .accessibilityText('添加待办')
    }
    .width('100%')
    .padding({
      left: SPACING.pageH,
      right: SPACING.pageH,
      top: 12,
      bottom: 20
    })
    .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
    .border({
      width: 1,
      color: this.tokens ? this.tokens.divider : '#EEF0F4'
    })
  }
}

// ═══════════════════════════════════════════════════
// 单条待办卡片（RADIUS.cardMd 圆角，左勾选圈 + 标题，已完成删除线）
//   自带错峰入场动画：初始 translateX -100% + opacity 0，
//   依 animIndex 错峰（每条 80ms）触发 springMotion 弹性滑入 → translateX 0 + opacity 1。
//   抽为独立 @Component 以便每条卡片持有各自的入场动画状态。
//   崩溃防范：§9.4 tokens 判空回退；入场经 aboutToAppear 内 animateTo 调度，无 getter-in-build。
// ═══════════════════════════════════════════════════
@Component
struct TodoAnimCard {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  /** 待办标题 */
  @Prop title: string = '';
  /** 完成态（父组件切换时经 @Prop 同步刷新视觉，无需重建） */
  @Prop completed: boolean = false;
  /** 错峰序号（可见列表中的位置，决定入场延迟 animIndex * 80ms） */
  @Prop animIndex: number = 0;

  /** 点击切换回调（父组件传入 toggleItem） */
  onToggle?: () => void;

  /** 入场动画：水平位移（-100% → 0，从左向右滑入） */
  @State private slideX: string = '-100%';
  /** 入场动画：透明度（0 → 1） */
  @State private cardOpacity: number = 0;

  aboutToAppear(): void {
    // 一条接一条从左向右滑入：延迟 animIndex * 80ms，springMotion 弹性曲线
    animateTo({
      delay: this.animIndex * ITEM_STAGGER_STEP,
      curve: curves.springMotion()
    }, () => {
      this.slideX = '0';
      this.cardOpacity = 1;
    });
  }

  build() {
    Row() {
      // 左侧勾选圆圈
      Stack() {
        if (this.completed) {
          SymbolGlyph(IconMapper.CHECKMARK)
            .fontSize(14)
            // HUI-034：完成态勾选套 btnPrimaryText 白勾（与 success 底成对比）
            .fontColor([this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF'])
        }
      }
      .width(26)
      .height(26)
      .borderRadius(13)
      // HUI-034：待办勾选圈完成态套 success 绿底（未完成留白描边）
      .backgroundColor(this.completed
        ? (this.tokens ? this.tokens.success : '#52C41A')
        : Color.Transparent)
      .border({
        width: this.completed ? 0 : 2,
        color: this.tokens ? this.tokens.border : '#E0E6ED'
      })

      // 标题（已完成加删除线 + 弱化色）
      Text(this.title)
        .fontSize(TYPO.body.size + 1)
        .fontWeight(this.completed ? 400 : 500)
        .fontColor(this.completed
          ? (this.tokens ? this.tokens.textTertiary : '#999999')
          : (this.tokens ? this.tokens.textPrimary : '#1A1A1A'))
        .decoration({
          type: this.completed ? TextDecorationType.LineThrough : TextDecorationType.None,
          color: this.tokens ? this.tokens.textTertiary : '#999999'
        })
        .layoutWeight(1)
        .margin({ left: 14 })
        .maxLines(2)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .attributeModifier(SKETCH_BODY) // HUI-027：待办标题(中文正文)→清松手写体2
    }
    .width('100%')
    .padding(SPACING.cardPadSm)
    .margin({ bottom: 10 })
    .borderRadius(RADIUS.cardMd)
    .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
    .border({
      width: 1,
      color: this.tokens ? this.tokens.border : '#E0E6ED'
    })
    .shadow({
      radius: 8,
      color: this.tokens ? this.tokens.shadow : 'rgba(0,0,0,0.08)',
      offsetX: 0,
      offsetY: 2
    })
    .translate({ x: this.slideX })
    .opacity(this.cardOpacity)
    .onClick(() => {
      if (this.onToggle !== undefined) {
        this.onToggle();
      }
    })
    .accessibilityText(this.title + (this.completed ? '，已完成' : '，未完成') + '，点击切换')
  }
}
