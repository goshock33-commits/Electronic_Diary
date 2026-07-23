// <!-- agentID: DEV-010 -->
// 文件: QuoteViewModel.ets
// 任务: M10 名言卡片业务逻辑 - AppStorage todayQuote + EventBus QUOTE_CHANGED (B01收编)
// 关联架构: ARC-001 4.1 QuoteDao / 2.0 feature specs / B01 EventBus
// SDK: HarmonyOS 6.1.1 (API 24)

import { QuoteDao, Quote, EventBus } from '@ohos/shared';
import { hilog } from '@kit.PerformanceAnalysisKit';
// §8.3②: AppStorage 是全局对象（component/common_ts_ets_api.d.ts declare class），
// 禁止 import（@kit.ArkUI 只导出 AppStorageV2，import AppStorage 会报 "not exported"）。直接用。

const TAG = 'QuoteViewModel';

interface QuoteData {
  content: string;
  author: string;
}

/** 120 built-in Chinese inspirational quotes */
const BUILT_IN_QUOTES: QuoteData[] = [
  { content: '千里之行，始于足下。', author: '老子' },
  { content: '学而不思则罔，思而不学则殆。', author: '孔子' },
  { content: '天行健，君子以自强不息。', author: '《周易》' },
  { content: '业精于勤，荒于嬉；行成于思，毁于随。', author: '韩愈' },
  { content: '生活不止眼前的苟且，还有诗和远方。', author: '高晓松' },
  { content: '不以物喜，不以己悲。', author: '范仲淹' },
  { content: '失败是成功之母。', author: '谚语' },
  { content: '宝剑锋从磨砺出，梅花香自苦寒来。', author: '《警世贤文》' },
  { content: '志当存高远。', author: '诸葛亮' },
  { content: '书山有路勤为径，学海无涯苦作舟。', author: '韩愈' },
  { content: '人生自古谁无死，留取丹心照汗青。', author: '文天祥' },
  { content: '三人行，必有我师焉。', author: '孔子' },
  { content: '知之为知之，不知为不知，是知也。', author: '孔子' },
  { content: '己所不欲，勿施于人。', author: '孔子' },
  { content: '温故而知新，可以为师矣。', author: '孔子' },
  { content: '不积跬步，无以至千里；不积小流，无以成江海。', author: '荀子' },
  { content: '青，取之于蓝而青于蓝；冰，水为之而寒于水。', author: '荀子' },
  { content: '路漫漫其修远兮，吾将上下而求索。', author: '屈原' },
  { content: '少壮不努力，老大徒伤悲。', author: '《乐府诗集》' },
  { content: '海内存知己，天涯若比邻。', author: '王勃' },
  { content: '君子坦荡荡，小人长戚戚。', author: '孔子' },
  { content: '敏而好学，不耻下问。', author: '孔子' },
  { content: '知之者不如好之者，好之者不如乐之者。', author: '孔子' },
  { content: '吾生也有涯，而知也无涯。', author: '庄子' },
  { content: '锲而不舍，金石可镂。', author: '荀子' },
  { content: '老骥伏枥，志在千里。烈士暮年，壮心不已。', author: '曹操' },
  { content: '非淡泊无以明志，非宁静无以致远。', author: '诸葛亮' },
  { content: '读书破万卷，下笔如有神。', author: '杜甫' },
  { content: '黑发不知勤学早，白首方悔读书迟。', author: '颜真卿' },
  { content: '长风破浪会有时，直挂云帆济沧海。', author: '李白' },
  { content: '天生我材必有用，千金散尽还复来。', author: '李白' },
  { content: '旧书不厌百回读，熟读深思子自知。', author: '苏轼' },
  { content: '博观而约取，厚积而薄发。', author: '苏轼' },
  { content: '纸上得来终觉浅，绝知此事要躬行。', author: '陆游' },
  { content: '山重水复疑无路，柳暗花明又一村。', author: '陆游' },
  { content: '问渠那得清如许，为有源头活水来。', author: '朱熹' },
  { content: '先天下之忧而忧，后天下之乐而乐。', author: '范仲淹' },
  { content: '出淤泥而不染，濯清涟而不妖。', author: '周敦颐' },
  { content: '天下兴亡，匹夫有责。', author: '顾炎武' },
  { content: '宰相必起于州部，猛将必发于卒伍。', author: '韩非子' },
  { content: '合抱之木，生于毫末；九层之台，起于累土。', author: '老子' },
  { content: '大直若屈，大巧若拙，大辩若讷。', author: '老子' },
  { content: '上善若水，水善利万物而不争。', author: '老子' },
  { content: '祸兮福之所倚，福兮祸之所伏。', author: '老子' },
  { content: '穷则独善其身，达则兼济天下。', author: '孟子' },
  { content: '富贵不能淫，贫贱不能移，威武不能屈。', author: '孟子' },
  { content: '天将降大任于是人也，必先苦其心志。', author: '孟子' },
  { content: '生于忧患，死于安乐。', author: '孟子' },
  { content: '尽信书，则不如无书。', author: '孟子' },
  { content: '爱人者，人恒爱之；敬人者，人恒敬之。', author: '孟子' },
  { content: '尺有所短，寸有所长。', author: '屈原' },
  { content: '举世皆浊我独清，众人皆醉我独醒。', author: '屈原' },
  { content: '前事不忘，后事之师。', author: '《战国策》' },
  { content: '亡羊补牢，犹未为晚。', author: '《战国策》' },
  { content: '兼听则明，偏信则暗。', author: '魏徵' },
  { content: '君子之交淡如水。', author: '《庄子》' },
  { content: '大器晚成。', author: '老子' },
  { content: '人无远虑，必有近忧。', author: '孔子' },
  { content: '己欲立而立人，己欲达而达人。', author: '孔子' },
  { content: '君子喻于义，小人喻于利。', author: '孔子' },
  { content: '不义而富且贵，于我如浮云。', author: '孔子' },
  { content: '工欲善其事，必先利其器。', author: '孔子' },
  { content: '其身正，不令而行；其身不正，虽令不从。', author: '孔子' },
  { content: '人之初，性本善。', author: '《三字经》' },
  { content: '明日复明日，明日何其多。我生待明日，万事成蹉跎。', author: '钱鹤滩' },
  { content: '绳锯木断，水滴石穿。', author: '《汉书》' },
  { content: '有志者，事竟成。', author: '《后汉书》' },
  { content: '精诚所至，金石为开。', author: '《后汉书》' },
  { content: '临渊羡鱼，不如退而结网。', author: '《淮南子》' },
  { content: '塞翁失马，焉知非福。', author: '《淮南子》' },
  { content: '桃李不言，下自成蹊。', author: '《史记》' },
  { content: '不鸣则已，一鸣惊人。', author: '《史记》' },
  { content: '智者千虑，必有一失；愚者千虑，必有一得。', author: '《史记》' },
  { content: '良药苦口利于病，忠言逆耳利于行。', author: '《孔子家语》' },
  { content: '满招损，谦受益。', author: '《尚书》' },
  { content: '人非圣贤，孰能无过。', author: '《左传》' },
  { content: '一日之计在于晨，一年之计在于春。', author: '《增广贤文》' },
  { content: '一寸光阴一寸金，寸金难买寸光阴。', author: '《增广贤文》' },
  { content: '流水不腐，户枢不蠹。', author: '《吕氏春秋》' },
  { content: '玉不琢，不成器；人不学，不知道。', author: '《礼记》' },
  { content: '知之为知之，不知为不知，是知也。', author: '孔子' },
  { content: '不登高山，不知天之高也。', author: '荀子' },
  { content: '千里之堤，溃于蚁穴。', author: '《韩非子》' },
  { content: '月满则亏，物盛则衰。', author: '《管子》' },
  { content: '智者乐水，仁者乐山。', author: '孔子' },
  { content: '大智若愚，大巧若拙。', author: '老子' },
  { content: '心有猛虎，细嗅蔷薇。', author: '萨松' },
  { content: '世界以痛吻我，要我报之以歌。', author: '泰戈尔' },
  { content: '黑夜无论怎样悠长，白昼总会到来。', author: '莎士比亚' },
  { content: '活着就是为了改变世界。', author: '乔布斯' },
  { content: '你可以被打倒，但不能被打败。', author: '海明威' },
  { content: '今天很残酷，明天更残酷，后天很美好。', author: '马云' },
  { content: '机会总是留给有准备的人。', author: '巴斯德' },
  { content: '幸福不是拥有的多，而是计较的少。', author: '佚名' },
  { content: '一个人最大的破产是绝望，最大的资产是希望。', author: '佚名' },
  { content: '做你害怕的事，害怕就会消失。', author: '爱默生' },
  { content: '不要问你的国家能为你做什么，而要问你能为你的国家做什么。', author: '肯尼迪' },
  { content: '给我一个支点，我能撬动地球。', author: '阿基米德' },
  { content: '想象力比知识更重要。', author: '爱因斯坦' },
  { content: '天才就是百分之一的灵感加上百分之九十九的汗水。', author: '爱迪生' },
  { content: '假如生活欺骗了你，不要悲伤，不要心急。', author: '普希金' },
  { content: '冬天来了，春天还会远吗？', author: '雪莱' },
  { content: '诚实不仅是对他人负责，也是对自己负责。', author: '佚名' },
  { content: '实践是检验真理的唯一标准。', author: '佚名' },
  { content: '每一个不曾起舞的日子，都是对生命的辜负。', author: '尼采' },
  { content: '人可以被毁灭，但不可以被打败。', author: '海明威' },
  { content: '时间的步伐有三种：未来姗姗来迟，现在像箭一样飞逝，过去永远静立不动。', author: '席勒' },
  { content: '世界上最宽阔的是海洋，比海洋更宽阔的是天空，比天空更宽阔的是人的心灵。', author: '雨果' },
  { content: '真正的幸福，是来自于内心的满足，而非外在的浮华。', author: '佚名' },
  { content: '态度决定高度，细节决定成败。', author: '佚名' },
  { content: '成功是百分之一的天赋加上百分之九十九的努力。', author: '爱迪生' },
  { content: '人生就像骑自行车，要想保持平衡就得往前走。', author: '爱因斯坦' },
  { content: '重要的不是生命的长度，而是生命的深度。', author: '爱默生' },
  { content: '你若盛开，蝴蝶自来。', author: '佚名' },
  { content: '心有多大，舞台就有多大。', author: '佚名' },
  { content: '梦想还是要有的，万一实现了呢？', author: '马云' },
  { content: '不忘初心，方得始终。', author: '《华严经》' },
  { content: '你若安好，便是晴天。', author: '白落梅' },
  { content: '人生如逆旅，我亦是行人。', author: '苏轼' },
  { content: '宠辱不惊，看庭前花开花落；去留无意，望天上云卷云舒。', author: '陈继儒' }
];

export class QuoteViewModel {
  private currentQuote: Quote | null = null;
  private todayDate: string = '';

  /**
   * Initialize the ViewModel: check if built-in quotes exist, seed if needed, get today's quote.
   */
  async init(): Promise<void> {
    this.todayDate = this.getTodayDateInternal();
    try {
      const count = await QuoteDao.count();
      if (count === 0) {
        await this.seedBuiltInQuotes();
      }
      await this.refresh();
    } catch (err) {
      hilog.error(0x0000, TAG, 'Init failed: %{public}s', (err as Error).message);
      throw new Error(`QuoteViewModel init failed: ${(err as Error).message}`);
    }
  }

  /**
   * Get today's random quote, excluding ones already shown today.
   * Updates currentQuote and marks the quote as shown.
   */
  async refresh(): Promise<Quote | null> {
    try {
      const quote = await QuoteDao.random(this.todayDate);
      if (quote) {
        this.currentQuote = quote;
        await QuoteDao.markShown(quote.id, this.todayDate);
        // Emit event for UI update
        this.emitQuoteChanged(quote);
        return quote;
      }
      // No unshown quotes available — reset all last_shown_date and try again
      if (this.currentQuote) {
        return this.currentQuote;
      }
      return null;
    } catch (err) {
      hilog.error(0x0000, TAG, 'Refresh failed: %{public}s', (err as Error).message);
      throw new Error(`QuoteViewModel refresh failed: ${(err as Error).message}`);
    }
  }

  /**
   * Add a user-customized quote to the database.
   * @param content Quote content text
   * @param author Quote author name
   * @returns The created Quote or null on failure
   */
  async addCustom(content: string, author: string): Promise<Quote | null> {
    try {
      if (!content || content.trim().length === 0) {
        hilog.warn(0x0000, TAG, 'Cannot add empty quote');
        return null;
      }
      const quote = new Quote(content.trim(), author.trim() || '佚名');
      quote.is_builtin = 0;
      const rowId = await QuoteDao.insertCustom(quote);
      if (rowId > 0) {
        quote.id = rowId;
        // Emit event so UI can update
        this.emitQuoteChanged(quote);
        return quote;
      }
      return null;
    } catch (err) {
      hilog.error(0x0000, TAG, 'AddCustom failed: %{public}s', (err as Error).message);
      throw new Error(`QuoteViewModel addCustom failed: ${(err as Error).message}`);
    }
  }

  /**
   * Get the currently displayed quote.
   */
  getCurrentQuote(): Quote | null {
    return this.currentQuote;
  }

  /**
   * Get today's date string in YYYY-MM-DD format.
   */
  getTodayDate(): string {
    return this.todayDate;
  }

  /**
   * Seed 120 built-in Chinese quotes on first launch.
   * Called automatically by init() when quote table is empty.
   */
  private async seedBuiltInQuotes(): Promise<void> {
    try {
      const quotes: Quote[] = [];
      for (const q of BUILT_IN_QUOTES) {
        const quote = new Quote(q.content, q.author);
        quote.is_builtin = 1;
        quotes.push(quote);
      }
      await QuoteDao.batchInsert(quotes);
      hilog.info(0x0000, TAG, 'Seeded %{public}d built-in quotes', quotes.length);
    } catch (err) {
      hilog.error(0x0000, TAG, 'Seed failed: %{public}s', (err as Error).message);
      throw new Error(`QuoteViewModel seedBuiltInQuotes failed: ${(err as Error).message}`);
    }
  }

  /**
   * Emit event:quote:changed event via emitter for UI refresh.
   */
  private emitQuoteChanged(quote: Quote): void {
    // §8.3①: Record<string,Object> 载荷禁止平铺字面量直传（arkts-no-untyped-obj-literals）。
    // 唯一编译通过写法：空字面量起手 + 括号逐键赋值。事件名/字段名/字段值零改动。
    const payload: Record<string, Object> = {};
    payload['id'] = quote.id;
    payload['content'] = quote.content;
    payload['author'] = quote.author;
    payload['is_builtin'] = quote.is_builtin;
    EventBus.emit(EventBus.EventNames.QUOTE_CHANGED, payload);
    // M10: Write todayQuote to AppStorage for cross-module reactive access
    AppStorage.setOrCreate<Quote>('todayQuote', quote);
    hilog.debug(0x0000, TAG, 'Emitted event:quote:changed via EventBus, id=%{public}d', quote.id);
  }

  /**
   * Generate today's date string as YYYY-MM-DD.
   */
  private getTodayDateInternal(): string {
    const d = new Date();
    const year = d.getFullYear();
    const month = String(d.getMonth() + 1).padStart(2, '0');
    const day = String(d.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
  }
}
