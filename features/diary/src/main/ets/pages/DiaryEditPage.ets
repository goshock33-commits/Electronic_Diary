// <!-- agentID: HUI-059 -->
// fix: HUI-001 v2（ghost text Stack 叠加内联：v1 下方建议行被软键盘遮挡，推翻重做——
//   底层 Text 镜像正文（Span 黑正文 + Span 浅灰接续，字符级内联续排），上层 TextArea 全透明承接输入，
//   两层同 fontSize/lineHeight/padding 对齐光标；onWillInsert 拦截 Enter 采纳/放行换行，
//   防抖 500ms + DeepSeekClient.chat(max_tokens 30/temperature 0.7)，设置总闸 persist_ai_writing_suggestion；
//   灰阶配色：浅色 #AAA / 深色 #666；API 验证：text_area.d.ts caretColor L613/fontColor L641/lineHeight L1666、span.d.ts fontColor L296）
// agentID: HUI-041（T-D05：添加图片加号统一 — 空心描边圆圈+粗加号）
// fix: HUI-041（T-D05 回修：顶栏关闭/退回钮去燕麦实心圆底 → 裸图标加粗，与全局导航控件统一）
// 页面：全屏日记编辑器 —— 复刻原型「写日记」（薄荷青 bento + 5 心情选择器）
// 关联设计稿：UX-001_redesign_report.md §6.8 日记编辑 / §1.3 圆角 / §3.1 五心情 / §7.5 黑白重彩
// 关联计划：PLN-003 P2-06（日记编辑页 + 5 心情选择器）
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 复刻要点：标题输入(placeholder 灰) + 正文 textarea(青 focus ring #00C2B8/20 + RADIUS.item)
//           + 5 心情选择器(水平 5 圆形 mood 图标；选中白底 + scale1.05 + 青字 + 青浅底 RADIUS.input)
//           +「保存时光」全圆主色按钮(borderRadius 22，主色 #00C2B8)。
// 令牌驱动：圆角 RADIUS、间距 SPACING、字号字重 TYPO，均引用 @ohos/shared。
// 崩溃防范（PROJECT_SPEC §9）：mood 图标 $r() 不写字段初值，aboutToAppear 中赋值（§9.3）；@StorageLink 判空。
// 图标合规（PROJECT_SPEC §10）：仅用 IconMapper 已验证 sys.symbol.*；本文件 0 emoji。

import type { ThemeColorTokens, DSMessage, DSChatResult, DSChatOptions } from '@ohos/shared';
// HUI-027：引入手绘字体助手——SKETCH_TITLE=猫啃什锦黑(eyebrow/标题)，SKETCH_BODY=清松手写体2(标签/正文)；纯数字/日期数字读出仍走 mono。
// HUI-001 ghost text：DeepSeekClient（T103 chat）+ PersistentState（AI 写作建议开关键）
import { DateUtils, IconMapper, RADIUS, SPACING, TYPO, ICON, SKETCH_TITLE, SKETCH_BODY, DeepSeekClient, PersistentState, ImageUtils, LottieAnimation } from '@ohos/shared';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DiaryViewModel } from '../viewmodel/DiaryViewModel';
import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
// fix: MAIN-001 · 图片上传去 mock：系统相册选择器 PhotoViewPicker + 沙箱持久化
import { picker } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';

// 青 focus ring（#00C2B8 @ 20%），UX-001 §6.8 编辑 textarea focus ring
const CYAN_FOCUS_RING: string = 'rgba(0,194,184,0.20)';

// ═══ HUI-001 · ghost text AI 内联补全常量 ═══
/** 建议文字灰阶（任务书钉死：浅色 #AAA / 深色 #666——比正文明显淡但对比度可读；无青色，遵守用户偏好） */
const GHOST_COLOR_LIGHT: string = '#AAAAAA';
const GHOST_COLOR_DARK: string = '#666666';
// fix: DEV-012 · 编译修复：ghost text 日志引用 TAG 但从未声明（Cannot find name 'TAG'）——仅补常量，不动 UI 逻辑
const TAG: string = 'DiaryEditPage';
/** 输入防抖窗口（ms） */
const GHOST_DEBOUNCE_MS: number = 500;
/** 触发建议的最少正文字数 */
const GHOST_MIN_CHARS: number = 3;
/** 叠加两层统一行高（vp）：底层镜像 Text 与上层透明 TextArea 显式同值，保证折行/光标逐行对齐 */
const GHOST_LINE_HEIGHT: number = 22;
/** 正文占位文案（上层 TextArea placeholder 透明化后由底层镜像 Text 自绘，两处共用一份） */
const BODY_PLACEHOLDER: string = '写点什么…记录今天的故事';
/** 续写 system prompt（任务书原文） */
const GHOST_SYSTEM_PROMPT: string =
  '你是日记续写助手。根据用户已写的内容，用汉语预测最可能的接续（5-20字）。只返回接续文字，不要解释、问候、标点格式化。语气自然流畅，与上文风格一致。';
// 心情语义色（UX-001 §3.1）
const MOOD_COLOR_SUN: string = '#E0BE72';    // 晴 amber
const MOOD_COLOR_STAR: string = '#E6D98A';   // 星 yellow
const MOOD_COLOR_HEART: string = '#78909C';  // 心 rose
const MOOD_COLOR_CLOUD: string = '#94A3B8';  // 云 slate
const MOOD_COLOR_RAIN: string = '#4FC3F7';   // 雨 blue

/**
 * 5 心情选择项
 */
interface MoodOption {
  key: string;
  label: string;
  /** rawfile 相对路径，Lottie 动画 JSON 文件 */
  animPath: string;
  color: string;
}

/**
 * 图片附件面板（内联组件）
 */
@Component
export struct ImageAttachmentPanel {
  @Prop images: string[] = [];
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  onAddImage?: () => void;
  onDeleteImage?: (index: number) => void;
  onPreviewImage?: (image: string) => void;

  build() {
    Row() {
      ForEach(this.images, (img: string, idx: number) => {
        Stack() {
          // fix: MAIN-001 · 真实图片路径渲染缩略图（file:///data/...），sys.symbol/mock 兜底
          Column() {
            if (img.startsWith('file://') || img.startsWith('/') || img.startsWith('datashare://') || img.startsWith('photo')) {
              Image(img)
                .width(72).height(72)
                .borderRadius(RADIUS.input)
                .objectFit(ImageFit.Cover)
            } else {
              SymbolGlyph(this.imageIconFor(img))
                .fontSize(32)
                .fontColor([this.tokens ? this.tokens.primary : '#00C2B8'])
            }
          }
          .width(72)
          .height(72)
          .borderRadius(RADIUS.input)
          .backgroundColor(this.tokens ? this.tokens.accent : '#E6F9F8')
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .onClick(() => {
            if (this.onPreviewImage) {
              this.onPreviewImage(img);
            }
          })
          .gesture(
            LongPressGesture({ repeat: false, duration: 400 })
              .onAction(() => {
                if (this.onDeleteImage) {
                  this.onDeleteImage(idx);
                }
              })
          )
          .accessibilityText('图片' + (idx + 1).toString() + '，长按删除')

          // 删除角标
          Button() {
            SymbolGlyph(IconMapper.CLOSE)
              .fontSize(12)
              .fontColor(['#FFFFFF'])
          }
          .width(22)
          .height(22)
          .backgroundColor(this.tokens ? this.tokens.danger : '#78909C')
          .borderRadius(11)
          .position({ right: -8, top: -8 })
          .onClick(() => {
            if (this.onDeleteImage) {
              this.onDeleteImage(idx);
            }
          })
          .accessibilityText('删除图片')
          .accessibilityLevel('yes')
        }
        .margin({ right: 10 })
      }, (img: string, idx: number) => idx.toString())

      // 添加图片按钮
      Column() {
        // HUI-041：空心描边圆圈 + 粗加号（去 plus_circle_fill 实心填充）
        Stack() {
          SymbolGlyph(IconMapper.PLUS)
            .fontSize(ICON.plus)
            .fontWeight(FontWeight.Bold)
            .fontColor([this.tokens ? this.tokens.textTertiary : '#CCCCCC'])
        }
        .width(ICON.plusRing)
        .height(ICON.plusRing)
        .borderRadius(ICON.plusRing / 2)
        .border({
          width: ICON.ringStroke,
          color: this.tokens ? this.tokens.textTertiary : '#CCCCCC'
        })
        Text('添加')
          .fontSize(TYPO.eyebrow.size)
          .fontColor(this.tokens ? this.tokens.textTertiary : '#CCCCCC')
          .margin({ top: 4 })
          .attributeModifier(SKETCH_BODY) // HUI-027：添加图片标签→清松手写体2
      }
      .width(72)
      .height(72)
      .borderRadius(RADIUS.input)
      .border({ width: 2, color: this.tokens ? this.tokens.btnAux : '#C6BBAE', style: BorderStyle.Dashed }) // HUI-035：添加图片描边→燕麦 btnAux
      .backgroundColor(Color.Transparent)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .onClick(() => {
        if (this.onAddImage) {
          this.onAddImage();
        }
      })
      .accessibilityText('添加图片')
      .accessibilityLevel('yes')
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
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
}

/**
 * Mock 待办数据（供关联选择）
 */
interface MockTodo {
  id: number;
  title: string;
  selected: boolean;
}

interface DiaryEditRouteParams {
  date?: string;
  title?: string;
  content?: string;
  images?: string[];
}

@Component
export struct DiaryEditPage {
  /** fix: HUI-FRONTEND-1 · 真实保存 VM（默认空构造，saveDiary 内 init+save） */
  private diaryVm: DiaryViewModel = new DiaryViewModel();
  @State date: string = DateUtils.today();
  @State title: string = '';
  @State content: string = '';
  @State images: string[] = [];
  @State selectedMoodKey: string = 'sunny';
  /** 5 心情选项：图标 $r() 不写字段初值，aboutToAppear 中赋值（§9.3） */
  @State private moodOptions: MoodOption[] = [];
  @State isSaving: boolean = false;
  @State showTodoPicker: boolean = false;
  @State linkedTodos: MockTodo[] = [
    { id: 1, title: '完成ArkTS组件学习笔记', selected: false },
    { id: 2, title: '搭建项目骨架', selected: false },
    { id: 3, title: '了解HarmonyOS权限机制', selected: false },
    { id: 4, title: '完成UI方案设计文档', selected: true },
    { id: 5, title: '确定技术选型', selected: true },
    { id: 6, title: '开展用户访谈', selected: true },
    { id: 7, title: '整理反馈意见', selected: false }
  ];
  @State characterCount: number = 0;
  @State private titleFocused: boolean = false;
  @State private bodyFocused: boolean = false;
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  // ═══ HUI-001 · ghost text 内联补全 ═══
  /** 深浅色标记（建议灰阶二选一：浅色 #AAA / 深色 #666） */
  @StorageLink('theme_is_dark') isDark: boolean = false;
  /** 当前 AI 建议文字（空 = 无建议） */
  @State ghostText: string = '';
  /** 建议请求进行中（loading 态建议行显「…」+ 防重发） */
  @State ghostLoading: boolean = false;
  /** 输入防抖 timer id（-1 = 无挂起） */
  private ghostTimer: number = -1;

  aboutToAppear(): void {
    // 5 心情选项：使用 Lottie 动画替代系统 SymbolGlyph 图标
    this.moodOptions = [
      { key: 'sunny', label: '风和', animPath: 'animations/sunny.json', color: MOOD_COLOR_SUN },
      { key: 'star', label: '繁星', animPath: 'animations/night.json', color: MOOD_COLOR_STAR },
      { key: 'heart', label: '欢喜', animPath: 'animations/happy.json', color: MOOD_COLOR_HEART },
      { key: 'cloudy', label: '多云', animPath: 'animations/sunclouds.json', color: MOOD_COLOR_CLOUD },
      { key: 'rainy', label: '微雨', animPath: 'animations/rain.json', color: MOOD_COLOR_RAIN }
    ];

    const params = router.getParams() as DiaryEditRouteParams;
    if (params) {
      if (params.date) {
        this.date = params.date;
      }
      if (params.title) {
        this.title = params.title;
      }
      if (params.content) {
        this.content = params.content;
        this.characterCount = this.content.length;
      }
      if (params.images) {
        this.images = params.images;
      }
    }
  }

  /** HUI-001 ghost text：离页清防抖 timer，避免退出后仍触发请求 */
  aboutToDisappear(): void {
    if (this.ghostTimer >= 0) {
      clearTimeout(this.ghostTimer);
      this.ghostTimer = -1;
    }
  }

  build() {
    Column() {
      // ═══════════════════════════════════════════
      // 顶部导航栏（关闭 · 日期 mono · 字数）
      // ═══════════════════════════════════════════
      Row() {
        Button() {
          SymbolGlyph(IconMapper.CLOSE)
            .fontSize(ICON.navBack)
            .fontWeight(FontWeight.Bold) // fix: HUI-041 — 顶部退回控件加粗，与全局裸导航图标等大统一
            .fontColor([this.tokens ? this.tokens.textPrimary : '#1A1A1A'])
        }
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor(Color.Transparent) // fix: HUI-041 — 去圆形填充底，保留 44vp 透明热区
        .onClick(() => {
          if (this.content.trim() || this.title.trim() || this.images.length > 0) {
            promptAction.showDialog({
              title: '放弃编辑？',
              message: '当前内容未保存，确定要放弃吗？',
              buttons: [
                { text: '继续编辑', color: this.tokens ? this.tokens.primary : '#00C2B8' },
                { text: '放弃', color: this.tokens ? this.tokens.danger : '#78909C' }
              ]
            }).then((result) => {
              if (result.index === 1) {
                router.back();
              }
            });
          } else {
            router.back();
          }
        })
        .accessibilityText('取消并返回')
        .accessibilityLevel('yes')

        // 日期显示
        Column() {
          Text(DateUtils.formatDateCN(this.date))
            .fontSize(TYPO.cardTitle.size)
            .fontWeight(TYPO.cardTitle.weight)
            .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          Text(DateUtils.getWeekdayName(this.date))
            .fontSize(TYPO.eyebrow.size)
            .fontColor(this.tokens ? this.tokens.textTertiary : '#CCCCCC')
            .margin({ top: 2 })
            .attributeModifier(SKETCH_BODY) // HUI-027：星期标签(纯中文)→清松手写体2；上方日期数字读出保留系统字
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Center)

        // 字数统计
        Text(this.characterCount.toString() + ' 字')
          .fontSize(TYPO.eyebrow.size)
          .fontColor(this.tokens ? this.tokens.textTertiary : '#CCCCCC')
      }
      .width('100%')
      .padding({ left: SPACING.pageH, right: SPACING.pageH, top: SPACING.pageTop, bottom: SPACING.cardPadSm })

      Scroll() {
        Column() {
          // ═══════════════════════════════════════════
          // 标题输入（placeholder 灰）
          // ═══════════════════════════════════════════
          TextInput({ text: this.title, placeholder: '给这段时光起个标题…' })
            .fontSize(TYPO.sectionTitle.size)
            .fontWeight(TYPO.sectionTitle.weight)
            .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
            .placeholderColor(this.tokens ? this.tokens.textTertiary : '#CCCCCC')
            .placeholderFont({ size: TYPO.sectionTitle.size, weight: 400 })
            .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
            .borderRadius(RADIUS.input)
            .height(52)
            .padding({ left: 16, right: 16 })
            .border(this.titleFocused
              ? { width: 2, color: CYAN_FOCUS_RING }
              : { width: 1, color: this.tokens ? this.tokens.border : '#EAEAE6' })
            .onFocus(() => {
              this.titleFocused = true;
            })
            .onBlur(() => {
              this.titleFocused = false;
            })
            .onChange((value: string) => {
              this.title = value;
            })
            .accessibilityText('日记标题输入框')

          // ═══════════════════════════════════════════
          // 5 心情选择器（青浅底 track + 选中白底/缩放/青字）
          // ═══════════════════════════════════════════
          Row() {
            SymbolGlyph(IconMapper.MOOD_HEART)
              .fontSize(13)
              .fontColor([this.tokens ? this.tokens.primary : '#00C2B8'])
            Text("TODAY'S MOOD")
              .fontSize(TYPO.eyebrow.size)
              .fontWeight(TYPO.eyebrow.weight)
              .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
              .letterSpacing(2)
              .opacity(0.7)
              .margin({ left: 6 })
              .attributeModifier(SKETCH_TITLE) // HUI-027：eyebrow 微标→猫啃什锦黑
            Text('今日心情')
              .fontSize(TYPO.body.size)
              .fontWeight(TYPO.cardTitle.weight)
              .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
              .margin({ left: 10 })
              .attributeModifier(SKETCH_BODY) // HUI-027：中文标签→清松手写体2
          }
          .width('100%')
          .margin({ top: SPACING.cardGap, bottom: SPACING.cardPadSm })

          Row() {
            ForEach(this.moodOptions, (opt: MoodOption) => {
              Column() {
                LottieAnimation({
                  animPath: opt.animPath,
                  loop: true,
                  autoPlay: true,
                  animWidth: 40,
                  animHeight: 40,
                  shouldPlay: true,
                  accessibilityLabel: opt.label
                })
                  .width(40)
                  .height(40)
                  .opacity(this.selectedMoodKey === opt.key ? 1.0 : 0.6)
                  .scale(this.selectedMoodKey === opt.key ? { x: 1.15, y: 1.15 } : { x: 1, y: 1 })
                  .animation({ duration: 200, curve: Curve.EaseInOut })
                Text(opt.label)
                  .fontSize(TYPO.eyebrow.size)
                  .fontWeight(this.selectedMoodKey === opt.key ? TYPO.cardTitle.weight : TYPO.eyebrow.weight)
                  .fontColor(this.selectedMoodKey === opt.key
                    ? (this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
                    : (this.tokens ? this.tokens.textSecondary : '#5A5A5A'))
                  .margin({ top: 4 })
                  .maxLines(1)
                  .attributeModifier(SKETCH_BODY) // HUI-027：心情中文标签→清松手写体2
              }
              .layoutWeight(1)
              .padding({ top: 10, bottom: 10 })
              .borderRadius(RADIUS.input)
              .backgroundColor(this.selectedMoodKey === opt.key
                ? (this.tokens ? this.tokens.btnPrimary : '#738A9C')
                : (this.tokens ? this.tokens.surface : '#FFFFFF')) // HUI-041：心情项未选中底由死白改读 surface token，深色模式跟随主题
              .scale(this.selectedMoodKey === opt.key ? { x: 1.05, y: 1.05 } : { x: 1, y: 1 })
              .shadow(this.selectedMoodKey === opt.key
                ? { radius: 10, color: this.tokens ? this.tokens.shadow : 'rgba(0,194,184,0.10)', offsetX: 0, offsetY: 4 }
                : { radius: 0, color: Color.Transparent, offsetX: 0, offsetY: 0 })
              .onClick(() => {
                this.selectedMoodKey = opt.key;
              })
              .animation({ duration: 200, curve: Curve.EaseInOut })
              .accessibilityText(opt.label + (this.selectedMoodKey === opt.key ? ' 已选中' : ''))
              .accessibilityLevel('yes')
            }, (opt: MoodOption) => opt.key)
          }
          .width('100%')
          .padding(4)
          .borderRadius(RADIUS.input)
          .backgroundColor(this.tokens ? this.tokens.accent : '#E6F9F8')

          // ═══════════════════════════════════════════
          // 正文 textarea（青 focus ring #00C2B8/20 + RADIUS.item）
          // ═══════════════════════════════════════════
          // ═══════════════════════════════════════════
          // 正文编辑区 —— fix: HUI-001 v2（Stack 叠加内联 ghost text）
          //   v1「TextArea 下方建议行」被软键盘遮挡（用户反馈），推翻重做：
          //   · 底层 Text 镜像正文：Span(黑正文) + Span(浅灰接续) 字符级内联续排——Span 支持局部
          //     fontColor（span.d.ts L296），多行折行时接续自然贴在最后一个字后，Row 双 Text 方案
          //     在多行正文下建议会整块排到段落右侧错位，故用 Span 实现同一目标
          //   · 上层 TextArea：文字/背景/placeholder 全透明只留光标（caretColor L613），承接全部输入
          //   · 两层同 fontSize/lineHeight/padding(16)，光标与镜像文字逐行对齐
          //   已知近似：正文超出 220vp 后 TextArea 内部滚动、底层不随滚（长文错位本期接受）
          // ═══════════════════════════════════════════
          // AI 写作建议（正文上方——键盘弹起时编辑区整体上移，始终可见）
          if (this.ghostText.length > 0 || this.ghostLoading) {
            Row() {
              Text(this.ghostLoading ? '…' : '↳ ' + this.ghostText)
                .fontSize(13)
                .fontColor(this.isDark ? GHOST_COLOR_DARK : GHOST_COLOR_LIGHT)
                .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              Text('Enter 采纳')
                .fontSize(11)
                .fontColor(this.isDark ? GHOST_COLOR_DARK : GHOST_COLOR_LIGHT)
                .opacity(0.7).margin({ left: 8 })
            }
            .width('100%').padding({ left: 16, right: 16, top: 8, bottom: 4 })
            .onClick(() => { this.adoptGhostText(); })
          }

          // 正文 TextArea
          TextArea({ text: this.content, placeholder: BODY_PLACEHOLDER })
            .fontSize(TYPO.body.size)
            .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
            .placeholderColor(this.tokens ? this.tokens.textTertiary : '#CCCCCC')
            .placeholderFont({ size: TYPO.body.size, weight: 400 })
            .caretColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
            .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
            .width('100%')
            .height(220)
            .padding(16)
            .borderRadius(RADIUS.item)
            .clip(true)
            .border(this.bodyFocused
              ? { width: 2, color: CYAN_FOCUS_RING }
              : { width: 1, color: this.tokens ? this.tokens.border : '#EAEAE6' })
            .margin({ top: SPACING.cardGap })
            .onFocus(() => { this.bodyFocused = true; })
            .onBlur(() => { this.bodyFocused = false; })
            .onChange((value: string) => {
              this.content = value; this.characterCount = value.length; this.onBodyChanged();
            })
            .onSubmit((enterKey: EnterKeyType) => {
              if (this.ghostText.length > 0) {
                this.adoptGhostText();
              }
            })
            .enterKeyType(EnterKeyType.NEW_LINE)
            .accessibilityText('日记正文输入框')

          // ═══════════════════════════════════════════
          // 图片附件面板
          // ═══════════════════════════════════════════
          ImageAttachmentPanel({
            images: this.images,
            onAddImage: () => { this.pickImages(); },
            onDeleteImage: (index: number) => {
              this.images.splice(index, 1);
              promptAction.showToast({ message: '已删除图片', duration: 1000 });
            },
            onPreviewImage: (_img: string) => {
              promptAction.showToast({ message: '长按图片可删除', duration: 1500 });
            }
          })
            .margin({ top: SPACING.cardPadSm })

          // ═══════════════════════════════════════════
          // 关联待办（保留鸿蒙增强功能，套用新令牌样式）
          // ═══════════════════════════════════════════
          Button() {
            Row() {
              SymbolGlyph(IconMapper.TAB_TODO)
                .fontSize(16)
                .fontColor([this.tokens ? this.tokens.primary : '#00C2B8'])
              Text('关联待办 (' + this.getSelectedTodoCount().toString() + ')')
                .fontSize(TYPO.body.size)
                .fontColor(this.tokens ? this.tokens.primary : '#00C2B8')
                .margin({ left: 6 })
                .attributeModifier(SKETCH_BODY) // HUI-027：按钮中文标签→清松手写体2
              Blank()
              SymbolGlyph(this.showTodoPicker ? IconMapper.COLLAPSE : IconMapper.EXPAND)
                .fontSize(14)
                .fontColor([this.tokens ? this.tokens.primary : '#00C2B8'])
            }
            .width('100%')
          }
          .width('100%')
          .backgroundColor(this.tokens ? this.tokens.btnAux : '#C6BBAE') // HUI-035：关联待办辅助按钮→燕麦 btnAux
          .borderRadius(RADIUS.item)
          .height(44)
          .padding({ left: 16, right: 16 })
          .margin({ top: SPACING.cardPadSm })
          .onClick(() => {
            this.showTodoPicker = !this.showTodoPicker;
          })
          .accessibilityText('关联待办事项，展开或收起')
          .accessibilityLevel('yes')

          if (this.showTodoPicker) {
            Column() {
              ForEach(this.linkedTodos, (todo: MockTodo, idx: number) => {
                Row() {
                  SymbolGlyph(todo.selected ? IconMapper.CHECKIN_DONE : $r('sys.symbol.circle'))
                    .fontSize(18)
                    .fontColor([todo.selected
                      ? (this.tokens ? this.tokens.btnPrimary : '#738A9C')
                      : (this.tokens ? this.tokens.textTertiary : '#CCCCCC')])
                  Text(todo.title)
                    .fontSize(TYPO.body.size)
                    .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
                    .margin({ left: 10 })
                    .layoutWeight(1)
                    .attributeModifier(SKETCH_BODY) // HUI-027：待办标题(中文正文)→清松手写体2
                }
                .width('100%')
                .padding({ left: 12, right: 12, top: 10, bottom: 10 })
                .borderRadius(RADIUS.input)
                .backgroundColor(todo.selected
                  ? (this.tokens ? this.tokens.btnAux : '#C6BBAE')
                  : Color.Transparent)
                .margin({ top: 4 })
                .onClick(() => {
                  this.linkedTodos[idx] = {
                    id: todo.id,
                    title: todo.title,
                    selected: !todo.selected
                  };
                })
                .accessibilityText(todo.title + (todo.selected ? ' 已选中' : ' 未选中'))
                .accessibilityLevel('yes')
              })
            }
            .width('100%')
            .padding(SPACING.cardPadSm)
            .borderRadius(RADIUS.cardMd)
            .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
            .margin({ top: 8 })
            .animation({ duration: 250, curve: Curve.EaseInOut })
          }

          // 底部留白
          Column()
            .height(SPACING.cardPadLg)
            .width('100%')
        }
        .width('100%')
        .padding({ left: SPACING.pageH, right: SPACING.pageH })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)

      // ═══════════════════════════════════════════
      //「保存时光」全圆主色按钮（borderRadius 22，主色 #00C2B8）
      // ═══════════════════════════════════════════
      Button(this.isSaving ? '保存中…' : '保存时光')
        .fontSize(TYPO.cardTitle.size)
        .fontWeight(TYPO.cardTitle.weight)
        .fontColor(this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
        .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#738A9C')
        .borderRadius(22)
        .height(44)
        .width('100%')
        .enabled(!this.isSaving && this.content.trim().length > 0)
        .opacity(this.content.trim().length > 0 ? 1.0 : 0.5)
        .shadow({
          radius: 12,
          color: 'rgba(115,138,156,0.30)',
          offsetX: 0,
          offsetY: 4
        })
        .margin({ left: SPACING.pageH, right: SPACING.pageH, top: SPACING.cardPadSm, bottom: SPACING.cardPadMd })
        .onClick(() => {
          this.saveDiary();
        })
        .accessibilityText('保存时光')
        .accessibilityLevel('yes')
    }
    .width('100%')
    .height('100%')
    .backgroundColor(this.tokens ? this.tokens.bg : '#FAF8F5')
  }

  /**
   * 获取已选待办数量
   */
  private getSelectedTodoCount(): number {
    return this.linkedTodos.filter((t: MockTodo) => t.selected).length;
  }

  // ════════════════════════════════════════════════════════════
  // HUI-001 · ghost text 内联补全（类 Copilot：输入停顿 500ms → AI 浅灰续写建议）
  //   边界（任务书 §⑤）：<3 字不请求 / Key 未配静默 / 失败静默 / 加载中不重发 / 开关关闭零请求
  // ════════════════════════════════════════════════════════════

  /** 正文变化：任何输入先清旧建议（任意非 Enter 键 → 建议消失），再重开 500ms 防抖窗 */
  private onBodyChanged(): void {
    this.ghostText = '';
    if (this.ghostTimer >= 0) {
      clearTimeout(this.ghostTimer);
      this.ghostTimer = -1;
    }
    if (!this.isGhostEnabled()) {
      return;
    }
    this.ghostTimer = setTimeout(() => {
      this.ghostTimer = -1;
      this.requestGhostText();
    }, GHOST_DEBOUNCE_MS);
  }

  /** 建议总闸：设置「AI 写作建议」开（persist_ai_writing_suggestion，默认开）+ Key 已配 + 正文 ≥ 3 字 */
  private isGhostEnabled(): boolean {
    const enabled: number = AppStorage.get<number>(PersistentState.KEY_AI_WRITING_SUGGESTION) ?? 1;
    if (enabled !== 1) { return false; }
    if (!DeepSeekClient.isConfigured()) { return false; }
    return this.content.trim().length >= GHOST_MIN_CHARS;
  }

  /** 防抖到期发起续写：加载中不重发；响应回来若正文已变则丢弃本次并按最新正文重排队 */
  private async requestGhostText(): Promise<void> {
    if (this.ghostLoading || !this.isGhostEnabled()) {
      return;
    }
    const snapshot: string = this.content;
    this.ghostLoading = true;
    try {
      const sysMsg: DSMessage = { role: 'system', content: GHOST_SYSTEM_PROMPT };
      const userMsg: DSMessage = { role: 'user', content: snapshot };
      const options: DSChatOptions = { temperature: 0.7, maxTokens: 50, model: 'deepseek-chat' };
      const result: DSChatResult = await DeepSeekClient.chat([sysMsg, userMsg], undefined, options);
      this.ghostLoading = false;
      if (this.content !== snapshot) {
        this.onBodyChanged(); // 等待期间用户又输入：本次作废，按最新正文重开防抖窗
        return;
      }
      if (!result.ok || result.message === undefined) {
        this.ghostText = '[err:' + (result.errorKind ?? '?') + ']';
        return;
      }
      const raw: string = result.message.content ?? '';
      const fc: string = result.finishReason ?? '';
      this.ghostText = raw.length === 0 ? '[empty|' + fc + ']' : raw.trim();
    } catch (err) {
      this.ghostLoading = false; // 兜底静默（chat 内部已归一化错误，理论不抛）
    }
  }

  /** 采纳建议：灰字并入正文末尾（简化方案），清空建议；后续 onChange 会自然重开防抖窗 */
  private adoptGhostText(): void {
    if (this.ghostText.length === 0) {
      return;
    }
    this.content = this.content + this.ghostText;
    this.characterCount = this.content.length;
    this.ghostText = '';
  }

  /**
   * fix: MAIN-001 · 图片上传去 mock：拉起系统相册 PhotoViewPicker，选中的图片经 ImageUtils.copyToSandbox
   * 复制到应用沙箱（持久化，PhotoViewPicker 的临时 URI 重启后会失效），追加到 images 数组。
   * 无需权限声明（系统 picker，用户在选择器内授完权，app 获临时 URI）。
   */
  private async pickImages(): Promise<void> {
    try {
      const remaining: number = 9 - this.images.length;
      if (remaining <= 0) {
        promptAction.showToast({ message: '最多添加 9 张图片', duration: 1500 });
        return;
      }
      const options: picker.PhotoSelectOptions = new picker.PhotoSelectOptions();
      options.MIMEType = picker.PhotoViewMIMETypes.IMAGE_TYPE;
      options.maxSelectNumber = remaining;
      const photoPicker: picker.PhotoViewPicker = new picker.PhotoViewPicker();
      const result: picker.PhotoSelectResult = await photoPicker.select(options);
      const uris: string[] = result.photoUris;
      if (!uris || uris.length === 0) {
        return;
      }
      const ctx: common.Context = getContext(this) as common.Context;
      const baseDir: string = ctx.filesDir;
      for (let i = 0; i < uris.length; i++) {
        // PhotoViewPicker 返回的临时 URI 在进程重启后失效；存入应用沙箱后持久可用，重启不丢。
        const sandboxPath: string | null = await ImageUtils.copyToSandbox(uris[i], baseDir);
        this.images.push(sandboxPath ?? uris[i]);
      }
      promptAction.showToast({ message: '已添加 ' + uris.length.toString() + ' 张图片', duration: 1500 });
    } catch (err) {
      hilog.error(0x0000, TAG, 'pickImages failed: %{public}s', JSON.stringify(err));
      promptAction.showToast({ message: '选择图片失败', duration: 1500 });
    }
  }

  /**
   * 保存日记（fix: HUI-FRONTEND-1 —— 原为 setTimeout 假保存，改接 DiaryViewModel 真落库）
   */
  private async saveDiary(): Promise<void> {
    if (this.isSaving) {
      return;
    }
    this.isSaving = true;
    try {
      await this.diaryVm.init(this.date);
      const ok: boolean = await this.diaryVm.save(this.content, this.images, this.title, this.selectedMoodKey);
      this.isSaving = false;
      if (ok) {
        promptAction.showToast({ message: '已保存！心情' + this.moodLabel(), duration: 2000 });
        router.back();
      } else {
        promptAction.showToast({ message: '保存失败：' + this.diaryVm.getLastSaveError(), duration: 3000 });
      }
    } catch (err) {
      this.isSaving = false;
      promptAction.showToast({ message: '保存失败：' + (err as Error).message, duration: 3000 });
    }
  }

  /**
   * 当前所选心情中文文案（用于保存提示）
   */
  private moodLabel(): string {
    const found = this.moodOptions.filter((m: MoodOption) => m.key === this.selectedMoodKey);
    return found.length > 0 ? found[0].label : '平静';
  }
}
