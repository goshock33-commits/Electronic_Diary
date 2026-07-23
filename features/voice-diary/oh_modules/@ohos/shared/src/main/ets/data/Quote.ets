// <!-- agentID: DEV-001 -->
// Task: T002 Quote entity - architecture 5.2 table 7

export class Quote {
  id: number = 0;
  content: string = '';
  author: string = 'Unknown';
  is_builtin: number = 1;
  last_shown_date: string | null = null;
  created_at: number = 0;

  constructor(content?: string, author?: string) {
    if (content) { this.content = content; }
    if (author) { this.author = author; }
    this.created_at = Date.now();
  }
}
