// <!-- agentID: HUI-065 -->
// @Entry 任务确认页（P2-11）—— 由 TaskConfirmAbility 加载 / 亦可 bindSheet 复用
// 关联任务：UX-001 §6.7 任务确认弹窗 / PLN-003 P2-11 / PLN-001 T108（接线）
//
// ── 本壳职责 ────────────────────────────────────────────────────
// · 提供 P2-07a 同款模态骨架的「遮罩 + 底部滑入」外层（毛玻璃遮罩 rgba(0,0,0,0.6) + backdropBlur）；
// · 40vp 白卡内容主体由 features_task_extraction 的 TaskConfirmView 自绘；
// · 点击遮罩 / 关闭 / 取消 → 下滑退出后 router.back()。
//
// ── T108 接线（HUI-003 · PLN-001 §4 T108）──────────────────────────
// · 数据源：mock → TaskExtractionViewModel。aboutToAppear 异步 vm.init() 后取 getUnconvertedTasks()。
// · 字段映射（R3 蛇形→驼峰）：ExtractedTask.task_date/task_time/location(可空) → ConfirmTaskItem.taskDate/taskTime/location（?? '' 兜底）。
// · 确认「全部添加」→ 对选中 id 逐个 vm.convertToTodo(id, today, 'today') 落库（VM 内 emit TASK_CONVERTED）。
// · R1：任务列表用 @State 才刷新；@Prop 首帧默认全选依赖列表已就绪，故用 loaded 门控 TaskConfirmView 挂载。
// · R2：跨页刷新订阅 EventBus.EventNames.TASK_EXTRACTED（新任务被提取时重载列表），aboutToDisappear off。
// · 只换数据源，保留原遮罩/滑入/白卡布局与样式；DB 空/查询失败走空态兜底。
//
// ── 令牌驱动（PLN-003 阅读须知1）──────────────────────────────────
// · 圆角/间距/字号字重全在 TaskConfirmView 内走 RADIUS/SPACING/TYPO；本壳仅遮罩与滑入
// · §1.4 三者一致：模块 name = features_task_extraction = 依赖 key = import 路径
//
// ── 崩溃防范（PROJECT_SPEC §9）────────────────────────────────────
// · §9.3 字段初值仅基础类型/空数组，无 $r()；§9.4 无 tokens 依赖（遮罩为固定色）
// · 关闭下滑用 animateTo onFinish 回调（无裸定时器，无需清理）
// · 异步拉数全包 try/catch（PROJECT_SPEC §8.3），失败走空态
//
// 开发范式：ArkTS 声明式开发范式（Stage 模型）

import { TaskConfirmView, type ConfirmTaskItem, TaskExtractionViewModel } from 'features_task_extraction';
import { ExtractedTask, EventBus, DateUtils, reportPawTouch, PawOverlayLayer } from '@ohos/shared';
import { router, promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG: string = 'TaskConfirmPage';

// 滑入起始偏移（卡片自屏幕下方滑入）
const SHEET_Y_HIDDEN: number = 600;

@Entry
@Component
struct TaskConfirmPage {
  // 卡片纵向偏移（初值在屏外下方 → aboutToAppear 动画归零）
  @State private sheetY: number = SHEET_Y_HIDDEN;

  // T108：待确认任务（真实数据源，R1 必须 @State 才触发刷新；初值空数组，无 $r()）
  @State private tasks: ConfirmTaskItem[] = [];
  // 数据是否已从 DB 拉取完成（门控 TaskConfirmView 挂载，保证其 aboutToAppear 默认全选时列表已就绪）
  @State private loaded: boolean = false;

  // TaskExtractionViewModel（默认空构造，init() 后 getter 才有数据）
  private vm: TaskExtractionViewModel = new TaskExtractionViewModel();

  aboutToAppear(): void {
    // 底部滑入（spring 气质）
    animateTo({ duration: 320, curve: Curve.FastOutSlowIn }, () => {
      this.sheetY = 0;
    });
    // 异步拉真实未转待办任务（不阻塞首帧）
    this.loadTasks();
    // R2：新任务被提取（如剪贴板/分享检测）时重载列表
    EventBus.on(EventBus.EventNames.TASK_EXTRACTED, (data: Record<string, Object>) => {
      this.loadTasks();
    });
  }

  aboutToDisappear(): void {
    EventBus.off(EventBus.EventNames.TASK_EXTRACTED);
  }

  /** 拉取未转待办的提取任务并映射为 UI 展示项（空态/异常兜底） */
  private async loadTasks(): Promise<void> {
    // 重载时先卸载列表视图，使 TaskConfirmView 重新 aboutToAppear（重算默认全选）
    this.loaded = false;
    try {
      await this.vm.init();
      this.tasks = this.mapTasks(this.vm.getUnconvertedTasks());
    } catch (err) {
      this.tasks = [];
      hilog.error(0x0000, TAG, 'loadTasks failed: %{public}s', JSON.stringify(err));
    } finally {
      this.loaded = true;
    }
  }

  /** R3 字段映射：ExtractedTask（蛇形/可空）→ ConfirmTaskItem（驼峰/非空） */
  private mapTasks(list: ExtractedTask[]): ConfirmTaskItem[] {
    return list.map((t: ExtractedTask): ConfirmTaskItem => {
      const item: ConfirmTaskItem = {
        id: t.id,
        title: t.title,
        source: t.source,
        category: t.category,
        taskDate: t.task_date ?? '',
        taskTime: t.task_time ?? '',
        location: t.location ?? ''
      };
      return item;
    });
  }

  /** 确认「全部添加」：对选中的提取任务逐个转为今日待办并落库 */
  private async handleConfirm(ids: number[]): Promise<void> {
    if (ids.length === 0) {
      return;
    }
    const today: string = DateUtils.today();
    let successCount: number = 0;
    for (const id of ids) {
      const ok: boolean = await this.vm.convertToTodo(id, today, 'today');
      if (ok) {
        successCount++;
      }
    }
    promptAction.showToast({ message: '已添加 ' + successCount + ' 项待办', duration: 1500 });
  }

  /** 下滑退出后返回 */
  private dismiss(): void {
    animateTo({
      duration: 220,
      curve: Curve.FastOutSlowIn,
      onFinish: () => {
        router.back();
      }
    }, () => {
      this.sheetY = SHEET_Y_HIDDEN;
    });
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      // ── 毛玻璃遮罩（点击关闭）──
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.6)')
        .backdropBlur(12)
        .onClick(() => {
          this.dismiss();
        })

      // ── 40vp 白卡（底部滑入）──
      Column() {
        if (this.loaded) {
          TaskConfirmView({
            tasks: this.tasks,
            onConfirm: (ids: number[]) => {
              this.handleConfirm(ids);
            },
            onCancel: () => {
            },
            onClose: () => {
              this.dismiss();
            }
          })
        }
      }
      .width('100%')
      .translate({ y: this.sheetY })

      // HUI-001: 猫爪视觉层（同树最上层子节点，整层 None 不参与命中，不挡交互）
      // PawOverlayLayer()
    }
    .width('100%')
    .height('100%')
    // HUI-001: 猫爪特效触摸捕获（页面树内监听 Down，不消费；视觉层在本页根 Stack 顶层）
    .onTouch((event: TouchEvent) => reportPawTouch(event))
  }
}
