// <!-- agentID: DEV-011 -->
// <!-- agentID: HUI-069 -->
// <!-- agentID: HUI-049 -->
// 页面组件：家庭成员管理（成员列表 + 添加按钮 + 昵称编辑弹窗 + 家庭邀请码卡片）
// 归属：features_family（纯 UI 内容主体，页面壳在 entry/pages/FamilyPage.ets）
// §1.4 三者一致：模块 name = features_family = 依赖 key = import 路径
// 交互约定（用户偏好）：点击成员行即编辑昵称（点击即编辑，无独立编辑按钮）
// 令牌：IconMapper / RADIUS / SPACING / TYPO —— 全引用，禁散写魔数
// 主题：HarmonyOS 蓝白卡片风格（primary=#0A59F7, bg=#F5F7FA, bgCard=#FFFFFF, accent=#EBF5FF）
// T707(DEV-011): aliases 显示逻辑 —— 成员列表显示名 = myAliases[member.uid] ?? member.nickname
//
// === 崩溃防范（PROJECT_SPEC §9）===
//   §9.1 无 getter-in-build
//   §9.4 @StorageLink tokens 读取全部判空兜底
//
// === 图标来源章节 ===
// | 图标资源                | 用途       | 验证来源                       |
// |-------------------------|------------|--------------------------------|
// | sys.symbol.person       | 成员头像   | IconMapper.NAV_PROFILE（已验） |
// | sys.symbol.plus         | 添加按钮   | IconMapper.PLUS（已验）        |
// | sys.symbol.chevron_right| 行尾箭头   | IconMapper.FORWARD（已验）     |
// | sys.symbol.doc_text_fill| 复制邀请码 | IconMapper.COPY（已验）        |

import type { ThemeColorTokens } from '@ohos/shared';
import { IconMapper, RADIUS, SPACING, TYPO, SKETCH_TITLE, SKETCH_BODY, ClipboardUtils } from '@ohos/shared';
import { promptAction, router } from '@kit.ArkUI';
import type { FamilyMember } from '@ohos/shared';
import { FamilyViewModel } from '../viewmodel/FamilyViewModel';
import { MemberNicknameModal } from '../components/MemberNicknameModal';
import { InviteCodeModal } from '../components/InviteCodeModal';

/** 状态标签浅绿底色（tokens.success #52C41A 的浅色背景） */
const STATUS_GREEN_BG: string = '#E8F5E9';

@Component
export struct FamilyPage {
  @StorageLink('theme_tokens') tokens: ThemeColorTokens | null = null;
  /** 成员列表（从 VM 拉副本，改动后整体重赋值驱动刷新） */
  @State private members: FamilyMember[] = [];
  /** T707: 我对别人的备注映射（targetUid → alias），用于成员列表显示名 */
  @State private myAliases: Record<string, string> = {};
  /** 昵称弹窗显隐 */
  @State private showNicknameModal: boolean = false;
  /** 邀请码输入弹窗显隐 */
  @State private showInviteModal: boolean = false;
  /** 本家庭邀请码（'' = 尚未生成） */
  @State private myInviteCode: string = '';
  /** 已加入的家庭邀请码（'' = 未加入） */
  @State private joinedInviteCode: string = '';
  /** 当前编辑的成员 ID（-1 = 添加新成员） */
  @State private editingId: number = -1;
  /** 弹窗回显昵称（添加态为空） */
  @State private editingName: string = '';
  /** T707: 当前编辑的是否为自己（用于区分弹窗标题「编辑昵称」vs「编辑备注」） */
  @State private editingIsSelf: boolean = false;
  /** HUI-058：是否已登录（HUI-LOGIN：未登录时点击任意功能按钮直接跳转登录页，不再禁点） */
  @StorageProp('account_logged_in') isLoggedIn: boolean = false;

  async aboutToAppear(): Promise<void> {
    this.members = await FamilyViewModel.getMembers();
    // T707: 加载我的 aliases 映射（用于成员列表显示名）
    this.myAliases = await FamilyViewModel.getMyAliases();
    this.myInviteCode = await FamilyViewModel.getMyInviteCode();
    this.joinedInviteCode = FamilyViewModel.getJoinedInviteCode();
  }

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        Scroll() {
          Column() {
            // ── 分组标题 ──
            this.buildCardTitle('FAMILY MEMBERS', '成员列表')

            // ── 成员列表（每成员独立白卡） ──
            if (this.members.length === 0) {
              // 空态：引导添加
              Column() {
                SymbolGlyph(IconMapper.NAV_PROFILE)
                  .fontSize(36)
                  .fontColor([this.tokens ? this.tokens.textTertiary : '#CCCCCC'])
                  .margin({ bottom: 10 })
                Text('还没有家庭成员')
                  .fontSize(TYPO.body.size)
                  .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
                  .attributeModifier(SKETCH_BODY)
                Text('点击下方按钮添加第一位家人')
                  .fontSize(TYPO.eyebrow.size)
                  .fontColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
                  .margin({ top: 4 })
                  .attributeModifier(SKETCH_BODY)
              }
              .width('100%')
              .padding({ top: 28, bottom: 28 })
              .borderRadius(RADIUS.card)
              .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
              .alignItems(HorizontalAlign.Center)
              .accessibilityText('还没有家庭成员，点击下方按钮添加第一位家人')
            } else {
              ForEach(this.members, (member: FamilyMember, index: number) => {
                this.buildMemberCard(member)
                if (index < this.members.length - 1) {
                  Blank().height(SPACING.cardGap)
                }
              }, (member: FamilyMember) => member.id + '_' + member.nickname)
            }

            // ── 添加成员区域（accent 浅蓝底） ──
            this.buildAddMemberArea()

            // ── HUI-058：未登录提示 ──
            if (!this.isLoggedIn) {
              Text('请先登录')
                .fontSize(TYPO.eyebrow.size)
                .fontColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
                .width('100%')
                .textAlign(TextAlign.Center)
                .margin({ top: SPACING.sectionGap, bottom: 8 })
                .attributeModifier(SKETCH_BODY)
            }

            // ── 家庭邀请码卡片（生成/展示复制/输码加入三态）──
            Column() {
              // HUI-058：未登录提示
              if (!this.isLoggedIn) {
                Text('请先登录后使用邀请码功能')
                  .fontSize(TYPO.eyebrow.size)
                  .fontColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
                  .width('100%')
                  .textAlign(TextAlign.Center)
                  .margin({ bottom: 12 })
                  .attributeModifier(SKETCH_BODY)
              }
              this.buildCardTitle('FAMILY INVITE', '家庭邀请码')
              this.buildInviteSection()
            }
            .width('100%')
            .borderRadius(RADIUS.card)
            .padding(SPACING.cardPadMd)
            .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
            .border({ width: 1, color: this.tokens ? this.tokens.border : '#E0E6ED' })
            .shadow({
              radius: 12,
              color: this.tokens ? this.tokens.shadow : 'rgba(0,0,0,0.06)',
              offsetX: 0,
              offsetY: 4
            })
            .alignItems(HorizontalAlign.Start)
            .margin({ top: SPACING.sectionGap })
            .opacity(this.isLoggedIn ? 1.0 : 0.5)
            .onClick(() => {
              if (!this.ensureLoggedIn()) {
                this.gotoLogin();
              }
            })
          }
          .width('100%')
        }
        .width('100%')
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.Spring)
        .align(Alignment.Top)
      }
      .width('100%')
      .height('100%')

      // ── 昵称编辑弹窗（添加 / 编辑两用，条件渲染保证每次打开重建回显） ──
      if (this.showNicknameModal) {
        MemberNicknameModal({
          titleText: this.editingId === -1 ? '添加成员' : (this.editingIsSelf ? '编辑昵称' : '编辑备注'),
          hintText: this.editingId === -1 ? '给新家人起个亲切的称呼'
            : (this.editingIsSelf ? '修改自己的称呼' : '修改对这位家人的备注'),
          initialName: this.editingName,
          onConfirm: (name: string) => {
            this.applyNickname(name);
          },
          onCancel: () => {
            this.showNicknameModal = false;
          }
        })
      }

      // ── 邀请码输入弹窗（条件渲染，每次打开重建清空输入） ──
      if (this.showInviteModal) {
        InviteCodeModal({
          onConfirm: (code: string) => {
            this.applyJoinFamily(code);
          },
          onCancel: () => {
            this.showInviteModal = false;
          }
        })
      }
    }
    .width('100%')
    .height('100%')
  }

  // ── 分组标题 ──
  @Builder
  buildCardTitle(en: string, cn: string) {
    Column() {
      Text(en)
        .fontSize(9)
        .fontWeight(800)
        .fontColor(this.tokens ? this.tokens.primary : '#0A59F7')
        .opacity(0.7)
        .letterSpacing(2)
        .attributeModifier(SKETCH_TITLE)
      Text(cn)
        .fontSize(TYPO.cardTitle.size)
        .fontWeight(700)
        .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
        .margin({ top: 2 })
        .attributeModifier(SKETCH_TITLE)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ bottom: 12 })
    .accessibilityText(cn)
  }

  // ── 成员卡片：独立白卡（头像圆 + 显示名 + 角色 + 状态标签） ──
  @Builder
  buildMemberCard(member: FamilyMember) {
    // T707: 显示名逻辑 —— 自己看自己的 nickname；看别人时优先取我对他的备注
    Row() {
      // 48vp 头像圆（accent 浅蓝底 + person 图标）
      Stack() {
        SymbolGlyph(IconMapper.NAV_PROFILE)
          .fontSize(24)
          .fontColor([this.tokens ? this.tokens.primary : '#0A59F7'])
      }
      .width(48)
      .height(48)
      .borderRadius(24)
      .backgroundColor(this.tokens ? this.tokens.accent : '#EBF5FF')
      .margin({ right: 12 })

      // 中间：显示名 + 角色
      Column() {
        Text(member.isSelf() ? member.nickname : this.getDisplayName(member))
          .fontSize(TYPO.cardTitle.size)
          .fontWeight(TYPO.cardTitle.weight)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .attributeModifier(SKETCH_BODY)
        Text('家庭成员')
          .fontSize(TYPO.eyebrow.size)
          .fontColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
          .margin({ top: 2 })
          .attributeModifier(SKETCH_BODY)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      // 右侧：状态标签（浅绿底 + 绿字「手表已连接」）
      Row() {
        Text('手表已连接')
          .fontSize(TYPO.eyebrow.size)
          .fontWeight(500)
          .fontColor(this.tokens ? this.tokens.success : '#52C41A')
          .attributeModifier(SKETCH_BODY)
      }
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .borderRadius(RADIUS.input)
      .backgroundColor(STATUS_GREEN_BG)
    }
    .width('100%')
    .height(64)
    .padding({ left: SPACING.cardPadSm, right: SPACING.cardPadSm })
    .borderRadius(RADIUS.card)
    .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
    .border({ width: 1, color: this.tokens ? this.tokens.border : '#E0E6ED' })
    .shadow({
      radius: 12,
      color: this.tokens ? this.tokens.shadow : 'rgba(0,0,0,0.06)',
      offsetX: 0,
      offsetY: 4
    })
    .alignItems(VerticalAlign.Center)
    .onClick(() => {
      this.openEditModal(member);
    })
    .accessibilityText('家庭成员：' + (member.isSelf() ? member.nickname : this.getDisplayName(member)) + (member.isSelf() ? '，点击编辑昵称' : '，点击编辑备注'))
  }

  // ── 添加成员区域（accent 浅蓝底 + 加号 + 文案） ──
  @Builder
  buildAddMemberArea() {
    Row() {
      SymbolGlyph(IconMapper.PLUS)
        .fontSize(18)
        .fontWeight(FontWeight.Bold)
        .fontColor([this.tokens ? this.tokens.primary : '#0A59F7'])
        .margin({ right: 8 })
      Text('添加家庭成员')
        .fontSize(TYPO.body.size)
        .fontWeight(600)
        .fontColor(this.tokens ? this.tokens.primary : '#0A59F7')
        .attributeModifier(SKETCH_BODY)
    }
    .width('100%')
    .height(48)
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .borderRadius(RADIUS.card)
    .backgroundColor(this.tokens ? this.tokens.accent : '#EBF5FF')
    .margin({ top: SPACING.sectionGap })
    .opacity(this.isLoggedIn ? 1.0 : 0.5)
    .onClick(() => {
      if (!this.ensureLoggedIn()) {
        this.gotoLogin();
        return;
      }
      this.showInviteModal = true;
    })
    .accessibilityText('添加家庭成员')
  }

  /**
   * T707: 获取成员显示名（非自己的成员）。
   * 优先取我对他设置的备注（myAliases[uid]），无备注则显示他自己的 nickname。
   */
  private getDisplayName(member: FamilyMember): string {
    if (member.uid === null) {
      return member.nickname;
    }
    const alias: string = this.myAliases[member.uid];
    if (alias !== undefined && alias.length > 0) {
      return alias;
    }
    return member.nickname;
  }

  // ── 邀请码区块：三态（已生成展示复制 / 已加入状态 / 空态双按钮） ──
  @Builder
  buildInviteSection() {
    if (this.myInviteCode.length > 0) {
      // 态一：已生成 —— 大号展示 + 点击即复制 + 复制按钮
      Column() {
        Text(this.myInviteCode)
          .fontSize(30)
          .fontWeight(800)
          .letterSpacing(8)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .attributeModifier(SKETCH_TITLE)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 14, bottom: 14 })
          .borderRadius(RADIUS.item)
          .backgroundColor(this.tokens ? this.tokens.accent : '#EBF5FF')
          .border({
            width: 1,
            color: this.tokens ? this.tokens.border : '#E0E6ED',
            style: BorderStyle.Dashed
          })
          .onClick(() => {
            if (!this.ensureLoggedIn()) {
              this.gotoLogin();
              return;
            }
            this.copyInviteCode();
          })
          .accessibilityText('家庭邀请码 ' + this.myInviteCode + '，点击复制')

        Text('分享给家人，输入后即可加入你的家庭')
          .fontSize(TYPO.eyebrow.size)
          .fontColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
          .margin({ top: 8 })
          .attributeModifier(SKETCH_BODY)

        Button() {
          Row() {
            SymbolGlyph(IconMapper.COPY)
              .fontSize(16)
              .fontColor([this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF'])
              .margin({ right: 8 })
            Text('复制邀请码')
              .fontSize(TYPO.body.size)
              .fontWeight(600)
              .fontColor(this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
              .attributeModifier(SKETCH_BODY)
          }
          .alignItems(VerticalAlign.Center)
          .justifyContent(FlexAlign.Center)
        }
        .width('100%')
        .height(48)
        .borderRadius(RADIUS.item)
        .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#0A59F7')
        .margin({ top: 12 })
        .onClick(() => {
          if (!this.ensureLoggedIn()) {
            this.gotoLogin();
            return;
          }
          this.copyInviteCode();
        })
        .accessibilityText('复制邀请码')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    } else if (this.joinedInviteCode.length > 0) {
      // 态二：已通过邀请码加入他人家庭
      Column() {
        Text('已加入家庭')
          .fontSize(TYPO.body.size)
          .fontWeight(600)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .attributeModifier(SKETCH_BODY)
        Text('邀请码：' + this.joinedInviteCode)
          .fontSize(TYPO.eyebrow.size)
          .fontColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
          .margin({ top: 4 })
          .attributeModifier(SKETCH_BODY)
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
      .accessibilityText('已加入家庭，邀请码 ' + this.joinedInviteCode)
    } else {
      // 态三：空态 —— 生成邀请码 / 输码加入 双按钮
      Column() {
        Text('创建家庭生成邀请码，或输入家人的邀请码加入')
          .fontSize(TYPO.eyebrow.size)
          .fontColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
          .margin({ bottom: 12 })
          .attributeModifier(SKETCH_BODY)

        Row() {
          Button('生成邀请码')
            .fontSize(TYPO.body.size)
            .fontWeight(600)
            .fontColor(this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF')
            .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#0A59F7')
            .layoutWeight(1)
            .height(48)
            .borderRadius(RADIUS.item)
            .onClick(() => {
              if (!this.ensureLoggedIn()) {
                this.gotoLogin();
                return;
              }
              this.generateInviteCode();
            })
            .accessibilityText('生成家庭邀请码')

          Button('输码加入')
            .fontSize(TYPO.body.size)
            .fontWeight(500)
            .fontColor(this.tokens ? this.tokens.textSecondary : '#5A5A5A')
            .backgroundColor(this.tokens ? this.tokens.surface : '#F7F7F7')
            .border({ width: 1, color: this.tokens ? this.tokens.border : '#E0E6ED' })
            .layoutWeight(1)
            .height(48)
            .borderRadius(RADIUS.item)
            .margin({ left: 12 })
            .onClick(() => {
              if (!this.ensureLoggedIn()) {
                this.gotoLogin();
                return;
              }
              this.showInviteModal = true;
            })
            .accessibilityText('输入邀请码加入家庭')
        }
        .width('100%')
      }
      .width('100%')
      .alignItems(HorizontalAlign.Start)
    }
  }

  /** 打开添加成员弹窗 */
  private openAddModal(): void {
    this.editingId = -1;
    this.editingName = '';
    this.editingIsSelf = false;
    this.showNicknameModal = true;
  }

  /** T707: 打开编辑弹窗。自己回显 nickname；他人回显我对他的备注（无备注则回显他的 nickname）。 */
  private openEditModal(member: FamilyMember): void {
    this.editingId = member.id;
    this.editingIsSelf = member.isSelf();
    if (member.isSelf()) {
      this.editingName = member.nickname;
    } else {
      const uid: string | null = member.uid;
      if (uid !== null) {
        const aliasVal: string = this.myAliases[uid];
        this.editingName = aliasVal !== undefined && aliasVal.length > 0 ? aliasVal : member.nickname;
      } else {
        this.editingName = member.nickname;
      }
    }
    this.showNicknameModal = true;
  }

  /** T707: 弹窗保存。添加态入列表；编辑态：自己改昵称，他人设备注（走 setAlias）。VM 落储后整体拉副本刷新。 */
  private async applyNickname(name: string): Promise<void> {
    if (this.editingId === -1) {
      // 添加新成员
      await FamilyViewModel.addMember(name);
    } else {
      const targetMember = this.findMemberById(this.editingId);
      if (targetMember !== null && targetMember.isSelf()) {
        await FamilyViewModel.updateNickname(this.editingId, name);
      } else if (targetMember !== null && targetMember.uid !== null) {
        await FamilyViewModel.setAlias(targetMember.uid, name);
      } else {
        await FamilyViewModel.updateNickname(this.editingId, name);
      }
    }
    this.myAliases = await FamilyViewModel.getMyAliases();
    if (this.editingId === -1) {
      this.members = await FamilyViewModel.getMembers();
    }
    this.showNicknameModal = false;
  }

  /** 按 id 查找成员 */
  private findMemberById(id: number): FamilyMember | null {
    for (let i = 0; i < this.members.length; i++) {
      if (this.members[i].id === id) {
        return this.members[i];
      }
    }
    return null;
  }

  /** 生成本家庭邀请码 */
  private async generateInviteCode(): Promise<void> {
    this.myInviteCode = await FamilyViewModel.generateInviteCode();
    promptAction.showToast({ message: '邀请码已生成，分享给家人吧', duration: 1500 });
  }

  /** 复制邀请码到剪贴板 */
  private copyInviteCode(): void {
    if (this.myInviteCode.length === 0) {
      return;
    }
    ClipboardUtils.setText(this.myInviteCode).then((ok: boolean) => {
      promptAction.showToast({
        message: ok ? '邀请码已复制' : '复制失败，请重试',
        duration: 1500
      });
    });
  }

  /** 弹窗确认：通过邀请码加入家庭 */
  private async applyJoinFamily(code: string): Promise<void> {
    const err: string = await FamilyViewModel.joinFamily(code);
    if (err.length === 0) {
      this.joinedInviteCode = FamilyViewModel.getJoinedInviteCode();
      this.showInviteModal = false;
      this.openAddModal();
    } else {
      promptAction.showToast({ message: err, duration: 2000 });
      this.showInviteModal = false;
    }
  }

  /** HUI-LOGIN：读取登录态 */
  private ensureLoggedIn(): boolean {
    return this.isLoggedIn;
  }

  /** HUI-LOGIN：跳转账号登录页 */
  private gotoLogin(): void {
    router.pushUrl({ url: 'pages/LoginPage' }).catch(() => {
    });
  }
}
