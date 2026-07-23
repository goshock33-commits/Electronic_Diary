// <!-- agentID: HUI-029 -->
// agentID: HUI-041（T-D05：添加按钮统一 — 空心描边圆圈+粗加号，热区提至 40vp）
// 组件：名言卡片（双引号装饰 + 名言文字 + 作者 + 淡入淡出切换动画）
// 功能：刷新按钮(SymbolGlyph shuffle)、关闭按钮、自定义名言添加入口、复制到剪贴板
// 关联设计稿：UX-001_prototype.html（quote-card）
// 关联任务：F14
// Skill 参考：frontend-design / ui-ux-pro-max / brainstorming
// 开发范式：ArkTS 声明式开发范式
// 无障碍：遵守 T042 规范（accessibilityText 不为空、触控热区 >= 48x48vp）
// Mock：10条内置中文名言，通过刷新按钮切换，同日不重复
//
// === 图标来源章节 ===
// 所有图标引用自 HarmonyOS SymbolGlyph 系统图标库，经 IconMapper 验证有效：
// | 图标资源                     | 用途             | 验证来源                                      |
// |------------------------------|------------------|-----------------------------------------------|
// | sys.symbol.shuffle           | 随机刷新名言     | IconMapper.RANDOM（已验证）                   |
// | sys.symbol.plus_circle_fill  | 添加自定义名言   | IconMapper.ADD（已验证）                      |
// | sys.symbol.xmark             | 关闭名言卡片     | IconMapper.CLOSE（已验证）                    |
// | sys.symbol.doc_on_doc        | 复制到剪贴板     | IconMapper.COPY（本次新增，已验证）            |
//
// === 华为文档引用章节 ===
// 核心组件参考：
//   - SymbolGlyph：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-basic-components-symbolglyph
//   - 状态管理（@State / @StorageLink）：https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-state-management
//   - Stack/Column/Row 容器：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/ts-container-stack
//   - 剪贴板 pasteboard：https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-pasteboard
// 设计指南参考：
//   - 卡片设计指南：https://developer.huawei.com/consumer/cn/doc/design-guides/design-concepts-0000001795698445
//   - Symbol 图标库：https://developer.huawei.com/consumer/cn/design/harmonyos-symbol/

import type { ThemeColorTokens } from '@ohos/shared';
// HUI-029：追加 SKETCH_BODY=清松手写体2（复制 toast + 作者署名等中文标签）；名言正文/装饰引号走 FONT.serif 保留不动。
import { IconMapper, RADIUS, FONT, ICON, SKETCH_BODY } from '@ohos/shared';
import { ClipboardUtils } from '@ohos/shared';
import { promptAction } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';

const TAG = 'QuoteCard';

/** 名言条目数据接口 */
interface QuoteItem {
  content: string;
  author: string;
}

/** Mock: 10条内置中文名言 */
const MOCK_QUOTES: QuoteItem[] = [
  { content: '千里之行，始于足下。', author: '老子' },
  { content: '学而不思则罔，思而不学则殆。', author: '孔子' },
  { content: '天行健，君子以自强不息。', author: '《周易》' },
  { content: '业精于勤，荒于嬉；行成于思，毁于随。', author: '韩愈' },
  { content: '宝剑锋从磨砺出，梅花香自苦寒来。', author: '《警世贤文》' },
  { content: '长风破浪会有时，直挂云帆济沧海。', author: '李白' },
  { content: '山重水复疑无路，柳暗花明又一村。', author: '陆游' },
  { content: '不以物喜，不以己悲。', author: '范仲淹' },
  { content: '穷则独善其身，达则兼济天下。', author: '孟子' },
  { content: '不忘初心，方得始终。', author: '《华严经》' }
];

/** 淡入淡出动画时长(ms) */
const FADE_DURATION: number = 300;

@Component
export struct QuoteCard {
  /** 当前显示的名言内容 */
  @State private quoteContent: string = '';
  /** 当前显示的作者 */
  @State private quoteAuthor: string = '';
  /** 淡出动画状态：true=文字半透明 */
  @State private isFadingOut: boolean = false;
  /** 卡片可见性（关闭后隐藏） */
  @State private isVisible: boolean = true;
  /** 复制反馈 toast 文本（空=不显示） */
  @State private copyToast: string = '';

  /** 主题色令牌 */
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;

  /** 关闭卡片回调（由父页面处理） */
  onCloseCard?: () => void;
  /** 添加自定义名言回调 */
  onAddCustom?: () => void;

  /** 今日已展示的名言索引列表（同日不重复） */
  private shownIndicesToday: number[] = [];
  /** 今日日期字符串 YYYY-MM-DD */
  private todayDateStr: string = '';
  /** 当前名言在 MOCK_QUOTES 中的索引 */
  private currentIndex: number = -1;
  /** 刷新淡出定时器 id（-1=无），卸载时清理防 setState-after-unmount */
  private refreshTimerId: number = -1;
  /** 复制 toast 自动消失定时器 id（-1=无） */
  private toastTimerId: number = -1;

  // ── 生命周期 ────────────────────────────────────────

  aboutToAppear(): void {
    this.todayDateStr = this.computeTodayStr();
    this.pickRandomQuote();
  }

  aboutToDisappear(): void {
    if (this.refreshTimerId !== -1) {
      clearTimeout(this.refreshTimerId);
      this.refreshTimerId = -1;
    }
    if (this.toastTimerId !== -1) {
      clearTimeout(this.toastTimerId);
      this.toastTimerId = -1;
    }
  }

  // ── UI 构建 ────────────────────────────────────────

  build() {
    if (!this.isVisible) {
      // 卡片被关闭，返回空节点
      Column() {}
    } else {
      Column() {
        // 复制成功 toast（轻提示）
        if (this.copyToast.length > 0) {
          Row() {
            Text(this.copyToast)
              .fontSize(12)
              .fontColor(Color.White)
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .attributeModifier(SKETCH_BODY) // HUI-029：复制提示 toast→清松手写体2
          }
          .borderRadius(20)
          .backgroundColor('rgba(0, 0, 0, 0.75)')
          .margin({ bottom: 8 })
          .alignSelf(ItemAlign.Center)
          .transition(
            TransitionEffect.OPACITY
              .animation({ duration: 200, curve: Curve.EaseInOut })
              .combine(TransitionEffect.translate({ y: -8 })
                .animation({ duration: 200, curve: Curve.EaseInOut }))
          )
        }

        // ═══════════════════════════════════
        // 引号装饰 + 名言正文
        // ═══════════════════════════════════
        Stack({ alignContent: Alignment.TopStart }) {
          // 装饰左双引号（青色 serif 引号，P1-07）
          Text('“')
            .fontSize(64)
            .fontFamily(FONT.serif)
            .fontColor(this.tokens ? this.tokens.primary : '#00C2B8')
            .opacity(0.22)
            .fontWeight(FontWeight.Bold)
            .position({ left: -4, top: -10 })
            .accessibilityLevel('no')

          // 装饰右双引号（放置于右下角）
          Text('”')
            .fontSize(64)
            .fontFamily(FONT.serif)
            .fontColor(this.tokens ? this.tokens.primary : '#00C2B8')
            .opacity(0.22)
            .fontWeight(FontWeight.Bold)
            .position({ right: -4, bottom: -20 })
            .accessibilityLevel('no')

          // 名言正文（serif 斜体）
          Text(this.quoteContent)
            .fontSize(17)
            .lineHeight(26)
            .fontFamily(FONT.serif)
            .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
            .fontStyle(FontStyle.Italic)
            .width('100%')
            .padding({ left: 24, right: 24, top: 6 })
            .maxLines(4)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .opacity(this.isFadingOut ? 0.3 : 1.0)
            .animation({ duration: FADE_DURATION, curve: Curve.EaseInOut })
        }
        .width('100%')

        // 作者署名行
        if (this.quoteAuthor.length > 0 && this.quoteAuthor !== '未知') {
          Text('—— ' + this.quoteAuthor)
            .fontSize(13)
            .fontColor(this.tokens ? this.tokens.textSecondary : '#8A9B8A')
            .width('100%')
            .textAlign(TextAlign.End)
            .margin({ top: 10, right: 4 })
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .attributeModifier(SKETCH_BODY) // HUI-029：作者署名（中文标签）→清松手写体2；名言正文 serif 保留
        }

        // ═══════════════════════════════════
        // 底部操作栏
        // ═══════════════════════════════════
        Row() {
          // 刷新 / 随机名言按钮
          Button() {
            SymbolGlyph(IconMapper.RANDOM)
              .fontSize(15)
              .fontColor([this.tokens ? this.tokens.textTertiary : '#B0B0B0'])
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.handleRefresh();
          })
          .accessibilityText('随机更换名言')

          // 复制到剪贴板按钮
          Button() {
            SymbolGlyph(IconMapper.COPY)
              .fontSize(15)
              .fontColor([this.tokens ? this.tokens.textTertiary : '#B0B0B0'])
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor(Color.Transparent)
          .margin({ left: 2 })
          .onClick(() => {
            this.handleCopyToClipboard();
          })
          .accessibilityText('复制名言到剪贴板')

          // 添加自定义名言按钮（HUI-041：空心描边圆圈 + 粗加号，热区 ≥40vp）
          Button() {
            Stack() {
              SymbolGlyph(IconMapper.PLUS)
                .fontSize(ICON.plus)
                .fontWeight(FontWeight.Bold)
                .fontColor([this.tokens ? this.tokens.textTertiary : '#B0B0B0'])
            }
            .width(ICON.plusRing)
            .height(ICON.plusRing)
            .borderRadius(ICON.plusRing / 2)
            .border({
              width: ICON.ringStroke,
              color: this.tokens ? this.tokens.textTertiary : '#B0B0B0'
            })
          }
          .width(ICON.touchTarget)
          .height(ICON.touchTarget)
          .borderRadius(ICON.touchTarget / 2)
          .backgroundColor(Color.Transparent)
          .margin({ left: 2 })
          .onClick(() => {
            if (this.onAddCustom) {
              this.onAddCustom();
            }
          })
          .accessibilityText('添加自定义名言')

          Blank()

          // 关闭按钮
          Button() {
            SymbolGlyph(IconMapper.CLOSE)
              .fontSize(15)
              .fontColor([this.tokens ? this.tokens.textTertiary : '#B0B0B0'])
          }
          .width(36)
          .height(36)
          .borderRadius(18)
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            if (this.onCloseCard) {
              this.onCloseCard();
            } else {
              // 默认行为：隐藏卡片
              this.isVisible = false;
            }
          })
          .accessibilityText('关闭名言卡片')
        }
        .width('100%')
        .margin({ top: 10 })
      }
      .width('100%')
      .borderRadius(RADIUS.card)
      .padding({ left: 20, right: 20, top: 18, bottom: 16 })
      // 暖白纸感卡（P1-07：名言卡暖白变体 #FAF8F5）
      .backgroundColor(this.tokens ?
        this.tokens.bg :
        '#FAF8F5')
      .backdropBlur(10)
      .border({
        width: 0.5,
        color: this.tokens ? this.tokens.border : 'rgba(76, 175, 80, 0.12)'
      })
      .shadow({
        radius: 16,
        color: this.tokens ? this.tokens.shadow : 'rgba(76, 175, 80, 0.06)',
        offsetX: 0,
        offsetY: 4
      })
      .accessibilityGroup(true)
      .accessibilityText('名言卡片：' + this.quoteContent + ' —— ' + this.quoteAuthor)
      .animation({ duration: FADE_DURATION, curve: Curve.EaseInOut })

      // toast 自动消失定时器
      .onDisAppear(() => {
        this.copyToast = '';
      })
    }
  }

  // ── 业务逻辑 ────────────────────────────────────────

  /**
   * 刷新名言：先淡出 → 更新内容 → 恢复
   * 同日不重复逻辑：优先选取今日未展示过的名言
   */
  private handleRefresh(): void {
    // 1. 淡出
    this.isFadingOut = true;

    this.refreshTimerId = setTimeout(() => {
      this.refreshTimerId = -1;
      // 2. 选取新名言
      this.pickRandomQuote();
      // 3. 淡入
      this.isFadingOut = false;
    }, FADE_DURATION);
  }

  /**
   * 复制当前名言到剪贴板，并显示 toast 反馈
   */
  private async handleCopyToClipboard(): Promise<void> {
    try {
      const copyText = `${this.quoteContent} —— ${this.quoteAuthor}`;
      const success = await ClipboardUtils.setText(copyText);
      if (success) {
        this.showCopyToast();
      }
    } catch (err) {
      hilog.error(0x0000, TAG, 'Copy to clipboard failed: %{public}s', (err as Error).message);
    }
  }

  /**
   * 显示"已复制"轻提示（2秒后自动消失）
   */
  private showCopyToast(): void {
    this.copyToast = '已复制';
    this.toastTimerId = setTimeout(() => {
      this.toastTimerId = -1;
      this.copyToast = '';
    }, 2000);
  }

  /**
   * 随机选取一条名言
   * 同日不重复：优先选取今日尚未展示过的索引
   * 若全部已展示，则清空记录重新开始
   */
  private pickRandomQuote(): void {
    // 校验日期是否跨天，若跨天则清空已展示记录
    const currentDateStr = this.computeTodayStr();
    if (currentDateStr !== this.todayDateStr) {
      this.todayDateStr = currentDateStr;
      this.shownIndicesToday = [];
    }

    // 收集今日尚未展示的索引
    const availableIndices: number[] = [];
    for (let i = 0; i < MOCK_QUOTES.length; i++) {
      if (!this.shownIndicesToday.includes(i)) {
        availableIndices.push(i);
      }
    }

    // 若全部已展示，重置
    if (availableIndices.length === 0) {
      this.shownIndicesToday = [];
      for (let i = 0; i < MOCK_QUOTES.length; i++) {
        availableIndices.push(i);
      }
    }

    // 从可用索引中随机选取一个
    const randomIndex: number = Math.floor(Math.random() * availableIndices.length);
    const selectedIndex: number = availableIndices[randomIndex];

    // 排除当前正显示的索引（确保刷新时一定会变化）
    if (availableIndices.length > 1 && selectedIndex === this.currentIndex) {
      // 选取另一个
      const nextIndex: number = (randomIndex + 1) % availableIndices.length;
      const fallbackIndex: number = availableIndices[nextIndex];
      this.currentIndex = fallbackIndex;
      this.shownIndicesToday.push(fallbackIndex);
    } else {
      this.currentIndex = selectedIndex;
      this.shownIndicesToday.push(selectedIndex);
    }

    const quote = MOCK_QUOTES[this.currentIndex];
    this.quoteContent = quote.content;
    this.quoteAuthor = quote.author;
  }

  /**
   * 获取当前日期字符串 YYYY-MM-DD
   */
  private computeTodayStr(): string {
    const d: Date = new Date();
    const year: number = d.getFullYear();
    const month: string = String(d.getMonth() + 1).padStart(2, '0');
    const day: string = String(d.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }
}
