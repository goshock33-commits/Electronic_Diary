// <!-- agentID: DEV-001 -->
// Task: T002 Diary entity - architecture 5.2 table 1

// DEV-DB: v2 新增 title/mood（ARC-001 §4 缺口#1/#2）；老数据由迁移器 ALTER 补列，读取用 isColumnNull 兜底
export class Diary {
  id: number = 0;
  date: string = '';
  content: string = '';
  images: string = '[]';
  title: string = '';
  mood: string = '';
  created_at: number = 0;
  updated_at: number = 0;

  constructor(date?: string) {
    if (date) { this.date = date; }
    this.created_at = Date.now();
    this.updated_at = Date.now();
  }

  getImageList(): string[] {
    try { return JSON.parse(this.images) as string[]; } catch (_e) { return []; }
  }

  setImageList(uris: string[]): void {
    this.images = JSON.stringify(uris);
  }
}
