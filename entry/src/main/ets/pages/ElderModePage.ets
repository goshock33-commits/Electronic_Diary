// <!-- agentID: DEV -->
// @Entry 长辈模式页「壳」：包装 features_elder_mode 的 ElderHomeView（内容主体），仅负责路由守卫 + 退出接线
// 入口链路：SettingsPage 长辈模式 Toggle 写 persist_elder_mode=1 → MainPage onPageShow 读键 replaceUrl 至本页
// 退出链路：本页「退出长辈模式」写回 0 → replaceUrl 回 MainPage（两侧均 replaceUrl 不压栈、无循环）
// 关联模块：features/elder-mode（HAR，§1.4 三者一致：features_elder_mode = 依赖 key = import 路径）
// 崩溃防范（PROJECT_SPEC §9）：字段初值无 $r()；@StorageLink tokens 判空兜底；无 getter-in-build 返回 Resource
// 适老化：退出按钮热区 >= 48vp、字号 18vp+；无青色（用户偏好），色值走 tokens 判空兜底中性色
// 开发范式：ArkTS 声明式开发范式（Stage 模型）

import type { ThemeColorTokens } from '@ohos/shared';
import { PersistentState } from '@ohos/shared';
import { ElderHomeView } from 'features_elder_mode';
import { router } from '@kit.ArkUI';

/** 兜底文字色（高对比近黑，tokens 未注入时使用） */
const FALLBACK_TEXT: string = '#1A1A1A';
/** 兜底按钮描边色（中性暖灰，无青色） */
const FALLBACK_BORDER: string = '#C9B8A0';

@Entry
@Component
struct ElderModePage {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  /** 语音监听态（占位：点击猫咪切换脉冲；真实语音会话接线归后续任务） */
  @State private isListening: boolean = false;

  /**
   * 对称守卫（与 MainPage onPageShow 成对）：键已归 0（如异常路径/外部改键）时替换回主页面，
   * 保证 persist_elder_mode 是「当前首页形态」的唯一真相源。
   */
  onPageShow(): void {
    const elderOn: number | undefined = AppStorage.get<number>(PersistentState.KEY_ELDER_MODE);
    if (elderOn !== 1) {
      router.replaceUrl({ url: 'pages/MainPage' }).catch(() => {
      });
    }
  }

  build() {
    Stack({ alignContent: Alignment.TopEnd }) {
      // 内容主体：features_elder_mode ElderHomeView（全屏渐变 + 居中语音猫 + 大字引导）
      ElderHomeView({
        isListening: this.isListening,
        onVoiceTap: () => {
          // 占位接线：切换监听态驱动脉冲动画；语音会话由后续任务接入
          this.isListening = !this.isListening;
        }
      })

      // 退出长辈模式（壳级最小接线：写回 0 + 替换回主页面；视觉细化归 HUI）
      Text('退出长辈模式')
        .fontSize(18)
        .fontWeight(FontWeight.Medium)
        .fontColor(this.tokens ? this.tokens.textPrimary : FALLBACK_TEXT)
        .padding({ left: 16, right: 16, top: 12, bottom: 12 }) // 热区 >= 48vp（适老化）
        .borderRadius(24)
        .border({ width: 1, color: this.tokens ? this.tokens.border : FALLBACK_BORDER })
        .margin({ top: 48, right: 20 })
        .onClick(() => {
          AppStorage.setOrCreate(PersistentState.KEY_ELDER_MODE, 0);
          router.replaceUrl({ url: 'pages/MainPage' }).catch(() => {
          });
        })
        .accessibilityText('退出长辈模式，返回普通首页')
    }
    .width('100%')
    .height('100%')
  }
}
