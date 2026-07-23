// <!-- agentID: DEV-001 -->
// Task: T002 PomodoroSession entity - architecture 5.2 table 8

export class PomodoroSession {
  id: number = 0;
  date: string = '';
  preset_type: string = 'focus';
  duration_minutes: number = 25;
  actual_seconds: number | null = null;
  completed: number = 0;
  created_at: number = 0;
  ended_at: number | null = null;

  constructor(date?: string, preset_type?: string, duration_minutes?: number) {
    if (date) { this.date = date; }
    if (preset_type) { this.preset_type = preset_type; }
    if (duration_minutes) { this.duration_minutes = duration_minutes; }
    this.created_at = Date.now();
  }

  isCompleted(): boolean { return this.completed === 1; }
}
