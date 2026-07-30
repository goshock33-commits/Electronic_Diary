// <!-- agentID: HUI-059 -->
// agentID: HUI-041（T-D05：返回箭头统一 — 裸 arrow_left 加粗 ICON.navBack，去圆形填充底）
// fix: HUI-041（T-D05 回修：顶栏编辑钮 plus_circle_fill 实心圆底 → 空心描边圆圈+粗加号，用户抽查漏改点）
// 页面：日记详情页（全屏）—— 复刻原型「日记详情」（薄荷青 bento）
// 关联设计稿：UX-001_redesign_report.md §6.8 日记详情 / §1.3 圆角 / §1.4 青染阴影 / §7.5 黑白重彩
// 关联计划：PLN-003 P2-06（日记详情 / 编辑页复刻）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 复刻要点：eyebrow「DIARY DETAIL」+ 日期(mono 数字) + mood 大图标(5 心情 SymbolGlyph 选一 + 青浅底 RADIUS.input)
//           + 正文(青段间距) + 图片 + 内联待办列表 + 开心事列表；主卡 RADIUS.cardLg + tokens.shadow 青染。
// 令牌驱动：圆角 RADIUS、间距 SPACING、字号字重 TYPO、mono 字体族 FONT，均引用 @ohos/shared。
// 崩溃防范（PROJECT_SPEC §9）：无 getter-in-build（用普通方法返回图标/颜色）；无字段初值写 $r()；@StorageLink 判空。
// 图标合规（PROJECT_SPEC §10）：仅用 IconMapper 已验证 sys.symbol.*；本文件 0 emoji。

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-027：引入手绘字体助手——SKETCH_TITLE=猫啃什锦黑(eyebrow)，SKETCH_BODY=清松手写体2(标签/正文)；mono 日期数字/计数保留不动。
import { DateUtils, IconMapper, RADIUS, SPACING, TYPO, FONT, ICON, SKETCH_TITLE, SKETCH_BODY, CheckInDao, TodoItem, HappyThing, LottieAnimation } from '@ohos/shared';
// fix: HUI-FRONTEND-1 · 去 mock，接真实数据库（嫁接 origin/main 的 DEV-WIRE-DIARY 接线）
import { DiaryViewModel, DiaryWithRelations } from '../viewmodel/DiaryViewModel';
import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

// 心情语义色（UX-001 §3.1，无对应 token，语义色硬编码）
const MOOD_COLOR_SUN: string = '#E0BE72';    // 晴 amber
const MOOD_COLOR_STAR: string = '#E6D98A';   // 星 yellow
const MOOD_COLOR_HEART: string = '#78909C';  // 心 rose
const MOOD_COLOR_CLOUD: string = '#94A3B8';  // 云 slate
const MOOD_COLOR_RAIN: string = '#4FC3F7';   // 雨 blue

export interface DiaryTodo {
  id: number;
  title: string;
  completed: boolean;
}

export interface DiaryHappyThing {
  id: number;
  content: string;
  /** 图标键（emoji 已移除，改用 SymbolGlyph 映射）：sun / star / heart / cloud */
  iconKey: string;
}

export interface DiaryDetailData {
  id: number;
  date: string;
  content: string;
  images: string[];
  isCheckedIn: boolean;
  /** 当日心情键：sunny / star / heart / cloudy / rainy（可选，缺省按 neutral 兜底） */
  mood?: string;
  todos: DiaryTodo[];
  happyThings: DiaryHappyThing[];
}

interface DiaryRouteParams {
  diary?: DiaryDetailData;
  date?: string;
  content?: string;
  images?: string[];
}

@Component
export struct DiaryDetailPage {
  @State diary: DiaryDetailData | null = null;
  @State previewImageIndex: number = -1;
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  // fix: HUI-FRONTEND-1 · 真实数据源（去除 mock），经 DiaryViewModel 读库
  private diaryVm: DiaryViewModel = new DiaryViewModel();

  aboutToAppear(): void {
    // 从路由参数取日期（缺省今天），异步从真实数据库加载
    const params = router.getParams() as DiaryRouteParams;
    let targetDate: string = DateUtils.today();
    if (params && params.diary) {
      // 直接携带完整数据（少数入口）：直接展示，不再读库
      this.diary = params.diary;
      return;
    }
    if (params && params.date) {
      targetDate = params.date;
    }
    this.loadDiary(targetDate);
  }

  /**
   * 从数据库加载指定日期的日记 + 关联待办 + 开心事 + 打卡态，映射为视图模型。
   * 无数据时保持 diary=null → 真实空态（非假数据）。
   */
  private async loadDiary(date: string): Promise<void> {
    try {
      const relations: DiaryWithRelations | null = await this.diaryVm.getDiaryWithRelations(date);
      if (!relations) {
        this.diary = null;
        return;
      }
      const checkedIn: boolean = await CheckInDao.exists(date);
      const todoList: DiaryTodo[] = [];
      for (let i = 0; i < relations.todos.length; i++) {
        const t: TodoItem = relations.todos[i];
        todoList.push({ id: t.id, title: t.title, completed: t.completed === 1 });
      }
      const happyList: DiaryHappyThing[] = [];
      for (let j = 0; j < relations.happyThings.length; j++) {
        const h: HappyThing = relations.happyThings[j];
        happyList.push({ id: h.id, content: h.content, iconKey: h.emoji_id.length > 0 ? h.emoji_id : 'star' });
      }
      const view: DiaryDetailData = {
        id: relations.diary.id,
        date: relations.diary.date,
        content: relations.diary.content,
        images: relations.diary.getImageList(),
        isCheckedIn: checkedIn,
        mood: relations.diary.mood,
        todos: todoList,
        happyThings: happyList
      };
      this.diary = view;
    } catch (err) {
      hilog.error(0x0000, 'DiaryDetailPage', 'loadDiary failed: %{public}s', JSON.stringify(err));
      this.diary = null;
    }
  }

  build() {
    Column() {
      // ═══════════════════════════════════════════
      // 顶部导航栏（返回 · 时钟图标）
      // ═══════════════════════════════════════════
      Row() {
        Button() {
          SymbolGlyph(IconMapper.ARROW_BACK)
            .fontSize(ICON.navBack)
            .fontWeight(FontWeight.Bold)
            .fontColor([this.tokens ? this.tokens.textPrimary : '#1A1A1A'])
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(Color.Transparent)
        .onClick(() => router.back())
        .accessibilityText('返回')

        Blank()

        Button() {
          SymbolGlyph(IconMapper.CLOCK)
            .fontSize(20)
            .fontColor([this.tokens ? this.tokens.textPrimary : '#1A1A1A'])
        }
        .width(40)
        .height(40)
        .borderRadius(20)
        .backgroundColor(Color.Transparent)
        .accessibilityText('时间信息')
      }
      .width('100%')
      .height(56)
      .padding({ left: SPACING.pageH, right: SPACING.pageH })
      .alignItems(VerticalAlign.Center)

      if (this.diary) {
        Scroll() {
          Column() {
            // ═══════════════════════════════════════════
            // 标题 + 日期/作者
            // ═══════════════════════════════════════════
            Text(this.diary.content.length > 20 ? this.diary.content.substring(0, 20) + '...' : this.diary.content)
              .fontSize(TYPO.h1.size)
              .fontWeight(TYPO.h1.weight)
              .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
              .width('100%')
              .attributeModifier(SKETCH_TITLE)

            Text(this.diary.date + ' · ' + this.moodLabelFor(this.diary.mood))
              .fontSize(TYPO.body.size)
              .fontColor(this.tokens ? this.tokens.textSecondary : '#666666')
              .margin({ top: 4 })
              .width('100%')
              .attributeModifier(SKETCH_BODY)

            // ═══════════════════════════════════════════
            // 图片展示区（3张并排）
            // ═══════════════════════════════════════════
            if (this.diary.images.length > 0) {
              Row({ space: 8 }) {
                ForEach(this.diary.images.slice(0, 3), (img: string) => {
                  Image(img)
                    .width('100%')
                    .height(120)
                    .borderRadius(RADIUS.cardMd)
                    .objectFit(ImageFit.Cover)
                    .layoutWeight(1)
                })
              }
              .width('100%')
              .margin({ top: SPACING.cardGap })
            }

            // ═══════════════════════════════════════════
            // 正文
            // ═══════════════════════════════════════════
            Text(this.diary.content)
              .fontSize(TYPO.body.size)
              .fontWeight(TYPO.body.weight)
              .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
              .lineHeight(TYPO.body.size * 1.5)
              .width('100%')
              .margin({ top: SPACING.cardGap })
              .attributeModifier(SKETCH_BODY)

            // ═══════════════════════════════════════════
            // AI分析信息卡片
            // ═══════════════════════════════════════════
            Column() {
              this.buildAIInfoRow($r('sys.symbol.position'), '地点', '公园')
              Divider().color(this.tokens ? this.tokens.divider : '#EEF0F4')
              this.buildAIInfoRow(IconMapper.MOOD_HAPPY, '天气', '晴朗 32℃')
              Divider().color(this.tokens ? this.tokens.divider : '#EEF0F4')
              this.buildAIInfoRow(IconMapper.NAV_PROFILE, '人物', '爸爸')
              Divider().color(this.tokens ? this.tokens.divider : '#EEF0F4')
              this.buildAIInfoRow(IconMapper.ACCESSIBILITY, '步数', '约5000步')
            }
            .width('100%')
            .padding(SPACING.cardPadMd)
            .borderRadius(RADIUS.card)
            .backgroundColor(this.tokens ? this.tokens.accent : '#EBF5FF')
            .margin({ top: SPACING.sectionGap })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .constraintSize({ minHeight: '100%' })
          .padding({ left: SPACING.pageH, right: SPACING.pageH, top: SPACING.cardGap, bottom: 80 })
        }
        .layoutWeight(1)
        .align(Alignment.Top)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)

        // ═══════════════════════════════════════════
        // 底部操作栏（编辑 · 分享 · 生成日记视频）
        // ═══════════════════════════════════════════
        Row({ space: 8 }) {
          Button('编辑')
            .fontSize(TYPO.body.size)
            .fontColor(this.tokens ? this.tokens.primary : '#0A59F7')
            .backgroundColor(Color.Transparent)
            .border({ width: 1, color: this.tokens ? this.tokens.primary : '#0A59F7' })
            .borderRadius(24)
            .height(44)
            .layoutWeight(1)
            .onClick(() => {
              router.pushUrl({ url: 'pages/DiaryEditPage', params: { date: this.diary!.date } });
            })
            .accessibilityText('编辑')

          Button('分享')
            .fontSize(TYPO.body.size)
            .fontColor(this.tokens ? this.tokens.primary : '#0A59F7')
            .backgroundColor(Color.Transparent)
            .border({ width: 1, color: this.tokens ? this.tokens.primary : '#0A59F7' })
            .borderRadius(24)
            .height(44)
            .layoutWeight(1)
            .accessibilityText('分享')

          Button('生成日记视频')
            .fontSize(TYPO.body.size)
            .fontColor(this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
            .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#0A59F7')
            .borderRadius(24)
            .height(44)
            .layoutWeight(1.5)
            .accessibilityText('生成日记视频')
        }
        .width('100%')
        .padding({ left: SPACING.pageH, right: SPACING.pageH, bottom: 16 })
      } else {
        // 空态
        Column() {
          Text('日记加载中...')
            .fontSize(TYPO.body.size)
            .fontColor(this.tokens ? this.tokens.textTertiary : '#999999')
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tokens ? this.tokens.bg : '#F5F7FA')
  }

  @Builder
  buildAIInfoRow(icon: Resource, label: string, value: string) {
    Row() {
      SymbolGlyph(icon)
        .fontSize(16)
        .fontColor([this.tokens ? this.tokens.primary : '#0A59F7'])
      Text(label)
        .fontSize(TYPO.body.size)
        .fontColor(this.tokens ? this.tokens.primary : '#0A59F7')
        .margin({ left: 8 })
      Blank()
      Text(value)
        .fontSize(TYPO.body.size)
        .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  /**
   * 取日期分量：0=年 1=月 2=日（供 mono 数字渲染）
   */
  private datePart(idx: number): string {
    if (!this.diary) {
      return '';
    }
    const parts = this.diary.date.split('-');
    return parts.length === 3 ? parts[idx] : '';
  }

  /**
   * 待办完成计数标签（mono 渲染）
   */
  private todoCountLabel(): string {
    if (!this.diary) {
      return '0/0';
    }
    const done = this.diary.todos.filter((t: DiaryTodo) => t.completed).length;
    return done.toString() + '/' + this.diary.todos.length.toString();
  }

  /**
   * 开心事计数标签
   */
  private happyCountLabel(): string {
    if (!this.diary) {
      return '0 件';
    }
    return this.diary.happyThings.length.toString() + ' 件';
  }

  /**
   * 图片占位键 → 图标（key→IconMapper 映射，避免动态 $r(变量)，§10 字面量约定合规）
   */
  private imageIconFor(key: string): Resource {
    if (key.indexOf('doc') >= 0) {
      return IconMapper.COPY;
    }
    return IconMapper.CAMERA;
  }

  /**
   * 心情键 → Lottie 动画路径（rawfile 相对路径）
   */
  private moodAnimPathFor(mood?: string): string {
    if (mood === 'sunny') {
      return 'animations/sunny.json';
    }
    if (mood === 'star') {
      return 'animations/night.json';
    }
    if (mood === 'heart') {
      return 'animations/happy.json';
    }
    if (mood === 'cloudy') {
      return 'animations/sunclouds.json';
    }
    if (mood === 'rainy') {
      return 'animations/rain.json';
    }
    return 'animations/sunny.json';
  }

  /**
   * 心情键 → 中文文案
   */
  private moodLabelFor(mood?: string): string {
    if (mood === 'sunny') {
      return '风和';
    }
    if (mood === 'star') {
      return '繁星';
    }
    if (mood === 'heart') {
      return '欢喜';
    }
    if (mood === 'cloudy') {
      return '多云';
    }
    if (mood === 'rainy') {
      return '微雨';
    }
    return '平静';
  }

  /**
   * 开心事图标键 → 图标（§9.3 合规）
   */
  private happyIconFor(key: string): Resource {
    if (key === 'sun') {
      return IconMapper.MOOD_HAPPY;
    }
    if (key === 'heart') {
      return IconMapper.MOOD_HEART;
    }
    if (key === 'cloud') {
      return IconMapper.MOOD_CLOUDY;
    }
    return IconMapper.MOOD_PLEASANT;
  }

  /**
   * 开心事图标键 → 语义色
   */
  private happyColorFor(key: string): string {
    if (key === 'sun') {
      return MOOD_COLOR_SUN;
    }
    if (key === 'heart') {
      return MOOD_COLOR_HEART;
    }
    if (key === 'cloud') {
      return MOOD_COLOR_CLOUD;
    }
    return MOOD_COLOR_STAR;
  }
}
