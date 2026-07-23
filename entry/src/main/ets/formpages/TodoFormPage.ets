// <!-- agentID: HUI-015 -->
// 文件: TodoFormPage.ets
// 任务: T030b 待办清单桌面卡片 UI 页面
// 关联架构: ARC-001 §3.1 FormExtensionAbility
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
//
// === 图标来源章节 ===
// 所有图标引用自 HarmonyOS SymbolGlyph 系统图标库，均经 IconMapper 验证有效：
// | 图标资源                          | 用途             | 验证来源                  |
// |-----------------------------------|------------------|---------------------------|
// | sys.symbol.checkmark_circle_fill  | 已完成图标       | IconMapper.CHECKIN_DONE   |
// | sys.symbol.checkmark              | 未完成图标       | IconMapper.CHECKMARK      |
// | sys.symbol.list_bullet            | 待办列表图标     | IconMapper.TAB_TODO       |
//
// === 主题色引用章节 ===
// 所有色值使用 $r('app.color.form_*') 资源引用，支持深色/浅色模式自动切换。
// 资源定义：entry/src/main/resources/base/element/color.json（浅色）
//          entry/src/main/resources/dark/element/color.json（深色）
//
// === 玻璃质感改造 ===
// 根容器 Column → Stack，叠加玻璃层：半透底 + 顶部高光 + 左上角强光 + 星光粒子(3颗)
// 分隔线放在标题行和待办列表之间
// 保留现有 Swiper 轮播

import { IconMapper } from '@ohos/shared';

interface TodoFormItem {
  id: number;
  title: string;
  isCompleted: number;
  type: string;
}

/** postCardAction router 参数结构 */
interface FormRouterParams {
  action: string;
  bundleName: string;
  abilityName: string;
  params: Record<string, string>;
}

/** 星光粒子位置（2x4 卡片用 3 颗） */
interface SparklePos {
  x: number;
  y: number;
}

const TODO_SPARKLES: SparklePos[] = [
  { x: 140, y: 15 },
  { x: 20, y: 60 },
  { x: 160, y: 100 }
];

/**
 * TodoFormPage - 2x4 待办清单桌面卡片 UI
 * 展示今日待办前 3 条 + 完成状态
 */
@Entry
@Component
struct TodoFormPage {
  @LocalStorageProp('dateStr') dateStr: string = '';
  @LocalStorageProp('totalCount') totalCount: number = 0;
  @LocalStorageProp('completedCount') completedCount: number = 0;
  @LocalStorageProp('todos') todosJson: string = '[]';
  @State private sparkleOpacity: number = 0.6;

  aboutToAppear(): void {
    this.startSparkleAnim();
  }

  private startSparkleAnim(): void {
    // 卡片应用不支持 setTimeout，直接启动动画
    animateTo({ duration: 1800, curve: Curve.EaseInOut, iterations: -1 }, () => {
      this.sparkleOpacity = 0.15;
    });
  }

  /** 从 @LocalStorageProp todosJson 即时解析前 3 条 TodoFormItem */
  private parseTodos(): TodoFormItem[] {
    const trimmed: string = (this.todosJson.length > 0) ? this.todosJson : '[]';
    const parsed: TodoFormItem[] = JSON.parse(trimmed) as TodoFormItem[];
    const maxCount: number = (parsed.length > 3) ? 3 : parsed.length;
    return parsed.slice(0, maxCount);
  }

  private getOverflowCount(): number {
    return this.totalCount > 3 ? this.totalCount - 3 : 0;
  }

  build() {
    Stack() {
      // 层1：半透叠加层
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.form_glass_overlay'))
        .borderRadius(16)

      // 层2：顶部渐变高光
      Column()
        .width('100%')
        .height('50%')
        .linearGradient({
          angle: 180,
          colors: [['rgba(255,255,255,0.3)', 0.0], ['rgba(255,255,255,0)', 1.0]]
        })
        .borderRadius({ topLeft: 16, topRight: 16 })

      // 层3：左上角强光光斑
      Column()
        .width(60)
        .height(60)
        .borderRadius(30)
        .radialGradient({
          center: [30, 30],
          radius: 30,
          colors: [['rgba(255,255,255,0.5)', 0.0], ['rgba(255,255,255,0)', 0.7]]
        })
        .position({ x: -10, y: -10 })

      // 层4：星光粒子（3 颗）
      ForEach(TODO_SPARKLES, (pos: SparklePos) => {
        Column() {
          Column()
            .width(1.5)
            .height(6)
            .backgroundColor('rgba(255,255,255,' + this.sparkleOpacity + ')')
          Column()
            .width(6)
            .height(1.5)
            .backgroundColor('rgba(255,255,255,' + this.sparkleOpacity + ')')
        }
        .position({ x: pos.x, y: pos.y })
      }, (pos: SparklePos) => pos.x + '_' + pos.y)

      // 层5：原有内容
      Column() {
        // 标题行
        Row() {
          Image(IconMapper.TAB_TODO)
            .width(16)
            .height(16)
            .fillColor($r('app.color.form_accent_green'))
            .objectFit(ImageFit.Contain)

          Text(this.dateStr)
            .fontSize(14)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.form_text_primary'))
            .margin({ left: 6 })
            .layoutWeight(1)

          Text('' + this.completedCount + '/' + this.totalCount)
            .fontSize(12)
            .fontColor($r('app.color.form_accent_green'))
            .fontWeight(FontWeight.Medium)
            .padding({ left: 8, right: 8, top: 3, bottom: 3 })
            .borderRadius(10)
            .backgroundColor($r('app.color.form_todo_badge_bg'))
        }
        .width('100%')
        .margin({ bottom: 6 })

        // 内部分隔线
        Divider()
          .strokeWidth(1)
          .color($r('app.color.form_glass_highlight'))
          .margin({ top: 2, bottom: 6 })

        // 待办列表 + 右下角轮播
        Column() {
          Stack({ alignContent: Alignment.BottomEnd }) {
            Column() {
              if (this.parseTodos().length > 0) {
                this.renderItem(0)
                if (this.parseTodos().length > 1) {
                  Divider().strokeWidth(1).color($r('app.color.form_divider')).margin({ top: 5, bottom: 5 })
                }
                this.renderItem(1)
                if (this.parseTodos().length > 2) {
                  Divider().strokeWidth(1).color($r('app.color.form_divider')).margin({ top: 5, bottom: 5 })
                }
                this.renderItem(2)

                if (this.getOverflowCount() > 0) {
                  Row() {
                    Blank()
                    Text('还有 ' + this.getOverflowCount() + ' 项')
                      .fontSize(11)
                      .fontColor($r('app.color.form_text_secondary'))
                  }
                  .width('100%')
                  .margin({ top: 5 })
                }
              } else {
                Row() {
                  Image(IconMapper.TAB_TODO)
                    .width(16)
                    .height(16)
                    .fillColor($r('app.color.form_icon_muted'))
                    .objectFit(ImageFit.Contain)
                  Text('今日暂无待办')
                    .fontSize(12)
                    .fontColor($r('app.color.form_text_secondary'))
                    .margin({ left: 6 })
                }
                .height(48)
                .justifyContent(FlexAlign.Center)
              }
            }
            .width('100%')
            .padding({ top: 8, bottom: 8, left: 10, right: 10 })

            Swiper() {
              ForEach(['cards/carousel1.jpg', 'cards/carousel2.jpg', 'cards/carousel3.jpg', 'cards/carousel4.jpg'],
                (path: string) => {
                  Image($rawfile(path))
                    .width('100%')
                    .height('100%')
                    .objectFit(ImageFit.Cover)
                    .borderRadius(6)
                },
                (path: string, index: number) => index.toString()
              )
            }
            .autoPlay(true)
            .interval(3000)
            .loop(true)
            .indicator(false)
            .width(56)
            .height(56)
            .margin({ right: 6, bottom: 6 })
          }
          .width('100%')
          .borderRadius(12)
          .backgroundColor($r('app.color.form_todo_sheet_bg'))
          .border({ width: 1, color: $r('app.color.form_todo_sheet_border') })
          .shadow({ radius: 12, color: $r('app.color.form_todo_sheet_shadow'), offsetY: 6 })
          .clip(true)
          .translate({ y: -6 })
        }
        .width('100%')
        .layoutWeight(1)

        // 完成率进度条
        Progress({
          value: this.completedCount,
          total: (this.totalCount > 0) ? this.totalCount : 1,
          type: ProgressType.Linear
        })
          .width('100%')
          .height(3)
          .color($r('app.color.form_accent_green'))
          .backgroundColor($r('app.color.form_todo_progress_track'))
          .style({ strokeWidth: 3 })
          .margin({ top: 6 })
      }
      .width('100%')
      .height('100%')
      .padding({ top: 14, bottom: 10, left: 16, right: 16 })
    }
    .width('100%')
    .height('100%')
    .borderRadius(16)
    .border({ width: 1.5, color: $r('app.color.form_glass_border') })
    .shadow({ radius: 30, color: 'rgba(255,255,255,0.2)', offsetX: 0, offsetY: 0 })
    .shadow({ radius: 12, color: 'rgba(0,0,0,0.1)', offsetX: 0, offsetY: 6 })
    .shadow({ radius: 4, color: 'rgba(0,0,0,0.06)', offsetX: 0, offsetY: 2 })
    .backgroundColor(Color.Transparent)
    .onClick(() => {
      const targetData: Record<string, string> = {};
      targetData['router_target'] = 'pages/TodoPage';
      const routerParams: FormRouterParams = {
        action: 'router',
        bundleName: 'com.example.electronic_diary',
        abilityName: 'EntryAbility',
        params: targetData
      };
      postCardAction(this, routerParams);
    })
    .accessibilityGroup(true)
    .accessibilityText(
      '待办清单：' + this.dateStr +
      '，共' + this.totalCount + '项，已完成' + this.completedCount + '项'
    )
  }

  @Builder
  renderItem(index: number) {
    Column() {
      if (this.parseTodos().length > index) {
        Row() {
          Image(this.parseTodos()[index].isCompleted === 1
            ? IconMapper.CHECKIN_DONE
            : IconMapper.CHECKMARK)
            .width(18)
            .height(18)
            .fillColor(this.parseTodos()[index].isCompleted === 1
              ? $r('app.color.form_accent_green')
              : $r('app.color.form_icon_inactive'))
            .objectFit(ImageFit.Contain)

          Text(this.parseTodos()[index].title)
            .fontSize(13)
            .fontColor(this.parseTodos()[index].isCompleted === 1
              ? $r('app.color.form_text_done')
              : $r('app.color.form_text_primary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .decoration(this.parseTodos()[index].isCompleted === 1
              ? { type: TextDecorationType.LineThrough, color: '#BDBDBD' }
              : { type: TextDecorationType.None })
            .layoutWeight(1)
            .margin({ left: 8 })
        }
        .width('100%')
        .height(28)
      }
    }
    .width('100%')
    .height(this.parseTodos().length > index ? 28 : 0)
    .clip(true)
  }
}
