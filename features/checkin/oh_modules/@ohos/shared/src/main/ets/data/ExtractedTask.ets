// <!-- agentID: DEV-001 -->
// Task: T002 ExtractedTask entity - architecture 5.2 table 6

export class ExtractedTask {
  id: number = 0;
  source: string = '';
  category: string = 'general';
  title: string = '';
  description: string | null = null;
  task_date: string | null = null;
  task_time: string | null = null;
  location: string | null = null;
  priority: number | null = null;
  is_converted: number = 0;
  converted_todo_id: number | null = null;
  created_at: number = 0;

  constructor(source?: string, title?: string) {
    if (source) { this.source = source; }
    if (title) { this.title = title; }
    this.created_at = Date.now();
  }

  isConverted(): boolean { return this.is_converted === 1; }
}
