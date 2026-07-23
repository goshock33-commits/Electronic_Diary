// <!-- agentID: DEV-001 -->
// Task: T002 HappyThing entity - architecture 5.2 table 4

export class HappyThing {
  id: number = 0;
  date: string = '';
  content: string = '';
  emoji_id: string = '';
  image: string | null = null;
  created_at: number = 0;

  constructor(date?: string, content?: string, emoji_id?: string) {
    if (date) { this.date = date; }
    if (content) { this.content = content; }
    if (emoji_id) { this.emoji_id = emoji_id; }
    this.created_at = Date.now();
  }
}
