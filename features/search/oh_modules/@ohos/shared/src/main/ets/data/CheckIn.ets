// <!-- agentID: DEV-001 -->
// Task: T002 CheckIn entity - architecture 5.2 table 2

export class CheckIn {
  id: number = 0;
  date: string = '';
  created_at: number = 0;

  constructor(date?: string) {
    if (date) { this.date = date; }
    this.created_at = Date.now();
  }
}
