#!/usr/bin/env node
/**
 * Static dependency gate for the multi-module Anomicon project.
 *
 * The project follows HarmonyOS' products -> features -> common deployment
 * model: every leaf under common/features/products is a real Hvigor module.
 * This checker intentionally understands both relative ETS imports and local
 * package imports (for example `import { CatalogViewModel } from 'catalog'`).
 * It does not try to parse ArkTS; it only enforces the boundaries that are
 * easy to regress during a physical move.
 *
 * Usage:
 *   node scripts/architecture-check.mjs [project-root] [--strict] [--json]
 */

import fs from 'node:fs';
import path from 'node:path';
import process from 'node:process';

const argv = process.argv.slice(2);
const strict = argv.includes('--strict');
const jsonOutput = argv.includes('--json');
const rootArg = argv.find((value) => !value.startsWith('--'));
const projectRoot = path.resolve(rootArg ?? process.cwd());

// Compatibility code is intentionally opt-in.  A page under products/phone
// is part of the active product surface unless it lives in an explicitly
// named migration/legacy directory (or carries the marker below).  Keeping
// this marker as a comment-only convention makes temporary bridges visible in
// code review and prevents a broad path exemption from hiding new leaks.
const COMPATIBILITY_MARKER = '@architecture-compat';
const COMPATIBILITY_DIRECTORIES = new Set(['migration', 'legacy']);

// Feature-internal dependency matrix. Composition is the only layer allowed to
// assemble every other layer; domain, application, data and presentation keep
// their dependency direction explicit and independently testable.
const FEATURE_LAYER_DEPENDENCIES = new Map([
  ['domain', new Set(['domain'])],
  ['application', new Set(['domain', 'application'])],
  ['data', new Set(['domain', 'data'])],
  ['presentation', new Set(['domain', 'application', 'presentation'])],
  ['composition', new Set(['domain', 'application', 'data', 'presentation', 'composition'])]
]);

// Official MusicHome-style group directories are folders only.  Leaving a
// generated HAR/HAP manifest at common/, features/ or products/ makes DevEco
// treat the group as a phantom module even though the root graph registers
// only its real leaf modules.
const GROUP_MODULE_SHELL_FILES = [
  'build-profile.json5',
  'oh-package.json5',
  'hvigorfile.ts',
  'Index.ets'
];

const modules = discoverModules(projectRoot);
if (modules.size === 0) {
  emitFailure(`no leaf modules found below ${path.join(projectRoot, 'common')}, ` +
    `${path.join(projectRoot, 'features')}, or ${path.join(projectRoot, 'products')}`);
  process.exit(2);
}

const packageToModule = new Map();
const diagnostics = [];
for (const module of modules.values()) {
  if (module.packageName !== undefined) {
    packageToModule.set(module.packageName, module);
  }
}

checkRootModuleRegistration(modules);
checkGroupingDirectories();

// Validate the deployment graph before walking source files.  A source-level
// import can be hidden behind a package manifest (or a future empty module),
// so the official products -> features -> common boundary is checked at both
// levels.
for (const module of modules.values()) {
  checkModuleManifest(module, packageToModule);
}
const manifestGraph = new Map();
for (const module of modules.values()) {
  const targets = (module.dependencies ?? [])
    .map((dependency) => packageToModule.get(dependency)?.root)
    .filter((target) => target !== undefined);
  manifestGraph.set(module.root, unique(targets));
}
for (const cycle of findCycles(manifestGraph)) {
  const names = cycle.map((root) => modules.get(root)?.name ?? relative(root));
  names.push(names[0]);
  error('module manifest dependency cycle detected',
    path.join(cycle[0], 'oh-package.json5'), names.join(' -> '));
}

const files = [];
const fileSet = new Set();
for (const module of modules.values()) {
  for (const file of collectEts(module.sourceRoot)) {
    files.push(file);
    fileSet.add(file);
  }
  // A HAR's public entry sits beside src/, as in MusicHome.  Product roots
  // also commonly expose an Index.ets there, so include it in the graph.
  if (module.publicIndex !== undefined && fs.existsSync(module.publicIndex)) {
    files.push(module.publicIndex);
    fileSet.add(module.publicIndex);
  }
}

const graph = new Map();
for (const file of unique(files)) {
  const module = moduleForFile(file, modules);
  const text = fs.readFileSync(file, 'utf8');
  const specifiers = parseImportSpecifiers(text);
  const edges = [];
  for (const specifier of specifiers) {
    const target = resolveImport(file, specifier, module, fileSet, packageToModule);
    if (target !== undefined && target !== file) {
      edges.push(target);
    }
  }
  graph.set(file, unique(edges));
  checkFile(file, module, specifiers, text, graph.get(file));
}

for (const cycle of findCycles(graph)) {
  const chain = cycle.map((file) => relative(file)).join(' -> ');
  // Compatibility files are deliberately retained until P5.  Keep the
  // default gate useful while allowing the migration to proceed in slices.
  if (!strict && cycle.some((file) => isCompatibilityFile(file, modules))) {
    warning('compatibility dependency cycle (remove before P5)', cycle[0], chain);
  } else {
    error('circular dependency detected', cycle[0], chain);
  }
}

const result = {
  projectRoot,
  modules: [...modules.values()].map((module) => ({
    name: module.name,
    kind: module.kind,
    packageName: module.packageName,
    path: relative(module.root)
  })),
  errors: diagnostics.filter((item) => item.level === 'error').length,
  warnings: diagnostics.filter((item) => item.level === 'warning').length
};

if (jsonOutput) {
  console.log(JSON.stringify(result, null, 2));
} else if (result.errors === 0 && result.warnings === 0) {
  console.log('architecture-check: dependency direction and cycle checks passed');
} else if (result.errors === 0) {
  console.log(`architecture-check: passed with ${result.warnings} warning(s)`);
} else {
  console.error(`architecture-check: ${result.errors} error(s), ${result.warnings} warning(s)`);
}
process.exit(result.errors > 0 ? 1 : 0);

function discoverModules(root) {
  const result = new Map();
  for (const [kind, group] of [['common', 'common'], ['feature', 'features'], ['product', 'products']]) {
    const groupRoot = path.join(root, group);
    if (!fs.existsSync(groupRoot)) {
      continue;
    }
    for (const entry of fs.readdirSync(groupRoot, { withFileTypes: true })) {
      if (!entry.isDirectory() || entry.name.startsWith('.')) {
        continue;
      }
      const moduleRoot = path.join(groupRoot, entry.name);
      const manifest = path.join(moduleRoot, 'oh-package.json5');
      const moduleJson = path.join(moduleRoot, 'src', 'main', 'module.json5');
      // Grouping shells (common/, features/, products/) are not leaf modules;
      // only directories containing a real source module manifest participate.
      if (!fs.existsSync(manifest) || !fs.existsSync(moduleJson)) {
        continue;
      }
      const packageJson = parseJson5Subset(manifest);
      const key = path.normalize(moduleRoot);
      result.set(key, {
        name: entry.name,
        kind,
        root: key,
        sourceRoot: path.join(moduleRoot, 'src', 'main', 'ets'),
        publicIndex: path.join(moduleRoot, 'Index.ets'),
        packageName: typeof packageJson.name === 'string' ? packageJson.name : entry.name,
        dependencies: packageJson.dependencies !== undefined &&
          typeof packageJson.dependencies === 'object' ?
          Object.keys(packageJson.dependencies) : [],
        moduleType: parseJson5Subset(moduleJson)?.module?.type
      });
    }
  }
  return result;
}

function checkModuleManifest(module, packageMap) {
  const expectedType = module.kind === 'product' ? 'entry' : 'har';
  if (module.moduleType !== undefined && module.moduleType !== expectedType) {
    error(`module manifest type must be ${expectedType} for ${module.kind}`,
      path.join(module.root, 'src', 'main', 'module.json5'),
      `found ${module.moduleType}`);
  }
  for (const dependency of module.dependencies ?? []) {
    const target = packageMap.get(dependency);
    if (target === undefined) {
      // External SDK/package dependencies are outside this project's graph.
      continue;
    }
    if (module.name === 'article' && target.name === 'catalog') {
      error('article manifest depends on catalog; bridge raw HTML in product composition',
        path.join(module.root, 'oh-package.json5'), dependency);
    }
    if (module.kind === 'common' && target.kind !== 'common') {
      error('common module manifest depends on a feature/product module',
        path.join(module.root, 'oh-package.json5'), dependency);
    } else if (module.kind === 'feature' && target.kind === 'product') {
      error('feature module manifest depends on a product module',
        path.join(module.root, 'oh-package.json5'), dependency);
    } else if (module.kind === 'product' && target.kind === 'product') {
      error('product module manifest depends on another product module',
        path.join(module.root, 'oh-package.json5'), dependency);
    }
  }
}

/** Every physical leaf must be registered once in the root Hvigor graph. */
function checkRootModuleRegistration(moduleMap) {
  const buildProfilePath = path.join(projectRoot, 'build-profile.json5');
  const profile = parseJson5Subset(buildProfilePath);
  const registrations = Array.isArray(profile.modules) ? profile.modules : [];
  const pathCounts = new Map();
  for (const registration of registrations) {
    if (registration === null || typeof registration !== 'object' ||
      typeof registration.srcPath !== 'string') {
      continue;
    }
    const registeredPath = path.normalize(path.resolve(projectRoot, registration.srcPath));
    pathCounts.set(registeredPath, (pathCounts.get(registeredPath) ?? 0) + 1);
  }
  for (const module of moduleMap.values()) {
    const count = pathCounts.get(module.root) ?? 0;
    if (count === 0) {
      error('leaf module is missing from root build-profile.json5', buildProfilePath,
        relative(module.root));
    } else if (count > 1) {
      error('leaf module is registered more than once in root build-profile.json5',
        buildProfilePath, relative(module.root));
    }
  }
}

/** Group folders organize modules; they must never be modules themselves. */
function checkGroupingDirectories() {
  for (const group of ['common', 'features', 'products']) {
    const groupRoot = path.join(projectRoot, group);
    for (const fileName of GROUP_MODULE_SHELL_FILES) {
      const file = path.join(groupRoot, fileName);
      if (fs.existsSync(file)) {
        error('layer grouping directory contains a phantom module shell', file,
          `${group}/ must only contain registered leaf modules`);
      }
    }
  }
}

function parseJson5Subset(file) {
  try {
    // Manifests in this project only use JSON-compatible syntax.  Removing
    // comments/trailing commas is enough and avoids adding a runtime package.
    const source = fs.readFileSync(file, 'utf8')
      .replace(/\/\*[\s\S]*?\*\//g, '')
      .replace(/\/\/[^\n]*/g, '')
      .replace(/,\s*([}\]])/g, '$1');
    return JSON.parse(source);
  } catch (_error) {
    return {};
  }
}

function collectEts(directory) {
  if (!fs.existsSync(directory)) {
    return [];
  }
  const result = [];
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      result.push(...collectEts(fullPath));
    } else if (entry.isFile() && entry.name.endsWith('.ets')) {
      result.push(path.normalize(fullPath));
    }
  }
  return result;
}

function moduleForFile(file, moduleMap) {
  let best;
  for (const module of moduleMap.values()) {
    if (file === module.root || file.startsWith(`${module.root}${path.sep}`)) {
      if (best === undefined || module.root.length > best.root.length) {
        best = module;
      }
    }
  }
  return best;
}

function resolveImport(from, specifier, fromModule, fileSet, packageMap) {
  if (specifier.startsWith('.')) {
    const base = path.normalize(path.resolve(path.dirname(from), specifier));
    const candidates = [base, `${base}.ets`, path.join(base, 'Index.ets')];
    return candidates.find((candidate) => fileSet.has(candidate));
  }
  // SDK and language imports are outside the project graph.
  if (specifier.startsWith('@') || specifier.includes(':')) {
    return undefined;
  }
  const targetModule = packageMap.get(specifier);
  if (targetModule === undefined) {
    return undefined;
  }
  return targetModule.publicIndex && fileSet.has(targetModule.publicIndex) ?
    targetModule.publicIndex : undefined;
}

function parseImportSpecifiers(text) {
  const source = stripComments(text);
  const result = [];
  const staticPattern = /(?:import|export)\s+(?:[\s\S]*?\s+from\s+)?["']([^"']+)["']/g;
  let match;
  while ((match = staticPattern.exec(source)) !== null) {
    result.push(match[1]);
  }
  const dynamicPattern = /\bimport\s*\(\s*["']([^"']+)["']\s*\)/g;
  while ((match = dynamicPattern.exec(source)) !== null) {
    result.push(match[1]);
  }
  return unique(result);
}

/** Return only module specifiers used by export-from declarations. */
function parseExportSpecifiers(text) {
  const source = stripComments(text);
  const result = [];
  const pattern = /\bexport\s+(?:[\s\S]*?\s+from\s+)?["']([^"']+)["']/g;
  let match;
  while ((match = pattern.exec(source)) !== null) {
    result.push(match[1]);
  }
  return unique(result);
}

/** Public HAR barrels must enumerate their surface instead of forwarding everything. */
function parseWildcardExportSpecifiers(text) {
  const source = stripComments(text);
  const result = [];
  const pattern = /\bexport\s*\*\s*from\s*["']([^"']+)["']/g;
  let match;
  while ((match = pattern.exec(source)) !== null) {
    result.push(match[1]);
  }
  return unique(result);
}

function stripComments(text) {
  return text.replace(/\/\*[\s\S]*?\*\//g, '').replace(/\/\/[^\n]*/g, '');
}

function stripCommentsAndStrings(text) {
  let result = '';
  let state = 'normal';
  let quote = '';
  let escaped = false;
  for (let index = 0; index < text.length; index++) {
    const character = text[index];
    const next = text[index + 1] ?? '';
    if (state === 'line') {
      result += character === '\n' ? '\n' : ' ';
      if (character === '\n') state = 'normal';
    } else if (state === 'block') {
      result += character === '\n' ? '\n' : ' ';
      if (character === '*' && next === '/') {
        result += ' ';
        index++;
        state = 'normal';
      }
    } else if (state === 'string') {
      result += character === '\n' ? '\n' : ' ';
      if (escaped) escaped = false;
      else if (character === '\\') escaped = true;
      else if (character === quote) state = 'normal';
    } else if (character === '/' && next === '/') {
      result += '  ';
      index++;
      state = 'line';
    } else if (character === '/' && next === '*') {
      result += '  ';
      index++;
      state = 'block';
    } else if (character === "'" || character === '"' || character === '`') {
      result += ' ';
      quote = character;
      escaped = false;
      state = 'string';
    } else {
      result += character;
    }
  }
  return result;
}

function checkFile(file, module, specifiers, text, edges) {
  if (module === undefined) return;
  const layer = classify(file, module);
  const code = stripCommentsAndStrings(text);
  const relativeSpecs = specifiers.filter((item) => item.startsWith('.'));
  const exportSpecifiers = parseExportSpecifiers(text);
  const wildcardExportSpecifiers = parseWildcardExportSpecifiers(text);
  const concreteSpecs = specifiers.filter((item) => /(^|\/)(data|services)(\/|$)/.test(item));
  const featureInternalSpecs = specifiers.filter((item) =>
    /(^|\/)features\/[^/]+\/(data|domain|application|presentation)\//.test(item));
  const articleCatalogSpecs = specifiers.filter((item) =>
    item === 'catalog' || /(^|\/)catalog(\/|$)/.test(item));

  checkFeatureLayerDependencyMatrix(file, module, layer, edges);

  if (module.kind === 'common' && specifiers.some((item) =>
    packageMapHasKind(item, 'feature') || packageMapHasKind(item, 'product'))) {
    error('common module depends on a feature/product module', file);
  }
  if ((layer === 'domain' || layer === 'application') &&
    specifiers.some((item) => /^@kit\./.test(item))) {
    error('domain/application imports a Harmony kit; depend on a port instead', file);
  }
  if (module.kind === 'feature' && (layer === 'domain' || layer === 'application') &&
    /\bUIContext\b/.test(code)) {
    error('feature domain/application exposes UIContext; keep it in product/presentation adapters', file);
  }
  if ((layer === 'domain' || layer === 'application') && concreteSpecs.length > 0) {
    error('domain/application imports concrete data/service code', file, concreteSpecs.join(', '));
  }
  if (layer === 'view' && (concreteSpecs.length > 0 || specifiers.some((item) =>
    /^@kit\.(ArkWeb|ArkGraphics3D|AbilityKit|CoreFileKit|BasicServicesKit|SensorServiceKit)/.test(item)))) {
    error('presentation View imports a data/platform implementation', file);
  }
  if (layer === 'viewmodel' && (concreteSpecs.length > 0 ||
    specifiers.some((item) => /^@kit\./.test(item)) ||
    specifiers.some((item) => /pages\/|components\//.test(item)) ||
    /\bNavPathStack\b|\bUIContext\b|\bwebview\b|\bScene\b|\bNode\b/.test(code))) {
    error('ViewModel depends on UI/navigation/platform objects or concrete data', file);
  }
  if (layer === 'viewmodel' && definesPrivateLoadState(text)) {
    error('ViewModel declares a private six-state load contract; use common ViewModelLoadState', file);
  }
  if (module.kind === 'feature' && featureInternalSpecs.length > 0) {
    warning('feature reaches into another feature internals; import its public Index', file,
      featureInternalSpecs.join(', '));
  }
  if (module.name === 'article' && articleCatalogSpecs.length > 0) {
    error('article imports catalog; adapt the raw HTML port in product composition', file,
      articleCatalogSpecs.join(', '));
  }
  if (module.name === 'catalog' &&
    /\b(?:ScpArticleDocument|ScpBlockType|ScpContentBlock|ScpFootnote|ScpTextSpan|ScpTextStyle|ArticleViewState|ArticleViewStatePort|ArticleViewStateRepository|ArticleDocumentCachePort|ArticleDocumentCacheRecord|CatalogDocumentCache|CatalogStoredDocument)\b/.test(code)) {
    error('catalog declares or consumes Article-owned document/cache/view-state symbols', file);
  }
  if (module.kind === 'product' && path.basename(file) === 'ScpArticlePage.ets') {
    if (!/\bArticleNativeRenderer\s*\(/.test(code)) {
      error('article product route does not delegate its native body to the Article feature', file);
    }
    if (/\b(?:spanText|blockView|headerCard|imageGallery|footnotesSection|relatedTalesSection|licenseFooter|articleContent)\s*\(/.test(code) ||
      /\b(?:ScpBlockType|ScpFootnote|ScpTextSpan|ScpTextStyle)\b/.test(code)) {
      error('article product route owns native body rendering; keep it in Article presentation/view', file);
    }
  }
  // A feature's package root is its public API.  Exporting an implementation
  // from `data/` or `services/` leaks persistence/network/platform details to
  // every consumer and defeats the dependency inversion enforced elsewhere.
  // Keep this check scoped to the public Index; internal composition files are
  // expected to import their own adapters.  The normal gate reports a warning
  // during staged migration, while --strict turns an accidental leak into a
  // hard failure so the final graph cannot silently regress.
  if (module.kind === 'feature' && isPublicIndex(file, module)) {
    const dataExports = exportSpecifiers.filter((item) =>
      /^(?:\.\.\/|\.\/)*(?:data|services)(?:\/|$)/.test(item));
    if (dataExports.length > 0) {
      const message = unique(dataExports).join(', ');
      if (strict) {
        error('feature public Index exports data/service implementation', file, message);
      } else {
        warning('feature public Index exports data/service implementation (remove before P5)',
          file, message);
      }
    }
  }
  // MusicHome-style HARs expose an explicit, reviewable API list.  A wildcard
  // barrel can silently publish a newly added adapter even when the direct
  // data-path check above does not see it (for example through another Index).
  if ((module.kind === 'feature' || module.kind === 'common') &&
    isPublicIndex(file, module) && wildcardExportSpecifiers.length > 0) {
    error('HAR public Index uses wildcard export; enumerate the public API', file,
      wildcardExportSpecifiers.join(', '));
  }
  if (module.kind === 'product' && !isComposition(file, module) &&
    (concreteSpecs.length > 0 || featureInternalSpecs.length > 0)) {
    error('product presentation imports a concrete feature/data path', file);
  }
  const forbiddenSingletons = forbiddenSingletonCalls(code, file, module);
  if ((layer === 'view' || layer === 'viewmodel' ||
    (module.kind === 'product' && !isComposition(file, module))) &&
    forbiddenSingletons.length > 0) {
    if (isCompatibilityFile(file, modules, text)) {
      if (strict) {
        error('compatibility page/view calls a singleton; remove before P5', file,
          forbiddenSingletons.join(', '));
      } else {
        warning('compatibility page/view calls a singleton (migration pending)', file,
          forbiddenSingletons.join(', '));
      }
    } else {
      error('presentation code calls a singleton directly', file,
        `${forbiddenSingletons.join(', ')}; resolve it through a ViewModel or an approved product composition boundary`);
    }
  }
  // A relative import from one feature to another is always an internal reach;
  // package imports resolve to the target's public Index and are fine.
  if (module.kind === 'feature' && relativeSpecs.some((item) =>
    /features[\\/]/.test(item))) {
    warning('feature uses a relative path into another feature', file);
  }
  // Keep the graph parameter referenced so future checks can use resolved edges.
  void edges;
}

function packageMapHasKind(specifier, kind) {
  const target = packageToModule.get(specifier);
  return target !== undefined && target.kind === kind;
}

function isPublicIndex(file, module) {
  // MusicHome-style modules commonly keep a thin root Index.ets beside src/
  // while the actual export list lives in src/main/ets/Index.ets.  Treat both
  // files as the public surface so a data/service re-export cannot hide behind
  // that wrapper.
  const rootIndex = module.publicIndex === undefined ? undefined : path.normalize(module.publicIndex);
  const sourceIndex = path.normalize(path.join(module.sourceRoot, 'Index.ets'));
  const normalized = path.normalize(file);
  return normalized === rootIndex || normalized === sourceIndex;
}

function classify(file, module) {
  const rel = path.relative(module.sourceRoot, file).split(path.sep);
  if (rel[0] === '..' || rel[0] === undefined) return 'module-index';
  if (rel[0] === 'domain') return 'domain';
  if (rel[0] === 'application') return 'application';
  if (rel[0] === 'data') return 'data';
  if (rel[0] === 'composition') return 'composition';
  if (rel[0] === 'presentation' && rel[1] === 'viewmodel') return 'viewmodel';
  if (rel[0] === 'presentation' && rel[1] === 'view') return 'view';
  if (rel[0] === 'presentation') return 'presentation';
  if (module.kind === 'product' && rel[0] === 'pages') return 'product-page';
  return module.kind;
}

/** Normalize presentation subdirectories into one matrix layer. */
function featureLayer(layer) {
  if (layer === 'view' || layer === 'viewmodel' || layer === 'presentation') {
    return 'presentation';
  }
  if (layer === 'domain' || layer === 'application' || layer === 'data' || layer === 'composition') {
    return layer;
  }
  return undefined;
}

/**
 * Enforce View -> Application -> Domain <- Data for every resolved feature
 * source edge. Package-root imports remain public API edges and are governed by
 * module manifests/public barrels; explicit layer paths must obey this matrix.
 */
function checkFeatureLayerDependencyMatrix(file, module, layer, edges) {
  if (module.kind !== 'feature') return;
  const sourceLayer = featureLayer(layer);
  if (sourceLayer === undefined) return;
  const allowedTargets = FEATURE_LAYER_DEPENDENCIES.get(sourceLayer);
  if (allowedTargets === undefined) return;
  const violations = [];
  for (const target of edges ?? []) {
    const targetModule = moduleForFile(target, modules);
    if (targetModule === undefined || targetModule.kind !== 'feature') continue;
    const targetLayer = featureLayer(classify(target, targetModule));
    if (targetLayer !== undefined && !allowedTargets.has(targetLayer)) {
      violations.push(`${sourceLayer} -> ${targetLayer}: ${relative(target)}`);
    }
  }
  if (violations.length > 0) {
    error('feature layer dependency matrix violation', file, unique(violations).join(', '));
  }
}

function isComposition(file, module) {
  if (module.kind !== 'product') return false;
  const rel = path.relative(module.sourceRoot, file).split(path.sep);
  return rel[0] === 'composition';
}

function singletonCalls(code) {
  const result = [];
  const pattern = /\b([A-Za-z_$][A-Za-z0-9_$]*)\s*\.\s*getInstance\s*\(/g;
  let match;
  while ((match = pattern.exec(code)) !== null) {
    result.push(match[1]);
  }
  return unique(result);
}

function forbiddenSingletonCalls(code, file, module) {
  return singletonCalls(code).filter((owner) =>
    !isApprovedProductSingletonBoundary(file, module, owner));
}

/**
 * The application container may be resolved only at the phone product's
 * composition seams.  A class-name-wide exemption would allow any future
 * page to become a service locator while still passing the architecture gate.
 */
function isApprovedProductSingletonBoundary(file, module, owner) {
  if (module.kind !== 'product') return false;
  const rel = path.relative(module.sourceRoot, file).split(path.sep);
  if (owner === 'AppContainer') {
    return rel[0] === 'composition' ||
      (rel[0] === 'pages' && rel[1] === 'routes') ||
      (rel.length === 2 && rel[0] === 'pages' && rel[1] === 'Index.ets');
  }
  return false;
}

function isCompatibilityFile(file, moduleMap, sourceText = undefined) {
  const module = moduleForFile(file, moduleMap);
  if (module === undefined) return false;
  const rel = path.relative(module.root, file).split(path.sep);
  if (rel.some((segment) => COMPATIBILITY_DIRECTORIES.has(segment.toLowerCase()))) {
    return true;
  }
  const text = sourceText ?? readSource(file);
  return text !== undefined && hasCompatibilityMarker(text);
}

function readSource(file) {
  try {
    return fs.readFileSync(file, 'utf8');
  } catch (_error) {
    return undefined;
  }
}

function hasCompatibilityMarker(text) {
  // Only comments count.  A string literal containing the marker must not be
  // able to silently suppress a boundary diagnostic.
  const comments = text.match(/\/\*[\s\S]*?\*\/|\/\/[^\n]*/g) ?? [];
  return comments.some((comment) => comment.includes(COMPATIBILITY_MARKER));
}

/** Prevent feature-local copies of idle/loading/refreshing/ready/partial/error. */
function definesPrivateLoadState(text) {
  const source = stripComments(text);
  const definesStatus = /\b(?:enum|type)\s+[A-Za-z_$][A-Za-z0-9_$]*(?:Load|View)?Status\b/.test(source);
  if (!definesStatus) return false;
  return ['idle', 'loading', 'refreshing', 'ready', 'partial', 'error']
    .every((value) => new RegExp(`["']${value}["']`).test(source));
}

function findCycles(edges) {
  const found = new Map();
  const state = new Map();
  const stack = [];
  const visit = (node) => {
    state.set(node, 1);
    stack.push(node);
    for (const target of edges.get(node) ?? []) {
      const targetState = state.get(target) ?? 0;
      if (targetState === 0) visit(target);
      else if (targetState === 1) {
        const start = stack.indexOf(target);
        if (start >= 0) {
          const cycle = stack.slice(start);
          const key = cycle.map(relative).sort().join('|');
          if (!found.has(key)) found.set(key, cycle);
        }
      }
    }
    stack.pop();
    state.set(node, 2);
  };
  for (const node of edges.keys()) if ((state.get(node) ?? 0) === 0) visit(node);
  return [...found.values()];
}

function unique(values) { return [...new Set(values)]; }
function relative(file) { return path.relative(projectRoot, file) || file; }

function report(level, message, file, detail = '') {
  const item = { level, message, file: file ? relative(file) : undefined, detail };
  diagnostics.push(item);
  if (!jsonOutput) {
    const prefix = level === 'error' ? '[architecture:error]' : '[architecture:warning]';
    console[level === 'error' ? 'error' : 'warn'](`${prefix} ${message}`);
    if (item.file) console[level === 'error' ? 'error' : 'warn'](`  ${item.file}`);
    if (detail) console[level === 'error' ? 'error' : 'warn'](`  ${detail}`);
  }
}
function error(message, file, detail = '') { report('error', message, file, detail); }
function warning(message, file, detail = '') { report('warning', message, file, detail); }
function emitFailure(message) { if (!jsonOutput) console.error(`[architecture:error] ${message}`); }
