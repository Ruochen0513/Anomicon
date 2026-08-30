import { CatalogTitleResolver } from '../domain/CatalogRepositories';
import { ScpCatalogTitleResolver } from './ScpCatalogTitleResolver';

/** 本地目录标题解析器的窄化适配器。 */
export class TitleResolverAdapter implements CatalogTitleResolver {
  private readonly resolver: ScpCatalogTitleResolver;

  constructor(resolver: ScpCatalogTitleResolver) {
    this.resolver = resolver;
  }

  resolve(itemId: string): Promise<string> {
    return this.resolver.resolve(itemId);
  }

  resolveMany(itemIds: string[]): Promise<Map<string, string>> {
    return this.resolver.resolveMany(itemIds);
  }
}
