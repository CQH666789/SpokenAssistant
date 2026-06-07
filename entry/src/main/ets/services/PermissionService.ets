import { abilityAccessCtrl } from '@kit.AbilityKit';
import type { Context, Permissions } from '@kit.AbilityKit';

const MICROPHONE_PERMISSION: Permissions = 'ohos.permission.MICROPHONE';

export class PermissionService {
  static async requestMicrophone(context: Context): Promise<boolean> {
    const atManager = abilityAccessCtrl.createAtManager();
    const result = await atManager.requestPermissionsFromUser(context, [MICROPHONE_PERMISSION]);
    if (!result || !result.authResults || result.authResults.length === 0) {
      return false;
    }
    return result.authResults[0] === 0;
  }
}
