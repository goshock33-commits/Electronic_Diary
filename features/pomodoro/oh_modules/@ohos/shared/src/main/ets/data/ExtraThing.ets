// <!-- agentID: DEV-001 -->
// Task: T002 ExtraThing entity - architecture 5.2 table 5

export class ExtraThing {
  id: number = 0;
  date: string = '';
  content: string = '';
  created_at: number = 0;

  constructor(date?: string, content?: string) {
    if (date) { this.date = date; }
    if (content) { this.content = content; }
    this.created_at = Date.now();
  }
}
