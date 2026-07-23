// <!-- agentID: DEV-008 / HUI-013 -->
// Settings module combined exports (ViewModel + UI Components)
export { SettingsViewModel } from './src/main/ets/viewmodel/SettingsViewModel';
// fix: HUI-FRONTEND-2 · 导出 ReminderMethod 枚举（entry 壳页提醒方式回调用）
export { ReminderMethod } from './src/main/ets/viewmodel/SettingsViewModel';
export { AdvancedSettingsViewModel } from './src/main/ets/viewmodel/AdvancedSettingsViewModel';
export { ReminderViewModel } from './src/main/ets/viewmodel/ReminderViewModel';
// HUI-013 / HUI-030 UI Components
export { SettingsPage } from './src/main/ets/pages/SettingsPage';
export { AdvancedSettingsPage } from './src/main/ets/pages/AdvancedSettingsPage';
export { ReminderSettingsPage } from './src/main/ets/pages/ReminderSettingsPage';
