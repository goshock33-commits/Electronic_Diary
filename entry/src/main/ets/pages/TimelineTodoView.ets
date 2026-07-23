// agentID: HUI-076（承接 HUI-054 时光轴待办设计，抽为可嵌入组件）
// 组件：时光轴待办视图「时光轴」eyebrow+H1+青进度卡+分类筛选pill+今日备忘+明日日程
// 说明：本组件为 MainPage「时光轴」Tab 的嵌入内容（@Component 可复用，非 @Entry）。
//       原 pages/TodoPage.ets 的 TodoView 复刻实现整体迁移至此，struct 更名 TimelineTodoView，
//       以便将 pages/TodoPage.ets 让位给 @Entry 独立路由「待办页」（HUI-076 任务）。
// 关联设计稿：UX-001 §2.3 TodoView 复刻
// 开发范式：ArkTS 声明式开发范式
// 无障碍：accessibilityText + 触控热区 >= 48x48vp
// 深色适配：ThemeColorTokens + 硬编码回退色
// T101 接线（HUI-004 · PLN-001 §4 T101）：
//   数据源 mock → TodoViewModel。aboutToAppear 异步 init(today) 拉今/明真实待办填 @State；
//   新增/勾选/删除改调 VM 写方法并回读；订阅 EventBus TODO_* 跨页刷新，aboutToDisappear off。
//   字段映射（R3 蛇形→驼峰）：TodoItem.completed(0/1) → TodoItemData.completed(bool) 用 isCompleted()；
//   sourceLabel 映射自 TodoItem.category（日常/学习/工作/日记/微信/语音），对齐 AddTodoDialog categoryOptions。

import type { ThemeColorTokens, Result, FamilyMember } from '@ohos/shared';
// HUI-026：引入手绘字体助手（全局黑白手绘换肤）——SKETCH_TITLE=猫啃(H1/eyebrow/kicker)，SKETCH_BODY=清松(标签/正文)；纯数字仍走 FONT.mono*。
// DEV-FAMILY 接线：FamilyManager.getSelf() 取本机成员昵称，供 toData 填 assigneeName（「执行人」chip）。
import { IconMapper, RADIUS, SPACING, TYPO, FONT, TodoItem, EventBus, DateUtils, SKETCH_TITLE, SKETCH_BODY, FrostedDialog, FamilyManager } from '@ohos/shared';
import { TodoList, TodoViewModel, type TodoReminderOptions } from 'features/todo';
import { AddTodoDialog, type AddTodoResult } from 'features/todo';
import type { TodoItemData } from 'features/todo';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'TimelineTodoView';

/** "YYYY-MM-DD" + "HH:MM" → ms 时间戳（避免 new Date(string) ArkTS 兼容性问题） */
function toTimestamp(dateStr: string, timeStr: string): number {
  const dp: string[] = dateStr.split('-');
  const tp: string[] = timeStr.split(':');
  if (dp.length < 3 || tp.length < 2) { return 0; }
  const y = parseInt(dp[0], 10); const mo = parseInt(dp[1], 10); const d = parseInt(dp[2], 10);
  const h = parseInt(tp[0], 10); const mi = parseInt(tp[1], 10);
  if (isNaN(y) || isNaN(mo) || isNaN(d) || isNaN(h) || isNaN(mi)) { return 0; }
  const jsDate = new Date(y, mo - 1, d, h, mi, 0);
  return jsDate.getTime();
}

/** ms 时间戳 → "YYYY-MM-DD" */
function toDateStr(ts: number): string {
  const d = new Date(ts);
  const mo = d.getMonth() + 1;
  const day = d.getDate();
  return d.getFullYear() + '-' + (mo < 10 ? '0' : '') + mo + '-' + (day < 10 ? '0' : '') + day;
}

/** ms 时间戳 → "HH:MM" */
function toTimeStr(ts: number): string {
  const d = new Date(ts);
  const h = d.getHours();
  const m = d.getMinutes();
  return (h < 10 ? '0' : '') + h + ':' + (m < 10 ? '0' : '') + m;
}

/**
 * 筛选选项
 */
interface FilterOption {
  label: string;
  key: string;
}

@Component
export struct TimelineTodoView {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  /** 今日待办（真实数据源，aboutToAppear 从 TodoViewModel 拉取填充；R1 必须 @State 才刷新） */
  @State todayItems: TodoItemData[] = [];

  /** 明日待办（真实数据源，aboutToAppear 从 TodoViewModel 拉取填充） */
  @State tomorrowItems: TodoItemData[] = [];

  /** 待办业务 VM（默认空构造，init() 后 getter 才有数据） */
  private vm: TodoViewModel = new TodoViewModel();

  // DEV-FAMILY 接线：本机成员缓存——getSelf() 为 async 而 toData() 为同步映射，
  //   loadData 时取一次缓存 id+昵称；未设置本机成员时保持默认（不展示执行人 chip）。
  /** 本机成员 id（-1=未设置/查询失败） */
  private selfId: number = -1;
  /** 本机成员昵称（空串=未设置/查询失败） */
  private selfNickname: string = '';

  /** 分类筛选激活项 */
  @State activeFilter: string = '全部';

  /** HUI-001（四轮）：当前删除态条目 id——改 @StorageLink 与 TodoItem 同 key 直连（AppStorage 框架级
   *  广播，绕开 ForEach 内 @Prop 链），弹窗取消/确认/遮罩关闭置 -1 即全局停抖 */
  @StorageLink('todo_active_delete_id') activeDeleteTodoId: number = -1;

  /** 进度条动画宽度 */
  @State private progressAnimWidth: number = 0;

  /** 筛选选项 */
  private filterOptions: FilterOption[] = [
    { label: '全部', key: '全部' },
    { label: '日常', key: '日常' },
    { label: '微信', key: '微信' },
    { label: '语音', key: '语音' },
    { label: '学习', key: '学习' },
    { label: '工作', key: '工作' },
    { label: '日记', key: '日记' }
  ];

  /** 新增弹窗控制器 */
  private addDialogController: CustomDialogController = new CustomDialogController({
    builder: AddTodoDialog({
      onSubmit: (result: AddTodoResult) => {
        this.handleAddTodo(result);
      }
    }),
    autoCancel: true,
    customStyle: true,
    alignment: DialogAlignment.Center
  });

  // HUI-001：删除确认——点叉号后弹「是否确认删除」（FrostedDialog 中性黑白灰按钮，无大红），确认才走 VM.delete。
  /** 待确认删除的待办 id（叉号点击时暂存，弹窗确认时读取） */
  private pendingDeleteId: number = -1;
  /** 删除确认弹窗控制器（onConfirm 闭包在确认时读取 pendingDeleteId） */
  private deleteConfirmController: CustomDialogController = new CustomDialogController({
    builder: FrostedDialog({
      title: '是否确认删除',
      message: '删除后该条待办将从列表移除',
      confirmText: '删除',
      cancelText: '取消',
      neutralButtons: true,
      onConfirm: () => {
        if (this.pendingDeleteId > 0) {
          this.deleteAsync(this.pendingDeleteId);
          this.pendingDeleteId = -1;
        }
        // HUI-001（三轮）：确认后退出抖动删除态
        this.activeDeleteTodoId = -1;
      },
      onCancel: () => {
        // HUI-001（三轮）：取消删除同样退出抖动删除态（同日记卡）
        this.activeDeleteTodoId = -1;
      }
    }),
    autoCancel: true,
    customStyle: true,
    alignment: DialogAlignment.Center,
    // HUI-001 修停抖 bug：autoCancel 点遮罩/返回键关闭不走按钮 onCancel，用 controller 级 cancel
    //   回调兜底（API24 custom_dialog_controller.d.ts:96），保证所有关闭路径均退出抖动删除态
    cancel: () => {
      this.activeDeleteTodoId = -1;
      this.pendingDeleteId = -1;
    }
  });

  // HUI-001：编辑弹窗——复用 AddTodoDialog 编辑模式（预填标题），保存走现有 VM.update 通路。
  //   controller 按需新建（预填值随被编辑项变化，不能像新增那样一次性构造）。
  /** 正在编辑的待办（VM 内存态实例，保存时改 title 后整体交 VM.update） */
  private editingTodo: TodoItem | null = null;
  /** 编辑弹窗控制器（handleEdit 按需重建） */
  private editDialogController: CustomDialogController | null = null;

  // ═══════════════════════════════════════════════════
  // 计算
  // ═══════════════════════════════════════════════════

  aboutToAppear(): void {
    // 异步拉真实今/明待办（不阻塞首帧）
    this.loadData();
    // R2：订阅 TODO_* 跨页刷新（其它页新增/完成/删除待办时重载本页）
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
    // HUI-001（四轮）：离页清全局删除态（AppStorage key 常驻，防残留导致回页仍抖）
    this.activeDeleteTodoId = -1;
  }

  /** 从 DB 拉取今/明待办并填充 @State（异常兜底空态） */
  private async loadData(): Promise<void> {
    try {
      // DEV-FAMILY 接线：先刷新本机成员缓存（Result 范式不外抛；fail 时回落默认值不展示 chip）
      const selfRes: Result<FamilyMember> = await FamilyManager.getInstance().getSelf();
      if (selfRes.success && selfRes.data !== null) {
        this.selfId = selfRes.data.id;
        this.selfNickname = selfRes.data.nickname;
      } else {
        this.selfId = -1;
        this.selfNickname = '';
      }
      await this.vm.init(DateUtils.today());
      this.applyVmData();
    } catch (err) {
      this.todayItems = [];
      this.tomorrowItems = [];
      this.progressAnimWidth = 0;
      hilog.error(0x0000, TAG, 'loadData failed: %{public}s', JSON.stringify(err));
    }
  }

  /** 用 VM 内存态回填两个 @State（写操作后即时刷新用） */
  private applyVmData(): void {
    this.todayItems = this.vm.getTodayTodos().map((t: TodoItem): TodoItemData => this.toData(t));
    this.tomorrowItems = this.vm.getTomorrowTodos().map((t: TodoItem): TodoItemData => this.toData(t));
    this.progressAnimWidth = this.getProgressPercent();
  }

  /** R3 字段映射：TodoItem（DB 蛇形/0-1）→ TodoItemData（驼峰/bool）+ 新字段 due_date/location/custom_tags */
  private toData(t: TodoItem): TodoItemData {
    const fmtDate = (d: string | null): string => {
      if (!d) { return ''; }
      const m = d.match(/^\d{4}-(\d{2})-(\d{2})$/);
      return m ? parseInt(m[1], 10) + '/' + parseInt(m[2], 10) : d;
    };
    const item: TodoItemData = {
      id: t.id,
      title: t.title,
      completed: t.isCompleted(),
      sourceLabel: t.category,
      date: t.date,
      time: t.due_time ?? undefined,
      location: t.location ?? undefined,
      customTag: t.custom_tags ?? undefined
    };
    // 截止日期格式化 M/D 显示
    if (t.due_date) { item.dueDateFmt = fmtDate(t.due_date); }
    // DEV-FAMILY 接线：assignee_member_id 命中本机成员时填 assigneeName（FamilyManager.getSelf 缓存），
    //   经 TodoItem 卡片「执行人」chip 展示；派给他人/未指派/未设置本机成员均不填（不误标本机昵称）。
    if (t.assignee_member_id !== null && t.assignee_member_id === this.selfId && this.selfNickname.length > 0) {
      item.assigneeName = this.selfNickname;
    }
    return item;
  }

  private getAllItems(): TodoItemData[] {
    return [...this.todayItems, ...this.tomorrowItems];
  }

  private getCompletedCount(): number {
    return this.getAllItems().filter((item: TodoItemData) => item.completed).length;
  }

  private getTotalCount(): number {
    return this.getAllItems().length;
  }

  private getProgressPercent(): number {
    const total: number = this.getTotalCount();
    if (total <= 0) {
      return 0;
    }
    return Math.round((this.getCompletedCount() / total) * 100);
  }

  /**
   * 分类筛选：匹配 sourceLabel（即 TodoItem.category）
   * 「全部」全通过；「日常」匹配 category 为 '日常'（默认值）；其余精确匹配
   */
  private matchesFilter(item: TodoItemData): boolean {
    if (this.activeFilter === '全部') {
      return true;
    }
    if (this.activeFilter === '日常') {
      return item.sourceLabel === '日常' || item.sourceLabel.length === 0;
    }
    return item.sourceLabel === this.activeFilter;
  }

  private getFilteredToday(): TodoItemData[] {
    return this.todayItems.filter((item: TodoItemData) => this.matchesFilter(item));
  }

  private getFilteredTomorrow(): TodoItemData[] {
    return this.tomorrowItems.filter((item: TodoItemData) => this.matchesFilter(item));
  }

  // ═══════════════════════════════════════════════════
  // 操作
  // ═══════════════════════════════════════════════════

  /**
   * 处理新增待办提交
   */
  private handleAddTodo(result: AddTodoResult): void {
    this.addTodoAsync(result);
  }

  /** 新增待办：调 VM 落库（DEV-013 TodoReminderOptions 全字段接线） */
  private async addTodoAsync(result: AddTodoResult): Promise<void> {
    try {
      const remindOpts: TodoReminderOptions = {};
      if (result.dueDate) { remindOpts.dueDate = result.dueDate; }
      if (result.timeText) { remindOpts.dueTime = result.timeText; }
      if (result.location) { remindOpts.location = result.location; }
      if (result.customTag) { remindOpts.customTags = [result.customTag]; }
      if (result.remindDate && result.remindTime) {
        remindOpts.remindAt = toTimestamp(result.remindDate, result.remindTime);
      }
      const created: TodoItem | null = await this.vm.add(result.title, result.type, result.category, undefined, remindOpts);
      if (created !== null) {
        animateTo({ duration: 350, curve: Curve.EaseOut }, () => {
          this.applyVmData();
        });
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'add failed: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 处理待办完成状态切换
   */
  private handleToggle(id: number): void {
    this.toggleAsync(id);
  }

  /** 勾选完成：调 VM 落库切换后回读刷新 */
  private async toggleAsync(id: number): Promise<void> {
    try {
      await this.vm.toggleComplete(id);
      animateTo({ duration: 250, curve: Curve.EaseInOut }, () => {
        this.applyVmData();
      });
    } catch (err) {
      hilog.error(0x0000, TAG, 'toggle failed: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 处理待办删除：HUI-001 改为先弹「是否确认删除」确认弹窗，确认后才调 VM.delete
   */
  private handleDelete(id: number): void {
    this.pendingDeleteId = id;
    this.deleteConfirmController.open();
  }

  /** 删除待办：调 VM 落库删除后回读刷新 */
  private async deleteAsync(id: number): Promise<void> {
    try {
      await this.vm.delete(id);
      animateTo({ duration: 300, curve: Curve.EaseIn }, () => {
        this.applyVmData();
      });
    } catch (err) {
      hilog.error(0x0000, TAG, 'delete failed: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * HUI-001：处理点击待办项进入编辑——从 VM 内存态定位 TodoItem，弹编辑模式 AddTodoDialog（预填标题）
   */
  private handleEdit(id: number): void {
    let target: TodoItem | null = null;
    const todayList: TodoItem[] = this.vm.getTodayTodos();
    const tomorrowList: TodoItem[] = this.vm.getTomorrowTodos();
    const inToday: TodoItem | undefined = todayList.find((t: TodoItem) => t.id === id);
    if (inToday) {
      target = inToday;
    } else {
      const inTomorrow: TodoItem | undefined = tomorrowList.find((t: TodoItem) => t.id === id);
      if (inTomorrow) {
        target = inTomorrow;
      }
    }
    if (target === null) {
      return;
    }
    this.editingTodo = target;
    this.editDialogController = new CustomDialogController({
      builder: AddTodoDialog({
        editMode: true,
        presetTitle: target.title,
        presetDueDate: target.due_date ?? target.date,
        presetCategory: target.category,
        presetTimeText: target.due_time ?? '',
        presetLocation: target.location ?? '',
        presetCustomTag: target.getCustomTags().join(','),
        presetRemindDate: target.remind_at ? toDateStr(target.remind_at) : '',
        presetRemindTime: target.remind_at ? toTimeStr(target.remind_at) : '',
        onSubmit: (result: AddTodoResult) => {
          this.saveEditAsync(result);
        }
      }),
      autoCancel: true,
      customStyle: true,
      alignment: DialogAlignment.Center
    });
    this.editDialogController.open();
  }

  /** HUI-001（七轮·DEV-003 接线）：保存编辑——title/category 直接改对象；改期只传 newType
   *  （新签名 update(todo, newType?)，date/sort_order 由 VM 重算，UI 不算日期）；
   *  保存后 loadData 从 DB 回读（跨今日/明日桶移动最稳）。
   *  HUI-078：result.type 由弹窗按 dueDate 推导（今天→today，否则→tomorrow），本方法逻辑不变；
   *  timeText/location/customTag/remind* 新字段待 DEV 接线落库。 */
  private async saveEditAsync(result: AddTodoResult): Promise<void> {
    const target: TodoItem | null = this.editingTodo;
    if (target === null) {
      return;
    }
    try {
      target.title = result.title;
      target.category = result.category;
      if (result.dueDate) { target.due_date = result.dueDate; }
      if (result.timeText) { target.due_time = result.timeText; }
      if (result.location) { target.location = result.location; }
      if (result.customTag) { target.custom_tags = JSON.stringify([result.customTag]); }
      if (result.remindDate && result.remindTime) {
        target.remind_at = toTimestamp(result.remindDate, result.remindTime);
      }
      if (result.type !== target.type) {
        await this.vm.update(target, result.type);
      } else {
        await this.vm.update(target);
      }
      this.editingTodo = null;
      await this.loadData();
    } catch (err) {
      hilog.error(0x0000, TAG, 'edit save failed: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * 打开新增待办弹窗
   */
  private openAddDialog(): void {
    this.addDialogController.open();
  }

  // ═══════════════════════════════════════════════════
  // 构建
  // ═══════════════════════════════════════════════════

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Scroll() {
        Column() {
          // ══════════════════════════════════════════
          // 页面头部：eyebrow + H1 + 完成数/总数
          // ══════════════════════════════════════════
          Row() {
            Column() {
              // eyebrow: TIMELINE AXIS + scope 图标
              Row() {
                SymbolGlyph($r('sys.symbol.scope'))
                  .fontSize(11)
                  .fontColor([this.tokens ? this.tokens.primary : '#00C2B8'])
                Text('TIMELINE AXIS')
                  .fontSize(TYPO.eyebrow.size)
                  .fontWeight(700)
                  .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
                  .opacity(0.6)
                  .letterSpacing(2.5)
                  .margin({ left: 4 })
                  .attributeModifier(SKETCH_TITLE) // HUI-026：eyebrow 微标→猫啃什锦黑
              }
              .accessibilityText('时光轴待办')

              // H1：时光轴待办
              Text('时光轴待办')
                .fontSize(TYPO.h1.size)
                .fontWeight(TYPO.h1.weight)
                .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
                .margin({ top: 4 })
                .accessibilityLevel('no')
                .attributeModifier(SKETCH_TITLE) // HUI-026：页面 H1→猫啃什锦黑
            }
            .alignItems(HorizontalAlign.Start)

            Blank()

            // 完成/总数（右对齐，mono 粗体）
            Row() {
              Text(this.getCompletedCount().toString())
                .fontSize(15)
                .fontFamily(FONT.monoExtraBold)
                .fontWeight(900)
                .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
              Text('/')
                .fontSize(15)
                .fontWeight(300)
                .fontColor(this.tokens ? this.tokens.textTertiary : '#BDBDBD')
                .opacity(0.4)
              Text(this.getTotalCount().toString() + '项已毕')
                .fontSize(13)
                .fontFamily(FONT.monoBold)
                .fontWeight(700)
                .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
                .opacity(0.7)
            }
            .accessibilityText('完成进度：' + this.getCompletedCount() +
              ' / ' + this.getTotalCount() + ' 项')
          }
          .width('100%')
          .padding({ left: 0, right: 0 })
          .margin({ bottom: SPACING.sectionGap })

          // ══════════════════════════════════════════
          // 青进度卡（spring 填充 + mono 百分比）
          // ══════════════════════════════════════════
          if (this.getTotalCount() > 0) {
            Column() {
              Row() {
                Row() {
                  SymbolGlyph(IconMapper.CHECKIN_DONE)
                    .fontSize(11)
                    .fontColor([this.tokens ? this.tokens.primary : '#00C2B8'])
                  Text('践行总进度')
                    .fontSize(TYPO.eyebrow.size)
                    .fontWeight(700)
                    .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
                    .opacity(0.5)
                    .margin({ left: 4 })
                    .attributeModifier(SKETCH_TITLE) // HUI-026：卡片 kicker→猫啃什锦黑
                }

                Blank()

                // mono 百分比（numCard 字号）
                Text(this.getProgressPercent().toString() + '%')
                  .fontSize(TYPO.numCard.size)
                  .fontFamily(FONT.monoExtraBold)
                  .fontWeight(900)
                  .fontColor(this.tokens ? this.tokens.primary : '#00C2B8')
              }
              .width('100%')
              .margin({ bottom: 12 })

              // 进度条 track（浅青底）
              Row() {
                Row()
                  .height(8)
                  .borderRadius(4)
                  .width(this.progressAnimWidth.toString() + '%')
                  .backgroundColor(this.tokens ? this.tokens.primary : '#00C2B8')
                  .animation({
                    duration: 800,
                    curve: Curve.FastOutSlowIn,
                    iterations: 1
                  })
              }
              .width('100%')
              .height(8)
              .borderRadius(4)
              .backgroundColor(this.tokens ? this.tokens.accent : '#E6F9F8')
            }
            .width('100%')
            .borderRadius(RADIUS.cardMd)
            .padding(SPACING.cardPadMd)
            .backgroundColor(this.tokens ? this.tokens.bgCard : '#FAFAFA')
            .border({
              width: 1,
              color: this.tokens ? this.tokens.border : '#E0E0E0'
            })
            .shadow({
              radius: 8,
              color: this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.06)',
              offsetX: 0,
              offsetY: 2
            })
            .margin({ bottom: SPACING.cardGap })
          }

          // ══════════════════════════════════════════
          // 分类筛选 pill 横滑（7项：全部+6类）
          // ══════════════════════════════════════════
          Scroll() {
            Row() {
              ForEach(this.filterOptions, (opt: FilterOption) => {
                Text(opt.label)
                  .fontSize(10)
                  .fontWeight(800)
                  // HUI-037：筛选 pill 选中态文字→btnPrimaryText 白（配 btnPrimary 底），未选中→textSecondary
                  .fontColor(this.activeFilter === opt.key ?
                    (this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF') :
                    (this.tokens ? this.tokens.textSecondary : '#5A5A5A'))
                  .opacity(this.activeFilter === opt.key ? 1.0 : 0.7)
                  // HUI-041：筛选 pill 未选中底由死白 #FFFFFF 改读 surface token（浅色 #F7F7F7 / 深色 #242424），修深色白底浅灰字不可见
                  .backgroundColor(this.activeFilter === opt.key ?
                    (this.tokens ? this.tokens.btnPrimary : '#738A9C') :
                    (this.tokens ? this.tokens.surface : '#FFFFFF'))
                  .borderRadius(999)
                  .padding({ left: 14, right: 14, top: 7, bottom: 7 })
                  .border({
                    width: this.activeFilter === opt.key ? 0 : 1,
                    color: this.tokens ? this.tokens.border : '#E0E0E0'
                  })
                  .margin({ right: 6 })
                  .onClick(() => {
                    this.activeFilter = opt.key;
                  })
                  .attributeModifier(SKETCH_BODY) // HUI-026：分类筛选 chip→清松手写体2
                  .accessibilityText(opt.label + (this.activeFilter === opt.key ? '，已选中' : ''))
              })
            }
            .padding({ left: 0, right: 0 })
          }
          .scrollBar(BarState.Off)
          .scrollable(ScrollDirection.Horizontal)
          .margin({ bottom: SPACING.cardGap })

          // ══════════════════════════════════════════
          // 今日备忘分组卡
          // ══════════════════════════════════════════
          TodoList({
            groupType: 'today',
            groupTitle: '今日备忘',
            items: this.getFilteredToday(),
            onToggle: (id: number) => {
              this.handleToggle(id);
            },
            onDelete: (id: number) => {
              this.handleDelete(id);
            },
            onEdit: (id: number) => {
              this.handleEdit(id);
            },
            onAdd: () => {
              this.openAddDialog();
            }
          })
            .margin({ bottom: SPACING.cardGap })

          // ══════════════════════════════════════════
          // 明日日程分组卡
          // ══════════════════════════════════════════
          TodoList({
            groupType: 'tomorrow',
            groupTitle: '明日日程',
            items: this.getFilteredTomorrow(),
            onToggle: (id: number) => {
              this.handleToggle(id);
            },
            onDelete: (id: number) => {
              this.handleDelete(id);
            },
            onEdit: (id: number) => {
              this.handleEdit(id);
            },
            onAdd: () => {
              this.openAddDialog();
            }
          })
        }
        .width('100%')
        .padding({
          left: SPACING.pageH,
          right: SPACING.pageH,
          top: SPACING.pageTop,
          bottom: SPACING.pageBottom
        })
      }
      .width('100%')
      .height('100%')
      .backgroundColor(this.tokens ? this.tokens.bg : '#FAF8F5')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)

      // HUI-001：右下 FAB 加号按钮已移除（页面 3 个加号与卡片中间"添加待办"按钮重复，全部去除）。
      //   原实现：56x56 圆钮 + IconMapper.ADD，onClick 调 this.openAddDialog()。
      //   openAddDialog 保留（TodoList 空态"添加待办"按钮经 onAdd 回调仍调用）。
    }
    .width('100%')
    .height('100%')
  }
}
