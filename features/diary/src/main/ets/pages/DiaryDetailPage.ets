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
      // 顶部导航栏（返回 · 编辑）—— 无标题栏，标题由卡内 eyebrow 承担
      // ═══════════════════════════════════════════
      Row() {
        Button() {
          SymbolGlyph(IconMapper.ARROW_BACK)
            .fontSize(ICON.navBack)
            .fontWeight(FontWeight.Bold) // HUI-041：系统裸箭头加粗
            .fontColor([this.tokens ? this.tokens.textPrimary : '#1A1A1A'])
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor(Color.Transparent) // HUI-041：去圆形填充底，保留 44vp 透明热区
        .onClick(() => router.back())
        .accessibilityText('返回')
        .accessibilityLevel('yes')

        Blank()

        Button() {
          // fix: HUI-041 — 原 IconMapper.EDIT(plus_circle_fill) 实心圆底 → 统一空心描边圆圈 + 粗加号
          Stack() {
            SymbolGlyph(IconMapper.PLUS)
              .fontSize(ICON.plus)
              .fontWeight(FontWeight.Bold)
              .fontColor([this.tokens ? this.tokens.primary : '#00C2B8'])
          }
          .width(ICON.plusRing)
          .height(ICON.plusRing)
          .borderRadius(ICON.plusRing / 2)
          .border({
            width: ICON.ringStroke,
            color: this.tokens ? this.tokens.primary : '#00C2B8'
          })
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor(Color.Transparent)
        .onClick(() => {
          // 跳转编辑页
          if (this.diary) {
            router.pushUrl({
              url: 'pages/DiaryEditPage',
              params: {
                date: this.diary.date,
                content: this.diary.content
              }
            }).catch(() => {
              promptAction.showToast({
                message: 'Mock: 编辑页跳转',
                duration: 1500
              });
            });
          }
        })
        .accessibilityText('编辑日记')
        .accessibilityLevel('yes')
      }
      .width('100%')
      .padding({ left: SPACING.pageH, right: SPACING.pageH, top: SPACING.pageTop, bottom: SPACING.cardPadSm })

      if (this.diary) {
        Scroll() {
          Column() {
            // ═══════════════════════════════════════════
            // 主卡：eyebrow + 日期(mono) + mood 大图标 + 正文
            // ═══════════════════════════════════════════
            Column() {
              // eyebrow「DIARY DETAIL」
              Row() {
                SymbolGlyph(IconMapper.NAV_DIARY)
                  .fontSize(13)
                  .fontColor([this.tokens ? this.tokens.primary : '#00C2B8'])
                Text('DIARY DETAIL')
                  .fontSize(TYPO.eyebrow.size)
                  .fontWeight(TYPO.eyebrow.weight)
                  .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
                  .letterSpacing(2)
                  .opacity(0.7)
                  .margin({ left: 6 })
                  .attributeModifier(SKETCH_TITLE) // HUI-027：eyebrow 微标→猫啃什锦黑
              }
              .width('100%')

              // 日期(mono 数字) + mood 大图标
              Row() {
                Column() {
                  // 大号 mono 日 + 年月 eyebrow
                  Row() {
                    Text(this.datePart(2))
                      .fontFamily(FONT.monoExtraBold)
                      .fontSize(TYPO.numHero.size)
                      .fontWeight(TYPO.numHero.weight)
                      .fontColor(this.tokens ? this.tokens.primary : '#00C2B8')
                    Column() {
                      Row() {
                        Text(this.datePart(0))
                          .fontFamily(FONT.monoBold)
                          .fontSize(TYPO.body.size)
                          .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
                        Text('年')
                          .fontSize(TYPO.eyebrow.size)
                          .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
                        Text(this.datePart(1))
                          .fontFamily(FONT.monoBold)
                          .fontSize(TYPO.body.size)
                          .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
                          .margin({ left: 2 })
                        Text('月')
                          .fontSize(TYPO.eyebrow.size)
                          .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
                      }
                      Text(DateUtils.getWeekdayName(this.diary!.date))
                        .fontSize(TYPO.eyebrow.size)
                        .fontColor(this.tokens ? this.tokens.textTertiary : '#CCCCCC')
                        .margin({ top: 2 })
                        .attributeModifier(SKETCH_BODY) // HUI-027：星期标签(纯中文)→清松手写体2；左侧日期数字保留 mono
                    }
                    .alignItems(HorizontalAlign.Start)
                    .margin({ left: 10 })
                  }
                  .alignItems(VerticalAlign.Center)
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)

                // mood 大图标（Lottie 动画 + 青浅底 RADIUS.input）
                Column() {
                  LottieAnimation({
                    animPath: this.moodAnimPathFor(this.diary!.mood),
                    loop: true,
                    autoPlay: true,
                    animWidth: 48,
                    animHeight: 48,
                    shouldPlay: true,
                    accessibilityLabel: this.moodLabelFor(this.diary!.mood)
                  })
                    .width(48)
                    .height(48)
                  Text(this.moodLabelFor(this.diary!.mood))
                    .fontSize(TYPO.eyebrow.size)
                    .fontWeight(TYPO.cardTitle.weight)
                    .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
                    .margin({ top: 4 })
                    .attributeModifier(SKETCH_BODY) // HUI-027：心情中文标签→清松手写体2
                }
                .width(76)
                .height(76)
                .justifyContent(FlexAlign.Center)
                .alignItems(HorizontalAlign.Center)
                .borderRadius(RADIUS.input)
                .backgroundColor(this.tokens ? this.tokens.accent : '#E6F9F8')
              }
              .width('100%')
              .margin({ top: SPACING.cardPadSm })
              .alignItems(VerticalAlign.Center)

              // 打卡状态青药丸（可选）
              if (this.diary!.isCheckedIn) {
                Row() {
                  SymbolGlyph(IconMapper.CHECKIN_DONE)
                    .fontSize(14)
                    .fontColor([this.tokens ? this.tokens.primary : '#00C2B8'])
                  Text('当日已打卡')
                    .fontSize(TYPO.eyebrow.size)
                    .fontWeight(TYPO.cardTitle.weight)
                    .fontColor(this.tokens ? this.tokens.primary : '#00C2B8')
                    .margin({ left: 6 })
                    .attributeModifier(SKETCH_BODY) // HUI-027：打卡状态中文标签→清松手写体2
                }
                .padding({ left: 12, right: 12, top: 6, bottom: 6 })
                .borderRadius(999)
                .backgroundColor(this.tokens ? this.tokens.accent : '#E6F9F8')
                .margin({ top: SPACING.cardPadSm })
              }

              // 青段分隔线
              Divider()
                .strokeWidth(1)
                .color(this.tokens ? this.tokens.accent : '#E6F9F8')
                .margin({ top: SPACING.cardPadMd, bottom: SPACING.cardPadMd })

              // 正文（青段间距：leading-relaxed）
              Text(this.diary!.content)
                .fontSize(TYPO.body.size)
                .fontWeight(TYPO.body.weight)
                .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
                .lineHeight(26)
                .width('100%')
                .attributeModifier(SKETCH_BODY) // HUI-027：日记正文(中文)→清松手写体2
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
            .padding(SPACING.cardPadLg)
            .borderRadius(RADIUS.cardLg)
            .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
            .shadow({
              radius: 24,
              color: this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.10)',
              offsetX: 0,
              offsetY: 8
            })

            // ═══════════════════════════════════════════
            // 图片区
            // ═══════════════════════════════════════════
            if (this.diary!.images.length > 0) {
              Column() {
                Row() {
                  SymbolGlyph(IconMapper.CAMERA)
                    .fontSize(15)
                    .fontColor([this.tokens ? this.tokens.textSecondary : '#5A5A5A'])
                  Text('图片附件')
                    .fontSize(TYPO.cardTitle.size)
                    .fontWeight(TYPO.cardTitle.weight)
                    .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
                    .margin({ left: 8 })
                    .attributeModifier(SKETCH_BODY) // HUI-027：区块中文标题→清松手写体2
                }
                .width('100%')
                .margin({ bottom: SPACING.cardPadSm })

                Row() {
                  ForEach(this.diary!.images, (img: string, idx: number) => {
                    Column() {
                      // fix: MAIN-001 · 真实图片渲染（沙箱 file:// 路径），sys.symbol/mock 兜底
                      if (img.startsWith('file://') || img.startsWith('/') || img.startsWith('datashare://') || img.startsWith('photo')) {
                        Image(img)
                          .width('100%')
                          .height('100%')
                          .borderRadius(RADIUS.item)
                          .objectFit(ImageFit.Cover)
                      } else {
                        SymbolGlyph(this.imageIconFor(img))
                          .fontSize(32)
                          .fontColor([this.tokens ? this.tokens.primary : '#00C2B8'])
                      }
                    }
                    .width('30%')
                    .aspectRatio(1)
                    .borderRadius(RADIUS.item)
                    .backgroundColor(this.tokens ? this.tokens.accent : '#E6F9F8')
                    .justifyContent(FlexAlign.Center)
                    .alignItems(HorizontalAlign.Center)
                    .margin({ right: 8 })
                    .onClick(() => {
                      this.previewImageIndex = idx;
                    })
                    .accessibilityText('日记图片' + (idx + 1).toString())
                    .accessibilityLevel('yes')
                  })
                }
                .width('100%')
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(SPACING.cardPadMd)
              .borderRadius(RADIUS.cardMd)
              .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
              .margin({ top: SPACING.cardGap })
              .shadow({
                radius: 24,
                color: this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.10)',
                offsetX: 0,
                offsetY: 8
              })
            }

            // ═══════════════════════════════════════════
            // 内联待办列表
            // ═══════════════════════════════════════════
            if (this.diary!.todos.length > 0) {
              Column() {
                Row() {
                  SymbolGlyph(IconMapper.TAB_TODO)
                    .fontSize(15)
                    .fontColor([this.tokens ? this.tokens.textSecondary : '#5A5A5A'])
                  Text('当日待办')
                    .fontSize(TYPO.cardTitle.size)
                    .fontWeight(TYPO.cardTitle.weight)
                    .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
                    .margin({ left: 8 })
                    .attributeModifier(SKETCH_BODY) // HUI-027：区块中文标题→清松手写体2
                  Blank()
                  Text(this.todoCountLabel())
                    .fontFamily(FONT.monoBold)
                    .fontSize(TYPO.eyebrow.size)
                    .fontColor(this.tokens ? this.tokens.primary : '#00C2B8')
                }
                .width('100%')
                .margin({ bottom: SPACING.cardPadSm })

                ForEach(this.diary!.todos, (todo: DiaryTodo) => {
                  Row() {
                    SymbolGlyph(todo.completed ? IconMapper.CHECKIN_DONE : $r('sys.symbol.circle'))
                      .fontSize(18)
                      .fontColor([todo.completed
                        ? (this.tokens ? this.tokens.primary : '#00C2B8')
                        : (this.tokens ? this.tokens.textTertiary : '#CCCCCC')])
                    Text(todo.title)
                      .fontSize(TYPO.body.size)
                      .fontColor(todo.completed
                        ? (this.tokens ? this.tokens.textTertiary : '#CCCCCC')
                        : (this.tokens ? this.tokens.textPrimary : '#1A1A1A'))
                      .margin({ left: 10 })
                      .layoutWeight(1)
                      .decoration(todo.completed
                        ? { type: TextDecorationType.LineThrough, color: this.tokens ? this.tokens.textTertiary : '#CCCCCC' }
                        : { type: TextDecorationType.None })
                      .attributeModifier(SKETCH_BODY) // HUI-027：待办标题(中文正文)→清松手写体2
                  }
                  .width('100%')
                  .padding({ top: 8, bottom: 8 })
                })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(SPACING.cardPadMd)
              .borderRadius(RADIUS.cardMd)
              .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
              .margin({ top: SPACING.cardGap })
              .shadow({
                radius: 24,
                color: this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.10)',
                offsetX: 0,
                offsetY: 8
              })
            }

            // ═══════════════════════════════════════════
            // 内联开心事列表（SymbolGlyph 图标，0 emoji）
            // ═══════════════════════════════════════════
            if (this.diary!.happyThings.length > 0) {
              Column() {
                Row() {
                  SymbolGlyph(IconMapper.MOOD_HEART)
                    .fontSize(15)
                    .fontColor([MOOD_COLOR_HEART])
                  Text('开心的事')
                    .fontSize(TYPO.cardTitle.size)
                    .fontWeight(TYPO.cardTitle.weight)
                    .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
                    .margin({ left: 8 })
                    .attributeModifier(SKETCH_BODY) // HUI-027：区块中文标题→清松手写体2
                  Blank()
                  Text(this.happyCountLabel())
                    .fontFamily(FONT.monoBold)
                    .fontSize(TYPO.eyebrow.size)
                    .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
                }
                .width('100%')
                .margin({ bottom: SPACING.cardPadSm })

                ForEach(this.diary!.happyThings, (h: DiaryHappyThing) => {
                  Row() {
                    Column() {
                      SymbolGlyph(this.happyIconFor(h.iconKey))
                        .fontSize(18)
                        .fontColor([this.happyColorFor(h.iconKey)])
                    }
                    .width(36)
                    .height(36)
                    .borderRadius(RADIUS.input)
                    .backgroundColor(this.tokens ? this.tokens.accent : '#E6F9F8')
                    .justifyContent(FlexAlign.Center)
                    .alignItems(HorizontalAlign.Center)
                    Text(h.content)
                      .fontSize(TYPO.body.size)
                      .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
                      .margin({ left: 10 })
                      .layoutWeight(1)
                      .attributeModifier(SKETCH_BODY) // HUI-027：开心事内容(中文正文)→清松手写体2
                  }
                  .width('100%')
                  .padding({ top: 8, bottom: 8 })
                  .alignItems(VerticalAlign.Center)
                })
              }
              .width('100%')
              .alignItems(HorizontalAlign.Start)
              .padding(SPACING.cardPadMd)
              .borderRadius(RADIUS.cardMd)
              .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
              .margin({ top: SPACING.cardGap })
              .shadow({
                radius: 24,
                color: this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.10)',
                offsetX: 0,
                offsetY: 8
              })
            }

            // 底部留白（避让悬浮 Tab）
            Column()
              .height(SPACING.pageBottom)
              .width('100%')
          }
          .width('100%')
          .padding({ left: SPACING.pageH, right: SPACING.pageH })
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      } else {
        // 空态
        Column() {
          SymbolGlyph(IconMapper.EMPTY)
            .fontSize(48)
            .fontColor([this.tokens ? this.tokens.textTertiary : '#CCCCCC'])
          Text('暂无日记数据')
            .fontSize(TYPO.body.size)
            .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
            .margin({ top: SPACING.cardPadSm })
            .attributeModifier(SKETCH_BODY) // HUI-027：空态中文提示→清松手写体2
          Button('去写日记')
            .fontSize(TYPO.cardTitle.size)
            .fontWeight(TYPO.cardTitle.weight)
            .fontColor(this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF') // HUI-035：主按钮文字→btnPrimaryText 白
            .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#738A9C') // HUI-035：去写日记主按钮→雾霾蓝 btnPrimary
            .borderRadius(22)
            .height(44)
            .padding({ left: 24, right: 24 })
            .margin({ top: SPACING.cardPadMd })
            .onClick(() => {
              router.pushUrl({ url: 'pages/DiaryEditPage' }).catch(() => {
                promptAction.showToast({ message: 'Mock: 跳转到写日记', duration: 1500 });
              });
            })
            .accessibilityText('去写日记')
            .accessibilityLevel('yes')
        }
        .width('100%')
        .height('60%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tokens ? this.tokens.bg : '#FAF8F5')
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
