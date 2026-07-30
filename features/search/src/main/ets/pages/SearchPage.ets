// fix: HUI-046（T-S01：修结果区上方大空白/条目贴底截断——Scroll 默认 align 为 Alignment.Center，
//      内容矮于视口时被垂直居中（dump 实证：子 Column 顶偏移 446px=(1366-474)/2、247px=(1366-872)/2 精确居中），
//      两处内容 Scroll 补 .align(Alignment.Top) 锚顶；结果列表内容列补 pageBottom 底部留白防被悬浮导航胶囊遮挡）
// <!-- agentID: HUI-057 -->
// agentID: HUI-042（T-D07 三轮：系统 DatePickerDialog 顶部标题区不可换肤（.d.ts 全字段穷举无 title/header 样式项）→ 按用户既定决策升级自绘 ThemedDatePickerModal（shared），滚轮交互不变、全量主题化）
// 页面：搜索页面内容层（P2-04 复刻：搜索输入+青focus ring+类型分段pill
//       +心绪下拉+分类下拉+结果计数+结果卡+空态+搜索历史+日期入口）
// 关联计划：PLN-003 P2-04 / 关联需求：UX-001 §2.6
// 关联规范：PROJECT_SPEC §9（防崩溃）§10（图标本地库）§1.4（三者一致）
// 令牌：IconMapper / RADIUS / SPACING / TYPO / FONT —— 全引用，禁散写魔数
// 崩溃防范：§9.3 sourceMeta $r() 不写字段初始值（aboutToAppear 赋值）；
//           §9.4 @StorageLink tokens 全判空；
//           §9.1 禁 getter-in-build。
// 开发范式：ArkTS 声明式开发范式

import type { ThemeColorTokens } from '@ohos/shared';
import { IconMapper, DateUtils, RADIUS, SPACING, TYPO, EmptyStateView, ThemedDatePickerModal, TodoItem, LottieAnimation } from '@ohos/shared';
// HUI-030：手绘字体助手（标题→猫啃什锦黑 SKETCH_TITLE，正文/标签→清松手写体 SKETCH_BODY）
import { SKETCH_TITLE, SKETCH_BODY } from '@ohos/shared';
// T105 接线：真实检索业务由 SearchViewModel 提供（跨 5 源 + preferences 历史）
import { SearchViewModel, SearchSourceType } from '../viewmodel/SearchViewModel';
import type { SearchResult } from '../viewmodel/SearchViewModel';

/** 搜索结果项（扩 'extracted' 以承接 SearchViewModel 的提取任务来源） */
export interface SearchResultItem {
  id: number;
  title: string;
  subtitle: string;
  sourceType: 'diary' | 'todo' | 'happy' | 'extra' | 'extracted';
  date: string;
  mood?: string;
  category?: string;
}

/** 来源标签信息 */
interface SourceLabelInfo {
  label: string;
  icon: Resource;
  color: ResourceColor;
}

/** 类型分段选项 */
interface TypeOption {
  key: string;
  label: string;
}

/** 心绪选项 */
interface MoodOption {
  key: string;
  label: string;
  /** rawfile 相对路径，Lottie 动画 JSON 文件 */
  animPath: string;
  color: ResourceColor;
}

/** 分类选项 */
interface CategoryOption {
  key: string;
  label: string;
  /** rawfile 相对路径，JPG 图标文件 */
  imagePath: string;
}

@Component
export struct SearchPage {
  @State keyword: string = '';
  @State results: SearchResultItem[] = [];
  /** 当前关键词的完整检索结果（类型分段过滤前），供 applyFilters 客户端筛选 */
  @State rawResults: SearchResultItem[] = [];
  @State history: string[] = [];
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  /** HUI-042（T-D07 三轮）：主题化日期选择弹窗显隐 */
  @State showDatePicker: boolean = false;
  /** 输入框聚焦状态（控制青 focus ring） */
  @State isFocused: boolean = false;
  /** 激活的类型分段 */
  @State activeType: string = 'all';
  /** 选中的心绪（空=全部） */
  @State selectedMood: string = '';
  /** 选中的分类（空=全部） */
  @State selectedCategory: string = '';
  /** 展开的下拉面板（'mood'|'category'|''） */
  @State openPanel: string = '';
  /** HUI-001（七轮·DEV-003 接线）：按日期查找的当前日期（YYYY-MM-DD，空=未启用）——
   *  驱动 hasActiveQuery 展示结果区；输入关键词/清除时退出日期模式 */
  @State dateQuery: string = '';
  onResultClick?: (item: SearchResultItem) => void;
  onDateClick?: (date: string) => void;

  /** 防抖定时器 */
  private searchTimer: number = -1;

  /** T105：真实检索业务 VM（默认空构造；init 需 Context） */
  private searchVm: SearchViewModel = new SearchViewModel();
  /** VM 是否已 init（成功拿到 Context 并加载历史） */
  private vmReady: boolean = false;

  // §9.3：含 $r() 的数据结构不写字段初始值，改 aboutToAppear 赋值
  private sourceMeta: Record<string, SourceLabelInfo> = {};
  private typeOptions: TypeOption[] = [
    { key: 'all', label: '全部' },
    { key: 'diary', label: '日记' },
    { key: 'todo', label: '待办' },
    { key: 'happy', label: '开心事' },
    { key: 'extra', label: '多做事' }
  ];
  private moodOptions: MoodOption[] = [];
  private categoryOptions: CategoryOption[] = [];

  aboutToAppear(): void {
    // §9.3：sourceMeta $r() 赋值放此处（资源上下文已就绪）
    this.sourceMeta = {
      'diary': { label: '日记', icon: IconMapper.NAV_DIARY, color: '#0A59F7' },
      'todo': { label: '待办', icon: IconMapper.TAB_TODO, color: '#3B82F6' },
      'happy': { label: '开心事', icon: IconMapper.MOOD_PLEASANT, color: '#EC407A' },
      'extra': { label: '多做事', icon: IconMapper.ADD, color: '#90A4AE' },
      'extracted': { label: '提取', icon: IconMapper.TAG, color: '#8D6E63' }
    };

    // 心绪选项（5 心情 Lottie 动画）
    this.moodOptions = [
      { key: 'sunny', label: '晴', animPath: 'animations/sunny.json', color: '#E0BE72' },
      { key: 'star', label: '星', animPath: 'animations/night.json', color: '#E6D98A' },
      { key: 'heart', label: '心', animPath: 'animations/happy.json', color: '#FF4D4F' },
      { key: 'cloudy', label: '云', animPath: 'animations/sunclouds.json', color: '#94A3B8' },
      { key: 'rainy', label: '雨', animPath: 'animations/rain.json', color: '#4FC3F7' }
    ];

    // 分类选项（对齐 AddTodoDialog categoryOptions，JPG 图标）
    this.categoryOptions = [
      { key: '日常', label: '日常', imagePath: 'animations/日常.jpg' },
      { key: '学习', label: '学习', imagePath: 'animations/学习.jpg' },
      { key: '工作', label: '工作', imagePath: 'animations/工作.jpg' },
      { key: '日记', label: '日记', imagePath: 'animations/日记.jpg' },
      { key: '微信', label: '微信', imagePath: 'animations/微信.jpg' },
      { key: '语音', label: '语音', imagePath: 'animations/语音.jpg' }
    ];

    // T105：init SearchViewModel（需 Context）并回读持久化历史
    this.initVm();
  }

  /** 获取源标签信息（安全回退） */
  private getSourceLabel(type: string): SourceLabelInfo {
    const meta: SourceLabelInfo | undefined = this.sourceMeta[type];
    if (meta) {
      return meta;
    }
    return { label: '', icon: IconMapper.SEARCH, color: '#999999' };
  }

  /** HUI-040：半透明版本：ArkUI hex-alpha 为 #AARRGGBB，需前置 alpha（修复 alpha 后拼致底色发脏/失效 bug） */
  private withAlpha(hex: string, alphaHex: string): string {
    return '#' + alphaHex + hex.replace('#', '');
  }

  /** 获取选中 mood 的 Lottie 动画路径 */
  private getSelectedMoodAnimPath(): string {
    for (let i = 0; i < this.moodOptions.length; i++) {
      if (this.moodOptions[i].key === this.selectedMood) {
        return this.moodOptions[i].animPath;
      }
    }
    return 'animations/sunclouds.json';
  }

  /** 获取选中分类的图片路径 */
  private getSelectedCategoryImagePath(): string {
    for (let i = 0; i < this.categoryOptions.length; i++) {
      if (this.categoryOptions[i].key === this.selectedCategory) {
        return this.categoryOptions[i].imagePath;
      }
    }
    return '';
  }

  /** 是否有活跃查询条件 */
  private hasActiveQuery(): boolean {
    return this.keyword.length > 0 || this.activeType !== 'all' ||
      this.selectedMood.length > 0 || this.selectedCategory.length > 0 ||
      this.dateQuery.length > 0;
  }

  // ════════════════════════════════════════════════════════
  // build
  // ════════════════════════════════════════════════════════

  build() {
    // HUI-042（T-D07 三轮）：根节点包 Stack，为主题化日期弹窗提供全屏覆盖层（同 SettingsPage 先例）
    Stack() {
      Column() {
      // ═══════════════════════════════════════════════
      // 搜索输入框（左放大镜 + 右清除 + 蓝色 focus ring + 右侧「取消」按钮）
      // ═══════════════════════════════════════════════
      Row() {
        // 搜索框主体（layoutWeight 撑满，右侧留取消按钮空间）
        Row() {
          SymbolGlyph(IconMapper.SEARCH)
            .fontSize(18)
            .fontColor([this.tokens ? this.tokens.textTertiary : '#999999'])
            .margin({ left: 16 })

          TextInput({ text: this.keyword, placeholder: '搜索日记、待办和记录...' })
            .fontSize(15)
            .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
            .placeholderColor(this.tokens ? this.tokens.textTertiary : '#999999')
            .backgroundColor(Color.Transparent)
            .layoutWeight(1)
            .height(48)
            .borderRadius(0)
            .onChange((value: string) => {
              this.keyword = value;
              this.debounceSearch(value);
            })
            .onSubmit(() => {
              this.executeSearch(this.keyword);
            })
            .onFocus(() => {
              this.isFocused = true;
            })
            .onBlur(() => {
              this.isFocused = false;
            })
            .accessibilityText('搜索输入框')

          if (this.keyword.length > 0) {
            Button() {
              SymbolGlyph(IconMapper.SEARCH_CLEAR)
                .fontSize(18)
                .fontColor([this.tokens ? this.tokens.textTertiary : '#999999'])
            }
            .width(36)
            .height(36)
            .borderRadius(18)
            .backgroundColor(Color.Transparent)
            .margin({ right: 8 })
            .onClick(() => {
              if (this.searchTimer >= 0) {
                clearTimeout(this.searchTimer);
              }
              this.keyword = '';
              this.dateQuery = ''; // HUI-001（七轮）：清除同时退出按日期查找模式
              this.rawResults = [];
              this.results = [];
            })
            .accessibilityText('清除搜索内容')
          }
        }
        .layoutWeight(1)
        .height(48)
        .borderRadius(24)
        .backgroundColor(this.tokens ? this.tokens.surface : '#F0F4F8')
        .border({
          width: this.isFocused ? 2 : 1,
          color: this.isFocused
            ? (this.tokens ? this.tokens.primary : '#0A59F7')
            : (this.tokens ? this.tokens.border : '#E0E6ED')
        })
        .shadow(
          this.isFocused
            ? { radius: 8, color: this.tokens ? this.tokens.shadow : 'rgba(0,0,0,0.08)', offsetX: 0, offsetY: 0 }
            : { radius: 0, color: 'rgba(0,0,0,0)', offsetX: 0, offsetY: 0 }
        )

        // 「取消」按钮（蓝色文字，清除搜索并退出活跃查询）
        Text('取消')
          .fontSize(15)
          .fontWeight(500)
          .fontColor(this.tokens ? this.tokens.primary : '#0A59F7')
          .margin({ left: 12 })
          .onClick(() => {
            if (this.searchTimer >= 0) {
              clearTimeout(this.searchTimer);
            }
            this.keyword = '';
            this.dateQuery = '';
            this.rawResults = [];
            this.results = [];
            this.activeType = 'all';
            this.selectedMood = '';
            this.selectedCategory = '';
            this.openPanel = '';
          })
          .accessibilityText('取消搜索')
      }
      .width('100%')
      .margin({ top: 0, bottom: SPACING.cardGap })
      .accessibilityGroup(true)
      .accessibilityText('搜索框，输入关键词搜索')

      // ═══════════════════════════════════════════════
      // 筛选卡：类型分段 + 心绪/分类下拉
      // ═══════════════════════════════════════════════
      Column() {
        // 类型分段下划线 tab 横滑
        Scroll() {
          Row() {
            ForEach(this.typeOptions, (opt: TypeOption) => {
              Column() {
                Text(opt.label)
                  .attributeModifier(SKETCH_BODY) // HUI-030：类型分段标签→清松手写体
                  .fontSize(TYPO.body.size)
                  .fontWeight(this.activeType === opt.key ? 600 : 400)
                  .fontColor(this.activeType === opt.key
                    ? (this.tokens ? this.tokens.primary : '#0A59F7')
                    : (this.tokens ? this.tokens.textSecondary : '#666666'))
                  .padding({ top: 8, bottom: 8 })

                // 选中态蓝色下划线
                Divider()
                  .strokeWidth(2)
                  .color(this.activeType === opt.key
                    ? (this.tokens ? this.tokens.primary : '#0A59F7')
                    : Color.Transparent)
                  .width('100%')
              }
              .margin({ right: 16 })
              .onClick(() => {
                this.activeType = opt.key;
                this.applyFilters();
              })
              .accessibilityText(opt.label + (this.activeType === opt.key ? '，已选中' : ''))
            })
          }
          .padding({ left: 0, right: 0 })
        }
        .scrollBar(BarState.Off)
        .scrollable(ScrollDirection.Horizontal)
        .margin({ bottom: 10 })

        // 心绪下拉 + 分类下拉（同行）
        Row({ space: 8 }) {
          // 心绪下拉触发按钮
          Row() {
            LottieAnimation({
              animPath: this.selectedMood.length > 0
                ? this.getSelectedMoodAnimPath()
                : 'animations/sunclouds.json',
              loop: true,
              autoPlay: true,
              animWidth: 20,
              animHeight: 20,
              shouldPlay: true
            })
              .width(20)
              .height(20)
              .margin({ right: 6 })

            Text(this.selectedMood.length > 0
              ? this.getSelectedMoodLabel()
              : '心绪')
              .attributeModifier(SKETCH_BODY) // HUI-030：心绪触发标签→清松手写体
              .fontSize(TYPO.eyebrow.size)
              .fontWeight(500)
              .fontColor(this.tokens ? this.tokens.textSecondary : '#666666')

            SymbolGlyph(this.openPanel === 'mood'
              ? IconMapper.COLLAPSE
              : IconMapper.EXPAND)
              .fontSize(12)
              .fontColor([this.tokens ? this.tokens.textTertiary : '#999999'])
              .margin({ left: 4 })
          }
          .height(36)
          .borderRadius(RADIUS.input)
          .padding({ left: 12, right: 12 })
          .border({
            width: 1,
            color: this.tokens ? this.tokens.border : '#E0E6ED'
          })
          .backgroundColor(this.tokens ? this.tokens.surface : '#F0F4F8')
          .layoutWeight(1)
          .onClick(() => {
            this.openPanel = this.openPanel === 'mood' ? '' : 'mood';
          })
          .accessibilityText('心绪筛选')

          // 分类下拉触发按钮
          Row() {
            if (this.selectedCategory.length > 0) {
              Image($rawfile(this.getSelectedCategoryImagePath()))
                .width(24)
                .height(24)
                .objectFit(ImageFit.Contain)
                .borderRadius(4)
                .margin({ right: 6 })
            } else {
              SymbolGlyph(IconMapper.TAG)
                .fontSize(16)
                .fontColor([this.tokens ? this.tokens.textTertiary : '#999999'])
                .margin({ right: 6 })
            }

            Text(this.selectedCategory.length > 0
              ? this.selectedCategory
              : '分类')
              .attributeModifier(SKETCH_BODY) // HUI-030：分类触发标签→清松手写体
              .fontSize(TYPO.eyebrow.size)
              .fontWeight(500)
              .fontColor(this.tokens ? this.tokens.textSecondary : '#666666')

            SymbolGlyph(this.openPanel === 'category'
              ? IconMapper.COLLAPSE
              : IconMapper.EXPAND)
              .fontSize(12)
              .fontColor([this.tokens ? this.tokens.textTertiary : '#999999'])
              .margin({ left: 4 })
          }
          .height(36)
          .borderRadius(RADIUS.input)
          .padding({ left: 12, right: 12 })
          .border({
            width: 1,
            color: this.tokens ? this.tokens.border : '#E0E6ED'
          })
          .backgroundColor(this.tokens ? this.tokens.surface : '#F0F4F8')
          .layoutWeight(1)
          .onClick(() => {
            this.openPanel = this.openPanel === 'category' ? '' : 'category';
          })
          .accessibilityText('分类筛选')
        }
        .width('100%')

        // 心绪下拉面板（展开时内联显示）
        if (this.openPanel === 'mood') {
          Column() {
            // 「全部心绪」项
            Row() {
              SymbolGlyph($r('sys.symbol.circle_fill'))
                .fontSize(16)
                .fontColor([this.tokens ? this.tokens.textTertiary : '#999999'])
                .margin({ right: 8 })
              Text('全部心绪')
                .attributeModifier(SKETCH_BODY) // HUI-030：全部心绪项→清松手写体
                .fontSize(TYPO.body.size)
                .fontWeight(400)
                .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
                .layoutWeight(1)
              if (this.selectedMood.length === 0) {
                SymbolGlyph(IconMapper.CHECKMARK)
                  .fontSize(14)
                  .fontColor([this.tokens ? this.tokens.primary : '#0A59F7'])
              }
            }
            .width('100%')
            .height(44)
            .padding({ left: 12, right: 12 })
            .onClick(() => {
              this.selectedMood = '';
              this.openPanel = '';
              this.applyFilters();
            })

            Divider()
              .strokeWidth(0.5)
              .color(this.tokens ? this.tokens.divider : '#EEF0F4')

            ForEach(this.moodOptions, (mo: MoodOption) => {
              Row() {
                LottieAnimation({
                  animPath: mo.animPath,
                  loop: true,
                  autoPlay: true,
                  animWidth: 20,
                  animHeight: 20,
                  shouldPlay: true
                })
                  .width(20)
                  .height(20)
                  .margin({ right: 8 })
                Text(mo.label)
                  .attributeModifier(SKETCH_BODY) // HUI-030：心绪选项标签→清松手写体
                  .fontSize(TYPO.body.size)
                  .fontWeight(400)
                  .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
                  .layoutWeight(1)
                if (this.selectedMood === mo.key) {
                  SymbolGlyph(IconMapper.CHECKMARK)
                    .fontSize(14)
                    .fontColor([this.tokens ? this.tokens.primary : '#0A59F7'])
                }
              }
              .width('100%')
              .height(44)
              .padding({ left: 12, right: 12 })
              .borderRadius(RADIUS.item)
              .backgroundColor(this.selectedMood === mo.key
                // HUI-040：alpha 后拼 → withAlpha 前置（#AARRGGBB），fallback 同步改前置
                ? (this.tokens ? this.withAlpha(this.tokens.btnPrimary, '08') : '#080A59F7')
                : Color.Transparent)
              .onClick(() => {
                this.selectedMood = mo.key;
                this.openPanel = '';
                this.applyFilters();
              })
              .accessibilityText(mo.label)
            })
          }
          .width('100%')
          .borderRadius(RADIUS.item)
          .padding({ top: 8, bottom: 8 })
          .backgroundColor(this.tokens ? this.tokens.surface : '#F0F4F8')
          .border({
            width: 1,
            color: this.tokens ? this.tokens.border : '#E0E6ED'
          })
          .margin({ top: 8 })
        }

        // 分类下拉面板（展开时内联显示）
        if (this.openPanel === 'category') {
          Column() {
            // 「全部分类」项
            Row() {
              SymbolGlyph(IconMapper.TAG)
                .fontSize(16)
                .fontColor([this.tokens ? this.tokens.textTertiary : '#999999'])
                .margin({ right: 8 })
              Text('全部分类')
                .attributeModifier(SKETCH_BODY) // HUI-030：全部分类项→清松手写体
                .fontSize(TYPO.body.size)
                .fontWeight(400)
                .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
                .layoutWeight(1)
              if (this.selectedCategory.length === 0) {
                SymbolGlyph(IconMapper.CHECKMARK)
                  .fontSize(14)
                  .fontColor([this.tokens ? this.tokens.primary : '#0A59F7'])
              }
            }
            .width('100%')
            .height(44)
            .padding({ left: 12, right: 12 })
            .onClick(() => {
              this.selectedCategory = '';
              this.openPanel = '';
              this.applyFilters();
            })

            Divider()
              .strokeWidth(0.5)
              .color(this.tokens ? this.tokens.divider : '#EEF0F4')

            ForEach(this.categoryOptions, (co: CategoryOption) => {
              Row() {
                Image($rawfile(co.imagePath))
                  .width(28)
                  .height(28)
                  .objectFit(ImageFit.Contain)
                  .borderRadius(4)
                  .margin({ right: 8 })
                Text(co.label)
                  .attributeModifier(SKETCH_BODY) // HUI-030：分类选项标签→清松手写体
                  .fontSize(TYPO.body.size)
                  .fontWeight(400)
                  .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
                  .layoutWeight(1)
                if (this.selectedCategory === co.key) {
                  SymbolGlyph(IconMapper.CHECKMARK)
                    .fontSize(14)
                    .fontColor([this.tokens ? this.tokens.primary : '#0A59F7'])
                }
              }
              .width('100%')
              .height(44)
              .padding({ left: 12, right: 12 })
              .borderRadius(RADIUS.item)
              .backgroundColor(this.selectedCategory === co.key
                // HUI-040：alpha 后拼 → withAlpha 前置（#AARRGGBB），fallback 同步改前置
                ? (this.tokens ? this.withAlpha(this.tokens.btnPrimary, '08') : '#080A59F7')
                : Color.Transparent)
              .onClick(() => {
                this.selectedCategory = co.key;
                this.openPanel = '';
                this.applyFilters();
              })
              .accessibilityText(co.label)
            })
          }
          .width('100%')
          .borderRadius(RADIUS.item)
          .padding({ top: 8, bottom: 8 })
          .backgroundColor(this.tokens ? this.tokens.surface : '#F0F4F8')
          .border({
            width: 1,
            color: this.tokens ? this.tokens.border : '#E0E6ED'
          })
          .margin({ top: 8 })
        }
      }
      .width('100%')
      .borderRadius(RADIUS.cardMd)
      .padding(SPACING.cardPadSm)
      .backgroundColor(this.tokens ? this.tokens.surface : '#F0F4F8')
      .border({
        width: 1,
        color: this.tokens ? this.tokens.border : '#E0E6ED'
      })
      .margin({ bottom: SPACING.cardGap })
      .accessibilityGroup(true)
      .accessibilityText('搜索筛选条件')

      // ═══════════════════════════════════════════════
      // 内容区：结果列表 / 空态 / 闲置（历史+热门+日期入口）
      // ═══════════════════════════════════════════════
      if (this.hasActiveQuery()) {
        this.buildSearchResults()
      } else {
        this.buildIdleContent()
      }
      }
      .width('100%')
      .height('100%')
      .padding({
        left: 0,
        right: 0,
        top: 0
      })

      // 主题化日期选择弹窗（覆盖层，条件渲染——同 SettingsPage ReminderTimePickerModal 先例）
      if (this.showDatePicker) {
        ThemedDatePickerModal({
          initialDate: this.dateQuery,
          onConfirm: (value: Date) => {
            this.showDatePicker = false;
            this.runDateSearch(DateUtils.formatDate(value));
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

  // ═════════════════════════════════════════════════
  // @Builder: 搜索结果区
  // ═════════════════════════════════════════════════

  @Builder
  buildSearchResults() {
    Scroll() {
      Column() {
        if (this.results.length > 0) {
          // 结果计数
          Row() {
            Text('找到 ' + this.results.length.toString() + ' 条结果')
              .attributeModifier(SKETCH_BODY) // HUI-030：结果计数中文标签→清松手写体（内嵌数非纯数字统计）
              .fontSize(TYPO.eyebrow.size)
              .fontWeight(600)
              .fontColor(this.tokens ? this.tokens.textSecondary : '#666666')
          }
          .width('100%')
          .padding({ top: 0, bottom: 10 })

          // 结果卡列表
          Column() {
            ForEach(this.results, (item: SearchResultItem, idx: number) => {
              Column() {
                // 来源标签 + 日期青药丸
                Row() {
                  Row() {
                    SymbolGlyph(this.getSourceLabel(item.sourceType).icon)
                      .fontSize(14)
                      .fontColor([this.getSourceLabel(item.sourceType).color])
                      .margin({ right: 4 })
                    Text(this.getSourceLabel(item.sourceType).label)
                      .attributeModifier(SKETCH_BODY) // HUI-030：来源徽标→清松手写体
                      .fontSize(10)
                      .fontWeight(700)
                      .fontColor(this.getSourceLabel(item.sourceType).color)
                  }
                  .padding({ left: 8, right: 8, top: 3, bottom: 3 })
                  .borderRadius(4)
                  // HUI-040：alpha 后拼 → withAlpha 前置（原写法 A 位被源色占用，chip 底色完全不显示）；
                  // color 声明为 ResourceColor（实际全为 hex 字符串），String() 收窄适配 withAlpha
                  .backgroundColor(this.withAlpha(String(this.getSourceLabel(item.sourceType).color), '14'))

                  Blank()

                  // 日期药丸（雾霾蓝 tint）
                  Row() {
                    Text(DateUtils.formatShortCN(item.date))
                      .fontSize(12)
                      .fontWeight(600)
                      .fontColor(this.tokens ? this.tokens.btnPrimary : '#0A59F7')
                  }
                  .padding({ left: 10, right: 10, top: 4, bottom: 4 })
                  .borderRadius(12)
                  // HUI-040：alpha 后拼 → withAlpha 前置（#AARRGGBB），fallback 同步改前置
                  .backgroundColor(this.tokens ? this.withAlpha(this.tokens.btnPrimary, '10') : '#100A59F7')
                  .onClick(() => {
                    if (this.onDateClick) {
                      this.onDateClick(item.date);
                    }
                  })
                  .accessibilityText('跳转到' + item.date)
                }
                .width('100%')
                .margin({ bottom: 8 })

                // 标题
                Text(item.title)
                  .attributeModifier(SKETCH_BODY) // HUI-030：结果标题→清松手写体（规则：结果标题走 BODY）
                  .fontSize(TYPO.cardTitle.size)
                  .fontWeight(600)
                  .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .margin({ bottom: 4 })

                // 预览
                Text(item.subtitle)
                  .attributeModifier(SKETCH_BODY) // HUI-030：结果预览→清松手写体
                  .fontSize(TYPO.body.size)
                  .fontWeight(400)
                  .fontColor(this.tokens ? this.tokens.textTertiary : '#999999')
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
              }
              .width('100%')
              .padding({ left: 0, right: 0, top: 0, bottom: 0 })
              .onClick(() => {
                if (this.onResultClick) {
                  this.onResultClick(item);
                }
              })
              .accessibilityText(this.getSourceLabel(item.sourceType).label + '：' + item.title)

              if (idx < this.results.length - 1) {
                Divider()
                  .strokeWidth(0.5)
                  .color(this.tokens ? this.tokens.divider : '#EEF0F4')
              }
            }, (item: SearchResultItem) => item.id.toString())
          }
          .width('100%')
          .borderRadius(RADIUS.cardMd)
          .padding({ left: SPACING.cardPadSm, right: SPACING.cardPadSm,
            top: SPACING.cardPadSm, bottom: SPACING.cardPadSm })
          .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
          .border({
            width: 1,
            color: this.tokens ? this.tokens.border : '#E0E6ED'
          })
          .accessibilityGroup(true)
          .accessibilityText('搜索结果列表，共' + this.results.length.toString() + '条')
        } else {
          // 空态
          Column() {
            EmptyStateView({
              icon: IconMapper.SEARCH,
              title: '未找到相关内容',
              description: '试试其他关键词或筛选条件'
            })
          }
          .width('100%')
          .margin({ top: 40 })
        }
      }
      .width('100%')
      // fix: HUI-046：结果列表内容列补底部留白（同 buildIdleContent L~894 先例），
      //      防内容超视口滚到末尾时最后一张卡被悬浮导航胶囊遮挡
      .padding({ bottom: SPACING.pageBottom })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    // fix: HUI-046：Scroll 默认 align=Alignment.Center，内容矮于视口时整体被垂直居中，
    //      造成筛选卡与「找到 N 条结果」之间大片空白（软键盘收起后同样触发）——锚顶修复
    .align(Alignment.Top)
  }

  // ═════════════════════════════════════════════════
  // @Builder: 闲置区（搜索历史 + 热门标签 + 日期入口）
  // ═════════════════════════════════════════════════

  @Builder
  buildIdleContent() {
    Scroll() {
      Column() {
        // ── 搜索历史 ──
        if (this.history.length > 0) {
          Column() {
            Row() {
              Text('最近搜索')
                .attributeModifier(SKETCH_TITLE) // HUI-030：区块标题→猫啃什锦黑
                .fontSize(TYPO.cardTitle.size)
                .fontWeight(600)
                .fontColor(this.tokens ? this.tokens.textSecondary : '#666666')
                .opacity(0.7)
              Blank()
              Text('清除全部')
                .attributeModifier(SKETCH_BODY) // HUI-030：清除全部动作标签→清松手写体
                .fontSize(TYPO.body.size)
                .fontWeight(500)
                .fontColor(this.tokens ? this.tokens.danger : '#FF4D4F')
                .onClick(() => {
                  this.clearAllHistory();
                })
                .accessibilityText('清除所有搜索记录')
            }
            .width('100%')
            .padding({ left: 0, right: 0, top: 0, bottom: 10 })

            ForEach(this.history, (h: string, idx: number) => {
              Row() {
                SymbolGlyph(IconMapper.HISTORY)
                  .fontSize(16)
                  .fontColor([this.tokens ? this.tokens.textTertiary : '#999999'])
                  .margin({ right: 10 })

                Text(h)
                  .attributeModifier(SKETCH_BODY) // HUI-030：历史词→清松手写体
                  .fontSize(TYPO.body.size)
                  .fontWeight(400)
                  .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
                  .layoutWeight(1)
                  .onClick(() => {
                    this.keyword = h;
                    this.executeSearch(h);
                  })

                SymbolGlyph(IconMapper.CLOSE)
                  .fontSize(14)
                  .fontColor([this.tokens ? this.tokens.textTertiary : '#999999'])
                  .width(36)
                  .height(36)
                  .borderRadius(18)
                  .onClick(() => {
                    this.removeHistoryItem(idx);
                  })
                  .accessibilityText('删除搜索记录：' + h)
              }
              .width('100%')
              .height(48)
              .padding({ left: 4, right: 4 })
              .alignItems(VerticalAlign.Center)
              .accessibilityText('搜索：' + h)

              if (idx < this.history.length - 1) {
                Divider()
                  .strokeWidth(0.5)
                  .color(this.tokens ? this.tokens.divider : '#EEF0F4')
              }
            }, (h: string, idx: number) => h + '_' + idx.toString())
          }
          .width('100%')
          .borderRadius(RADIUS.cardMd)
          .padding({ left: SPACING.cardPadSm, right: SPACING.cardPadSm,
            top: SPACING.cardPadSm, bottom: SPACING.cardPadSm })
          .backgroundColor(this.tokens ? this.tokens.surface : '#F0F4F8')
          .border({
            width: 1,
            color: this.tokens ? this.tokens.border : '#E0E6ED'
          })
          .margin({ bottom: SPACING.cardGap })
          .accessibilityGroup(true)
          .accessibilityText('搜索历史记录，共' + this.history.length.toString() + '条')
        }

        // ── 日期跳转入口 ──
        Row() {
          SymbolGlyph(IconMapper.TAB_CALENDAR)
            .fontSize(20)
            .fontColor([this.tokens ? this.tokens.primary : '#0A59F7'])
            .margin({ right: 12 })

          Column() {
            Text('按日期查找')
              .attributeModifier(SKETCH_BODY) // HUI-030：入口主标签→清松手写体
              .fontSize(TYPO.body.size)
              .fontWeight(600)
              .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
            Text('选择日期直接跳转到对应日记')
              .attributeModifier(SKETCH_BODY) // HUI-030：入口说明→清松手写体
              .fontSize(TYPO.eyebrow.size)
              .fontWeight(400)
              .fontColor(this.tokens ? this.tokens.textTertiary : '#999999')
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          SymbolGlyph(IconMapper.FORWARD)
            .fontSize(18)
            .fontColor([this.tokens ? this.tokens.textTertiary : '#999999'])
        }
        .width('100%')
        .height(64)
        .padding({ left: SPACING.cardPadSm, right: SPACING.cardPadSm })
        .borderRadius(RADIUS.cardMd)
        .backgroundColor(this.tokens ? this.tokens.surface : '#F0F4F8')
        .border({
          width: 1,
          color: this.tokens ? this.tokens.border : '#E0E6ED'
        })
        .margin({ bottom: SPACING.cardGap })
        .onClick(() => {
          // HUI-001（七轮·DEV-003 接线）：入口改弹系统 DatePicker → searchByDate → 复用结果列表渲染
          this.openDatePicker();
        })
        .accessibilityText('按日期查找日记，点击选择日期')

        // ── 热门搜索标签 ──
        Column() {
          Text('热门搜索')
            .attributeModifier(SKETCH_TITLE) // HUI-030：区块标题→猫啃什锦黑
            .fontSize(TYPO.cardTitle.size)
            .fontWeight(600)
            .fontColor(this.tokens ? this.tokens.textSecondary : '#666666')
            .opacity(0.7)
            .width('100%')
            .padding({ left: 0, right: 0, top: 0, bottom: 10 })

          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(['日记', '待办', '开心事', '会议', '天气', '打卡', '番茄钟', '学习'], (tag: string) => {
              Text(tag)
                .attributeModifier(SKETCH_BODY) // HUI-030：热门标签→清松手写体
                .fontSize(TYPO.body.size)
                .fontWeight(400)
                .fontColor(this.tokens ? this.tokens.btnPrimary : '#0A59F7')
                .padding({ left: 14, right: 14, top: 8, bottom: 8 })
                .borderRadius(999)
                // HUI-040：alpha 后拼 → withAlpha 前置（#AARRGGBB），fallback 同步改前置
                .backgroundColor(this.tokens ? this.withAlpha(this.tokens.btnPrimary, '10') : '#100A59F7')
                .margin({ right: 8, bottom: 8 })
                .onClick(() => {
                  this.keyword = tag;
                  this.executeSearch(tag);
                })
                .accessibilityText('搜索：' + tag)
            })
          }
          .width('100%')
          .padding({ left: 4, right: 4 })
        }
        .width('100%')
        .borderRadius(RADIUS.cardMd)
        .padding({ left: SPACING.cardPadSm, right: SPACING.cardPadSm,
          top: SPACING.cardPadSm, bottom: SPACING.cardPadSm })
        .backgroundColor(this.tokens ? this.tokens.surface : '#F0F4F8')
        .border({
          width: 1,
          color: this.tokens ? this.tokens.border : '#E0E6ED'
        })
      }
      .width('100%')
      .padding({ top: 0, bottom: SPACING.pageBottom })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    // fix: HUI-046：同结果区——历史为空等内容矮于视口场景防 Scroll 默认居中产生顶部空白
    .align(Alignment.Top)
  }

  // ═════════════════════════════════════════════════
  // 搜索逻辑
  // ═════════════════════════════════════════════════

  /** 获取选中 mood 的标签文本 */
  private getSelectedMoodLabel(): string {
    for (let i = 0; i < this.moodOptions.length; i++) {
      if (this.moodOptions[i].key === this.selectedMood) {
        return this.moodOptions[i].label;
      }
    }
    return '心绪';
  }

  /** 初始化 SearchViewModel（需 Context）并回读持久化历史 */
  private async initVm(): Promise<void> {
    try {
      const ctx = getContext(this) as Context;
      await this.searchVm.init(ctx);
      this.vmReady = true;
      this.history = this.searchVm.getHistory();
    } catch (e) {
      // 兜底：init 失败则空历史，不崩
      this.vmReady = false;
      this.history = [];
    }
  }

  /** SearchResult.sourceType(枚举) → UI 来源类型（R3 显式映射） */
  private mapSourceType(t: SearchSourceType): 'diary' | 'todo' | 'happy' | 'extra' | 'extracted' {
    if (t === SearchSourceType.DIARY) {
      return 'diary';
    }
    if (t === SearchSourceType.TODO) {
      return 'todo';
    }
    if (t === SearchSourceType.HAPPY) {
      return 'happy';
    }
    if (t === SearchSourceType.EXTRACTED) {
      return 'extracted';
    }
    return 'extra';
  }

  /** 调 SearchViewModel 真实检索（跨 5 源），映射为 UI 结果并回读历史 */
  private async runSearch(): Promise<void> {
    const kw: string = this.keyword.trim();
    if (kw.length === 0) {
      this.rawResults = [];
      this.results = [];
      return;
    }
    // HUI-001（七轮）：关键词检索统一退出按日期查找模式
    this.dateQuery = '';
    try {
      if (!this.vmReady) {
        const ctx = getContext(this) as Context;
        await this.searchVm.init(ctx);
        this.vmReady = true;
      }
      const list: SearchResult[] = await this.searchVm.search(kw);
      const mapped: SearchResultItem[] = [];
      for (let i = 0; i < list.length; i++) {
        const r: SearchResult = list[i];
        // R3 映射：SearchResult.snippet → UI subtitle；日记标题为「日记 - 日期」、正文在 snippet
        const item: SearchResultItem = {
          id: i + 1,
          title: r.title,
          subtitle: r.snippet,
          sourceType: this.mapSourceType(r.sourceType),
          date: r.date
        };
        if (r.sourceType === SearchSourceType.TODO) {
          item.category = (r.data as TodoItem).category;
        }
        mapped.push(item);
      }
      this.rawResults = mapped;
      this.applyFilters();
      // SearchViewModel.search 内部已持久化历史（上限 5），回读同步 UI
      this.history = this.searchVm.getHistory();
    } catch (e) {
      this.rawResults = [];
      this.results = [];
    }
  }

  /** HUI-001（七轮·DEV-003 接线）：弹日期选择器，选定后调 SearchViewModel.searchByDate 按日期检索。
   *  HUI-042（T-D07 三轮）：原 showDatePickerDialog 顶部标题区不可换肤（date_picker.d.ts:721
   *  DatePickerDialogOptions 全字段穷举无 title/header 样式项），按用户既定决策升级自绘
   *  ThemedDatePickerModal（shared）——内联系统 DatePicker 滚轮，交互不变，全量主题化；
   *  选中值处理（runDateSearch）与原 onDateAccept 完全一致。 */
  private openDatePicker(): void {
    this.showDatePicker = true;
  }

  /** HUI-001（七轮）：按日期检索——调 DEV 契约 searchByDate(YYYY-MM-DD)，映射复用现有结果列表渲染 */
  private async runDateSearch(dateStr: string): Promise<void> {
    try {
      if (!this.vmReady) {
        const ctx = getContext(this) as Context;
        await this.searchVm.init(ctx);
        this.vmReady = true;
      }
      const list: SearchResult[] = await this.searchVm.searchByDate(dateStr);
      const mapped: SearchResultItem[] = [];
      for (let i = 0; i < list.length; i++) {
        const r: SearchResult = list[i];
        const item: SearchResultItem = {
          id: i + 1,
          title: r.title,
          subtitle: r.snippet,
          sourceType: this.mapSourceType(r.sourceType),
          date: r.date
        };
        if (r.sourceType === SearchSourceType.TODO) {
          item.category = (r.data as TodoItem).category;
        }
        mapped.push(item);
      }
      this.keyword = '';
      this.dateQuery = dateStr;
      this.rawResults = mapped;
      this.applyFilters();
    } catch (e) {
      // 兜底：检索失败也进入日期模式显示空态，不崩
      this.keyword = '';
      this.dateQuery = dateStr;
      this.rawResults = [];
      this.results = [];
    }
  }

  /** 300ms 防抖：停止输入后调真实检索 */
  private debounceSearch(value: string): void {
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
    }
    if (value.trim().length === 0) {
      this.rawResults = [];
      this.results = [];
      return;
    }
    this.searchTimer = setTimeout(() => {
      this.runSearch();
    }, 300);
  }

  /** 执行搜索（提交/点击历史或热门时立即触发） */
  private executeSearch(keyword: string): void {
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
    }
    if (keyword.trim().length === 0) {
      return;
    }
    this.runSearch();
  }

  /** 在已检索结果上按类型分段 + 分类过滤（客户端，sourceType/category 可判） */
  private applyFilters(): void {
    this.openPanel = '';
    const filtered: SearchResultItem[] = [];
    for (let i = 0; i < this.rawResults.length; i++) {
      const item: SearchResultItem = this.rawResults[i];
      if (this.activeType !== 'all' && item.sourceType !== this.activeType) {
        continue;
      }
      if (this.selectedCategory.length > 0) {
        if (!item.category || item.category !== this.selectedCategory) {
          continue;
        }
      }
      filtered.push(item);
    }
    this.results = filtered;
  }

  /** 清空全部历史（SearchViewModel 持久化到 preferences） */
  private async clearAllHistory(): Promise<void> {
    try {
      await this.searchVm.clearHistory();
    } catch (e) {
      // 忽略清空失败
    }
    this.history = this.searchVm.getHistory();
  }

  /** 删除单条历史（会话级：VM 未暴露单条删除，重启后可能恢复，见交付降级说明） */
  private removeHistoryItem(index: number): void {
    if (index < 0 || index >= this.history.length) {
      return;
    }
    const next: string[] = [];
    for (let i = 0; i < this.history.length; i++) {
      if (i !== index) {
        next.push(this.history[i]);
      }
    }
    this.history = next;
  }
}
