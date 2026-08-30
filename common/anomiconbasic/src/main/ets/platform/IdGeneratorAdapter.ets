import { util } from '@kit.ArkTS';
import { IdGeneratorPort } from './PlatformPorts';

/** HarmonyOS UUID adapter; generated values are suitable for session keys. */
export class IdGeneratorAdapter implements IdGeneratorPort {
  generate(): string {
    return util.generateRandomUUID(true);
  }
}
