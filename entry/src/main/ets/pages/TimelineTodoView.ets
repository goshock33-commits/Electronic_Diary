// agentID: HUI-076（承接 HUI-054 时光轴待办设计，抽为可嵌入组件）
// agentID: DEV-036（从消息跳转时定位到指定待办）
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
// fix: DEV-036 · 从消息跳转时定位到指定待办：
//   aboutToAppear 读取 AppStorage('todo_detail_id')，如果存在则调用 loadDataAndEdit(id) 先加载数据后打开编辑对话框。

import type { ThemeColorTokens, Result, FamilyMember } from '@ohos/shared';
// HUI-026：引入手绘字体助手（全局黑白手绘换肤）——SKETCH_TITLE=猫啃(H1/eyebrow/kicker)，SKETCH_BODY=清松(标签/正文)；纯数字仍走 FONT.mono*。
// DEV-FAMILY 接线：FamilyManager.getSelf() 取本机成员昵称，供 toData 填 assigneeName（「执行人」chip）。
// DEV-035：待办指派消息发送（FamilyMemberDao 查被指派人 uid，FamilyMessageManager 发送消息）
import { IconMapper, RADIUS, SPACING, TYPO, FONT, TodoItem, EventBus, DateUtils, SKETCH_TITLE, SKETCH_BODY, FrostedDialog, FamilyManager, FamilyMemberDao, FamilyMessageManager } from '@ohos/shared';
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

  /** Tab 切换选项（全部/我创建的/分配给我的） */
  private tabOptions: FilterOption[] = [
    { label: '全部', key: '全部' },
    { label: '我创建的', key: '我创建的' },
    { label: '分配给我的', key: '分配给我的' }
  ];

  /** 分类筛选选项 */
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
    // fix: DEV-036 · 从消息跳转时定位到指定待办
    const todoId = AppStorage.get<string>('todo_detail_id');
    if (todoId !== undefined && todoId.length > 0) {
      hilog.info(0x0000, TAG, 'Navigate to todo: %{public}s', todoId);
      // 读取后清除，避免重复处理
      AppStorage.delete('todo_detail_id');
      // 先加载数据，然后打开编辑对话框
      this.loadDataAndEdit(todoId);
    } else {
      // 异步拉真实今/明待办（不阻塞首帧）
      this.loadData();
    }
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

  /** fix: DEV-036 · 从消息跳转时先加载数据，然后打开编辑对话框 */
  private async loadDataAndEdit(todoId: string): Promise<void> {
    try {
      // 先加载数据
      await this.loadData();
      // 转换 ID 并打开编辑对话框
      const id = parseInt(todoId, 10);
      if (!isNaN(id)) {
        // 延迟 300ms 确保数据已渲染到 UI
        setTimeout(() => {
          this.handleEdit(id);
        }, 300);
      } else {
        hilog.error(0x0000, TAG, 'Invalid todo_detail_id: %{public}s', todoId);
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'loadDataAndEdit failed: %{public}s', JSON.stringify(err));
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

  /** 已完成的待办（从今日+明日中筛选 completed=true 的项） */
  private getCompletedItems(): TodoItemData[] {
    return this.getAllItems().filter((item: TodoItemData) => item.completed);
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

        // DEV-035：如果指派了家人，发送消息
        if (result.assignToMemberId > 0) {
          try {
            const member: FamilyMember | null = await FamilyMemberDao.queryById(result.assignToMemberId);
            if (member && member.uid) {
              const myUid: string | undefined = AppStorage.get<string>('current_user_uid');
              const familyId: string | undefined = AppStorage.get<string>('current_family_id');

              await FamilyMessageManager.getInstance().sendTodoMessage(
                familyId ?? '',
                myUid ?? '',
                member.uid,
                created.id.toString(),
                result.title
              );

              hilog.info(0x0000, TAG, 'Todo assigned to %{public}s', member.nickname ?? 'member');
            }
          } catch (err) {
            hilog.error(0x0000, TAG, 'sendTodoMessage failed: %{public}s', JSON.stringify(err));
            // 不阻塞待办保存，只记录错误
          }
        }
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
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        // ══════════════════════════════════════════
        // 顶部 Tab 切换栏（全部/我创建的/分配给我的）— 固定不滚动
        // ══════════════════════════════════════════
        Row() {
          ForEach(this.tabOptions, (opt: FilterOption) => {
            Text(opt.label)
              .fontSize(TYPO.body.size)
              .fontWeight(this.activeFilter === opt.key ? FontWeight.Bold : FontWeight.Normal)
              .fontColor(this.activeFilter === opt.key ?
                (this.tokens ? this.tokens.btnPrimary : '#0A59F7') :
                (this.tokens ? this.tokens.textSecondary : '#666666'))
              .padding({ left: 12, right: 12, top: 8, bottom: 8 })
              .onClick(() => {
                this.activeFilter = opt.key;
              })
              .accessibilityText(opt.label + (this.activeFilter === opt.key ? '，已选中' : ''))
          })
        }
        .width('100%')
        .padding({ left: SPACING.pageH, right: SPACING.pageH, top: SPACING.pageTop, bottom: 8 })
        .backgroundColor(this.tokens ? this.tokens.bg : '#F5F7FA')

        // ══════════════════════════════════════════
        // 可滚动内容区
        // ══════════════════════════════════════════
        Scroll() {
          Column() {

          // ══════════════════════════════════════════
          // 今日待办分组
          // ══════════════════════════════════════════
          if (this.getFilteredToday().length > 0) {
            Row() {
              Text('今天 ' + DateUtils.today().replace(/-/g, '/').substring(5))
                .fontSize(TYPO.body.size)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.tokens ? this.tokens.btnPrimary : '#0A59F7')
            }
            .width('100%')
            .margin({ bottom: 8 })

            TodoList({
              groupType: 'today',
              groupTitle: '今天',
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
          }

          // ══════════════════════════════════════════
          // 明日待办分组
          // ══════════════════════════════════════════
          if (this.getFilteredTomorrow().length > 0) {
            Row() {
              Text('明天')
                .fontSize(TYPO.body.size)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.tokens ? this.tokens.btnPrimary : '#0A59F7')
            }
            .width('100%')
            .margin({ bottom: 8 })

            TodoList({
              groupType: 'tomorrow',
              groupTitle: '明天',
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

          // ══════════════════════════════════════════
          // 已完成分组
          // ══════════════════════════════════════════
          if (this.getCompletedItems().length > 0) {
            Row() {
              Text('已完成')
                .fontSize(TYPO.body.size)
                .fontWeight(FontWeight.Bold)
                .fontColor(this.tokens ? this.tokens.btnPrimary : '#0A59F7')
            }
            .width('100%')
            .margin({ top: SPACING.cardGap, bottom: 8 })

            TodoList({
              groupType: 'completed',
              groupTitle: '已完成',
              items: this.getCompletedItems(),
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

          // 空态
          if (this.getTotalCount() === 0) {
            Column() {
              Text('暂无待办')
                .fontSize(TYPO.body.size)
                .fontColor(this.tokens ? this.tokens.textTertiary : '#999999')
                .margin({ top: 80 })
            }
            .width('100%')
            .alignItems(HorizontalAlign.Center)
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
        .constraintSize({ minHeight: '100%' })
        .padding({
          left: SPACING.pageH,
          right: SPACING.pageH,
          top: SPACING.cardGap,
          bottom: 80
        })
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
      .backgroundColor(this.tokens ? this.tokens.bg : '#F5F7FA')
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.Spring)
      } // 关闭外层 Column

      // ══════════════════════════════════════════
      // 底部浮动新建按钮
      // ══════════════════════════════════════════
      Row() {
        Button() {
          Row() {
            SymbolGlyph(IconMapper.PLUS)
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor([this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF'])
            Text('新建待办')
              .fontSize(TYPO.body.size)
              .fontWeight(FontWeight.Medium)
              .fontColor(this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
              .margin({ left: 6 })
          }
        }
        .width('100%')
        .height(48)
        .borderRadius(24)
        .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#0A59F7')
        .shadow({
          radius: 12,
          color: this.tokens ? this.tokens.shadow : 'rgba(0,0,0,0.08)',
          offsetX: 0,
          offsetY: 4
        })
        .onClick(() => {
          this.openAddDialog();
        })
        .accessibilityText('新建待办')
      }
      .width('100%')
      .padding({ left: SPACING.pageH, right: SPACING.pageH, bottom: 100 })
    }
    .width('100%')
    .height('100%')
  }
}
