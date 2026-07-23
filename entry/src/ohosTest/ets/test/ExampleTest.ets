// <!-- agentID: DEV-001 -->
// File: ExampleTest.ets
// Task: T041 Test framework - Example test case to verify hypium setup
// Skill Ref: frontend-design / ui-ux-pro-max

import { describe, beforeAll, beforeEach, afterAll, afterEach, it, expect } from '@ohos/hypium';
import { Diary } from 'shared';

export default function exampleTest() {
  describe('ExampleTest', () => {
    beforeAll(() => {
      console.info('ExampleTest beforeAll');
    });

    afterAll(() => {
      console.info('ExampleTest afterAll');
    });

    it('should create Diary entity with correct date', 0, () => {
      const diary = new Diary('2026-07-07');
      expect(diary.date).assertEqual('2026-07-07');
    });

    it('should set and get image list', 0, () => {
      const diary = new Diary('2026-07-07');
      diary.setImageList(['uri1', 'uri2']);
      expect(diary.getImageList().length).assertEqual(2);
    });

    it('should have valid created_at timestamp', 0, () => {
      const diary = new Diary();
      expect(diary.created_at > 0).assertTrue();
    });
  });
}
