// <!-- agentID: DEV-001 -->
// Task: T002 AppSettings entity - architecture 5.2 table 10

export class AppSettings {
  id: number = 0;
  key: string = '';
  value: string = '';
  updated_at: number = 0;

  constructor(key?: string, value?: string) {
    if (key) { this.key = key; }
    if (value) { this.value = value; }
    this.updated_at = Date.now();
  }

  getValueAsObject<T>(): T | null {
    try { return JSON.parse(this.value) as T; } catch (_e) { return null; }
  }

  setValueFromObject(obj: Object): void {
    this.value = JSON.stringify(obj);
    this.updated_at = Date.now();
  }
}
