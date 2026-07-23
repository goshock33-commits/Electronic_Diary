// <!-- agentID: DEV+HUI -->
// File: Account.ets
// Task: Account entity - login state persistence
// Architecture: Shared data model for account table
// Dev paradigm: ArkTS declarative

/**
 * Account entity — persisted to account table.
 * Holds AGC Auth uid, phone, token, and login state.
 */
export class Account {
  id: number = 0;
  uid: string = '';
  phone: string = '';
  token: string = '';
  is_logged_in: number = 0;
  login_time: number = 0;
  created_at: number = 0;

  constructor(uid?: string, phone?: string, token?: string) {
    if (uid) { this.uid = uid; }
    if (phone) { this.phone = phone; }
    if (token) { this.token = token; }
    this.is_logged_in = 0;
    this.login_time = 0;
    this.created_at = Date.now();
  }
}
