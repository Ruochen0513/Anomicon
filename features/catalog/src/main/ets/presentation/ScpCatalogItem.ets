/** 图鉴目录条目的预览生命周期。 */
export enum CatalogPreviewState {
  IDLE = 'idle',
  LOADING = 'loading',
  READY = 'ready',
  NO_IMAGE = 'no_image',
  FAILED = 'failed'
}

/** 图鉴目录展示条目：编号/名称来自解析；描述与预览图由预览管线异步补全。 */
@ObservedV2
export class ScpCatalogEntry {
  readonly itemId: string;
  readonly title: string;
  /** 正文首段描述（预览管线异步填充）。 */
  @Trace description: string = '';
  /** 本地预览图路径；空串表示未加载/无图。 */
  @Trace previewPath: string = '';
  /** 远程预览图地址；首次加载由 Image 直接渲染，避免等待落盘。 */
  @Trace previewUrl: string = '';
  /** 预览请求状态跨 WaterFlow 节点复用保持不变。 */
  @Trace previewState: CatalogPreviewState = CatalogPreviewState.IDLE;
  /** 递增代际用于丢弃刷新前遗留的异步结果。 */
  @Trace previewGeneration: number = 0;
  /** 父列表刷新后由首个可见卡片消费，保证每个条目只强制重载一次。 */
  @Trace previewRefreshPending: boolean = false;

  constructor(itemId: string, title: string) {
    this.itemId = itemId;
    this.title = title;
  }
}
