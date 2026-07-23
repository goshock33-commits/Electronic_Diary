// <!-- agentID: DEV-001 -->
// File: ohosTest.ets
// Task: T041 Test framework - Test runner entry
// Skill Ref: frontend-design / ui-ux-pro-max

import { Hypium } from '@ohos/hypium';
import abilityTest from './ets/test/ExampleTest';

export default function testRunner() {
  Hypium.hypiumTest(abilityTest);
}
