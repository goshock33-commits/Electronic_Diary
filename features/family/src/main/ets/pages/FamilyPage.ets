// <!-- agentID: DEV-011 -->
// <!-- agentID: HUI-069 -->
// <!-- agentID: HUI-049 -->
// 页面组件：家庭成员管理（成员列表 + 添加按钮 + 昵称编辑弹窗 + 家庭邀请码卡片）
// 归属：features_family（纯 UI 内容主体，页面壳在 entry/pages/FamilyPage.ets）
// §1.4 三者一致：模块 name = features_family = 依赖 key = import 路径
// 交互约定（用户偏好）：点击成员行即编辑昵称（点击即编辑，无独立编辑按钮）
// 令牌：IconMapper / RADIUS / SPACING / TYPO —— 全引用，禁散写魔数
// T707(DEV-011): aliases 显示逻辑 —— 成员列表显示名 = myAliases[member.uid] ?? member.nickname；自己看自己的 nickname
//
// === 崩溃防范（PROJECT_SPEC §9）===
//   §9.1 无 getter-in-build
//   §9.4 @StorageLink tokens 读取全部判空兜底（黑白手绘风格中性兜底，无青色死值）
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
// HUI-LOGIN：未登录点击任意功能入口 → router 直跳 pages/LoginPage（entry main_pages.json 已注册）
import { promptAction, router } from '@kit.ArkUI';
import type { FamilyMember } from '@ohos/shared';
import { FamilyViewModel } from '../viewmodel/FamilyViewModel';
import { MemberNicknameModal } from '../components/MemberNicknameModal';
import { InviteCodeModal } from '../components/InviteCodeModal';

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
            // ── 成员列表卡片 ──
            Column() {
              this.buildCardTitle('FAMILY MEMBERS', '成员列表')

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
                .accessibilityText('还没有家庭成员，点击下方按钮添加第一位家人')
              } else {
                ForEach(this.members, (member: FamilyMember, index: number) => {
                  if (index > 0) {
                    Divider()
                      .strokeWidth(0.5)
                      .color(this.tokens ? this.tokens.divider : '#E0E0E0')
                  }
                  this.buildMemberRow(member)
                }, (member: FamilyMember) => member.id + '_' + member.nickname)
              }
            }
            .width('100%')
            .borderRadius(RADIUS.cardLg)
            .padding(SPACING.cardPadMd)
            .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
            .border({ width: 1, color: this.tokens ? this.tokens.border : '#CCCCCC' })
            .shadow({
              radius: 12,
              color: this.tokens ? this.tokens.shadow : 'rgba(0,0,0,0.08)',
              offsetX: 0,
              offsetY: 4
            })
            .alignItems(HorizontalAlign.Start)

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

            // ── 添加成员按钮 ──
            Button() {
              Row() {
                SymbolGlyph(IconMapper.PLUS)
                  .fontSize(18)
                  .fontWeight(FontWeight.Bold)
                  .fontColor([this.tokens ? this.tokens.btnPrimaryText : '#FFFFFF'])
                  .margin({ right: 8 })
                Text('加入家庭')
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
            .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#738A9C')
            .margin({ top: this.isLoggedIn ? SPACING.sectionGap : 0 })
            .opacity(this.isLoggedIn ? 1.0 : 0.4)
            .onClick(() => {
              // HUI-LOGIN：未登录点击直接跳转登录页（原 .enabled 禁点已移除）
              if (!this.ensureLoggedIn()) {
                this.gotoLogin();
                return;
              }
              this.showInviteModal = true;
            })
            .accessibilityText('通过邀请码加入家庭')

            // ── 家庭邀请码卡片（生成/展示复制/输码加入三态）──
            // HUI-058：未登录时整卡半透明置灰
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
            .borderRadius(RADIUS.cardLg)
            .padding(SPACING.cardPadMd)
            .backgroundColor(this.tokens ? this.tokens.bgCard : '#FFFFFF')
            .border({ width: 1, color: this.tokens ? this.tokens.border : '#CCCCCC' })
            .shadow({
              radius: 12,
              color: this.tokens ? this.tokens.shadow : 'rgba(0,0,0,0.08)',
              offsetX: 0,
              offsetY: 4
            })
            .alignItems(HorizontalAlign.Start)
            .margin({ top: SPACING.sectionGap })
            .opacity(this.isLoggedIn ? 1.0 : 0.5)
            // HUI-LOGIN：未登录不再 HitTestMode.None 屏蔽点击 —— 整卡可点，点击跳转登录页（卡内按钮各自守卫）
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
      // T707: 自己改昵称 vs 给他人设备注，标题/提示区分
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

  // ── 分组标题（复刻 settings buildCardTitle 风格） ──
  @Builder
  buildCardTitle(en: string, cn: string) {
    Column() {
      Text(en)
        .fontSize(9)
        .fontWeight(800)
        .fontColor(this.tokens ? this.tokens.primary : '#000000')
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

  // ── 成员行：头像圆 + 显示名（T707: 自己看自己的 nickname，别人看 alias ?? nickname） + 编辑提示 + 箭头 ──
  @Builder
  buildMemberRow(member: FamilyMember) {
    // T707: 显示名逻辑 —— 自己看自己的 nickname；看别人时优先取我对他的备注
    Row() {
      // 40vp 头像圆（surface 底 + 铅笔灰描边 + person 图标）
      Stack() {
        SymbolGlyph(IconMapper.NAV_PROFILE)
          .fontSize(20)
          .fontColor([this.tokens ? this.tokens.textPrimary : '#1A1A1A'])
      }
      .width(40)
      .height(40)
      .borderRadius(20)
      .backgroundColor(this.tokens ? this.tokens.surface : '#F7F7F7')
      .border({ width: 1, color: this.tokens ? this.tokens.border : '#CCCCCC' })
      .margin({ right: 12 })

      Column() {
        Text(member.isSelf() ? member.nickname : this.getDisplayName(member))
          .fontSize(TYPO.cardTitle.size)
          .fontWeight(TYPO.cardTitle.weight)
          .fontColor(this.tokens ? this.tokens.textPrimary : '#1A1A1A')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .attributeModifier(SKETCH_BODY)
        Text(member.isSelf() ? '点击编辑昵称' : '点击编辑备注')
          .fontSize(TYPO.eyebrow.size)
          .fontColor(this.tokens ? this.tokens.textTertiary : '#8A8A8A')
          .opacity(0.8)
          .margin({ top: 2 })
          .attributeModifier(SKETCH_BODY)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      SymbolGlyph(IconMapper.FORWARD)
        .fontSize(14)
        .fontColor([this.tokens ? this.tokens.textTertiary : '#CCCCCC'])
    }
    .width('100%')
    .height(56)
    .onClick(() => {
      this.openEditModal(member);
    })
    .accessibilityText('家庭成员：' + (member.isSelf() ? member.nickname : this.getDisplayName(member)) + (member.isSelf() ? '，点击编辑昵称' : '，点击编辑备注'))
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
          .backgroundColor(this.tokens ? this.tokens.surface : '#F7F7F7')
          .border({
            width: 1,
            color: this.tokens ? this.tokens.border : '#CCCCCC',
            style: BorderStyle.Dashed
          })
          .onClick(() => {
            // HUI-LOGIN：未登录点击跳转登录页
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
        .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#738A9C')
        .margin({ top: 12 })
        .onClick(() => {
          // HUI-LOGIN：未登录点击跳转登录页
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
            .backgroundColor(this.tokens ? this.tokens.btnPrimary : '#738A9C')
            .layoutWeight(1)
            .height(48)
            .borderRadius(RADIUS.item)
            .onClick(() => {
              // HUI-LOGIN：未登录点击直接跳转登录页
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
            .border({ width: 1, color: this.tokens ? this.tokens.border : '#CCCCCC' })
            .layoutWeight(1)
            .height(48)
            .borderRadius(RADIUS.item)
            .margin({ left: 12 })
            .onClick(() => {
              // HUI-LOGIN：未登录点击直接跳转登录页
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
      // 他人：优先回显我对他的备注
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
      // T707: 判断是编辑自己还是给他人设备注
      const targetMember = this.findMemberById(this.editingId);
      if (targetMember !== null && targetMember.isSelf()) {
        // 自己 → 改昵称
        await FamilyViewModel.updateNickname(this.editingId, name);
      } else if (targetMember !== null && targetMember.uid !== null) {
        // 他人 → 设备注（更新我自己的 aliases）
        await FamilyViewModel.setAlias(targetMember.uid, name);
      } else {
        // 兜底：无 uid 的本地成员仍走 updateNickname
        await FamilyViewModel.updateNickname(this.editingId, name);
      }
    }
    // 刷新列表 + aliases（setAlias 只改我自己的记录，不需全量云端同步）
    this.myAliases = await FamilyViewModel.getMyAliases();
    if (this.editingId === -1) {
      // 新增成员才需要重新拉列表
      this.members = await FamilyViewModel.getMembers();
    }
    this.showNicknameModal = false;
  }

  /** 按 id 查找成员（用于判断 self/非 self，路由 setAlias vs updateNickname） */
  private findMemberById(id: number): FamilyMember | null {
    for (let i = 0; i < this.members.length; i++) {
      if (this.members[i].id === id) {
        return this.members[i];
      }
    }
    return null;
  }

  /** 生成本家庭邀请码（VM 幂等；生成后刷新展示） */
  private async generateInviteCode(): Promise<void> {
    this.myInviteCode = await FamilyViewModel.generateInviteCode();
    promptAction.showToast({ message: '邀请码已生成，分享给家人吧', duration: 1500 });
  }

  /** 复制邀请码到剪贴板（成败均 Toast 反馈） */
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

  /** 弹窗确认：通过邀请码加入家庭（VM 校验；失败 Toast 原因） */
  private async applyJoinFamily(code: string): Promise<void> {
    const err: string = await FamilyViewModel.joinFamily(code);
    if (err.length === 0) {
      this.joinedInviteCode = FamilyViewModel.getJoinedInviteCode();
      this.showInviteModal = false;
      // 接着弹昵称弹窗，创建家庭成员记录
      this.openAddModal();
    } else {
      promptAction.showToast({ message: err, duration: 2000 });
      this.showInviteModal = false;
    }
  }

  /** HUI-LOGIN：读取登录态（HUI-049：@StorageProp('account_logged_in') 响应式订阅，登录/注册后自动同步，无需重查） */
  private ensureLoggedIn(): boolean {
    return this.isLoggedIn;
  }

  /** HUI-LOGIN：跳转账号登录页（entry main_pages.json 已注册 pages/LoginPage） */
  private gotoLogin(): void {
    router.pushUrl({ url: 'pages/LoginPage' }).catch(() => {
    });
  }
}
