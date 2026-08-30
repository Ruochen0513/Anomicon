import { systemDateTime } from '@kit.BasicServicesKit';
import { RuntimeClockPort } from './PlatformPorts';

/** HarmonyOS monotonic/wall-clock adapter for application policies. */
export class RuntimeClockAdapter implements RuntimeClockPort {
  uptime(): number | undefined {
    try {
      return systemDateTime.getUptime(systemDateTime.TimeType.ACTIVE, false);
    } catch (_error) {
      // A monotonic reading is required for crediting activity.  Returning
      // undefined makes the coordinator conservatively skip that interval.
      return undefined;
    }
  }

  wallTime(): number {
    try {
      return systemDateTime.getTime(false);
    } catch (_error) {
      return Date.now();
    }
  }
}
