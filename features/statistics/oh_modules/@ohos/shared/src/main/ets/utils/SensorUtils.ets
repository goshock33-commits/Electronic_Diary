// <!-- agentID: DEV-011 -->
// File: SensorUtils.ets
// Task: T007a Core utility - Accelerometer sensor / shake detection
// Architecture: ARC-001 4.4 SensorFramework / 2.0 技术选型
// Skill Ref: frontend-design / ui-ux-pro-max

import { sensor } from '@kit.SensorServiceKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'SensorUtils';

/**
 * Shake sensitivity levels.
 */
export enum ShakeSensitivity {
  LOW = 0,
  MEDIUM = 1,
  HIGH = 2
}

/**
 * Shake detection configuration per sensitivity level.
 */
interface ShakeConfig {
  /** Acceleration threshold (m/s^2) */
  threshold: number;
  /** Minimum interval between shake events (ms) */
  debounceMs: number;
  /** Number of acceleration changes needed to trigger */
  changeCount: number;
}

/**
 * SensorUtils - Accelerometer sensor wrapper for shake detection.
 * Supports three sensitivity levels: low / medium / high.
 */
export class SensorUtils {
  private static accelerometerCallback: ((data: sensor.AccelerometerResponse) => void) | null = null;
  private static shakeCallback: (() => void) | null = null;
  private static lastShakeTime: number = 0;
  private static lastX: number = 0;
  private static lastY: number = 0;
  private static lastZ: number = 0;
  private static shakeCount: number = 0;
  private static sensitivity: ShakeSensitivity = ShakeSensitivity.MEDIUM;
  private static isListening: boolean = false;

  /** Shake detection configs per sensitivity level. */
  private static getShakeConfig(sensitivity: ShakeSensitivity): ShakeConfig {
    if (sensitivity === ShakeSensitivity.LOW) {
      const config: ShakeConfig = { threshold: 15.0, debounceMs: 2000, changeCount: 2 };
      return config;
    } else if (sensitivity === ShakeSensitivity.MEDIUM) {
      const config: ShakeConfig = { threshold: 12.0, debounceMs: 1500, changeCount: 3 };
      return config;
    } else {
      const config: ShakeConfig = { threshold: 9.0, debounceMs: 1000, changeCount: 4 };
      return config;
    }
  }

  /**
   * Check if accelerometer sensor is available.
   * Reference: sensor.getSingleSensorSync (SDK 12+) replaces deprecated API
   */
  static isSensorAvailable(): boolean {
    try {
      sensor.getSingleSensorSync(sensor.SensorId.ACCELEROMETER);
      return true;
    } catch (_err) {
      return false;
    }
  }

  /**
   * Start listening for shake events.
   * @param callback Called when a shake is detected.
   * @param sensitivity Shake detection sensitivity level.
   */
  static startShakeListener(callback: () => void, sensitivity: ShakeSensitivity = ShakeSensitivity.MEDIUM): void {
    if (!SensorUtils.isSensorAvailable()) {
      hilog.warn(0xFF00, TAG, 'Accelerometer sensor not available');
      return;
    }
    if (SensorUtils.isListening) {
      hilog.warn(0xFF00, TAG, 'Shake listener already active');
      return;
    }

    SensorUtils.sensitivity = sensitivity;
    SensorUtils.shakeCallback = callback;
    SensorUtils.isListening = true;
    SensorUtils.shakeCount = 0;
    SensorUtils.lastShakeTime = 0;
    SensorUtils.lastX = 0;
    SensorUtils.lastY = 0;
    SensorUtils.lastZ = 0;

    const config = SensorUtils.getShakeConfig(sensitivity);

    SensorUtils.accelerometerCallback = (data: sensor.AccelerometerResponse): void => {
      const threshold = config.threshold;
      const deltaX = Math.abs(data.x - SensorUtils.lastX);
      const deltaY = Math.abs(data.y - SensorUtils.lastY);
      const deltaZ = Math.abs(data.z - SensorUtils.lastZ);
      const totalDelta = Math.sqrt(deltaX * deltaX + deltaY * deltaY + deltaZ * deltaZ);

      if (totalDelta > threshold) {
        SensorUtils.shakeCount++;
        if (SensorUtils.shakeCount >= config.changeCount) {
          const now = Date.now();
          if (now - SensorUtils.lastShakeTime > config.debounceMs) {
            SensorUtils.lastShakeTime = now;
            SensorUtils.shakeCount = 0;
            if (SensorUtils.shakeCallback) {
              hilog.info(0xFF00, TAG, 'Shake detected (sensitivity=%{public}d)', sensitivity);
              SensorUtils.shakeCallback();
            }
          }
        }
      } else {
        SensorUtils.shakeCount = Math.max(0, SensorUtils.shakeCount - 1);
      }

      SensorUtils.lastX = data.x;
      SensorUtils.lastY = data.y;
      SensorUtils.lastZ = data.z;
    };

    try {
      sensor.on(
        sensor.SensorId.ACCELEROMETER,
        SensorUtils.accelerometerCallback,
        { interval: 50000000 } // 50ms sampling interval (nanoseconds)
      );
      hilog.info(0xFF00, TAG, 'Shake listener started (sensitivity=%{public}d)', sensitivity);
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0xFF00, TAG, 'Failed to start shake listener: %{public}s', error.message);
      SensorUtils.isListening = false;
    }
  }

  /**
   * Stop listening for shake events. Call in onPageHide or aboutToDisappear.
   */
  static stopShakeListener(): void {
    if (!SensorUtils.isListening) {
      return;
    }
    try {
      if (SensorUtils.accelerometerCallback) {
        sensor.off(sensor.SensorId.ACCELEROMETER, SensorUtils.accelerometerCallback);
        SensorUtils.accelerometerCallback = null;
      }
      SensorUtils.shakeCallback = null;
      SensorUtils.isListening = false;
      hilog.info(0xFF00, TAG, 'Shake listener stopped');
    } catch (err) {
      hilog.error(0xFF00, TAG, 'Failed to stop shake listener: %{public}s', JSON.stringify(err));
    }
  }

  /**
   * Get the current sensitivity level.
   */
  static getSensitivity(): ShakeSensitivity {
    return SensorUtils.sensitivity;
  }

  /**
   * Set shake detection sensitivity level (updates in real time).
   */
  static setSensitivity(sensitivity: ShakeSensitivity): void {
    SensorUtils.sensitivity = sensitivity;
    hilog.info(0xFF00, TAG, 'Shake sensitivity changed to %{public}d', sensitivity);
  }

  /**
   * Check if shake listener is currently active.
   */
  static isShakeListenerActive(): boolean {
    return SensorUtils.isListening;
  }
}
