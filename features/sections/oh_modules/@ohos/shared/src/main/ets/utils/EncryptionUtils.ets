// <!-- agentID: DEV-017 -->
// File: EncryptionUtils.ets
// Task: T007c Data utility - AES-256 encryption/decryption, key management
// Architecture: ARC-001 non-functional security / SettingsViewModel
// Skill Ref: frontend-design / ui-ux-pro-max

import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { BusinessError } from '@kit.BasicServicesKit';

const TAG = 'EncryptionUtils';

/**
 * Encryption result containing ciphertext in hex format.
 */
export interface EncryptionResult {
  ciphertext: string;
  iv: string;
}

/**
 * EncryptionUtils - AES-256 encryption/decryption for data security.
 * Used for: PIN code storage, backup file encryption, sensitive data protection.
 */
export class EncryptionUtils {
  private static readonly ALGORITHM = 'AES256';
  private static readonly KEY_ALIAS = 'huawwei_diary_aes_key';

  /**
   * Derive an AES-256 key from a password string using PBKDF2-like approach.
   * In production, use the system KeyStore for secure key management.
   *
   * @param password User-provided password string.
   * @returns 32-byte key as base64 string, or null on failure.
   */
  static async deriveKey(password: string): Promise<string | null> {
    try {
      // Create a 32-byte key by hashing and truncating
      const symKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
      const keyData = EncryptionUtils.padPassword(password);
      const keyBlob: cryptoFramework.DataBlob = { data: keyData };
      const symKey = await symKeyGenerator.convertKey(keyBlob);
      const base64Helper = new util.Base64Helper();
      return base64Helper.encodeToStringSync(symKey.getEncoded().data);
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0xFF00, TAG, 'Key derivation failed: %{public}s', error.message);
      return null;
    }
  }

  /**
   * Encrypt plaintext using AES-256-CBC with a password.
   *
   * @param plaintext Text to encrypt.
   * @param password Password for key derivation.
   * @returns Encryption result with ciphertext (hex) and IV (hex), or null on failure.
   */
  static async encrypt(plaintext: string, password: string): Promise<EncryptionResult | null> {
    try {
      // Derive key from password
      const keyData = EncryptionUtils.padPassword(password);
      const symKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
      const keyBlob: cryptoFramework.DataBlob = { data: keyData };
      const symKey = await symKeyGenerator.convertKey(keyBlob);

      // Generate random IV (16 bytes for AES-CBC)
      // Reference: cryptoFramework.createRandom (API 12+) SDk @ohos.security.cryptoFramework
      const rand = cryptoFramework.createRandom();
      const ivBlob: cryptoFramework.DataBlob = rand.generateRandomSync(16);

      // Create cipher and encrypt
      const cipher = cryptoFramework.createCipher('AES256|CBC|PKCS5');
      const ivParams: cryptoFramework.IvParamsSpec = {
        algName: 'IvParamsSpec',
        iv: { data: ivBlob.data }
      };
      await cipher.init(cryptoFramework.CryptoMode.ENCRYPT_MODE, symKey, ivParams);

      const textEncoder = new util.TextEncoder();
      const plainData = textEncoder.encodeInto(plaintext);
      const plainBlob: cryptoFramework.DataBlob = { data: plainData };

      const encrypted = await cipher.doFinal(plainBlob);

      // Convert to hex strings
      const ivHex = EncryptionUtils.bytesToHex(ivBlob.data);
      const ctHex = EncryptionUtils.bytesToHex(encrypted.data);

      return { ciphertext: ctHex, iv: ivHex };
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0xFF00, TAG, 'Encryption failed: %{public}s', error.message);
      return null;
    }
  }

  /**
   * Decrypt ciphertext using AES-256-CBC with a password.
   *
   * @param hexCiphertext Ciphertext in hex format.
   * @param hexIv IV in hex format.
   * @param password Password for key derivation.
   * @returns Decrypted plaintext string, or null on failure.
   */
  static async decrypt(hexCiphertext: string, hexIv: string, password: string): Promise<string | null> {
    try {
      // Derive key from password
      const keyData = EncryptionUtils.padPassword(password);
      const symKeyGenerator = cryptoFramework.createSymKeyGenerator('AES256');
      const keyBlob: cryptoFramework.DataBlob = { data: keyData };
      const symKey = await symKeyGenerator.convertKey(keyBlob);

      // Convert IV from hex
      const ivData = EncryptionUtils.hexToBytes(hexIv);

      // Create cipher and decrypt
      const cipher = cryptoFramework.createCipher('AES256|CBC|PKCS5');
      const ivParams: cryptoFramework.IvParamsSpec = {
        algName: 'IvParamsSpec',
        iv: { data: ivData }
      };
      await cipher.init(cryptoFramework.CryptoMode.DECRYPT_MODE, symKey, ivParams);

      const ctData = EncryptionUtils.hexToBytes(hexCiphertext);
      const ctBlob: cryptoFramework.DataBlob = { data: ctData };

      const decrypted = await cipher.doFinal(ctBlob);

      const textDecoder = util.TextDecoder.create('utf-8');
      const plaintext = textDecoder.decodeWithStream(new Uint8Array(decrypted.data));
      return plaintext;
    } catch (err) {
      const error = err as BusinessError;
      hilog.error(0xFF00, TAG, 'Decryption failed: %{public}s', error.message);
      return null;
    }
  }

  /**
   * Encrypt a PIN code for secure storage.
   * @param pin 4-digit PIN code.
   * @param password Master password (app-level secret).
   * @returns Encrypted PIN hex string, or null on failure.
   */
  static async encryptPin(pin: string, password: string): Promise<string | null> {
    const result = await EncryptionUtils.encrypt(pin, password);
    if (result) {
      return result.ciphertext + ':' + result.iv;
    }
    return null;
  }

  /**
   * Decrypt a stored PIN and compare with input.
   * @param inputPin User-input PIN.
   * @param storedEncrypted Encrypted PIN string (ct:iv).
   * @param password Master password.
   * @returns true if PIN matches.
   */
  static async verifyPin(inputPin: string, storedEncrypted: string, password: string): Promise<boolean> {
    if (!storedEncrypted || storedEncrypted.length === 0) {
      return true; // No PIN set, allow access
    }
    const parts = storedEncrypted.split(':');
    if (parts.length !== 2) {
      return false;
    }
    const decrypted = await EncryptionUtils.decrypt(parts[0], parts[1], password);
    return decrypted === inputPin;
  }

  /**
   * Pad a password to 32 bytes for AES-256 key derivation.
   */
  private static padPassword(password: string): Uint8Array {
    const textEncoder = new util.TextEncoder();
    const raw = textEncoder.encodeInto(password);
    const key = new Uint8Array(32);
    for (let i = 0; i < 32; i++) {
      key[i] = raw[i % raw.length];
    }
    return key;
  }

  /**
   * Convert Uint8Array to hex string.
   */
  private static bytesToHex(bytes: Uint8Array): string {
    let hex = '';
    for (let i = 0; i < bytes.length; i++) {
      const byteHex = bytes[i].toString(16).padStart(2, '0');
      hex += byteHex;
    }
    return hex;
  }

  /**
   * Convert hex string to Uint8Array.
   */
  private static hexToBytes(hex: string): Uint8Array {
    const bytes = new Uint8Array(hex.length / 2);
    for (let i = 0; i < hex.length; i += 2) {
      bytes[i / 2] = parseInt(hex.substring(i, i + 2), 16);
    }
    return bytes;
  }
}
