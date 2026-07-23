// <!-- agentID: DEV-010 -->
// <!-- agentID: DEV-021 --> AI 提取的 task_date/task_time/location 接线到 TodoItem 的
//   due_date/due_time/location（DEV-013 字段，TodoDao.insert 全字段落库）。
//   新增 normalizeTaskDate：heuristic 原文日期片段（"7月18日"/"7/18"/"7-18"）归一化为
//   YYYY-MM-DD（TodoItem/DateUtils 统一约定），失败返回 null 不写入。
// File: TaskExtractionViewModel.ets
// Task: M07 Task extraction business logic - EventBus refs to EventNames + CLIPBOARD_TASK_DETECTED
// Architecture: ARC-001 S3 multi-source task extraction / 4.1 ExtractedTaskDao / B01 EventBus

import { ExtractedTaskDao } from '@ohos/shared';
import { TodoDao } from '@ohos/shared';
import { TodoItem } from '@ohos/shared';
import { ExtractedTask } from '@ohos/shared';
import { EventBus } from '@ohos/shared';
import { ShareUtils } from '@ohos/shared';
import { ClipboardUtils } from '@ohos/shared';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'TaskExtractionViewModel';

export enum TaskCategory { EXAM = 'exam', HOMEWORK = 'homework', MEETING = 'meeting', DEADLINE = 'deadline', GENERAL = 'general' }

export interface ExtractionResult {
  title: string;
  category: TaskCategory;
  taskDate?: string;
  taskTime?: string;
  location?: string;
  priority?: number;
  confidence: number;
}

export class TaskExtractionViewModel {
  private tasks: ExtractedTask[] = [];

  async init(): Promise<void> {
    try { this.tasks = await ExtractedTaskDao.queryUnconverted(); }
    catch (err) { hilog.error(0x0000, TAG, 'Init failed: %{public}s', (err as BusinessError).message); }
  }

  /** Parse shared text from external apps (QQ/WeChat) into structured task info */
  async receiveFromShare(text: string, sourceApp: string): Promise<ExtractionResult | null> {
    const cleaned = ShareUtils.extractTaskText(text);
    if (!cleaned) { return null; }
    return await this.extractTaskInfo(cleaned, sourceApp);
  }

  /** Parse clipboard content for task information */
  async receiveFromClipboard(text: string): Promise<ExtractionResult | null> {
    if (!(await ClipboardUtils.mightContainTask())) { return null; }
    const result = await this.extractTaskInfo(text, 'clipboard');
    // M07: Emit CLIPBOARD_TASK_DETECTED (B01 已补) for UI notification
    if (result) {
      const detectedPayload: Record<string, Object> = {};
      detectedPayload['title'] = result.title;
      detectedPayload['category'] = result.category;
      detectedPayload['confidence'] = result.confidence;
      EventBus.emit(EventBus.EventNames.CLIPBOARD_TASK_DETECTED, detectedPayload);
    }
    return result;
  }

  /** AI extraction with 3-tier degradation: high conf -> low conf prefill -> fallback manual */
  private async extractTaskInfo(text: string, source: string): Promise<ExtractionResult> {
    try {
      // Tier 1: Attempt AI extraction (placeholder for intent framework integration)
      // In production, this calls the Xiaoyi intent framework via intent_schema.json
      const extracted = TaskExtractionViewModel.heuristicExtract(text);
      if (extracted.confidence >= 0.7) {
        await this.saveTask(extracted, source, 'ai_high');
        return extracted;
      }
      // Tier 2: Low confidence - prefill and return for manual review
      if (extracted.confidence >= 0.3) {
        await this.saveTask(extracted, source, 'ai_low');
        return extracted;
      }
      // Tier 3: Failed - return raw text for full manual entry
      const fallback: ExtractionResult = { title: text, category: TaskCategory.GENERAL, confidence: 0 };
      await this.saveTask(fallback, source, 'failed');
      return fallback;
    } catch (_err) {
      const fallback: ExtractionResult = { title: text, category: TaskCategory.GENERAL, confidence: 0 };
      return fallback;
    }
  }

  /** Heuristic text extraction (stand-in for Xiaoyi AI until intent framework is integrated) */
  private static heuristicExtract(text: string): ExtractionResult {
    let category = TaskCategory.GENERAL;
    let confidence = 0.3;
    if (text.includes('考试') || text.includes('exam')) { category = TaskCategory.EXAM; confidence = 0.6; }
    else if (text.includes('作业') || text.includes('homework')) { category = TaskCategory.HOMEWORK; confidence = 0.6; }
    else if (text.includes('会议') || text.includes('开会') || text.includes('meeting')) { category = TaskCategory.MEETING; confidence = 0.7; }
    else if (text.includes('截止') || text.includes('deadline') || text.includes('到期')) { category = TaskCategory.DEADLINE; confidence = 0.5; }
    let title = text.substring(0, Math.min(text.length, 100));
    const dateMatch = text.match(/(\d{1,2}[月\/\-])\s*(\d{1,2}[日号]?)/);
    const timeMatch = text.match(/(\d{1,2}:\d{2})/);
    return {
      title, category,
      taskDate: dateMatch ? dateMatch[0] : undefined,
      taskTime: timeMatch ? timeMatch[1] : undefined,
      location: text.includes('地点') ? text.substring(text.indexOf('地点') + 2, Math.min(text.length, text.indexOf('地点') + 30)).trim() : undefined,
      confidence
    };
  }

  /** Save extracted task to database */
  async saveTask(result: ExtractionResult, source: string, quality: string): Promise<ExtractedTask | null> {
    try {
      const task = new ExtractedTask(source, result.title);
      task.category = result.category;
      if (result.taskDate) { task.task_date = result.taskDate; }
      if (result.taskTime) { task.task_time = result.taskTime; }
      if (result.location) { task.location = result.location; }
      if (result.priority) { task.priority = result.priority; }
      const rowId = await ExtractedTaskDao.insert(task);
      if (rowId > 0) {
        task.id = rowId;
        this.tasks.unshift(task);
        const extractedPayload: Record<string, Object> = {};
        extractedPayload['taskId'] = rowId;
        extractedPayload['source'] = source;
        EventBus.emit(EventBus.EventNames.TASK_EXTRACTED, extractedPayload);
        return task;
      }
      return null;
    } catch (err) { hilog.error(0x0000, TAG, 'SaveTask failed: %{public}s', (err as BusinessError).message); return null; }
  }

  /**
   * DEV-021 归一化提取日期为 YYYY-MM-DD（TodoItem.due_date / DateUtils 统一约定）。
   * 支持："2026-07-18"（已标准）、"7月18日"、"7/18"、"7-18"（heuristicExtract 原文片段，年份取当前年）。
   * 无法解析或月/日越界返回 null（调用方判空后不写入）。
   */
  static normalizeTaskDate(raw: string): string | null {
    const trimmed = raw.trim();
    if (trimmed.length === 0) { return null; }
    if (new RegExp('^\\d{4}-\\d{2}-\\d{2}$').test(trimmed)) { return trimmed; }
    const m = trimmed.match(/(\d{1,2})[月\/\-]\s*(\d{1,2})/);
    if (!m) { return null; }
    const month = parseInt(m[1], 10);
    const day = parseInt(m[2], 10);
    if (isNaN(month) || isNaN(day) || month < 1 || month > 12 || day < 1 || day > 31) { return null; }
    const year = new Date().getFullYear();
    return `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`;
  }

  /** Convert an extracted task to a todo item */
  async convertToTodo(taskId: number, date: string, type: string): Promise<boolean> {
    try {
      const task = this.tasks.find((t: ExtractedTask) => t.id === taskId);
      if (!task) { return false; }
      const todoItem = new TodoItem(date, task.title, type);
      todoItem.source_task_id = taskId;
      // DEV-021 AI 提取的日期/时间/地点接线到 TodoItem（DEV-013 字段，insert 全字段落库），判空后写入
      if (task.task_date !== null && task.task_date.length > 0) {
        const dueDate = TaskExtractionViewModel.normalizeTaskDate(task.task_date);
        if (dueDate !== null) { todoItem.due_date = dueDate; }
      }
      if (task.task_time !== null && task.task_time.length > 0) { todoItem.due_time = task.task_time; }
      if (task.location !== null && task.location.length > 0) { todoItem.location = task.location; }
      const todoId = await TodoDao.insert(todoItem);
      if (todoId > 0) {
        await ExtractedTaskDao.convertToTodo(taskId, todoId);
        task.is_converted = 1;
        task.converted_todo_id = todoId;
        const convertedPayload: Record<string, Object> = {};
        convertedPayload['taskId'] = taskId;
        convertedPayload['todoId'] = todoId;
        EventBus.emit(EventBus.EventNames.TASK_CONVERTED, convertedPayload);
        // DEV-003 ①：转待办=新建 todo 行，补发 TODO_CREATED（统计页/时光轴订阅方刷新；原先仅发 TASK_CONVERTED 感知不到）
        const createdPayload: Record<string, Object> = {};
        createdPayload['todoId'] = todoId;
        createdPayload['date'] = todoItem.date;
        createdPayload['type'] = todoItem.type;
        EventBus.emit(EventBus.EventNames.TODO_CREATED, createdPayload);
        return true;
      }
      return false;
    } catch (err) { hilog.error(0x0000, TAG, 'ConvertToTodo failed: %{public}s', (err as BusinessError).message); return false; }
  }

  getUnconvertedTasks(): ExtractedTask[] { return this.tasks.filter((t: ExtractedTask) => t.is_converted === 0); }
  getAllTasks(): ExtractedTask[] { return this.tasks; }
  async deleteTask(id: number): Promise<boolean> { try { await ExtractedTaskDao.delete(id); this.tasks = this.tasks.filter((t: ExtractedTask) => t.id !== id); return true; } catch (_) { return false; } }
}
